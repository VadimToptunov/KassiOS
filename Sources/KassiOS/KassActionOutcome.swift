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
        if config.autoScroll, let direction = scrollToward(element, outFromUnder: true) {
            if element.isHittable { return }
            throw KassError("is off screen or under a bar; scrolled \(direction) toward it")
        }
        throw KassError("exists but is not hittable")
    }

    /// For gestures on containers (swipes, pinch, rotate): scrolls toward `element`
    /// only if it's off screen, without requiring it to be hittable (a scroll view
    /// often isn't). Throws after a swipe so the retry checks again.
    func revealIfOffscreen(_ element: XCUIElement) throws {
        guard element.exists else { throw KassError("does not exist") }
        guard config.autoScroll, !element.isHittable,
              let direction = scrollToward(element, outFromUnder: false)
        else { return }
        if element.isHittable { return }
        throw KassError("is off screen; scrolled \(direction) toward it")
    }

    /// Drags the scroll container toward `element` until it's hittable, the
    /// content stops moving, or `KassAutoScroll.maxDrags` drags. Several drags per
    /// attempt, so a far target doesn't spend a whole retry on each one. Returns
    /// the last direction, or nil if there was nothing to scroll.
    private func scrollToward(_ element: XCUIElement, outFromUnder: Bool) -> KassScrollDirection? {
        var scrolled: KassScrollDirection?
        for _ in 0..<KassAutoScroll.maxDrags {
            let frame = element.frame
            guard let direction = KassAutoScroll.direction(toward: frame, in: app.frame)
                    ?? (outFromUnder ? KassAutoScroll.directionOutFromUnder(frame, in: app.frame) : nil),
                  let container = KassAutoScroll.container(for: frame, in: app),
                  container.frame != frame
            else { break }
            KassAutoScroll.swipe(container, direction)
            scrolled = direction
            if element.isHittable || element.frame == frame { break }
        }
        return scrolled
    }

    /// The switch-like value of `element` ("1"/"0"), if it has one.
    static func switchValue(_ element: XCUIElement) -> String? {
        element.value as? String
    }

    /// Focuses a text field with the cursor after its text and deletes it. A tap
    /// at the centre can land the cursor mid-text (right-aligned or long values),
    /// and the deletes then only remove what's left of it, so this taps the
    /// trailing edge. If text is still left, the field's clear button is tried.
    func emptyField(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        // A value equal to the placeholder may be real text ("000000" in a field
        // whose placeholder is "000000"), so delete anyway: extra deletes are harmless.
        guard let value = element.value as? String, !value.isEmpty else { return }
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        if let left = element.value as? String, !Self.isEmptyFieldValue(left, of: element) {
            let clear = element.buttons.firstMatch
            if clear.exists, clear.isHittable { clear.tap() }
        }
    }

    /// An empty field reports its placeholder as its value.
    static func isEmptyFieldValue(_ value: String, of element: XCUIElement) -> Bool {
        value.isEmpty || value == element.placeholderValue
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

    /// The most drags one attempt makes before handing back to the retry.
    static let maxDrags = 5

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

    /// For an element that is on screen but can't be hit near the top or bottom
    /// edge (under a floating tab bar, a toolbar, a navigation bar): which way to
    /// scroll it toward the middle. Nil in the middle band, where something other
    /// than a bar is in the way. Pure.
    static func directionOutFromUnder(_ frame: CGRect, in screen: CGRect) -> KassScrollDirection? {
        guard !frame.isEmpty, frame.intersects(screen) else { return nil }
        if frame.midY > screen.minY + screen.height * 0.75 { return .up }
        if frame.midY < screen.minY + screen.height * 0.15 { return .down }
        return nil
    }

    /// The scroll container to swipe for content at `frame`: among the scroll views,
    /// tables and collection views that can be touched right now (one behind a
    /// sheet can't), the largest that spans the element horizontally.
    @MainActor
    static func container(for frame: CGRect, in app: XCUIApplication) -> XCUIElement? {
        var candidates: [XCUIElement] = []
        for query in [app.collectionViews, app.tables, app.scrollViews] {
            for index in 0..<6 {
                let element = query.element(boundBy: index)
                guard element.exists else { break }
                candidates.append(element)
            }
        }
        return candidates
            .filter { !$0.frame.isEmpty && $0.isHittable && $0.frame.minX <= frame.midX && frame.midX <= $0.frame.maxX }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// A drag across half the container that holds still at the end, so the
    /// content moves a predictable distance with no fling and the next frame
    /// check sees where it stopped. Much quicker than a slow swipe.
    @MainActor
    static func swipe(_ container: XCUIElement, _ direction: KassScrollDirection) {
        #if os(iOS)
        let (from, to): (CGVector, CGVector)
        switch direction {
        case .up: (from, to) = (CGVector(dx: 0.5, dy: 0.75), CGVector(dx: 0.5, dy: 0.25))
        case .down: (from, to) = (CGVector(dx: 0.5, dy: 0.25), CGVector(dx: 0.5, dy: 0.75))
        case .left: (from, to) = (CGVector(dx: 0.75, dy: 0.5), CGVector(dx: 0.25, dy: 0.5))
        case .right: (from, to) = (CGVector(dx: 0.25, dy: 0.5), CGVector(dx: 0.75, dy: 0.5))
        }
        container.coordinate(withNormalizedOffset: from).press(
            forDuration: 0.05,
            thenDragTo: container.coordinate(withNormalizedOffset: to),
            withVelocity: .fast,
            thenHoldForDuration: 0.15
        )
        #else
        switch direction {
        case .up: container.swipeUp()
        case .down: container.swipeDown()
        case .left: container.swipeLeft()
        case .right: container.swipeRight()
        }
        #endif
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
