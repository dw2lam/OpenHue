import SwiftUI
import AppKit

// MARK: - Connection state → color

extension HueLight.ConnectionState {
    /// Dot / badge color: green ready, amber in progress, red failed, grey unavailable.
    var statusColor: Color {
        switch self {
        case .ready: return .green
        case .connecting, .discovering, .pairing: return .orange
        case .pairingFailed: return .red
        case .unavailable, .disconnected: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    /// True while a spinner is appropriate.
    var isBusy: Bool {
        switch self {
        case .connecting, .discovering, .pairing: return true
        default: return false
        }
    }
}

struct StatusDot: View {
    let connection: HueLight.ConnectionState
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(connection.statusColor)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel(connection.label)
    }
}

// MARK: - Color wheel

/// HSV hue/saturation wheel. Angle = hue, radius = saturation; the center is white.
/// Writes `xy` continuously while dragging; the thumb only follows the binding when idle
/// (xy → hue/saturation is lossy because of the gamut clamp).
struct ColorWheelView: View {
    @Binding var xy: XY
    var diameter: CGFloat = 260
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @State private var dragHue: Double = 0
    @State private var dragSaturation: Double = 0

    private static let hueStops: [Color] = (0...24).map { Color(hue: Double($0) / 24, saturation: 1, brightness: 1) }

    var body: some View {
        let radius = diameter / 2
        let placement = currentHueSaturation
        let angle = placement.hue * 2 * .pi
        let thumbCenter = CGPoint(
            x: radius + cos(angle) * placement.saturation * radius,
            y: radius + sin(angle) * placement.saturation * radius
        )

        ZStack {
            Circle()
                .fill(AngularGradient(colors: Self.hueStops, center: .center, startAngle: .zero, endAngle: .degrees(360)))
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
            Circle()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .overlay {
            Circle()
                .fill(thumbColor)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .position(thumbCenter)
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onEditingChanged(true)
                    }
                    let dx = value.location.x - radius
                    let dy = value.location.y - radius
                    var hue = atan2(dy, dx) / (2 * .pi)
                    if hue < 0 { hue += 1 }
                    let saturation = min(hypot(dx, dy) / radius, 1)
                    dragHue = hue
                    dragSaturation = saturation
                    xy = ColorMath.xy(fromHue: hue, saturation: saturation)
                }
                .onEnded { _ in
                    isDragging = false
                    onEditingChanged(false)
                }
        )
        .accessibilityLabel("Color wheel")
    }

    private var currentHueSaturation: (hue: Double, saturation: Double) {
        isDragging ? (dragHue, dragSaturation) : ColorMath.hueSaturation(fromXY: xy)
    }

    private var thumbColor: Color {
        isDragging
            ? Color(ColorMath.rgb(fromHSV: dragHue, s: dragSaturation, v: 1))
            : Color(ColorMath.rgb(fromXY: xy))
    }
}

// MARK: - Color temperature slider

/// Warm (left) → cool (right) black-body gradient track with a ring thumb. Values in kelvin.
struct TemperatureSlider: View {
    @Binding var kelvin: Double
    var range: ClosedRange<Double> = ColorMath.minKelvin...ColorMath.maxKelvin
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    private let trackHeight: CGFloat = 22
    private let thumbSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let usable = max(width - thumbSize, 1)
                let x = thumbSize / 2 + fraction(for: kelvin) * usable

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                        .frame(height: trackHeight)
                        .padding(.horizontal, (thumbSize - trackHeight) / 2)
                    Circle()
                        .fill(Color(ColorMath.rgb(fromKelvin: kelvin)))
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .position(x: x, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onEditingChanged(true)
                            }
                            let f = min(max((value.location.x - thumbSize / 2) / usable, 0), 1)
                            let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                            kelvin = min(max((raw / 10).rounded() * 10, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEditingChanged(false)
                        }
                )
            }
            .frame(height: thumbSize)

            HStack {
                Text(label(range.lowerBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(label(kelvin))
                    .font(.callout.monospacedDigit().weight(.medium))
                Spacer()
                Text(label(range.upperBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Color temperature")
        .accessibilityValue(label(kelvin))
    }

    private var gradientColors: [Color] {
        let span = range.upperBound - range.lowerBound
        return (0..<16).map { step in
            Color(ColorMath.rgb(fromKelvin: range.lowerBound + span * Double(step) / 15))
        }
    }

    private func fraction(for value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func label(_ value: Double) -> String { "\(Int(value.rounded())) K" }
}

// MARK: - Brightness slider

/// System slider over 1...254 with sun icons and a percentage readout.
struct BrightnessSlider: View {
    @Binding var brightness: UInt8
    var showsPercent = true
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: sliderValue, in: 1...254) {
                Text("Brightness")
            } minimumValueLabel: {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                onEditingChanged(editing)
            }
            .labelsHidden()

            if showsPercent {
                Text("\(percent)%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(brightness) },
            set: { brightness = HueWire.clampBrightness(UInt8(clamping: Int($0.rounded()))) }
        )
    }

    private var percent: Int {
        max(1, Int((Double(max(Int(brightness) - 1, 0)) / 253 * 100).rounded()))
    }
}

/// A brightness slider that mirrors an externally-updated value while idle and writes through
/// (via `onSet`) while the user drags. Used by the compact light rows.
struct LiveBrightnessSlider: View {
    var value: UInt8
    var showsPercent = true
    var onSet: (UInt8) -> Void

    @State private var local: UInt8
    @State private var isDragging = false

    init(value: UInt8, showsPercent: Bool = true, onSet: @escaping (UInt8) -> Void) {
        self.value = value
        self.showsPercent = showsPercent
        self.onSet = onSet
        _local = State(initialValue: value)
    }

    var body: some View {
        BrightnessSlider(
            brightness: Binding(get: { local }, set: { local = $0; onSet($0) }),
            showsPercent: showsPercent,
            onEditingChanged: { isDragging = $0 }
        )
        .onChange(of: value) { _, newValue in
            if !isDragging { local = newValue }
        }
    }
}

// MARK: - Effects

struct EffectsPicker: View {
    var selected: HueEffect
    var onSelect: (HueEffect) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(HueEffect.allCases) { effect in
                let isSelected = effect == selected
                Button {
                    onSelect(effect)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: effect.symbol)
                            .font(.title3)
                            .frame(height: 22)
                        Text(effect.displayName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(effect.displayName)
            }
        }
    }
}

// MARK: - Scene chip

/// Compact tappable scene pill: swatches + symbol + name. Used by the All Lights page and the menu bar.
struct SceneQuickChip: View {
    let scene: HueScene
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach(Array(scene.swatches.prefix(3).enumerated()), id: \.offset) { _, state in
                        Circle()
                            .fill(Color(state.color.displayRGB))
                            .frame(width: compact ? 10 : 12, height: compact ? 10 : 12)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    }
                }
                Image(systemName: scene.symbol)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                Text(scene.name)
                    .font(compact ? .caption : .callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Apply “\(scene.name)”")
    }
}


// MARK: - Empty state

/// Plain replacement for `ContentUnavailableView`, which on macOS 14/15 can scroll the
/// NavigationSplitView sidebar off its top when shown in the detail column.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, systemImage: String, description: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            actions()
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// MARK: - Mac-driven effects (Police, …)

/// Effects generated by this Mac rather than the bulb firmware. Any manual change to a light stops it.
struct AppEffectsSection: View {
    @EnvironmentObject private var model: AppModel
    var running: AppEffectRunner.Kind?
    var enabled: Bool
    var onToggle: (AppEffectRunner.Kind) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("From this Mac")
                    .font(.subheadline.weight(.semibold))
                Text("— runs while OpenHue is open; touching a control stops it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AppEffectRunner.Kind.allCases) { kind in
                    let isOn = running == kind
                    Button {
                        onToggle(kind)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.title3)
                                .frame(height: 22)
                                .symbolEffect(.pulse, isActive: isOn)
                            Text(kind.displayName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOn ? AnyShapeStyle(policeGradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isOn ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(kind.description)
                }
            }
            if running != nil {
                HStack(spacing: 10) {
                    Image(systemName: "tortoise").foregroundStyle(.secondary)
                    Slider(value: rateBinding, in: 0.15...1.0)
                    Image(systemName: "hare").foregroundStyle(.secondary)
                    Text(String(format: "%.2f s", model.appEffects.interval))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.top, 2)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private var policeGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.85, green: 0.1, blue: 0.15), Color(red: 0.1, green: 0.3, blue: 0.95)],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Slider is "faster to the right": invert the interval.
    private var rateBinding: Binding<Double> {
        Binding(get: { 1.15 - model.appEffects.interval },
                set: { model.appEffects.interval = 1.15 - $0 })
    }
}
