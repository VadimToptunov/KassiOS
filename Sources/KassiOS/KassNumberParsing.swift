import Foundation

/// Best-effort, locale-aware parsing of a number out of a string that may carry
/// currency symbols, grouping separators, or a non-`.` decimal separator.
///
/// Factored out of ``KassElement/readNumber()`` so the parsing logic itself is
/// unit-testable without a live `XCUIElement`.
enum KassNumberParsing {

    /// Tries `NumberFormatter` with `.decimal` then `.currency` styles against
    /// `locale`; if neither matches, falls back to stripping the string down to
    /// its digits, a leading minus sign, and one decimal separator (the last
    /// `.`/`,` found — earlier ones are assumed to be grouping) before handing
    /// the result to `Double.init`.
    ///
    /// Best-effort: the fallback's separator heuristic (a separator with exactly
    /// three trailing digits is treated as grouping, otherwise as a decimal
    /// point) is locale-dependent and can't disambiguate every string. For money
    /// assertions, prefer a value the app formats under the test's actual locale.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for style in [NumberFormatter.Style.decimal, .currency] {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = style
            if let number = formatter.number(from: trimmed) {
                return number.doubleValue
            }
        }

        return parseByStripping(trimmed)
    }

    /// The fallback path: keep digits, a leading minus, and normalize the last
    /// `.`/`,` in the string to the decimal point, dropping everything else
    /// (currency symbols, whitespace, and any earlier grouping separators).
    private static func parseByStripping(_ text: String) -> Double? {
        var decimalIndex = text.indices.last { text[$0] == "." || text[$0] == "," }

        // A separator followed by exactly three digits (e.g. `1,234`) is a
        // thousands group, not a decimal point — treat the value as a whole
        // number so a bare grouped integer doesn't become a ~1000× fraction.
        if let index = decimalIndex {
            let fractionDigits = text[text.index(after: index)...].prefix { $0.isNumber }
            if fractionDigits.count == 3 { decimalIndex = nil }
        }

        var cleaned = ""
        for index in text.indices {
            let character = text[index]
            if character.isNumber {
                cleaned.append(character)
            } else if character == "-" && cleaned.isEmpty {
                cleaned.append(character)
            } else if index == decimalIndex {
                cleaned.append(".")
            }
        }

        guard !cleaned.isEmpty, cleaned != "-" else { return nil }
        return Double(cleaned)
    }
}
