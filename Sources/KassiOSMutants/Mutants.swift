import Foundation

// The logic behind `kassios-mutants`: which tests must turn red under which injected
// defect, how to read xcodebuild's verdicts, and what counts as killed. No process
// handling here, so all of it is unit-tested.

/// The input file. Each mutant names the tests that must fail while it is injected.
///
/// ```json
/// {
///   "xcodebuild": ["-project", "App.xcodeproj", "-scheme", "AppUITests",
///                  "-destination", "platform=iOS Simulator,name=iPhone 17"],
///   "inject": "TEST_RUNNER_CB_INJECT_DEFECTS",
///   "mutants": {
///     "successToastMissing": ["AppUITests/TransferTests/test_transfer_happyPath_completes"]
///   }
/// }
/// ```
///
/// `inject` is the environment variable set to the mutant's id for the run (with
/// xcodebuild, a `TEST_RUNNER_` prefix reaches the test runner without it).
public struct MutantManifest: Decodable, Sendable, Equatable {
    public let xcodebuild: [String]
    public let inject: String
    public let mutants: [String: [String]]

    public init(xcodebuild: [String], inject: String, mutants: [String: [String]]) {
        self.xcodebuild = xcodebuild
        self.inject = inject
        self.mutants = mutants
    }

    public static func load(_ data: Data) throws -> MutantManifest {
        let manifest = try JSONDecoder().decode(MutantManifest.self, from: data)
        for (id, tests) in manifest.mutants {
            guard !tests.isEmpty else { throw MutantError("mutant '\(id)' names no tests") }
            for test in tests where TestID(test) == nil {
                throw MutantError("mutant '\(id)': '\(test)' isn't Target/Class/method")
            }
        }
        return manifest
    }

    /// Every test any mutant names, for the clean run.
    public var allTests: [String] { Array(Set(mutants.values.flatMap { $0 })).sorted() }
}

public struct MutantError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// `Target/Class/method`, as `xcodebuild -only-testing` takes it.
public struct TestID: Hashable, Sendable, CustomStringConvertible {
    public let target: String
    public let testClass: String
    public let method: String

    public init?(_ text: String) {
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        (target, testClass, method) = (parts[0], parts[1], parts[2])
    }

    public var description: String { "\(target)/\(testClass)/\(method)" }
}

/// One test's outcome as xcodebuild printed it.
public struct TestOutcome: Hashable, Sendable {
    public let testClass: String
    public let method: String
    public let passed: Bool
}

public enum XcodebuildLog {

    /// The `Test Case '-[Module.Class method]' passed|failed` lines of an xcodebuild
    /// log. A test retried by `-retry-tests-on-failure` reports more than once; the
    /// last line wins.
    public static func outcomes(_ log: String) -> [TestOutcome] {
        var latest: [String: TestOutcome] = [:]
        var order: [String] = []
        for line in log.split(separator: "\n") {
            guard let open = line.range(of: "Test Case '-["), let close = line.range(of: "]'", range: open.upperBound..<line.endIndex)
            else { continue }
            let rest = line[close.upperBound...]
            let passed: Bool
            if rest.hasPrefix(" passed") { passed = true } else if rest.hasPrefix(" failed") { passed = false } else { continue }
            let name = line[open.upperBound..<close.lowerBound].split(separator: " ")
            guard name.count == 2 else { continue }
            let testClass = String(name[0].split(separator: ".").last ?? name[0])
            let key = "\(testClass)/\(name[1])"
            if latest[key] == nil { order.append(key) }
            latest[key] = TestOutcome(testClass: testClass, method: String(name[1]), passed: passed)
        }
        return order.compactMap { latest[$0] }
    }
}

/// What one mutant run means.
public enum MutantVerdict: Equatable, Sendable {
    /// Every named test failed.
    case killed
    /// These named tests passed with the defect in.
    case survived([String])
    /// These named tests produced no result (build failure, wrong name, crash before the test).
    case noResult([String])

    public static func evaluate(expected: [String], outcomes: [TestOutcome]) -> MutantVerdict {
        var passed: [String] = []
        var missing: [String] = []
        for name in expected {
            guard let id = TestID(name) else { missing.append(name); continue }
            guard let outcome = outcomes.first(where: { $0.testClass == id.testClass && $0.method == id.method }) else {
                missing.append(name); continue
            }
            if outcome.passed { passed.append(name) }
        }
        if !missing.isEmpty { return .noResult(missing) }
        return passed.isEmpty ? .killed : .survived(passed)
    }

    public var label: String {
        switch self {
        case .killed: return "killed"
        case .survived: return "SURVIVED"
        case .noResult: return "NO RESULT"
        }
    }
}

/// The clean run's meaning: every named test must pass without a defect, or a
/// "kill" proves nothing.
public enum CleanCheck {
    public static func failures(expected: [String], outcomes: [TestOutcome]) -> [String] {
        expected.filter { name in
            guard let id = TestID(name) else { return true }
            return !outcomes.contains { $0.testClass == id.testClass && $0.method == id.method && $0.passed }
        }
    }
}

/// A plain-text table of the results, worst first.
public enum MutantReport {
    public static func table(_ results: [(id: String, verdict: MutantVerdict)]) -> String {
        let rank: (MutantVerdict) -> Int = { verdict in
            switch verdict {
            case .survived: return 0
            case .noResult: return 1
            case .killed: return 2
            }
        }
        let rows = results.sorted { (rank($0.verdict), $0.id) < (rank($1.verdict), $1.id) }
        let width = max(6, rows.map(\.id.count).max() ?? 0)
        var out = "mutant".padding(toLength: width, withPad: " ", startingAt: 0) + "  verdict\n"
        for row in rows {
            var line = row.id.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + row.verdict.label
            switch row.verdict {
            case .survived(let tests): line += "  (still green: \(tests.joined(separator: ", ")))"
            case .noResult(let tests): line += "  (no result: \(tests.joined(separator: ", ")))"
            case .killed: break
            }
            out += line + "\n"
        }
        let killed = results.filter { $0.verdict == .killed }.count
        out += "\n\(killed) of \(results.count) killed\n"
        return out
    }
}
