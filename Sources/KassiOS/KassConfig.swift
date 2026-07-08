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

    public init(
        timeout: TimeInterval = 15,
        pollInterval: TimeInterval = 0.5,
        flakySafetyEnabled: Bool = true,
        logger: KassLogger = ConsoleKassLogger()
    ) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.flakySafetyEnabled = flakySafetyEnabled
        self.logger = logger
    }

    public static let `default` = KassConfig()
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
