import AppKit
import Charts
import SwiftUI
import ActivityCore

// MARK: - Switches

/// "Переключения": how fragmented the period was. Shown under the summary for periods up to 30 days.
struct SwitchesCard: View {
    let stats: SwitchStats
    var lastHour: Int?
    var usualPerHour: Double?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.tr("Переключения между приложениями", "Switching between apps"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                metric(L.tr("В час", "Per hour"), stats.perHour.map { "\(Int($0.rounded()))" } ?? "—",
                       usualPerHour.map { L.tr("обычно \(Int($0.rounded()))", "usually \(Int($0.rounded()))") })
                if let lastHour {
                    metric(L.tr("За последний час", "Last hour"), "\(lastHour)", nil)
                }
                metric(L.tr("Без переключений, медиана", "Uninterrupted, median"),
                       stats.medianRun.map(Format.duration) ?? "—", nil)
                if !compact, let run = stats.longestRun {
                    metric(L.tr("Самый долгий отрезок", "Longest stretch"), Format.duration(run.duration), run.appName)
                }
            }
            if !stats.pairs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.tr("Чаще всего туда-обратно", "Most back-and-forth"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(stats.pairs.prefix(compact ? 2 : 5)) { pair in
                        HStack {
                            Text("\(pair.firstName) ↔ \(pair.secondName)").lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(L.tr("\(pair.count) раз", "\(pair.count) times")).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rhythm

struct RhythmPane: View {
    /// The day boundary setting (hidden for a saved database).
    var showsBoundary = true

    @EnvironmentObject private var insights: InsightsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L.tr("Когда начинается и заканчивается день", "When your day starts and ends"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Picker(L.tr("Период", "Period"), selection: $insights.rhythmDays) {
                        Text(L.tr("30 дней", "30 days")).tag(30)
                        Text(L.tr("90 дней", "90 days")).tag(90)
                        Text(L.tr("Год", "Year")).tag(365)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
                if let rhythm = insights.rhythm {
                    RhythmSummaryRow(rhythm: rhythm)
                    RhythmChart(points: rhythm.points)
                } else if let error = insights.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if showsBoundary { DayBoundaryNote() }
                Divider()
                HStack {
                    Text(L.tr("Год по дням", "The year day by day")).font(.title3.weight(.semibold))
                    Spacer()
                    let thisYear = insights.days.calendar.component(.year, from: insights.today)
                    Button { insights.calendarYear -= 1 } label: { Image(systemName: "chevron.left") }
                        .disabled(insights.calendarYear <= (insights.firstYear ?? thisYear))
                    Text(String(insights.calendarYear)).font(.headline).monospacedDigit().frame(width: 50)
                    Button { insights.calendarYear += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(insights.calendarYear >= thisYear)
                }
                .buttonStyle(.borderless)
                YearCalendar(stats: insights.year, days: insights.days, year: insights.calendarYear, today: insights.today)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { insights.reloadRhythm() }
    }
}

private struct RhythmSummaryRow: View {
    let rhythm: RhythmSummary

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            metric(L.tr("Обычно начинаешь", "You usually start"), rhythm.typicalStart.map(RhythmSummary.clock) ?? "—",
                   shift(rhythm.recentStartShift))
            metric(L.tr("Обычно заканчиваешь", "You usually finish"), rhythm.typicalEnd.map(RhythmSummary.clock) ?? "—",
                   shift(rhythm.recentEndShift))
            metric(L.tr("Дней в расчёте", "Days counted"), "\(rhythm.points.count)", nil)
        }
    }

    /// "последние 7 дней на 40 мин позже".
    private func shift(_ minutes: Double?) -> String? {
        guard let minutes, abs(minutes) >= 10 else { return minutes == nil ? nil : L.tr("последние 7 дней — как обычно", "last 7 days — as usual") }
        let amount = Format.duration(abs(minutes) * 60)
        return minutes > 0
            ? L.tr("последние 7 дней на \(amount) позже", "last 7 days \(amount) later")
            : L.tr("последние 7 дней на \(amount) раньше", "last 7 days \(amount) earlier")
    }

    private func metric(_ title: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One bar per day from the first to the last activity, by the clock (an end after midnight goes above 24:00).
private struct RhythmChart: View {
    let points: [RhythmPoint]

    var body: some View {
        if points.isEmpty {
            EmptyNote()
        } else {
            let low = max(0, floor((points.map(\.startHour).min() ?? 8) - 1))
            let high = min(30, ceil((points.map(\.endHour).max() ?? 24) + 1))
            Chart(points) { point in
                BarMark(x: .value(L.tr("День", "Day"), point.day, unit: .day),
                        yStart: .value(L.tr("Начало", "Start"), point.startHour),
                        yEnd: .value(L.tr("Конец", "End"), point.endHour))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            .chartYScale(domain: low...high)
            .chartYAxis {
                AxisMarks(values: Array(stride(from: low, through: high, by: high - low > 12 ? 3 : 2))) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text(RhythmSummary.clock(hours)) }
                    }
                }
            }
            .frame(height: 240)
        }
    }
}

/// "День заканчивается в 04:00": the setting, with a restart button when it changed.
struct DayBoundaryNote: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L.tr("Новый день начинается в", "A new day starts at"), selection: $settings.dayStartHour) {
                ForEach(0...5, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).tag(hour)
                }
            }
            .frame(maxWidth: 320)
            Text(L.tr("Работа после полуночи до этого часа считается во вчерашний день.",
                      "Work after midnight until this hour counts for the previous day."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.dayStartHour != AppServices.shared.days.startHour {
                HStack {
                    Text(L.tr("Применится после перезапуска: вся история пересчитается.",
                              "Takes effect after a restart: the whole history is recomputed."))
                        .font(.caption)
                    Button(L.tr("Перезапустить", "Restart")) { AppDelegate.restart() }
                }
                .padding(8)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// GitHub-style calendar of one calendar year: columns are weeks, rows Monday…Sunday, darker = more time.
struct YearCalendar: View {
    let stats: [DayStat]
    let days: DayCalendar
    let year: Int
    let today: Date

    @State private var hovered: Date?
    private let cell: CGFloat = 13
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 26

    private static let levels: [TimeInterval] = [1, 3600, 3 * 3600, 5 * 3600, 8 * 3600]

    var body: some View {
        let yearStart = days.date(fromKey: String(format: "%04d-01-01", year)) ?? today
        let yearEnd = days.date(fromKey: String(format: "%04d-12-31", year)) ?? today
        let firstWeek = days.startOfWeek(yearStart)
        let weeks = days.dayCount(from: firstWeek, to: yearEnd) / 7 + 1
        let byDay = Dictionary(stats.map { (days.key($0.day), $0.seconds) }, uniquingKeysWith: +)
        let total = stats.reduce(0) { $0 + $1.seconds }
        let active = stats.filter { $0.seconds > 0 }.count
        let visible: (Date) -> Bool = { day in day >= yearStart && day <= yearEnd && day <= today }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.tr("За \(String(year)) год: \(Format.duration(total)), активных дней: \(active)",
                          "\(String(year)): \(Format.duration(total)), active days: \(active)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hoverText(byDay))
                    .font(.caption.monospacedDigit())
            }
            Canvas { context, _ in
                let weekdays = [L.tr("пн", "Mon"), L.tr("ср", "Wed"), L.tr("пт", "Fri")]
                for (index, row) in [0, 2, 4].enumerated() {
                    context.draw(Text(weekdays[index]).font(.system(size: 9)).foregroundColor(.secondary),
                                 at: CGPoint(x: 0, y: CGFloat(row) * (cell + gap) + cell / 2), anchor: .leading)
                }
                for week in 0..<weeks {
                    for weekday in 0..<7 {
                        let day = days.addingDays(week * 7 + weekday, to: firstWeek)
                        guard visible(day) else { continue }
                        let rect = CGRect(x: labelWidth + CGFloat(week) * (cell + gap),
                                          y: CGFloat(weekday) * (cell + gap), width: cell, height: cell)
                        let seconds = byDay[days.key(day)] ?? 0
                        let color = day == hovered ? Color.primary : Self.color(seconds)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                    }
                }
            }
            .frame(width: labelWidth + CGFloat(weeks) * (cell + gap), height: 7 * (cell + gap))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let week = Int((point.x - labelWidth) / (cell + gap))
                    let weekday = Int(point.y / (cell + gap))
                    if point.x >= labelWidth, (0..<weeks).contains(week), (0..<7).contains(weekday) {
                        let day = days.addingDays(week * 7 + weekday, to: firstWeek)
                        hovered = visible(day) ? day : nil
                    } else {
                        hovered = nil
                    }
                case .ended:
                    hovered = nil
                }
            }
            HStack(spacing: 4) {
                Text(L.tr("меньше", "less")).font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0] + Self.levels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(level)).frame(width: 11, height: 11)
                }
                Text(L.tr("больше (8ч+)", "more (8h+)")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private static func color(_ seconds: TimeInterval) -> Color {
        guard seconds > 0 else { return Color.gray.opacity(0.15) }
        let level = levels.lastIndex { seconds >= $0 } ?? 0
        return Color.accentColor.opacity(0.25 + Double(level) * 0.18)
    }

    private func hoverText(_ byDay: [String: TimeInterval]) -> String {
        guard let hovered else { return L.tr("наведи на день", "hover over a day") }
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = L.current == .en ? "EEE, MMM d, yyyy" : "EEE, d MMM yyyy"
        return "\(formatter.string(from: hovered)) · \(Format.duration(byDay[days.key(hovered)] ?? 0))"
    }
}

// MARK: - Comparison

struct ComparisonPane: View {
    @EnvironmentObject private var insights: InsightsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker(L.tr("Сравнить", "Compare"), selection: $insights.comparisonMode) {
                    ForEach(InsightsModel.ComparisonMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let comparison = insights.comparison {
                    let titles = insights.comparisonMode.sideTitles
                    ComparisonSummary(comparison: comparison, titles: titles)
                    ComparisonTable(title: L.tr("Приложения", "Apps"), rows: comparison.apps, titles: titles)
                    ComparisonTable(title: L.tr("Сайты", "Sites"), rows: comparison.sites, titles: titles)
                    Text(L.tr("Время — в среднем за день периода. Нажми на строку, чтобы увидеть тренд за 90 дней.",
                              "Times are averages per day of each period. Click a row for its 90-day trend."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = insights.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { insights.reloadComparison() }
    }
}

private struct ComparisonSummary: View {
    let comparison: UsageComparison
    let titles: (String, String)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            side(titles.0, comparison.first)
            side(titles.1, comparison.second)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.tr("Разница в день", "Difference per day")).font(.caption).foregroundStyle(.secondary)
                Text(DeltaText.text(comparison.first.perDay - comparison.second.perDay))
                    .font(.title2.weight(.semibold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func side(_ title: String, _ side: UsageComparison.Side) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.duration(side.perDay) + L.tr(" в день", " a day"))
                .font(.title2.weight(.semibold)).monospacedDigit()
            Text(L.tr("всего \(Format.duration(side.total)), активных дней \(side.activeDays) из \(side.days)",
                      "total \(Format.duration(side.total)), active days \(side.activeDays) of \(side.days)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DeltaText {
    /// +12м / −1ч 5м / 0.
    static func text(_ seconds: TimeInterval) -> String {
        if abs(seconds) < 30 { return "0" }
        return (seconds > 0 ? "+" : "−") + Format.duration(abs(seconds))
    }
}

private struct ComparisonTable: View {
    let title: String
    let rows: [ComparisonRow]
    let titles: (String, String)

    @EnvironmentObject private var insights: InsightsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(titles.0).frame(width: 110, alignment: .trailing)
                Text(titles.1).frame(width: 110, alignment: .trailing)
                Text(L.tr("Разница", "Change")).frame(width: 90, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if rows.isEmpty { EmptyNote() }
            ForEach(rows) { row in
                HStack {
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                    if row.isNew { badge(L.tr("новое", "new"), .green) }
                    if row.isGone { badge(L.tr("пропало", "gone"), .gray) }
                    Spacer()
                    Text(Format.duration(row.first)).frame(width: 110, alignment: .trailing)
                    Text(Format.duration(row.second)).frame(width: 110, alignment: .trailing)
                    Text(DeltaText.text(row.delta))
                        .foregroundStyle(row.delta > 0 ? Color.orange : Color.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
                .monospacedDigit()
                .contentShape(Rectangle())
                .onTapGesture { insights.showTrend(row.target, name: row.name) }
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule())
    }
}

// MARK: - Trend card

struct TrendSheet: View {
    let card: InsightsModel.TrendCard
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(card.name).font(.title2.weight(.semibold)).lineLimit(1)
                Text(L.tr("за 90 дней", "over 90 days")).foregroundStyle(.secondary)
                Spacer()
            }
            if let error = card.error {
                Text(error).foregroundStyle(.red)
            } else if let trend = card.trend {
                summary(trend)
                Chart {
                    ForEach(trend.points) { point in
                        BarMark(x: .value(L.tr("День", "Day"), point.day, unit: .day),
                                y: .value(L.tr("Минуты", "Minutes"), point.seconds / 60))
                            .foregroundStyle(Color.accentColor.opacity(0.45))
                    }
                    ForEach(trend.points) { point in
                        LineMark(x: .value(L.tr("День", "Day"), point.day, unit: .day),
                                 y: .value(L.tr("Среднее за 7 дней", "7-day average"), point.average / 60))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) { Text(Format.duration(minutes * 60)) }
                        }
                    }
                }
                .frame(height: 220)
                Text(L.tr("Столбики — минуты в день, линия — среднее за 7 дней.", "Bars: minutes per day; line: 7-day average."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !card.titles.isEmpty {
                    Text(L.tr("Чаще всего", "Most of the time")).font(.headline)
                    ForEach(card.titles) { title in
                        HStack {
                            Text(title.title).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.duration(title.seconds)).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L.tr("Готово", "Done"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 600)
    }

    private func summary(_ trend: UsageTrend) -> some View {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = L.current == .en ? "MMM d" : "d MMM"
        var parts = [L.tr("в среднем \(Format.duration(trend.averagePerDay)) в день",
                          "\(Format.duration(trend.averagePerDay)) a day on average"),
                     L.tr("дней с использованием: \(trend.activeDays)", "days used: \(trend.activeDays)")]
        if let slope = trend.slopePerWeek {
            parts.append(abs(slope) < 60
                ? L.tr("держится ровно", "holding steady")
                : L.tr("\(DeltaText.text(slope)) в неделю", "\(DeltaText.text(slope)) per week"))
        } else {
            parts.append(L.tr("для тренда мало данных (нужно 14+ дней)", "too little data for a trend (14+ days needed)"))
        }
        if let record = trend.record {
            parts.append(L.tr("рекорд \(Format.duration(record.seconds)) (\(formatter.string(from: record.day)))",
                              "record \(Format.duration(record.seconds)) (\(formatter.string(from: record.day)))"))
        }
        return Text(parts.joined(separator: " · "))
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Stability

struct StabilityPane: View {
    @EnvironmentObject private var stability: StabilityMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let report = stability.report {
                    let uptime = stability.bootTime.map { Date().timeIntervalSince($0) }
                    StabilityVerdictCard(verdict: report.verdict(uptime: uptime))
                    StabilitySummary(report: report, uptime: uptime)
                    StabilityWeeksChart(weeks: report.weeks)
                    HStack(alignment: .top, spacing: 24) {
                        StabilityApps(title: L.tr("Твои программы (30 дней)", "Your programs (30 days)"),
                                      empty: L.tr("Ни одна не падала", "None crashed"),
                                      apps: report.apps.filter { !$0.isSystem })
                        StabilityApps(title: L.tr("Службы macOS (30 дней)", "macOS services (30 days)"),
                                      empty: L.tr("Сбоев не было", "No crashes"),
                                      apps: report.apps.filter(\.isSystem))
                    }
                    StabilityVersions(versions: report.versions)
                    StabilityList(events: report.recent)
                } else if let error = stability.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                HStack {
                    Button(L.tr("Открыть отчёты в Finder", "Show reports in Finder")) {
                        NSWorkspace.shared.open(StabilityMonitor.folders[0])
                    }
                    Spacer()
                }
                Text(L.tr("Отчёты о сбоях macOS пишет сама и через несколько недель удаляет. Приложение запоминает их коротко (название, время, тип), поэтому история здесь длиннее.",
                          "macOS writes crash reports itself and deletes them after a few weeks. The app keeps a short note of each (name, time, type), so the history here goes back further."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { stability.reload() }
    }
}

/// "С Mac всё в порядке" / what to do.
private struct StabilityVerdictCard: View {
    let verdict: StabilityVerdict

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(verdict.title).font(.title3.weight(.semibold))
                ForEach(verdict.details, id: \.self) { line in
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if verdict.suggestRestart {
                    Label(L.tr("Пора перезагрузить Mac", "Time to restart the Mac"), systemImage: "arrow.clockwise")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var symbol: String {
        switch verdict.level {
        case .ok: return "checkmark.seal.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch verdict.level {
        case .ok: return .green
        case .attention: return .orange
        case .problem: return .red
        }
    }
}

private struct StabilitySummary: View {
    let report: StabilityReport
    let uptime: TimeInterval?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            metric(L.tr("Сбои программ, 7 дней", "Program crashes, 7 days"), "\(report.crashes7 - report.serviceCrashes7)",
                   L.tr("то, что ты запускаешь сам", "what you run yourself"))
            metric(L.tr("Сбои служб macOS, 7 дней", "macOS service crashes, 7 days"), "\(report.serviceCrashes7)",
                   L.tr("перезапускаются сами", "restart by themselves"))
            metric(L.tr("Зависания, 7 дней", "Hangs, 7 days"), "\(report.hangs7)",
                   L.tr("программа не отвечала", "a program stopped responding"))
            metric(L.tr("Kernel panic, 30 дней", "Kernel panics, 30 days"), "\(report.panics30)",
                   L.tr("Mac перезагрузился сам", "the Mac restarted itself"))
            metric(L.tr("Без перезагрузки", "Since restart"), uptime.map(Format.longDuration) ?? "—", nil)
        }
    }

    private func metric(_ title: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StabilityWeeksChart: View {
    let weeks: [StabilityReport.Week]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.tr("По неделям", "By week")).font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(weeks) { week in
                    bar(week, week.crashes, L.tr("Сбои программ", "Program crashes"))
                    bar(week, week.serviceCrashes, L.tr("Сбои служб macOS", "macOS service crashes"))
                    bar(week, week.hangs, L.tr("Зависания", "Hangs"))
                    bar(week, week.other, L.tr("Нагрузка и предупреждения", "Load and warnings"))
                }
            }
            .chartForegroundStyleScale([
                L.tr("Сбои программ", "Program crashes"): Color.red,
                L.tr("Сбои служб macOS", "macOS service crashes"): Color.blue,
                L.tr("Зависания", "Hangs"): Color.orange,
                L.tr("Нагрузка и предупреждения", "Load and warnings"): Color.gray.opacity(0.6),
            ])
            .frame(height: 160)
            Text(L.tr("«Нагрузка и предупреждения» — не сбои: macOS записывает, что программа долго грузила процессор, много писала на диск или не хватало памяти.",
                      "“Load and warnings” are not crashes: macOS notes that a program kept the CPU busy, wrote a lot to disk, or memory ran short."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bar(_ week: StabilityReport.Week, _ count: Int, _ kind: String) -> some ChartContent {
        BarMark(x: .value(L.tr("Неделя", "Week"), week.start, unit: .weekOfYear),
                y: .value(L.tr("Число", "Count"), count))
            .foregroundStyle(by: .value(L.tr("Тип", "Kind"), kind))
    }
}

private struct StabilityApps: View {
    let title: String
    let empty: String
    let apps: [StabilityReport.AppCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if apps.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(apps.prefix(8)) { app in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(counts(app)).font(.caption).monospacedDigit()
                    }
                    if let description = StabilityNames.describe(app.name) {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func counts(_ app: StabilityReport.AppCount) -> String {
        var parts: [String] = []
        if app.crashes > 0 { parts.append(L.tr("сбоев: \(app.crashes)", "crashes: \(app.crashes)")) }
        if app.hangs > 0 { parts.append(L.tr("зависаний: \(app.hangs)", "hangs: \(app.hangs)")) }
        return parts.joined(separator: " · ")
    }
}

private struct StabilityVersions: View {
    let versions: [StabilityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.tr("Версии macOS", "macOS versions")).font(.headline)
            ForEach(versions) { event in
                HStack {
                    Text(event.name).lineLimit(1)
                    Text(event.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(StabilityList.date(event.at)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StabilityList: View {
    let events: [StabilityEvent]

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = L.current == .en ? "MMM d, HH:mm" : "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.tr("События", "Events")).font(.headline)
            if events.isEmpty { EmptyNote(text: L.tr("Пока ничего не случилось.", "Nothing has happened yet.")) }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.date(event.at))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Image(systemName: symbol(event))
                            .foregroundStyle(color(event))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(title(event)): \(event.name)").font(.callout).lineLimit(1)
                            ForEach(notes(event), id: \.self) { note in
                                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func isService(_ event: StabilityEvent) -> Bool {
        (event.kind == .crash || event.kind == .hang) && StabilityNames.isSystem(event.name)
    }

    private func notes(_ event: StabilityEvent) -> [String] {
        var notes: [String] = []
        if isService(event) {
            let what = StabilityNames.describe(event.name).map { L.tr("служба macOS: \($0)", "macOS service: \($0)") }
                ?? L.tr("фоновая служба macOS", "macOS background service")
            notes.append(what + L.tr(", перезапускается сама", ", restarts by itself"))
        }
        if event.kind == .resource {
            notes.append(L.tr("не сбой: macOS отметила большую нагрузку", "not a crash: macOS noted heavy use"))
        }
        if !event.detail.isEmpty { notes.append(event.detail) }
        return notes
    }

    private func title(_ event: StabilityEvent) -> String {
        switch event.kind {
        case .crash: return isService(event) ? L.tr("Сбой службы", "Service crash") : L.tr("Сбой программы", "Program crash")
        case .hang: return L.tr("Зависание", "Hang")
        case .panic: return "Kernel panic"
        case .resource: return L.tr("Нагрузка", "Heavy use")
        case .memory: return L.tr("Нехватка памяти", "Low memory")
        case .shutdown: return L.tr("Прошлое выключение", "Last shutdown")
        case .boot: return L.tr("Включение", "Boot")
        case .os: return "macOS"
        case .other: return L.tr("Отчёт", "Report")
        }
    }

    private func symbol(_ event: StabilityEvent) -> String {
        switch event.kind {
        case .crash: return isService(event) ? "arrow.triangle.2.circlepath" : "xmark.octagon"
        case .hang: return "hourglass"
        case .panic: return "exclamationmark.triangle.fill"
        case .resource: return "gauge.with.dots.needle.67percent"
        case .memory: return "memorychip"
        case .shutdown: return "power"
        case .boot: return "power.circle"
        case .os: return "arrow.down.circle"
        case .other: return "doc.text"
        }
    }

    private func color(_ event: StabilityEvent) -> Color {
        switch event.kind {
        case .crash: return isService(event) ? .blue : .red
        case .panic: return .red
        case .hang, .memory: return .orange
        default: return .secondary
        }
    }
}
