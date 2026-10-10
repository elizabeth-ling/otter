#!/usr/bin/env swift
// Renders images/app-icon.svg into the macOS app icon set: the glyph centred
// on a white rounded-square tile, following the macOS icon grid (an 824pt tile
// inset 100pt on a 1024pt canvas, with a soft drop shadow). Also copies the SVG
// into MenuBarIcon.imageset, where it is the menu bar's template image.
//
//   swift scripts/app-icon.swift
//
// Run it from the repository root after changing the SVG, and commit the results.
import AppKit

let svgURL = URL(fileURLWithPath: "images/app-icon.svg")
let setURL = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset")
let menuBarURL = URL(fileURLWithPath: "App/Resources/Assets.xcassets/MenuBarIcon.imageset/app-icon.svg")

guard let glyph = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write("could not read \(svgURL.path)\n".data(using: .utf8)!)
    exit(1)
}

/// Draws the icon on a `pixels`-square canvas.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024

    // Tile with a drop shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824).scaled(by: scale)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowBlurRadius = 20 * scale
    shadow.set()
    NSColor.white.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Barely-there top-to-bottom shading so the tile isn't flat.
    NSGradient(starting: .white, ending: NSColor(white: 0.93, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    // Glyph, 460pt tall, centred on the tile.
    let glyphHeight: CGFloat = 460
    let glyphWidth = glyphHeight * glyph.size.width / glyph.size.height
    let glyphRect = NSRect(
        x: 512 - glyphWidth / 2, y: 512 - glyphHeight / 2,
        width: glyphWidth, height: glyphHeight
    ).scaled(by: scale)
    glyph.draw(in: glyphRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSRect {
    func scaled(by s: CGFloat) -> NSRect {
        NSRect(x: minX * s, y: minY * s, width: width * s, height: height * s)
    }
}

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon_\(size)x\(size)\(factor == 2 ? "@2x" : "").png"
        try render(pixels: size * factor).write(to: setURL.appendingPathComponent(name))
        images.append(
            #"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(factor)x", "size" : "\#(size)x\#(size)" }"#)
    }
}

let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
try contents.write(to: setURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) icons to \(setURL.path)")

try? FileManager.default.removeItem(at: menuBarURL)
try FileManager.default.copyItem(at: svgURL, to: menuBarURL)
print("copied \(svgURL.path) to \(menuBarURL.path)")
