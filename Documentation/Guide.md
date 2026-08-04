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
- [Device control: kassios-agent (Tier C)](#device-control-kassios-agent-tier-c)
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
.package(url: "https://github.com/VadimToptunov/KassiOS.git", from: "1.4.0")
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
generic `element(_:type:)`. Resolution is **id-first**: it matches the real
accessibility identifier when one exists, and only falls back to XCUITest's
label-matching subscript when it doesn't — with `firstMatch`, so an ambiguous
id takes the first hit rather than crashing.

Type-agnostic and multi-attribute builders, for the common cases a bare id
misses:

```swift
element("checkout.confirm")                       // any element type, id-first
element(id: "sheet.title", label: "Confirm")       // id AND label — disambiguates
                                                    // SwiftUI's container-id propagation
button(id: "sheet.title", label: "Confirm")        // same, scoped to .button

staticText(containing: "Welcome")                  // label substring, case-insensitive
button(containing: "Sign In")                      // same, scoped to .button
element(labelContains: "Welcome")                  // same, any type
```

`staticText(containing:)`/`button(containing:)`/`element(labelContains:)` are
intentional label matching (dialogs/toasts/rows identified by their text), so
they never trigger the identifier-policy warning — there's no expected id to
miss.

Escape hatches when identifiers aren't enough:

```swift
lazy var banner = custom("promo banner") { app.otherElements["promo"].firstMatch }
```

Reach *into* an element with scoped children:

```swift
row.staticText("title").assertTextContains("Inbox")   // resolves within `row`
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
element.toggle()                        // flips unconditionally, regardless of current state
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

// The same, for a whole screen scope — every element built inside inherits it
onScreen(SlowScreen.self, timeout: 30) { screen in
    screen.title.assertVisible()
    screen.content.assertVisible()
}

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
element.assertTextContains("partial")   // substring of value-or-label (was `assertHasText`, now deprecated)
element.assertHasValue("exact")         // exact match on .value
element.assertLabel("exact")
element.assertLabelContains("part")
element.assertValueMatches("^\\d{4}$")   // regex on value-or-label

element.assertPlaceholder("Email")
element.waitUntil("is selected") { $0.isSelected }
```

Every assertion waits up to `config.timeout` before failing, and reports a
readable reason (`KassiOS: button 'login_submit' — assertVisible failed: …`).

### Deep assertions

Presence-only checks miss real defects — a rounded/mis-formatted amount, a
row that leaked into a filtered list, a toast that comes and goes before a
slower poll would see it. These go past "it exists":

```swift
// Numeric closeness — for money/math where an exact string match is wrong
// (rounding, formatting, locale: "$92.50" vs. 92.5).
element.assertValue(closeTo: 92.5, tolerance: 0.01)
element.readNumber()   // Double?, non-waiting, locale-aware parse of value-or-label

// Transient — passes the instant the element is *ever* seen inside the
// window, instead of waiting the full budget for it to be hittable now.
// For a success toast that appears then auto-dismisses.
toast.assertAppears(within: 2)
```

### Soft assertions: `verifyAll`

By default a test is fail-fast — `continueAfterFailure = false` — so the first
failed assertion stops the method and a red run only ever surfaces *one*
mismatch. `KassTestCase.verifyAll(_:_:)` is the standard QA "soft assertion" /
"verify-all" pattern: it flips `continueAfterFailure` on for its scope, runs
`block` to completion, then restores the prior setting — so one run reports
*every* mismatch on a screen instead of stopping at the first:

```swift
verifyAll("account summary") {
    onScreen(AccountScreen.self) { screen in
        screen.balance.assertHasValue("$100.00")
        screen.name.assertLabel("Jane Doe")
        screen.avatar.assertVisible()
    }
}
```

If the balance and the avatar are both wrong, the test still reports both
failures — the name check in between still ran too. Contrast this with the
default fail-fast behavior (everywhere else) and with `assertEach` below,
which is the same soft-aggregate idea but scoped to a collection's rows;
`verifyAll` is the whole-screen equivalent.

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

screen.cells().matching(label: "Settings").first.tap()   // was `elementMatching(label:)`, now deprecated

// Iterate live matches
screen.cells().forEach { $0.assertExists() }
let labels = screen.staticTexts().map { $0 }

// Deep assertions — a bare count misses a duplicated or leaked row
screen.cells().assertNoDuplicates()                    // by label; pass `by:` for a custom key
screen.cells().assertNoDuplicates(by: { $0.readValue() ?? "" })
screen.cells().assertEach("is money-in") { row in
    guard row.readLabel().contains("+") else { throw KassError("expected a money-in row") }
}
screen.cells().within(timeout: 5).assertNotEmpty()     // per-call timeout override, like `KassElement.within`
```

`assertEach` aggregates **every** failing row into a single failure message
instead of stopping at the first, so a coding agent (or you) sees the whole
picture at once.

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
eventually { try banner.requireVisible(); try dismiss.requireHittable() }

// Assert something stays true for a duration (inverse of flaky-safety).
continuously(during: 1.0) { try spinner.requireExists() }

// Pass if the UI is in any one of several valid states.
anyOf(
    KassBranch("logged in") { try home.requireVisible() },
    KassBranch("needs 2FA") { try otp.requireVisible() }
)

// Attempts-bounded retry.
retry(times: 3) { try list.requireExists() }

device.pressBack()   // taps the leading navigation-bar button

// Wait for any / all, and mid-test screen checkpoints
let which = waitForAny([home.welcome, login.error])   // index of the first to appear
waitForAll([toolbar, list])
assertOnScreen(HomeScreen.self)

// App alerts
home.showAlert.tap()
alert().assertExists().tap("OK")
```

`eventually` / `retry` return the block's value (as an optional, `nil` on
failure), so they compose:

```swift
let count = eventually { screen.cells().count } ?? 0
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

## Device control: `kassios-agent` (Tier C)

The `device` helpers above and `kass-simctl.sh` cover most needs, but some things
a test genuinely can't do from inside the simulator — grant permissions without a
dialog, freeze the status bar, set location, push a notification, flip appearance,
record video — because `xcrun simctl` is a **host-side** command and the XCUITest
process lives on the simulator and can't shell out. `kassios-agent` bridges that
gap: a tiny Mac process the in-simulator test talks to over `localhost`.

```swift
try device.permissions.grant(.location, for: "com.example.App")
try device.statusBar.freeze(time: "9:41", battery: 100, cellularBars: 4) // deterministic screenshots
try device.location.set(latitude: 34.7071, longitude: 33.0226)
try device.appearance(.dark)
try device.push(payloadJSON: #"{"aps":{"alert":"Hi"}}"#, to: "com.example.App")
```

Each call **`XCTSkip`s with an actionable message** — never hangs — when no agent
is running or on a real device, so a suite without the agent still goes green.

### Video on failure

With the agent running, opt into a **screen recording** that attaches to the
report only when a test fails — the artifact you actually want when a CI-only
flake needs debugging:

```swift
config = KassConfig(recordVideoOnFailure: true)
```

KassiOS records the simulator screen for the test (via the agent's
`simctl io recordVideo`) and, on failure, attaches the `.mp4` to the `.xcresult`;
a passing test discards it. Drive it by hand with `try device.startRecording()` /
`let mp4 = try device.stopRecording()` if you want a clip of a specific stretch.
Best-effort and simulator-only — no agent means a silent no-op, never a hang.

### Security posture

The agent shells out to the host, so it's built to be treated like it:

- **Loopback only.** Binds `127.0.0.1`, never `0.0.0.0`.
- **Token-authenticated.** A per-run token is required on every request (checked
  in constant time); unauthorized requests are refused before anything runs.
- **Allowlisted.** It maps a fixed command set to `simctl` and **never** forwards
  arbitrary argv or runs through a shell. Screen recording is no exception — the
  agent picks the output path itself; the client never supplies a filename.
- **Per-device.** Every command carries the target `SIMULATOR_UDID`, so parallel
  runs across simulators don't cross wires.
- **Bounded.** Each connection has a receive timeout; it can't be stalled by an
  unauthenticated peer.

On startup the agent writes its port + token to `~/.kassios-agent.json` (mode
`0600`); the in-simulator test discovers it via `$SIMULATOR_HOST_HOME` — the one
channel that actually reaches the XCUITest runner process.

### Running it in CI

Build and start the agent before the UI-test step; nothing else to wire up:

```bash
swift build --product kassios-agent
KASSIOS_AGENT_TOKEN="$(uuidgen)" KASSIOS_AGENT_PORT=8437 \
  nohup .build/debug/kassios-agent >agent.log 2>&1 &
sleep 2

xcodebuild test -scheme MyAppUITests -destination '…'
```

The agent is a **separate product** — the core library depends on nothing new,
and test targets that don't want the bridge don't build it.

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

### Pseudolocalization & RTL

Find localization bugs without a translator. `runPseudolocalized` relaunches with
doubled string lengths (surfacing truncation and layout overflow) and non-localized
strings uppercased (surfacing hardcoded text), then runs your flow:

```swift
func test_pseudo() {
    runPseudolocalized {
        onScreen(HomeScreen.self) { $0.title.assertVisible() }
        device.screenshot("home-pseudo")   // eyeball truncation/overflow
    }
}

// Force right-to-left layout regardless of language:
runPseudolocalized(rightToLeft: true) { … }
```

The same toggles are on the `relaunch` builder if you want them alongside a real
locale — `device.relaunch { $0.language("de").doubleLengthStrings().rightToLeft() }`.
All launch-argument based, so they work on the simulator and real devices.

## Synchronization backends

By default KassiOS polls (via `Waiter`). Plug in a `KassSynchronizer` to also
block until the app is *idle* (animations, network, main-queue work):

```swift
config = KassConfig(synchronizer: EarlGreySynchronizer())
```

The core ships `NoOpSynchronizer` and stays dependency-free; an EarlGrey-backed
adapter is an opt-in reference in `Examples/EarlGreySynchronizer.swift`.

### `StabilizingSynchronizer` — built-in idle waiting, no EarlGrey

`StabilizingSynchronizer` settles on a quiet accessibility tree without any
external dependency: it polls a cheap signature of the tree and returns once
the signature has held steady for `stableFor`, or `timeout` elapses:

```swift
config = KassConfig(synchronizer: StabilizingSynchronizer(
    stableFor: 0.1,      // must be unchanged this long to count as settled
    pollInterval: 0.05   // delay between polls
))
```

Reach for it when:
- You want stronger flaky-safety than pure polling but can't/don't want to
  link EarlGrey.
- Your screens animate or reflow between an action and the next assertion.

Stick with `NoOpSynchronizer` (the default) when your screens are simple and
`Waiter`'s retrying already covers you — the extra polling has a small cost.
Reach for `EarlGreySynchronizer` instead when you already depend on EarlGrey
and want its in-process run-loop draining rather than tree-diffing.

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
    accessibilityIdentifierPolicy: .warn,    // .ignore / .enforce (see below)
    captureScreenshotOnFailure: true         // attach a screenshot on failure
)
```

Set it in `setUp` after `super.setUp()`; the reporter starts lazily on first use,
so a config assigned there is already in place.

---

## Enforcing accessibility identifiers

Tests are only as stable as the app's element identity. Resolution is
**id-first** — every id-based builder matches the real accessibility identifier
first, and only falls back to XCUITest's label-matching subscript when no
element carries that identifier. The identifier policy governs what happens
when that fallback fires, and **pushes the app team to add real accessibility
identifiers**:

- `.warn` (default) — log a message and add an Xcode activity, but let the test pass.
- `.ignore` — say nothing.
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

## Identifier inventory (discovery)

`device.dumpIdentifiers(includingUnidentified:)` walks the current screen once
(bounded to 400 elements) and returns every element's identity as a `Codable`
`KassIdentifierInfo { identifier, type, label, isHittable }` — the same shape a
coding agent needs to scaffold `KassScreen` objects, or to discover what's
actually on screen instead of guessing at ids:

```swift
let inventory = device.dumpIdentifiers()               // real accessibility ids only
device.dumpIdentifiers(includingUnidentified: true)     // + label-only elements too
device.attachIdentifierInventory()                      // same, + pretty JSON on the report
```

`attachIdentifierInventory` hands the inventory to the report as
pretty-printed, sorted-key JSON (`JSONEncoder().outputFormatting =
[.prettyPrinted, .sortedKeys]`) — attach it whenever you want an artifact an
agent can read back to scaffold or fix a suite.

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

### Did you mean? — similar-identifier suggestions

When a locator built from an accessibility identifier (`button("home.welcom")`,
say) fails because the element genuinely doesn't exist, the failure message
appends the closest actual identifiers/labels found on screen — a self-correct
for a wrong-id guess, the kind an AI author makes constantly:

```
KassiOS: text 'welcom' — assertVisible failed: does not exist
  ↳ element not found in the current hierarchy
  ↳ did you mean: 'welcome', 'Welcome!'?
```

The candidates come from one bounded walk of the current screen (same 400-
element cap as the identifier inventory above); ranking is case-insensitive
Levenshtein distance via `KassIdentifierSuggestions.nearest(to:among:)`, capped
so an unrelated element on screen never gets suggested. Wired into
`KassElement.perform`, `scrollTo` and `softScrollTo`; gate it off with
`KassConfig(suggestSimilarIdentifiersOnFailure: false)` if you'd rather not pay
even the once-per-failure walk.

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
        KassConfig(timeout: 20, reporter: AllureReporter(), accessibilityIdentifierPolicy: .enforce)
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
  steps, scenarios, `anyOf`/`continuously`, flaky-safety with a shared budget,
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
