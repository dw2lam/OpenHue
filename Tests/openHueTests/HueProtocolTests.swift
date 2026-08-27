import XCTest
@testable import openHue

final class HueProtocolTests: XCTestCase {
    private func hex(_ s: String) -> Data {
        guard let d = Data(hex: s) else {
            XCTFail("bad hex fixture: \(s)")
            return Data()
        }
        return d
    }

    // MARK: TLV codec

    func testParseEmptyPayload() {
        XCTAssertEqual(HueTLV.parse(Data()).count, 0)
        XCTAssertEqual(HueTLV.parse(Data([0x01])).count, 0, "a lone tag byte has no length")
    }

    func testTLVEncodeParseRoundTrip() {
        let items: [(tag: UInt8, value: Data)] = [
            (tag: HueTLV.Tag.on, value: Data([0x01])),
            (tag: HueTLV.Tag.brightness, value: Data([0xFE])),
            (tag: HueTLV.Tag.mireds, value: Data([0x9C, 0x00])),
            (tag: HueTLV.Tag.xy, value: Data([0xC5, 0xAF, 0x51, 0x4E])),
        ]
        let encoded = HueTLV.encode(items)
        XCTAssertEqual(encoded, hex("01 01 01 02 01 FE 03 02 9C 00 04 04 C5 AF 51 4E"))

        let parsed = HueTLV.parse(encoded)
        XCTAssertEqual(parsed.count, 4)
        for item in items {
            XCTAssertEqual(parsed[item.tag], item.value, "tag \(item.tag)")
        }
    }

    func testParseStopsAtTruncatedRecord() {
        // 03 claims 2 bytes but only 1 follows.
        let parsed = HueTLV.parse(hex("01 01 01 03 02 9C"))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[HueTLV.Tag.on], Data([0x01]))
        XCTAssertNil(parsed[HueTLV.Tag.mireds])
    }

    func testTrailerTerminatesParsing() {
        // The 1005 power-on-default trailer (FF FF FF FF) must stop the parser even when bytes follow.
        let parsed = HueTLV.parse(hex("01 01 01 02 01 80 FF FF FF FF 03 02 9C 00"))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[HueTLV.Tag.brightness], Data([0x80]))
        XCTAssertNil(parsed[HueTLV.Tag.mireds])
    }

    // MARK: Captured payloads

    func testDecodeCapturedCoolWhite() {
        let state = LightState.decode(combined: hex("01 01 01 02 01 FE 03 02 9C 00"))
        XCTAssertTrue(state.on)
        XCTAssertEqual(state.brightness, 254)
        XCTAssertEqual(state.color, .ct(mireds: 156))
    }

    func testDecodeCapturedWarmWhite() {
        let state = LightState.decode(combined: hex("01 01 01 02 01 FE 03 02 5A 01"))
        XCTAssertTrue(state.on)
        XCTAssertEqual(state.brightness, 254)
        XCTAssertEqual(state.color, .ct(mireds: 346))
    }

    func testDecodeCapturedXY() {
        let state = LightState.decode(combined: hex("01 01 01 02 01 FE 04 04 C5 AF 51 4E"))
        XCTAssertTrue(state.on)
        XCTAssertEqual(state.brightness, 254)
        guard let xy = state.color.xy else {
            return XCTFail("expected xy color, got \(state.color)")
        }
        XCTAssertEqual(xy.x, 0.6867, accuracy: 0.001)
        XCTAssertEqual(xy.y, 0.3059, accuracy: 0.001)
    }

    func testDecodeCombinedWithEffect() {
        let state = LightState.decode(combined: hex("01 01 01 02 01 64 03 02 9C 00 06 01 01 08 01 40"))
        XCTAssertEqual(state.brightness, 100)
        XCTAssertEqual(state.effect, .candle)
        XCTAssertEqual(state.effectSpeed, 64)
        XCTAssertEqual(LightState.decode(combined: hex("06 01 7F")).effect, .none, "unknown effect ids fall back to none")
    }

    func testMiredsSentinelLeavesColorUntouched() {
        let base = LightState(on: true, brightness: 100, color: .xy(XY(x: 0.5, y: 0.4)))
        let state = LightState.decode(combined: hex("03 02 FF FF"), into: base)
        XCTAssertEqual(state.color, base.color)
        XCTAssertEqual(state.brightness, 100)
    }

    func testXYSentinelLeavesColorUntouched() {
        let base = LightState(on: true, brightness: 100, color: .ct(mireds: 300))
        let state = LightState.decode(combined: hex("04 04 FF FF FF FF"), into: base)
        XCTAssertEqual(state.color, .ct(mireds: 300))
    }

    func testDecodeMergesOntoBase() {
        let base = LightState(on: true, brightness: 42, color: .ct(mireds: 222), effect: .sparkle, effectSpeed: 9)
        let state = LightState.decode(combined: hex("02 01 C8"), into: base)
        XCTAssertTrue(state.on)
        XCTAssertEqual(state.brightness, 200)
        XCTAssertEqual(state.color, .ct(mireds: 222))
        XCTAssertEqual(state.effect, .sparkle)
        XCTAssertEqual(state.effectSpeed, 9)
    }

    // MARK: Encoding

    func testEncodeCombinedSizes() {
        let ct = LightState(on: true, brightness: 200, color: .ct(mireds: 300))
        XCTAssertEqual(ct.encodeCombined(includeEffect: false).count, 10)
        XCTAssertEqual(ct.encodeCombined(includeEffect: false), hex("01 01 01 02 01 C8 03 02 2C 01"))

        let xy = LightState(on: true, brightness: 200, color: .xy(XY(x: 0.5, y: 0.25)))
        XCTAssertEqual(xy.encodeCombined(includeEffect: false).count, 12)
        XCTAssertEqual(xy.encodeCombined(includePower: false, includeEffect: false).count, 9)

        // Effect tag always present when requested; speed only for a real effect.
        XCTAssertEqual(ct.encodeCombined().count, 13)
        var candle = ct
        candle.effect = .candle
        candle.effectSpeed = 0
        XCTAssertEqual(candle.encodeCombined().count, 16)
        XCTAssertEqual(candle.encodeCombined().suffix(6), hex("06 01 01 08 01 01"), "speed 0 is bumped to 1")
    }

    func testEncodeDecodeRoundTrip() {
        let states: [LightState] = [
            LightState(on: true, brightness: 1, color: .ct(mireds: 500)),
            LightState(on: false, brightness: 254, color: .ct(mireds: 153)),
            LightState(on: true, brightness: 128, color: .xy(XY(x: 0.3127, y: 0.3290))),
            LightState(on: true, brightness: 77, color: .ct(mireds: 367), effect: .fireplace, effectSpeed: 200),
        ]
        for s in states {
            let back = LightState.decode(combined: s.encodeCombined())
            XCTAssertEqual(back.on, s.on)
            XCTAssertEqual(back.brightness, s.brightness)
            XCTAssertEqual(back.effect, s.effect)
            if s.effect != .none { XCTAssertEqual(back.effectSpeed, s.effectSpeed) }
            switch (s.color, back.color) {
            case (.ct(let a), .ct(let b)):
                XCTAssertEqual(a, b)
            case (.xy(let a), .xy(let b)):
                XCTAssertEqual(a.x, b.x, accuracy: 1e-4)
                XCTAssertEqual(a.y, b.y, accuracy: 1e-4)
            default:
                XCTFail("color mode changed: \(s.color) → \(back.color)")
            }
        }
    }

    func testPowerOnDefaultEncoding() {
        let s = LightState(on: true, brightness: 128, color: .ct(mireds: 300))
        let data = s.encodePowerOnDefault()
        XCTAssertEqual(data.count, 14)
        XCTAssertEqual(data.suffix(4), Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(LightState.decode(combined: data), s)
    }

    // MARK: Wire helpers

    func testXYScaling() {
        XCTAssertEqual(HueWire.data(xy: XY(x: 0, y: 0)), hex("00 00 00 00"))
        XCTAssertEqual(HueWire.data(xy: XY(x: 1, y: 1)), hex("FF FF FF FF"))
        XCTAssertEqual(HueWire.data(xy: XY(x: 0.5, y: 0.25)), hex("00 80 00 40"))
        XCTAssertEqual(HueWire.data(xy: XY(x: 2, y: -1)), hex("FF FF 00 00"), "out-of-range coordinates clamp")

        let p = XY(x: 0.6867, y: 0.3059)
        guard let back = HueWire.decodeXY(HueWire.data(xy: p)) else { return XCTFail("xy decode") }
        XCTAssertEqual(back.x, p.x, accuracy: 1e-4)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-4)
    }

    func testU16LittleEndian() {
        XCTAssertEqual(HueWire.u16le(0x015A), Data([0x5A, 0x01]))
        XCTAssertEqual(HueWire.readU16le(Data([0x5A, 0x01]), at: 0), 0x015A)
        XCTAssertNil(HueWire.readU16le(Data([0x5A]), at: 0))
        XCTAssertNil(HueWire.readU16le(Data([0x5A, 0x01, 0x02]), at: 2))
    }

    func testBrightnessClamping() {
        XCTAssertEqual(HueWire.clampBrightness(0), 1)
        XCTAssertEqual(HueWire.clampBrightness(255), 254)
        XCTAssertEqual(HueWire.clampBrightness(128), 128)
        XCTAssertEqual(HueWire.data(brightness: 0), Data([0x01]))
        XCTAssertEqual(HueWire.data(brightness: 255), Data([0xFE]))
        XCTAssertEqual(HueWire.decodeBrightness(Data([0x00])), 1)
        XCTAssertEqual(HueWire.decodeBrightness(Data([0xFF])), 254)
        XCTAssertNil(HueWire.decodeBrightness(Data()))

        // Combined layout: 01 01 <on> 02 01 <brightness> … → the brightness value is byte 5.
        var s = LightState(on: true, brightness: 0, color: .ct(mireds: 300))
        XCTAssertEqual(s.encodeCombined(includeEffect: false)[5], 0x01)
        s.brightness = 255
        XCTAssertEqual(s.encodeCombined(includeEffect: false)[5], 0xFE)
    }

    func testMiredsClamping() {
        XCTAssertEqual(HueWire.clampMireds(100), 153)
        XCTAssertEqual(HueWire.clampMireds(600), 500)
        XCTAssertEqual(HueWire.clampMireds(480, max: 454), 454)
        XCTAssertEqual(HueWire.clampMireds(300), 300)
    }

    func testSingleCharacteristicDecoders() {
        XCTAssertEqual(HueWire.decodePower(Data([0x01])), true)
        XCTAssertEqual(HueWire.decodePower(Data([0x00])), false)
        XCTAssertNil(HueWire.decodePower(Data()))
        XCTAssertEqual(HueWire.decodeMireds(hex("9C 00")), 156)
        XCTAssertNil(HueWire.decodeMireds(hex("FF FF")), "0xFFFF means the bulb is in xy mode")
        XCTAssertNil(HueWire.decodeXY(hex("FF FF FF FF")), "0xFFFFFFFF means the bulb is in CT mode")
        XCTAssertNil(HueWire.decodeXY(hex("00 00")))
        XCTAssertEqual(HueWire.decodeString(Data("Hue lamp\0".utf8)), "Hue lamp")
    }

    func testEffectData() {
        XCTAssertEqual(HueWire.data(effect: .candle, speed: 0), hex("06 01 01 08 01 01"))
        XCTAssertEqual(HueWire.data(effect: .none, speed: 128), hex("06 01 00 08 01 80"))
    }

    func testBrightnessFraction() {
        XCTAssertEqual(LightState(on: true, brightness: 1).brightnessFraction, 0)
        XCTAssertEqual(LightState(on: true, brightness: 254).brightnessFraction, 1, accuracy: 1e-12)
        var s = LightState()
        s.brightnessFraction = 0.5
        XCTAssertEqual(s.brightness, 128)
        s.brightnessFraction = 0
        XCTAssertEqual(s.brightness, 1)
        s.brightnessFraction = 2
        XCTAssertEqual(s.brightness, 254)
    }

    // MARK: Hex helpers

    func testHexRoundTrip() {
        let d = Data([0x01, 0x02, 0xFF])
        XCTAssertEqual(d.hexString, "01 02 FF")
        XCTAssertEqual(Data(hex: "01 02 FF"), d)
        XCTAssertEqual(Data(hex: "0102ff"), d)
        XCTAssertEqual(Data(hex: "0x01,0x02,0xFF"), d)
        XCTAssertEqual(Data(hex: "01:02:FF"), d)
        XCTAssertEqual(Data(hex: d.hexString), d)
        XCTAssertEqual(Data(hex: ""), Data())
        XCTAssertNil(Data(hex: "ABC"), "odd nibble count")
        XCTAssertNil(Data(hex: "ZZ"), "non-hex characters")
    }
}
