import AppKit
import SwiftUI

struct SettingsView: View {
    let databaseURL: URL

    @EnvironmentObject private var settings: Settings
    @State private var accessibilityGranted = WindowTitle.isTrusted
    @State private var deniedBrowsers: [String] = []
    @State private var diagnosticsStatus: String?

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Оформление", selection: $settings.appearance) {
                    ForEach(Settings.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Строка меню", selection: $settings.menuBarStyle) {
                    ForEach(Settings.MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                if settings.menuBarStyle == .hidden {
                    Text("Трекер работает молча. Статистика — через Launchpad, Dock или двойной клик по приложению.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }))
                Toggle("Всегда показывать значок в Dock (иначе — только пока открыто окно)",
                       isOn: $settings.alwaysShowInDock)

                Picker("Считать, что меня нет, после", selection: $settings.idleThreshold) {
                    Text("1 мин").tag(60.0)
                    Text("2 мин").tag(120.0)
                    Text("3 мин").tag(180.0)
                    Text("5 мин").tag(300.0)
                    Text("10 мин").tag(600.0)
                }
                Toggle("Видео и звонки без мыши и клавиатуры — тоже активность",
                       isOn: $settings.countMediaAsActive)

                Divider()

                Toggle("Записывать заголовки окон", isOn: $settings.recordTitles)
                if settings.recordTitles && !accessibilityGranted {
                    permissionNote(
                        "Нужен доступ: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → ActivityTracker.",
                        button: "Выдать доступ"
                    ) {
                        WindowTitle.requestAccess()
                        openPrivacyPane("Privacy_Accessibility")
                    }
                }

                Toggle("Записывать сайты из браузеров", isOn: $settings.recordURLs)
                if settings.recordURLs {
                    Text("При первом открытии каждого браузера macOS спросит, можно ли ActivityTracker управлять им — нажмите «Разрешить». Firefox адреса не отдаёт, для него пишется только заголовок окна.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !deniedBrowsers.isEmpty {
                        permissionNote(
                            "Нет доступа к: \(deniedBrowsers.joined(separator: ", ")). Включите в разделе «Автоматизация».",
                            button: "Открыть настройки"
                        ) {
                            openPrivacyPane("Privacy_Automation")
                        }
                    }
                }

                Divider()

                UpdateSettings()

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Диагностика").font(.headline)
                    Button(diagnosticsStatus ?? "Скопировать сведения об окне (через 5 секунд)") {
                        captureWindowInfo()
                    }
                    .disabled(diagnosticsStatus != nil)
                    Text("Нажми и за 5 секунд переключись в нужное окно (например, приватное окно Safari). Описание окна скопируется в буфер обмена — его можно прислать разработчику.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Button("Показать базу данных в Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                    }
                    Text(databaseURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Все данные хранятся только на этом Mac.")
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
        diagnosticsStatus = "Переключись в нужное окно…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let info = WindowTitle.describeFocusedWindow(of: app)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info, forType: .string)
            diagnosticsStatus = "Скопировано: \(app.localizedName ?? "окно")"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { diagnosticsStatus = nil }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
