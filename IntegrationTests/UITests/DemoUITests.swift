import XCTest

/// KassiOS's own end-to-end coverage: real interactions against the bundled
/// demo app, run on the iOS Simulator in CI. Strict mode is on (`.enforce`) —
/// the demo sets accessibility identifiers everywhere, so it passes.
final class DemoUITests: KassTestCase {

    override func setUp() {
        super.setUp()
        config = KassConfig(accessibilityIdentifierPolicy: .enforce)
    }

    func test_login_then_home() {
        launch()
        onScreen(LoginScreen.self) { login in
            login.email.assertPlaceholder("Email")
            login.email.typeText("a@b.c")
            login.password.typeText("secret")
            login.signIn.tap()
        }
        onScreen(HomeScreen.self) { home in
            home.welcome.assertVisible()
            home.welcome.assertHasText("Welcome")
            home.notifications.setSwitch(on: true)
            home.notifications.assertHasValue("1")
        }
    }

    func test_list_collection() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("x@y.z"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.welcome.assertVisible()
            home.all("item-0", type: .staticText).assertNotEmpty()
            XCTAssertGreaterThan(home.staticTexts().count, 3)
        }
    }

    func test_login_validation_parameterized() {
        parameterized(
            [("", true), ("valid@example.com", false)],
            name: { $0.0.isEmpty ? "empty-email" : "valid-email" }
        ) { (email, expectsError) in
            relaunch()
            onScreen(LoginScreen.self) { login in
                if !email.isEmpty { login.email.typeText(email) }
                login.signIn.tap()
                if expectsError {
                    login.error.assertVisible()
                } else {
                    HomeScreen(app: app, config: config).welcome.assertVisible()
                }
            }
        }
    }

    func test_accessibility_audit() {
        launch()
        if #available(iOS 17.0, *) {
            // Exclude the sometimes-borderline contrast heuristic for a stable run.
            assertNoAccessibilityIssues(for: XCUIAccessibilityAuditType.all.subtracting(.contrast))
        }
    }

    func test_scaffold_generation() {
        launch()
        let code = KassScaffold.generate(for: app, screenName: "GeneratedLoginScreen")
        print("SCAFFOLD:\n\(code)")
        XCTAssertTrue(code.contains("final class GeneratedLoginScreen: KassScreen"))
        XCTAssertTrue(code.contains("textField(\"email\")"))
        XCTAssertTrue(code.contains("button(\"signIn\")"))
    }

    func test_localized_screenshots() {
        var visited: [String] = []
        forEachLocale(["en", "fr"]) { locale in
            onScreen(LoginScreen.self) { $0.email.assertVisible() }
            device.screenshot("login-\(locale)")
            visited.append(locale)
        }
        XCTAssertEqual(visited, ["en", "fr"])
    }

    func test_combinators_and_alert() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }

        assertOnScreen(HomeScreen.self)                       // checkpoint
        let home = HomeScreen(app: app, config: config)
        XCTAssertNotNil(waitForAny([home.welcome, home.notifications]))

        home.showAlert.tap()
        alert().assertExists().tap("OK")
    }

    func test_pullToRefresh() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.refreshed.assertNotExists()
            home.welcome.pullToRefresh()
            home.refreshed.assertVisible()
        }
    }

    func test_webView() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        HomeScreen(app: app, config: config).openWeb.tap()
        onScreen(WebScreen.self) { web in
            // Web content can be slow to load — give it a longer budget.
            web.heading.within(timeout: 30).assertVisible()
        }
    }

    func test_screenshotEachStep() {
        config = KassConfig(accessibilityIdentifierPolicy: .enforce, screenshotEachStep: true)
        launch()
        step("Login screen visible") {
            onScreen(LoginScreen.self) { $0.email.assertVisible() }
        }
        device.attachText("note", "a plain-text attachment")
    }
}
