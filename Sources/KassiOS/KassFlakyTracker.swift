import Foundation

/// One action that passed, but not on the first try — the flaky signal the
/// interceptor chain sees for free.
public struct KassFlakyRecovery: Codable, Sendable, Equatable {
    public let action: String
    public let attempts: Int
}

/// Accumulates retry-recoveries across a test run. `KassRetryInterceptor` records
/// into it; `KassTestCase` resets it per test and drains it at teardown into a
/// machine-readable flakiness report. A test that goes green but recovered here
/// is a quarantine candidate.
///
/// Process-global (reset per test). With parallel test workers the tally is
/// per-process, which still surfaces the flaky signal.
public final class KassFlakyTracker: @unchecked Sendable {
    public static let shared = KassFlakyTracker()

    private let lock = NSLock()
    private var recoveries: [KassFlakyRecovery] = []

    func record(action: String, attempts: Int) {
        lock.lock()
        recoveries.append(KassFlakyRecovery(action: action, attempts: attempts))
        lock.unlock()
    }

    /// Clears the accumulated recoveries (call at the start of each test).
    public func reset() {
        lock.lock(); recoveries = []; lock.unlock()
    }

    /// Returns and clears the accumulated recoveries.
    public func drain() -> [KassFlakyRecovery] {
        lock.lock(); defer { recoveries = []; lock.unlock() }
        return recoveries
    }
}

/// A tiny main-actor counter the retry loop bumps per attempt.
@MainActor
final class KassAttemptCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
