import Foundation

/// A stretch of uninterrupted use of one app (after merging rows and dropping short peeks).
public struct AppRun: Equatable {
    public var bundleID: String
    public var appName: String
    public var start: Date
    public var end: Date
    /// Follows the previous run without a pause (idle, lock, our own window), so the change counts as a switch.
    public var linked: Bool

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// "VS Code ↔ Telegram — 38 times".
public struct SwitchPair: Equatable, Identifiable {
    public var firstName: String
    public var secondName: String
    public var count: Int

    public var id: String { "\(firstName)|\(secondName)" }
}

/// How fragmented the time was: switches between apps, typical uninterrupted stretch, back-and-forth pairs.
public struct SwitchStats: Equatable {
    public var switches: Int
    public var activeSeconds: TimeInterval
    /// Median length of an uninterrupted stretch in one app.
    public var medianRun: TimeInterval?
    public var longestRun: AppRun?
    /// Most frequent back-and-forth pairs, most frequent first.
    public var pairs: [SwitchPair]

    /// Switches per hour of activity; nil for less than 10 active minutes (too little to say anything).
    public var perHour: Double? {
        activeSeconds >= 600 ? Double(switches) / (activeSeconds / 3600) : nil
    }

    public static let empty = SwitchStats(switches: 0, activeSeconds: 0, medianRun: nil, longestRun: nil, pairs: [])
}

public enum Switches {
    /// Shorter visits don't count as switching: a glance at a notification, ⌘-Tab passing through.
    public static let peek: TimeInterval = 10
    /// A longer pause between two rows (idle, lock, private window, our own window in front) breaks the chain.
    public static let maxGap: TimeInterval = 30

    /// `events` sorted by start.
    public static func stats(_ events: [ActivityEvent]) -> SwitchStats {
        let runs = self.runs(events)
        var switches = 0
        var pairCounts: [String: Int] = [:]
        var pairNames: [String: (String, String)] = [:]
        for index in runs.indices.dropFirst() where runs[index].linked {
            let previous = runs[index - 1]
            let current = runs[index]
            guard previous.bundleID != current.bundleID else { continue }
            switches += 1
            let ordered = previous.bundleID < current.bundleID ? (previous, current) : (current, previous)
            let key = ordered.0.bundleID + "|" + ordered.1.bundleID
            pairCounts[key, default: 0] += 1
            pairNames[key] = (ordered.0.appName, ordered.1.appName)
        }
        let pairs = pairCounts
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(5)
            .compactMap { entry in pairNames[entry.key].map { SwitchPair(firstName: $0.0, secondName: $0.1, count: entry.value) } }

        let durations = runs.map(\.duration).sorted()
        let median: TimeInterval? = durations.isEmpty ? nil
            : durations.count % 2 == 1 ? durations[durations.count / 2]
            : (durations[durations.count / 2 - 1] + durations[durations.count / 2]) / 2
        return SwitchStats(
            switches: switches,
            activeSeconds: events.reduce(0) { $0 + max(0, $1.duration) },
            medianRun: median,
            longestRun: runs.max { $0.duration < $1.duration },
            pairs: Array(pairs))
    }

    /// Only the part of `events` inside `from`…`to` (e.g. the last hour).
    public static func clip(_ events: [ActivityEvent], from: Date, to: Date) -> [ActivityEvent] {
        events.compactMap { event in
            guard event.end > from, event.start < to else { return nil }
            var clipped = event
            clipped.start = max(event.start, from)
            clipped.end = min(event.end, to)
            return clipped
        }
    }

    /// Rows → runs: a new row is written on every title change, so rows of one app are merged first; runs shorter
    /// than `peek` are dropped and the runs around them joined.
    static func runs(_ events: [ActivityEvent]) -> [AppRun] {
        var raw: [AppRun] = []
        var lastEnd: Date?
        for event in events where event.end > event.start {
            let linked = lastEnd.map { event.start.timeIntervalSince($0) <= maxGap } ?? false
            lastEnd = max(lastEnd ?? event.end, event.end)
            if linked, let last = raw.last, last.bundleID == event.bundleID {
                raw[raw.count - 1].end = max(last.end, event.end)
            } else {
                raw.append(AppRun(bundleID: event.bundleID, appName: event.appName, start: event.start,
                                  end: event.end, linked: linked))
            }
        }

        var result: [AppRun] = []
        var linkThrough = true   // whether the dropped peeks since the last kept run were themselves linked
        for run in raw {
            let linked = run.linked && linkThrough && !result.isEmpty
            if run.duration < peek {
                linkThrough = linked
                continue
            }
            linkThrough = true
            if linked, let last = result.last, last.bundleID == run.bundleID {
                result[result.count - 1].end = max(last.end, run.end)
            } else {
                var kept = run
                kept.linked = linked
                result.append(kept)
            }
        }
        return result
    }
}
