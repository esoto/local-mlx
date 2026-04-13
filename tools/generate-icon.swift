#!/usr/bin/env swift

// LocalMLX app icon generator.
//
// Run from the repo root:
//
//     swift tools/generate-icon.swift
//
// Produces all 10 sizes required by macOS `AppIcon.appiconset` and writes
// them into `LocalMLX/Resources/Assets.xcassets/AppIcon.appiconset/`. Run
// it once before `xcodegen generate`; the generated PNGs are checked in.
//
// The icon is drawn programmatically with AppKit/Core Graphics so there's
// no source asset to maintain and no external tooling required.

import AppKit
import Foundation

// MARK: - Sizes

struct IconSize {
    let pixels: Int
    let filename: String
}

let sizes: [IconSize] = [
    .init(pixels: 16,   filename: "icon_16x16.png"),
    .init(pixels: 32,   filename: "icon_16x16@2x.png"),
    .init(pixels: 32,   filename: "icon_32x32.png"),
    .init(pixels: 64,   filename: "icon_32x32@2x.png"),
    .init(pixels: 128,  filename: "icon_128x128.png"),
    .init(pixels: 256,  filename: "icon_128x128@2x.png"),
    .init(pixels: 256,  filename: "icon_256x256.png"),
    .init(pixels: 512,  filename: "icon_256x256@2x.png"),
    .init(pixels: 512,  filename: "icon_512x512.png"),
    .init(pixels: 1024, filename: "icon_512x512@2x.png"),
]

// MARK: - Drawing

/// Draws the LocalMLX icon at `size` × `size` pixels and returns PNG data.
///
/// The design is a rounded purple-to-blue square with a centered white
/// "sparkles" glyph — matching the sparkles used in-app for the assistant
/// avatar, so it reads as "AI chat" at a glance.
///
/// Uses `CGContext` directly rather than `NSImage.lockFocus()`, which
/// needs an AppKit event loop and crashes when run from a headless
/// command-line binary.
func renderIcon(size: Int) -> Data {
    let dimension = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext for size \(size)")
    }

    // Background gradient clipped to a rounded rect: deep purple → cobalt blue.
    let cornerRadius = dimension * 0.22
    let roundedPath = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil)
    ctx.addPath(roundedPath)
    ctx.clip()

    let colors = [
        CGColor(red: 0.43, green: 0.22, blue: 0.93, alpha: 1.0),   // #6D37ED
        CGColor(red: 0.18, green: 0.36, blue: 0.93, alpha: 1.0),   // #2E5CEC
    ] as CFArray
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: colors,
        locations: [0.0, 1.0]
    ) else {
        fatalError("Failed to build gradient for size \(size)")
    }
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: dimension),
        end: CGPoint(x: dimension, y: 0),
        options: []
    )

    // Subtle inner highlight — a slightly smaller rounded rect filled
    // with white at very low alpha.
    let inset = dimension * 0.03
    let highlightPath = CGPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        cornerWidth: cornerRadius * 0.9,
        cornerHeight: cornerRadius * 0.9,
        transform: nil)
    ctx.addPath(highlightPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
    ctx.fillPath()

    // Centered glyph drawn via Core Text so we don't need AppKit focus.
    let glyph = "✦"
    let fontSize = dimension * 0.58
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    ]
    let attrString = CFAttributedStringCreate(
        nil,
        glyph as CFString,
        attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attrString)
    let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
    ctx.textPosition = CGPoint(
        x: (dimension - bounds.width) / 2 - bounds.minX,
        y: (dimension - bounds.height) / 2 - bounds.minY
    )
    CTLineDraw(line, ctx)

    // Encode to PNG via CGImageDestination.
    guard let cgImage = ctx.makeImage() else {
        fatalError("Failed to snapshot CGContext for size \(size)")
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data, "public.png" as CFString, 1, nil
    ) else {
        fatalError("Failed to create PNG destination for size \(size)")
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Failed to finalize PNG for size \(size)")
    }
    return data as Data
}

// MARK: - Contents.json

let contentsJSON = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : {
    "author" : "LocalMLX",
    "version" : 1
  }
}
"""

// MARK: - Main

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconSetURL = cwd
    .appendingPathComponent("LocalMLX")
    .appendingPathComponent("Resources")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

try? fm.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

for size in sizes {
    let data = renderIcon(size: size.pixels)
    let out = iconSetURL.appendingPathComponent(size.filename)
    try data.write(to: out)
    print("wrote \(size.filename) (\(size.pixels)px)")
}

let contentsURL = iconSetURL.appendingPathComponent("Contents.json")
try contentsJSON.write(to: contentsURL, atomically: true, encoding: .utf8)
print("wrote Contents.json")
print("done — \(sizes.count) icons in \(iconSetURL.path)")
