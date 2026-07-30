import XCTest

/// KassiOS 1.3.0 "soft assertions": `verifyAll` runs every assertion in its
/// scope to completion — instead of stopping at the first failure — so one
/// run reports *all* the mismatches on a screen.
final class VerifyAllTests: KassTestCase {

    func test_verifyAll_recordsEveryFailure_andRunsToCompletion() {
        launch()
        var reachedEnd = false
        var issuesMatched = 0

        // Both the email- and password-label checks below are deliberately
        // wrong, so this always fails twice. `XCTExpectFailure` absorbs both
        // intentional failures (via `issueMatcher`, which also counts them)
        // so the suite stays green while still proving the behavior.
        XCTExpectFailure(
            "verifyAll intentionally fails two checks — every check still runs, and both are recorded",
            failingBlock: {
                onScreen(LoginScreen.self) { screen in
                    verifyAll("deliberately wrong screen-state expectations") {
                        // Fails #1.
                        screen.email.within(timeout: 1).assertLabel("not the email label")
                        // Passes — proves the scope doesn't just run failing checks.
                        screen.signIn.assertExists()
                        // Fails #2 — proves execution reached here after failure #1
                        // instead of stopping (fail-fast would never run this).
                        screen.password.within(timeout: 1).assertLabel("not the password label")
                        reachedEnd = true
                    }
                }
            },
            issueMatcher: { _ in
                issuesMatched += 1
                return true
            }
        )

        XCTAssertEqual(issuesMatched, 2, "both intentional failures were recorded — verifyAll didn't stop at the first")
        XCTAssertTrue(reachedEnd, "verifyAll ran the whole block instead of stopping at the first failure")
    }

    func test_verifyAll_allPassing_recordsNoFailure() {
        launch()
        // If verifyAll recorded a failure here, this test itself would go red —
        // no XCTExpectFailure needed, unlike the mismatched case above.
        onScreen(LoginScreen.self) { screen in
            verifyAll("all-correct screen-state expectations") {
                screen.email.assertExists()
                screen.password.assertExists()
                screen.signIn.assertExists()
            }
        }
    }
}
