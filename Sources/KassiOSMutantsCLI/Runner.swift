import Foundation
import KassiOSMutants

/// Runs jobs on a set of simulators, one job per simulator at a time.
struct MutantRunner: Sendable {
    let manifest: MutantManifest
    let logDir: URL

    /// Runs every job, one per simulator at a time, calling `finished` as each ends.
    /// `udids` empty means the manifest's own destination, one job at a time.
    func runAll(_ jobs: [MutantJob], udids: [String], finished: @escaping @Sendable (MutantJob, [TestOutcome], TimeInterval) -> Void) {
        let queue = JobQueue(jobs)
        let workers = udids.isEmpty ? [nil] : udids.map(Optional.some)
        DispatchQueue.concurrentPerform(iterations: workers.count) { index in
            while let job = queue.next() {
                let start = Date()
                var outcomes = run(job, udid: workers[index])
                if MutantPlan.ranNothing(job, outcomes: outcomes) {
                    print("› \(job.name): no test reported, retrying once")
                    outcomes = run(job, udid: workers[index], attempt: 2)
                }
                finished(job, outcomes, Date().timeIntervalSince(start))
            }
        }
    }

    /// Runs `xcodebuild` for the job's tests, with its defect injected if it has one.
    func run(_ job: MutantJob, udid: String?, attempt: Int = 1) -> [TestOutcome] {
        let name = attempt == 1 ? job.name : "\(job.name)-attempt\(attempt)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let bundle = logDir.appendingPathComponent("\(name).xcresult")
        try? FileManager.default.removeItem(at: bundle)
        process.arguments = MutantCommand.arguments(manifest, job: job, udid: udid, resultBundle: bundle.path)
        var environment = ProcessInfo.processInfo.environment
        if let defect = job.defect { environment[manifest.inject] = defect } else { environment.removeValue(forKey: manifest.inject) }
        process.environment = environment
        let logURL = logDir.appendingPathComponent("\(name).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let log = try? FileHandle(forWritingTo: logURL) else { fail("can't write \(logURL.path)") }
        process.standardOutput = log
        process.standardError = log
        do { try process.run() } catch { fail("can't start xcodebuild: \(error)") }
        Running.shared.add(process)
        process.waitUntilExit()
        Running.shared.remove(process)
        try? log.close()
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        return XcodebuildLog.outcomes(text)
    }
}

private final class JobQueue: @unchecked Sendable {
    private var jobs: ArraySlice<MutantJob>
    private let lock = NSLock()

    init(_ jobs: [MutantJob]) { self.jobs = jobs[...] }

    func next() -> MutantJob? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.popFirst()
    }
}

/// The xcodebuild runs in flight, so a stop signal can end them too.
final class Running: @unchecked Sendable {
    static let shared = Running()
    private var processes: [ObjectIdentifier: Process] = [:]
    private let lock = NSLock()

    func add(_ process: Process) { lock.withLock { processes[ObjectIdentifier(process)] = process } }
    func remove(_ process: Process) { _ = lock.withLock { processes.removeValue(forKey: ObjectIdentifier(process)) } }

    func terminateAll() {
        for process in lock.withLock({ Array(processes.values) }) {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

/// Clones of one simulator, one per extra worker, deleted when the run ends.
enum SimulatorClones {
    static let prefix = "kassios-mutants-"

    /// The source simulator plus `count - 1` clones of it.
    static func make(from source: String, count: Int) -> [String] {
        deleteLeftovers()
        // simctl clones only a shut-down device.
        _ = simctl(["shutdown", source])
        var udids = [source]
        for index in 1..<count {
            let output = simctl(["clone", source, "\(prefix)\(getpid())-\(index)"])
            let udid = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard UUID(uuidString: udid) != nil else { delete(Array(udids.dropFirst())); fail("simctl clone failed: \(output)") }
            udids.append(udid)
        }
        return udids
    }

    static func delete(_ udids: [String]) {
        for udid in udids {
            _ = simctl(["shutdown", udid])
            _ = simctl(["delete", udid])
        }
    }

    /// Clones a killed run left behind. A clone's name carries its run's pid, so
    /// those of a run still going are left alone.
    static func deleteLeftovers() {
        let json = Data(simctl(["list", "devices", "-j"]).utf8)
        struct Device: Decodable { let udid: String; let name: String }
        struct List: Decodable { let devices: [String: [Device]] }
        guard let list = try? JSONDecoder().decode(List.self, from: json) else { return }
        let orphans = list.devices.values.flatMap { $0 }.filter { device in
            guard device.name.hasPrefix(prefix) else { return false }
            let pid = device.name.dropFirst(prefix.count).split(separator: "-").first.flatMap { Int32($0) }
            return pid.map { kill($0, 0) != 0 } ?? true
        }
        delete(orphans.map(\.udid))
    }

    /// Runs `xcrun simctl`, returning stdout and stderr.
    static func simctl(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
