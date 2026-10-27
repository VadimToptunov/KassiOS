import Foundation

/// Global knobs for timing, flaky-safety and logging.
///
/// Passed down from the test case into every screen and every element, so a
/// single place controls behaviour for the whole suite.
public struct KassConfig: Sendable {

    /// Total time budget for a single interaction to succeed, *including* retries.
    /// Retries share this budget — they do not each get their own timeout.
    public var timeout: TimeInterval

    /// Delay between retry attempts.
    public var pollInterval: TimeInterval

    /// When `true`, failed interactions are retried until `timeout` elapses.
    /// When `false`, each interaction is attempted exactly once.
    public var flakySafetyEnabled: Bool

    /// Sink for step and interaction logs.
    public var logger: KassLogger

    /// Optional structured reporter (e.g. `AllureReporter`). When set, steps,
    /// interactions and attachments are recorded into a machine-readable report.
    public var reporter: KassReporter?

    /// Backend that settles the app before each interaction attempt. Defaults to
    /// `NoOpSynchronizer` (pure polling); swap for an EarlGrey-backed one.
    public var synchronizer: KassSynchronizer

    /// How to react when an element built from an identifier turns out to have
    /// been matched by label (i.e. the app set no `accessibilityIdentifier`).
    /// `.warn` (default) surfaces an Xcode message without failing, `.ignore`
    /// says nothing, `.enforce` fails the interaction.
    public var accessibilityIdentifierPolicy: KassIdentifierPolicy

    /// When `true` (default), a failed interaction attaches a screenshot of the
    /// screen at the moment of failure to the report.
    public var captureScreenshotOnFailure: Bool

    /// When `true`, every `step` attaches a screenshot of the resulting screen.
    /// Off by default — handy for building a visual trail of a whole test.
    public var screenshotEachStep: Bool

    /// When `true` (default), a not-found failure with an `expectedIdentifier`
    /// walks the current screen once (bounded — see `KassTreeWalk`) and appends
    /// the closest actual identifiers/labels found on screen to the failure
    /// message: `↳ did you mean: 'a', 'b', 'c'?`. Lets a wrong-id guess (common
    /// from an AI author) self-correct. The walk only runs once an assertion has
    /// already failed, so the cost is paid at most once per failure.
    public var suggestSimilarIdentifiersOnFailure: Bool

    /// The chain every waiting DSL action flows through, outermost first.
    /// Defaults to a single ``KassRetryInterceptor`` — the built-in flaky-safety,
    /// now a reorderable link. Add your own around it: before the retry to run
    /// once, after it to run on every attempt.
    public var interceptors: [KassInterceptor]

    /// When `true`, ``KassTestCase/launch(arguments:environment:)`` sets
    /// `KASS_DISABLE_ANIMATIONS=1` in the launch environment. Faster, steadier
    /// runs — but the **app must honour it** (read the variable on startup and
    /// call `UIView.setAnimationsEnabled(false)`), since a UI test can't disable
    /// another process's animations. Defaults to `false` to preserve behaviour.
    public var disableAnimations: Bool

    /// Opt-in: when the Tier C host agent is reachable, record the simulator
    /// screen during the test and attach the video to the report if the test
    /// fails (simulator only; best-effort).
    public var recordVideoOnFailure: Bool

    /// When `true` (default), actions that set a state (`setSwitch`, `toggle`,
    /// `replaceText`, `adjustPicker`) read the element back afterwards and fail if
    /// the state didn't change, instead of returning as if they had worked. A
    /// switch whose tap never reaches the control is the classic silent no-op.
    public var verifyActionOutcome: Bool

    /// When `true` (default), an interaction on an element that exists but sits
    /// off screen swipes the screen's scroll container toward it, one swipe per
    /// attempt, within the usual budget. Works for eagerly rendered content
    /// (`ScrollView` + `VStack`); a lazy `List` row that isn't rendered yet still
    /// needs ``KassElement/scrollTo(in:direction:file:line:)``.
    public var autoScroll: Bool

    /// When `true` (default), an interaction on an element covered by the
    /// keyboard (or the input accessory bar above it) dismisses the keyboard
    /// first. See ``KassScreen/dismissKeyboard()`` for how.
    public var dismissKeyboardWhenCovering: Bool

    public init(
        timeout: TimeInterval = 15,
        pollInterval: TimeInterval = 0.5,
        flakySafetyEnabled: Bool = true,
        logger: KassLogger = ConsoleKassLogger(),
        reporter: KassReporter? = nil,
        synchronizer: KassSynchronizer = NoOpSynchronizer(),
        accessibilityIdentifierPolicy: KassIdentifierPolicy = .warn,
        captureScreenshotOnFailure: Bool = true,
        screenshotEachStep: Bool = false,
        interceptors: [KassInterceptor] = [KassRetryInterceptor()],
        disableAnimations: Bool = false,
        recordVideoOnFailure: Bool = false,
        suggestSimilarIdentifiersOnFailure: Bool = true,
        verifyActionOutcome: Bool = true,
        autoScroll: Bool = true,
        dismissKeyboardWhenCovering: Bool = true
    ) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.flakySafetyEnabled = flakySafetyEnabled
        self.logger = logger
        self.reporter = reporter
        self.synchronizer = synchronizer
        self.accessibilityIdentifierPolicy = accessibilityIdentifierPolicy
        self.captureScreenshotOnFailure = captureScreenshotOnFailure
        self.screenshotEachStep = screenshotEachStep
        self.interceptors = interceptors
        self.disableAnimations = disableAnimations
        self.recordVideoOnFailure = recordVideoOnFailure
        self.suggestSimilarIdentifiersOnFailure = suggestSimilarIdentifiersOnFailure
        self.verifyActionOutcome = verifyActionOutcome
        self.autoScroll = autoScroll
        self.dismissKeyboardWhenCovering = dismissKeyboardWhenCovering
    }

    public static let `default` = KassConfig()
}

/// What KassiOS does when an element is used without a real accessibility
/// identifier (it was matched by label instead).
public enum KassIdentifierPolicy: Sendable {
    /// Say nothing.
    case ignore
    /// Log a message and add an Xcode activity, but let the test pass.
    case warn
    /// Fail the interaction with an actionable message.
    case enforce
}

/// Outcome of a step or interaction, as understood by a `KassReporter`.
public enum KassStepStatus {
    case passed, failed
}

/// Structured reporting surface. A reporter observes the test lifecycle and the
/// tree of steps/interactions so it can emit reports (Allure, JUnit, …).
///
/// Steps nest: every `stepStarted` opens a child of the currently-open step and
/// the matching `stepFinished` closes it. Implementations should tolerate steps
/// left open at `testFinished` (a hard failure can unwind past `stepFinished`).
public protocol KassReporter: AnyObject, Sendable {
    func testStarted(name: String, fullName: String)
    func stepStarted(_ name: String)
    func stepFinished(status: KassStepStatus, message: String?)
    func attach(name: String, type: String, data: Data)
    func testFinished(status: KassStepStatus, message: String?)

    /// Metadata for the current test (severity, feature, owner, …). Optional —
    /// reporters that don't support it inherit no-op defaults.
    func addLabel(_ name: String, value: String)
    func addLink(name: String, url: String, type: String)
}

public extension KassReporter {
    func addLabel(_ name: String, value: String) {}
    func addLink(name: String, url: String, type: String) {}
}

/// Minimal logging surface. Swap the implementation to route into Allure,
/// os_log, a file, etc.
public protocol KassLogger: Sendable {
    func log(_ message: String)
}

public struct ConsoleKassLogger: KassLogger {
    public init() {}
    public func log(_ message: String) {
        print("☕️ [KassiOS] \(message)")
    }
}

extension KassConfig {
    /// Settles the app before a single interaction or assertion attempt by asking
    /// the configured `synchronizer` to wait for idle, bounded to one `pollInterval`.
    ///
    /// Every retry-wrapped wait funnels through here. The bound is `pollInterval`,
    /// **not** the full `timeout`: inside a retry loop the loop itself (bounded by
    /// `timeout`) provides the overall patience, so a never-settling tree — a
    /// persistent spinner or animation, exactly where a synchronizer is wanted —
    /// can no longer let one `waitForIdle` consume the whole budget before the
    /// action is attempted even once. This matches the per-iteration cap
    /// `assertAppears` already uses.
    ///
    /// Idle detection needs `pollInterval >= StabilizingSynchronizer.stableFor`
    /// (defaults 0.5s vs 0.1s — fine); a much smaller `pollInterval` degrades the
    /// settle to a bounded delay and lets retry carry the rest. With the default
    /// `NoOpSynchronizer`, `timeout` is ignored entirely, so this is a no-op unless
    /// a real synchronizer is configured.
    func settle() {
        synchronizer.waitForIdle(timeout: pollInterval)
    }
}
