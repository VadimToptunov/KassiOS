import XCTest
@testable import KassiOSTool

final class ToolCommandTests: XCTestCase {

    func testNoArgumentsShowsHelp() throws {
        XCTAssertEqual(try ToolCommand.parse([]), .help)
    }

    func testAgentStartDefaultsToThePort8437() throws {
        XCTAssertEqual(try ToolCommand.parse(["agent", "start"]), .agentStart(port: 8437, log: nil))
    }

    func testAgentStartTakesPortAndLog() throws {
        XCTAssertEqual(try ToolCommand.parse(["agent", "start", "--port", "9000", "--log", "agent.log"]),
                       .agentStart(port: 9000, log: "agent.log"))
    }

    func testBareAgentRunsInTheForeground() throws {
        XCTAssertEqual(try ToolCommand.parse(["agent"]), .agentRun(port: 8437))
    }

    func testBadPortIsRejected() {
        XCTAssertThrowsError(try ToolCommand.parse(["agent", "start", "--port", "0"])) {
            XCTAssertEqual($0 as? ToolCommand.ParseError, .badPort("0"))
        }
        XCTAssertThrowsError(try ToolCommand.parse(["agent", "start", "--port"])) {
            XCTAssertEqual($0 as? ToolCommand.ParseError, .missingValue("--port"))
        }
    }

    func testMutantsAndLintForwardEveryArgument() throws {
        XCTAssertEqual(try ToolCommand.parse(["mutants", "m.json", "--clean", "--parallel", "3"]),
                       .forward(tool: "kassios-mutants", arguments: ["m.json", "--clean", "--parallel", "3"]))
        XCTAssertEqual(try ToolCommand.parse(["lint", "UITests", "--strict"]),
                       .forward(tool: "kassios-lint", arguments: ["UITests", "--strict"]))
    }

    func testUnknownCommandsAreRejected() {
        XCTAssertThrowsError(try ToolCommand.parse(["mutant"])) {
            XCTAssertEqual($0 as? ToolCommand.ParseError, .unknown("mutant"))
        }
        XCTAssertThrowsError(try ToolCommand.parse(["agent", "restart"])) {
            XCTAssertEqual($0 as? ToolCommand.ParseError, .unknown("agent restart"))
        }
    }

    func testLocatorPrefersTheToolNextToTheFrontEnd() {
        let found = ToolLocator.find("kassios-lint", besides: "/opt/kassios/bin/kassios", path: "/usr/bin:/opt/other") {
            ["/opt/kassios/bin/kassios-lint", "/opt/other/kassios-lint"].contains($0)
        }
        XCTAssertEqual(found, "/opt/kassios/bin/kassios-lint")
    }

    func testLocatorFallsBackToPath() {
        let found = ToolLocator.find("kassios-lint", besides: "/opt/kassios/bin/kassios", path: "/usr/bin:/opt/other") {
            $0 == "/opt/other/kassios-lint"
        }
        XCTAssertEqual(found, "/opt/other/kassios-lint")
        XCTAssertNil(ToolLocator.find("kassios-lint", besides: "/a/kassios", path: nil) { _ in false })
    }

    func testPidFileParsing() {
        XCTAssertEqual(AgentFiles.readPid("4242\n"), 4242)
        XCTAssertNil(AgentFiles.readPid("nope"))
        XCTAssertNil(AgentFiles.readPid("0"))
        XCTAssertNil(AgentFiles.readPid(nil))
    }
}
