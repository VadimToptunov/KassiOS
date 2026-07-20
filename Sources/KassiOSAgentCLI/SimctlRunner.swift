import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Runs an allowlisted ``AgentCommand`` by shelling out to `xcrun simctl`.
struct SimctlRunner {

    /// Thread-safe accumulator for a pipe drained on a background queue.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
        func append(_ chunk: Data) { lock.lock(); storage.append(chunk); lock.unlock() }
    }

    func run(_ command: AgentCommand, udid: String) -> AgentResponse {
        var arguments = command.simctlArguments(udid: udid)

        // `push` needs a payload file; write the JSON to a temp file and swap it
        // in for the "<payload-file>" placeholder.
        var tempFile: URL?
        if case let .pushNotification(_, payloadJSON) = command {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kassios-push-\(UUID().uuidString).json")
            do {
                try Data(payloadJSON.utf8).write(to: url)
                tempFile = url
                if let index = arguments.firstIndex(of: "<payload-file>") {
                    arguments[index] = url.path
                }
            } catch {
                return AgentResponse(ok: false, error: "could not write push payload: \(error)")
            }
        }
        defer { if let tempFile = tempFile { try? FileManager.default.removeItem(at: tempFile) } }

        return exec(["simctl"] + arguments)
    }

    /// Executes `xcrun` with `arguments`, capturing output and exit status.
    private func exec(_ arguments: [String]) -> AgentResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return AgentResponse(ok: false, error: "failed to launch xcrun: \(error)")
        }

        // Drain both pipes concurrently with the wait: reading them sequentially
        // after `waitUntilExit()` deadlocks if the child fills a pipe buffer
        // (~64KB) on the stream we're not yet reading.
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        for (fd, box) in [(stdout.fileHandleForReading.fileDescriptor, outBox),
                          (stderr.fileHandleForReading.fileDescriptor, errBox)] {
            group.enter()
            DispatchQueue.global().async {
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = read(fd, &buffer, buffer.count)
                    if count <= 0 { break }
                    box.append(Data(buffer[0..<count]))
                }
                group.leave()
            }
        }
        process.waitUntilExit()
        group.wait()

        let out = String(data: outBox.data, encoding: .utf8) ?? ""
        let err = String(data: errBox.data, encoding: .utf8) ?? ""
        let ok = process.terminationStatus == 0
        let trimmedErr = err.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentResponse(
            ok: ok,
            output: out.trimmingCharacters(in: .whitespacesAndNewlines),
            error: ok ? nil : (trimmedErr.isEmpty ? "simctl exited \(process.terminationStatus)" : trimmedErr)
        )
    }
}
