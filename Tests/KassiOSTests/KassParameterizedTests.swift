import XCTest
@testable import KassiOS

/// Exercises `KassTestCase.parameterized` as a real test. `setUp` is overridden
/// to skip `XCUIApplication` creation, which isn't needed here.
final class KassParameterizedTests: KassTestCase {

    override func setUp() {
        // Intentionally do not call super — avoids creating an XCUIApplication
        // in this unit-test context; the parameterized loop doesn't use it.
    }

    @MainActor
    func test_runsBodyOncePerCaseInOrder() {
        var seen: [Int] = []
        parameterized([10, 20, 30], name: { "case-\($0)" }) { value in
            seen.append(value)
        }
        XCTAssertEqual(seen, [10, 20, 30])
    }

    @MainActor
    func test_emptyCasesRunsNothing() {
        var calls = 0
        parameterized([String]()) { _ in calls += 1 }
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func test_restoresContinueAfterFailure() {
        continueAfterFailure = false
        parameterized([1]) { _ in }
        XCTAssertFalse(continueAfterFailure, "flag restored after the loop")
    }
}
