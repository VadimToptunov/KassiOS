import XCTest
@testable import KassiOS

/// `setUp` is overridden to skip `XCUIApplication` creation, which the run
/// builder doesn't need. `after` is registered as a teardown block, so it runs
/// before `tearDown()` — verified there.
final class KassRunTests: KassTestCase {

    private var order: [String] = []
    private var checkAfter = false

    override func setUp() { order = []; checkAfter = false }

    override func tearDown() {
        if checkAfter {
            XCTAssertEqual(order, ["before", "steps", "after"], "after ran as a teardown block")
        }
        super.tearDown()
    }

    func test_beforeRunsBeforeSteps() {
        run {
            self.order.append("steps")
        }
        XCTAssertEqual(order, ["steps"])
    }

    func test_afterRunsAtTeardown() {
        checkAfter = true
        before { self.order.append("before") }
            .after { self.order.append("after") }
            .run { self.order.append("steps") }
        // `after` has not run yet — it's a teardown block.
        XCTAssertEqual(order, ["before", "steps"])
    }
}
