import XCTest
@testable import ActivityCore

final class SystemStoreTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        calendar.firstWeekday = 2
        return calendar
    }()
    private var days: DayCalendar { DayCalendar(calendar: calendar) }
    private var path: String!
    private var store: SystemStore!

    override func setUpWithError() throws {
        L.current = .ru
        path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path
        store = try SystemStore(path: path, days: days)
    }

    override func tearDownWithError() throws {
        store = nil
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    /// One sample per minute for `minutes`, battery going from `from` by `step` per minute.
    private func run(from start: Date, minutes: Int, percent from: Double, step: Double, onAC: Bool,
                     watts: Double? = nil, thermal: Int = 0, energy: [AppEnergy] = []) throws {
        for minute in 0..<minutes {
            let sample = SystemSample(
                at: start.addingTimeInterval(TimeInterval(minute * 60)),
                batteryPercent: from + step * Double(minute), onAC: onAC, isCharging: onAC && step > 0,
                batteryWatts: watts, batteryTemperature: 31, cycleCount: 120, healthPercent: 91,
                cpuLoad: 0.25, memoryUsed: 8e9, memoryTotal: 16e9, swapUsed: 1e9, diskFree: 200e9, diskTotal: 500e9,
                thermalState: thermal)
            try store.record(sample, interval: 60, energy: energy)
        }
    }

    func testDrainChargesAndEnergy() throws {
        let chrome = AppEnergy(bundleID: "com.google.Chrome", appName: "Chrome", joules: 30, cpuSeconds: 6)
        let xcode = AppEnergy(bundleID: "com.apple.dt.Xcode", appName: "Xcode", joules: 10, cpuSeconds: 2)
        // 2 hours unplugged: 80 % → 60.5 % (0.1625 %/min ≈ 9.75 %/h), then plugged in for 30 minutes.
        try run(from: date("2026-10-22 09:00:00"), minutes: 120, percent: 80, step: -0.1625, onAC: false,
                watts: -7.5, energy: [chrome, xcode])
        try run(from: date("2026-10-22 11:00:00"), minutes: 30, percent: 61, step: 0.5, onAC: true, watts: 30,
                energy: [xcode])

        let report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))

        XCTAssertTrue(report.hasData)
        XCTAssertTrue(report.hasBattery)
        XCTAssertEqual(report.chargeCount, 1)
        XCTAssertEqual(report.timeOnBattery, 120 * 60)
        XCTAssertEqual(try XCTUnwrap(report.drainPerHour), 9.75, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.estimatedFullCharge) / 3600, 100 / 9.75, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.averageDischargeWatts), 7.5, accuracy: 0.001)
        XCTAssertEqual(report.energyOnBattery.map(\.appName), ["Chrome", "Xcode"])
        XCTAssertEqual(report.energyOnBattery[0].joules, 30 * 120, accuracy: 0.001)
        XCTAssertEqual(report.energyAll.first(where: { $0.appName == "Xcode" })?.joules ?? 0, 10 * 150, accuracy: 0.001)
        XCTAssertEqual(report.batteryPoints.count, 150)
        XCTAssertEqual(report.latest?.onAC, true)
        XCTAssertEqual(report.latest?.cycleCount, 120)
        XCTAssertEqual(report.cyclesAdded, 0)
        XCTAssertEqual(try XCTUnwrap(report.cpuAverage), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(report.memoryPeak), 0.5, accuracy: 0.0001)
    }

    func testSleepGapIsNotCountedAsDrain() throws {
        try run(from: date("2026-10-22 09:00:00"), minutes: 30, percent: 90, step: -0.2, onAC: false)
        // Lid closed for 8 hours, lost 4 % while asleep, then 30 more minutes of use.
        try run(from: date("2026-10-22 17:30:00"), minutes: 30, percent: 80, step: -0.2, onAC: false)

        let report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertEqual(try XCTUnwrap(report.drainPerHour), 12, accuracy: 0.01)   // 0.2 %/min, the sleep gap ignored
        XCTAssertEqual(report.chargeCount, 0)
    }

    func testFullOnACAndHotTime() throws {
        try run(from: date("2026-10-22 08:00:00"), minutes: 90, percent: 100, step: 0, onAC: true, thermal: 2)
        let report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertEqual(report.timeFullOnAC, 90 * 60)
        XCTAssertEqual(report.hotTime, 90 * 60)
        XCTAssertNil(report.drainPerHour)
    }

    func testLongRangesAreAggregatedPerDay() throws {
        try run(from: date("2026-10-20 10:00:00"), minutes: 60, percent: 70, step: -0.1, onAC: false)
        try run(from: date("2026-10-22 10:00:00"), minutes: 60, percent: 70, step: -0.1, onAC: false)
        let report = try store.report(range: .month, anchor: date("2026-10-22 20:00:00"))
        XCTAssertEqual(report.batteryPoints.count, 2)
        XCTAssertEqual(report.loadPoints.count, 2)
        XCTAssertEqual(report.batteryPoints[0].maxPercent, 70, accuracy: 0.0001)
    }

    func testDesktopWithoutBattery() throws {
        let sample = SystemSample(at: date("2026-10-22 10:00:00"), cpuLoad: 0.5, memoryUsed: 4e9, memoryTotal: 8e9,
                                  diskFree: 100e9, diskTotal: 250e9)
        try store.record(sample, interval: 60, energy: [])
        let report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertTrue(report.hasData)
        XCTAssertFalse(report.hasBattery)
        XCTAssertTrue(report.batteryPoints.isEmpty)
        XCTAssertNil(report.latest?.batteryPercent)
    }

    func testEmptyReport() throws {
        let report = try store.report(range: .week, anchor: date("2026-10-22 20:00:00"))
        XCTAssertFalse(report.hasData)
        XCTAssertNil(report.latest)
    }

    func testEnergyIsAggregatedPerHourAndErasable() throws {
        let chrome = AppEnergy(bundleID: "com.google.Chrome", appName: "Chrome", joules: 2, cpuSeconds: 1)
        try run(from: date("2026-10-22 09:00:00"), minutes: 90, percent: 80, step: -0.1, onAC: false, energy: [chrome])
        var report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertEqual(report.energyOnBattery.first?.joules ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(report.energyOnBattery.first?.cpuSeconds ?? 0, 90, accuracy: 0.001)

        try store.erase(.app("com.google.Chrome"))
        report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertTrue(report.energyAll.isEmpty)
        XCTAssertTrue(report.hasData)

        try store.erase(.since(date("2026-10-22 10:00:00")))
        report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertEqual(report.batteryPoints.count, 60)
        try store.erase(.all)
        XCTAssertFalse(try store.report(range: .day, anchor: date("2026-10-22 20:00:00")).hasData)
    }

    func testPlugStateSurvivesReopen() throws {
        try run(from: date("2026-10-22 09:00:00"), minutes: 5, percent: 50, step: -0.1, onAC: false)
        store = try SystemStore(path: path, days: days)
        try run(from: date("2026-10-22 09:05:00"), minutes: 5, percent: 50, step: 0.5, onAC: true)
        let report = try store.report(range: .day, anchor: date("2026-10-22 20:00:00"))
        XCTAssertEqual(report.chargeCount, 1)
    }
}
