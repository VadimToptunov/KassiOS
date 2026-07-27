import XCTest
@testable import KassiOS

/// A minimal robot with no extra behavior — just enough to exercise the
/// `robot(_:)` factory in isolation.
private final class TrivialRobot: KassRobot {}

/// Exercises `KassTestCase.robot(_:)`. `setUp` is overridden to skip
/// `XCUIApplication` creation, which the factory doesn't need.
final class KassRobotTests: KassTestCase {

    override func setUp() {
        // Intentionally do not call super — avoids creating an XCUIApplication
        // in this unit-test context; the factory doesn't touch the app.
    }

    @MainActor
    func test_robotFactory_wiresBackTheSameTestCase() {
        let robot = robot(TrivialRobot.self)
        XCTAssertTrue(robot.test === self)
    }
}
