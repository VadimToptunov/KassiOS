import XCTest
@testable import KassiOS

final class KassTestCaseNameParsingTests: XCTestCase {

    func test_parsesModuleQualifiedObjCName() {
        let parsed = KassTestCase.parseTestName("-[KassiOSTests.LoginFlowUITests test_login]")
        XCTAssertEqual(parsed.name, "test_login")
        XCTAssertEqual(parsed.fullName, "LoginFlowUITests.test_login")
    }

    func test_parsesBareObjCName() {
        let parsed = KassTestCase.parseTestName("-[LoginFlowUITests test_login]")
        XCTAssertEqual(parsed.name, "test_login")
        XCTAssertEqual(parsed.fullName, "LoginFlowUITests.test_login")
    }

    func test_fallsBackWhenUnparseable() {
        let parsed = KassTestCase.parseTestName("not a test name")
        XCTAssertEqual(parsed.name, "not a test name")
        XCTAssertEqual(parsed.fullName, "not a test name")
    }
}
