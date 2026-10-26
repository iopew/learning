import Foundation

/// Data out: CSV / JSON for spreadsheets and own programs (e.g. a Go CLI).
public enum Export {
    /// One row per recorded stretch. `details`: include window titles and addresses (otherwise only apps and domains).
    public static func eventsCSV(_ events: [ActivityEvent], details: Bool) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = .current
        var lines = [details ? "start,end,seconds,app,bundle_id,domain,title,url" : "start,end,seconds,app,bundle_id,domain"]
        for event in events {
            var fields = [iso.string(from: event.start), iso.string(from: event.end), String(Int(event.duration.rounded())),
                          event.appName, event.bundleID, event.domain]
            if details { fields += [event.title, event.url] }
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Seconds per day and app (and per day and site).
    public static func dailyCSV(_ usage: [DayUsage], days: DayCalendar) -> String {
        var lines = ["day,kind,name,id,seconds"]
        for day in usage {
            let key = days.key(day.day)
            for (bundleID, seconds) in day.apps.sorted(by: { $0.value > $1.value }) {
                lines.append([key, "app", day.appNames[bundleID] ?? bundleID, bundleID, String(Int(seconds.rounded()))]
                    .map(csvField).joined(separator: ","))
            }
            for (domain, seconds) in day.domains.sorted(by: { $0.value > $1.value }) {
                lines.append([key, "site", domain, domain, String(Int(seconds.rounded()))].map(csvField).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A report and (optionally) its events as JSON, `"schema": 1` so programs can check the format.
    public static func json(report: Report, events: [ActivityEvent]?, details: Bool, days: DayCalendar) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var object: [String: Any] = [
            "schema": 1,
            "range": report.range.rawValue,
            "from": days.key(report.fromDay),
            "to": days.key(report.toDay),
            "total_seconds": Int(report.total.rounded()),
            "active_days": report.activeDays,
            "apps": report.apps.map { ["name": $0.appName, "bundle_id": $0.bundleID, "seconds": Int($0.seconds.rounded())] },
            "sites": report.domains.map { ["domain": $0.domain, "seconds": Int($0.seconds.rounded())] },
            "days": report.buckets.map { ["start": days.key($0.start), "seconds": Int($0.seconds.rounded())] },
        ]
        if let events {
            object["events"] = events.map { event -> [String: Any] in
                var entry: [String: Any] = ["start": iso.string(from: event.start), "end": iso.string(from: event.end),
                                            "seconds": Int(event.duration.rounded()), "app": event.appName,
                                            "bundle_id": event.bundleID, "domain": event.domain]
                if details {
                    entry["title"] = event.title
                    entry["url"] = event.url
                }
                return entry
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    /// Quotes when needed. A value that a spreadsheet would read as a formula (=, +, -, @, tab, CR first: titles come
    /// from web pages, e.g. `=HYPERLINK(...)`) gets a leading apostrophe, so Excel / Numbers show it as text.
    static func csvField(_ raw: String) -> String {
        var value = raw
        if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension StatsRange {
    /// Names used on the command line: day, 7d, 30d, 60d, 90d, 180d, year, all (also week, month).
    public init?(cliName: String) {
        switch cliName.lowercased() {
        case "day", "today", "1d": self = .day
        case "7d", "week": self = .week
        case "30d", "month": self = .month
        case "60d": self = .days60
        case "90d": self = .days90
        case "180d": self = .days180
        case "year", "365d": self = .year
        case "all": self = .all
        default: return nil
        }
    }
}

/// "30m", "2h", "90" (minutes), "tomorrow" → the moment a pause ends.
public enum PauseLength {
    /// The longest timed pause (a day); longer, negative, NaN or infinite values are refused.
    public static let maximumMinutes: Double = 24 * 60

    public static func until(_ text: String, now: Date, days: DayCalendar) -> Date? {
        let value = text.lowercased().trimmingCharacters(in: .whitespaces)
        if value == "tomorrow" || value == "завтра" {
            return days.addingDays(1, to: days.startOfDay(now))
        }
        var minutes: Double?
        if value.hasSuffix("h") {
            minutes = Double(value.dropLast()).map { $0 * 60 }
        } else if value.hasSuffix("m") {
            minutes = Double(value.dropLast())
        } else {
            minutes = Double(value)
        }
        guard let minutes = valid(minutes) else { return nil }
        return now.addingTimeInterval(minutes * 60)
    }

    /// A pause length from outside (command line, link) in minutes, or nil if it isn't a sane number.
    public static func valid(_ minutes: Double?) -> Double? {
        guard let minutes, minutes.isFinite, minutes > 0, minutes <= maximumMinutes else { return nil }
        return minutes
    }
}

// MARK: - The day in words

/// A short plain-language story of a day, built from the day report: parts of the day with their main apps and
/// sites, the busiest hour, the longest stretch, switching. Rules, not AI: always available, always the same.
public enum DaySummary {
    public static func make(report: Report, switches: SwitchStats?, usualPerHour: Double?, days: DayCalendar) -> [String] {
        guard report.range == .day, report.total >= 10 * 60 else { return [] }
        var lines: [String] = []
        let midnight = days.midnight(of: report.toDay)

        // Parts of the day by the clock (a 04:00 day start keeps the night at the end).
        let parts: [(name: String, from: Double, to: Double)] = [
            (L.tr("Утро", "Morning"), 4, 12), (L.tr("День", "Afternoon"), 12, 18),
            (L.tr("Вечер", "Evening"), 18, 24), (L.tr("Ночь", "Night"), 24, 30),
        ]
        for part in parts {
            var apps: [String: (seconds: Double, details: [String: Double])] = [:]
            var first: Date?
            var last: Date?
            for session in report.sessions {
                var hour = session.start.timeIntervalSince(midnight) / 3600
                if hour < 4 { hour += 24 }   // a day starting at midnight: 00:00–04:00 is its night
                guard hour >= part.from, hour < part.to else { continue }
                var entry = apps[session.appName] ?? (0, [:])
                entry.seconds += session.duration
                // Sessions list domains (browsers) or window titles: only domains are named in the summary.
                for detail in session.details.prefix(2) where isDomain(detail) {
                    entry.details[detail, default: 0] += session.duration
                }
                apps[session.appName] = entry
                first = min(first ?? session.start, session.start)
                last = max(last ?? session.end, session.end)
            }
            let total = apps.values.reduce(0) { $0 + $1.seconds }
            guard total >= 15 * 60, let first, let last else { continue }
            let top = apps.sorted { $0.value.seconds > $1.value.seconds }.prefix(3).filter { $0.value.seconds >= 5 * 60 }
            let text = top.map { app -> String in
                let sites = app.value.details.sorted { $0.value > $1.value }.prefix(2).map(\.key)
                let suffix = sites.isEmpty ? "" : " (\(sites.joined(separator: ", ")))"
                return "\(app.key) \(Format.duration(app.value.seconds))\(suffix)"
            }.joined(separator: ", ")
            guard !text.isEmpty else { continue }
            lines.append("\(part.name), \(clock(first, days))–\(clock(last, days)): \(text).")
        }

        var overall: [String] = [L.tr("Всего \(Format.duration(report.total))", "In total \(Format.duration(report.total))")]
        let hours = Dictionary(grouping: report.hourly, by: \.hour).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        if let busiest = hours.max(by: { $0.value < $1.value }), busiest.value >= 20 * 60 {
            let hour = (busiest.key + report.firstHour) % 24
            overall.append(L.tr("самый плотный час — \(String(format: "%02d:00", hour))", "the busiest hour was \(String(format: "%02d:00", hour))"))
        }
        if let run = switches?.longestRun, run.duration >= 15 * 60 {
            overall.append(L.tr("дольше всего без переключений — \(Format.duration(run.duration)) в \(run.appName)",
                                "the longest uninterrupted stretch was \(Format.duration(run.duration)) in \(run.appName)"))
        }
        if let perHour = switches?.perHour {
            var text = L.tr("\(Int(perHour.rounded())) переключений в час", "\(Int(perHour.rounded())) switches per hour")
            if let usual = usualPerHour, usual > 0 {
                let ratio = perHour / usual
                text += ratio >= 1.3 ? L.tr(" — больше обычного, день был рваным", ", more than usual: a fragmented day")
                    : ratio <= 0.77 ? L.tr(" — меньше обычного, хорошая концентрация", ", fewer than usual: good focus")
                    : L.tr(", как обычно", ", as usual")
            }
            overall.append(text)
        }
        lines.append(overall.joined(separator: "; ") + ".")
        return lines
    }

    static func isDomain(_ text: String) -> Bool {
        text.contains(".") && !text.contains(" ") && text.count <= 60 && !text.hasSuffix(".go") && !text.hasSuffix(".swift")
    }

    private static func clock(_ date: Date, _ days: DayCalendar) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = days.calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
