import AppKit
import Charts
import SwiftUI
import ActivityCore

private func shortDate(_ date: Date, time: Bool = true) -> String {
    let formatter = DateFormatter()
    formatter.locale = L.locale
    formatter.dateFormat = time ? (L.current == .en ? "MMM d, HH:mm" : "d MMM, HH:mm") : (L.current == .en ? "MMM yyyy" : "LLLL yyyy")
    return formatter.string(from: date)
}

private struct SectionTitle: View {
    let text: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.headline)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Battery pane additions

/// What an hour of each activity costs, charges, wear forecast, nights and who kept the Mac awake.
struct BatteryDetails: View {
    let machine: MachineReport

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            costs
            charges
            forecast
            nights
        }
    }

    @ViewBuilder private var costs: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.tr("Сколько стоит час занятия", "What an hour of each activity costs"),
                         note: L.tr("Только время от батареи: сколько процентов в час уходило, пока это было на экране. Для периодов до 30 дней, от 15 минут на занятие.",
                                    "On battery only: percent per hour while it was on screen. For periods up to 30 days, from 15 minutes per activity."))
            if machine.costs.isEmpty {
                Text(L.tr("Пока мало данных от батареи за этот период.", "Not enough time on battery in this period yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(machine.costs.prefix(12)) { cost in
                HStack {
                    Text(cost.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(cost.percentPerHour.map { L.tr("\(Int($0.rounded()))% в час", "\(Int($0.rounded()))% an hour") } ?? "—")
                        .monospacedDigit().frame(width: 100, alignment: .trailing)
                    Text(cost.averageWatts.map { String(format: "%.1f W", $0) } ?? "—")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                    Text(Format.duration(cost.seconds)).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder private var charges: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.tr("Зарядки", "Charges"),
                         note: L.tr("Каждое подключение зарядки: с какого до какого процента, сколько ватт выдаёт адаптер и сколько реально шло в батарею.",
                                    "Every time the charger was plugged in: from and to what percent, the adapter's watts and what actually went into the battery."))
            if machine.charges.isEmpty {
                Text(L.tr("За этот период зарядка не подключалась.", "The charger wasn't plugged in during this period."))
                    .foregroundStyle(.secondary)
            }
            ForEach(machine.charges.prefix(15)) { charge in
                HStack(alignment: .firstTextBaseline) {
                    Text(shortDate(charge.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(percents(charge)).monospacedDigit()
                    Spacer()
                    if let rate = charge.percentPerHour {
                        Text(L.tr("+\(Int(rate.rounded()))% в час", "+\(Int(rate.rounded()))% an hour")).monospacedDigit()
                    }
                    Text(adapter(charge)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 200, alignment: .trailing)
                }
            }
        }
    }

    private func percents(_ charge: ChargeSession) -> String {
        let from = charge.startPercent.map { "\(Int($0.rounded()))%" } ?? "?"
        let to = charge.endPercent.map { "\(Int($0.rounded()))%" } ?? "?"
        let duration = charge.end.map { Format.duration($0.timeIntervalSince(charge.start)) } ?? L.tr("сейчас на зарядке", "charging now")
        return "\(from) → \(to) · \(duration)"
    }

    private func adapter(_ charge: ChargeSession) -> String {
        var parts: [String] = []
        if let watts = charge.adapterWatts { parts.append(L.tr("адаптер \(Int(watts)) Вт", "\(Int(watts)) W adapter")) }
        if let name = charge.adapterName { parts.append(name) }
        if let average = charge.averageChargeWatts { parts.append(L.tr("в батарею \(String(format: "%.0f", average)) Вт", "\(String(format: "%.0f", average)) W in")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var forecast: some View {
        if let forecast = machine.forecast {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: L.tr("Износ батареи", "Battery wear"),
                             note: L.tr("Apple считает батарею Mac рассчитанной на 1000 циклов и примерно 80% ёмкости к этому времени. Прогноз — по твоему темпу.",
                                        "Apple rates Mac batteries for 1000 cycles and about 80% capacity by then. The forecast follows your pace."))
                HStack(alignment: .top, spacing: 0) {
                    metric(L.tr("Здоровье", "Health"), forecast.health.map { "\(Int($0.rounded()))%" } ?? "—")
                    metric(L.tr("Циклов", "Cycles"), forecast.cycles.map { "\($0) / \(BatteryForecast.ratedCycles)" } ?? "—")
                    metric(L.tr("Циклов в месяц", "Cycles a month"), forecast.cyclesPerMonth.map { String(format: "%.0f", $0) } ?? "—")
                }
                if let date = forecast.cyclesLimitDate {
                    Text(L.tr("1000 циклов при таком темпе — примерно \(shortDate(date, time: false)).",
                              "1000 cycles at this pace — around \(shortDate(date, time: false)).")).font(.callout)
                }
                if let date = forecast.health80Date {
                    Text(L.tr("80% здоровья — примерно \(shortDate(date, time: false)).", "80% health — around \(shortDate(date, time: false)).")).font(.callout)
                }
                if forecast.cyclesLimitDate == nil, forecast.health80Date == nil {
                    Text(L.tr("Для прогноза нужно хотя бы 2 недели наблюдений (сейчас дней: \(forecast.historyDays)).",
                              "A forecast needs at least 2 weeks of history (days so far: \(forecast.historyDays))."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var nights: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.tr("Сон", "Sleep"),
                         note: L.tr("Сколько заряда уходит, пока Mac спит, и сколько раз он тайком просыпался (Power Nap, сеть, таймеры). Нормально — 1–3% за ночь.",
                                    "How much charge goes while the Mac sleeps and how often it woke up in the dark (Power Nap, network, timers). Normal is 1–3% a night."))
            if machine.nights.isEmpty {
                Text(L.tr("Пока не было сна от 15 минут в этом периоде.", "No sleep of 15+ minutes in this period yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(machine.nights.prefix(10)) { night in
                HStack {
                    Text("\(shortDate(night.start)) – \(shortDate(night.end))").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
                    Text(Format.duration(night.duration)).monospacedDigit()
                    Spacer()
                    if let drop = night.drop {
                        Text(drop >= 0 ? L.tr("−\(String(format: "%.0f", drop))% заряда", "−\(String(format: "%.0f", drop))% charge")
                                       : L.tr("заряжался", "charging"))
                            .foregroundStyle(drop >= 5 ? Color.orange : Color.primary)
                    }
                    if let wakes = night.darkWakes {
                        Text(L.tr("просыпался \(wakes) раз", "woke \(wakes) times")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !machine.blockers.isEmpty {
                Text(L.tr("Не давали Mac уснуть, пока тебя не было", "Kept the Mac awake while you were away"))
                    .font(.subheadline.weight(.semibold)).padding(.top, 6)
                ForEach(machine.blockers.prefix(8)) { blocker in
                    HStack {
                        Text(blocker.process).lineLimit(1)
                        Text(blocker.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.duration(blocker.seconds)).monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - System pane additions

/// Disk forecast and growth, SSD writes, swap, startup items.
struct SystemDetails: View {
    let machine: MachineReport

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            disk
            folders
            writes
            swap
            startup
        }
    }

    @ViewBuilder private var disk: some View {
        if let disk = machine.disk {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: L.tr("Диск", "Disk"))
                HStack(alignment: .top, spacing: 0) {
                    metric(L.tr("Свободно", "Free"), Format.bytes(disk.free))
                    metric(L.tr("Всего", "Total"), Format.bytes(disk.total))
                    metric(L.tr("За день", "Per day"), disk.perDay.map { ($0 >= 0 ? "+" : "−") + Format.bytes(abs($0)) } ?? "—")
                }
                if let days = disk.daysUntilFull {
                    Text(days < 365
                         ? L.tr("При таком темпе диск заполнится примерно через \(Int(days)) дн.", "At this pace the disk fills up in about \(Int(days)) days.")
                         : L.tr("Место уходит медленно — больше года в запасе.", "Space goes slowly: more than a year left."))
                        .font(.callout)
                        .foregroundStyle(days < 60 ? Color.orange : Color.primary)
                } else if disk.perDay != nil {
                    Text(L.tr("Свободное место не уменьшается.", "Free space isn't shrinking.")).font(.callout)
                }
            }
        }
    }

    @ViewBuilder private var folders: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.tr("Что занимает место", "What takes space"),
                         note: L.tr("Кэши и инструменты, измеряются раз в сутки. Загрузки, Документы и данные других приложений не читаются — для них macOS спросила бы разрешение.",
                                    "Caches and tools, measured once a day. Downloads, Documents and other apps' data aren't read: macOS would ask for permission."))
            if machine.folders.isEmpty {
                Text(L.tr("Первый замер — примерно через 10 минут после запуска.", "The first measurement comes about 10 minutes after launch."))
                    .foregroundStyle(.secondary)
            }
            ForEach(machine.folders) { folder in
                HStack {
                    Text(title(of: folder.path)).lineLimit(1)
                    Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Format.bytes(folder.bytes)).monospacedDigit()
                    Text(folder.weekChange.map { change in abs(change) < 1e6 ? "" : (change > 0 ? "+" : "−") + Format.bytes(abs(change)) } ?? "")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle((folder.weekChange ?? 0) > 1e9 ? Color.orange : Color.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .contextMenu {
                    Button(L.tr("Показать в Finder", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
                    }
                }
            }
            if machine.folders.contains(where: { $0.weekChange != nil }) {
                Text(L.tr("Справа — изменение за неделю.", "On the right: change over a week.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func title(of path: String) -> String {
        MachineMonitor.folders.first { $0.path == path }?.title ?? URL(fileURLWithPath: path).lastPathComponent
    }

    @ViewBuilder private var writes: some View {
        VStack(alignment: .leading, spacing: 6) {
            let total = machine.writes.reduce(0) { $0 + $1.bytes }
            SectionTitle(text: L.tr("Запись на диск", "Disk writes"),
                         note: L.tr("SSD изнашивается от записи. Обычный ноутбучный SSD рассчитан на сотни терабайт, так что десятки гигабайт в день — нормально. Процент износа macOS без сторонних утилит не показывает.",
                                    "An SSD wears with writes. A typical laptop SSD is rated for hundreds of terabytes, so tens of gigabytes a day is fine. macOS doesn't show the wear percentage without third-party tools."))
            if machine.writes.isEmpty {
                Text(L.tr("Считается с этой сборки, по часам.", "Counted from this build on, hourly.")).foregroundStyle(.secondary)
            } else {
                Text(L.tr("За период: \(Format.bytes(total)), в среднем \(Format.bytes(total / Double(machine.writes.count))) в день",
                          "This period: \(Format.bytes(total)), \(Format.bytes(total / Double(machine.writes.count))) a day on average"))
                if machine.writes.count > 1 {
                    Chart(machine.writes) { day in
                        BarMark(x: .value(L.tr("День", "Day"), day.day, unit: .day), y: .value(L.tr("Записано", "Written"), day.bytes))
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel { if let bytes = value.as(Double.self) { Text(Format.bytes(bytes)) } }
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    @ViewBuilder private var swap: some View {
        let peak = machine.swapDaily.map(\.peak).max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.tr("Подкачка (своп)", "Swap"),
                         note: L.tr("Когда памяти не хватает, macOS выгружает её на диск. До 1–2 ГБ — нормально; постоянно больше — Mac тормозит и сильнее пишет на SSD.",
                                    "When memory runs short, macOS moves it to disk. Up to 1–2 GB is fine; constantly more means slowdowns and extra SSD writes."))
            Text(L.tr("Пик за период: \(Format.bytes(peak))", "Peak in this period: \(Format.bytes(peak))"))
                .foregroundStyle(peak >= 4e9 ? Color.orange : Color.primary)
            if machine.swapDaily.count > 1 {
                Chart(Array(machine.swapDaily.enumerated()), id: \.offset) { item in
                    LineMark(x: .value(L.tr("День", "Day"), item.element.day, unit: .day), y: .value(L.tr("Своп", "Swap"), item.element.peak))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let bytes = value.as(Double.self) { Text(Format.bytes(bytes)) } }
                    }
                }
                .frame(height: 110)
            }
        }
    }

    @ViewBuilder private var startup: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L.tr("Запускается само", "Starts by itself"),
                         note: L.tr("Фоновые службы из LaunchAgents и LaunchDaemons: обновлялки, синхронизация, помощники. «Новое» — появилось за последнюю неделю.",
                                    "Background services from LaunchAgents and LaunchDaemons: updaters, sync, helpers. “New”: appeared in the last week."))
            let active = machine.startup.filter { !$0.removed }
            if active.isEmpty {
                Text(L.tr("Первая проверка — примерно через 10 минут после запуска.", "The first check comes about 10 minutes after launch."))
                    .foregroundStyle(.secondary)
            }
            ForEach(active) { item in
                HStack {
                    if item.isNew {
                        Text(L.tr("новое", "new")).font(.caption2).padding(.horizontal, 5)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                    }
                    Text(item.label).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(URL(fileURLWithPath: item.program).lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .help(item.path)
                .contextMenu {
                    Button(L.tr("Показать файл в Finder", "Show the file in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                    }
                }
            }
            let removed = machine.startup.filter(\.removed)
            if !removed.isEmpty {
                Text(L.tr("Удалено: ", "Removed: ") + removed.prefix(5).map(\.label).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
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
