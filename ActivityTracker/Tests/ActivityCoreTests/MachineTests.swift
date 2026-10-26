import XCTest
@testable import ActivityCore

final class MachineTests: XCTestCase {
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

    func testBatteryCostPerActivity() {
        let start = date("2026-10-21 10:00:00")
        // 60 minutes on battery: the first 30 on YouTube (1% a minute... 0.5%), the next 30 in Xcode (0.2%).
        var minutes: [BatteryMinute] = []
        for index in 0...60 {
            let percent = index <= 30 ? 100 - Double(index) * 0.5 : 85 - Double(index - 30) * 0.2
            minutes.append(BatteryMinute(at: start.addingTimeInterval(Double(index) * 60), percent: percent,
                                         watts: index <= 30 ? -12 : -5, onAC: false))
        }
        let events = [
            ActivityEvent(id: 1, start: start, end: start.addingTimeInterval(1800), bundleID: "safari", appName: "Safari",
                          title: "", url: "", domain: "youtube.com"),
            ActivityEvent(id: 2, start: start.addingTimeInterval(1800), end: start.addingTimeInterval(3600),
                          bundleID: "xcode", appName: "Xcode", title: "", url: "", domain: ""),
        ]
        let costs = BatteryCost.make(minutes: minutes, events: events)
        XCTAssertEqual(costs.map(\.name), ["youtube.com", "Xcode"])
        XCTAssertEqual(costs[0].percentPerHour!, 30, accuracy: 0.01)
        XCTAssertEqual(costs[0].averageWatts!, 12, accuracy: 0.01)
        XCTAssertEqual(costs[1].percentPerHour!, 12, accuracy: 0.01)
        XCTAssertEqual(costs[0].seconds, 1800)

        // Plugged in: nothing counts.
        let plugged = minutes.map { BatteryMinute(at: $0.at, percent: $0.percent, watts: 10, onAC: true) }
        XCTAssertTrue(BatteryCost.make(minutes: plugged, events: events).isEmpty)
    }

    func testChargeSessions() throws {
        let days = DayCalendar(calendar: calendar)
        let store = try SystemStore(path: tempPath(), days: days)
        let start = date("2026-10-21 10:00:00")
        func sample(_ minute: Int, percent: Double, onAC: Bool, watts: Double) -> SystemSample {
            var sample = SystemSample(at: start.addingTimeInterval(Double(minute) * 60), batteryPercent: percent, onAC: onAC,
                                      isCharging: onAC, batteryWatts: watts)
            sample.adapterWatts = onAC ? 96 : nil
            sample.adapterName = onAC ? "96W USB-C" : nil
            return sample
        }
        try store.record(sample(0, percent: 40, onAC: false, watts: -8), interval: 60, energy: [])
        for minute in 1...60 {
            try store.record(sample(minute, percent: 40 + Double(minute) * 0.5, onAC: true, watts: 30), interval: 60, energy: [])
        }
        try store.record(sample(61, percent: 70, onAC: false, watts: -8), interval: 60, energy: [])

        let sessions = try store.chargeSessions(from: date("2026-10-21 00:00:00"), to: date("2026-10-21 00:00:00"))
        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.startPercent, 40.5)
        XCTAssertEqual(session.endPercent, 70)
        XCTAssertEqual(session.adapterWatts, 96)
        XCTAssertEqual(session.adapterName, "96W USB-C")
        XCTAssertEqual(session.averageChargeWatts!, 30, accuracy: 0.01)
        XCTAssertEqual(session.percentPerHour!, 29.5, accuracy: 0.01)
    }

    func testForecasts() {
        let now = date("2026-10-21 12:00:00")
        var daily: [(day: Date, health: Double?, cycles: Int?)] = []
        for index in 0..<60 {
            daily.append((now.addingTimeInterval(Double(index - 59) * 86400), 95 - Double(index) * 0.05, 100 + index / 2))
        }
        let forecast = BatteryForecast.make(daily: daily, now: now)
        XCTAssertEqual(forecast.cycles, 129)
        XCTAssertEqual(forecast.cyclesPerMonth!, 14.75, accuracy: 0.5)
        XCTAssertNotNil(forecast.cyclesLimitDate)
        let health = try! XCTUnwrap(forecast.health80Date)
        // 92.05% falling 0.05 a day → ~241 days.
        XCTAssertEqual(health.timeIntervalSince(now) / 86400, 241, accuracy: 2)
        XCTAssertNil(BatteryForecast.make(daily: Array(daily.suffix(5)), now: now).cyclesLimitDate)

        let disk = DiskForecast.make(daily: (0..<10).map { (now.addingTimeInterval(Double($0) * 86400), 100e9 - Double($0) * 2e9) },
                                     total: 500e9)
        XCTAssertEqual(disk.perDay!, -2e9, accuracy: 1e6)
        XCTAssertEqual(disk.daysUntilFull!, 41, accuracy: 0.5)
        XCTAssertNil(DiskForecast.make(daily: [(now, 1e9)], total: 2e9).perDay)
    }

    func testSleepNightsAndStats() throws {
        let events = [
            PowerEvent(at: date("2026-10-20 23:00:00"), kind: .sleep, percent: 80, darkWakeCount: 100),
            PowerEvent(at: date("2026-10-21 07:30:00"), kind: .wake, percent: 77, darkWakeCount: 112),
            PowerEvent(at: date("2026-10-21 12:00:00"), kind: .sleep, percent: 60, darkWakeCount: 112),
            PowerEvent(at: date("2026-10-21 12:05:00"), kind: .wake, percent: 60, darkWakeCount: 112),   // too short
        ]
        let nights = SleepNights.make(events)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].duration, 8.5 * 3600)
        XCTAssertEqual(nights[0].drop, 3)
        XCTAssertEqual(nights[0].darkWakes, 12)
        XCTAssertEqual(SleepNights.darkWakeCount(inStats: "Sleep Count:59\nDark Wake Count:234\nUser Wake Count:59\n"), 234)

        let store = try MachineStore(path: tempPath(), days: DayCalendar(calendar: calendar))
        for event in events { try store.record(event) }
        let stored = try store.nights(from: date("2026-10-21 00:00:00"), to: date("2026-10-21 00:00:00"))
        XCTAssertEqual(stored.map(\.darkWakes), [12])

        try store.addBlocker(process: "Claude", reason: "Playing audio", seconds: 60, at: date("2026-10-21 03:10:00"))
        try store.addBlocker(process: "Claude", reason: "Playing audio", seconds: 60, at: date("2026-10-21 03:20:00"))
        let blockers = try store.blockers(from: date("2026-10-21 00:00:00"), to: date("2026-10-21 00:00:00"))
        XCTAssertEqual(blockers, [SleepBlocker(process: "Claude", reason: "Playing audio", seconds: 120)])
    }

    func testStartupFoldersAndWrites() throws {
        let store = try MachineStore(path: tempPath(), days: DayCalendar(calendar: calendar))
        let first = date("2026-10-01 10:00:00")
        try store.updateStartup(["/a.plist": ("com.a", "/bin/a"), "/b.plist": ("com.b", "/bin/b")], at: first)
        let later = date("2026-10-20 10:00:00")
        try store.updateStartup(["/a.plist": ("com.a", "/bin/a"), "/c.plist": ("com.c", "/bin/c")], at: later)
        let items = try store.startupItems(now: date("2026-10-21 10:00:00"))
        XCTAssertEqual(items.filter { !$0.removed }.map(\.label).sorted(), ["com.a", "com.c"])
        XCTAssertEqual(items.first { $0.label == "com.c" }?.isNew, true)
        XCTAssertEqual(items.first { $0.label == "com.a" }?.isNew, false)   // there from the first scan
        XCTAssertEqual(items.first { $0.label == "com.b" }?.removed, true)

        try store.recordFolders(["/x": 1e9], at: first)
        try store.recordFolders(["/x": 3e9], at: date("2026-10-08 10:00:00"))
        let folders = try store.folders()
        XCTAssertEqual(folders, [FolderGrowth(path: "/x", bytes: 3e9, weekChange: 2e9)])

        try store.addWrites(5e9, at: date("2026-10-21 10:00:00"))
        try store.addWrites(1e9, at: date("2026-10-21 18:00:00"))
        XCTAssertEqual(try store.writes(from: date("2026-10-21 00:00:00"), to: date("2026-10-21 00:00:00")).map(\.bytes), [6e9])
    }
}
