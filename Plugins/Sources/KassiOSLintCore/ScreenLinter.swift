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
/// `KassScreen` (or `KassTestCase`/`KassRobot`) subclass if its own
/// superclass — Swift requires it, if any, to be the *first* entry in the
/// inheritance clause, so protocol conformances listed after it are ignored —
/// is the root type directly, or is any other class already known to be one.
/// This is computed as a fixpoint over every class declared in the files
/// passed to ``lint(sources:)``, so it resolves any number of hierarchy
/// levels. That means `final class HomeScreen: CBScreen` is recognized even
/// when `CBScreen: KassScreen` lives in a different file. Call
/// ``lint(sources:)`` with every linted file at once to get cross-file
/// resolution; ``lint(source:filePath:)`` resolves bases within that one file
/// only.
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

    // className -> its *candidate* superclass name (the first entry in its
    // inheritance clause, unresolved), className -> its own declaration node,
    // and every protocol name declared anywhere — merged across every file (a
    // same-named class split across files is an edge case we don't need to
    // guard against here; first declaration wins).
    var superclassCandidates: [String: String] = [:]
    var classNodesByName: [String: ClassDeclSyntax] = [:]
    var protocolNames: Set<String> = []
    for file in files {
        let collector = InheritanceCollector()
        collector.walk(file.tree)
        for (className, candidate) in collector.superclassCandidates where superclassCandidates[className] == nil {
            superclassCandidates[className] = candidate
        }
        for (className, node) in collector.classNodes where classNodesByName[className] == nil {
            classNodesByName[className] = node
        }
        protocolNames.formUnion(collector.protocolNames)
    }

    // Resolve each class's candidate into an actual superclass name now that
    // every protocol declared in the linted set is known (a candidate that's
    // really a locally-declared protocol — shadowing a well-known root's
    // literal name — isn't a superclass at all; see `resolveSuperclass`).
    var inheritance: [String: [String]] = [:]
    for (className, candidate) in superclassCandidates {
        if let resolved = resolveSuperclass(candidate, protocolNames: protocolNames) {
            inheritance[className] = [resolved]
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
            protocolNames: protocolNames,
            ignoredLines: ignoredLines
        )
        visitor.walk(file.tree)
        diagnostics.append(contentsOf: visitor.diagnostics)
    }
    return diagnostics
}

/// Records, for every class declared in a file, its *candidate* superclass
/// name (the first entry in its inheritance clause, unresolved — Swift
/// requires an actual superclass, if any, to be listed first; everything
/// after it is protocol conformance) and the declaration node itself. Also
/// records every protocol name declared in the file. Feeds
/// ``resolveSuperclass(_:protocolNames:)``,
/// ``transitiveSubclasses(of:inheritance:)``, and the KAS001 onLoad
/// chain-walk.
private final class InheritanceCollector: SyntaxVisitor {
    private(set) var superclassCandidates: [String: String] = [:]
    private(set) var classNodes: [String: ClassDeclSyntax] = [:]
    private(set) var protocolNames: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if let candidate = node.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription {
            superclassCandidates[node.name.text] = candidate
        }
        if classNodes[node.name.text] == nil { classNodes[node.name.text] = node }
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolNames.insert(node.name.text)
        return .visitChildren
    }
}

/// The class's actual superclass name, if any. `candidate` is the first entry
/// in the inheritance clause — Swift requires the superclass, when one is
/// declared, to be listed first — but a class with no superclass at all can
/// also have a *protocol* as its first (and only) entry, syntactically
/// indistinguishable from a superclass reference. Cross-checking `candidate`
/// against every protocol name declared in the linted file set catches the
/// case where that name shadows a well-known root (e.g. a local
/// `protocol KassRobot {}`): such a candidate is a conformance, not a base
/// class, so it resolves to `nil`.
func resolveSuperclass(_ candidate: String?, protocolNames: Set<String>) -> String? {
    guard let candidate, !protocolNames.contains(candidate) else { return nil }
    return candidate
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
