import Foundation
import KassiOSMutants

// kassios-mutants: run each mutant's tests with the defect injected and check they
// turn red. Usage:
//
//   kassios-mutants mutants.json [--clean] [--only id,id] [--log-dir dir] [--parallel n]
//
//   --clean     first run every named test without a defect; they must all pass
//   --only      run just these mutants
//   --log-dir   keep each xcodebuild log here (default: a temp directory)
//   --parallel  run n defects at once, each on its own clone of the destination
//               simulator (needs "action": "test-without-building")
//
// Exit code 0 when every mutant is killed (and the clean run passed), 1 otherwise.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("kassios-mutants: \(message)\n".utf8))
    exit(2)
}

let usage = "usage: kassios-mutants mutants.json [--clean] [--only id,id] [--log-dir dir] [--parallel n]"
var args = Array(CommandLine.arguments.dropFirst())
guard let manifestPath = args.first, !manifestPath.hasPrefix("--") else { fail(usage) }
args.removeFirst()
let runClean = args.contains("--clean")
@MainActor func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}
let only = option("--only").map { Set($0.split(separator: ",").map(String.init)) }
let logDir = URL(fileURLWithPath: option("--log-dir") ?? NSTemporaryDirectory() + "kassios-mutants-\(getpid())")
try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
guard let parallel = Int(option("--parallel") ?? "1"), parallel >= 1 else { fail("--parallel takes a number ≥ 1") }

let manifest: MutantManifest
do {
    manifest = try MutantManifest.load(try Data(contentsOf: URL(fileURLWithPath: manifestPath)))
} catch {
    fail("can't read \(manifestPath): \(error)")
}

var udids: [String] = []
if parallel > 1 {
    guard manifest.action == "test-without-building" else {
        fail("--parallel needs \"action\": \"test-without-building\": parallel builds would share one DerivedData")
    }
    let source: String
    do {
        let destination = try SimulatorDestination.value(in: manifest.xcodebuild)
        let list = SimulatorClones.simctl(["list", "devices", "available", "-j"])
        source = try SimulatorDestination.udid(for: destination, simctlJSON: Data(list.utf8))
    } catch {
        fail("\(error)")
    }
    print("› cloning \(source) for \(parallel) workers")
    udids = SimulatorClones.make(from: source, count: parallel)
}
let clones = Array(udids.dropFirst())

// Ctrl-C or a CI cancel still deletes the clones.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stopSources = [SIGINT, SIGTERM].map { number in
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler {
        Running.shared.terminateAll()
        SimulatorClones.delete(clones)
        exit(130)
    }
    source.resume()
    return source
}

final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var clean: [TestOutcome] = []
    private(set) var verdicts: [(id: String, verdict: MutantVerdict)] = []

    func add(_ job: MutantJob, _ outcomes: [TestOutcome], _ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let time = "\(Int(seconds.rounded()))s"
        if let defect = job.defect {
            let verdict = MutantVerdict.evaluate(expected: job.tests, outcomes: outcomes)
            verdicts.append((defect, verdict))
            print("› \(defect): \(job.tests.count) test(s), \(verdict.label), \(time)")
        } else {
            clean += outcomes
            print("› \(job.name): \(job.tests.count) test(s), \(time)")
        }
    }
}

let jobs = MutantPlan.jobs(manifest, clean: runClean, only: only, workers: max(1, udids.count))
let results = Results()
let start = Date()
MutantRunner(manifest: manifest, logDir: logDir).runAll(jobs, udids: udids, finished: results.add)
SimulatorClones.delete(clones)

var ok = true
if runClean {
    let failures = CleanCheck.failures(expected: manifest.allTests, outcomes: results.clean)
    if failures.isEmpty {
        print("\nclean run: all \(manifest.allTests.count) green")
    } else {
        ok = false
        print("\nnot green without a defect, so their kills prove nothing:\n" + failures.map { "    \($0)" }.joined(separator: "\n"))
    }
}

print("\n" + MutantReport.table(results.verdicts))
print("\(Int(Date().timeIntervalSince(start).rounded()))s on \(max(1, udids.count)) simulator(s)")
print("logs: \(logDir.path)")
if results.verdicts.contains(where: { $0.verdict != .killed }) { ok = false }
withExtendedLifetime(stopSources) {}
exit(ok ? 0 : 1)
