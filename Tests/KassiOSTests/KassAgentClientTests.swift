import XCTest
@testable import KassiOS

final class KassAgentClientTests: XCTestCase {

    func test_fromEnvironment_nilWhenUnconfigured() {
        XCTAssertNil(KassAgentClient.fromEnvironment([:]))
        // Missing token / udid → still nil.
        XCTAssertNil(KassAgentClient.fromEnvironment(["KASSIOS_AGENT_PORT": "8437"]))
        XCTAssertNil(KassAgentClient.fromEnvironment([
            "KASSIOS_AGENT_PORT": "8437", "KASSIOS_AGENT_TOKEN": "t"
        ]))
    }

    func test_fromEnvironment_populatedWhenConfigured() {
        let client = KassAgentClient.fromEnvironment([
            "KASSIOS_AGENT_PORT": "8437",
            "KASSIOS_AGENT_TOKEN": "secret",
            "SIMULATOR_UDID": "UDID-1"
        ])
        XCTAssertEqual(client?.port, 8437)
        XCTAssertEqual(client?.token, "secret")
        XCTAssertEqual(client?.udid, "UDID-1")
    }

    func test_require_skipsWhenUnconfigured() {
        XCTAssertThrowsError(try KassAgentClient.require([:])) { error in
            XCTAssertTrue(error is XCTSkip)
        }
    }
}
