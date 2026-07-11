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
}
