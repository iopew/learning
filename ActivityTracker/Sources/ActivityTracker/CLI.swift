import AppKit
import ActivityCore

/// `activitytracker <command>` (the app binary with `--cli`): read statistics, export, run SQL, pause the running app.
/// Runs before any UI and exits; the database is opened next to the running app (SQLite WAL allows that).
enum CLI {
    /// Distributed notification the running app listens to: object "pause:<seconds>" / "resume".
    static let controlNotification = Notification.Name("com.iopew.ActivityTracker.control")

    static let help = """
    activitytracker — статистика ActivityTracker в Терминале / ActivityTracker statistics in the Terminal

      today                         итог сегодняшнего дня словами / today in words
      report [period] [--json]      итог периода: day, 7d, 30d, 60d, 90d, 180d, year, all
      apps [period]                 приложения за период / apps
      sites [period]                сайты за период / sites
      export [period] [--json|--daily] [--full] [--out FILE]
                                    записи в CSV (по умолчанию без заголовков и адресов; --full — с ними)
      sql "SELECT ..."              свой запрос (только чтение). Удобные представления: activity, daily_apps, daily_sites
      pause [30m|2h|90|tomorrow]    пауза записи (без аргумента — до «Продолжить»)
      resume                        продолжить запись
      db                            путь к базе / database path
    """

    static func run(_ arguments: [String]) -> Int32 {
        var args = arguments
        let command = args.isEmpty ? "help" : args.removeFirst()
        func flag(_ name: String) -> Bool {
            guard let index = args.firstIndex(of: name) else { return false }
            args.remove(at: index)
            return true
        }
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
            let value = args[index + 1]
            args.removeSubrange(index...(index + 1))
            return value
        }

        let settings = Settings()
        L.current = L.resolve(settings.language)
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let days = DayCalendar(calendar: calendar, startHour: UserDefaults.standard.integer(forKey: "dayStartHourApplied"))

        do {
            switch command {
            case "help", "-h", "--help":
                print(help)
            case "db":
                print(try ActivityStore.defaultURL().path)
            case "pause":
                var seconds: TimeInterval = 0
                if let length = args.first {
                    guard let until = PauseLength.until(length, now: Date(), days: days) else {
                        return fail("pause: 30m, 2h, 90 (минут, до суток) или tomorrow")
                    }
                    seconds = until.timeIntervalSinceNow
                }
                control(seconds > 0 ? "pause:\(Int(seconds.rounded()))" : "pause")
                print(seconds > 0 ? L.tr("Пауза на \(Format.duration(seconds)).", "Paused for \(Format.duration(seconds)).")
                                  : L.tr("Пауза.", "Paused."))
            case "resume":
                control("resume")
                print(L.tr("Запись продолжается.", "Recording resumed."))
            case "sql":
                guard let query = args.first else { return fail("sql \"SELECT ...\"") }
                let result = try ActivityStore.query(databaseAt: try ActivityStore.defaultURL().path, sql: query)
                print(result.columns.joined(separator: "\t"))
                for row in result.rows { print(row.joined(separator: "\t")) }
            case "today", "report", "apps", "sites", "export":
                let store = try ActivityStore(path: try ActivityStore.defaultURL().path, days: days)
                let json = flag("--json")
                let daily = flag("--daily")
                let full = flag("--full")
                let out = option("--out")
                let rangeName = command == "today" ? "day" : (args.first ?? (command == "export" ? "30d" : "day"))
                guard let range = StatsRange(cliName: rangeName) else { return fail("period: day, 7d, 30d, 60d, 90d, 180d, year, all") }
                let report = try store.report(range: range, anchor: Date())
                var text: String
                switch command {
                case "today":
                    let switches = Switches.stats(try store.spans(from: report.fromDay, to: report.toDay))
                    text = DaySummary.make(report: report, switches: switches, usualPerHour: nil, days: days).joined(separator: "\n")
                    if text.isEmpty { text = L.tr("Сегодня почти ничего не записано.", "Almost nothing recorded today.") }
                case "apps":
                    text = report.apps.map { "\(Format.duration($0.seconds))\t\($0.appName)" }.joined(separator: "\n")
                case "sites":
                    text = report.domains.map { "\(Format.duration($0.seconds))\t\($0.domain)" }.joined(separator: "\n")
                case "report" where json:
                    text = String(decoding: try Export.json(report: report, events: nil, details: false, days: days), as: UTF8.self)
                case "report":
                    var lines = [L.tr("Всего: \(Format.duration(report.total)), активных дней: \(report.activeDays)",
                                      "Total: \(Format.duration(report.total)), active days: \(report.activeDays)")]
                    lines += report.apps.prefix(10).map { "  \(Format.duration($0.seconds))\t\($0.appName)" }
                    if !report.domains.isEmpty {
                        lines.append(L.tr("Сайты:", "Sites:"))
                        lines += report.domains.prefix(10).map { "  \(Format.duration($0.seconds))\t\($0.domain)" }
                    }
                    text = lines.joined(separator: "\n")
                default:   // export
                    if daily {
                        text = Export.dailyCSV(try store.dailyUsage(from: report.fromDay, to: report.toDay), days: days)
                    } else {
                        let events = try store.events(from: report.fromDay, to: report.toDay)
                        text = json
                            ? String(decoding: try Export.json(report: report, events: events, details: full, days: days), as: UTF8.self)
                            : Export.eventsCSV(events, details: full)
                    }
                }
                if let out {
                    try text.write(toFile: (out as NSString).expandingTildeInPath, atomically: true, encoding: .utf8)
                    print(L.tr("Сохранено: \(out)", "Saved: \(out)"))
                } else {
                    print(text)
                }
            default:
                return fail(L.tr("Неизвестная команда «\(command)». ", "Unknown command “\(command)”. ") + "activitytracker help")
            }
            return 0
        } catch {
            return fail("\(error)")
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }

    private static func control(_ command: String) {
        DistributedNotificationCenter.default().postNotificationName(controlNotification, object: command, userInfo: nil,
                                                                    deliverImmediately: true)
    }

    // MARK: - In the running app

    /// Pause / resume from the command line or an `activitytracker://` link.
    static func listen() {
        DistributedNotificationCenter.default().addObserver(forName: controlNotification, object: nil, queue: .main) { note in
            handle(note.object as? String ?? "")
        }
    }

    /// From the `activitytracker` command (same user, same Mac). Anything malformed is ignored; a timed pause is at
    /// most a day.
    static func handle(_ command: String) {
        let tracker = AppServices.shared.tracker
        if command == "resume" {
            tracker.setPaused(false)
        } else if command == "pause" || command == "pause:0" {
            tracker.setPaused(true)
        } else if command.hasPrefix("pause:"),
                  let minutes = PauseLength.valid(Double(command.dropFirst("pause:".count)).map { $0 / 60 }) {
            tracker.setPaused(true, until: Date().addingTimeInterval(minutes * 60))
        }
    }

    /// activitytracker://open (any other link too) only opens the window. Pausing and resuming are left to the
    /// command line: a web page must not be able to switch recording on or off.
    static func handle(url: URL) {
        MainWindowController.shared.show()
    }

    // MARK: - Installing the command

    static var commandPath: String { NSHomeDirectory() + "/.local/bin/activitytracker" }

    /// Writes ~/.local/bin/activitytracker, a two-line script that runs this app's binary with --cli.
    static func installCommand() throws {
        let folder = (commandPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let script = "#!/bin/sh\nexec \"/Applications/ActivityTracker.app/Contents/MacOS/ActivityTracker\" --cli \"$@\"\n"
        try script.write(toFile: commandPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandPath)
    }

    /// Whether ~/.local/bin is on the shell's PATH (zsh by default doesn't have it).
    static var folderOnPath: Bool {
        let shellRC = (try? String(contentsOfFile: NSHomeDirectory() + "/.zshrc", encoding: .utf8)) ?? ""
        return shellRC.contains(".local/bin") || (ProcessInfo.processInfo.environment["PATH"] ?? "").contains(".local/bin")
    }
}
