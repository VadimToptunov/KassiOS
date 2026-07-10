# KassiOS ☕️

[![CI](https://github.com/VadimToptunov/KassiOS/actions/workflows/ci.yml/badge.svg)](https://github.com/VadimToptunov/KassiOS/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/VadimToptunov/KassiOS?sort=semver)](https://github.com/VadimToptunov/KassiOS/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A tiny, batteries-included DSL on top of **XCUITest** — readable screen objects,
automatic waits, and built-in flaky-safety. Kaspresso-style ergonomics for iOS,
with **zero external dependencies** and one-line SPM install.

> Types use a short `Kass` prefix (`KassScreen`, `KassElement`, `KassTestCase`, `KassConfig`). Change with one find-replace if you prefer another.

📖 **Full [documentation guide](Documentation/Guide.md)** — every feature, plus an
honest [when-to-use / when-not-to](Documentation/Guide.md#when-to-use-kassios--and-when-not-to).
API reference: build in Xcode via **Product ▸ Build Documentation** (a DocC
catalog ships in the target). Migrating an existing suite?
[Migration guide](Documentation/Migration.md). Release notes:
[CHANGELOG.md](CHANGELOG.md).

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
.package(url: "https://github.com/VadimToptunov/KassiOS.git", from: "0.1.0")
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
element.assertLabelContains("part")
element.assertValueMatches("^\\d{4}$")     // regex on value-or-label
element.assertHittable()          // .assertNotHittable()
element.waitUntil("is selected") { $0.isSelected }

// Scoped children — resolve within an element
row.staticText("title").assertHasText("Inbox")
row.button("delete").tap()

// Controls
element.setSwitch(on: true)                 // toggles only if needed
element.adjustSlider(toNormalizedPosition: 0.75)   // iOS
element.adjustPicker(toValue: "March")             // iOS

// Editing
element.replaceText("new")        // clears, then types

// Multitouch (iOS)
element.pinch(scale: 2, velocity: 1)
element.rotate(.pi / 4, velocity: 1)
element.twoFingerTap()
```

## Flow primitives (Kaspresso-style)

Compose custom conditions out of throwing checks (`requireExists`,
`requireVisible`, `requireHittable`) with the same primitives Kaspresso offers:

```swift
// Retry a multi-step condition until it holds (or the budget elapses).
flakySafely { try banner.requireVisible(); try dismiss.requireHittable() }

// Assert something stays true for a duration (the inverse of flaky-safety).
continuously(during: 1.0) { try spinner.requireExists() }

// Pass if the UI is in any one of several valid states.
compose(
    KassBranch("logged in")  { try home.requireVisible() },
    KassBranch("needs 2FA")  { try otpField.requireVisible() }
)

// Attempts-bounded retry.
retry(times: 3) { try list.requireExists() }

pressBack()   // taps the leading navigation-bar button
```

## Collections (lists & tables)

`KassElementCollection` is the query-level counterpart of `KassElement`:

```swift
screen.cells().assertNotEmpty()
screen.cells().assertCount(24)
screen.cells().element(at: 0).tap()
screen.cells().containing(.staticText, "Inbox").first.tap()
screen.staticTexts().matching(label: "Error").assertNotEmpty()
screen.images().forEach { $0.assertExists() }
```

Builders: `all(_:)`, `all(_:type:)`, `buttons()`, `staticTexts()`, `cells()`,
`images()`, `customCollection(_:_:)`.

## Parameterized tests

Run one body across many cases — each an isolated, reported activity (the
XCUITest analogue of Swift Testing's `@Test(arguments:)`):

```swift
parameterized([("a@b.c", true), ("bad", false), ("", false)], name: { $0.0 }) { email, valid in
    relaunch()                       // clean slate between cases
    onScreen(LoginScreen.self) { login in
        login.email.replaceText(email)
        login.submit.tap()
        valid ? onScreen(HomeScreen.self) { $0.welcome.assertVisible() }
              : login.error.assertVisible()
    }
}
```

## Device helpers

`device` on a `KassTestCase` reaches outside the app's view tree:

```swift
device.autoAllowSystemDialogs(test: self)   // dismiss permission alerts
app.tap()                                    // nudge XCUITest to deliver it
device.hideKeyboard()
device.screenshot("after login")            // attached to the .xcresult
device.allowSystemDialogNow()                // tap an on-screen permission alert
device.sendToBackground(for: 2)              // then reactivates
device.pressHome()                           // iOS only
device.rotate(to: .landscapeLeft)           // iOS only
device.open(url: "https://example.com")     // deep link via Safari (iOS)
device.waitForIdle()                         // via the configured synchronizer
let springboard = device.springboard         // home screen / system alerts host
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

## Allure reports

Attach an `AllureReporter` and KassiOS writes [Allure 2](https://allurereport.org)
result files — nested steps, interactions and screenshots included:

```swift
override func setUp() {
    super.setUp()
    config = KassConfig(reporter: AllureReporter())
}
```

Results go to `$ALLURE_RESULTS_PATH` (set it in the UI test target's scheme) or
`<temp>/allure-results`; the absolute path is logged at test start. Then:

```sh
allure serve <results-dir>
```

Every `step`, interaction and `device.screenshot` becomes a step/attachment in
the report. Steps left open by a hard failure are attributed the test's
terminal status, so the tree always closes cleanly.

## Synchronization backends

By default KassiOS is poll-based: `Waiter` re-tries until the UI is ready. For
stronger flaky-safety you can plug in a `KassSynchronizer` that blocks each
attempt until the app is *idle* (animations, network, main-queue work settled):

```swift
config = KassConfig(synchronizer: EarlGreySynchronizer())
```

The core ships `NoOpSynchronizer` and stays dependency-free; an EarlGrey-backed
adapter is provided as an opt-in reference in
[Examples/EarlGreySynchronizer.swift](Examples/EarlGreySynchronizer.swift).

## Strict identifiers, suites & structured runs

Force the app to carry real accessibility identifiers. `.warn` surfaces an Xcode
message; `.enforce` fails the test (with a screenshot) when an element is matched
by label instead of an explicit id:

```swift
config = KassConfig(accessibilityIdentifierPolicy: .enforce)  // or .warn / .ignore
// 'Orders' was matched without an accessibility identifier (element id='') —
// add .accessibilityIdentifier("Orders") to the view [strict mode]
//   ↳ exists=true hittable=true id='' label='Orders' type=48 frame=(…)
```

Run Apple's accessibility audit too:

```swift
if #available(iOS 17.0, *) { assertNoAccessibilityIssues() }
```

Share one config across a group with `KassSuite`, and structure a body with
`before`/`after`/`run` (`after` runs even on a hard failure):

```swift
class CheckoutSuite: KassSuite {
    override func configure() -> KassConfig {
        KassConfig(reporter: AllureReporter(), accessibilityIdentifierPolicy: .enforce)
    }
}

before { launch() }.after { device.screenshot("end") }.run {
    step("Checkout") { … }
}
```

## Configure

```swift
override func setUp() {
    super.setUp()
    config = KassConfig(timeout: 20, pollInterval: 0.25)
}
```

## Develop

The library wraps XCUITest, so it builds with Xcode rather than bare
`swift build`. Run the (pure-logic) unit tests on the macOS destination:

```sh
xcodebuild test -scheme KassiOS -destination 'platform=macOS'
```

Real UI coverage lives in [`IntegrationTests/`](IntegrationTests): a bundled
SwiftUI demo app plus KassiOS-driven UI tests that run on the simulator. Generate
the project and run them:

```sh
cd IntegrationTests && ruby gen.rb          # needs the `xcodeproj` gem
xcodebuild test -scheme KassDemoUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

Lint locally with [SwiftLint](https://github.com/realm/SwiftLint):

```sh
swiftlint lint --strict
```

CI (`.github/workflows/ci.yml`) runs three jobs on every push and PR — SwiftLint,
unit tests on macOS, and UI tests on a simulator. A separate workflow
(`.github/workflows/docs.yml`) publishes the DocC site to GitHub Pages (enable
Pages with the "GitHub Actions" source in repo settings).

## Status

v0.8 — core DSL, waits, flaky-safety, step logging, gestures + scroll-to +
multitouch + coordinate/drag, slider/switch/picker controls, rich assertions
(incl. label-contains/value-regex/placeholder/`waitUntil`), per-call
`within(timeout:)`, element collections for lists & tables, scoped child
elements, Kaspresso-style flow primitives
(`flakySafely`/`continuously`/`compose`/`retry`/`pressBack`), parameterized
(data-driven) tests, `KassSuite` + structured `before`/`after`/`run`
(teardown-safe), an **accessibility-identifier policy** (`ignore`/`warn`/`enforce`),
the **accessibility audit**, precise failure diagnostics (element snapshot +
screenshot), device/permission/deep-link/springboard helpers, reusable scenarios,
Allure export, and a pluggable synchronization backend. Real UI coverage runs on
the simulator in CI via a bundled demo app. See the
[full guide](Documentation/Guide.md).

Verified end-to-end against Apple's open-source
[Food Truck](https://github.com/apple/sample-food-truck) app on the iOS
Simulator — multi-screen navigation, flow primitives, screenshots and Allure
export all green.

## License

MIT — see [LICENSE](LICENSE).
