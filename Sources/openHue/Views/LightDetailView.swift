import SwiftUI

// MARK: - Single light

@MainActor
struct LightDetailView: View {
    @ObservedObject var light: HueLight
    @EnvironmentObject private var model: AppModel

    @State private var draftName: String
    @FocusState private var nameFocused: Bool
    @State private var pairingTick = 0
    @State private var confirmForget = false

    init(light: HueLight) {
        self.light = light
        _draftName = State(initialValue: light.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let fade = model.fadeRunner.active[light.id] {
                    fadeBanner(fade)
                }
                if showsPairingHelp {
                    pairingCallout
                }
                if light.connection == .unavailable(.needsRescan) {
                    rescanNote
                }
                LightControlsView(target: .light(light))
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task(id: light.connection) { await armPairingTimer() }
        .confirmationDialog("Forget “\(light.name)”?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget Light", role: .destructive) { model.forgetLight(light) }
        } message: {
            Text("The pairing on this Mac is removed. The bulb keeps its own settings and can be added again later.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(light.state.displayColor)
                Image(systemName: light.state.on ? "lightbulb.fill" : "lightbulb")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 56, height: 56)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                TextField("Light name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                    .onChange(of: light.name) { _, name in
                        if !nameFocused { draftName = name }
                    }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    StatusDot(connection: light.connection)
                    Text(light.connection.label)
                        .font(.subheadline)
                        .foregroundStyle(light.connection.isReady ? .primary : .secondary)
                    if light.connection.isBusy {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    if let rssi = light.rssi {
                        Text("· \(rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 12)

            Button("Identify", systemImage: "lightbulb.max") { light.identify() }
                .disabled(!light.connection.isReady)
                .help("Flash this bulb once")

            Menu {
                if light.connection.isConnectedOrBusy {
                    Button("Disconnect") { model.central.disconnect(light) }
                } else {
                    Button("Connect") { model.central.connect(light) }
                }
                Button("Refresh State") { light.refresh() }
                    .disabled(!light.connection.isReady)
                Divider()
                Button("Forget Light…", role: .destructive) { confirmForget = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }

    private var subtitle: String? {
        let parts = [light.info.model, light.info.firmware].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = light.name
            return
        }
        guard trimmed != light.name else { return }
        light.rename(trimmed)
    }

    // MARK: Callouts

    private func fadeBanner(_ progress: FadeRunner.Progress) -> some View {
        HStack(spacing: 12) {
            Image(systemName: progress.mode == .wakeUp ? "sunrise" : "moon.zzz")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.mode == .wakeUp ? "Wake-up fade running" : "Go-to-sleep fade running")
                    .font(.subheadline.weight(.medium))
                ProgressView(value: progress.fraction)
            }
            Button("Stop") { model.fadeRunner.cancel(light: light) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.1)))
    }

    private var pairingCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pairing needs a hand", systemImage: "exclamationmark.triangle")
                .font(.headline)
            PairingHelpView(light: light)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
    }

    private var rescanNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("This bulb wasn't seen on the last scan. It may be powered off, out of range, or its Bluetooth address changed after a reset.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Find it again…") { model.isDiscoveryPresented = true }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    /// `needsPairingHelp` flips 20 s into pairing without any published change; this nudges a redraw.
    private var showsPairingHelp: Bool {
        _ = pairingTick
        return light.connection.needsPairingHelp
    }

    private func armPairingTimer() async {
        guard case .pairing(let since) = light.connection else { return }
        let wait = since.addingTimeInterval(20.5).timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled else { return }
        pairingTick += 1
    }
}

// MARK: - Shared controls

enum ControlTarget {
    case light(HueLight)
    case all
}

/// Power / brightness / white / color / effects controls for one light or for every light.
struct LightControlsView: View {
    let target: ControlTarget

    var body: some View {
        switch target {
        case .light(let light):
            SingleLightControls(light: light)
        case .all:
            AllLightsControls()
        }
    }
}

private struct SingleLightControls: View {
    @ObservedObject var light: HueLight
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ControlsPanel(
            snapshot: ControlSnapshot(light: light, appEffects: model.appEffects),
            sink: ControlSink(
                setPower: { light.set(power: $0) },
                setBrightness: { light.set(brightness: $0) },
                setMireds: { light.set(mireds: HueWire.clampMireds($0, max: light.maxMireds)) },
                setXY: { light.set(xy: $0) },
                setEffect: { light.set(effect: $0, speed: $1) },
                toggleAppEffect: { model.toggleAppEffect($0, on: [light]) }
            )
        )
    }
}

private struct AllLightsControls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ControlsPanel(
            snapshot: ControlSnapshot(model: model),
            sink: ControlSink(
                setPower: { model.setAll(power: $0) },
                setBrightness: { model.setAll(brightness: $0) },
                setMireds: { model.setAll(mireds: $0) },
                setXY: { model.setAll(xy: $0) },
                setEffect: { model.setAll(effect: $0, speed: $1) },
                toggleAppEffect: { kind in
                    let ready = model.readyLights
                    model.toggleAppEffect(kind, on: ready.isEmpty ? model.lights : ready)
                }
            )
        )
    }
}

/// Value snapshot of whatever is being controlled; `Equatable` so the panel can sync on change.
private struct ControlSnapshot: Equatable {
    var isOn: Bool
    var brightness: UInt8
    var color: ColorMode
    var effect: HueEffect
    var effectSpeed: UInt8
    var supportsColor: Bool
    var maxMireds: UInt16
    var isEnabled: Bool
    var statusText: String
    var runningAppEffect: AppEffectRunner.Kind? = nil

    @MainActor
    init(light: HueLight, appEffects: AppEffectRunner? = nil) {
        isOn = light.state.on
        brightness = light.state.brightness
        color = light.state.color
        effect = light.state.effect
        effectSpeed = light.state.effectSpeed
        supportsColor = light.supportsColor
        maxMireds = light.maxMireds
        isEnabled = light.connection.isReady
        statusText = light.connection.label
        if let appEffects, appEffects.isRunning(on: light) { runningAppEffect = appEffects.running?.kind }
    }

    @MainActor
    init(model: AppModel) {
        let ready = model.readyLights
        let group = ready.isEmpty ? model.lights : ready
        let representative = group.first { $0.supportsColor && $0.state.on }
            ?? group.first { $0.supportsColor }
            ?? group.first
        isOn = model.anyLightOn
        brightness = model.allLightsBrightness
        color = representative?.state.color ?? .ct(mireds: 367)
        effect = representative?.state.effect ?? .none
        effectSpeed = representative?.state.effectSpeed ?? 128
        supportsColor = group.contains { $0.supportsColor }
        maxMireds = group.map(\.maxMireds).max() ?? ColorMath.maxMireds
        isEnabled = !ready.isEmpty
        statusText = model.lights.isEmpty ? "No lights" : "\(ready.count) of \(model.lights.count) connected"
        if let running = model.appEffects.running, Set(running.lightIDs) == Set(group.map(\.id)) {
            runningAppEffect = running.kind
        }
    }

    var kelvin: Double {
        switch color {
        case .ct(let mireds): return ColorMath.kelvin(fromMireds: mireds)
        case .xy: return 2700
        }
    }

    var xy: XY {
        switch color {
        case .xy(let point): return point
        case .ct(let mireds): return ColorMath.clampToGamutC(ColorMath.xy(fromKelvin: ColorMath.kelvin(fromMireds: mireds)))
        }
    }

    /// Slider range: the bulb's warmest supported white (rounded up to 10 K) … 6500 K.
    var kelvinRange: ClosedRange<Double> {
        let lower = (ColorMath.kelvin(fromMireds: maxMireds) / 10).rounded(.up) * 10
        return min(lower, ColorMath.maxKelvin - 100)...ColorMath.maxKelvin
    }

    var impliedMode: ControlsPanel.Mode {
        guard supportsColor else { return .white }
        if effect != .none { return .effects }
        return color.isColor ? .color : .white
    }

    var description: String {
        guard isOn else { return "Off" }
        var parts: [String] = []
        if effect != .none {
            parts.append("\(effect.displayName) effect")
        } else {
            switch color {
            case .ct: parts.append("\(Int(kelvin.rounded())) K")
            case .xy: parts.append("Color")
            }
        }
        parts.append("\(max(1, Int((Double(max(Int(brightness) - 1, 0)) / 253 * 100).rounded())))%")
        return parts.joined(separator: " · ")
    }
}

private struct ControlSink {
    var setPower: (Bool) -> Void
    var setBrightness: (UInt8) -> Void
    var setMireds: (UInt16) -> Void
    var setXY: (XY) -> Void
    var setEffect: (HueEffect, UInt8) -> Void
    var toggleAppEffect: (AppEffectRunner.Kind) -> Void = { _ in }
}

private struct ControlsPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case white = "White"
        case color = "Color"
        case effects = "Effects"
        var id: String { rawValue }
    }

    let snapshot: ControlSnapshot
    let sink: ControlSink

    @State private var mode: Mode
    @State private var brightness: UInt8
    @State private var kelvin: Double
    @State private var xy: XY
    @State private var speed: Double
    @State private var draggingBrightness = false
    @State private var draggingKelvin = false
    @State private var draggingWheel = false
    @State private var draggingSpeed = false

    init(snapshot: ControlSnapshot, sink: ControlSink) {
        self.snapshot = snapshot
        self.sink = sink
        _mode = State(initialValue: snapshot.impliedMode)
        _brightness = State(initialValue: snapshot.brightness)
        _kelvin = State(initialValue: snapshot.kelvin)
        _xy = State(initialValue: snapshot.xy)
        _speed = State(initialValue: Double(snapshot.effectSpeed))
    }

    var body: some View {
        VStack(spacing: 16) {
            powerCard
            if snapshot.supportsColor {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            modeCard
            ControlCard(title: "Brightness") {
                BrightnessSlider(brightness: brightnessBinding, onEditingChanged: { draggingBrightness = $0 })
            }
        }
        .disabled(!snapshot.isEnabled)
        .opacity(snapshot.isEnabled ? 1 : 0.55)
        .onChange(of: snapshot) { old, new in sync(from: old, to: new) }
    }

    private var powerCard: some View {
        ControlCard {
            HStack(spacing: 14) {
                Image(systemName: "power")
                    .font(.title2)
                    .foregroundStyle(snapshot.isOn ? Color.accentColor : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.isOn ? "On" : "Off")
                        .font(.headline)
                    Text(snapshot.isEnabled ? snapshot.description : snapshot.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Power", isOn: Binding(get: { snapshot.isOn }, set: { sink.setPower($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var modeCard: some View {
        switch mode {
        case .white:
            ControlCard(title: "Color temperature") {
                TemperatureSlider(kelvin: kelvinBinding, range: snapshot.kelvinRange, onEditingChanged: { draggingKelvin = $0 })
            }
        case .color:
            ControlCard(title: "Color") {
                ColorWheelView(xy: xyBinding, onEditingChanged: { draggingWheel = $0 })
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        case .effects:
            ControlCard(title: "Effects") {
                EffectsPicker(selected: snapshot.effect) { effect in
                    sink.setEffect(effect, UInt8(clamping: Int(speed.rounded())))
                }
                if snapshot.effect != .none {
                    HStack(spacing: 10) {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: speedBinding, in: 1...254, onEditingChanged: { draggingSpeed = $0 })
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                AppEffectsSection(running: snapshot.runningAppEffect, enabled: snapshot.supportsColor) { kind in
                    sink.toggleAppEffect(kind)
                }
                .padding(.top, 10)
            }
        }
    }

    // Write-through bindings: the local state changes only from the user, never from the sync.

    private var brightnessBinding: Binding<UInt8> {
        Binding(get: { brightness }, set: { brightness = $0; sink.setBrightness($0) })
    }

    private var kelvinBinding: Binding<Double> {
        Binding(get: { kelvin }, set: { kelvin = $0; sink.setMireds(ColorMath.mireds(fromKelvin: $0)) })
    }

    private var xyBinding: Binding<XY> {
        Binding(get: { xy }, set: { xy = $0; sink.setXY($0) })
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { speed },
            set: { speed = $0; sink.setEffect(snapshot.effect, UInt8(clamping: Int($0.rounded()))) }
        )
    }

    /// Follow the light while the user isn't dragging the corresponding control.
    private func sync(from old: ControlSnapshot, to new: ControlSnapshot) {
        if !draggingBrightness { brightness = new.brightness }
        if !draggingKelvin, case .ct = new.color { kelvin = new.kelvin }
        if !draggingWheel { xy = new.xy }
        if !draggingSpeed { speed = Double(new.effectSpeed) }

        guard new.supportsColor else {
            mode = .white
            return
        }
        // Follow the bulb when *it* changes mode (a scene, a schedule, the phone app) — but never
        // yank the user off the Effects tab.
        if new.effect != .none, old.effect == .none, mode != .effects {
            mode = .effects
        } else if mode != .effects, new.color.isColor != old.color.isColor {
            mode = new.color.isColor ? .color : .white
        }
    }
}

/// Rounded control-group card.
private struct ControlCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - All lights

struct AllLightsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All Lights")
                        .font(.largeTitle.weight(.bold))
                    Text("\(model.readyLights.count) of \(model.lights.count) connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LightControlsView(target: .all)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Scenes")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.scenes) { scene in
                                SceneQuickChip(scene: scene) { model.apply(scene: scene) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lights")
                        .font(.headline)
                    VStack(spacing: 0) {
                        ForEach(Array(model.lights.enumerated()), id: \.element.id) { index, light in
                            if index > 0 { Divider().padding(.leading, 14) }
                            LightMiniRow(light: light)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selection = .light(light.id) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Compact row: status dot, swatch, name, brightness slider, power toggle. Used by All Lights and the menu bar.
struct LightMiniRow: View {
    @ObservedObject var light: HueLight
    var sliderWidth: CGFloat = 160

    var body: some View {
        let ready = light.connection.isReady
        HStack(spacing: 10) {
            StatusDot(connection: light.connection)
            Circle()
                .fill(light.state.displayColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            Text(light.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            LiveBrightnessSlider(value: light.state.brightness, showsPercent: false) { light.set(brightness: $0) }
                .frame(width: sliderWidth)
                .disabled(!ready)
            Toggle("Power", isOn: Binding(get: { light.state.on }, set: { light.set(power: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(!ready)
        }
        .opacity(ready ? 1 : 0.6)
        .help(light.connection.label)
    }
}
