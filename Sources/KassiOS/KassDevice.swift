import XCTest
#if os(iOS)
import UIKit
#endif

/// Device- and system-level helpers that sit outside the app's own view tree:
/// permission dialogs, the keyboard, screenshots, backgrounding, orientation
/// and deep links. Reached through `KassTestCase.device`.
@MainActor
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

    /// The SpringBoard app — the home screen and host of system alerts.
    public var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// Dismisses a system permission dialog that is *currently* on screen by
    /// tapping the first matching SpringBoard button. Returns whether it tapped.
    /// Complements `autoAllowSystemDialogs`, which handles dialogs that appear
    /// later via an interruption monitor.
    @discardableResult
    public func allowSystemDialogNow(
        buttonTitles: [String] = ["Allow", "Allow While Using App", "Allow Once", "OK"]
    ) -> Bool {
        let sb = springboard
        for title in buttonTitles {
            let button = sb.buttons[title]
            if button.exists && button.isHittable {
                button.tap()
                return true
            }
        }
        return false
    }

    /// Blocks until the configured synchronizer reports the app is idle.
    public func waitForIdle() {
        config.synchronizer.waitForIdle(timeout: config.timeout)
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
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "📸 \(name)") { activity in
            activity.add(attachment)
        }
        config.logger.log("📸 \(name)")
        config.reporter?.attach(name: name, type: "image/png", data: shot.pngRepresentation)
    }

    /// Attaches arbitrary text (a log dump, a JSON payload, …) to the report.
    public func attachText(_ name: String, _ text: String) {
        let data = Data(text.utf8)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "📄 \(name)") { $0.add(attachment) }
        config.reporter?.attach(name: name, type: "text/plain", data: data)
    }

    // MARK: - Lifecycle

    #if os(iOS)
    /// Presses the hardware Home button. iOS only.
    public func pressHome() {
        XCUIDevice.shared.press(.home)
    }
    #endif

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

    /// Opens `url` via Safari. Best-effort **fallback**: Safari's address-bar
    /// element differs across iOS versions. Prefer the launch-argument
    /// convention — `KassTestCase.launch(deeplink:)` — which the app routes
    /// in-process and is reliable.
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

    // MARK: - Tier B: relaunch with settings (launch arguments)

    /// Relaunches the app with locale/language/Dynamic-Type overrides applied as
    /// launch arguments — **Tier B**: no host bridge, works on simulator *and*
    /// real devices, but requires a relaunch (it's modelled as one on purpose,
    /// rather than pretending the change is live).
    ///
    /// ```swift
    /// device.relaunch { $0.locale("de_DE").language("de") }
    /// ```
    @discardableResult
    public func relaunch(_ configure: (KassLaunchOptions) -> KassLaunchOptions) -> XCUIApplication {
        let options = configure(KassLaunchOptions())
        app.terminate()
        app.launchArguments += options.arguments
        app.launch()
        return app
    }
}

/// Builder for ``KassDevice/relaunch(_:)`` — the Tier B device settings that map
/// to launch arguments. Each method returns a new value, so calls chain:
/// `$0.locale("de_DE").language("de")`.
public struct KassLaunchOptions {
    private(set) var arguments: [String] = []

    private func adding(_ args: [String]) -> KassLaunchOptions {
        var copy = self
        copy.arguments += args
        return copy
    }

    /// `-AppleLocale`, e.g. `"de_DE"`. Drives `Locale.current`.
    public func locale(_ identifier: String) -> KassLaunchOptions {
        adding(["-AppleLocale", identifier])
    }

    /// `-AppleLanguages`, e.g. `"de"`. Drives the app's language.
    public func language(_ code: String) -> KassLaunchOptions {
        adding(["-AppleLanguages", "(\(code))"])
    }

    /// `-UIPreferredContentSizeCategoryName`, e.g.
    /// `"UICTContentSizeCategoryAccessibilityXL"` for a large Dynamic Type size.
    public func dynamicType(_ category: String) -> KassLaunchOptions {
        adding(["-UIPreferredContentSizeCategoryName", category])
    }
}
