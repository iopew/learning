import Foundation

/// Local-day arithmetic. Events are bucketed by the local calendar day they started on ("2026-10-21").
public struct DayCalendar {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(date)
    }

    /// Number of calendar days from `from` to `to`, inclusive.
    public func dayCount(from: Date, to: Date) -> Int {
        let days = calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
        return days + 1
    }
}

/// The periods offered in the UI. All except `.all` end on the anchor day and span a fixed number of days.
public enum StatsRange: String, CaseIterable, Identifiable {
    case day, week, month, days60, days90, days180, year, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: return "День"
        case .week: return "7д"
        case .month: return "30д"
        case .days60: return "60д"
        case .days90: return "90д"
        case .days180: return "180д"
        case .year: return "Год"
        case .all: return "Всё"
        }
    }

    /// nil for `.all`, whose length depends on how much history exists.
    public var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .days60: return 60
        case .days90: return 90
        case .days180: return 180
        case .year: return 365
        case .all: return nil
        }
    }
}
