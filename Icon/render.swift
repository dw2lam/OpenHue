#!/usr/bin/env swift
//
// render.swift — openHue icon compositor.
//
// Takes a full-bleed square artwork (any size, e.g. the 1024x1024 Codex render)
// and composites it onto Apple's macOS app-icon grid:
//
//   * 1024x1024 transparent canvas
//   * 824x824 continuous-corner squircle, centred (100 px margin each side)
//   * corner radius 185 px, Figma/Apple-style corner smoothing
//   * soft drop shadow kept inside the margin
//   * Liquid-Glass-style top sheen + thin rim light along the top edge
//
// Usage:
//   swift Icon/render.swift <artwork.png> <out.png> [--scale 1.10] [--no-shadow]
//
//   --scale S   scale the artwork to S x 824 px before cropping it into the
//               squircle (default 1.10 = slight crop-in so the bulb fills the
//               icon a little more). 1.0 = artwork exactly fits the squircle.
//   --no-shadow omit the drop shadow.
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Arguments

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: swift render.swift <artwork.png> <out.png> [--scale 1.10] [--no-shadow]\n".data(using: .utf8)!)
    exit(2)
}
let srcPath = args[1]
let outPath = args[2]
var artScale: CGFloat = 1.10
var drawShadow = true
var i = 3
while i < args.count {
    switch args[i] {
    case "--scale" where i + 1 < args.count:
        artScale = CGFloat(Double(args[i + 1]) ?? 1.10); i += 2
    case "--no-shadow":
        drawShadow = false; i += 1
    default:
        i += 1
    }
}

// MARK: - Grid constants (Apple macOS icon grid, 1024 pt master)

let canvas: CGFloat = 1024
let inset: CGFloat = 100          // transparent margin on every side
let side: CGFloat = 824           // squircle size
let cornerRadius: CGFloat = 185   // ~22.4 % of side, Apple's ratio
let cornerSmoothing: CGFloat = 0.6 // Figma-style smoothing; 0 = plain rounded rect

// MARK: - Continuous-corner squircle (figma-squircle construction)

func normalize(_ v: CGPoint) -> CGPoint {
    let l = sqrt(v.x * v.x + v.y * v.y)
    return CGPoint(x: v.x / l, y: v.y / l)
}

/// Builds the squircle in CoreGraphics (y-up) coordinates for a square `rect`.
func squirclePath(in rect: CGRect, radius r: CGFloat, smoothing s0: CGFloat, canvasHeight: CGFloat) -> CGPath {
    let deg = CGFloat.pi / 180
    let budget = min(rect.width, rect.height) / 2
    var s = s0
    var p = (1 + s) * r
    if p > budget { s = budget / r - 1; p = budget }

    let arcMeasure = 90 * (1 - s)                                  // degrees of true circular arc
    let arcLen = sin(arcMeasure / 2 * deg) * r * sqrt(2)           // chord projection of the arc
    let angleAlpha = (90 - arcMeasure) / 2
    let p3p4 = r * tan(angleAlpha / 2 * deg)
    let angleBeta = 45 * s
    let c = p3p4 * cos(angleBeta * deg)
    let d = c * tan(angleBeta * deg)
    let b = (p - arcLen - c - d) / 3
    let a = 2 * b

    // circular arc -> single cubic (arc <= 90 degrees)
    let theta = arcMeasure * deg
    let k = 4.0 / 3.0 * tan(theta / 4) * r

    // One corner in a local y-DOWN frame: corner at origin, path arrives along the
    // top edge travelling +x and leaves down the right edge travelling +y.
    let S  = CGPoint(x: -p, y: 0)
    let c1 = CGPoint(x: -p + a, y: 0)
    let c2 = CGPoint(x: -p + a + b, y: 0)
    let E1 = CGPoint(x: -p + a + b + c, y: d)
    let t0 = normalize(CGPoint(x: c, y: d))
    let E2 = CGPoint(x: E1.x + arcLen, y: E1.y + arcLen)
    let t3 = normalize(CGPoint(x: d, y: c))
    let c3 = CGPoint(x: E1.x + k * t0.x, y: E1.y + k * t0.y)
    let c4 = CGPoint(x: E2.x - k * t3.x, y: E2.y - k * t3.y)
    let c5 = CGPoint(x: E2.x + d, y: E2.y + c)
    let c6 = CGPoint(x: E2.x + d, y: E2.y + b + c)
    let E3 = CGPoint(x: E2.x + d, y: E2.y + a + b + c)     // == (0, p)

    // y-down rect
    let x1 = rect.maxX
    let y0 = canvasHeight - rect.maxY
    let cx = rect.midX, cy = canvasHeight - rect.midY

    // place local point at the top-right corner, then rotate k*90 deg clockwise about centre
    func place(_ l: CGPoint, _ kRot: Int) -> CGPoint {
        var px = x1 + l.x, py = y0 + l.y
        for _ in 0..<kRot {
            let dx = px - cx, dy = py - cy
            px = cx - dy; py = cy + dx
        }
        return CGPoint(x: px, y: canvasHeight - py)   // flip to y-up
    }

    let path = CGMutablePath()
    path.move(to: place(E3, 3))                        // start on top edge, after the TL corner
    for kRot in 0..<4 {                                // TR, BR, BL, TL
        path.addLine(to: place(S, kRot))
        path.addCurve(to: place(E1, kRot), control1: place(c1, kRot), control2: place(c2, kRot))
        path.addCurve(to: place(E2, kRot), control1: place(c3, kRot), control2: place(c4, kRot))
        path.addCurve(to: place(E3, kRot), control1: place(c5, kRot), control2: place(c6, kRot))
    }
    path.closeSubpath()
    return path
}

// MARK: - Load artwork

guard let nsimg = NSImage(contentsOfFile: srcPath),
      let art = nsimg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read artwork: \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Canvas

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

let rect = CGRect(x: inset, y: inset, width: side, height: side)
let squircle = squirclePath(in: rect, radius: cornerRadius, smoothing: cornerSmoothing, canvasHeight: canvas)

// 1. Drop shadow (stays inside the 100 px margin: offset 10 + blur 22)
if drawShadow {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.42))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.025, blue: 0.10, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
}

// 2. Artwork, clipped to the squircle, scaled about the centre and cropped
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let s = side * artScale
ctx.draw(art, in: CGRect(x: canvas / 2 - s / 2, y: canvas / 2 - s / 2, width: s, height: s))

// 3. Liquid-Glass top sheen: soft white wash fading out over the top 40 %
let sheen = CGGradient(colorsSpace: cs,
                       colors: [CGColor(gray: 1, alpha: 0.13), CGColor(gray: 1, alpha: 0.0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen,
                       start: CGPoint(x: 0, y: rect.maxY),
                       end: CGPoint(x: 0, y: rect.maxY - side * 0.40),
                       options: [])

// 4. Gentle bottom-edge darkening for depth
let foot = CGGradient(colorsSpace: cs,
                      colors: [CGColor(gray: 0, alpha: 0.18), CGColor(gray: 0, alpha: 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(foot,
                       start: CGPoint(x: 0, y: rect.minY),
                       end: CGPoint(x: 0, y: rect.minY + side * 0.12),
                       options: [])
ctx.restoreGState()

// 5. Rim light: 2 px inner stroke, bright at the top, gone by the bottom
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let rim = squircle.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.addPath(rim)
ctx.clip()
let rimGrad = CGGradient(colorsSpace: cs,
                         colors: [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0.12), CGColor(gray: 1, alpha: 0.0)] as CFArray,
                         locations: [0, 0.45, 1])!
ctx.drawLinearGradient(rimGrad,
                       start: CGPoint(x: 0, y: rect.maxY),
                       end: CGPoint(x: 0, y: rect.minY),
                       options: [])
ctx.restoreGState()

// MARK: - Write PNG

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(out.width)x\(out.height), scale \(artScale), shadow \(drawShadow))")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
