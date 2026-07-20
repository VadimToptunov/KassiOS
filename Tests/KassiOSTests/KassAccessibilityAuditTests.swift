import XCTest
@testable import KassiOS

final class KassAccessibilityAuditTests: XCTestCase {

    func test_flagsHittableWithoutIdentifier() {
        XCTAssertTrue(KassAccessibilityAudit.isUnidentified(
            identifier: "", isHittable: true, label: "Help", allowlist: []
        ))
    }

    func test_passesElementWithIdentifier() {
        XCTAssertFalse(KassAccessibilityAudit.isUnidentified(
            identifier: "help.button", isHittable: true, label: "Help", allowlist: []
        ))
    }

    func test_ignoresNonHittable() {
        XCTAssertFalse(KassAccessibilityAudit.isUnidentified(
            identifier: "", isHittable: false, label: "Help", allowlist: []
        ))
    }

    func test_allowlistExcludesByLabel() {
        XCTAssertFalse(KassAccessibilityAudit.isUnidentified(
            identifier: "", isHittable: true, label: "Help", allowlist: ["Help"]
        ))
    }
}
