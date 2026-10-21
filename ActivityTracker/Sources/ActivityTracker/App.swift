import AppKit
import SwiftUI
import ActivityCore

/// Long-lived objects shared by the scenes and the views.
final class AppServices {
    static let shared = AppServices()

    let settings: Settings
    let tracker: Tracker
    /// Separate report state for the menu bar window and the main window (each has its own period selection).
    let menuStats: StatsModel
    let windowStats: StatsModel
    let updater: Updater
    let databaseURL: URL
    let startupError: String?

    private init() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2   // weeks start on Monday
        let days = DayCalendar(calendar: calendar)

        func open(_ url: URL) throws -> (ActivityStore, ActivityStore) {
            (try ActivityStore(path: url.path, days: days), try ActivityStore(path: url.path, days: days))
        }

        // Two connections to one file: the tracker writes on the main thread, reports are built in the background.
        var url: URL
        var stores: (recorder: ActivityStore, reader: ActivityStore)
        var problem: String?
        do {
            url = try ActivityStore.defaultURL()
            stores = try open(url)
        } catch {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("ActivityTracker-fallback.sqlite")
            stores = try! open(url)
            problem = "Основная база недоступна (\(error)). Данные пишутся во временный файл."
        }
        databaseURL = url
        startupError = problem
        let (recorder, reader) = stores

        settings = Settings()
        tracker = Tracker(store: recorder, settings: settings)
        menuStats = StatsModel(store: reader)
        windowStats = StatsModel(store: reader)
        updater = Updater(settings: settings)
    }
}

@main
struct ActivityTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var tracker = AppServices.shared.tracker
    @StateObject private var stats = AppServices.shared.menuStats
    @StateObject private var settings = AppServices.shared.settings
    @StateObject private var updater = AppServices.shared.updater

    init() {
        let arguments = CommandLine.arguments
        func argument(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        // Command-line modes: do one job and exit, without any UI.
        if arguments.contains("--probe") {
            exit(Probe.run())
        }
        if let target = argument(after: "--install-update") {
            exit(Installer.runInstallMode(target: URL(fileURLWithPath: target)))
        }
        if let zip = argument(after: "--update-from-zip") {
            exit(Installer.updateFromZip(URL(fileURLWithPath: zip)))
        }

        // A hand-installed (ad-hoc signed) copy re-signs itself once with the stable local identity and restarts.
        // A manual launch (not at login, not a background restart) should end with the window open.
        let manualLaunch = !arguments.contains("--background") && ProcessInfo.processInfo.systemUptime > 300
        if Installer.adoptIfNeeded(showWindow: manualLaunch) {
            Installer.isHandingOver = true
            // Normally the installer quits this process within seconds. If it never does, carry on as usual
            // rather than sit there not recording.
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                guard Installer.isHandingOver else { return }
                Installer.log("adoption: installer did not take over, starting normally")
                Installer.isHandingOver = false
                Self.startServices()
                AppServices.shared.settings.applyAppearance()
                MainWindowController.shared.applyDockPolicy()
            }
            return
        }
        Self.startServices()
    }

    private static func startServices() {
        let services = AppServices.shared
        services.settings.firstRunSetup()
        services.tracker.start()
        services.updater.start()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            services.tracker.stop()
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarShown) {
            PopoverView(databaseURL: AppServices.shared.databaseURL, startupError: AppServices.shared.startupError)
                .environmentObject(tracker)
                .environmentObject(stats)
                .environmentObject(settings)
                .environmentObject(updater)
        } label: {
            if settings.menuBarStyle == .time {
                Text(Format.duration(tracker.todayTotal))
            } else {
                Image(systemName: statusSymbol)
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// The item disappears when the user picks "Скрыть" (or ⌘-drags it out of the menu bar).
    private var menuBarShown: Binding<Bool> {
        Binding(
            get: { settings.menuBarStyle != .hidden },
            set: { shown in if !shown { settings.menuBarStyle = .hidden } })
    }

    private var statusSymbol: String {
        switch tracker.state {
        case .active: return "clock"
        case .idle: return "moon.zzz"
        case .paused: return "pause.circle"
        case .away: return "lock"
        case .privateWindow: return "eye.slash"
        }
    }
}
