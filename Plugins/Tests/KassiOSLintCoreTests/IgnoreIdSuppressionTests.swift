import XCTest
@testable import KassiOSLintCore

/// KAS002's `// kassios:ignore-id` suppression — trivia-based, so only a real
/// comment counts, never the same text sitting inside a string literal.
final class IgnoreIdSuppressionTests: XCTestCase {

    private func source(_ lines: String...) -> String {
        lines.joined(separator: "\n")
    }

    func testIgnoreIdCommentSuppressesKAS002() {
        let src = source(
            "class RowScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func row(_ id: String) -> KassElement { cell(id) } // kassios:ignore-id",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Row.swift")
        XCTAssertTrue(diagnostics.isEmpty, "a trailing real comment should suppress KAS002, got \(diagnostics)")
    }

    func testLeadingIgnoreIdCommentIsAttributedToItsOwnLineNotTheNextToken() {
        // The comment sits alone on line 3, as *leading* trivia of the `func`
        // token on line 4. This locks down that trivia-position tracking
        // attributes it to line 3 (its own line) and not line 4 (the next
        // token's line) — a naive implementation that used the token's own
        // line for every leading-trivia piece would wrongly suppress the
        // flagged call below it.
        let src = source(
            "class RowScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    // kassios:ignore-id",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Row.swift")
        let message = "the comment is on line 3, not line 4 — it must not suppress the call below it, got \(diagnostics)"
        XCTAssertEqual(diagnostics.count, 1, message)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
        XCTAssertEqual(diagnostics[0].line, 4)
    }

    func testIgnoreIdMarkerInsideStringLiteralDoesNotSuppress() {
        // The marker text sits inside a string-literal argument on the same
        // line, not in a real comment — must still fire.
        let src = source(
            "class RowScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "    func note() -> String { \"see kassios:ignore-id in docs\" }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Row.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
    }
}
