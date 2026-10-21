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
    /// 18720 → "5ч 12м", 720 → "12м", 42 → "42с".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)ч \(minutes)м" : "\(hours)ч"
        }
        if minutes > 0 { return "\(minutes)м" }
        return "\(total)с"
    }

    /// 0.4321 → "43%"; tiny non-zero shares show as "<1%".
    public static func percent(_ part: TimeInterval, of whole: TimeInterval) -> String {
        guard whole > 0 else { return "0%" }
        let value = part / whole * 100
        if value > 0 && value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }
}
