import XCTest

public extension KassTestCase {

    /// Runs `flow` once per locale, relaunching the app in that language first —
    /// KassiOS's take on Kaspresso's Docloc. Inside `flow`, take
    /// `device.screenshot("name-\(locale)")` shots to build localized captures
    /// (for App Store screenshots or visual review).
    ///
    /// Appearance (light/dark) and Dynamic Type can't be switched from inside the
    /// test process; drive them host-side around the run — e.g.
    /// `kass-simctl appearance dark` — and loop the locales here within each.
    func forEachLocale(_ locales: [String], _ flow: (String) -> Void) {
        for locale in locales {
            relaunch(arguments: ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale])
            XCTContext.runActivity(named: "Locale: \(locale)") { _ in
                config.logger.log("🌍 Locale: \(locale)")
                flow(locale)
            }
        }
    }
}
