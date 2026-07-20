import XCTest
@testable import KassiOSAgentCLI

final class AgentCommandTests: XCTestCase {

    private let udid = "ABC-123"

    func test_permissions_mapToPrivacyArgs() {
        XCTAssertEqual(
            AgentCommand.permissionGrant(service: "location", bundleID: "com.x.App").simctlArguments(udid: udid),
            ["privacy", udid, "grant", "location", "com.x.App"]
        )
        XCTAssertEqual(
            AgentCommand.permissionReset(service: "all", bundleID: "com.x.App").simctlArguments(udid: udid),
            ["privacy", udid, "reset", "all", "com.x.App"]
        )
    }

    func test_statusBarOverride_includesOnlyProvidedFlags() {
        XCTAssertEqual(
            AgentCommand.statusBarOverride(time: "9:41", batteryLevel: 100, cellularBars: 4).simctlArguments(udid: udid),
            ["status_bar", udid, "override", "--time", "9:41", "--batteryLevel", "100", "--cellularBars", "4"]
        )
        XCTAssertEqual(
            AgentCommand.statusBarOverride(time: "9:41", batteryLevel: nil, cellularBars: nil).simctlArguments(udid: udid),
            ["status_bar", udid, "override", "--time", "9:41"]
        )
    }

    func test_location_appearance_openURL() {
        XCTAssertEqual(
            AgentCommand.location(latitude: 34.7071, longitude: 33.0226).simctlArguments(udid: udid),
            ["location", udid, "set", "34.7071,33.0226"]
        )
        XCTAssertEqual(AgentCommand.appearance("dark").simctlArguments(udid: udid), ["ui", udid, "appearance", "dark"])
        XCTAssertEqual(AgentCommand.openURL("myapp://x").simctlArguments(udid: udid), ["openurl", udid, "myapp://x"])
    }

    func test_push_leavesPayloadFilePlaceholder() {
        XCTAssertEqual(
            AgentCommand.pushNotification(bundleID: "com.x.App", payloadJSON: "{}").simctlArguments(udid: udid),
            ["push", udid, "com.x.App", "<payload-file>"]
        )
    }

    /// Auth is enforced: a mismatched token yields an unauthorized response.
    func test_handle_rejectsBadToken() throws {
        let body = try JSONEncoder().encode(AgentRequest(token: "wrong", udid: udid, command: .statusBarClear))
        let response = try JSONDecoder().decode(AgentResponse.self, from: Agent.handle(body: body, token: "right", runner: SimctlRunner()))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "unauthorized")
    }

    func test_handle_rejectsMalformedBody() throws {
        let response = try JSONDecoder().decode(AgentResponse.self, from: Agent.handle(body: Data("not json".utf8), token: "t", runner: SimctlRunner()))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "malformed request")
    }
}
