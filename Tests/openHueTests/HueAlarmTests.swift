import XCTest
@testable import OpenHue

/// Byte vectors are the Hue app's own packets captured by Glyphack (glyphack.com/huec).
final class HueAlarmTests: XCTestCase {
    private func bytes(_ hex: String) -> Data { Data(hex: hex)! }

    func testParseList() {
        let list = HueAlarm.parseList(bytes("00000702 2C002D00 FFFFFFFFFFFFFFFF"))
        XCTAssertEqual(list, HueAlarm.ListResponse(status: 0, ids: [44, 45]))
        XCTAssertNil(HueAlarm.parseList(bytes("0200")))
    }

    func testDecodeRoutineDetailAndReencode() throws {
        let response = bytes("02002C00 35000000 00010060559569 0009010101060109 08017D 2201 D40C138D81B94A4CAA42B99ACEC62D88 00FFFFFFFF 0A4D6F726E696E67207570 01 FFFFFF")
        let detail = try XCTUnwrap(HueAlarm.parseDetail(response))
        XCTAssertEqual(detail.status, 0)
        XCTAssertEqual(detail.id, 44)
        let alarm = try XCTUnwrap(detail.alarm)
        XCTAssertEqual(alarm.name, "Morning up")
        XCTAssertTrue(alarm.isEnabled)
        XCTAssertEqual(alarm.kind, 0)
        XCTAssertEqual(alarm.fireAt, Date(timeIntervalSince1970: 0x69955560))
        XCTAssertEqual(alarm.action, .lightState(bytes("010101060109 08017D")))
        XCTAssertEqual(alarm.uuid.uuidString.lowercased(), "d40c138d-81b9-4a4c-aa42-b99acec62d88")
        XCTAssertEqual(alarm.trailer, .none)
        XCTAssertFalse(alarm.isTimer)
        XCTAssertEqual(alarm.trailing, 1)
        // Effect 0x09 ("sunrise") only exists for routines; it is not one of the 0007 effects.
        if case .lightState(let tlv) = alarm.action {
            XCTAssertEqual(HueTLV.parse(tlv)[0x06], Data([0x09]))
            XCTAssertEqual(HueTLV.parse(tlv)[0x08], Data([0x7D]))
        }

        // Re-encoding reproduces the body byte for byte (payload length 0x35 = 53).
        let body = response.subdata(in: 8..<(8 + 0x35))
        XCTAssertEqual(alarm.encodeBody(), body)
        XCTAssertEqual(HueAlarm.Request.write(alarm, id: alarm.id), Data([0x01, 0x2C, 0x00]) + body)
    }

    func testDecodeTimerDetail() throws {
        let response = bytes("02003800 28000000 000001B9BA9469 010102 1D01 50C1534969604 0B1B33846 6BC3BB4258 032C010000 05 54696D6572 01")
        let alarm = try XCTUnwrap(HueAlarm.parseDetail(response)?.alarm)
        XCTAssertEqual(alarm.name, "Timer")
        XCTAssertFalse(alarm.isEnabled)
        XCTAssertEqual(alarm.kind, 1)
        XCTAssertEqual(alarm.action, .simple(0x02))
        XCTAssertEqual(alarm.trailer, .duration(seconds: 300))
        XCTAssertTrue(alarm.isTimer)
        XCTAssertEqual(alarm.durationSeconds, 300)
        XCTAssertEqual(alarm.encodeBody(), response.subdata(in: 8..<(8 + 0x28)))
    }

    func testCreatePayloadMatchesAppCapture() throws {
        // The app's create packet: slot FFFF, sunrise routine "Wake up", UUID v4 fbd061c2-….
        let capture = bytes("01FFFF00 0100305C9169 00090101010601090801 65 1F01 FBD061C25B6340F6AA71BB49E186F0C9 00FFFFFFFF 0757616B65207570 01")
        let alarm = try XCTUnwrap(HueAlarm.decodeBody(capture.subdata(in: 3..<capture.count), id: HueAlarm.Request.createID))
        XCTAssertEqual(alarm.name, "Wake up")
        XCTAssertEqual(alarm.uuid.uuidString.lowercased(), "fbd061c2-5b63-40f6-aa71-bb49e186f0c9")
        XCTAssertEqual(HueAlarm.Request.write(alarm, id: HueAlarm.Request.createID), capture)
    }

    func testEveryCapturedBlockIsAUUIDv4() {
        let blocks = ["FBD061C25B6340F6AA71BB49E186F0C9", "8597FE881CC14647A19D9F6A8C2C297B", "D40C138D81B94A4CAA42B99ACEC62D88",
                      "50C1534969604 0B1B338466BC3BB4258", "94D18484B75143DAA867A92F02110C8D", "CA492EA08E6A4868834FC01C5B8E8F47",
                      "FA3FD8C1E2304D1E81948BAE5EC24630", "2114F58FE79440F186C4BF6A852973C4", "BE744F8A71FA464D8C10910D7983676C",
                      "AA859C8796F44A08A30D26A7E9E0629B", "2DA26C130FA94BF882E9C3215C27A487", "1478FFD5B1F1431EAB18E212A72034D6"]
        for hex in blocks {
            let b = [UInt8](bytes(hex))
            XCTAssertEqual(b[6] >> 4, 4, "version nibble in \(hex)")
            XCTAssertEqual(b[8] >> 6, 0b10, "variant bits in \(hex)")
        }
    }

    func testMakeAndLightStateAction() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        let action = HueAlarm.lightStateAction(on: true, brightness: 254, color: .ct(mireds: 447), transition: 1800)
        XCTAssertEqual(action, .lightState(bytes("010101 0201FE 0302BF01 05025046")))
        let alarm = HueAlarm.make(name: "Sunrise", fireAt: fire, action: action)
        XCTAssertEqual(alarm.id, HueAlarm.Request.createID)
        XCTAssertTrue(alarm.isEnabled)
        XCTAssertEqual(alarm.trailing, 1)
        let round = HueAlarm.decodeBody(alarm.encodeBody(), id: 7)
        XCTAssertEqual(round?.name, "Sunrise")
        XCTAssertEqual(round?.uuid, alarm.uuid)
        XCTAssertEqual(round?.fireAt, fire)
        XCTAssertEqual(round?.transitionSeconds, 1800)
        XCTAssertEqual(round?.lightState?.brightness, 254)
        XCTAssertEqual(round?.lightState?.color, .ct(mireds: 447))
    }

    func testSettingEnabledAdvancesRoutineAndRestartsTimer() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = now.addingTimeInterval(-3 * 3600)
        let routine = HueAlarm.make(name: "Wake", fireAt: past, action: .simple(1), enabled: false)
        let armed = routine.settingEnabled(true, now: now)
        XCTAssertTrue(armed.isEnabled)
        XCTAssertEqual(armed.trailing, 1)
        XCTAssertEqual(armed.fireAt, past.addingTimeInterval(24 * 3600))
        XCTAssertEqual(routine.settingEnabled(false, now: now).fireAt, past, "disabling leaves the time alone")

        let timer = HueAlarm.make(name: "Timer", fireAt: past, action: .simple(2), trailer: .duration(seconds: 300), kind: 1)
        XCTAssertEqual(timer.settingEnabled(true, now: now).fireAt, now.addingTimeInterval(300))
    }

    func testAcks() {
        XCTAssertEqual(HueAlarm.parseAck(bytes("0100020003 00FFFF")), HueAlarm.Ack(opcode: 1, status: 0, id: 2))
        XCTAssertEqual(HueAlarm.parseAck(bytes("03001E00")), HueAlarm.Ack(opcode: 3, status: 0, id: 30))
        XCTAssertTrue(HueAlarm.isConfirm(bytes("041E00FFFF")))
        XCTAssertNil(HueAlarm.parseAck(bytes("041E00FFFF")))
    }
}
