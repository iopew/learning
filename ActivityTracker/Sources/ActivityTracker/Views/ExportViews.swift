import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ActivityCore

/// "Сводка дня": the day in a few sentences (day view).
struct DaySummaryCard: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.tr("День словами", "The day in words")).font(.caption).foregroundStyle(.secondary)
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
        }
    }
}

/// "Экспорт" for the selected period: records as CSV, per-day totals as CSV, or JSON.
struct ExportMenu: View {
    @EnvironmentObject private var stats: StatsModel

    var body: some View {
        Menu {
            Button(L.tr("Записи, CSV (только приложения и сайты)", "Records, CSV (apps and sites only)")) { export(.csv, details: false) }
            Button(L.tr("Записи, CSV (с заголовками и адресами)", "Records, CSV (with titles and addresses)")) { export(.csv, details: true) }
            Button(L.tr("Итоги по дням, CSV", "Daily totals, CSV")) { export(.daily, details: false) }
            Button("JSON") { export(.json, details: false) }
        } label: {
            Label(L.tr("Экспорт", "Export"), systemImage: "square.and.arrow.up")
        }
        .fixedSize()
    }

    private enum Kind {
        case csv, daily, json
    }

    private func export(_ kind: Kind, details: Bool) {
        let services = AppServices.shared
        let range = stats.range
        let anchor = stats.anchor
        let days = services.days
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let suffix = kind == .json ? "json" : "csv"
        panel.nameFieldStringValue = "ActivityTracker-\(range.rawValue)-\(formatter.string(from: anchor)).\(suffix)"
        panel.allowedContentTypes = [kind == .json ? .json : .commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = services.database
                let report = try store.report(range: range, anchor: anchor)
                let data: Data
                switch kind {
                case .csv:
                    data = Data(Export.eventsCSV(try store.events(from: report.fromDay, to: report.toDay), details: details).utf8)
                case .daily:
                    data = Data(Export.dailyCSV(try store.dailyUsage(from: report.fromDay, to: report.toDay), days: days).utf8)
                case .json:
                    data = try Export.json(report: report, events: try store.events(from: report.fromDay, to: report.toDay),
                                           details: false, days: days)
                }
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = L.tr("Не удалось сохранить", "Could not save")
                    alert.informativeText = "\(error)"
                    alert.runModal()
                }
            }
        }
    }
}

/// Settings → «Команда в Терминале».
struct CommandLineSection: View {
    @State private var installed = FileManager.default.isExecutableFile(atPath: CLI.commandPath)
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.tr("Команда в Терминале", "Terminal command")).font(.headline)
            HStack {
                Button(installed ? L.tr("Переустановить команду", "Reinstall the command") : L.tr("Установить команду activitytracker", "Install the activitytracker command")) {
                    do {
                        try CLI.installCommand()
                        installed = true
                        status = L.tr("Готово: \(CLI.commandPath)", "Done: \(CLI.commandPath)")
                    } catch {
                        status = L.tr("Не получилось: \(error)", "Failed: \(error)")
                    }
                }
                if installed {
                    Text(L.tr("установлена", "installed")).font(.caption).foregroundStyle(.green)
                }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if installed && !CLI.folderOnPath {
                Text(L.tr("Папка ~/.local/bin не в PATH. Выполни один раз в Терминале:", "~/.local/bin isn't on PATH. Run once in the Terminal:"))
                    .font(.caption)
                Text("echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.zshrc && source ~/.zshrc")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Text(L.tr("Примеры: activitytracker today · activitytracker report 7d · activitytracker pause 30m · activitytracker export 30d --out ~/Desktop/a.csv · activitytracker sql \"SELECT * FROM daily_apps LIMIT 10\". Ссылки activitytracker://pause?minutes=30 работают из заметок и Быстрых команд.",
                      "Examples: activitytracker today · activitytracker report 7d · activitytracker pause 30m · activitytracker export 30d --out ~/Desktop/a.csv · activitytracker sql \"SELECT * FROM daily_apps LIMIT 10\". Links like activitytracker://pause?minutes=30 work from notes and Shortcuts."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
