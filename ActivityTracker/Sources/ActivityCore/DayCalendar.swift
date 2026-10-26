import Foundation

/// Local-day arithmetic. Events are bucketed by the local calendar day they started on ("2026-10-21").
///
/// A day may begin later than midnight (`startHour`): with 4, work until 03:59 still belongs to the previous day,
/// so a late night stays one day in the statistics. All dates returned for a day (`startOfDay`, `date(fromKey:)`)
/// then point to that hour instead of midnight.
public struct DayCalendar {
    public let calendar: Calendar
    /// 0…5: the hour at which a new day begins.
    public let startHour: Int

    public init(calendar: Calendar = .current, startHour: Int = 0) {
        self.calendar = calendar
        self.startHour = min(max(startHour, 0), 5)
    }

    /// The moment moved so that the day boundary falls on midnight.
    private func shifted(_ date: Date) -> Date {
        startHour == 0 ? date : calendar.date(byAdding: .hour, value: -startHour, to: date) ?? date
    }

    /// A midnight of the shifted scale back to the real day start.
    private func unshifted(_ date: Date) -> Date {
        startHour == 0 ? date : calendar.date(byAdding: .hour, value: startHour, to: date) ?? date
    }

    public func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted(date))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let midnight = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return unshifted(midnight)
    }

    public func startOfDay(_ date: Date) -> Date {
        unshifted(calendar.startOfDay(for: shifted(date)))
    }

    /// Calendar midnight of the date a day is named after (the "00:00" its clock times are measured from).
    public func midnight(of day: Date) -> Date {
        calendar.startOfDay(for: shifted(day))
    }

    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public func startOfWeek(_ date: Date) -> Date {
        let moved = shifted(date)
        return unshifted(calendar.dateInterval(of: .weekOfYear, for: moved)?.start ?? calendar.startOfDay(for: moved))
    }

    /// Number of calendar days from `from` to `to`, inclusive.
    public func dayCount(from: Date, to: Date) -> Int {
        let days = calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
        return days + 1
    }

    /// Saturday or Sunday (by the calendar), for the day `date` belongs to.
    public func isWeekend(_ date: Date) -> Bool {
        calendar.isDateInWeekend(shifted(date))
    }
}

/// The periods offered in the UI. All except `.all` end on the anchor day and span a fixed number of days.
public enum StatsRange: String, CaseIterable, Identifiable {
    case day, week, month, days60, days90, days180, year, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: return L.tr("День", "Day")
        case .week: return L.tr("7д", "7d")
        case .month: return L.tr("30д", "30d")
        case .days60: return L.tr("60д", "60d")
        case .days90: return L.tr("90д", "90d")
        case .days180: return L.tr("180д", "180d")
        case .year: return L.tr("Год", "Year")
        case .all: return L.tr("Всё", "All")
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
