// Illustrative only. In a real project this lives in your app's UI Test target.
import XCTest
import KassiOS

final class LoginFlowUITests: KassTestCase {

    func test_validCredentials_openHome() {
        launch(arguments: ["-uitest"])

        onScreen(LoginScreen.self) { login in
            step("Enter valid credentials") {
                login.email.typeText("test@example.com")
                login.password.typeText("correct-horse")
                login.loginButton.tap()          // implicit wait + retry inside
            }
        }

        onScreen(HomeScreen.self) { home in
            step("Land on Home") {
                home.welcome.assertVisible()      // waits until it appears
            }
        }
    }

    func test_wrongPassword_showsError() {
        launch(arguments: ["-uitest"])

        onScreen(LoginScreen.self) { login in
            step("Enter a wrong password") {
                login.email.typeText("test@example.com")
                login.password.typeText("nope")
                login.loginButton.tap()
            }
            step("Error is shown") {
                login.errorLabel.assertHasText("Invalid credentials")
            }
        }
    }
}
