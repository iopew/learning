import Foundation

/// When a day's activity began and ended, and how much there was.
public struct DayStat: Equatable, Identifiable {
    /// The day's start (DayCalendar.startOfDay).
    public var day: Date
    public var first: Date
    public var last: Date
    public var seconds: TimeInterval

    public var id: Date { day }
}

/// Time per app and per site on one day.
public struct DayUsage: Equatable {
    public var day: Date
    public var total: TimeInterval = 0
    public var apps: [String: TimeInterval] = [:]
    public var appNames: [String: String] = [:]
    public var domains: [String: TimeInterval] = [:]

    public init(day: Date) {
        self.day = day
    }
}

/// One app (by bundle ID) or one site (by domain).
public enum UsageTarget: Hashable, Identifiable {
    case app(String)
    case domain(String)

    public var id: String {
        switch self {
        case .app(let bundleID): return "app:" + bundleID
        case .domain(let domain): return "site:" + domain
        }
    }
}

public enum TitleCleaner {
    /// "(3) Go Concurrency - YouTube" → "Go Concurrency": unread counters and the site's name are noise.
    public static func clean(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("("), let close = text.firstIndex(of: ")"),
           text[text.index(after: text.startIndex)..<close].allSatisfy(\.isNumber),
           close > text.index(after: text.startIndex) {
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" - YouTube", " — YouTube", " – YouTube"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Rhythm

/// Start and end of the day by the clock, in hours from the midnight of the day's date (an end after midnight is
/// above 24: 25.5 = 01:30 the next night).
public struct RhythmPoint: Equatable, Identifiable {
    public var day: Date
    public var startHour: Double
    public var endHour: Double
    public var seconds: TimeInterval

    public var id: Date { day }
}

public struct RhythmSummary: Equatable {
    public var points: [RhythmPoint]
    /// Medians over the period.
    public var typicalStart: Double?
    public var typicalEnd: Double?
    /// The last 7 days against the days before them: positive = later, in minutes.
    public var recentStartShift: Double?
    public var recentEndShift: Double?

    /// Days shorter than this don't say when the day starts or ends (a quick look at the Mac).
    public static let minimumDay: TimeInterval = 15 * 60

    public static func make(_ stats: [DayStat], days: DayCalendar) -> RhythmSummary {
        let points = stats.filter { $0.seconds >= minimumDay }.map { stat -> RhythmPoint in
            let midnight = days.midnight(of: stat.day)
            return RhythmPoint(day: stat.day,
                               startHour: stat.first.timeIntervalSince(midnight) / 3600,
                               endHour: stat.last.timeIntervalSince(midnight) / 3600,
                               seconds: stat.seconds)
        }
        var summary = RhythmSummary(points: points, typicalStart: median(points.map(\.startHour)),
                                    typicalEnd: median(points.map(\.endHour)))
        // A shift needs a few days on both sides to mean something.
        let recent = points.suffix(7)
        let before = points.dropLast(recent.count)
        if recent.count >= 4, before.count >= 5 {
            if let new = median(recent.map(\.startHour)), let old = median(before.map(\.startHour)) {
                summary.recentStartShift = (new - old) * 60
            }
            if let new = median(recent.map(\.endHour)), let old = median(before.map(\.endHour)) {
                summary.recentEndShift = (new - old) * 60
            }
        }
        return summary
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// 25.5 → "01:30".
    public static func clock(_ hours: Double) -> String {
        let minutes = (Int((hours * 60).rounded()) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Comparing periods

public struct ComparisonRow: Equatable, Identifiable {
    public var target: UsageTarget
    public var name: String
    /// Average per day of each period.
    public var first: TimeInterval
    public var second: TimeInterval

    public var id: String { target.id }
    public var delta: TimeInterval { first - second }
    /// Appeared in the first period (meaningfully), absent in the second.
    public var isNew: Bool { second == 0 && first >= 5 * 60 }
    public var isGone: Bool { first == 0 && second >= 5 * 60 }
    var larger: TimeInterval { max(first, second) }
}

/// Two sets of days side by side: "this week vs last week", "weekdays vs weekends".
public struct UsageComparison: Equatable {
    public struct Side: Equatable {
        public var total: TimeInterval
        /// Days in the period (calendar days, recorded or not).
        public var days: Int
        public var activeDays: Int
        public var perDay: TimeInterval { days > 0 ? total / Double(days) : 0 }
    }

    public var first: Side
    public var second: Side
    public var apps: [ComparisonRow]
    public var sites: [ComparisonRow]

    /// `firstDays` / `secondDays`: how many calendar days each period has (the average is per calendar day, so a
    /// 5-day and a 2-day set compare fairly).
    public static func make(first: [DayUsage], firstDays: Int, second: [DayUsage], secondDays: Int,
                            limit: Int = 15) -> UsageComparison {
        func side(_ usage: [DayUsage], _ count: Int) -> Side {
            Side(total: usage.reduce(0) { $0 + $1.total }, days: count, activeDays: usage.filter { $0.total > 0 }.count)
        }
        func sums(_ usage: [DayUsage], _ values: (DayUsage) -> [String: TimeInterval]) -> [String: TimeInterval] {
            var result: [String: TimeInterval] = [:]
            for day in usage {
                for (key, seconds) in values(day) { result[key, default: 0] += seconds }
            }
            return result
        }
        func rows(_ a: [String: TimeInterval], _ b: [String: TimeInterval], target: (String) -> UsageTarget,
                  name: (String) -> String) -> [ComparisonRow] {
            let firstCount = Double(max(firstDays, 1))
            let secondCount = Double(max(secondDays, 1))
            var result: [ComparisonRow] = []
            for key in Set(a.keys).union(b.keys) {
                let firstValue: TimeInterval = (a[key] ?? 0) / firstCount
                let secondValue: TimeInterval = (b[key] ?? 0) / secondCount
                let row = ComparisonRow(target: target(key), name: name(key), first: firstValue, second: secondValue)
                if row.larger >= 60 { result.append(row) }
            }
            result.sort { left, right in
                if left.larger != right.larger { return left.larger > right.larger }
                return left.name < right.name
            }
            return Array(result.prefix(limit))
        }
        var names: [String: String] = [:]
        for day in first + second {
            for (bundleID, name) in day.appNames { names[bundleID] = name }
        }
        return UsageComparison(
            first: side(first, firstDays), second: side(second, secondDays),
            apps: rows(sums(first, \.apps), sums(second, \.apps), target: { .app($0) }, name: { names[$0] ?? $0 }),
            sites: rows(sums(first, \.domains), sums(second, \.domains), target: { .domain($0) }, name: { $0 }))
    }
}

// MARK: - Trend of one app or site

public struct UsageTrend: Equatable {
    public struct Point: Equatable, Identifiable {
        public var day: Date
        public var seconds: TimeInterval
        /// 7-day moving average ending on this day.
        public var average: TimeInterval

        public var id: Date { day }
    }

    public var points: [Point]
    public var activeDays: Int
    public var averagePerDay: TimeInterval
    /// Change per week of the fitted line, seconds; nil while there is too little history.
    public var slopePerWeek: TimeInterval?
    public var record: Point?

    /// The slope is only shown with at least this many days that had any use.
    public static let minimumActiveDays = 14

    /// `daily` by day key; `from`…`to` are filled with zeros where nothing was recorded.
    public static func make(daily: [String: TimeInterval], from: Date, to: Date, days: DayCalendar) -> UsageTrend {
        var values: [(Date, TimeInterval)] = []
        var day = days.startOfDay(from)
        let last = days.startOfDay(to)
        while day <= last {
            values.append((day, daily[days.key(day)] ?? 0))
            day = days.addingDays(1, to: day)
        }
        var points: [Point] = []
        for index in values.indices {
            let window = values[max(0, index - 6)...index]
            points.append(Point(day: values[index].0, seconds: values[index].1,
                                average: window.reduce(0) { $0 + $1.1 } / Double(window.count)))
        }
        let active = values.filter { $0.1 > 0 }.count
        let total = values.reduce(0) { $0 + $1.1 }
        var trend = UsageTrend(points: points, activeDays: active,
                               averagePerDay: values.isEmpty ? 0 : total / Double(values.count),
                               slopePerWeek: nil, record: points.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds })
        if active >= minimumActiveDays, values.count >= 21 {
            trend.slopePerWeek = slope(values.map(\.1)) * 7
        }
        return trend
    }

    /// Least-squares slope per step.
    static func slope(_ values: [Double]) -> Double {
        let count = Double(values.count)
        guard count >= 2 else { return 0 }
        let meanX = (count - 1) / 2
        let meanY = values.reduce(0, +) / count
        var numerator = 0.0
        var denominator = 0.0
        for (index, value) in values.enumerated() {
            let dx = Double(index) - meanX
            numerator += dx * (value - meanY)
            denominator += dx * dx
        }
        return denominator > 0 ? numerator / denominator : 0
    }
}
