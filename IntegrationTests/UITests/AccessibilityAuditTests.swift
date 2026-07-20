import XCTest

/// Phase 5.1: the proactive accessibility-identifier audit. The demo login screen
/// has a deliberately un-identified "Help" button; the audit should flag it.
final class AccessibilityAuditTests: KassTestCase {

    func test_audit_flagsUnidentifiedButton() {
        launch()
        _ = onScreen(LoginScreen.self) { _ in }              // wait for the login screen
        let findings = auditAccessibilityIdentifiers(severity: .warn)   // warn: don't fail the test
        XCTAssertTrue(findings.contains { $0.label == "Help" })
    }

    func test_audit_allowlistExcludesElement() {
        launch()
        _ = onScreen(LoginScreen.self) { _ in }
        let findings = auditAccessibilityIdentifiers(allowingLabels: ["Help"], severity: .warn)
        XCTAssertFalse(findings.contains { $0.label == "Help" })
    }
}
