# Coming from Kaspresso

Map the Kaspresso/Kakao concepts you already know onto KassiOS.

## Overview

[Kaspresso](https://github.com/KasperskyLab/Kaspresso) is the de-facto UI-testing
framework on Android: Kakao screen objects, `flakySafely` retries, `step`
sections, interceptors, and a `device` facade. KassiOS brings the same shape to
iOS on top of XCUITest. Most of your muscle memory transfers directly — the names
were chosen to match.

## The one-to-one map

| Kaspresso / Kakao | KassiOS | Notes |
| --- | --- | --- |
| `TestCase` / `BaseTestCase` | ``KassTestCase`` | Subclass it instead of `XCTestCase`. |
| Shared `BaseTestCase` config | ``KassSuite`` | Override `configure()` once per suite. |
| `Screen` (Kakao) | ``KassScreen`` | `onLoad` lists the elements that prove the screen loaded. |
| `KView` / matched view | ``KassElement`` | Re-resolves each attempt — no stale references. |
| `flakySafely { }` | `flakySafely { }` | Same name; one shared time budget. |
| `continuously { }` | `continuously(during:)` | Asserts a condition holds for a duration. |
| `compose { }` | `compose(_:)` | Passes if any branch succeeds. |
| `step("…") { }` | `step("…") { }` | Groups actions in the report. |
| `scenario(…)` | ``KassScenario`` | Reusable, named flows. |
| `device` facade | ``KassDevice`` (`device`) | Permissions, keyboard, screenshots, deep links. |
| Allure integration | ``AllureReporter`` | Plus a ``KassReporter`` seam for JUnit and custom sinks. |

## A test, side by side

Kaspresso (Kotlin):

```kotlin
class LoginTest : TestCase() {
    @Test fun login() = run {
        step("Open login") { LoginScreen { email { typeText("a@b.c") } } }
        step("Submit") { LoginScreen { submit { click() } } }
    }
}
```

KassiOS (Swift):

```swift
final class LoginTests: KassTestCase {
    func test_login() {
        launch()
        step("Open login") {
            onScreen(LoginScreen.self) { $0.email.typeText("a@b.c") }
        }
        step("Submit") {
            onScreen(LoginScreen.self) { $0.submit.tap() }
        }
    }
}
```

## What is different on iOS

- **Out-of-process.** XCUITest drives the app from a separate process, so KassiOS
  can't reach into your view models the way an in-process Espresso/Kaspresso test
  can. Prefer accessibility identifiers and launch arguments to set up state.
- **Network stubbing.** Link `KassiOSStubs` in the app (debug) and drive it from
  the test with `launch(networkStubs: [.json(urlContains:body:)])` or
  `launch(offline: true)` — an in-process `URLProtocol` replays responses (or
  fails offline), deterministically. (The older `launch(stubs:)` sets `KASS_STUB_*`
  env for the app to interpret itself.)
- **Interceptors.** KassiOS has the Kaspresso-style chain: every action flows
  through `KassConfig.interceptors`, with a reorderable `KassRetryInterceptor`
  plus `KassLoggingInterceptor` and `KassSystemAlertInterceptor`.

## What transfers unchanged

Strict accessibility-identifier enforcement (``KassIdentifierPolicy``), the
accessibility audit (`assertNoAccessibilityIssues`), parameterized runs
(`parameterized`), and Allure reporting all behave the way you expect coming
from Kaspresso.
