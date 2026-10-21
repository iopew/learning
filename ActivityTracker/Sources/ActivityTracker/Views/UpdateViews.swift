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
                    Text("Доступна новая версия — сборка \(update.build)")
                        .font(.callout.weight(.medium))
                    if let note = Self.firstLine(update.notes) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Обновить") { updater.install(update) }
                    .disabled(!updater.canInstall)
            }
        case .downloading(let build):
            box(tint: .accentColor) {
                ProgressView().controlSize(.small)
                Text("Скачиваю сборку \(build)…").font(.callout)
                Spacer()
            }
        case .installing(let build):
            box(tint: .accentColor) {
                ProgressView().controlSize(.small)
                Text("Устанавливаю сборку \(build), приложение перезапустится…").font(.callout)
                Spacer()
            }
        case .failed(let message):
            box(tint: .orange) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).lineLimit(3)
                Spacer()
                Button("Ещё раз") { updater.check(userInitiated: true) }
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
            Text("Обновления").font(.headline)
            Toggle("Проверять обновления (раз в 30 минут, GitHub)", isOn: $settings.checkForUpdates)
            Toggle("Устанавливать автоматически", isOn: $settings.autoUpdate)
                .disabled(!settings.checkForUpdates)
            HStack {
                Text("Версия \(updater.currentVersion) (сборка \(updater.currentBuild))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Проверить сейчас") { updater.check(userInitiated: true) }
                    .disabled(updater.isBusy)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !updater.canInstall {
                Text("Чтобы обновляться, приложение должно лежать в папке «Программы».")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Журнал обновлений") {
                NSWorkspace.shared.open(Installer.logURL)
            }
            .disabled(!FileManager.default.fileExists(atPath: Installer.logURL.path))
            Text("Приложение отправляет только запрос «какая версия последняя» на GitHub. Ваши данные никуда не уходят.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        switch updater.phase {
        case .idle:
            if let lastCheck = updater.lastCheck { return "Последняя проверка: \(Self.time(lastCheck))" }
            return "Ещё не проверялось"
        case .checking: return "Проверяю…"
        case .upToDate: return "Установлена последняя версия" + (updater.lastCheck.map { " (проверено в \(Self.time($0)))" } ?? "")
        case .available(let update): return "Доступна сборка \(update.build)"
        case .downloading(let build): return "Скачиваю сборку \(build)…"
        case .installing(let build): return "Устанавливаю сборку \(build)…"
        case .failed(let message): return message
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
