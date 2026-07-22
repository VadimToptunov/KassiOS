import XCTest
@testable import KassiOS

final class KassLaunchOptionsTests: XCTestCase {

    func test_doubleLengthStrings_addsArgument() {
        XCTAssertEqual(KassLaunchOptions().doubleLengthStrings().arguments, ["-NSDoubleLocalizedStrings", "YES"])
    }

    func test_showNonLocalizedStrings_addsArgument() {
        XCTAssertEqual(
            KassLaunchOptions().showNonLocalizedStrings().arguments,
            ["-NSShowNonLocalizedStrings", "YES"]
        )
    }

    func test_rightToLeft_addsArguments() {
        XCTAssertEqual(
            KassLaunchOptions().rightToLeft().arguments,
            ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
        )
    }

    func test_disabledVariants_addNothing() {
        XCTAssertTrue(KassLaunchOptions().doubleLengthStrings(false).arguments.isEmpty)
        XCTAssertTrue(KassLaunchOptions().showNonLocalizedStrings(false).arguments.isEmpty)
        XCTAssertTrue(KassLaunchOptions().rightToLeft(false).arguments.isEmpty)
    }

    func test_chaining_composesInOrder() {
        let options = KassLaunchOptions().language("de").doubleLengthStrings().rightToLeft()
        XCTAssertEqual(options.arguments, [
            "-AppleLanguages", "(de)",
            "-NSDoubleLocalizedStrings", "YES",
            "-AppleTextDirection", "YES",
            "-NSForceRightToLeftWritingDirection", "YES"
        ])
    }

    func test_existingOptions_stillProduceDocumentedArguments() {
        XCTAssertEqual(KassLaunchOptions().locale("de_DE").arguments, ["-AppleLocale", "de_DE"])
        XCTAssertEqual(KassLaunchOptions().language("de").arguments, ["-AppleLanguages", "(de)"])
        XCTAssertEqual(
            KassLaunchOptions().dynamicType("UICTContentSizeCategoryAccessibilityXL").arguments,
            ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        )
    }
}
