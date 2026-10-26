import Foundation

/// Something that went wrong (or happened) to the Mac or an app: from macOS diagnostic reports and the boot log.
public struct StabilityEvent: Equatable, Identifiable {
    public enum Kind: String, CaseIterable {
        case crash        // an app crashed
        case hang         // an app stopped responding
        case panic        // kernel panic: the whole Mac restarted
        case resource     // macOS complained about a process (disk writes, CPU, wakeups)
        case memory       // memory pressure: macOS had to kill processes (JetsamEvent)
        case shutdown     // how the Mac was turned off last time (from the boot log)
        case boot         // the Mac started
        case os           // macOS was updated
        case other        // a report of a type we don't know
    }

    /// Where it came from (report file name, "boot-…"): unique, so a report is stored once.
    public var source: String
    public var at: Date
    public var kind: Kind
    /// App / process name, or the macOS version for boot / os.
    public var name: String
    public var detail: String

    public var id: String { source }

    public init(source: String, at: Date, kind: Kind, name: String, detail: String) {
        self.source = source
        self.at = at
        self.kind = kind
        self.name = name
        self.detail = detail
    }
}

/// Reads the beginning of a report from ~/Library/Logs/DiagnosticReports (or /Library/…).
public enum StabilityParser {
    /// File types worth opening.
    public static func isReport(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return [".ips", ".crash", ".hang", ".spin", ".diag", ".panic"].contains { lower.hasSuffix($0) }
    }

    /// `head`: the first few KB of the file. `modified`: the file date, used when the report has none.
    public static func parse(fileName: String, head: String, modified: Date) -> StabilityEvent? {
        let lower = fileName.lowercased()
        let lines = head.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var header: [String: Any] = [:]
        if let first = lines.first, first.hasPrefix("{"),
           let object = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] {
            header = object
        }
        let fields = textFields(lines)
        let bugType = (header["bug_type"] as? String) ?? (header["bug_type"] as? Int).map(String.init) ?? ""

        let kind: StabilityEvent.Kind
        if lower.hasSuffix(".panic") || bugType == "210" || lower.hasPrefix("kernel") || lower.contains("panic") {
            kind = .panic
        } else if lower.hasPrefix("jetsamevent") || bugType == "298" {
            kind = .memory
        } else if lower.hasSuffix(".hang") || lower.hasSuffix(".spin") || lower.contains(".hang") || bugType == "409" {
            kind = .hang
        } else if lower.hasSuffix(".diag") || lower.contains("_resource") || lower.contains("diskwrites")
                    || lower.contains("cpu_resource") || lower.contains("wakeups") || bugType == "145" || bugType == "142"
                    || bugType == "385" {
            kind = .resource
        } else if lower.hasSuffix(".crash") || bugType == "309" || bugType == "109" {
            kind = .crash
        } else {
            kind = .other
        }

        var name = processName(fromFile: fileName)
        if let value = header["app_name"] as? String, !value.isEmpty {
            name = value
        } else if let value = header["name"] as? String, !value.isEmpty {
            name = value
        } else if let value = fields["Process"] {
            name = value.components(separatedBy: " [").first ?? value   // "Safari [1234]"
        } else if let value = fields["Command"] {
            name = value
        }
        var at = modified
        if let text = header["timestamp"] as? String, let date = parseDate(text) {
            at = date
        } else if let text = fields["Date/Time"], let date = parseDate(text) {
            at = date
        }

        var detail = ""
        switch kind {
        case .resource:
            let event = fields["Event"] ?? ""
            let amount = fields["Writes"] ?? fields["CPU"] ?? fields["Wakeups"] ?? ""
            detail = [event, amount.components(separatedBy: " (").first ?? amount]
                .filter { !$0.isEmpty }.joined(separator: ": ")
        case .crash:
            detail = fields["Exception Type"] ?? ""
        case .other:
            detail = bugType.isEmpty ? fileName : L.tr("тип отчёта \(bugType)", "report type \(bugType)")
        default:
            break
        }
        if let version = header["app_version"] as? String, !version.isEmpty, kind == .crash || kind == .hang {
            detail = detail.isEmpty ? version : "\(detail) · \(version)"
        }
        return StabilityEvent(source: fileName, at: at, kind: kind, name: kind == .panic ? "macOS" : name,
                              detail: String(detail.prefix(200)))
    }

    /// "Event:            disk writes" → ["Event": "disk writes"].
    static func textFields(_ lines: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines.prefix(60) {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix("{"), !line.hasPrefix(" ") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.count <= 20, !value.isEmpty, fields[key] == nil else { continue }
            fields[key] = value
        }
        return fields
    }

    /// "Google Chrome Helper_2026-10-20-134512_MacBook-Pro.cpu_resource.diag" → "Google Chrome Helper".
    static func processName(fromFile fileName: String) -> String {
        var name = fileName
        if let dot = name.firstIndex(of: ".") { name = String(name[..<dot]) }
        if let range = name.range(of: #"[-_]\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        return name
    }

    /// "2026-10-20 13:45:12.00 +0500" and the variants macOS uses.
    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss.SSS Z", "yyyy-MM-dd HH:mm:ss Z",
                       "yyyy-MM-dd HH:mm:ss.SSSS Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespaces)) { return date }
        }
        return nil
    }

    /// "Previous shutdown cause: -128" → -128.
    public static func shutdownCause(inLog text: String) -> Int? {
        guard let range = text.range(of: "Previous shutdown cause:") else { return nil }
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return Int(rest.prefix { $0 == "-" || $0.isNumber })
    }

    /// What a shutdown cause code most likely means (Apple doesn't document them).
    public static func describeShutdown(_ code: Int) -> String {
        switch code {
        case 5: return L.tr("обычное выключение", "normal shutdown")
        case 3: return L.tr("принудительно, кнопкой питания", "forced with the power button")
        case 0: return L.tr("пропало питание", "power loss")
        case -3: return L.tr("перегрев", "overheating")
        case -60, -61, -62: return L.tr("батарея разрядилась или сбой питания", "battery drained or a power fault")
        case -128: return L.tr("неясная причина (часто так бывает после обновления)", "unclear (often after an update)")
        case -20, -14: return L.tr("аппаратный сбой", "hardware fault")
        default: return L.tr("неизвестная причина", "unknown cause")
        }
    }
}

/// Stability history in the same SQLite file (its own connection). Thread-safe.
public final class StabilityStore {
    private let db: Database
    private let lock = NSLock()

    public init(path: String) throws {
        db = try Database(path: path)
        try db.execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            CREATE TABLE IF NOT EXISTS stability_events(
                source TEXT PRIMARY KEY,
                at REAL NOT NULL,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                detail TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS stability_events_at ON stability_events(at);
            """)
    }

    /// Sources already stored (so their files aren't parsed again).
    public func knownSources() throws -> Set<String> {
        lock.lock()
        defer { lock.unlock() }

        return Set(try db.query("SELECT source FROM stability_events") { $0.text(0) })
    }

    /// Stores new events; ones already known are ignored. Returns how many were added.
    @discardableResult
    public func add(_ events: [StabilityEvent]) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var added = 0
        try db.execute("BEGIN")
        do {
            for event in events {
                try db.run("INSERT OR IGNORE INTO stability_events(source, at, kind, name, detail) VALUES(?,?,?,?,?)",
                           [.text(event.source), .double(event.at.timeIntervalSince1970), .text(event.kind.rawValue),
                            .text(event.name), .text(event.detail)])
                added += db.changes
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        return added
    }

    /// Events since `since`, newest first.
    public func events(since: Date, limit: Int = 2000) throws -> [StabilityEvent] {
        lock.lock()
        defer { lock.unlock() }

        return try db.query(
            "SELECT source, at, kind, name, detail FROM stability_events WHERE at >= ? ORDER BY at DESC LIMIT ?",
            [.double(since.timeIntervalSince1970), .int(Int64(limit))]
        ) { row in
            StabilityEvent(source: row.text(0), at: Date(timeIntervalSince1970: row.double(1)),
                           kind: StabilityEvent.Kind(rawValue: row.text(2)) ?? .other, name: row.text(3),
                           detail: row.text(4))
        }
    }

    /// Events before `moment` (clean-up of old history).
    public func erase(before moment: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        try db.run("DELETE FROM stability_events WHERE at < ?", [.double(moment.timeIntervalSince1970)])
    }
}

/// Summary for the Stability pane.
public struct StabilityReport: Equatable {
    public struct Week: Equatable, Identifiable {
        public var start: Date
        /// Crashes of the user's own programs.
        public var crashes: Int
        public var hangs: Int
        /// Resource complaints, memory pressure, kernel panics.
        public var other: Int
        /// Crashes of macOS background services (they restart by themselves).
        public var serviceCrashes: Int = 0

        public var id: Date { start }
    }

    public struct AppCount: Equatable, Identifiable {
        public var name: String
        public var crashes: Int
        public var hangs: Int

        public var id: String { name }
        /// A macOS background service rather than a program the user runs.
        public var isSystem: Bool { StabilityNames.isSystem(name) }
    }

    public var weeks: [Week]
    /// Apps by crashes + hangs over the last 30 days.
    public var apps: [AppCount]
    public var crashes7: Int
    public var hangs7: Int
    public var panics30: Int
    /// Of `crashes7`: crashes of macOS services.
    public var serviceCrashes7: Int = 0
    /// The user's programs that crashed or hung at least 3 times in 7 days, most first.
    public var frequent: [AppCount] = []
    public var recent: [StabilityEvent]
    /// macOS versions in the order they appeared, with the first date seen.
    public var versions: [StabilityEvent]

    /// `events` newest first (as StabilityStore returns them), covering at least `weekCount` weeks.
    public static func make(_ events: [StabilityEvent], now: Date, days: DayCalendar, weekCount: Int = 12) -> StabilityReport {
        let thisWeek = days.startOfWeek(now)
        var weeks = (0..<weekCount).reversed().map {
            Week(start: days.addingDays(-7 * $0, to: thisWeek), crashes: 0, hangs: 0, other: 0)
        }
        let firstWeek = weeks.first?.start ?? thisWeek
        var apps: [String: AppCount] = [:]
        var week: [String: AppCount] = [:]
        let monthAgo = now.addingTimeInterval(-30 * 86400)
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var report = StabilityReport(weeks: [], apps: [], crashes7: 0, hangs7: 0, panics30: 0, recent: [], versions: [])

        for event in events {
            if event.at >= firstWeek, let index = weeks.lastIndex(where: { $0.start <= event.at }) {
                switch event.kind {
                case .crash where StabilityNames.isSystem(event.name): weeks[index].serviceCrashes += 1
                case .crash: weeks[index].crashes += 1
                case .hang: weeks[index].hangs += 1
                case .panic, .resource, .memory: weeks[index].other += 1
                default: break
                }
            }
            if event.at >= monthAgo, event.kind == .crash || event.kind == .hang {
                var count = apps[event.name] ?? AppCount(name: event.name, crashes: 0, hangs: 0)
                if event.kind == .crash { count.crashes += 1 } else { count.hangs += 1 }
                apps[event.name] = count
            }
            if event.at >= weekAgo {
                if event.kind == .crash { report.crashes7 += 1 }
                if event.kind == .crash, StabilityNames.isSystem(event.name) { report.serviceCrashes7 += 1 }
                if event.kind == .hang { report.hangs7 += 1 }
                if event.kind == .crash || event.kind == .hang, !StabilityNames.isSystem(event.name) {
                    var count = week[event.name] ?? AppCount(name: event.name, crashes: 0, hangs: 0)
                    if event.kind == .crash { count.crashes += 1 } else { count.hangs += 1 }
                    week[event.name] = count
                }
            }
            if event.at >= monthAgo, event.kind == .panic { report.panics30 += 1 }
        }
        report.weeks = weeks
        report.apps = apps.values.sorted {
            ($0.crashes + $0.hangs, $1.name) > ($1.crashes + $1.hangs, $0.name)
        }.prefix(20).map { $0 }
        report.frequent = week.values.filter { $0.crashes + $0.hangs >= 3 }.sorted {
            ($0.crashes + $0.hangs, $1.name) > ($1.crashes + $1.hangs, $0.name)
        }
        report.recent = Array(events.filter { $0.kind != .boot }.prefix(200))
        report.versions = events.filter { $0.kind == .os }
        return report
    }
}

/// The one-line answer at the top of the Stability pane: is everything fine, and what to do if not.
public struct StabilityVerdict: Equatable {
    public enum Level: Equatable {
        case ok, attention, problem
    }

    public var level: Level
    public var title: String
    public var details: [String]
    public var suggestRestart: Bool
}

extension StabilityReport {
    /// Restart is suggested after 30 days without one (a monthly restart is enough), or earlier when macOS
    /// services keep crashing (5+ a week, at least 3 days of uptime).
    public func verdict(uptime: TimeInterval?) -> StabilityVerdict {
        var level = StabilityVerdict.Level.ok
        var title = L.tr("С Mac всё в порядке", "Your Mac is fine")
        var details: [String] = []
        if panics30 > 0 {
            level = .problem
            title = L.tr("Mac перезагружался из-за сбоя системы", "The Mac restarted because of a system failure")
            details.append(L.tr("Kernel panic за 30 дней: \(panics30). Если повторится — обнови macOS и проверь подключённые устройства (переходники, диски).",
                                "Kernel panics in 30 days: \(panics30). If it happens again, update macOS and check connected devices (adapters, drives)."))
        }
        for app in frequent {
            if level == .ok {
                level = .attention
                title = L.tr("Есть программы, которые часто падают", "Some programs crash often")
            }
            details.append(L.tr("\(app.name): \(app.crashes + app.hangs) раз за неделю. Обнови программу; для браузера — проверь расширения.",
                                "\(app.name): \(app.crashes + app.hangs) times this week. Update it; for a browser, check its extensions."))
        }
        if level == .ok, serviceCrashes7 > 0 {
            details.append(L.tr("Сбоили только фоновые службы macOS (\(serviceCrashes7) раз за неделю) — они перезапускаются сами, обычно это незаметно.",
                                "Only macOS background services crashed (\(serviceCrashes7) times this week); they restart by themselves, usually unnoticed."))
        }
        let day: TimeInterval = 86400
        let restart = uptime.map { $0 >= 30 * day || ($0 >= 3 * day && serviceCrashes7 >= 5) } ?? false
        if restart, let uptime {
            details.append(L.tr("Mac не перезагружался \(Format.longDuration(uptime)). Перезагрузи — это обычно убирает мелкие сбои служб.",
                                "No restart for \(Format.longDuration(uptime)). Restart: it usually clears small service glitches."))
        }
        return StabilityVerdict(level: level, title: title, details: details, suggestRestart: restart)
    }
}

/// Plain names for macOS background processes that show up in crash reports.
public enum StabilityNames {
    private static let known: [String: (ru: String, en: String)] = [
        "textunderstandingd": ("анализ текста (подсказки, Apple Intelligence)", "text analysis (suggestions, Apple Intelligence)"),
        "intelligenceplatformd": ("Apple Intelligence", "Apple Intelligence"),
        "bluetoothd": ("Bluetooth", "Bluetooth"),
        "nsattributedstringagent": ("отображение форматированного текста", "rendering formatted text"),
        "WindowServer": ("вывод изображения на экран", "drawing the screen"),
        "mds": ("поиск Spotlight", "Spotlight search"),
        "mds_stores": ("поиск Spotlight", "Spotlight search"),
        "mdworker": ("поиск Spotlight", "Spotlight search"),
        "mdworker_shared": ("поиск Spotlight", "Spotlight search"),
        "corespotlightd": ("поиск Spotlight", "Spotlight search"),
        "photoanalysisd": ("анализ фото", "photo analysis"),
        "mediaanalysisd": ("анализ фото и видео", "photo and video analysis"),
        "cloudd": ("iCloud", "iCloud"),
        "bird": ("iCloud Drive", "iCloud Drive"),
        "coreaudiod": ("звук", "audio"),
        "airportd": ("Wi-Fi", "Wi-Fi"),
        "WiFiAgent": ("Wi-Fi", "Wi-Fi"),
        "locationd": ("геолокация", "location"),
        "sharingd": ("AirDrop и Handoff", "AirDrop and Handoff"),
        "rapportd": ("связь с другими устройствами Apple", "talking to your other Apple devices"),
        "nsurlsessiond": ("загрузки в фоне", "background downloads"),
        "softwareupdated": ("обновления macOS", "macOS updates"),
        "suggestd": ("подсказки Siri", "Siri suggestions"),
        "assistantd": ("Siri", "Siri"),
        "siriactionsd": ("Siri", "Siri"),
        "Finder": ("Finder", "Finder"),
        "Dock": ("Dock и Launchpad", "Dock and Launchpad"),
        "SystemUIServer": ("значки в строке меню", "menu bar items"),
        "ControlCenter": ("Пункт управления", "Control Center"),
        "NotificationCenter": ("уведомления", "notifications"),
        "loginwindow": ("вход в систему", "login window"),
        "launchd": ("запуск служб macOS", "starting macOS services"),
        "kernel_task": ("ядро macOS", "the macOS kernel"),
    ]

    /// A macOS service (not a program the user runs): known names, Apple bundle IDs, or lowercase daemon-style
    /// names ending in "d" / "agent" / "service" or containing "helper".
    public static func isSystem(_ name: String) -> Bool {
        if known[name] != nil || name.hasPrefix("com.apple.") || name == "macOS" { return true }
        guard name == name.lowercased(), !name.contains(" ") else { return false }
        return name.hasSuffix("d") || name.hasSuffix("agent") || name.hasSuffix("service") || name.contains("helper")
    }

    /// "анализ текста (подсказки, Apple Intelligence)" — or nil for an unknown name.
    public static func describe(_ name: String) -> String? {
        known[name].map { L.tr($0.ru, $0.en) }
    }
}
