import XCTest
@testable import KassiOS

@MainActor
final class KassFlowTests: XCTestCase {

    // MARK: continuously

    func test_continuously_passesWhileStable() throws {
        var calls = 0
        try KassFlow.continuously(during: 0.2, pollInterval: 0.05) { calls += 1 }
        XCTAssertGreaterThan(calls, 1)
    }

    func test_continuously_failsWhenItBecomesFalse() {
        var calls = 0
        XCTAssertThrowsError(
            try KassFlow.continuously(during: 1, pollInterval: 0.05) {
                calls += 1
                if calls >= 3 { throw KassError("state changed") }
            }
        )
    }

    // MARK: compose

    func test_compose_returnsFirstPassingBranch() throws {
        let index = try KassFlow.compose([
            ("a", { throw KassError("nope") }),
            ("b", { }),
            ("c", { XCTFail("should not run"); })
        ])
        XCTAssertEqual(index, 1)
    }

    func test_compose_throwsWhenAllFail() {
        XCTAssertThrowsError(
            try KassFlow.compose([
                ("a", { throw KassError("x") }),
                ("b", { throw KassError("y") })
            ])
        ) { error in
            XCTAssertTrue("\(error)".contains("all 2 branch"))
        }
    }

    // MARK: retry

    func test_retry_succeedsWithinAttempts() throws {
        var calls = 0
        let result = try KassFlow.retry(times: 5, pollInterval: 0.01) { () -> String in
            calls += 1
            if calls < 3 { throw KassError("not yet") }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 3)
    }

    func test_retry_throwsAfterExhausting() {
        var calls = 0
        XCTAssertThrowsError(
            try KassFlow.retry(times: 3, pollInterval: 0.01) { calls += 1; throw KassError("always") }
        )
        XCTAssertEqual(calls, 3)
    }
}
