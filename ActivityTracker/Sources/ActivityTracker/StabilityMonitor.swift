import AppKit
import ActivityCore

/// Collects the stability history: macOS diagnostic reports (crashes, hangs, kernel panics, resource complaints),
/// boots, macOS updates and the cause of the last shutdown. Everything runs on a background queue; new reports are
/// noticed by watching the report folders (no polling). Report files are read once, only their first 8 KB.
final class StabilityMonitor: ObservableObject {
    @Published private(set) var report: StabilityReport?
    @Published private(set) var bootTime: Date?
    @Published private(set) var error: String?

    let days: DayCalendar
    private let path: String
    private var store: StabilityStore?
    private let queue = DispatchQueue(label: "ActivityTracker.stability", qos: .utility)
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var rescanPending = false
    private var known: Set<String>?

    static let folders: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
        URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
    ]

    private enum Keys {
        static let osVersion = "stabilityOSVersion"
        static let shutdownCheckedBoot = "stabilityShutdownCheckedBoot"
    }

    init(path: String, days: DayCalendar) {
        self.path = path
        self.days = days
    }

    func start() {
        queue.async { [self] in
            do {
                store = try StabilityStore(path: path)
            } catch {
                publishError(L.tr("Журнал стабильности недоступен: \(error)", "Stability log unavailable: \(error)"))
                return
            }
            let boot = Self.bootTime()
            DispatchQueue.main.async { self.bootTime = boot }
            recordBootAndVersion(boot: boot)
            scan()
            DispatchQueue.main.async { self.watch() }
            // The boot log is read a few minutes after start, once per boot, at low priority.
            queue.asyncAfter(deadline: .now() + 300) { [self] in checkShutdownCause(boot: boot) }
        }
    }

    /// Rebuilds the summary for the Stability pane.
    func reload() {
        queue.async { [self] in
            guard let store else { return }
            do {
                let events = try store.events(since: Date().addingTimeInterval(-400 * 86400))
                let report = StabilityReport.make(events, now: Date(), days: days)
                DispatchQueue.main.async {
                    self.report = report
                    self.error = nil
                }
            } catch {
                publishError(L.tr("Не удалось прочитать журнал: \(error)", "Could not read the log: \(error)"))
            }
        }
    }

    private func publishError(_ text: String) {
        DispatchQueue.main.async { self.error = text }
    }

    // MARK: - Reports

    /// Runs on `queue`. Parses report files not seen before.
    private func scan() {
        guard let store else { return }
        do {
            if known == nil { known = try store.knownSources() }
            var found: [StabilityEvent] = []
            for folder in Self.folders {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
                for name in names where StabilityParser.isReport(name) && known?.contains(name) != true {
                    let file = folder.appendingPathComponent(name)
                    guard let event = Self.read(file) else { continue }
                    found.append(event)
                    known?.insert(name)
                }
            }
            if !found.isEmpty { try store.add(found) }
        } catch {
            NSLog("ActivityTracker: stability scan: \(error)")
        }
        reload()
    }

    private static func read(_ file: URL) -> StabilityEvent? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 8192)) ?? Data()
        let head = String(decoding: data, as: UTF8.self)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return StabilityParser.parse(fileName: file.lastPathComponent, head: head, modified: modified)
    }

    /// New files in the report folders trigger a rescan (a few seconds later: macOS writes them in steps).
    private func watch() {
        for folder in Self.folders {
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
            source.setEventHandler { [weak self] in self?.scheduleRescan() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watchers.append(source)
        }
    }

    /// Runs on `queue`.
    private func scheduleRescan() {
        guard !rescanPending else { return }
        rescanPending = true
        queue.asyncAfter(deadline: .now() + 5) { [self] in
            rescanPending = false
            scan()
        }
    }

    // MARK: - Boots, updates, shutdowns

    static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// "macOS 15.1 (24B83)".
    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        let build = (try? String(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist", encoding: .utf8))
            .flatMap { plist -> String? in
                guard let range = plist.range(of: "<key>ProductBuildVersion</key>") else { return nil }
                let rest = plist[range.upperBound...]
                guard let open = rest.range(of: "<string>"), let close = rest.range(of: "</string>") else { return nil }
                return String(rest[open.upperBound..<close.lowerBound])
            }
        if let build { text += " (\(build))" }
        return text
    }

    /// Runs on `queue`.
    private func recordBootAndVersion(boot: Date?) {
        guard let store else { return }
        var events: [StabilityEvent] = []
        let version = Self.osVersion
        if let boot {
            events.append(StabilityEvent(source: "boot-\(Int(boot.timeIntervalSince1970))", at: boot, kind: .boot,
                                         name: version, detail: ""))
        }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Keys.osVersion)
        if previous != version {
            if let previous {
                events.append(StabilityEvent(source: "os-\(version)", at: boot ?? Date(), kind: .os, name: version,
                                             detail: L.tr("было: \(previous)", "was: \(previous)")))
            } else {
                // First run: remember the version the history starts with.
                events.append(StabilityEvent(source: "os-\(version)", at: Date(), kind: .os, name: version,
                                             detail: L.tr("версия на момент начала записи", "version when recording began")))
            }
            defaults.set(version, forKey: Keys.osVersion)
        }
        do {
            try store.add(events)
        } catch {
            NSLog("ActivityTracker: stability boot: \(error)")
        }
    }

    /// Runs on `queue`. `log show` over the first minutes after boot finds "Previous shutdown cause: N".
    private func checkShutdownCause(boot: Date?) {
        guard let boot, let store else { return }
        let bootKey = Int(boot.timeIntervalSince1970)
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Keys.shutdownCheckedBoot) != bootKey else { return }
        defaults.set(bootKey, forKey: Keys.shutdownCheckedBoot)   // once per boot, even if it fails

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--style", "compact",
                             "--start", formatter.string(from: boot.addingTimeInterval(-60)),
                             "--end", formatter.string(from: boot.addingTimeInterval(600)),
                             "--predicate", "eventMessage CONTAINS \"Previous shutdown cause\""]
        process.qualityOfService = .background
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        // Read while it runs (a full pipe would block it); give up after 60 s.
        var output = Data()
        let reader = DispatchQueue(label: "ActivityTracker.stability.log")
        let done = DispatchSemaphore(value: 0)
        reader.async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + 60) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 5)
        }
        process.waitUntilExit()
        guard let code = StabilityParser.shutdownCause(inLog: String(decoding: output, as: UTF8.self)) else { return }
        let event = StabilityEvent(source: "shutdown-\(bootKey)", at: boot, kind: .shutdown,
                                   name: StabilityParser.describeShutdown(code),
                                   detail: L.tr("код \(code)", "code \(code)"))
        _ = try? store.add([event])
        reload()
    }
}
