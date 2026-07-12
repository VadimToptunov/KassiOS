import XCTest
@testable import KassiOS

final class JUnitReporterTests: XCTestCase {

    private func makeTempDir() -> String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("kassios-junit-\(UUID().uuidString)")
    }

    private func readXML(in dir: String) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        let file = try XCTUnwrap(files.first { $0.hasSuffix(".xml") })
        return try String(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(file), encoding: .utf8)
    }

    func test_writesPassingTestcase() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let reporter = JUnitReporter(resultsPath: dir)
        reporter.testStarted(name: "test_login", fullName: "LoginTests.test_login")
        reporter.testFinished(status: .passed, message: nil)

        let xml = try readXML(in: dir)
        XCTAssertTrue(xml.contains("<testsuite name=\"LoginTests\" tests=\"1\" failures=\"0\""))
        XCTAssertTrue(xml.contains("<testcase classname=\"LoginTests\" name=\"test_login\""))
        XCTAssertFalse(xml.contains("<failure"))
    }

    func test_writesFailureWithEscapedMessage() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let reporter = JUnitReporter(resultsPath: dir)
        reporter.testStarted(name: "test_x", fullName: "S.test_x")
        reporter.testFinished(status: .failed, message: "expected <A> & \"B\"")

        let xml = try readXML(in: dir)
        XCTAssertTrue(xml.contains("failures=\"1\""))
        XCTAssertTrue(xml.contains("<failure message=\"expected &lt;A&gt; &amp; &quot;B&quot;\""))
    }

    func test_escape() {
        XCTAssertEqual(JUnitReporter.escape("a & b < c > d \"e\""), "a &amp; b &lt; c &gt; d &quot;e&quot;")
    }
}
