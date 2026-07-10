import XCTest

/// A lazy, self-waiting wrapper around `XCUIElementQuery` — the list/table
/// counterpart of `KassElement`. Like `KassElement`, the underlying query is
/// re-evaluated on each access, so it survives view-hierarchy reloads.
public struct KassElementCollection {

    let query: () -> XCUIElementQuery
    let description: String
    let config: KassConfig

    init(description: String, config: KassConfig, query: @escaping () -> XCUIElementQuery) {
        self.description = description
        self.config = config
        self.query = query
    }

    /// Live number of matching elements.
    public var count: Int { query().count }

    /// The element at `index` (by position in the query).
    public func element(at index: Int) -> KassElement {
        KassElement(description: "\(description)[\(index)]", config: config) { [query] in
            query().element(boundBy: index)
        }
    }

    public var first: KassElement {
        KassElement(description: "\(description).first", config: config) { [query] in
            query().firstMatch
        }
    }

    public var last: KassElement {
        KassElement(description: "\(description).last", config: config) { [query] in
            let resolved = query()
            return resolved.element(boundBy: max(0, resolved.count - 1))
        }
    }

    // MARK: - Refinement

    /// Narrows to elements that contain a descendant of `type` with `id`.
    public func containing(_ type: XCUIElement.ElementType, _ id: String) -> KassElementCollection {
        KassElementCollection(description: "\(description) containing \(id)", config: config) { [query] in
            query().containing(type, identifier: id)
        }
    }

    /// Narrows to elements whose label contains `text`.
    public func matching(label text: String) -> KassElementCollection {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return KassElementCollection(description: "\(description) matching '\(text)'", config: config) { [query] in
            query().matching(predicate)
        }
    }

    /// The first element whose label contains `text`.
    public func elementMatching(label text: String) -> KassElement {
        KassElement(description: "\(description) with label '\(text)'", config: config) { [query] in
            query().matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
    }

    // MARK: - Iteration

    /// Runs `body` for each currently-matching element.
    public func forEach(_ body: (KassElement) -> Void) {
        for index in 0..<query().count {
            body(element(at: index))
        }
    }

    /// Maps each currently-matching element through `transform`.
    public func map<T>(_ transform: (KassElement) -> T) -> [T] {
        (0..<query().count).map { transform(element(at: $0)) }
    }

    // MARK: - Assertions

    @discardableResult
    public func assertCount(_ expected: Int, file: StaticString = #file, line: UInt = #line) -> KassElementCollection {
        do {
            try Waiter.retry(timeout: config.timeout, pollInterval: config.pollInterval, enabled: config.flakySafetyEnabled) {
                let actual = query().count
                guard actual == expected else { throw KassError("expected \(expected) but found \(actual)") }
            }
        } catch {
            let message = "KassiOS: \(description) — assertCount(\(expected)) failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }

    @discardableResult
    public func assertNotEmpty(file: StaticString = #file, line: UInt = #line) -> KassElementCollection {
        do {
            try Waiter.retry(timeout: config.timeout, pollInterval: config.pollInterval, enabled: config.flakySafetyEnabled) {
                guard query().count > 0 else { throw KassError("collection is empty") }
            }
        } catch {
            let message = "KassiOS: \(description) — assertNotEmpty failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }
}
