import Foundation
import Network
import ActivityCore

/// Finds the paired Mac on the current network and fetches one snapshot. Every way is tried at once and the first
/// answer wins: an address typed in Settings (Tailscale), the address that worked last time, the Mac's addresses
/// from pairing (Tailscale's among them), Bonjour, and the iPhone's own hotspot network (172.20.10.2–14: the Mac is
/// one of these when it uses the iPhone's internet).
enum MacClient {
    enum ClientError: LocalizedError {
        case notFound
        case timeout
        case badAnswer

        var errorDescription: String? {
            switch self {
            case .notFound: return L.tr("Mac не найден в этой сети", "The Mac wasn't found on this network")
            case .timeout: return L.tr("Mac не ответил", "The Mac didn't answer")
            case .badAnswer: return L.tr("Ответ не открылся этим ключом — свяжи заново", "The answer didn't open with this key — pair again")
            }
        }
    }

    private static let queue = DispatchQueue(label: "ActivityPhone.client")

    static func fetch(pairing: PhoneLink.Pairing, lastHost: String?, manualHost: String?) async throws -> (snapshot: PhoneSnapshot, host: String?) {
        let port = NWEndpoint.Port(rawValue: PhoneLink.port)!
        var hosts: [String] = []
        for host in [manualHost, lastHost].compactMap({ $0 }) + pairing.hosts + (2...14).map({ "172.20.10.\($0)" })
        where !hosts.contains(host) {
            hosts.append(host)
        }
        let endpoints = hosts.prefix(40).map { NWEndpoint.hostPort(host: NWEndpoint.Host($0), port: port) }

        enum Outcome {
            case answer(PhoneSnapshot, String?)
            case wrongKey
            case nothing
        }
        func outcome(_ endpoint: NWEndpoint) async -> Outcome {
            do {
                let (snapshot, host) = try await attempt(endpoint, pairing: pairing)
                return .answer(snapshot, host)
            } catch ClientError.badAnswer {
                return .wrongKey
            } catch {
                return .nothing
            }
        }

        let result: Result<(snapshot: PhoneSnapshot, host: String?), ClientError> = await withTaskGroup(of: Outcome.self) { group in
            for endpoint in endpoints {
                group.addTask { await outcome(endpoint) }
            }
            group.addTask {
                // Bonjour: the Mac advertises itself under its computer name.
                for endpoint in await browse(seconds: 3) where endpointName(endpoint) == pairing.macName {
                    let result = await outcome(endpoint)
                    if case .answer = result { return result }
                }
                return .nothing
            }
            var wrongKey = false
            while let result = await group.next() {
                switch result {
                case .answer(let snapshot, let host):
                    group.cancelAll()
                    return .success((snapshot, host))
                case .wrongKey:
                    wrongKey = true
                case .nothing:
                    break
                }
            }
            return .failure(wrongKey ? ClientError.badAnswer : ClientError.notFound)
        }
        return try result.get()
    }

    private static func endpointName(_ endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    /// Services found within `seconds`.
    private static func browse(seconds: Double) async -> [NWEndpoint] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: PhoneLink.serviceType, domain: nil), using: .tcp)
            var found: [NWEndpoint] = []
            browser.browseResultsChangedHandler = { results, _ in found = results.map(\.endpoint) }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + seconds) {
                browser.cancel()
                continuation.resume(returning: found)
            }
        }
    }

    /// One request to one address: 4 s to connect, 30 s for the whole answer.
    static func attempt(_ endpoint: NWEndpoint, pairing: PhoneLink.Pairing) async throws -> (PhoneSnapshot, String?) {
        let challenge = PhoneLink.newChallenge()
        let connection = NWConnection(to: endpoint, using: .tcp)
        let once = Once<(PhoneSnapshot, String?)>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.onFinish = { connection.cancel() }
                guard once.begin(continuation) else { return }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let host = remoteHost(connection)
                        connection.send(content: PhoneLink.request(challenge: challenge, pairing: pairing),
                                        completion: .contentProcessed { error in if let error { once.fail(error) } })
                        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
                            guard error == nil, let header, let length = PhoneLink.responseLength(header) else {
                                return once.fail(error ?? ClientError.badAnswer)
                            }
                            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                                guard error == nil, let body, body.count == length else {
                                    return once.fail(error ?? ClientError.badAnswer)
                                }
                                do {
                                    once.succeed((try PhoneLink.open(body, challenge: challenge, pairing: pairing), host))
                                } catch {
                                    once.fail(ClientError.badAnswer)
                                }
                            }
                        }
                    case .failed(let error), .waiting(let error):
                        once.fail(error)
                    case .cancelled:
                        once.fail(CancellationError())
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + 4) {
                    if connection.state != .ready { once.fail(ClientError.timeout) }
                }
                queue.asyncAfter(deadline: .now() + 30) { once.fail(ClientError.timeout) }
            }
        } onCancel: {
            once.fail(CancellationError())
        }
    }

    private static func remoteHost(_ connection: NWConnection) -> String? {
        guard case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint,
              case .ipv4(let address) = host else { return nil }
        return "\(address)"
    }
}

/// Resumes a continuation exactly once, whatever fires first (answer, error, timeout, cancellation).
private final class Once<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var continuation: CheckedContinuation<Value, Error>?
    var onFinish: (() -> Void)?

    /// False if it was already cancelled (the continuation has then been resumed with CancellationError).
    func begin(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func succeed(_ value: Value) { finish(.success(value)) }
    func fail(_ error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        let onFinish = self.onFinish
        lock.unlock()
        onFinish?()
        continuation?.resume(with: result)
    }
}
