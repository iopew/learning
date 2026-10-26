import BackgroundTasks
import SwiftUI
import ActivityCore

@main
struct ActivityPhoneApp: App {
    nonisolated static let refreshTask = "com.iopew.ActivityPhone.refresh"

    @StateObject private var model = PhoneModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        L.current = L.resolve(.system)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTask, using: nil) { task in
            Self.handleRefresh(task)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    if url.isFileURL { model.importFile(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.sync() }
            case .background:
                model.recordMeter()
                Self.scheduleRefresh()
            default:
                break
            }
        }
    }

    /// iOS decides when (usually a few times a day); each wake takes a battery/traffic reading and tries the Mac.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        let work = Task { @MainActor in
            await PhoneModel.shared.sync()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            MacView()
                .tabItem { Label("Mac", systemImage: "laptopcomputer") }
            IPhoneView()
                .tabItem { Label("iPhone", systemImage: "iphone") }
            SettingsTab()
                .tabItem { Label(L.tr("Настройки", "Settings"), systemImage: "gear") }
        }
    }
}
