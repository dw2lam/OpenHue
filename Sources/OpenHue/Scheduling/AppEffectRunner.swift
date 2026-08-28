import Foundation

/// Mac-driven light effects the bulb firmware doesn't provide (e.g. Police: red/blue strobe).
/// The runner writes colours on a timer; any user interaction with a light cancels it there.
@MainActor
final class AppEffectRunner: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case police

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .police: return "Police"
            }
        }

        var symbol: String {
            switch self {
            case .police: return "light.beacon.max"
            }
        }

        var description: String {
            switch self {
            case .police: return "Red and blue flashing, alternating between lights."
            }
        }
    }

    struct Running: Equatable {
        var kind: Kind
        var lightIDs: [UUID]
        var startedAt: Date
    }

    @Published private(set) var running: Running?
    /// Seconds between colour flips (Police). 0.15…1.0.
    @Published var interval: TimeInterval = 0.35 {
        didSet { if running != nil { restartTimer() } }
    }

    private var lights: [HueLight] = []
    /// State of each light before the effect started, restored on stop.
    private var snapshot: [UUID: LightState] = [:]
    private var timer: Timer?
    private var phase = 0

    // Gamut-C corners for the strongest saturation the bulb can show.
    private static let red = ColorMath.clampToGamutC(ColorMath.xy(fromRGB: RGB(r: 1, g: 0, b: 0)))
    private static let blue = ColorMath.clampToGamutC(ColorMath.xy(fromRGB: RGB(r: 0, g: 0, b: 1)))

    func isRunning(on light: HueLight) -> Bool {
        running?.lightIDs.contains(light.id) ?? false
    }

    func isRunning(_ kind: Kind, on light: HueLight) -> Bool {
        running?.kind == kind && isRunning(on: light)
    }

    /// Starts `kind` on the given lights, replacing any effect already running.
    func start(_ kind: Kind, on targets: [HueLight]) {
        let targets = targets.filter(\.supportsColor)
        guard !targets.isEmpty else {
            hueLog("App effect \(kind.displayName): no colour-capable lights selected", level: .warning)
            return
        }
        stop(restore: true)
        lights = targets
        snapshot = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.state) })
        running = Running(kind: kind, lightIDs: targets.map(\.id), startedAt: Date())
        phase = 0
        hueLog("App effect \(kind.displayName) started on \(targets.map(\.name).joined(separator: ", "))")
        // Prime every light: on, full brightness, first colour — via apply so colour lands before power.
        for (index, light) in targets.enumerated() {
            light.apply(LightState(on: true, brightness: 254, color: .xy(color(forIndex: index))), source: .automation)
        }
        restartTimer()
    }

    /// Stops the effect. With `restore`, each light returns to the state it had before the effect began.
    func stop(restore: Bool = true) {
        guard let current = running else { return }
        timer?.invalidate()
        timer = nil
        running = nil
        hueLog("App effect \(current.kind.displayName) stopped")
        if restore {
            for light in lights {
                if let previous = snapshot[light.id] { light.apply(previous, source: .automation) }
            }
        }
        lights = []
        snapshot = [:]
    }

    /// Removes one light from a running effect (user touched it); stops entirely when none remain.
    func cancel(light: HueLight) {
        guard var current = running, current.lightIDs.contains(light.id) else { return }
        current.lightIDs.removeAll { $0 == light.id }
        lights.removeAll { $0.id == light.id }
        snapshot.removeValue(forKey: light.id)
        if current.lightIDs.isEmpty {
            stop(restore: false)
        } else {
            running = current
        }
    }

    // MARK: - Timer

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: max(0.15, min(1.0, interval)), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard running != nil else { return }
        phase &+= 1
        for (index, light) in lights.enumerated() {
            light.set(xy: color(forIndex: index), source: .automation)
        }
    }

    /// Alternate lights are out of phase so two bulbs behave like a light bar.
    private func color(forIndex index: Int) -> XY {
        (phase + index) % 2 == 0 ? Self.red : Self.blue
    }
}
