import XCTest

/// Generates `KassScreen` boilerplate from a running app's accessibility tree.
///
/// Call it once from a throwaway test on the screen you want to model; paste the
/// printed class into your suite. Only elements that carry a real
/// `accessibilityIdentifier` become properties — the rest are counted, nudging
/// the app team to add identifiers (see the strict-id policy).
public enum KassScaffold {

    private static let kinds: [(type: XCUIElement.ElementType, builder: String)] = [
        (.button, "button"),
        (.staticText, "staticText"),
        (.textField, "textField"),
        (.secureTextField, "secureTextField"),
        (.image, "image"),
        (.cell, "cell"),
        (.switch, "switchControl")
    ]

    /// Returns ready-to-paste Swift for a `KassScreen` subclass named `screenName`.
    public static func generate(for app: XCUIApplication, screenName: String) -> String {
        var properties: [String] = []
        var used = Set<String>()
        var missing = 0

        for kind in kinds {
            for element in app.descendants(matching: kind.type).allElementsBoundByAccessibilityElement {
                let id = element.identifier
                guard !id.isEmpty else { missing += 1; continue }
                var name = camelCase(id)
                while used.contains(name) { name += "_" }
                used.insert(name)
                properties.append("    lazy var \(name) = \(kind.builder)(\"\(id)\")")
            }
        }

        var out = "final class \(screenName): KassScreen {\n"
        out += properties.isEmpty ? "    // No identified elements found.\n" : properties.joined(separator: "\n") + "\n"
        out += "}"
        if missing > 0 {
            out += "\n// \(missing) element(s) had no accessibilityIdentifier — add ids to include them."
        }
        return out
    }

    /// Converts an accessibility identifier into a valid lowerCamelCase Swift name.
    static func camelCase(_ id: String) -> String {
        let parts = id.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let first = parts.first else { return "element" }
        let head = first.prefix(1).lowercased() + first.dropFirst()   // keep existing humps
        let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        var name = ([head] + tail).joined()
        if let f = name.first, f.isNumber { name = "e" + name }
        return name.isEmpty ? "element" : name
    }
}

public extension KassTestCase {
    /// Prints a `KassScreen` scaffold for the current screen to the console.
    func printScreenScaffold(_ screenName: String) {
        let code = KassScaffold.generate(for: app, screenName: screenName)
        config.logger.log("🧩 Screen scaffold:\n\(code)")
    }
}
