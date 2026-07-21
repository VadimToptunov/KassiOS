// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KassiOSLint",
    platforms: [
        .macOS(.v13) // SwiftSyntax needs macOS 13+; this tool runs on the host, not iOS.
    ],
    products: [
        .executable(name: "kassios-lint", targets: ["kassios-lint"]),
        .library(name: "KassiOSLintCore", targets: ["KassiOSLintCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"700.0.0")
    ],
    targets: [
        // The testable core: all SwiftSyntax parsing/diagnostic logic lives here so
        // it can be unit tested without shelling out to the CLI.
        .target(
            name: "KassiOSLintCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/KassiOSLintCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Thin CLI wrapper: reads paths from argv, prints diagnostics, sets exit code.
        .executableTarget(
            name: "kassios-lint",
            dependencies: ["KassiOSLintCore"],
            path: "Sources/kassios-lint",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // SPM command plugin: `swift package kassios-lint` runs the CLI over the
        // package's source root.
        .plugin(
            name: "KassiOSLintCommand",
            capability: .command(
                intent: .custom(verb: "kassios-lint", description: "Statically lint KassScreen definitions"),
                permissions: []
            ),
            dependencies: ["kassios-lint"],
            path: "Plugins/KassiOSLintCommand"
        ),
        .testTarget(
            name: "KassiOSLintCoreTests",
            dependencies: ["KassiOSLintCore"],
            path: "Tests/KassiOSLintCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
