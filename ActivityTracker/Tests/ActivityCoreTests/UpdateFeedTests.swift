import XCTest
@testable import ActivityCore

final class UpdateFeedTests: XCTestCase {
    private func release(_ tag: String, asset: String = "ActivityTracker.zip", draft: Bool = false) -> String {
        """
        {"tag_name": "\(tag)", "draft": \(draft), "body": "notes for \(tag)",
         "assets": [{"name": "\(asset)", "browser_download_url": "https://github.com/iopew/learning/releases/download/\(tag)/\(asset)"}]}
        """
    }

    private func feed(_ releases: [String]) -> Data {
        Data("[\(releases.joined(separator: ","))]".utf8)
    }

    func testPicksHighestNewerBuild() throws {
        let data = feed([
            release("activity-tracker-build-9"),
            release("activity-tracker-build-12"),
            release("activity-tracker-build-10"),
        ])
        let update = try XCTUnwrap(UpdateFeed.newest(in: data, newerThan: 9))
        XCTAssertEqual(update.build, 12)
        XCTAssertEqual(update.tag, "activity-tracker-build-12")
        XCTAssertEqual(update.downloadURL.lastPathComponent, "ActivityTracker.zip")
        XCTAssertEqual(update.notes, "notes for activity-tracker-build-12")
    }

    func testNothingNewer() throws {
        let data = feed([release("activity-tracker-build-5"), release("activity-tracker-build-7")])
        XCTAssertNil(try UpdateFeed.newest(in: data, newerThan: 7))
    }

    func testIgnoresDraftsForeignTagsAndMissingAssets() throws {
        let data = feed([
            release("activity-tracker-build-20", draft: true),
            release("v2.0"),
            release("activity-tracker-build-x"),
            release("activity-tracker-build-15", asset: "Other.zip"),
            release("activity-tracker-build-11"),
        ])
        XCTAssertEqual(try UpdateFeed.newest(in: data, newerThan: 1)?.build, 11)
    }

    func testEmptyFeed() throws {
        XCTAssertNil(try UpdateFeed.newest(in: Data("[]".utf8), newerThan: 0))
    }

    func testMalformedFeedThrows() {
        XCTAssertThrowsError(try UpdateFeed.newest(in: Data("{\"message\": \"rate limited\"}".utf8), newerThan: 0))
    }
}
