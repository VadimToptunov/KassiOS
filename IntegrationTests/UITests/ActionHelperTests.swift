import XCTest

/// Phase 2 action helpers: the gentle `softScrollTo` and `config.disableAnimations`.
final class ActionHelperTests: KassTestCase {

    override func setUp() {
        super.setUp()
        config = KassConfig(accessibilityIdentifierPolicy: .enforce)
    }

    /// A short, deterministic drag reaches an off-screen row without overshooting.
    func test_softScrollTo_revealsOffscreenRow() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.item(11).softScrollTo(in: home.list)
            home.item(11).assertVisible()
        }
    }

    /// With animations disabled the whole login → home flow still completes — the
    /// launch flag is honoured and nothing breaks.
    func test_disableAnimations_flowStillCompletes() {
        config = KassConfig(accessibilityIdentifierPolicy: .enforce, disableAnimations: true)
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.welcome.assertVisible() }
    }
}
