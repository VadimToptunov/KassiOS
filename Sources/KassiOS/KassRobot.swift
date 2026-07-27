import XCTest

/// Base class for the Robot layer — composite, cross-screen *actions*
/// ("sign in", "transfer money") that sit between ``KassScreen`` (locators for
/// one screen) and ``KassScenario`` (a whole reusable journey).
///
/// A robot method drives one or more screens and returns the next robot or
/// screen, so a test reads as a sequence of intents:
///
/// ```swift
/// final class LoginRobot: KassRobot {
///     @discardableResult
///     func signIn(_ email: String) -> HomeScreen {
///         test.onScreen(LoginScreen.self) { $0.email.typeText(email); $0.signIn.tap() }
///             .navigate(to: HomeScreen.self)
///     }
/// }
///
/// robot(LoginRobot.self).signIn("a@b.c").welcome.assertVisible()
/// ```
///
/// Optional — a single-screen test can keep using `onScreen` directly.
@MainActor
open class KassRobot {

    /// The test case this robot drives. Public so robot subclasses can reach
    /// anything on `KassTestCase` (`device`, `config`, `onScreen`, …) beyond the
    /// `step` forwarder below.
    public let test: KassTestCase

    public required init(_ test: KassTestCase) {
        self.test = test
    }

    /// Forwards to ``KassTestCase/step(_:_:)`` so robot methods can structure
    /// their own steps in the test report.
    public func step(_ name: String, _ block: @MainActor () -> Void) {
        test.step(name, block)
    }
}

public extension KassTestCase {

    /// Entry point for a robot chain, e.g.
    /// `robot(LoginRobot.self).signIn("a@b.c").welcome.assertVisible()`.
    @discardableResult
    func robot<R: KassRobot>(_ type: R.Type = R.self) -> R {
        R(self)
    }
}
