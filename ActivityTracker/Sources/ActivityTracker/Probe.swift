import AppKit
import ActivityCore

/// `ActivityTracker --probe`: prints one sample of what the collectors see and checks the database,
/// without starting the UI. Used by CI and handy for debugging permissions.
enum Probe {
    static func run() -> Int32 {
        print("ActivityTracker probe")

        if let app = NSWorkspace.shared.frontmostApplication {
            let bundleID = app.bundleIdentifier ?? "?"
            print("frontmost app:      \(app.localizedName ?? "?") (\(bundleID), pid \(app.processIdentifier))")
            print("accessibility:      \(WindowTitle.isTrusted ? "granted" : "not granted")")
            print("window title:       \(WindowTitle.focusedWindowTitle(of: app.processIdentifier))")
            if BrowserURL.isBrowser(bundleID) {
                let url = BrowserURL.currentURL(bundleID: bundleID)
                print("browser URL:        \(url) (error: \(BrowserURL.lastErrors[bundleID].map(String.init) ?? "none"))")
            }
        } else {
            print("frontmost app:      none")
        }
        print("idle seconds:       \(Int(Idle.secondsSinceLastInput()))")
        if let battery = BatteryReader.read() {
            print("battery:            \(Int(battery.percent))%, on AC: \(battery.onAC), charging: \(battery.charging), "
                  + "watts: \(battery.watts.map { String(format: "%.1f", $0) } ?? "?"), cycles: \(battery.cycleCount ?? -1), "
                  + "health: \(battery.health.map { String(format: "%.0f%%", $0) } ?? "?")")
        } else {
            print("battery:            none")
        }
        let energy = EnergyMeter()
        energy.baseline()
        Thread.sleep(forTimeInterval: 1)
        let apps = energy.collect().sorted { $0.joules > $1.joules }.prefix(3)
        print("energy (1 s):       \(apps.map { "\($0.appName) \(String(format: "%.3f", $0.joules)) J" })")
        print("display kept awake: \(Idle.isDisplaySleepPrevented())")

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("activity-probe-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        do {
            let store = try ActivityStore(path: path)
            let now = Date()
            let sample = Sample(bundleID: "probe", appName: "Probe", url: "https://example.com/")
            for step in 0..<3 {
                try store.record(sample, at: now.addingTimeInterval(TimeInterval(step * 5)), interval: 5)
            }
            let report = try store.report(range: .day, anchor: now)
            print("database:           ok, recorded \(Format.duration(report.total)), domains \(report.domains.map(\.domain))")
            guard report.total == 15 else {
                print("PROBE FAILED: expected 15 s, got \(report.total)")
                return 1
            }
        } catch {
            print("PROBE FAILED: \(error)")
            return 1
        }
        print("PROBE OK")
        return 0
    }
}
