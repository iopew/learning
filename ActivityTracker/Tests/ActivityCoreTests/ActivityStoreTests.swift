import XCTest
@testable import ActivityCore

final class ActivityStoreTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        calendar.firstWeekday = 2
        return calendar
    }()
    private var days: DayCalendar { DayCalendar(calendar: calendar) }
    private var path: String!
    private var store: ActivityStore!

    private let xcode = Sample(bundleID: "com.apple.dt.Xcode", appName: "Xcode", title: "main.swift")
    private let safari = Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "YouTube",
                                url: "https://www.youtube.com/watch?v=1")
    private let notes = Sample(bundleID: "com.apple.Notes", appName: "Notes")

    override func setUpWithError() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path
        store = try ActivityStore(path: path, days: days)
    }

    override func tearDownWithError() throws {
        store = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    /// Heartbeats every 5 s for `seconds`, as the collector would send them.
    private func use(_ sample: Sample, from start: Date, seconds: Int) throws {
        var offset = 0
        while offset < seconds {
            try store.record(sample, at: start.addingTimeInterval(TimeInterval(offset)), interval: 5)
            offset += 5
        }
    }

    // MARK: - Recording

    func testHeartbeatsMergeIntoOneEvent() throws {
        let start = date("2026-10-21 10:00:00")
        try use(xcode, from: start, seconds: 15)

        let events = try store.events(on: start)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].start, start)
        XCTAssertEqual(events[0].end, start.addingTimeInterval(15))
        XCTAssertEqual(events[0].title, "main.swift")
    }

    func testSwitchingAppTrimsCreditedTime() throws {
        let start = date("2026-10-21 10:00:00")
        try store.record(xcode, at: start, interval: 5)
        try store.record(safari, at: start.addingTimeInterval(3), interval: 5)

        let events = try store.events(on: start)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].duration, 3)
        XCTAssertEqual(events[1].start, start.addingTimeInterval(3))
        XCTAssertEqual(events[1].duration, 5)
        XCTAssertEqual(events[1].domain, "youtube.com")
        XCTAssertEqual(try store.total(on: start), 8)
    }

    func testTitleChangeStartsNewEvent() throws {
        let start = date("2026-10-21 10:00:00")
        try store.record(xcode, at: start, interval: 5)
        var other = xcode
        other.title = "Package.swift"
        try store.record(other, at: start.addingTimeInterval(5), interval: 5)

        let events = try store.events(on: start)
        XCTAssertEqual(events.map(\.title), ["main.swift", "Package.swift"])
        XCTAssertEqual(try store.total(on: start), 10)
    }

    func testGapStartsNewEvent() throws {
        let start = date("2026-10-21 10:00:00")
        try store.record(xcode, at: start, interval: 5)
        try store.record(xcode, at: start.addingTimeInterval(60), interval: 5)

        let events = try store.events(on: start)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].duration, 5)
        XCTAssertEqual(try store.total(on: start), 10)
    }

    func testDelayedTickStillMerges() throws {
        let start = date("2026-10-21 10:00:00")
        try store.record(xcode, at: start, interval: 5)
        try store.record(xcode, at: start.addingTimeInterval(9), interval: 5)

        let events = try store.events(on: start)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].duration, 14)
    }

    func testEndStreakTakesBackCreditedTime() throws {
        let start = date("2026-10-21 10:00:00")
        try store.record(xcode, at: start, interval: 5)
        try store.endStreak(at: start.addingTimeInterval(2))
        try store.record(xcode, at: start.addingTimeInterval(4), interval: 5)

        let events = try store.events(on: start)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].duration, 2)
        XCTAssertEqual(events[1].start, start.addingTimeInterval(4))
    }

    func testMidnightStartsNewDay() throws {
        let beforeMidnight = date("2026-10-21 23:59:55")
        try use(xcode, from: beforeMidnight, seconds: 10)

        XCTAssertEqual(try store.events(on: beforeMidnight).count, 1)
        let nextDay = date("2026-10-22 12:00:00")
        let events = try store.events(on: nextDay)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].start, date("2026-10-22 00:00:00"))
    }

    func testDataSurvivesReopen() throws {
        let start = date("2026-10-21 10:00:00")
        try use(xcode, from: start, seconds: 30)
        store = nil

        let reopened = try ActivityStore(path: path, days: days)
        XCTAssertEqual(try reopened.total(on: start), 30)
    }

    // MARK: - Reports

    func testWeekReportTotalsAppsDomainsTitles() throws {
        try use(xcode, from: date("2026-10-15 09:00:00"), seconds: 3600)   // 7 days before anchor: outside week
        try use(xcode, from: date("2026-10-16 09:00:00"), seconds: 1800)
        try use(safari, from: date("2026-10-18 20:00:00"), seconds: 600)
        try use(xcode, from: date("2026-10-22 10:00:00"), seconds: 1200)
        try use(notes, from: date("2026-10-22 11:00:00"), seconds: 60)

        let report = try store.report(range: .week, anchor: date("2026-10-22 18:00:00"))

        XCTAssertEqual(days.key(report.fromDay), "2026-10-16")
        XCTAssertEqual(days.key(report.toDay), "2026-10-22")
        XCTAssertEqual(report.total, 1800 + 600 + 1200 + 60)
        XCTAssertEqual(report.activeDays, 3)
        XCTAssertEqual(report.averagePerActiveDay, (1800 + 600 + 1200 + 60) / 3)
        XCTAssertEqual(report.apps.map(\.appName), ["Xcode", "Safari", "Notes"])
        XCTAssertEqual(report.apps[0].seconds, 3000)
        XCTAssertEqual(report.apps[0].topTitles, [TitleUsage(title: "main.swift", seconds: 3000)])
        XCTAssertEqual(report.apps[2].topTitles, [])
        XCTAssertEqual(report.domains, [DomainUsage(domain: "youtube.com", seconds: 600)])
        XCTAssertEqual(report.bucketUnit, .day)
        XCTAssertEqual(report.buckets.count, 7)
        XCTAssertEqual(report.buckets.map(\.seconds), [1800, 0, 600, 0, 0, 0, 1260])
        XCTAssertTrue(report.sessions.isEmpty)
        XCTAssertTrue(report.minutes.isEmpty)
    }

    func testLongRangesUseWeeklyBuckets() throws {
        try use(xcode, from: date("2026-10-20 09:00:00"), seconds: 600)   // Tuesday
        try use(xcode, from: date("2026-10-22 09:00:00"), seconds: 300)   // Thursday, same week

        let report = try store.report(range: .year, anchor: date("2026-10-22 12:00:00"))

        XCTAssertEqual(report.bucketUnit, .week)
        XCTAssertEqual(report.buckets.reduce(0.0) { $0 + $1.seconds }, 900)
        XCTAssertEqual(report.buckets.last?.start, date("2026-10-19 00:00:00"))   // Monday
        XCTAssertEqual(report.buckets.last?.seconds, 900)
        XCTAssertTrue(report.buckets.count >= 52 && report.buckets.count <= 54)
    }

    func testAllRangeStartsAtFirstRecordedDay() throws {
        try use(xcode, from: date("2026-09-01 09:00:00"), seconds: 60)
        try use(xcode, from: date("2026-10-22 09:00:00"), seconds: 60)

        let report = try store.report(range: .all, anchor: date("2026-10-22 12:00:00"))
        XCTAssertEqual(days.key(report.fromDay), "2026-09-01")
        XCTAssertEqual(report.total, 120)
        XCTAssertEqual(report.activeDays, 2)
    }

    func testAllRangeWithoutDataIsJustTheAnchorDay() throws {
        let report = try store.report(range: .all, anchor: date("2026-10-22 12:00:00"))
        XCTAssertEqual(days.key(report.fromDay), "2026-10-22")
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.buckets.count, 1)
    }

    func testDayReportMinutesHourlyAndSessions() throws {
        try use(xcode, from: date("2026-10-22 10:00:00"), seconds: 90)     // 10:00:00–10:01:30
        try use(safari, from: date("2026-10-22 10:01:30"), seconds: 60)    // 10:01:30–10:02:30
        try use(xcode, from: date("2026-10-22 11:30:00"), seconds: 120)

        let report = try store.report(range: .day, anchor: date("2026-10-22 18:00:00"))

        XCTAssertEqual(report.minutes.count, 1440)
        let tenOClock = 10 * 60
        XCTAssertEqual(report.minutes[tenOClock]?.appName, "Xcode")
        XCTAssertEqual(report.minutes[tenOClock]?.seconds, 60)
        // 10:01 is split 30 s Xcode / 30 s Safari: ties resolve deterministically.
        XCTAssertNotNil(report.minutes[tenOClock + 1])
        XCTAssertEqual(report.minutes[tenOClock + 2]?.appName, "Safari")
        XCTAssertNil(report.minutes[tenOClock + 3])
        XCTAssertEqual(report.minutes[11 * 60 + 31]?.appName, "Xcode")

        let hourly = Dictionary(grouping: report.hourly, by: \.hour).mapValues { $0.reduce(0.0) { $0 + $1.seconds } }
        XCTAssertEqual(hourly[10], 150)
        XCTAssertEqual(hourly[11], 120)
        XCTAssertEqual(report.hourly.reduce(0.0) { $0 + $1.seconds }, report.total)

        XCTAssertEqual(report.sessions.map(\.appName), ["Xcode", "Safari", "Xcode"])
        XCTAssertEqual(report.sessions[0].duration, 90)
        XCTAssertEqual(report.sessions[1].details, ["youtube.com"])
        XCTAssertEqual(report.sessions[0].details, ["main.swift"])
    }

    func testSessionsMergeSameAppAcrossTitlesAndShortGaps() throws {
        var other = xcode
        other.title = "Package.swift"
        try use(xcode, from: date("2026-10-22 10:00:00"), seconds: 300)
        try use(other, from: date("2026-10-22 10:05:30"), seconds: 600)   // 30 s gap
        try use(notes, from: date("2026-10-22 10:20:00"), seconds: 60)

        let report = try store.report(range: .day, anchor: date("2026-10-22 18:00:00"))

        XCTAssertEqual(report.sessions.count, 2)
        XCTAssertEqual(report.sessions[0].start, date("2026-10-22 10:00:00"))
        XCTAssertEqual(report.sessions[0].end, date("2026-10-22 10:15:30"))
        XCTAssertEqual(report.sessions[0].details, ["Package.swift", "main.swift"])
        XCTAssertEqual(report.sessions[1].appName, "Notes")
    }

    func testHourlyFoldsMinorAppsIntoOther() throws {
        let start = date("2026-10-22 09:00:00")
        for index in 0..<7 {
            let sample = Sample(bundleID: "app.\(index)", appName: "App \(index)")
            try use(sample, from: start.addingTimeInterval(TimeInterval(index * 600)), seconds: 600 - index * 60)
        }

        let report = try store.report(range: .day, anchor: start)
        let bundles = Set(report.hourly.map(\.bundleID))

        XCTAssertEqual(bundles, ["app.0", "app.1", "app.2", "app.3", "app.4", ActivityStore.otherBundleID])
        let otherSlices = report.hourly.filter { $0.bundleID == ActivityStore.otherBundleID }
        let other = otherSlices.reduce(0.0) { $0 + $1.seconds }
        XCTAssertEqual(other, 540)   // app.5 (300 s) + app.6 (240 s)
    }

    // MARK: - Deleting

    func testEraseDomainRemovesOnlyThatSite() throws {
        let start = date("2026-10-22 10:00:00")
        try use(xcode, from: start, seconds: 60)
        try use(safari, from: start.addingTimeInterval(60), seconds: 60)

        XCTAssertEqual(try store.erase(.domain("youtube.com")), 1)
        let events = try store.events(on: start)
        XCTAssertEqual(events.map(\.appName), ["Xcode"])
        XCTAssertEqual(try store.report(range: .day, anchor: start).domains, [])
    }

    func testEraseApp() throws {
        let start = date("2026-10-22 10:00:00")
        try use(xcode, from: start, seconds: 60)
        try use(notes, from: start.addingTimeInterval(60), seconds: 60)
        try store.erase(.app("com.apple.dt.Xcode"))
        XCTAssertEqual(try store.events(on: start).map(\.appName), ["Notes"])
    }

    func testForgetLastMinutesCutsTheRunningEvent() throws {
        let start = date("2026-10-22 10:00:00")
        try use(xcode, from: start, seconds: 600)                        // 10:00–10:10
        try use(safari, from: start.addingTimeInterval(600), seconds: 300)   // 10:10–10:15

        try store.erase(.since(date("2026-10-22 10:05:00")))
        let events = try store.events(on: start)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].end, date("2026-10-22 10:05:00"))
        XCTAssertEqual(try store.total(on: start), 300)
    }

    func testRecordingContinuesAfterErase() throws {
        let start = date("2026-10-22 10:00:00")
        try use(xcode, from: start, seconds: 30)
        try store.erase(.all)
        XCTAssertEqual(try store.total(on: start), 0)
        // The open event was deleted: the next heartbeat must start a fresh one, not extend a ghost.
        try store.record(xcode, at: start.addingTimeInterval(30), interval: 5)
        XCTAssertEqual(try store.total(on: start), 5)
    }

    // MARK: - Helpers

    func testDomainExtraction() {
        XCTAssertEqual(URLTools.domain(from: "https://www.youtube.com/watch?v=1"), "youtube.com")
        XCTAssertEqual(URLTools.domain(from: "http://Docs.Swift.org/x"), "docs.swift.org")
        XCTAssertEqual(URLTools.domain(from: "chrome://newtab/"), "")
        XCTAssertEqual(URLTools.domain(from: "file:///Users/me/a.html"), "")
        XCTAssertEqual(URLTools.domain(from: ""), "")
    }

    func testFormatting() {
        XCTAssertEqual(Format.duration(18720), "5ч 12м")
        XCTAssertEqual(Format.duration(7200), "2ч")
        XCTAssertEqual(Format.duration(720), "12м")
        XCTAssertEqual(Format.duration(42), "42с")
        XCTAssertEqual(Format.percent(25, of: 100), "25%")
        XCTAssertEqual(Format.percent(0.1, of: 100), "<1%")
        XCTAssertEqual(Format.percent(1, of: 0), "0%")
    }

    func testDayKeysFollowTheCalendarTimeZone() {
        // 2026-10-21 20:00 UTC is already the 22nd in Tashkent (UTC+5).
        let instant = Date(timeIntervalSince1970: 1_792_612_800)
        XCTAssertEqual(days.key(instant), "2026-10-22")
        XCTAssertEqual(days.date(fromKey: "2026-10-22"), date("2026-10-22 00:00:00"))
        XCTAssertNil(days.date(fromKey: ""))
    }
}
