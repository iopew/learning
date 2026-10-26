import Foundation

/// The network the Mac was on: a Wi-Fi network by name, a cable, the iPhone hotspot.
public struct NetworkInfo: Equatable {
    public enum Kind: String {
        case wifi, ethernet, hotspot, cellular, other
    }

    /// Stable identity: "wifi:Home_5G", "ethernet:en5", "router:192.168.1.1".
    public var key: String
    public var name: String
    public var kind: Kind

    public init(key: String, name: String, kind: Kind) {
        self.key = key
        self.name = name
        self.kind = kind
    }
}

/// One minute of networking: traffic of all physical interfaces, observed speeds, Wi-Fi link, ping.
public struct NetworkSample: Equatable {
    public var at: Date
    /// Seconds the sample stands for (normally 60).
    public var interval: TimeInterval
    public var network: NetworkInfo
    /// Bytes received / sent.
    public var rx: Double = 0
    public var tx: Double = 0
    /// Fastest 5-second average in the minute, bytes per second.
    public var peakRx: Double = 0
    public var peakTx: Double = 0
    /// Bytes and seconds of the 5-second windows with real transfer (above ~50 KB/s): the average speed while
    /// something was actually downloading, not diluted by idle time.
    public var busyRxBytes: Double = 0
    public var busyRxSeconds: Double = 0
    public var busyTxBytes: Double = 0
    public var busyTxSeconds: Double = 0
    /// Wi-Fi link rate to the router, Mbit/s; signal, dBm.
    public var linkRate: Double?
    public var rssi: Double?
    /// Round trip in ms to the router and to the internet (1.1.1.1); nil when no answer.
    public var pingRouter: Double?
    public var pingInternet: Double?
    /// Share of lost internet pings, 0…1.
    public var loss: Double?
    /// The internet answered; false = an outage minute; nil = not measured.
    public var online: Bool?

    public init(at: Date, interval: TimeInterval, network: NetworkInfo) {
        self.at = at
        self.interval = interval
        self.network = network
    }
}

/// One network over a period.
public struct NetworkUsage: Equatable, Identifiable {
    public var key: String
    public var name: String
    public var kind: NetworkInfo.Kind
    public var rx: Double
    public var tx: Double
    /// Time connected.
    public var connected: TimeInterval
    /// Average speed while transferring, bytes/s.
    public var averageDown: Double?
    public var averageUp: Double?
    public var peakDown: Double
    public var peakUp: Double
    public var linkRate: Double?
    public var rssi: Double?
    public var pingRouter: Double?
    public var pingInternet: Double?
    public var loss: Double?
    public var outageTime: TimeInterval
    public var outages: Int
    public var firstSeen: Date
    public var lastSeen: Date

    public var id: String { key }
    public var total: Double { rx + tx }
}

/// Traffic of one network in one chart bar.
public struct NetworkBucket: Equatable, Identifiable {
    public var start: Date
    public var key: String
    public var name: String
    public var rx: Double
    public var tx: Double

    public var id: String { "\(start.timeIntervalSince1970)|\(key)" }
}

public struct NetworkReport: Equatable {
    public enum Unit: Equatable {
        case hour, day, week
    }

    public var range: StatsRange
    public var fromDay: Date
    public var toDay: Date
    public var rx: Double
    public var tx: Double
    public var networks: [NetworkUsage]
    public var buckets: [NetworkBucket]
    public var unit: Unit

    public var total: Double { rx + tx }
    public var hasData: Bool { !networks.isEmpty }
}

/// Network history in the same SQLite file (own connection), one row per minute. Thread-safe.
public final class NetworkStore {
    public let days: DayCalendar
    private let db: Database
    private let lock = NSLock()

    public init(path: String, days: DayCalendar = DayCalendar()) throws {
        self.days = days
        db = try Database(path: path)
        try db.execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA secure_delete=ON;
            CREATE TABLE IF NOT EXISTS networks(
                key TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                custom_name TEXT
            );
            CREATE TABLE IF NOT EXISTS network_samples(
                at REAL PRIMARY KEY,
                day TEXT NOT NULL,
                network TEXT NOT NULL,
                interval REAL NOT NULL,
                rx REAL NOT NULL,
                tx REAL NOT NULL,
                peak_rx REAL NOT NULL,
                peak_tx REAL NOT NULL,
                busy_rx_bytes REAL NOT NULL,
                busy_rx_seconds REAL NOT NULL,
                busy_tx_bytes REAL NOT NULL,
                busy_tx_seconds REAL NOT NULL,
                link_rate REAL,
                rssi REAL,
                ping_router REAL,
                ping_internet REAL,
                loss REAL,
                online INTEGER
            );
            CREATE INDEX IF NOT EXISTS network_samples_day ON network_samples(day);
            """)
        // Hourly roll-ups of old minutes keep their outage time and count (`online` is per minute only).
        if !(try db.columns(of: "network_samples")).contains("rolled") {
            try db.execute("""
                ALTER TABLE network_samples ADD COLUMN rolled INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE network_samples ADD COLUMN offline_seconds REAL;
                ALTER TABLE network_samples ADD COLUMN outage_count INTEGER;
                """)
        }
    }

    /// Minutes before `moment` become one row per hour and network: traffic, busy time, peaks and outages stay
    /// exact, link / signal / ping / loss become time-weighted averages. Returns the number of minutes folded.
    @discardableResult
    public func rollUp(before moment: Date) throws -> Int {
        // A day at a time, each in its own short transaction: the tracker and the reports never wait long for the
        // lock or the database.
        let end = (moment.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        var total = 0
        while true {
            let folded = try rollUpChunk(before: end)
            if folded == 0 { break }
            total += folded
        }
        return total
    }

    private func rollUpChunk(before end: Double) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard let first = try db.query("SELECT MIN(at), COUNT(*) FROM network_samples WHERE rolled = 0 AND at < ?", [.double(end)],
                                       map: { $0.int(1) > 0 ? $0.double(0) : nil }).first ?? nil
        else { return 0 }
        let chunkEnd = min(end, (first / 3600).rounded(.down) * 3600 + 86400)
        let cutoff = SQLValue.double(chunkEnd)
        let count = try db.query("SELECT COUNT(*) FROM network_samples WHERE rolled = 0 AND at < ?", [cutoff]) { Int($0.int(0)) }.first ?? 0
        guard count > 0 else { return 0 }
        func average(_ column: String) -> String {
            "SUM(\(column) * interval) / SUM(CASE WHEN \(column) IS NOT NULL THEN interval END) AS \(column)"
        }
        try db.execute("BEGIN")
        do {
            try db.run("DROP TABLE IF EXISTS temp.network_rollup")
            try db.run("""
                CREATE TEMP TABLE network_rollup AS
                WITH m AS (
                    SELECT *, LAG(online) OVER (PARTITION BY network ORDER BY at) AS previous_online,
                           at - LAG(at) OVER (PARTITION BY network ORDER BY at) AS dt
                    FROM network_samples WHERE rolled = 0 AND at < ?
                )
                SELECT MIN(at) AS at, MIN(day) AS day, network, SUM(interval) AS interval, SUM(rx) AS rx, SUM(tx) AS tx,
                       MAX(peak_rx) AS peak_rx, MAX(peak_tx) AS peak_tx, SUM(busy_rx_bytes) AS busy_rx_bytes,
                       SUM(busy_rx_seconds) AS busy_rx_seconds, SUM(busy_tx_bytes) AS busy_tx_bytes,
                       SUM(busy_tx_seconds) AS busy_tx_seconds, \(average("link_rate")), \(average("rssi")),
                       \(average("ping_router")), \(average("ping_internet")), \(average("loss")),
                       SUM(CASE WHEN online = 0 THEN interval ELSE 0 END) AS offline_seconds,
                       SUM(CASE WHEN online = 0 AND (previous_online IS NULL OR previous_online != 0 OR dt > 90)
                                THEN 1 ELSE 0 END) AS outage_count
                FROM m GROUP BY CAST(at / 3600 AS INTEGER), network
                """, [cutoff])
            try db.run("DELETE FROM network_samples WHERE rolled = 0 AND at < ?", [cutoff])
            try db.run("""
                INSERT INTO network_samples(at, day, network, interval, rx, tx, peak_rx, peak_tx, busy_rx_bytes,
                    busy_rx_seconds, busy_tx_bytes, busy_tx_seconds, link_rate, rssi, ping_router, ping_internet, loss,
                    online, rolled, offline_seconds, outage_count)
                SELECT at, day, network, interval, rx, tx, peak_rx, peak_tx, busy_rx_bytes, busy_rx_seconds, busy_tx_bytes,
                       busy_tx_seconds, link_rate, rssi, ping_router, ping_internet, loss, NULL, 1, offline_seconds,
                       outage_count
                FROM temp.network_rollup
                """)
            try db.run("DROP TABLE temp.network_rollup")
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        return count
    }

    public func record(_ sample: NetworkSample) throws {
        lock.lock()
        defer { lock.unlock() }

        func optional(_ value: Double?) -> SQLValue { value.map { .double($0) } ?? .null }
        try db.execute("BEGIN")
        do {
            // The detected name follows the network (a renamed hotspot); a name the user set stays.
            try db.run("""
                INSERT INTO networks(key, name, kind) VALUES(?,?,?)
                ON CONFLICT(key) DO UPDATE SET name = excluded.name, kind = excluded.kind
                """, [.text(sample.network.key), .text(sample.network.name), .text(sample.network.kind.rawValue)])
            try db.run("""
                INSERT OR REPLACE INTO network_samples(at, day, network, interval, rx, tx, peak_rx, peak_tx,
                    busy_rx_bytes, busy_rx_seconds, busy_tx_bytes, busy_tx_seconds, link_rate, rssi, ping_router,
                    ping_internet, loss, online)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [.double(sample.at.timeIntervalSince1970), .text(days.key(sample.at)), .text(sample.network.key),
                 .double(sample.interval), .double(sample.rx), .double(sample.tx), .double(sample.peakRx),
                 .double(sample.peakTx), .double(sample.busyRxBytes), .double(sample.busyRxSeconds),
                 .double(sample.busyTxBytes), .double(sample.busyTxSeconds), optional(sample.linkRate),
                 optional(sample.rssi), optional(sample.pingRouter), optional(sample.pingInternet),
                 optional(sample.loss), sample.online.map { .int($0 ? 1 : 0) } ?? .null])
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    /// The user's own name for a network; nil or empty brings the detected name back.
    public func rename(_ key: String, to name: String?) throws {
        lock.lock()
        defer { lock.unlock() }

        let value = name?.trimmingCharacters(in: .whitespaces) ?? ""
        try db.run("UPDATE networks SET custom_name = ? WHERE key = ?", [value.isEmpty ? .null : .text(value), .text(key)])
    }

    public func erase(_ what: ActivityStore.Erase) throws {
        lock.lock()
        defer { lock.unlock() }

        switch what {
        case .domain, .app:
            return
        case .since(let moment):
            try db.run("DELETE FROM network_samples WHERE at >= ?", [.double(moment.timeIntervalSince1970)])
        case .before(let moment):
            try db.run("DELETE FROM network_samples WHERE at < ?", [.double(moment.timeIntervalSince1970)])
        case .all:
            try db.execute("DELETE FROM network_samples; DELETE FROM networks;")
        }
        // Network names (Wi-Fi names reveal places) go with their last sample.
        try db.execute("""
            DELETE FROM networks WHERE key NOT IN (SELECT DISTINCT network FROM network_samples);
            PRAGMA wal_checkpoint(TRUNCATE);
            """)
    }

    @discardableResult
    public func rekeyDays() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        return try ActivityStore.rekey(db: db, table: "network_samples", idColumn: "rowid", timeColumn: "at", days: days)
    }

    // MARK: - Reports

    public func report(range: StatsRange, anchor: Date) throws -> NetworkReport {
        lock.lock()
        defer { lock.unlock() }

        let toDay = days.startOfDay(anchor)
        var fromDay: Date
        if let length = range.days {
            fromDay = days.addingDays(-(length - 1), to: toDay)
        } else {
            let first = try db.query("SELECT MIN(day) FROM network_samples") { $0.text(0) }.first ?? ""
            fromDay = days.date(fromKey: first) ?? toDay
        }
        fromDay = min(fromDay, toDay)
        let window: [SQLValue] = [.text(days.key(fromDay)), .text(days.key(toDay))]

        var names: [String: (String, NetworkInfo.Kind)] = [:]
        for (key, name, custom, kind) in try db.query("SELECT key, name, COALESCE(custom_name, ''), kind FROM networks",
                                                      map: { ($0.text(0), $0.text(1), $0.text(2), $0.text(3)) }) {
            names[key] = (custom.isEmpty ? name : custom, NetworkInfo.Kind(rawValue: kind) ?? .other)
        }

        // Rolled-up hours stand for many minutes: averages are weighted by time.
        func weighted(_ column: String) -> String {
            "SUM(\(column) * interval) / SUM(CASE WHEN \(column) IS NOT NULL THEN interval END)"
        }
        var rolledOutages: [String: Int] = [:]
        var networks = try db.query(
            """
            SELECT network, SUM(rx), SUM(tx), SUM(interval), MAX(peak_rx), MAX(peak_tx),
                   SUM(busy_rx_bytes), SUM(busy_rx_seconds), SUM(busy_tx_bytes), SUM(busy_tx_seconds),
                   \(weighted("link_rate")), \(weighted("rssi")), \(weighted("ping_router")),
                   \(weighted("ping_internet")), \(weighted("loss")),
                   SUM(CASE WHEN online = 0 THEN interval ELSE 0 END) + COALESCE(SUM(offline_seconds), 0), MIN(at), MAX(at),
                   COUNT(link_rate), COUNT(rssi), COUNT(ping_router), COUNT(ping_internet), COUNT(loss),
                   COALESCE(SUM(outage_count), 0)
            FROM network_samples WHERE day BETWEEN ? AND ? GROUP BY network
            """, window
        ) { row -> NetworkUsage in
            func optional(_ column: Int32, count: Int32) -> Double? { row.int(count) > 0 ? row.double(column) : nil }
            func speed(_ bytes: Int32, _ seconds: Int32) -> Double? {
                row.double(seconds) >= 5 ? row.double(bytes) / row.double(seconds) : nil
            }
            let key = row.text(0)
            rolledOutages[key] = Int(row.int(23))
            return NetworkUsage(
                key: key, name: names[key]?.0 ?? key, kind: names[key]?.1 ?? .other,
                rx: row.double(1), tx: row.double(2), connected: row.double(3),
                averageDown: speed(6, 7), averageUp: speed(8, 9),
                peakDown: row.double(4), peakUp: row.double(5),
                linkRate: optional(10, count: 18), rssi: optional(11, count: 19),
                pingRouter: optional(12, count: 20), pingInternet: optional(13, count: 21), loss: optional(14, count: 22),
                outageTime: row.double(15), outages: 0,
                firstSeen: Date(timeIntervalSince1970: row.double(16)),
                lastSeen: Date(timeIntervalSince1970: row.double(17)))
        }

        // Outages: runs of minutes without internet (a gap of more than 90 s starts a new one).
        var outageCounts: [String: Int] = [:]
        var lastOffline: [String: Double] = [:]
        for (key, at) in try db.query(
            "SELECT network, at FROM network_samples WHERE day BETWEEN ? AND ? AND online = 0 ORDER BY at",
            window, map: { ($0.text(0), $0.double(1)) }) {
            if let previous = lastOffline[key], at - previous <= 90 {
                // the same outage continues
            } else {
                outageCounts[key, default: 0] += 1
            }
            lastOffline[key] = at
        }
        for index in networks.indices {
            networks[index].outages = (outageCounts[networks[index].key] ?? 0) + (rolledOutages[networks[index].key] ?? 0)
        }
        networks.sort { $0.total > $1.total || ($0.total == $1.total && $0.name < $1.name) }

        // Chart: hours for one day, days up to ~3 months, weeks beyond.
        let span = days.dayCount(from: fromDay, to: toDay)
        let unit: NetworkReport.Unit = span <= 1 ? .hour : (span <= 92 ? .day : .week)
        var buckets: [String: NetworkBucket] = [:]
        if unit == .hour {
            for (hour, key, rx, tx) in try db.query(
                """
                SELECT CAST(at / 3600 AS INTEGER) * 3600, network, SUM(rx), SUM(tx) FROM network_samples
                WHERE day BETWEEN ? AND ? GROUP BY 1, network
                """, window, map: { ($0.double(0), $0.text(1), $0.double(2), $0.double(3)) }) {
                let start = Date(timeIntervalSince1970: hour)
                buckets["\(hour)|\(key)"] = NetworkBucket(start: start, key: key, name: names[key]?.0 ?? key, rx: rx, tx: tx)
            }
        } else {
            for (dayKey, key, rx, tx) in try db.query(
                "SELECT day, network, SUM(rx), SUM(tx) FROM network_samples WHERE day BETWEEN ? AND ? GROUP BY day, network",
                window, map: { ($0.text(0), $0.text(1), $0.double(2), $0.double(3)) }) {
                guard let day = days.date(fromKey: dayKey) else { continue }
                let start = unit == .day ? day : days.startOfWeek(day)
                let id = "\(start.timeIntervalSince1970)|\(key)"
                var bucket = buckets[id] ?? NetworkBucket(start: start, key: key, name: names[key]?.0 ?? key, rx: 0, tx: 0)
                bucket.rx += rx
                bucket.tx += tx
                buckets[id] = bucket
            }
        }
        let sortedBuckets = buckets.values.sorted { $0.start < $1.start || ($0.start == $1.start && $0.key < $1.key) }
        return NetworkReport(range: range, fromDay: fromDay, toDay: toDay,
                             rx: networks.reduce(0) { $0 + $1.rx }, tx: networks.reduce(0) { $0 + $1.tx },
                             networks: networks, buckets: sortedBuckets, unit: unit)
    }
}

/// Parses the summary of macOS `ping`.
public enum PingOutput {
    /// Average round trip in ms (nil when nothing came back) and the share of lost packets (0…1).
    public static func parse(_ text: String) -> (average: Double?, loss: Double?) {
        var loss: Double?
        if let range = text.range(of: "% packet loss") {
            let before = text[..<range.lowerBound]
            let number = before.reversed().prefix { $0.isNumber || $0 == "." }
            loss = Double(String(number.reversed())).map { $0 / 100 }
        }
        var average: Double?
        if let range = text.range(of: "min/avg/max") {
            let rest = text[range.upperBound...]
            if let equals = rest.firstIndex(of: "=") {
                let values = rest[rest.index(after: equals)...]
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: "/")
                if values.count >= 2 { average = Double(values[1].trimmingCharacters(in: .whitespaces)) }
            }
        }
        return (average, loss)
    }
}
