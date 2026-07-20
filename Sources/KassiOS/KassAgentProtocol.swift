import Foundation

// The client's copy of the wire protocol shared with `kassios-agent`. Its copy
// lives in `Sources/KassiOSAgentCLI/AgentProtocol.swift`; they're separate
// modules that share the contract by matching Codable shapes. Keep the
// AgentCommand cases identical to the agent's. The client only encodes requests
// and decodes responses — the `simctl` mapping lives on the agent side.

struct AgentRequest: Codable {
    let token: String
    let udid: String
    let command: AgentCommand
}

struct AgentResponse: Codable {
    let ok: Bool
    let output: String
    let error: String?
}

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
}
