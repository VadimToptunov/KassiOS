import XCTest
@testable import KassiOS

/// Exercises the pure settle loop via the signature-injecting init — no
/// `XCUIApplication`/simulator required, so this runs on `platform=macOS`.
final class KassStabilizingSynchronizerTests: XCTestCase {

    /// Thread-safe-enough box for a counter read/written synchronously from one
    /// thread (the settle loop never hops threads) — `@unchecked Sendable` so it
    /// can be captured by the synchronizer's `@Sendable` signature closure.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    func test_settlesWhenStable() {
        let sync = StabilizingSynchronizer(stableFor: 0.1, pollInterval: 0.02) { 1 }

        let start = Date()
        sync.waitForIdle(timeout: 5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.1, "must wait out the stable window")
        XCTAssertLessThan(elapsed, 1, "a constant signature should settle well under the timeout")
    }

    func test_waitsOutChurnThenSettles() {
        let counter = Counter()
        // Changes on the first 3 reads, then holds steady.
        let sync = StabilizingSynchronizer(stableFor: 0.1, pollInterval: 0.02) {
            if counter.value < 3 { counter.value += 1 }
            return counter.value
        }

        let start = Date()
        sync.waitForIdle(timeout: 5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1, "should settle once the churn stops, long before the timeout")
    }

    func test_respectsTimeoutWhenNeverStable() {
        let counter = Counter()
        // Always changing: never settles.
        let sync = StabilizingSynchronizer(stableFor: 0.1, pollInterval: 0.02) {
            counter.value += 1
            return counter.value
        }

        let timeout: TimeInterval = 0.3
        let start = Date()
        sync.waitForIdle(timeout: timeout)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, timeout - 0.05, "must not return early when never stable")
        XCTAssertLessThan(elapsed, timeout + 0.5, "must not wildly overshoot the timeout")
    }

    func test_stableForLargerThanTimeoutStillReturnsAtTimeout() {
        // A constant (already-stable) signature, but `stableFor` can never be
        // reached within `timeout`: the deadline check must win, so it returns
        // at ~timeout rather than hanging for the full second.
        let sync = StabilizingSynchronizer(stableFor: 1, pollInterval: 0.02) { 1 }

        let timeout: TimeInterval = 0.2
        let start = Date()
        sync.waitForIdle(timeout: timeout)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, timeout - 0.05, "must wait until the deadline")
        XCTAssertLessThan(elapsed, timeout + 0.5, "must not wait for the unreachable stable window")
    }

    func test_zeroStableForReturnsImmediately() {
        let sync = StabilizingSynchronizer(stableFor: 0, pollInterval: 0.02) { 1 }

        let start = Date()
        sync.waitForIdle(timeout: 5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.2)
    }

    func test_zeroTimeoutReturnsImmediately() {
        let sync = StabilizingSynchronizer(stableFor: 0.1, pollInterval: 0.02) { 1 }

        let start = Date()
        sync.waitForIdle(timeout: 0)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.2)
    }
}
