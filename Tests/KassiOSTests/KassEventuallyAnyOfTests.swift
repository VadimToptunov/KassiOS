import XCTest
@testable import KassiOS

/// Exercises `KassTestCase.eventually`/`anyOf` — the 1.2.0 readability renames
/// of `flakySafely`/`compose` — as real tests. Both are pure over closures (no
/// `app` involved), so `setUp` skips `XCUIApplication` creation, mirroring
/// `KassParameterizedTests`.
final class KassEventuallyAnyOfTests: KassTestCase {

    override func setUp() {
        // Intentionally do not call super — avoids creating an XCUIApplication
        // in this unit-test context; these primitives don't use it.
    }

    @MainActor
    func test_eventually_retriesUntilItStopsThrowing() {
        var calls = 0
        let result = eventually(timeout: 1, pollInterval: 0.01) { () -> Int in
            calls += 1
            if calls < 3 { throw KassError("not yet") }
            return calls
        }
        XCTAssertEqual(result, 3)
    }

    @MainActor
    func test_anyOf_stopsAtTheFirstPassingBranch() {
        var ranThird = false
        anyOf(
            KassBranch("a") { throw KassError("nope") },
            KassBranch("b") { },
            KassBranch("c") { ranThird = true }
        )
        XCTAssertFalse(ranThird, "anyOf should stop at the first passing branch")
    }
}
