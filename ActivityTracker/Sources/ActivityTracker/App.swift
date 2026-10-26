import AppKit
import ApplicationServices
import SwiftUI
import ActivityCore

/// Which screen is open where. Lives outside the views so that rebuilding them (language switch) keeps it.
final class UIState: ObservableObject {
    @Published var popoverShowsSettings = false
    @Published var windowShowsSettings = false
    @Published var windowPane: MainWindowView.Pane = .activity
}

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
    let notifier: Notifier
    let insights: InsightsModel
    let stability: StabilityMonitor
    let network: NetworkMonitor
    /// For writing and for the reports of the network history.
    let networkStore: NetworkStore
    /// A reader connection for database tools (size, download, compact).
    let database: ActivityStore
    /// The writer of the battery/system history (for the hourly roll-up).
    let systemStore: SystemStore
    /// Sleep, sleep blockers, startup items, folder sizes, SSD writes.
    let machineStore: MachineStore
    let machine: MachineMonitor
    /// The day boundary in use (settings.dayStartHour as it was at launch).
    let days: DayCalendar
    let ui = UIState()
    let databaseURL: URL
    let startupError: String?

    /// The history (titles, addresses, Wi-Fi names) is readable by this user only: folder 700, files 600.
    static func restrictPermissions(of database: URL) {
        let manager = FileManager.default
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: database.deletingLastPathComponent().path)
        for suffix in ["", "-wal", "-shm"] where manager.fileExists(atPath: database.path + suffix) {
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path + suffix)
        }
    }

    private init() {
        settings = Settings()
        L.current = L.resolve(settings.language)

        var calendar = Calendar.current
        calendar.firstWeekday = 2   // weeks start on Monday
        let days = DayCalendar(calendar: calendar, startHour: settings.dayStartHour)
        self.days = days

        typealias Stores = (recorder: ActivityStore, reader: ActivityStore, systemRecorder: SystemStore,
                            systemReader: SystemStore, network: NetworkStore, machine: MachineStore)
        func open(_ url: URL) throws -> Stores {
            (try ActivityStore(path: url.path, days: days), try ActivityStore(path: url.path, days: days),
             try SystemStore(path: url.path, days: days), try SystemStore(path: url.path, days: days),
             try NetworkStore(path: url.path, days: days), try MachineStore(path: url.path, days: days))
        }

        // Several connections to one file: writers (tracker on the main thread, system sampler in the background)
        // and readers for building reports in the background.
        var url: URL
        var stores: Stores
        var problem: String?
        var isFallback = false
        do {
            url = try ActivityStore.defaultURL()
            // Another process may hold the file for a moment (an update finishing): try a few times.
            var attempt = 0
            while true {
                do {
                    stores = try open(url)
                    break
                } catch {
                    attempt += 1
                    if attempt >= 3 { throw error }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            Self.restrictPermissions(of: url)
        } catch {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("ActivityTracker-fallback.sqlite")
            stores = try! open(url)
            isFallback = true
            problem = L.tr("Основная база недоступна (\(error)). Данные пишутся во временный файл.", "The main database is unavailable (\(error)). Data goes to a temporary file.")
        }
        // The day boundary changed since the data was written: move every row to its new day once (never on the
        // temporary fallback file: the real database still needs it next time).
        let appliedKey = "dayStartHourApplied"
        if !isFallback, UserDefaults.standard.integer(forKey: appliedKey) != days.startHour {
            do {
                let moved = try stores.recorder.rekeyDays() + stores.systemRecorder.rekeyDays() + stores.network.rekeyDays()
                    + stores.machine.rekeyDays()
                UserDefaults.standard.set(days.startHour, forKey: appliedKey)
                NSLog("ActivityTracker: day boundary \(days.startHour):00, \(moved) rows moved")
            } catch {
                problem = problem ?? L.tr("Не удалось пересчитать дни: \(error)", "Could not recompute days: \(error)")
            }
        }
        databaseURL = url
        startupError = problem

        tracker = Tracker(store: stores.recorder, settings: settings)
        networkStore = stores.network
        database = stores.reader
        systemStore = stores.systemRecorder
        machineStore = stores.machine
        machine = MachineMonitor(store: stores.machine)
        menuStats = StatsModel(store: stores.reader, systemStore: stores.systemReader, networkStore: stores.network)
        windowStats = StatsModel(store: stores.reader, systemStore: stores.systemReader, networkStore: stores.network,
                                 machineStore: stores.machine)
        updater = Updater(settings: settings)
        sampler = SystemSampler(store: stores.systemRecorder, machine: stores.machine)
        insights = InsightsModel(store: stores.reader)
        notifier = Notifier(store: stores.reader, systemStore: stores.systemReader, settings: settings)
        stability = StabilityMonitor(path: url.path, days: days)
        network = NetworkMonitor(store: stores.network)
    }
}

@main
struct ActivityTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Only settings are observed here: every change re-evaluates the whole scene and rebuilds the main menu, so
    /// objects that change every tick (tracker, stats, updater) are observed by the views inside, not by the App.
    @StateObject private var settings = AppServices.shared.settings

    init() {
        // Everything the app creates (database, exports, logs) is private to this user.
        umask(0o077)
        let arguments = CommandLine.arguments
        func argument(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        // Command-line modes: do one job and exit, without any UI.
        if let index = arguments.firstIndex(of: "--cli") {
            exit(CLI.run(Array(arguments[(index + 1)...])))
        }
        if arguments.contains("--probe") {
            exit(Probe.run())
        }
        if let target = argument(after: "--install-update") {
            exit(Installer.runInstallMode(target: URL(fileURLWithPath: target)))
        }
        if let zip = argument(after: "--update-from-zip") {
            exit(Installer.updateFromZip(URL(fileURLWithPath: zip)))
        }

        // Restart (after changing the day boundary): let the previous instance quit before touching the database.
        if let pidText = argument(after: "--wait-for-pid"), let pid = pid_t(pidText) {
            let deadline = Date().addingTimeInterval(15)
            while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
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
        services.tracker.onTick = { [weak notifier = services.notifier] state, bundleID, now in
            notifier?.trackerTicked(state: state, bundleID: bundleID, now: now)
        }
        services.notifier.start()
        CLI.listen()
        services.stability.start()
        services.network.start()
        services.machine.start()
        removePhoneLeftovers()
        ArchiveSession.removeLeftovers()
        scheduleRollUp()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            services.tracker.stop()
        }
    }

    /// Builds 24–28 had an iPhone companion (removed in build 29): its pairing key and the downloaded iPhone source
    /// with build products are deleted (nothing to do once they are gone).
    private static func removePhoneLeftovers() {
        DispatchQueue.global(qos: .background).async {
            guard let folder = try? ActivityStore.defaultURL().deletingLastPathComponent() else { return }
            for name in ["phone-pairing.json", "iphone-src"] {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            UserDefaults.standard.removeObject(forKey: "phoneLastInstall")
            UserDefaults.standard.removeObject(forKey: "phoneTeamID")
        }
    }

    /// Once a day (first 3 minutes after start): minutes of battery/system and network history older than 90 days
    /// become hourly rows. Keeps the database at tens of MB a year instead of hundreds.
    private static func scheduleRollUp() {
        let services = AppServices.shared
        let queue = DispatchQueue(label: "ActivityTracker.maintenance", qos: .background)
        func run() {
            queue.async {
                let days = services.days
                let cutoff = days.addingDays(-90, to: days.startOfDay(Date()))
                do {
                    let system = try services.systemStore.rollUp(before: cutoff)
                    let network = try services.networkStore.rollUp(before: cutoff)
                    if system + network > 0 { NSLog("ActivityTracker: rolled up \(system) system and \(network) network minutes") }
                } catch {
                    NSLog("ActivityTracker: roll-up: \(error)")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { run() }
        let timer = Timer(timeInterval: 24 * 3600, repeats: true) { _ in run() }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarShown) {
            PopoverView(databaseURL: AppServices.shared.databaseURL, startupError: AppServices.shared.startupError)
                .id(settings.language)   // rebuild every text when the language changes
                .environmentObject(AppServices.shared.tracker)
                .environmentObject(AppServices.shared.menuStats)
                .environmentObject(settings)
                .environmentObject(AppServices.shared.updater)
                .environmentObject(AppServices.shared.ui)
        } label: {
            MenuBarLabel(tracker: AppServices.shared.tracker, settings: settings)
        }
        .menuBarExtraStyle(.window)
    }

    /// The item disappears when the user picks "Скрыть". Read-only on purpose: SwiftUI calls the setter whenever
    /// the status item's visibility changes, and writing the setting back from there re-evaluated the scene, which
    /// changed the visibility again — an endless loop that froze the app (build 8, `sample` showed it).
    private var menuBarShown: Binding<Bool> {
        Binding(get: { settings.menuBarStyle != .hidden }, set: { _ in })
    }
}

/// The menu bar item itself. A separate view so that the 5-second tracker updates redraw only the label.
private struct MenuBarLabel: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var settings: Settings

    var body: some View {
        if settings.menuBarStyle == .time {
            Text(Format.duration(tracker.todayTotal))
        } else {
            Image(systemName: statusSymbol)
        }
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
