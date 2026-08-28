import Foundation
import CoreBluetooth

struct DiscoveredBulb: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    /// Which advertisement key carried FE0F ("serviceUUIDs" / "serviceData").
    var foundVia: String
    var lastSeen: Date
    let peripheral: CBPeripheral
    var isKnown: Bool

    static func == (lhs: DiscoveredBulb, rhs: DiscoveredBulb) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rssi == rhs.rssi && lhs.isKnown == rhs.isKnown
    }
}

/// Owns the `CBCentralManager`; scans for Hue bulbs, restores remembered ones, and keeps them connected.
///
/// The central is created with `queue: nil`, so every CoreBluetooth callback lands on the main queue
/// and the `@preconcurrency` delegate conformance below is safe.
@MainActor
final class HueCentral: NSObject, ObservableObject {
    @Published private(set) var managerState: CBManagerState = .unknown
    @Published private(set) var lights: [HueLight] = []
    @Published private(set) var discovered: [DiscoveredBulb] = []
    @Published private(set) var isScanning = false

    /// Fired whenever `lights` or any light's `info` changes (AppModel persists).
    var onLightsChanged: (() -> Void)?
    /// Periodic keepalive read while connected (Settings → keepLightsConnected).
    var keepAlive = true

    var knownLights: [KnownLight] { lights.map(\.info) }
    var isPoweredOn: Bool { managerState == .poweredOn }
    var isUnauthorized: Bool { managerState == .unauthorized }

    private var manager: CBCentralManager?
    /// Delegate routing table (peripheral identifier → light).
    private var lightsByID: [UUID: HueLight] = [:]
    /// Recent disconnect timestamps per light, for the reconnect-loop guard.
    private var disconnectHistory: [UUID: [Date]] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]

    private static let scanServices: [CBUUID] = [HueUUID.lightService, HueUUID.signify]
    private static let loopGuardWindow: TimeInterval = 30
    private static let loopGuardThreshold = 3
    private static let loopGuardDelay: TimeInterval = 5
    private static let failedConnectRetryDelay: TimeInterval = 2
    private static let genericBulbName = "Hue bulb"

    init(known: [KnownLight]) {
        super.init()
        lights = known.map { HueLight(info: $0) }
        lights.forEach { wire($0) }
    }

    /// Creates the `CBCentralManager` (this is what triggers the macOS Bluetooth permission prompt).
    func start() {
        guard manager == nil else { return }
        hueLog("Central: starting CBCentralManager", level: .info)
        manager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Scanning

    func startScan() {
        guard let manager, managerState == .poweredOn else {
            hueLog("Central: cannot scan — Bluetooth is \(Self.describe(managerState))", level: .warning)
            isScanning = false
            return
        }
        discovered = []
        isScanning = true
        hueLog("Central: scanning for Hue bulbs (FE0F)", level: .info)
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        if manager?.isScanning == true { manager?.stopScan() }
        if isScanning {
            isScanning = false
            hueLog("Central: scan stopped (\(discovered.count) bulb\(discovered.count == 1 ? "" : "s") seen)", level: .info)
        }
    }

    // MARK: - Adding / forgetting

    @discardableResult func add(_ bulb: DiscoveredBulb) -> HueLight {
        if let existing = lightsByID[bulb.id] {
            hueLog("Central: \(bulb.name) is already remembered", level: .debug)
            existing.attach(peripheral: bulb.peripheral)
            connect(existing)
            return existing
        }
        let light = HueLight(info: KnownLight(id: bulb.id, name: bulb.name))
        wire(light)
        light.attach(peripheral: bulb.peripheral)
        light.handleSeen(rssi: bulb.rssi)
        lights.append(light)
        markDiscovered(bulb.id, known: true)
        hueLog("Central: added \(bulb.name) (\(bulb.id.uuidString), via \(bulb.foundVia))", level: .info)
        connect(light)
        onLightsChanged?()
        return light
    }

    /// Replaces a remembered light (e.g. after a factory reset changed its address) keeping its name;
    /// callers (AppModel) migrate scene/schedule references from `old.id` to the new id.
    @discardableResult func add(_ bulb: DiscoveredBulb, replacing old: HueLight) -> HueLight {
        if old.id == bulb.id { return add(bulb) }
        var info = KnownLight(id: bulb.id, name: old.info.name)
        info.addedAt = old.info.addedAt
        let light = HueLight(info: info)
        wire(light)
        light.attach(peripheral: bulb.peripheral)
        light.handleSeen(rssi: bulb.rssi)

        let index = lights.firstIndex { $0 === old } ?? lights.count
        remove(old)
        lights.insert(light, at: min(index, lights.count))
        markDiscovered(bulb.id, known: true)
        hueLog("Central: replaced \(old.info.name) (\(old.id.uuidString)) with \(bulb.id.uuidString)", level: .info)
        connect(light)
        onLightsChanged?()
        return light
    }

    func forget(_ light: HueLight) {
        hueLog("Central: forgetting \(light.name) (\(light.id.uuidString))", level: .info)
        remove(light)
        onLightsChanged?()
    }

    // MARK: - Connections

    func connect(_ light: HueLight) {
        light.wantsConnection = true
        cancelReconnect(light)
        guard let manager, managerState == .poweredOn else {
            // Picked up by `centralManagerDidUpdateState` once Bluetooth is on.
            return
        }
        guard let peripheral = light.peripheral else {
            light.markUnavailable(.needsRescan)
            return
        }
        if case .pairingFailed = light.connection {
            cycle(light)
            return
        }
        switch peripheral.state {
        case .connected:
            if !light.connection.isConnectedOrBusy { light.handleConnected() }
        case .connecting:
            light.noteConnectIssued()
        default:
            light.noteConnectIssued()
            hueLog("Central: connect → \(light.name)", level: .debug)
            manager.connect(peripheral, options: nil)
        }
    }

    func disconnect(_ light: HueLight) {
        light.wantsConnection = false
        cancelReconnect(light)
        // Set the state now: CoreBluetooth does not reliably deliver `didDisconnectPeripheral` for a
        // cancelled *pending* connect, so waiting for the callback could leave the light "Waiting for bulb…".
        light.markDisconnected()
        guard let manager, let peripheral = light.peripheral, peripheral.state != .disconnected else { return }
        hueLog("Central: disconnect → \(light.name)", level: .debug)
        manager.cancelPeripheralConnection(peripheral)
    }

    /// Drops the current link and reconnects — used for pairing retries and when discovery stalls.
    /// A live link is cancelled (the disconnect callback re-issues `connect` because `wantsConnection`
    /// is true); a pending or absent one just gets `connect` re-issued, which is idempotent.
    func cycle(_ light: HueLight) {
        light.wantsConnection = true
        cancelReconnect(light)
        guard let manager, managerState == .poweredOn, let peripheral = light.peripheral else { return }
        light.resetForReconnect()
        switch peripheral.state {
        case .connected, .disconnecting:
            hueLog("Central: cycling connection → \(light.name)", level: .debug)
            manager.cancelPeripheralConnection(peripheral)
        default:
            hueLog("Central: connect (retry) → \(light.name)", level: .debug)
            manager.connect(peripheral, options: nil)
        }
    }

    func connectAll() {
        lights.forEach { connect($0) }
    }

    /// Drops every link so the phone Hue app can connect (bulbs accept one central at a time).
    func disconnectAll() {
        hueLog("Central: disconnecting all lights", level: .info)
        lights.forEach { disconnect($0) }
    }

    /// Re-issues pending connects after system wake.
    func reconnectAfterWake() {
        hueLog("Central: reconnect after wake (Bluetooth \(Self.describe(managerState)))", level: .info)
        guard managerState == .poweredOn else { return }
        for light in lights where light.wantsConnection {
            guard let peripheral = light.peripheral else { continue }
            if peripheral.state != .connected {
                connect(light)
            } else if !light.connection.isConnectedOrBusy {
                light.handleConnected()
            }
        }
    }

    func light(id: UUID) -> HueLight? { lightsByID[id] ?? lights.first { $0.id == id } }

    // MARK: - Private

    private func wire(_ light: HueLight) {
        light.central = self
        light.onInfoChanged = { [weak self] _ in self?.onLightsChanged?() }
        lightsByID[light.id] = light
    }

    private func remove(_ light: HueLight) {
        light.wantsConnection = false
        cancelReconnect(light)
        if let manager, let peripheral = light.peripheral, peripheral.state != .disconnected {
            manager.cancelPeripheralConnection(peripheral)
        }
        light.detach()
        light.onInfoChanged = nil
        lightsByID.removeValue(forKey: light.id)
        disconnectHistory.removeValue(forKey: light.id)
        lights.removeAll { $0 === light }
        markDiscovered(light.id, known: false)
    }

    private func markDiscovered(_ id: UUID, known: Bool) {
        guard let index = discovered.firstIndex(where: { $0.id == id }), discovered[index].isKnown != known else { return }
        discovered[index].isKnown = known
    }

    private func cancelReconnect(_ light: HueLight) {
        reconnectTasks[light.id]?.cancel()
        reconnectTasks.removeValue(forKey: light.id)
    }

    private func scheduleReconnect(_ light: HueLight, after delay: TimeInterval) {
        cancelReconnect(light)
        reconnectTasks[light.id] = Task { @MainActor [weak self, weak light] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let light else { return }
            self.reconnectTasks.removeValue(forKey: light.id)
            guard light.wantsConnection, self.lightsByID[light.id] === light else { return }
            self.connect(light)
        }
    }

    /// Restores remembered bulbs once the radio is on. Idempotent: the state bounces around sleep.
    private func restoreKnownLights() {
        guard let manager else { return }
        let ids = lights.map(\.id)
        guard !ids.isEmpty else { return }
        var found: Set<UUID> = []

        for peripheral in manager.retrievePeripherals(withIdentifiers: ids) {
            guard let light = lightsByID[peripheral.identifier] else { continue }
            found.insert(light.id)
            adopt(peripheral, for: light)
        }
        // Links the system already holds (another app, or left over from before a relaunch).
        for peripheral in manager.retrieveConnectedPeripherals(withServices: Self.scanServices) {
            guard let light = lightsByID[peripheral.identifier] else { continue }
            if !found.contains(light.id) {
                found.insert(light.id)
                adopt(peripheral, for: light)
            }
        }
        for light in lights where !found.contains(light.id) {
            hueLog("Central: \(light.name) (\(light.id.uuidString)) is not retrievable — address changed? needs a rescan", level: .warning)
            light.markUnavailable(.needsRescan)
        }
    }

    private func adopt(_ peripheral: CBPeripheral, for light: HueLight) {
        light.attach(peripheral: peripheral)
        guard light.wantsConnection else { return }
        switch peripheral.state {
        case .connected:
            if !light.connection.isConnectedOrBusy {
                hueLog("Central: adopting existing link to \(light.name)", level: .debug)
                light.handleConnected()
            }
        case .connecting:
            light.noteConnectIssued()
        default:
            connect(light)
        }
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "off"
        case .poweredOn: return "on"
        @unknown default: return "state \(state.rawValue)"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension HueCentral: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        managerState = state
        hueLog("Central: Bluetooth \(Self.describe(state))", level: state == .poweredOn ? .info : .warning)
        if state != .poweredOn, isScanning { isScanning = false }

        switch state {
        case .poweredOn:
            restoreKnownLights()
        case .poweredOff, .unsupported:
            lights.forEach { $0.markUnavailable(.bluetoothOff) }
        case .unauthorized:
            lights.forEach { $0.markUnavailable(.unauthorized) }
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflowUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]

        let foundVia: String
        if serviceUUIDs.contains(HueUUID.signify) {
            foundVia = "serviceUUIDs"
        } else if serviceData[HueUUID.signify] != nil {
            foundVia = "serviceData"
        } else if overflowUUIDs.contains(HueUUID.signify) {
            foundVia = "overflowServiceUUIDs"
        } else {
            return
        }

        let rssi = RSSI.intValue
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? Self.genericBulbName
        let known = lightsByID[peripheral.identifier]
        let now = Date()

        if let light = known {
            light.handleSeen(rssi: rssi)
            if case .unavailable(.needsRescan) = light.connection, managerState == .poweredOn {
                hueLog("Central: \(light.name) reappeared in a scan — reattaching", level: .info)
                adopt(peripheral, for: light)
            }
        }

        if let index = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            var bulb = discovered[index]
            let materiallyChanged = abs(bulb.rssi - rssi) >= 4 || bulb.name != displayName || bulb.isKnown != (known != nil)
                || now.timeIntervalSince(bulb.lastSeen) > 2
            guard materiallyChanged else { return }
            bulb.rssi = rssi
            bulb.name = displayName
            bulb.foundVia = foundVia
            bulb.lastSeen = now
            bulb.isKnown = known != nil
            discovered[index] = bulb
        } else {
            hueLog("Central: discovered \(displayName) \(peripheral.identifier.uuidString) rssi \(rssi) via \(foundVia)\(known != nil ? " (known)" : "")", level: .info)
            discovered.append(DiscoveredBulb(id: peripheral.identifier, name: displayName, rssi: rssi, foundVia: foundVia,
                                             lastSeen: now, peripheral: peripheral, isKnown: known != nil))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let light = lightsByID[peripheral.identifier] else {
            hueLog("Central: connected to unknown peripheral \(peripheral.identifier.uuidString) — dropping", level: .debug)
            central.cancelPeripheralConnection(peripheral)
            return
        }
        hueLog("Central: connected → \(light.name)", level: .info)
        light.handleConnected()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let light = lightsByID[peripheral.identifier] else { return }
        hueLog("Central: failed to connect → \(light.name): \(error?.localizedDescription ?? "no error")", level: .warning)
        light.handleConnectFailed(error: error)
        if light.wantsConnection, managerState == .poweredOn {
            scheduleReconnect(light, after: Self.failedConnectRetryDelay)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let light = lightsByID[peripheral.identifier] else { return }
        hueLog("Central: disconnected → \(light.name)\(error.map { ": \($0.localizedDescription)" } ?? "")", level: error == nil ? .info : .warning)
        light.handleDisconnected(error: error)
        guard light.wantsConnection, managerState == .poweredOn else { return }

        let now = Date()
        var recent = (disconnectHistory[light.id] ?? []).filter { now.timeIntervalSince($0) < Self.loopGuardWindow }
        recent.append(now)
        disconnectHistory[light.id] = recent
        if recent.count > Self.loopGuardThreshold {
            hueLog("Central: \(light.name) dropped \(recent.count) times in \(Int(Self.loopGuardWindow)) s — waiting \(Int(Self.loopGuardDelay)) s before reconnecting", level: .warning)
            scheduleReconnect(light, after: Self.loopGuardDelay)
        } else {
            connect(light)
        }
    }
}
