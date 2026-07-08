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

## Interactions & assertions

Every method below is chainable, self-waiting and flaky-safe:

```swift
// Interactions
element.tap()
element.typeText("hello")
element.clearText()

// Gestures
element.doubleTap()
element.longPress(forDuration: 1.5)
element.swipeUp()   // .swipeDown() / .swipeLeft() / .swipeRight()

// Scroll a container until the element is on screen
row.scrollTo(in: list, direction: .up)

// Assertions
element.assertVisible()
element.assertExists()
element.assertNotExists()        // or .waitUntilGone()
element.assertEnabled()          // .assertDisabled()
element.assertSelected(true)
element.assertHasText("partial") // substring of value-or-label
element.assertHasValue("exact")  // exact match on .value
element.assertLabel("exact")
```

## Device helpers

`device` on a `KassTestCase` reaches outside the app's view tree:

```swift
device.autoAllowSystemDialogs(test: self)   // dismiss permission alerts
app.tap()                                    // nudge XCUITest to deliver it
device.hideKeyboard()
device.screenshot("after login")            // attached to the .xcresult
device.sendToBackground(for: 2)              // then reactivates
device.rotate(to: .landscapeLeft)           // iOS only
device.open(url: "https://example.com")     // deep link via Safari (iOS)
```

## Reusable flows (scenarios)

Extract common journeys into a `KassScenario` and replay them anywhere:

```swift
struct LoginScenario: KassScenario {
    let email: String, password: String
    func run(in test: KassTestCase) {
        test.onScreen(LoginScreen.self) { login in
            login.email.typeText(email)
            login.password.typeText(password)
            login.loginButton.tap()
        }
    }
}

func test_home() {
    launch()
    scenario(LoginScenario(email: "a@b.c", password: "secret"))
    onScreen(HomeScreen.self) { $0.welcome.assertVisible() }
}
```

A failing test automatically attaches a screenshot of its final state to the
report.

## Configure

```swift
override func setUp() {
    super.setUp()
    config = KassConfig(timeout: 20, pollInterval: 0.25)
}
```

## Status

v0.2 — core DSL, waits, flaky-safety, step logging, gestures + scroll-to, rich
assertions, device/permission/deep-link helpers, reusable scenarios, and
screenshot-on-failure. On the roadmap: Allure export and an optional EarlGrey
synchronization backend.

## License

MIT — see [LICENSE](LICENSE).
