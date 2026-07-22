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
        var bytes: [UInt8]
    }

    /// Compares two PNGs. `tolerance` is the maximum share of differing bytes
    /// (0...1); `perChannel` is the allowed per-channel delta (0...255).
    static func compare(_ lhs: Data, _ rhs: Data, tolerance: Double, perChannel: Int = 8) -> KassSnapshotResult {
        evaluate(reference: lhs, candidate: rhs, tolerance: tolerance, perChannel: perChannel).result
    }

    /// Compares two PNGs and, on mismatch, also renders a visual diff PNG
    /// (unaffected pixels dimmed, differing pixels flagged opaque red).
    /// `regions` are normalized (0...1) rects masked out of both images first.
    static func evaluate(
        reference: Data,
        candidate: Data,
        tolerance: Double,
        perChannel: Int = 8,
        ignoring regions: [CGRect] = []
    ) -> (result: KassSnapshotResult, diffPNG: Data?) {
        guard var left = bitmap(from: reference), var right = bitmap(from: candidate) else {
            return (.decodeFailed, nil)
        }
        guard left.width == right.width, left.height == right.height else {
            return (.sizeMismatch, nil)
        }
        applyMask(&left, regions: regions)
        applyMask(&right, regions: regions)

        let total = left.bytes.count
        guard total > 0 else { return (.match, nil) }

        var diffCount = 0
        for index in 0..<total where abs(Int(left.bytes[index]) - Int(right.bytes[index])) > perChannel {
            diffCount += 1
        }
        let ratio = Double(diffCount) / Double(total)
        guard ratio > tolerance else { return (.match, nil) }
        let diff = diffBitmap(left, right, perChannel: perChannel)
        return (.mismatch(ratio: ratio), png(from: diff))
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

    /// Encodes an RGBA premultiplied-last bitmap to PNG data.
    static func png(from bitmap: Bitmap) -> Data? {
        var buffer = bitmap.bytes
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &buffer,
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bytesPerRow: bitmap.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Builds a visual diff, same size as `reference`: differing pixels turn opaque
    /// red, matching pixels turn a dimmed grayscale of `reference` (faint context).
    /// Assumes both bitmaps are the same size — only call this after a size check.
    static func diffBitmap(_ reference: Bitmap, _ candidate: Bitmap, perChannel: Int) -> Bitmap {
        var bytes = [UInt8](repeating: 0, count: reference.bytes.count)
        let pixelCount = reference.width * reference.height
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            var differs = false
            for channel in 0..<4
            where abs(Int(reference.bytes[offset + channel]) - Int(candidate.bytes[offset + channel])) > perChannel {
                differs = true
                break
            }
            if differs {
                bytes[offset] = 255
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
                bytes[offset + 3] = 255
            } else {
                // Faint context: average the 3 channels (÷3), then darken 3× (÷3 → ÷9).
                let sum = Int(reference.bytes[offset]) + Int(reference.bytes[offset + 1]) + Int(reference.bytes[offset + 2])
                let gray = UInt8(sum / 9)
                bytes[offset] = gray
                bytes[offset + 1] = gray
                bytes[offset + 2] = gray
                bytes[offset + 3] = 255
            }
        }
        return Bitmap(width: reference.width, height: reference.height, bytes: bytes)
    }

    /// Zeroes the pixels inside each `regions` rect (normalized 0...1, in-place).
    /// Neutralizes dynamic content (clock, timestamps) before comparing.
    static func applyMask(_ bitmap: inout Bitmap, regions: [CGRect]) {
        guard !regions.isEmpty else { return }
        let width = bitmap.width
        let height = bitmap.height
        for region in regions {
            let x0 = max(0, min(width, Int((region.minX * CGFloat(width)).rounded(.down))))
            let y0 = max(0, min(height, Int((region.minY * CGFloat(height)).rounded(.down))))
            let x1 = max(0, min(width, Int((region.maxX * CGFloat(width)).rounded(.up))))
            let y1 = max(0, min(height, Int((region.maxY * CGFloat(height)).rounded(.up))))
            guard x0 < x1, y0 < y1 else { continue }
            for row in y0..<y1 {
                let rowStart = row * width * 4
                for col in x0..<x1 {
                    let offset = rowStart + col * 4
                    bitmap.bytes[offset] = 0
                    bitmap.bytes[offset + 1] = 0
                    bitmap.bytes[offset + 2] = 0
                    bitmap.bytes[offset + 3] = 0
                }
            }
        }
    }
}

@MainActor
public extension KassTestCase {

    /// Asserts the current screen (or `element`) matches a stored reference image.
    ///
    /// References go in `$KASS_SNAPSHOTS_PATH` when set (recommended on CI, where
    /// the source path may be read-only or different), otherwise a `__Snapshots__`
    /// folder beside the calling test file. The first run (or `record: true`, or
    /// the `KASS_RECORD_SNAPSHOTS` env var) writes the reference and fails,
    /// prompting you to commit it. Comparison is pixel-based — pin device and OS.
    /// `regions` are normalized (0...1, relative to the image) rects masked out
    /// of both images before comparing — use them to neutralize dynamic content
    /// such as a status-bar clock. Keep them tight: a region covering the whole
    /// frame makes any two images match. On mismatch the reference, actual, and
    /// a generated diff image are all attached to the test.
    func assertSnapshot(
        of element: KassElement? = nil,
        named name: String,
        record: Bool = false,
        tolerance: Double = 0.02,
        ignoring regions: [CGRect] = [],
        file: StaticString = #filePath,
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

        let evaluation = KassSnapshotEngine.evaluate(
            reference: referenceData,
            candidate: png,
            tolerance: tolerance,
            ignoring: regions
        )
        switch evaluation.result {
        case .match:
            break
        case .mismatch(let ratio):
            attachSnapshotArtifacts(name: name, referencePNG: referenceData, actualPNG: png, diffPNG: evaluation.diffPNG)
            if evaluation.diffPNG == nil {
                config.logger.log("⚠️ Snapshot '\(name)' diff image could not be rendered")
            }
            let diff = String(format: "%.2f%%", ratio * 100)
            let allowed = String(format: "%.2f%%", tolerance * 100)
            XCTFail("Snapshot '\(name)' differs by \(diff) (> \(allowed))", file: file, line: line)
        case .sizeMismatch:
            attachSnapshotArtifacts(name: name, referencePNG: referenceData, actualPNG: png, diffPNG: nil)
            XCTFail("Snapshot '\(name)' size differs from the reference — device/OS mismatch?", file: file, line: line)
        case .decodeFailed:
            XCTFail("Snapshot '\(name)' could not be decoded", file: file, line: line)
        case .recorded:
            break
        }
    }

    private func attachSnapshotArtifacts(name: String, referencePNG: Data, actualPNG: Data, diffPNG: Data?) {
        attachSnapshotPNG(referencePNG, name: "Snapshot reference — \(name)")
        attachSnapshotPNG(actualPNG, name: "Snapshot actual — \(name)")
        if let diffPNG {
            attachSnapshotPNG(diffPNG, name: "Snapshot diff — \(name)")
        }
    }

    private func attachSnapshotPNG(_ png: Data, name: String) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
