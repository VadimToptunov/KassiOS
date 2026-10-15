import Foundation

public extension KassiOSStubs {
    /// Decodes the hardware fixture passed by `KassTestCase.launch(hardware:)`, or
    /// `nil` when the app was not launched with one (the production path). Call it
    /// from your composition root in debug to decide whether to inject the stub
    /// implementations below.
    static func hardwareFixture(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KassHardwareFixtureDefinition? {
        guard let json = environment["KASS_HARDWARE_JSON"],
              let data = json.data(using: .utf8),
              let fixture = try? JSONDecoder().decode(KassHardwareFixtureDefinition.self, from: data)
        else { return nil }
        return fixture
    }
}

/// App-side copy of the hardware wire contract. Keep its `Codable` shape identical
/// to KassiOS's test-side `KassHardwareFixture`. The app only ever decodes this —
/// it never constructs it — so its initializers stay memberwise-internal.
public struct KassHardwareFixtureDefinition: Codable {
    public let scanner: [ScanResult]
    public let bluetooth: BluetoothScript?
    public let nfc: [NFCTag]

    public struct ScanResult: Codable {
        public let payload: String
        public let symbology: String?
        public let failWith: String?
    }

    public struct BluetoothScript: Codable {
        public let peripherals: [BluetoothPeripheral]
    }

    public struct BluetoothPeripheral: Codable {
        public let id: String
        public let name: String
        public let services: [String]
        public let autoConnect: Bool
        public let notifications: [BluetoothNotification]
    }

    public struct BluetoothNotification: Codable {
        public let characteristic: String
        public let valueHex: String
        public let afterMs: Int
    }

    public struct NFCTag: Codable {
        public let ndefText: String?
        public let ndefURL: String?
        public let failWith: String?
    }
}

/// Thrown by a stub when the fixture scripted a failure for this call, so the app's
/// error path runs exactly as it would for a real hardware error.
public struct KassStubbedFailure: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Replays scripted scanner results in order. In debug, wire your app's scanner
/// seam to call ``next()`` when a fixture is present.
public final class KassScannerStub {
    private var queue: [KassHardwareFixtureDefinition.ScanResult]
    private let lock = NSLock()

    public init(_ results: [KassHardwareFixtureDefinition.ScanResult]) {
        self.queue = results
    }

    /// The next scripted scan's payload, or a thrown ``KassStubbedFailure`` when the
    /// result scripted one. Throws once the queue is drained, so an over-eager test
    /// surfaces a clear error instead of a silent empty string.
    public func next() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !queue.isEmpty else { throw KassStubbedFailure("no more scripted scan results") }
        let result = queue.removeFirst()
        if let failure = result.failWith { throw KassStubbedFailure(failure) }
        return result.payload
    }
}

/// Replays a scripted Bluetooth environment: the peripherals a scan "discovers"
/// and their scheduled characteristic notifications.
public final class KassBLEStub {
    public let peripherals: [KassHardwareFixtureDefinition.BluetoothPeripheral]

    public init(_ script: KassHardwareFixtureDefinition.BluetoothScript?) {
        self.peripherals = script?.peripherals ?? []
    }

    /// Peripherals a scripted scan discovers.
    public func discovered() -> [KassHardwareFixtureDefinition.BluetoothPeripheral] {
        peripherals
    }

    /// Scheduled notifications for a peripheral as (characteristic, decoded bytes,
    /// delay). A notification whose `valueHex` is malformed yields empty `Data`.
    public func notifications(for id: String)
        -> [(characteristic: String, value: Data, afterMs: Int)] {
        let peripheral = peripherals.first { $0.id == id }
        return (peripheral?.notifications ?? []).map {
            (characteristic: $0.characteristic, value: Data(hex: $0.valueHex) ?? Data(), afterMs: $0.afterMs)
        }
    }
}

/// Replays scripted NFC tags in order, mirroring ``KassScannerStub``.
public final class KassNFCStub {
    private var queue: [KassHardwareFixtureDefinition.NFCTag]
    private let lock = NSLock()

    public init(_ tags: [KassHardwareFixtureDefinition.NFCTag]) {
        self.queue = tags
    }

    /// The next scripted tag, or a thrown ``KassStubbedFailure`` when it scripted
    /// one. Throws once the queue is drained.
    public func next() throws -> KassHardwareFixtureDefinition.NFCTag {
        lock.lock()
        defer { lock.unlock() }
        guard !queue.isEmpty else { throw KassStubbedFailure("no more scripted NFC tags") }
        let tag = queue.removeFirst()
        if let failure = tag.failWith { throw KassStubbedFailure(failure) }
        return tag
    }
}

extension Data {
    /// Parses an even-length hex string (e.g. `"0a1b2c"`) into bytes; `nil` on odd
    /// length or a non-hex character.
    init?(hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(chars[index ... index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self = Data(bytes)
    }
}
