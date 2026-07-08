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

    @discardableResult
    func assertEnabled(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertEnabled", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isEnabled else { throw KassError("exists but is disabled") }
        }
    }

    @discardableResult
    func assertDisabled(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertDisabled", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard !element.isEnabled else { throw KassError("exists but is enabled") }
        }
    }

    @discardableResult
    func assertSelected(_ expected: Bool = true, file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertSelected(\(expected))", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isSelected == expected else {
                throw KassError("expected isSelected == \(expected) but was \(element.isSelected)")
            }
        }
    }

    /// Exact-match on the element's `value` (unlike `assertHasText`, which is a
    /// substring match against value-or-label). Useful for toggles/sliders/fields.
    @discardableResult
    func assertHasValue(_ expected: String, file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertHasValue('\(expected)')", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let actual = element.value as? String
            guard actual == expected else {
                throw KassError("expected value '\(expected)' but found '\(actual ?? "nil")'")
            }
        }
    }

    @discardableResult
    func assertLabel(_ expected: String, file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("assertLabel('\(expected)')", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.label == expected else {
                throw KassError("expected label '\(expected)' but found '\(element.label)'")
            }
        }
    }

    /// Waits until the element is gone (or already absent). Reads better than
    /// `assertNotExists` at a call site that expects a disappearance.
    @discardableResult
    func waitUntilGone(file: StaticString = #file, line: UInt = #line) -> KassElement {
        assertNotExists(file: file, line: line)
    }

    // MARK: - Gestures

    @discardableResult
    func doubleTap(file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("doubleTap", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.doubleTap()
        }
    }

    @discardableResult
    func longPress(forDuration duration: TimeInterval = 1.0, file: StaticString = #file, line: UInt = #line) -> KassElement {
        perform("longPress(\(duration)s)", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.press(forDuration: duration)
        }
    }

    @discardableResult
    func swipeUp(file: StaticString = #file, line: UInt = #line) -> KassElement { swipe(.up, file: file, line: line) }
    @discardableResult
    func swipeDown(file: StaticString = #file, line: UInt = #line) -> KassElement { swipe(.down, file: file, line: line) }
    @discardableResult
    func swipeLeft(file: StaticString = #file, line: UInt = #line) -> KassElement { swipe(.left, file: file, line: line) }
    @discardableResult
    func swipeRight(file: StaticString = #file, line: UInt = #line) -> KassElement { swipe(.right, file: file, line: line) }

    private func swipe(_ direction: KassScrollDirection, file: StaticString, line: UInt) -> KassElement {
        perform("swipe(\(direction))", file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            switch direction {
            case .up: element.swipeUp()
            case .down: element.swipeDown()
            case .left: element.swipeLeft()
            case .right: element.swipeRight()
            }
        }
    }

    /// Scrolls `container` in `direction` until this element becomes hittable,
    /// or the shared time budget (`config.timeout`) elapses. Each attempt draws
    /// from that budget, so scrolling can't compound into a runaway timeout.
    @discardableResult
    func scrollTo(
        in container: KassElement,
        direction: KassScrollDirection = .up,
        file: StaticString = #file,
        line: UInt = #line
    ) -> KassElement {
        config.reporter?.stepStarted("scrollTo \(description)")
        do {
            try Waiter.retry(
                timeout: config.timeout,
                pollInterval: config.pollInterval,
                enabled: config.flakySafetyEnabled
            ) {
                let target = resolve()
                if target.exists && target.isHittable { return }
                let scroll = container.resolve()
                guard scroll.exists else {
                    throw KassError("scroll container \(container.description) does not exist")
                }
                switch direction {
                case .up: scroll.swipeUp()
                case .down: scroll.swipeDown()
                case .left: scroll.swipeLeft()
                case .right: scroll.swipeRight()
                }
                throw KassError("not visible yet after scrolling \(direction)")
            }
            config.reporter?.stepFinished(status: .passed, message: nil)
        } catch {
            config.reporter?.stepFinished(status: .failed, message: "\(error)")
            let message = "KassiOS: \(description) — scrollTo failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
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
        config.reporter?.stepStarted("\(name) \(description)")
        do {
            try Waiter.retry(
                timeout: config.timeout,
                pollInterval: config.pollInterval,
                enabled: config.flakySafetyEnabled
            ) {
                try body(resolve())
            }
            config.reporter?.stepFinished(status: .passed, message: nil)
        } catch {
            config.reporter?.stepFinished(status: .failed, message: "\(error)")
            let message = "KassiOS: \(description) — \(name) failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }
}

/// Direction for swipes and `scrollTo`.
public enum KassScrollDirection {
    case up, down, left, right
}
