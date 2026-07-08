# KassiOS ☕️

A tiny, batteries-included DSL on top of **XCUITest** — readable screen objects,
automatic waits, and built-in flaky-safety. Kaspresso-style ergonomics for iOS,
with **zero external dependencies** and one-line SPM install.

> Types use a short `Kass` prefix (`KassScreen`, `KassElement`, `KassTestCase`, `KassConfig`). Change with one find-replace if you prefer another.

## Why

Raw XCUITest makes you manage timing by hand. KassiOS bakes waiting and retries
into every interaction, so tests read like a script.

**Before — raw XCUITest:**

```swift
let email = app.textFields["login_email"]
XCTAssertTrue(email.waitForExistence(timeout: 10))
email.tap(); email.typeText("test@example.com")

let button = app.buttons["login_submit"]
XCTAssertTrue(button.waitForExistence(timeout: 10))
button.tap()

XCTAssertTrue(app.staticTexts["home_welcome"].waitForExistence(timeout: 10))
```

**After — KassiOS:**

```swift
onScreen(LoginScreen.self) { login in
    step("Enter valid credentials") {
        login.email.typeText("test@example.com")
        login.loginButton.tap()          // waits + retries internally
    }
}
onScreen(HomeScreen.self) { home in
    home.welcome.assertVisible()          // waits until it appears
}
```

No `waitForExistence`. No `sleep`. No stale references.

## Install

Swift Package Manager. Add the package and link it to your **UI Test target**:

```swift
.package(url: "https://github.com/<you>/KassiOS.git", from: "0.1.0")
```

## Use

1. Describe screens:

```swift
final class LoginScreen: KassScreen {
    lazy var email = textField("login_email")
    lazy var password = secureTextField("login_password")
    lazy var loginButton = button("login_submit")

    override var onLoad: [KassElement] { [email, loginButton] }
}
```

2. Write tests against a `KassTestCase`:

```swift
final class LoginFlowUITests: KassTestCase {
    func test_login() {
        launch()
        onScreen(LoginScreen.self) { login in
            login.email.typeText("test@example.com")
            login.password.typeText("secret")
            login.loginButton.tap()
        }
    }
}
```

## How it works

- **Implicit waits + flaky-safety.** Every interaction is wrapped in a retry
  loop (`Waiter`) that shares one time budget, so retries never compound into
  runaway timeouts. Toggle with `config.flakySafetyEnabled`.
- **Elements re-resolve on each attempt.** `KassElement` stores a
  `() -> XCUIElement` closure, not a cached element — the fix for stale
  references after the hierarchy reloads.
- **Readable reports.** `onScreen` and `step` wrap `XCTContext.runActivity`,
  so Xcode's test report and `.xcresult` group actions the way you wrote them.

## Configure

```swift
override func setUp() {
    super.setUp()
    config = KassConfig(timeout: 20, pollInterval: 0.25)
}
```

## Status

v0.1 — core DSL, waits, flaky-safety, step logging. On the roadmap: richer
assertions, gestures/scroll-to, permission & deep-link helpers, Allure export,
and an optional EarlGrey synchronization backend.

## License

MIT — see [LICENSE](LICENSE).
