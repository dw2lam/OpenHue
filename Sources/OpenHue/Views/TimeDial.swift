import SwiftUI
import AppKit

// MARK: - Time dial

/// Rotary kitchen-timer dial: one full turn = 60 min, keep turning for hours (0…720 min).
/// Dragging is relative (no jump-to-pointer), snaps to the minute with haptic ticks every 5.
/// While `running` is set it becomes a read-only countdown ring that drains from full.
struct TimeDial: View {
    @Binding var minutes: Int
    var running: SleepTimer? = nil
    var diameter: CGFloat = 240
    var tint: Color = .indigo
    var clock: () -> Date = { Date() }

    static let maxMinutes = 720

    @State private var isDragging = false
    @State private var startMinutes = 0
    @State private var lastAngle: Double?
    @State private var accumulated: Double = 0

    /// Ring stroke and knob are the same size on every dial (consistent touch target, consistent look).
    private let lineWidth: CGFloat = 18
    private let knobSize: CGFloat = 30
    /// Radius of the ring's centre line.
    private var ringRadius: CGFloat { (diameter - lineWidth) / 2 }
    /// Room for the knob overhang and its shadow.
    private var frameSize: CGFloat { diameter + (knobSize - lineWidth) + 12 }

    var body: some View {
        ZStack {
            if let running {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    ZStack {
                        ring(fraction: running.fraction(at: context.date), hourRing: false, knob: false)
                        countdownReadout(running, now: context.date)
                    }
                }
            } else {
                ring(fraction: idleFraction, hourRing: minutes >= 60, knob: true)
                    .animation(isDragging ? nil : .spring(duration: 0.4, bounce: 0.15), value: minutes)
                idleReadout
            }
        }
        .frame(width: frameSize, height: frameSize)
        .contentShape(Circle())
        .gesture(drag, including: running == nil ? .all : .subviews)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard running == nil else { return }
            switch direction {
            case .increment: minutes = min(Self.maxMinutes, minutes + 5)
            case .decrement: minutes = max(0, minutes - 5)
            @unknown default: break
            }
        }
    }

    // MARK: Ring

    private var idleFraction: Double {
        if minutes > 0, minutes % 60 == 0 { return 1 }
        return Double(minutes % 60) / 60
    }

    @ViewBuilder
    private func ring(fraction: Double, hourRing: Bool, knob: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)
            ticks
            Circle()
                .stroke(tint.opacity(0.28), lineWidth: lineWidth)
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)
                .opacity(hourRing ? 1 : 0)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.7), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)
                .rotationEffect(.degrees(-90))
            if knob {
                knobView
                    .modifier(OrbitOffset(degrees: fraction * 360, radius: ringRadius))
            }
        }
    }

    private var ticks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = ringRadius - lineWidth / 2 - 5
            for index in 0..<60 {
                let major = index % 5 == 0
                let length: CGFloat = major ? 8 : 5
                let angle = Double(index) / 60 * 2 * .pi - .pi / 2
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * (outer - length), y: center.y + sin(angle) * (outer - length)))
                context.stroke(path,
                               with: .color(Color.secondary.opacity(major ? 0.5 : 0.25)),
                               style: StrokeStyle(lineWidth: major ? 2 : 1.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private var knobView: some View {
        Circle()
            .fill(.clear)
            .frame(width: knobSize, height: knobSize)
            .liquidGlass(in: Circle())
            .overlay(
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            )
            .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }

    // MARK: Readouts

    private var idleReadout: some View {
        VStack(spacing: 2) {
            Text(idleNumber)
                .font(.system(size: diameter * 0.24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: minutes)
                .foregroundStyle(minutes == 0 ? .secondary : .primary)
            Text(idleUnit)
                .font(.system(size: max(11, diameter * 0.065), weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
    }

    private var idleNumber: String {
        guard minutes >= 60 else { return "\(minutes)" }
        let hours = minutes / 60, mins = minutes % 60
        return mins == 0 ? "\(hours)" : String(format: "%d:%02d", hours, mins)
    }

    private var idleUnit: String {
        guard minutes >= 60 else { return "min" }
        return minutes == 60 ? "hour" : "hours"
    }

    private func countdownReadout(_ timer: SleepTimer, now: Date) -> some View {
        let remaining = timer.remaining(at: now)
        let long = remaining >= 3600
        return VStack(spacing: 3) {
            Text(SleepTimerRunner.countdownText(remaining))
                .font(.system(size: diameter * (long ? 0.17 : 0.24), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.linear(duration: 0.2), value: remaining.rounded(.up))
            Text(timer.mode == .dimToSleep ? "Dimming · off at " : "Off at ") + Text(timer.endsAt, format: .dateTime.hour().minute())
            if timer.mode == .switchOff, timer.isFading(at: now) {
                Text("Fading out…")
                    .foregroundStyle(tint)
            }
        }
        .font(.system(size: max(11, diameter * 0.065), weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
    }

    private var accessibilityValue: String {
        if let running {
            return SleepTimerRunner.durationText(running.remaining(at: clock())) + " remaining"
        }
        return SleepTimerRunner.durationText(TimeInterval(minutes) * 60)
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = frameSize / 2
                let dx = value.location.x - center
                let dy = value.location.y - center
                if !isDragging {
                    isDragging = true
                    startMinutes = minutes
                    accumulated = 0
                    lastAngle = nil
                }
                // The angle is unstable near the centre; ignore those samples.
                guard hypot(dx, dy) >= ringRadius * 0.25 else { return }
                let angle = atan2(dy, dx)
                if let last = lastAngle {
                    var delta = angle - last
                    if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
                    accumulated += delta
                }
                lastAngle = angle

                let raw = Double(startMinutes) + accumulated / (2 * .pi) * 60
                let clamped = min(max(Int(raw.rounded()), 0), Self.maxMinutes)
                if Int(raw.rounded()) != clamped {
                    // Re-anchor at the limit so reversing responds immediately.
                    accumulated = Double(clamped - startMinutes) / 60 * 2 * .pi
                }
                if clamped != minutes {
                    Self.haptic(from: minutes, to: clamped)
                    minutes = clamped
                }
            }
            .onEnded { _ in
                isDragging = false
                lastAngle = nil
                accumulated = 0
            }
    }

    private static func haptic(from old: Int, to new: Int) {
        let range = min(old, new)...max(old, new)
        let performer = NSHapticFeedbackManager.defaultPerformer
        if range.contains(where: { $0 != old && $0 % 60 == 0 }) {
            performer.perform(.levelChange, performanceTime: .now)
        } else if range.contains(where: { $0 != old && $0 % 5 == 0 }) {
            performer.perform(.alignment, performanceTime: .now)
        }
    }
}

/// Places a view on a circle by angle (0° = top, clockwise) and animates *along the arc*
/// (a plain `offset` would animate across the chord; a `rotationEffect` would rotate the glass).
private struct OrbitOffset: ViewModifier, Animatable {
    var degrees: Double
    let radius: CGFloat

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func body(content: Content) -> some View {
        let radians = (degrees - 90) * .pi / 180
        return content.offset(x: cos(radians) * radius, y: sin(radians) * radius)
    }
}

// MARK: - Liquid Glass helpers (macOS 26, with material fallbacks)

extension View {
    /// Liquid Glass on macOS 26; a material fill with a hairline highlight before that.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(interactive).tint(tint), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.regularMaterial)
                        if let tint { shape.fill(tint.opacity(0.35)) }
                    }
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
        }
    }

    /// `.glassProminent` on macOS 26, `.borderedProminent` before that.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// `.glass` on macOS 26, `.bordered` before that.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Groups glass chips so they share one container (morphing) on macOS 26; plain content otherwise.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Capsule chip: Liquid Glass (tinted when selected) on macOS 26, flat tinted capsule before that.
struct GlassChip: View {
    let title: String
    let selected: Bool
    var tint: Color = .indigo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(ChipChrome(selected: selected, tint: tint))
        .animation(.spring(duration: 0.25), value: selected)
    }

    private struct ChipChrome: ViewModifier {
        let selected: Bool
        let tint: Color

        func body(content: Content) -> some View {
            if #available(macOS 26, *) {
                content
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .glassEffect(.regular.interactive().tint(selected ? tint.opacity(0.55) : nil), in: .capsule)
            } else {
                content
                    .foregroundStyle(selected ? tint : Color.primary)
                    .background(Capsule().fill(selected ? tint.opacity(0.18) : Color.primary.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(selected ? tint : Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
    }
}
