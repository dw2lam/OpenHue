import XCTest
@testable import OpenHue

final class PowerManagementTests: XCTestCase {
    func testPmsetCommandUsesCanonicalDayOrder() {
        let t = HourMinute(hour: 6, minute: 55)
        XCTAssertEqual(PowerManagement.PmsetWake.command(days: [.monday, .wednesday, .friday], time: t),
                       "/usr/bin/pmset repeat wakeorpoweron MWF 06:55:00")
        XCTAssertEqual(PowerManagement.PmsetWake.command(days: Weekday.everyday, time: t),
                       "/usr/bin/pmset repeat wakeorpoweron MTWRFSU 06:55:00")
        XCTAssertEqual(PowerManagement.PmsetWake.command(days: Weekday.weekdays, time: HourMinute(hour: 23, minute: 5)),
                       "/usr/bin/pmset repeat wakeorpoweron MTWRF 23:05:00")
        XCTAssertEqual(PowerManagement.PmsetWake.command(days: [.sunday, .saturday], time: HourMinute(hour: 0, minute: 0)),
                       "/usr/bin/pmset repeat wakeorpoweron SU 00:00:00")
    }

    func testPmsetApplyRejectsEmptyDays() {
        XCTAssertThrowsError(try PowerManagement.PmsetWake.apply(days: [], time: HourMinute(hour: 7, minute: 0))) { error in
            guard let pmsetError = error as? PowerManagement.PmsetError, case .noDays = pmsetError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testPmsetCurrentScheduleReadsWithoutPrivileges() {
        // `pmset -g sched` needs no admin rights; it may legitimately print nothing.
        let text = PowerManagement.PmsetWake.currentSchedule()
        if let text {
            XCTAssertFalse(text.isEmpty)
            XCTAssertEqual(text, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func testSleepAssertionAcquireAndRelease() {
        guard let assertion = PowerManagement.SleepAssertion(reason: "OpenHue tests") else {
            return XCTFail("could not create a sleep assertion")
        }
        XCTAssertEqual(assertion.reason, "OpenHue tests")
        assertion.release()
        assertion.release()   // second release is a no-op
    }

    func testPmsetErrorDescriptions() {
        XCTAssertEqual(PowerManagement.PmsetError.failed(status: 1, stderr: "  denied \n").errorDescription, "denied")
        XCTAssertEqual(PowerManagement.PmsetError.failed(status: 3, stderr: "").errorDescription, "pmset failed (exit 3).")
    }
}
