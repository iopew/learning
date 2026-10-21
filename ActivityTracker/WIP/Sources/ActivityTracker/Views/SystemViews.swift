import Charts
import SwiftUI
import ActivityCore

/// Battery: current state, how the period went, the level chart and which apps used the energy.
struct BatteryPanel: View {
    let system: SystemReport
    var chartHeight: CGFloat = 160

    @State private var onBatteryOnly = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !system.hasBattery {
                EmptyNote(text: L.tr("У этого Mac нет батареи.", "This Mac has no battery."))
            } else {
                if let latest = system.latest {
                    MetricGrid(items: [
                        (L.tr("Заряд", "Charge"), latest.batteryPercent.map { "\(Int($0.rounded()))%" } ?? "—"),
                        (L.tr("Сейчас", "Now"), stateText(latest)),
                        (L.tr("Здоровье", "Health"), latest.healthPercent.map { "\(Int($0.rounded()))%" } ?? "—"),
                        (L.tr("Циклы", "Cycles"), latest.cycleCount.map(String.init) ?? "—"),
                    ])
                }
                MetricGrid(items: [
                    (L.tr("Зарядок", "Charges"), "\(system.chargeCount)"),
                    (L.tr("От батареи", "On battery"), Format.duration(system.timeOnBattery)),
                    (L.tr("Расход", "Drain"), system.drainPerHour.map { String(format: L.tr("%.1f%% в час", "%.1f%%/h"), $0) } ?? "—"),
                    (L.tr("Хватит на", "Full charge lasts"), system.estimatedFullCharge.map { "≈ " + Format.duration($0) } ?? "—"),
                ])
                MetricGrid(items: [
                    (L.tr("Мощность", "Power draw"), system.averageDischargeWatts.map { String(format: L.tr("%.1f Вт", "%.1f W"), $0) } ?? "—"),
                    (L.tr("Температура макс.", "Max temperature"), system.maxBatteryTemperature.map { String(format: "%.0f°C", $0) } ?? "—"),
                    (L.tr("На 100% от сети", "At 100% plugged in"), Format.duration(system.timeFullOnAC)),
                    (L.tr("Циклов за период", "Cycles in period"), system.cyclesAdded.map(String.init) ?? "—"),
                ])

                if !system.batteryPoints.isEmpty {
                    Text(L.tr("Уровень заряда", "Battery level")).font(.caption).foregroundStyle(.secondary)
                    Chart(system.batteryPoints) { point in
                        if system.range != .day {
                            AreaMark(x: .value("t", point.at), yStart: .value("min", point.minPercent),
                                     yEnd: .value("max", point.maxPercent))
                                .foregroundStyle(Color.green.opacity(0.15))
                        }
                        LineMark(x: .value("t", point.at), y: .value("%", point.percent))
                            .foregroundStyle(Color.accentColor)
                        if point.charging {
                            PointMark(x: .value("t", point.at), y: .value("%", point.percent))
                                .symbolSize(10)
                                .foregroundStyle(Color.green)
                        }
                    }
                    .chartYScale(domain: 0.0...100.0)
                    .frame(height: chartHeight)
                }

                HStack {
                    Text(L.tr("Кто тратит энергию", "Energy by app")).font(.headline)
                    Spacer()
                    Picker("", selection: $onBatteryOnly) {
                        Text(L.tr("От батареи", "On battery")).tag(true)
                        Text(L.tr("Всё время", "All the time")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            EnergyList(usage: system.hasBattery && onBatteryOnly ? system.energyOnBattery : system.energyAll)
        }
    }

    private func stateText(_ sample: SystemSample) -> String {
        if sample.isCharging { return L.tr("Заряжается", "Charging") }
        if sample.onAC { return L.tr("От сети", "Plugged in") }
        return L.tr("От батареи", "On battery")
    }
}

struct EnergyList: View {
    let usage: [EnergyUsage]

    var body: some View {
        let total = usage.reduce(0) { $0 + $1.joules }
        LazyVStack(alignment: .leading, spacing: 8) {
            if usage.isEmpty {
                EmptyNote(text: L.tr("Пока нет данных — они появляются раз в минуту.",
                                     "No data yet — it is collected once a minute."))
            }
            ForEach(usage.prefix(20)) { app in
                UsageRow(color: .orange, name: app.appName, seconds: 0, total: 0, valueText: energyText(app.joules),
                         share: total > 0 ? app.joules / total : 0)
            }
            Text(L.tr("По данным macOS о каждом процессе (как колонка «Энергия» в Мониторе системы). Системные процессы macOS не учитываются.",
                      "From macOS per-process data (like the Energy column in Activity Monitor). macOS system processes are not included."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func energyText(_ joules: Double) -> String {
        let wattHours = joules / 3600
        return wattHours >= 1 ? String(format: L.tr("%.1f Вт·ч", "%.1f Wh"), wattHours)
                              : String(format: L.tr("%.0f мВт·ч", "%.0f mWh"), wattHours * 1000)
    }
}

/// CPU, memory, disk and heat.
struct SystemPanel: View {
    let system: SystemReport
    var chartHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !system.hasData {
                EmptyNote(text: L.tr("Пока нет данных — они появляются раз в минуту.",
                                     "No data yet — it is collected once a minute."))
            } else {
                MetricGrid(items: [
                    (L.tr("Процессор, среднее", "CPU, average"), percent(system.cpuAverage)),
                    (L.tr("Процессор, пик", "CPU, peak"), percent(system.cpuPeak)),
                    (L.tr("Память, пик", "Memory, peak"), percent(system.memoryPeak)),
                    (L.tr("Подкачка, пик", "Swap, peak"), system.swapPeak.map(Format.bytes) ?? "—"),
                ])
                MetricGrid(items: [
                    (L.tr("Свободно на диске", "Free disk space"), system.latest.map { Format.bytes($0.diskFree) } ?? "—"),
                    (L.tr("Перегрев", "Running hot"), Format.duration(system.hotTime)),
                    (L.tr("Тепло сейчас", "Thermal state"), thermalText(system.latest?.thermalState ?? 0)),
                    ("", ""),
                ])
                if !system.loadPoints.isEmpty {
                    Text(L.tr("Нагрузка процессора и памяти", "CPU and memory load"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(system.loadPoints) { point in
                        LineMark(x: .value("t", point.at), y: .value("%", point.cpu * 100), series: .value("s", "cpu"))
                            .foregroundStyle(Color.accentColor)
                        LineMark(x: .value("t", point.at), y: .value("%", point.memory * 100), series: .value("s", "mem"))
                            .foregroundStyle(Color.purple.opacity(0.7))
                    }
                    .chartYScale(domain: 0.0...100.0)
                    .frame(height: chartHeight)
                    HStack(spacing: 14) {
                        Label(L.tr("Процессор", "CPU"), systemImage: "circle.fill").foregroundStyle(Color.accentColor)
                        Label(L.tr("Память", "Memory"), systemImage: "circle.fill").foregroundStyle(Color.purple.opacity(0.7))
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    private func thermalText(_ state: Int) -> String {
        switch state {
        case 0: return L.tr("Норма", "Normal")
        case 1: return L.tr("Тёплый", "Warm")
        case 2: return L.tr("Горячий", "Hot")
        default: return L.tr("Критично", "Critical")
        }
    }
}

/// Today's tips as cards.
struct TipsPanel: View {
    let tips: [Recommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tips.isEmpty {
                TipCard(tip: Recommendation(
                    id: "ok", kind: .positive, symbol: "checkmark.seal",
                    title: L.tr("Всё в порядке", "All good"),
                    detail: L.tr("Сегодня никаких советов. Хорошего дня!", "No tips today. Have a good day!")))
            }
            ForEach(tips) { TipCard(tip: $0) }
        }
    }
}

struct TipCard: View {
    let tip: Recommendation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tip.symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(.callout.weight(.semibold))
                Text(tip.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch tip.kind {
        case .positive: return .green
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

/// Four small "title / value" metrics in a row.
struct MetricGrid: View {
    let items: [(String, String)]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(item.1).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
