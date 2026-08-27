import Foundation
import SwiftUI

/// CIE 1931 chromaticity.
struct XY: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// sRGB components in 0...1 (gamma-encoded unless stated otherwise).
struct RGB: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    static let white = RGB(r: 1, g: 1, b: 1)
}

/// Pure color conversions for Hue bulbs. Nonisolated so tests and views can call it freely.
enum ColorMath {
    // MARK: Gamut

    /// Gamut C (LCA/LCT/LCL/LCG/LST color bulbs).
    static let gamutC = (r: XY(x: 0.692, y: 0.308), g: XY(x: 0.170, y: 0.700), b: XY(x: 0.153, y: 0.048))

    static let minMireds: UInt16 = 153   // ~6535 K
    static let maxMireds: UInt16 = 500   // 2000 K
    static let minKelvin: Double = 2000
    static let maxKelvin: Double = 6500

    // MARK: sRGB <-> xy

    static func linearize(_ c: Double) -> Double {
        c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
    }

    static func gammaEncode(_ c: Double) -> Double {
        let v = max(0, min(1, c))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// sRGB → CIE xy (Philips wide-gamut D65 matrix), clamped into gamut C.
    static func xy(fromRGB rgb: RGB) -> XY {
        let r = linearize(max(0, min(1, rgb.r)))
        let g = linearize(max(0, min(1, rgb.g)))
        let b = linearize(max(0, min(1, rgb.b)))
        let X = r * 0.664511 + g * 0.154324 + b * 0.162028
        let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let sum = X + Y + Z
        guard sum > 0 else { return XY(x: 0.3127, y: 0.3290) }
        return clampToGamutC(XY(x: X / sum, y: Y / sum))
    }

    /// CIE xy → sRGB, normalized so the brightest channel is 1, then scaled by `brightness` (0...1).
    static func rgb(fromXY xy: XY, brightness: Double = 1) -> RGB {
        let y = max(xy.y, 1e-6)
        let Y = 1.0
        let X = (Y / y) * xy.x
        let Z = (Y / y) * (1 - xy.x - xy.y)
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530
        r = max(0, r); g = max(0, g); b = max(0, b)
        let m = max(r, g, b)
        if m > 0 { r /= m; g /= m; b /= m }
        let k = max(0, min(1, brightness))
        return RGB(r: gammaEncode(r * k), g: gammaEncode(g * k), b: gammaEncode(b * k))
    }

    // MARK: Hue / saturation (color wheel)

    /// HSV(h, s, 1) → xy. `hue` and `saturation` in 0...1.
    static func xy(fromHue hue: Double, saturation: Double) -> XY {
        xy(fromRGB: rgb(fromHSV: hue, s: saturation, v: 1))
    }

    /// xy → (hue, saturation) in 0...1, for placing the wheel thumb.
    static func hueSaturation(fromXY xy: XY) -> (hue: Double, saturation: Double) {
        let hsv = hsv(fromRGB: rgb(fromXY: xy))
        return (hsv.h, hsv.s)
    }

    static func rgb(fromHSV h: Double, s: Double, v: Double) -> RGB {
        let hh = (h - floor(h)) * 6
        let i = Int(hh)
        let f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return RGB(r: v, g: t, b: p)
        case 1: return RGB(r: q, g: v, b: p)
        case 2: return RGB(r: p, g: v, b: t)
        case 3: return RGB(r: p, g: q, b: v)
        case 4: return RGB(r: t, g: p, b: v)
        default: return RGB(r: v, g: p, b: q)
        }
    }

    static func hsv(fromRGB c: RGB) -> (h: Double, s: Double, v: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        var h = 0.0
        if d > 1e-9 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = mx > 0 ? d / mx : 0
        return (h, s, mx)
    }

    // MARK: Gamut clamp

    static func clampToGamutC(_ p: XY) -> XY {
        let (r, g, b) = gamutC
        if isInside(p, r, g, b) { return p }
        let candidates = [closestPoint(on: r, g, to: p), closestPoint(on: g, b, to: p), closestPoint(on: b, r, to: p)]
        return candidates.min { dist2($0, p) < dist2($1, p) } ?? p
    }

    private static func isInside(_ p: XY, _ a: XY, _ b: XY, _ c: XY) -> Bool {
        func sign(_ p1: XY, _ p2: XY, _ p3: XY) -> Double {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }

    private static func closestPoint(on a: XY, _ b: XY, to p: XY) -> XY {
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        guard len2 > 0 else { return a }
        var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2
        t = max(0, min(1, t))
        return XY(x: a.x + t * abx, y: a.y + t * aby)
    }

    private static func dist2(_ a: XY, _ b: XY) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    // MARK: Color temperature

    static func mireds(fromKelvin k: Double) -> UInt16 {
        let m = (1_000_000 / max(k, 1)).rounded()
        return UInt16(clamping: Int(min(max(m, Double(minMireds)), Double(maxMireds))))
    }

    static func kelvin(fromMireds m: UInt16) -> Double {
        1_000_000 / Double(max(m, 1))
    }

    /// Approximate sRGB for a black-body temperature (Tanner Helland's fit). Drives the slider gradient.
    static func rgb(fromKelvin kelvin: Double) -> RGB {
        let t = max(1000, min(40000, kelvin)) / 100
        var r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
            b = t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
            b = 255
        }
        func c(_ v: Double) -> Double { max(0, min(255, v)) / 255 }
        return RGB(r: c(r), g: c(g), b: c(b))
    }

    /// Correlated color temperature of an xy point (McCamy), as clamped mireds. Used to apply color
    /// scenes to white-only bulbs.
    static func approxMireds(fromXY xy: XY) -> UInt16 {
        let n = (xy.x - 0.3320) / (0.1858 - xy.y)
        let cct = 449 * pow(n, 3) + 3525 * pow(n, 2) + 6823.3 * n + 5520.33
        guard cct.isFinite else { return 367 }
        return mireds(fromKelvin: cct)
    }

    /// Approximate xy of a black-body temperature (Kim et al. cubic spline). Used for warm/cool
    /// interpolation in xy space when needed.
    static func xy(fromKelvin kelvin: Double) -> XY {
        let T = max(1667, min(25000, kelvin))
        let x: Double
        if T <= 4000 {
            x = -0.2661239e9 / pow(T, 3) - 0.2343589e6 / pow(T, 2) + 0.8776956e3 / T + 0.179910
        } else {
            x = -3.0258469e9 / pow(T, 3) + 2.1070379e6 / pow(T, 2) + 0.2226347e3 / T + 0.240390
        }
        let y: Double
        if T <= 2222 {
            y = -1.1063814 * pow(x, 3) - 1.34811020 * pow(x, 2) + 2.18555832 * x - 0.20219683
        } else if T <= 4000 {
            y = -0.9549476 * pow(x, 3) - 1.37418593 * pow(x, 2) + 2.09137015 * x - 0.16748867
        } else {
            y = 3.0817580 * pow(x, 3) - 5.87338670 * pow(x, 2) + 3.75112997 * x - 0.37001483
        }
        return XY(x: x, y: y)
    }
}

// MARK: - Convenience

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

extension ColorMode {
    /// Full-brightness representative color for swatches.
    var displayRGB: RGB {
        switch self {
        case .ct(let m): return ColorMath.rgb(fromKelvin: ColorMath.kelvin(fromMireds: m))
        case .xy(let p): return ColorMath.rgb(fromXY: p)
        }
    }
}

extension LightState {
    /// Swatch color: full-chroma color dimmed toward 35% at minimum brightness; dark when off.
    var displayRGB: RGB {
        let base = color.displayRGB
        let k = on ? 0.35 + 0.65 * brightnessFraction : 0.12
        return RGB(r: base.r * k, g: base.g * k, b: base.b * k)
    }
    var displayColor: Color { Color(displayRGB) }
}
