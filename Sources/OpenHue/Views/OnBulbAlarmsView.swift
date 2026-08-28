import SwiftUI

// MARK: - "On the bulb" section

/// Alarms stored in a bulb's own memory. They fire on the bulb's clock — no Mac, no phone needed.
struct OnBulbAlarmsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var light: HueLight
    @ObservedObject var alarms: HueAlarmClient
    @State private var showEditor = false
    @State private var pendingDelete: HueAlarm?

    init(light: HueLight) {
        self.light = light
        self.alarms = light.alarms
    }

    var body: some View {
        Section {
            if !light.connection.isReady {
                placeholder("Connect “\(light.name)” to read the schedules stored on it.", systemImage: "antenna.radiowaves.left.and.right.slash")
            } else if alarms.status == .unsupported {
                placeholder("This bulb has no schedule storage.", systemImage: "questionmark.circle")
            } else if alarms.alarms.isEmpty {
                placeholder(alarms.lastRefreshed == nil ? "Reading the bulb's schedules…" : "Nothing stored on this bulb yet.", systemImage: "clock.badge.questionmark")
            } else {
                ForEach(alarms.alarms) { alarm in
                    OnBulbAlarmRow(light: light, alarm: alarm,
                                   isRepeating: model.isRepeating(alarm.uuid),
                                   onDelete: { pendingDelete = alarm })
                }
            }
            if let outcome = alarms.lastOutcome, Date().timeIntervalSince(outcome.at) < 120 {
                Label(outcome.message, systemImage: outcome.isError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(outcome.isError ? Color.red : Color.secondary)
            } else if case .error(let message) = alarms.status {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            HStack(spacing: 8) {
                Text("On the bulb · \(light.name)")
                if case .busy(let what) = alarms.status {
                    ProgressView().controlSize(.mini)
                    Text(what).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    alarms.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-read the bulb's schedules")
                .disabled(!light.connection.isReady || alarms.isBusy)
                Button {
                    showEditor = true
                } label: {
                    Label("Add to Bulb", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Store a new schedule on this bulb")
                .disabled(!light.connection.isReady || alarms.status == .unsupported)
            }
        }
        .sheet(isPresented: $showEditor) {
            OnBulbAlarmEditor(light: light)
                .environmentObject(model)
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")” from \(light.name)?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { alarm in
            Button("Delete from Bulb", role: .destructive) { model.deleteOnBulbAlarm(alarm, on: light) }
        } message: { _ in
            Text("The bulb forgets this schedule. This can't be undone.")
        }
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

// MARK: - Row

private struct OnBulbAlarmRow: View {
    @EnvironmentObject private var model: AppModel
    let light: HueLight
    let alarm: HueAlarm
    let isRepeating: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Armed", isOn: Binding(
                get: { alarm.isEnabled },
                set: { light.alarms.setEnabled(alarm, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.top, 2)
            .help(alarm.isEnabled ? "Armed — the bulb fires it once, then disarms it" : "Disarmed — switch on to arm it for the next occurrence")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alarm.name.isEmpty ? "Untitled" : alarm.name).font(.headline)
                    if isRepeating {
                        Label("Daily", systemImage: "repeat")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                            .help("OpenHue re-arms this schedule for the next day whenever it is connected")
                    }
                    if alarm.isTimer {
                        Text("Timer").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(OnBulbText.action(alarm))
                Text(OnBulbText.fires(alarm))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(alarm.isEnabled ? 1 : 0.6)

            Spacer(minLength: 8)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        if !alarm.isTimer {
            Toggle("Re-arm Every Day", isOn: Binding(
                get: { isRepeating },
                set: { model.setRepeating(alarm.uuid, $0, light: light) }
            ))
        }
        Button(alarm.isEnabled ? "Disarm" : "Arm for Next Occurrence") { light.alarms.setEnabled(alarm, !alarm.isEnabled) }
        Divider()
        Button("Delete from Bulb…", role: .destructive, action: onDelete)
    }
}

// MARK: - Editor

/// Stores a new alarm on the bulb: name, time, what the light should do.
struct OnBulbAlarmEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let light: HueLight

    private enum Kind: String, CaseIterable, Identifiable {
        case turnOn, turnOff
        var id: String { rawValue }
        var title: String { self == .turnOn ? "Turn on" : "Turn off" }
    }

    private enum Warmth: Double, CaseIterable, Identifiable {
        case warm = 2700, neutral = 4000, cool = 5500
        var id: Double { rawValue }
        var title: String {
            switch self {
            case .warm: return "Warm"
            case .neutral: return "Neutral"
            case .cool: return "Cool"
            }
        }
    }

    @State private var name = "Wake up"
    @State private var time = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var kind: Kind = .turnOn
    @State private var brightness: Double = 254
    @State private var warmth: Warmth = .warm
    @State private var fadeMinutes = 0
    @State private var repeatsDaily = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to \(light.name)").font(.title2.weight(.semibold))
                Text("Stored in the bulb's own memory and fired by its clock — this Mac and the phone can both be off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Form {
                TextField("Name", text: $name)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Picker("Action", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if kind == .turnOn {
                    LabeledContent("Brightness") {
                        HStack {
                            Slider(value: $brightness, in: 1...254)
                            Text("\(percent)%").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                    if light.supportsColor || true {
                        Picker("Warmth", selection: $warmth) {
                            ForEach(Warmth.allCases) { Text("\($0.title) · \(Int($0.rawValue)) K").tag($0) }
                        }
                    }
                    Stepper(value: $fadeMinutes, in: 0...60, step: 5) {
                        LabeledContent("Fade in", value: fadeMinutes == 0 ? "Instant" : "\(fadeMinutes) min")
                    }
                }
                Toggle(isOn: $repeatsDaily) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Re-arm every day")
                        Text("The bulb fires a schedule once, then disarms it. OpenHue re-arms it for the next day whenever it is connected to the bulb.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Text(preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save to Bulb") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var percent: Int { max(1, Int((Double(max(Int(brightness) - 1, 0)) / 253 * 100).rounded())) }

    /// Next occurrence of the chosen clock time (today if still ahead, else tomorrow).
    private var fireTime: Date {
        let now = Date()
        let hm = HourMinute(date: time)
        var next = hm.date(on: now)
        if next <= now.addingTimeInterval(60) { next = Calendar.current.date(byAdding: .day, value: 1, to: next) ?? next }
        return next
    }

    private var fadeSeconds: TimeInterval { kind == .turnOn ? TimeInterval(fadeMinutes * 60) : 0 }

    private var preview: String {
        let when = fireTime.formatted(.dateTime.weekday(.wide).hour().minute())
        let fade = fadeSeconds > 0 ? " (fade starts \(fireTime.addingTimeInterval(-fadeSeconds).formatted(.dateTime.hour().minute())))" : ""
        return "Fires \(when)\(fade)."
    }

    private func save() {
        let action: HueAlarm.Action
        switch kind {
        case .turnOff:
            action = HueAlarm.lightStateAction(on: false)
        case .turnOn:
            let mireds = HueWire.clampMireds(ColorMath.mireds(fromKelvin: warmth.rawValue), max: light.maxMireds)
            action = HueAlarm.lightStateAction(on: true, brightness: UInt8(clamping: Int(brightness.rounded())),
                                               color: .ct(mireds: mireds), transition: fadeSeconds > 0 ? fadeSeconds : nil)
        }
        let alarm = HueAlarm.make(name: name.trimmingCharacters(in: .whitespaces),
                                  fireAt: fireTime.addingTimeInterval(-fadeSeconds), action: action)
        model.createOnBulbAlarm(alarm, on: light, repeatsDaily: repeatsDaily)
        dismiss()
    }
}

// MARK: - Text

enum OnBulbText {
    static func action(_ alarm: HueAlarm) -> String {
        switch alarm.action {
        case .simple(let code):
            let what = code == 0x02 ? "off" : code == 0x01 ? "on" : "action \(code)"
            if let d = alarm.durationSeconds { return "Countdown \(SleepTimerRunner.durationText(TimeInterval(d))) → \(what)" }
            return "Turn \(what)"
        case .lightState:
            guard let state = alarm.lightState else { return "Light state" }
            guard state.on else { return "Turn off" }
            var parts = ["Turn on"]
            parts.append("\(max(1, Int((Double(max(Int(state.brightness) - 1, 0)) / 253 * 100).rounded())))%")
            if case .ct(let m) = state.color { parts.append("\(Int(ColorMath.kelvin(fromMireds: m).rounded())) K") }
            if let t = alarm.transitionSeconds, t > 0 { parts.append("fade \(SleepTimerRunner.durationText(t))") }
            if case .lightState(let tlv) = alarm.action, let effect = HueTLV.parse(tlv)[0x06]?.first, effect == 0x09 {
                parts.append("sunrise")
            }
            return parts.joined(separator: " · ")
        case .unknown(let type, let payload):
            return "Unknown action \(type): \(payload.hexString)"
        }
    }

    static func fires(_ alarm: HueAlarm) -> String {
        let end = alarm.fireAt.addingTimeInterval(alarm.transitionSeconds ?? 0)
        let when = end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        if alarm.isEnabled {
            return end < Date() ? "Was set for \(when) — the bulb's clock may be off" : "Fires \(when)"
        }
        return "Disarmed · last set for \(when)"
    }
}
