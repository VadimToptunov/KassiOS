import XCTest

/// Composite login flow lived here instead of the test body, showing the
/// ``KassRobot`` layer sitting between ``KassScreen`` (locators) and
/// ``KassScenario`` (whole journeys).
final class LoginRobot: KassRobot {
    @discardableResult
    func signIn(_ email: String) -> HomeScreen {
        // Wrapped in a robot-owned `step` (also exercises the `step` forwarder).
        step("Sign in as \(email)") {
            _ = test.onScreen(LoginScreen.self) { $0.email.typeText(email); $0.signIn.tap() }
        }
        return test.onScreen(HomeScreen.self) { _ in }
    }
}

/// Phase 8: the robot layer. `robot(_:)` composes actions across screens so
/// the test body stays a one-liner.
final class RobotTests: KassTestCase {

    func test_robot_composesLoginFlow() {
        launch()
        robot(LoginRobot.self).signIn("a@b.c").welcome.assertVisible()
    }
}
