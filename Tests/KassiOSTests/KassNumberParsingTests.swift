import XCTest
@testable import KassiOS

final class KassNumberParsingTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US_POSIX")

    func test_parsesDollarCurrency() {
        XCTAssertEqual(KassNumberParsing.parse("$92.50", locale: enUS), 92.5)
    }

    func test_parsesThousandsGrouping() {
        XCTAssertEqual(KassNumberParsing.parse("1,234.56", locale: enUS), 1234.56)
    }

    func test_parsesCommaDecimalFallback() {
        // Not a valid en_US decimal or currency string, so this exercises the
        // strip-to-digits fallback, treating the comma as the decimal point.
        XCTAssertEqual(KassNumberParsing.parse("92,50 €", locale: enUS), 92.5)
    }

    func test_parsesNegativeNumber() {
        XCTAssertEqual(KassNumberParsing.parse("-5", locale: enUS), -5)
    }

    func test_unparsableReturnsNil() {
        XCTAssertNil(KassNumberParsing.parse("x", locale: enUS))
    }

    func test_emptyStringReturnsNil() {
        XCTAssertNil(KassNumberParsing.parse("   ", locale: enUS))
    }
}
