import SwiftUI
import AppKit
import CoreBluetooth

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiagnosticsOverview(central: model.central, settings: model.settings)

                if model.lights.isEmpty {
                    Text("No lights added yet — use Add Light to pair a bulb.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.lights) { light in
                    LightDiagnosticsCard(light: light)
                }

                DiagnosticsLogSection(log: DebugLog.shared)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Diagnostics")
    }
}

// MARK: - Overview

private struct DiagnosticsOverview: View {
    @ObservedObject var central: HueCentral
    let settings: AppSettings

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Bluetooth").foregroundStyle(.secondary)
                    Text(Self.describe(central.managerState))
                }
                GridRow {
                    Text("Lights").foregroundStyle(.secondary)
                    Text("\(central.lights.count) remembered")
                }
                GridRow {
                    Text("Keep-alive").foregroundStyle(.secondary)
                    Text(central.keepAlive ? "On" : "Off")
                        + Text(settings.keepLightsConnected ? " (Keep lights connected is on)" : " (Keep lights connected is off)")
                            .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Data folder").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(Store.directory.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([Store.directory])
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("System", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Unknown (starting up)"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported on this Mac"
        case .unauthorized: return "Unauthorized — allow openHue in System Settings → Privacy & Security → Bluetooth"
        case .poweredOff: return "Powered off"
        case .poweredOn: return "Powered on"
        @unknown default: return "Unknown state (\(state.rawValue))"
        }
    }
}

// MARK: - Per-light card

private struct LightDiagnosticsCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var light: HueLight

    private enum PowerOnChoice: Hashable { case restoreLast, warmWhite, custom }

    @State private var showCharacteristics = false
    @State private var confirmForget = false
    @State private var writeUUID = HueUUID.combined.uuidString
    @State private var writeHex = ""
    @State private var writeError: String?
    @State private var powerOnChoice: PowerOnChoice = .restoreLast

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header
                infoGrid
                stateLine
                actionButtons

                Divider()

                rawCallouts

                DisclosureGroup("Characteristics", isExpanded: $showCharacteristics) {
                    VStack(alignment: .leading, spacing: 10) {
                        characteristicsGrid
                        rawWriteRow
                    }
                    .padding(.top, 6)
                }

                Divider()

                powerOnForm
            }
            .padding(4)
        } label: {
            Label(light.name, systemImage: "lightbulb")
        }
        .confirmationDialog("Forget “\(light.name)”?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { model.forgetLight(light) }
        } message: {
            Text("Removes the light and its scene/schedule references. The bulb's pairing in System Settings → Bluetooth is not touched.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(light.connection.isReady ? Color.green : (light.connection.isConnectedOrBusy ? Color.orange : Color.secondary))
                .frame(width: 8, height: 8)
            Text(light.connection.label)
                .font(.callout.weight(.medium))
            if let rssi = light.rssi {
                Text("· \(rssi) dBm")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(light.id.uuidString)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
            GridRow {
                Text("Model").foregroundStyle(.secondary)
                Text(light.info.model ?? "—")
                Text("Firmware").foregroundStyle(.secondary)
                Text(light.info.firmware ?? "—")
            }
            GridRow {
                Text("Manufacturer").foregroundStyle(.secondary)
                Text(light.info.manufacturer ?? "—")
                Text("Bulb name").foregroundStyle(.secondary)
                Text(light.info.bulbName ?? "—")
            }
            GridRow {
                Text("Color").foregroundStyle(.secondary)
                Text(light.supportsColor ? "Yes (xy + CT)" : "No (CT only)")
                Text("Max mireds").foregroundStyle(.secondary)
                Text("\(light.maxMireds) (\(Int(ColorMath.kelvin(fromMireds: light.maxMireds))) K)")
            }
            GridRow {
                Text("Last seen").foregroundStyle(.secondary)
                Text(light.info.lastSeen.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                Text("Added").foregroundStyle(.secondary)
                Text(light.info.addedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .font(.callout)
    }

    private var stateLine: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(light.state.displayColor)
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary))
            Text(Self.describe(light.state))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("Refresh") { light.refresh() }
                .disabled(!light.connection.isReady)
            Button("Identify") { light.identify() }
                .disabled(!light.connection.isReady)
            if light.connection.isConnectedOrBusy {
                Button("Disconnect") { model.central.disconnect(light) }
            } else {
                Button("Connect") { model.central.connect(light) }
            }
            Spacer()
            Button("Forget…", role: .destructive) { confirmForget = true }
        }
        .controlSize(.small)
    }

    private var rawCallouts: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            rawRow("Capabilities (0001)", HueUUID.capabilities)
            rawRow("Combined state (0007)", HueUUID.combined)
            rawRow("Power-on default (1005)", HueUUID.powerOnDefault)
        }
        .font(.callout)
    }

    private func rawRow(_ title: String, _ uuid: CBUUID) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(light.rawValues[uuid]?.hexString ?? "—")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Button("Read") { light.readRaw(uuid) }
                .controlSize(.small)
                .disabled(!light.connection.isReady)
        }
    }

    @ViewBuilder private var characteristicsGrid: some View {
        if light.characteristics.isEmpty {
            Text("Characteristics appear once the bulb is connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Service").font(.caption.weight(.semibold))
                    Text("Characteristic").font(.caption.weight(.semibold))
                    Text("Props").font(.caption.weight(.semibold))
                    Text("Last value").font(.caption.weight(.semibold))
                    Text("")
                }
                ForEach(light.characteristics) { characteristic in
                    GridRow {
                        Text(HueUUID.label(characteristic.service))
                            .font(.caption)
                        Text(characteristic.label)
                            .font(.caption)
                            .help(characteristic.uuid.uuidString)
                        Text(characteristic.propertyText)
                            .font(.system(.caption, design: .monospaced))
                        Text(light.rawValues[characteristic.uuid]?.hexString ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Read") { light.readRaw(characteristic.uuid) }
                            .controlSize(.mini)
                            .disabled(!characteristic.properties.contains(.read) || !light.connection.isReady)
                    }
                }
            }
        }
    }

    private var rawWriteRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Raw write")
                .font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                TextField("Characteristic UUID", text: $writeUUID)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 250)
                TextField("Hex bytes, e.g. 01 01 02 FE", text: $writeHex)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(performWrite)
                Button("Write", action: performWrite)
                    .controlSize(.small)
                    .disabled(!light.connection.isReady)
            }
            if let writeError {
                Text(writeError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Writes go straight to the bulb — a bad TLV can leave it in an odd state until power-cycled.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var powerOnForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Power-on behaviour")
                    .font(.headline)
                Text("Experimental")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
            }
            Picker("Power-on behaviour", selection: $powerOnChoice) {
                Text("Restore last state").tag(PowerOnChoice.restoreLast)
                Text("Warm white 100%").tag(PowerOnChoice.warmWhite)
                Text("Custom…").tag(PowerOnChoice.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(powerOnCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Write power-on default") { applyPowerOn() }
                .controlSize(.small)
                .disabled(!light.connection.isReady)
        }
    }

    // MARK: Helpers

    private var powerOnCaption: String {
        switch powerOnChoice {
        case .restoreLast:
            return "Writes the bulb's current state to characteristic 1005 so it comes back the same way after a power cut. Whether the bulb honours a true “restore” flag over Bluetooth is unverified."
        case .warmWhite:
            return "Hue's factory default: 100% brightness at 2700 K (367 mireds)."
        case .custom:
            return "Set the light how you want it to come on after a power cut (use its detail view), then click Write."
        }
    }

    private func applyPowerOn() {
        switch powerOnChoice {
        case .restoreLast:
            light.setPowerOnDefault(light.state)
        case .warmWhite:
            light.setPowerOnDefault(LightState(on: true, brightness: 254, color: .ct(mireds: 367)))
        case .custom:
            light.setPowerOnDefault(light.state)
        }
    }

    private func performWrite() {
        guard let uuid = Self.parseUUID(writeUUID) else {
            writeError = "Invalid UUID — use 4, 8 or 32 hex digits (dashes allowed)."
            return
        }
        guard let data = Data(hex: writeHex), !data.isEmpty else {
            writeError = "Invalid hex — use pairs of hex digits like “01 FE”."
            return
        }
        writeError = nil
        light.writeRaw(uuid, data)
    }

    /// `CBUUID(string:)` throws an Objective-C exception on malformed input, so validate first.
    private static func parseUUID(_ raw: String) -> CBUUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 36, UUID(uuidString: trimmed) != nil {
            return CBUUID(string: trimmed)
        }
        if trimmed.count == 4 || trimmed.count == 8, trimmed.allSatisfy(\.isHexDigit) {
            return CBUUID(string: trimmed)
        }
        return nil
    }

    private static func describe(_ state: LightState) -> String {
        var parts: [String] = []
        parts.append(state.on ? "on" : "off")
        parts.append("bri \(state.brightness)/254 (\(Int((state.brightnessFraction * 100).rounded()))%)")
        switch state.color {
        case .ct(let mireds):
            parts.append("ct \(mireds) mireds (\(Int(ColorMath.kelvin(fromMireds: mireds))) K)")
        case .xy(let point):
            parts.append(String(format: "xy (%.4f, %.4f)", point.x, point.y))
        }
        if state.effect != .none {
            parts.append("effect \(state.effect.displayName) speed \(state.effectSpeed)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Log

private struct DiagnosticsLogSection: View {
    @ObservedObject var log: DebugLog
    @State private var filter = ""

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var filtered: [DebugLog.Entry] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return log.entries }
        return log.entries.filter { $0.message.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Spacer()
                    Text("\(filtered.count) of \(log.entries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.text, forType: .string)
                    }
                    .help("Copy the full log to the clipboard")
                    Button("Clear") { log.clear() }
                }
                .controlSize(.small)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(filtered) { entry in
                                Text("\(Self.timeFormatter.string(from: entry.date)) \(entry.level.symbol) \(entry.message)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Self.color(for: entry.level))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: log.entries.count) { scrollToEnd(proxy) }
                }

                Text("Terminal alternative: log stream --predicate 'subsystem == \"com.davidlam.openhue\"'")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(4)
        } label: {
            Label("Log", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = filtered.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    private static func color(for level: DebugLog.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
