import Foundation
import Combine

/// Request/response client for the bulb's on-board alarm characteristic (`9da2ddf1-0001`).
///
/// One request is in flight at a time: each write is answered by a notification whose first byte
/// echoes the opcode; writes and deletes are followed by a second `04` "committed" notification
/// that is informational. `HueLight` owns one of these, routes notifications into
/// `handleNotification` and provides `send`.
@MainActor
final class HueAlarmClient: ObservableObject {
    enum Status: Equatable {
        case idle
        case busy(String)
        case error(String)
        case unsupported
    }

    struct Outcome: Equatable {
        var message: String
        var isError: Bool
        var at: Date
    }

    @Published private(set) var alarms: [HueAlarm] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastRefreshed: Date?
    /// Result of the last write / delete / create, for the UI.
    @Published private(set) var lastOutcome: Outcome?

    /// Writes a request to the characteristic (set by `HueLight`).
    var send: ((Data) -> Void)?
    var log: ((String, DebugLog.Level) -> Void)?
    var clock: () -> Date = { Date() }
    var timeout: TimeInterval = 6

    private struct Request {
        enum Kind: Equatable {
            case list
            case detail(UInt16)
            case write(id: UInt16, name: String)
            case delete(UInt16)
        }
        let kind: Kind
        let data: Data

        var opcode: UInt8 { data.first ?? 0xFF }
    }

    private var queue: [Request] = []
    private var inFlight: Request?
    private var timeoutTask: Task<Void, Never>?
    private var pendingDetailIDs: Set<UInt16> = []
    private var collected: [HueAlarm] = []
    private var refreshing = false

    var isBusy: Bool { inFlight != nil || !queue.isEmpty }

    // MARK: - Commands

    /// Reloads the alarm list from the bulb.
    func refresh() {
        guard status != .unsupported else { return }
        guard !refreshing else { return }
        refreshing = true
        collected = []
        pendingDetailIDs = []
        status = .busy("Reading alarms…")
        enqueue(Request(kind: .list, data: HueAlarm.Request.list))
    }

    /// Re-arms (next occurrence / restart countdown) or disarms an alarm the bulb already holds.
    func setEnabled(_ alarm: HueAlarm, _ enabled: Bool) {
        let updated = alarm.settingEnabled(enabled, now: clock())
        write(updated, id: alarm.id, label: enabled ? "enable" : "disable")
    }

    /// Writes a brand-new alarm (fresh UUID, slot `0xFFFF`). Experimental: the bulb assigns the id.
    func create(_ alarm: HueAlarm) {
        write(alarm, id: HueAlarm.Request.createID, label: "create")
    }

    /// Rewrites an existing alarm in place (time, action, name).
    func update(_ alarm: HueAlarm) {
        write(alarm, id: alarm.id, label: "update")
    }

    func delete(_ alarm: HueAlarm) {
        status = .busy("Deleting “\(alarm.name)”…")
        enqueue(Request(kind: .delete(alarm.id), data: HueAlarm.Request.delete(alarm.id)))
    }

    private func write(_ alarm: HueAlarm, id: UInt16, label: String) {
        let data = HueAlarm.Request.write(alarm, id: id)
        log?("\(label) “\(alarm.name)” (slot \(id == HueAlarm.Request.createID ? "new" : String(id))): \(data.hexString)", .info)
        status = .busy("Writing “\(alarm.name)”…")
        enqueue(Request(kind: .write(id: id, name: alarm.name), data: data))
    }

    /// The characteristic isn't on this bulb.
    func markUnsupported() {
        status = .unsupported
        queue.removeAll()
        inFlight = nil
        timeoutTask?.cancel()
    }

    /// Link dropped: forget everything in progress (the list is kept for display).
    func linkDropped() {
        queue.removeAll()
        inFlight = nil
        refreshing = false
        timeoutTask?.cancel(); timeoutTask = nil
        if case .busy = status { status = .idle }
    }

    // MARK: - Responses

    func handleNotification(_ data: Data) {
        guard let opcode = data.first else { return }
        if HueAlarm.isConfirm(data) {
            log?("committed: \(data.hexString)", .debug)
            return
        }
        guard let request = inFlight else {
            log?("unsolicited alarm notification \(data.hexString)", .debug)
            return
        }
        guard opcode == request.opcode else {
            log?("expected a \(String(format: "%02X", request.opcode)) response, got \(data.hexString)", .warning)
            return
        }
        timeoutTask?.cancel(); timeoutTask = nil
        inFlight = nil

        switch request.kind {
        case .list:
            guard let list = HueAlarm.parseList(data) else { return fail("Unreadable alarm list (\(data.hexString))") }
            guard list.status == 0 else { return fail("Alarm list refused (status \(list.status))") }
            log?("\(list.ids.count) alarm(s) on the bulb: \(list.ids)", .info)
            if list.ids.isEmpty {
                finishRefresh()
            } else {
                pendingDetailIDs = Set(list.ids)
                for id in list.ids {
                    queue.append(Request(kind: .detail(id), data: HueAlarm.Request.detail(id)))
                }
            }

        case .detail(let id):
            if let detail = HueAlarm.parseDetail(data) {
                if let alarm = detail.alarm {
                    collected.append(alarm)
                    log?("alarm \(id) “\(alarm.name)” \(alarm.isEnabled ? "armed" : "off") fires \(alarm.fireAt) \(alarm.isTimer ? "timer \(alarm.durationSeconds ?? 0) s" : "routine") uuid \(alarm.uuid.uuidString.lowercased())", .info)
                } else {
                    log?("alarm \(id): undecodable (status \(detail.status)) \(data.hexString)", .warning)
                }
            } else {
                log?("alarm \(id): unreadable response \(data.hexString)", .warning)
            }
            pendingDetailIDs.remove(id)
            if pendingDetailIDs.isEmpty { finishRefresh() }

        case .write(let id, let name):
            guard let ack = HueAlarm.parseAck(data) else { return fail("Unreadable write acknowledgement (\(data.hexString))") }
            if ack.status == 0 {
                let slot = ack.id.map(String.init) ?? "?"
                let message = id == HueAlarm.Request.createID ? "Created “\(name)” in slot \(slot)" : "Saved “\(name)”"
                log?(message + " (\(data.hexString))", .info)
                lastOutcome = Outcome(message: message, isError: false, at: clock())
                status = .idle
                refresh()
            } else {
                let message = "Bulb refused “\(name)” (status \(ack.status), \(data.hexString))"
                log?(message, .warning)
                lastOutcome = Outcome(message: message, isError: true, at: clock())
                status = .error(message)
            }

        case .delete(let id):
            guard let ack = HueAlarm.parseAck(data) else { return fail("Unreadable delete acknowledgement (\(data.hexString))") }
            if ack.status == 0 {
                log?("deleted alarm \(id)", .info)
                lastOutcome = Outcome(message: "Deleted", isError: false, at: clock())
                alarms.removeAll { $0.id == id }
                status = .idle
                refresh()
            } else {
                fail("Delete of alarm \(id) refused (status \(ack.status))")
            }
        }
        pumpNext()
    }

    // MARK: - Internals

    private func finishRefresh() {
        alarms = collected.sorted { $0.fireAt < $1.fireAt }
        collected = []
        refreshing = false
        lastRefreshed = clock()
        if case .busy = status { status = .idle }
    }

    private func fail(_ message: String) {
        log?(message, .warning)
        status = .error(message)
        lastOutcome = Outcome(message: message, isError: true, at: clock())
        refreshing = false
        queue.removeAll()
        inFlight = nil
        timeoutTask?.cancel(); timeoutTask = nil
    }

    private func enqueue(_ request: Request) {
        queue.append(request)
        pumpNext()
    }

    private func pumpNext() {
        guard inFlight == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        inFlight = request
        send?(request.data)
        let limit = timeout
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self, let current = self.inFlight, current.kind == request.kind else { return }
            self.fail("No answer from the bulb for \(String(format: "%02X", current.opcode)) within \(Int(limit)) s")
        }
    }
}
