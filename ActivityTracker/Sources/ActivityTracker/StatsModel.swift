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
    @Published private(set) var error: String?

    let days: DayCalendar
    private let store: ActivityStore
    private let systemStore: SystemStore
    private let queue = DispatchQueue(label: "ActivityTracker.stats", qos: .userInitiated)
    private var generation = 0
    private var lastLoad = Date.distantPast
    /// True while the user looks at "today" (not a past period): the anchor then moves on at midnight.
    private var followsToday = true
    /// The usual day changes once a day; only touched on `queue`.
    private var baselineCache: (day: String, baseline: UsageBaseline)?

    init(store: ActivityStore, systemStore: SystemStore) {
        self.store = store
        self.systemStore = systemStore
        self.days = store.days
        for name in [Notification.Name.activityDataChanged, .languageChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
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
        let request = (generation: generation, range: range, anchor: anchor, today: followsToday)
        queue.async { [self] in
            let result = Result { () -> (Report, SystemReport, [Recommendation]) in
                let report = try store.report(range: request.range, anchor: request.anchor)
                let system = try systemStore.report(range: request.range, anchor: request.anchor)
                var tips: [Recommendation] = []
                if request.today {
                    tips = try todayTips(dayReport: request.range == .day ? report : nil,
                                         daySystem: request.range == .day ? system : nil)
                }
                return (report, system, tips)
            }
            DispatchQueue.main.async {
                guard request.generation == self.generation else { return }   // a newer request is in flight
                switch result {
                case .success(let (report, system, tips)):
                    self.report = report
                    self.system = system
                    self.tips = tips
                    self.error = nil
                case .failure(let error):
                    self.error = L.tr("Не удалось построить отчёт: \(error)", "Could not build the report: \(error)")
                }
            }
        }
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
