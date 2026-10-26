import Foundation
import ActivityCore

/// Selected period + its reports (activity, battery/system) and today's tips. Built on a background queue with
/// the reader connections.
final class StatsModel: ObservableObject {
    @Published var range: StatsRange = .day {
        didSet { if range != oldValue { reload() } }
    }
    @Published private(set) var anchor = Date()
    @Published private(set) var report: Report?
    @Published private(set) var system: SystemReport?
    @Published private(set) var tips: [Recommendation] = []
    /// Switching between apps in the period (only for periods up to 30 days: longer ones would be heavy).
    @Published private(set) var switches: SwitchStats?
    /// Today only: switches in the last 60 minutes, and the usual rate per hour over the previous two weeks.
    @Published private(set) var lastHourSwitches: Int?
    @Published private(set) var usualSwitchesPerHour: Double?
    @Published private(set) var network: NetworkReport?
    /// The day in words (day view only).
    @Published private(set) var daySummary: [String] = []
    /// Battery and System pane details; only for the main window and saved databases (not the menu bar window).
    @Published private(set) var machine: MachineReport?
    @Published private(set) var error: String?

    let days: DayCalendar
    private let store: ActivityStore
    private let systemStore: SystemStore
    private let networkStore: NetworkStore
    private let machineStore: MachineStore?
    /// The wear and disk forecasts look at the whole history: once a day. Only touched on `queue`.
    private var forecastCache: (day: String, battery: BatteryForecast, disk: DiskForecast?)?
    private let queue = DispatchQueue(label: "ActivityTracker.stats", qos: .userInitiated)
    private var generation = 0
    private var lastLoad = Date.distantPast
    /// True while the user looks at "today" (not a past period): the anchor then moves on at midnight.
    private var followsToday = true
    /// The usual day changes once a day; only touched on `queue`.
    private var baselineCache: (day: String, baseline: UsageBaseline)?
    /// The usual switches per hour; only touched on `queue`.
    private var switchBaselineCache: (day: String, perHour: Double?)?

    /// `anchor`: start on this day instead of today (a saved database: its last recorded day).
    init(store: ActivityStore, systemStore: SystemStore, networkStore: NetworkStore, machineStore: MachineStore? = nil,
         anchor: Date? = nil) {
        self.store = store
        self.systemStore = systemStore
        self.networkStore = networkStore
        self.machineStore = machineStore
        self.days = store.days
        if let anchor {
            self.anchor = anchor
            followsToday = false
        }
        for name in [Notification.Name.activityDataChanged, .languageChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                queue.async {   // deleted data must not linger in the usual day
                    self.baselineCache = nil
                    self.switchBaselineCache = nil
                }
                reload()
            }
        }
    }

    /// Called on every tracker tick while a stats view is visible. Periods that include today change as you work:
    /// the day view refreshes every tick, longer (heavier) periods at most once a minute.
    func refreshIfLive() {
        guard followsToday else { return }
        if range == .day || Date().timeIntervalSince(lastLoad) >= 60 || !isAtToday { reload() }
    }

    func reload() {
        if followsToday { anchor = Date() }   // after midnight "today" is a new day
        lastLoad = Date()
        generation += 1
        let request = (generation: generation, range: range, anchor: anchor, today: followsToday && isAtToday)
        queue.async { [self] in
            let result = Result { () -> Loaded in
                let report = try store.report(range: request.range, anchor: request.anchor)
                let system = try systemStore.report(range: request.range, anchor: request.anchor)
                // Tips are always about today, whatever period the user is looking at.
                let sameDay = request.today && request.range == .day
                let tips = try todayTips(dayReport: sameDay ? report : nil, daySystem: sameDay ? system : nil)
                var loaded = Loaded(report: report, system: system, tips: tips)
                loaded.network = try networkStore.report(range: request.range, anchor: request.anchor)
                var spans: [ActivityEvent]?
                if let length = request.range.days, length <= 30 {
                    spans = try store.spans(from: report.fromDay, to: report.toDay)
                }
                if let spans {
                    loaded.switches = Switches.stats(spans)
                    if sameDay {
                        let now = Date()
                        loaded.lastHour = Switches.stats(Switches.clip(spans, from: now.addingTimeInterval(-3600), to: now)).switches
                        loaded.usualPerHour = try switchBaseline(today: report.toDay)
                    }
                }
                if request.range == .day {
                    loaded.daySummary = DaySummary.make(report: report, switches: loaded.switches,
                                                        usualPerHour: loaded.usualPerHour, days: days)
                }
                if let machineStore {
                    loaded.machine = try machineReport(machineStore, from: report.fromDay, to: report.toDay, spans: spans)
                }
                return loaded
            }
            DispatchQueue.main.async {
                guard request.generation == self.generation else { return }   // a newer request is in flight
                switch result {
                case .success(let loaded):
                    self.report = loaded.report
                    self.system = loaded.system
                    self.tips = loaded.tips
                    self.switches = loaded.switches
                    self.lastHourSwitches = loaded.lastHour
                    self.usualSwitchesPerHour = loaded.usualPerHour
                    self.network = loaded.network
                    self.machine = loaded.machine
                    self.daySummary = loaded.daySummary
                    self.error = nil
                case .failure(let error):
                    self.error = L.tr("Не удалось построить отчёт: \(error)", "Could not build the report: \(error)")
                }
            }
        }
    }

    private struct Loaded {
        var report: Report
        var system: SystemReport
        var tips: [Recommendation]
        var switches: SwitchStats?
        var lastHour: Int?
        var usualPerHour: Double?
        var network: NetworkReport?
        var machine: MachineReport?
        var daySummary: [String] = []
    }

    /// Runs on `queue`.
    private func machineReport(_ machineStore: MachineStore, from: Date, to: Date, spans: [ActivityEvent]?) throws -> MachineReport {
        var report = MachineReport()
        if let spans {
            report.costs = BatteryCost.make(minutes: try systemStore.batteryMinutes(from: from, to: to), events: spans)
        }
        report.charges = try systemStore.chargeSessions(from: from, to: to)
        report.nights = try machineStore.nights(from: from, to: to)
        report.blockers = try machineStore.blockers(from: from, to: to)
        report.folders = try machineStore.folders()
        report.writes = try machineStore.writes(from: from, to: to)
        report.swapDaily = try systemStore.swapDaily(from: from, to: to)
        report.startup = try machineStore.startupItems(now: Date())
        let key = days.key(Date())
        if forecastCache?.day != key {
            let battery = BatteryForecast.make(daily: try systemStore.batteryHistory(), now: Date())
            let disk = try systemStore.diskDaily(days: 30, before: Date())
            forecastCache = (key, battery, disk.total > 0 ? DiskForecast.make(daily: disk.daily, total: disk.total) : nil)
        }
        report.forecast = forecastCache?.battery
        report.disk = forecastCache?.disk
        return report
    }

    /// Runs on `queue`. Computed once a day from the previous 14 days.
    private func switchBaseline(today: Date) throws -> Double? {
        let key = days.key(today)
        if let cached = switchBaselineCache, cached.day == key { return cached.perHour }
        let spans = try store.spans(from: days.addingDays(-14, to: today), to: days.addingDays(-1, to: today))
        let perHour = Switches.stats(spans).perHour
        switchBaselineCache = (key, perHour)
        return perHour
    }

    /// Runs on `queue`.
    private func todayTips(dayReport: Report?, daySystem: SystemReport?) throws -> [Recommendation] {
        let now = Date()
        let report = try dayReport ?? store.report(range: .day, anchor: now)
        let system = try daySystem ?? systemStore.report(range: .day, anchor: now)
        let key = days.key(now)
        let baseline: UsageBaseline
        if let cached = baselineCache, cached.day == key {
            baseline = cached.baseline
        } else {
            baseline = try store.baseline(before: now)
            baselineCache = (key, baseline)
        }
        let minute = Int(now.timeIntervalSince(days.startOfDay(now)) / 60)
        return Recommendations.make(RecommendationInput(
            today: report, baseline: baseline, system: system, now: now, minuteOfDay: minute))
    }

    // MARK: - Navigation

    var isAtToday: Bool { days.startOfDay(anchor) >= days.startOfDay(Date()) }
    var canStep: Bool { range.days != nil }

    /// Moves one whole period back (-1) or forward (+1), never past today.
    func step(_ direction: Int) {
        guard let length = range.days else { return }
        anchor = min(days.addingDays(direction * length, to: anchor), Date())
        followsToday = isAtToday
        reload()
    }

    func goToToday() {
        followsToday = true
        reload()
    }

    var periodTitle: String {
        let today = days.startOfDay(Date())
        let end = days.startOfDay(anchor)
        let english = L.current == .en
        switch range {
        case .day:
            if end == today { return L.tr("Сегодня", "Today") }
            if end == days.addingDays(-1, to: today) { return L.tr("Вчера", "Yesterday") }
            return Self.format(end, sameYear: english ? "EEEE, MMMM d" : "EEEE, d MMMM",
                               otherYear: english ? "MMMM d, yyyy" : "d MMMM yyyy")
        case .all:
            guard let start = report?.fromDay, report?.range == .all else { return L.tr("Всё время", "All time") }
            return L.tr("С ", "Since ") + Self.format(start, sameYear: english ? "MMMM d" : "d MMMM",
                                                      otherYear: english ? "MMMM d, yyyy" : "d MMMM yyyy")
        default:
            let start = days.addingDays(-((range.days ?? 1) - 1), to: end)
            let (short, long) = english ? ("MMM d", "MMM d, yyyy") : ("d MMM", "d MMM yyyy")
            return Self.format(start, sameYear: short, otherYear: long) + " – " + Self.format(end, sameYear: short, otherYear: long)
        }
    }

    private static func format(_ date: Date, sameYear: String, otherYear: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        formatter.dateFormat = isThisYear ? sameYear : otherYear
        return formatter.string(from: date)
    }
}

extension Notification.Name {
    /// The UI language changed: texts built in the background (tips) must be rebuilt.
    static let languageChanged = Notification.Name("ActivityTrackerLanguageChanged")
}
