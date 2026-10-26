import AppKit
import Darwin
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import ActivityCore

/// Once a minute, on a background queue: battery (IOKit AppleSmartBattery), CPU and memory (Mach host statistics),
/// swap, disk, thermal state, and how much energy / CPU every app used (proc_pid_rusage V6: the kernel's own
/// per-process energy counter, Apple Silicon). Costs a few milliseconds per minute.
final class SystemSampler {
    static let interval: TimeInterval = 60

    private let store: SystemStore
    private let machine: MachineStore
    private let queue = DispatchQueue(label: "ActivityTracker.system", qos: .utility)
    private var timer: Timer?
    private var lastSampleAt: Date?
    private var previousCPU: (busy: UInt64, total: UInt64)?
    private let energy = EnergyMeter()
    /// Only touched on `queue`.
    private var lastWrites: Double?
    private var lastWritesCheck: Date?
    private var hotSince: [String: (since: Date, alerted: Bool)] = [:]
    private var observers: [NSObjectProtocol] = []

    /// A process using at least this share of one core for `watchdogMinutes` while the user is away is reported.
    static let watchdogShare = 0.8
    static let watchdogMinutes: TimeInterval = 10 * 60
    /// The user counts as away (for sleep blockers and the watchdog) after this long without input.
    static let awayAfter: TimeInterval = 5 * 60

    init(store: SystemStore, machine: MachineStore) {
        self.store = store
        self.machine = machine
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.sample() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // A first pass sets the CPU / energy baselines; the next one (a minute later) records real deltas.
        queue.async { [self] in
            _ = cpuLoad()
            energy.baseline()
            lastWrites = Self.ssdBytesWritten()
            lastWritesCheck = Date()
        }
        // Sleep and wake with the battery level and macOS's dark-wake counter: the night card.
        let center = NSWorkspace.shared.notificationCenter
        for (name, kind) in [(NSWorkspace.willSleepNotification, PowerEvent.Kind.sleep),
                             (NSWorkspace.didWakeNotification, PowerEvent.Kind.wake)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.recordPower(kind)
            })
        }
    }

    private func recordPower(_ kind: PowerEvent.Kind) {
        let now = Date()
        let percent = BatteryReader.read()?.percent   // quick (I/O Registry), before the Mac goes to sleep
        queue.async { [self] in
            let event = PowerEvent(at: now, kind: kind, percent: percent, darkWakeCount: Self.darkWakeCount())
            do {
                try machine.record(event)
            } catch {
                NSLog("ActivityTracker: power event: \(error)")
            }
        }
    }

    /// `pmset -g stats`: the number of dark wakes since boot.
    private static func darkWakeCount() -> Int? {
        guard let output = try? Installer.run("/usr/bin/pmset", ["-g", "stats"], timeout: 5) else { return nil }
        return SleepNights.darkWakeCount(inStats: output)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Deletes battery/system history together with the activity data (see DataEraser).
    func erase(_ what: ActivityStore.Erase) {
        queue.async { [store] in
            do {
                try store.erase(what)
            } catch {
                NSLog("ActivityTracker: erase system data: \(error)")
            }
            DispatchQueue.main.async { NotificationCenter.default.post(name: .activityDataChanged, object: nil) }
        }
    }

    private func sample() {
        queue.async { [self] in
            let now = Date()
            // Samples queued up while the queue was busy would each claim a second: skip them.
            if let last = lastSampleAt, now.timeIntervalSince(last) < 30 { return }
            // Time this sample stands for: normally a minute; never more (after sleep the gap was not "on battery").
            let elapsed = lastSampleAt.map { min(max(now.timeIntervalSince($0), 1), Self.interval) } ?? Self.interval
            lastSampleAt = now

            var sample = SystemSample(at: now)
            if let battery = BatteryReader.read() {
                sample.batteryPercent = battery.percent
                sample.onAC = battery.onAC
                sample.isCharging = battery.charging
                sample.batteryWatts = battery.watts
                sample.batteryTemperature = battery.temperature
                sample.cycleCount = battery.cycleCount
                sample.healthPercent = battery.health
            }
            sample.cpuLoad = cpuLoad() ?? 0
            let memory = Self.memory()
            sample.memoryUsed = memory.used
            sample.memoryTotal = memory.total
            sample.swapUsed = Self.swapUsed()
            let disk = Self.disk()
            sample.diskFree = disk.free
            sample.diskTotal = disk.total
            sample.thermalState = ProcessInfo.processInfo.thermalState.rawValue
            if sample.onAC, let adapter = Self.adapter() {
                sample.adapterWatts = adapter.watts
                sample.adapterName = adapter.name
            }

            let apps = energy.collect()
            do {
                try store.record(sample, interval: elapsed, energy: apps)
            } catch {
                NSLog("ActivityTracker: system sample: \(error)")
            }
            let idle = Idle.secondsSinceLastInput()
            if idle >= Self.awayAfter {
                recordSleepBlockers(seconds: elapsed, at: now)
            }
            watchdog(apps, elapsed: elapsed, idle: idle, now: now)
            recordWrites(now)
        }
    }

    // MARK: Charger

    /// Watts and name of the connected power adapter.
    static func adapter() -> (watts: Double?, name: String?)? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        let watts = (details["Watts"] as? NSNumber)?.doubleValue
        let name = (details["Name"] as? String) ?? (details["Manufacturer"] as? String)
        return (watts, name)
    }

    // MARK: Hidden use

    /// While the user is away: which processes hold a "don't sleep" assertion. Runs on `queue`.
    private func recordSleepBlockers(seconds: TimeInterval, at now: Date) {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return }
        let types: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]
        var seen = Set<String>()
        for (pid, assertions) in byProcess {
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String, types.contains(type) else { continue }
                let process = (assertion["Process Name"] as? String) ?? Self.processName(pid.int32Value)
                let reason = (assertion["AssertName"] as? String) ?? type
                guard seen.insert(process + "|" + reason).inserted else { continue }
                try? machine.addBlocker(process: process, reason: reason, seconds: seconds, at: now)
            }
        }
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : "pid \(pid)"
    }

    /// A process busy on the CPU for 10+ minutes while the user is away: one notification and a Stability entry
    /// per stretch. Runs on `queue`.
    private func watchdog(_ apps: [AppEnergy], elapsed: TimeInterval, idle: TimeInterval, now: Date) {
        guard idle >= Self.awayAfter, elapsed > 0 else {
            hotSince.removeAll()
            return
        }
        var stillHot = Set<String>()
        for app in apps where app.cpuSeconds / elapsed >= Self.watchdogShare {
            stillHot.insert(app.bundleID)
            var entry = hotSince[app.bundleID] ?? (now.addingTimeInterval(-elapsed), false)
            let minutes = now.timeIntervalSince(entry.since)
            if !entry.alerted, minutes >= Self.watchdogMinutes {
                entry.alerted = true
                let share = Int((app.cpuSeconds / elapsed * 100).rounded())
                DispatchQueue.main.async {
                    AppServices.shared.notifier.runaway(name: app.appName, percent: share, minutes: minutes)
                    AppServices.shared.stability.recordRunaway(name: app.appName, percent: share, minutes: minutes, at: now)
                }
            }
            hotSince[app.bundleID] = entry
        }
        hotSince = hotSince.filter { stillHot.contains($0.key) }
    }

    /// Bytes written to the internal disk, added up per day (checked hourly). Runs on `queue`.
    private func recordWrites(_ now: Date) {
        guard let last = lastWritesCheck, now.timeIntervalSince(last) >= 3600 else { return }
        lastWritesCheck = now
        guard let total = Self.ssdBytesWritten() else { return }
        defer { lastWrites = total }
        guard let previous = lastWrites else { return }
        // After a restart the counter starts from zero.
        let delta = total >= previous ? total - previous : total
        try? machine.addWrites(delta, at: now)
    }

    /// "Bytes (Write)" of the storage drivers since boot (public I/O Registry statistics).
    static func ssdBytesWritten() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var total: Double = 0
        var found = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let bytes = statistics["Bytes (Write)"] as? NSNumber
            else { continue }
            total += bytes.doubleValue
            found = true
        }
        return found ? total : nil
    }

    // MARK: CPU

    /// Share of non-idle CPU ticks since the previous call (all cores together), nil on the first call.
    private func cpuLoad() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { previousCPU = (busy, total) }
        guard let previous = previousCPU, total > previous.total else { return nil }
        return Double(busy &- previous.busy) / Double(total - previous.total)
    }

    // MARK: Memory, swap, disk

    /// "Memory used" as Activity Monitor shows it: app memory + wired + compressed.
    private static func memory() -> (used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = Double(vm_kernel_page_size)
        let appPages = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (max(appPages, 0) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    private static func swapUsed() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used)
    }

    private static func disk() -> (free: Double, total: Double) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (Double(values?.volumeAvailableCapacityForImportantUsage ?? 0), Double(values?.volumeTotalCapacity ?? 0))
    }
}

/// Battery facts from the AppleSmartBattery entry of the I/O Registry (no special permissions needed).
enum BatteryReader {
    struct Reading {
        var percent: Double
        var onAC: Bool
        var charging: Bool
        var watts: Double?
        var temperature: Double?
        var cycleCount: Int?
        var health: Double?
    }

    static func read() -> Reading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }   // a Mac without a battery
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let battery = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }

        func number(_ key: String) -> Int64? {
            // Negative values (amperage while discharging) sometimes come back as huge unsigned numbers.
            (battery[key] as? NSNumber).map { Int64(truncatingIfNeeded: $0.uint64Value) }
        }

        // Apple Silicon reports CurrentCapacity/MaxCapacity in percent, Intel in mAh: the ratio works for both.
        guard let current = number("CurrentCapacity"), let maximum = number("MaxCapacity"), maximum > 0 else { return nil }
        var reading = Reading(
            percent: min(100, Double(current) / Double(maximum) * 100),
            onAC: (battery["ExternalConnected"] as? Bool) ?? false,
            charging: (battery["IsCharging"] as? Bool) ?? false)

        if let voltage = number("Voltage"), let amperage = number("InstantAmperage") ?? number("Amperage") {
            reading.watts = Double(voltage) / 1000 * Double(amperage) / 1000
        }
        if let temperature = number("Temperature") {
            reading.temperature = Double(temperature) / 100
        }
        reading.cycleCount = number("CycleCount").map(Int.init)
        let fullCharge = number("AppleRawMaxCapacity") ?? (maximum > 100 ? maximum : nil)
        if let fullCharge, let design = number("DesignCapacity"), design > 0 {
            reading.health = min(100, Double(fullCharge) / Double(design) * 100)
        }
        return reading
    }
}

/// Per-app energy and CPU time between calls, from proc_pid_rusage of every process the user owns.
/// Energy is `ri_energy_nj`, the process's own CPU/GPU energy (`ri_billed_energy` would be what *other* processes
/// spent on its behalf). Intel Macs have no such counter (it stays 0); the UI then ranks apps by CPU time.
/// Helper processes are attributed to the app bundle they live in (Chrome's renderers count as Chrome).
final class EnergyMeter {
    private struct Counters {
        var energy: UInt64   // nanojoules
        var cpu: UInt64      // Mach absolute time units
    }

    private struct ProcessKey: Hashable {
        var pid: pid_t
        var started: UInt64
    }

    private struct Owner {
        var bundleID: String
        var name: String
    }

    private var previous: [ProcessKey: Counters] = [:]
    private var owners: [ProcessKey: Owner] = [:]
    private var bundles: [String: Owner] = [:]
    private var lastCollect: UInt64 = 0
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Records the current counters without reporting anything (so the first report covers one interval only).
    func baseline() {
        _ = collect()
    }

    func collect() -> [AppEnergy] {
        let now = mach_absolute_time()
        let isFirst = lastCollect == 0
        var current: [ProcessKey: Counters] = [:]
        var perApp: [String: (owner: Owner, joules: Double, cpu: Double)] = [:]

        for pid in Self.allPIDs() where pid > 0 {
            var usage = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard result == 0 else { continue }   // other users' processes (root daemons) are not readable
            let key = ProcessKey(pid: pid, started: usage.ri_proc_start_abstime)
            let counters = Counters(energy: usage.ri_energy_nj, cpu: usage.ri_user_time + usage.ri_system_time)
            current[key] = counters
            guard !isFirst else { continue }

            let delta: Counters
            if let before = previous[key] {
                delta = Counters(energy: counters.energy &- before.energy, cpu: counters.cpu &- before.cpu)
                guard counters.energy >= before.energy, counters.cpu >= before.cpu else { continue }
            } else if key.started > lastCollect {
                delta = counters   // started during this interval: all of its usage is new
            } else {
                continue
            }
            guard delta.energy > 0 || delta.cpu > 0, let owner = owner(of: key) else { continue }
            var entry = perApp[owner.bundleID] ?? (owner, 0, 0)
            entry.joules += Double(delta.energy) / 1e9
            entry.cpu += Double(delta.cpu) * timebase / 1e9
            perApp[owner.bundleID] = entry
        }

        previous = current
        owners = owners.filter { current[$0.key] != nil }
        lastCollect = now
        return perApp.values.map { AppEnergy(bundleID: $0.owner.bundleID, appName: $0.owner.name,
                                             joules: $0.joules, cpuSeconds: $0.cpu) }
    }

    private func owner(of key: ProcessKey) -> Owner? {
        if let known = owners[key] { return known }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(key.pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)

        let owner: Owner
        if path.contains("/com.apple.WebKit.") {
            // Safari's (and Mail's) web pages run in shared WebKit helper processes outside any .app bundle.
            owner = Owner(bundleID: "com.apple.WebKit", name: L.tr("Веб-страницы (Safari и др.)", "Web pages (Safari etc.)"))
        } else if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            if let known = bundles[bundlePath] {
                owner = known
            } else {
                let bundle = Bundle(path: bundlePath)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
                owner = Owner(bundleID: bundle?.bundleIdentifier ?? bundlePath, name: name)
                bundles[bundlePath] = owner
            }
        } else {
            let name = URL(fileURLWithPath: path).lastPathComponent
            owner = Owner(bundleID: "process:\(name)", name: name)
        }
        owners[key] = owner
        return owner
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(count, 0))))
    }
}
