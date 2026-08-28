import Foundation

/// An alarm stored **on the bulb** (characteristic `9da2ddf1-0001`), decoded from the detail
/// response and re-encodable for enable/disable/create writes.
///
/// Wire layout of the body shared by the detail response (after the 8-byte header) and the
/// `0x01` write (after `01 idLo idHi`), reconstructed from huec's parser and the Hue-app packet
/// captures on glyphack.com/huec:
///
///     [flagA][enabled][kind][fireAt u32 LE, UTC epoch]
///     [actionType][actionLen][action…]            type 0 = light-state TLV (same tags as 0007), type 1 = simple code
///     [blockLen][01][uuid 16 bytes]                blockLen counts everything from the 01 to the end
///     [trailerType][trailer u32 LE]                00 FFFFFFFF = none, 03 <seconds> = timer duration
///     [nameLen][name UTF-8][trailing]
///
/// The 16 bytes were long assumed to be a MAC — every captured sample has the RFC 4122 version‑4
/// nibble and variant bits, so they are a client-generated UUID v4: the app simply mints a fresh
/// identifier per alarm. `encode(...)` does the same.
struct HueAlarm: Identifiable, Equatable, Hashable {
    enum Action: Equatable, Hashable {
        /// Light-state TLV: 01 on, 02 brightness, 03 mireds, 04 xy, 05 transition (100 ms units), 06 effect, 08 speed.
        case lightState(Data)
        /// One-byte action code (the Hue app's countdown timer uses 0x02).
        case simple(UInt8)
        case unknown(type: UInt8, payload: Data)

        var type: UInt8 {
            switch self {
            case .lightState: return 0
            case .simple: return 1
            case .unknown(let t, _): return t
            }
        }

        var payload: Data {
            switch self {
            case .lightState(let d): return d
            case .simple(let code): return Data([code])
            case .unknown(_, let d): return d
            }
        }
    }

    enum Trailer: Equatable, Hashable {
        case none
        case duration(seconds: UInt32)
        case raw(type: UInt8, value: UInt32)

        var type: UInt8 {
            switch self {
            case .none: return 0
            case .duration: return 3
            case .raw(let t, _): return t
            }
        }

        var value: UInt32 {
            switch self {
            case .none: return 0xFFFF_FFFF
            case .duration(let s): return s
            case .raw(_, let v): return v
            }
        }
    }

    /// Slot id on the bulb. Not stable across edits — refresh the list before acting on one.
    var id: UInt16
    var flagA: UInt8 = 0
    var isEnabled: Bool
    /// 0 on wake-up / go-to-sleep routines, 1 on the app's countdown timers.
    var kind: UInt8 = 0
    /// When the alarm fires (for routines with a fade this is when the fade *starts*).
    var fireAt: Date
    var action: Action
    var uuid: UUID
    var marker: UInt8 = 1
    var trailer: Trailer = .none
    var name: String
    /// Last byte; mirrors `isEnabled` in every capture.
    var trailing: UInt8 = 0

    var isTimer: Bool {
        if case .duration = trailer { return true }
        return false
    }

    var durationSeconds: UInt32? {
        if case .duration(let s) = trailer { return s }
        return nil
    }

    /// Decoded light state for a `lightState` action (nil for other action types or unparsable TLV).
    var lightState: LightState? {
        guard case .lightState(let tlv) = action else { return nil }
        return LightState.decode(combined: tlv, into: LightState(on: true, brightness: 254, color: .ct(mireds: 367)))
    }

    /// Fade/transition (tag 05, 100 ms units) from a light-state action.
    var transitionSeconds: TimeInterval? {
        guard case .lightState(let tlv) = action, let v = HueTLV.parse(tlv)[0x05], v.count == 2 else { return nil }
        let b = [UInt8](v)
        return TimeInterval(UInt16(b[0]) | UInt16(b[1]) << 8) / 10
    }

    // MARK: - Requests

    enum Request {
        static let list = Data([0x00])
        static func detail(_ id: UInt16) -> Data { Data([0x02, UInt8(id & 0xFF), UInt8(id >> 8), 0x00, 0x00]) }
        static func delete(_ id: UInt16) -> Data { Data([0x03, UInt8(id & 0xFF), UInt8(id >> 8)]) }
        /// `0x01` write. `id` = the slot to edit, or `createID` for a new alarm.
        static func write(_ alarm: HueAlarm, id: UInt16) -> Data {
            Data([0x01, UInt8(id & 0xFF), UInt8(id >> 8)]) + alarm.encodeBody()
        }
        static let createID: UInt16 = 0xFFFF
    }

    // MARK: - Responses

    struct ListResponse: Equatable {
        var status: UInt8
        var ids: [UInt16]
    }

    /// `00 status ?? count id…` — nil if this isn't a well-formed list response.
    static func parseList(_ data: Data) -> ListResponse? {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] == 0x00 else { return nil }
        let status = b[1]
        let count = Int(b[3])
        guard b.count >= 4 + count * 2 else { return ListResponse(status: status, ids: []) }
        var ids: [UInt16] = []
        for i in 0..<count {
            ids.append(UInt16(b[4 + i * 2]) | UInt16(b[5 + i * 2]) << 8)
        }
        return ListResponse(status: status, ids: ids)
    }

    struct DetailResponse: Equatable {
        var status: UInt8
        var id: UInt16
        var alarm: HueAlarm?
    }

    /// `02 status idLo idHi len 00 00 00 body…`
    static func parseDetail(_ data: Data) -> DetailResponse? {
        let b = [UInt8](data)
        guard b.count >= 5, b[0] == 0x02 else { return nil }
        let status = b[1]
        let id = UInt16(b[2]) | UInt16(b[3]) << 8
        guard status == 0 else { return DetailResponse(status: status, id: id, alarm: nil) }
        let length = Int(b[4])
        guard b.count >= 8 + length else { return DetailResponse(status: status, id: id, alarm: nil) }
        let body = Data(b[8..<(8 + length)])
        return DetailResponse(status: status, id: id, alarm: HueAlarm.decodeBody(body, id: id))
    }

    /// Write/delete acknowledgement: `01 status idLo idHi verLo verHi` / `03 status idLo idHi`.
    struct Ack: Equatable {
        var opcode: UInt8
        var status: UInt8
        var id: UInt16?
    }

    static func parseAck(_ data: Data) -> Ack? {
        let b = [UInt8](data)
        guard b.count >= 2, b[0] == 0x01 || b[0] == 0x03 else { return nil }
        let id: UInt16? = b.count >= 4 ? UInt16(b[2]) | UInt16(b[3]) << 8 : nil
        return Ack(opcode: b[0], status: b[1], id: id)
    }

    /// `04 …` is the bulb's second "committed" notification after a write or delete.
    static func isConfirm(_ data: Data) -> Bool { data.first == 0x04 }

    // MARK: - Body codec

    static func decodeBody(_ body: Data, id: UInt16) -> HueAlarm? {
        let b = [UInt8](body)
        var i = 0
        func take(_ n: Int) -> [UInt8]? {
            guard i + n <= b.count else { return nil }
            defer { i += n }
            return Array(b[i..<(i + n)])
        }
        guard let head = take(7) else { return nil }
        let flagA = head[0], enabled = head[1], kind = head[2]
        let ts = UInt32(head[3]) | UInt32(head[4]) << 8 | UInt32(head[5]) << 16 | UInt32(head[6]) << 24
        guard let actionHead = take(2), let actionPayload = take(Int(actionHead[1])) else { return nil }
        let action: Action
        switch actionHead[0] {
        case 0: action = .lightState(Data(actionPayload))
        case 1 where actionPayload.count == 1: action = .simple(actionPayload[0])
        default: action = .unknown(type: actionHead[0], payload: Data(actionPayload))
        }
        guard let blockLen = take(1), let marker = take(1), let uuidBytes = take(16) else { return nil }
        _ = blockLen
        guard let trailerHead = take(1), let trailerValue = take(4) else { return nil }
        let value = UInt32(trailerValue[0]) | UInt32(trailerValue[1]) << 8 | UInt32(trailerValue[2]) << 16 | UInt32(trailerValue[3]) << 24
        let trailer: Trailer
        switch (trailerHead[0], value) {
        case (0, 0xFFFF_FFFF): trailer = .none
        case (3, _): trailer = .duration(seconds: value)
        default: trailer = .raw(type: trailerHead[0], value: value)
        }
        guard let nameLen = take(1), let nameBytes = take(Int(nameLen[0])) else { return nil }
        let trailing = take(1)?[0] ?? enabled
        let uuid = uuidBytes.withUnsafeBytes { raw -> UUID in
            var u = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            memcpy(&u, raw.baseAddress!, 16)
            return UUID(uuid: u)
        }
        return HueAlarm(id: id, flagA: flagA, isEnabled: enabled != 0, kind: kind,
                        fireAt: Date(timeIntervalSince1970: TimeInterval(ts)),
                        action: action, uuid: uuid, marker: marker[0], trailer: trailer,
                        name: String(decoding: nameBytes, as: UTF8.self), trailing: trailing)
    }

    func encodeBody() -> Data {
        var out = Data()
        out.append(flagA)
        out.append(isEnabled ? 1 : 0)
        out.append(kind)
        let ts = UInt32(clamping: Int64(fireAt.timeIntervalSince1970.rounded()))
        out.append(contentsOf: [UInt8(ts & 0xFF), UInt8((ts >> 8) & 0xFF), UInt8((ts >> 16) & 0xFF), UInt8(ts >> 24)])
        let payload = action.payload
        out.append(action.type)
        out.append(UInt8(clamping: payload.count))
        out.append(payload)
        let nameBytes = Data(name.utf8.prefix(32))
        let blockLen = 1 + 16 + 5 + 1 + nameBytes.count + 1
        out.append(UInt8(clamping: blockLen))
        out.append(marker)
        let u = uuid.uuid
        out.append(contentsOf: [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15])
        out.append(trailer.type)
        let v = trailer.value
        out.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
        out.append(UInt8(nameBytes.count))
        out.append(nameBytes)
        out.append(trailing)
        return out
    }

    // MARK: - Helpers for edits

    /// Copy with the enabled flags set. Re-enabling a routine whose time has passed moves it to the
    /// next occurrence (24 h steps); re-enabling a countdown timer restarts it from now.
    func settingEnabled(_ enabled: Bool, now: Date = Date()) -> HueAlarm {
        var copy = self
        copy.isEnabled = enabled
        copy.trailing = enabled ? 1 : 0
        guard enabled else { return copy }
        if let seconds = durationSeconds {
            copy.fireAt = now.addingTimeInterval(TimeInterval(seconds))
        } else {
            var next = fireAt
            while next <= now { next = next.addingTimeInterval(24 * 3600) }
            copy.fireAt = next
        }
        return copy
    }

    /// A brand-new alarm ready for `Request.write(_, id: Request.createID)`.
    static func make(name: String, fireAt: Date, action: Action, trailer: Trailer = .none, kind: UInt8 = 0, enabled: Bool = true) -> HueAlarm {
        HueAlarm(id: Request.createID, flagA: 0, isEnabled: enabled, kind: kind, fireAt: fireAt,
                 action: action, uuid: UUID(), marker: 1, trailer: trailer, name: name, trailing: enabled ? 1 : 0)
    }

    /// Light-state action TLV: on/off, brightness, colour, optional transition (tag 05, 100 ms units).
    static func lightStateAction(on: Bool, brightness: UInt8? = nil, color: ColorMode? = nil, transition: TimeInterval? = nil, effect: HueEffect? = nil, speed: UInt8? = nil) -> Action {
        var tlv = Data()
        tlv.append(contentsOf: [0x01, 0x01, on ? 1 : 0])
        if let brightness { tlv.append(contentsOf: [0x02, 0x01, HueWire.clampBrightness(brightness)]) }
        switch color {
        case .ct(let mireds):
            tlv.append(contentsOf: [0x03, 0x02, UInt8(mireds & 0xFF), UInt8(mireds >> 8)])
        case .xy(let xy):
            let x = UInt16(clamping: Int((xy.x * 65535).rounded())), y = UInt16(clamping: Int((xy.y * 65535).rounded()))
            tlv.append(contentsOf: [0x04, 0x04, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8)])
        case nil:
            break
        }
        if let transition {
            let units = UInt16(clamping: Int((transition * 10).rounded()))
            tlv.append(contentsOf: [0x05, 0x02, UInt8(units & 0xFF), UInt8(units >> 8)])
        }
        if let effect, effect != .none {
            tlv.append(contentsOf: [0x06, 0x01, effect.rawValue])
            if let speed { tlv.append(contentsOf: [0x08, 0x01, speed]) }
        }
        return .lightState(tlv)
    }
}
