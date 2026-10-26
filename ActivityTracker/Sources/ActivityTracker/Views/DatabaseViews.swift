import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ActivityCore

/// Settings → «База данных»: size and history, download a copy, open a saved copy, clean up old data, compact.
struct DatabaseSection: View {
    let databaseURL: URL

    @State private var size: Int64?
    @State private var summary: (first: Date?, last: Date?, days: Int)?
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.tr("База данных", "Database")).font(.headline)
            Text(infoText)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L.tr("Скачать базу…", "Download database…")) { download() }
                Button(L.tr("Открыть сохранённую…", "Open a saved copy…")) { ArchiveSession.choose() }
            }
            HStack {
                Menu(L.tr("Удалить старые данные", "Delete old data")) {
                    Button(L.tr("Старше года", "Older than a year")) { cleanUp(days: 365) }
                    Button(L.tr("Старше 180 дней", "Older than 180 days")) { cleanUp(days: 180) }
                    Button(L.tr("Старше 90 дней", "Older than 90 days")) { cleanUp(days: 90) }
                    Button(L.tr("Старше 30 дней", "Older than 30 days")) { cleanUp(days: 30) }
                }
                .fixedSize()
                Button(L.tr("Сжать базу", "Compact database")) { compact() }
            }
            .disabled(busy)
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Text(L.tr("Скачанная копия — обычный файл .sqlite со всей историей. Его можно открыть здесь же («Открыть сохранённую…» или перетащить на значок приложения) и смотреть всю статистику, ничего не меняя в текущей базе.",
                      "A downloaded copy is a regular .sqlite file with the whole history. Open it here (“Open a saved copy…” or drop it on the app icon) to browse all statistics without touching the current database."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .activityDataChanged)) { _ in refresh() }
    }

    private var infoText: String {
        let sizeText = size.map { Format.bytes(Double($0)) } ?? "…"
        guard let summary else { return L.tr("Размер: \(sizeText)", "Size: \(sizeText)") }
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = L.current == .en ? "MMM d, yyyy" : "d MMM yyyy"
        var text = L.tr("Размер: \(sizeText) · дней с записями: \(summary.days)",
                        "Size: \(sizeText) · days with records: \(summary.days)")
        if let first = summary.first, let last = summary.last {
            text += L.tr(" (с \(formatter.string(from: first)) по \(formatter.string(from: last)))",
                         " (\(formatter.string(from: first)) – \(formatter.string(from: last)))")
        }
        return text
    }

    /// The database file with its write-ahead log.
    static func fileSize(_ url: URL) -> Int64 {
        ["", "-wal"].reduce(Int64(0)) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path + suffix)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    private func refresh() {
        let url = databaseURL
        DispatchQueue.global(qos: .userInitiated).async {
            let size = Self.fileSize(url)
            let summary = try? AppServices.shared.database.historySummary()
            DispatchQueue.main.async {
                self.size = size
                self.summary = summary
            }
        }
    }

    private func run(_ work: @escaping () throws -> String) {
        busy = true
        status = L.tr("Работаю…", "Working…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            do {
                result = try work()
            } catch {
                result = L.tr("Ошибка: \(error)", "Error: \(error)")
            }
            DispatchQueue.main.async {
                busy = false
                status = result
                refresh()
            }
        }
    }

    private func download() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "ActivityTracker-\(formatter.string(from: Date())).sqlite"
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run {
            try AppServices.shared.database.backup(to: url.path)
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            return L.tr("Сохранено: \(url.lastPathComponent), \(Format.bytes(Double(Self.fileSize(url))))",
                        "Saved: \(url.lastPathComponent), \(Format.bytes(Double(Self.fileSize(url))))")
        }
    }

    private func cleanUp(days count: Int) {
        let days = AppServices.shared.days
        let moment = days.addingDays(-count, to: days.startOfDay(Date()))
        guard DataEraser.confirmAndErase(.before(moment)) else { return }
        compact()
    }

    private func compact() {
        let url = databaseURL
        run {
            let before = Self.fileSize(url)
            try AppServices.shared.database.compact()
            let after = Self.fileSize(url)
            return L.tr("Сжато: было \(Format.bytes(Double(before))), стало \(Format.bytes(Double(after)))",
                        "Compacted: \(Format.bytes(Double(before))) → \(Format.bytes(Double(after)))")
        }
    }
}

// MARK: - Browsing a saved database

/// A saved database opened for browsing. The file is copied to a temporary folder first, so the original stays
/// untouched (an older copy gets the current tables and day boundary on the copy only).
final class ArchiveSession: NSObject, NSWindowDelegate {
    private static var sessions: [ArchiveSession] = []

    private let folder: URL
    private let stats: StatsModel
    private let insights: InsightsModel
    private let stability: StabilityMonitor
    private var window: NSWindow?

    private init(folder: URL, stats: StatsModel, insights: InsightsModel, stability: StabilityMonitor) {
        self.folder = folder
        self.stats = stats
        self.insights = insights
        self.stability = stability
    }

    static func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L.tr("Выбери сохранённую базу ActivityTracker (.sqlite)", "Choose a saved ActivityTracker database (.sqlite)")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    static func open(_ url: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityTracker-archive-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent("archive.sqlite")
            try FileManager.default.copyItem(at: url, to: copy)
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: url.path + suffix)
                if FileManager.default.fileExists(atPath: side.path) {
                    try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
            let days = AppServices.shared.days
            let store = try ActivityStore(path: copy.path, days: days)
            let system = try SystemStore(path: copy.path, days: days)
            let network = try NetworkStore(path: copy.path, days: days)
            let machine = try MachineStore(path: copy.path, days: days)
            try store.rekeyDays()
            try system.rekeyDays()
            try network.rekeyDays()
            try machine.rekeyDays()
            let summary = try store.historySummary()
            let last = summary.last ?? days.startOfDay(Date())
            let stats = StatsModel(store: store, systemStore: system, networkStore: network, machineStore: machine, anchor: last)
            let insights = InsightsModel(store: store, now: { last })
            let stability = StabilityMonitor(path: copy.path, days: days)
            stability.openReadOnly()

            let session = ArchiveSession(folder: folder, stats: stats, insights: insights, stability: stability)
            sessions.append(session)
            session.show(name: url.lastPathComponent, summary: summary)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L.tr("Не удалось открыть базу", "Could not open the database")
            alert.informativeText = "\(url.lastPathComponent): \(error)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func show(name: String, summary: (first: Date?, last: Date?, days: Int)) {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = L.current == .en ? "MMM d, yyyy" : "d MMM yyyy"
        var subtitle = L.tr("Только просмотр · дней с записями: \(summary.days)", "Read-only · days with records: \(summary.days)")
        if let first = summary.first, let last = summary.last {
            subtitle += " · \(formatter.string(from: first)) – \(formatter.string(from: last))"
        }
        let root = ArchiveView(title: name, subtitle: subtitle, stats: stats, insights: insights, stability: stability)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = L.tr("Архив: ", "Archive: ") + name
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.sessions.removeAll { $0 === self }
        let folder = folder
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            try? FileManager.default.removeItem(at: folder)
            MainWindowController.shared.applyDockPolicy()
        }
    }
}

struct ArchiveView: View {
    let title: String
    let subtitle: String
    @ObservedObject var stats: StatsModel
    @ObservedObject var insights: InsightsModel
    @ObservedObject var stability: StabilityMonitor

    @State private var pane: Pane = .activity

    enum Pane: String, CaseIterable, Identifiable {
        case activity, rhythm, compare, battery, system, network, stability

        var id: String { rawValue }

        var title: String {
            switch self {
            case .activity: return L.tr("Активность", "Activity")
            case .rhythm: return L.tr("Ритм", "Rhythm")
            case .compare: return L.tr("Сравнение", "Compare")
            case .battery: return L.tr("Батарея", "Battery")
            case .system: return L.tr("Система", "System")
            case .network: return L.tr("Сеть", "Network")
            case .stability: return L.tr("Стабильность", "Stability")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Picker(L.tr("Раздел", "Section"), selection: $pane) {
                ForEach(Pane.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 820)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            Divider()
            switch pane {
            case .activity: activity
            case .rhythm: RhythmPane(showsBoundary: false)
            case .compare: ComparisonPane()
            case .battery:
                single {
                    if let system = stats.system { BatteryPanel(system: system, chartHeight: 220) }
                    if let machine = stats.machine { BatteryDetails(machine: machine) }
                }
            case .system:
                single {
                    if let system = stats.system { SystemPanel(system: system, chartHeight: 200) }
                    if let machine = stats.machine { SystemDetails(machine: machine) }
                }
            case .network: NetworkPane(isArchive: true)
            case .stability: StabilityPane()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .environmentObject(stats)
        .environmentObject(insights)
        .environmentObject(stability)
        .environmentObject(AppServices.shared.settings)
        .onAppear { stats.reload() }
        .background(Color.clear.sheet(item: $insights.trend) { card in
            TrendSheet(card: card) { insights.trend = nil }
        })
    }

    private var activity: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StatsControls()
                    if let report = stats.report {
                        DaySummaryCard(lines: stats.daySummary)
                        ReportOverview(report: report, style: .wide)
                        if let switches = stats.switches {
                            SwitchesCard(stats: switches, usualPerHour: nil)
                        }
                    } else {
                        ReportPlaceholder()
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 500, maxWidth: .infinity)
            Divider()
            ScrollView {
                if let report = stats.report {
                    ReportLists(report: report, onTrend: { target, name in insights.showTrend(target, name: name) })
                        .padding(20)
                }
            }
            .frame(width: 400)
        }
    }

    private func single<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatsControls()
                content()
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
