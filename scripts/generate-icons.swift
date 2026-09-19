#!/usr/bin/env swift
//
//  generate-icons.swift
//
//  The design source of truth for every UltraWin icon. Renders, with
//  CoreGraphics only (no external tooling):
//
//    - UltraWin/Assets.xcassets/AppIcon.appiconset/icon_*.png  (all 10 sizes)
//    - UltraWin/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf
//    - docs/assets/app-icon-{light,dark}.png, apple-touch-icon.png,
//      favicon-{16,32}.png, og-image.png
//
//  Usage:
//
//      swift scripts/generate-icons.swift              # regenerate everything
//      swift scripts/generate-icons.swift --previews /tmp/previews
//                                                      # + menu bar glyph previews
//
//  Re-run it whenever the design changes and commit the outputs; nothing in CI
//  runs this script. Output paths are resolved relative to the repo root (the
//  parent of this script's directory), so it can be run from anywhere.
//
import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Apple-style continuous ("squircle") rounded rect, straight from SwiftUI so it
/// matches the Big Sur icon mask exactly. Do not hand-roll this with Béziers —
/// the corners come out notched.
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r).cgPath
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func linearGradient(_ ctx: CGContext, _ path: CGPath, from: CGPoint, to: CGPoint, colors: [CGColor], locations: [CGFloat]? = nil) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func radialGradient(_ ctx: CGContext, _ path: CGPath, center: CGPoint, radius: CGFloat, colors: [CGColor]) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

func resized(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = makeContext(size, size)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

// MARK: - App icon artwork (1024 canvas, drawn in a y-up coordinate space)

/// Colourful abstract wallpaper (soft blobs of saturated colour on black, in
/// the spirit of a pro display's demo wallpaper). Drawn clipped to `path`.
func drawWallpaper(_ ctx: CGContext, in r: CGRect, clip path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.setFillColor(rgb(0x2A0A6B)); ctx.fill(r)
    // Painted back to front with normal blending so every colour stays
    // saturated instead of adding up to white.
    // (x, y) as fractions of the screen rect (y-up), radius as a fraction of its width
    let blobs: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
        (0.05, 0.15, 0.55, 0x4A1DFF), // violet, bottom-left
        (0.98, 0.20, 0.55, 0x00C2A8), // teal, bottom-right
        (0.90, 0.95, 0.50, 0x0A84FF), // blue, top-right
        (0.22, 0.95, 0.46, 0xFF1F6E), // magenta, top-left
        (0.55, 0.05, 0.40, 0xFF5A1F), // orange-red, bottom-centre
        (0.58, 0.62, 0.30, 0xFFB300), // amber, centre-right
        (0.38, 0.48, 0.24, 0xFF3D2E), // red core, centre-left
    ]
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    for (fx, fy, fr, hex) in blobs {
        let c = CGPoint(x: r.minX + fx * r.width, y: r.minY + fy * r.height)
        let g = CGGradient(colorsSpace: cs, colors: [rgb(hex, 1), rgb(hex, 0.8), rgb(hex, 0)] as CFArray, locations: [0, 0.4, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: fr * r.width, options: [])
    }
    ctx.restoreGState()
}

/// Draws the icon artwork: a pro-display-style monitor (silver rim, thin black
/// bezel, silver neck rising from the bottom edge, no foot) showing a colourful
/// wallpaper that is dimmed everywhere except inside the UltraWin frame.
/// `full` = true fills the whole canvas (favicon / touch icon, where the
/// platform applies its own mask and padding); false uses Apple's 1024 template
/// (824 squircle, 100 px margin) and adds a drop shadow. `small` drops the
/// corner handles and fattens everything, for the 16/32/64 px sizes that are
/// rendered natively rather than downsampled.
func drawAppIcon(_ ctx: CGContext, canvas: CGFloat, full: Bool, small: Bool = false) {
    let side: CGFloat = full ? canvas : canvas * 824 / 1024
    let inset = (canvas - side) / 2
    let box = CGRect(x: inset, y: inset, width: side, height: side)
    let u = side / 824 // unit: 1 template px
    let mask = squircle(box, radius: 185.4 * u)

    // 0. Drop shadow (template mode only).
    if !full {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: rgb(0x000000, 0.35))
        ctx.addPath(mask); ctx.setFillColor(rgb(0x14161C)); ctx.fillPath()
        ctx.restoreGState()
    }

    // 1. Background: neutral graphite, lit from the top, so the display's
    //    colours and the silver neck carry the icon.
    linearGradient(ctx, mask, from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.minY),
                   colors: [rgb(0x3A3F4C), rgb(0x1E212A), rgb(0x0C0D12)], locations: [0, 0.5, 1])
    radialGradient(ctx, mask, center: CGPoint(x: box.midX, y: box.maxY), radius: side * 0.8,
                   colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0.0)])

    // Geometry. The display spans almost the whole squircle; the neck comes up
    // from the bottom edge and disappears behind it.
    let bodyW = (small ? 768 : 752) * u, bodyH = (small ? 480 : 466) * u
    let bodyRect = CGRect(x: box.midX - bodyW / 2, y: box.midY - bodyH / 2 + (small ? 24 : 22) * u, width: bodyW, height: bodyH)
    let rim = (small ? 10 : 6) * u, bezel = (small ? 22 : 16) * u
    let bezelRect = bodyRect.insetBy(dx: rim, dy: rim)
    let screenRect = bezelRect.insetBy(dx: bezel, dy: bezel)
    let bodyR = 30 * u

    ctx.saveGState()
    ctx.addPath(mask); ctx.clip()

    // 2. Silver neck.
    let neckW = (small ? 260 : 228) * u
    let neck = CGRect(x: box.midX - neckW / 2, y: box.minY - 10 * u, width: neckW, height: bodyRect.midY - box.minY)
    let neckPath = CGPath(rect: neck, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4 * u), blur: 30 * u, color: rgb(0x000000, 0.55))
    ctx.setFillColor(rgb(0xC9CCD1)); ctx.addPath(neckPath); ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, neckPath, from: CGPoint(x: neck.minX, y: 0), to: CGPoint(x: neck.maxX, y: 0),
                   colors: [rgb(0x8B8F97), rgb(0xD9DBDF), rgb(0xF6F7F8), rgb(0xD2D4D9), rgb(0x858991)],
                   locations: [0, 0.18, 0.5, 0.82, 1])
    // the neck darkens towards the bottom edge of the icon
    linearGradient(ctx, neckPath, from: CGPoint(x: 0, y: bodyRect.minY), to: CGPoint(x: 0, y: box.minY),
                   colors: [rgb(0x000000, 0.0), rgb(0x000000, 0.28)])

    // 3. Display body: silver aluminium rim, with a drop shadow onto the neck.
    let bodyPath = rounded(bodyRect, bodyR)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16 * u), blur: 36 * u, color: rgb(0x000000, 0.65))
    ctx.setFillColor(rgb(0xB9BCC2)); ctx.addPath(bodyPath); ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, bodyPath, from: CGPoint(x: 0, y: bodyRect.maxY), to: CGPoint(x: 0, y: bodyRect.minY),
                   colors: [rgb(0xF4F5F7), rgb(0xB4B7BD), rgb(0x8E9299)], locations: [0, 0.5, 1])
    // black glass bezel
    ctx.setFillColor(rgb(0x050506)); ctx.addPath(rounded(bezelRect, bodyR - rim)); ctx.fillPath()

    // 4. Screen: wallpaper, then a dark overlay everywhere except the region.
    let screenPath = rounded(screenRect, max(bodyR - rim - bezel, 4 * u))
    drawWallpaper(ctx, in: screenRect, clip: screenPath)

    let regW = (small ? 400 : 372) * u, regH = regW * 9 / 16
    let regRect = CGRect(x: screenRect.midX - regW / 2, y: screenRect.midY - regH / 2, width: regW, height: regH)
    let regPath = rounded(regRect, 10 * u)

    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.addRect(screenRect); ctx.addPath(regPath); ctx.clip(using: .evenOdd)
    ctx.setFillColor(rgb(0x05060C, 0.62)); ctx.fill(screenRect)
    ctx.restoreGState()

    // 5. UltraWin frame: white stroke + corner handles, soft glow.
    let frameW = (small ? 18 : 9) * u
    let framePath = rounded(regRect.insetBy(dx: -frameW / 2, dy: -frameW / 2), 14 * u)
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.setShadow(offset: .zero, blur: 26 * u, color: rgb(0xFFFFFF, 0.55))
    ctx.addPath(framePath); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(frameW); ctx.strokePath()
    ctx.restoreGState()
    if !small {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2 * u), blur: 6 * u, color: rgb(0x000000, 0.45))
        ctx.setFillColor(rgb(0xFFFFFF))
        let hr = 15 * u, o = frameW / 2
        for (cx, cy) in [(regRect.minX - o, regRect.minY - o), (regRect.maxX + o, regRect.minY - o),
                         (regRect.minX - o, regRect.maxY + o), (regRect.maxX + o, regRect.maxY + o)] {
            ctx.addEllipse(in: CGRect(x: cx - hr, y: cy - hr, width: 2 * hr, height: 2 * hr))
        }
        ctx.fillPath()
        ctx.restoreGState()
    }

    // glass reflection across the top-left of the screen
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    let gl = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gl, start: CGPoint(x: screenRect.minX, y: screenRect.maxY),
                           end: CGPoint(x: screenRect.minX + screenRect.width * 0.35, y: screenRect.minY), options: [])
    ctx.restoreGState()

    ctx.restoreGState() // mask clip

    // 6. Squircle top-edge highlight + rim stroke for depth.
    ctx.saveGState()
    ctx.addPath(mask); ctx.clip()
    let hl = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.maxY - 120 * u), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(mask)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(3 * u); ctx.strokePath()
    ctx.restoreGState()
}

func renderAppIcon(_ px: Int, full: Bool) -> CGImage {
    let ctx = makeContext(px, px)
    drawAppIcon(ctx, canvas: CGFloat(px), full: full, small: px <= 64)
    return ctx.makeImage()!
}

// MARK: - Menu bar template icon (18x18 pt, PDF, black = template)

/// The glyph is vertically symmetric, so these coordinates are identical in
/// CoreGraphics (y-up) and in the SVG copy on docs/index.html (y-down).
func drawMenuBarIcon(_ ctx: CGContext, color: CGColor = rgb(0x000000)) {
    ctx.setStrokeColor(color); ctx.setFillColor(color)
    let outer = CGRect(x: 0.75, y: 4.5, width: 16.5, height: 9)     // ultrawide screen outline
    ctx.addPath(rounded(outer, 2.5)); ctx.setLineWidth(1.5); ctx.strokePath()
    let region = CGRect(x: 5.5, y: 7, width: 7, height: 4)          // selected region
    ctx.addPath(rounded(region, 1)); ctx.fillPath()
}

/// Quartz stamps a wall-clock `CreationDate`/`ModDate` and a random document
/// `/ID` into every PDF it writes, which would make this file churn in git on
/// every run. Both are overwritten with fixed values of exactly the same byte
/// length, so the xref offsets stay valid and a re-run is a byte-for-byte no-op.
func makeDeterministic(_ data: Data) -> Data {
    var bytes = [UInt8](data)

    func overwrite(at i: Int, with value: String) {
        bytes.replaceSubrange(i..<(i + value.utf8.count), with: Array(value.utf8))
    }
    func matches(_ i: Int, _ s: String) -> Bool {
        let m = Array(s.utf8)
        guard i + m.count <= bytes.count else { return false }
        return Array(bytes[i..<(i + m.count)]) == m
    }
    let digit: (UInt8) -> Bool = { $0 >= 0x30 && $0 <= 0x39 }
    let hex: (UInt8) -> Bool = { digit($0) || ($0 >= 0x61 && $0 <= 0x66) }

    let fixedDate = "20200101000000"          // (D:20200101000000Z00'00')
    let fixedID = String(repeating: "0", count: 32)

    var i = 0
    while i < bytes.count {
        // (D:YYYYMMDDHHMMSS…) — CreationDate and ModDate
        if matches(i, "(D:"), i + 3 + fixedDate.count <= bytes.count,
           bytes[(i + 3)..<(i + 3 + fixedDate.count)].allSatisfy(digit) {
            overwrite(at: i + 3, with: fixedDate)
            i += 3 + fixedDate.count
            continue
        }
        // <32 lowercase hex digits> — the two halves of the trailer /ID
        if bytes[i] == UInt8(ascii: "<"), i + 33 < bytes.count,
           bytes[(i + 1)..<(i + 33)].allSatisfy(hex), bytes[i + 33] == UInt8(ascii: ">") {
            overwrite(at: i + 1, with: fixedID)
            i += 34
            continue
        }
        i += 1
    }
    return Data(bytes)
}

func writeMenuBarPDF(to url: URL) {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawMenuBarIcon(ctx)
    ctx.endPDFPage(); ctx.closePDF()
    try! makeDeterministic(data as Data).write(to: url)
}

/// Menu bar glyph on a fake menu bar background, for PR screenshots only.
func renderMenuBarPreview(scale: Int, onDark: Bool) -> CGImage {
    let px = 18 * scale
    let ctx = makeContext(px, px)
    ctx.setFillColor(onDark ? rgb(0x2B2B2B) : rgb(0xE8E8E8)); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    drawMenuBarIcon(ctx, color: onDark ? rgb(0xFFFFFF) : rgb(0x000000))
    return ctx.makeImage()!
}

// MARK: - OG image 1200x630

func renderOG(icon: CGImage) -> CGImage {
    let w = 1200, h = 630
    let ctx = makeContext(w, h)
    let all = CGRect(x: 0, y: 0, width: w, height: h)
    linearGradient(ctx, CGPath(rect: all, transform: nil), from: CGPoint(x: 0, y: h), to: CGPoint(x: w, y: 0),
                   colors: [rgb(0x2A3350), rgb(0x171C2E)])
    ctx.draw(icon, in: CGRect(x: 120, y: 145, width: 340, height: 340))
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    let title = NSAttributedString(string: "UltraWin", attributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: NSColor.white])
    title.draw(at: NSPoint(x: 540, y: 335))
    let sub = NSAttributedString(string: "Sharing your screen shouldn't be this hard.", attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: NSColor(srgbRed: 0.73, green: 0.76, blue: 0.84, alpha: 1)])
    sub.draw(at: NSPoint(x: 543, y: 270))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

// MARK: - Main

/// Repo root = the parent of this script's directory (scripts/).
let repoRoot: URL = {
    let arg0 = CommandLine.arguments[0]
    let scriptURL = arg0.hasPrefix("/")
        ? URL(fileURLWithPath: arg0)
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(arg0)
    return scriptURL.deletingLastPathComponent().deletingLastPathComponent()
}()

var previewDir: URL?
if let i = CommandLine.arguments.firstIndex(of: "--previews"), i + 1 < CommandLine.arguments.count {
    previewDir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
}

let appIconSet = repoRoot.appendingPathComponent("UltraWin/Assets.xcassets/AppIcon.appiconset")
let menuBarSet = repoRoot.appendingPathComponent("UltraWin/Assets.xcassets/MenuBarIcon.imageset")
let docsAssets = repoRoot.appendingPathComponent("docs/assets")
for dir in [appIconSet, menuBarSet, docsAssets] {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

// App icon set: 16/32/64 px rendered natively (the small variant), the rest
// downsampled from the 1024 master.
let master = renderAppIcon(1024, full: false)
writePNG(master, to: appIconSet.appendingPathComponent("icon_512@2x.png"))
for (name, px) in [("icon_16", 16), ("icon_16@2x", 32), ("icon_32", 32), ("icon_32@2x", 64), ("icon_128", 128),
                   ("icon_128@2x", 256), ("icon_256", 256), ("icon_256@2x", 512), ("icon_512", 512)] {
    let img = px <= 64 ? renderAppIcon(px, full: false) : resized(master, to: px)
    writePNG(img, to: appIconSet.appendingPathComponent("\(name).png"))
}

// Menu bar template icon.
writeMenuBarPDF(to: menuBarSet.appendingPathComponent("MenuBarIcon.pdf"))

// Website + README assets. The light and dark variants are intentionally
// identical: the icon reads on both backgrounds, but both filenames are
// referenced by docs/index.html and the README.
let docsIcon = resized(master, to: 296)
writePNG(docsIcon, to: docsAssets.appendingPathComponent("app-icon-light.png"))
writePNG(docsIcon, to: docsAssets.appendingPathComponent("app-icon-dark.png"))
let full = renderAppIcon(1024, full: true)
writePNG(resized(full, to: 180), to: docsAssets.appendingPathComponent("apple-touch-icon.png"))
writePNG(resized(full, to: 32), to: docsAssets.appendingPathComponent("favicon-32.png"))
writePNG(resized(full, to: 16), to: docsAssets.appendingPathComponent("favicon-16.png"))
writePNG(renderOG(icon: master), to: docsAssets.appendingPathComponent("og-image.png"))

if let previewDir {
    try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    writePNG(renderMenuBarPreview(scale: 8, onDark: false), to: previewDir.appendingPathComponent("menubar-preview-light.png"))
    writePNG(renderMenuBarPreview(scale: 8, onDark: true), to: previewDir.appendingPathComponent("menubar-preview-dark.png"))
    print("previews ->", previewDir.path)
}

print("icons ->", repoRoot.path)
