import AppKit
import ActivityCore
import ServiceManagement

/// User preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return L.tr("Как в системе", "System")
            case .light: return L.tr("Светлая", "Light")
            case .dark: return L.tr("Тёмная", "Dark")
            }
        }
    }

    static func title(of language: AppLanguage) -> String {
        switch language {
        case .system: return L.tr("Как в системе", "System")
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case icon, time, hidden

        var id: String { rawValue }

        var title: String {
            switch self {
            case .icon: return L.tr("Значок", "Icon")
            case .time: return L.tr("Время", "Time")
            case .hidden: return L.tr("Скрыть", "Hide")
            }
        }
    }

    private let defaults: UserDefaults

    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Keys.isPaused) } }
    /// After this many seconds without keyboard/mouse input the user counts as away.
    @Published var idleThreshold: TimeInterval { didSet { defaults.set(idleThreshold, forKey: Keys.idleThreshold) } }
    /// Video playing or a call in progress (display kept awake) counts as activity even without input.
    @Published var countMediaAsActive: Bool { didSet { defaults.set(countMediaAsActive, forKey: Keys.countMedia) } }
    @Published var recordTitles: Bool { didSet { defaults.set(recordTitles, forKey: Keys.recordTitles) } }
    @Published var recordURLs: Bool { didSet { defaults.set(recordURLs, forKey: Keys.recordURLs) } }
    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }
    @Published var alwaysShowInDock: Bool {
        didSet {
            defaults.set(alwaysShowInDock, forKey: Keys.alwaysShowInDock)
            MainWindowController.shared.applyDockPolicy()
        }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            L.current = L.resolve(language)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }
    /// What the menu bar item shows. Hidden: the app runs silently, statistics open from Launchpad / Dock.
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) } }
    /// Ask GitHub Releases for newer builds (the app's only network access).
    @Published var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Keys.checkForUpdates) } }
    /// Install new builds without asking; otherwise an "Обновить" button appears.
    @Published var autoUpdate: Bool { didSet { defaults.set(autoUpdate, forKey: Keys.autoUpdate) } }

    private enum Keys {
        static let isPaused = "isPaused"
        static let idleThreshold = "idleThreshold"
        static let countMedia = "countMediaAsActive"
        static let recordTitles = "recordTitles"
        static let recordURLs = "recordURLs"
        static let appearance = "appearance"
        static let alwaysShowInDock = "alwaysShowInDock"
        static let language = "language"
        static let menuBarStyle = "menuBarStyle"
        static let checkForUpdates = "checkForUpdates"
        static let autoUpdate = "autoUpdate"
        static let loginItemConfigured = "loginItemConfigured"
        static let accessibilityPromptVersion = "accessibilityPromptVersion"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.isPaused: false,
            Keys.idleThreshold: 180.0,
            Keys.countMedia: true,
            Keys.recordTitles: true,
            Keys.recordURLs: true,
            Keys.appearance: Appearance.system.rawValue,
            Keys.alwaysShowInDock: false,
            Keys.language: AppLanguage.system.rawValue,
            Keys.menuBarStyle: MenuBarStyle.icon.rawValue,
            Keys.checkForUpdates: true,
            Keys.autoUpdate: true,
        ])
        isPaused = defaults.bool(forKey: Keys.isPaused)
        idleThreshold = defaults.double(forKey: Keys.idleThreshold)
        countMediaAsActive = defaults.bool(forKey: Keys.countMedia)
        recordTitles = defaults.bool(forKey: Keys.recordTitles)
        recordURLs = defaults.bool(forKey: Keys.recordURLs)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        alwaysShowInDock = defaults.bool(forKey: Keys.alwaysShowInDock)
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Keys.menuBarStyle) ?? "") ?? .icon
        checkForUpdates = defaults.bool(forKey: Keys.checkForUpdates)
        autoUpdate = defaults.bool(forKey: Keys.autoUpdate)
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("ActivityTracker: launch at login: \(error)")
            }
        }
    }

    /// A tracker is only useful if it always runs: on the first start from an app bundle turn launch-at-login on.
    /// The Accessibility prompt (window titles) is shown once per signing scheme: builds are now signed with a
    /// stable local identity, so a permission granted to an older ad-hoc build doesn't carry over and is asked again.
    func firstRunSetup() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        if !defaults.bool(forKey: Keys.loginItemConfigured) {
            defaults.set(true, forKey: Keys.loginItemConfigured)
            launchAtLogin = true
        }
        let promptVersion = 2
        if recordTitles && !WindowTitle.isTrusted && defaults.integer(forKey: Keys.accessibilityPromptVersion) < promptVersion {
            defaults.set(promptVersion, forKey: Keys.accessibilityPromptVersion)
            WindowTitle.requestAccess()
        }
    }
}
