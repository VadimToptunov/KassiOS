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
    ///
    /// Deliberately **not** `query.allElementsBoundByIndex.prefix(elementCap)`:
    /// `allElementsBoundByIndex` resolves and snapshots the *entire* matching
    /// set before a `.prefix` ever gets to trim it — exactly wrong for a walk
    /// that only runs once something has already failed (the hierarchy may be
    /// huge, mid-transition, or hung right then). Instead, resolve one index at
    /// a time via `element(boundBy:)` and stop the moment it stops existing, so
    /// the query itself never touches more than ``elementCap`` elements and a
    /// small tree finishes in well under that.
    @MainActor
    static func walk(_ app: XCUIApplication) -> [Visited] {
        let query = app.descendants(matching: .any)
        var visited: [Visited] = []
        visited.reserveCapacity(elementCap)
        for index in 0..<elementCap {
            let element = query.element(boundBy: index)
            guard element.exists else { break }
            visited.append(
                Visited(identifier: element.identifier, label: element.label, type: element.elementType, isHittable: element.isHittable)
            )
        }
        return visited
    }
}
