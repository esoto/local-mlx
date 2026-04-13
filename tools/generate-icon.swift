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
func renderIcon(size: Int) -> Data {
    let dimension = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: dimension, height: dimension)

    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("Failed to acquire CGContext for size \(size)")
    }

    // Background gradient: deep purple → cobalt blue.
    let cornerRadius = dimension * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()

    let colors = [
        CGColor(red: 0.43, green: 0.22, blue: 0.93, alpha: 1.0),   // #6D37ED
        CGColor(red: 0.18, green: 0.36, blue: 0.93, alpha: 1.0),   // #2E5CEC
    ]
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: dimension),
        end: CGPoint(x: dimension, y: 0),
        options: []
    )

    // Subtle inner highlight.
    let highlight = NSBezierPath(
        roundedRect: rect.insetBy(dx: dimension * 0.03, dy: dimension * 0.03),
        xRadius: cornerRadius * 0.9,
        yRadius: cornerRadius * 0.9
    )
    NSColor.white.withAlphaComponent(0.06).setFill()
    highlight.fill()

    // Sparkles glyph — use the SF Symbol if the OS provides it, else fall
    // back to a large centered dot so the script still runs on older OSes.
    let glyphFontSize = dimension * 0.58
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: glyphFontSize, weight: .bold),
        .foregroundColor: NSColor.white
    ]

    let glyph: String
    if let config = NSImage.SymbolConfiguration(pointSize: glyphFontSize, weight: .bold) as NSImage.SymbolConfiguration?,
       let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
           .withSymbolConfiguration(config) {
        let w = symbol.size.width
        let h = symbol.size.height
        let scale = min(dimension * 0.6 / w, dimension * 0.6 / h)
        let drawW = w * scale
        let drawH = h * scale
        let drawRect = NSRect(
            x: (dimension - drawW) / 2,
            y: (dimension - drawH) / 2,
            width: drawW,
            height: drawH
        )
        // Tint the symbol white.
        NSColor.white.set()
        symbol.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceAtop,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
        // Also overlay a white-coloring pass via a rectangle with sourceIn.
        ctx.setBlendMode(.sourceAtop)
        NSColor.white.setFill()
        drawRect.fill()
        ctx.setBlendMode(.normal)
        glyph = ""
    } else {
        glyph = "✦"
    }

    if !glyph.isEmpty {
        let text = glyph as NSString
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (dimension - textSize.width) / 2,
            y: (dimension - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    // Convert to PNG.
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for size \(size)")
    }
    return pngData
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
