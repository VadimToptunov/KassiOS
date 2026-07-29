import XCTest

/// KassiOS 1.2.0 "clearer flow-primitive names": end-to-end coverage for the
/// renamed-for-readability APIs — `eventually` (was `flakySafely`), `anyOf`
/// (was `compose`), and `device.pressBack()` (moved off `KassTestCase`). The
/// old names still compile (deprecated forwarders); this file only exercises
/// the new ones.
final class ClearerNamesTests: KassTestCase {

    func test_eventually_retriesAMultiStepConditionUntilTheStubbedFetchLands() {
        launch(networkStubs: [.json(urlContains: "/user", body: #"{"name":"Alex"}"#)])
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.fetchButton.tap()
            // A genuine multi-step condition (content populated *and* the button
            // still there) — a single flaky-safe assertion can't express "and",
            // which is exactly why `eventually` exists.
            eventually {
                guard home.fetchResult.readLabel().contains("Alex") else {
                    throw KassError("fetch result not populated yet")
                }
                try home.fetchButton.requireVisible()
            }
            home.fetchResult.assertTextContains("Alex")
        }
    }

    func test_anyOf_passesWhenTheBranchMatchingTheLandedScreenSucceeds() {
        launch()
        onScreen(LoginScreen.self) { login in
            login.email.typeText("a@b.c")
            login.signIn.tap()
        }
        let home = HomeScreen(app: app, config: config)
        let login = LoginScreen(app: app, config: config)
        // Valid credentials land on Home, but the shape of the check is the
        // point: the UI may legitimately be in one of several states, and
        // `anyOf` passes as soon as one branch matches.
        anyOf(
            KassBranch("home") { try home.welcome.requireVisible() },
            KassBranch("login error") { try login.error.requireVisible() }
        )
    }

    func test_devicePressBack_returnsFromAPushedScreen() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.openWeb.tap() }
        onScreen(WebScreen.self, timeout: 30) { web in
            web.heading.assertVisible()
        }
        device.pressBack()
        onScreen(HomeScreen.self) { $0.welcome.assertVisible() }
    }
}
