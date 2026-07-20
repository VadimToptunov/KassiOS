import XCTest

/// Phase 6: the machine-readable failure artifact. Deliberately fails (inside
/// `XCTExpectFailure`) so the diagnostic-building + attach path runs against a
/// real element, without turning the suite red.
final class DiagnosticTests: KassTestCase {

    func test_diagnosticArtifact_emittedOnFailure() {
        launch()
        _ = onScreen(LoginScreen.self) { _ in }
        XCTExpectFailure("intentional — exercises the KassiOS diagnostic artifact") {
            // `email` exists, so asserting it's absent fails fast (1s), which
            // triggers makeDiagnostic + attachDiagnostic.
            onScreen(LoginScreen.self) { $0.email.within(timeout: 1).assertNotExists() }
        }
    }
}
