import AppKit
import SwiftUI
import ActivityCore

/// The window that opens from the menu bar item.
struct PopoverView: View {
    let databaseURL: URL
    let startupError: String?

    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var stats: StatsModel
    @EnvironmentObject private var settings: Settings

    @State private var showSettings = false
    @State private var tab: ListTab = .apps

    private let refresh = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    enum ListTab: String, CaseIterable, Identifiable {
        case apps = "Приложения"
        case sites = "Сайты"
        case timeline = "Хронология"

        var id: String { rawValue }
    }

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
                statistics
            }
            Divider()
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 460, height: 700)
        .onAppear { stats.reload() }
        .onReceive(refresh) { _ in
            // Keep "today" live while the window is open; past periods don't change.
            if !showSettings && stats.isAtToday && stats.range == .day { stats.reload() }
        }
    }

    private var statistics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Период", selection: $stats.range) {
                    ForEach(StatsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                PeriodBar()

                if let report = stats.report {
                    let colors = AppColors(apps: report.apps)
                    SummaryRow(report: report)

                    if report.range == .day {
                        HourlyChart(slices: report.hourly, colors: colors)
                        MinuteGrid(minutes: report.minutes, colors: colors)
                    } else {
                        RangeChart(report: report)
                    }

                    Picker("Список", selection: $tab) {
                        ForEach(ListTab.allCases.filter { $0 != .timeline || report.range == .day }) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch effectiveTab(for: report) {
                    case .apps: AppsList(report: report, colors: colors)
                    case .sites: SitesList(report: report)
                    case .timeline: TimelineList(sessions: report.sessions, colors: colors)
                    }
                } else if let error = stats.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(14)
        }
    }

    private func effectiveTab(for report: Report) -> ListTab {
        tab == .timeline && report.range != .day ? .apps : tab
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                tracker.setPaused(!settings.isPaused)
            } label: {
                Label(settings.isPaused ? "Продолжить" : "Пауза",
                      systemImage: settings.isPaused ? "play.fill" : "pause.fill")
            }
            Spacer()
            Button {
                showSettings.toggle()
                if !showSettings { stats.reload() }
            } label: {
                Label(showSettings ? "Статистика" : "Настройки",
                      systemImage: showSettings ? "chart.bar.xaxis" : "gearshape")
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Выйти", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
    }
}

/// Today's total and what is being recorded right now.
struct StatusHeader: View {
    @EnvironmentObject private var tracker: Tracker

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Сегодня за компьютером")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.duration(tracker.todayTotal))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                if let current = tracker.current {
                    Text(current.appName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    let detail = current.domain.isEmpty ? current.title : current.domain
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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
        }
    }

    private var statusColor: Color {
        switch tracker.state {
        case .active: return .green
        case .idle: return .yellow
        case .paused, .away: return .gray
        }
    }
}

/// "‹ 16 окт – 22 окт ›" with a jump back to today.
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
