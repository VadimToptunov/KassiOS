import XCTest

// Gestures beyond the basic swipes: a swipe at a chosen speed and a drag by an offset.

#if os(iOS)
public extension KassElement {

    /// A swipe at a chosen speed (`.slow`, `.default`, `.fast`, or points per second).
    /// A fast swipe flings a scroll view further; a slow one is a drag.
    @discardableResult
    func swipe(_ direction: KassScrollDirection, velocity: XCUIGestureVelocity,
               file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("swipe(\(direction), velocity: \(velocity.rawValue))", kind: .gesture, file: file, line: line) { element in
            try revealIfOffscreen(element)
            switch direction {
            case .up: element.swipeUp(velocity: velocity)
            case .down: element.swipeDown(velocity: velocity)
            case .left: element.swipeLeft(velocity: velocity)
            case .right: element.swipeRight(velocity: velocity)
            }
        }
    }

    /// Presses the element's centre and drags it by `dx`, `dy` points (a slider
    /// thumb, a card to dismiss, a map). Unlike ``drag(to:file:line:)`` it needs no
    /// target element.
    @discardableResult
    func drag(byX dx: CGFloat, y dy: CGFloat, holdFor duration: TimeInterval = 0.3,
              file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("drag(by: \(dx), \(dy))", kind: .gesture, file: file, line: line) { element in
            try makeHittable(element)
            let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: duration, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)))
        }
    }
}
#endif
