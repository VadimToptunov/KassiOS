import XCTest
@testable import KassiOSLintCore

final class ScreenLinterTests: XCTestCase {

    private func source(_ lines: String...) -> String {
        lines.joined(separator: "\n")
    }

    // MARK: - KAS001

    func testMissingOnLoadFires() {
        let src = source(
            "class LoginScreen: KassScreen {",
            "    func doThing() {}",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Login.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas001)
        XCTAssertEqual(diagnostics[0].line, 1)
        XCTAssertEqual(diagnostics[0].column, 7) // "class " is 6 chars, name starts at col 7
        XCTAssertTrue(diagnostics[0].message.contains("LoginScreen"))
        XCTAssertTrue(diagnostics[0].message.contains("KAS001"))
    }

    func testEmptyOnLoadOverrideFires() {
        let src = source(
            "class LoginScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [] }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Login.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas001)
        XCTAssertEqual(diagnostics[0].line, 1)
    }

    func testNonEmptyOnLoadIsClean() {
        let src = source(
            "class LoginScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [staticText(\"title\")] }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Login.swift")
        XCTAssertTrue(diagnostics.isEmpty, "expected no diagnostics, got \(diagnostics)")
    }

    func testComputedOnLoadReferencingElementsIsClean() {
        let src = source(
            "class LoginScreen: KassScreen {",
            "    override var onLoad: [KassElement] {",
            "        if flag { return [button(\"a\")] } else { return [] }",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Login.swift")
        XCTAssertTrue(diagnostics.isEmpty, "branchy bodies aren't traced — lenient by design, got \(diagnostics)")
    }

    func testNonScreenClassIsIgnored() {
        let src = source(
            "class NotAScreen {",
            "    func doThing() {}",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Plain.swift")
        XCTAssertTrue(diagnostics.isEmpty)
    }

    // MARK: - KAS002

    func testInterpolatedIdentifierFires() {
        let src = source(
            "class RowScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func row(_ index: Int) -> KassElement { cell(\"row_\\(index)\") }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Row.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
        XCTAssertEqual(diagnostics[0].line, 3)
        XCTAssertTrue(diagnostics[0].message.contains("KAS002"))
    }

    func testVariableIdentifierFires() {
        let src = source(
            "class RowScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Row.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
        XCTAssertEqual(diagnostics[0].line, 3)
    }

    func testStaticLiteralIdentifierIsClean() {
        let src = source(
            "class HomeScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [staticText(\"title\")] }",
            "    func login() -> KassElement { button(\"login_email\") }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Home.swift")
        XCTAssertTrue(diagnostics.isEmpty, "expected no diagnostics, got \(diagnostics)")
    }

    func testDescendantDynamicIdentifierFires() {
        let src = source(
            "class DetailScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func dyn(_ row: KassElement, _ id: String) -> KassElement { row.descendant(.button, id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Detail.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
        XCTAssertEqual(diagnostics[0].line, 3)
    }

    func testDescendantStaticIdentifierIsClean() {
        let src = source(
            "class DetailScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func dyn(_ row: KassElement) -> KassElement { row.descendant(.button, \"ok\") }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Detail.swift")
        XCTAssertTrue(diagnostics.isEmpty, "expected no diagnostics, got \(diagnostics)")
    }

    func testDynamicIdentifierOutsideScreenIsIgnored() {
        let src = source(
            "class Helper {",
            "    func x(_ id: String) -> String { cell(id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Helper.swift")
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testCollectionElementAtIsIgnored() {
        // `element(at:)` is a labelled Int-index API on a collection, not the
        // identifier builder — it must not trip KAS002.
        let src = source(
            "class ListScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func row(_ i: Int) -> KassElement { cells().element(at: i) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "List.swift")
        XCTAssertTrue(diagnostics.isEmpty, "element(at:) is not an identifier builder, got \(diagnostics)")
    }

    func testSameNamedMethodOnOtherReceiverIsIgnored() {
        // `alert.button(title)` matches an alert's label-text lookup, not a
        // screen's identifier builder — KAS002 only owns self's builders.
        let src = source(
            "class ConfirmScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func confirm(_ a: KassAlert, _ title: String) -> KassElement { a.button(title) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Confirm.swift")
        XCTAssertTrue(diagnostics.isEmpty, "a builder on a non-self receiver isn't ours, got \(diagnostics)")
    }

    func testSelfQualifiedDynamicIdentifierFires() {
        // `self.cell(id)` is still one of the screen's own builders.
        let src = source(
            "class RowScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [button(\"ok\")] }",
            "    func row(_ id: String) -> KassElement { self.cell(id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Row.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
    }
}
