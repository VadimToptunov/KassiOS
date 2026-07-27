import XCTest
@testable import KassiOS

final class KassConfigTests: XCTestCase {

    func test_defaultIdentifierPolicyIsWarn() {
        // 0.23.0: the default flipped from `.ignore` to `.warn` — a label-fallback
        // match should no longer be silent by default.
        XCTAssertEqual(KassConfig().accessibilityIdentifierPolicy, .warn)
        XCTAssertEqual(KassConfig.default.accessibilityIdentifierPolicy, .warn)
    }
}
