import XCTest
@testable import KassiOS

@MainActor
final class KassElementCollectionDuplicatesTests: XCTestCase {

    func test_noDuplicates_returnsEmpty() {
        XCTAssertEqual(KassElementCollection.duplicates(in: ["a", "b", "c"]), [])
    }

    func test_findsSingleDuplicate() {
        XCTAssertEqual(KassElementCollection.duplicates(in: ["a", "b", "a"]), ["a"])
    }

    func test_findsMultipleDuplicatesInFirstSeenOrder() {
        XCTAssertEqual(KassElementCollection.duplicates(in: ["a", "b", "b", "a", "c"]), ["b", "a"])
    }

    func test_repeatedDuplicateOnlyReportedOnce() {
        XCTAssertEqual(KassElementCollection.duplicates(in: ["a", "a", "a"]), ["a"])
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertEqual(KassElementCollection.duplicates(in: []), [])
    }
}
