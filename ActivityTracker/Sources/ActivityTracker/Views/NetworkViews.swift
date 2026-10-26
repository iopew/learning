import AppKit
import Charts
import SwiftUI
import ActivityCore

/// "Сеть": traffic per network and in total for the selected period, speeds, ping, outages.
struct NetworkPane: View {
    @EnvironmentObject private var stats: StatsModel
    /// Renaming and the Location hint only make sense for the live database.
    var isArchive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatsControls()
                if let report = stats.network {
                    NetworkSummary(report: report)
                    if report.hasData {
                        NetworkChart(report: report)
                        ForEach(report.networks) { network in
                            NetworkCard(network: network, share: report.total > 0 ? network.total / report.total : 0,
                                        isArchive: isArchive)
                        }
                    } else {
                        EmptyNote(text: L.tr("За этот период сеть не записана. Замеры идут раз в минуту, пока Mac в сети.",
                                             "No network data for this period. It is measured once a minute while the Mac is online."))
                    }
                } else if let error = stats.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if !isArchive, !AppServices.shared.network.namesAllowed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.tr("Чтобы видеть названия Wi-Fi сетей, macOS требует доступ к геолокации. Он нужен только для имени сети: координаты не читаются и не сохраняются.",
                                  "To show Wi-Fi network names, macOS requires Location access. It is used only for the network name: no coordinates are read or stored."))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L.tr("Показывать названия сетей", "Show network names")) { AppServices.shared.network.requestNames() }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }
                Text(L.tr("Трафик — всё, что прошло через Wi-Fi, кабель и модем (VPN не считается дважды). Средняя скорость — пока что-то реально скачивалось, а не в среднем за всё время. Скорость Wi-Fi — связь Mac с роутером. Пинг — раз в минуту до роутера и до 1.1.1.1. Обрыв — минута, когда интернет не ответил.",
                          "Traffic is everything over Wi-Fi, cable and tethering (VPN isn't counted twice). Average speed is while something was actually transferring, not over the whole time. Wi-Fi speed is the link between the Mac and the router. Ping: once a minute to the router and to 1.1.1.1. An outage is a minute when the internet didn't answer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct NetworkSummary: View {
    let report: NetworkReport

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            metric(L.tr("Всего", "Total"), Format.bytes(report.total))
            metric(L.tr("Скачано ↓", "Downloaded ↓"), Format.bytes(report.rx))
            metric(L.tr("Отправлено ↑", "Uploaded ↑"), Format.bytes(report.tx))
            metric(L.tr("Сетей", "Networks"), "\(report.networks.count)")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Traffic per hour / day / week, stacked by network.
private struct NetworkChart: View {
    let report: NetworkReport

    var body: some View {
        let unit: Calendar.Component = report.unit == .hour ? .hour : (report.unit == .day ? .day : .weekOfYear)
        VStack(alignment: .leading, spacing: 4) {
            Text(report.unit == .hour ? L.tr("Трафик по часам", "Traffic per hour")
                 : report.unit == .day ? L.tr("Трафик по дням", "Traffic per day") : L.tr("Трафик по неделям", "Traffic per week"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(report.buckets) { bucket in
                BarMark(x: .value(L.tr("Время", "Time"), bucket.start, unit: unit),
                        y: .value(L.tr("Трафик", "Traffic"), bucket.rx + bucket.tx))
                    .foregroundStyle(by: .value(L.tr("Сеть", "Network"), bucket.name))
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) { Text(Format.bytes(bytes)) }
                    }
                }
            }
            .frame(height: 220)
        }
    }
}

private struct NetworkCard: View {
    let network: NetworkUsage
    let share: Double
    let isArchive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).foregroundStyle(Color.accentColor)
                Text(network.name).font(.headline).lineLimit(1)
                Text(kindTitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.bytes(network.total)).font(.headline).monospacedDigit()
                Text(Format.percent(share, of: 1)).font(.caption).foregroundStyle(.secondary)
                if !isArchive {
                    Button {
                        rename()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(L.tr("Переименовать", "Rename"))
                }
            }
            if let verdict {
                Text(verdict).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    cell(L.tr("Скачано ↓", "Downloaded ↓"), Format.bytes(network.rx),
                         L.tr("Сколько данных пришло из интернета в эту сеть за период.", "Data received over this network in the period."))
                    cell(L.tr("Отправлено ↑", "Uploaded ↑"), Format.bytes(network.tx),
                         L.tr("Сколько данных Mac отправил: загрузки файлов, бэкапы, видеозвонки.", "Data the Mac sent: uploads, backups, video calls."))
                    cell(L.tr("Подключён", "Connected"), Format.duration(network.connected),
                         L.tr("Сколько времени Mac был в этой сети (пока не спал).", "How long the Mac was on this network (while awake)."))
                }
                GridRow {
                    cell(L.tr("Средняя скорость ↓", "Average speed ↓"), network.averageDown.map(Format.bitrate) ?? "—",
                         L.tr("С какой скоростью реально качалось, пока что-то качалось. Это не предел тарифа: сайт мог отдавать медленнее.",
                              "How fast data actually came while something was downloading. Not your plan's limit: the server may have been slower."))
                    cell(L.tr("Средняя скорость ↑", "Average speed ↑"), network.averageUp.map(Format.bitrate) ?? "—",
                         L.tr("То же для отправки.", "The same for uploads."))
                    cell(L.tr("Пик ↓ / ↑", "Peak ↓ / ↑"), "\(Format.bitrate(network.peakDown)) / \(Format.bitrate(network.peakUp))",
                         L.tr("Самая высокая скорость за 5 секунд. Ближе всего к тому, на что способна сеть.",
                              "The fastest 5 seconds. The closest to what the network can do."))
                }
                GridRow {
                    cell(L.tr("Пинг до интернета", "Ping to the internet"), network.pingInternet.map(Format.milliseconds) ?? "—",
                         L.tr("Задержка до сервера 1.1.1.1 в интернете. До 50 мс — отлично, 50–100 — нормально, больше 100 — заметно в играх и звонках.",
                              "Delay to the 1.1.1.1 server. Under 50 ms is great, 50–100 fine, over 100 noticeable in games and calls."))
                    cell(L.tr("Пинг до роутера", "Ping to the router"), network.pingRouter.map(Format.milliseconds) ?? "—",
                         L.tr("Задержка только по Wi-Fi или кабелю до роутера. До 10 мс — Wi-Fi в порядке; больше 20 — проблема в Wi-Fi, а не у провайдера.",
                              "Delay over Wi-Fi or cable to the router only. Under 10 ms: Wi-Fi is fine; over 20: the problem is the Wi-Fi, not the provider."))
                    cell(L.tr("Потери пакетов", "Packet loss"), network.loss.map { Format.percent($0, of: 1) } ?? "—",
                         L.tr("Доля пингов без ответа. Больше 1–2% — связь нестабильная: обрывы звонков, подвисания.",
                              "Share of pings without an answer. Over 1–2%: an unstable connection, dropped calls, stalls."))
                }
                GridRow {
                    cell(L.tr("Скорость Wi-Fi", "Wi-Fi link"), network.linkRate.map { L.tr("\(Int($0)) Мбит/с", "\(Int($0)) Mbit/s") } ?? "—",
                         L.tr("Скорость радиосвязи между Mac и роутером, а не скорость интернета. Интернет обычно медленнее: дальше роутера идёт линия провайдера.",
                              "The radio link between the Mac and the router, not the internet speed. The internet is usually slower: past the router it's the provider's line."))
                    cell(L.tr("Сигнал", "Signal"), network.rssi.map { "\(Int($0)) dBm · " + signalWord($0) } ?? "—",
                         L.tr("Сила сигнала Wi-Fi: ближе к нулю — лучше. −50 отлично, −67 хорошо, ниже −75 слабо.",
                              "Wi-Fi signal strength: closer to zero is better. −50 excellent, −67 good, below −75 weak."))
                    cell(L.tr("Обрывы", "Outages"), network.outages == 0 ? L.tr("не было", "none")
                         : L.tr("\(network.outages), всего \(Format.duration(network.outageTime))",
                                "\(network.outages), \(Format.duration(network.outageTime)) in total"),
                         L.tr("Минуты, когда сеть была, а интернет не отвечал.", "Minutes when the network was up but the internet didn't answer."))
                }
            }
            Text(L.tr("Наведи на показатель, чтобы увидеть, что он значит.", "Hover over a value to see what it means."))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(L.tr("Впервые: \(date(network.firstSeen)) · последний раз: \(date(network.lastSeen))",
                      "First seen: \(date(network.firstSeen)) · last: \(date(network.lastSeen))"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var symbol: String {
        switch network.kind {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .hotspot: return "personalhotspot"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }

    private var kindTitle: String {
        switch network.kind {
        case .wifi: return "Wi-Fi"
        case .ethernet: return L.tr("кабель", "cable")
        case .hotspot: return L.tr("точка доступа iPhone", "iPhone hotspot")
        case .cellular: return L.tr("сотовая", "cellular")
        case .other: return L.tr("другое", "other")
        }
    }

    private func signalWord(_ rssi: Double) -> String {
        if rssi >= -55 { return L.tr("отличный", "excellent") }
        if rssi >= -67 { return L.tr("хороший", "good") }
        if rssi >= -75 { return L.tr("средний", "fair") }
        return L.tr("слабый", "weak")
    }

    private func cell(_ title: String, _ value: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .frame(minWidth: 180, alignment: .leading)
        .contentShape(Rectangle())
        .help(help)
    }

    /// "Wi-Fi отличный, задержка — у провайдера": what the numbers mean together.
    private var verdict: String? {
        var parts: [String] = []
        let wifiWeak = (network.rssi.map { $0 < -72 } ?? false) || (network.pingRouter.map { $0 > 20 } ?? false)
        if network.kind == .wifi || network.kind == .hotspot, network.rssi != nil || network.pingRouter != nil {
            parts.append(wifiWeak ? L.tr("Wi-Fi слабый: подойди ближе к роутеру или убери преграды", "Weak Wi-Fi: move closer to the router or remove obstacles")
                                  : L.tr("Wi-Fi в порядке", "Wi-Fi is fine"))
        }
        if let ping = network.pingInternet {
            if ping > 100 {
                parts.append(wifiWeak ? L.tr("интернет с большой задержкой", "high internet delay")
                                      : L.tr("большая задержка у провайдера", "high delay at the provider"))
            } else {
                parts.append(L.tr("задержка интернета нормальная", "internet delay is normal"))
            }
        }
        if let loss = network.loss, loss > 0.02 {
            parts.append(L.tr("теряются пакеты — связь нестабильная", "packets get lost: the connection is unstable"))
        }
        if network.outages > 0 {
            parts.append(L.tr("были обрывы интернета", "the internet dropped out"))
        }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    private func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = L.current == .en ? "MMM d, HH:mm" : "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    private func rename() {
        let alert = NSAlert()
        alert.messageText = L.tr("Название сети", "Network name")
        alert.informativeText = L.tr("Пустое поле вернёт название, которое определил Mac.", "Leave empty to use the name the Mac detected.")
        let field = NSTextField(string: network.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L.tr("Сохранить", "Save"))
        alert.addButton(withTitle: L.tr("Отмена", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try AppServices.shared.networkStore.rename(network.key, to: field.stringValue)
        } catch {
            NSLog("ActivityTracker: rename network: \(error)")
        }
        NotificationCenter.default.post(name: .activityDataChanged, object: nil)
    }
}
