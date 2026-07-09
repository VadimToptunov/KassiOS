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

    // MARK: - Flow primitives (Kaspresso-style)

    /// Retries `block` until it stops throwing or the time budget elapses, then
    /// `XCTFail`s. Use for custom multi-step conditions; single interactions are
    /// already flaky-safe on their own.
    @discardableResult
    public func flakySafely<T>(
        timeout: TimeInterval? = nil,
        pollInterval: TimeInterval? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () throws -> T
    ) -> T? {
        do {
            return try Waiter.retry(
                timeout: timeout ?? config.timeout,
                pollInterval: pollInterval ?? config.pollInterval,
                enabled: config.flakySafetyEnabled,
                action: block
            )
        } catch {
            config.logger.log("❌ flakySafely failed: \(error)")
            XCTFail("flakySafely failed: \(error)", file: file, line: line)
            return nil
        }
    }

    /// Asserts `block` keeps succeeding for the whole `duration` — fails the
    /// instant it throws. The inverse of `flakySafely`.
    public func continuously(
        during duration: TimeInterval,
        pollInterval: TimeInterval? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () throws -> Void
    ) {
        do {
            try KassFlow.continuously(during: duration, pollInterval: pollInterval ?? config.pollInterval, action: block)
        } catch {
            config.logger.log("❌ continuously failed: \(error)")
            XCTFail("continuously failed: \(error)", file: file, line: line)
        }
    }

    /// Passes if at least one branch succeeds; fails only if all do not. Use
    /// when the UI may legitimately be in one of several states.
    public func compose(
        file: StaticString = #file,
        line: UInt = #line,
        _ branches: KassBranch...
    ) {
        do {
            try KassFlow.compose(branches.map { ($0.name, $0.action) })
        } catch {
            config.logger.log("❌ compose failed: \(error)")
            XCTFail("compose failed: \(error)", file: file, line: line)
        }
    }

    /// Attempts `block` up to `times`, pausing between tries, then `XCTFail`s.
    @discardableResult
    public func retry<T>(
        times: Int,
        pollInterval: TimeInterval? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () throws -> T
    ) -> T? {
        do {
            return try KassFlow.retry(times: times, pollInterval: pollInterval ?? config.pollInterval, action: block)
        } catch {
            config.logger.log("❌ retry failed after \(times) attempt(s): \(error)")
            XCTFail("retry failed after \(times) attempt(s): \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - Parameterized (data-driven) tests

    /// Runs `body` once per case, each grouped as its own activity and report
    /// step, isolating failures so every case runs (like Swift Testing's
    /// `@Test(arguments:)`, but for XCUITest). Because UI state persists between
    /// cases, reset inside `body` (e.g. `relaunch()`) when cases aren't
    /// independent.
    ///
    /// ```swift
    /// parameterized(["a@b.c", "bad-email", ""]) { email in
    ///     relaunch()
    ///     onScreen(LoginScreen.self) { $0.email.replaceText(email); $0.submit.tap() }
    /// }
    /// ```
    public func parameterized<Case>(
        _ cases: [Case],
        name: (Case) -> String = { "\($0)" },
        file: StaticString = #file,
        line: UInt = #line,
        _ body: (Case) -> Void
    ) {
        startReportingIfNeeded()
        let previousContinue = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousContinue }

        for testCase in cases {
            let label = name(testCase)
            config.logger.log("▶︎ Case: \(label)")
            config.reporter?.stepStarted("Case: \(label)")
            let failuresBefore = testRun?.failureCount ?? 0
            XCTContext.runActivity(named: "Case: \(label)") { _ in
                body(testCase)
            }
            let failed = (testRun?.failureCount ?? 0) > failuresBefore
            config.logger.log("\(failed ? "✗" : "✓") Case: \(label)")
            config.reporter?.stepFinished(status: failed ? .failed : .passed, message: failed ? "case '\(label)' failed" : nil)
        }
    }

    /// Terminates and relaunches the app under test — handy between
    /// `parameterized` cases that need a clean slate.
    @discardableResult
    public func relaunch(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        app.terminate()
        return launch(arguments: arguments, environment: environment)
    }

    /// Taps the leading navigation-bar button (typically Back).
    public func pressBack(file: StaticString = #file, line: UInt = #line) {
        flakySafely(file: file, line: line) {
            let back = self.app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists, back.isHittable else { throw KassError("no back button available") }
            back.tap()
        }
    }

    // MARK: - Accessibility audit

    /// Runs Apple's automated accessibility audit on the app and fails the test
    /// for any issue found (contrast, hit-region size, clipped/overlapping text,
    /// missing labels, …). A natural companion to strict identifiers. Pass
    /// `auditTypes` to narrow the checks (e.g. exclude the sometimes-borderline
    /// `.contrast` heuristic).
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
    public func assertNoAccessibilityIssues(
        for auditTypes: XCUIAccessibilityAuditType = .all,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        startReportingIfNeeded()
        config.reporter?.stepStarted("assertNoAccessibilityIssues")
        let failuresBefore = testRun?.failureCount ?? 0
        do {
            try app.performAccessibilityAudit(for: auditTypes)
        } catch {
            XCTFail("Accessibility audit could not run: \(error)", file: file, line: line)
        }
        let failed = (testRun?.failureCount ?? 0) > failuresBefore
        config.reporter?.stepFinished(status: failed ? .failed : .passed, message: failed ? "accessibility issues found" : nil)
    }
}

/// A named branch for `KassTestCase.compose`.
public struct KassBranch {
    let name: String
    let action: () throws -> Void
    public init(_ name: String, _ action: @escaping () throws -> Void) {
        self.name = name
        self.action = action
    }
}
