# Typed navigation & the Robot pattern

Make multi-screen tests read like a route — and fail fast when they go off it.

## Overview

Every screen object declares an "I have arrived" condition in
``KassScreen/onLoad``. `navigate(to:)` uses it: it asserts the landing screen
loaded before handing it back, so a test reads as the path a user takes and
fails the instant it doesn't land where expected — no acting on a screen that
isn't there yet.

```swift
onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
    .navigate(to: HomeScreen.self)   // waits for Home to load, returns it
    .welcome.assertVisible()
```

Put the navigating action in the `onScreen` block, then `navigate(to:)` verifies
and returns the destination. It types the rewind too — tap a Back button, then
name the screen you land back on:

```swift
onScreen(HomeScreen.self) { $0.backButton.tap() }
    .navigate(to: SettingsListScreen.self)   // typed rewind
```

This is **opt-in**. A one-screen test stays one screen simple — plain `onScreen`
still works; you reach for the fluent form only when a test spans screens.

## Automatic page-load verification

Declare what proves a screen arrived, and navigation waits on it:

```swift
final class HomeScreen: KassScreen {
    lazy var welcome = staticText("home.welcome")
    override var onLoad: [KassElement] { [welcome] }   // "I have arrived"
}
```

`navigate(to:)`/`proceed(to:)` (and `onScreen`) check every `onLoad` element
exists before proceeding — killing the class of races where a test taps the next
screen before it renders.

## The Robot pattern (optional layer)

Separate **what** the test does from **how** a screen is driven, so scenarios
survive UI refactors. KassiOS doesn't mandate it — layer it on the screen DSL
when a flow is reused:

```swift
struct LoginRobot {
    let test: KassTestCase
    @discardableResult
    func signIn(_ email: String) -> HomeScreen {
        test.onScreen(LoginScreen.self) { $0.email.typeText(email); $0.signIn.tap() }
            .navigate(to: HomeScreen.self)
    }
}

// A scenario reads intent-first; the screen details live in the robot.
LoginRobot(test: self).signIn("a@b.c").welcome.assertVisible()
```

Reusable, cross-test flows can also be packaged as a ``KassScenario``.
