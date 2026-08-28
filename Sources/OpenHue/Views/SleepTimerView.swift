import SwiftUI

// MARK: - Timer page

/// One countdown for All Lights plus one per bulb. Each card owns a `TimeDial` and a mode:
/// **Timer** switches the lights off when the countdown ends, **Sleep** dims them down over the
/// whole countdown first. The runner (`model.sleepTimers`) does the work.
struct SleepTimerView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]
    private let tint = Color.indigo

    var body: some View {
        Group {
            if model.lights.isEmpty {
                EmptyStateView("No lights yet", systemImage: "timer",
                               description: "Pair a Hue Bluetooth bulb first — then set a countdown here and it switches off (or dims you to sleep) when the time is up.") {
                    Button("Add Light…", systemImage: "plus") { model.isDiscoveryPresented = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                content
            }
        }
        .navigationTitle("Timer")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                SleepTimerCard(target: .allLights, layout: .wide, tint: tint) {
                    Image(systemName: "lightbulb.2")
                        .foregroundStyle(.secondary)
                    Text("All Lights")
                        .font(.headline)
                    Text("\(model.readyLights.count) of \(model.lights.count) connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.lights) { light in
                        LightSleepTimerCard(light: light, tint: tint)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timer")
                    .font(.largeTitle.weight(.bold))
                Text("Lights switch off when the countdown ends — or dim down to it in Sleep mode. Runs on this Mac; keep OpenHue open.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .trailing, spacing: 3) {
                FadeOutPicker(label: "Fade out")
                Text("Timer mode: dims the lights down just before switching off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }
}

// MARK: - Fade-out picker (shared with Settings)

struct FadeOutPicker: View {
    @EnvironmentObject private var model: AppModel
    let label: String

    static let options: [(seconds: TimeInterval, title: String)] = [
        (0, "Off"), (30, "30 s"), (60, "1 min"), (300, "5 min"), (900, "15 min"), (1800, "30 min"),
    ]

    var body: some View {
        Picker(label, selection: Binding(
            get: { model.settings.sleepTimerFadeSeconds },
            set: { value in model.updateSettings { $0.sleepTimerFadeSeconds = value } }
        )) {
            ForEach(Self.options, id: \.seconds) { option in
                Text(option.title).tag(option.seconds)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Per-light card

private struct LightSleepTimerCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var light: HueLight
    let tint: Color

    var body: some View {
        SleepTimerCard(target: .light(light.id), layout: .compact, tint: tint) {
            StatusDot(connection: light.connection)
            Circle()
                .fill(light.state.displayColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .opacity(light.state.on ? 1 : 0.35)
            Text(light.name)
                .font(.headline)
                .lineLimit(1)
            Text(light.state.on ? "On" : "Off")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Card

/// 5 min … 8 h, as David asked: short steps first, then the longer evening ones.
private let sleepTimerPresets: [(minutes: Int, title: String)] = [
    (5, "5m"), (10, "10m"), (15, "15m"), (30, "30m"), (45, "45m"), (60, "1h"),
    (90, "1h 30"), (120, "2h"), (180, "3h"), (240, "4h"), (360, "6h"), (480, "8h"),
]

private struct SleepTimerCard<Leading: View>: View {
    enum Layout { case wide, compact }

    @EnvironmentObject private var model: AppModel
    let target: SleepTimer.Target
    let layout: Layout
    let tint: Color
    @ViewBuilder let leading: () -> Leading

    @State private var minutes = 20
    @State private var mode: SleepTimer.Mode = .switchOff
    @State private var showsCustom = false

    /// The mode shown by the segmented control: the running timer's while one runs.
    private var shownMode: Binding<SleepTimer.Mode> {
        Binding(get: { running?.mode ?? mode }, set: { mode = $0 })
    }

    private var presetList: [(minutes: Int, title: String)] { sleepTimerPresets }
    /// Six chips per row beside the big dial, four per row in a bulb card (3 × 4 = the 12 presets).
    private var chipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: layout == .wide ? 56 : 64, maximum: 92), spacing: 6)]
    }

    private var running: SleepTimer? { model.sleepTimers.timer(for: target) }
    /// The all-lights countdown, when this card is a single light that it will also switch off.
    private var groupTimer: SleepTimer? {
        target == .allLights ? nil : model.sleepTimers.timer(for: .allLights)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                leading()
                Spacer(minLength: 8)
                if let running {
                    OffAtPill(timer: running, tint: tint)
                }
            }

            switch layout {
            case .wide:
                HStack(alignment: .center, spacing: 24) {
                    TimeDial(minutes: $minutes, running: running, diameter: 240, tint: tint)
                    VStack(alignment: .leading, spacing: 12) {
                        modePicker
                        presetsHeader
                        presets
                        actions
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .compact:
                VStack(spacing: 12) {
                    modePicker
                    TimeDial(minutes: $minutes, running: running, diameter: 180, tint: tint)
                    presetsHeader
                    presets
                    actions
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            }

            if let groupTimer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label("Also off with All Lights in \(SleepTimerRunner.countdownText(groupTimer.remaining(at: context.date)))",
                          systemImage: "lightbulb.2")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    /// Timer (off at the end) vs. Sleep (dim down over the whole countdown, then off).
    private var modePicker: some View {
        Picker("Mode", selection: shownMode) {
            ForEach(SleepTimer.Mode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(running != nil)
        .help("Timer switches the lights off when the countdown ends; Sleep dims them down over the whole countdown first")
    }

    private var presetsTitle: String {
        switch (shownMode.wrappedValue, running != nil) {
        case (.switchOff, false): return "Turn off in"
        case (.switchOff, true): return "Turning off in"
        case (.dimToSleep, false): return "Dim to sleep over"
        case (.dimToSleep, true): return "Dimming to sleep over"
        }
    }

    /// "Turn off in … Custom…" row above the chips.
    private var presetsHeader: some View {
        HStack {
            Text(presetsTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Custom…") { showsCustom = true }
                .buttonStyle(.plain)
                .font(.subheadline.weight(isCustomValue ? .semibold : .regular))
                .foregroundStyle(isCustomValue ? tint : Color.accentColor)
                .popover(isPresented: $showsCustom, arrowEdge: .bottom) {
                    CustomDurationPopover(minutes: $minutes)
                }
                .help("Set any duration up to 12 hours")
        }
        .disabled(running != nil)
        .opacity(running != nil ? 0.45 : 1)
    }

    private var presets: some View {
        GlassGroup(spacing: 6) {
            LazyVGrid(columns: chipColumns, spacing: 6) {
                ForEach(presetList, id: \.minutes) { preset in
                    GlassChip(title: preset.title, selected: minutes == preset.minutes, tint: tint) {
                        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { minutes = preset.minutes }
                    }
                }
            }
        }
        .disabled(running != nil)
        .opacity(running != nil ? 0.45 : 1)
    }

    private var isCustomValue: Bool {
        minutes > 0 && !presetList.contains { $0.minutes == minutes }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if running != nil {
                Button {
                    model.sleepTimers.extend(target, by: 5 * 60)
                } label: {
                    Label("+5 min", systemImage: "plus")
                        .frame(minWidth: 72)
                }
                .glassButton()
                .help("Push the countdown out by five minutes")

                Button {
                    model.sleepTimers.cancel(target)
                } label: {
                    Text("Cancel")
                        .frame(minWidth: 72)
                }
                .glassButton()
            } else {
                Button {
                    model.startSleepTimer(target, minutes: minutes, mode: mode)
                } label: {
                    Label(mode == .dimToSleep ? "Start Sleep" : "Start",
                          systemImage: mode == .dimToSleep ? "moon.zzz.fill" : "timer")
                        .frame(minWidth: 96)
                }
                .prominentGlassButton()
                .tint(tint)
                .disabled(minutes == 0)
                .help(startHelp)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: layout == .compact ? .infinity : nil, alignment: .center)
    }

    private var startHelp: String {
        guard minutes > 0 else { return "Turn the dial to set a duration" }
        let text = SleepTimerRunner.durationText(TimeInterval(minutes) * 60)
        return mode == .dimToSleep ? "Dim down over \(text), then switch off" : "Switch off in \(text)"
    }
}

// MARK: - Pieces

private struct OffAtPill: View {
    let timer: SleepTimer
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: timer.mode == .dimToSleep ? "moon.zzz.fill" : "timer")
                .font(.caption2)
            Text(timer.mode == .dimToSleep ? "Dimming · off at " : "Off at ") + Text(timer.endsAt, format: .dateTime.hour().minute())
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
        .fixedSize()
    }
}

private struct CustomDurationPopover: View {
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var mins: Int

    init(minutes: Binding<Int>) {
        _minutes = minutes
        _hours = State(initialValue: min(12, minutes.wrappedValue / 60))
        _mins = State(initialValue: minutes.wrappedValue % 60)
    }

    private var total: Int { min(TimeDial.maxMinutes, max(0, hours * 60 + mins)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom duration")
                .font(.headline)
            HStack(spacing: 18) {
                field("hours", value: $hours, range: 0...12)
                field("min", value: $mins, range: 0...59)
            }
            HStack {
                Text(SleepTimerRunner.durationText(TimeInterval(total) * 60))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Set") {
                    minutes = max(1, total)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(total == 0)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func field(_ unit: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .onChange(of: value.wrappedValue) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value.wrappedValue = clamped }
                }
            Stepper("", value: value, in: range)
                .labelsHidden()
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
