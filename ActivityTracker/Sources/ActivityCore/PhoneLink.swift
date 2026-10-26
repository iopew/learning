import Foundation
import CryptoKit

// MARK: - What the iPhone gets

/// Everything the iPhone app shows about the Mac: ready-made reports, no raw history (no window titles, no
/// addresses — only app names and site domains, as in the Mac's own lists).
public struct PhoneSnapshot: Codable, Equatable {
    public static let currentSchema = 1

    public struct Item: Codable, Equatable, Identifiable {
        public var name: String
        /// Bundle ID of an app or the domain of a site.
        public var key: String
        public var seconds: Double
        public var id: String { key }

        public init(name: String, key: String, seconds: Double) {
            self.name = name
            self.key = key
            self.seconds = seconds
        }
    }

    public struct Bar: Codable, Equatable, Identifiable {
        public var start: Date
        public var seconds: Double
        public var id: Date { start }

        public init(start: Date, seconds: Double) {
            self.start = start
            self.seconds = seconds
        }
    }

    public struct Network: Codable, Equatable, Identifiable {
        public var name: String
        public var kind: String
        public var rx: Double
        public var tx: Double
        public var averageDown: Double?
        public var pingInternet: Double?
        public var loss: Double?
        public var outages: Int
        public var id: String { name + kind }
    }

    public struct Period: Codable, Equatable, Identifiable {
        /// `StatsRange.rawValue`.
        public var range: String
        public var fromDay: Date
        public var toDay: Date
        public var total: Double
        public var activeDays: Int
        public var apps: [Item]
        public var sites: [Item]
        /// Day: one bar per hour starting at the day's first hour; longer periods: per day or per week.
        public var bars: [Bar]
        /// "hour", "day" or "week".
        public var barUnit: String
        /// The day in words (day only).
        public var summary: [String]
        public var networkRx: Double
        public var networkTx: Double
        public var networks: [Network]
        public var id: String { range }

        public var statsRange: StatsRange? { StatsRange(rawValue: range) }
    }

    public struct Battery: Codable, Equatable {
        public var percent: Double?
        public var charging: Bool
        public var onAC: Bool
        public var health: Double?
        public var cycles: Int?
        public var drainPerHour: Double?
        public var timeOnBatteryToday: Double
    }

    public var schema: Int
    public var generatedAt: Date
    public var macName: String
    public var build: Int
    /// The Mac's language when the snapshot was made ("ru" / "en"): texts like the day summary are in it.
    public var language: String
    public var periods: [Period]
    public var battery: Battery?

    public func period(_ range: StatsRange) -> Period? {
        periods.first { $0.range == range.rawValue }
    }
}

extension PhoneSnapshot {
    /// The ranges sent to the phone.
    public static let ranges: [StatsRange] = [.day, .week, .month, .days90, .year, .all]

    /// Builds the snapshot from the Mac's stores. `listLimit`: apps and sites per period.
    public static func make(activity: ActivityStore, network: NetworkStore?, system: SystemStore?, days: DayCalendar,
                            now: Date, macName: String, build: Int, listLimit: Int = 25) throws -> PhoneSnapshot {
        var periods: [Period] = []
        var battery: Battery?
        for range in ranges {
            let report = try activity.report(range: range, anchor: now)
            var bars: [Bar]
            let unit: String
            var summary: [String] = []
            if range == .day {
                unit = "hour"
                var perHour = [Double](repeating: 0, count: 24)
                for slice in report.hourly where slice.hour >= 0 && slice.hour < 24 {
                    perHour[slice.hour] += slice.seconds
                }
                let first = days.startOfDay(report.toDay)
                bars = perHour.enumerated().map { Bar(start: first.addingTimeInterval(Double($0.offset) * 3600), seconds: $0.element) }
                let switches = Switches.stats(try activity.spans(from: report.fromDay, to: report.toDay))
                summary = DaySummary.make(report: report, switches: switches, usualPerHour: nil, days: days)
            } else {
                unit = report.bucketUnit == .week ? "week" : "day"
                bars = report.buckets.map { Bar(start: $0.start, seconds: $0.seconds) }
            }
            let net = try network?.report(range: range, anchor: now)
            periods.append(Period(
                range: range.rawValue, fromDay: report.fromDay, toDay: report.toDay, total: report.total,
                activeDays: report.activeDays,
                apps: report.apps.prefix(listLimit).map { Item(name: $0.appName, key: $0.bundleID, seconds: $0.seconds) },
                sites: report.domains.prefix(listLimit).map { Item(name: $0.domain, key: $0.domain, seconds: $0.seconds) },
                bars: bars, barUnit: unit, summary: summary,
                networkRx: net?.rx ?? 0, networkTx: net?.tx ?? 0,
                networks: (net?.networks ?? []).map {
                    Network(name: $0.name, kind: "\($0.kind)", rx: $0.rx, tx: $0.tx, averageDown: $0.averageDown,
                            pingInternet: $0.pingInternet, loss: $0.loss, outages: $0.outages)
                }))
            if range == .day, let system, let report = try? system.report(range: .day, anchor: now), report.hasBattery,
               let latest = report.latest {
                battery = Battery(percent: latest.batteryPercent, charging: latest.isCharging, onAC: latest.onAC,
                                  health: latest.healthPercent, cycles: latest.cycleCount,
                                  drainPerHour: report.drainPerHour, timeOnBatteryToday: report.timeOnBattery)
            }
        }
        return PhoneSnapshot(schema: currentSchema, generatedAt: now, macName: macName, build: build,
                             language: L.current == .en ? "en" : "ru", periods: periods, battery: battery)
    }
}

// MARK: - Pairing and the wire format

/// The Mac and the iPhone share one random 256-bit key, handed over once as a QR code on the Mac's screen.
///
/// Request (iPhone → Mac, 68 bytes): "ATP1" + 32 random bytes (challenge) + HMAC-SHA256 of both. The Mac answers only
/// a valid request (strangers on the network get nothing, not even an error).
/// Response: 4-byte big-endian length + ChaCha20-Poly1305 box of the compressed snapshot JSON, bound to the
/// challenge (an old answer can't be replayed, a forged one doesn't open). AirDrop file: "ATF1" + challenge + box.
public enum PhoneLink {
    public static let port: UInt16 = 47_219
    public static let serviceType = "_activitytrk._tcp"
    public static let fileExtension = "atsnap"
    public static let requestSize = 4 + 32 + 32
    public static let maximumResponse = 32 * 1024 * 1024
    static let requestMagic = Data("ATP1".utf8)
    static let fileMagic = Data("ATF1".utf8)
    static let pairingPrefix = "atpair1:"

    public enum LinkError: Error, Equatable {
        case badPairing
        case badRequest
        case badResponse
        case tooLarge
    }

    public struct Pairing: Codable, Equatable {
        public var id: String
        public var macName: String
        /// 32 random bytes.
        public var key: Data
        /// The Mac's IPv4 addresses when the QR code was shown (tried first).
        public var hosts: [String]

        public init(id: String = UUID().uuidString, macName: String, key: Data? = nil, hosts: [String] = []) {
            self.id = id
            self.macName = macName
            self.key = key ?? SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            self.hosts = hosts
        }

        var authKey: SymmetricKey { derived("ActivityTracker phone auth v1") }
        var sealKey: SymmetricKey { derived("ActivityTracker phone seal v1") }

        private func derived(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), info: Data(info.utf8), outputByteCount: 32)
        }
    }

    /// The text inside the QR code.
    public static func encode(_ pairing: Pairing) -> String {
        let json = (try? JSONEncoder().encode(pairing)) ?? Data()
        return pairingPrefix + json.base64EncodedString()
    }

    public static func decodePairing(_ text: String) -> Pairing? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(pairingPrefix), trimmed.count < 4096,
              let data = Data(base64Encoded: String(trimmed.dropFirst(pairingPrefix.count))),
              let pairing = try? JSONDecoder().decode(Pairing.self, from: data),
              pairing.key.count == 32, !pairing.id.isEmpty, pairing.macName.count < 200, pairing.hosts.count < 20
        else { return nil }
        return pairing
    }

    public static func newChallenge() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func request(challenge: Data, pairing: Pairing) -> Data {
        let body = requestMagic + challenge
        return body + Data(HMAC<SHA256>.authenticationCode(for: body, using: pairing.authKey))
    }

    /// The challenge of a valid request, or nil.
    public static func challenge(fromRequest data: Data, pairing: Pairing) -> Data? {
        let data = Data(data)
        guard data.count == requestSize, data.prefix(4) == requestMagic else { return nil }
        let body = data.prefix(36)
        let code = data.suffix(32)
        guard HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: body, using: pairing.authKey) else { return nil }
        return Data(body.suffix(32))
    }

    /// The framed response: length + sealed box.
    public static func response(_ snapshot: PhoneSnapshot, challenge: Data, pairing: Pairing) throws -> Data {
        let box = try seal(snapshot, challenge: challenge, pairing: pairing)
        var length = UInt32(box.count).bigEndian
        return Data(bytes: &length, count: 4) + box
    }

    /// Length announced by the first 4 bytes of a response; nil if it is out of bounds.
    public static func responseLength(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        return length > 0 && length <= maximumResponse ? length : nil
    }

    public static func seal(_ snapshot: PhoneSnapshot, challenge: Data, pairing: Pairing) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = try encoder.encode(snapshot)
        let packed = try (json as NSData).compressed(using: .lzfse) as Data
        let box = try ChaChaPoly.seal(packed, using: pairing.sealKey, authenticating: requestMagic + challenge)
        return box.combined
    }

    public static func open(_ box: Data, challenge: Data, pairing: Pairing) throws -> PhoneSnapshot {
        guard box.count <= maximumResponse else { throw LinkError.tooLarge }
        let sealed = try ChaChaPoly.SealedBox(combined: box)
        let packed = try ChaChaPoly.open(sealed, using: pairing.sealKey, authenticating: requestMagic + challenge)
        let json = try (packed as NSData).decompressed(using: .lzfse) as Data
        guard json.count <= maximumResponse * 4 else { throw LinkError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(PhoneSnapshot.self, from: json)
    }

    /// A snapshot as a file for AirDrop (opens only on the paired iPhone).
    public static func file(_ snapshot: PhoneSnapshot, pairing: Pairing) throws -> Data {
        let challenge = newChallenge()
        return fileMagic + challenge + (try seal(snapshot, challenge: challenge, pairing: pairing))
    }

    public static func open(file data: Data, pairing: Pairing) throws -> PhoneSnapshot {
        let data = Data(data)
        guard data.count > 36, data.prefix(4) == fileMagic else { throw LinkError.badResponse }
        return try open(Data(data.dropFirst(36)), challenge: Data(data.dropFirst(4).prefix(32)), pairing: pairing)
    }
}

// MARK: - The iPhone's own battery and traffic

/// A reading taken whenever the iPhone app runs (opened, or woken by iOS for a background refresh).
public struct PhoneMeterSample: Codable, Equatable {
    public var at: Date
    /// 0…100, nil if unknown.
    public var battery: Double?
    public var charging: Bool
    /// Interface byte counters since the iPhone started (32-bit: they wrap at 4 GB).
    public var wifiRx: UInt64
    public var wifiTx: UInt64
    public var cellRx: UInt64
    public var cellTx: UInt64
    /// When the iPhone started; counters restart from zero after a reboot.
    public var bootTime: Date

    public init(at: Date, battery: Double?, charging: Bool, wifiRx: UInt64, wifiTx: UInt64, cellRx: UInt64,
                cellTx: UInt64, bootTime: Date) {
        self.at = at
        self.battery = battery
        self.charging = charging
        self.wifiRx = wifiRx
        self.wifiTx = wifiTx
        self.cellRx = cellRx
        self.cellTx = cellTx
        self.bootTime = bootTime
    }
}

public struct PhoneDayUsage: Equatable, Identifiable {
    public var day: Date
    public var wifi: Double
    public var cellular: Double
    /// Percent of battery used while not charging (drops between readings).
    public var batteryUsed: Double
    public var id: Date { day }
}

public enum PhoneMeter {
    static let counterWrap: Double = 4_294_967_296

    /// Traffic between two readings of one counter: a smaller value means the 32-bit counter wrapped.
    static func delta(_ old: UInt64, _ new: UInt64) -> Double {
        new >= old ? Double(new - old) : Double(new) + (counterWrap - Double(old))
    }

    /// Traffic and battery per day. A reboot between readings loses the traffic of that gap (counters restarted);
    /// the traffic of each gap goes to the day of the later reading.
    public static func daily(_ samples: [PhoneMeterSample], days: DayCalendar) -> [PhoneDayUsage] {
        let sorted = samples.sorted { $0.at < $1.at }
        var byDay: [String: PhoneDayUsage] = [:]
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            let key = days.key(current.at)
            var usage = byDay[key] ?? PhoneDayUsage(day: days.startOfDay(current.at), wifi: 0, cellular: 0, batteryUsed: 0)
            if abs(previous.bootTime.timeIntervalSince(current.bootTime)) < 60 {
                usage.wifi += delta(previous.wifiRx, current.wifiRx) + delta(previous.wifiTx, current.wifiTx)
                usage.cellular += delta(previous.cellRx, current.cellRx) + delta(previous.cellTx, current.cellTx)
            }
            if let old = previous.battery, let new = current.battery, !previous.charging, !current.charging, new < old {
                usage.batteryUsed += old - new
            }
            byDay[key] = usage
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Readings older than `keepDays` are dropped; at most one reading per 5 minutes is kept.
    public static func append(_ sample: PhoneMeterSample, to samples: [PhoneMeterSample], keepDays: Int = 400) -> [PhoneMeterSample] {
        var result = samples.filter { sample.at.timeIntervalSince($0.at) < Double(keepDays) * 86_400 }
        if let last = result.last, sample.at.timeIntervalSince(last.at) < 300, last.bootTime == sample.bootTime {
            result[result.count - 1] = sample
        } else {
            result.append(sample)
        }
        return result
    }
}
