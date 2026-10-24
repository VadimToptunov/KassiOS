import XCTest

/// A single bounded, one-shot walk of the app's accessibility tree, shared by
/// the "did you mean?" identifier suggestions (see `KassIdentifierSuggestions`
/// in `KassElement`'s failure path) and the discovery inventory
/// (`KassDevice.dumpIdentifiers`).
///
/// Bounded on purpose: both callers only run this after something has already
/// gone wrong (a failed assertion) or on explicit request, but a huge tree
/// still must not turn that into a hang.
enum KassTreeWalk {

    /// Hard cap on how many elements a single walk visits.
    static let elementCap = 400

    /// Cap for the per-index fallback: every element there costs several
    /// round-trips, so a smaller budget keeps a degraded walk from becoming the
    /// slow path the snapshot walk exists to avoid.
    static let fallbackCap = 50

    /// A cheap snapshot of one visited element — the handful of properties both
    /// callers need, read once per element.
    struct Visited: Equatable {
        let identifier: String
        let label: String
        let type: XCUIElement.ElementType
        /// From the snapshot path this is ``isOnScreen(_:within:)`` — the frame
        /// is non-empty and intersects the app's frame — not XCUITest's
        /// `isHittable`, which a snapshot doesn't carry and which costs its own
        /// round-trip per element. The "did you mean?" path ignores it; for
        /// `dumpIdentifiers` (discovery/scaffolding) "is it on screen" is the
        /// useful signal, and occlusion by an overlay is the only case the two
        /// disagree on. The per-index fallback still reads the real `isHittable`.
        let isHittable: Bool
    }

    /// Walks every descendant of `app`, bounded to ``elementCap`` elements.
    ///
    /// Takes one `XCUIElement.snapshot()` of the app — a single IPC round-trip
    /// for the whole tree — and flattens it locally in the same pre-order as
    /// `app.descendants(matching: .any)`. The previous per-index walk resolved
    /// the descendants query and read five properties per element, each its own
    /// round-trip: ~60 s on a ~150-element screen, all of it spent after the
    /// check had already failed. If the snapshot throws (app gone, tree
    /// mid-teardown), falls back to ``walkByIndex(_:cap:)`` with
    /// ``fallbackCap``.
    @MainActor
    static func walk(_ app: XCUIApplication) -> [Visited] {
        guard let root = try? app.snapshot() else {
            return walkByIndex(app, cap: fallbackCap)
        }
        let appFrame = root.frame
        return flatten(root, cap: elementCap, children: { $0.children }) { node in
            Visited(
                identifier: node.identifier,
                label: node.label,
                type: node.elementType,
                isHittable: isOnScreen(node.frame, within: appFrame)
            )
        }
    }

    /// Pre-order, depth-first flattening of `root`'s descendants (the root
    /// itself excluded, matching `descendants(matching: .any)`), stopping after
    /// `cap` nodes. Iterative, so a deep tree can't overflow the stack. Pure —
    /// unit-tested against a fake tree.
    static func flatten<Node>(
        _ root: Node,
        cap: Int,
        children: (Node) -> [Node],
        visit: (Node) -> Visited
    ) -> [Visited] {
        var visited: [Visited] = []
        visited.reserveCapacity(Swift.min(Swift.max(cap, 0), 64))
        var stack: [Node] = children(root).reversed()
        while visited.count < cap, let node = stack.popLast() {
            visited.append(visit(node))
            stack.append(contentsOf: children(node).reversed())
        }
        return visited
    }

    /// The snapshot stand-in for `isHittable`: a non-empty frame that overlaps
    /// the app's frame.
    static func isOnScreen(_ frame: CGRect, within appFrame: CGRect) -> Bool {
        !frame.isEmpty && frame.intersects(appFrame)
    }

    /// The pre-snapshot walk, kept as the fallback.
    ///
    /// Deliberately **not** `query.allElementsBoundByIndex.prefix(cap)`:
    /// `allElementsBoundByIndex` resolves and snapshots the *entire* matching
    /// set before a `.prefix` ever gets to trim it. Instead, resolve one index
    /// at a time via `element(boundBy:)` and stop the moment it stops existing.
    @MainActor
    static func walkByIndex(_ app: XCUIApplication, cap: Int) -> [Visited] {
        let query = app.descendants(matching: .any)
        var visited: [Visited] = []
        visited.reserveCapacity(cap)
        for index in 0..<cap {
            let element = query.element(boundBy: index)
            guard element.exists else { break }
            visited.append(
                Visited(identifier: element.identifier, label: element.label, type: element.elementType, isHittable: element.isHittable)
            )
        }
        return visited
    }
}
