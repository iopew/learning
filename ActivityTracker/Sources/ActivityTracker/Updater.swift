import AppKit
import ActivityCore

/// Checks GitHub Releases for newer builds and installs them (automatically or by the "Обновить" button).
///
/// Install = download the zip → `Installer.stage` (unpack, verify, re-sign with this Mac's stable identity so
/// permissions survive) → start the new copy in installer mode, which quits this app, swaps the bundles, starts the
/// new version and rolls back if it doesn't stay up. See docs/01 - Архитектура.md.
final class Updater: ObservableObject {
    static let releasesURL = URL(string: "https://api.github.com/repos/iopew/learning/releases?per_page=30")!
    static let checkInterval: TimeInterval = 30 * 60

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case downloading(Int)
        case installing(Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastCheck: Date?

    let currentBuild: Int
    let currentVersion: String

    private let settings: Settings
    private let session: URLSession
    private var timer: Timer?

    init(settings: Settings) {
        let info = Bundle.main.infoDictionary ?? [:]
        currentBuild = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        self.settings = settings
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration)
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var canInstall: Bool { Installer.canReplace(Bundle.main.bundleURL) }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Not right at launch: let the app (and the network after wake/login) settle first, and let a just-finished
        // installer exit before its leftovers are removed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            Installer.cleanUpOldDownloads()
            self?.check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) {
        guard !isBusy, userInitiated || settings.checkForUpdates else { return }
        phase = .checking

        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ActivityTracker/\(currentBuild)", forHTTPHeaderField: "User-Agent")
        let currentBuild = currentBuild
        session.dataTask(with: request) { data, response, error in
            let result: Result<AvailableUpdate?, Error>
            if let error {
                result = .failure(error)
            } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                result = .failure(UpdateError.http(status))
            } else {
                result = Result { try UpdateFeed.newest(in: data ?? Data(), newerThan: currentBuild) }
            }
            DispatchQueue.main.async { self.finishCheck(result, userInitiated: userInitiated) }
        }.resume()
    }

    private func finishCheck(_ result: Result<AvailableUpdate?, Error>, userInitiated: Bool) {
        lastCheck = Date()
        switch result {
        case .failure(let error):
            // Background checks fail quietly (offline, rate limit); the next one will retry.
            phase = userInitiated ? .failed("Не удалось проверить обновления: \(error.localizedDescription)") : .idle
        case .success(nil):
            phase = .upToDate
        case .success(let update?):
            phase = .available(update)
            let failedBefore = Installer.lastFailedBuild == update.build
            if settings.autoUpdate && canInstall && !failedBefore && !userInitiated {
                install(update)
            }
        }
    }

    func install(_ update: AvailableUpdate) {
        guard !isBusy else { return }
        guard canInstall else {
            phase = .failed("Обновление возможно только для приложения в папке «Программы».")
            return
        }
        phase = .downloading(update.build)
        Installer.log("downloading build \(update.build) from \(update.downloadURL)")

        session.downloadTask(with: update.downloadURL) { location, response, error in
            do {
                if let error { throw error }
                guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                // The temporary file is deleted when this handler returns: move it first.
                let zip = try Installer.updatesDirectory().appendingPathComponent("build-\(update.build).zip")
                try? FileManager.default.removeItem(at: zip)
                try FileManager.default.moveItem(at: location, to: zip)

                DispatchQueue.main.async { self.phase = .installing(update.build) }
                let staged = try Installer.stage(zip: zip, expectedBuild: update.build)
                try Installer.launchInstaller(staged: staged, target: Bundle.main.bundleURL)
                // The installer quits this app in a moment. If it doesn't, say so instead of spinning forever.
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                    if self.phase == .installing(update.build) {
                        self.phase = .failed("Установщик не ответил. Подробности — в журнале обновлений.")
                    }
                }
            } catch {
                Installer.log("update to \(update.build) failed: \(error)")
                DispatchQueue.main.async {
                    self.phase = .failed("Не удалось обновиться: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}

enum UpdateError: LocalizedError {
    case http(Int)
    case badBundle(String)
    case command(String, Int32, String)
    case notInstallable

    var errorDescription: String? {
        switch self {
        case .http(let status): return "сервер ответил \(status)"
        case .badBundle(let reason): return "неверный пакет обновления: \(reason)"
        case .command(let tool, let status, let output): return "\(tool) завершился с кодом \(status): \(output)"
        case .notInstallable: return "приложение лежит не в папке «Программы»"
        }
    }
}

/// Unpacking, signing and swapping app bundles. Shared by the updater, the first-run "adoption" of the stable
/// signing identity, and the `--install-update` / `--update-from-zip` command-line modes.
enum Installer {
    private static let defaults = UserDefaults.standard
    private static let failedBuildKey = "updateFailedBuild"
    private static let adoptionKey = "signingAdoptionAttemptedBuild"

    /// Set while this process is handing over to an installer: the app must not start recording or show UI.
    static var isHandingOver = false

    /// A build that was rolled back; automatic updates skip it (the button can still retry it).
    static var lastFailedBuild: Int? {
        defaults.object(forKey: failedBuildKey) as? Int
    }

    // MARK: Locations

    static func updatesDirectory() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let folder = caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ActivityTracker")
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ActivityTracker/update.log")
    }

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(getpid())] \(message)\n"
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Only a bundle in a folder we can write to (normally /Applications) can be replaced.
    static func canReplace(_ app: URL) -> Bool {
        guard Bundle.main.bundleIdentifier != nil, app.pathExtension == "app",
              !app.path.contains("/AppTranslocation/")
        else { return false }
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    // MARK: Staging

    /// Unpacks the downloaded zip, checks it is our app (and the expected build), signs it with the local identity.
    static func stage(zip: URL, expectedBuild: Int?) throws -> URL {
        let folder = try updatesDirectory().appendingPathComponent("staged", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        try? FileManager.default.removeItem(at: zip)

        let app = folder.appendingPathComponent("ActivityTracker.app")
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
            throw UpdateError.badBundle("нет Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.badBundle("чужой идентификатор \(info["CFBundleIdentifier"] ?? "?")")
        }
        if let expectedBuild, Int(info["CFBundleVersion"] as? String ?? "") != expectedBuild {
            throw UpdateError.badBundle("ожидалась сборка \(expectedBuild)")
        }
        try sign(app)
        return app
    }

    static func sign(_ app: URL) throws {
        guard let script = Bundle.main.url(forResource: "local-sign", withExtension: "sh") else {
            throw UpdateError.badBundle("нет local-sign.sh")
        }
        let output = try run("/bin/bash", [script.path, app.path])
        log(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isSignedLocally(_ app: URL) -> Bool {
        guard let script = Bundle.main.url(forResource: "local-sign", withExtension: "sh") else { return false }
        return (try? run("/bin/bash", [script.path, "--check", app.path])) != nil
    }

    /// Starts `staged` as a separate app instance in installer mode. Returns once the launch was requested.
    static func launchInstaller(staged: URL, target: URL) throws {
        log("starting installer \(staged.path) for \(target.path)")
        try open(staged, arguments: ["--install-update", target.path])
    }

    /// `open -n -g`: a new instance, in the background, as its own launchd job (so it outlives this process).
    private static func open(_ app: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-g", app.path, "--args"] + arguments
        try process.run()
        // `open` returns once LaunchServices has the request; don't hang on it if it takes longer.
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if !process.isRunning && process.terminationStatus != 0 {
            throw UpdateError.command("open", process.terminationStatus, app.path)
        }
    }

    // MARK: First-run adoption

    /// A copy installed by hand (downloaded build, ad-hoc signed) is re-signed with the stable local identity once,
    /// before the user grants permissions, so later updates keep them. Returns true when a hand-over started.
    static func adoptIfNeeded() -> Bool {
        let app = Bundle.main.bundleURL
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        guard canReplace(app), app.path.contains("/Applications/"),
              defaults.string(forKey: adoptionKey) != build,   // one attempt per build: never loop
              !isSignedLocally(app)
        else { return false }
        defaults.set(build, forKey: adoptionKey)
        do {
            let folder = try updatesDirectory().appendingPathComponent("adopt", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent("ActivityTracker.app")
            try run("/usr/bin/ditto", [app.path, copy.path])
            try sign(copy)
            try launchInstaller(staged: copy, target: app)
            log("adoption: handing over to the locally signed copy")
            return true
        } catch {
            log("adoption failed: \(error)")
            return false
        }
    }

    // MARK: Installer mode (runs inside the new copy)

    /// `--install-update <target>`: quit the running app, put this bundle in its place, start it, verify it stays up,
    /// otherwise restore the previous version. Runs before any UI; returns the process exit code.
    static func runInstallMode(target: URL) -> Int32 {
        let source = Bundle.main.bundleURL
        let myPID = getpid()
        let newBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
        log("installer: \(source.path) → \(target.path) (build \(newBuild))")
        guard let bundleID = Bundle.main.bundleIdentifier else { return 1 }

        // One installer at a time: an update and an adoption must never swap bundles concurrently.
        guard let lock = acquireInstallLock() else {
            log("installer: another installer is running, giving up")
            return 1
        }
        defer { close(lock) }

        func failed(_ reason: String) -> Int32 {
            log("installer: \(reason)")
            defaults.set(newBuild, forKey: failedBuildKey)   // automatic updates won't retry this build
            return 1
        }
        func others() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != myPID && kill($0.processIdentifier, 0) == 0 }
        }
        func isRunning(at url: URL) -> Bool {
            others().contains { $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path }
        }

        // 1. Quit every other running copy (the old version, a command-line caller).
        for app in others() { app.terminate() }
        if !wait(15, until: { others().isEmpty }) {
            log("installer: force-quitting \(others().map(\.processIdentifier))")
            for app in others() { app.forceTerminate() }
            _ = wait(5, until: { others().isEmpty })
        }

        // 2. Swap the bundles, keeping the old one for a rollback.
        let fileManager = FileManager.default
        guard let backup = try? updatesDirectory().appendingPathComponent("previous.app") else {
            return failed("no updates folder")
        }
        try? fileManager.removeItem(at: backup)
        let hadOldVersion = fileManager.fileExists(atPath: target.path)
        var movedOldVersion = false
        do {
            if hadOldVersion {
                try fileManager.moveItem(at: target, to: backup)
                movedOldVersion = true
            }
            try run("/usr/bin/ditto", [source.path, target.path])
        } catch {
            if movedOldVersion {
                restore(backup: backup, target: target)
            } else if hadOldVersion {
                try? open(target, arguments: ["--background"])   // the old version is untouched: just restart it
            }
            return failed("swap failed: \(error)")
        }

        // 3. Start the new version and make sure it stays up.
        try? open(target, arguments: ["--background"])
        let started = wait(20, until: { isRunning(at: target) })
        let stable = started && { _ = wait(5, until: { false }); return isRunning(at: target) }()
        guard stable else {
            for app in others() where app.bundleURL?.standardizedFileURL.path == target.standardizedFileURL.path {
                app.forceTerminate()
            }
            if movedOldVersion {
                restore(backup: backup, target: target)
            }
            return failed("build \(newBuild) did not stay up, rolled back")
        }
        defaults.removeObject(forKey: failedBuildKey)
        log("installer: build \(newBuild) installed and running")
        return 0
    }

    /// Puts the previous version back in place and starts it.
    private static func restore(backup: URL, target: URL) {
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: backup, to: target)
            try open(target, arguments: ["--background"])
            log("installer: previous version restored")
        } catch {
            log("installer: ROLLBACK FAILED: \(error); previous version is at \(backup.path)")
        }
    }

    /// An exclusive lock on Updates/install.lock, held until the installer exits; nil if someone else holds it.
    private static func acquireInstallLock() -> Int32? {
        guard let path = try? updatesDirectory().appendingPathComponent("install.lock").path else { return nil }
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    /// Removes downloads and unpacked copies left from earlier updates (the previous version is kept for rollbacks).
    static func cleanUpOldDownloads() {
        guard let folder = try? updatesDirectory(),
              let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for item in items where !["previous.app", "install.lock"].contains(item.lastPathComponent) {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// `--update-from-zip <zip>`: install a locally built zip into this app's place (used by CI and for debugging).
    static func updateFromZip(_ zip: URL) -> Int32 {
        do {
            let target = Bundle.main.bundleURL
            guard canReplace(target) else { throw UpdateError.notInstallable }
            let staged = try stage(zip: zip, expectedBuild: nil)
            try launchInstaller(staged: staged, target: target)
            print("installer started for \(target.path); log: \(logURL.path)")
            return 0
        } catch {
            print("update failed: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: Helpers

    /// Polls `condition`, turning the run loop in between so AppKit's view of running apps stays current.
    private static func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.command((tool as NSString).lastPathComponent, process.terminationStatus,
                                      String(output.suffix(500)))
        }
        return output
    }
}
