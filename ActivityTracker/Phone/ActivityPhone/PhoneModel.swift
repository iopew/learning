import Foundation
import Security
import UIKit
import ActivityCore

/// The app's state: the pairing (key in the Keychain), the last snapshot from the Mac, the iPhone's own readings.
@MainActor
final class PhoneModel: ObservableObject {
    static let shared = PhoneModel()

    @Published private(set) var pairing: PhoneLink.Pairing?
    @Published private(set) var snapshot: PhoneSnapshot?
    @Published private(set) var syncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var meter: [PhoneMeterSample] = []

    let days: DayCalendar
    private let defaults = UserDefaults.standard

    private init() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        days = DayCalendar(calendar: calendar)
        pairing = Keychain.load()
        snapshot = Storage.load(PhoneSnapshot.self, from: "snapshot.json")
        meter = Storage.load([PhoneMeterSample].self, from: "meter.json") ?? []
        lastSync = defaults.object(forKey: "lastSync") as? Date
    }

    var lastHost: String? { defaults.string(forKey: "lastHost") }

    /// Typed in Settings: a Tailscale address (100.x.y.z), a MagicDNS name or any address of the Mac.
    @Published var manualHost: String = UserDefaults.standard.string(forKey: "manualHost") ?? "" {
        didSet { defaults.set(manualHost.trimmingCharacters(in: .whitespaces), forKey: "manualHost") }
    }

    // MARK: - Pairing

    /// From the scanned QR code. Returns false if it isn't an ActivityTracker code.
    func pair(code: String) -> Bool {
        guard let pairing = PhoneLink.decodePairing(code) else { return false }
        Keychain.save(pairing)
        self.pairing = pairing
        defaults.removeObject(forKey: "lastHost")
        lastError = nil
        Task { await sync() }
        return true
    }

    func unpair() {
        Keychain.delete()
        pairing = nil
        snapshot = nil
        Storage.delete("snapshot.json")
        defaults.removeObject(forKey: "lastHost")
        defaults.removeObject(forKey: "lastSync")
        lastSync = nil
    }

    // MARK: - Getting the Mac's statistics

    func sync() async {
        recordMeter()
        guard let pairing, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let manual = manualHost.trimmingCharacters(in: .whitespaces)
            let (snapshot, host) = try await MacClient.fetch(pairing: pairing, lastHost: lastHost,
                                                             manualHost: manual.isEmpty ? nil : manual)
            accept(snapshot)
            if let host { defaults.set(host, forKey: "lastHost") }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A snapshot sent from the Mac through AirDrop.
    func importFile(_ url: URL) {
        guard let pairing else {
            lastError = L.tr("Сначала свяжи iPhone с Mac", "Pair the iPhone with the Mac first")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= PhoneLink.maximumResponse else {
                throw PhoneLink.LinkError.tooLarge
            }
            accept(try PhoneLink.open(file: Data(contentsOf: url), pairing: pairing))
            lastError = nil
        } catch {
            lastError = L.tr("Файл не открылся этим ключом: он от другого Mac или повреждён", "The file didn't open with this key: it is from another Mac or damaged")
        }
        try? FileManager.default.removeItem(at: url)   // the copy iOS put into the Inbox
    }

    private func accept(_ snapshot: PhoneSnapshot) {
        // An older snapshot (an old AirDrop file) never replaces a newer one.
        if let current = self.snapshot, current.generatedAt > snapshot.generatedAt { return }
        self.snapshot = snapshot
        Storage.save(snapshot, to: "snapshot.json")
        lastSync = Date()
        defaults.set(lastSync, forKey: "lastSync")
    }

    // MARK: - The iPhone's own readings

    func recordMeter() {
        meter = PhoneMeter.append(MeterReader.read(), to: meter)
        Storage.save(meter, to: "meter.json")
    }
}

/// Small JSON files in Application Support, readable after the first unlock (background refresh needs them).
enum Storage {
    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
}

/// The pairing key lives in the Keychain, on this iPhone only (not in backups to other devices, not in iCloud).
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ActivityTracker pairing",
        kSecAttrAccount as String: "mac",
    ]

    static func load() -> PhoneLink.Pairing? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PhoneLink.Pairing.self, from: data)
    }

    static func save(_ pairing: PhoneLink.Pairing) {
        delete()
        guard let data = try? JSONEncoder().encode(pairing) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Battery and the interface byte counters right now.
@MainActor
enum MeterReader {
    static func read() -> PhoneMeterSample {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let charging = device.batteryState == .charging || device.batteryState == .full
        var wifiRx: UInt64 = 0, wifiTx: UInt64 = 0, cellRx: UInt64 = 0, cellTx: UInt64 = 0
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let entry = pointer.pointee
                guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                      let raw = entry.ifa_data else { continue }
                let name = String(cString: entry.ifa_name)
                let data = raw.load(as: if_data.self)
                if name == "en0" {
                    wifiRx += UInt64(data.ifi_ibytes)
                    wifiTx += UInt64(data.ifi_obytes)
                } else if name.hasPrefix("pdp_ip") {
                    cellRx += UInt64(data.ifi_ibytes)
                    cellTx += UInt64(data.ifi_obytes)
                }
            }
            freeifaddrs(list)
        }
        return PhoneMeterSample(at: Date(), battery: level >= 0 ? Double(level) * 100 : nil, charging: charging,
                                wifiRx: wifiRx, wifiTx: wifiTx, cellRx: cellRx, cellTx: cellTx, bootTime: bootTime())
    }

    private static func bootTime() -> Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: Double(time.tv_sec))
    }
}
