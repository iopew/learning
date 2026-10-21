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
            CREATE TABLE IF NOT EXISTS app_energy(
                at REAL NOT NULL,
                day TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                app TEXT NOT NULL,
                joules REAL NOT NULL,
                cpu_seconds REAL NOT NULL,
                on_battery INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS app_energy_day ON app_energy(day);
            CREATE TABLE IF NOT EXISTS charge_events(
                at REAL NOT NULL,
                day TEXT NOT NULL,
                plugged INTEGER NOT NULL,
                percent REAL
            );
            CREATE INDEX IF NOT EXISTS charge_events_day ON charge_events(day);
            """)
        lastOnAC = try db.query("SELECT on_ac FROM system_samples ORDER BY at DESC LIMIT 1") { $0.int(0) != 0 }.first
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
                try db.run("INSERT INTO charge_events(at, day, plugged, percent) VALUES(?,?,?,?)",
                           [.double(at), .text(day), .int(sample.onAC ? 1 : 0), optional(sample.batteryPercent)])
            }

            for app in energy where app.joules > 0 || app.cpuSeconds > 0 {
                try db.run(
                    "INSERT INTO app_energy(at, day, bundle_id, app, joules, cpu_seconds, on_battery) VALUES(?,?,?,?,?,?,?)",
                    [.double(at), .text(day), .text(app.bundleID), .text(app.appName), .double(app.joules),
                     .double(app.cpuSeconds), .int(sample.onAC ? 0 : 1)])
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        lastOnAC = sample.onAC
    }

    private func optional(_ value: Double?) -> SQLValue {
        value.map { .double($0) } ?? .null
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

        // Drain: battery drop between consecutive minutes while unplugged (gaps from sleep are skipped).
        let drain = try db.query(
            """
            SELECT COALESCE(SUM(-delta), 0), COALESCE(SUM(dt), 0) FROM (
                SELECT battery_percent - LAG(battery_percent) OVER (ORDER BY at) AS delta,
                       at - LAG(at) OVER (ORDER BY at) AS dt,
                       on_ac, LAG(on_ac) OVER (ORDER BY at) AS previous_ac
                FROM system_samples WHERE \(inWindow) AND battery_percent IS NOT NULL)
            WHERE on_ac = 0 AND previous_ac = 0 AND dt <= 300 AND delta <= 0
            """, window) { ($0.double(0), $0.double(1)) }.first ?? (0, 0)
        if drain.1 >= 600 {
            let perHour = drain.0 / (drain.1 / 3600)
            report.drainPerHour = perHour
            if perHour > 0.1 { report.estimatedFullCharge = 100 / perHour * 3600 }
        }

        let battery = try db.query(
            """
            SELECT COALESCE(SUM(CASE WHEN on_ac = 0 THEN interval ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN on_ac = 1 AND battery_percent >= 99 THEN interval ELSE 0 END), 0),
                   AVG(CASE WHEN on_ac = 0 AND battery_watts < 0 THEN -battery_watts END),
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
            SELECT AVG(cpu), MAX(cpu), MAX(CASE WHEN mem_total > 0 THEN mem_used / mem_total ELSE 0 END), MAX(swap_used),
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
                SELECT bundle_id, MAX(app), SUM(joules) AS j, SUM(cpu_seconds) FROM app_energy
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
