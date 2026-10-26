import Foundation

/// Pieces of the "install on iPhone" button that read tool output: Xcode's signed-in teams, connected iPhones
/// (`devicectl list devices --json-output`), the errors of an `xcodebuild` log.
public enum PhoneInstall {
    /// Where the source of the iPhone app comes from (the branch the Mac releases are built from).
    public static let repositoryURL = "https://github.com/iopew/learning.git"
    public static let branch = "claude/trusting-galileo-9vcql7"
    public static let projectPath = "ActivityTracker/Phone/ActivityPhone.xcodeproj"
    public static let scheme = "ActivityPhone"

    public struct Team: Equatable {
        public var id: String
        public var name: String
        public var isFree: Bool
    }

    public struct Device: Equatable {
        /// For devicectl.
        public var identifier: String
        /// For xcodebuild -destination id=…
        public var udid: String
        public var name: String
        public var wired: Bool
        public var developerModeEnabled: Bool
    }

    /// A bundle ID of our own per team: a free team can't use an ID another team registered first.
    public static func bundleID(team: String) -> String {
        "com.iopew.ActivityPhone." + team.filter { $0.isLetter || $0.isNumber }
    }

    /// Teams from `defaults export com.apple.dt.Xcode -` (Xcode → Settings → Accounts). Paid teams first.
    /// Xcode versions keep them under different keys (IDEProvisioningTeamByIdentifier, IDEProvisioningTeams, …),
    /// so every dictionary with a "teamID" anywhere in the settings counts.
    public static func teams(xcodeDefaults data: Data) -> [Team] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [] }
        var result: [Team] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 12 else { return }
            if let entry = value as? [String: Any] {
                if let id = (entry["teamID"] ?? entry["teamIdentifier"] ?? entry["TeamIdentifier"]) as? String,
                   isTeamID(id), !result.contains(where: { $0.id == id }) {
                    let name = (entry["teamName"] ?? entry["name"]) as? String ?? id
                    let type = entry["teamType"] as? String ?? ""
                    let isFree = (entry["isFreeProvisioningTeam"] as? Bool) ?? (type.contains("Personal") || name.contains("Personal Team"))
                    result.append(Team(id: id, name: name, isFree: isFree))
                }
                entry.values.forEach { visit($0, depth: depth + 1) }
            } else if let list = value as? [Any] {
                list.forEach { visit($0, depth: depth + 1) }
            } else if let data = value as? Data,
                      let nested = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                visit(nested, depth: depth + 1)   // some settings are stored as an embedded plist
            }
        }
        visit(plist, depth: 0)
        return result.sorted { !$0.isFree && $1.isFree }
    }

    /// Apple team IDs are 10 upper-case letters and digits.
    static func isTeamID(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { ($0.isASCII && $0.isUppercase && $0.isLetter) || ($0.isASCII && $0.isNumber) }
    }

    /// The team in a signing certificate's subject ("…/OU=ABCDE12345/…" from `security find-certificate -p | openssl x509 -subject`).
    public static func team(fromCertificateSubject subject: String) -> String? {
        for part in subject.components(separatedBy: CharacterSet(charactersIn: "/,")) {
            let field = part.trimmingCharacters(in: .whitespaces)
            for prefix in ["OU=", "OU = "] where field.hasPrefix(prefix) {
                let value = String(field.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if isTeamID(value) { return value }
            }
        }
        return nil
    }

    /// Paired iPhones from `devicectl list devices --json-output`, the cable-connected ones first.
    public static func devices(devicectlJSON data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = (root["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [] }
        var result: [Device] = []
        for device in devices {
            let hardware = device["hardwareProperties"] as? [String: Any] ?? [:]
            let connection = device["connectionProperties"] as? [String: Any] ?? [:]
            let properties = device["deviceProperties"] as? [String: Any] ?? [:]
            guard (hardware["platform"] as? String) == "iOS", (hardware["deviceType"] as? String) != "appleWatch",
                  (connection["pairingState"] as? String) == "paired",
                  (connection["tunnelState"] as? String) != "unavailable",
                  let identifier = device["identifier"] as? String, let udid = hardware["udid"] as? String
            else { continue }
            result.append(Device(identifier: identifier, udid: udid, name: properties["name"] as? String ?? "iPhone",
                                 wired: (connection["transportType"] as? String) == "wired",
                                 developerModeEnabled: (properties["developerModeStatus"] as? String ?? "enabled") == "enabled"))
        }
        return result.sorted { $0.wired && !$1.wired }
    }

    /// The distinct "error:" lines of an xcodebuild log, at most `limit`.
    public static func errors(inBuildLog log: String, limit: Int = 5) -> [String] {
        var seen: [String] = []
        for line in log.split(separator: "\n") {
            guard let range = line.range(of: "error: ") else { continue }
            let message = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !message.isEmpty, !seen.contains(message) { seen.append(message) }
            if seen.count == limit { break }
        }
        return seen
    }
}
