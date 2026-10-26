import Foundation

// MARK: - What an hour of something costs the battery

/// Battery cost of one app or site while it was in front, on battery.
public struct ActivityCost: Equatable, Identifiable {
    public var name: String
    /// Time on battery with this in front.
    public var seconds: TimeInterval
    public var averageWatts: Double?
    /// Battery percent per hour.
    public var percentPerHour: Double?

    public var id: String { name }
}

/// One minute-ish battery reading for the cost calculation.
public struct BatteryMinute: Equatable {
    public var at: Date
    public var percent: Double
    /// Negative while discharging.
    public var watts: Double?
    public var onAC: Bool

    public init(at: Date, percent: Double, watts: Double?, onAC: Bool) {
        self.at = at
        self.percent = percent
        self.watts = watts
        self.onAC = onAC
    }
}

public enum BatteryCost {
    /// Below this the numbers are noise.
    public static let minimumTime: TimeInterval = 15 * 60

    /// Each interval between two readings on battery (no gap over 5 min) goes to what was in front most of it:
    /// the site (for browsers) or the app; nothing in front = "Mac idle / screen off".
    /// `minutes` and `events` sorted by time.
    public static func make(minutes: [BatteryMinute], events: [ActivityEvent]) -> [ActivityCost] {
        var totals: [String: (seconds: Double, energy: Double, energySeconds: Double, drop: Double)] = [:]
        var eventIndex = 0
        for index in minutes.indices.dropFirst() {
            let previous = minutes[index - 1]
            let current = minutes[index]
            let dt = current.at.timeIntervalSince(previous.at)
            guard !previous.onAC, !current.onAC, dt > 0, dt <= 300 else { continue }

            // Events overlapping (previous.at, current.at]: advance past the ones that ended earlier.
            while eventIndex < events.count, events[eventIndex].end <= previous.at { eventIndex += 1 }
            var overlap: [String: Double] = [:]
            var probe = eventIndex
            while probe < events.count, events[probe].start < current.at {
                let event = events[probe]
                let seconds = min(event.end, current.at).timeIntervalSince(max(event.start, previous.at))
                if seconds > 0 { overlap[event.domain.isEmpty ? event.appName : event.domain, default: 0] += seconds }
                probe += 1
            }
            let name = overlap.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
                ?? L.tr("Mac без дела / экран выключен", "Mac idle / screen off")
            var entry = totals[name] ?? (0, 0, 0, 0)
            entry.seconds += dt
            if let watts = current.watts, watts < 0 {
                entry.energy += -watts * dt
                entry.energySeconds += dt
            }
            entry.drop += max(0, previous.percent - current.percent)
            totals[name] = entry
        }
        return totals.filter { $0.value.seconds >= minimumTime }.map { name, entry in
            ActivityCost(name: name, seconds: entry.seconds,
                         averageWatts: entry.energySeconds > 0 ? entry.energy / entry.energySeconds : nil,
                         percentPerHour: entry.drop / (entry.seconds / 3600))
        }
        .sorted { ($0.percentPerHour ?? 0) > ($1.percentPerHour ?? 0) }
    }
}

// MARK: - Charges

public struct ChargeSession: Equatable, Identifiable {
    public var start: Date
    /// nil while still plugged in.
    public var end: Date?
    public var startPercent: Double?
    public var endPercent: Double?
    public var adapterWatts: Double?
    public var adapterName: String?
    /// Average power going into the battery while charging.
    public var averageChargeWatts: Double?

    public var id: Date { start }

    /// Percent gained per hour plugged in.
    public var percentPerHour: Double? {
        guard let end, let startPercent, let endPercent, end.timeIntervalSince(start) >= 600 else { return nil }
        return (endPercent - startPercent) / (end.timeIntervalSince(start) / 3600)
    }
}

// MARK: - Battery wear forecast

public struct BatteryForecast: Equatable {
    public var cycles: Int?
    public var health: Double?
    /// Cycles per 30 days over the history.
    public var cyclesPerMonth: Double?
    /// When the battery reaches its rated 1000 cycles at the current pace.
    public var cyclesLimitDate: Date?
    /// When health falls to 80% at the current pace (only with a clear trend over 30+ days).
    public var health80Date: Date?
    /// Days of history the forecast is based on.
    public var historyDays: Int

    public static let ratedCycles = 1000

    /// `daily`: (day, health %, cycle count) — the last known values per day, oldest first.
    public static func make(daily: [(day: Date, health: Double?, cycles: Int?)], now: Date) -> BatteryForecast {
        let health = daily.last { $0.health != nil }?.health ?? nil
        let cycles = daily.last { $0.cycles != nil }?.cycles ?? nil
        var forecast = BatteryForecast(cycles: cycles, health: health, cyclesPerMonth: nil, cyclesLimitDate: nil,
                                       health80Date: nil, historyDays: 0)
        guard let first = daily.first?.day, let last = daily.last?.day else { return forecast }
        let span = last.timeIntervalSince(first) / 86400
        forecast.historyDays = Int(span.rounded()) + 1

        let withCycles = daily.filter { $0.cycles != nil }
        if span >= 14, let a = withCycles.first, let b = withCycles.last, let c0 = a.cycles, let c1 = b.cycles {
            let days = b.day.timeIntervalSince(a.day) / 86400
            if days >= 14 {
                let perDay = Double(c1 - c0) / days
                forecast.cyclesPerMonth = perDay * 30
                if perDay > 0, c1 < ratedCycles {
                    forecast.cyclesLimitDate = now.addingTimeInterval(Double(ratedCycles - c1) / perDay * 86400)
                }
            }
        }

        let withHealth = daily.compactMap { entry in entry.health.map { (entry.day, $0) } }
        if span >= 30, withHealth.count >= 10, let current = withHealth.last?.1, current > 80 {
            let origin = withHealth[0].0
            let xs = withHealth.map { $0.0.timeIntervalSince(origin) / 86400 }
            let ys = withHealth.map { $0.1 }
            let slope = Trend.slope(xs: xs, ys: ys)   // percent per day
            if slope < -0.001 {
                forecast.health80Date = now.addingTimeInterval((current - 80) / -slope * 86400)
            }
        }
        return forecast
    }
}

enum Trend {
    /// Least-squares slope of y over x.
    static func slope(xs: [Double], ys: [Double]) -> Double {
        let count = Double(xs.count)
        guard count >= 2 else { return 0 }
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        return denominator > 0 ? numerator / denominator : 0
    }
}

// MARK: - Sleep

/// One stretch of sleep: from going to sleep until waking up.
public struct SleepNight: Equatable, Identifiable {
    public var start: Date
    public var end: Date
    public var startPercent: Double?
    public var endPercent: Double?
    /// Times the Mac woke up in the dark (Power Nap, network, timers) during the sleep; nil if unknown.
    public var darkWakes: Int?

    public var id: Date { start }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    /// Battery lost while asleep (negative: it was charging).
    public var drop: Double? {
        guard let startPercent, let endPercent else { return nil }
        return startPercent - endPercent
    }
}

/// A sleep or wake moment with the battery level and macOS's sleep counters (`pmset -g stats`).
public struct PowerEvent: Equatable {
    public enum Kind: String {
        case sleep, wake
    }

    public var at: Date
    public var kind: Kind
    public var percent: Double?
    public var darkWakeCount: Int?

    public init(at: Date, kind: Kind, percent: Double?, darkWakeCount: Int?) {
        self.at = at
        self.kind = kind
        self.percent = percent
        self.darkWakeCount = darkWakeCount
    }
}

public enum SleepNights {
    /// Pairs each sleep with the next wake. Sleeps shorter than 15 minutes are left out.
    public static func make(_ events: [PowerEvent]) -> [SleepNight] {
        var nights: [SleepNight] = []
        var pending: PowerEvent?
        for event in events.sorted(by: { $0.at < $1.at }) {
            switch event.kind {
            case .sleep:
                pending = event
            case .wake:
                guard let sleep = pending else { continue }
                pending = nil
                guard event.at.timeIntervalSince(sleep.at) >= 15 * 60 else { continue }
                var darkWakes: Int?
                if let before = sleep.darkWakeCount, let after = event.darkWakeCount, after >= before {
                    darkWakes = after - before   // a restart resets the counter: then unknown
                }
                nights.append(SleepNight(start: sleep.at, end: event.at, startPercent: sleep.percent,
                                         endPercent: event.percent, darkWakes: darkWakes))
            }
        }
        return nights
    }

    /// "Dark Wake Count:234" from `pmset -g stats`.
    public static func darkWakeCount(inStats text: String) -> Int? {
        for line in text.split(separator: "\n") where line.lowercased().hasPrefix("dark wake count") {
            if let value = line.split(separator: ":").last.map({ $0.trimmingCharacters(in: .whitespaces) }) {
                return Int(value)
            }
        }
        return nil
    }
}

/// Who kept the Mac from sleeping while the user was away.
public struct SleepBlocker: Equatable, Identifiable {
    public var process: String
    public var reason: String
    public var seconds: TimeInterval

    public var id: String { process + "|" + reason }
}

// MARK: - Disk

public struct DiskForecast: Equatable {
    public var free: Double
    public var total: Double
    /// Change of free space per day over the last weeks (negative: filling up).
    public var perDay: Double?
    /// Days until the disk is full at that pace.
    public var daysUntilFull: Double?

    /// `daily`: lowest free space of each day, oldest first. A trend needs a week.
    public static func make(daily: [(day: Date, free: Double)], total: Double) -> DiskForecast {
        var forecast = DiskForecast(free: daily.last?.free ?? 0, total: total, perDay: nil, daysUntilFull: nil)
        let recent = Array(daily.suffix(30))
        guard recent.count >= 7, let origin = recent.first?.day else { return forecast }
        let slope = Trend.slope(xs: recent.map { $0.day.timeIntervalSince(origin) / 86400 }, ys: recent.map(\.free))
        forecast.perDay = slope
        // Filling by more than 100 MB a day counts as a trend.
        if slope < -100e6, forecast.free > 0 {
            forecast.daysUntilFull = forecast.free / -slope
        }
        return forecast
    }
}

/// A folder whose size is tracked (caches, toolchains).
public struct FolderGrowth: Equatable, Identifiable {
    public var path: String
    public var bytes: Double
    /// Change since about a week ago; nil without an older measurement.
    public var weekChange: Double?

    public var id: String { path }
}

/// Bytes written to the internal SSD per day.
public struct DiskWrites: Equatable, Identifiable {
    public var day: Date
    public var bytes: Double

    public var id: Date { day }
}

// MARK: - Startup items

/// A launch agent / daemon: something that starts by itself.
public struct StartupItem: Equatable, Identifiable {
    public var path: String
    public var label: String
    public var program: String
    public var firstSeen: Date
    public var lastSeen: Date
    /// The file disappeared (the item was removed).
    public var removed: Bool

    public var id: String { path }
    /// Appeared in the last 7 days (and wasn't there from the first scan).
    public var isNew: Bool = false
}

// MARK: - Everything for the Battery and System panes

public struct MachineReport: Equatable {
    public var costs: [ActivityCost] = []
    public var charges: [ChargeSession] = []
    public var forecast: BatteryForecast?
    public var nights: [SleepNight] = []
    public var blockers: [SleepBlocker] = []
    public var disk: DiskForecast?
    public var folders: [FolderGrowth] = []
    public var writes: [DiskWrites] = []
    public var swapDaily: [(day: Date, peak: Double)] = []
    public var startup: [StartupItem] = []

    public init() {}

    public static func == (lhs: MachineReport, rhs: MachineReport) -> Bool {
        lhs.costs == rhs.costs && lhs.charges == rhs.charges && lhs.forecast == rhs.forecast && lhs.nights == rhs.nights
            && lhs.blockers == rhs.blockers && lhs.disk == rhs.disk && lhs.folders == rhs.folders
            && lhs.writes == rhs.writes && lhs.startup == rhs.startup
            && lhs.swapDaily.map(\.peak) == rhs.swapDaily.map(\.peak)
    }
}

/// Storage for sleep/wake moments, sleep blockers, startup items, folder sizes and SSD writes (own connection,
/// same file). Thread-safe.
public final class MachineStore {
    public let days: DayCalendar
    private let db: Database
    private let lock = NSLock()

    public init(path: String, days: DayCalendar = DayCalendar()) throws {
        self.days = days
        db = try Database(path: path)
        try db.execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            CREATE TABLE IF NOT EXISTS power_events(
                at REAL PRIMARY KEY, day TEXT NOT NULL, kind TEXT NOT NULL, percent REAL, dark_wakes INTEGER);
            CREATE INDEX IF NOT EXISTS power_events_day ON power_events(day);
            CREATE TABLE IF NOT EXISTS sleep_blockers_hourly(
                hour REAL NOT NULL, day TEXT NOT NULL, process TEXT NOT NULL, reason TEXT NOT NULL, seconds REAL NOT NULL,
                PRIMARY KEY(hour, process, reason));
            CREATE INDEX IF NOT EXISTS sleep_blockers_day ON sleep_blockers_hourly(day);
            CREATE TABLE IF NOT EXISTS startup_items(
                path TEXT PRIMARY KEY, label TEXT NOT NULL, program TEXT NOT NULL, first_seen REAL NOT NULL,
                last_seen REAL NOT NULL, removed INTEGER NOT NULL DEFAULT 0, initial INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS folder_sizes(at REAL NOT NULL, path TEXT NOT NULL, bytes REAL NOT NULL,
                PRIMARY KEY(at, path));
            CREATE TABLE IF NOT EXISTS disk_writes_daily(day TEXT PRIMARY KEY, bytes REAL NOT NULL);
            """)
    }

    // MARK: Recording

    public func record(_ event: PowerEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        try db.run("INSERT OR REPLACE INTO power_events(at, day, kind, percent, dark_wakes) VALUES(?,?,?,?,?)",
                   [.double(event.at.timeIntervalSince1970), .text(days.key(event.at)), .text(event.kind.rawValue),
                    event.percent.map { .double($0) } ?? .null, event.darkWakeCount.map { .int(Int64($0)) } ?? .null])
    }

    /// `seconds` of `process` keeping the Mac awake (reason: the assertion name) within the hour of `at`.
    public func addBlocker(process: String, reason: String, seconds: TimeInterval, at: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        let hour = (at.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        try db.run("""
            INSERT INTO sleep_blockers_hourly(hour, day, process, reason, seconds) VALUES(?,?,?,?,?)
            ON CONFLICT(hour, process, reason) DO UPDATE SET seconds = seconds + excluded.seconds
            """, [.double(hour), .text(days.key(at)), .text(process), .text(String(reason.prefix(120))), .double(seconds)])
    }

    /// Adds bytes written to the SSD to the day of `at`.
    public func addWrites(_ bytes: Double, at: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        try db.run("""
            INSERT INTO disk_writes_daily(day, bytes) VALUES(?, ?)
            ON CONFLICT(day) DO UPDATE SET bytes = bytes + excluded.bytes
            """, [.text(days.key(at)), .double(bytes)])
    }

    public func recordFolders(_ sizes: [String: Double], at: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        for (path, bytes) in sizes {
            try db.run("INSERT OR REPLACE INTO folder_sizes(at, path, bytes) VALUES(?,?,?)",
                       [.double(at.timeIntervalSince1970), .text(path), .double(bytes)])
        }
    }

    /// When the folders were last measured.
    public func lastFolderScan() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }

        let value = try db.query("SELECT MAX(at) FROM folder_sizes") { $0.double(0) }.first ?? 0
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Updates the startup items with a fresh scan (path → (label, program)). The first scan ever marks everything
    /// as initial, so only later additions show up as new.
    public func updateStartup(_ found: [String: (label: String, program: String)], at: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        let isFirst = (try db.query("SELECT COUNT(*) FROM startup_items") { $0.int(0) }.first ?? 0) == 0
        let now = SQLValue.double(at.timeIntervalSince1970)
        try db.execute("BEGIN")
        do {
            for (path, item) in found {
                try db.run("""
                    INSERT INTO startup_items(path, label, program, first_seen, last_seen, removed, initial)
                    VALUES(?,?,?,?,?,0,?)
                    ON CONFLICT(path) DO UPDATE SET label = excluded.label, program = excluded.program,
                        last_seen = excluded.last_seen, removed = 0
                    """, [.text(path), .text(item.label), .text(item.program), now, now, .int(isFirst ? 1 : 0)])
            }
            let paths = Set(found.keys)
            for path in try db.query("SELECT path FROM startup_items WHERE removed = 0", map: { $0.text(0) })
            where !paths.contains(path) {
                try db.run("UPDATE startup_items SET removed = 1, last_seen = ? WHERE path = ?", [now, .text(path)])
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    public func erase(_ what: ActivityStore.Erase) throws {
        lock.lock()
        defer { lock.unlock() }

        switch what {
        case .domain, .app:
            return
        case .since(let moment):
            let time = SQLValue.double(moment.timeIntervalSince1970)
            try db.run("DELETE FROM power_events WHERE at >= ?", [time])
            try db.run("DELETE FROM sleep_blockers_hourly WHERE hour >= ?", [time])
        case .before(let moment):
            let time = SQLValue.double(moment.timeIntervalSince1970)
            try db.run("DELETE FROM power_events WHERE at < ?", [time])
            try db.run("DELETE FROM sleep_blockers_hourly WHERE hour < ?", [time])
            try db.run("DELETE FROM folder_sizes WHERE at < ?", [time])
            try db.run("DELETE FROM disk_writes_daily WHERE day < ?", [.text(days.key(moment))])
        case .all:
            try db.execute("""
                DELETE FROM power_events; DELETE FROM sleep_blockers_hourly; DELETE FROM folder_sizes;
                DELETE FROM disk_writes_daily;
                """)
        }
    }

    @discardableResult
    public func rekeyDays() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        return try ActivityStore.rekey(db: db, table: "power_events", idColumn: "rowid", timeColumn: "at", days: days)
            + ActivityStore.rekey(db: db, table: "sleep_blockers_hourly", idColumn: "rowid", timeColumn: "hour", days: days)
    }

    // MARK: Reading

    /// Sleeps that ended within `from`…`to` (by day), newest first.
    public func nights(from: Date, to: Date) throws -> [SleepNight] {
        lock.lock()
        defer { lock.unlock() }

        // A sleep that started the evening before the window still belongs to the first morning in it.
        let start = days.addingDays(-1, to: days.startOfDay(from)).timeIntervalSince1970
        let end = days.addingDays(1, to: days.startOfDay(to)).timeIntervalSince1970
        let events = try db.query(
            "SELECT at, kind, percent, percent IS NULL, dark_wakes, dark_wakes IS NULL FROM power_events WHERE at >= ? AND at < ? ORDER BY at",
            [.double(start), .double(end)]
        ) { row in
            PowerEvent(at: Date(timeIntervalSince1970: row.double(0)), kind: PowerEvent.Kind(rawValue: row.text(1)) ?? .wake,
                       percent: row.int(3) != 0 ? nil : row.double(2),
                       darkWakeCount: row.int(5) != 0 ? nil : Int(row.int(4)))
        }
        let window = days.startOfDay(from)...days.addingDays(1, to: days.startOfDay(to))
        return Array(SleepNights.make(events).filter { window.contains($0.end) }.reversed())
    }

    public func blockers(from: Date, to: Date) throws -> [SleepBlocker] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            """
            SELECT process, reason, SUM(seconds) AS s FROM sleep_blockers_hourly WHERE day BETWEEN ? AND ?
            GROUP BY process, reason ORDER BY s DESC LIMIT 15
            """, [.text(days.key(from)), .text(days.key(to))]
        ) { SleepBlocker(process: $0.text(0), reason: $0.text(1), seconds: $0.double(2)) }
    }

    /// Tracked folders: the latest size and the change against the measurement closest to 7 days earlier.
    public func folders() throws -> [FolderGrowth] {
        lock.lock()
        defer { lock.unlock() }

        guard let latest = try db.query("SELECT MAX(at) FROM folder_sizes", map: { $0.double(0) }).first, latest > 0
        else { return [] }
        let weekAgo = latest - 7 * 86400
        let previous = try db.query(
            "SELECT at FROM folder_sizes WHERE at <= ? ORDER BY ABS(at - ?) LIMIT 1", [.double(latest - 5 * 86400), .double(weekAgo)]
        ) { $0.double(0) }.first
        var before: [String: Double] = [:]
        if let previous {
            for (path, bytes) in try db.query("SELECT path, bytes FROM folder_sizes WHERE at = ?", [.double(previous)],
                                              map: { ($0.text(0), $0.double(1)) }) {
                before[path] = bytes
            }
        }
        return try db.query("SELECT path, bytes FROM folder_sizes WHERE at = ? ORDER BY bytes DESC", [.double(latest)]) { row in
            let path = row.text(0)
            let bytes = row.double(1)
            return FolderGrowth(path: path, bytes: bytes, weekChange: before[path].map { bytes - $0 })
        }
    }

    public func writes(from: Date, to: Date) throws -> [DiskWrites] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query("SELECT day, bytes FROM disk_writes_daily WHERE day BETWEEN ? AND ? ORDER BY day",
                            [.text(days.key(from)), .text(days.key(to))]) { row -> DiskWrites? in
            days.date(fromKey: row.text(0)).map { DiskWrites(day: $0, bytes: row.double(1)) }
        }.compactMap { $0 }
    }

    public func startupItems(now: Date) throws -> [StartupItem] {
        lock.lock()
        defer { lock.unlock() }

        let weekAgo = now.timeIntervalSince1970 - 7 * 86400
        return try db.query(
            "SELECT path, label, program, first_seen, last_seen, removed, initial FROM startup_items ORDER BY removed, first_seen DESC"
        ) { row in
            var item = StartupItem(path: row.text(0), label: row.text(1), program: row.text(2),
                                   firstSeen: Date(timeIntervalSince1970: row.double(3)),
                                   lastSeen: Date(timeIntervalSince1970: row.double(4)), removed: row.int(5) != 0)
            item.isNew = row.int(6) == 0 && row.double(3) >= weekAgo
            return item
        }
    }
}
