import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// `kassios-agent` — a tiny host-side bridge that lets an in-simulator UI test
/// drive `simctl` (permissions, push, location, status-bar, appearance).
///
/// Security posture (this shells out to the host — treat it like it):
///  - Binds **127.0.0.1 only**. Never `0.0.0.0`.
///  - Requires a token (env `KASSIOS_AGENT_TOKEN`) on every request.
///  - Runs an **allowlisted** `simctl` command set — never arbitrary argv.
///  - The caller supplies the target `udid` per request (parallel-safe).
@main
struct Agent {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["KASSIOS_AGENT_TOKEN"], !token.isEmpty else {
            FileHandle.standardError.write(Data("kassios-agent: set KASSIOS_AGENT_TOKEN\n".utf8))
            exit(2)
        }
        let port = UInt16(env["KASSIOS_AGENT_PORT"] ?? "8437") ?? 8437
        let runner = SimctlRunner()
        do {
            let server = try HTTPServer(port: port)
            writeDiscoveryFile(port: port, token: token)
            FileHandle.standardError.write(Data("kassios-agent: listening on 127.0.0.1:\(port)\n".utf8))
            server.serve { body in
                handle(body: body, token: token, runner: runner)
            }
        } catch {
            FileHandle.standardError.write(Data("kassios-agent: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Decodes a request, checks the token, runs the command. Returns the JSON
    /// response body.
    static func handle(body: Data, token: String, runner: SimctlRunner) -> Data {
        let encoder = JSONEncoder()
        func encode(_ response: AgentResponse) -> Data {
            (try? encoder.encode(response)) ?? Data("{\"ok\":false}".utf8)
        }
        guard let request = try? JSONDecoder().decode(AgentRequest.self, from: body) else {
            return encode(AgentResponse(ok: false, error: "malformed request"))
        }
        guard constantTimeEquals(request.token, token) else {
            return encode(AgentResponse(ok: false, error: "unauthorized"))
        }
        return encode(runner.run(request.command, udid: request.udid))
    }

    /// Constant-time token comparison — over loopback there's no network jitter
    /// to mask a short-circuiting `==`, so compare every byte regardless.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8), right = Array(rhs.utf8)
        var diff = UInt8(left.count == right.count ? 0 : 1)
        for index in 0..<Swift.max(left.count, right.count) {
            diff |= (index < left.count ? left[index] : 0) ^ (index < right.count ? right[index] : 0)
        }
        return diff == 0
    }

    /// Publishes the port + token to `~/.kassios-agent.json` so the in-simulator
    /// test runner can discover the agent via `$SIMULATOR_HOST_HOME` — the only
    /// channel that reliably reaches the runner (scheme env vars go to the app,
    /// not the runner; `SIMCTL_CHILD_` isn't honoured by xcodebuild's launch).
    /// Written 0600 since it holds the token.
    static func writeDiscoveryFile(port: UInt16, token: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kassios-agent.json")
        let payload = ["port": String(port), "token": token]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        // Create the file 0600 from the start — never a world-readable window
        // (the token lives here). Remove any stale copy first so the mode sticks.
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    }
}
