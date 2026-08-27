import XCTest
@testable import openHue

// MARK: - Fakes

@MainActor
final class FakeContext: SchedulerContext {
    var schedules: [Schedule] = []
    var settings = AppSettings()   // grace: 30 min for on-actions, 6 h for off-actions

    func lights(for schedule: Schedule) -> [HueLight] { [] }
    func resolve(_ target: LightTarget, for light: HueLight, index: Int) -> LightState? { nil }
}

/// One recorded execution through the scheduler's test seam.
struct Execution: Equatable {
    var id: UUID
    var scheduledAt: Date
    var lateness: TimeInterval
}

// MARK: - Tests

@MainActor
final class SchedulerTests: XCTestCase {
    /// Toronto observes DST (EST/EDT): spring forward 2026-03-08 02:00, fall back 2026-11-01 02:00.
    static let toronto: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        c.locale = Locale(identifier: "en_CA")
        return c
    }()

    private var calendar: Calendar { Self.toronto }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func components(_ d: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
    }

    private func weekly(_ days: Set<Weekday>, _ hour: Int, _ minute: Int = 0, action: ScheduleAction = .turnOn(.state(brightness: 254, color: .ct(mireds: 300))), name: String = "Test") -> Schedule {
        Schedule(name: name, trigger: .weekly(days: days, time: HourMinute(hour: hour, minute: minute)), action: action)
    }

    private func makeScheduler(context: FakeContext, now: Date) -> (Scheduler, () -> [Execution]) {
        let scheduler = Scheduler(fadeRunner: FadeRunner())
        scheduler.context = context
        scheduler.calendar = calendar
        scheduler.clock = { now }
        var executions: [Execution] = []
        scheduler.executeAction = { schedule, scheduledAt, lateness in
            executions.append(Execution(id: schedule.id, scheduledAt: scheduledAt, lateness: lateness))
        }
        return (scheduler, { executions })
    }

    // MARK: nextFire — weekly

    func testWeeklySameDayLaterTime() {
        // Wednesday 2026-08-26 10:00 → 18:00 the same day.
        let s = weekly([.wednesday], 18)
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 10), calendar: calendar), date(2026, 8, 26, 18))
    }

    func testWeeklyEarlierTimeRollsToNextWeek() {
        let s = weekly([.wednesday], 7)
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 10), calendar: calendar), date(2026, 9, 2, 7))
    }

    func testWeeklyExactMomentIsStrictlyAfter() {
        let s = weekly([.wednesday], 7)
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 7), calendar: calendar), date(2026, 9, 2, 7))
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 6, 59, 59), calendar: calendar), date(2026, 8, 26, 7))
    }

    func testWeeklyEarlierTimeMovesToNextSelectedDay() {
        let s = weekly([.monday, .wednesday, .friday], 7)
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 10), calendar: calendar), date(2026, 8, 28, 7))
    }

    func testWeeklyMultipleDaysPicksEarliest() {
        let s = weekly([.sunday, .thursday, .saturday], 9)
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 10), calendar: calendar), date(2026, 8, 27, 9))
        let everyday = weekly(Weekday.everyday, 23, 30)
        XCTAssertEqual(everyday.nextFire(after: date(2026, 8, 26, 23, 45), calendar: calendar), date(2026, 8, 27, 23, 30))
    }

    func testWeeklyWeekWrap() {
        let sundayMorning = weekly([.sunday], 8)
        XCTAssertEqual(sundayMorning.nextFire(after: date(2026, 8, 29, 12), calendar: calendar), date(2026, 8, 30, 8), "Saturday → Sunday")
        XCTAssertEqual(sundayMorning.nextFire(after: date(2026, 8, 30, 12), calendar: calendar), date(2026, 9, 6, 8), "Sunday afternoon → next Sunday")
        let mondayMorning = weekly([.monday], 6, 30)
        XCTAssertEqual(mondayMorning.nextFire(after: date(2026, 8, 30, 23, 59), calendar: calendar), date(2026, 8, 31, 6, 30))
    }

    func testWeeklyEmptyDaysIsNil() {
        XCTAssertNil(weekly([], 7).nextFire(after: date(2026, 8, 26, 10), calendar: calendar))
    }

    // MARK: nextFire — once

    func testOnce() {
        let fire = date(2026, 8, 26, 12)
        let s = Schedule(name: "Once", trigger: .once(fire), action: .turnOff)
        XCTAssertEqual(s.nextFire(after: date(2026, 8, 26, 10), calendar: calendar), fire)
        XCTAssertNil(s.nextFire(after: fire, calendar: calendar), "strictly after")
        XCTAssertNil(s.nextFire(after: date(2026, 8, 26, 13), calendar: calendar))
    }

    // MARK: nextFire — DST

    func testSpringForwardKeepsWallClockTime() {
        // Saturday 2026-03-07 23:00 EST → Sunday 07:00 EDT is 7 real hours, not 8.
        let reference = date(2026, 3, 7, 23)
        guard let fire = weekly([.sunday], 7).nextFire(after: reference, calendar: calendar) else { return XCTFail("nil") }
        let c = components(fire)
        XCTAssertEqual(c.month, 3)
        XCTAssertEqual(c.day, 8)
        XCTAssertEqual(c.hour, 7)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(fire.timeIntervalSince(reference), 7 * 3600, accuracy: 1)
        XCTAssertEqual(calendar.timeZone.isDaylightSavingTime(for: fire), true)
        XCTAssertEqual(calendar.timeZone.isDaylightSavingTime(for: reference), false)
    }

    func testSpringForwardNonexistentTimeIsPushedPastTheGap() {
        // 02:30 does not exist on 2026-03-08 in Toronto. `.nextTime` yields the first valid instant
        // after the gap (03:00 EDT) rather than dropping the day or skipping a week.
        let reference = date(2026, 3, 7, 23)
        guard let fire = weekly([.sunday], 2, 30).nextFire(after: reference, calendar: calendar) else { return XCTFail("nil") }
        let c = components(fire)
        XCTAssertEqual(c.month, 3)
        XCTAssertEqual(c.day, 8)
        XCTAssertEqual(c.weekday, Weekday.sunday.rawValue)
        XCTAssertEqual(c.hour, 3)
        XCTAssertEqual(fire.timeIntervalSince(reference), 3 * 3600, accuracy: 1)

        // A time before the gap on the same night is untouched.
        let early = weekly([.sunday], 1, 30).nextFire(after: reference, calendar: calendar)
        XCTAssertEqual(early, date(2026, 3, 8, 1, 30))
        XCTAssertEqual(early?.timeIntervalSince(reference) ?? 0, 2.5 * 3600, accuracy: 1)
    }

    func testFallBackKeepsWallClockTime() {
        // Saturday 2026-10-31 23:00 EDT → Sunday 07:00 EST is 9 real hours.
        let reference = date(2026, 10, 31, 23)
        guard let fire = weekly([.sunday], 7).nextFire(after: reference, calendar: calendar) else { return XCTFail("nil") }
        let c = components(fire)
        XCTAssertEqual(c.month, 11)
        XCTAssertEqual(c.day, 1)
        XCTAssertEqual(c.hour, 7)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(fire.timeIntervalSince(reference), 9 * 3600, accuracy: 1)
        XCTAssertEqual(calendar.timeZone.isDaylightSavingTime(for: fire), false)
    }

    func testFallBackRepeatedTimeUsesFirstOccurrence() {
        // 01:30 happens twice on 2026-11-01; the first (EDT) occurrence wins.
        let reference = date(2026, 10, 31, 23)
        guard let fire = weekly([.sunday], 1, 30).nextFire(after: reference, calendar: calendar) else { return XCTFail("nil") }
        let c = components(fire)
        XCTAssertEqual(c.day, 1)
        XCTAssertEqual(c.hour, 1)
        XCTAssertEqual(c.minute, 30)
        XCTAssertEqual(fire.timeIntervalSince(reference), 2.5 * 3600, accuracy: 1)
        XCTAssertEqual(calendar.timeZone.isDaylightSavingTime(for: fire), true)
    }

    func testWeekSpanningTransitionStaysOnWallClock() {
        // Sunday 2026-03-01 08:00 EST → next Sunday 07:00 EDT: 168 h, minus 1 h (08:00 → 07:00),
        // minus another hour lost to spring-forward = 166 real hours on the same wall-clock time.
        let reference = date(2026, 3, 1, 8)
        guard let fire = weekly([.sunday], 7).nextFire(after: reference, calendar: calendar) else { return XCTFail("nil") }
        XCTAssertEqual(components(fire).hour, 7)
        XCTAssertEqual(components(fire).minute, 0)
        XCTAssertEqual(components(fire).day, 8)
        XCTAssertEqual(fire.timeIntervalSince(reference), 7 * 24 * 3600 - 2 * 3600, accuracy: 1)
    }

    // MARK: tick

    func testArmsOnlyEnabledSchedules() {
        let context = FakeContext()
        var disabled = weekly([.wednesday], 9, name: "Disabled")
        disabled.isEnabled = false
        let enabled = weekly([.wednesday], 9, name: "Enabled")
        context.schedules = [disabled, enabled, weekly([], 9, name: "No days")]
        let (scheduler, _) = makeScheduler(context: context, now: date(2026, 8, 26, 6))
        scheduler.schedulesDidChange()
        XCTAssertNil(scheduler.nextFire(for: disabled))
        XCTAssertEqual(scheduler.nextFire(for: enabled), date(2026, 8, 26, 9))
        XCTAssertEqual(scheduler.nextFires.count, 1)
    }

    func testFiresOnceWhenDueAndNotAgain() async {
        let context = FakeContext()
        let schedule = weekly([.wednesday], 7)
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 26, 6, 59))
        scheduler.schedulesDidChange()
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 8, 26, 7))

        scheduler.tick(now: date(2026, 8, 26, 6, 59, 30))
        await scheduler.awaitInflight()
        XCTAssertTrue(executions().isEmpty, "not due yet")
        XCTAssertNil(context.schedules[0].lastFired)

        scheduler.tick(now: date(2026, 8, 26, 7, 0, 10))
        XCTAssertTrue(scheduler.running.contains(schedule.id), "marked running while the action executes")
        await scheduler.awaitInflight()
        XCTAssertFalse(scheduler.running.contains(schedule.id))
        XCTAssertEqual(executions(), [Execution(id: schedule.id, scheduledAt: date(2026, 8, 26, 7), lateness: 10)])
        XCTAssertEqual(context.schedules[0].lastFired, date(2026, 8, 26, 7))
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 9, 2, 7), "re-armed for next week")
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.hasPrefix("Ran") ?? false, "\(scheduler.lastOutcome)")
        XCTAssertFalse(scheduler.lastOutcome[schedule.id]?.contains("late") ?? true, "10 s is not reported as late")

        scheduler.tick(now: date(2026, 8, 26, 7, 0, 40))
        scheduler.tick(now: date(2026, 8, 26, 12))
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1, "must not fire twice for the same occurrence")
    }

    func testLateOnActionWithinGraceRunsAndReportsLateness() async {
        let context = FakeContext()
        let schedule = weekly([.wednesday], 7)
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 26, 6, 59))
        scheduler.schedulesDidChange()

        scheduler.tick(now: date(2026, 8, 26, 7, 12))
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1)
        XCTAssertEqual(executions().first?.lateness ?? 0, 12 * 60, accuracy: 0.001)
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.contains("12 min late") ?? false, "\(scheduler.lastOutcome)")
    }

    func testSkipsOnActionBeyondGrace() async {
        let context = FakeContext()
        let schedule = weekly([.wednesday], 7)   // on-action: 30 min grace
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 26, 6, 59))
        scheduler.schedulesDidChange()

        scheduler.tick(now: date(2026, 8, 26, 7, 45))
        await scheduler.awaitInflight()
        XCTAssertTrue(executions().isEmpty, "45 min late exceeds the 30 min grace")
        XCTAssertFalse(scheduler.running.contains(schedule.id))
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.hasPrefix("Skipped") ?? false, "\(scheduler.lastOutcome)")
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.contains("45 min") ?? false)
        XCTAssertEqual(context.schedules[0].lastFired, date(2026, 8, 26, 7), "a skipped occurrence is still consumed")
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 9, 2, 7))
    }

    func testOffActionRunsWithinSixHoursButNotAfter() async {
        let context = FakeContext()
        let schedule = weekly([.wednesday], 23, action: .turnOff)   // off-action: 6 h grace
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 26, 22))
        scheduler.schedulesDidChange()

        scheduler.tick(now: date(2026, 8, 27, 3))   // 4 h late
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1)
        XCTAssertEqual(executions().first?.lateness ?? 0, 4 * 3600, accuracy: 0.001)
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.contains("4 h late") ?? false, "\(scheduler.lastOutcome)")

        // Next week's occurrence, noticed 7 h late → skipped.
        scheduler.tick(now: date(2026, 9, 3, 6))
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1)
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.hasPrefix("Skipped") ?? false, "\(scheduler.lastOutcome)")
        XCTAssertEqual(context.schedules[0].lastFired, date(2026, 9, 2, 23))
    }

    func testGoToSleepUsesOffGrace() async {
        let context = FakeContext()
        let schedule = weekly([.wednesday], 22, action: .goToSleep(minutes: 30))
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 26, 21))
        scheduler.schedulesDidChange()
        scheduler.tick(now: date(2026, 8, 26, 23, 30))   // 90 min late: beyond the on-grace, within off-grace
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1)
    }

    func testWalksPastMultipleMissedOccurrencesAndRunsOnlyTheLast() async {
        let context = FakeContext()
        let schedule = weekly(Weekday.everyday, 7, action: .turnOff, name: "Every morning off")
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 24, 6, 59))   // Monday
        scheduler.schedulesDidChange()
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 8, 24, 7))

        // Mac was asleep Monday–Thursday morning; noticed Thursday 08:00.
        scheduler.tick(now: date(2026, 8, 27, 8))
        await scheduler.awaitInflight()
        XCTAssertEqual(executions(), [Execution(id: schedule.id, scheduledAt: date(2026, 8, 27, 7), lateness: 3600)])
        XCTAssertEqual(context.schedules[0].lastFired, date(2026, 8, 27, 7))
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 8, 28, 7))
    }

    func testWalksPastMissedOccurrencesAndSkipsWhenTheLastIsTooLate() async {
        let context = FakeContext()
        let schedule = weekly(Weekday.everyday, 7)   // on-action, 30 min grace
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 24, 6, 59))
        scheduler.schedulesDidChange()

        scheduler.tick(now: date(2026, 8, 27, 12))
        await scheduler.awaitInflight()
        XCTAssertTrue(executions().isEmpty)
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.hasPrefix("Skipped") ?? false)
        XCTAssertEqual(context.schedules[0].lastFired, date(2026, 8, 27, 7))
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 8, 28, 7))
    }

    func testOnceDisablesAfterFiring() async {
        let context = FakeContext()
        let fireAt = date(2026, 8, 26, 7)
        let schedule = Schedule(name: "Once", trigger: .once(fireAt), action: .turnOff)
        context.schedules = [schedule]
        let (scheduler, executions) = makeScheduler(context: context, now: date(2026, 8, 26, 6, 59))
        scheduler.schedulesDidChange()
        XCTAssertEqual(scheduler.nextFire(for: schedule), fireAt)

        scheduler.tick(now: date(2026, 8, 26, 7, 0, 5))
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1)
        XCTAssertEqual(executions().first?.scheduledAt, fireAt)
        XCTAssertFalse(context.schedules[0].isEnabled, "one-shots disable themselves")
        XCTAssertEqual(context.schedules[0].lastFired, fireAt)
        XCTAssertNil(scheduler.nextFire(for: schedule))

        scheduler.tick(now: date(2026, 8, 26, 7, 1))
        scheduler.schedulesDidChange()
        scheduler.tick(now: date(2026, 8, 26, 7, 2))
        await scheduler.awaitInflight()
        XCTAssertEqual(executions().count, 1)
        XCTAssertNil(scheduler.nextFire(for: schedule))
    }

    func testRecomputeCatchesRecentMissWithinGrace() async {
        // App launched 10 min after a 07:00 on-schedule: it still counts (30 min grace).
        let context = FakeContext()
        let schedule = weekly([.wednesday], 7)
        context.schedules = [schedule]
        let now = date(2026, 8, 26, 7, 10)
        let (scheduler, executions) = makeScheduler(context: context, now: now)
        scheduler.schedulesDidChange()
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 8, 26, 7))

        scheduler.tick(now: now)
        await scheduler.awaitInflight()
        XCTAssertEqual(executions(), [Execution(id: schedule.id, scheduledAt: date(2026, 8, 26, 7), lateness: 600)])
    }

    func testRecomputeIgnoresMissBeyondGrace() {
        let context = FakeContext()
        let onSchedule = weekly([.wednesday], 7, name: "on")                       // 30 min grace
        let offSchedule = weekly([.wednesday], 7, action: .turnOff, name: "off")   // 6 h grace
        let once = Schedule(name: "once", trigger: .once(date(2026, 8, 26, 5)), action: .turnOn(.state(brightness: 1, color: .ct(mireds: 300))))
        context.schedules = [onSchedule, offSchedule, once]
        let (scheduler, _) = makeScheduler(context: context, now: date(2026, 8, 26, 8))
        scheduler.schedulesDidChange()
        XCTAssertEqual(scheduler.nextFire(for: onSchedule), date(2026, 9, 2, 7), "1 h late on-action is not retried")
        XCTAssertEqual(scheduler.nextFire(for: offSchedule), date(2026, 8, 26, 7), "1 h late off-action is still due")
        XCTAssertNil(scheduler.nextFire(for: once), "expired one-shot is not armed")
    }

    func testRecomputeRespectsLastFired() {
        let context = FakeContext()
        var schedule = weekly([.wednesday], 7)
        schedule.lastFired = date(2026, 8, 26, 7)
        context.schedules = [schedule]
        let (scheduler, _) = makeScheduler(context: context, now: date(2026, 8, 26, 7, 5))
        scheduler.schedulesDidChange()
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 9, 2, 7), "already fired this morning")
    }

    func testDisablingRemovesFromNextFires() {
        let context = FakeContext()
        let schedule = weekly([.wednesday], 7)
        context.schedules = [schedule]
        let (scheduler, _) = makeScheduler(context: context, now: date(2026, 8, 26, 6))
        scheduler.schedulesDidChange()
        XCTAssertNotNil(scheduler.nextFire(for: schedule))
        context.schedules[0].isEnabled = false
        scheduler.schedulesDidChange()
        XCTAssertNil(scheduler.nextFire(for: schedule))
        XCTAssertTrue(scheduler.nextFires.isEmpty)
    }

    func testRunNowExecutesImmediatelyWithZeroLateness() async {
        let context = FakeContext()
        let schedule = weekly([.monday], 7)   // nowhere near due
        context.schedules = [schedule]
        let now = date(2026, 8, 26, 12)
        let (scheduler, executions) = makeScheduler(context: context, now: now)
        scheduler.schedulesDidChange()

        scheduler.runNow(schedule)
        XCTAssertTrue(scheduler.running.contains(schedule.id))
        await scheduler.awaitInflight()
        XCTAssertFalse(scheduler.running.contains(schedule.id))
        XCTAssertEqual(executions(), [Execution(id: schedule.id, scheduledAt: now, lateness: 0)])
        XCTAssertTrue(scheduler.lastOutcome[schedule.id]?.hasPrefix("Ran") ?? false)
        XCTAssertNil(context.schedules[0].lastFired, "run now does not consume the trigger")
        XCTAssertEqual(scheduler.nextFire(for: schedule), date(2026, 8, 31, 7))
    }

    func testTickWithoutContextIsNoOp() {
        let scheduler = Scheduler(fadeRunner: FadeRunner())
        scheduler.schedulesDidChange()
        scheduler.tick(now: date(2026, 8, 26, 12))
        XCTAssertTrue(scheduler.nextFires.isEmpty)
        XCTAssertTrue(scheduler.running.isEmpty)
    }

    func testLatenessText() {
        XCTAssertEqual(Scheduler.latenessText(45), "45 s")
        XCTAssertEqual(Scheduler.latenessText(12 * 60), "12 min")
        XCTAssertEqual(Scheduler.latenessText(2 * 3600), "2 h")
        XCTAssertEqual(Scheduler.latenessText(2 * 3600 + 15 * 60), "2 h 15 min")
    }
}
