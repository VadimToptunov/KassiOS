import XCTest
@testable import KassiOS

/// The client's copy of the wire protocol (`KassAgentProtocol.swift`). See
/// `AgentCommandTests` in `KassiOSAgentCLITests` for the agent's matching copy.
final class KassAgentProtocolTests: XCTestCase {

    func test_startStopRecording_roundTripCodable() throws {
        for command in [AgentCommand.startRecording, .stopRecording] {
            let data = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(AgentCommand.self, from: data)
            XCTAssertEqual(decoded, command)
        }
    }

    func test_agentResponse_decodesDataField() throws {
        let json = Data("""
        {"ok":true,"output":"","error":null,"data":"aGVsbG8="}
        """.utf8)
        let response = try JSONDecoder().decode(AgentResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.data, "aGVsbG8=")
    }

    /// Backward compatibility: a response with no `data` key at all (as every
    /// non-recording command still produces) still decodes, with `data == nil`.
    func test_agentResponse_decodesWithoutDataField() throws {
        let json = Data("""
        {"ok":true,"output":"done","error":null}
        """.utf8)
        let response = try JSONDecoder().decode(AgentResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertNil(response.data)
    }
}
