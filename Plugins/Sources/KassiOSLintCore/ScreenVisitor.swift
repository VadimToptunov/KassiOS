import SwiftSyntax

/// The builder methods audited by KAS002, and which positional argument holds
/// the identifier. `descendant` takes the element type first, so its
/// identifier is the *second* argument; every other builder takes the
/// identifier first.
private let identifierArgumentIndex: [String: Int] = [
    "button": 0, "staticText": 0, "textField": 0, "secureTextField": 0,
    "image": 0, "cell": 0, "switchControl": 0, "link": 0, "other": 0,
    "element": 0, "descendant": 1
]

/// KAS003's fixed interaction vocabulary — element-mutating calls that belong
/// in a `KassRobot`, not inlined by the dozen in a test method.
private let interactionMethodNames: Set<String> = [
    "tap", "doubleTap", "typeText", "clearText", "replaceText", "longPress",
    "swipeUp", "swipeDown", "swipeLeft", "swipeRight", "setSwitch",
    "adjustSlider", "adjustPicker", "scrollTo", "drag"
]

/// KAS003 only fires inside a method whose test class qualifies, and never
/// inside a `KassRobot` subclass (that's where the interactions belong).
private let kas003InteractionThreshold = 5

/// Walks one file's syntax tree and reports KAS001/KAS002/KAS003. Base-class
/// membership (`screenBaseNames`/`testCaseBaseNames`/`robotBaseNames`) and the
/// `// kassios:ignore-id` suppression set are resolved once, up front, by
/// ``lint(sources:)`` and handed in — this type only does the per-file walk.
final class ScreenVisitor: SyntaxVisitor {
    private let filePath: String
    private let converter: SourceLocationConverter
    private let screenBaseNames: Set<String>
    private let testCaseBaseNames: Set<String>
    private let robotBaseNames: Set<String>
    private let classNodesByName: [String: ClassDeclSyntax]
    private let ignoredLines: Set<Int>
    private(set) var diagnostics: [Diagnostic] = []

    /// Per enclosing class (innermost last): whether it's a recognized
    /// `KassScreen` subclass, and whether test-method interactions inside it
    /// should be counted toward KAS003.
    private struct ClassContext {
        let isScreen: Bool
        let isTestCase: Bool
        let isRobot: Bool
    }
    private var classStack: [ClassContext] = []

    /// Per enclosing function (innermost last): the interaction tally toward
    /// KAS003, and whether this function is eligible to report it at all.
    private struct FunctionContext {
        let node: FunctionDeclSyntax
        var interactionCount = 0
        let countsTowardKas003: Bool
    }
    private var functionStack: [FunctionContext] = []

    init(
        filePath: String,
        converter: SourceLocationConverter,
        screenBaseNames: Set<String>,
        testCaseBaseNames: Set<String>,
        robotBaseNames: Set<String>,
        classNodesByName: [String: ClassDeclSyntax],
        ignoredLines: Set<Int>
    ) {
        self.filePath = filePath
        self.converter = converter
        self.screenBaseNames = screenBaseNames
        self.testCaseBaseNames = testCaseBaseNames
        self.robotBaseNames = robotBaseNames
        self.classNodesByName = classNodesByName
        self.ignoredLines = ignoredLines
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let inherited = Set((node.inheritanceClause?.inheritedTypes).map { $0.map { $0.type.trimmedDescription } } ?? [])
        let isScreen = !inherited.isDisjoint(with: screenBaseNames)
        let isRobot = !inherited.isDisjoint(with: robotBaseNames)
        let isTestCase = !inherited.isDisjoint(with: testCaseBaseNames)
        classStack.append(ClassContext(isScreen: isScreen, isTestCase: isTestCase, isRobot: isRobot))
        if isScreen {
            checkOnLoad(node)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        classStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let classContext = classStack.last
        let countsTowardKas003 = classContext?.isTestCase == true
            && classContext?.isRobot == false
            && node.name.text.hasPrefix("test")
        functionStack.append(FunctionContext(node: node, countsTowardKas003: countsTowardKas003))
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        let context = functionStack.removeLast()
        guard context.countsTowardKas003, context.interactionCount >= kas003InteractionThreshold else { return }
        report(
            node.name, rule: .kas003,
            message: "test method '\(node.name.text)' has \(context.interactionCount) inline interactions — "
                + "extract a reusable flow into a KassRobot (KAS003)"
        )
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if classStack.last?.isScreen == true {
            checkBuilderCall(node)
        }
        if !functionStack.isEmpty, let name = bareCalleeName(node), interactionMethodNames.contains(name) {
            functionStack[functionStack.count - 1].interactionCount += 1
        }
        return .visitChildren
    }

    // MARK: - KAS001

    private func checkOnLoad(_ node: ClassDeclSyntax) {
        guard isOnLoadEmptyAcrossChain(node) else { return }
        report(node.name, rule: .kas001, message: kas001Message(className: node.name.text))
    }

    /// Whether the *resolved* `onLoad` is missing or empty: this class's own
    /// override if it declares one, otherwise the nearest override up the
    /// superclass chain (Swift requires the superclass, if any, to be listed
    /// first in the inheritance clause) among classes declared anywhere in
    /// the linted file set. A subclass that inherits a non-empty `onLoad`
    /// from a traced base without re-declaring it is clean; a chain that
    /// never overrides `onLoad` defaults to `KassScreen`'s own empty `[]`.
    /// Stops at the first unresolved link (an external base, or a protocol).
    private func isOnLoadEmptyAcrossChain(_ node: ClassDeclSyntax) -> Bool {
        var current = node
        var visitedNames: Set<String> = []
        while visitedNames.insert(current.name.text).inserted {
            if let onLoad = onLoadBinding(in: current) {
                guard let arrayLiteral = returnedArrayLiteral(in: onLoad) else {
                    // No directly-visible array literal (e.g. branches, a helper
                    // call) — lenient: assume it's a computed body that supplies
                    // elements.
                    return false
                }
                return arrayLiteral.elements.isEmpty
            }
            guard let superclassName = current.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription,
                  let next = classNodesByName[superclassName] else {
                return true // no onLoad anywhere in the resolvable chain
            }
            current = next
        }
        return true // cycle guard (shouldn't happen for valid Swift)
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
        guard argument.expression.as(StringLiteralExprSyntax.self) == nil else { return }
        // A trailing `// kassios:ignore-id` real comment on the call's own end
        // line suppresses this finding — a reviewed, deliberately dynamic id.
        // Limitation: the check is line-based, so two flagged builder calls on
        // one line share the same suppression; keep one flagged call per line.
        let endLine = converter.location(for: node.endPositionBeforeTrailingTrivia).line
        guard !ignoredLines.contains(endLine) else { return }
        report(
            argument.expression, rule: .kas002,
            message: "element identifier is not a string literal (a bare variable or call); it can't be "
                + "statically audited or enforced — an interpolated literal is fine, or suppress a reviewed case with "
                + "a same-line `// kassios:ignore-id` comment (KAS002)"
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

    // MARK: - KAS003

    /// The bare method name of any call, regardless of receiver — KAS003
    /// counts an interaction wherever it's called (`row.tap()`, `$0.tap()`),
    /// unlike KAS002's builder check, which only owns `self`'s own methods.
    /// Reuses ``builderCallee(_:)``'s name extraction and just drops the
    /// `onSelf` flag it doesn't need.
    private func bareCalleeName(_ node: FunctionCallExprSyntax) -> String? {
        builderCallee(node)?.name
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
