import AppKit
import ApplicationServices
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
    let sampler: SystemSampler
    let databaseURL: URL
    let startupError: String?

    private init() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2   // weeks start on Monday
        let days = DayCalendar(calendar: calendar)

        typealias Stores = (recorder: ActivityStore, reader: ActivityStore, systemRecorder: SystemStore,
                            systemReader: SystemStore)
        func open(_ url: URL) throws -> Stores {
            (try ActivityStore(path: url.path, days: days), try ActivityStore(path: url.path, days: days),
             try SystemStore(path: url.path, days: days), try SystemStore(path: url.path, days: days))
        }

        // Several connections to one file: writers (tracker on the main thread, system sampler in the background)
        // and readers for building reports in the background.
        var url: URL
        var stores: Stores
        var problem: String?
        do {
            url = try ActivityStore.defaultURL()
            stores = try open(url)
        } catch {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("ActivityTracker-fallback.sqlite")
            stores = try! open(url)
            problem = L.tr("Основная база недоступна (\(error)). Данные пишутся во временный файл.", "The main database is unavailable (\(error)). Data goes to a temporary file.")
        }
        databaseURL = url
        startupError = problem

        settings = Settings()
        L.current = L.resolve(settings.language)
        tracker = Tracker(store: stores.recorder, settings: settings)
        menuStats = StatsModel(store: stores.reader, systemStore: stores.systemReader)
        windowStats = StatsModel(store: stores.reader, systemStore: stores.systemReader)
        updater = Updater(settings: settings)
        sampler = SystemSampler(store: stores.systemRecorder)
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
        // Every Accessibility call to another app gives up after half a second (default: 6 s per call), so a
        // hung app can't stall the tracker.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        let services = AppServices.shared
        services.settings.firstRunSetup()
        services.tracker.start()
        services.sampler.start()
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
                .id(settings.language)   // rebuild every text when the language changes
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
