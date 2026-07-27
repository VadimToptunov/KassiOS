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
    lazy var requestLocation = button("requestLocation")
    lazy var locationStatus = staticText("locationStatus")
    lazy var locale = staticText("locale")
    lazy var fetchButton = button("fetchButton")
    lazy var fetchResult = staticText("fetchResult")
    lazy var refreshed = staticText("refreshed")
    lazy var list = custom("home-scroll") { [app] in
        let collection = app.collectionViews.firstMatch
        return collection.exists ? collection : app.tables.firstMatch
    }

    func item(_ index: Int) -> KassElement { staticText("item-\(index)") }

    // Locator-ergonomics (0.23.0) coverage — see KassDemoApp's "Locator ergonomics" section.
    /// Type-agnostic id lookup; also the id-first proof: a label-only decoy with
    /// the same string appears earlier in the tree but must lose to this real id.
    lazy var decoyTarget = element("decoyMatch")
    /// Disambiguates same-id rows by their (different) labels.
    func duplicateRow(label: String) -> KassElement { element(id: "duplicateId", label: label, type: .staticText) }

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
