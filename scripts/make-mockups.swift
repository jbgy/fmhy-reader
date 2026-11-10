#!/usr/bin/env swift
//
//  make-mockups.swift
//  fmhy
//
//  Renders the pictures in the README and on the Pages site: the macOS overview
//  and an iPhone reading one of FMHY's monthly posts. Section names, icons and
//  link counts come from the bundled snapshot, so a refresh keeps them honest.
//  Usage: swift scripts/make-mockups.swift [output directory]
//

import AppKit

let scale: CGFloat = 2
let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "docs/images",
    isDirectory: true
)

let accent: UInt32 = 0x7C5CFF
let ink: UInt32 = 0x14131A
let muted: UInt32 = 0x5F5D6B
let hairline: UInt32 = 0xE4E2EE
let card: UInt32 = 0xF6F5FB
let tileEdge: UInt32 = 0xE9E7F2
let sidebarFill: UInt32 = 0xF5F4FA

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - Drawing

func canvas(_ width: CGFloat, _ height: CGFloat, _ body: () -> Void) -> NSBitmapImageRep {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: Int(width * scale),
        height: Int(height * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    context.setShouldAntialias(true)

    let graphics = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    body()
    NSGraphicsContext.restoreGraphicsState()

    return NSBitmapImageRep(cgImage: context.makeImage()!)
}

@discardableResult
func text(
    _ string: String,
    _ x: CGFloat,
    _ y: CGFloat,
    width: CGFloat,
    font: NSFont,
    color textColor: NSColor,
    lineHeight: CGFloat? = nil,
    tracking: CGFloat = 0,
    lineBreak: NSLineBreakMode = .byTruncatingTail
) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = lineBreak
    if let lineHeight {
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .paragraphStyle: style,
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let measured = attributed.boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    attributed.draw(
        with: NSRect(x: x, y: y, width: width, height: ceil(measured.height)),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return ceil(measured.height)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ fill: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let border {
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func symbol(_ name: String, in box: NSRect, color symbolColor: NSColor, pointSize: CGFloat, weight: NSFont.Weight = .medium) {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let size = base.size
    let tinted = NSImage(size: size, flipped: false) { bounds in
        symbolColor.setFill()
        bounds.fill()
        base.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
        return true
    }
    tinted.draw(
        in: NSRect(
            x: box.midX - size.width / 2,
            y: box.midY - size.height / 2,
            width: size.width,
            height: size.height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

@discardableResult
func capsule(
    _ label: String,
    _ x: CGFloat,
    _ y: CGFloat,
    font: NSFont = .systemFont(ofSize: 11),
    foreground: NSColor = color(muted),
    background: NSColor = color(0xF2F1F7),
    dot: NSColor? = nil,
    leading: String? = nil,
    trailing: String? = nil,
    height: CGFloat = 26
) -> CGFloat {
    let textSize = (label as NSString).size(withAttributes: [.font: font])
    var content = textSize.width
    if dot != nil { content += 12 }
    if leading != nil { content += 18 }
    if trailing != nil { content += 16 }
    let width = content + 22

    rect(x, y, width, height, background, radius: height / 2)

    var cursor = x + 11
    if let dot {
        dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: cursor, y: y + height / 2 - 3, width: 6, height: 6)).fill()
        cursor += 12
    }
    if let leading {
        symbol(leading, in: NSRect(x: cursor, y: y + 7, width: 12, height: 12), color: foreground, pointSize: 9)
        cursor += 18
    }
    (label as NSString).draw(
        at: NSPoint(x: cursor, y: y + (height - textSize.height) / 2),
        withAttributes: [.font: font, .foregroundColor: foreground]
    )
    cursor += textSize.width
    if let trailing {
        symbol(trailing, in: NSRect(x: cursor + 4, y: y + 8, width: 10, height: 10), color: foreground, pointSize: 8, weight: .semibold)
    }
    return width
}

// MARK: - Snapshot data

enum Catalog {
    struct Page {
        let title: String
        let symbol: String
        let slug: String
    }

    static let pages: [Page] = [
        .init(title: "Beginner's Guide", symbol: "lightbulb", slug: "beginners-guide"),
        .init(title: "Adblocking & Privacy", symbol: "shield.lefthalf.filled", slug: "privacy"),
        .init(title: "AI", symbol: "sparkles", slug: "ai"),
        .init(title: "Audio", symbol: "music.note", slug: "audio"),
        .init(title: "Video", symbol: "play.tv", slug: "video"),
        .init(title: "Video Tools", symbol: "film", slug: "video-tools"),
        .init(title: "Reading", symbol: "books.vertical", slug: "reading"),
        .init(title: "Gaming", symbol: "gamecontroller", slug: "gaming"),
        .init(title: "Gaming Tools", symbol: "wrench.and.screwdriver", slug: "gaming-tools"),
        .init(title: "Downloading", symbol: "arrow.down.circle", slug: "downloading"),
        .init(title: "Torrenting", symbol: "point.3.connected.trianglepath.dotted", slug: "torrenting"),
        .init(title: "Educational", symbol: "graduationcap", slug: "educational"),
        .init(title: "Storage", symbol: "externaldrive", slug: "storage"),
        .init(title: "File Tools", symbol: "folder", slug: "file-tools"),
        .init(title: "Image Tools", symbol: "photo", slug: "image-tools"),
        .init(title: "Text Tools", symbol: "textformat", slug: "text-tools"),
        .init(title: "System Tools", symbol: "gearshape", slug: "system-tools"),
        .init(title: "Developer Tools", symbol: "hammer", slug: "developer-tools"),
        .init(title: "Internet Tools", symbol: "globe", slug: "internet-tools"),
        .init(title: "Mobile", symbol: "iphone", slug: "mobile"),
        .init(title: "Linux & macOS", symbol: "terminal", slug: "linux-macos"),
        .init(title: "Social Media Tools", symbol: "bubble.left.and.bubble.right", slug: "social-media-tools"),
        .init(title: "Misc", symbol: "square.grid.2x2", slug: "misc"),
        .init(title: "Unsafe Sites", symbol: "exclamationmark.triangle", slug: "unsafe"),
        .init(title: "Non-English", symbol: "character.bubble", slug: "non-english"),
        .init(title: "Sandbox", symbol: "testtube.2", slug: "sandbox"),
    ]
}

/// Entry bullets per section, straight from the bundled snapshot.
func seedCounts() -> [String: Int] {
    let folder = URL(fileURLWithPath: "fmhy/Resources/WikiSeed", isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
        return [:]
    }
    var counts: [String: Int] = [:]
    for file in files where file.pathExtension == "md" {
        let body = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        counts[file.deletingPathExtension().lastPathComponent] = body
            .split(separator: "\n")
            .filter { line in
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
            }
            .count
    }
    return counts
}

func grouped(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

let counts = seedCounts()
let totalLinks = counts.values.reduce(0, +)
let sectionCount = Catalog.pages.count

// MARK: - macOS overview

func desktopOverview() -> NSBitmapImageRep {
    let width: CGFloat = 1180
    let height: CGFloat = 800
    let window = NSRect(x: 40, y: 40, width: 1100, height: 720)

    return canvas(width, height) {
        // Desktop backdrop.
        NSGradient(starting: color(0xE9E6F4), ending: color(0xF8F7FC))?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

        // Window.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 44
        shadow.shadowOffset = NSSize(width: 0, height: 18)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        rect(window.minX, window.minY, window.width, window.height, .white, radius: 14)
        NSGraphicsContext.restoreGraphicsState()
        rect(window.minX, window.minY, window.width, window.height, .white, radius: 14)

        // Title bar.
        rect(window.minX, window.minY, window.width, 52, color(0xFBFAFE), radius: 14)
        rect(window.minX, window.minY + 40, window.width, 12, color(0xFBFAFE))
        rect(window.minX, window.minY + 51, window.width, 1, color(hairline))
        let lights = [0xFF5F57, 0xFEBC2E, 0x28C840]
        for (index, tone) in lights.enumerated() {
            color(UInt32(tone)).setFill()
            NSBezierPath(ovalIn: NSRect(x: window.minX + 22 + CGFloat(index) * 20, y: window.minY + 20, width: 12, height: 12)).fill()
        }
        _ = text("FMHY", window.minX + 250 + (window.width - 250) / 2 - 40, window.minY + 19, width: 200, font: .systemFont(ofSize: 12, weight: .semibold), color: color(muted), lineBreak: .byClipping)

        let sidebar = NSRect(x: window.minX, y: window.minY + 52, width: 250, height: window.height - 52)
        rect(sidebar.minX, sidebar.minY, sidebar.width, sidebar.height, color(sidebarFill))
        rect(sidebar.maxX - 1, sidebar.minY, 1, sidebar.height, color(hairline))

        _ = text("LIBRARY", sidebar.minX + 18, 108, width: 120, font: .systemFont(ofSize: 10, weight: .semibold), color: color(muted), tracking: 0.7, lineBreak: .byClipping)
        rect(47, 126, 236, 30, color(accent, 0.14), radius: 8)
        symbol("rectangle.grid.2x2", in: NSRect(x: 56, y: 133, width: 16, height: 16), color: color(accent), pointSize: 12)
        _ = text("Overview", 80, 133, width: 180, font: .systemFont(ofSize: 12.5, weight: .medium), color: color(accent), lineBreak: .byClipping)

        let libraryRows = [("magnifyingglass", "Search Wiki"), ("star.fill", "Bookmarks")]
        for (index, row) in libraryRows.enumerated() {
            let y = 160 + CGFloat(index) * 30
            symbol(row.0, in: NSRect(x: 56, y: y + 7, width: 16, height: 16), color: color(ink, 0.72), pointSize: 11)
            _ = text(row.1, 80, y + 7, width: 180, font: .systemFont(ofSize: 12.5), color: color(ink), lineBreak: .byClipping)
        }

        _ = text("WIKI", sidebar.minX + 18, 240, width: 120, font: .systemFont(ofSize: 10, weight: .semibold), color: color(muted), tracking: 0.7, lineBreak: .byClipping)
        for (index, page) in Catalog.pages.prefix(9).enumerated() {
            let y = 258 + CGFloat(index) * 30
            symbol(page.symbol, in: NSRect(x: 56, y: y + 7, width: 16, height: 16), color: color(accent, 0.9), pointSize: 11)
            _ = text(page.title, 80, y + 7, width: 190, font: .systemFont(ofSize: 12.5), color: color(ink), lineBreak: .byClipping)
        }

        // Sync status.
        color(0x2FBF5B).setFill()
        NSBezierPath(ovalIn: NSRect(x: 58, y: 712, width: 7, height: 7)).fill()
        _ = text("Synced just now", 72, 708, width: 170, font: .systemFont(ofSize: 10.5), color: color(muted), lineBreak: .byClipping)
        _ = text("fmhy.net · online", 58, 724, width: 170, font: .systemFont(ofSize: 10), color: color(muted, 0.75), lineBreak: .byClipping)

        // Detail column.
        let left: CGFloat = 320
        let right: CGFloat = 1106
        symbol("sparkles.tv.fill", in: NSRect(x: left, y: 108, width: 36, height: 36), color: color(accent), pointSize: 27)
        _ = text("FMHY", left + 48, 106, width: 400, font: .systemFont(ofSize: 30, weight: .bold), color: color(ink), lineBreak: .byClipping)
        _ = text("The largest collection of free stuff on the internet.", left + 48, 144, width: 520, font: .systemFont(ofSize: 13), color: color(muted), lineBreak: .byClipping)

        var chipX = left
        chipX += capsule("\(sectionCount) sections", chipX, 182) + 8
        chipX += capsule("\(grouped(totalLinks)) links", chipX, 182) + 8
        chipX += capsule("Posts", chipX, 182, foreground: color(accent), background: color(accent, 0.14), leading: "newspaper") + 8
        _ = capsule("fmhy.net", chipX, 182, dot: color(0x2FBF5B), trailing: "chevron.down")

        _ = text("New links since the last update", left, 228, width: 420, font: .systemFont(ofSize: 11, weight: .semibold), color: color(muted))
        var newX = left
        for (name, added) in [("Educational", 42), ("Gaming", 18), ("Video Tools", 7), ("Privacy", 4)] {
            let label = "\(name)  +\(added)"
            newX += capsule(label, newX, 250, foreground: color(0x5A44D8), background: color(accent, 0.12)) + 8
        }

        // Section grid.
        let columns = 3
        let gap: CGFloat = 12
        let tileWidth = (right - left - CGFloat(columns - 1) * gap) / CGFloat(columns)
        let tileHeight: CGFloat = 92
        for (index, page) in Catalog.pages.prefix(12).enumerated() {
            let column = index % columns
            let row = index / columns
            let x = left + CGFloat(column) * (tileWidth + gap)
            let y = 296 + CGFloat(row) * (tileHeight + gap)

            rect(x, y, tileWidth, tileHeight, color(card), radius: 12, border: color(tileEdge))
            rect(x + 12, y + 12, 28, 28, color(accent, 0.13), radius: 8)
            symbol(page.symbol, in: NSRect(x: x + 18, y: y + 18, width: 16, height: 16), color: color(accent), pointSize: 12)
            _ = text(page.title, x + 12, y + 48, width: tileWidth - 24, font: .systemFont(ofSize: 12.5, weight: .semibold), color: color(ink), lineBreak: .byTruncatingTail)
            let count = counts[page.slug] ?? 0
            _ = text("\(grouped(count)) links", x + 12, y + 68, width: tileWidth - 24, font: .systemFont(ofSize: 10.5), color: color(muted), lineBreak: .byClipping)
        }
    }
}

// MARK: - iPhone post

func phonePost() -> NSBitmapImageRep {
    let width: CGFloat = 620
    let height: CGFloat = 1000
    let device = NSRect(x: 110, y: 60, width: 400, height: 840)
    let screen = NSRect(x: 120, y: 70, width: 380, height: 820)

    let bullets = [
        "Added FMHY \"Featured On\" badges to sites dropdown. TY to @cufiy for these.",
        "Added 3 new instances to FMHY backups (hoffnung, jvbf & vencat). TY to members who set these up.",
        "Split Antivirus / Malware into Antivirus, Sandboxes / VMs and Online Scanners.",
        "Added section for Physical Media / Streaming to Shopping.",
        "Added section for Whiteboards / Handwritten Notes to Text Tools.",
        "Added section for DJ Mixes / Livesets to Audio. TY to @Dan for doing this.",
        "Re-ordered Image Viewers (desktop) based on polls and added platform icons.",
    ]

    return canvas(width, height) {
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: 14)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        rect(device.minX, device.minY, device.width, device.height, color(0x0B0B0F), radius: 60)
        NSGraphicsContext.restoreGraphicsState()

        rect(device.minX, device.minY, device.width, device.height, color(0x0B0B0F), radius: 60)
        rect(screen.minX, screen.minY, screen.width, screen.height, .white, radius: 50)

        // Status bar and island.
        rect(250, 80, 120, 30, color(0x0B0B0F), radius: 15)
        _ = text("9:41", 150, 92, width: 60, font: .systemFont(ofSize: 13, weight: .semibold), color: color(ink), lineBreak: .byClipping)
        for (index, barHeight) in [4, 6, 8, 10].enumerated() {
            rect(404 + CGFloat(index) * 5, 107 - CGFloat(barHeight), 3, CGFloat(barHeight), color(ink, 0.85), radius: 1)
        }
        rect(438, 98, 24, 10, color(ink, 0.85), radius: 3)
        rect(440, 100, 20, 6, .white, radius: 1.5)
        rect(440, 100, 14, 6, color(ink), radius: 1.5)

        // Navigation.
        symbol("chevron.left", in: NSRect(x: 146, y: 138, width: 14, height: 14), color: color(accent), pointSize: 13, weight: .semibold)
        _ = text("Posts", 162, 137, width: 120, font: .systemFont(ofSize: 13, weight: .medium), color: color(accent), lineBreak: .byClipping)

        let titleHeight = text(
            "Monthly Updates [November]",
            146, 158, width: 348,
            font: .systemFont(ofSize: 23, weight: .bold),
            color: color(ink),
            lineHeight: 28,
            lineBreak: .byWordWrapping
        )
        var cursor = 158 + titleHeight + 2
        cursor += text("1 November 2026", 146, cursor, width: 348, font: .systemFont(ofSize: 11), color: color(muted), lineBreak: .byClipping)
        cursor += 18
        cursor += text("Wiki Updates", 146, cursor, width: 348, font: .systemFont(ofSize: 13.5, weight: .semibold), color: color(ink), lineBreak: .byClipping)
        cursor += 10

        for bullet in bullets {
            color(ink, 0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: 147, y: cursor + 6, width: 4, height: 4)).fill()
            let used = text(
                bullet, 160, cursor, width: 334,
                font: .systemFont(ofSize: 12.5),
                color: color(ink, 0.86),
                lineHeight: 17,
                lineBreak: .byWordWrapping
            )
            cursor += used + 8
        }

        rect(250, 872, 120, 5, color(0x0B0B0F, 0.25), radius: 2.5)
    }
}

// MARK: - Output

func write(_ rep: NSBitmapImageRep, named name: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "mockup", code: 1)
    }
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
    print("wrote \(name) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try write(desktopOverview(), named: "overview.png")
try write(phonePost(), named: "posts.png")
