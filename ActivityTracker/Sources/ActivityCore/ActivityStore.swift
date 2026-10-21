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
                title TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL DEFAULT '',
                domain TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS events_day ON events(day);
            """)
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

        try db.run(
            "INSERT INTO events(day, start_at, end_at, bundle_id, app, title, url, domain) VALUES(?,?,?,?,?,?,?,?)",
            [.text(day), .double(time.timeIntervalSince1970), .double(creditedEnd.timeIntervalSince1970),
             .text(sample.bundleID), .text(sample.appName), .text(sample.title), .text(sample.url),
             .text(sample.domain)])
        open = OpenEvent(id: db.lastInsertRowID, sample: sample, day: day, start: time, end: creditedEnd)
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
        case .all:
            try db.run("DELETE FROM events")
            affected = db.changes
        }
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        return affected
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
            "SELECT id, start_at, end_at, bundle_id, app, title, url, domain FROM events WHERE day = ? ORDER BY start_at",
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

    // MARK: - Reports

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
                SELECT title, \(duration) AS seconds FROM events
                WHERE day BETWEEN ? AND ? AND bundle_id = ? AND title != ''
                GROUP BY title ORDER BY seconds DESC LIMIT 5
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
            hourly: [], minutes: [], sessions: [])

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
