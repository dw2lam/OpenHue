import Foundation

/// One-shot "lights off in N minutes" countdowns, run on this Mac.
///
/// Deadlines are wall-clock based, so a Mac that slept through one turns the lights off on wake
/// (within `missedGrace`). One timer per target; starting another for the same target replaces
/// it. The owner persists `timers` through `onChange` and hands them back with `restore` on
/// launch. While a timer is pending an idle-sleep assertion keeps the Mac awake (optional).
@MainActor
final class SleepTimerRunner: ObservableObject {
    @Published private(set) var timers: [SleepTimer] = []

    /// Source of "now" (tests pin it).
    var clock: () -> Date = { Date() }
    /// Resolves the lights a target refers to (set by the owner).
    var resolveLights: (SleepTimer.Target) -> [HueLight] = { _ in [] }
    /// Called after every change to `timers` (persist).
    var onChange: (() -> Void)?
    /// Hold a system-sleep assertion while a timer is pending.
    var keepsMacAwake = true { didSet { updateAssertion() } }
    /// A deadline missed by more than this (Mac asleep, app closed) is dropped instead of fired,
    /// so a stale bedtime timer can't switch the lights off the next morning.
    var missedGrace: TimeInterval = 30 * 60
    /// How long to wait for a disconnected bulb when a timer fires.
    var connectTimeout: TimeInterval = 30
    /// Test seam: when set, replaces the real per-light "switch off" (connect on demand + power write).
    var performSwitchOff: ((HueLight) -> Void)?

    private let fadeRunner: FadeRunner
    private var timer: Timer?
    /// Timers whose fade-down has been started.
    private var fading: Set<UUID> = []
    private var sleepAssertion: PowerManagement.SleepAssertion?

    init(fadeRunner: FadeRunner) {
        self.fadeRunner = fadeRunner
    }

    // MARK: - Queries

    func timer(for target: SleepTimer.Target) -> SleepTimer? {
        timers.first { $0.target == target }
    }

    func isActive(_ target: SleepTimer.Target) -> Bool { timer(for: target) != nil }

    /// Every timer that will switch this light off (its own and the all-lights one), soonest first.
    func timers(affecting lightID: UUID) -> [SleepTimer] {
        timers.filter { $0.target == .allLights || $0.target == .light(lightID) }.sorted { $0.endsAt < $1.endsAt }
    }

    // MARK: - Commands

    /// Starts (or replaces) the timer for `target`. The fade is clipped to the countdown; in
    /// `.dimToSleep` mode it spans the whole countdown and begins right away.
    @discardableResult
    func start(_ target: SleepTimer.Target, duration: TimeInterval, fadeSeconds: TimeInterval = 0, mode: SleepTimer.Mode = .switchOff) -> SleepTimer {
        let now = clock()
        let length = max(1, duration)
        let fade = mode == .dimToSleep ? length : min(max(0, fadeSeconds), length)
        let new = SleepTimer(target: target, mode: mode, startedAt: now, endsAt: now.addingTimeInterval(length), fadeSeconds: fade)
        if let old = timer(for: target) { remove(old, cancelFade: true) }
        timers.append(new)
        switch mode {
        case .switchOff:
            hueLog("Timer: \(describe(target)) off in \(Self.durationText(length))" + (fade > 0 ? " (fade \(Int(fade.rounded())) s)" : ""))
        case .dimToSleep:
            hueLog("Sleep timer: \(describe(target)) dimming to off over \(Self.durationText(length))")
        }
        didChange()
        tick(now: now)   // a sleep timer starts its ramp immediately
        return new
    }

    /// Pushes the deadline out. A fade already in progress is cancelled and restarts later; a
    /// sleep timer's ramp restarts right away from the current brightness over the new remainder.
    func extend(_ target: SleepTimer.Target, by seconds: TimeInterval) {
        guard let index = timers.firstIndex(where: { $0.target == target }), seconds > 0 else { return }
        let now = clock()
        let old = timers[index]
        timers[index].endsAt = old.endsAt.addingTimeInterval(seconds)
        if old.mode == .dimToSleep {
            timers[index].fadeSeconds = timers[index].endsAt.timeIntervalSince(now)
        }
        if fading.remove(old.id) != nil {
            resolveLights(target).forEach { fadeRunner.cancel(light: $0) }
        }
        hueLog("Timer: \(describe(target)) extended by \(Self.durationText(seconds)), now \(Self.durationText(timers[index].remaining(at: now))) left")
        didChange()
        tick(now: now)
    }

    func cancel(_ target: SleepTimer.Target) {
        guard let old = timer(for: target) else { return }
        remove(old, cancelFade: true)
        hueLog("Sleep timer: \(describe(target)) cancelled")
        didChange()
    }

    func cancelAll() {
        guard !timers.isEmpty else { return }
        for old in timers { remove(old, cancelFade: true) }
        hueLog("Sleep timer: all cancelled")
        didChange()
    }

    /// A light was replaced (re-paired): keep its timer.
    func migrate(lightID old: UUID, to new: UUID) {
        guard let index = timers.firstIndex(where: { $0.target == .light(old) }) else { return }
        timers[index].target = .light(new)
        didChange()
    }

    /// Brings persisted timers back after a launch. Overdue ones inside the grace window fire now.
    func restore(_ saved: [SleepTimer]) {
        guard !saved.isEmpty else { return }
        let now = clock()
        var restored: [SleepTimer] = []
        // Fired or expired entries are gone from the saved file after the next save.
        var consumed = false
        for entry in saved where timer(for: entry.target) == nil {
            if entry.endsAt <= now {
                consumed = true
                if now.timeIntervalSince(entry.endsAt) <= missedGrace {
                    hueLog("Sleep timer: \(describe(entry.target)) was due while OpenHue wasn't running — switching off now")
                    switchOff(entry.target)
                } else {
                    hueLog("Sleep timer: \(describe(entry.target)) expired \(Self.durationText(now.timeIntervalSince(entry.endsAt))) ago, dropped", level: .warning)
                }
            } else {
                restored.append(entry)
            }
        }
        timers.append(contentsOf: restored)
        if !restored.isEmpty {
            hueLog("Sleep timer: restored \(restored.count) timer(s)")
        }
        if consumed || !restored.isEmpty { didChange() }
    }

    /// One step (exposed for tests; the timer calls it with the wall clock).
    func tick(now: Date = Date()) {
        for entry in timers {
            if now >= entry.endsAt {
                let lateness = now.timeIntervalSince(entry.endsAt)
                if lateness > missedGrace {
                    hueLog("Sleep timer: \(describe(entry.target)) missed by \(Self.durationText(lateness)) — dropped, lights left as they are", level: .warning)
                } else {
                    hueLog("Sleep timer: \(describe(entry.target)) done — switching off")
                    switchOff(entry.target)
                }
                remove(entry, cancelFade: false)
                continue
            }
            if entry.isFading(at: now), !fading.contains(entry.id) {
                fading.insert(entry.id)
                let lights = resolveLights(entry.target).filter { $0.state.on }
                guard !lights.isEmpty else { continue }
                let remaining = entry.endsAt.timeIntervalSince(now)
                let progress = 1 - remaining / entry.fadeSeconds
                fadeRunner.start(lights: lights, duration: entry.fadeSeconds, startProgress: min(1, max(0, progress)), mode: .goToSleep)
                hueLog("Sleep timer: \(describe(entry.target)) fading down over the last \(Self.durationText(remaining))", level: .debug)
            }
        }
        if timers.count != lastPublishedCount { didChange() }
        updateTimer()
    }

    // MARK: - Internals

    private var lastPublishedCount = 0

    private func switchOff(_ target: SleepTimer.Target) {
        for light in resolveLights(target) {
            // A fade that is still running would also switch off at its end; finish it now so the
            // bulb gets exactly one "off" and the UI clears immediately.
            fadeRunner.cancel(light: light)
            if let performSwitchOff {
                performSwitchOff(light)
            } else if light.connection.isReady {
                light.set(power: false, source: .automation)
            } else {
                let timeout = connectTimeout
                Task { @MainActor in
                    do {
                        try await light.ensureReady(timeout: timeout)
                    } catch {
                        hueLog("Sleep timer: \(light.name) unreachable (\(error.localizedDescription)) — queuing off for when it reconnects", level: .warning)
                    }
                    light.set(power: false, source: .automation)
                }
            }
        }
    }

    private func remove(_ entry: SleepTimer, cancelFade: Bool) {
        timers.removeAll { $0.id == entry.id }
        if fading.remove(entry.id) != nil, cancelFade {
            resolveLights(entry.target).forEach { fadeRunner.cancel(light: $0) }
        }
    }

    private func didChange() {
        lastPublishedCount = timers.count
        onChange?()
        updateTimer()
        updateAssertion()
    }

    private func updateTimer() {
        if timers.isEmpty {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick(now: self.clock())
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)   // keep counting during slider drags / open menus
        timer = t
    }

    private func updateAssertion() {
        let wanted = keepsMacAwake && !timers.isEmpty
        if wanted, sleepAssertion == nil {
            sleepAssertion = PowerManagement.SleepAssertion(reason: "OpenHue: sleep timer counting down")
        } else if !wanted, let assertion = sleepAssertion {
            assertion.release()
            sleepAssertion = nil
        }
    }

    private func describe(_ target: SleepTimer.Target) -> String {
        switch target {
        case .allLights: return "all lights"
        case .light(let id): return resolveLights(.light(id)).first?.name ?? id.uuidString
        }
    }

    // MARK: - Formatting

    /// "20 min", "1 h 30 min", "45 s".
    nonisolated static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(minutes) min"
        }
    }

    /// "19:58" or "1:29:58" — the countdown readout.
    nonisolated static func countdownText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
