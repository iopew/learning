import XCTest
@testable import ActivityCore

final class TrafficCounterTests: XCTestCase {
    func testWrapResetAndImpossibleJumps() {
        // Normal growth.
        XCTAssertEqual(TrafficCounter.delta(old: 1_000, new: 51_000, elapsed: 5), 50_000)
        // A real 32-bit wrap: 296 + 704 bytes.
        XCTAssertEqual(TrafficCounter.delta(old: UInt32.max - 295, new: 704, elapsed: 5), 1_000)
        // A restarted counter (interface recreated): only what it counted since, never "4 GB in 5 s".
        XCTAssertEqual(TrafficCounter.delta(old: 50_000_000, new: 2_000, elapsed: 5), 2_000)
        // A jump faster than the cap (2.5 Gbit/s) is an artefact.
        XCTAssertEqual(TrafficCounter.delta(old: 0, new: 4_000_000_000, elapsed: 5), 0)
        // After a long gap (sleep) more bytes are possible.
        XCTAssertEqual(TrafficCounter.delta(old: 0, new: 4_000_000_000, elapsed: 3600), 4_000_000_000)
    }

    func testSpikesFromOldBuildsAreRemoved() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let office = NetworkInfo(key: "wifi:Office", name: "Office", kind: .wifi)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        do {
            let store = try NetworkStore(path: path)
            var normal = NetworkSample(at: start, interval: 60, network: office)
            normal.rx = 30_000_000
            normal.peakRx = 2_000_000
            normal.busyRxBytes = 30_000_000
            normal.busyRxSeconds = 20
            try store.record(normal)
            // The counter-reset minute recorded by an old build: 4.29 GB "in 5 s" on top of 10 MB of real traffic.
            var spike = NetworkSample(at: start.addingTimeInterval(60), interval: 60, network: office)
            spike.rx = 4_294_000_000 + 10_000_000
            spike.tx = 4_294_000_000
            spike.peakRx = 4_294_000_000 / 5
            spike.peakTx = 4_294_000_000 / 5
            spike.busyRxBytes = 4_294_000_000 + 10_000_000
            spike.busyRxSeconds = 15
            spike.busyTxBytes = 4_294_000_000
            spike.busyTxSeconds = 5
            try store.record(spike)
        }
        // Opening the store again cleans the spike; a second opening changes nothing more.
        _ = try NetworkStore(path: path)
        let store = try NetworkStore(path: path)
        let report = try store.report(range: .day, anchor: start)
        XCTAssertEqual(report.rx, 40_000_000, accuracy: 1)
        XCTAssertEqual(report.tx, 0, accuracy: 1)
        let usage = try XCTUnwrap(report.networks.first)
        XCTAssertLessThan(usage.peakDown, TrafficCounter.maximumRate)
    }
}
