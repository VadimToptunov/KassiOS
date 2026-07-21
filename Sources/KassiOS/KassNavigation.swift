import XCTest

public extension KassScreen {

    /// Typed, fluent navigation: assert the landing screen `S` has arrived (its
    /// ``KassScreen/onLoad`` elements exist) and return it — so a test reads as a
    /// route and fails fast, with a clear diagnostic, the moment it doesn't land
    /// where expected.
    ///
    /// ```swift
    /// onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
    ///     .navigate(to: HomeScreen.self)   // waits for HomeScreen to load
    ///     .welcome.assertVisible()
    /// ```
    ///
    /// Works both ways — tap a Back button, then `navigate(to: PreviousScreen.self)`
    /// to type the rewind. Opt-in: plain ``KassTestCase/onScreen(_:file:line:_:)``
    /// still works, so a one-screen test stays one screen simple. Chain it after
    /// `onScreen` (which opens the report); the destination screen must declare
    /// ``KassScreen/onLoad`` or there's nothing to verify arrival against.
    @discardableResult
    func navigate<S: KassScreen>(
        to type: S.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> S {
        let destination = String(describing: type)
        let screen = S(app: app, config: config)
        // Log the intent so a flat CI log carries the route next to any failure.
        config.logger.log("▶︎ Navigate to \(destination)")
        if screen.onLoad.isEmpty {
            config.logger.log("⚠️ \(destination).onLoad is empty — navigate(to:) can't verify arrival; add onLoad elements")
        }
        XCTContext.runActivity(named: "Navigate to \(destination)") { _ in
            for element in screen.onLoad {
                element.assertExists(file: file, line: line)
            }
        }
        return screen
    }
}
