import XCTest

/// A lazy, self-waiting wrapper around `XCUIElement`.
///
/// The underlying element is **re-resolved on every attempt** via `resolve`,
/// not cached. That is deliberate: after the view hierarchy reloads, a cached
/// `XCUIElement` goes stale and interactions fail spuriously. Re-resolving is
/// what lets flaky-safety actually recover.
public struct KassElement {

    let resolve: () -> XCUIElement
    let description: String
    let config: KassConfig

    init(description: String, config: KassConfig, resolve: @escaping () -> XCUIElement) {
        self.description = description
        self.config = config
        self.resolve = resolve
    }
}

// MARK: - Interactions (all chainable, all self-waiting)

public extension KassElement {

    @discardableResult
    func tap(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("tap", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.tap()
        }
    }

    @discardableResult
    func typeText(_ text: String, file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("typeText('\(text)')", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.tap()
            element.typeText(text)
        }
    }

    @discardableResult
    func clearText(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("clearText", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard let value = element.value as? String else { throw KassError("has no text value to clear") }
            element.tap()
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            element.typeText(deletes)
        }
    }

    @discardableResult
    func assertVisible(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertVisible", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            // Non-interactive elements (e.g. staticText labels) are frequently on
            // screen yet report `isHittable == false`. Treat a rendered, non-empty
            // frame as visible too, so assertions on labels don't flake.
            guard element.isHittable || !element.frame.isEmpty else {
                throw KassError("exists but is not visible")
            }
        }
    }

    @discardableResult
    func assertExists(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertExists", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
        }
    }

    @discardableResult
    func assertNotExists(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertNotExists", file: file, line: line) { element in
            guard !element.exists else { throw KassError("still exists") }
        }
    }

    @discardableResult
    func assertHasText(_ expected: String, file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertHasText('\(expected)')", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let actual = (element.value as? String) ?? element.label
            guard actual.contains(expected) else {
                throw KassError("expected text containing '\(expected)' but found '\(actual)'")
            }
        }
    }

    /// Escape hatch for anything not yet wrapped. Runs `body` under the same
    /// flaky-safety and logging as the built-in interactions.
    @discardableResult
    func perform(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line,
        _ body: @escaping (XCUIElement) throws -> Void
    ) -> KassElement {
        do {
            try Waiter.retry(
                timeout: config.timeout,
                pollInterval: config.pollInterval,
                enabled: config.flakySafetyEnabled
            ) {
                try body(resolve())
            }
        } catch {
            let message = "KassiOS: \(description) — \(name) failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }
}
