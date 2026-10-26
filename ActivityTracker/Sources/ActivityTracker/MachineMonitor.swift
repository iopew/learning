import Foundation
import ActivityCore

/// Once a day, at the lowest priority: what starts by itself (launch agents and daemons) and how big the usual
/// space eaters are (caches, toolchains). Folders that macOS protects (Downloads, Documents, other apps' data) are
/// left out on purpose: reading them would ask for permissions.
final class MachineMonitor {
    private let store: MachineStore
    private let queue = DispatchQueue(label: "ActivityTracker.machine", qos: .background)
    private var timer: Timer?

    /// Tracked folders: (path, how it is shown).
    static var folders: [(path: String, title: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            (home + "/Library/Caches", L.tr("Кэши приложений", "App caches")),
            (home + "/Library/Caches/go-build", L.tr("Кэш сборки Go", "Go build cache")),
            (home + "/go/pkg/mod", L.tr("Модули Go", "Go modules")),
            (home + "/Library/Developer", L.tr("Xcode и симуляторы", "Xcode and simulators")),
            (home + "/.npm", "npm"),
            (home + "/.cache", L.tr("Кэши утилит (~/.cache)", "Tool caches (~/.cache)")),
            ("/opt/homebrew", "Homebrew"),
            ("/usr/local/Cellar", "Homebrew (Intel)"),
        ]
    }

    static let startupFolders: [String] = [
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
    ]

    init(store: MachineStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.run() }
        timer.tolerance = 3600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Not at launch: the Mac is busiest then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in self?.run() }
    }

    private func run() {
        queue.async { [self] in
            scanStartup()
            let last = (try? store.lastFolderScan()) ?? nil
            // Walking big folders costs energy: only on power, not in Low Power Mode.
            let onBattery = BatteryReader.read().map { !$0.onAC } ?? false
            guard !onBattery, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
            if last.map({ Date().timeIntervalSince($0) >= 20 * 3600 }) ?? true { scanFolders() }
        }
    }

    // MARK: - Startup items

    private func scanStartup() {
        var found: [String: (label: String, program: String)] = [:]
        for folder in Self.startupFolders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let path = folder + "/" + name
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                let label = plist["Label"] as? String ?? String(name.dropLast(6))
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
                found[path] = (label, program)
            }
        }
        do {
            try store.updateStartup(found, at: Date())
        } catch {
            NSLog("ActivityTracker: startup items: \(error)")
        }
    }

    // MARK: - Folder sizes

    private func scanFolders() {
        var sizes: [String: Double] = [:]
        for folder in Self.folders where FileManager.default.fileExists(atPath: folder.path) {
            sizes[folder.path] = Self.size(of: URL(fileURLWithPath: folder.path),
                                           skipAppleCaches: folder.path.hasSuffix("/Library/Caches"))
        }
        do {
            try store.recordFolders(sizes, at: Date())
        } catch {
            NSLog("ActivityTracker: folder sizes: \(error)")
        }
    }

    /// Space taken on disk. Apple's own caches are skipped (some are protected and would ask for access).
    static func size(of url: URL, skipAppleCaches: Bool) -> Double {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Double = 0
        let deadline = Date().addingTimeInterval(120)   // a huge folder gets a partial size rather than minutes of work
        while let next = enumerator.nextObject() {
            autoreleasepool {
                guard let file = next as? URL else { return }
                if skipAppleCaches, enumerator.level == 1, file.lastPathComponent.hasPrefix("com.apple.") {
                    enumerator.skipDescendants()
                    return
                }
                if let size = (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize {
                    total += Double(size)
                }
            }
            if Date() > deadline { break }
        }
        return total
    }
}
