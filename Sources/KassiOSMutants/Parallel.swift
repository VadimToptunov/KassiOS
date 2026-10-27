import Foundation

// Splitting a mutants run across simulators: what each simulator runs, and how to
// point xcodebuild at a given one. The CLI clones the simulators and runs the jobs.

/// One xcodebuild run: `tests`, with `defect` injected (`nil` for the clean run).
public struct MutantJob: Equatable, Sendable {
    public let name: String
    public let tests: [String]
    public let defect: String?

    public init(name: String, tests: [String], defect: String?) {
        self.name = name
        self.tests = tests
        self.defect = defect
    }
}

public enum MutantPlan {

    /// The clean run split into one part per worker, so it takes no longer than the
    /// first defects, then one job per defect in id order. Parts are cut by test
    /// class, so a class's tests share one launch sequence.
    public static func jobs(_ manifest: MutantManifest, clean: Bool, only: Set<String>?, workers: Int) -> [MutantJob] {
        var jobs: [MutantJob] = []
        if clean {
            let parts = cleanParts(manifest.allTests, workers: max(1, workers))
            for (index, tests) in parts.enumerated() {
                jobs.append(MutantJob(name: parts.count == 1 ? "clean" : "clean-\(index + 1)", tests: tests, defect: nil))
            }
        }
        for id in manifest.mutants.keys.sorted() where only?.contains(id) ?? true {
            jobs.append(MutantJob(name: id, tests: manifest.mutants[id] ?? [], defect: id))
        }
        return jobs
    }

    /// True when xcodebuild reported none of the job's tests: the runner never
    /// started ("Busy", a simulator that didn't boot). Worth one more try, since
    /// no verdict was reached. A run where some tests reported is never retried.
    public static func ranNothing(_ job: MutantJob, outcomes: [TestOutcome]) -> Bool {
        !job.tests.contains { name in
            guard let id = TestID(name) else { return false }
            return outcomes.contains { $0.testClass == id.testClass && $0.method == id.method }
        }
    }

    /// Classes go, largest first, to whichever part has the fewest tests so far.
    static func cleanParts(_ tests: [String], workers: Int) -> [[String]] {
        var byClass: [String: [String]] = [:]
        for test in tests {
            let key = TestID(test).map { "\($0.target)/\($0.testClass)" } ?? test
            byClass[key, default: []].append(test)
        }
        let classes = byClass.sorted { ($1.value.count, $0.key) < ($0.value.count, $1.key) }
        var parts = Array(repeating: [String](), count: min(workers, max(1, classes.count)))
        for (_, members) in classes {
            let smallest = parts.indices.min { (parts[$0].count, $0) < (parts[$1].count, $1) } ?? 0
            parts[smallest] += members
        }
        return parts.filter { !$0.isEmpty }.map { $0.sorted() }
    }
}

public enum SimulatorDestination {

    /// The value after `-destination`, if there is exactly one.
    public static func value(in arguments: [String]) throws -> String {
        let indices = arguments.indices.filter { arguments[$0] == "-destination" }
        guard indices.count == 1, let index = indices.first, index + 1 < arguments.count else {
            throw MutantError("--parallel needs exactly one -destination in the manifest's xcodebuild arguments")
        }
        return arguments[index + 1]
    }

    /// `arguments` with the destination pointed at the simulator `udid`.
    public static func pointing(_ arguments: [String], at udid: String) -> [String] {
        var out = arguments
        if let index = out.firstIndex(of: "-destination"), index + 1 < out.count {
            out[index + 1] = "platform=iOS Simulator,id=\(udid)"
        }
        return out
    }

    /// The udid of the simulator a destination names (`id=`, or `name=` with an
    /// optional `OS=`), looked up in `xcrun simctl list devices available -j`.
    public static func udid(for destination: String, simctlJSON: Data) throws -> String {
        var fields: [String: String] = [:]
        for pair in destination.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        if let id = fields["id"] { return id }
        guard let name = fields["name"] else {
            throw MutantError("destination '\(destination)' names no simulator (need id= or name=)")
        }
        let os = fields["OS"].flatMap { $0 == "latest" ? nil : $0 }

        struct Device: Decodable { let udid: String; let name: String; let state: String }
        struct List: Decodable { let devices: [String: [Device]] }
        let list = try JSONDecoder().decode(List.self, from: simctlJSON)
        // Newest runtime first, so a bare name means what xcodebuild would pick.
        let runtimes = list.devices.keys.filter { $0.contains(".iOS-") }
            .sorted { runtimeVersion($1).lexicographicallyPrecedes(runtimeVersion($0)) }
        for runtime in runtimes {
            if let os, !runtimeMatches(runtime, os: os) { continue }
            if let device = list.devices[runtime]?.first(where: { $0.name == name }) { return device.udid }
        }
        throw MutantError("no available simulator matches '\(destination)'")
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-27-0` → [27, 0].
    static func runtimeVersion(_ runtime: String) -> [Int] {
        guard let range = runtime.range(of: ".iOS-") else { return [] }
        return runtime[range.upperBound...].split(separator: "-").compactMap { Int($0) }
    }

    /// `OS=27` and `OS=27.0` both match the 27.0 runtime.
    static func runtimeMatches(_ runtime: String, os: String) -> Bool {
        var wanted = os.split(separator: ".").compactMap { Int($0) }
        var have = runtimeVersion(runtime)
        while wanted.last == 0 { wanted.removeLast() }
        while have.last == 0 { have.removeLast() }
        return !wanted.isEmpty && wanted == have
    }
}

public enum MutantCommand {

    /// The xcodebuild arguments for one job. Each job writes its own result bundle,
    /// since runs started in the same second would otherwise share a name in
    /// DerivedData. Diagnostics collection is off: a mutant run is meant to fail,
    /// and collecting a sysdiagnose per failure can stall xcodebuild for minutes
    /// after the tests have finished.
    public static func arguments(_ manifest: MutantManifest, job: MutantJob, udid: String?, resultBundle: String) -> [String] {
        var arguments = udid.map { SimulatorDestination.pointing(manifest.xcodebuild, at: $0) } ?? manifest.xcodebuild
        if !arguments.contains("-resultBundlePath") { arguments += ["-resultBundlePath", resultBundle] }
        if !arguments.contains("-collect-test-diagnostics") { arguments += ["-collect-test-diagnostics", "never"] }
        return ["xcodebuild", manifest.action] + arguments + job.tests.map { "-only-testing:\($0)" }
    }
}
