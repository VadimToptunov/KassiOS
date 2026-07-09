import XCTest
@testable import KassiOS

/// `setUp` is overridden to skip `XCUIApplication` creation, which the run
/// builder doesn't need.
final class KassRunTests: KassTestCase {

    override func setUp() { /* no super — no app needed here */ }

    func test_runsSectionsInOrder() {
        var log: [String] = []
        before { log.append("before") }
            .after { log.append("after") }
            .run { log.append("steps") }
        XCTAssertEqual(log, ["before", "steps", "after"])
    }

    func test_runWithoutSections() {
        var ran = false
        run { ran = true }
        XCTAssertTrue(ran)
    }

    func test_afterRunsEvenWithoutBefore() {
        var log: [String] = []
        after { log.append("after") }
            .run { log.append("steps") }
        XCTAssertEqual(log, ["steps", "after"])
    }
}
