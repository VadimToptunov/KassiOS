# ``KassiOS``

A UI-testing suite over XCUITest — readable screen objects, automatic waits,
built-in flaky-safety, and Kaspresso-style ergonomics, with zero external
dependencies.

## Overview

Swift Testing replaces XCTest for *unit* tests, but it does not drive an app's
UI — that is still XCUITest, and XCUITest still makes you manage timing by hand.
KassiOS is the suite on top: it bakes waiting and retries into every interaction,
so tests read like a script:

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

### Guides

- <doc:ComingFromKaspresso>
- <doc:WhyXCUITestFlakes>
- <doc:ParameterizedUITests>
- <doc:CIRecipe>

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

### Interceptors

- ``KassInterceptor``
- ``KassRetryInterceptor``
- ``KassActionContext``
- ``KassActionKind``

### Errors

- ``KassError``
