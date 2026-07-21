import SwiftSyntax
import SwiftParser

/// Statically twins the runtime accessibility-identifier audit: parses a Swift
/// source file and flags `KassScreen` subclasses that skip the guardrails the
/// runtime can only catch on a live app (an unverifiable `onLoad`, or an
/// element identifier that can't be seen without running the test).
///
/// Limitation (MVP): only classes whose own inheritance clause literally lists
/// `KassScreen` are recognized — a subclass of a subclass in another file
/// (cross-file base classes) isn't resolved. That keeps false positives at
/// zero at the cost of missing some deeper hierarchies.
public func lint(source: String, filePath: String) -> [Diagnostic] {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: filePath, tree: tree)
    let visitor = ScreenVisitor(filePath: filePath, converter: converter)
    visitor.walk(tree)
    return visitor.diagnostics
}

/// The builder methods audited by KAS002, and which positional argument holds
/// the identifier. `descendant` takes the element type first, so its
/// identifier is the *second* argument; every other builder takes the
/// identifier first.
private let identifierArgumentIndex: [String: Int] = [
    "button": 0, "staticText": 0, "textField": 0, "secureTextField": 0,
    "image": 0, "cell": 0, "switchControl": 0, "link": 0, "other": 0,
    "element": 0, "descendant": 1
]

final class ScreenVisitor: SyntaxVisitor {
    private let filePath: String
    private let converter: SourceLocationConverter
    private(set) var diagnostics: [Diagnostic] = []

    /// Whether each enclosing class (innermost last) is a recognized
    /// `KassScreen` subclass — element-builder calls only fire inside one.
    private var screenStack: [Bool] = []

    init(filePath: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let isScreen = inheritsKassScreen(node)
        screenStack.append(isScreen)
        if isScreen {
            checkOnLoad(node)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        screenStack.removeLast()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if screenStack.last == true {
            checkBuilderCall(node)
        }
        return .visitChildren
    }

    // MARK: - KAS001

    private func inheritsKassScreen(_ node: ClassDeclSyntax) -> Bool {
        guard let inheritedTypes = node.inheritanceClause?.inheritedTypes else { return false }
        return inheritedTypes.contains { $0.type.trimmedDescription == "KassScreen" }
    }

    private func checkOnLoad(_ node: ClassDeclSyntax) {
        guard let onLoad = onLoadBinding(in: node) else {
            report(node.name, rule: .kas001, message: kas001Message(className: node.name.text))
            return
        }
        guard let arrayLiteral = returnedArrayLiteral(in: onLoad) else {
            // No directly-visible array literal (e.g. branches, a helper call) —
            // lenient: assume it's a computed body that supplies elements.
            return
        }
        guard !arrayLiteral.elements.isEmpty else {
            report(node.name, rule: .kas001, message: kas001Message(className: node.name.text))
            return
        }
    }

    private func kas001Message(className: String) -> String {
        "KassScreen '\(className)' has no non-empty onLoad; navigate(to:) can't verify arrival — "
            + "declare the elements that prove this screen loaded (KAS001)"
    }

    /// Finds this class's own `onLoad` property binding, if it declares one.
    private func onLoadBinding(in node: ClassDeclSyntax) -> PatternBindingSyntax? {
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      pattern.identifier.text == "onLoad" else { continue }
                return binding
            }
        }
        return nil
    }

    /// The array literal this property's accessor directly returns, if any —
    /// either an implicit single-expression body (`{ [a, b] }`) or an explicit
    /// `return [a, b]`. Nested control flow isn't traced (see type doc).
    private func returnedArrayLiteral(in binding: PatternBindingSyntax) -> ArrayExprSyntax? {
        guard let accessorBlock = binding.accessorBlock else { return nil }
        let statements: CodeBlockItemListSyntax
        switch accessorBlock.accessors {
        case .getter(let items):
            statements = items
        case .accessors(let accessorDecls):
            guard let getter = accessorDecls.first(where: { $0.accessorSpecifier.tokenKind == .keyword(.get) }),
                  let body = getter.body else { return nil }
            statements = body.statements
        }

        var found: ArrayExprSyntax?
        for item in statements {
            switch item.item {
            case .expr(let expr):
                if let array = expr.as(ArrayExprSyntax.self) { found = array }
            case .stmt(let stmt):
                if let returnStmt = stmt.as(ReturnStmtSyntax.self), let array = returnStmt.expression?.as(ArrayExprSyntax.self) {
                    found = array
                }
            case .decl:
                continue
            }
        }
        return found
    }

    // MARK: - KAS002

    private func checkBuilderCall(_ node: FunctionCallExprSyntax) {
        guard let callee = builderCallee(node), let index = identifierArgumentIndex[callee.name] else { return }
        // `descendant` is a scoped child on any `KassElement`; every other
        // builder is one of `KassScreen`'s own, so only an unqualified call or
        // one on `self` is ours — not a same-named method on another type
        // (e.g. `cells().element(at:)` or `alert.button(title)`).
        guard callee.name == "descendant" || callee.onSelf else { return }
        let arguments = Array(node.arguments)
        guard index < arguments.count else { return }
        let argument = arguments[index]
        // The identifier builders take the id as an *unlabeled* argument; a
        // labelled argument at that position is a different API (`element(at:)`).
        guard argument.label == nil else { return }
        guard !isStaticStringLiteral(argument.expression) else { return }
        report(
            argument.expression, rule: .kas002,
            message: "element identifier is not a static string literal; it can't be statically audited or enforced (KAS002)"
        )
    }

    /// The bare method name of a call and whether it targets `self` — either an
    /// unqualified call (`button("id")`) or an explicit `self.button("id")`.
    private func builderCallee(_ node: FunctionCallExprSyntax) -> (name: String, onSelf: Bool)? {
        if let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return (identifier.baseName.text, true)
        }
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let onSelf = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self)
            return (member.declName.baseName.text, onSelf)
        }
        return nil
    }

    private func isStaticStringLiteral(_ expr: ExprSyntax) -> Bool {
        guard let literal = expr.as(StringLiteralExprSyntax.self) else { return false }
        return literal.segments.allSatisfy { $0.is(StringSegmentSyntax.self) }
    }

    // MARK: - Reporting

    private func report(_ node: some SyntaxProtocol, rule: Diagnostic.Rule, message: String) {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        diagnostics.append(Diagnostic(
            file: filePath, line: location.line, column: location.column,
            rule: rule, severity: .warning, message: message
        ))
    }
}
