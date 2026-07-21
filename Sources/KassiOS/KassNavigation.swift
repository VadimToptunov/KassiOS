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
    /// still works, so a one-screen test stays one screen simple.
    @discardableResult
    func navigate<S: KassScreen>(
        to type: S.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> S {
        let screen = S(app: app, config: config)
        XCTContext.runActivity(named: "Navigate to \(String(describing: type))") { _ in
            for element in screen.onLoad {
                element.assertExists(file: file, line: line)
            }
        }
        return screen
    }
}
