import XCTest
@testable import KassiOS

/// `setUp` is overridden to skip `XCUIApplication` creation, which the run
/// builder doesn't need. `after` is registered as a teardown block, so it runs
/// before `tearDown()` — verified there.
final class KassRunTests: KassTestCase {

    private var order: [String] = []
    private var checkAfter = false

    // `nonisolated` to match `KassTestCase.setUp()`/`tearDown()`; `assumeIsolated`
    // is safe since XCTest only ever calls these on the main thread. `self` is
    // boxed first — see `MainActorBox` for why.
    nonisolated override func setUp() {
        let this = MainActorBox(self)
        MainActor.assumeIsolated { this.value.order = []; this.value.checkAfter = false }
    }

    nonisolated override func tearDown() {
        let this = MainActorBox(self)
        MainActor.assumeIsolated {
            if this.value.checkAfter {
                XCTAssertEqual(this.value.order, ["before", "steps", "after"], "after ran as a teardown block")
            }
        }
        super.tearDown()
    }

    @MainActor
    func test_beforeRunsBeforeSteps() {
        run {
            self.order.append("steps")
        }
        XCTAssertEqual(order, ["steps"])
    }

    @MainActor
    func test_afterRunsAtTeardown() {
        checkAfter = true
        before { self.order.append("before") }
            .after { self.order.append("after") }
            .run { self.order.append("steps") }
        // `after` has not run yet — it's a teardown block.
        XCTAssertEqual(order, ["before", "steps"])
    }
}
