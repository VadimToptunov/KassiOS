import XCTest
@testable import KassiOS

final class KassIdentifierInventoryTests: XCTestCase {

    func test_identifierInfo_codableRoundTrip() throws {
        let info = KassIdentifierInfo(identifier: "signIn", type: "button", label: "Sign In", isHittable: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(info)

        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"identifier\""))
        XCTAssertTrue(json.contains("\"isHittable\""))

        let decoded = try JSONDecoder().decode(KassIdentifierInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }

    func test_identifierInfo_arrayCodableRoundTrip() throws {
        let inventory = [
            KassIdentifierInfo(identifier: "email", type: "textField", label: "Email", isHittable: true),
            KassIdentifierInfo(identifier: "", type: "staticText", label: "Decoration", isHittable: false)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(inventory)
        let decoded = try JSONDecoder().decode([KassIdentifierInfo].self, from: data)
        XCTAssertEqual(decoded, inventory)
    }
}
