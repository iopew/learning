import XCTest
@testable import ActivityCore

final class ExportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        calendar.firstWeekday = 2
        return calendar
    }()
    private var paths: [String] = []

    override func setUp() {
        L.current = .ru
    }

    override func tearDown() {
        for path in paths {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        paths = []
    }

    private func tempPath() -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path
        paths.append(path)
        return path
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    func testCSVAndJSON() throws {
        let event = ActivityEvent(id: 1, start: date("2026-10-21 10:00:00"), end: date("2026-10-21 10:01:00"),
                                  bundleID: "com.apple.Safari", appName: "Safari", title: "Go, \"Tour\"",
                                  url: "https://go.dev/tour", domain: "go.dev")
        let short = Export.eventsCSV([event], details: false).split(separator: "\n")
        XCTAssertEqual(short.first, "start,end,seconds,app,bundle_id,domain")
        XCTAssertTrue(short[1].hasSuffix(",60,Safari,com.apple.Safari,go.dev"))
        let full = Export.eventsCSV([event], details: true)
        XCTAssertTrue(full.contains("\"Go, \"\"Tour\"\"\",https://go.dev/tour"))

        var day = DayUsage(day: date("2026-10-21 00:00:00"))
        day.apps = ["com.apple.Safari": 60]
        day.appNames = ["com.apple.Safari": "Safari"]
        day.domains = ["go.dev": 60]
        let daily = Export.dailyCSV([day], days: DayCalendar(calendar: calendar))
        XCTAssertEqual(daily, "day,kind,name,id,seconds\n2026-10-21,app,Safari,com.apple.Safari,60\n2026-10-21,site,go.dev,go.dev,60\n")

        let report = Report(range: .day, fromDay: date("2026-10-21 00:00:00"), toDay: date("2026-10-21 00:00:00"), total: 60,
                            activeDays: 1, apps: [], domains: [], buckets: [], bucketUnit: .day, hourly: [], minutes: [], sessions: [])
        let json = try JSONSerialization.jsonObject(
            with: Export.json(report: report, events: [event], details: false, days: DayCalendar(calendar: calendar))) as? [String: Any]
        XCTAssertEqual(json?["schema"] as? Int, 1)
        XCTAssertEqual(json?["from"] as? String, "2026-10-21")
        let events = json?["events"] as? [[String: Any]]
        XCTAssertEqual(events?.first?["domain"] as? String, "go.dev")
        XCTAssertNil(events?.first?["title"])
    }

    func testCommandLineHelpers() {
        let days = DayCalendar(calendar: calendar)
        let now = date("2026-10-21 10:00:00")
        XCTAssertEqual(PauseLength.until("30m", now: now, days: days), now.addingTimeInterval(1800))
        XCTAssertEqual(PauseLength.until("2h", now: now, days: days), now.addingTimeInterval(7200))
        XCTAssertEqual(PauseLength.until("90", now: now, days: days), now.addingTimeInterval(5400))
        XCTAssertEqual(PauseLength.until("tomorrow", now: now, days: days), date("2026-10-22 00:00:00"))
        XCTAssertNil(PauseLength.until("soon", now: now, days: days))
        XCTAssertEqual(StatsRange(cliName: "7d"), .week)
        XCTAssertEqual(StatsRange(cliName: "year"), .year)
        XCTAssertNil(StatsRange(cliName: "decade"))
    }

    func testViewsAndReadOnlyQueries() throws {
        let path = tempPath()
        let store = try ActivityStore(path: path, days: DayCalendar(calendar: calendar))
        try store.record(Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "Go Tour", url: "https://go.dev/tour"),
                         at: date("2026-10-21 10:00:00"), interval: 5)
        let result = try ActivityStore.query(databaseAt: path, sql: "SELECT app, title, domain, seconds FROM activity")
        XCTAssertEqual(result.columns, ["app", "title", "domain", "seconds"])
        XCTAssertEqual(result.rows, [["Safari", "Go Tour", "go.dev", "5.0"]])
        XCTAssertEqual(try ActivityStore.query(databaseAt: path, sql: "SELECT day, seconds FROM daily_sites").rows,
                       [["2026-10-21", "5.0"]])
        XCTAssertThrowsError(try ActivityStore.query(databaseAt: path, sql: "DELETE FROM events"))   // read-only
        XCTAssertEqual(try store.events(from: date("2026-10-21 00:00:00"), to: date("2026-10-21 00:00:00")).first?.url,
                       "https://go.dev/tour")
    }

    func testDaySummary() throws {
        let days = DayCalendar(calendar: calendar)
        let store = try ActivityStore(path: tempPath(), days: days)
        let code = Sample(bundleID: "code", appName: "VS Code", title: "main.go — learning")
        let video = Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "Go", url: "https://www.youtube.com/watch?v=1")
        var time = date("2026-10-21 09:00:00")
        while time < date("2026-10-21 10:30:00") {
            try store.record(code, at: time, interval: 5)
            time = time.addingTimeInterval(5)
        }
        time = date("2026-10-21 20:00:00")
        while time < date("2026-10-21 20:40:00") {
            try store.record(video, at: time, interval: 5)
            time = time.addingTimeInterval(5)
        }
        let report = try store.report(range: .day, anchor: date("2026-10-21 12:00:00"))
        let switches = Switches.stats(try store.spans(from: report.fromDay, to: report.toDay))
        let lines = DaySummary.make(report: report, switches: switches, usualPerHour: nil, days: days)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Утро, 09:00–10:30: VS Code 1ч 30м.")
        XCTAssertEqual(lines[1], "Вечер, 20:00–20:40: Safari 40м (youtube.com).")
        XCTAssertTrue(lines[2].hasPrefix("Всего 2ч 10м; самый плотный час — 09:00"))
        XCTAssertTrue(lines[2].contains("дольше всего без переключений — 1ч 30м в VS Code"))
    }
}
