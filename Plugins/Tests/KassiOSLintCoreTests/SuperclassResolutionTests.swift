import XCTest
@testable import KassiOSLintCore

/// Only the inheritance clause's *first* entry (the superclass, per Swift's
/// superclass-first rule) drives KAS001/KAS002/KAS003 classification —
/// trailing protocol conformances never do, even ones that happen to share a
/// well-known root's literal name.
final class SuperclassResolutionTests: XCTestCase {

    private func source(_ lines: String...) -> String {
        lines.joined(separator: "\n")
    }

    func testTrailingProtocolConformanceIsNotMisreadAsSuperclass() {
        // LoginTests's superclass is CBTestCase (first in the list); the
        // trailing `KassRobot` is just a protocol conformance — it must not
        // suppress KAS003 as if this were a robot method.
        let src = source(
            "protocol KassRobot {}",
            "class CBTestCase: KassTestCase {}",
            "final class LoginTests: CBTestCase, KassRobot {",
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
        XCTAssertEqual(kas003.count, 1, "the trailing KassRobot conformance must not be read as the superclass, got \(diagnostics)")
    }

    func testProtocolConformanceListedAfterSuperclassStillClassifies() {
        let src = source(
            "protocol SomeProtocol {}",
            "class CBTestCase: KassTestCase {}",
            "final class X: CBTestCase, SomeProtocol {",
            "    func testFoo() {",
            "        row1.tap()",
            "        row2.tap()",
            "        row3.tap()",
            "        row4.tap()",
            "        row5.tap()",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "X.swift")
        XCTAssertEqual(diagnostics.filter { $0.rule == .kas003 }.count, 1)
    }

    func testProtocolOnlyConformanceShadowingARootNameIsNotClassified() {
        // Y's only inheritance-clause entry is a *protocol* — one declared
        // right here with the literal name of a well-known root — not an
        // actual superclass. It must not be classified as a KassTestCase
        // subclass just because the name matches.
        let src = source(
            "protocol KassTestCase {}",
            "final class Y: KassTestCase {",
            "    func testFoo() {",
            "        row1.tap()",
            "        row2.tap()",
            "        row3.tap()",
            "        row4.tap()",
            "        row5.tap()",
            "    }",
            "}"
        )
        let diagnostics = lint(source: src, filePath: "Y.swift")
        XCTAssertTrue(
            diagnostics.filter { $0.rule == .kas003 }.isEmpty,
            "Y's only inheritance entry is a local protocol shadowing KassTestCase, not the real class, got \(diagnostics)"
        )
    }
}
