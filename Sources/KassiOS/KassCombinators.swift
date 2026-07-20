import XCTest

@MainActor
public extension KassTestCase {

    /// Builds the interceptor context for a wait-combinator.
    private func combinatorContext(_ name: String, timeout: TimeInterval?, file: StaticString, line: UInt) -> KassActionContext {
        KassActionContext(
            kind: .wait,
            name: name,
            elementDescription: name,
            identifier: nil,
            timeout: timeout ?? config.timeout,
            pollInterval: config.pollInterval,
            flakySafetyEnabled: config.flakySafetyEnabled,
            file: file,
            line: line
        )
    }

    /// Waits until any of `elements` exists and returns its index (or fails).
    /// Handy when a tap can lead to one of several screens.
    @discardableResult
    func waitForAny(
        _ elements: [KassElement],
        timeout: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int? {
        do {
            var found: Int?
            try KassInterceptorChain.run(
                config.interceptors,
                context: combinatorContext("waitForAny(\(elements.count))", timeout: timeout, file: file, line: line)
            ) {
                self.config.synchronizer.waitForIdle(timeout: self.config.timeout)
                for (index, element) in elements.enumerated() where element.resolve().exists {
                    found = index
                    return
                }
                throw KassError("none of \(elements.count) elements appeared")
            }
            return found
        } catch {
            config.logger.log("❌ waitForAny failed: \(error)")
            XCTFail("waitForAny failed: \(error)", file: file, line: line)
            return nil
        }
    }

    /// Waits until every element in `elements` exists (or fails).
    func waitForAll(
        _ elements: [KassElement],
        timeout: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try KassInterceptorChain.run(
                config.interceptors,
                context: combinatorContext("waitForAll(\(elements.count))", timeout: timeout, file: file, line: line)
            ) {
                self.config.synchronizer.waitForIdle(timeout: self.config.timeout)
                for element in elements where !element.resolve().exists {
                    throw KassError("\(element.description) not present yet")
                }
            }
        } catch {
            config.logger.log("❌ waitForAll failed: \(error)")
            XCTFail("waitForAll failed: \(error)", file: file, line: line)
        }
    }

    /// Asserts the screen's `onLoad` elements are visible, without entering a
    /// block. Reads well as a mid-test checkpoint: `assertOnScreen(HomeScreen.self)`.
    @discardableResult
    func assertOnScreen<S: KassScreen>(
        _ type: S.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> S {
        let screen = S(app: app, config: config)
        XCTContext.runActivity(named: "Assert on \(String(describing: type))") { _ in
            for element in screen.onLoad {
                element.assertExists(file: file, line: line)
            }
        }
        return screen
    }

    /// Interact with the app's frontmost alert.
    func alert() -> KassAlert {
        KassAlert(app: app, config: config)
    }
}

/// A thin handle over the frontmost `UIAlertController`-style alert.
@MainActor
public struct KassAlert {

    let app: XCUIApplication
    let config: KassConfig

    private func button(_ title: String) -> KassElement {
        KassElement(description: "alert button '\(title)'", config: config) { [app] in
            app.alerts.buttons[title].firstMatch
        }
    }

    @discardableResult
    public func assertExists(file: StaticString = #filePath, line: UInt = #line) -> KassAlert {
        KassElement(description: "alert", config: config) { [app] in app.alerts.firstMatch }
            .assertExists(file: file, line: line)
        return self
    }

    @discardableResult
    public func tap(_ buttonTitle: String, file: StaticString = #filePath, line: UInt = #line) -> KassAlert {
        button(buttonTitle).tap(file: file, line: line)
        return self
    }
}
