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

    private var reportingStarted = false

    open override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Attaches a screenshot of the final state whenever the test failed, so a
    /// red run in the `.xcresult` always carries visual evidence, and closes the
    /// structured report (if any).
    open override func tearDown() {
        let failed = (testRun?.failureCount ?? 0) > 0
        if failed, app != nil {
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "Failure — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            config.reporter?.attach(name: "Failure", type: "image/png", data: shot.pngRepresentation)
        }
        if reportingStarted {
            config.reporter?.testFinished(
                status: failed ? .failed : .passed,
                message: failed ? "Test failed — see attached screenshot" : nil
            )
        }
        super.tearDown()
    }

    /// Opens the structured report lazily, on first use, so a `config` (and its
    /// `reporter`) assigned in a subclass's `setUp` is already in place.
    private func startReportingIfNeeded() {
        guard !reportingStarted else { return }
        reportingStarted = true
        let (display, full) = Self.parseTestName(name)
        config.reporter?.testStarted(name: display, fullName: full)
    }

    /// Splits XCTest's `-[Class method]` name into (method, "Class.method").
    static func parseTestName(_ raw: String) -> (name: String, fullName: String) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-[]"))
        let parts = trimmed.split(separator: " ")
        guard parts.count == 2 else { return (trimmed, trimmed) }
        let cls = parts[0].split(separator: ".").last.map(String.init) ?? String(parts[0])
        let method = String(parts[1])
        return (method, "\(cls).\(method)")
    }

    /// Launches the app under test.
    @discardableResult
    public func launch(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        startReportingIfNeeded()
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
        startReportingIfNeeded()
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
    /// (via `XCTContext`), records it in the structured report, and logs
    /// start/finish to the console.
    public func step(_ name: String, _ block: () -> Void) {
        startReportingIfNeeded()
        config.logger.log("▶︎ \(name)")
        config.reporter?.stepStarted(name)
        let start = Date()
        XCTContext.runActivity(named: name) { _ in
            block()
        }
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        config.logger.log("✓ \(name) (\(elapsed))")
        config.reporter?.stepFinished(status: .passed, message: nil)
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
