import AppKit
import SwiftUI
import ActivityCore

struct SettingsView: View {
    let databaseURL: URL

    @EnvironmentObject private var settings: Settings
    @State private var accessibilityGranted = WindowTitle.isTrusted
    /// SMAppService status is an IPC call: read it on appear / every poll, not on every redraw.
    @State private var launchAtLogin = false
    @State private var deniedBrowsers: [String] = []
    @State private var diagnosticsStatus: String?

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker(L.tr("Язык", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(Settings.title(of: language)).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Picker(L.tr("Оформление", "Appearance"), selection: $settings.appearance) {
                    ForEach(Settings.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Picker(L.tr("Строка меню", "Menu bar"), selection: $settings.menuBarStyle) {
                    ForEach(Settings.MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                if settings.menuBarStyle == .hidden {
                    Text(L.tr("Трекер работает молча. Статистика — через Launchpad, Dock или двойной клик по приложению.", "The tracker runs silently. Open statistics from Launchpad, the Dock or by double-clicking the app."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(L.tr("Запускать при входе в систему", "Launch at login"), isOn: Binding(
                    get: { launchAtLogin },
                    set: {
                        settings.launchAtLogin = $0
                        launchAtLogin = settings.launchAtLogin
                    }))
                Toggle(L.tr("Всегда показывать значок в Dock (иначе — только пока открыто окно)", "Always show the Dock icon (otherwise only while the window is open)"),
                       isOn: $settings.alwaysShowInDock)

                Picker(L.tr("Считать, что меня нет, после", "Consider me away after"), selection: $settings.idleThreshold) {
                    Text(L.tr("1 мин", "1 min")).tag(60.0)
                    Text(L.tr("2 мин", "2 min")).tag(120.0)
                    Text(L.tr("3 мин", "3 min")).tag(180.0)
                    Text(L.tr("5 мин", "5 min")).tag(300.0)
                    Text(L.tr("10 мин", "10 min")).tag(600.0)
                }
                Toggle(L.tr("Видео и звонки без мыши и клавиатуры — тоже активность", "Video and calls without mouse or keyboard count as activity"),
                       isOn: $settings.countMediaAsActive)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L.tr("Уведомления", "Notifications")).font(.headline)
                    HStack {
                        Toggle(L.tr("Итог дня в", "Daily summary at"), isOn: $settings.digestEnabled)
                        Picker(L.tr("Время", "Time"), selection: $settings.digestHour) {
                            ForEach(18...23, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        .disabled(!settings.digestEnabled)
                    }
                    Text(L.tr("Одно уведомление вечером: время, главные приложения, лучший фокус. Если Mac был закрыт — придёт утром. По понедельникам — итог недели в сравнении с прошлой.",
                              "One notification in the evening: time, top apps, best focus. If the Mac was closed, it comes in the morning. On Mondays: the week compared with the one before."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(L.tr("Сообщать, если процесс грузит процессор, пока меня нет", "Tell me when a process keeps the CPU busy while I'm away"),
                           isOn: $settings.watchdogAlerts)
                    Toggle(L.tr("Напоминать о перерыве", "Remind me to take a break"), isOn: $settings.breakReminders)
                    Text(L.tr("После 1,5–2 часов работы без перерыва, в естественной паузе (сменил приложение, перестал печатать). Во время звонка молчит.",
                              "After 1.5–2 hours of work without a break, at a natural pause (you switched apps or stopped typing). Silent during calls."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                DayBoundaryNote()

                Divider()

                Toggle(L.tr("Записывать заголовки окон", "Record window titles"), isOn: $settings.recordTitles)
                if settings.recordTitles && !accessibilityGranted {
                    permissionNote(
                        L.tr("Нужен доступ: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → ActivityTracker.", "Needs access: System Settings → Privacy & Security → Accessibility → ActivityTracker."),
                        button: L.tr("Выдать доступ", "Grant access")
                    ) {
                        WindowTitle.requestAccess()
                        openPrivacyPane("Privacy_Accessibility")
                    }
                }

                Toggle(L.tr("Записывать сайты из браузеров", "Record sites from browsers"), isOn: $settings.recordURLs)
                Toggle(L.tr("Safari: не записывать сайты и заголовки (только время)",
                            "Safari: don't record sites or titles (time only)"), isOn: $settings.hideSafariDetails)
                Text(L.tr("Приватные окна Chrome, Яндекса, Edge, Brave и Arc распознаются и не записываются. У Safari такого признака нет — приложение пробует узнать это по меню «Окно», но надёжнее включить этот переключатель.",
                          "Private windows of Chrome, Yandex, Edge, Brave and Arc are recognised and not recorded. Safari has no such signal — the app tries its Window menu, but this switch is the reliable option."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.recordURLs {
                    Text(L.tr("При первом открытии каждого браузера macOS спросит, можно ли ActivityTracker управлять им — нажмите «Разрешить». Firefox адреса не отдаёт, для него пишется только заголовок окна.", "The first time each browser is used, macOS asks whether ActivityTracker may control it — click Allow. Firefox does not share addresses; only its window title is recorded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !deniedBrowsers.isEmpty {
                        permissionNote(
                            L.tr("Нет доступа к: \(deniedBrowsers.joined(separator: ", ")). Включите в разделе «Автоматизация».",
                             "No access to: \(deniedBrowsers.joined(separator: ", ")). Turn it on under Automation."),
                            button: L.tr("Открыть настройки", "Open Settings")
                        ) {
                            openPrivacyPane("Privacy_Automation")
                        }
                    }
                }

                Divider()

                UpdateSettings()

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.tr("Данные", "Data")).font(.headline)
                    HStack {
                        ForgetMenu()
                        Spacer()
                        Button(L.tr("Удалить всю историю…", "Delete entire history…"), role: .destructive) { DataEraser.confirmAndErase(.all) }
                    }
                    Text(L.tr("Сайт или приложение целиком удаляются из списков: наведи на строку и нажми корзину.", "To delete a whole site or app, hover over its row in the lists and click the trash."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                DatabaseSection(databaseURL: databaseURL)

                Divider()

                CommandLineSection()

                Divider()

                PhoneSection(server: AppServices.shared.phone)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.tr("Диагностика", "Diagnostics")).font(.headline)
                    Button(diagnosticsStatus ?? L.tr("Скопировать сведения об окне (через 5 секунд)", "Copy window details (in 5 seconds)")) {
                        captureWindowInfo()
                    }
                    .disabled(diagnosticsStatus != nil)
                    Text(L.tr("Нажми и за 5 секунд переключись в нужное окно (например, приватное окно Safari). Описание окна скопируется в буфер обмена — его можно прислать разработчику.", "Click, then switch to the window within 5 seconds (for example, a private Safari window). Its description is copied to the clipboard so you can send it to the developer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Button(L.tr("Показать базу данных в Finder", "Show database in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                    }
                    Text(databaseURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(L.tr("Все данные хранятся только на этом Mac.", "All data stays on this Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .onAppear(perform: refreshPermissions)
        .onReceive(poll) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        accessibilityGranted = WindowTitle.isTrusted
        launchAtLogin = settings.launchAtLogin
        deniedBrowsers = BrowserURL.lastErrors
            .filter { $0.value == BrowserURL.notPermittedError }
            .map { entry in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.key)?
                    .deletingPathExtension().lastPathComponent ?? entry.key
            }
            .sorted()
    }

    private func permissionNote(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private func captureWindowInfo() {
        diagnosticsStatus = L.tr("Переключись в нужное окно…", "Switch to the window…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let info = WindowTitle.describeFocusedWindow(of: app)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info, forType: .string)
            let name = app.localizedName ?? L.tr("окно", "window")
            diagnosticsStatus = L.tr("Скопировано: \(name)", "Copied: \(name)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { diagnosticsStatus = nil }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
