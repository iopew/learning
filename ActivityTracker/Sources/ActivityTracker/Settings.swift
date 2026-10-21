import Foundation
import ServiceManagement

/// User preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Keys.isPaused) } }
    /// After this many seconds without keyboard/mouse input the user counts as away.
    @Published var idleThreshold: TimeInterval { didSet { defaults.set(idleThreshold, forKey: Keys.idleThreshold) } }
    /// Video playing or a call in progress (display kept awake) counts as activity even without input.
    @Published var countMediaAsActive: Bool { didSet { defaults.set(countMediaAsActive, forKey: Keys.countMedia) } }
    @Published var recordTitles: Bool { didSet { defaults.set(recordTitles, forKey: Keys.recordTitles) } }
    @Published var recordURLs: Bool { didSet { defaults.set(recordURLs, forKey: Keys.recordURLs) } }

    private enum Keys {
        static let isPaused = "isPaused"
        static let idleThreshold = "idleThreshold"
        static let countMedia = "countMediaAsActive"
        static let recordTitles = "recordTitles"
        static let recordURLs = "recordURLs"
        static let loginItemConfigured = "loginItemConfigured"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.isPaused: false,
            Keys.idleThreshold: 180.0,
            Keys.countMedia: true,
            Keys.recordTitles: true,
            Keys.recordURLs: true,
        ])
        isPaused = defaults.bool(forKey: Keys.isPaused)
        idleThreshold = defaults.double(forKey: Keys.idleThreshold)
        countMediaAsActive = defaults.bool(forKey: Keys.countMedia)
        recordTitles = defaults.bool(forKey: Keys.recordTitles)
        recordURLs = defaults.bool(forKey: Keys.recordURLs)
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

    /// A tracker is only useful if it always runs: on the first start from an app bundle turn launch-at-login on
    /// and ask for the Accessibility permission (window titles). Both can be changed in the settings afterwards.
    func firstRunSetup() {
        guard Bundle.main.bundleIdentifier != nil, !defaults.bool(forKey: Keys.loginItemConfigured) else { return }
        defaults.set(true, forKey: Keys.loginItemConfigured)
        launchAtLogin = true
        if recordTitles { WindowTitle.requestAccess() }
    }
}
