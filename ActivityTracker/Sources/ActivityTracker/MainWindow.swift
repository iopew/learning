import AppKit
import SwiftUI
import ActivityCore

/// The full application window. Built with AppKit so it can be opened from anywhere (menu bar window, Dock,
/// Finder/Launchpad reopen). While it is open the app shows up in the Dock and ⌘-Tab like a normal app.
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    /// On screen or minimized to the Dock.
    var isOpen: Bool { window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Right after an .accessory → .regular switch the menu bar can keep the previous app's menus;
        // activating once more on the next run loop pass fixes it.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        window?.close()
    }

    /// Dock icon only while the window is open, unless the user wants it always.
    func applyDockPolicy() {
        let inDock = AppServices.shared.settings.alwaysShowInDock || isVisible
        NSApp.setActivationPolicy(inDock ? .regular : .accessory)
    }

    func windowWillClose(_ notification: Notification) {
        // The window is still visible during this callback.
        DispatchQueue.main.async { self.applyDockPolicy() }
    }

    private func makeWindow() -> NSWindow {
        let services = AppServices.shared
        let root = MainWindowView(databaseURL: services.databaseURL, startupError: services.startupError)
            .environmentObject(services.tracker)
            .environmentObject(services.windowStats)
            .environmentObject(services.settings)
            .environmentObject(services.updater)
            .environmentObject(services.ui)
            .environmentObject(services.insights)
            .environmentObject(services.stability)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = "ActivityTracker"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("ActivityTrackerMainWindow")
        return window
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var allowQuit = false
    /// The app was started by hand (not at login, not by the updater in the background).
    static var launchedByUser = false

    /// Quit and stop recording (the "Выйти" buttons). ⌘Q in the main window only closes the window.
    static func quitForReal() {
        allowQuit = true
        NSApp.terminate(nil)
    }

    /// Starts a fresh instance (it waits until this one is gone, then opens the window) and quits.
    static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path, "--args", "--wait-for-pid", "\(getpid())", "--show-window"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("ActivityTracker: restart: \(error)")
            return
        }
        quitForReal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Decided here, while the launch Apple Event is current; used by the adoption hand-over too.
        Self.launchedByUser = shouldOpenWindowAtLaunch()
        guard !Installer.isHandingOver else { return }
        AppServices.shared.settings.applyAppearance()
        MainWindowController.shared.applyDockPolicy()
        if Self.launchedByUser { MainWindowController.shared.show() }
    }

    /// A saved database dropped on the app icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "activitytracker" {
                CLI.handle(url: url)
            } else if url.pathExtension.lowercased() == "sqlite" {
                ArchiveSession.open(url)
            }
        }
    }

    /// Double-click in Finder / Launchpad / Dock while already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.allowQuit { return .terminateNow }
        // Logout, shutdown and the update installer ask to quit with an Apple Event: always obey.
        if NSAppleEventManager.shared().currentAppleEvent?.eventID == AEEventID(kAEQuitApplication) {
            return .terminateNow
        }
        // A held ⌘Q repeats: the first press closed the window, the repeats must not quit for real.
        if let event = NSApp.currentEvent, event.type == .keyDown, event.isARepeat {
            return .terminateCancel
        }
        // The user quitting from the window (⌘Q on any layout, or the app menu): close the window and keep
        // recording. Only the "Выйти" buttons stop the tracker.
        if MainWindowController.shared.isOpen {
            MainWindowController.shared.close()
            return .terminateCancel
        }
        return .terminateNow
    }

    /// Manual launches open the window; launches at login and restarts after an update stay in the menu bar.
    private func shouldOpenWindowAtLaunch() -> Bool {
        if CommandLine.arguments.contains("--show-window") { return true }
        if CommandLine.arguments.contains("--background") { return false }
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return false
        }
        // Started together with the system (login item): don't pop a window at the user.
        return ProcessInfo.processInfo.systemUptime > 300
    }
}

struct MainWindowView: View {
    let databaseURL: URL
    let startupError: String?

    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var stats: StatsModel
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var updater: Updater

    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var insights: InsightsModel

    enum Pane: String, CaseIterable, Identifiable {
        case activity, rhythm, compare, battery, system, network, stability, tips

        var id: String { rawValue }

        var title: String {
            switch self {
            case .activity: return L.tr("Активность", "Activity")
            case .rhythm: return L.tr("Ритм", "Rhythm")
            case .compare: return L.tr("Сравнение", "Compare")
            case .battery: return L.tr("Батарея", "Battery")
            case .system: return L.tr("Система", "System")
            case .network: return L.tr("Сеть", "Network")
            case .stability: return L.tr("Стабильность", "Stability")
            case .tips: return L.tr("Советы", "Tips")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                StatusHeader(large: true)
                    .frame(maxWidth: 420)
                Spacer()
                HStack(spacing: 10) {
                    PauseButton()
                    ForgetMenu()
                    Button {
                        ui.windowShowsSettings = true
                    } label: {
                        Label(L.tr("Настройки", "Settings"), systemImage: "gearshape")
                    }
                    QuitButton()
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            if let startupError {
                Text(startupError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            Picker(L.tr("Раздел", "Section"), selection: $ui.windowPane) {
                ForEach(Pane.allCases) { item in
                    Text(item.title + (item == .tips && !stats.tips.isEmpty ? " (\(stats.tips.count))" : "")).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 820)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            Divider()
            switch ui.windowPane {
            case .activity: activity
            case .rhythm: RhythmPane()
            case .compare: ComparisonPane()
            case .stability: StabilityPane()
            case .network: NetworkPane()
            case .battery:
                single {
                    if let system = stats.system { BatteryPanel(system: system, chartHeight: 220) }
                    if let machine = stats.machine { BatteryDetails(machine: machine) }
                }
            case .system:
                single {
                    if let system = stats.system { SystemPanel(system: system, chartHeight: 200) }
                    if let machine = stats.machine { SystemDetails(machine: machine) }
                }
            case .tips:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.tr("Советы на сегодня", "Tips for today")).font(.title3.weight(.semibold))
                        TipsPanel(tips: stats.tips)
                        Text(L.tr("Советы считаются только на этом Mac по твоей же истории: сегодня против обычного дня за последние две недели.",
                                  "Tips are computed on this Mac from your own history: today against your usual day over the last two weeks."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .id(settings.language)   // rebuild every text when the language changes
        .onAppear { stats.reload() }
        .onReceive(tracker.$todayTotal) { _ in
            if MainWindowController.shared.isVisible { stats.refreshIfLive() }
        }
        .background(Color.clear.sheet(item: $insights.trend) { card in
            TrendSheet(card: card) { insights.trend = nil }
        })
        .sheet(isPresented: $ui.windowShowsSettings) {
            VStack(spacing: 0) {
                SettingsView(databaseURL: databaseURL)
                Divider()
                HStack {
                    Spacer()
                    Button(L.tr("Готово", "Done")) { ui.windowShowsSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 520, height: 640)
            .environmentObject(settings)
            .environmentObject(updater)
            .environmentObject(ui)
        }
    }

    /// Statistics: charts on the left, lists on the right.
    private var activity: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    UpdateBanner()
                    StatsControls()
                    HStack {
                        Spacer()
                        ExportMenu()
                    }
                    if let report = stats.report {
                        DaySummaryCard(lines: stats.daySummary)
                        ReportOverview(report: report, style: .wide)
                        if let switches = stats.switches {
                            SwitchesCard(stats: switches, lastHour: stats.lastHourSwitches,
                                         usualPerHour: stats.usualSwitchesPerHour)
                        }
                    } else {
                        ReportPlaceholder()
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 500, maxWidth: .infinity)
            Divider()
            ScrollView {
                if let report = stats.report {
                    ReportLists(report: report, onTrend: { target, name in insights.showTrend(target, name: name) })
                        .padding(20)
                }
            }
            .frame(width: 400)
        }
    }

    /// One scrolling column with the period controls on top (battery, system).
    private func single<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatsControls()
                content()
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
