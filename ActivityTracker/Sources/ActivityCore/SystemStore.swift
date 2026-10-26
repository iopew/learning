import Foundation

/// Battery, load and per-app energy history: one row per minute in `system_samples`, per-app energy per minute in
/// `app_energy`, charger plug/unplug moments in `charge_events`. Lives in the same SQLite file as the activity data,
/// with its own connection. Thread-safe like ActivityStore.
public final class SystemStore {
    public let days: DayCalendar
    private let db: Database
    private let lock = NSLock()
    private var lastOnAC: Bool?

    public init(path: String, days: DayCalendar = DayCalendar()) throws {
        self.days = days
        db = try Database(path: path)
        try db.execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA secure_delete=ON;
            CREATE TABLE IF NOT EXISTS system_samples(
                at REAL PRIMARY KEY,
                day TEXT NOT NULL,
                interval REAL NOT NULL,
                battery_percent REAL,
                on_ac INTEGER NOT NULL,
                charging INTEGER NOT NULL,
                battery_watts REAL,
                battery_temp REAL,
                cycle_count INTEGER,
                health REAL,
                cpu REAL NOT NULL,
                mem_used REAL NOT NULL,
                mem_total REAL NOT NULL,
                swap_used REAL NOT NULL,
                disk_free REAL NOT NULL,
                disk_total REAL NOT NULL,
                thermal INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS system_samples_day ON system_samples(day);
            CREATE TABLE IF NOT EXISTS app_energy_hourly(
                hour REAL NOT NULL,
                day TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                app TEXT NOT NULL,
                joules REAL NOT NULL,
                cpu_seconds REAL NOT NULL,
                on_battery INTEGER NOT NULL,
                PRIMARY KEY(hour, bundle_id, on_battery)
            );
            CREATE INDEX IF NOT EXISTS app_energy_hourly_day ON app_energy_hourly(day);
            DROP TABLE IF EXISTS app_energy;
            CREATE TABLE IF NOT EXISTS charge_events(
                at REAL NOT NULL,
                day TEXT NOT NULL,
                plugged INTEGER NOT NULL,
                percent REAL
            );
            CREATE INDEX IF NOT EXISTS charge_events_day ON charge_events(day);
            """)
        // The charger of each plug-in (build 19+).
        if !(try db.columns(of: "charge_events")).contains("adapter_watts") {
            try db.execute("""
                ALTER TABLE charge_events ADD COLUMN adapter_watts REAL;
                ALTER TABLE charge_events ADD COLUMN adapter_name TEXT;
                """)
        }
        // Hourly roll-ups of old minutes (see rollUp): a mark, and the battery drain they stood for.
        let columns = try db.columns(of: "system_samples")
        if !columns.contains("rolled") {
            try db.execute("""
                ALTER TABLE system_samples ADD COLUMN rolled INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE system_samples ADD COLUMN drain_pct REAL;
                ALTER TABLE system_samples ADD COLUMN drain_sec REAL;
                """)
        }
        lastOnAC = try db.query("SELECT on_ac FROM system_samples ORDER BY at DESC LIMIT 1") { $0.int(0) != 0 }.first
    }

    /// Recomputes the day of every row after the day boundary changed (see ActivityStore.rekeyDays).
    @discardableResult
    public func rekeyDays() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var moved = 0
        for (table, time) in [("system_samples", "at"), ("app_energy_hourly", "hour"), ("charge_events", "at")] {
            moved += try ActivityStore.rekey(db: db, table: table, idColumn: "rowid", timeColumn: time, days: days)
        }
        return moved
    }

    /// Minutes before `moment` become hourly rows (one per hour and state: on battery or not, charging, full,
    /// hot), so a year of history takes ~60 times less space. Totals, time on battery / full / hot and the battery
    /// drain stay exact; averages are weighted by time. Returns the number of minutes folded.
    @discardableResult
    public func rollUp(before moment: Date) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = SQLValue.double((moment.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let count = try db.query("SELECT COUNT(*) FROM system_samples WHERE rolled = 0 AND at < ?", [cutoff]) { Int($0.int(0)) }.first ?? 0
        guard count > 0 else { return 0 }
        try db.execute("BEGIN")
        do {
            try db.run("DROP TABLE IF EXISTS temp.system_rollup")
            try db.run("""
                CREATE TEMP TABLE system_rollup AS
                WITH m AS (
                    SELECT *, battery_percent - LAG(battery_percent) OVER (ORDER BY at) AS delta,
                           at - LAG(at) OVER (ORDER BY at) AS dt, LAG(on_ac) OVER (ORDER BY at) AS previous_ac
                    FROM system_samples WHERE rolled = 0 AND at < ?
                )
                SELECT MIN(at) AS at, MIN(day) AS day, SUM(interval) AS interval,
                       SUM(battery_percent * interval) / SUM(CASE WHEN battery_percent IS NOT NULL THEN interval END) AS battery_percent,
                       on_ac, charging,
                       SUM(battery_watts * interval) / SUM(CASE WHEN battery_watts IS NOT NULL THEN interval END) AS battery_watts,
                       MAX(battery_temp) AS battery_temp, MAX(cycle_count) AS cycle_count, MAX(health) AS health,
                       SUM(cpu * interval) / SUM(interval) AS cpu, SUM(mem_used * interval) / SUM(interval) AS mem_used,
                       MAX(mem_total) AS mem_total, MAX(swap_used) AS swap_used, MIN(disk_free) AS disk_free,
                       MAX(disk_total) AS disk_total, MAX(thermal) AS thermal,
                       SUM(CASE WHEN on_ac = 0 AND previous_ac = 0 AND dt <= 300 AND delta <= 0 THEN -delta ELSE 0 END) AS drain_pct,
                       SUM(CASE WHEN on_ac = 0 AND previous_ac = 0 AND dt <= 300 AND delta <= 0 THEN dt ELSE 0 END) AS drain_sec
                FROM m
                GROUP BY CAST(at / 3600 AS INTEGER), on_ac, charging, COALESCE(battery_percent >= 99, 0), thermal >= 2
                """, [cutoff])
            try db.run("DELETE FROM system_samples WHERE rolled = 0 AND at < ?", [cutoff])
            try db.run("""
                INSERT INTO system_samples(at, day, interval, battery_percent, on_ac, charging, battery_watts, battery_temp,
                    cycle_count, health, cpu, mem_used, mem_total, swap_used, disk_free, disk_total, thermal, rolled,
                    drain_pct, drain_sec)
                SELECT at, day, interval, battery_percent, on_ac, charging, battery_watts, battery_temp, cycle_count, health,
                       cpu, mem_used, mem_total, swap_used, disk_free, disk_total, thermal, 1, drain_pct, drain_sec
                FROM temp.system_rollup
                """)
            try db.run("DROP TABLE temp.system_rollup")
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        return count
    }

    // MARK: - Recording

    /// Stores one snapshot (`interval` = seconds it stands for) and the per-app energy of that interval.
    public func record(_ sample: SystemSample, interval: TimeInterval, energy: [AppEnergy]) throws {
        lock.lock()
        defer { lock.unlock() }

        let at = sample.at.timeIntervalSince1970
        let day = days.key(sample.at)
        try db.execute("BEGIN")
        do {
            try db.run(
                """
                INSERT OR REPLACE INTO system_samples(at, day, interval, battery_percent, on_ac, charging, battery_watts,
                    battery_temp, cycle_count, health, cpu, mem_used, mem_total, swap_used, disk_free, disk_total, thermal)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [.double(at), .text(day), .double(interval), optional(sample.batteryPercent),
                 .int(sample.onAC ? 1 : 0), .int(sample.isCharging ? 1 : 0), optional(sample.batteryWatts),
                 optional(sample.batteryTemperature), sample.cycleCount.map { SQLValue.int(Int64($0)) } ?? SQLValue.null,
                 optional(sample.healthPercent), .double(sample.cpuLoad), .double(sample.memoryUsed),
                 .double(sample.memoryTotal), .double(sample.swapUsed), .double(sample.diskFree),
                 .double(sample.diskTotal), .int(Int64(sample.thermalState))])

            if let previous = lastOnAC, previous != sample.onAC, sample.batteryPercent != nil {
                try db.run("INSERT INTO charge_events(at, day, plugged, percent, adapter_watts, adapter_name) VALUES(?,?,?,?,?,?)",
                           [.double(at), .text(day), .int(sample.onAC ? 1 : 0), optional(sample.batteryPercent),
                            optional(sample.onAC ? sample.adapterWatts : nil),
                            sample.onAC ? (sample.adapterName.map { SQLValue.text($0) } ?? SQLValue.null) : SQLValue.null])
            }

            // One row per app per hour (and power source): a year stays in the hundreds of thousands of rows.
            let hour = (at / 3600).rounded(.down) * 3600
            for app in energy where app.joules >= 0.01 || app.cpuSeconds >= 0.01 {
                try db.run(
                    """
                    INSERT INTO app_energy_hourly(hour, day, bundle_id, app, joules, cpu_seconds, on_battery)
                    VALUES(?,?,?,?,?,?,?)
                    ON CONFLICT(hour, bundle_id, on_battery) DO UPDATE SET
                        joules = joules + excluded.joules, cpu_seconds = cpu_seconds + excluded.cpu_seconds,
                        app = excluded.app
                    """,
                    [.double(hour), .text(day), .text(app.bundleID), .text(app.appName), .double(app.joules),
                     .double(app.cpuSeconds), .int(sample.onAC ? 0 : 1)])
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        lastOnAC = sample.onAC
    }

    /// Mirrors ActivityStore.erase for the battery/system history.
    public func erase(_ what: ActivityStore.Erase) throws {
        lock.lock()
        defer { lock.unlock() }

        switch what {
        case .domain:
            return   // no per-site data here
        case .app(let bundleID):
            try db.run("DELETE FROM app_energy_hourly WHERE bundle_id = ?", [.text(bundleID)])
        case .since(let moment):
            let time = SQLValue.double(moment.timeIntervalSince1970)
            let hour = SQLValue.double((moment.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
            try db.run("DELETE FROM system_samples WHERE at >= ?", [time])
            try db.run("DELETE FROM charge_events WHERE at >= ?", [time])
            try db.run("DELETE FROM app_energy_hourly WHERE hour >= ?", [hour])
        case .before(let moment):
            let time = SQLValue.double(moment.timeIntervalSince1970)
            try db.run("DELETE FROM system_samples WHERE at < ?", [time])
            try db.run("DELETE FROM charge_events WHERE at < ?", [time])
            try db.run("DELETE FROM app_energy_hourly WHERE hour < ?", [time])
        case .all:
            try db.execute("DELETE FROM system_samples; DELETE FROM charge_events; DELETE FROM app_energy_hourly;")
        }
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    private func optional(_ value: Double?) -> SQLValue {
        value.map { .double($0) } ?? .null
    }

    // MARK: - Details for the Battery and System panes

    /// Battery readings (minutes only, not rolled-up hours) of `from`…`to`, for the cost of activities.
    public func batteryMinutes(from: Date, to: Date) throws -> [BatteryMinute] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            """
            SELECT at, battery_percent, battery_watts, battery_watts IS NULL, on_ac FROM system_samples
            WHERE day BETWEEN ? AND ? AND rolled = 0 AND battery_percent IS NOT NULL ORDER BY at
            """, [.text(days.key(from)), .text(days.key(to))]
        ) { row in
            BatteryMinute(at: Date(timeIntervalSince1970: row.double(0)), percent: row.double(1),
                          watts: row.int(3) != 0 ? nil : row.double(2), onAC: row.int(4) != 0)
        }
    }

    /// Plug-in → unplug sessions that started within `from`…`to`, newest first.
    public func chargeSessions(from: Date, to: Date) throws -> [ChargeSession] {
        lock.lock()
        defer { lock.unlock() }

        let rows = try db.query(
            """
            SELECT at, plugged, percent, percent IS NULL, adapter_watts, adapter_watts IS NULL, COALESCE(adapter_name, '')
            FROM charge_events WHERE day BETWEEN ? AND ? ORDER BY at
            """, [.text(days.key(from)), .text(days.key(days.addingDays(1, to: to)))]
        ) { row in
            (at: Date(timeIntervalSince1970: row.double(0)), plugged: row.int(1) != 0,
             percent: row.int(3) != 0 ? nil : row.double(2), watts: row.int(5) != 0 ? nil : row.double(4), name: row.text(6))
        }
        var sessions: [ChargeSession] = []
        let last = days.addingDays(1, to: days.startOfDay(to))
        for (index, row) in rows.enumerated() where row.plugged && row.at < last {
            let unplug = rows[(index + 1)...].first { !$0.plugged }
            var session = ChargeSession(start: row.at, end: unplug?.at, startPercent: row.percent,
                                        endPercent: unplug?.percent, adapterWatts: row.watts,
                                        adapterName: row.name.isEmpty ? nil : row.name, averageChargeWatts: nil)
            let end = unplug?.at ?? Date()
            session.averageChargeWatts = try db.query(
                """
                SELECT SUM(battery_watts * interval) / SUM(interval) FROM system_samples
                WHERE at > ? AND at <= ? AND charging = 1 AND battery_watts > 0
                """, [.double(row.at.timeIntervalSince1970), .double(end.timeIntervalSince1970)]
            ) { $0.double(0) }.first.flatMap { $0 > 0 ? $0 : nil }
            if session.endPercent == nil, unplug == nil {
                session.endPercent = try db.query(
                    "SELECT battery_percent FROM system_samples WHERE battery_percent IS NOT NULL ORDER BY at DESC LIMIT 1"
                ) { $0.double(0) }.first
            }
            sessions.append(session)
        }
        return sessions.reversed()
    }

    /// Battery health and cycle count per day over the whole history, oldest first.
    public func batteryHistory() throws -> [(day: Date, health: Double?, cycles: Int?)] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            """
            SELECT day, AVG(health), COUNT(health), MAX(cycle_count), COUNT(cycle_count) FROM system_samples
            WHERE battery_percent IS NOT NULL GROUP BY day ORDER BY day
            """
        ) { row -> (day: Date, health: Double?, cycles: Int?)? in
            guard let day = days.date(fromKey: row.text(0)) else { return nil }
            return (day, row.int(2) > 0 ? row.double(1) : nil, row.int(4) > 0 ? Int(row.int(3)) : nil)
        }.compactMap { $0 }
    }

    /// Lowest free disk space per day over the last `count` days and the disk size.
    public func diskDaily(days count: Int, before end: Date) throws -> (daily: [(day: Date, free: Double)], total: Double) {
        lock.lock()
        defer { lock.unlock() }

        let to = days.startOfDay(end)
        let from = days.addingDays(-(count - 1), to: to)
        var total: Double = 0
        let daily = try db.query(
            """
            SELECT day, MIN(disk_free), MAX(disk_total) FROM system_samples
            WHERE day BETWEEN ? AND ? AND disk_total > 0 GROUP BY day ORDER BY day
            """, [.text(days.key(from)), .text(days.key(to))]
        ) { row -> (day: Date, free: Double)? in
            total = max(total, row.double(2))
            return days.date(fromKey: row.text(0)).map { ($0, row.double(1)) }
        }.compactMap { $0 }
        return (daily, total)
    }

    /// Highest swap use per day.
    public func swapDaily(from: Date, to: Date) throws -> [(day: Date, peak: Double)] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            "SELECT day, MAX(swap_used) FROM system_samples WHERE day BETWEEN ? AND ? GROUP BY day ORDER BY day",
            [.text(days.key(from)), .text(days.key(to))]
        ) { row -> (day: Date, peak: Double)? in
            days.date(fromKey: row.text(0)).map { ($0, row.double(1)) }
        }.compactMap { $0 }
    }

    // MARK: - Reports

    public func report(range: StatsRange, anchor: Date) throws -> SystemReport {
        lock.lock()
        defer { lock.unlock() }

        let toDay = days.startOfDay(anchor)
        var fromDay: Date
        if let length = range.days {
            fromDay = days.addingDays(-(length - 1), to: toDay)
        } else {
            let first = try db.query("SELECT MIN(day) FROM system_samples") { $0.text(0) }.first ?? ""
            fromDay = days.date(fromKey: first) ?? toDay
        }
        fromDay = min(fromDay, toDay)
        let window: [SQLValue] = [.text(days.key(fromDay)), .text(days.key(toDay))]
        let inWindow = "day BETWEEN ? AND ?"

        let count = try db.query("SELECT COUNT(*), COUNT(battery_percent) FROM system_samples WHERE \(inWindow)",
                                 window) { ($0.int(0), $0.int(1)) }.first ?? (0, 0)

        var report = SystemReport(
            range: range, fromDay: fromDay, toDay: toDay, hasData: count.0 > 0, hasBattery: count.1 > 0,
            latest: nil, batteryPoints: [], loadPoints: [], chargeCount: 0, cyclesAdded: nil, drainPerHour: nil,
            averageDischargeWatts: nil, timeOnBattery: 0, timeFullOnAC: 0, estimatedFullCharge: nil,
            energyOnBattery: [], energyAll: [], cpuAverage: nil, cpuPeak: nil, memoryPeak: nil, swapPeak: nil,
            hotTime: 0, maxBatteryTemperature: nil)
        guard report.hasData else { return report }

        report.latest = try db.query(
            """
            SELECT at, battery_percent, on_ac, charging, battery_watts, battery_temp, cycle_count, health, cpu, mem_used,
                   mem_total, swap_used, disk_free, disk_total, thermal,
                   battery_percent IS NULL, battery_watts IS NULL, battery_temp IS NULL, cycle_count IS NULL, health IS NULL
            FROM system_samples WHERE \(inWindow) ORDER BY at DESC LIMIT 1
            """, window
        ) { row in
            SystemSample(
                at: Date(timeIntervalSince1970: row.double(0)),
                batteryPercent: row.int(15) != 0 ? nil : row.double(1),
                onAC: row.int(2) != 0, isCharging: row.int(3) != 0,
                batteryWatts: row.int(16) != 0 ? nil : row.double(4),
                batteryTemperature: row.int(17) != 0 ? nil : row.double(5),
                cycleCount: row.int(18) != 0 ? nil : Int(row.int(6)),
                healthPercent: row.int(19) != 0 ? nil : row.double(7),
                cpuLoad: row.double(8), memoryUsed: row.double(9), memoryTotal: row.double(10),
                swapUsed: row.double(11), diskFree: row.double(12), diskTotal: row.double(13),
                thermalState: Int(row.int(14)))
        }.first

        // Chart points: raw minutes for one day, hourly up to a week, daily beyond.
        let span = days.dayCount(from: fromDay, to: toDay)
        let bucket = span <= 1 ? "at" : (span <= 7 ? "CAST(at / 3600 AS INTEGER) * 3600" : "MIN(at)")
        let group = span <= 1 ? "at" : (span <= 7 ? "CAST(at / 3600 AS INTEGER)" : "day")
        report.batteryPoints = try db.query(
            """
            SELECT \(bucket), AVG(battery_percent), MIN(battery_percent), MAX(battery_percent), MAX(charging)
            FROM system_samples WHERE \(inWindow) AND battery_percent IS NOT NULL GROUP BY \(group) ORDER BY 1
            """, window
        ) { BatteryPoint(at: Date(timeIntervalSince1970: $0.double(0)), percent: $0.double(1),
                         minPercent: $0.double(2), maxPercent: $0.double(3), charging: $0.int(4) != 0) }
        report.loadPoints = try db.query(
            """
            SELECT \(bucket), AVG(cpu), AVG(CASE WHEN mem_total > 0 THEN mem_used / mem_total ELSE 0 END)
            FROM system_samples WHERE \(inWindow) GROUP BY \(group) ORDER BY 1
            """, window
        ) { LoadPoint(at: Date(timeIntervalSince1970: $0.double(0)), cpu: $0.double(1), memory: $0.double(2)) }

        let charges = try db.query(
            "SELECT COUNT(*) FROM charge_events WHERE \(inWindow) AND plugged = 1", window) { $0.int(0) }
        report.chargeCount = Int(charges.first ?? 0)

        let cycles = try db.query(
            "SELECT MAX(cycle_count) - MIN(cycle_count), COUNT(cycle_count) FROM system_samples WHERE \(inWindow)",
            window) { ($0.int(0), $0.int(1)) }.first
        if let cycles, cycles.1 > 0 { report.cyclesAdded = Int(cycles.0) }

        // Drain: battery drop between consecutive minutes while unplugged (gaps from sleep are skipped); rolled-up
        // hours carry their own.
        let minuteDrain = try db.query(
            """
            SELECT COALESCE(SUM(-delta), 0), COALESCE(SUM(dt), 0) FROM (
                SELECT battery_percent - LAG(battery_percent) OVER (ORDER BY at) AS delta,
                       at - LAG(at) OVER (ORDER BY at) AS dt,
                       on_ac, LAG(on_ac) OVER (ORDER BY at) AS previous_ac
                FROM system_samples WHERE \(inWindow) AND battery_percent IS NOT NULL AND rolled = 0)
            WHERE on_ac = 0 AND previous_ac = 0 AND dt <= 300 AND delta <= 0
            """, window) { ($0.double(0), $0.double(1)) }.first ?? (0, 0)
        let rolledDrain = try db.query(
            "SELECT COALESCE(SUM(drain_pct), 0), COALESCE(SUM(drain_sec), 0) FROM system_samples WHERE \(inWindow) AND rolled = 1",
            window) { ($0.double(0), $0.double(1)) }.first ?? (0, 0)
        let drain = (minuteDrain.0 + rolledDrain.0, minuteDrain.1 + rolledDrain.1)
        if drain.1 >= 600 {
            let perHour = drain.0 / (drain.1 / 3600)
            report.drainPerHour = perHour
            if perHour > 0.1 { report.estimatedFullCharge = 100 / perHour * 3600 }
        }

        let battery = try db.query(
            """
            SELECT COALESCE(SUM(CASE WHEN on_ac = 0 THEN interval ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN on_ac = 1 AND battery_percent >= 99 THEN interval ELSE 0 END), 0),
                   SUM(CASE WHEN on_ac = 0 AND battery_watts < 0 THEN -battery_watts * interval END)
                       / SUM(CASE WHEN on_ac = 0 AND battery_watts < 0 THEN interval END),
                   COUNT(CASE WHEN on_ac = 0 AND battery_watts < 0 THEN 1 END),
                   MAX(battery_temp), COUNT(battery_temp)
            FROM system_samples WHERE \(inWindow) AND battery_percent IS NOT NULL
            """, window) { row in
                (row.double(0), row.double(1), row.int(3) > 0 ? row.double(2) : nil,
                 row.int(5) > 0 ? row.double(4) : nil)
            }.first
        if let battery {
            report.timeOnBattery = battery.0
            report.timeFullOnAC = battery.1
            report.averageDischargeWatts = battery.2
            report.maxBatteryTemperature = battery.3
        }

        let load = try db.query(
            """
            SELECT SUM(cpu * interval) / SUM(interval), MAX(cpu), MAX(CASE WHEN mem_total > 0 THEN mem_used / mem_total ELSE 0 END), MAX(swap_used),
                   COALESCE(SUM(CASE WHEN thermal >= 2 THEN interval ELSE 0 END), 0)
            FROM system_samples WHERE \(inWindow)
            """, window) { ($0.double(0), $0.double(1), $0.double(2), $0.double(3), $0.double(4)) }.first
        if let load {
            report.cpuAverage = load.0
            report.cpuPeak = load.1
            report.memoryPeak = load.2
            report.swapPeak = load.3
            report.hotTime = load.4
        }

        func energy(onBatteryOnly: Bool) throws -> [EnergyUsage] {
            try db.query(
                """
                SELECT bundle_id, MAX(app), SUM(joules) AS j, SUM(cpu_seconds) FROM app_energy_hourly
                WHERE \(inWindow) \(onBatteryOnly ? "AND on_battery = 1" : "")
                GROUP BY bundle_id ORDER BY j DESC LIMIT 25
                """, window
            ) { EnergyUsage(bundleID: $0.text(0), appName: $0.text(1), joules: $0.double(2), cpuSeconds: $0.double(3)) }
        }
        report.energyAll = try energy(onBatteryOnly: false)
        report.energyOnBattery = try energy(onBatteryOnly: true)
        return report
    }
}
