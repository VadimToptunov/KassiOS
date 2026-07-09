import XCTest

/// Base class for screen (page) objects.
///
/// Subclass it, declare your elements as `lazy` properties, and optionally list
/// the elements that prove the screen is loaded in `onLoad`.
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
    public func other(_ id: String) -> KassElement { element(id, type: .other) }

    /// Generic builder: resolves by accessibility identifier within a type.
    ///
    /// Uses `firstMatch` so an ambiguous identifier (e.g. a title that also
    /// appears elsewhere in the tree) resolves to the first hit rather than
    /// throwing "Multiple matching elements found".
    public func element(_ id: String, type: XCUIElement.ElementType) -> KassElement {
        KassElement(description: "\(Self.typeName(type)) '\(id)'", config: config) { [app] in
            app.descendants(matching: type)[id].firstMatch
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

    static func typeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .staticText: return "text"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .image: return "image"
        case .cell: return "cell"
        case .switch: return "switch"
        default: return "element"
        }
    }
}
