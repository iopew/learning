import Foundation
import ActivityCore

/// Selected period + its report. Reports are built on a background queue with the reader connection.
final class StatsModel: ObservableObject {
    @Published var range: StatsRange = .day {
        didSet { if range != oldValue { reload() } }
    }
    @Published private(set) var anchor = Date()
    @Published private(set) var report: Report?
    @Published private(set) var error: String?

    let days: DayCalendar
    private let store: ActivityStore
    private let queue = DispatchQueue(label: "ActivityTracker.stats", qos: .userInitiated)
    private var generation = 0
    private var lastLoad = Date.distantPast
    /// True while the user looks at "today" (not a past period): the anchor then moves on at midnight.
    private var followsToday = true

    init(store: ActivityStore) {
        self.store = store
        self.days = store.days
        NotificationCenter.default.addObserver(forName: .activityDataChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
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
        let request = (generation: generation, range: range, anchor: anchor)
        queue.async { [store] in
            let result = Result { try store.report(range: request.range, anchor: request.anchor) }
            DispatchQueue.main.async {
                guard request.generation == self.generation else { return }   // a newer request is in flight
                switch result {
                case .success(let report):
                    self.report = report
                    self.error = nil
                case .failure(let error):
                    self.error = "Не удалось построить отчёт: \(error)"
                }
            }
        }
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
        switch range {
        case .day:
            if end == today { return "Сегодня" }
            if end == days.addingDays(-1, to: today) { return "Вчера" }
            return Self.format(end, sameYear: "EEEE, d MMMM", otherYear: "d MMMM yyyy")
        case .all:
            guard let start = report?.fromDay, report?.range == .all else { return "Всё время" }
            return "С " + Self.format(start, sameYear: "d MMMM", otherYear: "d MMMM yyyy")
        default:
            let start = days.addingDays(-((range.days ?? 1) - 1), to: end)
            return Self.format(start, sameYear: "d MMM", otherYear: "d MMM yyyy")
                + " – " + Self.format(end, sameYear: "d MMM", otherYear: "d MMM yyyy")
        }
    }

    private static func format(_ date: Date, sameYear: String, otherYear: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        formatter.dateFormat = isThisYear ? sameYear : otherYear
        return formatter.string(from: date)
    }
}
