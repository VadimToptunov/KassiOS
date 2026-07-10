import XCTest
@testable import KassiOS

final class KassScaffoldTests: XCTestCase {

    func test_camelCase_separators() {
        XCTAssertEqual(KassScaffold.camelCase("login_email"), "loginEmail")
        XCTAssertEqual(KassScaffold.camelCase("sign-in"), "signIn")
        XCTAssertEqual(KassScaffold.camelCase("item-0"), "item0")
        XCTAssertEqual(KassScaffold.camelCase("nav.back.button"), "navBackButton")
    }

    func test_camelCase_preservesExistingHumps() {
        XCTAssertEqual(KassScaffold.camelCase("signIn"), "signIn")
        XCTAssertEqual(KassScaffold.camelCase("welcome"), "welcome")
    }

    func test_camelCase_lowercasesLeadingWord() {
        XCTAssertEqual(KassScaffold.camelCase("Notifications"), "notifications")
    }

    func test_camelCase_guardsLeadingDigitAndEmpty() {
        XCTAssertEqual(KassScaffold.camelCase("2fa_code"), "e2faCode")
        XCTAssertEqual(KassScaffold.camelCase(""), "element")
        XCTAssertEqual(KassScaffold.camelCase("!!!"), "element")
    }
}
