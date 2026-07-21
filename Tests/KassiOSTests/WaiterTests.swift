import XCTest
@testable import KassiOS

@MainActor
final class WaiterTests: XCTestCase {

    func test_succeedsOnFirstTry() throws {
        var calls = 0
        let result = try Waiter.retry(timeout: 1, pollInterval: 0.05, enabled: true) { () -> Int in
            calls += 1
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(calls, 1)
    }

    func test_recoversAfterTransientFailures() throws {
        var calls = 0
        let result = try Waiter.retry(timeout: 2, pollInterval: 0.05, enabled: true) { () -> String in
            calls += 1
            if calls < 3 { throw KassError("not ready") }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertGreaterThanOrEqual(calls, 3)
    }

    func test_disabled_triesExactlyOnce() {
        var calls = 0
        XCTAssertThrowsError(
            try Waiter.retry(timeout: 5, pollInterval: 0.05, enabled: false) {
                calls += 1
                throw KassError("always fails")
            }
        )
        XCTAssertEqual(calls, 1)
    }

    func test_givesUpAfterTimeout() {
        var calls = 0
        // A roomy budget vs the poll interval so ≥2 attempts happen even on a
        // heavily-loaded CI runner (a tight 0.3s budget flaked when scheduling
        // ate the window before the second attempt). This still runs the full
        // budget since the action always fails — kept short but not knife-edge.
        XCTAssertThrowsError(
            try Waiter.retry(timeout: 1.5, pollInterval: 0.05, enabled: true) {
                calls += 1
                throw KassError("always fails")
            }
        )
        XCTAssertGreaterThan(calls, 1) // retried at least once before giving up
    }
}
