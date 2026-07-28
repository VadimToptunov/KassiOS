import XCTest
@testable import KassiOSLintCore

/// KAS003 — a `KassTestCase` test method drowning in inline interactions.
final class KAS003Tests: XCTestCase {

    private func source(_ lines: String...) -> String {
        lines.joined(separator: "\n")
    }

    func testFatTestMethodFiresKAS003() {
        let src = source(
            "class CBTestCase: KassTestCase {}",
            "final class LoginTests: CBTestCase {",
            "    func testSignIn() {",
            "        row1.tap()",
            "        row2.tap()",
            "        row3.tap()",
            "        row4.tap()",
            "        row5.tap()",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "LoginTests.swift")
        let kas003 = diagnostics.filter { $0.rule == .kas003 }
        XCTAssertEqual(kas003.count, 1)
        XCTAssertTrue(kas003[0].message.contains("testSignIn"))
        XCTAssertTrue(kas003[0].message.contains("5 inline interactions"))
    }

    func testSmallTestMethodDoesNotFireKAS003() {
        let src = source(
            "class CBTestCase: KassTestCase {}",
            "final class LoginTests: CBTestCase {",
            "    func testSignIn() {",
            "        row1.tap()",
            "        row2.tap()",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "LoginTests.swift")
        XCTAssertTrue(diagnostics.filter { $0.rule == .kas003 }.isEmpty)
    }

    func testInteractionsInsideKassRobotSubclassDoNotFireKAS003() {
        let src = source(
            "class CBRobot: KassRobot {}",
            "final class LoginRobot: CBRobot {",
            "    func testSignIn() {",
            "        row1.tap()",
            "        row2.tap()",
            "        row3.tap()",
            "        row4.tap()",
            "        row5.tap()",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "LoginRobot.swift")
        XCTAssertTrue(diagnostics.filter { $0.rule == .kas003 }.isEmpty)
    }

    func testFatMethodInPlainClassDoesNotFireKAS003() {
        let src = source(
            "final class Helper {",
            "    func testSignIn() {",
            "        row1.tap()",
            "        row2.tap()",
            "        row3.tap()",
            "        row4.tap()",
            "        row5.tap()",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Helper.swift")
        XCTAssertTrue(diagnostics.filter { $0.rule == .kas003 }.isEmpty)
    }
}
