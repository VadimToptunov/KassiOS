import XCTest

// KassiOS sources are compiled directly into this UI-test target, so there is no
// `import KassiOS`. Screen objects for the demo app.

final class LoginScreen: KassScreen {
    lazy var email = textField("email")
    lazy var password = secureTextField("password")
    lazy var signIn = button("signIn")
    lazy var error = staticText("loginError")

    override var onLoad: [KassElement] { [email, signIn] }
}

final class HomeScreen: KassScreen {
    lazy var welcome = staticText("welcome")
    lazy var notifications = switchControl("notifications")
    lazy var showAlert = button("showAlert")

    override var onLoad: [KassElement] { [welcome] }
}
