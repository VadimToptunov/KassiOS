import XCTest
#if os(iOS)
import UIKit
#endif

/// Device- and system-level helpers that sit outside the app's own view tree:
/// permission dialogs, the keyboard, screenshots, backgrounding, orientation
/// and deep links. Reached through `KassTestCase.device`.
public struct KassDevice {

    public let app: XCUIApplication
    public let config: KassConfig

    public init(app: XCUIApplication, config: KassConfig = .default) {
        self.app = app
        self.config = config
    }

    // MARK: - System alerts (permissions)

    /// Registers a monitor that dismisses springboard permission dialogs by
    /// tapping the first matching button title.
    ///
    /// XCUITest only delivers interruptions on the *next* interaction with the
    /// app, so follow this with an `app.tap()` (or any real interaction) to make
    /// a pending dialog resolve. Returns the monitor token so callers can
    /// `removeUIInterruptionMonitor(_:)` when done.
    @discardableResult
    public func autoAllowSystemDialogs(
        buttonTitles: [String] = ["Allow", "Allow While Using App", "Allow Once", "OK"],
        test: XCTestCase
    ) -> NSObjectProtocol {
        test.addUIInterruptionMonitor(withDescription: "KassiOS system dialog") { alert in
            for title in buttonTitles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Keyboard

    /// Dismisses the software keyboard. Tries a common "return"/"done" key, then
    /// falls back to tapping a neutral point of the app. No-op if no keyboard.
    public func hideKeyboard() {
        guard app.keyboards.count > 0 else { return }
        for key in ["Return", "return", "Done", "done", "Go", "Search"] {
            let button = app.keyboards.buttons[key]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
        }
        // Fall back to tapping the top-left corner, away from inputs.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
    }

    // MARK: - Screenshots

    /// Captures the app's current screen and attaches it to the test report
    /// (`.xcresult`) under `name`.
    public func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "📸 \(name)") { activity in
            activity.add(attachment)
        }
        config.logger.log("📸 \(name)")
    }

    // MARK: - Lifecycle

    /// Sends the app to the background for `seconds`, then reactivates it.
    public func sendToBackground(for seconds: TimeInterval = 1) {
        #if os(iOS)
        XCUIDevice.shared.press(.home)
        #endif
        Thread.sleep(forTimeInterval: seconds)
        app.activate()
    }

    /// Brings the app back to the foreground.
    public func foreground() {
        app.activate()
    }

    // MARK: - Orientation

    #if os(iOS)
    /// Rotates the device. iOS only.
    public func rotate(to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
    }
    #endif

    // MARK: - Deep links

    /// Opens `url` via Safari. Best-effort: Safari's address-bar element differs
    /// across iOS versions, so treat this as a convenience, not a contract.
    #if os(iOS)
    public func open(url: String) {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        let field = safari.textFields["Address"].exists
            ? safari.textFields["Address"]
            : safari.otherElements["Address"]
        guard field.waitForExistence(timeout: config.timeout) else {
            config.logger.log("❌ Safari address bar not found — cannot open \(url)")
            return
        }
        field.tap()
        field.typeText(url)
        safari.typeText("\n")
    }
    #endif
}
