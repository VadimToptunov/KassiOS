import XCTest
@testable import KassiOS

/// Exercises `KassTestCase.verifyAll` as a real test. `setUp` is overridden to
/// skip `XCUIApplication` creation, which isn't needed here — mirrors
/// `KassParameterizedTests`.
final class KassVerifyAllTests: KassTestCase {

    override func setUp() {
        // Intentionally do not call super — avoids creating an XCUIApplication
        // in this unit-test context; verifyAll's scope logic doesn't use it.
    }

    @MainActor
    func test_runsBlockToCompletion() {
        var seen: [Int] = []
        verifyAll("all steps run") {
            seen.append(1)
            seen.append(2)
            seen.append(3)
        }
        XCTAssertEqual(seen, [1, 2, 3])
    }

    @MainActor
    func test_restoresContinueAfterFailure() {
        continueAfterFailure = false
        verifyAll("noop") { }
        XCTAssertFalse(continueAfterFailure, "flag restored after the scope")
    }

    @MainActor
    func test_flipsContinueAfterFailureDuringScope() {
        continueAfterFailure = false
        var observed = false
        verifyAll("observe scope") {
            observed = continueAfterFailure
        }
        XCTAssertTrue(observed, "continue-after-failure is enabled inside the scope")
    }
}
