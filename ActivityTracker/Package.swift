// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ActivityTracker",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ActivityTracker", targets: ["ActivityTracker"]),
    ],
    targets: [
        // Platform-independent logic: storage, aggregation, reports. Fully unit-tested.
        .target(
            name: "ActivityCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The macOS menu bar app: collectors (AppKit, Accessibility, AppleScript) and SwiftUI views.
        .executableTarget(
            name: "ActivityTracker",
            dependencies: ["ActivityCore"]
        ),
        .testTarget(
            name: "ActivityCoreTests",
            dependencies: ["ActivityCore"]
        ),
    ]
)
