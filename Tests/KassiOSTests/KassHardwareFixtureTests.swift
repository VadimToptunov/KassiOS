import XCTest
@testable import KassiOS

final class KassHardwareFixtureTests: XCTestCase {

    func test_encodesToExpectedKeys() throws {
        let fixture = KassHardwareFixture(scanner: [.code("ABC", symbology: "qr")])
        let data = try JSONEncoder().encode(fixture)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let scanner = object?["scanner"] as? [[String: Any]]
        XCTAssertEqual(scanner?.first?["payload"] as? String, "ABC")
        XCTAssertEqual(scanner?.first?["symbology"] as? String, "qr")
    }

    func test_roundTripsThroughJSON() throws {
        let fixture = KassHardwareFixture(
            scanner: [.code("X"), .failure("nope")],
            bluetooth: .init(peripherals: [
                .init(id: "p1", name: "Sensor",
                      notifications: [.init(characteristic: "2a37", valueHex: "0a1b", afterMs: 50)])
            ]),
            nfc: [.init(ndefText: "tag")]
        )
        let data = try JSONEncoder().encode(fixture)
        let restored = try JSONDecoder().decode(KassHardwareFixture.self, from: data)
        XCTAssertEqual(fixture, restored)
    }

    func test_scanResultFactories() {
        XCTAssertEqual(KassHardwareFixture.ScanResult.code("Q", symbology: "qr").payload, "Q")
        XCTAssertEqual(KassHardwareFixture.ScanResult.failure("boom").failWith, "boom")
    }
}
