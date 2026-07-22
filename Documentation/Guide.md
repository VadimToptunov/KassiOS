# KassiOS Guide

A complete tour of KassiOS — a Kaspresso-style DSL over XCUITest with implicit
waits, flaky-safety, readable reports, and zero external dependencies.

- [Installation](#installation)
- [Core concepts](#core-concepts)
- [Screens & elements](#screens--elements)
- [Interactions](#interactions)
- [Assertions](#assertions)
- [Collections (lists & tables)](#collections-lists--tables)
- [Web content](#web-content)
- [Flow primitives](#flow-primitives)
- [Parameterized tests](#parameterized-tests)
- [Steps & scenarios](#steps--scenarios)
- [Device helpers](#device-helpers)
- [Reporting: screenshots & Allure](#reporting-screenshots--allure)
- [Localized screenshots (Docloc)](#localized-screenshots-docloc)
- [Synchronization backends](#synchronization-backends)
- [Configuration reference](#configuration-reference)
- [Enforcing accessibility identifiers](#enforcing-accessibility-identifiers)
- [Scaffolding screen objects](#scaffolding-screen-objects)
- [Accessibility audit](#accessibility-audit)
- [Failure diagnostics](#failure-diagnostics)
- [Suites & structured runs](#suites--structured-runs)
- [Snapshot regression](#snapshot-regression)
- [When to use KassiOS — and when not to](#when-to-use-kassios--and-when-not-to)

---

## Installation

Swift Package Manager, linked to your **UI Test target**:

```swift
.package(url: "https://github.com/VadimToptunov/KassiOS.git", from: "0.10.0")
```

The library wraps XCUITest, so it builds with Xcode (not bare `swift build`).

---

## Core concepts

Three types carry the whole DSL:

| Type | Role |
| --- | --- |
| `KassTestCase` | Base class for tests. Owns `app`, `config`, `device`, and the `onScreen`/`step`/flow APIs. |
| `KassScreen` | A page object. Declares elements as lazy properties and lists `onLoad` proof elements. |
| `KassElement` | A lazy, self-waiting handle to one `XCUIElement`. Every interaction retries under one shared time budget. |

`KassConfig` flows from the test case into every screen and element, so one place
controls timing, flaky-safety, logging, reporting and synchronization.

The key design choice: `KassElement` stores a `() -> XCUIElement` **closure**, not
a cached element. It re-resolves on every attempt, which is what lets flaky-safety
recover after the view hierarchy reloads.

---

## Screens & elements

```swift
final class LoginScreen: KassScreen {
    lazy var email = textField("login_email")
    lazy var password = secureTextField("login_password")
    lazy var submit = button("login_submit")

    // The screen is "loaded" once these are visible.
    override var onLoad: [KassElement] { [email, submit] }
}
```

Element builders (by accessibility identifier): `button`, `staticText`,
`textField`, `secureTextField`, `image`, `cell`, `switchControl`, `other`, and the
generic `element(_:type:)`. Identifiers resolve with `firstMatch`, so an ambiguous
id takes the first hit rather than crashing.

Escape hatches when identifiers aren't enough:

```swift
lazy var banner = custom("promo banner") { app.otherElements["promo"].firstMatch }
```

Reach *into* an element with scoped children:

```swift
row.staticText("title").assertHasText("Inbox")   // resolves within `row`
row.button("delete").tap()
```

---

## Interactions

All are chainable, self-waiting and flaky-safe:

```swift
element.tap()
element.typeText("hello")
element.clearText()
element.replaceText("new")              // clear, then type

element.doubleTap()
element.longPress(forDuration: 1.5)
element.swipeUp()                       // .swipeDown/.swipeLeft/.swipeRight

element.setSwitch(on: true)             // toggles only if needed
element.adjustSlider(toNormalizedPosition: 0.75)   // iOS
element.adjustPicker(toValue: "March")             // iOS

// Multitouch (iOS)
element.pinch(scale: 2, velocity: 1)
element.rotate(.pi / 4, velocity: 1)
element.twoFingerTap()

// Scroll a container until the element is on screen
row.scrollTo(in: list, direction: .up)

// Coordinates & drag
element.tapAtNormalizedOffset(x: 0.9, y: 0.5)
source.drag(to: destination)

// Pull-to-refresh — call on an element near the top of the scrollable content
firstRow.pullToRefresh()

// A one-off timeout, longer or shorter than the global config
slowRow.within(timeout: 30).assertVisible()

// Read state without waiting
let text = field.readValue()
let label = row.readLabel()
```

For anything unwrapped, `perform` runs your closure under the same flaky-safety:

```swift
element.perform("custom") { xcuiElement in
    guard xcuiElement.isHittable else { throw KassError("not ready") }
    xcuiElement.tap()
}
```

---

## Assertions

```swift
element.assertVisible()                 // strict: exists + hittable (on screen)
element.assertPresent()                 // softer: exists + non-empty frame (may be off screen)
element.assertExists()
element.assertNotExists()               // or .waitUntilGone()
element.assertEnabled()                 // .assertDisabled()
element.assertSelected(true)
element.assertHittable()                // .assertNotHittable()
element.assertHasText("partial")        // substring of value-or-label
element.assertHasValue("exact")         // exact match on .value
element.assertLabel("exact")
element.assertLabelContains("part")
element.assertValueMatches("^\\d{4}$")   // regex on value-or-label

element.assertPlaceholder("Email")
element.waitUntil("is selected") { $0.isSelected }
```

Every assertion waits up to `config.timeout` before failing, and reports a
readable reason (`KassiOS: button 'login_submit' — assertVisible failed: …`).

---

## Collections (lists & tables)

`KassElementCollection` is the query-level counterpart of `KassElement` — lazy and
re-evaluated on each access.

```swift
let donuts = screen.images()                    // all images
donuts.assertNotEmpty()
donuts.assertCount(24)
XCTAssertGreaterThan(donuts.count, 5)

screen.cells().element(at: 0).tap()
screen.cells().first.assertVisible()
screen.cells().last.assertExists()

// Refine, then act
screen.cells()
    .containing(.staticText, "Inbox")
    .first
    .tap()

screen.staticTexts()
    .matching(label: "Error")
    .assertNotEmpty()

screen.cells().elementMatching(label: "Settings").tap()

// Iterate live matches
screen.cells().forEach { $0.assertExists() }
let labels = screen.staticTexts().map { $0 }
```

Builders on `KassScreen`: `all(_:)`, `all(_:type:)`, and the shortcuts
`buttons()`, `staticTexts()`, `cells()`, `images()`. Or wrap any query with
`customCollection(_:_:)`.

---

## Web content

Reach into a `WKWebView` with `webView()` and the usual builders. HTML has no
accessibility identifiers, so resolve web elements by label via `custom` (or
`links()` for a collection of links):

```swift
final class ArticleScreen: KassScreen {
    lazy var web = webView()
    lazy var title = custom("web title") { app.webViews.staticTexts["Hello Web"].firstMatch }
    override var onLoad: [KassElement] { [web] }
}

onScreen(ArticleScreen.self) { article in
    article.title.within(timeout: 30).assertVisible()   // web can be slow to load
    article.web.links().first.tap()
}
```

## Flow primitives

Kaspresso-style building blocks on `KassTestCase`. They take throwing closures —
inside them, use the single-shot throwing checks (`requireExists`,
`requireVisible`, `requireHittable`) or raw `XCUIElement` conditions.

```swift
// Retry a multi-step condition until it holds (or the budget elapses).
flakySafely { try banner.requireVisible(); try dismiss.requireHittable() }

// Assert something stays true for a duration (inverse of flaky-safety).
continuously(during: 1.0) { try spinner.requireExists() }

// Pass if the UI is in any one of several valid states.
compose(
    KassBranch("logged in") { try home.requireVisible() },
    KassBranch("needs 2FA") { try otp.requireVisible() }
)

// Attempts-bounded retry.
retry(times: 3) { try list.requireExists() }

pressBack()   // taps the leading navigation-bar button

// Wait for any / all, and mid-test screen checkpoints
let which = waitForAny([home.welcome, login.error])   // index of the first to appear
waitForAll([toolbar, list])
assertOnScreen(HomeScreen.self)

// App alerts
home.showAlert.tap()
alert().assertExists().tap("OK")
```

`flakySafely` / `retry` return the block's value (as an optional, `nil` on
failure), so they compose:

```swift
let count = flakySafely { screen.cells().count } ?? 0
```

---

## Parameterized tests

Run one body across many cases — each grouped as its own activity and report
step, with failures isolated so every case runs. The XCUITest analogue of Swift
Testing's `@Test(arguments:)`.

```swift
func test_login_validation() {
    parameterized(
        [("a@b.c", true), ("bad-email", false), ("", false)],
        name: { $0.0 }
    ) { (email, valid) in
        relaunch()                      // clean slate between cases
        onScreen(LoginScreen.self) { login in
            login.email.replaceText(email)
            login.submit.tap()
            if valid {
                onScreen(HomeScreen.self) { $0.welcome.assertVisible() }
            } else {
                login.error.assertVisible()
            }
        }
    }
}
```

Because UI state persists between cases, reset inside the body when they aren't
independent — `relaunch()` terminates and relaunches the app.

---

## Steps & scenarios

`step` groups actions in Xcode's report (and the Allure report) and logs timing:

```swift
step("Enter credentials") {
    login.email.typeText("test@example.com")
    login.submit.tap()
}
```

`KassScenario` extracts reusable journeys:

```swift
struct LoginScenario: KassScenario {
    let email: String, password: String
    func run(in test: KassTestCase) {
        test.onScreen(LoginScreen.self) { login in
            login.email.typeText(email)
            login.password.typeText(password)
            login.submit.tap()
        }
    }
}

scenario(LoginScenario(email: "a@b.c", password: "secret"))
```

---

## Device helpers

`device` reaches outside the app's view tree:

```swift
device.autoAllowSystemDialogs(test: self)   // monitor for later permission alerts
app.tap()                                    // nudge XCUITest to deliver a pending one
device.allowSystemDialogNow()                // tap an alert already on screen
device.hideKeyboard()
device.screenshot("after login")            // attached to the report
device.sendToBackground(for: 2)              // then reactivates
device.pressHome()                           // iOS
device.rotate(to: .landscapeLeft)           // iOS
launch(deeplink: "acme://item/42")           // preferred: app reads -deeplink and routes
device.open(url: "https://example.com")     // fallback: deep link via Safari (iOS)
device.waitForIdle()                         // via the configured synchronizer
device.attachText("api-log", logString)      // attach arbitrary text to the report
let springboard = device.springboard         // home screen / system-alert host
```

Set `config.screenshotEachStep = true` to attach a screenshot after every
`step` — a visual trail of the whole test.

> System-level operations that need `simctl` (network, GPS, status bar, granting
> permissions without a dialog, push) run *outside* the test process, in your CI
> harness — the XCUITest process lives on the simulator and can't shell out.

For those, KassiOS ships [`Scripts/kass-simctl.sh`](../Scripts/kass-simctl.sh) —
run it around `xcodebuild test`:

```sh
kass-simctl boot "iPhone 16"
kass-simctl status-bar override            # clean 9:41 bar for screenshots
kass-simctl appearance dark
kass-simctl permission com.acme.App grant photos
kass-simctl location 37.7749 -122.4194
kass-simctl push com.acme.App payload.json
kass-simctl openurl "acme://deep/link"
```

---

## Reporting: screenshots & Allure

A failing test automatically attaches a screenshot of its final state.

Attach an `AllureReporter` for machine-readable [Allure 2](https://allurereport.org)
results — nested steps, interactions and screenshots:

```swift
override func setUp() {
    super.setUp()
    config = KassConfig(reporter: AllureReporter())
}
```

Results go to `$ALLURE_RESULTS_PATH` or `<temp>/allure-results`; the path is
logged at test start. Then `allure serve <results-dir>`. Steps left open by a hard
failure are attributed the test's terminal status, so the tree always closes.

Tag tests with metadata — it lands as Allure labels and links:

```swift
severity(.critical)
feature("Login"); story("Sign in with email")
owner("qa-team"); tag("smoke")
issue("JIRA-1234", "https://tracker/JIRA-1234")
tms("TC-42", "https://tms/TC-42")
```

Prefer plain JUnit XML (every CI understands it)? Use `JUnitReporter` — same
protocol, one `<testsuite>` file per test under `$KASS_JUNIT_PATH`:

```swift
config = KassConfig(reporter: JUnitReporter())
```

Implement `KassReporter` to route into any other backend (metadata methods have
no-op defaults).

---

## Localized screenshots (Docloc)

Capture a flow across languages — for App Store screenshots or visual review.
`forEachLocale` relaunches the app in each language and runs your flow:

```swift
func test_localized() {
    forEachLocale(["en", "fr", "de"]) { locale in
        onScreen(LoginScreen.self) { $0.email.assertVisible() }
        device.screenshot("login-\(locale)")
    }
}
```

Appearance (light/dark) and Dynamic Type can't be switched from inside the test
process — drive them host-side and loop locales within each:

```sh
for mode in light dark; do
  kass-simctl appearance $mode
  xcodebuild test -only-testing:…/test_localized …
done
```

## Synchronization backends

By default KassiOS polls (via `Waiter`). Plug in a `KassSynchronizer` to also
block until the app is *idle* (animations, network, main-queue work):

```swift
config = KassConfig(synchronizer: EarlGreySynchronizer())
```

The core ships `NoOpSynchronizer` and stays dependency-free; an EarlGrey-backed
adapter is an opt-in reference in `Examples/EarlGreySynchronizer.swift`.

---

## Configuration reference

```swift
config = KassConfig(
    timeout: 20,                 // total budget per interaction, incl. retries
    pollInterval: 0.25,          // delay between attempts
    flakySafetyEnabled: true,    // false = attempt each interaction exactly once
    logger: ConsoleKassLogger(), // step/interaction log sink
    reporter: AllureReporter(),  // optional structured report
    synchronizer: NoOpSynchronizer(),
    accessibilityIdentifierPolicy: .ignore,  // .warn / .enforce (see below)
    captureScreenshotOnFailure: true         // attach a screenshot on failure
)
```

Set it in `setUp` after `super.setUp()`; the reporter starts lazily on first use,
so a config assigned there is already in place.

---

## Enforcing accessibility identifiers

Tests are only as stable as the app's element identity. The identifier policy
**pushes the app team to add real accessibility identifiers** — when an element
is found by its visible label instead of an explicit `accessibilityIdentifier`:

- `.ignore` (default) — say nothing.
- `.warn` — log a message and add an Xcode activity, but let the test pass.
- `.enforce` — fail with an actionable message (and a screenshot).

```swift
config = KassConfig(accessibilityIdentifierPolicy: .enforce)
```

```
'Orders' was matched without an accessibility identifier (element id='') —
add .accessibilityIdentifier("Orders") to the view [strict mode]
  ↳ exists=true hittable=true id='' label='Orders' type=48 frame=(33.0, 234.3, 91.3, 23.7)
```

Only elements built from an identifier (`button(_:)`, `staticText(_:)`, …,
`descendant(_:_:)`) are checked; `custom(_:_:)` closures and collection elements
are exempt. XCUITest reports an empty `identifier` for label-matched elements,
which is how KassiOS tells a real identifier from a label fallback.

## Scaffolding screen objects

Model a screen once from the live tree instead of hand-writing it. From a
throwaway test on the screen you want:

```swift
func test_scaffold() {
    launch()
    printScreenScaffold("LoginScreen")   // prints ready-to-paste Swift
}
```

```swift
final class LoginScreen: KassScreen {
    lazy var signIn = button("signIn")
    lazy var email = textField("email")
    lazy var password = secureTextField("password")
}
// 3 element(s) had no accessibilityIdentifier — add ids to include them.
```

Only elements with a real identifier become properties; the trailing count tells
you how many are still missing (pairs with strict mode).
`KassScaffold.generate(for:screenName:)` returns the string if you'd rather write
it to a file.

## Accessibility audit

Run Apple's automated accessibility audit (iOS 17+) — contrast, hit-region size,
clipped/overlapping text, missing labels — a natural companion to strict ids:

```swift
if #available(iOS 17.0, *) {
    assertNoAccessibilityIssues()
    // Narrow the checks if a heuristic is too strict for you:
    assertNoAccessibilityIssues(for: XCUIAccessibilityAuditType.all.subtracting(.contrast))
}
```

## Failure diagnostics

Every failed interaction appends a one-line snapshot of the offending element —
`exists`, `hittable`, `id`, `label`, `type`, `frame` — and (unless disabled via
`captureScreenshotOnFailure`) attaches a screenshot of the screen at the moment
of failure to the report. The message names the exact element, so a red run
points straight at the problem. A failing test also attaches the full
accessibility tree (`app.debugDescription`) in `tearDown` — invaluable when an
element wasn't where you expected.

## Network stubs

XCUITest runs out of process, so you can't intercept traffic in-process. The
reliable pattern is a launch-time switch the app reads to serve fixtures.
`launch(stubs:)` passes them as `KASS_STUB_<name>` environment variables:

```swift
launch(stubs: ["profile": "fixtures/profile.json", "feed": "empty"])
// In the app:  ProcessInfo.processInfo.environment["KASS_STUB_profile"]
```

The app side (reading the vars and returning fixtures or booting a local stub
server) is yours; KassiOS just standardises the convention.

## Suites & structured runs

Share one configuration across a group of tests with `KassSuite`:

```swift
class CheckoutSuite: KassSuite {
    override func configure() -> KassConfig {
        KassConfig(timeout: 20, reporter: AllureReporter(), requireAccessibilityIdentifiers: true)
    }
}

final class CartTests: CheckoutSuite { /* inherits the config */ }
```

Structure a test body with `before` / `after` / `run`:

```swift
before { launch() }
    .after { device.screenshot("end") }
    .run {
        step("Add to cart") { … }
        step("Checkout")    { … }
    }
```

`before` runs first and `after` on normal completion; for teardown that must
survive a hard failure, use `tearDown`.

## Snapshot regression

Compare the current screen (or an element) against a committed reference image —
zero-dependency (PNG pixels via CoreGraphics/ImageIO, no external library):

```swift
assertSnapshot(named: "home")                 // whole screen
assertSnapshot(of: home.card, named: "card")  // one element
assertSnapshot(named: "home", tolerance: 0.01)
```

References go in `$KASS_SNAPSHOTS_PATH` when set (recommended on CI, where the
source path may be read-only or different), otherwise a `__Snapshots__` folder
beside the test file. The first run (or `record: true`, or the
`KASS_RECORD_SNAPSHOTS` env var) records the reference and fails, prompting you
to commit it. Comparison is pixel-based, so **pin the simulator device and OS** —
otherwise anti-aliasing differences cause noise.

Mask out dynamic regions (a status-bar clock, a live timestamp) with normalized
`ignoring` rects — masked areas never trigger a mismatch:

```swift
// Ignore the top 4% (status bar) — rects are normalized 0...1 of the image.
assertSnapshot(named: "home", ignoring: [CGRect(x: 0, y: 0, width: 1, height: 0.04)])
```

On a mismatch KassiOS attaches three images to the report — the **reference**,
the **actual**, and a generated **diff** (unchanged UI dimmed to faint
grayscale, changed pixels flagged red) — so you can see *what* moved straight
from the `.xcresult` without eyeballing two screenshots side by side.

## When to use KassiOS — and when not to

KassiOS is a thin, opinionated layer, not a silver bullet. An honest take:

**Reach for it when**
- You write a lot of UI tests and want Kaspresso-parity ergonomics out of the box:
  steps, scenarios, `compose`/`continuously`, flaky-safety with a shared budget,
  Allure export, parameterized cases.
- Your team comes from Android/Kaspresso and wants familiar structure.

**Prefer plain XCUITest when**
- You want minimum magic and the shortest path from a failure to the offending
  line. KassiOS interactions call `XCTFail` internally and return `self`; with
  `continueAfterFailure = true`, a chain keeps running past a failure.
- A handful of `XCUIElement` extensions (a `tapWhenReady` helper + page objects)
  would already cover your needs with types every iOS developer knows.
- You value staying close to where Apple is heading (Swift Testing) over a bespoke
  layer you must maintain.

Two things dominate test readability regardless of framework: **good page objects**
and **accessibility identifiers on the app**. Both are available on raw XCUITest.
KassiOS adds convenience on top of them — it doesn't replace them.
