import XCTest
@testable import KassiOSLintCore

/// KAS001/KAS002 firing through an intermediate base class — same file and,
/// via the batch API, across files.
final class BaseClassTracingTests: XCTestCase {

    private func source(_ lines: String...) -> String {
        lines.joined(separator: "\n")
    }

    func testTransitiveBaseClassSameFileFiresKAS001() {
        // Neither CBScreen nor HomeScreen declares onLoad, so the resolved
        // onLoad for HomeScreen is KassScreen's own empty default — fires.
        let src = source(
            "class CBScreen: KassScreen {",
            "}",
            "final class HomeScreen: CBScreen {",
            "    func doThing() {}",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Home.swift")
        XCTAssertEqual(diagnostics.filter { $0.rule == .kas001 }.map(\.message).filter { $0.contains("HomeScreen") }.count, 1)
        XCTAssertEqual(diagnostics.filter { $0.rule == .kas001 }.map(\.message).filter { $0.contains("CBScreen") }.count, 1)
    }

    func testTransitiveBaseClassInheritedOnLoadIsClean() {
        // HomeScreen doesn't override onLoad, but the resolved onLoad — the
        // nearest ancestor's — is CBScreen's non-empty one: no false positive.
        let src = source(
            "class CBScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [staticText(\"base\")] }",
            "}",
            "final class HomeScreen: CBScreen {",
            "    func doThing() {}",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Home.swift")
        XCTAssertTrue(diagnostics.isEmpty, "HomeScreen inherits a non-empty onLoad, got \(diagnostics)")
    }

    func testTransitiveBaseClassSameFileFiresKAS002() {
        let src = source(
            "class CBScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [staticText(\"base\")] }",
            "}",
            "final class HomeScreen: CBScreen {",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Home.swift")
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
    }

    func testTransitiveBaseClassSeparateFilesFiresViaBatchAPI() {
        let base = source(
            "class CBScreen: KassScreen {",
            "    override var onLoad: [KassElement] { [staticText(\"base\")] }",
            "}"
        )
        let home = source(
            "final class HomeScreen: CBScreen {",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "}"
        )
        let diagnostics = lint(sources: [
            (source: base, filePath: "CBScreen.swift"),
            (source: home, filePath: "Home.swift")
        ])
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].rule, .kas002)
        XCTAssertEqual(diagnostics[0].file, "Home.swift")
    }

    func testTransitiveBaseClassSeparateFilesSingleFileLintMissesIt() {
        // Documented single-file limitation: lint(source:filePath:) only sees
        // same-file bases, so a cross-file base isn't resolved.
        let home = source(
            "final class HomeScreen: CBScreen {",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "}"
        )
        let diagnostics = lint(source: home, filePath: "Home.swift")
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testNonScreenBaseStaysIgnoredEvenTransitively() {
        let src = source(
            "class PlainBase {",
            "}",
            "final class NotAScreen: PlainBase {",
            "    func row(_ id: String) -> KassElement { cell(id) }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "NotAScreen.swift")
        XCTAssertTrue(diagnostics.isEmpty, "PlainBase never reaches KassScreen, got \(diagnostics)")
    }
}
