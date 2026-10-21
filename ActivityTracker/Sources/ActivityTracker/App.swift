import AppKit
import SwiftUI
import ActivityCore

/// Long-lived objects shared by the scene and the views.
final class AppServices {
    static let shared = AppServices()

    let settings: Settings
    let tracker: Tracker
    let stats: StatsModel
    let databaseURL: URL
    let startupError: String?

    private init() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2   // weeks start on Monday
        let days = DayCalendar(calendar: calendar)

        // Two connections to one file: the tracker writes on the main thread, reports are built in the background.
        func open(_ url: URL) throws -> (ActivityStore, ActivityStore) {
            (try ActivityStore(path: url.path, days: days), try ActivityStore(path: url.path, days: days))
        }

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
        stats = StatsModel(store: reader)
    }
}

@main
struct ActivityTrackerApp: App {
    @StateObject private var tracker = AppServices.shared.tracker
    @StateObject private var stats = AppServices.shared.stats
    @StateObject private var settings = AppServices.shared.settings

    init() {
        // `ActivityTracker --probe`: print what the collectors see and exit, without any UI.
        if CommandLine.arguments.contains("--probe") {
            exit(Probe.run())
        }

        let services = AppServices.shared
        services.settings.firstRunSetup()
        services.tracker.start()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            services.tracker.stop()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(databaseURL: AppServices.shared.databaseURL, startupError: AppServices.shared.startupError)
                .environmentObject(tracker)
                .environmentObject(stats)
                .environmentObject(settings)
        } label: {
            Text("\(Image(systemName: statusSymbol)) \(Format.duration(tracker.todayTotal))")
        }
        .menuBarExtraStyle(.window)
    }

    private var statusSymbol: String {
        switch tracker.state {
        case .active: return "clock"
        case .idle: return "moon.zzz"
        case .paused: return "pause.circle"
        case .away: return "lock"
        }
    }
}
