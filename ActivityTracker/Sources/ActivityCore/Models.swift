import Foundation

/// What the user is doing right now: one observation from the collector.
public struct Sample: Equatable {
    public var bundleID: String
    public var appName: String
    public var title: String
    public var url: String

    public init(bundleID: String, appName: String, title: String = "", url: String = "") {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.url = url
    }

    public var domain: String { URLTools.domain(from: url) }
}

/// A continuous stretch of time spent in one app / window / page.
public struct ActivityEvent: Equatable, Identifiable {
    public var id: Int64
    public var start: Date
    public var end: Date
    public var bundleID: String
    public var appName: String
    public var title: String
    public var url: String
    public var domain: String

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct AppUsage: Equatable, Identifiable {
    public var bundleID: String
    public var appName: String
    public var seconds: TimeInterval
    /// Most-used window titles of this app within the report period.
    public var topTitles: [TitleUsage]

    public var id: String { bundleID }
}

public struct TitleUsage: Equatable, Identifiable {
    public var title: String
    public var seconds: TimeInterval

    public var id: String { title }
}

public struct DomainUsage: Equatable, Identifiable {
    public var domain: String
    public var seconds: TimeInterval

    public var id: String { domain }
}

/// One bar of the period chart: a day, or a week for long periods.
public struct ChartBucket: Equatable, Identifiable {
    public var start: Date
    public var seconds: TimeInterval

    public var id: Date { start }
}

/// Seconds one app was active within one hour of a day (stacked hourly chart).
public struct HourSlice: Equatable, Identifiable {
    public var hour: Int
    public var bundleID: String
    public var seconds: TimeInterval

    public var id: String { "\(hour)|\(bundleID)" }
}

/// The app that dominated one minute of a day.
public struct MinuteCell: Equatable {
    public var bundleID: String
    public var appName: String
    public var seconds: TimeInterval
}

/// Consecutive events in the same app merged into one row of the day timeline.
public struct Session: Equatable, Identifiable {
    public var start: Date
    public var end: Date
    public var bundleID: String
    public var appName: String
    /// Window titles / domains seen in this session, longest first.
    public var details: [String]

    public var id: Date { start }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum BucketUnit: Equatable {
    case day
    case week
}

public struct Report: Equatable {
    public var range: StatsRange
    public var fromDay: Date
    public var toDay: Date
    public var total: TimeInterval
    public var activeDays: Int
    public var apps: [AppUsage]
    public var domains: [DomainUsage]
    public var buckets: [ChartBucket]
    public var bucketUnit: BucketUnit
    // Day-only details (empty for longer periods).
    public var hourly: [HourSlice]
    /// 1440 entries, one per minute of the day; nil where nothing was recorded.
    public var minutes: [MinuteCell?]
    public var sessions: [Session]
    /// Clock hour of the first row of `hourly` / `minutes` (the day may begin at 04:00, see DayCalendar).
    public var firstHour: Int = 0

    public var averagePerActiveDay: TimeInterval {
        activeDays > 0 ? total / Double(activeDays) : 0
    }
}
