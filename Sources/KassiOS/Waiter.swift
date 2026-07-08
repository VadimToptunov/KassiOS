import Foundation

/// A human-readable failure reason surfaced through the logs and XCTFail.
public struct KassError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The heart of flaky-safety.
///
/// Runs `action` repeatedly until it returns without throwing or the shared
/// deadline passes. Because every attempt draws from one deadline, retries
/// never compound into runaway timeouts.
enum Waiter {

    @discardableResult
    static func retry<T>(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        enabled: Bool,
        action: () throws -> T
    ) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        repeat {
            do {
                return try action()
            } catch {
                lastError = error
                // Flaky-safety off, or budget spent: give up after this attempt.
                if !enabled || Date() >= deadline { break }
                // Yield instead of hard-sleeping so the app under test keeps
                // making progress (animations settle, network resolves, etc.).
                RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
            }
        } while Date() < deadline

        throw lastError ?? KassError("Waiter exhausted its budget without a specific error")
    }
}
