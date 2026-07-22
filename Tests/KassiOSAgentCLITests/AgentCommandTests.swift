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
        let data = Agent.handle(body: body, token: "right", runner: SimctlRunner(), recordingManager: RecordingManager())
        let response = try JSONDecoder().decode(AgentResponse.self, from: data)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "unauthorized")
    }

    func test_handle_rejectsMalformedBody() throws {
        let data = Agent.handle(body: Data("not json".utf8), token: "t", runner: SimctlRunner(), recordingManager: RecordingManager())
        let response = try JSONDecoder().decode(AgentResponse.self, from: data)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "malformed request")
    }

    func test_constantTimeEquals() {
        XCTAssertTrue(Agent.constantTimeEquals("secret", "secret"))
        XCTAssertFalse(Agent.constantTimeEquals("secret", "secreT"))
        XCTAssertFalse(Agent.constantTimeEquals("secret", "secre"))
    }

    /// `startRecording`/`stopRecording` are handled by `RecordingManager`, not
    /// the generic `simctl` runner — they must never get an argv of their own.
    func test_recordingCommands_haveNoSimctlArguments() {
        XCTAssertEqual(AgentCommand.startRecording.simctlArguments(udid: udid), [])
        XCTAssertEqual(AgentCommand.stopRecording.simctlArguments(udid: udid), [])
    }

    func test_startStopRecording_roundTripCodable() throws {
        for command in [AgentCommand.startRecording, .stopRecording] {
            let data = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(AgentCommand.self, from: data)
            XCTAssertEqual(decoded, command)
        }
    }

    func test_agentResponse_encodesAndDecodesDataField() throws {
        let response = AgentResponse(ok: true, data: "aGVsbG8=")
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AgentResponse.self, from: encoded)
        XCTAssertEqual(decoded.data, "aGVsbG8=")
    }

    /// Existing call sites like `AgentResponse(ok:output:error:)` must still
    /// compile now that `data` is a member — it defaults to `nil`.
    func test_agentResponse_dataDefaultsToNil() {
        XCTAssertNil(AgentResponse(ok: true).data)
    }

    /// `startRecording`/`stopRecording` are routed to `RecordingManager`
    /// before the generic runner ever sees them.
    func test_handle_routesRecordingCommandsToRecordingManager() throws {
        let manager = RecordingManager()
        let body = try JSONEncoder().encode(AgentRequest(token: "t", udid: udid, command: .stopRecording))
        let data = Agent.handle(body: body, token: "t", runner: SimctlRunner(), recordingManager: manager)
        let response = try JSONDecoder().decode(AgentResponse.self, from: data)
        // No recording was ever started for this udid, so stopping is a no-op.
        XCTAssertTrue(response.ok)
        XCTAssertNil(response.data)
    }
}
