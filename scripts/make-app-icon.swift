#!/usr/bin/env swift
//
//  make-app-icon.swift
//  fmhy
//
//  Renders the AppIcon set: a rounded list glyph on an indigo gradient.
//  Usage: swift scripts/make-app-icon.swift [AppIcon.appiconset directory]
//

import AppKit

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "fmhy/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

enum Variant { case standard, dark, tinted }

func bitmap(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    return rep
}

/// Three stacked "list" bars plus a sparkle, drawn inside `rect`.
func drawGlyph(in rect: NSRect, barAlpha: [CGFloat], sparkleColor: NSColor) {
    let unit = rect.width / 1024
    let barHeight = 92 * unit
    let gap = 58 * unit
    let widths: [CGFloat] = [520, 520, 340]
    let left = rect.midX - 260 * unit
    var y = rect.midY - (3 * barHeight + 2 * gap) / 2

    for index in widths.indices {
        let bar = NSRect(x: left, y: y, width: widths[index] * unit, height: barHeight)
        NSColor.white.withAlphaComponent(barAlpha[index]).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        y += barHeight + gap
    }

    let center = NSPoint(x: rect.midX + 250 * unit, y: rect.midY + 300 * unit)
    let radius = 86 * unit
    let pinch = radius * 0.14
    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: center.x, y: center.y + radius))
    sparkle.curve(
        to: NSPoint(x: center.x + radius, y: center.y),
        controlPoint1: NSPoint(x: center.x + pinch, y: center.y + pinch),
        controlPoint2: NSPoint(x: center.x + pinch, y: center.y + pinch)
    )
    sparkle.curve(
        to: NSPoint(x: center.x, y: center.y - radius),
        controlPoint1: NSPoint(x: center.x + pinch, y: center.y - pinch),
        controlPoint2: NSPoint(x: center.x + pinch, y: center.y - pinch)
    )
    sparkle.curve(
        to: NSPoint(x: center.x - radius, y: center.y),
        controlPoint1: NSPoint(x: center.x - pinch, y: center.y - pinch),
        controlPoint2: NSPoint(x: center.x - pinch, y: center.y - pinch)
    )
    sparkle.curve(
        to: NSPoint(x: center.x, y: center.y + radius),
        controlPoint1: NSPoint(x: center.x - pinch, y: center.y + pinch),
        controlPoint2: NSPoint(x: center.x - pinch, y: center.y + pinch)
    )
    sparkle.close()
    sparkleColor.setFill()
    sparkle.fill()
}

func render(pixels: Int, variant: Variant, rounded: Bool) -> NSBitmapImageRep {
    let rep = bitmap(pixels)
    let size = CGFloat(pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = rounded ? size * 0.085 : 0
    let art = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
    let corner = rounded ? art.width * 0.225 : 0
    let shape = NSBezierPath(roundedRect: art, xRadius: corner, yRadius: corner)

    if variant != .tinted {
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()

        let top: NSColor
        let bottom: NSColor
        switch variant {
        case .standard:
            top = color(0x5B54E8)
            bottom = color(0x7C3AED)
        case .dark:
            // iOS paints its dark icon slot on a dark home screen, so this is a
            // separate design on a near-black backdrop rather than a dimmed copy.
            top = color(0x1B1930)
            bottom = color(0x07070C)
        case .tinted:
            top = .white
            bottom = .white
        }
        NSGradient(starting: bottom, ending: top)?.draw(
            from: NSPoint(x: art.minX, y: art.minY),
            to: NSPoint(x: art.maxX, y: art.maxY),
            options: []
        )

        // Soft highlight in the upper-left corner.
        NSColor.white.withAlphaComponent(variant == .dark ? 0.05 : 0.12).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: art.minX - art.width * 0.3,
            y: art.midY + art.height * 0.1,
            width: art.width * 1.0,
            height: art.height * 0.9
        )).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    switch variant {
    case .standard:
        drawGlyph(in: art, barAlpha: [1, 0.85, 0.7], sparkleColor: .white)
    case .dark:
        drawGlyph(in: art, barAlpha: [1, 0.82, 0.64], sparkleColor: color(0x9F8BFF))
    case .tinted:
        drawGlyph(in: art, barAlpha: [1, 1, 1], sparkleColor: .white)
    }
    return rep
}

func write(_ rep: NSBitmapImageRep, named name: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
    print("wrote \(name) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

try write(render(pixels: 1024, variant: .standard, rounded: false), named: "AppIcon-1024.png")
try write(render(pixels: 1024, variant: .dark, rounded: false), named: "AppIcon-1024-dark.png")
try write(render(pixels: 1024, variant: .tinted, rounded: false), named: "AppIcon-1024-tinted.png")

// macOS keeps its own rounded-square artwork with padding.
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try write(render(pixels: pixels, variant: .standard, rounded: true), named: "mac-\(pixels).png")
}

// A lossless 1024² gradient is ~850 KB; palette-compress it when Pillow is around.
let compactScript = """
import os, sys
from PIL import Image
folder = sys.argv[1]
for name in sorted(os.listdir(folder)):
    if not name.endswith('.png'):
        continue
    path = os.path.join(folder, name)
    image = Image.open(path)
    if name.startswith('mac-'):
        alpha = image.convert('RGBA').getchannel('A')
        flat = image.convert('RGB').quantize(
            colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG
        ).convert('RGBA')
        flat.putalpha(alpha)
        flat.save(path, optimize=True)
    else:
        image.convert('RGB').quantize(
            colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG
        ).save(path, optimize=True)
"""

let compact = Process()
// `/usr/bin/env` so this finds whichever python3 actually has Pillow installed.
compact.executableURL = URL(fileURLWithPath: "/usr/bin/env")
compact.arguments = ["python3", "-c", compactScript, outputDirectory.path]
compact.standardOutput = FileHandle.nullDevice
compact.standardError = FileHandle.nullDevice
try? compact.run()
compact.waitUntilExit()
