// Illustrative only — shows how a consumer writes reusable scenarios.
// It isn't wired into a compiled target because it refers to a hypothetical app.
import KassiOS

/// A reusable log-in journey, replayable from any test via `scenario(_:)`.
struct LoginScenario: KassScenario {
    let email: String
    let password: String

    func run(in test: KassTestCase) {
        test.onScreen(LoginScreen.self) { login in
            test.step("Log in as \(email)") {
                login.email.typeText(email)
                login.password.typeText(password)
                login.loginButton.tap()
            }
        }
    }
}

final class HomeAfterLoginUITests: KassTestCase {
    func test_landsOnHome() {
        launch(arguments: ["-uitest"])
        device.autoAllowSystemDialogs(test: self)

        scenario(LoginScenario(email: "test@example.com", password: "correct-horse"))

        onScreen(HomeScreen.self) { home in
            home.welcome.assertVisible()
            device.screenshot("home")
        }
    }
}
