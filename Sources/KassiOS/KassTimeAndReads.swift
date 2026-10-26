import XCTest

// Reading several values at one instant, holding an assertion over a time window,
// and taps fast enough to race the app.

/// Reads accessibility text out of one hierarchy snapshot. Pure over the tree, so
/// it's unit-tested with a fake one.
enum KassSnapshotRead {

    /// For each wanted identifier, the text of the first element (pre-order) that
    /// carries it: its `value` when that's a non-empty string, else its `label`.
    /// Identifiers not found are absent from the result.
    static func texts<Node>(
        in root: Node,
        identifiers: Set<String>,
        children: (Node) -> [Node],
        read: (Node) -> (identifier: String, value: Any?, label: String)
    ) -> [String: String] {
        var found: [String: String] = [:]
        var stack: [Node] = children(root).reversed()
        while found.count < identifiers.count, let node = stack.popLast() {
            let (identifier, value, label) = read(node)
            if identifiers.contains(identifier), found[identifier] == nil {
                if let text = value as? String, !text.isEmpty { found[identifier] = text } else { found[identifier] = label }
            }
            stack.append(contentsOf: children(node).reversed())
        }
        return found
    }
}

public extension KassScreen {

    /// The text of several elements, read from **one** snapshot of the hierarchy,
    /// so values that change over time (a ticking price, a running total) are
    /// compared as they were at the same instant. Separate reads would each see a
    /// different moment.
    ///
    /// Waits (within the config's timeout) until every identifier is present, then
    /// returns their texts. Fails the test and returns what it found if some never
    /// appear.
    ///
    /// ```swift
    /// let t = home.readTexts(["home.total", "home.account.EUR", "home.account.USD"])
    /// ```
    func readTexts(_ identifiers: [String], file: StaticString = #filePath, line: UInt = #line) -> [String: String] {
        let wanted = Set(identifiers)
        let deadline = Date().addingTimeInterval(config.timeout)
        var latest: [String: String] = [:]
        repeat {
            config.settle()
            if let root = try? app.snapshot() {
                latest = KassSnapshotRead.texts(in: root, identifiers: wanted, children: { $0.children }) {
                    ($0.identifier, $0.value, $0.label)
                }
                if latest.count == wanted.count { return latest }
            }
            Thread.sleep(forTimeInterval: config.pollInterval)
        } while Date() < deadline
        let missing = wanted.subtracting(latest.keys).sorted()
        XCTFail("KassiOS: readTexts never found \(missing.joined(separator: ", "))", file: file, line: line)
        return latest
    }
}

public extension KassElement {

    /// Fails if the element's text changes at any point during `seconds`.
    ///
    /// For values that must hold still: a price captured on an order ticket that
    /// shouldn't follow the live feed, a balance that shouldn't move while a request
    /// is pending. Waits for the element first (normal budget), then samples its
    /// text every `pollInterval` for the window.
    @discardableResult
    func assertUnchanged(for seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        var first: String?
        perform("assertUnchanged(for: \(seconds)s)", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            first = Self.textOf(element)
        }
        guard let first else { return self }
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            Thread.sleep(forTimeInterval: Swift.min(config.pollInterval, 0.25))
            let element = resolve()
            let now = element.exists ? Self.textOf(element) : "<gone>"
            if now != first {
                let after = String(format: "%.1f", Date().timeIntervalSince(start))
                let message = "KassiOS: \(description) — assertUnchanged failed: changed from '\(first)' to '\(now)' after \(after) s"
                config.logger.log("❌ \(message)")
                config.reporter?.stepFinished(status: .failed, message: message)
                XCTFail(message, file: file, line: line)
                return self
            }
        }
        return self
    }

    #if os(iOS)
    /// `times` taps on the same spot, one right after another, without waiting for
    /// the element or checking it between taps.
    ///
    /// For double-submit bugs: the point is captured before the first tap, so the
    /// second lands where a finger would land, even if the first tap already started
    /// changing the screen. Each tap still goes through XCUITest's event handling
    /// (a few hundred milliseconds), which is well inside a request still in flight.
    /// Not `tap(withNumberOfTaps:)`: the system turns that into one multi-tap
    /// gesture, and a SwiftUI button then sees one tap fewer.
    @discardableResult
    func rapidTap(times: Int = 2, file: StaticString = #filePath, line: UInt = #line) -> KassElement {
        perform("rapidTap(times: \(times))", kind: .tap, file: file, line: line) { element in
            guard times >= 1 else { throw KassError("rapidTap needs at least one tap") }
            try makeHittable(element)
            let spot = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            for _ in 0..<times { spot.tap() }
        }
    }
    #endif
}
