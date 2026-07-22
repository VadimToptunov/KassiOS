import XCTest

/// Phase 3 Tier B: relaunch with launch-argument device settings (no host bridge).
final class DeviceTierBTests: KassTestCase {

    func test_relaunch_appliesLocale() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.welcome.assertVisible() }

        // Tier B: relaunch into a German locale. The demo app has no German
        // bundle, so the language falls back to `en`, but the region flips to
        // DE — the reliable signal that the `-AppleLocale` override took effect.
        device.relaunch { $0.locale("de_DE").language("de") }

        // Relaunch resets to login; sign in again and check the locale label.
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.locale.assertHasText("DE") }
    }

    /// Regression test for launch-argument accumulation: a `device.relaunch`
    /// into German must not leak into a later `runPseudolocalized` relaunch,
    /// which should reset to the original launch-argument base.
    func test_relaunch_thenPseudolocalized_doesNotInheritPriorLocale() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.welcome.assertVisible() }

        device.relaunch { $0.locale("de_DE").language("de") }
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.locale.assertHasText("DE") }

        runPseudolocalized {
            onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
            onScreen(HomeScreen.self) { home in
                let locale = KassElement.textOf(home.locale.resolve())
                XCTAssertFalse(locale.contains("DE"), "pseudolocalized relaunch inherited the prior German locale: \(locale)")
            }
        }
    }
}
