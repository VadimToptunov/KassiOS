import XCTest
@testable import KassiOSMutants

final class ParallelTests: XCTestCase {

    private let manifest = MutantManifest(
        xcodebuild: ["-scheme", "S", "-destination", "platform=iOS Simulator,name=iPhone 17"],
        inject: "X",
        mutants: [
            "b": ["T/Transfer/test_a"],
            "a": ["T/Transfer/test_b", "T/Card/test_c"],
            "c": ["T/Card/test_d", "T/Home/test_e"],
        ],
        action: "test-without-building"
    )

    func testTheCleanRunComesFirstSplitPerWorkerThenDefectsInIdOrder() {
        let jobs = MutantPlan.jobs(manifest, clean: true, only: nil, workers: 2)
        XCTAssertEqual(jobs.map(\.name), ["clean-1", "clean-2", "a", "b", "c"])
        XCTAssertNil(jobs[0].defect)
        XCTAssertEqual(jobs[2], MutantJob(name: "a", tests: ["T/Transfer/test_b", "T/Card/test_c"], defect: "a"))
        XCTAssertEqual(Set(jobs[0].tests + jobs[1].tests), Set(manifest.allTests), "every test runs clean once")
        XCTAssertEqual(jobs[0].tests.count + jobs[1].tests.count, manifest.allTests.count)
    }

    func testOneWorkerKeepsASingleCleanRunAndOnlyFilters() {
        let jobs = MutantPlan.jobs(manifest, clean: true, only: ["c"], workers: 1)
        XCTAssertEqual(jobs.map(\.name), ["clean", "c"])
        XCTAssertEqual(MutantPlan.jobs(manifest, clean: false, only: nil, workers: 4).map(\.name), ["a", "b", "c"])
    }

    func testCleanPartsKeepAClassTogetherAndBalanceBySize() {
        let tests = ["T/A/1", "T/A/2", "T/A/3", "T/B/1", "T/B/2", "T/C/1"]
        let parts = MutantPlan.cleanParts(tests, workers: 2)
        XCTAssertEqual(parts, [["T/A/1", "T/A/2", "T/A/3"], ["T/B/1", "T/B/2", "T/C/1"]])
        XCTAssertEqual(MutantPlan.cleanParts(["T/A/1"], workers: 3), [["T/A/1"]], "no empty parts")
    }

    func testTheDestinationIsRepointedAtAClone() throws {
        XCTAssertEqual(try SimulatorDestination.value(in: manifest.xcodebuild), "platform=iOS Simulator,name=iPhone 17")
        XCTAssertEqual(
            SimulatorDestination.pointing(manifest.xcodebuild, at: "U-1"),
            ["-scheme", "S", "-destination", "platform=iOS Simulator,id=U-1"]
        )
        XCTAssertThrowsError(try SimulatorDestination.value(in: ["-scheme", "S"]))
        XCTAssertThrowsError(try SimulatorDestination.value(in: ["-destination", "a", "-destination", "b"]))
    }

    func testANamedDestinationResolvesToTheNewestRuntimeUnlessOSIsGiven() throws {
        let json = Data("""
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [{"udid": "OLD", "name": "iPhone 17", "state": "Shutdown"}],
          "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"udid": "NEW", "name": "iPhone 17", "state": "Booted"},
                                                         {"udid": "PRO", "name": "iPhone 17 Pro", "state": "Shutdown"}],
          "com.apple.CoreSimulator.SimRuntime.watchOS-12-0": [{"udid": "WATCH", "name": "iPhone 17", "state": "Shutdown"}]
        }}
        """.utf8)
        XCTAssertEqual(try SimulatorDestination.udid(for: "platform=iOS Simulator,name=iPhone 17", simctlJSON: json), "NEW")
        XCTAssertEqual(try SimulatorDestination.udid(for: "platform=iOS Simulator,name=iPhone 17,OS=latest", simctlJSON: json), "NEW")
        XCTAssertEqual(try SimulatorDestination.udid(for: "platform=iOS Simulator,name=iPhone 17,OS=26.2", simctlJSON: json), "OLD")
        XCTAssertEqual(try SimulatorDestination.udid(for: "platform=iOS Simulator,OS=27,name=iPhone 17 Pro", simctlJSON: json), "PRO")
        XCTAssertEqual(try SimulatorDestination.udid(for: "id=ABC", simctlJSON: json), "ABC", "an id needs no lookup")
        XCTAssertThrowsError(try SimulatorDestination.udid(for: "platform=iOS Simulator,name=iPad", simctlJSON: json))
        XCTAssertThrowsError(try SimulatorDestination.udid(for: "platform=iOS Simulator", simctlJSON: json))
    }

    func testEachJobGetsItsOwnResultBundleAndNoDiagnostics() {
        let job = MutantJob(name: "a", tests: ["T/Card/test_c"], defect: "a")
        XCTAssertEqual(
            MutantCommand.arguments(manifest, job: job, udid: "U-2", resultBundle: "/logs/a.xcresult"),
            ["xcodebuild", "test-without-building", "-scheme", "S", "-destination", "platform=iOS Simulator,id=U-2",
             "-resultBundlePath", "/logs/a.xcresult", "-collect-test-diagnostics", "never", "-only-testing:T/Card/test_c"]
        )
        let own = MutantManifest(xcodebuild: ["-resultBundlePath", "/mine", "-collect-test-diagnostics", "on-failure"],
                                 inject: "X", mutants: ["a": ["T/C/m"]])
        XCTAssertEqual(
            MutantCommand.arguments(own, job: job, udid: nil, resultBundle: "/logs/a.xcresult"),
            ["xcodebuild", "test", "-resultBundlePath", "/mine", "-collect-test-diagnostics", "on-failure", "-only-testing:T/Card/test_c"],
            "the manifest's own choices win"
        )
    }

    func testOnlyARunWhereNoTestReportedIsRetried() {
        let job = MutantJob(name: "a", tests: ["T/Card/test_c", "T/Card/test_d"], defect: "a")
        XCTAssertTrue(MutantPlan.ranNothing(job, outcomes: []))
        XCTAssertTrue(MutantPlan.ranNothing(job, outcomes: [TestOutcome(testClass: "Other", method: "test_c", passed: false)]))
        XCTAssertFalse(MutantPlan.ranNothing(job, outcomes: [TestOutcome(testClass: "Card", method: "test_d", passed: true)]),
                       "a partial result is a verdict, not a launch failure")
    }
}
