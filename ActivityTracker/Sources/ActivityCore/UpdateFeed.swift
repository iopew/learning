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
                  let asset = release.assets.first(where: { $0.name == assetName })
            else { continue }
            if build > (best?.build ?? Int.min) {
                best = AvailableUpdate(build: build, tag: release.tag_name, downloadURL: asset.browser_download_url,
                                       notes: release.body ?? "")
            }
        }
        return best
    }
}
