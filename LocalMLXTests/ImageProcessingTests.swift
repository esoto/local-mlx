import XCTest
import AppKit
@testable import LocalMLX

final class ImageProcessingTests: XCTestCase {

    // MARK: - Test image generators

    /// Build a PNG blob at the given size. Uses a solid colour fill
    /// so the bytes are deterministic enough for tests.
    private func makePNG(width: Int, height: Int) -> Data {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("could not synthesize PNG at \(width)x\(height)")
            return Data()
        }
        return png
    }

    /// Decode an arbitrary image blob back to (width, height) pixels.
    private func pixelSize(of data: Data) -> (Int, Int)? {
        guard let image = NSImage(data: data) else { return nil }
        return (Int(image.size.width), Int(image.size.height))
    }

    // MARK: - Passthrough

    func test_process_smallImage_passesOriginalBytesThrough() {
        let input = makePNG(width: 256, height: 256)
        let result = ImageProcessing.process(input, originalMimeType: "image/png")

        XCTAssertEqual(result?.data, input,
                       "small images should pass through byte-for-byte (no lossy re-encode)")
        XCTAssertEqual(result?.mimeType, "image/png")
        XCTAssertEqual(result?.width, 256)
        XCTAssertEqual(result?.height, 256)
    }

    func test_process_exactMaxDimension_passesThrough() {
        // Anything at or under the cap must pass through unchanged.
        let dim = Int(ImageProcessing.maxDimension)
        let input = makePNG(width: dim, height: dim / 2)
        let result = ImageProcessing.process(input, originalMimeType: "image/png")

        XCTAssertEqual(result?.data, input)
        XCTAssertEqual(result?.width, dim)
        XCTAssertEqual(result?.height, dim / 2)
    }

    // MARK: - Downscale

    func test_process_oversizedImage_downscalesLongestEdgeToMax() {
        // 4000x2000 should scale to 2048x1024 (longest edge caps at 2048,
        // aspect preserved).
        let input = makePNG(width: 4000, height: 2000)
        let result = ImageProcessing.process(input, originalMimeType: "image/png")

        XCTAssertEqual(result?.width, 2048)
        XCTAssertEqual(result?.height, 1024)
    }

    func test_process_oversizedImage_switchesToJPEG() {
        let input = makePNG(width: 4000, height: 2000)
        let result = ImageProcessing.process(input, originalMimeType: "image/png")
        XCTAssertEqual(result?.mimeType, "image/jpeg",
                       "downscaled images are re-encoded as JPEG")
    }

    func test_process_oversizedImage_dataIsSmallerThanOriginal() {
        let input = makePNG(width: 4000, height: 4000)
        let result = ImageProcessing.process(input, originalMimeType: "image/png")
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.data.count, input.count,
                          "downscaled + JPEG'd output should be smaller")
    }

    func test_process_tallPortrait_capsHeightNotWidth() {
        // Portrait 1000x4000: longest edge (4000) caps at 2048, so scale
        // is 2048/4000 = 0.512 and width becomes 1000 * 0.512 = 512.
        let input = makePNG(width: 1000, height: 4000)
        let result = ImageProcessing.process(input, originalMimeType: "image/png")
        XCTAssertEqual(result?.height, 2048)
        XCTAssertEqual(result?.width, 512)
    }

    // MARK: - Corrupt input

    func test_process_junkBytes_returnsNil() {
        let result = ImageProcessing.process(
            Data("not an image".utf8), originalMimeType: "image/png")
        XCTAssertNil(result, "unreadable input should be rejected")
    }

    func test_process_emptyData_returnsNil() {
        let result = ImageProcessing.process(Data(), originalMimeType: "image/png")
        XCTAssertNil(result)
    }

    // MARK: - Round-trip decode verification

    func test_process_downscaledBytes_decodeBackToStatedDimensions() {
        // Sanity: after downscaling, the declared width/height should
        // match what NSImage sees if it re-decodes the output bytes.
        let input = makePNG(width: 3000, height: 1500)
        guard let result = ImageProcessing.process(input, originalMimeType: "image/png"),
              let (decW, decH) = pixelSize(of: result.data)
        else {
            XCTFail("could not process or re-decode")
            return
        }
        XCTAssertEqual(decW, result.width)
        XCTAssertEqual(decH, result.height)
    }
}
