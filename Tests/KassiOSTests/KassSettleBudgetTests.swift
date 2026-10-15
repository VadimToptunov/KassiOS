import XCTest
@testable import KassiOS

/// Records the timeout it was asked to settle with, to prove `settle()` bounds the
/// idle-wait to `pollInterval` rather than the full `timeout`.
private final class RecordingSynchronizer: KassSynchronizer, @unchecked Sendable {
    var lastTimeout: TimeInterval?
    func waitForIdle(timeout: TimeInterval) { lastTimeout = timeout }
}

/// Characterizes `StabilizingSynchronizer.waitForIdle` timing — the reason the
/// retry-wrapped call sites now funnel through `KassConfig.settle()`. Passing the
/// full `timeout` there means a never-settling tree blocks for the whole budget,
/// which is the behaviour the follow-up budget-bounding fix will address at the
/// call sites (not in the synchronizer), so these tests stay valid across it.
final class KassSettleBudgetTests: XCTestCase {

    func test_constantSignature_settlesWellBeforeTimeout() {
        let sync = StabilizingSynchronizer(stableFor: 0.05, pollInterval: 0.01) { 42 }
        let start = Date()
        sync.waitForIdle(timeout: 2)
        XCTAssertLessThan(
            Date().timeIntervalSince(start), 0.5,
            "a stable tree should settle on stableFor, not run to the timeout"
        )
    }

    func test_everChangingSignature_runsToTimeout() {
        // A signature that differs on every poll never reaches `stableFor`, so the
        // wait runs to its timeout — the cost a full-budget settle imposes on every
        // retry attempt.
        let sync = StabilizingSynchronizer(stableFor: 0.05, pollInterval: 0.01) {
            Int(Date().timeIntervalSince1970 * 1_000_000)
        }
        let start = Date()
        sync.waitForIdle(timeout: 0.3)
        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(start), 0.25,
            "a never-settling tree should consume ~the whole timeout"
        )
    }

    func test_settle_boundsToPollIntervalNotTimeout() {
        let sync = RecordingSynchronizer()
        let config = KassConfig(timeout: 30, pollInterval: 0.25, synchronizer: sync)
        config.settle()
        XCTAssertEqual(
            sync.lastTimeout, 0.25,
            "settle() must bound the idle-wait to pollInterval, not the full timeout"
        )
    }
}
