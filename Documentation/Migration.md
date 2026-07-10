# Migrating from raw XCUITest

KassiOS is a thin layer over XCUITest — you can adopt it incrementally, one
screen at a time. `app` is always available on a `KassTestCase`, so raw XCUITest
and KassiOS can coexist in the same test.

## The pattern map

| Raw XCUITest | KassiOS |
| --- | --- |
| `XCTAssertTrue(app.buttons["id"].waitForExistence(timeout: 10))` | `screen.button.assertExists()` |
| `let el = app.textFields["id"]; el.tap(); el.typeText("x")` | `screen.field.typeText("x")` |
| clear field by hand (select-all + delete) | `screen.field.replaceText("x")` |
| `app.buttons["id"].tap()` (+ manual wait) | `screen.button.tap()` |
| `XCTAssertEqual(el.label, "x")` | `screen.el.assertLabel("x")` |
| `XCTAssertTrue(el.isHittable)` | `screen.el.assertVisible()` |
| `while !el.isHittable { app.swipeUp() }` | `row.scrollTo(in: list)` |
| ad-hoc page-object structs | `KassScreen` subclasses with `onLoad` |
| manual `waitForExistence` everywhere | built-in flaky-safety (shared budget) |
| `add(XCTAttachment(screenshot:))` | `device.screenshot("name")` |
| `addUIInterruptionMonitor { … }` | `device.autoAllowSystemDialogs(test:)` |
| repeating a test with different inputs | `parameterized([...]) { … }` |

## Step by step

1. **Change the base class.** `class LoginTests: XCTestCase` → `class LoginTests:
   KassTestCase`. Everything still compiles; `app` is there.

2. **Wrap one screen.** Turn a page-object into a `KassScreen`:

   ```swift
   final class LoginScreen: KassScreen {
       lazy var email = textField("login_email")
       lazy var submit = button("login_submit")
       override var onLoad: [KassElement] { [email, submit] }
   }
   ```

   Not sure which identifiers exist? Generate the screen from the live tree:
   `printScreenScaffold("LoginScreen")` (see the Guide).

3. **Replace waits with interactions.** Delete `waitForExistence` /
   `XCTAssertTrue(...exists)` and use `tap()` / `typeText()` / `assert*()` — they
   wait and retry for you.

4. **Group with `onScreen` / `step`.** Wrap actions so the report reads like a
   script and screenshots-on-failure land automatically.

5. **Adopt the extras as needed** — collections, flow primitives
   (`flakySafely`/`compose`), Allure export, strict accessibility identifiers.

## Coexistence

Anything not yet wrapped stays raw XCUITest via `app`, or use the escape hatches:

```swift
let banner = custom("promo") { app.otherElements["promo"].firstMatch }
element.perform("custom") { xcui in xcui.tap() }
```

Migrate the rest whenever it's convenient — there's no all-or-nothing switch.
