import XCTest

/// A lazy, self-waiting wrapper around `XCUIElement`.
///
/// The underlying element is **re-resolved on every attempt** via `resolve`,
/// not cached. That is deliberate: after the view hierarchy reloads, a cached
/// `XCUIElement` goes stale and interactions fail spuriously. Re-resolving is
/// what lets flaky-safety actually recover.
@MainActor
public struct KassElement {

    let resolve: () -> XCUIElement
    let description: String
    let config: KassConfig

    /// The identifier this element was *asked* to resolve by, if any. Used by
    /// strict mode to verify the app actually set an accessibility identifier.
    let expectedIdentifier: String?

    init(
        description: String,
        config: KassConfig,
        expectedIdentifier: String? = nil,
        resolve: @escaping () -> XCUIElement
    ) {
        self.description = description
        self.config = config
        self.expectedIdentifier = expectedIdentifier
        self.resolve = resolve
    }
}

// MARK: - Interactions (all chainable, all self-waiting)

public extension KassElement {

    @discardableResult
    func tap(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("tap", kind: .tap, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.tap()
        }
    }

    @discardableResult
    func typeText(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("typeText('\(text)')", kind: .type, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.tap()
            element.typeText(text)
        }
    }

    /// Clears the field by sending one delete per character of the current
    /// `value`. Known limitation: for secure fields and formatted inputs (phone,
    /// card, currency) the `value` length may not equal the number of deletes
    /// needed, so clearing can be incomplete — verify with `assertHasValue("")`
    /// or clear it in the app for those.
    @discardableResult
    func clearText(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("clearText", kind: .clear, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard let value = element.value as? String else { throw KassError("has no text value to clear") }
            element.tap()
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            element.typeText(deletes)
        }
    }

    /// Strict visibility: the element exists and is hittable (on screen and
    /// interactable). An element scrolled off screen is *not* hittable, so this
    /// cannot go falsely green on it. For non-interactive elements (e.g. some
    /// `staticText` labels) that render but aren't hittable, use `assertPresent`.
    @discardableResult
    func assertVisible(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertVisible", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable/on-screen") }
        }
    }

    /// Softer than `assertVisible`: the element exists in the hierarchy and has a
    /// non-empty frame. It does **not** guarantee the element is on screen — use
    /// it for rendered-but-not-hittable labels; prefer `assertVisible` otherwise.
    @discardableResult
    func assertPresent(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertPresent", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard !element.frame.isEmpty else { throw KassError("exists but has an empty frame") }
        }
    }

    @discardableResult
    func assertExists(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertExists", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
        }
    }

    @discardableResult
    func assertNotExists(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertNotExists", kind: .assert, file: file, line: line) { element in
            guard !element.exists else { throw KassError("still exists") }
        }
    }

    @discardableResult
    func assertHasText(_ expected: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertHasText('\(expected)')", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let actual = Self.textOf(element)
            guard actual.contains(expected) else {
                throw KassError("expected text containing '\(expected)' but found '\(actual)'")
            }
        }
    }

    /// The element's text for matching: its `value` if non-empty, else its
    /// `label`. Many SwiftUI elements (e.g. `Text`) expose an empty `value` and
    /// carry the text in `label`, so a plain `value ?? label` would read blank.
    static func textOf(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    @discardableResult
    func assertEnabled(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertEnabled", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isEnabled else { throw KassError("exists but is disabled") }
        }
    }

    @discardableResult
    func assertDisabled(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertDisabled", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard !element.isEnabled else { throw KassError("exists but is enabled") }
        }
    }

    @discardableResult
    func assertSelected(_ expected: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertSelected(\(expected))", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isSelected == expected else {
                throw KassError("expected isSelected == \(expected) but was \(element.isSelected)")
            }
        }
    }

    /// Exact-match on the element's `value` (unlike `assertHasText`, which is a
    /// substring match against value-or-label). Useful for toggles/sliders/fields.
    @discardableResult
    func assertHasValue(_ expected: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertHasValue('\(expected)')", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let actual = element.value as? String
            guard actual == expected else {
                throw KassError("expected value '\(expected)' but found '\(actual ?? "nil")'")
            }
        }
    }

    @discardableResult
    func assertLabel(_ expected: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertLabel('\(expected)')", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.label == expected else {
                throw KassError("expected label '\(expected)' but found '\(element.label)'")
            }
        }
    }

    @discardableResult
    func assertLabelContains(_ substring: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertLabelContains('\(substring)')", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.label.contains(substring) else {
                throw KassError("expected label containing '\(substring)' but found '\(element.label)'")
            }
        }
    }

    /// Asserts the element's value (or label) matches a regular expression.
    @discardableResult
    func assertValueMatches(_ pattern: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertValueMatches('\(pattern)')", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let actual = Self.textOf(element)
            guard actual.range(of: pattern, options: .regularExpression) != nil else {
                throw KassError("expected '\(actual)' to match /\(pattern)/")
            }
        }
    }

    /// Waits until the element is gone (or already absent). Reads better than
    /// `assertNotExists` at a call site that expects a disappearance.
    @discardableResult
    func waitUntilGone(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        assertNotExists(file: file, line: line)
    }

    /// Waits until `condition` holds for the re-resolved element, or the budget
    /// elapses. The escape hatch for one-off states not covered by an assertion.
    @discardableResult
    func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping (XCUIElement) -> Bool
    ) -> KassElement {
        perform("waitUntil(\(description))", kind: .wait, file: file, line: line) { element in
            guard condition(element) else { throw KassError("condition '\(description)' not met") }
        }
    }

    // MARK: - Reads & placeholders

    /// The element's current `value` as a string, if any (does not wait).
    func readValue() -> String? { resolve().value as? String }

    /// The element's accessibility label (does not wait).
    func readLabel() -> String { resolve().label }

    @discardableResult
    func assertPlaceholder(_ expected: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertPlaceholder('\(expected)')", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.placeholderValue == expected else {
                throw KassError("expected placeholder '\(expected)' but found '\(element.placeholderValue ?? "nil")'")
            }
        }
    }

    // MARK: - Per-call configuration

    /// Returns a copy of this element with an overridden timeout / poll interval,
    /// for a one-off wait longer or shorter than the global config.
    /// `slowRow.within(timeout: 30).assertVisible()`.
    func within(timeout: TimeInterval? = nil, pollInterval: TimeInterval? = nil) -> KassElement {
        var overridden = config
        if let timeout = timeout { overridden.timeout = timeout }
        if let pollInterval = pollInterval { overridden.pollInterval = pollInterval }
        return KassElement(description: description, config: overridden, expectedIdentifier: expectedIdentifier, resolve: resolve)
    }

    // MARK: - Scoped children

    /// Resolves `type`/`id` *within* this element — for reaching into a specific
    /// cell/section, e.g. `cell.staticText("title")`.
    func descendant(_ type: XCUIElement.ElementType, _ id: String) -> KassElement {
        let label = "\(description) › \(KassScreen.typeName(type)) '\(id)'"
        return KassElement(description: label, config: config, expectedIdentifier: id) { [resolve] in
            resolve().descendants(matching: type)[id].firstMatch
        }
    }

    func button(_ id: String) -> KassElement { descendant(.button, id) }
    func staticText(_ id: String) -> KassElement { descendant(.staticText, id) }
    func textField(_ id: String) -> KassElement { descendant(.textField, id) }
    func image(_ id: String) -> KassElement { descendant(.image, id) }
    func cell(_ id: String) -> KassElement { descendant(.cell, id) }

    // MARK: - Controls

    /// Toggles a switch to the desired state (no-op if already there).
    ///
    /// A SwiftUI `Toggle` outside a `Form`/`List` toggles only when its inner
    /// switch control is tapped (not the row), so we tap the descendant switch
    /// when present and fall back to the element itself (UIKit `UISwitch`).
    @discardableResult
    func setSwitch(on: Bool, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("setSwitch(on: \(on))", kind: .control, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard (element.value as? String) != (on ? "1" : "0") else { return }
            let control = element.switches.firstMatch
            (control.exists ? control : element).tap()
        }
    }

    #if os(iOS)
    /// Drags a slider to a normalized position in `0...1`.
    @discardableResult
    func adjustSlider(toNormalizedPosition position: CGFloat, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("adjustSlider(\(position))", kind: .control, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            element.adjust(toNormalizedSliderPosition: position)
        }
    }

    /// Spins a picker wheel to `value`.
    @discardableResult
    func adjustPicker(toValue value: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("adjustPicker('\(value)')", kind: .control, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            element.adjust(toPickerWheelValue: value)
        }
    }
    #endif

    @discardableResult
    func assertHittable(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertHittable", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
        }
    }

    @discardableResult
    func assertNotHittable(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("assertNotHittable", kind: .assert, file: file, line: line) { element in
            guard !element.isHittable else { throw KassError("is hittable") }
        }
    }

    // MARK: - Throwing checks (for composition inside flow primitives)

    /// Single-shot, non-failing checks — they `throw` instead of calling
    /// `XCTFail`, so they compose inside `flakySafely`/`continuously`/`compose`/
    /// `retry`. Unlike `assert*`, they do not retry on their own.

    func requireExists() throws {
        let element = resolve()
        guard element.exists else { throw KassError("\(description) does not exist") }
        try enforceIdentifierIfNeeded(element)
    }

    func requireVisible() throws {
        let element = resolve()
        guard element.exists else { throw KassError("\(description) does not exist") }
        guard element.isHittable else { throw KassError("\(description) is not hittable/on-screen") }
        try enforceIdentifierIfNeeded(element)
    }

    func requirePresent() throws {
        let element = resolve()
        guard element.exists else { throw KassError("\(description) does not exist") }
        guard !element.frame.isEmpty else { throw KassError("\(description) has an empty frame") }
        try enforceIdentifierIfNeeded(element)
    }

    func requireHittable() throws {
        let element = resolve()
        guard element.exists else { throw KassError("\(description) does not exist") }
        guard element.isHittable else { throw KassError("\(description) is not hittable") }
        try enforceIdentifierIfNeeded(element)
    }

    // MARK: - Gestures

    /// Clears any existing text, then types `text`. Shares `clearText`'s
    /// delete-by-length limitation on secure/formatted fields.
    @discardableResult
    func replaceText(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("replaceText('\(text)')", kind: .type, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.tap()
            if let value = element.value as? String, !value.isEmpty {
                element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
            }
            element.typeText(text)
        }
    }

    @discardableResult
    func doubleTap(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("doubleTap", kind: .tap, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.doubleTap()
        }
    }

    @discardableResult
    func longPress(forDuration duration: TimeInterval = 1.0, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("longPress(\(duration)s)", kind: .gesture, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.press(forDuration: duration)
        }
    }

    @discardableResult
    func swipeUp(file: StaticString = #filePath, line: UInt = #line) -> KassElement { swipe(.up, file: file, line: line) }
    @discardableResult
    func swipeDown(file: StaticString = #filePath, line: UInt = #line) -> KassElement { swipe(.down, file: file, line: line) }
    @discardableResult
    func swipeLeft(file: StaticString = #filePath, line: UInt = #line) -> KassElement { swipe(.left, file: file, line: line) }
    @discardableResult
    func swipeRight(file: StaticString = #filePath, line: UInt = #line) -> KassElement { swipe(.right, file: file, line: line) }

    private func swipe(_ direction: KassScrollDirection, file: StaticString, line: UInt) -> KassElement {
        perform("swipe(\(direction))", kind: .gesture, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            switch direction {
            case .up: element.swipeUp()
            case .down: element.swipeDown()
            case .left: element.swipeLeft()
            case .right: element.swipeRight()
            }
        }
    }

    #if os(iOS)
    @discardableResult
    func pinch(scale: CGFloat, velocity: CGFloat, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("pinch(scale: \(scale))", kind: .gesture, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            element.pinch(withScale: scale, velocity: velocity)
        }
    }

    @discardableResult
    func rotate(_ rotation: CGFloat, velocity: CGFloat, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("rotate(\(rotation))", kind: .gesture, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            element.rotate(rotation, withVelocity: velocity)
        }
    }

    @discardableResult
    func twoFingerTap(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("twoFingerTap", kind: .tap, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            guard element.isHittable else { throw KassError("exists but is not hittable") }
            element.twoFingerTap()
        }
    }
    #endif

    /// Taps at a point inside the element, given as a fraction of its size.
    @discardableResult
    func tapAtNormalizedOffset(x: CGFloat, y: CGFloat, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("tapAtNormalizedOffset(\(x), \(y))", kind: .tap, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            element.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        }
    }

    /// Pull-to-refresh: drags this scroll container down from near its top.
    @discardableResult
    func pullToRefresh(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("pullToRefresh", kind: .gesture, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            let end = start.withOffset(CGVector(dx: 0, dy: 400))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
    }

    /// Press-and-drags from this element onto `target`.
    @discardableResult
    func drag(to target: KassElement, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("drag(to: \(target.description))", kind: .gesture, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let destination = target.resolve()
            guard destination.exists else { throw KassError("target \(target.description) does not exist") }
            element.press(forDuration: 0.5, thenDragTo: destination)
        }
    }

    /// Scrolls `container` in `direction` until this element becomes hittable,
    /// or the shared time budget (`config.timeout`) elapses. Each attempt draws
    /// from that budget, so scrolling can't compound into a runaway timeout.
    @discardableResult
    func scrollTo(
        in container: KassElement,
        direction: KassScrollDirection = .up,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> KassElement {
        config.reporter?.stepStarted("scrollTo \(description)")
        let context = KassActionContext(
            kind: .scroll,
            name: "scrollTo(\(direction))",
            elementDescription: description,
            identifier: expectedIdentifier,
            timeout: config.timeout,
            pollInterval: config.pollInterval,
            flakySafetyEnabled: config.flakySafetyEnabled,
            file: file,
            line: line
        )
        do {
            try KassInterceptorChain.run(config.interceptors, context: context) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
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

    /// Like ``scrollTo(in:direction:file:line:)`` but with a gentle, short
    /// press-drag (~30% of the container) instead of `swipeUp`'s momentum fling,
    /// which overshoots and skips past small targets. Slower but more
    /// deterministic — reach for it when a full swipe keeps flying past the row.
    @discardableResult
    func softScrollTo(
        in container: KassElement,
        direction: KassScrollDirection = .up,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> KassElement {
        config.reporter?.stepStarted("softScrollTo \(description)")
        let context = KassActionContext(
            kind: .scroll,
            name: "softScrollTo(\(direction))",
            elementDescription: description,
            identifier: expectedIdentifier,
            timeout: config.timeout,
            pollInterval: config.pollInterval,
            flakySafetyEnabled: config.flakySafetyEnabled,
            file: file,
            line: line
        )
        do {
            try KassInterceptorChain.run(config.interceptors, context: context) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
                let target = resolve()
                if target.exists && target.isHittable { return }
                let scroll = container.resolve()
                guard scroll.exists else {
                    throw KassError("scroll container \(container.description) does not exist")
                }
                // A short drag mirroring the swipe direction (start → end).
                let (start, end): (CGVector, CGVector)
                switch direction {
                case .up: (start, end) = (CGVector(dx: 0.5, dy: 0.65), CGVector(dx: 0.5, dy: 0.35))
                case .down: (start, end) = (CGVector(dx: 0.5, dy: 0.35), CGVector(dx: 0.5, dy: 0.65))
                case .left: (start, end) = (CGVector(dx: 0.65, dy: 0.5), CGVector(dx: 0.35, dy: 0.5))
                case .right: (start, end) = (CGVector(dx: 0.35, dy: 0.5), CGVector(dx: 0.65, dy: 0.5))
                }
                scroll.coordinate(withNormalizedOffset: start)
                    .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: end))
                throw KassError("not visible yet after soft-scrolling \(direction)")
            }
            config.reporter?.stepFinished(status: .passed, message: nil)
        } catch {
            config.reporter?.stepFinished(status: .failed, message: "\(error)")
            let message = "KassiOS: \(description) — softScrollTo failed: \(error)"
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
        kind: KassActionKind = .custom,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @escaping (XCUIElement) throws -> Void
    ) -> KassElement {
        config.reporter?.stepStarted("\(name) \(description)")
        let context = KassActionContext(
            kind: kind,
            name: name,
            elementDescription: description,
            identifier: expectedIdentifier,
            timeout: config.timeout,
            pollInterval: config.pollInterval,
            flakySafetyEnabled: config.flakySafetyEnabled,
            file: file,
            line: line
        )
        do {
            // Every action flows through the interceptor chain; the built-in
            // retry lives in it (see `config.interceptors`). The terminal is a
            // single attempt — the chain re-runs it as its members decide.
            try KassInterceptorChain.run(config.interceptors, context: context) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
                try body(resolve())
            }
            // Strict mode: verify the element carried a real accessibility id.
            // Kept outside the chain so a strict violation fails fast, unretried.
            try enforceIdentifierIfNeeded(resolve())
            config.reporter?.stepFinished(status: .passed, message: nil)
        } catch {
            let message = "KassiOS: \(description) — \(name) failed: \(error)\(failureDiagnostics())"
            config.logger.log("❌ \(message)")
            if config.captureScreenshotOnFailure {
                attachFailureScreenshot(label: "\(name) — \(description)")
            }
            // Machine-readable failure artifact — hand it to a coding agent.
            attachDiagnostic(makeDiagnostic(action: name, kind: kind, error: error, file: file, line: line))
            config.reporter?.stepFinished(status: .failed, message: message)
            XCTFail(message, file: file, line: line)
        }
        return self
    }

    // MARK: - Strict identifiers & failure diagnostics

    /// Applies `config.accessibilityIdentifierPolicy`. When the element exists
    /// but was matched by label (its `identifier` is empty or differs from what
    /// we asked for): `.warn` surfaces an Xcode message, `.enforce` throws.
    func enforceIdentifierIfNeeded(_ element: XCUIElement) throws {
        guard config.accessibilityIdentifierPolicy != .ignore, let expected = expectedIdentifier else { return }
        guard element.exists, element.identifier != expected else { return }
        let message = "'\(expected)' was matched without an accessibility identifier "
            + "(element id='\(element.identifier)') — add .accessibilityIdentifier(\"\(expected)\") to the view"
        switch config.accessibilityIdentifierPolicy {
        case .ignore:
            return
        case .warn:
            config.logger.log("⚠️ \(message)")
            XCTContext.runActivity(named: "⚠️ Missing accessibility identifier: '\(expected)'") { _ in }
        case .enforce:
            throw KassError(message + " [strict mode]")
        }
    }

    /// A one-line snapshot of the element's live state, appended to failures so
    /// the report points precisely at the offending element.
    private func failureDiagnostics() -> String {
        let element = resolve()
        guard element.exists else { return "\n  ↳ element not found in the current hierarchy" }
        return "\n  ↳ exists=true hittable=\(element.isHittable) id='\(element.identifier)' "
            + "label='\(element.label)' type=\(element.elementType.rawValue) frame=\(element.frame)"
    }

    private func attachFailureScreenshot(label: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Failure — \(label)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "❌ \(label)") { $0.add(attachment) }
        config.reporter?.attach(name: "Failure — \(label)", type: "image/png", data: screenshot.pngRepresentation)
    }
}

/// Direction for swipes and `scrollTo`.
public enum KassScrollDirection {
    case up, down, left, right
}
