import XCTest
@testable import KassiOSStubs

final class KassHardwareStubsTests: XCTestCase {

    func test_hardwareFixture_decodesFromEnvironment() {
        let json = #"{"scanner":[{"payload":"ABC123","symbology":"qr","failWith":null}],"bluetooth":null,"nfc":[]}"#
        let fixture = KassiOSStubs.hardwareFixture(["KASS_HARDWARE_JSON": json])
        XCTAssertEqual(fixture?.scanner.first?.payload, "ABC123")
        XCTAssertEqual(fixture?.scanner.first?.symbology, "qr")
    }

    func test_hardwareFixture_nilWithoutEnvironment() {
        XCTAssertNil(KassiOSStubs.hardwareFixture([:]))
    }

    func test_hardwareFixture_nilOnMalformedJSON() {
        XCTAssertNil(KassiOSStubs.hardwareFixture(["KASS_HARDWARE_JSON": "{not json"]))
    }

    func test_scannerStub_popsInOrderThenThrows() throws {
        let stub = KassScannerStub([
            .init(payload: "A", symbology: nil, failWith: nil),
            .init(payload: "", symbology: nil, failWith: "boom")
        ])
        XCTAssertEqual(try stub.next(), "A")
        XCTAssertThrowsError(try stub.next())   // scripted failure
        XCTAssertThrowsError(try stub.next())   // drained
    }

    func test_nfcStub_popsInOrderThenThrows() throws {
        let stub = KassNFCStub([.init(ndefText: "hello", ndefURL: nil, failWith: nil)])
        XCTAssertEqual(try stub.next().ndefText, "hello")
        XCTAssertThrowsError(try stub.next())
    }

    func test_bleStub_discoversAndMapsNotifications() {
        let json = #"""
        {"scanner":[],"bluetooth":{"peripherals":[{"id":"p1","name":"Sensor","services":["180d"],"autoConnect":true,"notifications":[{"characteristic":"2a37","valueHex":"0a1b","afterMs":100}]}]},"nfc":[]}
        """#
        let fixture = KassiOSStubs.hardwareFixture(["KASS_HARDWARE_JSON": json])
        let ble = KassBLEStub(fixture?.bluetooth)
        XCTAssertEqual(ble.discovered().first?.name, "Sensor")
        let notes = ble.notifications(for: "p1")
        XCTAssertEqual(notes.first?.value, Data([0x0a, 0x1b]))
        XCTAssertEqual(notes.first?.afterMs, 100)
    }

    func test_dataHex_parsesAndRejects() {
        XCTAssertEqual(Data(hex: "0a1b"), Data([0x0a, 0x1b]))
        XCTAssertNil(Data(hex: "abc"))   // odd length
        XCTAssertNil(Data(hex: "zz"))    // non-hex characters
    }
}
