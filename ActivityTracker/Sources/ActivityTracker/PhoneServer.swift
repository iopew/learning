import AppKit
import Network
import SystemConfiguration
import ActivityCore

/// Answers the paired iPhone on the local network (home Wi-Fi, the iPhone's hotspot, the office network): one
/// encrypted snapshot of the reports per request, see `PhoneLink`. Off until an iPhone is paired; idle costs nothing
/// (the listener only wakes up on a connection).
final class PhoneServer: ObservableObject {
    @Published private(set) var pairing: PhoneLink.Pairing?
    @Published private(set) var lastServed: Date?
    @Published private(set) var problem: String?

    private let makeSnapshot: () throws -> PhoneSnapshot
    private let queue = DispatchQueue(label: "ActivityTracker.phone", qos: .utility)
    private var listener: NWListener?
    /// Touched on `queue` only.
    private var openConnections = 0
    private var servingPairing: PhoneLink.Pairing?
    private var lastAnswer = Date.distantPast

    init(makeSnapshot: @escaping () throws -> PhoneSnapshot) {
        self.makeSnapshot = makeSnapshot
        pairing = Self.loadPairing()
    }

    // MARK: - Pairing

    /// ~/Library/Application Support/ActivityTracker/phone-pairing.json (600, like the database).
    private static var pairingURL: URL? {
        try? ActivityStore.defaultURL().deletingLastPathComponent().appendingPathComponent("phone-pairing.json")
    }

    private static func loadPairing() -> PhoneLink.Pairing? {
        guard let url = pairingURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PhoneLink.Pairing.self, from: data)
    }

    /// A new key: any iPhone paired before stops getting data.
    func pair() {
        let pairing = PhoneLink.Pairing(macName: Self.computerName, hosts: Self.addresses())
        do {
            guard let url = Self.pairingURL else { return }
            try JSONEncoder().encode(pairing).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            self.pairing = pairing
            problem = nil
            restart()
        } catch {
            problem = L.tr("Не удалось сохранить ключ: \(error)", "Could not save the key: \(error)")
        }
    }

    /// The QR code text, pairing first when there is no pairing yet (main thread).
    func codeForCable() -> String? {
        if pairing == nil { pair() }
        return pairing.map(PhoneLink.encode)
    }

    func unpair() {
        if let url = Self.pairingURL { try? FileManager.default.removeItem(at: url) }
        pairing = nil
        stop()
    }

    /// "MacBook Pro Davron" as in System Settings → General → Sharing (Host.current() may block on DNS).
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    /// The Mac's current IPv4 addresses (Wi-Fi, Ethernet, the iPhone's hotspot), so the iPhone knows where to look.
    static func addresses() -> [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, entry.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            let name = String(cString: entry.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                              NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            // Wi-Fi / Ethernet / hotspot, and Tailscale (a utun interface with an address in 100.64.0.0/10).
            if name.hasPrefix("en") || name.hasPrefix("bridge") || (name.hasPrefix("utun") && isTailscale(text)) {
                result.append(text)
            }
        }
        return result
    }

    /// 100.64.0.0/10: the addresses Tailscale gives its devices.
    static func isTailscale(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    // MARK: - Listening

    func start() {
        guard pairing != nil, listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: PhoneLink.port)!)
            listener.service = NWListener.Service(name: Self.computerName, type: PhoneLink.serviceType)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    DispatchQueue.main.async {
                        self?.problem = L.tr("Сервер для iPhone не запустился: \(error)", "The server for the iPhone failed: \(error)")
                        self?.stop()
                    }
                }
            }
            let pairing = pairing
            queue.async { self.servingPairing = pairing }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            problem = L.tr("Сервер для iPhone не запустился: \(error)", "The server for the iPhone failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { self.servingPairing = nil }
    }

    private func restart() {
        stop()
        start()
    }

    /// On `queue`. Anything that isn't a valid request within 5 seconds is dropped without an answer.
    private func accept(_ connection: NWConnection) {
        guard openConnections < 4, let pairing = servingPairing else {
            connection.cancel()
            return
        }
        openConnections += 1
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            openConnections -= 1
            connection.cancel()
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { finish() }
        connection.receive(minimumIncompleteLength: PhoneLink.requestSize, maximumLength: PhoneLink.requestSize) {
            [weak self] data, _, _, error in
            guard let self, !finished, error == nil, let data,
                  let challenge = PhoneLink.challenge(fromRequest: data, pairing: pairing),
                  Date().timeIntervalSince(self.lastAnswer) > 1   // at most one report per second
            else { return finish() }
            self.lastAnswer = Date()
            do {
                let response = try PhoneLink.response(try self.makeSnapshot(), challenge: challenge, pairing: pairing)
                connection.send(content: response, completion: .contentProcessed { _ in finish() })
                DispatchQueue.main.async { self.lastServed = Date() }
            } catch {
                NSLog("ActivityTracker: phone snapshot: \(error)")
                finish()
            }
        }
    }

    // MARK: - AirDrop

    /// Writes an encrypted snapshot file and offers it to AirDrop (for networks where devices can't see each other).
    func sendViaAirDrop() {
        guard let pairing else { return }
        queue.async { [self] in
            do {
                let data = try PhoneLink.file(try makeSnapshot(), pairing: pairing)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ActivityTracker-phone", isDirectory: true)
                try? FileManager.default.removeItem(at: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH.mm"
                let url = folder.appendingPathComponent("ActivityTracker \(formatter.string(from: Date())).\(PhoneLink.fileExtension)")
                try data.write(to: url)
                DispatchQueue.main.async {
                    if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [url]) {
                        service.perform(withItems: [url])
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.problem = L.tr("Не удалось подготовить снимок: \(error)", "Could not prepare the snapshot: \(error)")
                }
            }
        }
    }
}
