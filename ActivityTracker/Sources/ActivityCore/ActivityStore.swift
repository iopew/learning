import Foundation

/// Persists activity as events (start/end spans) in SQLite and builds reports from them.
///
/// Recording works like heartbeats: the collector calls `record` every few seconds. A sample that matches the
/// open event (same app, title and URL, same day, no gap) just extends its end; anything else starts a new event.
/// Each sample is credited `interval` seconds forward, so a single sample still counts for one tick.
///
/// Thread-safe: every public method takes the store's lock. The app uses one instance for recording (main thread)
/// and another for building reports in the background, both on the same file (SQLite WAL mode).
public final class ActivityStore {
    public static let otherBundleID = "__other__"

    public let days: DayCalendar
    private let db: Database
    private let lock = NSLock()
    private var open: OpenEvent?
    /// Text → its number in `texts`, for the recorder (cleared on erase and when it grows large).
    private var textIDs: [String: Int64] = [:]

    private struct OpenEvent {
        var id: Int64
        var sample: Sample
        var day: String
        var start: Date
        var end: Date
    }

    public init(path: String, days: DayCalendar = DayCalendar()) throws {
        self.days = days
        db = try Database(path: path)
        try db.execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA secure_delete=ON;
            CREATE TABLE IF NOT EXISTS events(
                id INTEGER PRIMARY KEY,
                day TEXT NOT NULL,
                start_at REAL NOT NULL,
                end_at REAL NOT NULL,
                bundle_id TEXT NOT NULL,
                app TEXT NOT NULL,
                title_id INTEGER NOT NULL DEFAULT 0,
                url_id INTEGER NOT NULL DEFAULT 0,
                domain TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS events_day ON events(day);
            CREATE TABLE IF NOT EXISTS texts(
                id INTEGER PRIMARY KEY,
                value TEXT NOT NULL UNIQUE
            );
            """)
        try Self.upgradeTexts(db)
    }

    /// Before build 17 every event stored its window title and URL in full, although the same ones repeat
    /// hundreds of times a day. Each distinct text is now stored once in `texts` and events keep its number
    /// (0 = none). Runs once per database; the file is compacted afterwards.
    static func upgradeTexts(_ db: Database) throws {
        let columns = try db.columns(of: "events")
        guard columns.contains("title") else { return }
        try db.execute("BEGIN")
        do {
            if !columns.contains("title_id") {
                try db.execute("""
                    ALTER TABLE events ADD COLUMN title_id INTEGER NOT NULL DEFAULT 0;
                    ALTER TABLE events ADD COLUMN url_id INTEGER NOT NULL DEFAULT 0;
                    """)
            }
            try db.execute("""
                INSERT OR IGNORE INTO texts(value) SELECT DISTINCT title FROM events WHERE title != '';
                INSERT OR IGNORE INTO texts(value) SELECT DISTINCT url FROM events WHERE url != '';
                UPDATE events SET title_id = (SELECT id FROM texts WHERE value = events.title) WHERE title != '';
                UPDATE events SET url_id = (SELECT id FROM texts WHERE value = events.url) WHERE url != '';
                ALTER TABLE events DROP COLUMN title;
                ALTER TABLE events DROP COLUMN url;
                """)
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }

    /// ~/Library/Application Support/ActivityTracker/activity.sqlite
    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("ActivityTracker", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("activity.sqlite")
    }

    // MARK: - Recording

    public func record(_ sample: Sample, at time: Date, interval: TimeInterval) throws {
        lock.lock()
        defer { lock.unlock() }

        let day = days.key(time)
        let creditedEnd = time.addingTimeInterval(interval)

        if var current = open, current.sample == sample, current.day == day,
           time.timeIntervalSince(current.end) <= interval {
            current.end = max(current.end, creditedEnd)
            try updateEnd(of: current)
            open = current
            return
        }

        // The previous event was credited past this moment; give that time to the new sample instead.
        if var current = open, current.end > time {
            current.end = max(current.start, time)
            try updateEnd(of: current)
        }

        let titleID = try textID(sample.title)
        let urlID = try textID(sample.url)
        try db.run(
            "INSERT INTO events(day, start_at, end_at, bundle_id, app, title_id, url_id, domain) VALUES(?,?,?,?,?,?,?,?)",
            [.text(day), .double(time.timeIntervalSince1970), .double(creditedEnd.timeIntervalSince1970),
             .text(sample.bundleID), .text(sample.appName), .int(titleID), .int(urlID), .text(sample.domain)])
        open = OpenEvent(id: db.lastInsertRowID, sample: sample, day: day, start: time, end: creditedEnd)
    }

    /// The number of `text` in `texts` (added if new); 0 for an empty text. Called with the lock held.
    private func textID(_ text: String) throws -> Int64 {
        guard !text.isEmpty else { return 0 }
        if let id = textIDs[text] { return id }
        try db.run("INSERT OR IGNORE INTO texts(value) VALUES(?)", [.text(text)])
        let id = try db.query("SELECT id FROM texts WHERE value = ?", [.text(text)]) { $0.int(0) }.first ?? 0
        if textIDs.count >= 5000 { textIDs.removeAll() }
        textIDs[text] = id
        return id
    }

    /// Stops the current streak (idle, sleep, screen lock, pause). Time credited past `time` is taken back.
    public func endStreak(at time: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        guard var current = open else { return }
        open = nil
        if current.end > time {
            current.end = max(current.start, time)
            try updateEnd(of: current)
        }
    }

    /// Recomputes every event's day after the day boundary (DayCalendar.startHour) changed. Returns rows moved.
    /// Call before recording starts.
    @discardableResult
    public func rekeyDays() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        open = nil
        return try Self.rekey(db: db, table: "events", idColumn: "id", timeColumn: "start_at", days: days)
    }

    /// Shared by the activity and system tables: `day` = key of the row's time, updated only where it differs.
    static func rekey(db: Database, table: String, idColumn: String, timeColumn: String, days: DayCalendar) throws -> Int {
        let rows = try db.query("SELECT \(idColumn), \(timeColumn), day FROM \(table)") {
            ($0.int(0), $0.double(1), $0.text(2))
        }
        var moved = 0
        try db.execute("BEGIN")
        do {
            for (id, time, day) in rows {
                let key = days.key(Date(timeIntervalSince1970: time))
                guard key != day else { continue }
                try db.run("UPDATE \(table) SET day = ? WHERE \(idColumn) = ?", [.text(key), .int(id)])
                moved += 1
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        return moved
    }

    private func updateEnd(of event: OpenEvent) throws {
        try db.run("UPDATE events SET end_at = ? WHERE id = ?",
                   [.double(event.end.timeIntervalSince1970), .int(event.id)])
    }

    // MARK: - Deleting

    public enum Erase: Equatable {
        /// Everything recorded on this site.
        case domain(String)
        /// Everything recorded in this app (by bundle ID).
        case app(String)
        /// Everything after this moment ("forget the last 15 minutes"); an event running across it is cut there.
        case since(Date)
        /// Everything before this moment (clean-up of old history); an event running across it is cut there.
        case before(Date)
        /// The whole history.
        case all
    }

    /// Deletes for good: rows are removed, freed pages are zeroed (secure_delete) and the WAL is checkpointed,
    /// so no copy of the deleted titles or URLs stays in the database files. Returns the number of affected events.
    @discardableResult
    public func erase(_ what: Erase) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        open = nil   // the open event may be gone; the next sample starts a new one
        var affected = 0
        switch what {
        case .domain(let domain):
            try db.run("DELETE FROM events WHERE domain = ?", [.text(domain)])
            affected = db.changes
        case .app(let bundleID):
            try db.run("DELETE FROM events WHERE bundle_id = ?", [.text(bundleID)])
            affected = db.changes
        case .since(let moment):
            let time = SQLValue.double(moment.timeIntervalSince1970)
            try db.run("DELETE FROM events WHERE start_at >= ?", [time])
            affected = db.changes
            try db.run("UPDATE events SET end_at = ? WHERE end_at > ? AND start_at < ?", [time, time, time])
            affected += db.changes
        case .before(let moment):
            let time = SQLValue.double(moment.timeIntervalSince1970)
            try db.run("DELETE FROM events WHERE end_at <= ?", [time])
            affected = db.changes
            try db.run("UPDATE events SET start_at = ? WHERE start_at < ? AND end_at > ?", [time, time, time])
            affected += db.changes
        case .all:
            try db.run("DELETE FROM events")
            affected = db.changes
        }
        // Titles and addresses nobody refers to any more are deleted too (privacy: nothing of a deleted site stays).
        textIDs.removeAll()
        try db.execute("""
            DELETE FROM texts WHERE id NOT IN (SELECT title_id FROM events) AND id NOT IN (SELECT url_id FROM events);
            PRAGMA wal_checkpoint(TRUNCATE);
            """)
        return affected
    }

    // MARK: - The database file

    /// First and last recorded day and how many days have any activity.
    public func historySummary() throws -> (first: Date?, last: Date?, days: Int) {
        lock.lock()
        defer { lock.unlock() }

        let row = try db.query("SELECT MIN(day), MAX(day), COUNT(DISTINCT day) FROM events") {
            ($0.text(0), $0.text(1), Int($0.int(2)))
        }.first ?? ("", "", 0)
        return (days.date(fromKey: row.0), days.date(fromKey: row.1), row.2)
    }

    /// A consistent copy of the whole database file (all tables) at `path`, while recording goes on.
    public func backup(to path: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try? FileManager.default.removeItem(atPath: path)
        try db.run("VACUUM INTO ?", [.text(path)])
    }

    /// Rebuilds the file without free pages (after deleting a lot it shrinks).
    public func compact() throws {
        lock.lock()
        defer { lock.unlock() }

        try db.execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM; PRAGMA wal_checkpoint(TRUNCATE);")
    }

    // MARK: - Queries

    public func total(on date: Date) throws -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        return try db.query("SELECT COALESCE(SUM(end_at - start_at), 0) FROM events WHERE day = ?",
                            [.text(days.key(date))]) { $0.double(0) }.first ?? 0
    }

    public func firstDay() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }

        return try firstDayLocked()
    }

    private func firstDayLocked() throws -> Date? {
        let key = try db.query("SELECT MIN(day) FROM events") { $0.text(0) }.first ?? ""
        return days.date(fromKey: key)
    }

    public func events(on date: Date) throws -> [ActivityEvent] {
        lock.lock()
        defer { lock.unlock() }

        return try eventsLocked(dayKey: days.key(date))
    }

    private func eventsLocked(dayKey: String) throws -> [ActivityEvent] {
        try db.query(
            """
            SELECT e.id, e.start_at, e.end_at, e.bundle_id, e.app, COALESCE(t.value, ''), COALESCE(u.value, ''), e.domain
            FROM events e LEFT JOIN texts t ON t.id = e.title_id LEFT JOIN texts u ON u.id = e.url_id
            WHERE e.day = ? ORDER BY e.start_at
            """,
            [.text(dayKey)]
        ) { row in
            ActivityEvent(
                id: row.int(0),
                start: Date(timeIntervalSince1970: row.double(1)),
                end: Date(timeIntervalSince1970: row.double(2)),
                bundleID: row.text(3), appName: row.text(4), title: row.text(5), url: row.text(6),
                domain: row.text(7))
        }
    }

    /// Events of the days `from`…`to` without titles and URLs (lighter): for switches, streaks, battery costs.
    public func spans(from: Date, to: Date) throws -> [ActivityEvent] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            "SELECT id, start_at, end_at, bundle_id, app, domain FROM events WHERE day BETWEEN ? AND ? ORDER BY start_at",
            [.text(days.key(from)), .text(days.key(to))]
        ) { row in
            ActivityEvent(
                id: row.int(0),
                start: Date(timeIntervalSince1970: row.double(1)),
                end: Date(timeIntervalSince1970: row.double(2)),
                bundleID: row.text(3), appName: row.text(4), title: "", url: "", domain: row.text(5))
        }
    }

    /// First start, last end and total of every recorded day in `from`…`to` (rhythm, year calendar).
    public func dayStats(from: Date, to: Date) throws -> [DayStat] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            """
            SELECT day, MIN(start_at), MAX(end_at), SUM(end_at - start_at) FROM events
            WHERE day BETWEEN ? AND ? GROUP BY day ORDER BY day
            """, [.text(days.key(from)), .text(days.key(to))]
        ) { row -> DayStat? in
            guard let day = days.date(fromKey: row.text(0)) else { return nil }
            return DayStat(day: day, first: Date(timeIntervalSince1970: row.double(1)),
                           last: Date(timeIntervalSince1970: row.double(2)), seconds: row.double(3))
        }.compactMap { $0 }
    }

    /// Time per app and per site for every day in `from`…`to` (period comparison).
    public func dailyUsage(from: Date, to: Date) throws -> [DayUsage] {
        lock.lock()
        defer { lock.unlock() }

        let window: [SQLValue] = [.text(days.key(from)), .text(days.key(to))]
        var result: [String: DayUsage] = [:]
        func entry(_ key: String) -> DayUsage? {
            if let existing = result[key] { return existing }
            return days.date(fromKey: key).map { DayUsage(day: $0) }
        }
        for (key, bundleID, name, seconds) in try db.query(
            "SELECT day, bundle_id, MAX(app), SUM(end_at - start_at) FROM events WHERE day BETWEEN ? AND ? GROUP BY day, bundle_id",
            window, map: { ($0.text(0), $0.text(1), $0.text(2), $0.double(3)) }) {
            guard var usage = entry(key) else { continue }
            usage.apps[bundleID] = seconds
            usage.appNames[bundleID] = name
            usage.total += seconds
            result[key] = usage
        }
        for (key, domain, seconds) in try db.query(
            "SELECT day, domain, SUM(end_at - start_at) FROM events WHERE day BETWEEN ? AND ? AND domain != '' GROUP BY day, domain",
            window, map: { ($0.text(0), $0.text(1), $0.double(2)) }) {
            guard var usage = entry(key) else { continue }
            usage.domains[domain] = seconds
            result[key] = usage
        }
        return result.values.sorted { $0.day < $1.day }
    }

    /// Seconds per day for one app or site, and its most-used titles, over `from`…`to` (trend card).
    public func usageHistory(of target: UsageTarget, from: Date, to: Date) throws -> (daily: [String: TimeInterval], titles: [TitleUsage]) {
        lock.lock()
        defer { lock.unlock() }

        let column: String
        let value: String
        switch target {
        case .app(let bundleID):
            column = "bundle_id"
            value = bundleID
        case .domain(let domain):
            column = "domain"
            value = domain
        }
        let params: [SQLValue] = [.text(days.key(from)), .text(days.key(to)), .text(value)]
        var daily: [String: TimeInterval] = [:]
        for (day, seconds) in try db.query(
            "SELECT day, SUM(end_at - start_at) FROM events WHERE day BETWEEN ? AND ? AND \(column) = ? GROUP BY day",
            params, map: { ($0.text(0), $0.double(1)) }) {
            daily[day] = seconds
        }
        let raw = try db.query(
            """
            SELECT t.value, s.seconds FROM (
                SELECT title_id, SUM(end_at - start_at) AS seconds FROM events
                WHERE day BETWEEN ? AND ? AND \(column) = ? AND title_id != 0
                GROUP BY title_id ORDER BY seconds DESC LIMIT 60
            ) s JOIN texts t ON t.id = s.title_id
            """, params
        ) { (TitleCleaner.clean($0.text(0)), $0.double(1)) }
        // Titles that differ only by a notification counter ("(3) …") are one title.
        var merged: [String: TimeInterval] = [:]
        for (title, seconds) in raw where !title.isEmpty { merged[title, default: 0] += seconds }
        let titles = merged.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(10).map { TitleUsage(title: $0.key, seconds: $0.value) }
        return (daily, titles)
    }

    // MARK: - Reports

    /// The usual day over the `count` days before `day`, averaged over the days that had any activity.
    public func baseline(days count: Int = 14, before day: Date) throws -> UsageBaseline {
        lock.lock()
        defer { lock.unlock() }

        let today = days.startOfDay(day)
        let window: [SQLValue] = [.text(days.key(days.addingDays(-count, to: today))),
                                  .text(days.key(days.addingDays(-1, to: today)))]
        let totals = try db.query(
            "SELECT COUNT(DISTINCT day), COALESCE(SUM(end_at - start_at), 0) FROM events WHERE day BETWEEN ? AND ?",
            window) { (Int($0.int(0)), $0.double(1)) }.first ?? (0, 0)
        guard totals.0 > 0 else { return UsageBaseline() }
        let activeDays = Double(totals.0)

        var apps: [String: TimeInterval] = [:]
        for (bundleID, seconds) in try db.query(
            "SELECT bundle_id, SUM(end_at - start_at) FROM events WHERE day BETWEEN ? AND ? GROUP BY bundle_id",
            window, map: { ($0.text(0), $0.double(1)) }) {
            apps[bundleID] = seconds / activeDays
        }
        var domains: [String: TimeInterval] = [:]
        for (domain, seconds) in try db.query(
            "SELECT domain, SUM(end_at - start_at) FROM events WHERE day BETWEEN ? AND ? AND domain != '' GROUP BY domain",
            window, map: { ($0.text(0), $0.double(1)) }) {
            domains[domain] = seconds / activeDays
        }
        return UsageBaseline(activeDays: totals.0, totalPerDay: totals.1 / activeDays, appsPerDay: apps,
                             domainsPerDay: domains)
    }

    /// Statistics for `range` ending on the day of `anchor` (for `.all`: from the first recorded day).
    public func report(range: StatsRange, anchor: Date) throws -> Report {
        lock.lock()
        defer { lock.unlock() }

        let toDay = days.startOfDay(anchor)
        var fromDay: Date
        if let length = range.days {
            fromDay = days.addingDays(-(length - 1), to: toDay)
        } else {
            fromDay = try firstDayLocked() ?? toDay
        }
        fromDay = min(fromDay, toDay)

        let window: [SQLValue] = [.text(days.key(fromDay)), .text(days.key(toDay))]
        let duration = "SUM(end_at - start_at)"

        var daily: [String: TimeInterval] = [:]
        for (day, seconds) in try db.query(
            "SELECT day, \(duration) FROM events WHERE day BETWEEN ? AND ? GROUP BY day", window,
            map: { ($0.text(0), $0.double(1)) }) {
            daily[day] = seconds
        }

        var apps = try db.query(
            """
            SELECT bundle_id, MAX(app), \(duration) AS seconds FROM events
            WHERE day BETWEEN ? AND ? GROUP BY bundle_id ORDER BY seconds DESC
            """, window
        ) { AppUsage(bundleID: $0.text(0), appName: $0.text(1), seconds: $0.double(2), topTitles: []) }

        for index in apps.indices.prefix(15) {
            apps[index].topTitles = try db.query(
                """
                SELECT t.value, s.seconds FROM (
                    SELECT title_id, \(duration) AS seconds FROM events
                    WHERE day BETWEEN ? AND ? AND bundle_id = ? AND title_id != 0
                    GROUP BY title_id ORDER BY seconds DESC LIMIT 5
                ) s JOIN texts t ON t.id = s.title_id ORDER BY s.seconds DESC
                """, window + [.text(apps[index].bundleID)]
            ) { TitleUsage(title: $0.text(0), seconds: $0.double(1)) }
        }

        let domains = try db.query(
            """
            SELECT domain, \(duration) AS seconds FROM events
            WHERE day BETWEEN ? AND ? AND domain != '' GROUP BY domain ORDER BY seconds DESC LIMIT 30
            """, window
        ) { DomainUsage(domain: $0.text(0), seconds: $0.double(1)) }

        let (buckets, unit) = Self.buckets(daily: daily, from: fromDay, to: toDay, days: days)

        var report = Report(
            range: range, fromDay: fromDay, toDay: toDay,
            total: daily.values.reduce(0, +),
            activeDays: daily.values.filter { $0 > 0 }.count,
            apps: apps, domains: domains, buckets: buckets, bucketUnit: unit,
            hourly: [], minutes: [], sessions: [], firstHour: days.startHour)

        if range == .day {
            let events = try eventsLocked(dayKey: days.key(toDay))
            let details = Self.dayDetails(events: events, day: toDay, days: days)
            report.hourly = details.hourly
            report.minutes = details.minutes
            report.sessions = details.sessions
        }
        return report
    }

    /// One bar per day; one per week once the period is longer than ~3 months.
    static func buckets(daily: [String: TimeInterval], from: Date, to: Date,
                        days: DayCalendar) -> ([ChartBucket], BucketUnit) {
        let unit: BucketUnit = days.dayCount(from: from, to: to) > 92 ? .week : .day
        var buckets: [ChartBucket] = []
        var day = days.startOfDay(from)
        let last = days.startOfDay(to)
        while day <= last {
            let start = unit == .day ? day : days.startOfWeek(day)
            let seconds = daily[days.key(day)] ?? 0
            if let lastBucket = buckets.last, lastBucket.start == start {
                buckets[buckets.count - 1].seconds += seconds
            } else {
                buckets.append(ChartBucket(start: start, seconds: seconds))
            }
            day = days.addingDays(1, to: day)
        }
        return (buckets, unit)
    }

    static func dayDetails(events: [ActivityEvent], day: Date, days: DayCalendar)
        -> (hourly: [HourSlice], minutes: [MinuteCell?], sessions: [Session]) {
        let dayStart = days.startOfDay(day)
        let dayLength = days.addingDays(1, to: dayStart).timeIntervalSince(dayStart)
        let minuteCount = 1440

        var perMinute = [[String: TimeInterval]](repeating: [:], count: minuteCount)
        var names: [String: String] = [:]
        var dayTotals: [String: TimeInterval] = [:]

        for event in events {
            names[event.bundleID] = event.appName
            var cursor = max(0, event.start.timeIntervalSince(dayStart))
            let stop = min(dayLength, event.end.timeIntervalSince(dayStart))
            while cursor < stop {
                let minute = Int(cursor / 60)
                guard minute < minuteCount else { break }
                let chunkEnd = min(stop, Double(minute + 1) * 60)
                guard chunkEnd > cursor else { break }
                perMinute[minute][event.bundleID, default: 0] += chunkEnd - cursor
                dayTotals[event.bundleID, default: 0] += chunkEnd - cursor
                cursor = chunkEnd
            }
        }

        let minutes: [MinuteCell?] = perMinute.map { usage in
            guard let top = usage.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })
            else { return nil }
            return MinuteCell(bundleID: top.key, appName: names[top.key] ?? top.key, seconds: top.value)
        }

        // Hourly chart: the day's top 5 apps keep their own color, the rest are folded into "other".
        let ranked = dayTotals.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
        let featured = Set(ranked.prefix(5).map { $0.key })
        var hourly: [HourSlice] = []
        for hour in 0..<24 {
            var perApp: [String: TimeInterval] = [:]
            for minute in (hour * 60)..<((hour + 1) * 60) {
                for (bundleID, seconds) in perMinute[minute] {
                    perApp[featured.contains(bundleID) ? bundleID : otherBundleID, default: 0] += seconds
                }
            }
            for (bundleID, seconds) in perApp.sorted(by: { $0.key < $1.key }) {
                hourly.append(HourSlice(hour: hour, bundleID: bundleID, seconds: seconds))
            }
        }

        // Timeline: consecutive events of one app (gaps up to a minute) form a session.
        var sessions: [Session] = []
        var sessionDetails: [[String: TimeInterval]] = []
        for event in events {
            let detail = event.domain.isEmpty ? event.title : event.domain
            if let last = sessions.last, last.bundleID == event.bundleID,
               event.start.timeIntervalSince(last.end) <= 60 {
                sessions[sessions.count - 1].end = max(last.end, event.end)
            } else {
                sessions.append(Session(start: event.start, end: event.end, bundleID: event.bundleID,
                                        appName: event.appName, details: []))
                sessionDetails.append([:])
            }
            if !detail.isEmpty {
                sessionDetails[sessionDetails.count - 1][detail, default: 0] += event.duration
            }
        }
        for index in sessions.indices {
            sessions[index].details = sessionDetails[index]
                .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
                .prefix(3).map { $0.key }
        }

        return (hourly, minutes, sessions)
    }
}
