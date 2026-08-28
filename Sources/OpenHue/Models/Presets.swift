import Foundation

/// Hue's stock scenes. IDs are fixed so schedules can reference them across launches.
enum Presets {
    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "7B1E0000-0000-4000-8000-%012X", n))!
    }

    private static func white(_ bri: UInt8, _ mireds: UInt16) -> LightState {
        LightState(on: true, brightness: bri, color: .ct(mireds: mireds))
    }

    private static func color(_ x: Double, _ y: Double, _ bri: UInt8) -> LightState {
        LightState(on: true, brightness: bri, color: .xy(XY(x: x, y: y)))
    }

    static let bright      = HueScene(id: id(1), name: "Bright",      kind: .preset, symbol: "sun.max",          palette: [white(254, 367)])
    static let dimmed      = HueScene(id: id(2), name: "Dimmed",      kind: .preset, symbol: "sun.min",          palette: [white(77, 367)])
    static let nightlight  = HueScene(id: id(3), name: "Nightlight",  kind: .preset, symbol: "moon",             palette: [color(0.561, 0.404, 1)])
    static let relax       = HueScene(id: id(4), name: "Relax",       kind: .preset, symbol: "cup.and.saucer",   palette: [white(144, 447)])
    static let read        = HueScene(id: id(5), name: "Read",        kind: .preset, symbol: "book",             palette: [white(254, 346)])
    static let concentrate = HueScene(id: id(6), name: "Concentrate", kind: .preset, symbol: "brain.head.profile", palette: [white(254, 233)])
    static let energize    = HueScene(id: id(7), name: "Energize",    kind: .preset, symbol: "bolt",             palette: [white(254, 156)])

    static let savannaSunset = HueScene(id: id(11), name: "Savanna Sunset", kind: .preset, symbol: "sunset",
        palette: [color(0.644, 0.340, 200), color(0.570, 0.384, 200), color(0.492, 0.428, 200)])
    static let tropicalTwilight = HueScene(id: id(12), name: "Tropical Twilight", kind: .preset, symbol: "leaf",
        palette: [color(0.312, 0.133, 180), color(0.405, 0.208, 180), color(0.602, 0.321, 180)])
    static let arcticAurora = HueScene(id: id(13), name: "Arctic Aurora", kind: .preset, symbol: "snowflake",
        palette: [color(0.164, 0.332, 200), color(0.221, 0.521, 200), color(0.150, 0.100, 200)])
    static let springBlossom = HueScene(id: id(14), name: "Spring Blossom", kind: .preset, symbol: "camera.macro",
        palette: [color(0.438, 0.270, 210), color(0.354, 0.247, 210), color(0.460, 0.380, 210)])

    static let whiteScenes: [HueScene] = [bright, dimmed, nightlight, relax, read, concentrate, energize]
    static let colorScenes: [HueScene] = [savannaSunset, tropicalTwilight, arcticAurora, springBlossom]
    static let all: [HueScene] = whiteScenes + colorScenes

    static func scene(id: UUID) -> HueScene? { all.first { $0.id == id } }
}
