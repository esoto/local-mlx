import Foundation
import AppKit
import CoreGraphics

/// Downscales and re-encodes pasted/dropped/attached images before they
/// get stored on a `Message` and later base64-encoded into a request
/// body. Vision models generally don't benefit from resolutions above
/// ~2048 px on the longest edge, and larger images make the resulting
/// `data:` URL enormous (a 12 MP phone screenshot is ~4 MB raw and
/// ~5.3 MB after base64), which wastes wire time and RAM on every
/// request.
///
/// Kept as a pure value-in/value-out helper so tests can assert on
/// real image bytes without spinning up any SwiftUI or NSViewController.
enum ImageProcessing {

    /// Longest-edge cap in pixels. Anything wider or taller gets
    /// proportionally downscaled until it fits. Anything already below
    /// the cap is passed through without resampling.
    static let maxDimension: CGFloat = 2048

    /// JPEG quality for the re-encoded output. 0.85 balances visible
    /// quality with size — higher values produce diminishing returns
    /// for the kind of images a chat user typically drops.
    static let jpegQuality: CGFloat = 0.85

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
        guard let image = NSImage(data: input) else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        // Under the cap: pass through. This keeps small images
        // byte-for-byte identical instead of round-tripping them
        // through JPEG and introducing compression artefacts for no
        // reason.
        if originalSize.width <= maxDimension && originalSize.height <= maxDimension {
            return Processed(
                data: input,
                mimeType: originalMimeType,
                width: Int(originalSize.width),
                height: Int(originalSize.height)
            )
        }

        // Over the cap: compute the target size preserving aspect ratio
        // then resample through CGContext.
        let scale = maxDimension / max(originalSize.width, originalSize.height)
        let targetWidth = Int((originalSize.width * scale).rounded())
        let targetHeight = Int((originalSize.height * scale).rounded())

        guard let resized = downscale(image, to: CGSize(width: targetWidth, height: targetHeight)),
              let jpegData = jpegEncode(resized)
        else { return nil }

        return Processed(
            data: jpegData,
            mimeType: "image/jpeg",
            width: targetWidth,
            height: targetHeight
        )
    }

    // MARK: - Internal helpers

    /// Resample an `NSImage` to the given target size using a bitmap
    /// context. Returns nil if either the source has no usable
    /// representation or the target context can't be created.
    static func downscale(_ image: NSImage, to target: CGSize) -> NSImage? {
        let result = NSImage(size: target)
        result.lockFocus()
        defer { result.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: .zero,
            operation: .copy,
            fraction: 1.0)
        return result
    }

    /// Encode an `NSImage` as JPEG bytes at `jpegQuality`.
    static func jpegEncode(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: jpegQuality]
        )
    }
}
