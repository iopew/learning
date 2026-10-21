import AppKit
import SwiftUI
import ActivityCore

/// The small window that opens from the menu bar item.
struct PopoverView: View {
    let databaseURL: URL
    let startupError: String?

    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var stats: StatsModel
    @EnvironmentObject private var settings: Settings

    @State private var showSettings = false
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            if let startupError {
                Text(startupError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            Divider()
            if showSettings {
                SettingsView(databaseURL: databaseURL)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        UpdateBanner()
                        StatsControls()
                        if let report = stats.report {
                            ReportOverview(report: report, style: .compact)
                            ReportLists(report: report)
                        } else {
                            ReportPlaceholder()
                        }
                    }
                    .padding(14)
                }
            }
            Divider()
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 460, height: 700)
        .onAppear {
            isOpen = true
            stats.reload()
        }
        .onDisappear { isOpen = false }
        .onReceive(tracker.$todayTotal) { _ in
            // Keep the numbers in step with the menu bar counter while the window is open.
            if isOpen && !showSettings { stats.refreshIfLive() }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            PauseButton()
            Spacer()
            Button {
                MainWindowController.shared.show()
            } label: {
                Label("Окно", systemImage: "macwindow")
            }
            Button {
                showSettings.toggle()
                if !showSettings { stats.reload() }
            } label: {
                Label(showSettings ? "Статистика" : "Настройки",
                      systemImage: showSettings ? "chart.bar.xaxis" : "gearshape")
            }
            QuitButton()
        }
        .buttonStyle(.borderless)
    }
}

/// Today's total and the recording status.
struct StatusHeader: View {
    var large = false

    @EnvironmentObject private var tracker: Tracker

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Сегодня за компьютером")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.duration(tracker.todayTotal))
                    .font(.system(size: large ? 34 : 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                if let error = tracker.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            .frame(maxWidth: 270, alignment: .trailing)
        }
    }

    private var statusText: String {
        switch tracker.state {
        case .active: return "Записываю"
        case .idle: return "Не за компьютером"
        case .paused: return "Пауза"
        case .away: return "Экран заблокирован"
        case .privateWindow: return "Приватное окно — не записываю"
        }
    }

    private var statusColor: Color {
        switch tracker.state {
        case .active: return .green
        case .idle: return .yellow
        case .paused, .away, .privateWindow: return .gray
        }
    }
}

/// Period picker + "‹ 16 окт – 22 окт ›".
struct StatsControls: View {
    @EnvironmentObject private var stats: StatsModel

    var body: some View {
        VStack(spacing: 10) {
            Picker("Период", selection: $stats.range) {
                ForEach(StatsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            PeriodBar()
        }
    }
}

struct PeriodBar: View {
    @EnvironmentObject private var stats: StatsModel

    var body: some View {
        HStack {
            if stats.canStep {
                Button { stats.step(-1) } label: { Image(systemName: "chevron.left") }
            }
            Text(stats.periodTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
            if stats.canStep {
                if !stats.isAtToday {
                    Button("Сегодня") { stats.goToToday() }
                        .font(.caption)
                }
                Button { stats.step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(stats.isAtToday)
            }
        }
        .buttonStyle(.borderless)
    }
}

/// Summary numbers and charts of a report.
struct ReportOverview: View {
    enum Style {
        case compact   // menu bar window
        case wide      // main window

        var hourlyHeight: CGFloat { self == .compact ? 130 : 220 }
        var rangeHeight: CGFloat { self == .compact ? 150 : 260 }
        var minuteRowHeight: CGFloat { self == .compact ? 7 : 13 }
    }

    let report: Report
    let style: Style

    var body: some View {
        let colors = AppColors(apps: report.apps)
        VStack(alignment: .leading, spacing: 14) {
            SummaryRow(report: report)
            if report.range == .day {
                HourlyChart(slices: report.hourly, colors: colors, height: style.hourlyHeight)
                MinuteGrid(minutes: report.minutes, colors: colors, rowHeight: style.minuteRowHeight)
            } else {
                RangeChart(report: report, height: style.rangeHeight)
            }
        }
    }
}

/// Apps / sites / timeline tabs for a report.
struct ReportLists: View {
    let report: Report

    @State private var tab: ListTab = .apps

    enum ListTab: String, CaseIterable, Identifiable {
        case apps = "Приложения"
        case sites = "Сайты"
        case timeline = "Хронология"

        var id: String { rawValue }
    }

    var body: some View {
        let colors = AppColors(apps: report.apps)
        let current = tab == .timeline && report.range != .day ? .apps : tab
        VStack(alignment: .leading, spacing: 12) {
            Picker("Список", selection: $tab) {
                ForEach(ListTab.allCases.filter { $0 != .timeline || report.range == .day }) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch current {
            case .apps: AppsList(report: report, colors: colors)
            case .sites: SitesList(report: report)
            case .timeline: TimelineList(sessions: report.sessions, colors: colors)
            }
        }
    }
}

struct ReportPlaceholder: View {
    @EnvironmentObject private var stats: StatsModel

    var body: some View {
        if let error = stats.error {
            Text(error).foregroundStyle(.red)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

struct SummaryRow: View {
    let report: Report

    var body: some View {
        HStack(spacing: 0) {
            metric("Всего", Format.duration(report.total))
            if report.range != .day {
                metric("В среднем за день", Format.duration(report.averagePerActiveDay))
                metric("Активных дней", "\(report.activeDays)")
            } else {
                metric("Приложений", "\(report.apps.count)")
                metric("Сайтов", "\(report.domains.count)")
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PauseButton: View {
    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var settings: Settings

    var body: some View {
        Button {
            tracker.setPaused(!settings.isPaused)
        } label: {
            Label(settings.isPaused ? "Продолжить" : "Пауза",
                  systemImage: settings.isPaused ? "play.fill" : "pause.fill")
        }
    }
}

/// Really quits (stops recording), unlike ⌘Q in the main window which only closes it.
struct QuitButton: View {
    var body: some View {
        Button {
            AppDelegate.quitForReal()
        } label: {
            Label("Выйти", systemImage: "power")
        }
    }
}

/// Stable colors for the period's top apps; everything else is gray.
struct AppColors {
    static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .red, .indigo, .mint]
    static let other = Color.gray.opacity(0.55)

    private var colors: [String: Color] = [:]

    init(apps: [AppUsage]) {
        for (index, app) in apps.prefix(Self.palette.count).enumerated() {
            colors[app.bundleID] = Self.palette[index]
        }
    }

    func color(_ bundleID: String) -> Color {
        colors[bundleID] ?? Self.other
    }
}
