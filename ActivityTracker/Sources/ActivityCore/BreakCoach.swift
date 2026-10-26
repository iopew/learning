import Foundation

/// Decides when to suggest a break. Fed every tracker tick (5 s).
///
/// The work streak starts with input and lasts until a real break: no input for `breakAfter` (5 min), or the screen
/// locked / the Mac asleep for that long. After `softLimit` (90 min) the reminder waits for a natural pause, so it
/// doesn't interrupt in the middle of a thought: a switch to another app, or a short stop of typing (30 s+).
/// At `hardLimit` (120 min) it comes anyway. Never during a call, and not more often than every `repeatAfter`.
public struct BreakCoach {
    public var breakAfter: TimeInterval = 5 * 60
    public var softLimit: TimeInterval = 90 * 60
    public var hardLimit: TimeInterval = 120 * 60
    public var repeatAfter: TimeInterval = 20 * 60

    public private(set) var workStart: Date?
    private var lastTick: Date?
    private var awaySince: Date?
    private var lastReminder: Date?
    private var lastApp: String?

    public init() {}

    /// Returns the length of the streak when a reminder should be shown now.
    /// `away`: screen locked, Mac asleep or recording paused. `inCall` is asked only when a reminder is due.
    public mutating func update(now: Date, idle: TimeInterval, away: Bool, app: String?,
                                inCall: () -> Bool) -> TimeInterval? {
        defer { lastTick = now }
        // The Mac slept (no ticks): that was a break.
        if let lastTick, now.timeIntervalSince(lastTick) >= breakAfter { reset() }

        if away {
            if awaySince == nil { awaySince = now }
            if let awaySince, now.timeIntervalSince(awaySince) >= breakAfter { reset() }
            return nil
        }
        awaySince = nil
        if idle >= breakAfter {
            reset()
            return nil
        }

        guard let workStart else {
            if idle < 60 { workStart = now.addingTimeInterval(-idle) }
            lastApp = app
            return nil
        }
        let switched = app != nil && lastApp != nil && app != lastApp
        if let app { lastApp = app }

        let streak = now.timeIntervalSince(workStart)
        guard streak >= softLimit else { return nil }
        if let lastReminder, now.timeIntervalSince(lastReminder) < repeatAfter { return nil }
        let naturalPause = switched || idle >= 30
        guard naturalPause || streak >= hardLimit, !inCall() else { return nil }
        lastReminder = now
        return streak
    }

    public mutating func reset() {
        workStart = nil
        lastReminder = nil
        lastApp = nil
        awaySince = nil
    }
}
