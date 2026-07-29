import XCTest

/// KassiOS 1.1.0 "API ergonomics": end-to-end coverage for the additive,
/// readability-smoothing APIs (`assertTextContains`, `toggle()`,
/// `button(containing:)`) against the demo app's "API ergonomics" section
/// (see `KassDemoApp.swift`).
final class ApiErgonomicsTests: KassTestCase {

    override func setUp() {
        super.setUp()
        config = KassConfig(accessibilityIdentifierPolicy: .enforce)
    }

    private func signInToHome() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
    }

    func test_assertTextContains_passesOnASubstring() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.welcome.assertTextContains("Welcome")
        }
    }

    func test_assertTextContains_failsOnANonSubstring() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            _ = XCTExpectFailure("intentional — 'Goodbye' is not a substring of 'Welcome!'") {
                // Short timeout: this cannot recover on retry, so a full-budget
                // retry would only slow the run down before failing anyway.
                home.welcome.within(timeout: 3).assertTextContains("Goodbye")
            }
        }
    }

    func test_toggle_flipsASwitchRegardlessOfCurrentState() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.ergonomicsToggle.scrollTo(in: home.list)
            home.ergonomicsToggle.assertHasValue("0")
            home.ergonomicsToggle.toggle()
            home.ergonomicsToggle.assertHasValue("1")
            home.ergonomicsToggle.toggle()
            home.ergonomicsToggle.assertHasValue("0")
        }
    }

    func test_buttonContaining_resolvesByLabelSubstring() {
        signInToHome()
        onScreen(HomeScreen.self) { home in
            home.button(containing: "Ergonomics").scrollTo(in: home.list).assertVisible()
        }
    }
}
