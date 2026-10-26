import AppKit
import ActivityCore

/// "Install on iPhone": gets the iPhone app's source, builds it with the Xcode on this Mac, signs it with the Apple ID
/// signed in to Xcode and installs it on the iPhone connected by cable. The same button every 7 days renews the free
/// signature. Xcode itself is never opened.
final class PhoneInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    /// What the user has to do before it can work (shown with a button).
    enum Fix: Equatable {
        case installXcode
        case signIn
        case none
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var fix = Fix.none
    @Published private(set) var lastInstall: Date? = UserDefaults.standard.object(forKey: "phoneLastInstall") as? Date

    private let queue = DispatchQueue(label: "ActivityTracker.phoneInstall", qos: .userInitiated)
    /// Called on the main thread: the pairing code (pairs first if needed), handed to the iPhone app over the cable.
    var pairingCode: () -> String? = { nil }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ActivityTracker/iphone-install.log")
    }

    /// The source lives inside the app's own folder (never in a folder the user keeps, like an Obsidian vault).
    private static var sourceURL: URL {
        get throws { try ActivityStore.defaultURL().deletingLastPathComponent().appendingPathComponent("iphone-src", isDirectory: true) }
    }

    func install() {
        guard !isWorking else { return }
        fix = .none
        phase = .working(L.tr("Проверяю Xcode…", "Checking Xcode…"))
        queue.async { [self] in
            let result: Phase
            do {
                result = .done(try run())
            } catch let error as InstallError {
                result = .failed(error.message)
                DispatchQueue.main.async { self.fix = error.fix }
            } catch {
                result = .failed("\(error)")
            }
            DispatchQueue.main.async {
                self.phase = result
                if case .done = result {
                    self.lastInstall = Date()
                    UserDefaults.standard.set(self.lastInstall, forKey: "phoneLastInstall")
                }
            }
        }
    }

    private struct InstallError: Error {
        var message: String
        var fix: Fix = .none
    }

    private func step(_ text: String) {
        log("— " + text)
        DispatchQueue.main.async { self.phase = .working(text) }
    }

    /// On `queue`. Returns the success message.
    private func run() throws -> String {
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logURL.path, contents: Data("ActivityTracker → iPhone, \(Date())\n".utf8))

        // 1. Xcode (the command line tools alone can't build for an iPhone).
        guard let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else {
            throw InstallError(message: L.tr("Нужен Xcode (бесплатно, App Store).", "Xcode is needed (free, App Store)."), fix: .installXcode)
        }
        let developer = xcode.appendingPathComponent("Contents/Developer").path
        let environment = ["DEVELOPER_DIR": developer]

        // 2. The team of the Apple ID signed in to Xcode.
        guard let team = findTeam() else {
            throw InstallError(message: L.tr("Не нашёл команду Apple ID. Проверь вход: Xcode → Settings → Apple Accounts. Если вход есть — открой там Personal Team, скопируй Team ID и вставь в поле ниже.",
                                             "Couldn't find the Apple ID team. Check Xcode → Settings → Apple Accounts. If you are signed in, open Personal Team there, copy the Team ID and paste it below."),
                               fix: .signIn)
        }
        log("team \(team.name) (\(team.id)), free: \(team.isFree)")

        // 3. The iPhone.
        step(L.tr("Ищу iPhone…", "Looking for the iPhone…"))
        let list = FileManager.default.temporaryDirectory.appendingPathComponent("activitytracker-devices.json")
        try? FileManager.default.removeItem(at: list)
        _ = try? tool("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", list.path], environment: environment, timeout: 60)
        let devices = PhoneInstall.devices(devicectlJSON: (try? Data(contentsOf: list)) ?? Data())
        guard let device = devices.first else {
            throw InstallError(message: L.tr("iPhone не найден. Подключи его кабелем, разблокируй и нажми «Доверять этому компьютеру».",
                                             "No iPhone found. Connect it with a cable, unlock it and tap “Trust This Computer”."))
        }
        guard device.developerModeEnabled else {
            throw InstallError(message: L.tr("На iPhone выключен режим разработчика: Настройки → Конфиденциальность и безопасность → Режим разработчика (iPhone перезагрузится).",
                                             "Developer Mode is off on the iPhone: Settings → Privacy & Security → Developer Mode (the iPhone restarts)."))
        }
        log("device \(device.name) \(device.udid)")

        // 4. The source: a shallow copy of the release branch, refreshed every time.
        step(L.tr("Скачиваю код приложения…", "Downloading the app's source…"))
        let source = try Self.sourceURL
        if FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) {
            try tool("/usr/bin/git", ["-C", source.path, "fetch", "--depth", "1", "origin", PhoneInstall.branch],
                     environment: environment, timeout: 300).check(L.tr("Не удалось скачать код", "Could not download the source"))
            try tool("/usr/bin/git", ["-C", source.path, "reset", "--hard", "FETCH_HEAD"], environment: environment, timeout: 60)
                .check(L.tr("Не удалось обновить код", "Could not update the source"))
        } else {
            try? FileManager.default.removeItem(at: source)
            try tool("/usr/bin/git", ["clone", "--depth", "1", "--branch", PhoneInstall.branch, "--", PhoneInstall.repositoryURL, source.path],
                     environment: environment, timeout: 600).check(L.tr("Не удалось скачать код", "Could not download the source"))
        }

        // 5. Build and sign (the first time Xcode also creates the certificate and registers the iPhone).
        step(L.tr("Собираю и подписываю (первый раз — до 10 минут)…", "Building and signing (the first time up to 10 minutes)…"))
        let bundleID = PhoneInstall.bundleID(team: team.id)
        let derived = source.appendingPathComponent("build")
        let build = try tool("/usr/bin/xcrun", [
            "xcodebuild", "-project", source.appendingPathComponent(PhoneInstall.projectPath).path,
            "-scheme", PhoneInstall.scheme, "-configuration", "Release",
            "-destination", "id=\(device.udid)", "-derivedDataPath", derived.path,
            "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
            "DEVELOPMENT_TEAM=\(team.id)", "PRODUCT_BUNDLE_IDENTIFIER=\(bundleID)", "CODE_SIGN_STYLE=Automatic",
            "build",
        ], environment: environment, timeout: 1800)
        guard build.status == 0 else {
            let errors = PhoneInstall.errors(inBuildLog: build.output)
            throw InstallError(message: L.tr("Сборка не удалась: ", "The build failed: ")
                               + (errors.isEmpty ? L.tr("подробности в журнале.", "see the log.") : errors.joined(separator: "\n")))
        }
        let app = derived.appendingPathComponent("Build/Products/Release-iphoneos/ActivityPhone.app")

        // 6. Install and start.
        step(L.tr("Устанавливаю на \(device.name)…", "Installing on \(device.name)…"))
        try tool("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", device.identifier, app.path],
                 environment: environment, timeout: 300).check(L.tr("Не удалось установить на iPhone", "Could not install on the iPhone"))
        // Pair over the cable too: the code goes into the app's own folder, the app takes it on start (no QR needed).
        var code: String?
        DispatchQueue.main.sync { code = self.pairingCode() }
        if let code {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("activitytracker-\(UUID().uuidString).atpair")
            try? Data(code.utf8).write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let copied = try? tool("/usr/bin/xcrun", ["devicectl", "device", "copy", "to", "--device", device.identifier,
                                                      "--source", file.path, "--destination", "Documents/pairing.atpair",
                                                      "--domain-type", "appDataContainer", "--domain-identifier", bundleID],
                                   environment: environment, timeout: 60)
            try? FileManager.default.removeItem(at: file)
            log(copied?.status == 0 ? "pairing handed over" : "pairing not handed over (QR still works)")
        }
        let launch = try tool("/usr/bin/xcrun", ["devicectl", "device", "process", "launch", "--terminate-existing",
                                                 "--device", device.identifier, bundleID],
                              environment: environment, timeout: 120)
        if launch.status != 0 {
            return L.tr("Установлено. Первый раз iPhone не даст открыть приложение: Настройки → Основные → VPN и управление устройством → твой Apple ID → «Доверять». Потом открой ActivityTracker на iPhone.",
                        "Installed. The first time the iPhone won't open it: Settings → General → VPN & Device Management → your Apple ID → “Trust”. Then open ActivityTracker on the iPhone.")
        }
        return team.isFree
            ? L.tr("Готово: приложение открыто на \(device.name). Бесплатная подпись действует 7 дней — потом просто нажми кнопку снова.",
                   "Done: the app is open on \(device.name). The free signature lasts 7 days — then just press the button again.")
            : L.tr("Готово: приложение открыто на \(device.name).", "Done: the app is open on \(device.name).")
    }

    /// Typed by hand in Settings when nothing else finds the team.
    static let manualTeamKey = "phoneTeamID"

    /// The team to sign with: typed by hand, Xcode's settings, an Apple Development certificate, a provisioning profile.
    private func findTeam() -> PhoneInstall.Team? {
        if let typed = UserDefaults.standard.string(forKey: Self.manualTeamKey)?.trimmingCharacters(in: .whitespaces).uppercased(),
           !typed.isEmpty {
            return PhoneInstall.Team(id: typed, name: L.tr("введён вручную", "typed in"), isFree: true)
        }
        if let output = try? quietTool("/usr/bin/defaults", ["export", "com.apple.dt.Xcode", "-"]) {
            if let team = PhoneInstall.teams(xcodeDefaults: Data(output.utf8)).first { return team }
            // For the log: which settings exist (names only), to see where a newer Xcode keeps its accounts.
            if let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any] {
                log("Xcode settings keys: " + plist.keys.filter { $0.localizedCaseInsensitiveContains("team") || $0.localizedCaseInsensitiveContains("account") || $0.localizedCaseInsensitiveContains("provision") }.sorted().joined(separator: ", "))
            }
        }
        // A certificate Xcode created earlier: its subject carries the team (OU=…).
        if let pems = try? quietTool("/usr/bin/security", ["find-certificate", "-a", "-c", "Apple Development", "-p"]) {
            for block in pems.components(separatedBy: "-----END CERTIFICATE-----") where block.contains("BEGIN CERTIFICATE") {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("activitytracker-\(UUID().uuidString).pem")
                defer { try? FileManager.default.removeItem(at: file) }
                guard (try? Data((block + "-----END CERTIFICATE-----\n").utf8).write(to: file)) != nil,
                      let subject = try? quietTool("/usr/bin/openssl", ["x509", "-noout", "-subject", "-in", file.path]),
                      let id = PhoneInstall.team(fromCertificateSubject: subject) else { continue }
                return PhoneInstall.Team(id: id, name: "Apple Development", isFree: true)
            }
        }
        // A provisioning profile Xcode downloaded earlier.
        let home = FileManager.default.homeDirectoryForCurrentUser
        for folder in ["Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"] {
            let url = home.appendingPathComponent(folder)
            for file in (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "mobileprovision" {
                guard let decoded = try? quietTool("/usr/bin/security", ["cms", "-D", "-i", file.path]),
                      let plist = try? PropertyListSerialization.propertyList(from: Data(decoded.utf8), format: nil) as? [String: Any],
                      let id = (plist["TeamIdentifier"] as? [String])?.first else { continue }
                return PhoneInstall.Team(id: id, name: plist["TeamName"] as? String ?? id, isFree: true)
            }
        }
        return nil
    }

    /// A short tool run whose output isn't copied to the log (settings, certificates).
    private func quietTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()   // read before waiting: a full pipe would stall it
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError(message: "\(path) \(process.terminationStatus)") }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Running tools

    private struct Output {
        var status: Int32
        var output: String

        @discardableResult
        func check(_ what: String) throws -> Output {
            guard status == 0 else {
                let tail = output.split(separator: "\n").suffix(3).joined(separator: "\n")
                throw InstallError(message: what + (tail.isEmpty ? "" : ":\n" + tail))
            }
            return self
        }
    }

    /// Output goes to a temporary file (xcodebuild prints megabytes; a pipe would fill up and stall it) and the log.
    @discardableResult
    private func tool(_ path: String, _ arguments: [String], environment: [String: String] = [:],
                      timeout: TimeInterval) throws -> Output {
        log("$ \(([path] + arguments).joined(separator: " "))")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("activitytracker-tool-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let handle = try FileHandle(forWritingTo: outputURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                try? handle.close()
                throw InstallError(message: L.tr("Слишком долго: \((path as NSString).lastPathComponent)", "Took too long: \((path as NSString).lastPathComponent)"))
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        try? handle.close()
        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        log(output.count > 20_000 ? "…" + String(output.suffix(20_000)) : output)
        return Output(status: process.terminationStatus, output: output)
    }

    private func log(_ text: String) {
        guard let handle = try? FileHandle(forWritingTo: Self.logURL) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((text + "\n").utf8))
        try? handle.close()
    }
}
