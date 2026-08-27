import XCTest
@testable import OpenHue

@MainActor
final class FadeRunnerTests: XCTestCase {
    private func makeLight(name: String = "Lamp", on: Bool, brightness: UInt8 = 200, color: ColorMode = .ct(mireds: 300), maxMireds: UInt16 = 500) -> HueLight {
        var info = KnownLight(id: UUID(), name: name)
        info.maxMireds = maxMireds
        info.lastState = LightState(on: on, brightness: brightness, color: color)
        return HueLight(info: info)
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRunner(now: Date) -> (FadeRunner, (Date) -> Void) {
        let runner = FadeRunner()
        var current = now
        runner.clock = { current }
        return (runner, { current = $0 })
    }

    func testWakeUpProgressFollowsWallClock() {
        let (runner, setNow) = makeRunner(now: t0)
        let light = makeLight(on: false)
        runner.start(lights: [light], target: { _, _ in LightState(on: true, brightness: 254, color: .ct(mireds: 250)) }, duration: 600, mode: .wakeUp)

        XCTAssertTrue(runner.isFading(light))
        XCTAssertEqual(runner.active[light.id], FadeRunner.Progress(mode: .wakeUp, startedAt: t0, duration: 600, fraction: 0))

        setNow(t0.addingTimeInterval(300))
        runner.tick(now: t0.addingTimeInterval(300))
        XCTAssertEqual(runner.active[light.id]?.fraction ?? -1, 0.5, accuracy: 1e-9)

        // A long pause (lid closed) is caught up from the clock, not counted in ticks.
        runner.tick(now: t0.addingTimeInterval(599))
        XCTAssertEqual(runner.active[light.id]?.fraction ?? -1, 599.0 / 600, accuracy: 1e-9)

        runner.tick(now: t0.addingTimeInterval(600))
        XCTAssertFalse(runner.isFading(light), "fade completes at the end of its duration")
        XCTAssertTrue(runner.active.isEmpty)
    }

    func testLateWakeUpResumesMidRamp() {
        let (runner, _) = makeRunner(now: t0)
        let light = makeLight(on: false)
        runner.start(lights: [light], duration: 600, startProgress: 0.5, mode: .wakeUp)
        XCTAssertEqual(runner.active[light.id]?.fraction ?? -1, 0.5, accuracy: 1e-9)

        runner.tick(now: t0.addingTimeInterval(150))
        XCTAssertEqual(runner.active[light.id]?.fraction ?? -1, 0.75, accuracy: 1e-9)

        runner.tick(now: t0.addingTimeInterval(300))
        XCTAssertFalse(runner.isFading(light), "ends at the originally scheduled end time")
    }

    func testWakeUpAlreadyPastEndAppliesImmediately() {
        let (runner, _) = makeRunner(now: t0)
        let light = makeLight(on: false)
        runner.start(lights: [light], duration: 600, startProgress: 1, mode: .wakeUp)
        XCTAssertFalse(runner.isFading(light))
        runner.start(lights: [light], duration: 0, mode: .wakeUp)
        XCTAssertFalse(runner.isFading(light))
    }

    func testGoToSleepSkipsLightsThatAreOff() {
        let (runner, _) = makeRunner(now: t0)
        let off = makeLight(name: "Off", on: false)
        let on = makeLight(name: "On", on: true)
        runner.start(lights: [off, on], duration: 1200, mode: .goToSleep)
        XCTAssertFalse(runner.isFading(off))
        XCTAssertTrue(runner.isFading(on))
        XCTAssertEqual(runner.active[on.id]?.mode, .goToSleep)

        runner.tick(now: t0.addingTimeInterval(1200))
        XCTAssertTrue(runner.active.isEmpty)
    }

    func testCancelStopsOneLightAndCancelAllStopsEverything() {
        let (runner, _) = makeRunner(now: t0)
        let a = makeLight(name: "A", on: true)
        let b = makeLight(name: "B", on: true, color: .xy(XY(x: 0.5, y: 0.4)))
        runner.start(lights: [a, b], duration: 900, mode: .goToSleep)
        XCTAssertEqual(runner.active.count, 2)

        runner.cancel(light: a)
        XCTAssertFalse(runner.isFading(a))
        XCTAssertTrue(runner.isFading(b))

        runner.tick(now: t0.addingTimeInterval(450))
        XCTAssertEqual(runner.active[b.id]?.fraction ?? -1, 0.5, accuracy: 1e-9)

        runner.cancelAll()
        XCTAssertTrue(runner.active.isEmpty)
        runner.cancel(light: a)   // idempotent
        runner.cancelAll()
    }

    func testRestartingAFadeReplacesThePreviousOne() {
        let (runner, setNow) = makeRunner(now: t0)
        let light = makeLight(on: false)
        runner.start(lights: [light], duration: 600, mode: .wakeUp)
        setNow(t0.addingTimeInterval(100))
        runner.start(lights: [light], duration: 300, mode: .wakeUp)
        XCTAssertEqual(runner.active[light.id]?.startedAt, t0.addingTimeInterval(100))
        XCTAssertEqual(runner.active[light.id]?.duration, 300)
        XCTAssertEqual(runner.active.count, 1)
    }
}
