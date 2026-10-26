// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ActivityTracker",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .executable(name: "ActivityTracker", targets: ["ActivityTracker"]),
        // Used by the iPhone app (Phone/ActivityPhone.xcodeproj).
        .library(name: "ActivityCore", targets: ["ActivityCore"]),
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
            dependencies: ["ActivityCore"],
            // FoundationModels (on-device AI, macOS 26+) is linked weakly so the app still starts on macOS 13–15.
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-autolink-framework", "-Xfrontend", "FoundationModels"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])]
        ),
        .testTarget(
            name: "ActivityCoreTests",
            dependencies: ["ActivityCore"]
        ),
    ]
)
