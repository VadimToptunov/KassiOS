import XCTest

/// Phase 7: typed, fluent navigation. A screen action returns the verified
/// landing screen, so a test reads as a route and fails fast if it doesn't land.
final class NavigationTests: KassTestCase {

    func test_fluentNavigation_loginToHome() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
            .navigate(to: HomeScreen.self)
            .welcome.assertVisible()
    }

    func test_navigate_failsFastWhenNotLanded() {
        config = KassConfig(timeout: 2)   // don't wait the full budget to prove the failure
        launch()
        XCTExpectFailure("navigating to a screen we never reached fails fast") {
            // Stay on login (don't sign in), then claim we're on Home.
            _ = onScreen(LoginScreen.self) { _ in }.navigate(to: HomeScreen.self)
        }
    }
}
