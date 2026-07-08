import Foundation

/// Global knobs for timing, flaky-safety and logging.
///
/// Passed down from the test case into every screen and every element, so a
/// single place controls behaviour for the whole suite.
public struct KassConfig {

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

    public init(
        timeout: TimeInterval = 15,
        pollInterval: TimeInterval = 0.5,
        flakySafetyEnabled: Bool = true,
        logger: KassLogger = ConsoleKassLogger(),
        reporter: KassReporter? = nil
    ) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.flakySafetyEnabled = flakySafetyEnabled
        self.logger = logger
        self.reporter = reporter
    }

    public static let `default` = KassConfig()
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
public protocol KassReporter: AnyObject {
    func testStarted(name: String, fullName: String)
    func stepStarted(_ name: String)
    func stepFinished(status: KassStepStatus, message: String?)
    func attach(name: String, type: String, data: Data)
    func testFinished(status: KassStepStatus, message: String?)
}

/// Minimal logging surface. Swap the implementation to route into Allure,
/// os_log, a file, etc.
public protocol KassLogger {
    func log(_ message: String)
}

public struct ConsoleKassLogger: KassLogger {
    public init() {}
    public func log(_ message: String) {
        print("☕️ [KassiOS] \(message)")
    }
}
