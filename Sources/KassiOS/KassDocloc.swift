import XCTest

@MainActor
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

    /// Relaunches under a pseudolocalization pass — doubled string lengths and
    /// visible (uppercased) non-localized strings — then runs `flow`. Surfaces
    /// truncation/overflow and hardcoded, un-localized strings without a
    /// translator. Pass `rightToLeft: true` to also force RTL layout. Take
    /// `device.screenshot(...)` shots inside `flow` for review. Launch-argument
    /// based, so it works on simulator and real devices.
    ///
    /// Like ``forEachLocale(_:_:)``, it relaunches applying these arguments on
    /// top of the app's existing launch arguments — call it on a fresh launch
    /// (or standalone) so a prior relaunch's locale doesn't carry over.
    func runPseudolocalized(rightToLeft: Bool = false, _ flow: () -> Void) {
        // Route through `relaunch(arguments:)` (not `device.relaunch`) so the
        // pseudolocalized launch gets the same reporting + `disableAnimations`
        // treatment as `forEachLocale`.
        let arguments = KassLaunchOptions()
            .doubleLengthStrings().showNonLocalizedStrings().rightToLeft(rightToLeft)
            .arguments
        relaunch(arguments: arguments)
        XCTContext.runActivity(named: "Pseudolocalized\(rightToLeft ? " (RTL)" : "")") { _ in
            config.logger.log("🌍 Pseudolocalized\(rightToLeft ? " (RTL)" : "")")
            flow()
        }
    }
}
