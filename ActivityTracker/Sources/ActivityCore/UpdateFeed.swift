import Foundation

/// A newer build published on GitHub Releases.
public struct AvailableUpdate: Equatable {
    public var build: Int
    public var tag: String
    public var downloadURL: URL
    public var notes: String
}

/// Picks the newest app build out of the GitHub Releases API response
/// (GET /repos/{owner}/{repo}/releases). Builds are tagged "<prefix><build number>", e.g. "activity-tracker-build-42".
public enum UpdateFeed {
    public static let tagPrefix = "activity-tracker-build-"
    public static let assetName = "ActivityTracker.zip"
    /// Releases are only accepted from this repository.
    public static let repository = "iopew/learning"
    /// A forged "build 2000000000" would otherwise block every real update after it.
    public static let maximumJump = 10_000

    private struct Release: Decodable {
        var tag_name: String
        var draft: Bool?
        var body: String?
        var assets: [Asset]
    }

    private struct Asset: Decodable {
        var name: String
        var browser_download_url: URL
    }

    /// The highest build newer than `currentBuild` that has the app zip attached, or nil.
    public static func newest(in releasesJSON: Data, newerThan currentBuild: Int) throws -> AvailableUpdate? {
        let releases = try JSONDecoder().decode([Release].self, from: releasesJSON)
        var best: AvailableUpdate?
        for release in releases where release.draft != true && release.tag_name.hasPrefix(tagPrefix) {
            guard let build = Int(release.tag_name.dropFirst(tagPrefix.count)), build > currentBuild,
                  build <= currentBuild + maximumJump,
                  let asset = release.assets.first(where: { $0.name == assetName }),
                  isTrustedDownload(asset.browser_download_url, tag: release.tag_name)
            else { continue }
            if build > (best?.build ?? Int.min) {
                best = AvailableUpdate(build: build, tag: release.tag_name, downloadURL: asset.browser_download_url,
                                       notes: release.body ?? "")
            }
        }
        return best
    }

    /// Only https://github.com/<repository>/releases/download/<tag>/ActivityTracker.zip: a poisoned feed can't point
    /// the updater at another host, plain http or a local file.
    public static func isTrustedDownload(_ url: URL, tag: String) -> Bool {
        guard url.scheme == "https", url.host == "github.com", url.user == nil, url.port == nil,
              url.query == nil, url.fragment == nil
        else { return false }
        return url.path == "/\(repository)/releases/download/\(tag)/\(assetName)"
    }

    /// Zip entries of an update: everything inside one top-level ActivityTracker.app, no absolute paths, no "..".
    public static func isSafeArchiveListing(_ entries: [String]) -> Bool {
        guard !entries.isEmpty else { return false }
        for entry in entries where !entry.isEmpty {
            guard !entry.hasPrefix("/"), entry == "ActivityTracker.app/" || entry.hasPrefix("ActivityTracker.app/"),
                  !entry.split(separator: "/").contains("..")
            else { return false }
        }
        return true
    }
}
