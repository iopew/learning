import AppKit
import ActivityCore

/// Samples what the user is doing every few seconds and feeds it to the store.
/// Lives on the main thread: timer, notifications and AppleScript all run there.
final class Tracker: ObservableObject {
    enum State: Equatable {
        case active
        case idle
        case paused
        case away   // screen locked, display asleep, system asleep, another user session
    }

    static let interval: TimeInterval = 5

    @Published private(set) var state: State = .active
    @Published private(set) var current: Sample?
    @Published private(set) var todayTotal: TimeInterval = 0
    @Published private(set) var lastError: String?

    private let store: ActivityStore
    private let settings: Settings
    private var timer: Timer?
    private var activityToken: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var screenLocked = false
    private var asleep = false

    init(store: ActivityStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        // Keep App Nap from throttling the timer of a background (menu bar only) app.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Recording activity")

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observeSystem()
        tick()
    }

    func stop() {
        try? store.endStreak(at: Date())
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        activityToken = nil
    }

    func setPaused(_ paused: Bool) {
        settings.isPaused = paused
        tick()
    }

    func tick() {
        let now = Date()
        defer { refreshToday(now) }

        if settings.isPaused { return pause(.paused, at: now) }
        if screenLocked || asleep { return pause(.away, at: now) }

        let idle = Idle.secondsSinceLastInput()
        if idle >= settings.idleThreshold && !(settings.countMediaAsActive && Idle.isDisplaySleepPrevented()) {
            return pause(.idle, at: now)
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleID = app.bundleIdentifier ?? app.executableURL?.lastPathComponent ?? "unknown"
        if bundleID == "com.apple.loginwindow" || bundleID == "com.apple.ScreenSaver.Engine" {
            return pause(.away, at: now)
        }
        // Looking at our own statistics is not worth recording.
        if bundleID == Bundle.main.bundleIdentifier { return }

        var sample = Sample(bundleID: bundleID, appName: app.localizedName ?? bundleID)
        if settings.recordTitles {
            sample.title = String(WindowTitle.focusedWindowTitle(of: app.processIdentifier).prefix(300))
        }
        if settings.recordURLs && BrowserURL.isBrowser(bundleID) {
            sample.url = String(BrowserURL.currentURL(bundleID: bundleID).prefix(2000))
        }

        do {
            try store.record(sample, at: now, interval: Self.interval)
            lastError = nil
        } catch {
            lastError = "Не удалось записать: \(error)"
        }
        current = sample
        state = .active
    }

    private func pause(_ newState: State, at time: Date) {
        do {
            try store.endStreak(at: time)
        } catch {
            lastError = "Не удалось записать: \(error)"
        }
        current = nil
        state = newState
    }

    private func refreshToday(_ now: Date) {
        if let total = try? store.total(on: now) { todayTotal = total }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func on(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (Tracker) -> Void) {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                action(self)
                self.tick()
            }
            observers.append((center, observer))
        }

        on(workspace, NSWorkspace.willSleepNotification) { $0.asleep = true }
        on(workspace, NSWorkspace.didWakeNotification) { $0.asleep = false }
        on(workspace, NSWorkspace.screensDidSleepNotification) { $0.asleep = true }
        on(workspace, NSWorkspace.screensDidWakeNotification) { $0.asleep = false }
        on(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.screenLocked = true }
        on(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.screenLocked = false }
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        // Record app switches immediately instead of waiting for the next tick.
        on(workspace, NSWorkspace.didActivateApplicationNotification) { _ in }
    }
}
