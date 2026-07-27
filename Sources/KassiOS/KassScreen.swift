import XCTest

/// Base class for screen (page) objects.
///
/// Subclass it, declare your elements as `lazy` properties, and optionally list
/// the elements that prove the screen is loaded in `onLoad`.
@MainActor
open class KassScreen {

    public let app: XCUIApplication
    public let config: KassConfig

    public required init(app: XCUIApplication, config: KassConfig) {
        self.app = app
        self.config = config
    }

    /// Elements that must be visible for this screen to be considered loaded.
    /// `KassTestCase.onScreen` waits for these before running the block.
    open var onLoad: [KassElement] { [] }

    // MARK: - Element builders (by accessibility identifier)

    public func button(_ id: String) -> KassElement { element(id, type: .button) }
    public func staticText(_ id: String) -> KassElement { element(id, type: .staticText) }
    public func textField(_ id: String) -> KassElement { element(id, type: .textField) }
    public func secureTextField(_ id: String) -> KassElement { element(id, type: .secureTextField) }
    public func image(_ id: String) -> KassElement { element(id, type: .image) }
    public func cell(_ id: String) -> KassElement { element(id, type: .cell) }
    public func switchControl(_ id: String) -> KassElement { element(id, type: .switch) }
    public func link(_ id: String) -> KassElement { element(id, type: .link) }
    public func other(_ id: String) -> KassElement { element(id, type: .other) }

    /// The frontmost web view (`WKWebView`). Its contents are reachable with the
    /// usual builders (`staticText`, `link`, `button`, …) once loaded.
    public func webView() -> KassElement {
        KassElement(description: "webView", config: config) { [app] in
            app.webViews.firstMatch
        }
    }

    /// All web links in the tree.
    public func links() -> KassElementCollection { all(.link) }

    /// Generic builder: resolves by accessibility identifier within a type.
    ///
    /// id-first: matches the accessibility identifier first, and only falls
    /// back to the label subscript (XCUITest's behaviour when an element's
    /// identifier is empty) if no element actually carries that identifier —
    /// so a real id always wins over a coincidental label match.
    /// Uses `firstMatch` so an ambiguous identifier (e.g. a title that also
    /// appears elsewhere in the tree) resolves to the first hit rather than
    /// throwing "Multiple matching elements found".
    public func element(_ id: String, type: XCUIElement.ElementType) -> KassElement {
        KassElement(description: "\(Self.typeName(type)) '\(id)'", config: config, expectedIdentifier: id) { [app] in
            Self.idFirstMatch(app.descendants(matching: type), id: id)
        }
    }

    /// Resolves by accessibility identifier regardless of element type — SwiftUI
    /// exposes one view as button/cell/other by context, and pinning a type is a
    /// common source of flake. id-first, same as `element(_:type:)`.
    public func element(_ id: String) -> KassElement {
        KassElement(description: "'\(id)'", config: config, expectedIdentifier: id) { [app] in
            Self.idFirstMatch(app.descendants(matching: .any), id: id)
        }
    }

    /// Matches an element carrying BOTH accessibility identifier `id` AND `label`
    /// — for SwiftUI's container-id propagation (a sheet's id lands on every child).
    public func element(id: String, label: String, type: XCUIElement.ElementType = .any) -> KassElement {
        KassElement(
            description: "\(Self.typeName(type)) '\(id)' labeled '\(label)'",
            config: config,
            expectedIdentifier: id
        ) { [app] in
            app.descendants(matching: type)
                .matching(identifier: id)
                .matching(NSPredicate(format: "label == %@", label))
                .firstMatch
        }
    }

    /// Convenience for `element(id:label:type:)` scoped to `.button`.
    public func button(id: String, label: String) -> KassElement { element(id: id, label: label, type: .button) }

    /// Matches by a label substring (case-insensitive) — for dialogs/toasts/rows
    /// identified by their text. This is intentional label matching, so it does
    /// NOT warn under the identifier policy (there is no expected identifier).
    public func staticText(containing substring: String) -> KassElement {
        element(labelContains: substring, type: .staticText)
    }

    /// Matches by a label substring (case-insensitive), any type by default.
    /// Intentional label matching — does NOT warn under the identifier policy.
    public func element(labelContains substring: String, type: XCUIElement.ElementType = .any) -> KassElement {
        KassElement(description: "\(Self.typeName(type)) label contains '\(substring)'", config: config) { [app] in
            app.descendants(matching: type)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", substring))
                .firstMatch
        }
    }

    /// Escape hatch: wrap an arbitrary query when identifiers aren't enough.
    public func custom(_ description: String, _ resolve: @escaping () -> XCUIElement) -> KassElement {
        KassElement(description: description, config: config, resolve: resolve)
    }

    /// Escape hatch for collections: wrap an arbitrary query.
    public func customCollection(_ description: String, _ query: @escaping () -> XCUIElementQuery) -> KassElementCollection {
        KassElementCollection(description: description, config: config, query: query)
    }

    // MARK: - Collection builders (lists, tables, grids)

    public func buttons() -> KassElementCollection { all(.button) }
    public func staticTexts() -> KassElementCollection { all(.staticText) }
    public func cells() -> KassElementCollection { all(.cell) }
    public func images() -> KassElementCollection { all(.image) }

    /// Every element of `type` in the tree.
    public func all(_ type: XCUIElement.ElementType) -> KassElementCollection {
        KassElementCollection(description: "all \(Self.typeName(type))s", config: config) { [app] in
            app.descendants(matching: type)
        }
    }

    /// Every element of `type` sharing accessibility identifier `id`.
    public func all(_ id: String, type: XCUIElement.ElementType) -> KassElementCollection {
        KassElementCollection(description: "\(Self.typeName(type))s '\(id)'", config: config) { [app] in
            app.descendants(matching: type).matching(identifier: id)
        }
    }

    // MARK: - Helpers

    /// id-first resolution: `[id]` on an `XCUIElementQuery` — and, empirically,
    /// `.matching(identifier:)` too — silently falls back to matching an
    /// element's *label* when its identifier is empty, so a test author who
    /// thinks they matched by id may actually be matching a label. A raw
    /// `identifier ==` predicate has no such fallback, so use that for the
    /// real-id check; fall back to the label subscript only when no element
    /// carries `id` as its identifier. Shared by `KassScreen.element`/
    /// `element(_:)` and `KassElement.descendant`.
    static func idFirstMatch(_ query: XCUIElementQuery, id: String) -> XCUIElement {
        let byId = query.matching(NSPredicate(format: "identifier == %@", id)).firstMatch
        return byId.exists ? byId : query[id].firstMatch
    }

    static func typeName(_ type: XCUIElement.ElementType) -> String {
        let names: [XCUIElement.ElementType: String] = [
            .button: "button", .staticText: "text", .textField: "textField",
            .secureTextField: "secureTextField", .image: "image", .cell: "cell",
            .switch: "switch", .link: "link", .searchField: "searchField",
            .slider: "slider", .stepper: "stepper", .segmentedControl: "segmentedControl",
            .picker: "picker", .menuButton: "menuButton"
        ]
        return names[type] ?? "element"
    }
}
