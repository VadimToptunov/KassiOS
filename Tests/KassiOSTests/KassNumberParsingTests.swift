import XCTest
@testable import KassiOS

final class KassNumberParsingTests: XCTestCase {

    // POSIX: no grouping/currency knowledge, so these exercise the strip fallback.
    private let posix = Locale(identifier: "en_US_POSIX")

    func test_parsesDollarCurrency() {
        XCTAssertEqual(KassNumberParsing.parse("$92.50", locale: posix), 92.5)
    }

    func test_parsesThousandsGrouping() {
        XCTAssertEqual(KassNumberParsing.parse("1,234.56", locale: posix), 1234.56)
    }

    /// A plain grouped integer must stay a whole number, not become 1.234 — the
    /// separator here is a thousands group (3 trailing digits), not a decimal.
    func test_parsesPlainThousandsInteger() {
        XCTAssertEqual(KassNumberParsing.parse("1,234", locale: posix), 1234)
        XCTAssertEqual(KassNumberParsing.parse("$1,234", locale: posix), 1234)
    }

    func test_parsesCommaDecimalFallback() {
        // Not a valid en_US decimal or currency string, so this exercises the
        // strip-to-digits fallback, treating the comma as the decimal point.
        XCTAssertEqual(KassNumberParsing.parse("92,50 €", locale: posix), 92.5)
    }

    func test_parsesNegativeNumber() {
        XCTAssertEqual(KassNumberParsing.parse("-5", locale: posix), -5)
    }

    func test_unparsableReturnsNil() {
        XCTAssertNil(KassNumberParsing.parse("x", locale: posix))
    }

    func test_emptyStringReturnsNil() {
        XCTAssertNil(KassNumberParsing.parse("   ", locale: posix))
    }
}
