import XCTest
@testable import OpenHue

@MainActor
final class SleepTimerRunnerTests: XCTestCase {
    private func makeLight(name: String = "Lamp", on: Bool, brightness: UInt8 = 200, color: ColorMode = .ct(mireds: 300), maxMireds: UInt16 = 500) -> HueLight {
        var info = KnownLight(id: UUID(), name: name)
        info.maxMireds = maxMireds
        info.lastState = LightState(on: on, brightness: brightness, color: color)
        return HueLight(info: info)
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A `SleepTimerRunner` and its `FadeRunner` sharing one pinned clock, resolving targets against
    /// `lights` the way the app's `AppModel` would.
    private func makeRunner(now: Date, lights: [HueLight]) -> (SleepTimerRunner, FadeRunner, (Date) -> Void) {
        var current = now
        let fadeRunner = FadeRunner()
        fadeRunner.clock = { current }
        let runner = SleepTimerRunner(fadeRunner: fadeRunner)
        runner.clock = { current }
        runner.keepsMacAwake = false   // avoid real IOKit sleep assertions in tests
        runner.resolveLights = { target in
            switch target {
            case .allLights: return lights
            case .light(let id): return lights.filter { $0.id == id }
            }
        }
        return (runner, fadeRunner, { current = $0 })
    }

    // MARK: - start

    func testStartCreatesOneTimerPerTargetWithClippedFadeAndFiresOnChange() {
        let lightA = makeLight(name: "A", on: true)
        let lightB = makeLight(name: "B", on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [lightA, lightB])
        var onChangeCount = 0
        runner.onChange = { onChangeCount += 1 }

        let allTimer = runner.start(.allLights, duration: 60, fadeSeconds: 5000)
        XCTAssertEqual(allTimer.startedAt, t0)
        XCTAssertEqual(allTimer.endsAt, t0.addingTimeInterval(60))
        XCTAssertEqual(allTimer.fadeSeconds, 60, "fade is clipped to the timer's own duration")
        XCTAssertEqual(onChangeCount, 1)

        let lightTimer = runner.start(.light(lightA.id), duration: 30)
        XCTAssertEqual(lightTimer.startedAt, t0)
        XCTAssertEqual(lightTimer.endsAt, t0.addingTimeInterval(30))
        XCTAssertEqual(lightTimer.fadeSeconds, 0)
        XCTAssertEqual(onChangeCount, 2)

        XCTAssertEqual(runner.timers.count, 2, "one timer per target")
        XCTAssertEqual(runner.timer(for: .allLights)?.id, allTimer.id)
        XCTAssertEqual(runner.timer(for: .light(lightA.id))?.id, lightTimer.id)
        XCTAssertTrue(runner.isActive(.allLights))
        XCTAssertTrue(runner.isActive(.light(lightA.id)))
        XCTAssertFalse(runner.isActive(.light(lightB.id)))
    }

    func testStartingAgainForSameTargetReplacesTheOldTimer() {
        let light = makeLight(on: true)
        let (runner, _, setNow) = makeRunner(now: t0, lights: [light])

        let first = runner.start(.allLights, duration: 60)
        setNow(t0.addingTimeInterval(10))
        let second = runner.start(.allLights, duration: 120)

        XCTAssertEqual(runner.timers.count, 1, "replacing keeps exactly one timer for the target")
        XCTAssertEqual(runner.timer(for: .allLights)?.id, second.id)
        XCTAssertNotEqual(runner.timer(for: .allLights)?.id, first.id)
        XCTAssertEqual(runner.timer(for: .allLights)?.startedAt, t0.addingTimeInterval(10))
        XCTAssertEqual(runner.timer(for: .allLights)?.endsAt, t0.addingTimeInterval(130))
    }

    // MARK: - tick: deadline

    func testTickDoesNothingBeforeDeadlineAndSwitchesOffAtDeadline() {
        let lightA = makeLight(name: "A", on: true)
        let lightB = makeLight(name: "B", on: true)
        let (runner, _, setNow) = makeRunner(now: t0, lights: [lightA, lightB])
        var onChangeCount = 0
        runner.onChange = { onChangeCount += 1 }
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        runner.start(.allLights, duration: 60)
        onChangeCount = 0   // discount start()'s own notification

        runner.tick(now: t0.addingTimeInterval(59))
        XCTAssertTrue(switchedOff.isEmpty, "not due yet")
        XCTAssertEqual(onChangeCount, 0, "no change published before the deadline")
        XCTAssertNotNil(runner.timer(for: .allLights))

        runner.tick(now: t0.addingTimeInterval(60))
        XCTAssertEqual(Set(switchedOff.map(\.id)), Set([lightA.id, lightB.id]))
        XCTAssertEqual(switchedOff.count, 2, "one call per resolved light")
        XCTAssertNil(runner.timer(for: .allLights), "timer removed once it fires")
        XCTAssertEqual(onChangeCount, 1)

        // A per-light target only switches off the light it names, not every light.
        switchedOff.removeAll()
        setNow(t0.addingTimeInterval(60))
        runner.start(.light(lightA.id), duration: 10)
        runner.tick(now: t0.addingTimeInterval(70))
        XCTAssertEqual(switchedOff.map(\.id), [lightA.id])
    }

    // MARK: - tick: fade window

    func testTickStartsGoToSleepFadeOnlyForLightsThatAreOnWithinFadeWindow() {
        let onLight = makeLight(name: "On", on: true)
        let offLight = makeLight(name: "Off", on: false)
        let (runner, fadeRunner, setNow) = makeRunner(now: t0, lights: [onLight, offLight])
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }
        func tick(_ offset: TimeInterval) {
            let now = t0.addingTimeInterval(offset)
            setNow(now)
            runner.tick(now: now)
        }

        runner.start(.allLights, duration: 120, fadeSeconds: 30)   // window opens at +90

        tick(80)
        XCTAssertFalse(fadeRunner.isFading(onLight), "not inside the fade window yet")

        tick(91)
        XCTAssertTrue(fadeRunner.isFading(onLight), "an on light fades down inside the window")
        XCTAssertFalse(fadeRunner.isFading(offLight), "an already-off light is skipped")
        let startedAt = fadeRunner.active[onLight.id]?.startedAt

        tick(100)   // still inside the same window
        XCTAssertEqual(fadeRunner.active[onLight.id]?.startedAt, startedAt, "fade is not restarted mid-window")

        tick(120)
        XCTAssertFalse(fadeRunner.isFading(onLight), "fade is cancelled once the timer itself fires")
        XCTAssertTrue(switchedOff.contains { $0.id == onLight.id })
        XCTAssertNil(runner.timer(for: .allLights))
    }

    // MARK: - extend

    func testExtendPushesDeadlineOutAndRestartsCancelledFade() {
        let onLight = makeLight(on: true)
        let (runner, fadeRunner, setNow) = makeRunner(now: t0, lights: [onLight])
        runner.performSwitchOff = { _ in }
        func tick(_ offset: TimeInterval) {
            let now = t0.addingTimeInterval(offset)
            setNow(now)
            runner.tick(now: now)
        }

        runner.start(.allLights, duration: 120, fadeSeconds: 30)
        tick(91)   // inside the original window [90, 120)
        XCTAssertTrue(fadeRunner.isFading(onLight))

        runner.extend(.allLights, by: 60)
        XCTAssertEqual(runner.timer(for: .allLights)?.endsAt, t0.addingTimeInterval(180))
        XCTAssertFalse(fadeRunner.isFading(onLight), "an in-progress fade is cancelled by extending")

        tick(151)   // inside the new window [150, 180)
        XCTAssertTrue(fadeRunner.isFading(onLight), "fade restarts once the pushed-out window is reached")

        tick(180)
        XCTAssertFalse(fadeRunner.isFading(onLight))
        XCTAssertNil(runner.timer(for: .allLights))
    }

    // MARK: - cancel / cancelAll

    func testCancelRemovesTimerAndCancelsInProgressFade() {
        let onLight = makeLight(on: true)
        let (runner, fadeRunner, setNow) = makeRunner(now: t0, lights: [onLight])
        var onChangeCount = 0
        runner.onChange = { onChangeCount += 1 }
        func tick(_ offset: TimeInterval) {
            let now = t0.addingTimeInterval(offset)
            setNow(now)
            runner.tick(now: now)
        }

        runner.start(.allLights, duration: 120, fadeSeconds: 30)
        tick(91)
        XCTAssertTrue(fadeRunner.isFading(onLight))

        onChangeCount = 0
        runner.cancel(.allLights)
        XCTAssertNil(runner.timer(for: .allLights))
        XCTAssertFalse(fadeRunner.isFading(onLight), "cancelling a timer also cancels its in-progress fade")
        XCTAssertEqual(onChangeCount, 1)
    }

    func testCancelAllClearsEveryTimerAndFade() {
        let lightA = makeLight(name: "A", on: true)
        let lightB = makeLight(name: "B", on: true)
        let (runner, fadeRunner, setNow) = makeRunner(now: t0, lights: [lightA, lightB])
        func tick(_ offset: TimeInterval) {
            let now = t0.addingTimeInterval(offset)
            setNow(now)
            runner.tick(now: now)
        }

        runner.start(.allLights, duration: 120, fadeSeconds: 30)
        runner.start(.light(lightA.id), duration: 300)
        XCTAssertEqual(runner.timers.count, 2)
        tick(91)
        XCTAssertTrue(fadeRunner.isFading(lightA))
        XCTAssertTrue(fadeRunner.isFading(lightB))

        runner.cancelAll()
        XCTAssertTrue(runner.timers.isEmpty)
        XCTAssertTrue(fadeRunner.active.isEmpty)
    }

    func testCancelWithNoTimerIsANoOp() {
        let (runner, _, _) = makeRunner(now: t0, lights: [])
        var onChangeCount = 0
        runner.onChange = { onChangeCount += 1 }

        runner.cancel(.allLights)

        XCTAssertEqual(onChangeCount, 0)
        XCTAssertTrue(runner.timers.isEmpty)
    }

    // MARK: - timers(affecting:)

    func testTimersAffectingLightReturnsItsOwnAndAllLightsTimerSoonestFirst() {
        let lightA = makeLight(name: "A", on: true)
        let lightB = makeLight(name: "B", on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [lightA, lightB])

        runner.start(.allLights, duration: 300)
        runner.start(.light(lightA.id), duration: 60)
        runner.start(.light(lightB.id), duration: 120)

        let affectingA = runner.timers(affecting: lightA.id)
        XCTAssertEqual(affectingA.map(\.target), [.light(lightA.id), .allLights], "soonest deadline first")
        XCTAssertFalse(affectingA.contains { $0.target == .light(lightB.id) })
    }

    // MARK: - migrate

    func testMigrateRetargetsALightTimer() {
        let oldID = UUID()
        let newID = UUID()
        let (runner, _, _) = makeRunner(now: t0, lights: [])
        var onChangeCount = 0
        runner.onChange = { onChangeCount += 1 }

        let original = runner.start(.light(oldID), duration: 60)
        onChangeCount = 0
        runner.migrate(lightID: oldID, to: newID)

        XCTAssertNil(runner.timer(for: .light(oldID)))
        let migrated = runner.timer(for: .light(newID))
        XCTAssertEqual(migrated?.id, original.id, "same timer, new target")
        XCTAssertEqual(migrated?.endsAt, original.endsAt)
        XCTAssertEqual(onChangeCount, 1)
    }

    // MARK: - restore

    func testRestoreKeepsATimerStillInTheFuture() {
        let light = makeLight(on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [light])
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        let saved = SleepTimer(target: .allLights, startedAt: t0.addingTimeInterval(-10), endsAt: t0.addingTimeInterval(100), fadeSeconds: 0)
        runner.restore([saved])

        XCTAssertEqual(runner.timer(for: .allLights)?.endsAt, t0.addingTimeInterval(100))
        XCTAssertTrue(switchedOff.isEmpty)
    }

    func testRestoreFiresATimerOverdueWithinGraceImmediately() {
        let light = makeLight(on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [light])
        runner.missedGrace = 30 * 60
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        // 100 s overdue, well inside the 30 min grace.
        let saved = SleepTimer(target: .allLights, startedAt: t0.addingTimeInterval(-500), endsAt: t0.addingTimeInterval(-100), fadeSeconds: 0)
        runner.restore([saved])

        XCTAssertEqual(switchedOff.map(\.id), [light.id], "fires switch-off immediately for a timer overdue within grace")
        XCTAssertNil(runner.timer(for: .allLights), "not kept as a live timer")
    }

    func testRestoreDropsATimerOverdueBeyondGraceWithoutSwitchingOff() {
        let light = makeLight(on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [light])
        runner.missedGrace = 30 * 60
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        // ~33 min overdue, past the 30 min grace.
        let saved = SleepTimer(target: .allLights, startedAt: t0.addingTimeInterval(-4000), endsAt: t0.addingTimeInterval(-2000), fadeSeconds: 0)
        runner.restore([saved])

        XCTAssertTrue(switchedOff.isEmpty, "too stale to switch off")
        XCTAssertNil(runner.timer(for: .allLights))
    }

    /// BUG: `restore()` decides whether to notify by comparing `restored.count != saved.count`, but a
    /// saved entry whose target already has a live timer is filtered out of the loop entirely (via the
    /// `for entry in saved where timer(for: entry.target) == nil` clause) — it's never counted as
    /// "restored", "fired", or "dropped". That makes the count comparison fire spuriously: `timers` is
    /// completely unchanged, yet `onChange` still gets called. This is inconsistent with `cancel()`,
    /// which is an explicit, documented no-op when there's nothing to do. This test encodes the
    /// no-op-like expectation and currently FAILS against `SleepTimerRunner.restore` in
    /// Sources/OpenHue/Scheduling/SleepTimerRunner.swift (the `if fired || restored.count != saved.count
    /// || !restored.isEmpty { didChange() }` line) — see the final assertion.
    func testRestoreIgnoresATargetThatAlreadyHasALiveTimer() {
        let light = makeLight(on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [light])
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        let live = runner.start(.allLights, duration: 100)
        var onChangeCount = 0
        runner.onChange = { onChangeCount += 1 }

        let saved = SleepTimer(target: .allLights, startedAt: t0, endsAt: t0.addingTimeInterval(500), fadeSeconds: 0)
        runner.restore([saved])

        XCTAssertEqual(runner.timers.count, 1)
        XCTAssertEqual(runner.timer(for: .allLights)?.id, live.id, "the saved entry is ignored; the live timer is untouched")
        XCTAssertEqual(runner.timer(for: .allLights)?.endsAt, live.endsAt)
        XCTAssertTrue(switchedOff.isEmpty)

        XCTAssertEqual(onChangeCount, 0, "restore() should not publish a change when `timers` didn't actually change (BUG: currently fires)")
    }

    // MARK: - tick: missed deadline (Mac was asleep)

    func testTickDropsATimerMissedByMoreThanGraceWithoutSwitchingOff() {
        let light = makeLight(on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [light])
        runner.missedGrace = 30 * 60
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        runner.start(.allLights, duration: 60)
        // One big jump past the deadline AND the whole grace window, as if the Mac had been asleep.
        runner.tick(now: t0.addingTimeInterval(60 + 30 * 60 + 1))

        XCTAssertTrue(switchedOff.isEmpty, "missed by more than the grace window — lights are left as they are")
        XCTAssertNil(runner.timer(for: .allLights))
    }

    func testTickSwitchesOffATimerMissedWithinGrace() {
        let light = makeLight(on: true)
        let (runner, _, _) = makeRunner(now: t0, lights: [light])
        runner.missedGrace = 30 * 60
        var switchedOff: [HueLight] = []
        runner.performSwitchOff = { switchedOff.append($0) }

        runner.start(.allLights, duration: 60)
        // 15 minutes late in one jump — still inside the grace window.
        runner.tick(now: t0.addingTimeInterval(60 + 15 * 60))

        XCTAssertEqual(switchedOff.map(\.id), [light.id])
        XCTAssertNil(runner.timer(for: .allLights))
    }

    // MARK: - formatting

    func testDurationTextFormatsSecondsMinutesAndHours() {
        XCTAssertEqual(SleepTimerRunner.durationText(45), "45 s")
        XCTAssertEqual(SleepTimerRunner.durationText(20 * 60), "20 min")
        XCTAssertEqual(SleepTimerRunner.durationText(3600), "1 h")
        XCTAssertEqual(SleepTimerRunner.durationText(5400), "1 h 30 min")
    }

    func testCountdownTextFormatsAndRoundsUp() {
        XCTAssertEqual(SleepTimerRunner.countdownText(1198), "19:58")
        XCTAssertEqual(SleepTimerRunner.countdownText(5398), "1:29:58")
        XCTAssertEqual(SleepTimerRunner.countdownText(0), "0:00")
        XCTAssertEqual(SleepTimerRunner.countdownText(0.4), "0:01")
    }
}
