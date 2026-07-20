import Foundation

/// One action that passed, but not on the first try — the flaky signal the
/// interceptor chain sees for free. Carries the element identity so a test with
/// several flaky taps produces distinguishable entries.
public struct KassFlakyRecovery: Codable, Sendable, Equatable {
    public let action: String
    public let element: String
    public let attempts: Int

    public init(action: String, element: String, attempts: Int) {
        self.action = action
        self.element = element
        self.attempts = attempts
    }
}

/// Accumulates retry-recoveries across a test run. `KassRetryInterceptor` records
/// into it; `KassTestCase` resets it per test and drains it at teardown into a
/// machine-readable flakiness report. A test that goes green but recovered here
/// is a quarantine candidate.
///
/// Process-global (reset per test). With parallel test workers the tally is
/// per-process, which still surfaces the flaky signal. Attribution relies on the
/// standard lifecycle order — `super.setUp()` first, `super.tearDown()` **last**;
/// a subclass that runs DSL interactions after `super.tearDown()` will lose those
/// recoveries.
public final class KassFlakyTracker: @unchecked Sendable {
    public static let shared = KassFlakyTracker()

    private let lock = NSLock()
    private var recoveries: [KassFlakyRecovery] = []

    /// Records an action that passed only after a retry. Public so a custom retry
    /// interceptor (not just the built-in ``KassRetryInterceptor``) can participate.
    public func record(action: String, element: String, attempts: Int) {
        lock.lock()
        recoveries.append(KassFlakyRecovery(action: action, element: element, attempts: attempts))
        lock.unlock()
    }

    /// Clears the accumulated recoveries (call at the start of each test).
    public func reset() {
        lock.lock(); recoveries = []; lock.unlock()
    }

    /// Returns and clears the accumulated recoveries.
    public func drain() -> [KassFlakyRecovery] {
        lock.lock(); defer { lock.unlock() }
        let snapshot = recoveries
        recoveries = []
        return snapshot
    }
}

/// A tiny main-actor counter the retry loop bumps per attempt.
@MainActor
final class KassAttemptCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
