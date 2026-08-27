import SwiftUI
import AppKit

// MARK: - Schedules list

struct SchedulesView: View {
    @EnvironmentObject var model: AppModel

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let schedule: Schedule?
    }

    @State private var editor: EditorRequest?
    @State private var pendingDelete: Schedule?

    var body: some View {
        VStack(spacing: 0) {
            HueInfoCallout("Schedules run on this Mac — it must be awake, openHue running, and the bulbs in range.") {
                SettingsLink { Text("Settings…") }
                    .controlSize(.small)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

            if model.schedules.isEmpty {
                EmptyStateView("No Schedules", systemImage: "clock",
                               description: "Add a wake-up fade, a bedtime fade-out, or a simple on/off timer.") {
                    Button("Add Schedule") { editor = EditorRequest(schedule: nil) }
                }
            } else {
                List {
                    ForEach(model.schedules) { schedule in
                        Row(
                            schedule: schedule,
                            scheduler: model.scheduler,
                            onEdit: { editor = EditorRequest(schedule: schedule) },
                            onRunNow: { model.runNow(schedule) },
                            onDuplicate: { duplicate(schedule) },
                            onDelete: { pendingDelete = schedule }
                        )
                    }
                }
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editor = EditorRequest(schedule: nil) } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                .help("Add a schedule")
            }
        }
        .sheet(item: $editor) { request in
            ScheduleEditorView(schedule: request.schedule) { saved in
                if request.schedule == nil {
                    model.addSchedule(saved)
                } else {
                    model.updateSchedule(saved)
                }
            }
            .environmentObject(model)
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { schedule in
            Button("Delete", role: .destructive) { model.deleteSchedule(id: schedule.id) }
        } message: { _ in
            Text("This schedule will be removed. This can't be undone.")
        }
    }

    private func duplicate(_ schedule: Schedule) {
        var copy = schedule
        copy.id = UUID()
        copy.name = schedule.name + " copy"
        model.addSchedule(copy)
    }
}

// MARK: - Row

extension SchedulesView {
    struct Row: View {
        @EnvironmentObject var model: AppModel
        let schedule: Schedule
        @ObservedObject var scheduler: Scheduler
        let onEdit: () -> Void
        let onRunNow: () -> Void
        let onDuplicate: () -> Void
        let onDelete: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Toggle("Enabled", isOn: Binding(
                    get: { schedule.isEnabled },
                    set: { model.setSchedule(id: schedule.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(schedule.name).font(.headline)
                        if scheduler.running.contains(schedule.id) {
                            ProgressView().controlSize(.small)
                            Text("Running…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(ScheduleText.action(schedule.action, scenes: model.scenes))
                    Text("\(ScheduleText.trigger(schedule.trigger)) · \(targetsSummary)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    statusLines
                }
                .opacity(schedule.isEnabled ? 1 : 0.6)

                Spacer(minLength: 8)

                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Schedule actions")
            }
            .padding(.vertical, 6)
            .contextMenu { actions }
        }

        @ViewBuilder private var actions: some View {
            Button("Edit…", action: onEdit)
            Button("Run Now", action: onRunNow)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }

        @ViewBuilder private var statusLines: some View {
            if let next = scheduler.nextFire(for: schedule) {
                Text("Next: \(ScheduleText.nextFire(next))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if schedule.isEnabled {
                Text(expiredText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let outcome = scheduler.lastOutcome[schedule.id] {
                Text(outcome)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }

        private var expiredText: String {
            switch schedule.trigger {
            case .once: return "Already passed — won't fire again"
            case .weekly(let days, _): return days.isEmpty ? "No days selected" : "Not scheduled"
            }
        }

        private var targetsSummary: String {
            if schedule.targets.isEmpty { return "All lights" }
            let names = schedule.targets
                .compactMap { model.light(id: $0)?.name }
                .sorted()
            if names.isEmpty { return "Unknown lights" }
            return names.joined(separator: ", ")
        }
    }
}

// MARK: - Text formatting

/// Human-readable summaries shared by the list and the editor preview.
enum ScheduleText {
    static func action(_ action: ScheduleAction, scenes: [HueScene]) -> String {
        switch action {
        case .turnOff:
            return "Turn off"
        case .turnOn(let t):
            return "Turn on → \(target(t, scenes: scenes))"
        case .wakeUp(let minutes, let t):
            return "Wake up over \(minutes) min → \(target(t, scenes: scenes))"
        case .goToSleep(let minutes):
            return "Go to sleep over \(minutes) min"
        }
    }

    static func target(_ target: LightTarget, scenes: [HueScene]) -> String {
        switch target {
        case .scene(let id):
            return scenes.first { $0.id == id }?.name ?? "Missing scene"
        case .state(let brightness, let color):
            let pct = Int((Double(max(1, brightness) - 1) / 253.0 * 100).rounded())
            switch color {
            case .ct(let mireds):
                let kelvin = ColorMath.kelvin(fromMireds: mireds)
                let tone = kelvin < 3300 ? "warm white" : (kelvin > 5000 ? "cool white" : "white")
                return "\(pct)% \(tone)"
            case .xy:
                return "\(pct)% color"
            }
        }
    }

    static func trigger(_ trigger: ScheduleTrigger) -> String {
        switch trigger {
        case .weekly(let days, let time):
            return "\(self.days(days)) \(time.formatted)"
        case .once(let date):
            return "Once · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    /// "Every day", "Mon–Fri", "Weekends", "Mon, Wed, Fri", "Mon–Thu, Sat".
    static func days(_ days: Set<Weekday>) -> String {
        if days.isEmpty { return "No days" }
        if days == Weekday.everyday { return "Every day" }
        if days == Weekday.weekdays { return "Mon–Fri" }
        if days == [.saturday, .sunday] { return "Weekends" }
        var groups: [[Weekday]] = []
        for day in days.sorted() {
            if let last = groups.last?.last, last.rawValue + 1 == day.rawValue {
                groups[groups.count - 1].append(day)
            } else {
                groups.append([day])
            }
        }
        return groups.map { group -> String in
            if group.count >= 3, let first = group.first, let last = group.last {
                return "\(first.shortName)–\(last.shortName)"
            }
            return group.map(\.shortName).joined(separator: ", ")
        }
        .joined(separator: ", ")
    }

    /// "Thu 6:55 AM (in 9 hours)" — adds the date when more than a week away.
    static func nextFire(_ date: Date, now: Date = Date()) -> String {
        let absolute: String
        if date.timeIntervalSince(now) < 6 * 86_400 {
            absolute = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        } else {
            absolute = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        relative.dateTimeStyle = .named
        return "\(absolute) (\(relative.localizedString(for: date, relativeTo: now)))"
    }
}

// MARK: - Editor

struct ScheduleEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum TriggerKind: Hashable { case weekly, once }
    private enum ActionKind: Hashable { case turnOn, turnOff, wakeUp, goToSleep }
    private enum TargetKind: Hashable { case scene, custom }
    private enum ColorKind: Hashable { case white, color }

    private let existing: Schedule?
    private let onSave: (Schedule) -> Void

    @State private var name: String
    @State private var triggerKind: TriggerKind
    @State private var days: Set<Weekday>
    @State private var time: Date
    @State private var onceDate: Date
    @State private var allLights: Bool
    @State private var targets: Set<UUID>
    @State private var actionKind: ActionKind
    @State private var targetKind: TargetKind
    @State private var sceneID: UUID
    @State private var brightness: Double
    @State private var colorKind: ColorKind
    @State private var kelvin: Double
    @State private var pickerColor: Color
    @State private var wakeMinutes: Int
    @State private var sleepMinutes: Int

    init(schedule: Schedule?, onSave: @escaping (Schedule) -> Void) {
        self.existing = schedule
        self.onSave = onSave

        let base = schedule ?? Schedule(
            name: "Morning",
            trigger: .weekly(days: Weekday.weekdays, time: HourMinute(hour: 6, minute: 55)),
            action: .wakeUp(minutes: 30, target: .scene(Presets.energize.id))
        )

        var triggerKind = TriggerKind.weekly
        var days = Weekday.weekdays
        var time = HourMinute(hour: 6, minute: 55).date()
        var onceDate = Date().addingTimeInterval(3600)
        switch base.trigger {
        case .weekly(let d, let t):
            triggerKind = .weekly
            days = d
            time = t.date()
        case .once(let date):
            triggerKind = .once
            onceDate = date
        }

        var actionKind = ActionKind.turnOn
        var target: LightTarget?
        var wakeMinutes = 30
        var sleepMinutes = 15
        switch base.action {
        case .turnOff:
            actionKind = .turnOff
        case .turnOn(let t):
            actionKind = .turnOn
            target = t
        case .wakeUp(let minutes, let t):
            actionKind = .wakeUp
            wakeMinutes = minutes
            target = t
        case .goToSleep(let minutes):
            actionKind = .goToSleep
            sleepMinutes = minutes
        }

        var targetKind = TargetKind.scene
        var sceneID = Presets.energize.id
        var brightness = 254.0
        var colorKind = ColorKind.white
        var kelvin = 2700.0
        var pickerColor = Color(ColorMath.rgb(fromXY: XY(x: 0.5, y: 0.4)))
        switch target {
        case .scene(let id):
            targetKind = .scene
            sceneID = id
        case .state(let b, let c):
            targetKind = .custom
            brightness = Double(b)
            switch c {
            case .ct(let mireds):
                colorKind = .white
                kelvin = min(max(ColorMath.kelvin(fromMireds: mireds), ColorMath.minKelvin), ColorMath.maxKelvin)
            case .xy(let point):
                colorKind = .color
                pickerColor = Color(ColorMath.rgb(fromXY: point))
            }
        case nil:
            break
        }

        _name = State(initialValue: base.name)
        _triggerKind = State(initialValue: triggerKind)
        _days = State(initialValue: days)
        _time = State(initialValue: time)
        _onceDate = State(initialValue: onceDate)
        _allLights = State(initialValue: base.targets.isEmpty)
        _targets = State(initialValue: base.targets)
        _actionKind = State(initialValue: actionKind)
        _targetKind = State(initialValue: targetKind)
        _sceneID = State(initialValue: sceneID)
        _brightness = State(initialValue: brightness)
        _colorKind = State(initialValue: colorKind)
        _kelvin = State(initialValue: kelvin)
        _pickerColor = State(initialValue: pickerColor)
        _wakeMinutes = State(initialValue: wakeMinutes)
        _sleepMinutes = State(initialValue: sleepMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                }

                Section("When") {
                    Picker("Repeat", selection: $triggerKind) {
                        Text("Weekly").tag(TriggerKind.weekly)
                        Text("Once").tag(TriggerKind.once)
                    }
                    .pickerStyle(.segmented)

                    switch triggerKind {
                    case .weekly:
                        LabeledContent("Days") {
                            HueWeekdayPicker(days: $days)
                        }
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    case .once:
                        DatePicker("Date & time", selection: $onceDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Lights") {
                    Toggle("All lights", isOn: $allLights)
                    if !allLights {
                        if model.lights.isEmpty {
                            Text("No lights added yet.").foregroundStyle(.secondary)
                        }
                        ForEach(model.lights) { light in
                            Toggle(light.name, isOn: Binding(
                                get: { targets.contains(light.id) },
                                set: { on in
                                    if on { targets.insert(light.id) } else { targets.remove(light.id) }
                                }
                            ))
                        }
                    }
                }

                Section("Action") {
                    Picker("Action", selection: $actionKind) {
                        Text("Turn on").tag(ActionKind.turnOn)
                        Text("Turn off").tag(ActionKind.turnOff)
                        Text("Wake up (fade in)").tag(ActionKind.wakeUp)
                        Text("Go to sleep (fade out)").tag(ActionKind.goToSleep)
                    }

                    if actionKind == .wakeUp {
                        Stepper("Fade in over \(wakeMinutes) min", value: $wakeMinutes, in: 1...120)
                        Text("Starts dim and warm, then brightens to the target below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if actionKind == .goToSleep {
                        Stepper("Fade out over \(sleepMinutes) min", value: $sleepMinutes, in: 1...120)
                        Text("Dims to the warmest, dimmest setting, then switches the lights off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if actionKind == .turnOn || actionKind == .wakeUp {
                        targetForm
                    }
                }

                Section {
                    LabeledContent("Next fires") {
                        Text(nextFirePreview).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 480, height: 620)
        .onAppear {
            // A referenced scene may have been deleted; fall back to the first one so the picker isn't blank.
            if !model.scenes.contains(where: { $0.id == sceneID }), let first = model.scenes.first {
                sceneID = first.id
            }
        }
    }

    @ViewBuilder private var targetForm: some View {
        Picker("Target", selection: $targetKind) {
            Text("Scene").tag(TargetKind.scene)
            Text("Custom").tag(TargetKind.custom)
        }
        .pickerStyle(.segmented)

        switch targetKind {
        case .scene:
            Picker("Scene", selection: $sceneID) {
                ForEach(model.scenes) { scene in
                    Text(scene.name).tag(scene.id)
                }
            }
        case .custom:
            LabeledContent("Brightness \(brightnessPercent)%") {
                Slider(value: $brightness, in: 1...254, step: 1)
            }
            Picker("Color", selection: $colorKind) {
                Text("White").tag(ColorKind.white)
                Text("Color").tag(ColorKind.color)
            }
            .pickerStyle(.segmented)

            switch colorKind {
            case .white:
                LabeledContent("\(Int(kelvin)) K") {
                    Slider(value: $kelvin, in: ColorMath.minKelvin...ColorMath.maxKelvin, step: 50) {
                        Text("Temperature")
                    } minimumValueLabel: {
                        Text("Warm").font(.caption)
                    } maximumValueLabel: {
                        Text("Cool").font(.caption)
                    }
                }
            case .color:
                ColorPicker("Color", selection: $pickerColor, supportsOpacity: false)
            }

            LabeledContent("Preview") {
                RoundedRectangle(cornerRadius: 4)
                    .fill(previewColor)
                    .frame(width: 64, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            }
        }
    }

    // MARK: Derived values

    private var brightnessPercent: Int {
        Int(((brightness - 1) / 253.0 * 100).rounded())
    }

    private var colorMode: ColorMode {
        switch colorKind {
        case .white:
            return .ct(mireds: ColorMath.mireds(fromKelvin: kelvin))
        case .color:
            return .xy(ColorMath.xy(fromRGB: Self.rgb(from: pickerColor)))
        }
    }

    private var previewColor: Color {
        Color(colorMode.displayRGB)
    }

    private var trigger: ScheduleTrigger {
        switch triggerKind {
        case .weekly: return .weekly(days: days, time: HourMinute(date: time))
        case .once: return .once(onceDate)
        }
    }

    private var lightTarget: LightTarget {
        switch targetKind {
        case .scene:
            return .scene(sceneID)
        case .custom:
            return .state(brightness: HueWire.clampBrightness(UInt8(clamping: Int(brightness.rounded()))), color: colorMode)
        }
    }

    private var action: ScheduleAction {
        switch actionKind {
        case .turnOn: return .turnOn(lightTarget)
        case .turnOff: return .turnOff
        case .wakeUp: return .wakeUp(minutes: wakeMinutes, target: lightTarget)
        case .goToSleep: return .goToSleep(minutes: sleepMinutes)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draft: Schedule {
        var schedule = existing ?? Schedule(name: trimmedName, trigger: trigger, action: action)
        schedule.name = trimmedName
        schedule.trigger = trigger
        schedule.targets = allLights ? [] : targets
        schedule.action = action
        return schedule
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && (triggerKind == .once || !days.isEmpty) && (allLights || !targets.isEmpty)
    }

    private var nextFirePreview: String {
        if triggerKind == .weekly && days.isEmpty { return "Pick at least one day" }
        guard let next = draft.nextFire(after: Date()) else {
            return triggerKind == .once ? "In the past — won't fire" : "—"
        }
        return ScheduleText.nextFire(next)
    }

    private static func rgb(from color: Color) -> RGB {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        return RGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }
}

// MARK: - Shared controls

/// Seven circular day buttons in Sun…Sat order.
struct HueWeekdayPicker: View {
    @Binding var days: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let selected = days.contains(day)
                Button {
                    if selected { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(selected ? Color.accentColor : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(day.shortName)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Subtle informational callout with an optional trailing accessory (e.g. a `SettingsLink`).
struct HueInfoCallout<Accessory: View>: View {
    let text: String
    private let accessory: () -> Accessory

    init(_ text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

extension HueInfoCallout where Accessory == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}
