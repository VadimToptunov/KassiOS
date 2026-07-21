/// One finding reported by ``lint(source:filePath:)``.
public struct Diagnostic: Codable, Equatable, Sendable {

    /// The rule that fired.
    public enum Rule: String, Codable, Sendable {
        /// A `KassScreen` subclass with no non-empty `onLoad`.
        case kas001 = "KAS001"
        /// An element-builder call whose identifier isn't a static string literal.
        case kas002 = "KAS002"
    }

    /// How strictly the CLI should treat this finding.
    public enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    public let file: String
    public let line: Int
    public let column: Int
    public let rule: Rule
    public let severity: Severity
    public let message: String

    public init(file: String, line: Int, column: Int, rule: Rule, severity: Severity, message: String) {
        self.file = file
        self.line = line
        self.column = column
        self.rule = rule
        self.severity = severity
        self.message = message
    }
}
