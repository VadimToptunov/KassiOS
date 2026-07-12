import XCTest
import CoreGraphics
import ImageIO

/// Outcome of a snapshot comparison.
public enum KassSnapshotResult: Equatable {
    case recorded
    case match
    case mismatch(ratio: Double)
    case sizeMismatch
    case decodeFailed
}

/// Zero-dependency image comparison for snapshot regression. Decodes PNGs with
/// ImageIO/CoreGraphics and compares pixels with a tolerance — no third-party
/// library. Snapshot references are pixel-exact, so pin the device/OS.
enum KassSnapshotEngine {

    struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    /// Compares two PNGs. `tolerance` is the maximum share of differing bytes
    /// (0...1); `perChannel` is the allowed per-channel delta (0...255).
    static func compare(_ lhs: Data, _ rhs: Data, tolerance: Double, perChannel: Int = 8) -> KassSnapshotResult {
        guard let left = bitmap(from: lhs), let right = bitmap(from: rhs) else { return .decodeFailed }
        guard left.width == right.width, left.height == right.height else { return .sizeMismatch }
        let total = left.bytes.count
        guard total > 0 else { return .match }

        var diffCount = 0
        for index in 0..<total where abs(Int(left.bytes[index]) - Int(right.bytes[index])) > perChannel {
            diffCount += 1
        }
        let ratio = Double(diffCount) / Double(total)
        return ratio <= tolerance ? .match : .mismatch(ratio: ratio)
    }

    static func bitmap(from data: Data) -> Bitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(width: width, height: height, bytes: buffer)
    }
}

public extension KassTestCase {

    /// Asserts the current screen (or `element`) matches a stored reference image.
    ///
    /// References go in `$KASS_SNAPSHOTS_PATH` when set (recommended on CI, where
    /// the source path may be read-only or different), otherwise a `__Snapshots__`
    /// folder beside the calling test file. The first run (or `record: true`, or
    /// the `KASS_RECORD_SNAPSHOTS` env var) writes the reference and fails,
    /// prompting you to commit it. Comparison is pixel-based — pin device and OS.
    func assertSnapshot(
        of element: KassElement? = nil,
        named name: String,
        record: Bool = false,
        tolerance: Double = 0.02,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let screenshot = element.map { $0.resolve().screenshot() } ?? app.screenshot()
        let png = screenshot.pngRepresentation

        let directory = ProcessInfo.processInfo.environment["KASS_SNAPSHOTS_PATH"]
            ?? (("\(file)" as NSString).deletingLastPathComponent + "/__Snapshots__")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let reference = (directory as NSString).appendingPathComponent("\(name).png")

        let recording = record || ProcessInfo.processInfo.environment["KASS_RECORD_SNAPSHOTS"] != nil
        let exists = FileManager.default.fileExists(atPath: reference)

        if recording || !exists {
            try? png.write(to: URL(fileURLWithPath: reference))
            config.logger.log("📷 Recorded snapshot '\(name)' → \(reference)")
            XCTFail("Recorded snapshot '\(name)'. Commit it and re-run with recording off.", file: file, line: line)
            return
        }

        guard let referenceData = try? Data(contentsOf: URL(fileURLWithPath: reference)) else {
            XCTFail("Could not read snapshot reference '\(name)'", file: file, line: line)
            return
        }

        switch KassSnapshotEngine.compare(png, referenceData, tolerance: tolerance) {
        case .match:
            break
        case .mismatch(let ratio):
            attachSnapshotFailure(name: name, png: png)
            let diff = String(format: "%.2f%%", ratio * 100)
            let allowed = String(format: "%.2f%%", tolerance * 100)
            XCTFail("Snapshot '\(name)' differs by \(diff) (> \(allowed))", file: file, line: line)
        case .sizeMismatch:
            attachSnapshotFailure(name: name, png: png)
            XCTFail("Snapshot '\(name)' size differs from the reference — device/OS mismatch?", file: file, line: line)
        case .decodeFailed:
            XCTFail("Snapshot '\(name)' could not be decoded", file: file, line: line)
        case .recorded:
            break
        }
    }

    private func attachSnapshotFailure(name: String, png: Data) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "Snapshot mismatch — \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
