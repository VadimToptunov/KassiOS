import Foundation
import KassiOSLintCore

var strict = false
var paths: [String] = []
for argument in CommandLine.arguments.dropFirst() {
    if argument == "--strict" {
        strict = true
    } else {
        paths.append(argument)
    }
}
if paths.isEmpty { paths = ["."] }

/// Every `.swift` file under `path` (or `path` itself if it's a file).
func swiftFiles(under path: String) -> [String] {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
    guard isDirectory.boolValue else {
        return path.hasSuffix(".swift") ? [path] : []
    }
    guard let enumerator = fileManager.enumerator(atPath: path) else { return [] }
    var files: [String] = []
    for case let relativePath as String in enumerator where relativePath.hasSuffix(".swift") {
        guard !relativePath.contains(".build/") else { continue }
        files.append((path as NSString).appendingPathComponent(relativePath))
    }
    return files
}

var diagnostics: [Diagnostic] = []
for path in paths {
    for file in swiftFiles(under: path) {
        guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
        diagnostics.append(contentsOf: lint(source: source, filePath: file))
    }
}

for diagnostic in diagnostics.sorted(by: { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }) {
    print("\(diagnostic.file):\(diagnostic.line):\(diagnostic.column): \(diagnostic.severity.rawValue): "
        + "\(diagnostic.message) [\(diagnostic.rule.rawValue)]")
}

let hasError = diagnostics.contains { $0.severity == .error }
let shouldFail = hasError || (strict && !diagnostics.isEmpty)
exit(shouldFail ? 1 : 0)
