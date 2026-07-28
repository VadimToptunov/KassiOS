import SwiftSyntax
import SwiftParser

/// Statically twins the runtime accessibility-identifier audit: parses Swift
/// source and flags `KassScreen` subclasses that skip the guardrails the
/// runtime can only catch on a live app (an unverifiable `onLoad`, or an
/// element identifier that can't be seen without running the test), plus a
/// soft nudge (KAS003) toward extracting a reusable `KassRobot` out of a
/// test method drowning in inline interactions.
///
/// Base classes are traced across the linted file set: a class counts as a
/// `KassScreen` (or `KassTestCase`/`KassRobot`) subclass if it inherits the
/// root type directly, or inherits any other class already known to be one —
/// computed as a fixpoint over every class declared in the files passed to
/// ``lint(sources:)``, so it resolves any number of hierarchy levels. That
/// means `final class HomeScreen: CBScreen` is recognized even when
/// `CBScreen: KassScreen` lives in a different file. Call ``lint(sources:)``
/// with every linted file at once to get cross-file resolution;
/// ``lint(source:filePath:)`` only sees same-file bases.
public func lint(source: String, filePath: String) -> [Diagnostic] {
    lint(sources: [(source: source, filePath: filePath)])
}

/// Batch entry point: lints every file in `sources` together so base classes
/// declared in one file are resolved for subclasses declared in another. See
/// the type-level doc above for the resolution algorithm.
public func lint(sources: [(source: String, filePath: String)]) -> [Diagnostic] {
    struct ParsedFile {
        let filePath: String
        let tree: SourceFileSyntax
        let converter: SourceLocationConverter
    }

    let files = sources.map { entry -> ParsedFile in
        let tree = Parser.parse(source: entry.source)
        return ParsedFile(filePath: entry.filePath, tree: tree, converter: SourceLocationConverter(fileName: entry.filePath, tree: tree))
    }

    // className -> the type names it lists in its own inheritance clause, and
    // className -> its own declaration node — merged across every file (a
    // same-named class split across files is an edge case we don't need to
    // guard against here; first declaration wins).
    var inheritance: [String: [String]] = [:]
    var classNodesByName: [String: ClassDeclSyntax] = [:]
    for file in files {
        let collector = InheritanceCollector()
        collector.walk(file.tree)
        for (className, bases) in collector.inheritance {
            inheritance[className, default: []].append(contentsOf: bases)
        }
        for (className, node) in collector.classNodes where classNodesByName[className] == nil {
            classNodesByName[className] = node
        }
    }

    let screenBaseNames = transitiveSubclasses(of: "KassScreen", inheritance: inheritance).union(["KassScreen"])
    let testCaseBaseNames = transitiveSubclasses(of: "KassTestCase", inheritance: inheritance).union(["KassTestCase"])
    let robotBaseNames = transitiveSubclasses(of: "KassRobot", inheritance: inheritance).union(["KassRobot"])

    var diagnostics: [Diagnostic] = []
    for file in files {
        let ignoredLines = ignoreIdCommentLines(in: file.tree, converter: file.converter)
        let visitor = ScreenVisitor(
            filePath: file.filePath,
            converter: file.converter,
            screenBaseNames: screenBaseNames,
            testCaseBaseNames: testCaseBaseNames,
            robotBaseNames: robotBaseNames,
            classNodesByName: classNodesByName,
            ignoredLines: ignoredLines
        )
        visitor.walk(file.tree)
        diagnostics.append(contentsOf: visitor.diagnostics)
    }
    return diagnostics
}

/// Records, for every class declared in a file, the type names in its own
/// inheritance clause (unresolved — just the literal text) and the
/// declaration node itself. Feeds ``transitiveSubclasses(of:inheritance:)``
/// and the KAS001 onLoad chain-walk.
private final class InheritanceCollector: SyntaxVisitor {
    private(set) var inheritance: [String: [String]] = [:]
    private(set) var classNodes: [String: ClassDeclSyntax] = [:]

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let bases = (node.inheritanceClause?.inheritedTypes).map { $0.map { $0.type.trimmedDescription } } ?? []
        inheritance[node.name.text, default: []].append(contentsOf: bases)
        if classNodes[node.name.text] == nil { classNodes[node.name.text] = node }
        return .visitChildren
    }
}

/// Fixpoint closure over `inheritance`: every class name that transitively
/// inherits from `root` — directly, or via any number of intermediate bases
/// also declared among the linted files. Runs to a stable point rather than a
/// fixed depth, so any hierarchy depth resolves.
private func transitiveSubclasses(of root: String, inheritance: [String: [String]]) -> Set<String> {
    var known = Set<String>()
    var changed = true
    while changed {
        changed = false
        for (className, bases) in inheritance where !known.contains(className) {
            if bases.contains(root) || bases.contains(where: known.contains) {
                known.insert(className)
                changed = true
            }
        }
    }
    return known
}

/// The set of source lines carrying a real `// kassios:ignore-id` (or `///`)
/// comment, found by walking every token's trivia once — so a marker sitting
/// inside a string-literal argument never counts, only an actual comment.
private func ignoreIdCommentLines(in tree: SourceFileSyntax, converter: SourceLocationConverter) -> Set<Int> {
    var lines: Set<Int> = []
    for token in tree.tokens(viewMode: .sourceAccurate) {
        var position = token.position
        for piece in token.leadingTrivia {
            if isIgnoreIdComment(piece) {
                lines.insert(converter.location(for: position).line)
            }
            position += piece.sourceLength
        }
        position = token.endPositionBeforeTrailingTrivia
        for piece in token.trailingTrivia {
            if isIgnoreIdComment(piece) {
                lines.insert(converter.location(for: position).line)
            }
            position += piece.sourceLength
        }
    }
    return lines
}

private func isIgnoreIdComment(_ piece: TriviaPiece) -> Bool {
    switch piece {
    case .lineComment(let text), .docLineComment(let text):
        return text.contains("kassios:ignore-id")
    default:
        return false
    }
}
