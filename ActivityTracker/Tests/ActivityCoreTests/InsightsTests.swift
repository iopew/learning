import XCTest
@testable import ActivityCore

final class InsightsTests: XCTestCase {
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

    private func event(_ app: String, _ start: String, _ end: String) -> ActivityEvent {
        ActivityEvent(id: 0, start: date(start), end: date(end), bundleID: app, appName: app.uppercased(),
                      title: "", url: "", domain: "")
    }

    // MARK: - Day boundary

    func testDayStartingAtFourKeepsTheNightInThePreviousDay() {
        let days = DayCalendar(calendar: calendar, startHour: 4)
        XCTAssertEqual(days.key(date("2026-10-22 03:59:00")), "2026-10-21")
        XCTAssertEqual(days.key(date("2026-10-22 04:00:00")), "2026-10-22")
        XCTAssertEqual(days.startOfDay(date("2026-10-22 02:00:00")), date("2026-10-21 04:00:00"))
        XCTAssertEqual(days.date(fromKey: "2026-10-21"), date("2026-10-21 04:00:00"))
        XCTAssertEqual(days.midnight(of: date("2026-10-22 02:00:00")), date("2026-10-21 00:00:00"))
        XCTAssertEqual(days.addingDays(1, to: date("2026-10-21 04:00:00")), date("2026-10-22 04:00:00"))
        // Monday 2026-10-19; Monday 01:00 still belongs to Sunday, so to the week before.
        XCTAssertEqual(days.startOfWeek(date("2026-10-21 12:00:00")), date("2026-10-19 04:00:00"))
        XCTAssertEqual(days.startOfWeek(date("2026-10-19 01:00:00")), date("2026-10-12 04:00:00"))
        XCTAssertEqual(days.dayCount(from: date("2026-10-21 05:00:00"), to: date("2026-10-23 02:00:00")), 2)
    }

    func testMidnightDayIsUnchanged() {
        let days = DayCalendar(calendar: calendar)
        XCTAssertEqual(days.key(date("2026-10-22 00:30:00")), "2026-10-22")
        XCTAssertEqual(days.startOfDay(date("2026-10-22 00:30:00")), date("2026-10-22 00:00:00"))
        XCTAssertEqual(days.midnight(of: date("2026-10-22 00:30:00")), date("2026-10-22 00:00:00"))
    }

    func testRekeyMovesNightEventsToThePreviousDay() throws {
        let path = tempPath()
        let sample = Sample(bundleID: "a", appName: "A")
        do {
            let store = try ActivityStore(path: path, days: DayCalendar(calendar: calendar))
            try store.record(sample, at: date("2026-10-22 02:00:00"), interval: 5)
            try store.endStreak(at: date("2026-10-22 02:00:05"))
            try store.record(sample, at: date("2026-10-22 10:00:00"), interval: 5)
        }
        let shifted = DayCalendar(calendar: calendar, startHour: 4)
        let store = try ActivityStore(path: path, days: shifted)
        XCTAssertEqual(try store.rekeyDays(), 1)
        XCTAssertEqual(try store.total(on: date("2026-10-21 12:00:00")), 5)
        XCTAssertEqual(try store.total(on: date("2026-10-22 12:00:00")), 5)
        XCTAssertEqual(try store.rekeyDays(), 0)

        let report = try store.report(range: .day, anchor: date("2026-10-21 12:00:00"))
        XCTAssertEqual(report.firstHour, 4)
        // 02:00 is 22 hours after the 04:00 day start.
        XCTAssertNotNil(report.minutes[22 * 60])

        let systemStore = try SystemStore(path: path, days: shifted)
        XCTAssertEqual(try systemStore.rekeyDays(), 0)
    }

    func testLateNightRespectsTheDayStart() {
        var minutes = [MinuteCell?](repeating: nil, count: 1440)
        let cell = MinuteCell(bundleID: "a", appName: "A", seconds: 60)
        minutes[0] = cell            // 04:00 – counted (before 05:00)
        minutes[60] = cell           // 05:00 – not counted
        minutes[21 * 60] = cell      // 01:00 – counted
        minutes[19 * 60] = cell      // 23:00 – not counted
        XCTAssertEqual(Recommendations.lateNight(minutes: minutes, firstHour: 4), 120)
    }

    // MARK: - Switches

    func testSwitchesMergeRowsDropPeeksAndBreakOnPauses() {
        let events = [
            event("code", "2026-10-21 10:00:00", "2026-10-21 10:10:00"),
            event("code", "2026-10-21 10:10:00", "2026-10-21 10:20:00"),   // new title, same app
            event("chat", "2026-10-21 10:20:00", "2026-10-21 10:20:05"),   // a peek: dropped
            event("code", "2026-10-21 10:20:05", "2026-10-21 10:30:00"),
            event("chat", "2026-10-21 10:30:00", "2026-10-21 10:35:00"),   // switch 1
            event("code", "2026-10-21 10:35:00", "2026-10-21 10:40:00"),   // switch 2
            event("web", "2026-10-21 11:00:00", "2026-10-21 11:10:00"),    // after a 20-minute pause: no switch
            event("code", "2026-10-21 11:10:00", "2026-10-21 11:20:00"),   // switch 3
        ]
        let stats = Switches.stats(events)
        XCTAssertEqual(stats.switches, 3)
        XCTAssertEqual(stats.longestRun?.bundleID, "code")
        XCTAssertEqual(stats.longestRun?.duration, 30 * 60)
        XCTAssertEqual(stats.pairs.first, SwitchPair(firstName: "CHAT", secondName: "CODE", count: 2))
        XCTAssertEqual(stats.activeSeconds, 60 * 60)
        XCTAssertEqual(stats.perHour!, 3, accuracy: 0.001)
        // Runs: code 30m, chat 5m, code 5m, web 10m, code 10m → median 10m.
        XCTAssertEqual(stats.medianRun, 10 * 60)
    }

    func testClipKeepsOnlyTheWindow() {
        let events = [event("a", "2026-10-21 09:00:00", "2026-10-21 10:30:00")]
        let clipped = Switches.clip(events, from: date("2026-10-21 10:00:00"), to: date("2026-10-21 11:00:00"))
        XCTAssertEqual(clipped.first?.duration, 30 * 60)
        XCTAssertTrue(Switches.clip(events, from: date("2026-10-21 11:00:00"), to: date("2026-10-21 12:00:00")).isEmpty)
    }

    // MARK: - Rhythm

    func testRhythmMeasuresFromMidnightAndFindsAShift() {
        let days = DayCalendar(calendar: calendar, startHour: 4)
        var stats: [DayStat] = []
        for index in 0..<14 {
            let day = days.addingDays(index, to: date("2026-10-01 04:00:00"))
            let midnight = days.midnight(of: day)
            // The last 7 days end an hour later (01:00 instead of midnight).
            let end = midnight.addingTimeInterval(index >= 7 ? 25 * 3600 : 24 * 3600)
            stats.append(DayStat(day: day, first: midnight.addingTimeInterval(9 * 3600), last: end, seconds: 8 * 3600))
        }
        stats.append(DayStat(day: date("2026-10-15 04:00:00"), first: date("2026-10-15 05:00:00"),
                             last: date("2026-10-15 05:05:00"), seconds: 300))   // too short, ignored
        let summary = RhythmSummary.make(stats, days: days)
        XCTAssertEqual(summary.points.count, 14)
        XCTAssertEqual(summary.typicalStart, 9)
        XCTAssertEqual(summary.points.last?.endHour, 25)
        XCTAssertEqual(summary.recentEndShift, 60)
        XCTAssertEqual(summary.recentStartShift, 0)
        XCTAssertEqual(RhythmSummary.clock(25.5), "01:30")
        XCTAssertEqual(RhythmSummary.clock(9.25), "09:15")
    }

    // MARK: - Comparison and trend

    func testComparisonAveragesPerCalendarDay() {
        var monday = DayUsage(day: date("2026-10-19 00:00:00"))
        monday.total = 5 * 3600
        monday.apps = ["code": 14400.0, "chat": 3600.0]
        monday.appNames = ["code": "Code", "chat": "Chat"]
        monday.domains = ["go.dev": 1800.0]
        var saturday = DayUsage(day: date("2026-10-24 00:00:00"))
        saturday.total = 2 * 3600
        saturday.apps = ["video": 7200.0]
        saturday.appNames = ["video": "Video"]

        let comparison = UsageComparison.make(first: [monday], firstDays: 5, second: [saturday], secondDays: 2)
        XCTAssertEqual(comparison.first.perDay, 3600)
        XCTAssertEqual(comparison.second.perDay, 3600)
        XCTAssertEqual(comparison.first.activeDays, 1)
        let code = comparison.apps.first { $0.target == .app("code") }
        XCTAssertEqual(code?.first, 48 * 60)
        XCTAssertEqual(code?.isNew, true)
        XCTAssertEqual(comparison.apps.first { $0.target == .app("video") }?.isGone, true)
        XCTAssertEqual(comparison.sites.first?.name, "go.dev")
    }

    func testTrendFillsGapsAndFitsASlope() {
        let days = DayCalendar(calendar: calendar)
        let from = date("2026-08-01 00:00:00")
        var daily: [String: TimeInterval] = [:]
        for index in 0..<28 {
            daily[days.key(days.addingDays(index, to: from))] = TimeInterval(index * 60)   // +1 minute a day
        }
        let trend = UsageTrend.make(daily: daily, from: from, to: days.addingDays(29, to: from), days: days)
        XCTAssertEqual(trend.points.count, 30)
        XCTAssertEqual(trend.points.last?.seconds, 0)
        XCTAssertEqual(trend.activeDays, 27)   // day 0 had 0 minutes
        XCTAssertEqual(trend.record?.seconds, 27 * 60)
        XCTAssertNotNil(trend.slopePerWeek)
        XCTAssertEqual(trend.points[6].average, 3 * 60)   // mean of 0…6 minutes

        let short = UsageTrend.make(daily: daily, from: from, to: days.addingDays(9, to: from), days: days)
        XCTAssertNil(short.slopePerWeek)
        XCTAssertEqual(UsageTrend.slope([1, 2, 3, 4]), 1, accuracy: 1e-9)
    }

    func testTitleCleaner() {
        XCTAssertEqual(TitleCleaner.clean("(3) Go Concurrency - YouTube"), "Go Concurrency")
        XCTAssertEqual(TitleCleaner.clean("(new) Notes"), "(new) Notes")
        XCTAssertEqual(TitleCleaner.clean("main.go — project"), "main.go — project")
    }

    func testUsageHistoryAndDailyUsage() throws {
        let days = DayCalendar(calendar: calendar)
        let store = try ActivityStore(path: tempPath(), days: days)
        let video = Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "(2) Channels - YouTube",
                           url: "https://www.youtube.com/watch?v=1")
        let video2 = Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "Channels - YouTube",
                            url: "https://www.youtube.com/watch?v=1")
        try store.record(video, at: date("2026-10-20 10:00:00"), interval: 5)
        try store.record(video2, at: date("2026-10-21 10:00:00"), interval: 5)
        let history = try store.usageHistory(of: .domain("youtube.com"), from: date("2026-10-19 00:00:00"),
                                             to: date("2026-10-21 00:00:00"))
        XCTAssertEqual(history.daily, ["2026-10-20": 5, "2026-10-21": 5])
        XCTAssertEqual(history.titles, [TitleUsage(title: "Channels", seconds: 10)])

        let usage = try store.dailyUsage(from: date("2026-10-19 00:00:00"), to: date("2026-10-21 00:00:00"))
        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage.first?.apps["com.apple.Safari"], 5)
        XCTAssertEqual(usage.first?.domains["youtube.com"], 5)

        let stats = try store.dayStats(from: date("2026-10-19 00:00:00"), to: date("2026-10-21 00:00:00"))
        XCTAssertEqual(stats.map(\.seconds), [5, 5])
        XCTAssertEqual(try store.spans(from: date("2026-10-20 00:00:00"), to: date("2026-10-21 00:00:00")).count, 2)
    }

    // MARK: - Digest

    func testDigestScheduleWithCatchUp() {
        let days = DayCalendar(calendar: calendar)
        let evening = date("2026-10-21 21:30:00")
        let morning = date("2026-10-22 09:00:00")
        XCTAssertEqual(DigestSchedule.dueDay(now: evening, hour: 21, lastSent: nil, days: days), date("2026-10-21 00:00:00"))
        XCTAssertNil(DigestSchedule.dueDay(now: evening, hour: 21, lastSent: "2026-10-21", days: days))
        XCTAssertNil(DigestSchedule.dueDay(now: date("2026-10-21 20:00:00"), hour: 21, lastSent: "2026-10-20", days: days))
        // The Mac was closed in the evening: yesterday's digest comes in the morning.
        XCTAssertEqual(DigestSchedule.dueDay(now: morning, hour: 21, lastSent: "2026-10-20", days: days), date("2026-10-21 00:00:00"))
        XCTAssertNil(DigestSchedule.dueDay(now: morning, hour: 21, lastSent: "2026-10-21", days: days))
        XCTAssertNil(DigestSchedule.dueDay(now: morning, hour: 21, lastSent: nil, days: days))

        // Monday 2026-10-19 at 21:00 the week of 12…18 October is due.
        XCTAssertNil(DigestSchedule.dueWeek(now: date("2026-10-19 20:00:00"), hour: 21, lastSent: nil, days: days))
        XCTAssertEqual(DigestSchedule.dueWeek(now: date("2026-10-19 21:00:00"), hour: 21, lastSent: "2026-10-05", days: days),
                       date("2026-10-12 00:00:00"))
        XCTAssertNil(DigestSchedule.dueWeek(now: date("2026-10-21 10:00:00"), hour: 21, lastSent: "2026-10-12", days: days))
    }

    func testDigestTexts() {
        let report = Report(range: .day, fromDay: Date(), toDay: Date(), total: 4 * 3600, activeDays: 1,
                            apps: [AppUsage(bundleID: "code", appName: "VS Code", seconds: 3 * 3600, topTitles: [])],
                            domains: [DomainUsage(domain: "youtube.com", seconds: 1800)], buckets: [], bucketUnit: .day,
                            hourly: [], minutes: [], sessions: [])
        let run = AppRun(bundleID: "code", appName: "VS Code", start: Date(), end: Date().addingTimeInterval(3120), linked: false)
        let switches = SwitchStats(switches: 40, activeSeconds: 4 * 3600, medianRun: 300, longestRun: run, pairs: [])
        let message = Digest.daily(report: report, switches: switches, tip: nil)
        XCTAssertEqual(message?.title, "Итог дня: 4ч")
        XCTAssertEqual(message?.body, "VS Code 3ч · youtube.com 30м\nЛучший фокус 52м в VS Code, 10 переключений в час")

        var empty = report
        empty.total = 60
        XCTAssertNil(Digest.daily(report: empty, switches: .empty, tip: nil))

        var previous = report
        previous.total = 2 * 3600
        previous.apps = [AppUsage(bundleID: "code", appName: "VS Code", seconds: 3600, topTitles: [])]
        var week = report
        week.range = .week
        week.activeDays = 2
        let weekly = Digest.weekly(week: week, previous: previous)
        XCTAssertEqual(weekly?.title, "Неделя: 4ч (+100%)")
        XCTAssertEqual(weekly?.body, "Больше всего: VS Code 3ч (+2ч)\nАктивных дней: 2 из 7, в среднем 2ч")
    }

    // MARK: - Breaks

    func testBreakReminderWaitsForANaturalPause() {
        var coach = BreakCoach()
        let start = date("2026-10-21 09:00:00")
        var now = start
        func tick(idle: TimeInterval = 0, app: String = "code", inCall: Bool = false, away: Bool = false) -> TimeInterval? {
            defer { now = now.addingTimeInterval(5) }
            return coach.update(now: now, idle: idle, away: away, app: app, inCall: { inCall })
        }
        // 95 minutes of typing in one app: past the soft limit, but no natural pause yet.
        for _ in 0..<(95 * 12) { XCTAssertNil(tick()) }
        // Switching apps is a natural pause → reminder.
        XCTAssertNotNil(tick(app: "chat"))
        // Not again right away.
        XCTAssertNil(tick(app: "code"))
        // A 5-minute break resets the streak.
        XCTAssertNil(tick(idle: 300))
        XCTAssertNil(coach.workStart)
        XCTAssertNil(tick())
        XCTAssertNotNil(coach.workStart)
    }

    func testBreakHardLimitAndCalls() {
        var coach = BreakCoach()
        var now = date("2026-10-21 09:00:00")
        var reminders = 0
        // Two hours without any pause, the last 10 minutes in a call.
        for step in 0..<(125 * 12) {
            let inCall = step >= 110 * 12 && step < 120 * 12
            if coach.update(now: now, idle: 0, away: false, app: "code", inCall: { inCall }) != nil { reminders += 1 }
            now = now.addingTimeInterval(5)
        }
        // The hard limit (120 min) is reached right after the call.
        XCTAssertEqual(reminders, 1)

        // Sleep (no ticks for 10 minutes) counts as a break.
        _ = coach.update(now: now.addingTimeInterval(600), idle: 0, away: false, app: "code", inCall: { false })
        XCTAssertEqual(coach.workStart, now.addingTimeInterval(600))
    }

    // MARK: - Stability

    func testParsesCrashAndResourceReports() {
        let modified = date("2026-10-21 12:00:00")
        let crash = StabilityParser.parse(
            fileName: "Safari-2026-10-20-134512.ips",
            head: #"{"app_name":"Safari","timestamp":"2026-10-20 13:45:12.00 +0500","app_version":"18.1","bug_type":"309","os_version":"macOS 15.1 (24B83)"}"# + "\n{\n  \"uptime\" : 1000",
            modified: modified)
        XCTAssertEqual(crash?.kind, .crash)
        XCTAssertEqual(crash?.name, "Safari")
        XCTAssertEqual(crash?.at, date("2026-10-20 13:45:12"))
        XCTAssertEqual(crash?.detail, "18.1")

        let diag = StabilityParser.parse(
            fileName: "Google Chrome Helper_2026-10-20-101010_MacBook-Pro.diskwrites_resource.diag",
            head: """
            Date/Time:        2026-10-20 10:10:10.123 +0500
            End time:         2026-10-20 19:10:10.123 +0500
            OS Version:       macOS 15.1 (Build 24B83)
            Command:          Google Chrome Helper
            Event:            disk writes
            Writes:           2147.48 MB of file backed memory dirtied over 32400 seconds (66.28 KB per second average)
            """,
            modified: modified)
        XCTAssertEqual(diag?.kind, .resource)
        XCTAssertEqual(diag?.name, "Google Chrome Helper")
        XCTAssertEqual(diag?.detail, "disk writes: 2147.48 MB of file backed memory dirtied over 32400 seconds")
        XCTAssertEqual(diag!.at.timeIntervalSince(date("2026-10-20 10:10:10")), 0.123, accuracy: 0.5)

        let panic = StabilityParser.parse(fileName: "panic-full-2026-10-19-080000.0002.panic", head: "panic", modified: modified)
        XCTAssertEqual(panic?.kind, .panic)
        XCTAssertEqual(panic?.at, modified)

        let jetsam = StabilityParser.parse(fileName: "JetsamEvent-2026-10-19-080000.ips", head: #"{"bug_type":"298"}"#, modified: modified)
        XCTAssertEqual(jetsam?.kind, .memory)

        let unknown = StabilityParser.parse(fileName: "Something-2026-10-19.ips", head: #"{"bug_type":"999","name":"X"}"#, modified: modified)
        XCTAssertEqual(unknown?.kind, .other)
        XCTAssertEqual(unknown?.detail, "тип отчёта 999")

        XCTAssertTrue(StabilityParser.isReport("a.ips"))
        XCTAssertFalse(StabilityParser.isReport("a.plist"))
        XCTAssertEqual(StabilityParser.shutdownCause(inLog: "kernel: Previous shutdown cause: -128\n"), -128)
        XCTAssertEqual(StabilityParser.shutdownCause(inLog: "Previous shutdown cause: 5"), 5)
        XCTAssertNil(StabilityParser.shutdownCause(inLog: "nothing here"))
    }

    func testStabilityStoreAndReport() throws {
        let days = DayCalendar(calendar: calendar)
        let store = try StabilityStore(path: tempPath())
        let now = date("2026-10-21 12:00:00")
        let events = [
            StabilityEvent(source: "1", at: now.addingTimeInterval(-3600), kind: .crash, name: "Safari", detail: ""),
            StabilityEvent(source: "2", at: now.addingTimeInterval(-2 * 86400), kind: .crash, name: "Safari", detail: ""),
            StabilityEvent(source: "3", at: now.addingTimeInterval(-3 * 86400), kind: .hang, name: "Xcode", detail: ""),
            StabilityEvent(source: "4", at: now.addingTimeInterval(-20 * 86400), kind: .panic, name: "macOS", detail: ""),
            StabilityEvent(source: "5", at: now.addingTimeInterval(-86400), kind: .boot, name: "macOS 15.1", detail: ""),
        ]
        XCTAssertEqual(try store.add(events), 5)
        XCTAssertEqual(try store.add(events), 0)
        XCTAssertEqual(try store.knownSources(), ["1", "2", "3", "4", "5"])

        let stored = try store.events(since: now.addingTimeInterval(-100 * 86400))
        XCTAssertEqual(stored.first?.source, "1")
        let report = StabilityReport.make(stored, now: now, days: days)
        XCTAssertEqual(report.crashes7, 2)
        XCTAssertEqual(report.hangs7, 1)
        XCTAssertEqual(report.panics30, 1)
        XCTAssertEqual(report.apps.first, StabilityReport.AppCount(name: "Safari", crashes: 2, hangs: 0))
        XCTAssertEqual(report.weeks.count, 12)
        XCTAssertEqual(report.weeks.reduce(0) { $0 + $1.crashes + $1.hangs }, 3)
        XCTAssertEqual(report.recent.count, 4)   // boots are not listed
    }
}
