import Foundation

public enum URLTools {
    /// "https://www.youtube.com/watch?v=1" → "youtube.com". Non-web URLs give "".
    public static func domain(from url: String) -> String {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(), !host.isEmpty
        else { return "" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

public enum Format {
    /// 18720 → "5ч 12м" / "5h 12m", 720 → "12м" / "12m", 42 → "42с" / "42s".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let (h, m, s) = L.current == .en ? ("h", "m", "s") : ("ч", "м", "с")
        if hours > 0 {
            return minutes > 0 ? "\(hours)\(h) \(minutes)\(m)" : "\(hours)\(h)"
        }
        if minutes > 0 { return "\(minutes)\(m)" }
        return "\(total)\(s)"
    }

    /// Long spans: 1_958_520 → "22д 16ч" / "22d 16h"; under a day like `duration`.
    public static func longDuration(_ seconds: TimeInterval) -> String {
        guard seconds >= 86400 else { return duration(seconds) }
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let (d, h) = L.current == .en ? ("d", "h") : ("д", "ч")
        return hours > 0 ? "\(days)\(d) \(hours)\(h)" : "\(days)\(d)"
    }

    /// 15_300_000_000 → "15,3 ГБ" / "15.3 GB".
    public static func bytes(_ count: Double) -> String {
        let units = L.current == .en ? ["B", "KB", "MB", "GB", "TB"] : ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        var value = max(count, 0)
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let number = value >= 100 || unit == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return (L.current == .en ? number : number.replacingOccurrences(of: ".", with: ",")) + " " + units[unit]
    }

    /// Bytes per second → "12,4 Мбит/с" / "12.4 Mbit/s" (network speeds are quoted in bits).
    public static func bitrate(_ bytesPerSecond: Double) -> String {
        let units = L.current == .en ? ["bit/s", "Kbit/s", "Mbit/s", "Gbit/s"] : ["бит/с", "Кбит/с", "Мбит/с", "Гбит/с"]
        var value = max(bytesPerSecond, 0) * 8
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let number = value >= 100 || unit == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return (L.current == .en ? number : number.replacingOccurrences(of: ".", with: ",")) + " " + units[unit]
    }

    /// 23.4 → "23 мс" / "23 ms"; below 10 with a decimal.
    public static func milliseconds(_ value: Double) -> String {
        let number = value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return (L.current == .en ? number : number.replacingOccurrences(of: ".", with: ",")) + (L.current == .en ? " ms" : " мс")
    }

    /// 0.4321 → "43%"; tiny non-zero shares show as "<1%".
    public static func percent(_ part: TimeInterval, of whole: TimeInterval) -> String {
        guard whole > 0 else { return "0%" }
        let value = part / whole * 100
        if value > 0 && value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    /// "только что", "5 мин назад", "3 ч назад", "2 дн назад" / "just now", "5 min ago"…
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return L.tr("только что", "just now") }
        if seconds < 3600 { return L.tr("\(Int(seconds / 60)) мин назад", "\(Int(seconds / 60)) min ago") }
        if seconds < 86_400 { return L.tr("\(Int(seconds / 3600)) ч назад", "\(Int(seconds / 3600)) h ago") }
        return L.tr("\(Int(seconds / 86_400)) дн назад", "\(Int(seconds / 86_400)) d ago")
    }
}
