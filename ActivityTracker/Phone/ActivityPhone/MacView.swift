import Charts
import SwiftUI
import ActivityCore

/// The Mac's statistics from the last snapshot.
struct MacView: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var range = StatsRange.day.rawValue

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.snapshot {
                    report(snapshot)
                } else {
                    empty
                }
            }
            .navigationTitle(model.snapshot?.macName ?? "Mac")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.syncing {
                        ProgressView()
                    } else if model.pairing != nil {
                        Button { Task { await model.sync() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(model.pairing == nil ? L.tr("Не связан с Mac", "Not paired with a Mac") : L.tr("Ещё нет данных", "No data yet"),
                  systemImage: "laptopcomputer.and.iphone")
        } description: {
            if model.pairing == nil {
                Text(L.tr("На Mac: ActivityTracker → Настройки → iPhone → «Связать с iPhone». Здесь: вкладка «Настройки» → «Связать с Mac».",
                          "On the Mac: ActivityTracker → Settings → iPhone → “Pair with an iPhone”. Here: the Settings tab → “Pair with Mac”."))
            } else {
                Text(model.lastError ?? L.tr("Mac и iPhone должны быть в одной сети: Wi-Fi или режим модема.", "The Mac and the iPhone must be on one network: Wi-Fi or the hotspot."))
            }
        } actions: {
            if model.pairing != nil {
                Button(L.tr("Обновить", "Refresh")) { Task { await model.sync() } }
            }
        }
    }

    private func report(_ snapshot: PhoneSnapshot) -> some View {
        let period = snapshot.periods.first { $0.range == range } ?? snapshot.periods.first
        return List {
            Section {
                status(snapshot)
                Picker(L.tr("Период", "Period"), selection: $range) {
                    ForEach(snapshot.periods) { period in
                        Text(period.statsRange?.title ?? period.range).tag(period.range)
                    }
                }
                .pickerStyle(.segmented)
                if let period { totals(period) }
            }
            if let period {
                if !period.bars.isEmpty && period.total > 0 {
                    Section { chart(period) }
                }
                if !period.summary.isEmpty {
                    Section(L.tr("День словами", "The day in words")) {
                        ForEach(Array(period.summary.enumerated()), id: \.offset) { Text($0.element) }
                    }
                }
                if !period.apps.isEmpty {
                    Section(L.tr("Приложения", "Apps")) {
                        ForEach(period.apps) { UsageRow(item: $0, total: period.total) }
                    }
                }
                if !period.sites.isEmpty {
                    Section(L.tr("Сайты", "Sites")) {
                        ForEach(period.sites) { UsageRow(item: $0, total: period.total) }
                    }
                }
                if !period.networks.isEmpty {
                    Section(L.tr("Сеть Mac", "Mac network")) {
                        LabeledContent(L.tr("Всего", "Total"), value: "↓ \(Format.bytes(period.networkRx))  ↑ \(Format.bytes(period.networkTx))")
                        ForEach(period.networks) { NetworkRow(network: $0) }
                    }
                }
            }
            if let battery = snapshot.battery {
                Section(L.tr("Батарея Mac", "Mac battery")) {
                    if let percent = battery.percent {
                        LabeledContent(L.tr("Заряд", "Charge"),
                                       value: "\(Int(percent.rounded()))%" + (battery.charging ? L.tr(", заряжается", ", charging") : ""))
                    }
                    if let drain = battery.drainPerHour {
                        LabeledContent(L.tr("Расход от батареи", "Drain on battery"), value: String(format: "%.1f%%/h", drain))
                    }
                    LabeledContent(L.tr("От батареи сегодня", "On battery today"), value: Format.duration(battery.timeOnBatteryToday))
                    if let health = battery.health {
                        LabeledContent(L.tr("Здоровье", "Health"), value: "\(Int(health.rounded()))%")
                    }
                    if let cycles = battery.cycles {
                        LabeledContent(L.tr("Циклы", "Cycles"), value: "\(cycles)")
                    }
                }
            }
        }
        .refreshable { await model.sync() }
    }

    private func status(_ snapshot: PhoneSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.tr("Данные на \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)) (\(Format.relative(snapshot.generatedAt)))",
                      "Data as of \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)) (\(Format.relative(snapshot.generatedAt)))"))
                .font(.footnote)
            if let error = model.lastError {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func totals(_ period: PhoneSnapshot.Period) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.duration(period.total)).font(.largeTitle.bold())
            if period.range != StatsRange.day.rawValue, period.activeDays > 0 {
                Text(L.tr("в среднем \(Format.duration(period.total / Double(period.activeDays))) за активный день · дней: \(period.activeDays)",
                          "\(Format.duration(period.total / Double(period.activeDays))) per active day on average · days: \(period.activeDays)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chart(_ period: PhoneSnapshot.Period) -> some View {
        let unit: Calendar.Component = period.barUnit == "hour" ? .hour : (period.barUnit == "week" ? .weekOfYear : .day)
        return Chart(period.bars) { bar in
            BarMark(x: .value(L.tr("Время", "Time"), bar.start, unit: unit),
                    y: .value(L.tr("Часы", "Hours"), bar.seconds / 3600))
                .foregroundStyle(Color.accentColor)
        }
        .chartYAxisLabel(L.tr("ч", "h"))
        .frame(height: 160)
    }
}

struct UsageRow: View {
    let item: PhoneSnapshot.Item
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name).lineLimit(1)
                Spacer()
                Text(Format.duration(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(2, geometry.size.width * (total > 0 ? item.seconds / total : 0)))
            }
            .frame(height: 4)
        }
    }
}

struct NetworkRow: View {
    let network: PhoneSnapshot.Network

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(network.name).lineLimit(1)
                Spacer()
                Text("↓ \(Format.bytes(network.rx))  ↑ \(Format.bytes(network.tx))").font(.footnote).monospacedDigit()
            }
            let details = [
                network.averageDown.map { L.tr("скорость \(Format.bitrate($0))", "speed \(Format.bitrate($0))") },
                network.pingInternet.map { L.tr("пинг \(Format.milliseconds($0))", "ping \(Format.milliseconds($0))") },
                network.outages > 0 ? L.tr("обрывов: \(network.outages)", "outages: \(network.outages)") : nil,
            ].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
