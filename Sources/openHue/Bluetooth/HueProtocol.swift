import Foundation
import CoreBluetooth

// MARK: - GATT identifiers

/// GATT identifiers for Philips Hue Bluetooth bulbs (Signify).
/// Sources: flip-dots/HueBLE, glyphack/huec packet captures, ai212983/blemacd (macOS).
enum HueUUID {
    /// Advertised by every Hue BT bulb (Signify Netherlands B.V., 0xFE0F). The same UUID is also the
    /// device-configuration service on the connected GATT server (name / zigbee address live there).
    static let signify = CBUUID(string: "FE0F")

    static let lightService   = CBUUID(string: "932C32BD-0000-47A2-835A-A8D455B859DD")
    /// Read-only, 15 bytes. Probably a TLV with min/max mireds — unconfirmed, dump in Diagnostics.
    static let capabilities   = CBUUID(string: "932C32BD-0001-47A2-835A-A8D455B859DD")
    /// 1 byte 0/1. R/W/Notify. Reading this is what triggers the macOS pairing dialog.
    static let power          = CBUUID(string: "932C32BD-0002-47A2-835A-A8D455B859DD")
    /// 1 byte 1...254 (never write 0). R/W/Notify.
    static let brightness     = CBUUID(string: "932C32BD-0003-47A2-835A-A8D455B859DD")
    /// uint16 LE mireds 153...500 (454 on some models). Reads 0xFFFF while in xy mode. R/W/Notify.
    static let colorTemp      = CBUUID(string: "932C32BD-0004-47A2-835A-A8D455B859DD")
    /// 2× uint16 LE = round(x·65535), round(y·65535). Reads 0xFFFFFFFF while in CT mode. R/W/Notify.
    static let colorXY        = CBUUID(string: "932C32BD-0005-47A2-835A-A8D455B859DD")
    /// Write-only alert/flash: 0x00 none, 0x01 flash once, 0x02 flash repeatedly.
    static let alert          = CBUUID(string: "932C32BD-0006-47A2-835A-A8D455B859DD")
    /// Combined state TLV (see `HueTLV`). R/W/Notify. The only single read giving the whole state.
    static let combined       = CBUUID(string: "932C32BD-0007-47A2-835A-A8D455B859DD")
    /// Power-on default state: same TLV as `combined` followed by FF FF FF FF. R/W.
    static let powerOnDefault = CBUUID(string: "932C32BD-1005-47A2-835A-A8D455B859DD")

    /// 8 bytes, read-only.
    static let zigbeeAddress  = CBUUID(string: "97FE6561-0001-4F62-86E9-B71EE2DA3D22")
    /// ASCII light name. Read + Write (write is untested by the community — best effort only).
    static let name           = CBUUID(string: "97FE6561-0003-4F62-86E9-B71EE2DA3D22")
    /// Reads 0x0A; "write 01 to enable pairing requests" per blemacd. Unverified.
    static let pairingControl = CBUUID(string: "97FE6561-2001-4F62-86E9-B71EE2DA3D22")

    static let deviceInfoService = CBUUID(string: "180A")
    static let manufacturer   = CBUUID(string: "2A29")
    static let model          = CBUUID(string: "2A24")
    static let firmware       = CBUUID(string: "2A28")

    /// On-bulb alarm request/response channel (Write + Notify). Creation is MAC-protected; only
    /// list / detail / enable / disable / delete are possible.
    static let alarm          = CBUUID(string: "9DA2DDF1-0001-44D0-909C-3F3D3CB34A7B")

    /// Characteristics we subscribe to for push state updates.
    static let notifyCharacteristics: [CBUUID] = [power, brightness, colorTemp, colorXY, combined]

    /// Reads issued once the link is encrypted (after the initial `power` read succeeded).
    static let initialReads: [CBUUID] = [combined, capabilities, powerOnDefault, manufacturer, model, firmware, name]

    static func label(_ uuid: CBUUID) -> String {
        switch uuid {
        case signify: return "Signify config service"
        case lightService: return "Light service"
        case capabilities: return "Capabilities (0001)"
        case power: return "Power (0002)"
        case brightness: return "Brightness (0003)"
        case colorTemp: return "Color temperature (0004)"
        case colorXY: return "Color xy (0005)"
        case alert: return "Alert (0006)"
        case combined: return "Combined state (0007)"
        case powerOnDefault: return "Power-on default (1005)"
        case zigbeeAddress: return "Zigbee address"
        case name: return "Light name"
        case pairingControl: return "Pairing control (2001)"
        case deviceInfoService: return "Device Information"
        case manufacturer: return "Manufacturer"
        case model: return "Model"
        case firmware: return "Firmware"
        case alarm: return "On-bulb alarms"
        default: return uuid.uuidString
        }
    }
}

// MARK: - Effects

enum HueEffect: UInt8, CaseIterable, Codable, Identifiable {
    case none = 0x00
    case candle = 0x01
    case fireplace = 0x02
    case prism = 0x03
    case sparkle = 0x0A
    case opal = 0x0B
    case glisten = 0x0C
    case underwater = 0x0E
    case cosmos = 0x0F
    case sunbeam = 0x10
    case enchant = 0x11

    var id: UInt8 { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .candle: return "Candle"
        case .fireplace: return "Fireplace"
        case .prism: return "Prism"
        case .sparkle: return "Sparkle"
        case .opal: return "Opal"
        case .glisten: return "Glisten"
        case .underwater: return "Underwater"
        case .cosmos: return "Cosmos"
        case .sunbeam: return "Sunbeam"
        case .enchant: return "Enchant"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle.slash"
        case .candle: return "flame"
        case .fireplace: return "fireplace"
        case .prism: return "triangle"
        case .sparkle: return "sparkles"
        case .opal: return "circle.hexagongrid"
        case .glisten: return "sun.max"
        case .underwater: return "water.waves"
        case .cosmos: return "moon.stars"
        case .sunbeam: return "sun.horizon"
        case .enchant: return "wand.and.stars"
        }
    }
}

// MARK: - Light state

/// Which color system the bulb is currently driven by. The bulb is always in exactly one mode;
/// writing `colorTemp` switches it to CT and writing `colorXY` to xy.
enum ColorMode: Codable, Equatable, Hashable {
    case ct(mireds: UInt16)
    case xy(XY)

    var isColor: Bool { if case .xy = self { return true } else { return false } }
    var mireds: UInt16? { if case .ct(let m) = self { return m } else { return nil } }
    var xy: XY? { if case .xy(let p) = self { return p } else { return nil } }
}

struct LightState: Codable, Equatable, Hashable {
    var on: Bool = false
    /// 1...254
    var brightness: UInt8 = 254
    var color: ColorMode = .ct(mireds: 367)
    var effect: HueEffect = .none
    /// 1...254
    var effectSpeed: UInt8 = 128

    static let `default` = LightState()

    var brightnessFraction: Double {
        get { Double(max(1, brightness) - 1) / 253.0 }
        set { brightness = HueWire.clampBrightness(UInt8(clamping: Int((newValue * 253.0).rounded()) + 1)) }
    }
}

// MARK: - TLV codec (combined state 0007 / power-on default 1005)

enum HueTLV {
    enum Tag {
        static let on: UInt8 = 0x01          // len 1
        static let brightness: UInt8 = 0x02  // len 1
        static let mireds: UInt8 = 0x03      // len 2, uint16 LE
        static let xy: UInt8 = 0x04          // len 4, uint16 LE x, uint16 LE y
        static let effect: UInt8 = 0x06      // len 1
        static let speed: UInt8 = 0x08       // len 1
    }

    /// Parses `[tag][len][value...]*`. Stops at a 0xFF tag (the 1005 trailer) or a truncated record.
    static func parse(_ data: Data) -> [UInt8: Data] {
        let bytes = [UInt8](data)
        var out: [UInt8: Data] = [:]
        var i = 0
        while i + 1 < bytes.count {
            let tag = bytes[i]
            if tag == 0xFF { break }
            let len = Int(bytes[i + 1])
            guard i + 2 + len <= bytes.count else { break }
            out[tag] = Data(bytes[(i + 2)..<(i + 2 + len)])
            i += 2 + len
        }
        return out
    }

    static func encode(_ items: [(tag: UInt8, value: Data)]) -> Data {
        var out = Data()
        for item in items {
            out.append(item.tag)
            out.append(UInt8(item.value.count))
            out.append(item.value)
        }
        return out
    }
}

extension LightState {
    /// Applies a combined-state (0007 / 1005) payload on top of `base`. Fields absent from the
    /// payload, and mode sentinels (0xFFFF / 0xFFFFFFFF), leave the corresponding field untouched.
    static func decode(combined data: Data, into base: LightState = .default) -> LightState {
        var s = base
        let f = HueTLV.parse(data)
        if let v = f[HueTLV.Tag.on]?.first { s.on = v != 0 }
        if let v = f[HueTLV.Tag.brightness]?.first { s.brightness = HueWire.clampBrightness(v) }
        if let d = f[HueTLV.Tag.mireds], let m = HueWire.readU16le(d, at: 0), m != 0xFFFF {
            s.color = .ct(mireds: m)
        }
        if let d = f[HueTLV.Tag.xy], let x = HueWire.readU16le(d, at: 0), let y = HueWire.readU16le(d, at: 2),
           !(x == 0xFFFF && y == 0xFFFF) {
            s.color = .xy(XY(x: Double(x) / 65535.0, y: Double(y) / 65535.0))
        }
        if let v = f[HueTLV.Tag.effect]?.first { s.effect = HueEffect(rawValue: v) ?? .none }
        if let v = f[HueTLV.Tag.speed]?.first { s.effectSpeed = max(1, v) }
        return s
    }

    /// Encodes this state as a combined-state TLV (for 0007).
    func encodeCombined(includePower: Bool = true, includeEffect: Bool = true) -> Data {
        var items: [(tag: UInt8, value: Data)] = []
        if includePower { items.append((HueTLV.Tag.on, Data([on ? 1 : 0]))) }
        items.append((HueTLV.Tag.brightness, Data([HueWire.clampBrightness(brightness)])))
        switch color {
        case .ct(let m): items.append((HueTLV.Tag.mireds, HueWire.u16le(m)))
        case .xy(let p): items.append((HueTLV.Tag.xy, HueWire.data(xy: p)))
        }
        if includeEffect {
            items.append((HueTLV.Tag.effect, Data([effect.rawValue])))
            if effect != .none { items.append((HueTLV.Tag.speed, Data([max(1, effectSpeed)]))) }
        }
        return HueTLV.encode(items)
    }

    /// Encodes this state for the power-on default characteristic (1005): TLV + FF FF FF FF trailer.
    func encodePowerOnDefault() -> Data {
        encodeCombined(includePower: true, includeEffect: false) + Data([0xFF, 0xFF, 0xFF, 0xFF])
    }
}

// MARK: - Single-characteristic wire helpers

enum HueWire {
    static func clampBrightness(_ v: UInt8) -> UInt8 { min(max(v, 1), 254) }
    static func clampMireds(_ m: UInt16, max maxMireds: UInt16 = 500) -> UInt16 { min(max(m, 153), maxMireds) }

    static func u16le(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }

    static func readU16le(_ d: Data, at offset: Int) -> UInt16? {
        let b = [UInt8](d)
        guard offset + 1 < b.count else { return nil }
        return UInt16(b[offset]) | (UInt16(b[offset + 1]) << 8)
    }

    static func data(power on: Bool) -> Data { Data([on ? 1 : 0]) }
    static func data(brightness: UInt8) -> Data { Data([clampBrightness(brightness)]) }
    static func data(mireds: UInt16) -> Data { u16le(mireds) }
    static func data(xy: XY) -> Data {
        let x = UInt16(clamping: Int((min(max(xy.x, 0), 1) * 65535.0).rounded()))
        let y = UInt16(clamping: Int((min(max(xy.y, 0), 1) * 65535.0).rounded()))
        return u16le(x) + u16le(y)
    }
    static func data(effect: HueEffect, speed: UInt8) -> Data {
        HueTLV.encode([(HueTLV.Tag.effect, Data([effect.rawValue])), (HueTLV.Tag.speed, Data([max(1, speed)]))])
    }
    static let alertOnce = Data([0x01])
    static let alertStop = Data([0x00])

    static func decodePower(_ d: Data) -> Bool? { d.first.map { $0 != 0 } }
    static func decodeBrightness(_ d: Data) -> UInt8? { d.first.map(clampBrightness) }
    /// nil when the bulb is in xy mode (sentinel 0xFFFF) or the payload is short.
    static func decodeMireds(_ d: Data) -> UInt16? {
        guard let m = readU16le(d, at: 0), m != 0xFFFF else { return nil }
        return m
    }
    /// nil when the bulb is in CT mode (sentinel 0xFFFFFFFF) or the payload is short.
    static func decodeXY(_ d: Data) -> XY? {
        guard let x = readU16le(d, at: 0), let y = readU16le(d, at: 2), !(x == 0xFFFF && y == 0xFFFF) else { return nil }
        return XY(x: Double(x) / 65535.0, y: Double(y) / 65535.0)
    }
    static func decodeString(_ d: Data) -> String? {
        String(data: d, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
    }
}

// MARK: - Hex helpers

extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }

    /// Accepts "01 02 ff", "0102FF", "0x01,0x02".
    init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "0x", with: "")
            .filter { !$0.isWhitespace && $0 != "," && $0 != ":" }
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let b = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self.init(bytes)
    }
}
