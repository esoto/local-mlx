import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LocalMLX

final class ImageProcessingTests: XCTestCase {

    // MARK: - Test image generators

    /// Build a PNG blob at the exact pixel dimensions requested.
    /// Uses `CGContext` + `CGImageDestination` rather than
    /// `NSImage.lockFocus`, because NSImage sizes are in *points*
    /// and on a Retina display a nominal 2048×1024 NSImage comes
    /// out as a 4096×2048 bitmap — which breaks every passthrough
    /// assertion. The CG path has no such ambiguity.
    private func makePNG(width: Int, height: Int) -> Data {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("could not create CGContext at \(width)x\(height)")
            return Data()
        }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = ctx.makeImage() else {
            XCTFail("could not snapshot CGContext")
            return Data()
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            XCTFail("could not create PNG destination")
            return Data()
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            XCTFail("could not finalize PNG")
            return Data()
        }
        return data as Data
    }

    /// Decode an arbitrary image blob back to (width, height) pixels.
    /// Uses `CGImageSource` so the values are true pixel counts, not
    /// points.
    private func pixelSize(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return ImageProcessing.pixelSize(of: source)
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
