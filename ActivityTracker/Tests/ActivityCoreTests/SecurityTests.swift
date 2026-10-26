import XCTest
@testable import ActivityCore

/// What a hostile web page title, a poisoned update feed, a crafted database file or a malformed command could try.
final class SecurityTests: XCTestCase {
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

    // MARK: - SQL injection

    func testHostileTitlesAreStoredAsText() throws {
        let path = tempPath()
        let store = try ActivityStore(path: path)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let title = "'); DROP TABLE events; --"
        let url = "https://evil.example/?q=' OR 1=1 --"
        try store.record(Sample(bundleID: "com.apple.Safari", appName: "Safari", title: title, url: url),
                         at: start, interval: 5)
        try store.record(Sample(bundleID: "x\"; DELETE FROM texts; --", appName: "Robert'); DROP TABLE texts;--"),
                         at: start.addingTimeInterval(5), interval: 5)
        try store.endStreak(at: start.addingTimeInterval(10))

        let events = try store.events(from: start.addingTimeInterval(-86400), to: start.addingTimeInterval(86400))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.title, title)
        XCTAssertEqual(events.first?.url, url)
        XCTAssertEqual(events.last?.appName, "Robert'); DROP TABLE texts;--")

        // Both tables are still there, and erasing by a hostile name only matches that exact name.
        XCTAssertEqual(try store.erase(.app("' OR '1'='1")), 0)
        XCTAssertEqual(try store.erase(.domain("' OR 1=1 --")), 0)
        XCTAssertEqual(try store.events(from: start.addingTimeInterval(-86400), to: start.addingTimeInterval(86400)).count, 2)
    }

    func testCommandLineSQLIsReadOnly() throws {
        let path = tempPath()
        let store = try ActivityStore(path: path)
        try store.record(Sample(bundleID: "a", appName: "A"), at: Date(timeIntervalSince1970: 1_790_000_000), interval: 5)
        try store.endStreak(at: Date(timeIntervalSince1970: 1_790_000_005))

        XCTAssertThrowsError(try ActivityStore.query(databaseAt: path, sql: "DELETE FROM events"))
        XCTAssertThrowsError(try ActivityStore.query(databaseAt: path, sql: "DROP TABLE events"))
        XCTAssertThrowsError(try ActivityStore.query(databaseAt: path, sql: "ATTACH DATABASE '/tmp/x.sqlite' AS x"))
        // A second statement after a SELECT is never run.
        _ = try ActivityStore.query(databaseAt: path, sql: "SELECT 1; DELETE FROM events")
        XCTAssertEqual(try ActivityStore.query(databaseAt: path, sql: "SELECT COUNT(*) FROM events").rows, [["1"]])
    }

    // MARK: - Opening a saved database

    func testArchiveWithTriggersIsRefused() throws {
        let path = tempPath()
        _ = try ActivityStore(path: path)
        XCTAssertNil(ActivityStore.archiveProblem(at: path))

        let db = try Database(path: path)
        try db.execute("CREATE TRIGGER sneaky AFTER INSERT ON events BEGIN DELETE FROM texts; END;")
        XCTAssertNotNil(ActivityStore.archiveProblem(at: path))
    }

    func testNonDatabaseFileIsRefused() throws {
        let path = tempPath()
        try Data("not a database at all".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertNotNil(ActivityStore.archiveProblem(at: path))
        XCTAssertNotNil(ActivityStore.archiveProblem(at: path + ".missing"))
    }

    func testOversizedArchiveIsRefused() throws {
        let path = tempPath()
        _ = try ActivityStore(path: path)
        XCTAssertNotNil(ActivityStore.archiveProblem(at: path, maximumSize: 10))
    }

    // MARK: - Erasing leaves nothing behind

    func testEraseRemovesTitlesAndURLs() throws {
        let path = tempPath()
        let store = try ActivityStore(path: path)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        try store.record(Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "Secret page",
                                url: "https://secret.example/page"), at: start, interval: 5)
        try store.endStreak(at: start.addingTimeInterval(5))
        try store.erase(.domain("secret.example"))

        let texts = try ActivityStore.query(databaseAt: path, sql: "SELECT COUNT(*) FROM texts WHERE value LIKE '%ecret%'")
        XCTAssertEqual(texts.rows, [["0"]])
    }

    // MARK: - CSV formula injection

    func testCSVFormulasAreDefused() {
        XCTAssertEqual(Export.csvField("=HYPERLINK(\"http://evil\")"), "\"'=HYPERLINK(\"\"http://evil\"\")\"")
        XCTAssertEqual(Export.csvField("+1"), "'+1")
        XCTAssertEqual(Export.csvField("-2+3"), "'-2+3")
        XCTAssertEqual(Export.csvField("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(Export.csvField("\tcmd"), "'\tcmd")
        XCTAssertEqual(Export.csvField("plain"), "plain")
        XCTAssertEqual(Export.csvField("a=b"), "a=b")
    }

    // MARK: - Updates

    func testOnlyGitHubHTTPSDownloadsAreTrusted() {
        let tag = "activity-tracker-build-30"
        let good = "https://github.com/iopew/learning/releases/download/\(tag)/ActivityTracker.zip"
        XCTAssertTrue(UpdateFeed.isTrustedDownload(URL(string: good)!, tag: tag))
        for bad in [
            "http://github.com/iopew/learning/releases/download/\(tag)/ActivityTracker.zip",
            "https://evil.example/iopew/learning/releases/download/\(tag)/ActivityTracker.zip",
            "https://github.com.evil.example/iopew/learning/releases/download/\(tag)/ActivityTracker.zip",
            "https://github.com/someone/else/releases/download/\(tag)/ActivityTracker.zip",
            "https://github.com/iopew/learning/releases/download/activity-tracker-build-29/ActivityTracker.zip",
            "https://github.com/iopew/learning/releases/download/\(tag)/Other.zip",
            "https://user@github.com/iopew/learning/releases/download/\(tag)/ActivityTracker.zip",
            "https://github.com:8443/iopew/learning/releases/download/\(tag)/ActivityTracker.zip",
            "https://github.com/iopew/learning/releases/download/\(tag)/ActivityTracker.zip?x=1",
            "file:///tmp/ActivityTracker.zip",
        ] {
            XCTAssertFalse(UpdateFeed.isTrustedDownload(URL(string: bad)!, tag: tag), bad)
        }
    }

    func testPoisonedFeedIsIgnored() throws {
        func release(_ build: Int, url: String) -> String {
            """
            {"tag_name": "activity-tracker-build-\(build)", "body": "", "assets": [{"name": "ActivityTracker.zip",
             "browser_download_url": "\(url)"}]}
            """
        }
        let base = "https://github.com/iopew/learning/releases/download/activity-tracker-build-"
        let json = "[" + [
            release(25, url: "https://evil.example/ActivityTracker.zip"),
            release(2_000_000_000, url: base + "2000000000/ActivityTracker.zip"),
            release(24, url: base + "24/ActivityTracker.zip"),
        ].joined(separator: ",") + "]"
        let update = try UpdateFeed.newest(in: Data(json.utf8), newerThan: 22)
        XCTAssertEqual(update?.build, 24)
    }

    func testArchiveListing() {
        XCTAssertTrue(UpdateFeed.isSafeArchiveListing(["ActivityTracker.app/", "ActivityTracker.app/Contents/Info.plist"]))
        XCTAssertFalse(UpdateFeed.isSafeArchiveListing([]))
        XCTAssertFalse(UpdateFeed.isSafeArchiveListing(["ActivityTracker.app/../../.zshrc"]))
        XCTAssertFalse(UpdateFeed.isSafeArchiveListing(["/Applications/Evil.app/x"]))
        XCTAssertFalse(UpdateFeed.isSafeArchiveListing(["ActivityTracker.app/x", "Evil.app/x"]))
        XCTAssertFalse(UpdateFeed.isSafeArchiveListing(["ActivityTracker.appx/y"]))
    }

    // MARK: - Commands from outside

    func testPauseLengthRefusesNonsense() {
        let days = DayCalendar()
        let now = Date()
        for bad in ["nan", "inf", "-5", "0", "1e300", "25h", "abc", "", "30x"] {
            XCTAssertNil(PauseLength.until(bad, now: now, days: days), bad)
        }
        XCTAssertEqual(PauseLength.until("30m", now: now, days: days), now.addingTimeInterval(1800))
        XCTAssertEqual(PauseLength.until("2h", now: now, days: days), now.addingTimeInterval(7200))
        XCTAssertNotNil(PauseLength.until("tomorrow", now: now, days: days))
        XCTAssertNil(PauseLength.valid(.nan))
        XCTAssertNil(PauseLength.valid(.infinity))
        XCTAssertNil(PauseLength.valid(nil))
        XCTAssertEqual(PauseLength.valid(1440), 1440)
    }

    // MARK: - Correctness fixes from the review

    func testKernelResourceReportIsNotAPanic() {
        let event = StabilityParser.parse(fileName: "kernel_task_2026-10-20-101010_Mac.cpu_resource.diag", head: "",
                                          modified: Date())
        XCTAssertNotEqual(event?.kind, .panic)
        XCTAssertEqual(StabilityParser.parse(fileName: "Kernel-2026-10-20-101010.panic", head: "", modified: Date())?.kind,
                       .panic)
    }

    func testShortLowercaseNamesAreNotServices() {
        XCTAssertFalse(StabilityNames.isSystem("zed"))
        XCTAssertTrue(StabilityNames.isSystem("bluetoothd"))
    }

    func testDayBoundaryAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let days = DayCalendar(calendar: calendar, startHour: 4)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        // Clocks go back at 02:00 on 2026-11-01: 03:30 is still the evening of October 31, 04:30 is November 1.
        XCTAssertEqual(days.key(formatter.date(from: "2026-11-01 03:30")!), "2026-10-31")
        XCTAssertEqual(days.key(formatter.date(from: "2026-11-01 04:30")!), "2026-11-01")
        XCTAssertEqual(formatter.string(from: days.startOfDay(formatter.date(from: "2026-11-01 12:00")!)), "2026-11-01 04:00")
        // Clocks go forward on 2026-03-08.
        XCTAssertEqual(formatter.string(from: days.startOfDay(formatter.date(from: "2026-03-08 12:00")!)), "2026-03-08 04:00")
    }

    func testSQLRekeyMatchesCalendar() throws {
        let path = tempPath()
        let days = DayCalendar(calendar: Calendar.current, startHour: 4)
        let store = try ActivityStore(path: path, days: DayCalendar(calendar: Calendar.current))
        let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        for hour in [1, 3, 5, 23] {
            try store.record(Sample(bundleID: "a\(hour)", appName: "A"), at: base.addingTimeInterval(Double(hour) * 3600),
                             interval: 5)
            try store.endStreak(at: base.addingTimeInterval(Double(hour) * 3600 + 5))
        }
        let rekeyed = try ActivityStore(path: path, days: days)
        _ = try rekeyed.rekeyDays()
        let rows = try ActivityStore.query(databaseAt: path, sql: "SELECT start_at, day FROM events").rows
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            let start = Date(timeIntervalSince1970: Double(row[0])!)
            XCTAssertEqual(row[1], days.key(start))
        }
    }
}
