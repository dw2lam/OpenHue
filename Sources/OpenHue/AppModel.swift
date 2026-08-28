import Foundation
import Combine
import AppKit

/// The one app-wide model: owns persistence, the BLE central, the scheduler and the fade runner,
/// and exposes everything the views need. Everything runs on the main actor.
@MainActor
final class AppModel: ObservableObject, SchedulerContext {
    enum SidebarItem: Hashable {
        case allLights
        case light(UUID)
        case scenes
        case sleepTimer
        case schedules
        case diagnostics
    }

    let store: Store
    let central: HueCentral
    let fadeRunner: FadeRunner
    let appEffects = AppEffectRunner()
    let scheduler: Scheduler
    let sleepTimers: SleepTimerRunner

    /// Presets (`Presets.all`) first, then user scenes. Only user scenes are persisted.
    @Published var scenes: [HueScene] { didSet { scheduleSave(.scenes) } }
    @Published var schedules: [Schedule] { didSet { scheduleSave(.schedules) } }
    @Published private(set) var settings: AppSettings { didSet { scheduleSave(.settings) } }
    @Published var selection: SidebarItem? = .allLights
    @Published var isDiscoveryPresented = false
    @Published private(set) var loginItemError: String?
    @Published private(set) var pmsetError: String?

    private var cancellables = Set<AnyCancellable>()
    /// Per-light `objectWillChange` forwarders, keyed by light id (rebuilt whenever the list changes).
    private var lightCancellables: [UUID: AnyCancellable] = [:]
    private var alarmCancellables: [UUID: AnyCancellable] = [:]
    private var pendingSaves: [Store.File: Task<Void, Never>] = [:]
    private var sleepAssertion: PowerManagement.SleepAssertion?
    private var wakeObserver: PowerManagement.WakeObserver?

    // MARK: - Init

    init() {
        let store = Store()
        self.store = store

        let known: [KnownLight] = store.load(.lights, default: [])
        let userScenes: [HueScene] = store.load(.scenes, default: [])
        let schedules: [Schedule] = store.load(.schedules, default: [])
        var settings: AppSettings = store.load(.settings, default: AppSettings())
        settings.launchAtLogin = PowerManagement.LoginItem.isEnabled

        self.settings = settings
        self.scenes = Presets.all + userScenes.filter { $0.kind == .user }
        self.schedules = schedules

        let central = HueCentral(known: known)
        self.central = central
        let fadeRunner = FadeRunner()
        self.fadeRunner = fadeRunner
        self.scheduler = Scheduler(fadeRunner: fadeRunner)
        self.sleepTimers = SleepTimerRunner(fadeRunner: fadeRunner)

        AppDelegate.shouldHideWindowAtLaunch = !settings.openWindowAtLaunch
        hueLog("AppModel: loaded \(known.count) light(s), \(userScenes.count) user scene(s), \(schedules.count) schedule(s)")

        scheduler.context = self
        sleepTimers.resolveLights = { [weak self] target in self?.lights(for: target) ?? [] }
        sleepTimers.onChange = { [weak self] in self?.scheduleSave(.sleepTimers) }
        sleepTimers.keepsMacAwake = settings.keepMacAwakeForSleepTimers

        // Persist the light list whenever the central reports a change.
        central.onLightsChanged = { [weak self] in self?.scheduleSave(.lights) }

        // Wire every light (now and whenever the list changes).
        central.$lights
            .sink { [weak self] lights in self?.wire(lights) }
            .store(in: &cancellables)

        // Views that only observe `model` still refresh when nested objects change.
        central.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        scheduler.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        fadeRunner.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        appEffects.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sleepTimers.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Make sure nothing debounced is lost when the app quits.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flushPendingSaves() }
            .store(in: &cancellables)

        applySideEffects(from: nil, to: settings)

        wakeObserver = PowerManagement.WakeObserver(onWake: { [weak self] in
            hueLog("System woke — re-issuing connects in 4 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                MainActor.assumeIsolated { self?.central.reconnectAfterWake() }
            }
        })

        central.start()
        scheduler.start()
        let savedTimers: [SleepTimer] = store.load(.sleepTimers, default: [])
        sleepTimers.restore(savedTimers)

        // Developer hook: OPENHUE_ALARM_SELFTEST=<seconds> (or 0 for a disarmed store/delete test),
        // optional OPENHUE_ALARM_SELFTEST_LIGHT=<name>.
        if let raw = ProcessInfo.processInfo.environment["OPENHUE_ALARM_SELFTEST"] {
            let seconds = TimeInterval(raw) ?? 0
            let wanted = ProcessInfo.processInfo.environment["OPENHUE_ALARM_SELFTEST_LIGHT"]
            Task { @MainActor [weak self] in
                for _ in 0..<120 {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    let candidates = self.lights.filter { $0.connection.isReady && $0.alarms.lastRefreshed != nil }
                    if let light = candidates.first(where: { wanted == nil || $0.name == wanted }) {
                        self.testOnBulbStorage(light: light, fireIn: seconds > 5 ? seconds : nil)
                        return
                    }
                }
            }
        }
    }

    private func wire(_ lights: [HueLight]) {
        var forwarders: [UUID: AnyCancellable] = [:]
        var alarmWatchers: [UUID: AnyCancellable] = [:]
        for light in lights {
            light.onUserWrite = { [weak self] light in
                self?.fadeRunner.cancel(light: light)
                self?.appEffects.cancel(light: light)
            }
            forwarders[light.id] = light.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
            alarmWatchers[light.id] = light.alarms.$alarms
                .sink { [weak self, weak light] alarms in
                    guard let self, let light else { return }
                    self.rearmRepeatingAlarms(alarms, on: light)
                }
        }
        lightCancellables = forwarders
        alarmCancellables = alarmWatchers
    }

    // MARK: - On-bulb alarms

    func isRepeating(_ uuid: UUID) -> Bool { settings.repeatingBulbAlarms.contains(uuid) }

    func setRepeating(_ uuid: UUID, _ on: Bool, light: HueLight? = nil) {
        updateSettings { if on { $0.repeatingBulbAlarms.insert(uuid) } else { $0.repeatingBulbAlarms.remove(uuid) } }
        if on, let light { rearmRepeatingAlarms(light.alarms.alarms, on: light) }
    }

    func createOnBulbAlarm(_ alarm: HueAlarm, on light: HueLight, repeatsDaily: Bool) {
        if repeatsDaily { setRepeating(alarm.uuid, true) }
        hueLog("On-bulb alarm “\(alarm.name)” → \(light.name), fires \(alarm.fireAt)\(repeatsDaily ? ", re-armed daily" : "")")
        light.alarms.create(alarm)
    }

    func deleteOnBulbAlarm(_ alarm: HueAlarm, on light: HueLight) {
        setRepeating(alarm.uuid, false)
        light.alarms.delete(alarm)
    }

    /// Latest line of the storage self-test per light (Diagnostics).
    @Published private(set) var onBulbTestReport: [UUID: String] = [:]

    /// Creates a test schedule on `light`, reads it back and deletes it. With `fireIn` it is armed
    /// for that many seconds ahead with the light's *current* state as its action (nothing visible
    /// happens) and the test waits to see the bulb fire and disarm it on its own clock.
    func testOnBulbStorage(light: HueLight, fireIn: TimeInterval?) {
        let state = light.state
        let action = HueAlarm.lightStateAction(on: state.on, brightness: state.brightness, color: state.color)
        let fireAt = Date().addingTimeInterval(fireIn ?? 3600)
        let alarm = HueAlarm.make(name: "OpenHue test", fireAt: fireAt, action: action, enabled: fireIn != nil)
        report(light, "Creating test schedule \(alarm.uuid.uuidString.lowercased()) (\(fireIn == nil ? "disarmed" : "fires \(fireAt)"))…")
        light.alarms.create(alarm)

        Task { @MainActor [weak self, weak light] in
            guard let self, let light else { return }
            var stored: HueAlarm?
            for _ in 0..<25 {
                try? await Task.sleep(for: .seconds(1))
                if let found = light.alarms.alarms.first(where: { $0.uuid == alarm.uuid }) { stored = found; break }
                if let outcome = light.alarms.lastOutcome, outcome.isError, outcome.at > fireAt.addingTimeInterval(-(fireIn ?? 3600)) { break }
            }
            guard let stored else {
                self.report(light, "❌ The bulb did not store the test schedule: \(light.alarms.lastOutcome?.message ?? "no answer")")
                return
            }
            let same = stored.encodeBody() == alarm.encodeBody()
            self.report(light, "✅ Stored as slot \(stored.id): \(OnBulbText.action(stored)) · \(OnBulbText.fires(stored)) — read-back \(same ? "identical" : "differs: \(stored.encodeBody().hexString)")")
            guard let fireIn else {
                light.alarms.delete(stored)
                self.report(light, "✅ Deleted it again — this bulb stores schedules.")
                return
            }
            let wait = max(5, fireIn + 25)
            self.report(light, "Waiting \(Int(wait)) s for the bulb to fire it on its own clock…")
            try? await Task.sleep(for: .seconds(wait))
            light.alarms.refresh()
            for _ in 0..<20 {
                try? await Task.sleep(for: .seconds(1))
                if !light.alarms.isBusy { break }
            }
            if let after = light.alarms.alarms.first(where: { $0.uuid == alarm.uuid }) {
                if after.isEnabled {
                    self.report(light, "❌ Still armed \(Int(Date().timeIntervalSince(fireAt))) s after its time — the bulb did not fire it (clock offset \(light.clockOffset.map { String(format: "%+.0f", $0) } ?? "?") s)")
                } else {
                    self.report(light, "✅ The bulb fired it and disarmed it itself — on-bulb schedules work.")
                }
                light.alarms.delete(after)
            } else {
                self.report(light, "⚠️ The test schedule vanished after its time (the bulb may delete fired one-shots).")
            }
        }
    }

    private func report(_ light: HueLight, _ text: String) {
        hueLog("[\(light.name)] bulb storage test: \(text)")
        onBulbTestReport[light.id] = text
    }

    /// The bulb disarms an alarm after it fires; alarms marked "daily" are armed again for the next
    /// occurrence whenever the list comes back with them disarmed and in the past.
    private func rearmRepeatingAlarms(_ alarms: [HueAlarm], on light: HueLight) {
        let now = Date()
        for alarm in alarms
        where settings.repeatingBulbAlarms.contains(alarm.uuid) && !alarm.isEnabled && !alarm.isTimer && alarm.fireAt < now {
            hueLog("On-bulb alarm “\(alarm.name)” on \(light.name) fired — re-arming for the next day")
            light.alarms.setEnabled(alarm, true)
        }
    }

    // MARK: - Lights

    var lights: [HueLight] { central.lights }
    var readyLights: [HueLight] { lights.filter { $0.connection.isReady } }

    /// Ready lights, falling back to every remembered light (their last known state) when none is connected.
    private var controlLights: [HueLight] {
        let ready = readyLights
        return ready.isEmpty ? lights : ready
    }

    var anyLightOn: Bool { controlLights.contains { $0.state.on } }

    /// Average brightness over ready lights (fallback: last known states), 1...254.
    var allLightsBrightness: UInt8 {
        let group = controlLights
        guard !group.isEmpty else { return 254 }
        let total = group.reduce(0) { $0 + Int($1.state.brightness) }
        let average = Double(total) / Double(group.count)
        return HueWire.clampBrightness(UInt8(clamping: Int(average.rounded())))
    }

    func setAll(power: Bool) {
        controlLights.forEach { $0.set(power: power) }
    }

    func setAll(brightness: UInt8) {
        let value = HueWire.clampBrightness(brightness)
        controlLights.forEach { $0.set(brightness: value) }
    }

    func setAll(mireds: UInt16) {
        controlLights.forEach { $0.set(mireds: HueWire.clampMireds(mireds, max: $0.maxMireds)) }
    }

    func setAll(xy: XY) {
        for light in controlLights {
            if light.supportsColor {
                light.set(xy: xy)
            } else {
                light.set(mireds: HueWire.clampMireds(ColorMath.approxMireds(fromXY: xy), max: light.maxMireds))
            }
        }
    }

    func setAll(effect: HueEffect, speed: UInt8) {
        controlLights.forEach { $0.set(effect: effect, speed: max(1, speed)) }
    }

    func addLight(_ bulb: DiscoveredBulb) {
        let light = central.add(bulb)
        hueLog("Added light \(light.name) (\(light.id))")
        selection = .light(light.id)
    }

    func replaceLight(_ old: HueLight, with bulb: DiscoveredBulb) {
        let oldID = old.id
        fadeRunner.cancel(light: old)
        appEffects.cancel(light: old)
        let new = central.add(bulb, replacing: old)
        guard new.id != oldID else { return }
        hueLog("Replaced light \(old.name): \(oldID) → \(new.id)")
        migrateReferences(from: oldID, to: new.id)
        sleepTimers.migrate(lightID: oldID, to: new.id)
        if selection == .light(oldID) { selection = .light(new.id) }
    }

    func forgetLight(_ light: HueLight) {
        hueLog("Forgot light \(light.name) (\(light.id))")
        fadeRunner.cancel(light: light)
        appEffects.cancel(light: light)
        sleepTimers.cancel(.light(light.id))
        central.forget(light)
        // Drop references so a user scene doesn't keep a dead entry and a schedule that targeted
        // only this light doesn't silently become "all lights" (empty targets).
        for index in scenes.indices where scenes[index].kind == .user {
            scenes[index].states.removeValue(forKey: light.id)
        }
        var schedulesChanged = false
        for index in schedules.indices where schedules[index].targets.contains(light.id) {
            schedules[index].targets.remove(light.id)
            if schedules[index].targets.isEmpty {
                schedules[index].isEnabled = false
                hueLog("Schedule “\(schedules[index].name)” disabled — its only light was forgotten", level: .warning)
            }
            schedulesChanged = true
        }
        if schedulesChanged { scheduler.schedulesDidChange() }
        if selection == .light(light.id) { selection = .allLights }
    }

    func light(id: UUID) -> HueLight? { central.light(id: id) }

    /// Moves every scene entry and schedule target from `oldID` to `newID`.
    private func migrateReferences(from oldID: UUID, to newID: UUID) {
        var updatedScenes = scenes
        var scenesChanged = false
        for index in updatedScenes.indices where updatedScenes[index].kind == .user {
            if let state = updatedScenes[index].states.removeValue(forKey: oldID) {
                updatedScenes[index].states[newID] = state
                scenesChanged = true
            }
        }
        if scenesChanged { scenes = updatedScenes }

        var updatedSchedules = schedules
        var schedulesChanged = false
        for index in updatedSchedules.indices {
            if updatedSchedules[index].targets.remove(oldID) != nil {
                updatedSchedules[index].targets.insert(newID)
                schedulesChanged = true
            }
        }
        if schedulesChanged {
            schedules = updatedSchedules
            scheduler.schedulesDidChange()
        }
    }

    // MARK: - Scenes

    var presetScenes: [HueScene] { scenes.filter(\.isPreset) }
    var userScenes: [HueScene] { scenes.filter { !$0.isPreset } }

    func scene(id: UUID) -> HueScene? { scenes.first { $0.id == id } }

    /// Applies a scene to `lights` (nil = every remembered light). Color states are converted to a
    /// color temperature for white-only bulbs.
    func apply(scene: HueScene, to lights: [HueLight]? = nil) {
        let targets = lights ?? self.lights
        hueLog("Applying scene “\(scene.name)” to \(targets.count) light(s)")
        for (index, light) in targets.enumerated() {
            guard let state = scene.state(for: light.id, index: index) else { continue }
            light.apply(adapt(state, for: light))
        }
    }

    @discardableResult
    func saveCurrentAsScene(named name: String) -> HueScene {
        var states: [UUID: LightState] = [:]
        for light in lights { states[light.id] = light.state }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scene = HueScene(name: trimmed.isEmpty ? "New Scene" : trimmed, kind: .user, symbol: "star", states: states)
        scenes.append(scene)
        hueLog("Saved scene “\(scene.name)” with \(states.count) light(s)")
        return scene
    }

    func renameScene(id: UUID, to name: String) {
        guard let index = scenes.firstIndex(where: { $0.id == id && $0.kind == .user }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        scenes[index].name = trimmed
    }

    func deleteScene(id: UUID) {
        scenes.removeAll { $0.id == id && $0.kind == .user }
    }

    // MARK: - Schedules

    // Schedules are "armed" at save time (lastFired = now) so a trigger time that already passed
    // today doesn't count as a missed occurrence inside the grace window and fire immediately.
    func addSchedule(_ schedule: Schedule) {
        var armed = schedule
        armed.lastFired = Date()
        schedules.append(armed)
        scheduler.schedulesDidChange()
    }

    func updateSchedule(_ schedule: Schedule) {
        var updated = schedule
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            if schedules[index].trigger != updated.trigger || schedules[index].action != updated.action {
                updated.lastFired = Date()
            }
            schedules[index] = updated
        } else {
            updated.lastFired = Date()
            schedules.append(updated)
        }
        scheduler.schedulesDidChange()
    }

    func deleteSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
        scheduler.schedulesDidChange()
    }

    func setSchedule(id: UUID, enabled: Bool) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isEnabled = enabled
        if enabled { schedules[index].lastFired = Date() }
        scheduler.schedulesDidChange()
    }

    // MARK: - App effects (Mac-driven)

    func toggleAppEffect(_ kind: AppEffectRunner.Kind, on targets: [HueLight]) {
        let ids = Set(targets.map(\.id))
        if let running = appEffects.running, running.kind == kind, Set(running.lightIDs) == ids {
            appEffects.stop(restore: true)
        } else {
            appEffects.start(kind, on: targets)
        }
    }

    func runNow(_ schedule: Schedule) {
        scheduler.runNow(schedule)
    }

    // MARK: - Sleep timers

    func lights(for target: SleepTimer.Target) -> [HueLight] {
        switch target {
        case .allLights: return lights
        case .light(let id): return light(id: id).map { [$0] } ?? []
        }
    }

    /// Starts (or replaces) a countdown for `target`: `.switchOff` keeps the lights as they are and
    /// switches them off at the end (after the configured `sleepTimerFadeSeconds` fade-out);
    /// `.dimToSleep` ramps the brightness down over the whole countdown, then off.
    func startSleepTimer(_ target: SleepTimer.Target, minutes: Int, mode: SleepTimer.Mode = .switchOff) {
        let duration = TimeInterval(max(1, minutes)) * 60
        sleepTimers.start(target, duration: duration, fadeSeconds: settings.sleepTimerFadeSeconds, mode: mode)
    }

    // MARK: - Settings

    /// Mutates a copy of the settings, applies the side effects of whatever changed, then persists.
    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        guard updated != settings else { return }
        let previous = settings
        settings = updated
        applySideEffects(from: previous, to: updated)
    }

    private func applySideEffects(from old: AppSettings?, to new: AppSettings) {
        central.keepAlive = new.keepLightsConnected
        sleepTimers.keepsMacAwake = new.keepMacAwakeForSleepTimers

        if new.keepMacAwakeWhileRunning {
            if sleepAssertion == nil {
                sleepAssertion = PowerManagement.SleepAssertion(reason: "OpenHue is keeping your lights connected")
            }
        } else if let assertion = sleepAssertion {
            assertion.release()
            sleepAssertion = nil
        }

        guard let old else { return }

        if old.launchAtLogin != new.launchAtLogin {
            do {
                try PowerManagement.LoginItem.setEnabled(new.launchAtLogin)
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
                hueLog("Login item change failed: \(error.localizedDescription)", level: .error)
                settings.launchAtLogin = PowerManagement.LoginItem.isEnabled   // keep the toggle honest
            }
        }

        // pmset runs `osascript … with administrator privileges`, which blocks until the admin
        // password dialog is dismissed — keep it off the main actor.
        if new.wakeMac.enabled {
            if old.wakeMac != new.wakeMac {
                let days = new.wakeMac.days, time = new.wakeMac.time
                runPmset("pmset wake schedule") { try PowerManagement.PmsetWake.apply(days: days, time: time) }
            }
        } else if old.wakeMac.enabled {
            runPmset("pmset wake cancel") { try PowerManagement.PmsetWake.cancel() }
        }
    }

    private func runPmset(_ label: String, _ work: @escaping @Sendable () throws -> Void) {
        Task.detached(priority: .userInitiated) {
            let result: String?
            do {
                try work()
                result = nil
            } catch {
                result = error.localizedDescription
            }
            await MainActor.run { [weak self] in
                self?.pmsetError = result
                if let result { hueLog("\(label) failed: \(result)", level: .error) }
                else { hueLog("\(label) applied", level: .info) }
            }
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(Store.directory)
    }

    // MARK: - SchedulerContext

    func lights(for schedule: Schedule) -> [HueLight] {
        schedule.targets.isEmpty ? lights : lights.filter { schedule.targets.contains($0.id) }
    }

    func resolve(_ target: LightTarget, for light: HueLight, index: Int) -> LightState? {
        switch target {
        case .state(let brightness, let color):
            return adapt(LightState(on: true, brightness: brightness, color: color), for: light)
        case .scene(let id):
            guard let state = scene(id: id)?.state(for: light.id, index: index) else { return nil }
            return adapt(state, for: light)
        }
    }

    /// Fits a state to what a bulb can actually show: xy → mireds on white-only bulbs, mireds clamped
    /// to the bulb's range, brightness clamped to 1...254.
    private func adapt(_ state: LightState, for light: HueLight) -> LightState {
        var fitted = state
        switch fitted.color {
        case .xy(let point) where !light.supportsColor:
            fitted.color = .ct(mireds: HueWire.clampMireds(ColorMath.approxMireds(fromXY: point), max: light.maxMireds))
        case .ct(let mireds):
            fitted.color = .ct(mireds: HueWire.clampMireds(mireds, max: light.maxMireds))
        default:
            break
        }
        fitted.brightness = HueWire.clampBrightness(fitted.brightness)
        return fitted
    }

    // MARK: - Persistence (debounced 500 ms per file)

    private func scheduleSave(_ file: Store.File) {
        pendingSaves[file]?.cancel()
        pendingSaves[file] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.pendingSaves[file] = nil
            self.performSave(file)
        }
    }

    private func performSave(_ file: Store.File) {
        switch file {
        case .lights: store.save(central.knownLights, to: .lights)
        case .scenes: store.save(userScenes, to: .scenes)
        case .schedules: store.save(schedules, to: .schedules)
        case .settings: store.save(settings, to: .settings)
        case .sleepTimers: store.save(sleepTimers.timers, to: .sleepTimers)
        }
    }

    /// Writes everything that is still debounced. Called on quit.
    func flushPendingSaves() {
        let pending = pendingSaves
        pendingSaves = [:]
        for (file, task) in pending {
            task.cancel()
            performSave(file)
        }
    }
}
