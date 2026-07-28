import XCTest

/// A single bounded, one-shot walk of the app's accessibility tree, shared by
/// the "did you mean?" identifier suggestions (see `KassIdentifierSuggestions`
/// in `KassElement`'s failure path) and the discovery inventory
/// (`KassDevice.dumpIdentifiers`).
///
/// Bounded on purpose: both callers only run this after something has already
/// gone wrong (a failed assertion) or on explicit request, but a huge tree
/// still must not turn that into a hang — each visited element costs an
/// IPC round-trip to the app process.
enum KassTreeWalk {

    /// Hard cap on how many elements a single walk visits.
    static let elementCap = 400

    /// A cheap snapshot of one visited element — the handful of properties both
    /// callers need, read once per element.
    struct Visited {
        let identifier: String
        let label: String
        let type: XCUIElement.ElementType
        let isHittable: Bool
    }

    /// Walks every descendant of `app`, bounded to ``elementCap`` elements.
    @MainActor
    static func walk(_ app: XCUIApplication) -> [Visited] {
        app.descendants(matching: .any).allElementsBoundByIndex.prefix(elementCap).map {
            Visited(identifier: $0.identifier, label: $0.label, type: $0.elementType, isHittable: $0.isHittable)
        }
    }
}
