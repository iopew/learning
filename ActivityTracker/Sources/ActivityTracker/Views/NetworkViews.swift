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
                    Text(L.tr("Чтобы видеть названия Wi-Fi сетей, разреши ActivityTracker геолокацию: Системные настройки → Конфиденциальность и безопасность → Службы геолокации. Координаты не читаются.",
                              "To see Wi-Fi network names, allow Location Services for ActivityTracker: System Settings → Privacy & Security → Location Services. No coordinates are read."))
                        .font(.caption)
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
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    cell(L.tr("Скачано ↓", "Downloaded ↓"), Format.bytes(network.rx))
                    cell(L.tr("Отправлено ↑", "Uploaded ↑"), Format.bytes(network.tx))
                    cell(L.tr("Подключён", "Connected"), Format.duration(network.connected))
                }
                GridRow {
                    cell(L.tr("Средняя скорость ↓", "Average speed ↓"), network.averageDown.map(Format.bitrate) ?? "—")
                    cell(L.tr("Средняя скорость ↑", "Average speed ↑"), network.averageUp.map(Format.bitrate) ?? "—")
                    cell(L.tr("Пик ↓ / ↑", "Peak ↓ / ↑"), "\(Format.bitrate(network.peakDown)) / \(Format.bitrate(network.peakUp))")
                }
                GridRow {
                    cell(L.tr("Пинг до интернета", "Ping to the internet"), network.pingInternet.map(Format.milliseconds) ?? "—")
                    cell(L.tr("Пинг до роутера", "Ping to the router"), network.pingRouter.map(Format.milliseconds) ?? "—")
                    cell(L.tr("Потери пакетов", "Packet loss"), network.loss.map { Format.percent($0, of: 1) } ?? "—")
                }
                GridRow {
                    cell(L.tr("Скорость Wi-Fi", "Wi-Fi link"), network.linkRate.map { L.tr("\(Int($0)) Мбит/с", "\(Int($0)) Mbit/s") } ?? "—")
                    cell(L.tr("Сигнал", "Signal"), network.rssi.map { "\(Int($0)) dBm · " + signalWord($0) } ?? "—")
                    cell(L.tr("Обрывы", "Outages"), network.outages == 0 ? L.tr("не было", "none")
                         : L.tr("\(network.outages), всего \(Format.duration(network.outageTime))",
                                "\(network.outages), \(Format.duration(network.outageTime)) in total"))
                }
            }
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
        switch rssi {
        case -55...: return L.tr("отличный", "excellent")
        case -67 ..< -55: return L.tr("хороший", "good")
        case -75 ..< -67: return L.tr("средний", "fair")
        default: return L.tr("слабый", "weak")
        }
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .frame(minWidth: 180, alignment: .leading)
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
