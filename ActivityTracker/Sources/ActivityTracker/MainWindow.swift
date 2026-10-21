import AppKit
import SwiftUI
import ActivityCore

/// The full application window. Built with AppKit so it can be opened from anywhere (menu bar window, Dock,
/// Finder/Launchpad reopen). While it is open the app shows up in the Dock and ⌘-Tab like a normal app.
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Decided here, while the launch Apple Event is current; used by the adoption hand-over too.
        Self.launchedByUser = shouldOpenWindowAtLaunch()
        guard !Installer.isHandingOver else { return }
        AppServices.shared.settings.applyAppearance()
        MainWindowController.shared.applyDockPolicy()
        if Self.launchedByUser { MainWindowController.shared.show() }
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
        // The user quitting from the window (⌘Q on any layout, or the app menu): close the window and keep
        // recording. Only the "Выйти" buttons stop the tracker.
        if MainWindowController.shared.isVisible {
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

    @State private var showSettings = false

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
                        showSettings = true
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
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
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        UpdateBanner()
                        StatsControls()
                        if let report = stats.report {
                            ReportOverview(report: report, style: .wide)
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
                        ReportLists(report: report)
                            .padding(20)
                    }
                }
                .frame(width: 400)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { stats.reload() }
        .onReceive(tracker.$todayTotal) { _ in
            if MainWindowController.shared.isVisible { stats.refreshIfLive() }
        }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 0) {
                SettingsView(databaseURL: databaseURL)
                Divider()
                HStack {
                    Spacer()
                    Button("Готово") { showSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 520, height: 640)
            .environmentObject(settings)
            .environmentObject(updater)
        }
    }
}
