# Parameterized UI tests

Run one UI flow across many inputs — the data-driven testing Swift Testing gives
unit tests, but for XCUITest.

## Overview

Swift Testing's `@Test(arguments:)` is great for logic, but it doesn't drive an
app's UI. `parameterized(_:)` brings the same shape to KassiOS: one body, many
cases, each isolated so a failure in one doesn't hide the others.

```swift
func test_login_validation() {
    parameterized(["a@b.c", "bad-email", ""]) { email in
        relaunch()
        onScreen(LoginScreen.self) {
            $0.email.replaceText(email)
            $0.submit.tap()
        }
    }
}
```

Each case runs as its own activity in the Xcode report and its own step in the
structured report, labelled by the case value.

## Naming cases

Pass `name:` to turn a case into a readable label (otherwise its `description`
is used):

```swift
parameterized(
    [("", true), ("valid@example.com", false)],
    name: { $0.0.isEmpty ? "empty-email" : "valid-email" }
) { (email, expectsError) in
    relaunch()
    onScreen(LoginScreen.self) { login in
        if !email.isEmpty { login.email.typeText(email) }
        login.submit.tap()
        if expectsError {
            login.error.assertVisible()
        } else {
            onScreen(HomeScreen.self) { $0.welcome.assertVisible() }
        }
    }
}
```

## Reset between cases

UI state persists between cases — a form you filled in case 1 is still filled in
case 2. When cases aren't independent, reset inside the body. `relaunch()`
terminates and relaunches the app for a clean slate; for a cheaper reset, navigate
back or clear fields yourself.

## How isolation works

`parameterized` flips `continueAfterFailure` on for its duration, so every case
runs even after one fails, then restores it. Each case reports pass/fail
independently — you get the full matrix in one run, not a stop at the first red.

## When to reach for it

- Field validation across valid/invalid inputs.
- The same flow under several feature-flag or locale combinations (pair with
  `forEachLocale` for localized screenshots).
- Boundary values a single hand-written test would only spot-check.
