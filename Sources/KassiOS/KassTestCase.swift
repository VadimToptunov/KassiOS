import XCTest

/// Base class for UI tests. Subclass this instead of `XCTestCase`.
///
/// Gives you `launch()`, the `onScreen(_:)` scope, and `step(_:)` — the pieces
/// that make a test read like a script instead of a pile of queries.
///
/// The class is `@MainActor` (UI tests run on the main thread), so subclasses and
/// their test methods inherit that isolation automatically — you don't annotate
/// your own tests. The `setUp()`/`tearDown()` overrides stay `nonisolated` to
/// match XCTestCase's Objective-C hooks.
@MainActor
open class KassTestCase: XCTestCase {

    public private(set) var app: XCUIApplication!

    /// `nonisolated(unsafe)` because it is assigned in the `nonisolated` `setUp()`
    /// (before any test body runs) and read on the main actor thereafter — a
    /// single-threaded lifecycle the compiler can't see. `KassConfig` is `Sendable`.
    public nonisolated(unsafe) var config: KassConfig = .default

    /// Device- and system-level helpers (permissions, keyboard, screenshots,
    /// backgrounding, orientation, deep links). Wires `device`'s back-reference
    /// so its `relaunch(_:)` shares this test case's launch-argument base
    /// instead of tracking an independent snapshot — see `KassDevice.testCase`.
    @MainActor
    public lazy var device: KassDevice = {
        var device = KassDevice(app: app, config: config)
        device.testCase = self
        return device
    }()

    private var reportingStarted = false

    /// Snapshot of `app.launchArguments` taken on the first `launch(arguments:)`
    /// call, so every later `launch`/`relaunch` composes its arguments against
    /// this stable base instead of accumulating across relaunches (e.g.
    /// `forEachLocale` followed by `runPseudolocalized` would otherwise inherit
    /// the last locale's arguments).
    private var baseLaunchArguments: [String]?

    /// `nonisolated(unsafe)` for the same reason as `config` — set from
    /// `launch()` on the main actor, read in the `nonisolated` `tearDown()`.
    nonisolated(unsafe) var recordingActive = false

    /// `XCTestCase.setUp()` is a nonisolated override point (it's declared in
    /// Objective-C with no actor annotation), so this override stays
    /// `nonisolated` to match it. XCUITest only ever calls it on the main
    /// thread, though, so `MainActor.assumeIsolated` safely hops in to touch
    /// `app`/`config` without changing when or where this runs. `self` is
    /// boxed first — see `MainActorBox` for why.
    nonisolated open override func setUp() {
        super.setUp()
        KassFlakyTracker.shared.reset()   // fresh flaky tally per test
        let this = MainActorBox(self)
        MainActor.assumeIsolated {
            this.value.continueAfterFailure = false
            this.value.app = XCUIApplication()
        }
    }

    /// Attaches a screenshot of the final state whenever the test failed, so a
    /// red run in the `.xcresult` always carries visual evidence, and closes the
    /// structured report (if any). See `setUp()` for why `assumeIsolated`
    /// (and boxing `self`) is safe here.
    nonisolated open override func tearDown() {
        let this = MainActorBox(self)
        MainActor.assumeIsolated {
            let failed = (this.value.testRun?.failureCount ?? 0) > 0
            if failed, this.value.app != nil {
                let shot = this.value.app.screenshot()
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = "Failure — \(this.value.name)"
                attachment.lifetime = .keepAlways
                this.value.add(attachment)
                this.value.config.reporter?.attach(name: "Failure", type: "image/png", data: shot.pngRepresentation)

                // Full accessibility tree — saves hours when diagnosing a red test.
                let tree = this.value.app.debugDescription
                let treeAttachment = XCTAttachment(string: tree)
                treeAttachment.name = "Accessibility tree — \(this.value.name)"
                treeAttachment.lifetime = .keepAlways
                this.value.add(treeAttachment)
                this.value.config.reporter?.attach(name: "Accessibility tree", type: "text/plain", data: Data(tree.utf8))
            }

            // Screen recording: independent of `captureScreenshotOnFailure` —
            // always stop (best-effort) to end the `recordVideo` process, but
            // only attach the bytes when the test failed.
            if this.value.recordingActive {
                let video = try? this.value.device.stopRecording()
                this.value.recordingActive = false
                if failed, let video = video {
                    let attachment = XCTAttachment(data: video, uniformTypeIdentifier: "public.mpeg-4")
                    attachment.name = "Recording — \(this.value.name)"
                    attachment.lifetime = .keepAlways
                    this.value.add(attachment)
                    this.value.config.reporter?.attach(name: "Recording", type: "video/mp4", data: video)
                }
            }

            // Flakiness report: actions that passed only after a retry. A green
            // test with entries here is a quarantine candidate.
            let recoveries = KassFlakyTracker.shared.drain()
            if !recoveries.isEmpty,
               let data = try? JSONEncoder().encode(recoveries) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "Flaky recoveries — \(this.value.name)"
                attachment.lifetime = .keepAlways
                this.value.add(attachment)
                this.value.config.reporter?.attach(name: "Flaky recoveries", type: "application/json", data: data)
                this.value.config.logger.log("⚠️ \(recoveries.count) action(s) recovered on retry — potential flake")
            }

            if this.value.reportingStarted {
                this.value.config.reporter?.testFinished(
                    status: failed ? .failed : .passed,
                    message: failed ? "Test failed — see attached screenshot" : nil
                )
            }
        }
        super.tearDown()
    }

    /// Opens the structured report lazily, on first use, so a `config` (and its
    /// `reporter`) assigned in a subclass's `setUp` is already in place.
    @MainActor
    func startReportingIfNeeded() {
        guard !reportingStarted else { return }
        reportingStarted = true
        let (display, full) = Self.parseTestName(name)
        config.reporter?.testStarted(name: display, fullName: full)
    }

    /// Splits XCTest's `-[Class method]` name into (method, "Class.method").
    /// Pure string logic — `nonisolated` so it can be called (and unit-tested)
    /// off the main actor without an artificial isolation hop.
    nonisolated static func parseTestName(_ raw: String) -> (name: String, fullName: String) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-[]"))
        let parts = trimmed.split(separator: " ")
        guard parts.count == 2 else { return (trimmed, trimmed) }
        let cls = parts[0].split(separator: ".").last.map(String.init) ?? String(parts[0])
        let method = String(parts[1])
        return (method, "\(cls).\(method)")
    }

    /// Launches the app under test.
    @discardableResult
    @MainActor
    public func launch(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        startReportingIfNeeded()
        if baseLaunchArguments == nil { baseLaunchArguments = app.launchArguments }
        app.launchArguments = (baseLaunchArguments ?? []) + arguments
        for (key, value) in environment { app.launchEnvironment[key] = value }
        if config.disableAnimations { app.launchEnvironment["KASS_DISABLE_ANIMATIONS"] = "1" }
        app.launch()
        // Best-effort: no agent (or a real device) means a silent no-op, never
        // a hang or a hard failure. Guarded so `relaunch()` (which calls back
        // into `launch()`) doesn't start a second recording on top of one
        // already running.
        if config.recordVideoOnFailure, !recordingActive {
            if (try? device.startRecording()) != nil { recordingActive = true }
        }
        return app
    }

    /// Launches the app with a deep link passed as a launch argument
    /// (`-deeplink <url>`) for the app to read and route on startup. This is the
    /// reliable, in-process convention — prefer it over `device.open(url:)`,
    /// which drives Safari and is best-effort.
    @discardableResult
    @MainActor
    public func launch(
        deeplink url: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        launch(arguments: ["-deeplink", url] + arguments, environment: environment)
    }

    /// Launches with network stubs passed as launch environment
    /// (`KASS_STUB_<name>=<value>`). The app reads these on startup and serves
    /// local fixtures instead of hitting the network — the reliable XCUITest
    /// pattern, since out-of-process tests can't intercept traffic in-process.
    @discardableResult
    @MainActor
    public func launch(
        stubs: [String: String],
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        var merged = environment
        for (key, value) in stubs { merged["KASS_STUB_\(key)"] = value }
        return launch(arguments: arguments, environment: merged)
    }

    /// Enter a screen scope. Waits for the screen's `onLoad` elements to exist
    /// (proof the screen loaded — fails fast if they don't), then runs `block`.
    /// Existence (not strict visibility) is used so non-hittable proof elements
    /// like labels don't cause false negatives.
    @discardableResult
    @MainActor
    public func onScreen<S: KassScreen>(
        _ type: S.Type,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: @MainActor (S) -> Void
    ) -> S {
        startReportingIfNeeded()
        let screen = S(app: app, config: config)
        XCTContext.runActivity(named: "On \(String(describing: type))") { _ in
            for element in screen.onLoad {
                element.assertExists(file: file, line: line)
            }
            block(screen)
        }
        return screen
    }

    /// A labelled, timed step. Groups its actions in Xcode's test report
    /// (via `XCTContext`), records it in the structured report, and logs
    /// start/finish to the console.
    @MainActor
    public func step(_ name: String, _ block: @MainActor () -> Void) {
        startReportingIfNeeded()
        config.logger.log("▶︎ \(name)")
        config.reporter?.stepStarted(name)
        let start = Date()
        XCTContext.runActivity(named: name) { _ in
            block()
        }
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        config.logger.log("✓ \(name) (\(elapsed))")
        if config.screenshotEachStep, app != nil {
            device.screenshot("step: \(name)")
        }
        config.reporter?.stepFinished(status: .passed, message: nil)
    }

    /// Runs a reusable `KassScenario` against this test case, grouped in the
    /// report under the scenario's name.
    @MainActor
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
    @MainActor
    public func flakySafely<T>(
        timeout: TimeInterval? = nil,
        pollInterval: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: @MainActor () throws -> T
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
    @MainActor
    public func continuously(
        during duration: TimeInterval,
        pollInterval: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: @MainActor () throws -> Void
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
    @MainActor
    public func compose(
        file: StaticString = #filePath,
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
    @MainActor
    public func retry<T>(
        times: Int,
        pollInterval: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: @MainActor () throws -> T
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
    @MainActor
    public func parameterized<Case>(
        _ cases: [Case],
        name: @MainActor (Case) -> String = { "\($0)" },
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @MainActor (Case) -> Void
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
    @MainActor
    public func relaunch(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        app.terminate()
        return launch(arguments: arguments, environment: environment)
    }

    /// Taps the leading navigation-bar button (typically Back).
    @MainActor
    public func pressBack(file: StaticString = #filePath, line: UInt = #line) {
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
    @MainActor
    public func assertNoAccessibilityIssues(
        for auditTypes: XCUIAccessibilityAuditType = .all,
        file: StaticString = #filePath,
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
    let action: @MainActor () throws -> Void
    public init(_ name: String, _ action: @escaping @MainActor () throws -> Void) {
        self.name = name
        self.action = action
    }
}
