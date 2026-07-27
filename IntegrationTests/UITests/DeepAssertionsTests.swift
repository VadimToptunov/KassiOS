import XCTest

/// KassiOS 0.24.0 "deep assertions": end-to-end coverage for the numeric,
/// dedup/per-row, and transient checks against the demo app's "Deep
/// assertions" section (see `KassDemoApp.swift`).
///
/// These are driven directly by a buggy-matrix experiment against ChaosBank,
/// where presence-only assertions missed `roundingDrift`, `paginationDup`,
/// `filterLeaksCategory`, and `successToastMissing`.
final class DeepAssertionsTests: KassTestCase {

    override func setUp() {
        super.setUp()
        config = KassConfig(accessibilityIdentifierPolicy: .enforce)
    }

    private func signInToHome() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
    }

    // MARK: - Numeric closeness

    func test_assertValue_closeTo_matchesFormattedAmount() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.amount.scrollTo(in: home.list)
            // "$92.50" is not a string round-trippable exact match target —
            // the point of `assertValue(closeTo:)` is to check the number.
            home.amount.assertValue(closeTo: 92.5, tolerance: 0.01)
            XCTAssertEqual(home.amount.readNumber(), 92.5)
        }
    }

    // MARK: - Collection: duplicates

    func test_assertNoDuplicates_passesOnUniqueRows() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.dedupRows.element(at: 0).scrollTo(in: home.list)
            home.dedupRows.assertNoDuplicates()
        }
    }

    func test_assertNoDuplicates_catchesADuplicatedRow() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.duplicateToggle.scrollTo(in: home.list)
            home.duplicateToggle.tap()
            _ = XCTExpectFailure("the toggle intentionally duplicates a row's label") {
                // Short timeout: the duplicate persists, so a retry-based
                // assert would otherwise burn the full budget before failing.
                home.dedupRows.within(timeout: 3).assertNoDuplicates()
            }
        }
    }

    // MARK: - Collection: per-row check

    func test_assertEach_passesWhenEveryRowMatches() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.dedupRows.element(at: 0).scrollTo(in: home.list)
            home.dedupRows.assertEach("starts with 'Row'") { row in
                guard row.readLabel().hasPrefix("Row") else {
                    throw KassError("expected a label starting with 'Row'")
                }
            }
        }
    }

    // MARK: - Transient appearance

    func test_assertAppears_catchesTheToastBeforeItDismisses() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.toastButton.scrollTo(in: home.list)
            home.toastButton.tap()
            // The toast is only up briefly — `assertAppears` fast-polls
            // existence and passes on the first sighting, unlike
            // `assertVisible`, which would burn the whole flaky-safety budget.
            home.toast.assertAppears(within: 5)
        }
    }
}
