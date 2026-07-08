import XCTest

/// Base class for UI tests. Subclass this instead of `XCTestCase`.
///
/// Gives you `launch()`, the `onScreen(_:)` scope, and `step(_:)` — the pieces
/// that make a test read like a script instead of a pile of queries.
open class KassTestCase: XCTestCase {

    public private(set) var app: XCUIApplication!
    public var config: KassConfig = .default

    /// Device- and system-level helpers (permissions, keyboard, screenshots,
    /// backgrounding, orientation, deep links).
    public lazy var device = KassDevice(app: app, config: config)

    open override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Attaches a screenshot of the final state whenever the test failed, so a
    /// red run in the `.xcresult` always carries visual evidence.
    open override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0, app != nil {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Failure — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.tearDown()
    }

    /// Launches the app under test.
    @discardableResult
    public func launch(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        app.launchArguments += arguments
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
        return app
    }

    /// Enter a screen scope. Waits for the screen's `onLoad` elements to be
    /// visible (fails fast if they aren't), then runs `block` against it.
    @discardableResult
    public func onScreen<S: KassScreen>(
        _ type: S.Type,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: (S) -> Void
    ) -> S {
        let screen = S(app: app, config: config)
        XCTContext.runActivity(named: "On \(String(describing: type))") { _ in
            for element in screen.onLoad {
                element.assertVisible(file: file, line: line)
            }
            block(screen)
        }
        return screen
    }

    /// A labelled, timed step. Groups its actions in Xcode's test report
    /// (via `XCTContext`) and logs start/finish to the console.
    public func step(_ name: String, _ block: () -> Void) {
        config.logger.log("▶︎ \(name)")
        let start = Date()
        XCTContext.runActivity(named: name) { _ in
            block()
        }
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        config.logger.log("✓ \(name) (\(elapsed))")
    }

    /// Runs a reusable `KassScenario` against this test case, grouped in the
    /// report under the scenario's name.
    public func scenario(_ scenario: KassScenario) {
        config.logger.log("▶︎ Scenario: \(scenario.name)")
        XCTContext.runActivity(named: "Scenario: \(scenario.name)") { _ in
            scenario.run(in: self)
        }
    }
}
