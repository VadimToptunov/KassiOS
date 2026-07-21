import XCTest
import CoreGraphics
import ImageIO
@testable import KassiOS

final class KassSnapshotTests: XCTestCase {

    /// Encodes a solid-colour image to PNG in memory.
    private func makePNG(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> Data {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for pixel in stride(from: 0, to: buffer.count, by: 4) {
            buffer[pixel] = red
            buffer[pixel + 1] = green
            buffer[pixel + 2] = blue
            buffer[pixel + 3] = 255
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let image = context?.makeImage()
        let output = NSMutableData()
        if let image, let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return output as Data
    }

    func test_identicalImagesMatch() {
        let image = makePNG(width: 8, height: 8, red: 10, green: 20, blue: 30)
        XCTAssertEqual(KassSnapshotEngine.compare(image, image, tolerance: 0), .match)
    }

    func test_smallPerChannelDiffMatches() {
        let reference = makePNG(width: 10, height: 10, red: 100, green: 100, blue: 100)
        let candidate = makePNG(width: 10, height: 10, red: 104, green: 100, blue: 100)  // Δ4 ≤ 8
        XCTAssertEqual(KassSnapshotEngine.compare(reference, candidate, tolerance: 0), .match)
    }

    func test_largeColorDiffMismatch() {
        let reference = makePNG(width: 8, height: 8, red: 10, green: 20, blue: 30)
        let candidate = makePNG(width: 8, height: 8, red: 200, green: 50, blue: 60)
        if case .mismatch = KassSnapshotEngine.compare(reference, candidate, tolerance: 0) {
            // expected
        } else {
            XCTFail("expected a mismatch")
        }
    }

    func test_sizeMismatch() {
        let reference = makePNG(width: 4, height: 4, red: 0, green: 0, blue: 0)
        let candidate = makePNG(width: 5, height: 5, red: 0, green: 0, blue: 0)
        XCTAssertEqual(KassSnapshotEngine.compare(reference, candidate, tolerance: 0), .sizeMismatch)
    }

    func test_decodeFailed() {
        XCTAssertEqual(KassSnapshotEngine.compare(Data([1, 2, 3]), Data([4, 5, 6]), tolerance: 0), .decodeFailed)
    }

    /// Encodes a solid-colour image with one corner painted a different colour.
    private func makePNG(
        width: Int,
        height: Int,
        base: (red: UInt8, green: UInt8, blue: UInt8),
        corner: (red: UInt8, green: UInt8, blue: UInt8),
        cornerSize: Int
    ) -> Data {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for row in 0..<height {
            for col in 0..<width {
                let offset = row * bytesPerRow + col * 4
                if row < cornerSize, col < cornerSize {
                    buffer[offset] = corner.red
                    buffer[offset + 1] = corner.green
                    buffer[offset + 2] = corner.blue
                } else {
                    buffer[offset] = base.red
                    buffer[offset + 1] = base.green
                    buffer[offset + 2] = base.blue
                }
                buffer[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let image = context?.makeImage()
        let output = NSMutableData()
        if let image, let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return output as Data
    }

    func test_maskedRegionMakesDifferenceMatch() {
        let reference = makePNG(
            width: 10, height: 10, base: (10, 20, 30), corner: (10, 20, 30), cornerSize: 0
        )
        let candidate = makePNG(
            width: 10, height: 10, base: (10, 20, 30), corner: (250, 5, 5), cornerSize: 3
        )
        let maskedRegion = CGRect(x: 0, y: 0, width: 0.3, height: 0.3)
        let evaluation = KassSnapshotEngine.evaluate(
            reference: reference,
            candidate: candidate,
            tolerance: 0,
            ignoring: [maskedRegion]
        )
        XCTAssertEqual(evaluation.result, .match)
        XCTAssertNil(evaluation.diffPNG)
    }

    func test_differenceOutsideMaskStillMismatches() {
        let reference = makePNG(
            width: 10, height: 10, base: (10, 20, 30), corner: (250, 5, 5), cornerSize: 3
        )
        let candidate = makePNG(
            width: 10, height: 10, base: (200, 20, 30), corner: (250, 5, 5), cornerSize: 3
        )
        let maskedRegion = CGRect(x: 0, y: 0, width: 0.3, height: 0.3)
        let evaluation = KassSnapshotEngine.evaluate(
            reference: reference,
            candidate: candidate,
            tolerance: 0,
            ignoring: [maskedRegion]
        )
        if case .mismatch = evaluation.result {
            // expected
        } else {
            XCTFail("expected a mismatch outside the masked region")
        }
    }

    func test_evaluateReturnsDiffPNGOnMismatch() {
        let reference = makePNG(width: 8, height: 8, red: 10, green: 20, blue: 30)
        let candidate = makePNG(width: 8, height: 8, red: 200, green: 50, blue: 60)
        let evaluation = KassSnapshotEngine.evaluate(reference: reference, candidate: candidate, tolerance: 0)
        guard case .mismatch = evaluation.result, let diffPNG = evaluation.diffPNG else {
            XCTFail("expected a mismatch with a non-nil diff PNG")
            return
        }
        guard let diffBitmap = KassSnapshotEngine.bitmap(from: diffPNG) else {
            XCTFail("diff PNG should decode")
            return
        }
        guard let referenceBitmap = KassSnapshotEngine.bitmap(from: reference) else {
            XCTFail("reference PNG should decode")
            return
        }
        XCTAssertEqual(diffBitmap.width, referenceBitmap.width)
        XCTAssertEqual(diffBitmap.height, referenceBitmap.height)
    }

    func test_evaluateReturnsNilDiffPNGOnMatch() {
        let image = makePNG(width: 8, height: 8, red: 10, green: 20, blue: 30)
        let evaluation = KassSnapshotEngine.evaluate(reference: image, candidate: image, tolerance: 0)
        XCTAssertEqual(evaluation.result, .match)
        XCTAssertNil(evaluation.diffPNG)
    }
}
