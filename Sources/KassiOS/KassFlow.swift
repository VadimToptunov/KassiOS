import Foundation

/// Kaspresso-style flow primitives, as pure functions over throwing closures.
///
/// These operate on `() throws -> …` blocks: inside them you use throwing checks
/// (e.g. `KassElement.require*`) or raw `XCUIElement` assertions. The wrappers on
/// `KassTestCase` (`flakySafely`, `continuously`, `compose`, `retry`) add the
/// config defaults and turn a thrown error into an `XCTFail`.
enum KassFlow {

    /// Runs `action` repeatedly for the whole `duration`; rethrows the moment it
    /// throws. Passes only if the condition holds continuously — the inverse of
    /// flaky-safety, for catching a state that must *stay* true.
    @MainActor
    static func continuously(
        during duration: TimeInterval,
        pollInterval: TimeInterval,
        action: @MainActor () throws -> Void
    ) throws {
        let deadline = Date().addingTimeInterval(duration)
        repeat {
            try action()
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        } while Date() < deadline
    }

    /// Tries each branch in order and returns the index of the first that
    /// succeeds. Throws an aggregate error only if every branch fails. Use for
    /// "the UI may be in one of several valid states".
    @discardableResult
    @MainActor
    static func compose(_ branches: [(name: String, action: @MainActor () throws -> Void)]) throws -> Int {
        var failures: [String] = []
        for (index, branch) in branches.enumerated() {
            do {
                try branch.action()
                return index
            } catch {
                failures.append("[\(branch.name)] \(error)")
            }
        }
        throw KassError("compose: all \(branches.count) branch(es) failed:\n" + failures.joined(separator: "\n"))
    }

    /// Attempts `action` up to `times`, pausing `pollInterval` between tries.
    /// Attempts-bounded (vs. `Waiter`'s time-bounded budget).
    @discardableResult
    @MainActor
    static func retry<T>(
        times: Int,
        pollInterval: TimeInterval,
        action: @MainActor () throws -> T
    ) throws -> T {
        let attempts = max(1, times)
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try action()
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
                }
            }
        }
        throw lastError ?? KassError("retry exhausted its \(attempts) attempt(s) without a specific error")
    }
}
