// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KassiOS",
    platforms: [
        .iOS(.v14),
        .macOS(.v11) // macOS UI testing works too; drop if you only target iOS.
    ],
    products: [
        .library(name: "KassiOS", targets: ["KassiOS"]),
        // The host-side bridge for Tier C device control (permissions, push,
        // location, status bar). Runs on the Mac; the in-simulator test client
        // reaches it over 127.0.0.1. Separate product so the library needs it
        // only for the shared wire types.
        .executable(name: "kassios-agent", targets: ["KassiOSAgentCLI"])
    ],
    targets: [
        // The library imports XCTest so it can wrap XCUIElement. This is the same
        // approach XCUITest helper libraries use: you add KassiOS to your app's
        // *UI Test* target, where XCTest/XCUITest are available.
        .target(
            name: "KassiOS",
            path: "Sources/KassiOS",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KassiOSTests",
            dependencies: ["KassiOS"],
            path: "Tests/KassiOSTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The agent executable (Foundation + Darwin sockets; macOS host only).
        // It carries its own copy of the wire protocol — it can't import the
        // XCTest-based library, and that library is compiled straight into iOS
        // UI-test targets, so the two share the contract by matching Codable.
        .executableTarget(
            name: "KassiOSAgentCLI",
            path: "Sources/KassiOSAgentCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KassiOSAgentCLITests",
            dependencies: ["KassiOSAgentCLI"],
            path: "Tests/KassiOSAgentCLITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
