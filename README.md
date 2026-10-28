# KassiOS ☕️

[![CI](https://github.com/VadimToptunov/KassiOS/actions/workflows/ci.yml/badge.svg)](https://github.com/VadimToptunov/KassiOS/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/VadimToptunov/KassiOS?sort=semver)](https://github.com/VadimToptunov/KassiOS/releases)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FVadimToptunov%2FKassiOS%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/VadimToptunov/KassiOS)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FVadimToptunov%2FKassiOS%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/VadimToptunov/KassiOS)
[![Docs](https://img.shields.io/badge/docs-DocC-informational)](https://vadimtoptunov.github.io/KassiOS/documentation/kassios/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

KassiOS is a layer over XCUITest in the style of
[Kaspresso](https://github.com/KasperskyLab/Kaspresso): screen objects, waits and
retries inside every action, steps in the report, Allure and JUnit output,
parameterized tests and snapshot checks. The library has no dependencies and goes
into your UI-test target. A few host-side tools come with it: `kassios-agent` for
simulator control, `kassios-mutants` for checking that tests catch the defects
they're written for, and `kassios-lint` for screen objects.

## Why

In raw XCUITest, waiting and retrying are up to you. In KassiOS every action
waits and retries within one time budget, and checks what it did.

**Before — raw XCUITest:**

```swift
let email = app.textFields["login.email"]
XCTAssertTrue(email.waitForExistence(timeout: 10))
email.tap(); email.typeText("test@example.com")

let button = app.buttons["login.submit"]
XCTAssertTrue(button.waitForExistence(timeout: 10))
button.tap()

XCTAssertTrue(app.staticTexts["home.welcome"].waitForExistence(timeout: 10))
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

### Where Swift Testing fits

Swift Testing doesn't drive an app's UI (in Xcode 27.1 its only template is for
unit tests), so the two cover different layers:

| | Swift Testing | KassiOS |
| --- | --- | --- |
| Layer | unit / logic | end-to-end UI |
| Drives the app UI | no | yes (XCUITest) |
| Runs in-process with your types | yes | no (separate UI-test target) |
| Parameterized cases | `@Test(arguments:)` | `parameterized(_:)` |

Use Swift Testing for model and view-model logic and KassiOS for the flows a
user taps through. They live in different targets.

> Types use a short `Kass` prefix (`KassScreen`, `KassElement`, `KassTestCase`, `KassConfig`). Change with one find-replace if you prefer another.

Documentation:

- [Guide](Documentation/Guide.md): every feature in detail, and
  [when to use KassiOS and when not to](Documentation/Guide.md#when-to-use-kassios--and-when-not-to).
- [DocC reference](https://vadimtoptunov.github.io/KassiOS/documentation/kassios/),
  with articles on coming from Kaspresso, why XCUITest suites flake,
  parameterized UI tests and CI.
- [Migration guide](Documentation/Migration.md) for an existing suite, and the
  [changelog](CHANGELOG.md).

A real suite to read: [ChaosBank ⨯ KassiOS](https://github.com/VadimToptunov/ChaosBank-KassiOS-Tests)
tests [ChaosBank](https://github.com/VadimToptunov/ChaosBank-iOS), a banking app
with switchable defects (a WKWebView login, a live market feed, money flows). It
passes on the clean build and turns red on each defect it lists.

## Install

Add the package with Swift Package Manager and link `KassiOS` to your UI-test target:

```swift
.package(url: "https://github.com/VadimToptunov/KassiOS.git", from: "1.9.0")
```

The host-side tools (`kassios`, `kassios-agent`, `kassios-mutants`,
`kassios-lint`) come as one Homebrew formula, prebuilt for Apple silicon and Intel:

```sh
brew install vadimtoptunov/tap/kassios
```

```sh
kassios agent start                 # simulator control for device.* calls; `kassios agent stop`
kassios lint UITests --strict       # check screen objects before a run
kassios mutants mutants.json --clean
```

Without Homebrew, download `kassios-<version>-macos.zip` from
[Releases](https://github.com/VadimToptunov/KassiOS/releases) and put its `bin/`
on your `PATH`, or run them from a checkout with `swift run kassios …`. The
library doesn't need any of the tools; each is only for the features named here.

## Use

1. Describe screens:

```swift
final class LoginScreen: KassScreen {
    lazy var email = textField("login.email")
    lazy var password = secureTextField("login.password")
    lazy var loginButton = button("login.submit")

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

## How it compares

| | Raw XCUITest | EarlGrey | KassiOS |
| --- | --- | --- | --- |
| Waiting and retries | `waitForExistence` by hand | idling resources, in process | in every action, one shared budget |
| Element found again on each attempt | by hand | n/a | yes |
| Screen objects | your own | your own | `KassScreen` |
| Reports | `.xcresult` | `.xcresult` | `.xcresult`, Allure, JUnit |
| Knows when the app is idle | no | yes | through a synchronizer hook (EarlGrey adapter included) |
| Setup | none | framework in the app | SPM package in the UI-test target |

EarlGrey runs inside the app and knows when it's idle. KassiOS stays out of
process, like XCUITest, and polls. More on the trade-offs in
[when to use KassiOS and when not to](Documentation/Guide.md#when-to-use-kassios--and-when-not-to).

## Interactions & assertions

Every method below is chainable, self-waiting and flaky-safe:

```swift
// Locators — id-first: matches the real accessibility identifier when one
// exists, only falling back to a label match when it doesn't
element("checkout.confirm")                     // any element type, not just one
element(id: "sheet.title", label: "Confirm")    // id AND label — for SwiftUI's
button(id: "sheet.title", label: "Confirm")     // container-id propagation
staticText(containing: "Welcome")               // label substring (intentional
button(containing: "Sign In")                   // label matching — no id warning)
element(labelContains: "Welcome")               // — any type, same intent

// Interactions
element.tap()
element.typeText("hello")
element.clearText()

// Gestures
element.doubleTap()
element.longPress(forDuration: 1.5)
element.swipeUp()   // .swipeDown() / .swipeLeft() / .swipeRight()
element.swipe(.up, velocity: .fast)                 // iOS
element.drag(byX: 0, y: -200)                       // iOS: press and drag by an offset
element.rapidTap(times: 2)                          // iOS: same spot, no waiting between taps

// Scroll a container until the element is on screen
row.scrollTo(in: list, direction: .up)

// Assertions
element.assertVisible()          // strict: exists + hittable (on screen)
element.assertPresent()          // softer: exists + non-empty frame
element.assertExists()
element.assertNotExists()        // or .waitUntilGone()
element.assertEnabled()          // .assertDisabled()
element.assertSelected(true)
element.assertTextContains("partial") // substring of value-or-label (was `assertHasText`, now deprecated)
element.assertHasValue("exact")  // exact match on .value
element.assertLabel("exact")
element.assertLabelContains("part")
element.assertValueMatches("^\\d{4}$")     // regex on value-or-label
element.assertHittable()          // .assertNotHittable()
element.waitUntil("is selected") { $0.isSelected }
element.assertUnchanged(for: 3)  // the text must not change for 3 s

// Deep assertions — beyond presence-only checks
element.assertValue(closeTo: 92.5, tolerance: 0.01)  // numeric, locale-aware ("$92.50")
element.assertAppears(within: 2)                     // catches a transient (toast) before it dismisses

// Scoped children — resolve within an element
row.staticText("title").assertTextContains("Inbox")
row.button("delete").tap()

// Controls
element.setSwitch(on: true)                 // toggles only if needed
element.toggle()                            // flips unconditionally, regardless of current state
element.adjustSlider(toNormalizedPosition: 0.75)   // iOS
element.adjustPicker(toValue: "March")             // iOS

// Editing
element.replaceText("new")        // clears, then types

// Multitouch (iOS)
element.pinch(scale: 2, velocity: 1)
element.rotate(.pi / 4, velocity: 1)
element.twoFingerTap()
```

### What an action checks for you

- **It gets the element into reach.** An element that exists but is off screen is
  scrolled to (one swipe of the screen's scroll container per attempt). If the
  keyboard or its accessory bar covers it, the keyboard is dismissed first, with
  the bar's Done or the keyboard's Done / Hide key, never Return. A lazy `List`
  row that isn't rendered yet still needs `scrollTo(in:)`.
- **It checks that a state change happened.** `setSwitch`, `toggle`,
  `replaceText` and `adjustPicker` read the element back. A switch that didn't
  flip gets one more tap on its trailing edge and then fails the test.
  `replaceText` accepts the field's own formatting ("2,000" for "2000").

All three can be switched off in `KassConfig` (`autoScroll`,
`dismissKeyboardWhenCovering`, `verifyActionOutcome`).

To compare values that change over time, read them from one snapshot:

```swift
let t = home.readTexts(["home.total", "home.account.EUR", "home.account.USD"])
```

### Failure diagnostics: "did you mean?"

A not-found failure appends a one-line snapshot of the element (`exists`,
`hittable`, `id`, `label`, `type`, `frame`) plus, when the locator was built
from an accessibility identifier that genuinely doesn't exist, the closest
matching identifiers and labels on screen, so a mistyped identifier shows its
likely fix in the failure itself:

```
KassiOS: text 'welcom' — assertVisible failed: does not exist
  ↳ element not found in the current hierarchy
  ↳ did you mean: 'welcome', 'Welcome!'?
```

Ranked by case-insensitive Levenshtein distance
(`KassIdentifierSuggestions.nearest(to:among:)`), bounded to a 400-element walk
of the current screen, and gated behind
`KassConfig.suggestSimilarIdentifiersOnFailure` (on by default — the walk only
runs once an assertion has already failed).

### Soft assertions: `verifyAll`

A test defaults to fail-fast: the first failed assertion stops the method, so
a red run only ever tells you about *one* mismatch. `verifyAll` is the
standard QA "soft assertion" / "verify-all" pattern for a screen-state check —
it runs every assertion in its scope to completion, so one run reports *all*
the mismatches at once:

```swift
verifyAll("account summary") {
    onScreen(AccountScreen.self) { screen in
        screen.balance.assertHasValue("$100.00")
        screen.name.assertLabel("Jane Doe")
        screen.avatar.assertVisible()
    }
}
```

If two of those three fail, the test still reports both — not just the first.
`verifyAll` restores the prior fail-fast setting once its scope ends, so
everything outside (or after) it is fail-fast again. It's the whole-screen
counterpart to `assertEach` below, which is the same soft-aggregate idea
scoped to a collection's rows.

## Flow primitives (Kaspresso-style)

Compose custom conditions out of throwing checks (`requireExists`,
`requireVisible`, `requireHittable`) with the same primitives Kaspresso offers:

```swift
// Retry a multi-step condition until it holds (or the budget elapses).
eventually { try banner.requireVisible(); try dismiss.requireHittable() }

// Assert something stays true for a duration (the inverse of flaky-safety).
continuously(during: 1.0) { try spinner.requireExists() }

// Pass if the UI is in any one of several valid states.
anyOf(
    KassBranch("logged in")  { try home.requireVisible() },
    KassBranch("needs 2FA")  { try otpField.requireVisible() }
)

// Attempts-bounded retry.
retry(times: 3) { try list.requireExists() }

device.pressBack()   // taps the leading navigation-bar button
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

// Deep assertions — catch pagination/leakage bugs a count alone misses
screen.cells().assertNoDuplicates()                  // by label, or pass `by:` for a custom key
screen.cells().assertEach("is money-in") { row in
    guard row.readLabel().contains("+") else { throw KassError("expected a money-in row") }
}
screen.cells().within(timeout: 5).assertNotEmpty()   // per-call timeout, like KassElement.within
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

### Discovery: `dumpIdentifiers`

A list of the elements on the current screen, with each one's identifier, type,
label and hittability, for writing `KassScreen` objects without reading
`debugDescription`:

```swift
let inventory = device.dumpIdentifiers()               // only real accessibility ids
device.dumpIdentifiers(includingUnidentified: true)     // + everything else, for discovery
device.attachIdentifierInventory()                      // same, + pretty JSON attached to the report
```

Each entry is a `Codable` `KassIdentifierInfo { identifier, type, label,
isHittable }`, read from one accessibility snapshot of the app (so `isHittable`
here means "on screen", not occlusion-aware); the walk is bounded (400 elements),
same as the "did you mean?" suggestions above.

### Relaunch with another locale, language or Dynamic Type size

Some device settings can't change while the app runs, so KassiOS relaunches it
with launch arguments. This works on the simulator and on real devices:

```swift
device.relaunch { $0.locale("de_DE").language("de") }
device.relaunch { $0.dynamicType("UICTContentSizeCategoryAccessibilityXL") }
```

## Device control: `kassios-agent`

Some things a test can't do from inside the simulator: grant permissions
without a dialog, freeze the status bar, set a location, send a push, switch
appearance, record the screen. They need `xcrun simctl`, which runs on the Mac.
`kassios-agent` is a small Mac process that the test talks to over `127.0.0.1`.
Start it before the tests:

```sh
kassios agent start      # in CI, or in the scheme's Test pre-action
```

It picks a random token for the run and writes it, with the port, to
`~/.kassios-agent.json` (mode 0600), where the test finds it. There's nothing to
configure.

```swift
try device.statusBar.freeze(time: "9:41", battery: 100, cellularBars: 4)
try device.location.set(latitude: 34.7071, longitude: 33.0226)
try device.appearance(.dark)
config = KassConfig(recordVideoOnFailure: true)   // .mp4 attached only on failure
```

Without the agent, or on a real device, each call skips the test with a message
instead of hanging. The full API, how the agent is locked down (loopback only, a
token on every request, a fixed set of `simctl` commands) and the CI and Xcode
setup are in the [Guide](Documentation/Guide.md#device-control-kassios-agent).

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

## Reports and failure artifacts

A failing test gets a screenshot of the screen at that moment and the full
accessibility tree attached to its result. With `recordVideoOnFailure` and the
agent running, it also gets a video of the simulator screen.

### Allure

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
For built-in idle waiting without EarlGrey, use `StabilizingSynchronizer`,
which settles once the accessibility tree stops changing — see
[Documentation/Guide.md](Documentation/Guide.md#synchronization-backends).

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

### Static lint: `kassios-lint`

The audit above runs at test time, on a live app. `kassios-lint` is its
compile-time twin: a SwiftSyntax linter that reads your screen-object *source*
and flags the same class of problems before you even launch the simulator —
`KassScreen` subclasses with no non-empty `onLoad` (**KAS001**) and element
builders whose identifier isn't a static string literal (**KAS002**).

It's built from a nested package at `Plugins/`, so swift-syntax never becomes a
dependency of the library. Run it with:

```sh
kassios lint MyApp/UITests            # informational; --strict fails on any finding
```

Add `kassios lint --strict UITests` to CI to keep every screen object
identifier-clean. From a checkout, `cd Plugins && swift run kassios-lint …` does
the same. See the DocC article *Static linting with kassios-lint*.

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

## Arranging state over HTTP: `KassHTTP`

When the app has an API, set the state up through it and check the UI, instead of
tapping through the whole flow first. Each call shows up in the report.

```swift
let api = KassHTTP(baseURL: URL(string: "http://localhost:8080")!,
                   headers: ["Authorization": "Bearer \(token)"])
api.post("/v1/transfers", json: ["from": "EUR", "amount": "100.00"], expect: 201)
let balance = api.get("/v1/accounts/EUR")["balance"]
```

## Mutation checks: `kassios-mutants`

If your app can switch defects on at launch (a debug flag, an environment
variable), `kassios-mutants` checks that each defect turns its tests red. A
defect that leaves its tests green is a hole in the suite.

```json
{
  "xcodebuild": ["-project", "App.xcodeproj", "-scheme", "AppUITests",
                 "-destination", "platform=iOS Simulator,name=iPhone 17"],
  "inject": "TEST_RUNNER_APP_DEFECTS",
  "mutants": {
    "successToastMissing": ["AppUITests/TransferTests/test_transfer_happyPath_completes"],
    "pnlSign": ["AppUITests/PortfolioValueTests/test_portfolio_tslaLoss_isRenderedAsLoss"]
  }
}
```

```sh
kassios mutants mutants.json --clean
```

Add `"action": "test-without-building"` and run `xcodebuild build-for-testing` once
first, so the defects don't each rebuild the project.

`--clean` first runs every listed test without a defect; they must pass, or a
"kill" proves nothing. Each defect then runs its tests with `inject` set to the
defect's id. The report lists survivors first, and the exit code is non-zero if
any defect survived.

`--parallel 3` runs three defects at once, each on its own clone of the
destination simulator; the clean run is split across them too. It needs
`test-without-building` (parallel builds would share one DerivedData). The
clones are deleted at the end, or on Ctrl-C. Tests that share state outside the
simulator, such as one backend server, can see each other's writes, so run those
sequentially.

Each run's log and result bundle are kept in `--log-dir`.

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

CI (`.github/workflows/ci.yml`) runs SwiftLint, the unit tests, the linter's own
tests and the UI tests on a simulator on every push and PR. `docs.yml` publishes
the DocC site to GitHub Pages. `release.yml` builds the host-side tools when a
release is published, attaches the zip to it and updates the Homebrew formula;
`Scripts/build-tools.sh <version>` does the same build locally.

## Status

1.9.0. The public API has followed [semantic versioning](https://semver.org)
since 1.0.0, and releases since then add to it (see the [changelog](CHANGELOG.md)).
CI runs SwiftLint, the unit tests and the UI tests on a simulator on every pull
request. Besides the bundled demo app, KassiOS has been run against Apple's
[Food Truck](https://github.com/apple/sample-food-truck) sample and is tested
against [ChaosBank](https://github.com/VadimToptunov/ChaosBank-iOS) by the
[ChaosBank ⨯ KassiOS](https://github.com/VadimToptunov/ChaosBank-KassiOS-Tests) suite.

## License

MIT — see [LICENSE](LICENSE).
