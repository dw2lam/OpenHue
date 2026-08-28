import Foundation
import AppKit

/// What the scheduler needs from the app. `AppModel` conforms.
@MainActor
protocol SchedulerContext: AnyObject {
    var schedules: [Schedule] { get set }
    var settings: AppSettings { get }
    /// Lights a schedule targets (all remembered lights when `targets` is empty).
    func lights(for schedule: Schedule) -> [HueLight]
    /// Resolves a target to a concrete state for a light (`index` = position among the targets,
    /// used for preset palette round-robin). nil if a scene has no entry for the light.
    func resolve(_ target: LightTarget, for light: HueLight, index: Int) -> LightState?
}

// MARK: - Next fire (pure)

extension Schedule {
    /// Next time this schedule should fire strictly after `reference`. nil for expired one-shots
    /// or weekly schedules with no days.
    ///
    /// Weekly triggers are resolved per selected weekday with `Calendar.nextDate`, which walks
    /// calendar days rather than adding 24 h multiples — so the result lands on the requested wall
    /// clock time across DST transitions. A time that does not exist on a spring-forward day is
    /// pushed to the first valid instant after the gap (`.nextTime`); a time that occurs twice on a
    /// fall-back day uses the first occurrence (`.first`).
    func nextFire(after reference: Date, calendar: Calendar = .current) -> Date? {
        switch trigger {
        case .once(let date):
            return date > reference ? date : nil

        case .weekly(let days, let time):
            guard !days.isEmpty else { return nil }
            var best: Date?
            for day in days {
                var match = DateComponents()
                match.hour = time.hour
                match.minute = time.minute
                match.second = 0
                match.weekday = day.rawValue
                guard let candidate = calendar.nextDate(after: reference,
                                                        matching: match,
                                                        matchingPolicy: .nextTime,
                                                        repeatedTimePolicy: .first,
                                                        direction: .forward) else { continue }
                if let current = best {
                    if candidate < current { best = candidate }
                } else {
                    best = candidate
                }
            }
            return best
        }
    }
}

// MARK: - Scheduler

/// Mac-side scheduler: runs schedules while the app is running, tolerates sleep/wake and clock changes.
///
/// Time flows through two seams so the logic is testable without waiting or Bluetooth:
/// - `clock` supplies "now" for `start()` / `schedulesDidChange()` (`tick(now:)` takes it explicitly).
/// - `executeAction`, when set, replaces the real per-light execution (`ensureReady` + writes).
@MainActor
final class Scheduler: ObservableObject {
    @Published private(set) var nextFires: [UUID: Date] = [:]
    @Published private(set) var running: Set<UUID> = []
    /// Human-readable last outcome per schedule ("Ran 07:00", "Skipped — Mac was asleep 45 min", …).
    @Published private(set) var lastOutcome: [UUID: String] = [:]

    let fadeRunner: FadeRunner
    weak var context: SchedulerContext?

    /// Replaces the real execution path (tests). Receives the schedule, the occurrence it is
    /// firing for and how late the scheduler noticed it (0 for "Run now").
    typealias ActionExecutor = @MainActor (_ schedule: Schedule, _ scheduledAt: Date, _ lateness: TimeInterval) async -> Void
    var executeAction: ActionExecutor?
    /// Source of "now" for the timer-driven paths. Tests pin it.
    var clock: () -> Date = { Date() }
    /// Calendar used to resolve weekly triggers. Tests pin a time zone.
    var calendar: Calendar = .current

    /// How long a light may take to connect before the schedule gives up on it.
    var connectTimeout: TimeInterval = 20

    private var timer: Timer?
    private var wakeTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultCenterObservers: [NSObjectProtocol] = []
    private var inflight: [UUID: Task<Void, Never>] = [:]

    init(fadeRunner: FadeRunner) {
        self.fadeRunner = fadeRunner
    }

    // MARK: Lifecycle

    /// Starts the tick timer and sleep/wake/clock observers.
    func start() {
        stop()
        recompute(now: clock())

        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick(now: self.clock())
            }
        }
        RunLoop.main.add(timer, forMode: .common)   // keep ticking during slider drags / open menus
        timer.tolerance = 5
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDidWake() }
        })

        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, Notification.Name.NSCalendarDayChanged] {
            defaultCenterObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.handleClockChange(note.name) }
            })
        }
        hueLog("Scheduler started (\(nextFires.count) armed)", level: .debug)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        wakeTask?.cancel()
        wakeTask = nil
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
        defaultCenterObservers.forEach { NotificationCenter.default.removeObserver($0) }
        defaultCenterObservers.removeAll()
    }

    /// Recompute `nextFires` after schedules were added/edited/toggled.
    func schedulesDidChange() {
        recompute(now: clock())
    }

    /// "Run now" — executes the schedule's action immediately regardless of its trigger.
    func runNow(_ schedule: Schedule) {
        let now = clock()
        hueLog("Schedule “\(schedule.name)”: run now")
        run(schedule, at: now, lateness: 0, outcome: "Ran \(Self.timeText(now)) (manually)")
    }

    func nextFire(for schedule: Schedule) -> Date? { nextFires[schedule.id] }

    /// Awaits every execution started by `tick`/`runNow` (tests).
    func awaitInflight() async {
        for task in Array(inflight.values) { await task.value }
    }

    // MARK: Tick

    /// One scheduler pass (exposed for tests).
    ///
    /// For every enabled schedule whose next fire is due, walks forward past every occurrence
    /// that is already in the past (only the most recent one is acted on), then either runs it
    /// (within the missed-fire grace) or records it as skipped. Either way `lastFired` is written
    /// back so the occurrence is never considered again, and one-shots disable themselves.
    func tick(now: Date = Date()) {
        guard let context else { return }
        var schedules = context.schedules
        var schedulesChanged = false
        var toStart: [(Schedule, Date, TimeInterval, String)] = []

        for schedule in schedules where schedule.isEnabled {
            guard var due = nextFires[schedule.id] else { continue }
            var toRun: Date?
            var exhausted = false
            while due <= now {
                toRun = due
                guard let next = schedule.nextFire(after: due, calendar: calendar), next > due else {
                    exhausted = true
                    break
                }
                due = next
            }
            if exhausted {
                nextFires.removeValue(forKey: schedule.id)
            } else {
                nextFires[schedule.id] = due
            }
            guard let fireAt = toRun else { continue }

            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index].lastFired = fireAt
                if case .once = schedule.trigger { schedules[index].isEnabled = false }
                schedulesChanged = true
            }

            let lateness = now.timeIntervalSince(fireAt)
            let allowed = grace(for: schedule.action)
            let timeText = Self.timeText(fireAt)
            if lateness <= allowed {
                var outcome = "Ran \(timeText)"
                if lateness >= 60 { outcome += " (\(Self.latenessText(lateness)) late)" }
                toStart.append((schedule, fireAt, lateness, outcome))
            } else {
                let outcome = "Skipped — \(Self.latenessText(lateness)) late"
                lastOutcome[schedule.id] = outcome
                hueLog("Schedule “\(schedule.name)” due \(timeText) skipped: \(Self.latenessText(lateness)) late exceeds the \(Self.latenessText(allowed)) grace", level: .warning)
            }
        }

        if schedulesChanged {
            context.schedules = schedules
        }
        for (schedule, fireAt, lateness, outcome) in toStart {
            run(schedule, at: fireAt, lateness: lateness, outcome: outcome)
        }
    }

    // MARK: Internals

    private func recompute(now: Date) {
        guard let context else {
            nextFires = [:]
            return
        }
        var next: [UUID: Date] = [:]
        for schedule in context.schedules where schedule.isEnabled {
            let floor = max(schedule.lastFired ?? .distantPast, now.addingTimeInterval(-grace(for: schedule.action)))
            if let fire = schedule.nextFire(after: floor, calendar: calendar) {
                next[schedule.id] = fire
            }
        }
        nextFires = next
    }

    private func grace(for action: ScheduleAction) -> TimeInterval {
        let settings = context?.settings ?? AppSettings()
        if action.isOnAction {
            return TimeInterval(max(0, settings.missedGraceOnMinutes)) * 60
        }
        return TimeInterval(max(0, settings.missedGraceOffHours)) * 3600
    }

    private func handleDidWake() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            hueLog("Scheduler: Mac woke, checking schedules", level: .debug)
            self.tick(now: self.clock())
        }
    }

    private func handleClockChange(_ name: Notification.Name) {
        hueLog("Scheduler: \(name == .NSCalendarDayChanged ? "day changed" : "system clock changed"), recomputing", level: .debug)
        let now = clock()
        recompute(now: now)
        tick(now: now)
    }

    private func run(_ schedule: Schedule, at fireAt: Date, lateness: TimeInterval, outcome: String) {
        running.insert(schedule.id)
        lastOutcome[schedule.id] = outcome
        hueLog("Schedule “\(schedule.name)”: running (\(lateness >= 60 ? Self.latenessText(lateness) + " late" : "on time"))")
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if let executeAction = self.executeAction {
                await executeAction(schedule, fireAt, lateness)
            } else {
                let notes = await self.execute(schedule, lateness: lateness)
                if !notes.isEmpty {
                    self.lastOutcome[schedule.id] = outcome + " — " + notes.joined(separator: ", ")
                }
            }
            self.running.remove(schedule.id)
            self.inflight.removeValue(forKey: schedule.id)
        }
        inflight[schedule.id] = task
    }

    /// Real execution: connect on demand and apply the action to every targeted light, each light
    /// on its own task so one unreachable bulb never delays the others. Returns per-light notes
    /// ("Bedroom unreachable") for the outcome line.
    private func execute(_ schedule: Schedule, lateness: TimeInterval) async -> [String] {
        guard let context else { return [] }
        let lights = context.lights(for: schedule)
        guard !lights.isEmpty else {
            hueLog("Schedule “\(schedule.name)”: no lights to control", level: .warning)
            return ["no lights"]
        }
        let action = schedule.action
        let began = clock()
        let timeout = connectTimeout

        return await withTaskGroup(of: (Int, String?).self, returning: [String].self) { group in
            for (index, light) in lights.enumerated() {
                group.addTask { @MainActor [weak self] in
                    do {
                        try await light.ensureReady(timeout: timeout)
                    } catch {
                        hueLog("Schedule “\(schedule.name)”: \(light.name) unreachable (\(error.localizedDescription))", level: .warning)
                        return (index, "\(light.name) unreachable")
                    }
                    guard let self else { return (index, nil) }
                    let note = self.perform(action, on: light, index: index, context: context,
                                            lateness: lateness + self.clock().timeIntervalSince(began))
                    return (index, note)
                }
            }
            var notes: [(Int, String)] = []
            for await (index, note) in group {
                if let note { notes.append((index, note)) }
            }
            return notes.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    /// Applies one action to one (ready) light. `lateness` includes the time spent connecting so a
    /// late fade resumes at the right point.
    private func perform(_ action: ScheduleAction, on light: HueLight, index: Int, context: SchedulerContext, lateness: TimeInterval) -> String? {
        switch action {
        case .turnOff:
            light.set(power: false, source: .automation)
            return nil

        case .turnOn(let target):
            guard var state = context.resolve(target, for: light, index: index) else {
                hueLog("Schedule: no scene entry for \(light.name), skipped", level: .debug)
                return "\(light.name) not in scene"
            }
            state.on = true
            light.apply(state, source: .automation)
            return nil

        case .wakeUp(let minutes, let target):
            guard var end = context.resolve(target, for: light, index: index) else {
                hueLog("Schedule: no scene entry for \(light.name), skipped", level: .debug)
                return "\(light.name) not in scene"
            }
            end.on = true
            let duration = TimeInterval(max(0, minutes)) * 60
            guard duration > 0 else {
                light.apply(end, source: .automation)
                return nil
            }
            let startProgress = min(1, max(0, lateness / duration))
            if startProgress >= 1 {
                light.apply(end, source: .automation)
            } else {
                fadeRunner.start(lights: [light], target: { _, _ in end }, duration: duration, startProgress: startProgress, mode: .wakeUp)
            }
            return nil

        case .goToSleep(let minutes):
            let duration = TimeInterval(max(0, minutes)) * 60
            guard duration > 0 else {
                light.set(power: false, source: .automation)
                return nil
            }
            let startProgress = min(1, max(0, lateness / duration))
            if startProgress >= 1 {
                light.set(power: false, source: .automation)
            } else {
                fadeRunner.start(lights: [light], duration: duration, startProgress: startProgress, mode: .goToSleep)
            }
            return nil
        }
    }

    // MARK: Formatting

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "45 s", "12 min", "2 h", "2 h 15 min".
    static func latenessText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
