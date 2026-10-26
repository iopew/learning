import AppKit
import CoreAudio
import UserNotifications
import ActivityCore

/// Notifications: the evening digest (+ the Monday review of the week) and break reminders.
/// The digest is checked once a minute; the break coach runs on the tracker's tick. Reports for the digest are built
/// on a background queue.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let store: ActivityStore
    private let systemStore: SystemStore
    let settings: Settings
    private let queue = DispatchQueue(label: "ActivityTracker.notifier", qos: .utility)
    private var timer: Timer?
    private var coach = BreakCoach()
    private var building = false
    private var started = false

    private enum Keys {
        static let lastDigestDay = "lastDigestDay"
        static let lastWeeklyDigest = "lastWeeklyDigest"
    }

    init(store: ActivityStore, systemStore: SystemStore, settings: Settings) {
        self.store = store
        self.systemStore = systemStore
        self.settings = settings
    }

    /// Notifications need an app bundle (not the bare binary used by `--probe`).
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func start() {
        guard !started, canNotify else { return }
        started = true
        UNUserNotificationCenter.current().delegate = self
        if settings.digestEnabled || settings.breakReminders { requestPermission() }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.checkDigest() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // After waking up the catch-up digest shouldn't wait for the next minute.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self?.checkDigest() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkDigest() }
    }

    /// macOS asks once ("ActivityTracker would like to send notifications"); later calls just return the answer.
    func requestPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("ActivityTracker: notifications: \(error)") }
            if !granted { NSLog("ActivityTracker: notifications not allowed") }
        }
    }

    /// Shows notifications even while our window is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// A click on a notification opens the statistics.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { MainWindowController.shared.show() }
        completionHandler()
    }

    func post(id: String, _ message: DigestMessage, sound: Bool = false) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("ActivityTracker: notification \(id): \(error)") }
        }
    }

    // MARK: - Digest

    private func checkDigest() {
        guard settings.digestEnabled, !building, canNotify else { return }
        let now = Date()
        let days = store.days
        let defaults = UserDefaults.standard
        let dueDay = DigestSchedule.dueDay(now: now, hour: settings.digestHour,
                                           lastSent: defaults.string(forKey: Keys.lastDigestDay), days: days)
        let dueWeek = DigestSchedule.dueWeek(now: now, hour: settings.digestHour,
                                             lastSent: defaults.string(forKey: Keys.lastWeeklyDigest), days: days)
        guard dueDay != nil || dueWeek != nil else { return }
        building = true
        queue.async { [self] in
            var daily: DigestMessage?
            var weekly: DigestMessage?
            do {
                if let dueDay { daily = try dailyMessage(for: dueDay, now: now) }
                if let dueWeek { weekly = try weeklyMessage(weekStart: dueWeek) }
            } catch {
                NSLog("ActivityTracker: digest: \(error)")
            }
            DispatchQueue.main.async { [self] in
                building = false
                // Marked as sent even when nothing was recorded (or a report failed): no retry every minute.
                if let dueDay {
                    defaults.set(days.key(dueDay), forKey: Keys.lastDigestDay)
                    if let daily { post(id: "digest-\(days.key(dueDay))", daily) }
                }
                if let dueWeek {
                    defaults.set(days.key(dueWeek), forKey: Keys.lastWeeklyDigest)
                    if let weekly { post(id: "week-\(days.key(dueWeek))", weekly) }
                }
            }
        }
    }

    /// Runs on `queue`.
    private func dailyMessage(for day: Date, now: Date) throws -> DigestMessage? {
        let report = try store.report(range: .day, anchor: day)
        let switches = Switches.stats(try store.spans(from: day, to: day))
        // The most important of today's tips (warnings first); not about yesterday.
        var tip: Recommendation?
        if store.days.startOfDay(now) == day {
            let system = try systemStore.report(range: .day, anchor: day)
            let baseline = try store.baseline(before: day)
            let minute = Int(now.timeIntervalSince(day) / 60)
            let tips = Recommendations.make(RecommendationInput(
                today: report, baseline: baseline, system: system, now: now, minuteOfDay: minute))
            tip = tips.first { $0.kind == .warning } ?? tips.first { $0.kind == .info }
        }
        var message = Digest.daily(report: report, switches: switches, tip: tip)
        if message != nil, store.days.startOfDay(now) != day {
            message?.title = L.tr("Вчера: ", "Yesterday: ") + Format.duration(report.total)
        }
        return message
    }

    /// Runs on `queue`.
    private func weeklyMessage(weekStart: Date) throws -> DigestMessage? {
        let lastDay = store.days.addingDays(6, to: weekStart)
        let week = try store.report(range: .week, anchor: lastDay)
        let previous = try store.report(range: .week, anchor: store.days.addingDays(-7, to: lastDay))
        return Digest.weekly(week: week, previous: previous)
    }

    // MARK: - Breaks

    /// Called by the tracker every tick (5 s).
    func trackerTicked(state: Tracker.State, bundleID: String?, now: Date) {
        guard settings.breakReminders, canNotify else {
            coach.reset()
            return
        }
        let away = state == .away || state == .paused
        let idle = Idle.secondsSinceLastInput()
        guard let streak = coach.update(now: now, idle: idle, away: away, app: bundleID,
                                        inCall: { Microphone.isInUse() })
        else { return }
        post(id: "break", DigestMessage(
            title: L.tr("Пора сделать перерыв", "Time for a break"),
            body: L.tr("\(Format.duration(streak)) без перерыва. Встань, разомнись и дай глазам отдохнуть 5–10 минут.",
                       "\(Format.duration(streak)) without a break. Stand up, stretch and rest your eyes for 5–10 minutes.")),
             sound: true)
    }
}

extension Notifier {
    /// "gopls грузит процессор на 90% уже 12 минут, пока тебя нет".
    func runaway(name: String, percent: Int, minutes: TimeInterval) {
        guard settings.watchdogAlerts else { return }
        post(id: "runaway-\(name)", DigestMessage(
            title: L.tr("\(name) грузит процессор", "\(name) is keeping the CPU busy"),
            body: L.tr("\(percent)% одного ядра уже \(Format.duration(minutes)), пока тебя нет. Если это не нужно — закрой его в Мониторинге системы.",
                       "\(percent)% of a core for \(Format.duration(minutes)) while you're away. If it isn't needed, quit it in Activity Monitor.")))
    }
}

/// Whether some app is recording from the default microphone (a call). Public Core Audio property, no permission.
enum Microphone {
    static func isInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0
        else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
