import XCTest
@testable import KassiOSMutants

final class MutantsTests: XCTestCase {

    private let log = """
    Test Suite 'TransferTests' started at 2026-10-26 12:00:00.000.
    Test Case '-[AppUITests.TransferTests test_happy]' started.
    Test Case '-[AppUITests.TransferTests test_happy]' failed (12.345 seconds).
    Test Case '-[AppUITests.TransferTests test_zero]' started.
    Test Case '-[AppUITests.TransferTests test_zero]' passed (3.210 seconds).
    Test Case '-[AppUITests.CardTests test_cvv]' failed (2.000 seconds).
    Test Case '-[AppUITests.CardTests test_cvv]' passed (2.100 seconds).
    """

    func testReadsVerdictsAndTheLastRetryWins() {
        let outcomes = XcodebuildLog.outcomes(log)
        XCTAssertEqual(outcomes, [
            TestOutcome(testClass: "TransferTests", method: "test_happy", passed: false),
            TestOutcome(testClass: "TransferTests", method: "test_zero", passed: true),
            TestOutcome(testClass: "CardTests", method: "test_cvv", passed: true),
        ])
    }

    func testAMutantIsKilledOnlyWhenEveryNamedTestFails() {
        let outcomes = XcodebuildLog.outcomes(log)
        let happy = "AppUITests/TransferTests/test_happy", zero = "AppUITests/TransferTests/test_zero"
        XCTAssertEqual(MutantVerdict.evaluate(expected: [happy], outcomes: outcomes), .killed)
        XCTAssertEqual(MutantVerdict.evaluate(expected: [happy, zero], outcomes: outcomes), .survived([zero]))
    }

    func testATestThatNeverRanIsNoResultNotAKill() {
        XCTAssertEqual(
            MutantVerdict.evaluate(expected: ["AppUITests/TransferTests/test_typo"], outcomes: XcodebuildLog.outcomes(log)),
            .noResult(["AppUITests/TransferTests/test_typo"])
        )
        XCTAssertEqual(MutantVerdict.evaluate(expected: ["AppUITests/x"], outcomes: []), .noResult(["AppUITests/x"]))
    }

    func testTheCleanRunNeedsEveryTestGreen() {
        let outcomes = XcodebuildLog.outcomes(log)
        let expected = ["AppUITests/TransferTests/test_happy", "AppUITests/CardTests/test_cvv", "AppUITests/CardTests/test_gone"]
        XCTAssertEqual(
            CleanCheck.failures(expected: expected, outcomes: outcomes),
            ["AppUITests/TransferTests/test_happy", "AppUITests/CardTests/test_gone"]
        )
    }

    func testTheManifestRejectsEmptyAndMalformedEntries() throws {
        let good = #"{"xcodebuild":["-scheme","S"],"inject":"TEST_RUNNER_X","mutants":{"a":["T/C/m"],"b":["T/C/n","T/D/m"]}}"#
        let manifest = try MutantManifest.load(Data(good.utf8))
        XCTAssertEqual(manifest.allTests, ["T/C/m", "T/C/n", "T/D/m"])
        XCTAssertEqual(manifest.action, "test", "the default action")
        let prebuilt = #"{"action":"test-without-building","xcodebuild":[],"inject":"X","mutants":{"a":["T/C/m"]}}"#
        XCTAssertEqual(try MutantManifest.load(Data(prebuilt.utf8)).action, "test-without-building")
        XCTAssertThrowsError(try MutantManifest.load(Data(#"{"xcodebuild":[],"inject":"X","mutants":{"a":[]}}"#.utf8)))
        XCTAssertThrowsError(try MutantManifest.load(Data(#"{"xcodebuild":[],"inject":"X","mutants":{"a":["C/m"]}}"#.utf8)))
    }

    func testTheReportPutsSurvivorsFirstAndCounts() {
        let table = MutantReport.table([
            (id: "b", verdict: .killed),
            (id: "a", verdict: .survived(["T/C/m"])),
            (id: "c", verdict: .noResult(["T/C/x"])),
        ])
        let lines = table.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[1].hasPrefix("a") && lines[1].contains("SURVIVED") && lines[1].contains("still green: T/C/m"))
        XCTAssertTrue(lines[2].hasPrefix("c") && lines[2].contains("NO RESULT"))
        XCTAssertTrue(lines[3].hasPrefix("b") && lines[3].contains("killed"))
        XCTAssertTrue(table.contains("1 of 3 killed"))
    }
}
