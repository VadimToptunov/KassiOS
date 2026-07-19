// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KassiOS",
    platforms: [
        .iOS(.v14),
        .macOS(.v11) // macOS UI testing works too; drop if you only target iOS.
    ],
    products: [
        .library(name: "KassiOS", targets: ["KassiOS"])
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
        )
    ]
)
