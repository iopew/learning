import AppKit
import SwiftUI

struct SettingsView: View {
    let databaseURL: URL

    @EnvironmentObject private var settings: Settings
    @State private var accessibilityGranted = WindowTitle.isTrusted
    @State private var deniedBrowsers: [String] = []

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }))

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
            .map { bundleID, _ in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
                    .deletingPathExtension().lastPathComponent ?? bundleID
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

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
