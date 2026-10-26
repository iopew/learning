import AppKit
import SwiftUI
import ActivityCore

/// "Доступна новая версия → Обновить", download/install progress, or an update error. Empty otherwise.
struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.phase {
        case .available(let update):
            box(tint: .accentColor) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.tr("Доступна новая версия — сборка \(update.build)", "New version available — build \(update.build)"))
                        .font(.callout.weight(.medium))
                    if let note = Self.firstLine(update.notes) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button(L.tr("Обновить", "Update")) { updater.install(update) }
                    .disabled(!updater.canInstall)
            }
        case .downloading(let build):
            box(tint: .accentColor) {
                ProgressView().controlSize(.small)
                Text(L.tr("Скачиваю сборку \(build)…", "Downloading build \(build)…")).font(.callout)
                Spacer()
            }
        case .installing(let build):
            box(tint: .accentColor) {
                ProgressView().controlSize(.small)
                Text(L.tr("Устанавливаю сборку \(build), приложение перезапустится…", "Installing build \(build), the app will restart…")).font(.callout)
                Spacer()
            }
        case .failed(let message):
            box(tint: .orange) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).lineLimit(3)
                Spacer()
                Button(L.tr("Ещё раз", "Retry")) { updater.check(userInitiated: true) }
            }
        case .idle, .checking, .upToDate:
            EmptyView()
        }
    }

    private func box<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return line?.isEmpty == false ? line : nil
    }
}

/// The "Обновления" block of the settings.
struct UpdateSettings: View {
    @EnvironmentObject private var updater: Updater
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.tr("Обновления", "Updates")).font(.headline)
            Toggle(L.tr("Проверять обновления (раз в 30 минут, GitHub)", "Check for updates (every 30 minutes, GitHub)"), isOn: $settings.checkForUpdates)
            Toggle(L.tr("Устанавливать автоматически", "Install automatically"), isOn: $settings.autoUpdate)
                .disabled(!settings.checkForUpdates)
            HStack {
                Text(L.tr("Версия \(updater.currentVersion) (сборка \(updater.currentBuild))", "Version \(updater.currentVersion) (build \(updater.currentBuild))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.tr("Проверить сейчас", "Check now")) { updater.check(userInitiated: true) }
                    .disabled(updater.isBusy)
            }
            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .available(let update) = updater.phase {
                    Spacer()
                    Button(L.tr("Обновить", "Update")) { updater.install(update) }
                        .disabled(!updater.canInstall)
                }
            }
            if !updater.canInstall {
                Text(L.tr("Чтобы обновляться, приложение должно лежать в папке «Программы».", "To update, the app must be in the Applications folder."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(L.tr("Журнал обновлений", "Update log")) {
                NSWorkspace.shared.open(Installer.logURL)
            }
            .disabled(!FileManager.default.fileExists(atPath: Installer.logURL.path))
            Text(L.tr("Приложение отправляет только запрос «какая версия последняя» на GitHub. Ваши данные никуда не уходят.", "The app only asks GitHub which version is the latest. Your data never leaves the Mac."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        switch updater.phase {
        case .idle:
            if let lastCheck = updater.lastCheck { return L.tr("Последняя проверка: \(Self.time(lastCheck))", "Last check: \(Self.time(lastCheck))") }
            return L.tr("Ещё не проверялось", "Not checked yet")
        case .checking: return L.tr("Проверяю…", "Checking…")
        case .upToDate: return L.tr("Установлена последняя версия", "Up to date") + (updater.lastCheck.map { L.tr(" (проверено в \(Self.time($0)))", " (checked at \(Self.time($0)))") } ?? "")
        case .available(let update): return L.tr("Доступна сборка \(update.build)", "Build \(update.build) available")
        case .downloading(let build): return L.tr("Скачиваю сборку \(build)…", "Downloading build \(build)…")
        case .installing(let build): return L.tr("Устанавливаю сборку \(build)…", "Installing build \(build)…")
        case .failed(let message): return message
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
