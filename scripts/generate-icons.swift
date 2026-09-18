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

/// Draws the icon artwork. `full` = true fills the whole canvas (favicon /
/// touch icon, where the platform applies its own mask and padding); false uses
/// Apple's 1024 template (824 squircle, 100 px margin) and adds a drop shadow.
/// `small` drops the stand and the corner handles and fattens everything, for
/// the 16/32/64 px sizes that are rendered natively rather than downsampled.
func drawAppIcon(_ ctx: CGContext, canvas: CGFloat, full: Bool, small: Bool = false) {
    let side: CGFloat = full ? canvas : canvas * 824 / 1024
    let inset = (canvas - side) / 2
    let box = CGRect(x: inset, y: inset, width: side, height: side)
    let u = side / 824 // unit: 1 template px
    let mask = squircle(box, radius: 185.4 * u)

    // 0. Drop shadow (only in template mode; the full-bleed variant is masked
    //    by the platform, which would clip the shadow anyway).
    if !full {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: rgb(0x000000, 0.35))
        ctx.addPath(mask); ctx.setFillColor(rgb(0x141B2E)); ctx.fillPath()
        ctx.restoreGState()
    }

    // 1. Background: navy → deep indigo, lit from the top.
    linearGradient(ctx, mask, from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.minY),
                   colors: [rgb(0x2C3A5E), rgb(0x1B2440), rgb(0x0F1526)], locations: [0, 0.55, 1])
    // soft top-left radial sheen
    radialGradient(ctx, mask, center: CGPoint(x: box.minX + side * 0.3, y: box.maxY - side * 0.05), radius: side * 0.9,
                   colors: [rgb(0x6C8CFF, 0.22), rgb(0x6C8CFF, 0.0)])

    // 2. Ultrawide display: bezel + screen, centered slightly above middle.
    let screenW = (small ? 700 : 660) * u, screenH = (small ? 330 : 296) * u
    let screenRect = CGRect(x: box.midX - screenW / 2, y: box.midY - screenH / 2 + (small ? 0 : 26) * u, width: screenW, height: screenH)
    let bezelRect = screenRect.insetBy(dx: -24 * u, dy: -24 * u)

    // stand (behind the bezel) — dropped at small sizes where it turns to mush
    if !small {
        let neck = CGRect(x: box.midX - 34 * u, y: bezelRect.minY - 46 * u, width: 68 * u, height: 50 * u)
        let base = CGRect(x: box.midX - 140 * u, y: bezelRect.minY - 62 * u, width: 280 * u, height: 22 * u)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * u), blur: 16 * u, color: rgb(0x000000, 0.45))
        ctx.setFillColor(rgb(0x0B1020))
        ctx.addPath(rounded(base, 11 * u)); ctx.fillPath()
        ctx.addRect(neck); ctx.fillPath()
        ctx.restoreGState()
        linearGradient(ctx, rounded(base, 11 * u), from: CGPoint(x: 0, y: base.maxY), to: CGPoint(x: 0, y: base.minY),
                       colors: [rgb(0x4A587C), rgb(0x232C46)])
        linearGradient(ctx, CGPath(rect: neck, transform: nil), from: CGPoint(x: neck.minX, y: 0), to: CGPoint(x: neck.maxX, y: 0),
                       colors: [rgb(0x1C2338), rgb(0x2E3853), rgb(0x1C2338)])
    }

    // bezel with drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * u), blur: 36 * u, color: rgb(0x000000, 0.55))
    ctx.setFillColor(rgb(0x0B1020)); ctx.addPath(rounded(bezelRect, 40 * u)); ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, rounded(bezelRect, 40 * u), from: CGPoint(x: 0, y: bezelRect.maxY), to: CGPoint(x: 0, y: bezelRect.minY),
                   colors: [rgb(0x1E2640), rgb(0x0B1020)])
    // bezel rim highlight
    ctx.saveGState()
    ctx.addPath(rounded(bezelRect.insetBy(dx: 1.5 * u, dy: 1.5 * u), 39 * u))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(3 * u); ctx.strokePath()
    ctx.restoreGState()

    // screen surface: the "dimmed" desktop outside the shared region
    let screenPath = rounded(screenRect, 22 * u)
    linearGradient(ctx, screenPath, from: CGPoint(x: screenRect.minX, y: screenRect.maxY), to: CGPoint(x: screenRect.maxX, y: screenRect.minY),
                   colors: [rgb(0x2A3554), rgb(0x1A2340)])

    // 3. Selected region: bright 16:9 rectangle, white frame, corner handles.
    let regW = (small ? 360 : 320) * u, regH = regW * 9 / 16
    let regRect = CGRect(x: screenRect.midX - regW / 2, y: screenRect.midY - regH / 2, width: regW, height: regH)
    let regPath = rounded(regRect, 14 * u)
    // glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 44 * u, color: rgb(0x3D9BFF, 0.75))
    ctx.setFillColor(rgb(0x0A84FF)); ctx.addPath(regPath); ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, regPath, from: CGPoint(x: regRect.minX, y: regRect.maxY), to: CGPoint(x: regRect.maxX, y: regRect.minY),
                   colors: [rgb(0x7FD1FF), rgb(0x2E9BFF), rgb(0x0A6CFF)], locations: [0, 0.5, 1])
    // frame
    ctx.saveGState()
    let frameW = (small ? 16 : 9) * u
    ctx.addPath(rounded(regRect.insetBy(dx: -frameW / 2, dy: -frameW / 2), 18 * u))
    ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(frameW); ctx.strokePath()
    ctx.restoreGState()
    // corner handles (large sizes only)
    if !small {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2 * u), blur: 6 * u, color: rgb(0x000000, 0.35))
        ctx.setFillColor(rgb(0xFFFFFF))
        let hr = 15 * u
        for (cx, cy) in [(regRect.minX - 4 * u, regRect.minY - 4 * u), (regRect.maxX + 4 * u, regRect.minY - 4 * u),
                         (regRect.minX - 4 * u, regRect.maxY + 4 * u), (regRect.maxX + 4 * u, regRect.maxY + 4 * u)] {
            ctx.addEllipse(in: CGRect(x: cx - hr, y: cy - hr, width: 2 * hr, height: 2 * hr))
        }
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 4. Squircle top-edge highlight + rim stroke for depth.
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
