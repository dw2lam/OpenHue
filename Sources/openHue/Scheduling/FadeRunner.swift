import Foundation

/// Wall-clock-driven brightness / color-temperature ramps (wake-up and go-to-sleep).
///
/// Progress is derived from the wall clock on every tick rather than counted in steps, so a fade
/// that was paused by a lid close resumes at the point it should have reached. One shared timer
/// serves every active fade and a system-sleep assertion is held while any fade runs.
@MainActor
final class FadeRunner: ObservableObject {
    enum Mode: Equatable { case wakeUp, goToSleep }

    struct Progress: Equatable {
        var mode: Mode
        var startedAt: Date
        var duration: TimeInterval
        /// 0...1
        var fraction: Double
    }

    /// Light id → progress of its running fade.
    @Published private(set) var active: [UUID: Progress] = [:]

    /// Source of "now" (tests pin it).
    var clock: () -> Date = { Date() }

    private struct Fade {
        let light: HueLight
        let mode: Mode
        /// Brightness / color at fraction 0.
        let from: LightState
        /// Brightness / color at fraction 1.
        let to: LightState
        let startedAt: Date
        let duration: TimeInterval
        let startProgress: Double
        /// Last values written, so ticks only send what changed.
        var lastBrightness: UInt8?
        var lastMireds: UInt16?

        var rampsMireds: Bool { from.color.mireds != nil && to.color.mireds != nil }

        func fraction(at now: Date) -> Double {
            guard duration > 0 else { return 1 }
            return min(1, max(0, startProgress + now.timeIntervalSince(startedAt) / duration))
        }

        func brightness(at p: Double) -> UInt8 {
            HueWire.clampBrightness(UInt8(clamping: Int(FadeRunner.lerp(Double(from.brightness), Double(to.brightness), p).rounded())))
        }

        func mireds(at p: Double) -> UInt16? {
            guard let a = from.color.mireds, let b = to.color.mireds else { return nil }
            return UInt16(clamping: Int(FadeRunner.lerp(Double(a), Double(b), p).rounded()))
        }
    }

    private var fades: [UUID: Fade] = [:]
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var sleepAssertion: PowerManagement.SleepAssertion?

    /// Starts a fade on each light. `target(light, index)` gives the end state for wake-up
    /// (ignored for go-to-sleep, which ends at brightness 1 / warmest and then turns off).
    /// `startProgress` lets a late-started wake-up resume mid-ramp.
    func start(lights: [HueLight], target: ((HueLight, Int) -> LightState)? = nil, duration: TimeInterval, startProgress: Double = 0, mode: Mode) {
        let now = clock()
        let p0 = min(1, max(0, startProgress))

        for (index, light) in lights.enumerated() {
            cancel(light: light)
            let warmest = ColorMode.ct(mireds: light.info.maxMireds)

            switch mode {
            case .wakeUp:
                var to = target?(light, index) ?? LightState(on: true, brightness: 254, color: .ct(mireds: 367))
                to.on = true
                // CT targets ramp from the warmest white; xy targets are set up front and only brightness ramps.
                let from = LightState(on: true, brightness: 1, color: to.color.mireds != nil ? warmest : to.color)
                if p0 >= 1 || duration <= 0 {
                    light.apply(to, source: .automation)
                    continue
                }
                var fade = Fade(light: light, mode: .wakeUp, from: from, to: to, startedAt: now, duration: duration, startProgress: p0)
                // Prelude at the resume point: `apply` sends color before power so an off bulb
                // doesn't flash its old color, and a late start doesn't dip to 1 first.
                var initial = from
                initial.brightness = fade.brightness(at: p0)
                if let m = fade.mireds(at: p0) { initial.color = .ct(mireds: m) }
                light.apply(initial, source: .automation)
                fade.lastBrightness = initial.brightness
                fade.lastMireds = initial.color.mireds
                fades[light.id] = fade
                hueLog("Fade: wake-up on \(light.name) over \(Int(duration.rounded())) s from \(Int((p0 * 100).rounded()))%", level: .debug)

            case .goToSleep:
                let current = light.state
                guard current.on else {
                    hueLog("Fade: \(light.name) is already off, nothing to fade", level: .debug)
                    continue
                }
                let to = LightState(on: true, brightness: 1, color: current.color.mireds != nil ? warmest : current.color)
                if p0 >= 1 || duration <= 0 {
                    light.set(power: false, source: .automation)
                    continue
                }
                var fade = Fade(light: light, mode: .goToSleep, from: current, to: to, startedAt: now, duration: duration, startProgress: p0)
                fade.lastBrightness = current.brightness
                fade.lastMireds = current.color.mireds
                fades[light.id] = fade
                hueLog("Fade: go-to-sleep on \(light.name) over \(Int(duration.rounded())) s from \(Int((p0 * 100).rounded()))%", level: .debug)
            }

            active[light.id] = Progress(mode: mode, startedAt: now, duration: duration, fraction: p0)
        }

        if fades.isEmpty {
            stopTimerIfIdle()
        } else {
            ensureTimer()
        }
    }

    func cancel(light: HueLight) {
        guard fades.removeValue(forKey: light.id) != nil else { return }
        active.removeValue(forKey: light.id)
        hueLog("Fade: cancelled on \(light.name)", level: .debug)
        stopTimerIfIdle()
    }

    func cancelAll() {
        guard !fades.isEmpty else { return }
        fades.removeAll()
        active.removeAll()
        hueLog("Fade: all cancelled", level: .debug)
        stopTimerIfIdle()
    }

    func isFading(_ light: HueLight) -> Bool { active[light.id] != nil }

    /// One fade step (exposed for tests; the timer calls it with the wall clock).
    func tick(now: Date = Date()) {
        for id in Array(fades.keys) {
            guard var fade = fades[id] else { continue }
            let p = fade.fraction(at: now)

            if p >= 1 {
                finish(fade)
                fades.removeValue(forKey: id)
                active.removeValue(forKey: id)
                continue
            }

            let brightness = fade.brightness(at: p)
            if brightness != fade.lastBrightness {
                fade.light.set(brightness: brightness, source: .automation)
                fade.lastBrightness = brightness
            }
            if let mireds = fade.mireds(at: p), mireds != fade.lastMireds {
                fade.light.set(mireds: mireds, source: .automation)
                fade.lastMireds = mireds
            }
            fades[id] = fade
            active[id] = Progress(mode: fade.mode, startedAt: fade.startedAt, duration: fade.duration, fraction: p)
        }
        stopTimerIfIdle()
    }

    // MARK: Internals

    private func finish(_ fade: Fade) {
        switch fade.mode {
        case .wakeUp:
            fade.light.apply(fade.to, source: .automation)
            hueLog("Fade: wake-up on \(fade.light.name) complete", level: .debug)
        case .goToSleep:
            if fade.to.brightness != fade.lastBrightness {
                fade.light.set(brightness: fade.to.brightness, source: .automation)
            }
            if let m = fade.to.color.mireds, fade.rampsMireds, m != fade.lastMireds {
                fade.light.set(mireds: m, source: .automation)
            }
            fade.light.set(power: false, source: .automation)
            hueLog("Fade: go-to-sleep on \(fade.light.name) complete, turned off", level: .debug)
        }
    }

    /// Tick interval: one brightness step per tick for the shortest active fade, clamped to 1…10 s.
    private var desiredInterval: TimeInterval {
        let shortest = fades.values.map(\.duration).min() ?? 60
        return min(10, max(1, shortest / 254))
    }

    private func ensureTimer() {
        let interval = desiredInterval
        if let timer, timer.isValid, abs(timerInterval - interval) < 0.001 { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick(now: self.clock())
            }
        }
        RunLoop.main.add(t, forMode: .common)   // keep ticking during slider drags / open menus
        t.tolerance = interval * 0.1
        timer = t
        timerInterval = interval
        if sleepAssertion == nil {
            sleepAssertion = PowerManagement.SleepAssertion(reason: "openHue: light fade in progress")
        }
    }

    private func stopTimerIfIdle() {
        guard fades.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        timerInterval = 0
        sleepAssertion?.release()
        sleepAssertion = nil
    }

    nonisolated fileprivate static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
