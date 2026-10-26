import XCTest

// Making an element reachable before acting on it, and checking that a state-setting
// action actually changed the state. Both run inside the action's attempt, so they
// re-resolve on every attempt and share the action's one time budget.

/// Text comparison for "did the field end up with what we typed?".
///
/// Exact match first; failing that, the two strings are compared with everything
/// but letters and digits removed, so a field that formats its input ("2000" shown
/// as "2,000", "4111 1111 …" for a card number) still counts as matching.
enum KassTextMatch {
    static func matches(_ actual: String, typed: String) -> Bool {
        if actual == typed { return true }
        let strip: (String) -> String = { $0.filter { $0.isLetter || $0.isNumber } }
        return !strip(typed).isEmpty && strip(actual) == strip(typed)
    }
}

/// Polls `condition` every 0.1 s until it holds or `seconds` pass. Returns whether it held.
@MainActor
func kassPoll(within seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return condition()
}

/// How long a state-setting action waits for the UI to reflect it before trying
/// its fallback or failing. Long enough for a SwiftUI re-render, short enough that
/// a real no-op fails within the action's budget.
let kassOutcomeWindow: TimeInterval = 1.5

extension KassElement {

    /// Gets `element` into a state where it can be touched: it exists and is hittable.
    /// If it's covered by the keyboard, dismisses the keyboard; if it's off screen,
    /// swipes once toward it and throws, so the surrounding retry tries again.
    func makeHittable(_ element: XCUIElement) throws {
        guard element.exists else { throw KassError("does not exist") }
        if element.isHittable { return }
        if config.dismissKeyboardWhenCovering, KassKeyboard.covers(element, in: app) {
            KassKeyboard.dismiss(in: app)
            if element.isHittable { return }
        }
        if config.autoScroll, let direction = KassAutoScroll.direction(toward: element.frame, in: app.frame),
           let container = KassAutoScroll.container(in: app) {
            switch direction {
            case .up: container.swipeUp()
            case .down: container.swipeDown()
            case .left: container.swipeLeft()
            case .right: container.swipeRight()
            }
            throw KassError("is off screen; scrolled \(direction) toward it")
        }
        throw KassError("exists but is not hittable")
    }

    /// For gestures on containers (swipes, pinch, rotate): scrolls toward `element`
    /// only if it's off screen, without requiring it to be hittable (a scroll view
    /// often isn't). Throws after a swipe so the retry checks again.
    func revealIfOffscreen(_ element: XCUIElement) throws {
        guard element.exists else { throw KassError("does not exist") }
        guard config.autoScroll, !element.isHittable,
              let direction = KassAutoScroll.direction(toward: element.frame, in: app.frame),
              let container = KassAutoScroll.container(in: app),
              container.frame != element.frame
        else { return }
        switch direction {
        case .up: container.swipeUp()
        case .down: container.swipeDown()
        case .left: container.swipeLeft()
        case .right: container.swipeRight()
        }
        throw KassError("is off screen; scrolled \(direction) toward it")
    }

    /// The switch-like value of `element` ("1"/"0"), if it has one.
    static func switchValue(_ element: XCUIElement) -> String? {
        element.value as? String
    }

    /// Taps the switch and, if `flipped` doesn't come true, taps its trailing edge
    /// once more. Throws if it still hasn't flipped (only when verifying outcomes).
    func flipSwitch(_ element: XCUIElement, flipped: () -> Bool) throws {
        let control = element.switches.firstMatch
        let target = control.exists ? control : element
        target.tap()
        guard config.verifyActionOutcome else { return }
        if kassPoll(within: kassOutcomeWindow, flipped) { return }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if kassPoll(within: kassOutcomeWindow, flipped) { return }
        let value = Self.switchValue(element) ?? "no value"
        throw KassError("was tapped but its value is still \(value): the tap didn't reach the control, or the app ignored it")
    }
}

public extension KassElement {

    /// Toggles a switch to the desired state (no-op if already there).
    ///
    /// A SwiftUI `Toggle` outside a `Form`/`List` toggles only when its inner
    /// switch control is tapped (not the row), so we tap the descendant switch
    /// when present and fall back to the element itself (UIKit `UISwitch`).
    ///
    /// With ``KassConfig/verifyActionOutcome`` (the default) the value is read
    /// back. If the tap didn't flip it, a second tap goes to the switch's
    /// trailing edge, where a SwiftUI `Toggle`'s control sits; if the value still
    /// hasn't changed, the action fails instead of returning as if it had worked.
    @discardableResult
    func setSwitch(on: Bool, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("setSwitch(on: \(on))", kind: .control, file: file, line: line) { element in
            try makeHittable(element)
            let target = on ? "1" : "0"
            guard Self.switchValue(element) != target else { return }
            try flipSwitch(element) { Self.switchValue(element) == target }
        }
    }

    /// Flips a switch unconditionally (unlike `setSwitch(on:)`, which only taps
    /// when the state differs). Verified like `setSwitch(on:)`.
    @discardableResult
    func toggle(file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("toggle", kind: .control, file: file, line: line) { element in
            try makeHittable(element)
            let before = Self.switchValue(element)
            try flipSwitch(element) { Self.switchValue(element) != before }
        }
    }
}

/// Scrolling toward an off-screen element.
enum KassAutoScroll {

    /// Which way to swipe so content at `frame` moves into `screen`, or nil if it
    /// already overlaps the screen (then it's covered, not off screen). Pure.
    static func direction(toward frame: CGRect, in screen: CGRect) -> KassScrollDirection? {
        guard !frame.isEmpty else { return nil }
        if frame.minY >= screen.maxY || frame.maxY > screen.maxY { return .up }
        if frame.maxY <= screen.minY || frame.minY < screen.minY { return .down }
        if frame.minX >= screen.maxX { return .left }
        if frame.maxX <= screen.minX { return .right }
        return nil
    }

    /// The screen's main scroll container: the largest visible scroll view,
    /// table or collection view.
    @MainActor
    static func container(in app: XCUIApplication) -> XCUIElement? {
        let candidates = [app.collectionViews.firstMatch, app.tables.firstMatch, app.scrollViews.firstMatch]
            .filter { $0.exists && !$0.frame.isEmpty }
        return candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

/// The software keyboard and the input accessory bar above it.
enum KassKeyboard {

    /// Room above the keyboard that an input accessory bar (WKWebView's ⌃⌄ Done bar,
    /// a custom toolbar) can take.
    static let accessoryAllowance: CGFloat = 50

    /// Whether `frame` reaches into the area the keyboard and its accessory bar cover. Pure.
    static func covers(_ frame: CGRect, keyboard: CGRect) -> Bool {
        guard !keyboard.isEmpty, !frame.isEmpty else { return false }
        return frame.maxY > keyboard.minY - accessoryAllowance
    }

    @MainActor
    static func covers(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        return keyboard.exists && covers(element.frame, keyboard: keyboard.frame)
    }

    /// Dismisses the keyboard without submitting anything if it can: the accessory
    /// bar's Done button first, then a Done / Hide key on the keyboard. Returns
    /// whether the keyboard is gone. Return is never pressed, because on many forms
    /// it submits.
    @MainActor
    @discardableResult
    static func dismiss(in app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return true }
        let candidates = [
            app.toolbars.buttons["Done"],
            keyboard.buttons["Done"],
            keyboard.buttons["Hide keyboard"],
            keyboard.buttons["Dismiss"],
        ]
        for button in candidates where button.exists && button.isHittable {
            button.tap()
            if kassPoll(within: 1, { !keyboard.exists }) { return true }
        }
        return !keyboard.exists
    }
}

public extension KassScreen {

    /// Hides the software keyboard without submitting the form: taps the input
    /// accessory bar's Done (WKWebView, custom toolbars) or the keyboard's own
    /// Done / Hide key. Fails if neither exists, rather than pressing Return.
    func dismissKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        if !KassKeyboard.dismiss(in: app) {
            XCTFail("KassiOS: couldn't dismiss the keyboard: no Done / Hide key and no accessory Done button", file: file, line: line)
        }
    }
}
