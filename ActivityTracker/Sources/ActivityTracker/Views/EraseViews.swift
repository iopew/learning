import AppKit
import SwiftUI
import ActivityCore

/// Asks for confirmation and deletes recorded data.
enum DataEraser {
    static func confirmAndErase(_ what: ActivityStore.Erase) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = question(for: what)
        alert.informativeText = L.tr("Данные удаляются насовсем, вместе с заголовками и адресами. Отменить нельзя.", "Data is deleted for good, with titles and addresses. This cannot be undone.")
        alert.addButton(withTitle: L.tr("Удалить", "Delete"))
        alert.addButton(withTitle: L.tr("Отмена", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppServices.shared.tracker.erase(what)
    }

    private static func question(for what: ActivityStore.Erase) -> String {
        switch what {
        case .domain(let domain): return L.tr("Удалить всё, что записано о \(domain)?", "Delete everything recorded about \(domain)?")
        case .app(let bundleID):
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
                .deletingPathExtension().lastPathComponent ?? bundleID
            return L.tr("Удалить всё, что записано о «\(name)»?", "Delete everything recorded about “\(name)”?")
        case .since(let moment):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return L.tr("Забыть всё, что записано после \(formatter.string(from: moment))?", "Forget everything recorded after \(formatter.string(from: moment))?")
        case .all: return L.tr("Удалить всю историю активности?", "Delete the whole activity history?")
        }
    }
}

/// "Забыть…" menu: the last 15 minutes, hour, today, everything.
struct ForgetMenu: View {
    var body: some View {
        Menu {
            Button(L.tr("Последние 15 минут", "Last 15 minutes")) { DataEraser.confirmAndErase(.since(Date().addingTimeInterval(-15 * 60))) }
            Button(L.tr("Последний час", "Last hour")) { DataEraser.confirmAndErase(.since(Date().addingTimeInterval(-3600))) }
            Button(L.tr("Сегодня", "Today")) { DataEraser.confirmAndErase(.since(Calendar.current.startOfDay(for: Date()))) }
            Divider()
            Button(L.tr("Всю историю…", "Entire history…")) { DataEraser.confirmAndErase(.all) }
        } label: {
            Label(L.tr("Забыть", "Forget"), systemImage: "eye.slash")
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
        .help(L.tr("Удалить все данные", "Delete all data"))
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }
}
