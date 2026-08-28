import Foundation
import CoreBluetooth
import Combine

struct CharacteristicInfo: Identifiable, Equatable {
    let service: CBUUID
    let uuid: CBUUID
    let properties: CBCharacteristicProperties
    var id: String { service.uuidString + "/" + uuid.uuidString }
    var label: String { HueUUID.label(uuid) }
    var propertyText: String {
        var p: [String] = []
        if properties.contains(.read) { p.append("R") }
        if properties.contains(.write) { p.append("W") }
        if properties.contains(.writeWithoutResponse) { p.append("WnR") }
        if properties.contains(.notify) { p.append("N") }
        if properties.contains(.indicate) { p.append("I") }
        return p.joined(separator: "/")
    }
}

/// Thrown by `HueLight.ensureReady(timeout:)`.
struct HueLightError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One bulb: owns the `CBPeripheral`, its characteristic map, connection state machine and write queue.
///
/// Connection flow (all on the main actor, CoreBluetooth callbacks arrive on the main queue):
///
///     unavailable ──(attach + connect)──▶ connecting ──didConnect──▶ discovering
///     discovering: discoverServices → discoverCharacteristics → read `power` (the gate read that
///                  makes macOS show its pairing dialog on an unbonded bulb)
///        gate OK   → initial reads + notify subscriptions → ready (once `combined` answered, or 3 s)
///        gate says insufficientAuthentication/Encryption → pairing(since:)
///     pairing:     poll-read `power` every 2 s; success resumes the discovery flow; 60 s or a
///                  broken-bond error → pairingFailed (link dropped, `wantsConnection = false`)
///     pairingFailed ──(user Retry = central.connect)──▶ connecting
///     ready ──handleDisconnected──▶ connecting (the central re-issues `connect`)
@MainActor
final class HueLight: NSObject, ObservableObject, Identifiable {
    enum UnavailableReason: Equatable { case bluetoothOff, unauthorized, needsRescan }

    enum ConnectionState: Equatable {
        case unavailable(UnavailableReason)
        /// Not linked and not trying: the user disconnected it, or the link dropped while `wantsConnection` was false.
        case disconnected
        case connecting
        case discovering
        case pairing(since: Date)
        case pairingFailed(String)
        case ready

        var isReady: Bool { self == .ready }
        var isConnectedOrBusy: Bool {
            switch self {
            case .discovering, .pairing, .ready: return true
            default: return false
            }
        }
        var label: String {
            switch self {
            case .unavailable(.bluetoothOff): return "Bluetooth is off"
            case .unavailable(.unauthorized): return "Bluetooth access denied"
            case .unavailable(.needsRescan): return "Not found — rescan"
            case .disconnected: return "Disconnected"
            case .connecting: return "Waiting for bulb…"
            case .discovering: return "Connecting…"
            case .pairing: return "Pairing…"
            case .pairingFailed(let why): return "Pairing failed: \(why)"
            case .ready: return "Connected"
            }
        }
        /// True when the pairing help callout should be shown.
        var needsPairingHelp: Bool {
            switch self {
            case .pairingFailed: return true
            case .pairing(let since): return Date().timeIntervalSince(since) > 20
            default: return false
            }
        }
    }

    enum WriteSource { case user, automation }

    let id: UUID
    @Published var info: KnownLight
    /// Starts as `.connecting` so remembered lights don't claim "Bluetooth is off" before the first
    /// `centralManagerDidUpdateState`, which sets the real state.
    @Published private(set) var connection: ConnectionState = .connecting {
        didSet {
            guard oldValue != connection else { return }
            log("state: \(oldValue.label) → \(connection.label)", .info)
        }
    }
    @Published private(set) var state: LightState = .default
    @Published private(set) var rssi: Int?
    @Published private(set) var lastError: String?
    @Published private(set) var characteristics: [CharacteristicInfo] = []
    @Published private(set) var rawValues: [CBUUID: Data] = [:]
    /// Alarms stored on the bulb itself (list / arm / disarm / delete / create).
    let alarms = HueAlarmClient()
    /// Bulb clock minus Mac clock at the last read (nil until read). Re-synced automatically past `clockTolerance`.
    @Published private(set) var clockOffset: TimeInterval?
    static let clockTolerance: TimeInterval = 20
    private var alarmCancellable: AnyCancellable?
    /// One-off exploratory reads of undocumented characteristics (logged, never acted on).
    private var probeReads: Set<CBUUID> = []

    /// When true the central keeps a pending connect so the bulb reconnects whenever it reappears.
    var wantsConnection = true
    private(set) var peripheral: CBPeripheral?
    weak var central: HueCentral?

    /// Called on every user-originated write (AppModel uses it to cancel a running fade).
    var onUserWrite: ((HueLight) -> Void)?
    /// Called whenever `info` changes in a way worth persisting.
    var onInfoChanged: ((HueLight) -> Void)?

    var name: String { info.name }
    var supportsColor: Bool { info.supportsColor }
    var maxMireds: UInt16 { info.maxMireds }

    // MARK: - Private state

    private struct PendingWrite {
        var data: Data
        var attempts: Int
        var enqueuedAt: Date
    }

    private struct InFlightWrite {
        let uuid: CBUUID
        let data: Data
        let attempts: Int
        let enqueuedAt: Date
        /// Monotonic per-write id so a late watchdog can't clobber a newer write to the same characteristic.
        let serial: Int
    }

    /// Latest value per characteristic (slider floods coalesce into one write).
    private var pending: [CBUUID: PendingWrite] = [:]
    private var inFlight: InFlightWrite?
    private var pumpTask: Task<Void, Never>?
    private var writeSerial = 0
    private var writeWatchdog: Task<Void, Never>?

    private var charMap: [CBUUID: CBCharacteristic] = [:]
    private var servicesAwaitingCharacteristics: Set<CBUUID> = []
    /// Reads we issued that have not been answered yet (lets us tell a read response from a notify).
    private var outstandingReads: [CBUUID: Int] = [:]
    /// Set once the encrypted-link reads/subscriptions have been issued on this connection.
    private var initialReadsIssued = false
    private var awaitingCombinedForReady = false

    private var pairingStartedAt: Date?
    private var pairingPollTimer: Timer?
    private var keepAliveTimer: Timer?
    private var readyFallbackTask: Task<Void, Never>?
    private var discoveryWatchdog: Task<Void, Never>?
    private var gateRetryTask: Task<Void, Never>?
    private var gateAttempts = 0
    /// Back-to-back CBATT 5/15 errors; past `pairingSlowdownThreshold` the pairing poll slows down.
    private var consecutiveEncryptionErrors = 0
    private var lastKeepAliveReadAt: Date = .distantPast
    private var lastRSSIReadAt: Date = .distantPast

    private var readyWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    private var lastInfoNotifyAt: Date = .distantPast
    private var infoNotifyTask: Task<Void, Never>?

    /// Last CT write above the common 454 cap, so the bulb's echo can teach us its real maximum.
    private var lastHighMiredsWrite: (value: UInt16, at: Date)?

    /// Color before power so applying a scene to an OFF bulb never flashes its old color.
    private static let writeOrder: [CBUUID] = [
        HueUUID.colorTemp, HueUUID.colorXY, HueUUID.brightness, HueUUID.power,
        HueUUID.combined, HueUUID.alert, HueUUID.name, HueUUID.powerOnDefault,
    ]
    private static let pairingTimeout: TimeInterval = 60
    private static let pairingPollInterval: TimeInterval = 2
    private static let pairingSlowPollInterval: TimeInterval = 5
    private static let pairingSlowdownThreshold = 5
    /// One timer drives both the keepalive read (45 s) and the RSSI refresh (30 s).
    private static let linkTimerInterval: TimeInterval = 15
    private static let keepAliveInterval: TimeInterval = 45
    private static let rssiInterval: TimeInterval = 30
    private static let writeTimeout: TimeInterval = 5
    private static let readyFallbackDelay: TimeInterval = 3
    private static let discoveryTimeout: TimeInterval = 20
    private static let stalePendingAge: TimeInterval = 60
    private static let maxWriteAttempts = 3
    private static let commonMiredsCap: UInt16 = 454

    init(info: KnownLight) {
        self.id = info.id
        self.info = info
        self.state = info.lastState ?? .default
        super.init()
        alarms.send = { [weak self] data in self?.enqueue(HueUUID.alarm, data) }
        alarms.log = { [weak self] message, level in self?.log("alarms: " + message, level) }
        alarmCancellable = alarms.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - Commands

    func set(power: Bool, source: WriteSource = .user) {
        noteWrite(source)
        enqueue(HueUUID.power, HueWire.data(power: power))
    }

    func set(brightness: UInt8, source: WriteSource = .user) {
        noteWrite(source)
        enqueue(HueUUID.brightness, HueWire.data(brightness: HueWire.clampBrightness(brightness)))
    }

    func set(mireds: UInt16, source: WriteSource = .user) {
        noteWrite(source)
        enqueueColor(.ct(mireds: mireds))
    }

    func set(xy: XY, source: WriteSource = .user) {
        noteWrite(source)
        enqueueColor(.xy(xy))
    }

    func set(effect: HueEffect, speed: UInt8, source: WriteSource = .user) {
        noteWrite(source)
        enqueue(HueUUID.combined, HueWire.data(effect: effect, speed: max(1, speed)))
    }

    /// Flash the bulb once so the user can tell which one it is.
    func identify() {
        enqueue(HueUUID.alert, HueWire.alertOnce)
    }

    /// Applies a full state (color before power so an off bulb doesn't flash its old color).
    func apply(_ newState: LightState, source: WriteSource = .user) {
        noteWrite(source)
        guard newState.on else {
            enqueue(HueUUID.power, HueWire.data(power: false))
            return
        }
        enqueueColor(newState.color)
        enqueue(HueUUID.brightness, HueWire.data(brightness: newState.brightness))
        enqueue(HueUUID.power, HueWire.data(power: true))
        if newState.effect != .none || state.effect != .none {
            enqueue(HueUUID.combined, HueWire.data(effect: newState.effect, speed: newState.effectSpeed))
        }
    }

    /// Stores the name locally, then best-effort writes it to the bulb's name characteristic.
    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        info.name = trimmed
        notifyInfoChanged(immediate: true)
        guard let char = charMap[HueUUID.name],
              char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse),
              let data = trimmed.data(using: .utf8) else {
            log("rename: name characteristic not writable/present, kept locally only", .debug)
            return
        }
        enqueue(HueUUID.name, data)
    }

    /// Resolves once the light is `.ready`; throws on timeout. Used by the scheduler (connect on demand).
    func ensureReady(timeout: TimeInterval) async throws {
        if connection.isReady { return }
        guard peripheral != nil else {
            throw HueLightError("\(info.name) was not found — rescan to find it")
        }
        wantsConnection = true
        var needsConnect = peripheral?.state != .connected
        if case .pairingFailed = connection { needsConnect = true }
        if needsConnect { central?.connect(self) }

        let token = UUID()
        let deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, timeout)))
            guard !Task.isCancelled, let self else { return }
            self.failReadyWaiter(token, HueLightError("\(self.info.name) did not become ready within \(Int(timeout.rounded())) s (\(self.connection.label))"))
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if connection.isReady {
                continuation.resume()
            } else {
                readyWaiters[token] = continuation
            }
        }
    }

    /// Re-reads the combined state.
    func refresh() {
        if !issueRead(HueUUID.combined) {
            log("refresh: combined-state characteristic unavailable", .debug)
        }
    }

    /// Diagnostics: raw read/write of any characteristic.
    func readRaw(_ uuid: CBUUID) {
        guard charMap[uuid] != nil else {
            lastError = "No characteristic \(HueUUID.label(uuid)) on this bulb"
            log("readRaw: \(HueUUID.label(uuid)) not present", .warning)
            return
        }
        if !issueRead(uuid) {
            lastError = "\(HueUUID.label(uuid)) is not readable (or the bulb is disconnected)"
            log("readRaw: \(HueUUID.label(uuid)) not readable / not connected", .warning)
        }
    }

    func writeRaw(_ uuid: CBUUID, _ data: Data) {
        enqueue(uuid, data)
    }

    func setPowerOnDefault(_ state: LightState) {
        enqueue(HueUUID.powerOnDefault, state.encodePowerOnDefault())
    }

    /// Writes this Mac's UTC time into the bulb's clock (`1001`) so on-bulb alarms fire on time.
    func syncClock() {
        guard charMap[HueUUID.clock] != nil else {
            log("syncClock: no clock characteristic on this bulb", .debug)
            return
        }
        let now = UInt32(clamping: Int64(Date().timeIntervalSince1970.rounded()))
        log("syncClock: setting bulb clock to \(Date()) (was \(clockOffset.map { String(format: "%+.0f s", $0) } ?? "unread"))", .info)
        enqueue(HueUUID.clock, Data([UInt8(now & 0xFF), UInt8((now >> 8) & 0xFF), UInt8((now >> 16) & 0xFF), UInt8(now >> 24)]))
        clockOffset = 0
    }

    // MARK: - Hooks used by HueCentral

    func attach(peripheral: CBPeripheral) {
        if let existing = self.peripheral, existing !== peripheral {
            existing.delegate = nil
            stopLinkTimers()
            resetLinkState()
            if let f = inFlight {
                requeueIfNoNewer(f, countAttempt: false)
                inFlight = nil
            }
            log("attach: replacing peripheral object — rediscovery required", .debug)
            // Whatever the old object's link looked like, the new one has to be discovered from scratch.
            connection = wantsConnection ? .connecting : .disconnected
        }
        self.peripheral = peripheral
        peripheral.delegate = self
        if case .unavailable = connection {
            // Reachable again (Bluetooth back on / seen in a scan). The central decides whether to connect.
            connection = wantsConnection ? .connecting : .disconnected
        }
    }

    func detach() {
        stopLinkTimers()
        pending.removeAll()
        inFlight = nil
        peripheral?.delegate = nil
        peripheral = nil
        pairingStartedAt = nil
        resetLinkState()
        failReadyWaiters(HueLightError("\(info.name) was removed"))
        connection = .unavailable(.needsRescan)
    }

    /// The central issued (or is about to issue) `connect`; show "Waiting for bulb…" unless a link is live.
    func noteConnectIssued() {
        guard !connection.isConnectedOrBusy else { return }
        connection = .connecting
    }

    /// User-initiated retry from `.pairingFailed` (or a watchdog cycle): forget the pairing clock and
    /// go back to `.connecting` regardless of the current state.
    func resetForReconnect() {
        stopLinkTimers()
        pairingStartedAt = nil
        gateAttempts = 0
        consecutiveEncryptionErrors = 0
        resetLinkState()
        inFlight = nil
        lastError = nil
        connection = .connecting
    }

    /// The user (or `HueCentral.disconnect`) dropped this light on purpose. CoreBluetooth does not reliably
    /// report a cancelled *pending* connect, so the state is set here instead of waiting for a callback.
    func markDisconnected() {
        stopLinkTimers()
        if let f = inFlight {
            requeueIfNoNewer(f, countAttempt: false)
            inFlight = nil
        }
        resetLinkState()
        switch connection {
        case .pairingFailed, .unavailable: return   // both say more than "Disconnected" — keep them
        default: connection = .disconnected
        }
    }

    func handleConnected() {
        guard let peripheral else { return }
        stopLinkTimers()
        resetLinkState()
        gateAttempts = 0
        consecutiveEncryptionErrors = 0
        pruneStalePending()
        if let f = inFlight {
            requeueIfNoNewer(f, countAttempt: false)
            inFlight = nil
        }
        connection = .discovering
        log("connected, discovering services", .debug)
        peripheral.discoverServices(nil)
        discoveryWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.discoveryTimeout))
            guard !Task.isCancelled, let self, self.connection == .discovering else { return }
            self.log("discovery did not complete within \(Int(Self.discoveryTimeout)) s — cycling the connection", .warning)
            self.lastError = "Service discovery timed out"
            self.central?.cycle(self)
        }
    }

    func handleConnectFailed(error: Error?) {
        if let error {
            lastError = error.localizedDescription
            log("connect failed: \(describe(error))", .warning)
            if isBondBroken(error) {
                failPairing(bondBrokenReason(error))
                return
            }
        } else {
            log("connect failed (no error given)", .warning)
        }
        if case .unavailable = connection { return }
        if case .pairingFailed = connection { return }
        connection = wantsConnection ? .connecting : .disconnected
    }

    func handleDisconnected(error: Error?) {
        stopLinkTimers()
        if let f = inFlight {
            requeueIfNoNewer(f, countAttempt: false)
            inFlight = nil
        }
        resetLinkState()
        if let error {
            lastError = error.localizedDescription
            log("disconnected: \(describe(error))", .warning)
            if isBondBroken(error) {
                failPairing(bondBrokenReason(error))
                return
            }
        } else {
            log("disconnected", .info)
        }
        if case .unavailable = connection { return }
        if case .pairingFailed = connection { return }    // deliberate drop after a pairing failure — keep it visible
        connection = wantsConnection ? .connecting : .disconnected
    }

    func markUnavailable(_ reason: UnavailableReason) {
        stopLinkTimers()
        if let f = inFlight {
            requeueIfNoNewer(f, countAttempt: false)
            inFlight = nil
        }
        resetLinkState()
        if reason == .needsRescan {
            peripheral?.delegate = nil
            peripheral = nil
        }
        let message: String
        switch reason {
        case .bluetoothOff: message = "Bluetooth is off"
        case .unauthorized: message = "Bluetooth access denied"
        case .needsRescan: message = "\(info.name) was not found — rescan to find it"
        }
        failReadyWaiters(HueLightError(message))
        connection = .unavailable(reason)
    }

    func handleSeen(rssi: Int) {
        guard rssi != 127, rssi != 0 else { return }   // 127 = "unavailable" per the BLE spec
        if self.rssi != rssi { self.rssi = rssi }
    }

    // MARK: - Write queue

    private func noteWrite(_ source: WriteSource) {
        if source == .user { onUserWrite?(self) }
    }

    /// Picks the CT or xy characteristic, clamps, and drops the opposing pending color write so
    /// the last requested mode wins.
    private func enqueueColor(_ mode: ColorMode) {
        // Before discovery `charMap` is empty and `info` is our best guess; afterwards the bulb's
        // characteristics decide. Plain-white LWA/LWB bulbs have neither 0004 nor 0005.
        let discovered = !charMap.isEmpty
        let hasCT = discovered ? charMap[HueUUID.colorTemp] != nil : true
        let hasXY = discovered ? charMap[HueUUID.colorXY] != nil : info.supportsColor
        switch mode {
        case .ct(let m):
            guard hasCT else {
                log("color temperature not supported by this bulb (no 0004) — skipped", .debug)
                return
            }
            let clamped = HueWire.clampMireds(m, max: info.maxMireds)
            pending.removeValue(forKey: HueUUID.colorXY)
            enqueue(HueUUID.colorTemp, HueWire.data(mireds: clamped))
        case .xy(let p):
            guard hasXY else {
                guard hasCT else {
                    log("color not supported by this bulb (no 0004/0005) — skipped", .debug)
                    return
                }
                // White-ambiance bulb: approximate the requested color with a color temperature.
                let approx = HueWire.clampMireds(ColorMath.approxMireds(fromXY: p), max: info.maxMireds)
                log("xy requested on a white bulb — using \(approx) mireds instead", .debug)
                pending.removeValue(forKey: HueUUID.colorXY)
                enqueue(HueUUID.colorTemp, HueWire.data(mireds: approx))
                return
            }
            pending.removeValue(forKey: HueUUID.colorTemp)
            enqueue(HueUUID.colorXY, HueWire.data(xy: ColorMath.clampToGamutC(p)))
        }
    }

    private func enqueue(_ uuid: CBUUID, _ data: Data) {
        pending[uuid] = PendingWrite(data: data, attempts: 0, enqueuedAt: Date())
        pump()
    }

    private var isWriteAllowedNow: Bool {
        switch connection {
        case .ready, .pairing: return true
        default: return false
        }
    }

    private func nextPendingUUID() -> CBUUID? {
        for uuid in Self.writeOrder where pending[uuid] != nil { return uuid }
        return pending.keys.sorted { $0.uuidString < $1.uuidString }.first
    }

    private func pump() {
        guard inFlight == nil, isWriteAllowedNow,
              let peripheral, peripheral.state == .connected,
              let uuid = nextPendingUUID(),
              let entry = pending.removeValue(forKey: uuid) else { return }
        guard let char = charMap[uuid] else {
            lastError = "No characteristic \(HueUUID.label(uuid)) on this bulb"
            log("write dropped: \(HueUUID.label(uuid)) not present", .warning)
            pump()
            return
        }
        let type: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
        writeSerial += 1
        let serial = writeSerial
        inFlight = InFlightWrite(uuid: uuid, data: entry.data, attempts: entry.attempts, enqueuedAt: entry.enqueuedAt, serial: serial)
        log("write \(HueUUID.label(uuid)) = \(entry.data.hexString)\(entry.attempts > 0 ? " (retry \(entry.attempts))" : "")\(type == .withoutResponse ? " (no response)" : "")", .debug)
        peripheral.writeValue(entry.data, for: char, type: type)
        if type == .withoutResponse {
            completeWrite(uuid: uuid, error: nil)
        } else {
            armWriteWatchdog(serial: serial)
        }
    }

    /// A `.withResponse` write whose ack never comes would wedge the queue; after 5 s treat it as transient.
    private func armWriteWatchdog(serial: Int) {
        writeWatchdog?.cancel()
        writeWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.writeTimeout))
            guard !Task.isCancelled, let self, let f = self.inFlight, f.serial == serial else { return }
            self.log("write \(HueUUID.label(f.uuid)) got no response within \(Int(Self.writeTimeout)) s — requeuing", .warning)
            self.writeWatchdog = nil
            self.inFlight = nil
            self.requeueIfNoNewer(f, countAttempt: false)
            self.pump()
        }
    }

    private func schedulePump(after seconds: TimeInterval) {
        pumpTask?.cancel()
        pumpTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.pumpTask = nil
            self.pump()
        }
    }

    /// Puts an in-flight write back unless a newer value for the same characteristic arrived meanwhile.
    /// `countAttempt` is false for link-level reasons (pairing, disconnect) so those don't eat the retry budget.
    private func requeueIfNoNewer(_ f: InFlightWrite, countAttempt: Bool = true) {
        guard pending[f.uuid] == nil else { return }
        pending[f.uuid] = PendingWrite(data: f.data, attempts: f.attempts + (countAttempt ? 1 : 0), enqueuedAt: f.enqueuedAt)
    }

    /// A scheduled scene survives a link drop; a stale slider value from a minute ago doesn't.
    private func pruneStalePending() {
        let now = Date()
        let stale = pending.filter { now.timeIntervalSince($0.value.enqueuedAt) > Self.stalePendingAge }
        for (uuid, _) in stale {
            pending.removeValue(forKey: uuid)
            log("dropped stale queued write to \(HueUUID.label(uuid))", .debug)
        }
    }

    private func completeWrite(uuid: CBUUID, error: Error?) {
        guard let f = inFlight, f.uuid == uuid else {
            log("unexpected write acknowledgement for \(HueUUID.label(uuid))", .debug)
            return
        }
        inFlight = nil
        writeWatchdog?.cancel(); writeWatchdog = nil
        if let error {
            lastError = error.localizedDescription
            if isEncryptionError(error) {
                log("write \(HueUUID.label(uuid)) needs an encrypted link: \(describe(error))", .warning)
                requeueIfNoNewer(f, countAttempt: false)
                noteEncryptionError()
                enterPairing()
                schedulePump(after: currentPairingPollInterval)
                return
            }
            if isBondBroken(error) {
                log("write \(HueUUID.label(uuid)): \(describe(error))", .error)
                failPairing(bondBrokenReason(error))
                return
            }
            if f.attempts + 1 < Self.maxWriteAttempts {
                log("write \(HueUUID.label(uuid)) failed (attempt \(f.attempts + 1)): \(describe(error)) — retrying", .warning)
                requeueIfNoNewer(f)
                schedulePump(after: 0.25)
            } else {
                log("write \(HueUUID.label(uuid)) failed after \(f.attempts + 1) attempts: \(describe(error)) — dropped", .error)
                schedulePump(after: 0.05)
            }
            return
        }
        log("write \(HueUUID.label(uuid)) OK", .debug)
        applyOptimistic(uuid, f.data)
        if uuid == HueUUID.name {
            _ = issueRead(HueUUID.name)
        }
        if case .pairing = connection {
            // A write went through, so the link is encrypted — resume the discovery flow.
            onLinkEncrypted()
        }
        schedulePump(after: 0.05)
    }

    private func applyOptimistic(_ uuid: CBUUID, _ data: Data) {
        switch uuid {
        case HueUUID.power:
            guard let on = HueWire.decodePower(data) else { return }
            state.on = on
        case HueUUID.brightness:
            guard let b = HueWire.decodeBrightness(data) else { return }
            state.brightness = b
        case HueUUID.colorTemp:
            guard let m = HueWire.readU16le(data, at: 0), m != 0xFFFF else { return }
            state.color = .ct(mireds: m)
            lastHighMiredsWrite = m > Self.commonMiredsCap ? (m, Date()) : nil
        case HueUUID.colorXY:
            guard let xy = HueWire.decodeXY(data) else { return }
            state.color = .xy(xy)
        case HueUUID.combined:
            state = LightState.decode(combined: data, into: state)
        default:
            return
        }
        stateChanged()
    }

    private func isWritePendingOrInFlight(for uuid: CBUUID) -> Bool {
        pending[uuid] != nil || inFlight?.uuid == uuid
    }

    // MARK: - Discovery / pairing flow

    private func resetLinkState() {
        charMap.removeAll()
        servicesAwaitingCharacteristics.removeAll()
        outstandingReads.removeAll()
        initialReadsIssued = false
        awaitingCombinedForReady = false
        probeReads.removeAll()
        alarms.linkDropped()
        if !characteristics.isEmpty { characteristics = [] }
    }

    private func stopLinkTimers() {
        pairingPollTimer?.invalidate(); pairingPollTimer = nil
        keepAliveTimer?.invalidate(); keepAliveTimer = nil
        readyFallbackTask?.cancel(); readyFallbackTask = nil
        discoveryWatchdog?.cancel(); discoveryWatchdog = nil
        gateRetryTask?.cancel(); gateRetryTask = nil
        pumpTask?.cancel(); pumpTask = nil
        writeWatchdog?.cancel(); writeWatchdog = nil
    }

    private func onCharacteristicsDiscovered() {
        discoveryWatchdog?.cancel(); discoveryWatchdog = nil
        updateCapabilities()
        guard charMap[HueUUID.power] != nil else {
            lastError = "No Hue light service on this device"
            log("no Hue light service (power characteristic) found — not a Hue bulb?", .error)
            failPairing("no Hue light service found")
            return
        }
        issueGateRead()
    }

    /// The `power` read: succeeds only over an encrypted link, so it doubles as the pairing probe.
    private func issueGateRead() {
        gateAttempts += 1
        log("gate read of power (attempt \(gateAttempts)) — macOS may show a Connection Request now", .debug)
        if !issueRead(HueUUID.power) {
            log("gate read could not be issued", .warning)
        }
    }

    private func onLinkEncrypted() {
        pairingPollTimer?.invalidate(); pairingPollTimer = nil
        gateRetryTask?.cancel(); gateRetryTask = nil
        pairingStartedAt = nil
        gateAttempts = 0
        consecutiveEncryptionErrors = 0
        if case .pairing = connection {
            log("paired — link is encrypted", .info)
            connection = .discovering
        }
        guard let peripheral else { return }
        initialReadsIssued = true
        for uuid in HueUUID.initialReads where charMap[uuid] != nil {
            _ = issueRead(uuid)
        }
        for uuid in HueUUID.notifyCharacteristics {
            guard let char = charMap[uuid],
                  char.properties.contains(.notify) || char.properties.contains(.indicate) else { continue }
            peripheral.setNotifyValue(true, for: char)
        }
        awaitingCombinedForReady = charMap[HueUUID.combined] != nil
        if awaitingCombinedForReady {
            readyFallbackTask?.cancel()
            readyFallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.readyFallbackDelay))
                guard !Task.isCancelled, let self, self.connection == .discovering else { return }
                self.log("combined-state read did not answer within \(Int(Self.readyFallbackDelay)) s — marking ready anyway", .debug)
                self.becomeReady()
            }
        } else {
            becomeReady()
        }
    }

    private func becomeReady() {
        readyFallbackTask?.cancel(); readyFallbackTask = nil
        awaitingCombinedForReady = false
        guard connection != .ready else { return }
        connection = .ready
        lastError = nil
        startKeepAlive()
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for (_, continuation) in waiters { continuation.resume() }
        pump()
        if charMap[HueUUID.alarm] == nil {
            alarms.markUnsupported()
        } else {
            alarms.refresh()
        }
        probeUndocumentedCharacteristics()
    }

    /// Reads every readable characteristic we don't otherwise touch, once per link, and logs the
    /// raw bytes at info level — how the clock characteristic (if any) will be found.
    private func probeUndocumentedCharacteristics() {
        guard probeReads.isEmpty else { return }
        let known: Set<CBUUID> = Set(HueUUID.initialReads + HueUUID.notifyCharacteristics + [HueUUID.power, HueUUID.zigbeeAddress, HueUUID.alarm])
        for (uuid, char) in charMap where char.properties.contains(.read) && !known.contains(uuid) {
            probeReads.insert(uuid)
            _ = issueRead(uuid)
        }
        if !probeReads.isEmpty {
            log("probing \(probeReads.count) undocumented readable characteristic(s)", .debug)
        }
    }

    private func enterPairing() {
        if case .pairing = connection { return }
        let since = pairingStartedAt ?? Date()
        pairingStartedAt = since
        connection = .pairing(since: since)
        log("waiting for pairing — accept the Connection Request dialog on this Mac", .info)
        startPairingPoll()
    }

    private var currentPairingPollInterval: TimeInterval {
        consecutiveEncryptionErrors > Self.pairingSlowdownThreshold ? Self.pairingSlowPollInterval : Self.pairingPollInterval
    }

    /// Polls `power` while pairing. Keeping a poll going is what lets the user tap "Make Discoverable"
    /// in the phone app mid-wait; `.common` mode keeps it firing while a slider drags or a menu is open.
    private func startPairingPoll() {
        pairingPollTimer?.invalidate()
        let timer = Timer(timeInterval: currentPairingPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pairingPollTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pairingPollTimer = timer
    }

    /// Repeated CBATT 5/15 errors usually mean the user dismissed the macOS dialog (or the bulb is bonded to
    /// the phone and macOS shows nothing); slow the poll so it can't become a dialog storm.
    private func noteEncryptionError() {
        consecutiveEncryptionErrors += 1
        log("encryption error #\(consecutiveEncryptionErrors) in a row", .debug)
        if consecutiveEncryptionErrors == Self.pairingSlowdownThreshold + 1 {
            log("still not paired after \(consecutiveEncryptionErrors) attempts — slowing the pairing poll to \(Int(Self.pairingSlowPollInterval)) s", .info)
            if case .pairing = connection { startPairingPoll() }
        }
    }

    private func pairingPollTick() {
        guard case .pairing(let since) = connection else {
            pairingPollTimer?.invalidate(); pairingPollTimer = nil
            return
        }
        if Date().timeIntervalSince(since) > Self.pairingTimeout {
            failPairing("the Mac did not pair within \(Int(Self.pairingTimeout)) s")
            return
        }
        guard let peripheral, peripheral.state == .connected else { return }
        if (outstandingReads[HueUUID.power] ?? 0) == 0 {
            _ = issueRead(HueUUID.power)
        }
    }

    private func failPairing(_ reason: String) {
        stopLinkTimers()
        pairingStartedAt = nil
        gateAttempts = 0
        consecutiveEncryptionErrors = 0
        connection = .pairingFailed(reason)
        lastError = "Pairing failed: \(reason)"
        log("pairing failed: \(reason)", .error)
        wantsConnection = false
        failReadyWaiters(HueLightError("\(info.name): pairing failed — \(reason)"))
        // Drop the link so the bulb is free (and no reconnect loop re-triggers the dialog);
        // `handleDisconnected` keeps `.pairingFailed` visible because `wantsConnection` is false.
        central?.disconnect(self)
    }

    private func failReadyWaiter(_ token: UUID, _ error: Error) {
        guard let continuation = readyWaiters.removeValue(forKey: token) else { return }
        continuation.resume(throwing: error)
    }

    private func failReadyWaiters(_ error: Error) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for (_, continuation) in waiters { continuation.resume(throwing: error) }
    }

    // MARK: - Reads / keepalive

    @discardableResult
    private func issueRead(_ uuid: CBUUID) -> Bool {
        guard let peripheral, peripheral.state == .connected,
              let char = charMap[uuid], char.properties.contains(.read) else { return false }
        outstandingReads[uuid, default: 0] += 1
        peripheral.readValue(for: char)
        return true
    }

    private func consumeOutstandingRead(_ uuid: CBUUID) -> Bool {
        guard let n = outstandingReads[uuid], n > 0 else { return false }
        if n == 1 { outstandingReads.removeValue(forKey: uuid) } else { outstandingReads[uuid] = n - 1 }
        return true
    }

    /// One 15 s `.common`-mode timer: keepalive `power` read every 45 s (if enabled) and an RSSI refresh
    /// every 30 s so the detail view's dBm isn't frozen at the last scan.
    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        lastKeepAliveReadAt = Date()        // the initial reads just exercised the link
        lastRSSIReadAt = .distantPast       // refresh RSSI right away
        let timer = Timer(timeInterval: Self.linkTimerInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.linkTimerTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepAliveTimer = timer
        linkTimerTick()
    }

    private func linkTimerTick() {
        guard connection.isReady, let peripheral, peripheral.state == .connected else { return }
        let now = Date()
        if now.timeIntervalSince(lastRSSIReadAt) >= Self.rssiInterval - 1 {   // -1 s absorbs timer jitter
            lastRSSIReadAt = now
            peripheral.readRSSI()
        }
        if let central, central.keepAlive, now.timeIntervalSince(lastKeepAliveReadAt) >= Self.keepAliveInterval - 1 {
            lastKeepAliveReadAt = now
            log("keepalive read", .debug)
            _ = issueRead(HueUUID.power)
        }
    }

    // MARK: - Decoding

    private func handleValue(_ uuid: CBUUID, _ data: Data, wasRead: Bool) {
        rawValues[uuid] = data
        log("\(wasRead ? "read" : "notify") \(HueUUID.label(uuid)) = \(data.hexString)", probeReads.contains(uuid) ? .info : .debug)
        if uuid == HueUUID.alarm {
            // Request/response channel: responses arrive as notifies, often before the write ack.
            alarms.handleNotification(data)
            return
        }

        if !wasRead {
            let stale: Bool
            if uuid == HueUUID.combined {
                stale = !pending.isEmpty || inFlight != nil   // 0007 echoes every single-char write
            } else {
                stale = isWritePendingOrInFlight(for: uuid)
            }
            if stale {
                log("ignored notify for \(HueUUID.label(uuid)) while a write is queued", .debug)
                return
            }
        }

        switch uuid {
        case HueUUID.power:
            if let on = HueWire.decodePower(data) {
                state.on = on
                stateChanged()
            }
        case HueUUID.brightness:
            if let b = HueWire.decodeBrightness(data) {
                state.brightness = b
                stateChanged()
            }
        case HueUUID.colorTemp:
            if let m = HueWire.decodeMireds(data) {
                learnMaxMireds(reported: m)
                state.color = .ct(mireds: m)
                stateChanged()
            } else {
                log("color temperature reads as sentinel (bulb is in xy mode)", .debug)
            }
        case HueUUID.colorXY:
            if let xy = HueWire.decodeXY(data) {
                state.color = .xy(xy)
                stateChanged()
            } else {
                log("xy reads as sentinel (bulb is in CT mode)", .debug)
            }
        case HueUUID.combined:
            let decoded = LightState.decode(combined: data, into: state)
            if case .ct(let m) = decoded.color, decoded.color != state.color { learnMaxMireds(reported: m) }
            state = decoded
            stateChanged()
        case HueUUID.model:
            let value = HueWire.decodeString(data).flatMap { $0.isEmpty ? nil : $0 }
            if value != info.model {
                info.model = value
                log("model: \(value ?? "?")", .info)
                updateCapabilities()
                notifyInfoChanged(immediate: true)
            }
        case HueUUID.firmware:
            let value = HueWire.decodeString(data).flatMap { $0.isEmpty ? nil : $0 }
            if value != info.firmware {
                info.firmware = value
                log("firmware: \(value ?? "?")", .info)
                notifyInfoChanged(immediate: true)
            }
        case HueUUID.manufacturer:
            let value = HueWire.decodeString(data).flatMap { $0.isEmpty ? nil : $0 }
            if value != info.manufacturer {
                info.manufacturer = value
                log("manufacturer: \(value ?? "?")", .info)
                notifyInfoChanged(immediate: true)
            }
        case HueUUID.name:
            let value = HueWire.decodeString(data).flatMap { $0.isEmpty ? nil : $0 }
            var changed = false
            if value != info.bulbName {
                info.bulbName = value
                changed = true
                log("bulb name: \(value ?? "?")", .info)
            }
            if let value, hasGenericName, value != info.name {
                info.name = value
                changed = true
                log("adopted the bulb's own name “\(value)”", .info)
            }
            if changed { notifyInfoChanged(immediate: true) }
        case HueUUID.clock:
            guard data.count >= 4 else { break }
            let b = [UInt8](data)
            let epoch = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            let offset = TimeInterval(epoch) - Date().timeIntervalSince1970
            clockOffset = offset
            log("clock (1001): \(Date(timeIntervalSince1970: TimeInterval(epoch))) — \(String(format: "%+.0f", offset)) s vs this Mac", .info)
            if abs(offset) > Self.clockTolerance, wasRead {
                syncClock()
            }
        case HueUUID.capabilities:
            log("capabilities (0001): \(data.hexString)", .info)
        case HueUUID.powerOnDefault:
            log("power-on default (1005): \(data.hexString)", .info)
        case HueUUID.zigbeeAddress:
            log("zigbee address: \(data.hexString)", .info)
        default:
            break
        }
    }

    private func stateChanged() {
        info.lastState = state
        info.lastSeen = Date()
        notifyInfoChanged(immediate: false)
    }

    /// Throttles persistence-worthy `info` changes to once per second for state-only updates;
    /// identity changes (name/model/firmware/capabilities) fire immediately.
    private func notifyInfoChanged(immediate: Bool) {
        if immediate {
            infoNotifyTask?.cancel(); infoNotifyTask = nil
            lastInfoNotifyAt = Date()
            onInfoChanged?(self)
            return
        }
        let elapsed = Date().timeIntervalSince(lastInfoNotifyAt)
        if elapsed >= 1 {
            lastInfoNotifyAt = Date()
            onInfoChanged?(self)
        } else if infoNotifyTask == nil {
            infoNotifyTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0.05, 1 - elapsed)))
                guard !Task.isCancelled, let self else { return }
                self.infoNotifyTask = nil
                self.lastInfoNotifyAt = Date()
                self.onInfoChanged?(self)
            }
        }
    }

    /// Advertised names ("Hue Lamp", "Hue color lamp", the "Hue bulb" fallback…) are placeholders
    /// that the bulb's own name characteristic should override.
    private var hasGenericName: Bool {
        let n = info.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n == "hue bulb" || n == "hue lamp" || n == "hue" { return true }
        guard n.hasPrefix("hue ") else { return false }
        return ["lamp", "bulb", "light", "lightstrip", "strip", "spot", "candle", "filament"].contains { n.hasSuffix(" \($0)") || n == "hue \($0)" }
    }

    /// Color support = the xy characteristic exists and, when the model is known, it is a color model
    /// (Hue color models are LC* — LCA/LCT/LCL/LCG/LCE/LCX… — plus LST lightstrips).
    private func updateCapabilities() {
        guard !charMap.isEmpty else { return }
        let hasXY = charMap[HueUUID.colorXY] != nil
        let supports: Bool
        if let model = info.model?.uppercased().trimmingCharacters(in: .whitespaces), !model.isEmpty {
            let colorPrefixes = ["LCA", "LCT", "LCL", "LCG", "LST", "LC"]
            supports = hasXY && colorPrefixes.contains { model.hasPrefix($0) }
        } else {
            supports = hasXY
        }
        if supports != info.supportsColor {
            info.supportsColor = supports
            log("supportsColor learned: \(supports) (xy char: \(hasXY), model: \(info.model ?? "unknown"))", .info)
            notifyInfoChanged(immediate: true)
        }
    }

    /// After writing a CT above 454, a bulb that caps there reports the cap back — remember it.
    private func learnMaxMireds(reported: UInt16) {
        guard let w = lastHighMiredsWrite else { return }
        guard Date().timeIntervalSince(w.at) < 10 else { lastHighMiredsWrite = nil; return }
        lastHighMiredsWrite = nil
        guard reported < w.value, reported >= ColorMath.minMireds else { return }
        if info.maxMireds != reported {
            info.maxMireds = reported
            log("maxMireds learned: \(reported) (wrote \(w.value))", .info)
            notifyInfoChanged(immediate: true)
        }
    }

    // MARK: - Errors / logging

    private func isEncryptionError(_ error: Error) -> Bool {
        guard let att = error as? CBATTError else { return false }
        return att.code == .insufficientAuthentication || att.code == .insufficientEncryption
    }

    private func isBondBroken(_ error: Error) -> Bool {
        guard let cb = error as? CBError else { return false }
        return cb.code == .peerRemovedPairingInformation || cb.code == .encryptionTimedOut
    }

    private func bondBrokenReason(_ error: Error) -> String {
        if let cb = error as? CBError, cb.code == .peerRemovedPairingInformation {
            return "the bulb forgot this Mac (reset or re-paired elsewhere) — remove it in System Settings › Bluetooth, then retry"
        }
        return "encryption timed out — retry, and accept the Connection Request promptly"
    }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code) \(ns.localizedDescription)"
    }

    private func log(_ message: String, _ level: DebugLog.Level = .debug) {
        hueLog("[\(info.name)] \(message)", level: level)
    }
}

// MARK: - CBPeripheralDelegate

extension HueLight: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastError = error.localizedDescription
            log("service discovery failed: \(describe(error))", .error)
            return
        }
        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            lastError = "No services found"
            log("no services found", .warning)
            return
        }
        servicesAwaitingCharacteristics = Set(services.map(\.uuid))
        for service in services {
            log("service \(HueUUID.label(service.uuid))", .debug)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            log("characteristic discovery failed for \(HueUUID.label(service.uuid)): \(describe(error))", .warning)
        }
        var infos = characteristics.filter { $0.service != service.uuid }
        for char in service.characteristics ?? [] {
            charMap[char.uuid] = char
            let ci = CharacteristicInfo(service: service.uuid, uuid: char.uuid, properties: char.properties)
            infos.append(ci)
            log("  char \(HueUUID.label(char.uuid)) [\(ci.propertyText)]", .debug)
        }
        characteristics = infos
        servicesAwaitingCharacteristics.remove(service.uuid)
        if servicesAwaitingCharacteristics.isEmpty {
            onCharacteristicsDiscovered()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        let wasRead = consumeOutstandingRead(uuid)

        if let error {
            if probeReads.contains(uuid) {
                log("probe read \(HueUUID.label(uuid)) failed: \(describe(error))", .info)
                return
            }
            lastError = error.localizedDescription
            if isEncryptionError(error) {
                log("read \(HueUUID.label(uuid)) refused — link not encrypted: \(describe(error))", .info)
                noteEncryptionError()
                enterPairing()
                return
            }
            if isBondBroken(error) {
                log("read \(HueUUID.label(uuid)): \(describe(error))", .error)
                failPairing(bondBrokenReason(error))
                return
            }
            log("read \(HueUUID.label(uuid)) failed: \(describe(error))", .warning)
            if uuid == HueUUID.power, connection == .discovering, !initialReadsIssued {
                // The gate read itself failed with something other than an encryption error: retry a few
                // times, then let the discovery watchdog cycle the connection.
                if gateAttempts < 3 {
                    gateRetryTask?.cancel()
                    gateRetryTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled, let self, self.connection == .discovering, !self.initialReadsIssued else { return }
                        self.issueGateRead()
                    }
                }
            }
            return
        }

        guard let data = characteristic.value else { return }
        handleValue(uuid, data, wasRead: wasRead)

        // Any successful read proves the link is encrypted.
        if wasRead {
            if case .pairing = connection {
                onLinkEncrypted()
            } else if connection == .discovering, !initialReadsIssued {
                onLinkEncrypted()
            } else if uuid == HueUUID.combined, awaitingCombinedForReady {
                becomeReady()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        completeWrite(uuid: characteristic.uuid, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("notify subscription for \(HueUUID.label(characteristic.uuid)) failed: \(describe(error))", .warning)
            if isEncryptionError(error) {
                noteEncryptionError()
                enterPairing()
            }
            return
        }
        log("notifications \(characteristic.isNotifying ? "on" : "off") for \(HueUUID.label(characteristic.uuid))", .debug)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        handleSeen(rssi: RSSI.intValue)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log("services modified (\(invalidatedServices.map { HueUUID.label($0.uuid) }.joined(separator: ", "))) — rediscovering", .warning)
        guard connection.isConnectedOrBusy else { return }
        central?.cycle(self)
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        log("advertised name changed to \(peripheral.name ?? "nil")", .debug)
    }
}
