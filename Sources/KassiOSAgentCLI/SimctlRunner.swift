import Foundation

/// Runs an allowlisted ``AgentCommand`` by shelling out to `xcrun simctl`.
struct SimctlRunner {

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
        process.waitUntilExit()

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ok = process.terminationStatus == 0
        return AgentResponse(
            ok: ok,
            output: out.trimmingCharacters(in: .whitespacesAndNewlines),
            error: ok ? nil : (err.isEmpty ? "simctl exited \(process.terminationStatus)" : err.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }
}
