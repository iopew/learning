import Foundation

/// One snapshot of the Mac's state, taken about once a minute.
public struct SystemSample: Equatable {
    public var at: Date
    /// 0…100; nil on a Mac without a battery.
    public var batteryPercent: Double?
    public var onAC: Bool
    public var isCharging: Bool
    /// Battery power in watts: positive while charging, negative while the Mac runs from the battery.
    public var batteryWatts: Double?
    /// °C
    public var batteryTemperature: Double?
    public var cycleCount: Int?
    /// Current maximum capacity as a share of the design capacity, 0…100.
    public var healthPercent: Double?
    /// Whole-machine CPU load over the last interval, 0…1.
    public var cpuLoad: Double
    public var memoryUsed: Double
    public var memoryTotal: Double
    public var swapUsed: Double
    public var diskFree: Double
    public var diskTotal: Double
    /// ProcessInfo.ThermalState raw value: 0 nominal, 1 fair, 2 serious, 3 critical.
    public var thermalState: Int
    /// The power adapter, when plugged in (IOPSCopyExternalPowerAdapterDetails).
    public var adapterWatts: Double?
    public var adapterName: String?

    public init(at: Date, batteryPercent: Double? = nil, onAC: Bool = true, isCharging: Bool = false,
                batteryWatts: Double? = nil, batteryTemperature: Double? = nil, cycleCount: Int? = nil,
                healthPercent: Double? = nil, cpuLoad: Double = 0, memoryUsed: Double = 0, memoryTotal: Double = 0,
                swapUsed: Double = 0, diskFree: Double = 0, diskTotal: Double = 0, thermalState: Int = 0) {
        self.at = at
        self.batteryPercent = batteryPercent
        self.onAC = onAC
        self.isCharging = isCharging
        self.batteryWatts = batteryWatts
        self.batteryTemperature = batteryTemperature
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.cpuLoad = cpuLoad
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.swapUsed = swapUsed
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.thermalState = thermalState
    }
}

/// Energy and CPU time one app (with all its helper processes) used during one sampling interval.
public struct AppEnergy: Equatable {
    public var bundleID: String
    public var appName: String
    public var joules: Double
    public var cpuSeconds: Double

    public init(bundleID: String, appName: String, joules: Double, cpuSeconds: Double) {
        self.bundleID = bundleID
        self.appName = appName
        self.joules = joules
        self.cpuSeconds = cpuSeconds
    }
}

public struct EnergyUsage: Equatable, Identifiable {
    public var bundleID: String
    public var appName: String
    public var joules: Double
    public var cpuSeconds: Double

    public var id: String { bundleID }
}

/// Battery level at a moment (day view) or averaged over an hour / a day (longer periods).
public struct BatteryPoint: Equatable, Identifiable {
    public var at: Date
    public var percent: Double
    public var minPercent: Double
    public var maxPercent: Double
    public var charging: Bool

    public var id: Date { at }
}

/// CPU load at a moment (day view) or averaged over an hour / a day.
public struct LoadPoint: Equatable, Identifiable {
    public var at: Date
    public var cpu: Double
    public var memory: Double

    public var id: Date { at }
}

public struct SystemReport: Equatable {
    public var range: StatsRange
    public var fromDay: Date
    public var toDay: Date
    public var hasData: Bool
    public var hasBattery: Bool
    /// The newest sample in the period.
    public var latest: SystemSample?

    public var batteryPoints: [BatteryPoint]
    public var loadPoints: [LoadPoint]
    /// How many times the charger was plugged in.
    public var chargeCount: Int
    /// Battery cycles added during the period.
    public var cyclesAdded: Int?
    /// Average battery drop per hour while running from the battery, in percent.
    public var drainPerHour: Double?
    public var averageDischargeWatts: Double?
    public var timeOnBattery: TimeInterval
    /// Time spent plugged in with the battery at 99–100 %.
    public var timeFullOnAC: TimeInterval
    /// A full charge would last this long at the average drain.
    public var estimatedFullCharge: TimeInterval?
    public var energyOnBattery: [EnergyUsage]
    public var energyAll: [EnergyUsage]
    public var cpuAverage: Double?
    public var cpuPeak: Double?
    public var memoryPeak: Double?
    public var swapPeak: Double?
    public var hotTime: TimeInterval
    public var maxBatteryTemperature: Double?
}

public struct Recommendation: Equatable, Identifiable {
    public enum Kind: String {
        case positive, info, warning
    }

    public var id: String
    public var kind: Kind
    /// SF Symbol name.
    public var symbol: String
    public var title: String
    public var detail: String

    public init(id: String, kind: Kind, symbol: String, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// How a usual day looked over the previous weeks (per active day).
public struct UsageBaseline: Equatable {
    public var activeDays: Int
    public var totalPerDay: TimeInterval
    public var appsPerDay: [String: TimeInterval]
    public var domainsPerDay: [String: TimeInterval]

    public init(activeDays: Int = 0, totalPerDay: TimeInterval = 0, appsPerDay: [String: TimeInterval] = [:],
                domainsPerDay: [String: TimeInterval] = [:]) {
        self.activeDays = activeDays
        self.totalPerDay = totalPerDay
        self.appsPerDay = appsPerDay
        self.domainsPerDay = domainsPerDay
    }
}
