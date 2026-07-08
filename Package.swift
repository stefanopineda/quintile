// swift-tools-version:6.0
import PackageDescription

// Tests: this environment ships Command Line Tools without a usable
// XCTest/Testing harness, so tests live in the `quintile-tests` executable
// (Tests/QuintileTestRunner) with a tiny Swift-Testing-shaped API.
// Run them with `swift run quintile-tests` (or `make test`).
let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Quintile",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Testable core: pure logic, no SwiftUI. AppKit/ApplicationServices are
        // used only behind protocol seams so unit tests run without permissions.
        .target(
            name: "QuintileCore",
            path: "Sources/QuintileCore",
            swiftSettings: settings
        ),
        // Thin app shell: LSUIElement menu-bar agent (bundle assembled by Scripts/build-app.sh).
        .executableTarget(
            name: "QuintileApp",
            dependencies: ["QuintileCore"],
            path: "Sources/QuintileApp",
            swiftSettings: settings
        ),
        .executableTarget(
            name: "quintile-tests",
            dependencies: ["QuintileCore"],
            path: "Tests/QuintileTestRunner",
            swiftSettings: settings
        ),
    ]
)
