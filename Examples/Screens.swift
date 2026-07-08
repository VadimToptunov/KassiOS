// Illustrative only — this file shows how a consumer writes screen objects.
// It isn't wired into a compiled target because it refers to a hypothetical app.
import KassiOS

final class LoginScreen: KassScreen {
    lazy var email = textField("login_email")
    lazy var password = secureTextField("login_password")
    lazy var loginButton = button("login_submit")
    lazy var errorLabel = staticText("login_error")

    // The screen is "loaded" once these are on screen.
    override var onLoad: [KassElement] { [email, loginButton] }
}

final class HomeScreen: KassScreen {
    lazy var welcome = staticText("home_welcome")
    lazy var profileTab = button("tab_profile")

    override var onLoad: [KassElement] { [welcome] }
}
