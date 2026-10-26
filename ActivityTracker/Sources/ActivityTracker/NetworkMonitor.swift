import AppKit
import CoreLocation
import CoreWLAN
import Network
import SystemConfiguration
import ActivityCore

/// Network statistics, on a background queue:
/// - every 5 s the byte counters of the physical interfaces (en*, pdp_ip*) are read: traffic, peak speed and the
///   speed while something was actually transferring;
/// - once a minute the minute is stored together with the network it belongs to (Wi-Fi name, cable, iPhone hotspot),
///   the Wi-Fi link rate and signal, and a ping (3 packets) to the router and to 1.1.1.1.
/// No speed tests: nothing is downloaded on purpose. The pings are ~100 KB a day.
final class NetworkMonitor: NSObject, CLLocationManagerDelegate {
    static let tick: TimeInterval = TrafficCounter.tick
    static let minute: TimeInterval = 60
    /// A 5-second window above this counts as "transferring" (for the average speed).
    static let busyRate: Double = 50_000
    static let internetHost = "1.1.1.1"

    private let store: NetworkStore
    private let queue = DispatchQueue(label: "ActivityTracker.network", qos: .utility)
    private let pingQueue = DispatchQueue(label: "ActivityTracker.network.ping", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let path = NWPathMonitor()
    private var expensive = false
    private var location: CLLocationManager?

    // Only touched on `queue`.
    private var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastRead: Date?
    private var minute = MinuteTotals()
    private var minuteStart: Date?
    private var pingRunning = false

    private struct MinuteTotals {
        var rx: Double = 0
        var tx: Double = 0
        var peakRx: Double = 0
        var peakTx: Double = 0
        var busyRxBytes: Double = 0
        var busyRxSeconds: Double = 0
        var busyTxBytes: Double = 0
        var busyTxSeconds: Double = 0
    }

    init(store: NetworkStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        // Wi-Fi names need Location Services (macOS 14+); coordinates are never read.
        let manager = CLLocationManager()
        manager.delegate = self
        location = manager
        // macOS asks for Location only when the user chooses to see network names (button in the Network pane).

        path.pathUpdateHandler = { [weak self] path in self?.expensive = path.isExpensive }
        path.start(queue: queue)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: Self.tick, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    /// "Показывать названия сетей": asks macOS for Location (used only to read Wi-Fi names).
    func requestNames() {
        if location?.authorizationStatus == .notDetermined {
            location?.requestWhenInUseAuthorization()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    /// A router address from the network (DHCP) is used as a ping argument only if it is a plain IPv4 address.
    static func isIPv4(_ text: String) -> Bool {
        var address = in_addr()
        return text.count <= 15 && inet_pton(AF_INET, text, &address) == 1
    }

    /// Whether Wi-Fi names can be read (Location Services allowed).
    var namesAllowed: Bool {
        let status = location?.authorizationStatus ?? .notDetermined
        return status == .authorizedAlways || status == .authorized
    }

    // MARK: - Counters

    /// Runs on `queue` every 5 s.
    private func sample() {
        let now = Date()
        let current = Self.readCounters()
        if let lastRead {
            let elapsed = now.timeIntervalSince(lastRead)
            var rx: Double = 0
            var tx: Double = 0
            for (name, value) in current {
                guard let old = counters[name] else { continue }
                // 32-bit counters wrap at 4 GB, and restart when an interface is recreated (an iPhone plugged in).
                rx += TrafficCounter.delta(old: old.rx, new: value.rx, elapsed: elapsed)
                tx += TrafficCounter.delta(old: old.tx, new: value.tx, elapsed: elapsed)
            }
            // After sleep the window is long; its speed would be meaningless.
            if elapsed > 0, elapsed <= Self.tick * 3 {
                let rxRate = rx / elapsed
                let txRate = tx / elapsed
                minute.peakRx = max(minute.peakRx, rxRate)
                minute.peakTx = max(minute.peakTx, txRate)
                if rxRate >= Self.busyRate {
                    minute.busyRxBytes += rx
                    minute.busyRxSeconds += elapsed
                }
                if txRate >= Self.busyRate {
                    minute.busyTxBytes += tx
                    minute.busyTxSeconds += elapsed
                }
            }
            minute.rx += rx
            minute.tx += tx
        }
        counters = current
        lastRead = now
        if minuteStart == nil { minuteStart = now }
        if let start = minuteStart, now.timeIntervalSince(start) >= Self.minute {
            finishMinute(start: start, now: now)
        }
    }

    /// Bytes in/out since boot of the physical interfaces that carry a network: no loopback, no VPN tunnels (they
    /// repeat the traffic), and no links without a routable address — like the cable link Xcode and Finder use to
    /// talk to an iPhone (only fe80:: addresses), whose gigabytes of device files are not internet traffic.
    static func readCounters() -> [String: (rx: UInt32, tx: UInt32)] {
        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var routable: Set<String> = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return counters }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = entry.pointee.ifa_data else { continue }
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                counters[name] = (stats.ifi_ibytes, stats.ifi_obytes)
            case AF_INET:
                let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                if ip >> 16 != 0xA9FE { routable.insert(name) }   // 169.254.x.x: no network behind it
            case AF_INET6:
                let linkLocal = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0.pointee.sin6_addr.__u6_addr.__u6_addr8.0 == 0xFE && ($0.pointee.sin6_addr.__u6_addr.__u6_addr8.1 & 0xC0) == 0x80
                }
                if !linkLocal { routable.insert(name) }
            default:
                break
            }
        }
        return counters.filter { routable.contains($0.key) }
    }

    // MARK: - The minute

    /// Runs on `queue`.
    private func finishMinute(start: Date, now: Date) {
        let totals = minute
        minute = MinuteTotals()
        minuteStart = now
        guard let current = currentNetwork() else { return }   // offline: nothing to attribute
        let network = current.0
        let router = current.1
        var sample = NetworkSample(at: now, interval: min(now.timeIntervalSince(start), Self.minute * 1.25), network: network)
        sample.rx = totals.rx
        sample.tx = totals.tx
        sample.peakRx = totals.peakRx
        sample.peakTx = totals.peakTx
        sample.busyRxBytes = totals.busyRxBytes
        sample.busyRxSeconds = totals.busyRxSeconds
        sample.busyTxBytes = totals.busyTxBytes
        sample.busyTxSeconds = totals.busyTxSeconds
        if network.kind == .wifi || network.kind == .hotspot, let wifi = CWWiFiClient.shared().interface(),
           wifi.wlanChannel() != nil {
            let rate = wifi.transmitRate()
            let rssi = wifi.rssiValue()
            if rate > 0 { sample.linkRate = rate }
            if rssi != 0 { sample.rssi = Double(rssi) }
        }

        // Pinging takes a few seconds: on its own queue, then the sample is stored. One at a time.
        guard !pingRunning else {
            record(sample)
            return
        }
        pingRunning = true
        pingQueue.async { [self] in
            if let router, Self.isIPv4(router) {
                sample.pingRouter = Self.ping(router).average
            }
            let internet = Self.ping(Self.internetHost)
            sample.pingInternet = internet.average
            sample.loss = internet.loss
            if let loss = internet.loss { sample.online = loss < 1 }
            queue.async { [self] in
                pingRunning = false
                record(sample)
            }
        }
    }

    private func record(_ sample: NetworkSample) {
        do {
            try store.record(sample)
        } catch {
            NSLog("ActivityTracker: network sample: \(error)")
        }
    }

    /// `ping -c 3`: average round trip in ms and the share lost.
    static func ping(_ host: String) -> (average: Double?, loss: Double?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-q", "-c", "3", "-t", "5", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (nil, nil)
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()   // ping ends by itself within 5 s (-t)
        process.waitUntilExit()
        return PingOutput.parse(String(decoding: output, as: UTF8.self))
    }

    /// The network that carries the traffic now, and its router. Runs on `queue`.
    private func currentNetwork() -> (NetworkInfo, String?)? {
        guard let dynamic = SCDynamicStoreCreate(nil, "ActivityTracker" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(dynamic, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primary = global["PrimaryInterface"] as? String
        else { return nil }
        let router = global["Router"] as? String
        let wifi = CWWiFiClient.shared().interface()

        // A VPN is the primary interface while the real traffic goes over Wi-Fi or a cable underneath.
        var interface = primary
        if primary.hasPrefix("utun") || primary.hasPrefix("ipsec") || primary.hasPrefix("ppp"),
           let wifi, wifi.wlanChannel() != nil, let name = wifi.interfaceName {
            interface = name
        }

        if let wifi, wifi.interfaceName == interface {
            let ssid = wifi.ssid()
            let kind: NetworkInfo.Kind = expensive ? .hotspot : .wifi
            if let ssid, !ssid.isEmpty {
                return (NetworkInfo(key: "wifi:" + ssid, name: ssid, kind: kind), router)
            }
            let place = router ?? interface
            return (NetworkInfo(key: "router:" + place, name: "Wi-Fi (\(place))", kind: kind), router)
        }
        if interface.hasPrefix("pdp_ip") {
            return (NetworkInfo(key: "cellular", name: L.tr("Сотовая связь", "Cellular"), kind: .cellular), router)
        }
        if interface.hasPrefix("en") {
            // iPhone over USB is an "en" interface too, but marked expensive.
            if expensive {
                return (NetworkInfo(key: "usb-hotspot:" + interface, name: L.tr("Модем iPhone (USB)", "iPhone USB tethering"),
                                    kind: .hotspot), router)
            }
            let place = router ?? interface
            return (NetworkInfo(key: "ethernet:" + place, name: L.tr("Кабель (\(place))", "Ethernet (\(place))"),
                                kind: .ethernet), router)
        }
        return (NetworkInfo(key: "other:" + interface, name: interface, kind: .other), router)
    }
}
