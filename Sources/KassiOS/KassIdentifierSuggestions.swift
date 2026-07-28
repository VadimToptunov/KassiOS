import XCTest

/// Ranks candidate accessibility identifiers/labels by closeness to a target
/// string — the "did you mean?" behind a not-found failure. Pure and
/// independently unit-tested; `KassElement` wires it into the failure path
/// below.
public enum KassIdentifierSuggestions {

    /// The closest `max` of `candidates` to `target` (case-insensitive
    /// Levenshtein distance), nearest first.
    ///
    /// Drops an exact (case-insensitive) match — it isn't a useful suggestion
    /// for its own failure — de-duplicates candidates that only differ by case,
    /// and drops anything farther than `maxDistance` (default: half of
    /// `target`'s length, floored at 1) so an unrelated candidate on screen
    /// (e.g. `"home.title"`) doesn't get suggested for `"login.submit"` just
    /// because both happen to exist.
    public static func nearest(
        to target: String,
        among candidates: [String],
        max: Int = 3,
        maxDistance: Int? = nil
    ) -> [String] {
        guard !target.isEmpty else { return [] }
        let targetLower = target.lowercased()
        let cap = maxDistance ?? Swift.max(1, target.count / 2)
        var seenLower = Set<String>()
        let scored: [(candidate: String, distance: Int)] = candidates.compactMap { candidate in
            guard !candidate.isEmpty else { return nil }
            let lower = candidate.lowercased()
            guard lower != targetLower else { return nil }
            guard seenLower.insert(lower).inserted else { return nil }
            let distance = levenshtein(targetLower, lower)
            guard distance <= cap else { return nil }
            return (candidate, distance)
        }
        return scored
            .sorted { $0.distance == $1.distance ? $0.candidate < $1.candidate : $0.distance < $1.distance }
            .prefix(max)
            .map(\.candidate)
    }

    /// Classic edit-distance (insertions/deletions/substitutions), O(n·m) time,
    /// O(min(n, m)) space. Its own small function, independently tested.
    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for row in 1...left.count {
            current[0] = row
            for column in 1...right.count {
                let substitutionCost = left[row - 1] == right[column - 1] ? 0 : 1
                current[column] = Swift.min(
                    previous[column] + 1,               // deletion
                    current[column - 1] + 1,            // insertion
                    previous[column - 1] + substitutionCost
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}

extension KassElement {

    /// "Did you mean?" — when the locator's target genuinely doesn't exist,
    /// walks this element's own app tree once (bounded, see ``KassTreeWalk``)
    /// and suggests the closest actual identifiers/labels found on screen, so
    /// a wrong-id guess (common from an AI author) self-corrects. Returns `""`
    /// when the element exists, carries no `expectedIdentifier`,
    /// `config.suggestSimilarIdentifiersOnFailure` is off, or nothing on screen
    /// is close enough to be worth suggesting.
    func similarIdentifierSuggestion(for element: XCUIElement) -> String {
        guard config.suggestSimilarIdentifiersOnFailure, !element.exists, let expected = expectedIdentifier else {
            return ""
        }
        // Best-effort settle before the diagnostic read, like every other wait
        // path — a mid-transition snapshot shouldn't suggest a label that's
        // about to disappear.
        config.synchronizer.waitForIdle(timeout: config.timeout)
        let candidates = KassTreeWalk.walk(app).flatMap { visited -> [String] in
            [visited.identifier, visited.label].filter { !$0.isEmpty }
        }
        let suggestions = KassIdentifierSuggestions.nearest(to: expected, among: candidates)
        guard !suggestions.isEmpty else { return "" }
        return "\n  ↳ did you mean: " + suggestions.map { "'\($0)'" }.joined(separator: ", ") + "?"
    }
}
