import Foundation
import ActivityCore

/// Data for the Rhythm and Compare panes and the trend card. Built on a background queue with the reader connection,
/// only while a pane is open.
final class InsightsModel: ObservableObject {
    enum ComparisonMode: String, CaseIterable, Identifiable {
        case week, month, weekdays

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return L.tr("7 дней к прошлым 7", "7 days vs previous 7")
            case .month: return L.tr("30 дней к прошлым 30", "30 days vs previous 30")
            case .weekdays: return L.tr("Будни и выходные", "Weekdays vs weekends")
            }
        }

        var sideTitles: (String, String) {
            switch self {
            case .week: return (L.tr("Последние 7 дней", "Last 7 days"), L.tr("7 дней до них", "7 days before"))
            case .month: return (L.tr("Последние 30 дней", "Last 30 days"), L.tr("30 дней до них", "30 days before"))
            case .weekdays: return (L.tr("Будни", "Weekdays"), L.tr("Выходные", "Weekends"))
            }
        }
    }

    struct TrendCard: Identifiable {
        var target: UsageTarget
        var name: String
        var trend: UsageTrend?
        var titles: [TitleUsage] = []
        var error: String?

        var id: String { target.id }
    }

    @Published var rhythmDays = 30 {
        didSet { if rhythmDays != oldValue { reloadRhythm() } }
    }
    @Published private(set) var rhythm: RhythmSummary?
    /// The last 53 weeks, day by day (year calendar).
    @Published private(set) var year: [DayStat] = []
    @Published var comparisonMode: ComparisonMode = .week {
        didSet { if comparisonMode != oldValue { reloadComparison() } }
    }
    @Published private(set) var comparison: UsageComparison?
    @Published var trend: TrendCard?
    @Published private(set) var error: String?

    let days: DayCalendar
    private let store: ActivityStore
    private let queue = DispatchQueue(label: "ActivityTracker.insights", qos: .userInitiated)
    private var rhythmGeneration = 0
    private var comparisonGeneration = 0

    init(store: ActivityStore) {
        self.store = store
        self.days = store.days
        NotificationCenter.default.addObserver(forName: .activityDataChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if rhythm != nil { reloadRhythm() }
            if comparison != nil { reloadComparison() }
        }
    }

    private func fail(_ error: Error) {
        DispatchQueue.main.async {
            self.error = L.tr("Не удалось построить отчёт: \(error)", "Could not build the report: \(error)")
        }
    }

    func reloadRhythm() {
        rhythmGeneration += 1
        let generation = rhythmGeneration
        let count = rhythmDays
        queue.async { [self] in
            do {
                let today = days.startOfDay(Date())
                let yearStart = days.addingDays(-52 * 7, to: days.startOfWeek(today))
                let stats = try store.dayStats(from: yearStart, to: today)
                let from = days.addingDays(-(count - 1), to: today)
                let summary = RhythmSummary.make(stats.filter { $0.day >= from }, days: days)
                DispatchQueue.main.async {
                    guard generation == self.rhythmGeneration else { return }
                    self.rhythm = summary
                    self.year = stats
                    self.error = nil
                }
            } catch {
                fail(error)
            }
        }
    }

    func reloadComparison() {
        comparisonGeneration += 1
        let generation = comparisonGeneration
        let mode = comparisonMode
        queue.async { [self] in
            do {
                let today = days.startOfDay(Date())
                let result: UsageComparison
                switch mode {
                case .week, .month:
                    let length = mode == .week ? 7 : 30
                    let firstStart = days.addingDays(-(length - 1), to: today)
                    let secondStart = days.addingDays(-length, to: firstStart)
                    let usage = try store.dailyUsage(from: secondStart, to: today)
                    result = UsageComparison.make(
                        first: usage.filter { $0.day >= firstStart }, firstDays: length,
                        second: usage.filter { $0.day < firstStart }, secondDays: length)
                case .weekdays:
                    let start = days.addingDays(-29, to: today)
                    let usage = try store.dailyUsage(from: start, to: today)
                    var weekdayCount = 0
                    var weekendCount = 0
                    var day = start
                    while day <= today {
                        if days.isWeekend(day) { weekendCount += 1 } else { weekdayCount += 1 }
                        day = days.addingDays(1, to: day)
                    }
                    result = UsageComparison.make(
                        first: usage.filter { !days.isWeekend($0.day) }, firstDays: weekdayCount,
                        second: usage.filter { days.isWeekend($0.day) }, secondDays: weekendCount)
                }
                DispatchQueue.main.async {
                    guard generation == self.comparisonGeneration else { return }
                    self.comparison = result
                    self.error = nil
                }
            } catch {
                fail(error)
            }
        }
    }

    /// 90 days of one app or site.
    func showTrend(_ target: UsageTarget, name: String) {
        trend = TrendCard(target: target, name: name)
        queue.async { [self] in
            var card = TrendCard(target: target, name: name)
            do {
                let today = days.startOfDay(Date())
                let from = days.addingDays(-89, to: today)
                let history = try store.usageHistory(of: target, from: from, to: today)
                card.trend = UsageTrend.make(daily: history.daily, from: from, to: today, days: days)
                card.titles = history.titles
            } catch {
                card.error = "\(error)"
            }
            DispatchQueue.main.async {
                guard self.trend?.target == target else { return }   // closed or another one opened
                self.trend = card
            }
        }
    }
}
