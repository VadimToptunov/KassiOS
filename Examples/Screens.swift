// Illustrative only — this file shows how a consumer writes screen objects.
// It isn't wired into a compiled target because it refers to a hypothetical app.
import KassiOS

final class LoginScreen: KassScreen {
    lazy var email = textField("login.email")
    lazy var password = secureTextField("login.password")
    lazy var loginButton = button("login.submit")
    lazy var errorLabel = staticText("login.error")

    // The screen is "loaded" once these are on screen.
    override var onLoad: [KassElement] { [email, loginButton] }
}

final class HomeScreen: KassScreen {
    lazy var welcome = staticText("home.welcome")
    lazy var profileTab = button("home.profileTab")

    override var onLoad: [KassElement] { [welcome] }
}
