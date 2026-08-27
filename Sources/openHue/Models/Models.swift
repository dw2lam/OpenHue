import Foundation

// MARK: - Lights

/// Persisted record of a bulb we have paired with.
struct KnownLight: Codable, Identifiable, Equatable, Hashable {
    /// `CBPeripheral.identifier` — per-Mac and per-BLE-address (changes after a factory reset).
    var id: UUID
    /// User-chosen name (shown everywhere). Falls back to the bulb's own name when added.
    var name: String
    /// Name read from the bulb's name characteristic.
    var bulbName: String?
    var model: String?
    var firmware: String?
    var manufacturer: String?
    var supportsColor: Bool = true
    /// Learned: some models cap at 454 instead of 500.
    var maxMireds: UInt16 = 500
    var addedAt: Date = Date()
    var lastSeen: Date?
    /// Last known state, so the UI shows something before the bulb reconnects.
    var lastState: LightState?

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Scenes

/// Named `HueScene` to avoid clashing with `SwiftUI.Scene`.
struct HueScene: Codable, Identifiable, Equatable, Hashable {
    enum Kind: Codable, Equatable, Hashable {
        case preset
        case user
    }

    var id: UUID
    var name: String
    var kind: Kind
    /// SF Symbol name.
    var symbol: String
    /// Preset scenes: applied round-robin over the target lights (index-based).
    var palette: [LightState] = []
    /// User scenes: exact state per light id (snapshot of "what the room looked like").
    var states: [UUID: LightState] = [:]

    init(id: UUID = UUID(), name: String, kind: Kind, symbol: String, palette: [LightState] = [], states: [UUID: LightState] = [:]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.symbol = symbol
        self.palette = palette
        self.states = states
    }

    var isPreset: Bool { kind == .preset }

    /// Resolves the state for a given light. `index` is the light's position among the targets
    /// (used for palette round-robin). Returns nil if a user scene has no entry for the light.
    func state(for lightID: UUID, index: Int) -> LightState? {
        if let s = states[lightID] { return s }
        guard !palette.isEmpty else { return nil }
        return palette[index % palette.count]
    }

    /// Representative colors for swatch strips.
    var swatches: [LightState] {
        if !palette.isEmpty { return palette }
        return states.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { states[$0] }
    }
}

// MARK: - Schedules

/// Calendar weekday numbering (Sunday = 1 … Saturday = 7), matching `DateComponents.weekday`.
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var letter: String { String(shortName.prefix(1)) }

    /// `pmset repeat` day code.
    var pmsetCode: String {
        switch self {
        case .sunday: return "U"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "R"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let everyday: Set<Weekday> = Set(allCases)
}

struct HourMinute: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.hour = c.hour ?? 0
        self.minute = c.minute ?? 0
    }

    /// Today's date at this time (calendar-local).
    func date(on day: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var formatted: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date())
    }
}

enum ScheduleTrigger: Codable, Equatable, Hashable {
    case weekly(days: Set<Weekday>, time: HourMinute)
    case once(Date)
}

/// What a light should end up looking like.
enum LightTarget: Codable, Equatable, Hashable {
    case scene(UUID)
    case state(brightness: UInt8, color: ColorMode)
}

enum ScheduleAction: Codable, Equatable, Hashable {
    case turnOff
    case turnOn(LightTarget)
    /// Fade from dim + warm up to `target` over `minutes`.
    case wakeUp(minutes: Int, target: LightTarget)
    /// Fade from the current state down to dim + warm over `minutes`, then off.
    case goToSleep(minutes: Int)

    var isOnAction: Bool {
        switch self {
        case .turnOn, .wakeUp: return true
        case .turnOff, .goToSleep: return false
        }
    }

    var fadeMinutes: Int? {
        switch self {
        case .wakeUp(let m, _), .goToSleep(let m): return m
        default: return nil
        }
    }
}

struct Schedule: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var isEnabled: Bool = true
    var trigger: ScheduleTrigger
    /// Empty = all lights.
    var targets: Set<UUID> = []
    var action: ScheduleAction
    var lastFired: Date?

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, trigger: ScheduleTrigger, targets: Set<UUID> = [], action: ScheduleAction, lastFired: Date? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.targets = targets
        self.action = action
        self.lastFired = lastFired
    }
}

// MARK: - Settings

struct WakeMacSetting: Codable, Equatable, Hashable {
    var enabled: Bool = false
    var days: Set<Weekday> = Weekday.everyday
    var time: HourMinute = HourMinute(hour: 6, minute: 55)
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool = false
    /// Keep bulbs connected (periodic keepalive read) so commands are instant.
    var keepLightsConnected: Bool = true
    /// Hold a system-sleep assertion whenever the app runs.
    var keepMacAwakeWhileRunning: Bool = false
    /// A missed "on" schedule still runs if the Mac wakes within this many minutes.
    var missedGraceOnMinutes: Int = 30
    /// A missed "off" schedule still runs if the Mac wakes within this many hours.
    var missedGraceOffHours: Int = 6
    /// `pmset repeat wakeorpoweron` entry managed by the app.
    var wakeMac: WakeMacSetting = WakeMacSetting()
    var openWindowAtLaunch: Bool = true
}
