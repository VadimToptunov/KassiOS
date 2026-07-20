import Foundation

// The agent's copy of the wire protocol. The client's copy lives in
// `Sources/KassiOS/KassAgentProtocol.swift`; the two are separate modules (the
// XCTest-based library can't be imported by this CLI, and this CLI can't be
// compiled into an iOS UI-test target), so they share the contract by matching
// Codable shapes. Keep the two AgentCommand cases identical.

struct AgentRequest: Codable {
    let token: String
    let udid: String
    let command: AgentCommand
}

struct AgentResponse: Codable {
    let ok: Bool
    let output: String
    let error: String?

    init(ok: Bool, output: String = "", error: String? = nil) {
        self.ok = ok
        self.output = output
        self.error = error
    }
}

/// The allowlisted command set. The agent maps each to a fixed `simctl`
/// invocation and refuses anything else — it never forwards arbitrary argv.
enum AgentCommand: Codable, Equatable {
    case permissionGrant(service: String, bundleID: String)
    case permissionRevoke(service: String, bundleID: String)
    case permissionReset(service: String, bundleID: String)
    case statusBarOverride(time: String?, batteryLevel: Int?, cellularBars: Int?)
    case statusBarClear
    case appearance(String)
    case location(latitude: Double, longitude: Double)
    case pushNotification(bundleID: String, payloadJSON: String)
    case openURL(String)

    /// The `simctl` argv for this command (everything after `xcrun simctl`).
    /// For `pushNotification` the final element is a placeholder the runner
    /// replaces with a real payload-file path.
    func simctlArguments(udid: String) -> [String] {
        switch self {
        case let .permissionGrant(service, bundleID):
            return ["privacy", udid, "grant", service, bundleID]
        case let .permissionRevoke(service, bundleID):
            return ["privacy", udid, "revoke", service, bundleID]
        case let .permissionReset(service, bundleID):
            return ["privacy", udid, "reset", service, bundleID]
        case let .statusBarOverride(time, battery, bars):
            var args = ["status_bar", udid, "override"]
            if let time = time { args += ["--time", time] }
            if let battery = battery { args += ["--batteryLevel", String(battery)] }
            if let bars = bars { args += ["--cellularBars", String(bars)] }
            return args
        case .statusBarClear:
            return ["status_bar", udid, "clear"]
        case let .appearance(mode):
            return ["ui", udid, "appearance", mode]
        case let .location(lat, lon):
            return ["location", udid, "set", "\(lat),\(lon)"]
        case let .pushNotification(bundleID, _):
            return ["push", udid, bundleID, "<payload-file>"]
        case let .openURL(url):
            return ["openurl", udid, url]
        }
    }
}
