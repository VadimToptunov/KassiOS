// swift-tools-version:5.9
import PackageDescription

// NOTE: "KassiOS" is a placeholder name — rename here and in the Sources/KassiOS folder
// to whatever you settle on. This is the only place the module name is defined.
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
            path: "Sources/KassiOS"
        ),
        .testTarget(
            name: "KassiOSTests",
            dependencies: ["KassiOS"],
            path: "Tests/KassiOSTests"
        )
    ]
)
