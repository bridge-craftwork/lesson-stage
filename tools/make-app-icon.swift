#!/usr/bin/env swift
//
//  Generates the app icon: a pull-down projection screen with a spade on it —
//  a bridge lesson on a classroom projector, which is what the app is for.
//
//  Run from the repo root:
//
//      swift tools/make-app-icon.swift [dark|green|navy] [output.png]
//
//  With no arguments it rewrites the icon in the asset catalog. Committed so
//  the icon has a source that can be re-cut or re-coloured, rather than being
//  a binary nobody can edit.
//
//  iPadOS 17 takes a single 1024×1024 icon and masks the corners itself, so the
//  artwork is square, edge to edge, and **opaque** — an icon with an alpha
//  channel is rejected at submission, which is why this draws into a
//  `noneSkipLast` bitmap rather than going through `NSImage`.

import AppKit
import Foundation

struct Palette {
    let surroundTop: CGColor
    let surroundBottom: CGColor
    let casing: CGColor
    let screen: CGColor
    let screenEdge: CGColor
    let spade: CGColor

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    static func grey(_ w: CGFloat) -> CGColor { rgb(w, w, w) }

    /// The card table. Distinctive on a home screen, and it reads as "cards"
    /// before the spade itself resolves.
    ///
    /// The roller and pull tab are pale, not the dark charcoal a real one would
    /// be: against a dark surround a dark roller vanishes, and the screen stops
    /// reading as a pull-down screen at all.
    static let green = Palette(
        surroundTop: rgb(0.10, 0.34, 0.24), surroundBottom: rgb(0.05, 0.20, 0.14),
        casing: rgb(0.85, 0.86, 0.84), screen: rgb(0.98, 0.97, 0.94),
        screenEdge: grey(0.62), spade: grey(0.08))

    // Alternatives kept for comparison; see `make-app-icon.swift <name>`.
    static let greenSilver = Palette(
        surroundTop: rgb(0.10, 0.34, 0.24), surroundBottom: rgb(0.05, 0.20, 0.14),
        casing: rgb(0.70, 0.72, 0.71), screen: rgb(0.98, 0.97, 0.94),
        screenEdge: grey(0.62), spade: grey(0.08))


    /// The app's own presentation surround.
    static let dark = Palette(
        surroundTop: grey(0.20), surroundBottom: grey(0.10),
        casing: grey(0.34), screen: rgb(0.97, 0.96, 0.93),
        screenEdge: grey(0.80), spade: grey(0.08))

    static let navy = Palette(
        surroundTop: rgb(0.16, 0.22, 0.36), surroundBottom: rgb(0.07, 0.10, 0.19),
        casing: rgb(0.82, 0.84, 0.88), screen: rgb(0.99, 0.99, 0.97),
        screenEdge: grey(0.75), spade: rgb(0.09, 0.11, 0.16))
}

/// A spade, drawn rather than set as a glyph so its weight is ours: broad
/// lobes and a concave flared stem, which still reads as a spade at the 76pt an
/// iPad home screen gives it.
func addSpade(to ctx: CGContext, centre c: CGPoint, height h: CGFloat) {
    let w = h * 0.88
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + w * x, y: c.y + h * y) }
    let path = CGMutablePath()

    path.move(to: p(0, -0.50))                                    // apex
    // Right lobe: out to the shoulder, then curling under to the waist.
    path.addCurve(to: p(0.50, -0.02), control1: p(0.21, -0.24), control2: p(0.50, -0.20))
    path.addCurve(to: p(0.11, 0.22), control1: p(0.50, 0.14), control2: p(0.27, 0.23))
    // Stem: pinched at the waist, flaring along a concave curve to a flat foot.
    path.addCurve(to: p(0.22, 0.48), control1: p(0.085, 0.33), control2: p(0.125, 0.48))
    path.addLine(to: p(-0.22, 0.48))
    path.addCurve(to: p(-0.11, 0.22), control1: p(-0.125, 0.48), control2: p(-0.085, 0.33))
    // Left lobe, mirrored.
    path.addCurve(to: p(-0.50, -0.02), control1: p(-0.27, 0.23), control2: p(-0.50, 0.14))
    path.addCurve(to: p(0, -0.50), control1: p(-0.50, -0.20), control2: p(-0.21, -0.24))
    path.closeSubpath()

    ctx.addPath(path)
}

func renderIcon(_ pal: Palette, to url: URL) throws {
    let side = 1024
    let S = CGFloat(side)
    guard let ctx = CGContext(data: nil, width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("could not make the bitmap") }

    // Lay out top-left down, the way the design reads.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    // Surround: a soft vertical gradient, so the icon has some depth under the
    // corner mask instead of reading as a flat tile.
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [pal.surroundTop, pal.surroundBottom] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: S), options: [])

    let screenW: CGFloat = 736, screenH: CGFloat = 552
    let screenTop: CGFloat = 268
    let screen = CGRect(x: (S - screenW) / 2, y: screenTop, width: screenW, height: screenH)

    // The roller the screen hangs from, a little wider than the screen itself.
    let casingW = screenW + 72, casingH: CGFloat = 58
    ctx.setFillColor(pal.casing)
    ctx.addPath(CGPath(roundedRect: CGRect(x: (S - casingW) / 2, y: screenTop - casingH + 6,
                                           width: casingW, height: casingH),
                       cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.fillPath()

    // The screen, shadowed so it sits in front of the roller.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 26,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.setFillColor(pal.screen)
    ctx.fill(screen)
    ctx.restoreGState()

    // A hairline edge, so the screen still has a boundary on a pale surround.
    ctx.setStrokeColor(pal.screenEdge)
    ctx.setLineWidth(4)
    ctx.stroke(screen.insetBy(dx: 2, dy: 2))

    // The pull tab — the detail that makes it a pull-down screen rather than a
    // plain white rectangle.
    let tabW: CGFloat = 74, tabH: CGFloat = 30
    ctx.setFillColor(pal.casing)
    ctx.addPath(CGPath(roundedRect: CGRect(x: (S - tabW) / 2, y: screen.maxY - 2,
                                           width: tabW, height: tabH),
                       cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.fillPath()

    ctx.setFillColor(pal.spade)
    addSpade(to: ctx, centre: CGPoint(x: S / 2, y: screen.midY), height: 348)
    ctx.fillPath()

    guard let image = ctx.makeImage(),
          let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("could not encode the png") }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { fatalError("could not write \(url.path)") }
}

let args = Array(CommandLine.arguments.dropFirst())
let palette: Palette = switch args.first {
case "dark": .dark
case "navy": .navy
case "green-silver": .greenSilver
default: .green
}
let destination = args.count > 1
    ? URL(fileURLWithPath: args[1])
    : URL(fileURLWithPath: "app/LessonStage/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

try renderIcon(palette, to: destination)
print("wrote \(destination.path)")
