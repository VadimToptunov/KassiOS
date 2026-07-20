import XCTest

/// Transport to the host-side `kassios-agent`. Configured from the launch
/// environment the test target inherits.
struct KassAgentClient {
    let port: Int
    let token: String
    let udid: String

    /// Builds a client from `KASSIOS_AGENT_PORT` / `KASSIOS_AGENT_TOKEN` /
    /// `SIMULATOR_UDID`, or `nil` if the bridge isn't configured (no agent, or a
    /// real device where `SIMULATOR_UDID` is absent).
    static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> KassAgentClient? {
        guard let udid = env["SIMULATOR_UDID"], !udid.isEmpty else { return nil }
        // Explicit env wins; otherwise discover the agent via the file it wrote
        // to the host home (reachable from the runner through SIMULATOR_HOST_HOME
        // — the channel that actually reaches the XCUITest runner process).
        if let portString = env["KASSIOS_AGENT_PORT"], let port = Int(portString),
           let token = env["KASSIOS_AGENT_TOKEN"], !token.isEmpty {
            return KassAgentClient(port: port, token: token, udid: udid)
        }
        if let hostHome = env["SIMULATOR_HOST_HOME"],
           let discovery = readDiscovery(atPath: hostHome + "/.kassios-agent.json") {
            return KassAgentClient(port: discovery.port, token: discovery.token, udid: udid)
        }
        return nil
    }

    /// Reads the agent's `{port, token}` discovery file.
    static func readDiscovery(atPath path: String) -> (port: Int, token: String)? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let portString = json["port"], let port = Int(portString),
              let token = json["token"], !token.isEmpty else { return nil }
        return (port, token)
    }

    /// The client, or an `XCTSkip` naming the tier, the missing agent, and the
    /// one-line fix — so Tier C degrades in the open instead of hanging.
    static func require(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> KassAgentClient {
        guard let client = fromEnvironment(env) else {
            throw XCTSkip(
                "Tier C needs the host bridge. Start `kassios-agent` and pass "
                + "KASSIOS_AGENT_PORT + KASSIOS_AGENT_TOKEN to the UI-test target "
                + "(SIMULATOR_UDID is set automatically on the simulator; Tier C is "
                + "unavailable on real devices)."
            )
        }
        return client
    }

    @discardableResult
    func send(_ command: AgentCommand) throws -> AgentResponse {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/command")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AgentRequest(token: token, udid: udid, command: command))
        request.timeoutInterval = 15

        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            box.set(data: data, error: error)
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = box.error {
            throw XCTSkip("kassios-agent unreachable at 127.0.0.1:\(port): \(error.localizedDescription). Is it running?")
        }
        let response = try JSONDecoder().decode(AgentResponse.self, from: box.data ?? Data())
        guard response.ok else { throw KassError("kassios-agent: \(response.error ?? "command failed")") }
        return response
    }

    /// Carries the async result across the semaphore boundary.
    final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _data: Data?
        private var _error: Error?
        var data: Data? { lock.lock(); defer { lock.unlock() }; return _data }
        var error: Error? { lock.lock(); defer { lock.unlock() }; return _error }
        func set(data: Data?, error: Error?) { lock.lock(); _data = data; _error = error; lock.unlock() }
    }
}

/// An iOS privacy service, as `simctl privacy` names it.
public enum KassPermissionService: String, Sendable {
    case all
    case location
    case locationAlways = "location-always"
    case photos
    case photosAdd = "photos-add"
    case camera
    case microphone
    case contacts
    case calendar
    case reminders
    case siri
    case motion
    case mediaLibrary = "media-library"
}

/// Light/dark appearance override.
public enum KassAppearance: String, Sendable {
    case light, dark
}

// MARK: - Tier C device API (host bridge; simulator only)

public extension KassDevice {

    /// Permission control via the host agent — **Tier C** (simulator only).
    var permissions: KassPermissions { KassPermissions() }

    /// Status-bar override via the host agent — **Tier C** (simulator only).
    /// Freezing the clock/battery/signal is how you make screenshots deterministic.
    var statusBar: KassStatusBar { KassStatusBar() }

    /// Simulated location via the host agent — **Tier C** (simulator only).
    var location: KassLocation { KassLocation() }

    /// Delivers a push notification via the host agent — **Tier C** (simulator
    /// only). `payloadJSON` is a full APNs payload. Skips if no agent is running.
    func push(payloadJSON: String, to bundleID: String) throws {
        try KassAgentClient.require().send(.pushNotification(bundleID: bundleID, payloadJSON: payloadJSON))
    }

    /// Sets the simulator's light/dark appearance live via the host agent —
    /// **Tier C** (simulator only). Skips if no agent is running.
    func appearance(_ mode: KassAppearance) throws {
        try KassAgentClient.require().send(.appearance(mode.rawValue))
    }
}

/// Permission control — **Tier C** (host agent, simulator only). Every method
/// `XCTSkip`s when no agent is reachable.
public struct KassPermissions {
    public func grant(_ service: KassPermissionService, for bundleID: String) throws {
        try KassAgentClient.require().send(.permissionGrant(service: service.rawValue, bundleID: bundleID))
    }
    public func revoke(_ service: KassPermissionService, for bundleID: String) throws {
        try KassAgentClient.require().send(.permissionRevoke(service: service.rawValue, bundleID: bundleID))
    }
    public func reset(_ service: KassPermissionService, for bundleID: String) throws {
        try KassAgentClient.require().send(.permissionReset(service: service.rawValue, bundleID: bundleID))
    }
}

/// Status-bar override — **Tier C** (host agent, simulator only).
public struct KassStatusBar {
    /// Freezes the status bar to fixed values (default 9:41 / 100% / 4 bars) —
    /// the deterministic-screenshot trick.
    public func freeze(time: String = "9:41", battery: Int = 100, cellularBars: Int = 4) throws {
        try KassAgentClient.require().send(.statusBarOverride(time: time, batteryLevel: battery, cellularBars: cellularBars))
    }
    /// Clears any override, restoring the live status bar.
    public func clear() throws {
        try KassAgentClient.require().send(.statusBarClear)
    }
}

/// Simulated location — **Tier C** (host agent, simulator only).
public struct KassLocation {
    public func set(latitude: Double, longitude: Double) throws {
        try KassAgentClient.require().send(.location(latitude: latitude, longitude: longitude))
    }
}
