import XCTest

/// A hardware fixture: canned results for device hardware the simulator cannot
/// provide — a barcode/QR scanner, Bluetooth peripherals, NFC tags. Passed to the
/// app with ``KassTestCase/launch(hardware:arguments:environment:)`` and replayed
/// by the app's debug-only `KassiOSStubs` bridge against the seams the app injects
/// them into.
///
/// Unlike network stubbing, hardware cannot be intercepted transparently: there is
/// no `URLProtocol`-style hook. The app must abstract each device behind its own
/// protocol and, in debug, feed that protocol from these fixtures (see
/// `Documentation/HardwareStubbing.md`). Location and push are deliberately absent
/// here — those go through the simctl device API, not this fixture.
///
/// This is the test-side copy of the wire contract shared with `KassiOSStubs`; keep
/// its `Codable` shape identical to the app-side `KassHardwareFixtureDefinition`.
public struct KassHardwareFixture: Codable, Sendable, Equatable {
    public var scanner: [ScanResult]
    public var bluetooth: BluetoothScript?
    public var nfc: [NFCTag]

    public init(
        scanner: [ScanResult] = [],
        bluetooth: BluetoothScript? = nil,
        nfc: [NFCTag] = []
    ) {
        self.scanner = scanner
        self.bluetooth = bluetooth
        self.nfc = nfc
    }

    /// One result the app's scanner seam returns, consumed in order. A non-nil
    /// `failWith` makes that invocation throw instead, to exercise the error path.
    public struct ScanResult: Codable, Sendable, Equatable {
        public var payload: String
        public var symbology: String?
        public var failWith: String?

        public init(payload: String = "", symbology: String? = nil, failWith: String? = nil) {
            self.payload = payload
            self.symbology = symbology
            self.failWith = failWith
        }

        /// A successful scan returning `payload` (optionally tagged with a symbology).
        public static func code(_ payload: String, symbology: String? = nil) -> ScanResult {
            ScanResult(payload: payload, symbology: symbology)
        }

        /// A scan that throws, to drive the scan-failure branch.
        public static func failure(_ message: String) -> ScanResult {
            ScanResult(failWith: message)
        }
    }

    public struct BluetoothScript: Codable, Sendable, Equatable {
        public var peripherals: [Peripheral]

        public init(peripherals: [Peripheral] = []) {
            self.peripherals = peripherals
        }

        public struct Peripheral: Codable, Sendable, Equatable {
            public var id: String
            public var name: String
            public var services: [String]
            public var autoConnect: Bool
            public var notifications: [Notification]

            public init(
                id: String,
                name: String,
                services: [String] = [],
                autoConnect: Bool = true,
                notifications: [Notification] = []
            ) {
                self.id = id
                self.name = name
                self.services = services
                self.autoConnect = autoConnect
                self.notifications = notifications
            }
        }

        /// A canned characteristic value, delivered `afterMs` after connection.
        public struct Notification: Codable, Sendable, Equatable {
            public var characteristic: String
            public var valueHex: String
            public var afterMs: Int

            public init(characteristic: String, valueHex: String, afterMs: Int = 0) {
                self.characteristic = characteristic
                self.valueHex = valueHex
                self.afterMs = afterMs
            }
        }
    }

    public struct NFCTag: Codable, Sendable, Equatable {
        public var ndefText: String?
        public var ndefURL: String?
        public var failWith: String?

        public init(ndefText: String? = nil, ndefURL: String? = nil, failWith: String? = nil) {
            self.ndefText = ndefText
            self.ndefURL = ndefURL
            self.failWith = failWith
        }
    }
}

public extension KassTestCase {
    /// Launches the app with a hardware fixture. The app, linking `KassiOSStubs` in
    /// debug, replays these canned scanner / Bluetooth / NFC results through the
    /// seams it injects them into, instead of touching real hardware. The fixture
    /// is encoded into the `KASS_HARDWARE_JSON` launch-environment variable.
    @discardableResult
    func launch(
        hardware: KassHardwareFixture,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        var merged = environment
        if let data = try? JSONEncoder().encode(hardware),
           let json = String(data: data, encoding: .utf8) {
            merged["KASS_HARDWARE_JSON"] = json
        }
        return launch(arguments: arguments, environment: merged)
    }
}
