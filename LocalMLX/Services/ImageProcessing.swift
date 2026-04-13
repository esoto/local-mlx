import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Downscales and re-encodes pasted/dropped/attached images before they
/// get stored on a `Message` and later base64-encoded into a request
/// body. Vision models generally don't benefit from resolutions above
/// ~2048 px on the longest edge, and larger images make the resulting
/// `data:` URL enormous (a 12 MP phone screenshot is ~4 MB raw and
/// ~5.3 MB after base64), which wastes wire time and RAM on every
/// request.
///
/// Built on `CGImageSource` / `CGContext` / `CGImageDestination` so
/// every path is safe to call from a background thread. The earlier
/// version used `NSImage.lockFocus()` which requires an AppKit
/// main-thread context — fine when called from a SwiftUI view body,
/// broken the moment we moved drop processing into a
/// `Task.detached`, because `lockFocus` silently returned a blank
/// image off the main thread and the whole attachment pipeline
/// looked like it was dropping images on the floor.
enum ImageProcessing {

    /// Longest-edge cap in pixels. Anything wider or taller gets
    /// proportionally downscaled until it fits. Anything already below
    /// the cap is passed through without resampling.
    static let maxDimension: Int = 2048

    /// JPEG quality for the re-encoded output. 0.85 balances visible
    /// quality with size — higher values produce diminishing returns
    /// for the kind of images a chat user typically drops.
    static let jpegQuality: Double = 0.85

    /// Result of processing an attachment.
    struct Processed: Equatable {
        let data: Data
        let mimeType: String
        let width: Int
        let height: Int
    }

    /// Process raw image bytes: if the input decodes to an image
    /// smaller than `maxDimension` on every side, pass the original
    /// bytes and MIME type through unchanged. Otherwise, downscale
    /// proportionally and re-encode as JPEG at `jpegQuality`.
    /// Returns `nil` if the input isn't a recognisable image.
    static func process(_ input: Data, originalMimeType: String) -> Processed? {
        guard let source = CGImageSourceCreateWithData(input as CFData, nil) else {
            return nil
        }
        guard let (originalWidth, originalHeight) = pixelSize(of: source) else {
            return nil
        }

        // Under the cap on both sides: pass through untouched. Keeps
        // small PNGs byte-for-byte identical instead of round-tripping
        // through JPEG and introducing artefacts for no reason.
        if originalWidth <= maxDimension && originalHeight <= maxDimension {
            return Processed(
                data: input,
                mimeType: originalMimeType,
                width: originalWidth,
                height: originalHeight)
        }

        // Over the cap: compute the target size preserving aspect ratio
        // then resample through a CGContext. All CG APIs here are
        // thread-safe, unlike NSImage.lockFocus.
        let scale = Double(maxDimension) / Double(max(originalWidth, originalHeight))
        let targetWidth = Int((Double(originalWidth) * scale).rounded())
        let targetHeight = Int((Double(originalHeight) * scale).rounded())

        guard let resized = resample(source: source,
                                     toWidth: targetWidth,
                                     toHeight: targetHeight),
              let jpegData = jpegEncode(resized)
        else {
            return nil
        }

        return Processed(
            data: jpegData,
            mimeType: "image/jpeg",
            width: targetWidth,
            height: targetHeight)
    }

    // MARK: - Internal helpers

    /// Pull pixel dimensions out of a `CGImageSource` without fully
    /// decoding the image. Fast and thread-safe.
    static func pixelSize(of source: CGImageSource) -> (Int, Int)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(
                source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// Decode + resample to the target size via a fresh RGBA CGContext.
    /// No NSImage, no AppKit event loop — safe from any queue.
    static func resample(
        source: CGImageSource,
        toWidth width: Int,
        toHeight height: Int
    ) -> CGImage? {
        guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Encode a `CGImage` as JPEG bytes at `jpegQuality`. Uses
    /// `CGImageDestination` so no NSImage is required.
    static func jpegEncode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
