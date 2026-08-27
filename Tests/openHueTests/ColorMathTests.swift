import XCTest
@testable import OpenHue

final class ColorMathTests: XCTestCase {
    private let gamut = ColorMath.gamutC

    /// Distance from `p` to the segment a–b.
    private func distance(_ p: XY, toSegment a: XY, _ b: XY) -> Double {
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2
        t = max(0, min(1, t))
        let cx = a.x + t * abx, cy = a.y + t * aby
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }

    private func distanceToGamutEdge(_ p: XY) -> Double {
        min(distance(p, toSegment: gamut.r, gamut.g),
            distance(p, toSegment: gamut.g, gamut.b),
            distance(p, toSegment: gamut.b, gamut.r))
    }

    /// Inside-or-on-edge test with a tolerance (sign test against each edge).
    private func isInsideGamut(_ p: XY, tolerance: Double = 1e-9) -> Bool {
        func side(_ a: XY, _ b: XY) -> Double { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) }
        let s1 = side(gamut.r, gamut.g), s2 = side(gamut.g, gamut.b), s3 = side(gamut.b, gamut.r)
        let allNonNegative = s1 >= -tolerance && s2 >= -tolerance && s3 >= -tolerance
        let allNonPositive = s1 <= tolerance && s2 <= tolerance && s3 <= tolerance
        return allNonNegative || allNonPositive
    }

    // MARK: Gamut

    func testPointsInsideGamutAreUnchanged() {
        let inside = [
            XY(x: 0.3127, y: 0.3290),
            XY(x: 0.4, y: 0.4),
            XY(x: 0.2, y: 0.3),
            XY(x: (gamut.r.x + gamut.g.x + gamut.b.x) / 3, y: (gamut.r.y + gamut.g.y + gamut.b.y) / 3),
            gamut.r, gamut.g, gamut.b,
        ]
        for p in inside {
            XCTAssertEqual(ColorMath.clampToGamutC(p), p, "\(p) should be inside gamut C")
        }
    }

    func testPointsOutsideGamutAreClampedOntoTriangle() {
        let outside = [
            XY(x: 0.9, y: 0.9),
            XY(x: 0.0, y: 0.0),
            XY(x: 0.8, y: 0.1),
            XY(x: 0.05, y: 0.8),
            XY(x: 0.7006, y: 0.2993),
            XY(x: 0.1, y: 0.4),
        ]
        for p in outside {
            XCTAssertFalse(isInsideGamut(p, tolerance: 0), "\(p) fixture must lie outside")
            let c = ColorMath.clampToGamutC(p)
            XCTAssertNotEqual(c, p)
            XCTAssertTrue(isInsideGamut(c), "\(c) should be inside or on the edge")
            XCTAssertLessThan(distanceToGamutEdge(c), 1e-9, "\(c) should lie on the triangle boundary")
        }
    }

    // MARK: sRGB <-> xy

    func testPureRedMapsNearGamutRed() {
        let xy = ColorMath.xy(fromRGB: RGB(r: 1, g: 0, b: 0))
        XCTAssertGreaterThanOrEqual(xy.x, 0.67)
        XCTAssertLessThanOrEqual(xy.x, 0.70)
        XCTAssertGreaterThanOrEqual(xy.y, 0.30)
        XCTAssertLessThanOrEqual(xy.y, 0.33)
    }

    func testWhiteMapsNearD65() {
        // The Philips wide-gamut matrix puts sRGB white at ≈ (0.3227, 0.3290), a hair right of D65.
        let xy = ColorMath.xy(fromRGB: .white)
        XCTAssertEqual(xy.x, 0.3127, accuracy: 0.02)
        XCTAssertEqual(xy.y, 0.3290, accuracy: 0.01)
        let black = ColorMath.xy(fromRGB: RGB(r: 0, g: 0, b: 0))
        XCTAssertEqual(black.x, 0.3127, accuracy: 1e-9, "black falls back to D65")
    }

    func testRGBFromXYIsNormalized() {
        for xy in [XY(x: 0.3127, y: 0.3290), gamut.r, gamut.g, gamut.b, XY(x: 0.45, y: 0.41)] {
            let rgb = ColorMath.rgb(fromXY: xy)
            XCTAssertEqual(max(rgb.r, rgb.g, rgb.b), 1, accuracy: 1e-9, "\(xy)")
            XCTAssertGreaterThanOrEqual(min(rgb.r, rgb.g, rgb.b), 0)
        }
        let dark = ColorMath.rgb(fromXY: XY(x: 0.3127, y: 0.3290), brightness: 0)
        XCTAssertEqual(dark, RGB(r: 0, g: 0, b: 0))
    }

    func testGammaRoundTrip() {
        for v in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(ColorMath.gammaEncode(ColorMath.linearize(v)), v, accuracy: 1e-9)
        }
    }

    // MARK: Hue / saturation

    func testHueSaturationRoundTrip() {
        // Full-saturation wheel positions: through xy (clamped to gamut C) and back. Gamut clamping
        // desaturates the cyan/yellow corners, so saturation is checked loosely; hue must hold.
        for hue in [0.0, 1.0 / 6, 1.0 / 3, 0.5, 2.0 / 3, 5.0 / 6] {
            let xy = ColorMath.xy(fromHue: hue, saturation: 1)
            let back = ColorMath.hueSaturation(fromXY: xy)
            var diff = abs(back.hue - hue)
            diff = min(diff, 1 - diff)
            XCTAssertLessThan(diff, 0.06, "hue \(hue) came back as \(back.hue)")
            XCTAssertGreaterThan(back.saturation, 0.7, "hue \(hue) saturation \(back.saturation)")
        }
    }

    private func assertRGB(_ actual: RGB, _ expected: RGB, accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.r, expected.r, accuracy: accuracy, "r", file: file, line: line)
        XCTAssertEqual(actual.g, expected.g, accuracy: accuracy, "g", file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, "b", file: file, line: line)
    }

    func testHSVConversions() {
        assertRGB(ColorMath.rgb(fromHSV: 0, s: 1, v: 1), RGB(r: 1, g: 0, b: 0))
        assertRGB(ColorMath.rgb(fromHSV: 1.0 / 3, s: 1, v: 1), RGB(r: 0, g: 1, b: 0))
        assertRGB(ColorMath.rgb(fromHSV: 2.0 / 3, s: 1, v: 1), RGB(r: 0, g: 0, b: 1))
        assertRGB(ColorMath.rgb(fromHSV: 0.5, s: 1, v: 1), RGB(r: 0, g: 1, b: 1))
        assertRGB(ColorMath.rgb(fromHSV: 0.5, s: 0, v: 0.5), RGB(r: 0.5, g: 0.5, b: 0.5))
        assertRGB(ColorMath.rgb(fromHSV: 1.25, s: 1, v: 1), ColorMath.rgb(fromHSV: 0.25, s: 1, v: 1), accuracy: 1e-9)

        let hsv = ColorMath.hsv(fromRGB: RGB(r: 0, g: 0, b: 1))
        XCTAssertEqual(hsv.h, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(hsv.s, 1)
        XCTAssertEqual(hsv.v, 1)
        let grey = ColorMath.hsv(fromRGB: RGB(r: 0.3, g: 0.3, b: 0.3))
        XCTAssertEqual(grey.s, 0)
        XCTAssertEqual(grey.h, 0)
    }

    // MARK: Color temperature

    func testMiredsFromKelvin() {
        XCTAssertEqual(ColorMath.mireds(fromKelvin: 2000), 500)
        let cool = ColorMath.mireds(fromKelvin: 6500)
        XCTAssertTrue((153...154).contains(cool), "6500 K → \(cool)")
        XCTAssertEqual(ColorMath.mireds(fromKelvin: 1000), 500, "clamped to the warm end")
        XCTAssertEqual(ColorMath.mireds(fromKelvin: 10000), 153, "clamped to the cool end")
        XCTAssertEqual(ColorMath.mireds(fromKelvin: 2700), 370)
    }

    func testKelvinMiredsInverse() {
        XCTAssertEqual(ColorMath.kelvin(fromMireds: 500), 2000, accuracy: 1e-9)
        XCTAssertEqual(ColorMath.kelvin(fromMireds: 0), 1_000_000, accuracy: 1e-9, "guards against divide by zero")
        for m: UInt16 in [153, 200, 300, 370, 454, 500] {
            XCTAssertEqual(ColorMath.mireds(fromKelvin: ColorMath.kelvin(fromMireds: m)), m)
        }
    }

    func testApproxMiredsFromD65() {
        let m = ColorMath.approxMireds(fromXY: XY(x: 0.3127, y: 0.3290))
        XCTAssertTrue((153...160).contains(m), "D65 → \(m) mireds")
        let warm = ColorMath.approxMireds(fromXY: ColorMath.xy(fromKelvin: 2700))
        XCTAssertTrue((340...400).contains(warm), "2700 K via xy → \(warm) mireds")
    }

    func testXYFromKelvin() {
        let d65 = ColorMath.xy(fromKelvin: 6500)
        XCTAssertEqual(d65.x, 0.3127, accuracy: 0.01)
        XCTAssertEqual(d65.y, 0.3290, accuracy: 0.01)
        let warm = ColorMath.xy(fromKelvin: 2700)
        XCTAssertEqual(warm.x, 0.46, accuracy: 0.02)
        XCTAssertEqual(warm.y, 0.41, accuracy: 0.02)
        XCTAssertGreaterThan(warm.x, d65.x, "warmer light sits further right on the locus")
    }

    func testRGBFromKelvinWarmVsCool() {
        let warm = ColorMath.rgb(fromKelvin: 2700)
        XCTAssertGreaterThan(warm.r, warm.b)
        XCTAssertEqual(warm.r, 1, accuracy: 1e-9)

        let cool = ColorMath.rgb(fromKelvin: 8000)
        XCTAssertGreaterThanOrEqual(cool.b, cool.r)
        XCTAssertEqual(cool.b, 1, accuracy: 1e-9)

        let neutral = ColorMath.rgb(fromKelvin: 6500)
        XCTAssertGreaterThan(min(neutral.r, neutral.g, neutral.b), 0.9, "6500 K is near white")

        // Clamped input range: the extremes still produce valid colors.
        for k in [100.0, 1000.0, 40000.0, 1_000_000.0] {
            let c = ColorMath.rgb(fromKelvin: k)
            XCTAssertTrue((0...1).contains(c.r) && (0...1).contains(c.g) && (0...1).contains(c.b), "\(k) K")
        }
    }

    // MARK: Display helpers

    func testDisplayRGB() {
        let off = LightState(on: false, brightness: 254, color: .ct(mireds: 367)).displayRGB
        XCTAssertLessThan(max(off.r, off.g, off.b), 0.2)

        let dim = LightState(on: true, brightness: 1, color: .ct(mireds: 367)).displayRGB
        let bright = LightState(on: true, brightness: 254, color: .ct(mireds: 367)).displayRGB
        XCTAssertGreaterThan(bright.r, dim.r)
        XCTAssertEqual(dim.r, 0.35, accuracy: 1e-9, "minimum brightness dims to 35%")
        XCTAssertEqual(bright.r, 1, accuracy: 1e-9)

        let color = ColorMode.xy(XY(x: 0.692, y: 0.308)).displayRGB
        XCTAssertEqual(color.r, 1, accuracy: 1e-9)
        XCTAssertLessThan(color.b, 0.1)
    }
}
