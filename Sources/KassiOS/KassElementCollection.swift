import XCTest

/// A lazy, self-waiting wrapper around `XCUIElementQuery` — the list/table
/// counterpart of `KassElement`. Like `KassElement`, the underlying query is
/// re-evaluated on each access, so it survives view-hierarchy reloads.
@MainActor
public struct KassElementCollection {

    let query: () -> XCUIElementQuery
    let description: String
    let config: KassConfig

    init(description: String, config: KassConfig, query: @escaping () -> XCUIElementQuery) {
        self.description = description
        self.config = config
        self.query = query
    }

    /// Builds the interceptor context for a collection assertion.
    private func context(_ name: String, file: StaticString, line: UInt) -> KassActionContext {
        KassActionContext(
            kind: .assert,
            name: name,
            elementDescription: description,
            identifier: nil,
            timeout: config.timeout,
            pollInterval: config.pollInterval,
            flakySafetyEnabled: config.flakySafetyEnabled,
            file: file,
            line: line
        )
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

    /// Returns a copy of this collection with an overridden timeout / poll
    /// interval, for a one-off wait longer or shorter than the global config —
    /// mirrors `KassElement.within(timeout:pollInterval:)`.
    public func within(timeout: TimeInterval? = nil, pollInterval: TimeInterval? = nil) -> KassElementCollection {
        var overridden = config
        if let timeout = timeout { overridden.timeout = timeout }
        if let pollInterval = pollInterval { overridden.pollInterval = pollInterval }
        return KassElementCollection(description: description, config: overridden, query: query)
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
    public func assertCount(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) -> KassElementCollection {
        do {
            try KassInterceptorChain.run(config.interceptors, context: context("assertCount(\(expected))", file: file, line: line)) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
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
    public func assertNotEmpty(file: StaticString = #filePath, line: UInt = #line) -> KassElementCollection {
        do {
            try KassInterceptorChain.run(config.interceptors, context: context("assertNotEmpty", file: file, line: line)) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
                guard query().count > 0 else { throw KassError("collection is empty") }
            }
        } catch {
            let message = "KassiOS: \(description) — assertNotEmpty failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }

    /// Fails if two elements share the same key (default: the element's
    /// label). Catches duplicated rows — e.g. a pagination bug that repeats a
    /// page and renders the same row twice.
    @discardableResult
    public func assertNoDuplicates(
        by key: @escaping @MainActor (KassElement) -> String = { $0.readLabel() },
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> KassElementCollection {
        do {
            try KassInterceptorChain.run(config.interceptors, context: context("assertNoDuplicates", file: file, line: line)) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
                let keys = (0..<query().count).map { key(element(at: $0)) }
                let duplicateKeys = Self.duplicates(in: keys)
                guard duplicateKeys.isEmpty else {
                    throw KassError("found duplicate key(s): \(duplicateKeys.joined(separator: ", "))")
                }
            }
        } catch {
            let message = "KassiOS: \(description) — assertNoDuplicates failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }

    /// Finds keys that appear more than once in `values`, in first-duplicated
    /// order. Factored out of ``assertNoDuplicates(by:file:line:)`` so the
    /// duplicate-finding logic itself is unit-testable over a plain `[String]`.
    public static func duplicates(in values: [String]) -> [String] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for value in values {
            if seen.contains(value) {
                if !duplicates.contains(value) { duplicates.append(value) }
            } else {
                seen.insert(value)
            }
        }
        return duplicates
    }

    /// Applies `check` to every currently-matching element, aggregating **all**
    /// failures instead of stopping at the first — for "no row should violate
    /// this rule" checks (e.g. every row must be money-in; a leaked category
    /// shows up as one failing index instead of silently passing).
    @discardableResult
    public func assertEach(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: @escaping (KassElement) throws -> Void
    ) -> KassElementCollection {
        do {
            try KassInterceptorChain.run(config.interceptors, context: context("assertEach('\(description)')", file: file, line: line)) {
                config.synchronizer.waitForIdle(timeout: config.timeout)
                var failures: [String] = []
                for index in 0..<query().count {
                    do {
                        try check(element(at: index))
                    } catch {
                        failures.append("[\(index)] \(error)")
                    }
                }
                guard failures.isEmpty else {
                    throw KassError("\(failures.count) row(s) failed '\(description)': \(failures.joined(separator: "; "))")
                }
            }
        } catch {
            let message = "KassiOS: \(self.description) — assertEach('\(description)') failed: \(error)"
            config.logger.log("❌ \(message)")
            XCTFail(message, file: file, line: line)
        }
        return self
    }
}
