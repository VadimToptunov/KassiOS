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
    lazy var openWeb = button("openWeb")
    lazy var refreshed = staticText("refreshed")
    lazy var list = custom("home-scroll") { [app] in
        let collection = app.collectionViews.firstMatch
        return collection.exists ? collection : app.tables.firstMatch
    }

    override var onLoad: [KassElement] { [welcome] }
}

final class WebScreen: KassScreen {
    lazy var container = webView()
    // Web (HTML) content has no accessibilityIdentifier, so resolve by label via
    // a custom query (exempt from the strict-id policy).
    lazy var heading = custom("web 'Hello Web'") { [app] in
        app.webViews.staticTexts["Hello Web"].firstMatch
    }

    override var onLoad: [KassElement] { [container] }
}
