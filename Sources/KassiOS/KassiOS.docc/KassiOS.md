# ``KassiOS``

A tiny, batteries-included DSL over XCUITest — readable screen objects, automatic
waits, built-in flaky-safety, and Kaspresso-style ergonomics, with zero external
dependencies.

## Overview

Raw XCUITest makes you manage timing by hand. KassiOS bakes waiting and retries
into every interaction, so tests read like a script:

```swift
final class LoginFlowUITests: KassTestCase {
    func test_login() {
        launch()
        onScreen(LoginScreen.self) { login in
            login.email.typeText("test@example.com")
            login.password.typeText("secret")
            login.loginButton.tap()
        }
        onScreen(HomeScreen.self) { home in
            home.welcome.assertVisible()
        }
    }
}
```

Every ``KassElement`` interaction re-resolves its underlying `XCUIElement` and
retries under one shared time budget (``Waiter``), so tests survive view-hierarchy
reloads without `waitForExistence`, `sleep`, or stale references.

For a full prose walkthrough see the
[Guide](https://github.com/VadimToptunov/KassiOS/blob/main/Documentation/Guide.md).

## Topics

### Writing tests

- ``KassTestCase``
- ``KassSuite``
- ``KassRunBuilder``
- ``KassScenario``
- ``KassBranch``

### Screens & elements

- ``KassScreen``
- ``KassElement``
- ``KassElementCollection``
- ``KassScrollDirection``

### Configuration

- ``KassConfig``
- ``KassIdentifierPolicy``

### Reporting

- ``KassReporter``
- ``AllureReporter``
- ``KassStepStatus``
- ``KassLogger``
- ``ConsoleKassLogger``

### Synchronization

- ``KassSynchronizer``
- ``NoOpSynchronizer``

### Errors

- ``KassError``
