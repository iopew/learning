import XCTest
@testable import ActivityCore

final class RecommendationsTests: XCTestCase {
    override func setUp() {
        L.current = .ru
    }

    private func report(total: TimeInterval = 0, apps: [AppUsage] = [], domains: [DomainUsage] = [],
                        minutes: [MinuteCell?] = Array(repeating: nil, count: 1440)) -> Report {
        Report(range: .day, fromDay: Date(), toDay: Date(), total: total, activeDays: total > 0 ? 1 : 0, apps: apps,
               domains: domains, buckets: [], bucketUnit: .day, hourly: [], minutes: minutes, sessions: [])
    }

    private func input(_ report: Report, baseline: UsageBaseline = UsageBaseline(), system: SystemReport? = nil,
                       minute: Int = 12 * 60) -> RecommendationInput {
        RecommendationInput(today: report, baseline: baseline, system: system, now: Date(), minuteOfDay: minute)
    }

    private func ids(_ tips: [Recommendation]) -> [String] { tips.map(\.id) }

    func testYouTubeAboveUsual() {
        let today = report(total: 4 * 3600, domains: [DomainUsage(domain: "youtube.com", seconds: 2 * 3600)])
        let baseline = UsageBaseline(activeDays: 10, totalPerDay: 5 * 3600, domainsPerDay: ["youtube.com": 3600])
        let tips = Recommendations.make(input(today, baseline: baseline))
        let tip = tips.first { $0.id == "site-above-usual-youtube.com" }
        XCTAssertEqual(tip?.kind, .warning)
        XCTAssertEqual(tip?.title, "youtube.com: 2ч сегодня")
        XCTAssertTrue(tip?.detail.contains("на 100% больше") == true)
    }

    func testEntertainmentWithoutHistory() {
        let today = report(total: 2 * 3600, domains: [DomainUsage(domain: "youtube.com", seconds: 80 * 60)])
        let tips = Recommendations.make(input(today))
        XCTAssertTrue(ids(tips).contains("site-a-lot-youtube.com"))
    }

    func testUsualAmountGivesNoSiteTip() {
        let today = report(total: 3 * 3600, domains: [DomainUsage(domain: "youtube.com", seconds: 3600)])
        let baseline = UsageBaseline(activeDays: 10, totalPerDay: 5 * 3600, domainsPerDay: ["youtube.com": 3600])
        XCTAssertFalse(ids(Recommendations.make(input(today, baseline: baseline))).contains { $0.hasPrefix("site-") })
    }

    func testLongStreakAndBreaks() {
        var minutes = [MinuteCell?](repeating: nil, count: 1440)
        let cell = MinuteCell(bundleID: "a", appName: "A", seconds: 60)
        for minute in (10 * 60)..<(12 * 60) { minutes[minute] = cell }          // 10:00–12:00
        minutes[11 * 60 + 30] = nil                                             // a 1-minute gap is not a break
        XCTAssertEqual(Recommendations.currentStreak(minutes: minutes, endingAt: 12 * 60 - 1), 120 * 60)
        let tips = Recommendations.make(input(report(total: 7200, minutes: minutes), minute: 12 * 60 - 1))
        XCTAssertTrue(ids(tips).contains("long-streak"))

        for minute in (11 * 60)..<(11 * 60 + 10) { minutes[minute] = nil }      // a real 10-minute break
        XCTAssertEqual(Recommendations.currentStreak(minutes: minutes, endingAt: 12 * 60 - 1), 50 * 60)
        // Right now on a break (12:00–12:04 empty): no streak.
        XCTAssertEqual(Recommendations.currentStreak(minutes: minutes, endingAt: 12 * 60 + 4), 0)
    }

    func testLateNight() {
        var minutes = [MinuteCell?](repeating: nil, count: 1440)
        for minute in 60..<90 { minutes[minute] = MinuteCell(bundleID: "a", appName: "A", seconds: 60) }
        XCTAssertEqual(Recommendations.lateNight(minutes: minutes), 30 * 60)
        XCTAssertTrue(ids(Recommendations.make(input(report(total: 1800, minutes: minutes)))).contains("late-night"))
    }

    func testCodingIsPraised() {
        let xcode = AppUsage(bundleID: "com.apple.dt.Xcode", appName: "Xcode", seconds: 2 * 3600, topTitles: [])
        let tips = Recommendations.make(input(report(total: 2 * 3600, apps: [xcode])))
        XCTAssertEqual(tips.first { $0.id == "coding-good" }?.kind, .positive)
    }

    func testFunOverCode() {
        let today = report(total: 3 * 3600, domains: [DomainUsage(domain: "youtube.com", seconds: 50 * 60),
                                                      DomainUsage(domain: "reddit.com", seconds: 20 * 60)])
        XCTAssertTrue(ids(Recommendations.make(input(today))).contains("fun-over-code"))
    }

    func testSystemTips() {
        let latest = SystemSample(at: Date(), batteryPercent: 50, onAC: false, healthPercent: 76,
                                  diskFree: 8e9, diskTotal: 500e9)
        let system = SystemReport(
            range: .day, fromDay: Date(), toDay: Date(), hasData: true, hasBattery: true, latest: latest,
            batteryPoints: [], loadPoints: [], chargeCount: 1, cyclesAdded: 0, drainPerHour: 25,
            averageDischargeWatts: 12, timeOnBattery: 3600, timeFullOnAC: 7 * 3600, estimatedFullCharge: 4 * 3600,
            energyOnBattery: [EnergyUsage(bundleID: "c", appName: "Chrome", joules: 700, cpuSeconds: 10),
                              EnergyUsage(bundleID: "x", appName: "Xcode", joules: 300, cpuSeconds: 5)],
            energyAll: [], cpuAverage: 0.2, cpuPeak: 0.9, memoryPeak: 0.8, swapPeak: 5e9, hotTime: 20 * 60,
            maxBatteryTemperature: 36)
        let tips = Recommendations.make(input(report(), system: system))
        XCTAssertEqual(Set(ids(tips)), ["battery-health", "energy-top-c", "fast-drain", "full-on-ac", "hot", "disk", "memory"])
        XCTAssertEqual(tips.first { $0.id == "energy-top-c" }?.title, "Chrome съел 70% энергии от батареи")
    }

    func testEnglish() {
        L.current = .en
        defer { L.current = .ru }
        let today = report(total: 2 * 3600, domains: [DomainUsage(domain: "youtube.com", seconds: 80 * 60)])
        let tip = Recommendations.make(input(today)).first { $0.id == "site-a-lot-youtube.com" }
        XCTAssertEqual(tip?.title, "youtube.com: already 1h 20m today")
    }

    func testQuietDayHasNoTips() {
        XCTAssertTrue(Recommendations.make(input(report(total: 3600))).isEmpty)
    }

    func testLanguageResolution() {
        XCTAssertEqual(L.resolve(.system, preferred: ["ru-UZ"]), .ru)
        XCTAssertEqual(L.resolve(.system, preferred: ["en-US", "ru"]), .en)
        XCTAssertEqual(L.resolve(.system, preferred: []), .en)
        XCTAssertEqual(L.resolve(.ru, preferred: ["en"]), .ru)
    }
}
