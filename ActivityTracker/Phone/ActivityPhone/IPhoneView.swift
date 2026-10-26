import Charts
import SwiftUI
import ActivityCore

/// The iPhone's own battery and traffic, from readings taken whenever the app runs.
struct IPhoneView: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var span = 7

    var body: some View {
        NavigationStack {
            List {
                if let last = model.meter.last {
                    Section(L.tr("Сейчас", "Now")) {
                        if let battery = last.battery {
                            LabeledContent(L.tr("Заряд", "Charge"),
                                           value: "\(Int(battery.rounded()))%" + (last.charging ? L.tr(", заряжается", ", charging") : ""))
                        }
                        LabeledContent(L.tr("Включён с", "On since"), value: last.bootTime.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                let daily = PhoneMeter.daily(model.meter, days: model.days)
                let recent = daily.filter { $0.day >= model.days.addingDays(-(span - 1), to: model.days.startOfDay(Date())) }
                Section {
                    Picker(L.tr("Период", "Period"), selection: $span) {
                        Text(L.tr("День", "Day")).tag(1)
                        Text(L.tr("7д", "7d")).tag(7)
                        Text(L.tr("30д", "30d")).tag(30)
                        Text(L.tr("90д", "90d")).tag(90)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Wi-Fi", value: Format.bytes(recent.reduce(0) { $0 + $1.wifi }))
                    LabeledContent(L.tr("Мобильная сеть", "Cellular"), value: Format.bytes(recent.reduce(0) { $0 + $1.cellular }))
                    LabeledContent(L.tr("Батарея израсходована", "Battery used"),
                                   value: "\(Int(recent.reduce(0) { $0 + $1.batteryUsed }.rounded()))%")
                    if span > 1 && !recent.isEmpty {
                        Chart(recent) { day in
                            BarMark(x: .value(L.tr("День", "Day"), day.day, unit: .day), y: .value("MB", day.wifi / 1_000_000))
                                .foregroundStyle(by: .value(L.tr("Сеть", "Network"), "Wi-Fi"))
                            BarMark(x: .value(L.tr("День", "Day"), day.day, unit: .day), y: .value("MB", day.cellular / 1_000_000))
                                .foregroundStyle(by: .value(L.tr("Сеть", "Network"), L.tr("Мобильная", "Cellular")))
                        }
                        .chartYAxisLabel(L.tr("МБ", "MB"))
                        .frame(height: 160)
                    }
                } header: {
                    Text(L.tr("Трафик и батарея", "Traffic and battery"))
                } footer: {
                    Text(L.tr("iOS не даёт приложениям работать постоянно: замеры делаются, когда приложение открыто или его ненадолго будит система. Трафик между замерами считается точно, но после перезагрузки iPhone счётчики обнуляются, и промежуток до первого замера теряется. Время по приложениям iPhone Apple открывает только через Экранное время (нужен платный аккаунт разработчика).",
                              "iOS doesn't let apps run all the time: readings are taken when the app is open or briefly woken by the system. Traffic between readings is exact, but a restart of the iPhone resets the counters and the gap before the first reading is lost. Per-app time on the iPhone is only available through Screen Time (needs a paid developer account)."))
                }
            }
            .navigationTitle("iPhone")
            .refreshable { model.recordMeter() }
            .onAppear { model.recordMeter() }
        }
    }
}
