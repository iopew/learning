import Foundation

/// When the evening digest and the weekly review are due.
public enum DigestSchedule {
    /// The moment the digest of `day` goes out: `hour`:00 on the day's date.
    public static func time(of day: Date, hour: Int, days: DayCalendar) -> Date {
        let midnight = days.midnight(of: day)
        return days.calendar.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
    }

    /// Today's digest once its time has come; yesterday's in the morning if the Mac was closed in the evening.
    /// `lastSent` is the key of the last day sent; nil (never sent) means no catch-up.
    public static func dueDay(now: Date, hour: Int, lastSent: String?, days: DayCalendar) -> Date? {
        let today = days.startOfDay(now)
        let todayKey = days.key(today)
        if now >= time(of: today, hour: hour, days: days) {
            return lastSent == todayKey ? nil : today
        }
        guard let lastSent else { return nil }
        let yesterday = days.addingDays(-1, to: today)
        return lastSent < days.key(yesterday) ? yesterday : nil
    }

    /// The last full week, from the first day of this week at the digest time on, if it wasn't sent yet.
    /// Returns the start of that week.
    public static func dueWeek(now: Date, hour: Int, lastSent: String?, days: DayCalendar) -> Date? {
        let thisWeek = days.startOfWeek(now)
        guard now >= time(of: thisWeek, hour: hour, days: days) else { return nil }
        let previous = days.startOfWeek(days.addingDays(-7, to: thisWeek))
        let key = days.key(previous)
        if let lastSent, lastSent >= key { return nil }
        return previous
    }
}

/// The text of a notification.
public struct DigestMessage: Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum Digest {
    /// "Итог дня: 6ч 48м" / "VS Code 2ч 10м · YouTube 1ч 05м · …" / "Лучший фокус 52м …".
    /// nil for a day with almost nothing recorded.
    public static func daily(report: Report, switches: SwitchStats, tip: Recommendation?) -> DigestMessage? {
        guard report.total >= 10 * 60 else { return nil }
        var lines: [String] = []
        var top = report.apps.prefix(3).map { "\($0.appName) \(Format.duration($0.seconds))" }
        if let site = report.domains.first, site.seconds >= 10 * 60 {
            top.append("\(site.domain) \(Format.duration(site.seconds))")
        }
        lines.append(top.joined(separator: " · "))

        var focus: [String] = []
        if let run = switches.longestRun, run.duration >= 10 * 60 {
            focus.append(L.tr("лучший фокус \(Format.duration(run.duration)) в \(run.appName)",
                              "best focus \(Format.duration(run.duration)) in \(run.appName)"))
        }
        if let perHour = switches.perHour {
            focus.append(L.tr("\(Int(perHour.rounded())) переключений в час", "\(Int(perHour.rounded())) switches per hour"))
        }
        if !focus.isEmpty {
            let text = focus.joined(separator: ", ")
            lines.append(text.prefix(1).uppercased() + text.dropFirst())
        }
        if let tip { lines.append(tip.title) }
        return DigestMessage(title: L.tr("Итог дня: \(Format.duration(report.total))",
                                         "Your day: \(Format.duration(report.total))"),
                             body: lines.joined(separator: "\n"))
    }

    /// The week against the week before. nil when the week was nearly empty.
    public static func weekly(week: Report, previous: Report) -> DigestMessage? {
        guard week.total >= 3600 else { return nil }
        var title = L.tr("Неделя: \(Format.duration(week.total))", "Your week: \(Format.duration(week.total))")
        if previous.total >= 3600 {
            let change = Int(((week.total / previous.total) - 1) * 100)
            title += change >= 0 ? " (+\(change)%)" : " (\(change)%)"
        }
        var lines: [String] = []
        let before = Dictionary(previous.apps.map { ($0.bundleID, $0.seconds) }, uniquingKeysWith: +)
        let top = week.apps.prefix(3).map { app -> String in
            let delta = app.seconds - (before[app.bundleID] ?? 0)
            guard abs(delta) >= 30 * 60, previous.total > 0 else { return "\(app.appName) \(Format.duration(app.seconds))" }
            return "\(app.appName) \(Format.duration(app.seconds)) (\(delta > 0 ? "+" : "−")\(Format.duration(abs(delta))))"
        }
        lines.append(L.tr("Больше всего: ", "Most: ") + top.joined(separator: ", "))
        lines.append(L.tr("Активных дней: \(week.activeDays) из 7, в среднем \(Format.duration(week.averagePerActiveDay))",
                          "Active days: \(week.activeDays) of 7, \(Format.duration(week.averagePerActiveDay)) on average"))
        return DigestMessage(title: title, body: lines.joined(separator: "\n"))
    }
}
