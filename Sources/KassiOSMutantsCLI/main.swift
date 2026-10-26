import Foundation
import KassiOSMutants

// kassios-mutants: run each mutant's tests with the defect injected and check they
// turn red. Usage:
//
//   kassios-mutants mutants.json [--clean] [--only id,id] [--log-dir dir]
//
//   --clean     first run every named test without a defect; they must all pass
//   --only      run just these mutants
//   --log-dir   keep each xcodebuild log here (default: a temp directory)
//
// Exit code 0 when every mutant is killed (and the clean run passed), 1 otherwise.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("kassios-mutants: \(message)\n".utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let manifestPath = args.first, !manifestPath.hasPrefix("--") else {
    fail("usage: kassios-mutants mutants.json [--clean] [--only id,id] [--log-dir dir]")
}
args.removeFirst()
let runClean = args.contains("--clean")
@MainActor func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}
let only = option("--only").map { Set($0.split(separator: ",").map(String.init)) }
let logDir = URL(fileURLWithPath: option("--log-dir") ?? NSTemporaryDirectory() + "kassios-mutants-\(getpid())")
try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

let manifest: MutantManifest
do {
    manifest = try MutantManifest.load(try Data(contentsOf: URL(fileURLWithPath: manifestPath)))
} catch {
    fail("can't read \(manifestPath): \(error)")
}

/// Runs `xcodebuild test` for `tests`, with `defect` injected if given; returns the outcomes.
@MainActor func run(_ tests: [String], defect: String?, logName: String) -> [TestOutcome] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["xcodebuild", manifest.action] + manifest.xcodebuild + tests.map { "-only-testing:\($0)" }
    var environment = ProcessInfo.processInfo.environment
    if let defect { environment[manifest.inject] = defect } else { environment.removeValue(forKey: manifest.inject) }
    process.environment = environment
    let logURL = logDir.appendingPathComponent("\(logName).log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    guard let log = try? FileHandle(forWritingTo: logURL) else { fail("can't write \(logURL.path)") }
    process.standardOutput = log
    process.standardError = log
    do { try process.run() } catch { fail("can't start xcodebuild: \(error)") }
    process.waitUntilExit()
    try? log.close()
    let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    return XcodebuildLog.outcomes(text)
}

var ok = true

if runClean {
    print("› clean run: \(manifest.allTests.count) tests")
    let failures = CleanCheck.failures(expected: manifest.allTests, outcomes: run(manifest.allTests, defect: nil, logName: "clean"))
    if failures.isEmpty {
        print("  all green\n")
    } else {
        ok = false
        print("  not green without a defect, so their kills prove nothing:\n" + failures.map { "    \($0)" }.joined(separator: "\n") + "\n")
    }
}

var results: [(id: String, verdict: MutantVerdict)] = []
for id in manifest.mutants.keys.sorted() where only?.contains(id) ?? true {
    let tests = manifest.mutants[id] ?? []
    print("› \(id): \(tests.count) test(s)")
    let verdict = MutantVerdict.evaluate(expected: tests, outcomes: run(tests, defect: id, logName: id))
    print("  \(verdict.label)")
    results.append((id, verdict))
}

print("\n" + MutantReport.table(results))
print("logs: \(logDir.path)")
if results.contains(where: { $0.verdict != .killed }) { ok = false }
exit(ok ? 0 : 1)
