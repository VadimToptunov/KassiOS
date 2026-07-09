import XCTest
@testable import KassiOS

final class AllureReporterTests: XCTestCase {

    private func makeTempDir() -> String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("kassios-allure-\(UUID().uuidString)")
    }

    private func readResult(in dir: String) throws -> [String: Any] {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        let resultFile = try XCTUnwrap(files.first { $0.hasSuffix("-result.json") })
        let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(resultFile))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_writesNestedResultAndClosesOpenSteps() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let reporter = AllureReporter(resultsPath: dir)
        reporter.testStarted(name: "test_login", fullName: "KassiOSTests.LoginFlowUITests.test_login")
        reporter.stepStarted("parent")
        reporter.stepStarted("child")
        reporter.stepFinished(status: .passed, message: nil)
        reporter.attach(name: "shot", type: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        reporter.stepFinished(status: .passed, message: nil)      // close parent
        reporter.stepStarted("orphan")                            // deliberately left open
        reporter.testFinished(status: .failed, message: "boom")

        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        XCTAssertTrue(files.contains { $0.hasSuffix("-attachment.png") }, "attachment file written")

        let json = try readResult(in: dir)
        XCTAssertEqual(json["status"] as? String, "failed")
        XCTAssertEqual(json["fullName"] as? String, "KassiOSTests.LoginFlowUITests.test_login")
        XCTAssertEqual(json["stage"] as? String, "finished")

        let steps = try XCTUnwrap(json["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 2)                            // parent + orphan

        let parent = steps[0]
        XCTAssertEqual(parent["name"] as? String, "parent")
        XCTAssertEqual(parent["status"] as? String, "passed")
        let children = try XCTUnwrap(parent["steps"] as? [[String: Any]])
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0]["name"] as? String, "child")
        let parentAttachments = try XCTUnwrap(parent["attachments"] as? [[String: Any]])
        XCTAssertEqual(parentAttachments.count, 1)
        XCTAssertEqual(parentAttachments[0]["name"] as? String, "shot")

        let orphan = steps[1]
        XCTAssertEqual(orphan["name"] as? String, "orphan")
        XCTAssertEqual(orphan["status"] as? String, "failed", "open step gets the test's terminal status")

        let labels = try XCTUnwrap(json["labels"] as? [[String: Any]])
        XCTAssertTrue(labels.contains {
            ($0["name"] as? String) == "framework" && ($0["value"] as? String) == "KassiOS"
        })
        XCTAssertTrue(labels.contains {
            ($0["name"] as? String) == "suite" && ($0["value"] as? String) == "KassiOSTests"
        })
    }

    func test_attachmentAtRootWhenNoStepOpen() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let reporter = AllureReporter(resultsPath: dir)
        reporter.testStarted(name: "t", fullName: "S.t")
        reporter.attach(name: "root-shot", type: "image/png", data: Data([0x01]))
        reporter.testFinished(status: .passed, message: nil)

        let json = try readResult(in: dir)
        XCTAssertEqual(json["status"] as? String, "passed")
        let attachments = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0]["name"] as? String, "root-shot")
        XCTAssertEqual(attachments[0]["type"] as? String, "image/png")
    }
}
