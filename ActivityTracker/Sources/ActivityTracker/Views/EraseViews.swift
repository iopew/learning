import AppKit
import SwiftUI
import ActivityCore

/// Asks for confirmation and deletes recorded data.
enum DataEraser {
    static func confirmAndErase(_ what: ActivityStore.Erase) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = question(for: what)
        alert.informativeText = "Данные удаляются насовсем, вместе с заголовками и адресами. Отменить нельзя."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppServices.shared.tracker.erase(what)
    }

    private static func question(for what: ActivityStore.Erase) -> String {
        switch what {
        case .domain(let domain): return "Удалить всё, что записано о \(domain)?"
        case .app(let bundleID):
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
                .deletingPathExtension().lastPathComponent ?? bundleID
            return "Удалить всё, что записано о «\(name)»?"
        case .since(let moment):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Забыть всё, что записано после \(formatter.string(from: moment))?"
        case .all: return "Удалить всю историю активности?"
        }
    }
}

/// "Забыть…" menu: the last 15 minutes, hour, today, everything.
struct ForgetMenu: View {
    var body: some View {
        Menu {
            Button("Последние 15 минут") { DataEraser.confirmAndErase(.since(Date().addingTimeInterval(-15 * 60))) }
            Button("Последний час") { DataEraser.confirmAndErase(.since(Date().addingTimeInterval(-3600))) }
            Button("Сегодня") { DataEraser.confirmAndErase(.since(Calendar.current.startOfDay(for: Date()))) }
            Divider()
            Button("Всю историю…") { DataEraser.confirmAndErase(.all) }
        } label: {
            Label("Забыть", systemImage: "eye.slash")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// A trash button that shows up while the pointer is over a row.
struct RowEraseButton: View {
    let what: ActivityStore.Erase
    let isVisible: Bool

    var body: some View {
        Button {
            DataEraser.confirmAndErase(what)
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Удалить все данные")
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }
}
