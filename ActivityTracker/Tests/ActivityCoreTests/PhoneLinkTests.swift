import XCTest
@testable import ActivityCore

final class PhoneLinkTests: XCTestCase {
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

    private func snapshot() throws -> PhoneSnapshot {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path
        paths.append(path)
        let store = try ActivityStore(path: path)
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        try store.record(Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "Secret title",
                                url: "https://go.dev/secret/path"), at: now.addingTimeInterval(-120), interval: 5)
        try store.endStreak(at: now.addingTimeInterval(-60))
        return try PhoneSnapshot.make(activity: store, network: try NetworkStore(path: path), system: try SystemStore(path: path),
                                      days: DayCalendar(), now: now, macName: "Test Mac", build: 24)
    }

    func testSnapshotHasReportsButNoTitlesOrAddresses() throws {
        let snapshot = try snapshot()
        XCTAssertEqual(snapshot.periods.map(\.range), PhoneSnapshot.ranges.map(\.rawValue))
        let day = try XCTUnwrap(snapshot.period(.day))
        XCTAssertEqual(day.total, 60, accuracy: 1)
        XCTAssertEqual(day.apps.first?.name, "Safari")
        XCTAssertEqual(day.sites.first?.key, "go.dev")
        XCTAssertEqual(day.bars.count, 24)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("Secret"))
        XCTAssertFalse(json.contains("/secret/path"))
    }

    func testRoundTripAndTampering() throws {
        let pairing = PhoneLink.Pairing(macName: "Test Mac", hosts: ["192.168.1.5"])
        let snapshot = try snapshot()
        let challenge = PhoneLink.newChallenge()

        let request = PhoneLink.request(challenge: challenge, pairing: pairing)
        XCTAssertEqual(request.count, PhoneLink.requestSize)
        XCTAssertEqual(PhoneLink.challenge(fromRequest: request, pairing: pairing), challenge)

        let response = try PhoneLink.response(snapshot, challenge: challenge, pairing: pairing)
        let length = try XCTUnwrap(PhoneLink.responseLength(response.prefix(4)))
        XCTAssertEqual(length, response.count - 4)
        let opened = try PhoneLink.open(Data(response.dropFirst(4)), challenge: challenge, pairing: pairing)
        XCTAssertEqual(opened.macName, "Test Mac")
        XCTAssertEqual(opened.periods.count, snapshot.periods.count)

        // Another key, another challenge (a replayed answer), a flipped byte: nothing opens.
        let stranger = PhoneLink.Pairing(macName: "Test Mac")
        XCTAssertNil(PhoneLink.challenge(fromRequest: request, pairing: stranger))
        XCTAssertThrowsError(try PhoneLink.open(Data(response.dropFirst(4)), challenge: challenge, pairing: stranger))
        XCTAssertThrowsError(try PhoneLink.open(Data(response.dropFirst(4)), challenge: PhoneLink.newChallenge(), pairing: pairing))
        var flipped = Data(response.dropFirst(4))
        flipped[flipped.count / 2] ^= 0x01
        XCTAssertThrowsError(try PhoneLink.open(flipped, challenge: challenge, pairing: pairing))

        var badRequest = request
        badRequest[10] ^= 0x01
        XCTAssertNil(PhoneLink.challenge(fromRequest: badRequest, pairing: pairing))
        XCTAssertNil(PhoneLink.challenge(fromRequest: Data("GET / HTTP/1.1\r\n".utf8), pairing: pairing))
        XCTAssertNil(PhoneLink.responseLength(Data([0xFF, 0xFF, 0xFF, 0xFF])))
        XCTAssertNil(PhoneLink.responseLength(Data([0, 0, 0, 0])))
    }

    func testAirDropFile() throws {
        let pairing = PhoneLink.Pairing(macName: "Test Mac")
        let file = try PhoneLink.file(try snapshot(), pairing: pairing)
        XCTAssertEqual(try PhoneLink.open(file: file, pairing: pairing).build, 24)
        XCTAssertThrowsError(try PhoneLink.open(file: file, pairing: PhoneLink.Pairing(macName: "Other")))
        XCTAssertThrowsError(try PhoneLink.open(file: Data("junk".utf8), pairing: pairing))
    }

    func testPairingCode() {
        let pairing = PhoneLink.Pairing(macName: "MacBook", hosts: ["192.168.1.5", "100.101.102.103"])
        let code = PhoneLink.encode(pairing)
        XCTAssertEqual(PhoneLink.decodePairing(code), pairing)
        XCTAssertNil(PhoneLink.decodePairing("https://example.com"))
        XCTAssertNil(PhoneLink.decodePairing("atpair1:!!!"))
        var short = pairing
        short.key = Data(repeating: 1, count: 8)
        XCTAssertNil(PhoneLink.decodePairing(PhoneLink.encode(short)))
    }

    func testMeterDailyTrafficWithWrapAndReboot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let days = DayCalendar(calendar: calendar)
        let boot = Date(timeIntervalSince1970: 1_790_000_000)
        let start = boot.addingTimeInterval(3600)
        func sample(_ hours: Double, wifi: UInt64, cell: UInt64, battery: Double, boot: Date = boot) -> PhoneMeterSample {
            PhoneMeterSample(at: start.addingTimeInterval(hours * 3600), battery: battery, charging: false,
                             wifiRx: wifi, wifiTx: 0, cellRx: cell, cellTx: 0, bootTime: boot)
        }
        let samples = [
            sample(0, wifi: 1_000, cell: 0, battery: 90),
            sample(1, wifi: 4_294_967_000, cell: 500, battery: 85),
            sample(2, wifi: 704, cell: 1_500, battery: 80),   // wrapped: 296 + 704 = 1000 bytes
            // Rebooted: counters restart, the gap is not counted.
            sample(3, wifi: 50, cell: 10, battery: 78, boot: boot.addingTimeInterval(3 * 3600)),
        ]
        let daily = PhoneMeter.daily(samples, days: days)
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(daily[0].wifi, (4_294_967_000 - 1_000) + 1_000)
        XCTAssertEqual(daily[0].cellular, 1_500)
        XCTAssertEqual(daily[0].batteryUsed, 12)
    }

    func testMeterAppendKeepsOnePerFiveMinutes() {
        let boot = Date(timeIntervalSince1970: 1_790_000_000)
        func sample(_ minutes: Double) -> PhoneMeterSample {
            PhoneMeterSample(at: boot.addingTimeInterval(minutes * 60), battery: 50, charging: false,
                             wifiRx: 0, wifiTx: 0, cellRx: 0, cellTx: 0, bootTime: boot)
        }
        var samples: [PhoneMeterSample] = []
        for minute in [0.0, 1, 2, 10, 11] { samples = PhoneMeter.append(sample(minute), to: samples) }
        XCTAssertEqual(samples.map { $0.at.timeIntervalSince(boot) / 60 }, [2, 11])
    }
}
