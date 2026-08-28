import SwiftUI
import AppKit
import CoreBluetooth

// MARK: - Add Light sheet

struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DiscoveryContent(central: model.central)
    }
}

private struct DiscoveryContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var central: HueCentral
    @Environment(\.dismiss) private var dismiss

    @State private var helpExpanded = false

    private var sorted: [DiscoveredBulb] {
        central.discovered.sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            List {
                if sorted.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(central.isPoweredOn ? "No bulbs found yet." : "Bluetooth isn't available.")
                            .foregroundStyle(.secondary)
                        Text("Hue Bluetooth bulbs advertise only while powered; a bulb already connected to another device (your phone, or this app) won't show up.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(sorted) { bulb in
                    DiscoveredRow(bulb: bulb) {
                        model.addLight(bulb)
                        dismiss()
                    } onReplace: { light in
                        model.replaceLight(light, with: bulb)
                        dismiss()
                    }
                }

                Section {
                    DisclosureGroup("Pairing help", isExpanded: $helpExpanded) {
                        PairingHelpView(light: nil)
                            .padding(.vertical, 4)
                    }
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                if !central.isPoweredOn {
                    bluetoothWarning
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 480)
        // Deferred: start/stop publish central state, which SwiftUI forbids during a view update.
        .onAppear { DispatchQueue.main.async { central.startScan() } }
        .onDisappear { DispatchQueue.main.async { central.stopScan() } }
        .onChange(of: central.managerState) { _, _ in
            if central.isPoweredOn && !central.isScanning { central.startScan() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add Light")
                .font(.title2.weight(.semibold))
            Text("Power the bulb on and keep it within a couple of metres.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if central.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                } else {
                    Image(systemName: "pause.circle")
                    Text("Scan stopped")
                }
                Spacer()
                Button {
                    central.stopScan()
                    central.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!central.isPoweredOn)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var bluetoothWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button(warningButtonTitle) {
                    NSWorkspace.shared.open(warningURL)
                }
                .controlSize(.small)
            }
        }
    }

    private var warningText: String {
        switch central.managerState {
        case .poweredOff: return "Bluetooth is off. Turn it on in Control Center or System Settings."
        case .unauthorized: return "Bluetooth access denied. Allow OpenHue in System Settings → Privacy & Security → Bluetooth."
        case .unsupported: return "This Mac has no Bluetooth Low Energy support."
        default: return "Bluetooth is starting up…"
        }
    }

    private var warningButtonTitle: String {
        central.managerState == .unauthorized ? "Open Privacy Settings" : "Open Bluetooth Settings"
    }

    private var warningURL: URL {
        let raw = central.managerState == .unauthorized
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            : "x-apple.systempreferences:com.apple.Bluetooth"
        return URL(string: raw) ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")
    }
}

// MARK: - Discovered row

private struct DiscoveredRow: View {
    @EnvironmentObject var model: AppModel
    let bulb: DiscoveredBulb
    let onAdd: () -> Void
    let onReplace: (HueLight) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SignalBars(rssi: bulb.rssi)
                .help("\(bulb.rssi) dBm")

            VStack(alignment: .leading, spacing: 2) {
                Text(bulb.name)
                    .font(.headline)
                Text("\(bulb.rssi) dBm · found via \(bulb.foundVia)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if bulb.isKnown {
                Text("Already added")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if !model.lights.isEmpty {
                    Menu("Add as replacement for…") {
                        ForEach(model.lights) { light in
                            Button(light.name) { onReplace(light) }
                        }
                    }
                    .controlSize(.small)
                    .fixedSize()
                    .help("Use after a factory reset: the bulb has a new address but keeps its name, scenes and schedules here.")
                }
                Button("Add", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Four-bar signal indicator derived from RSSI (dBm).
private struct SignalBars: View {
    let rssi: Int

    private var level: Int {
        if rssi >= -60 { return 4 }
        if rssi >= -70 { return 3 }
        if rssi >= -80 { return 2 }
        return 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < level ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(5 + index * 3))
            }
        }
        .frame(width: 22, height: 14, alignment: .bottom)
        .accessibilityLabel("Signal \(level) of 4")
    }
}

// MARK: - Pairing help

/// Numbered pairing steps. When `light` is given, shows its connection status with Retry / Bluetooth
/// Settings buttons (embedded by `LightDetailView`).
struct PairingHelpView: View {
    private let light: HueLight?

    init(light: HueLight?) {
        self.light = light
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let light {
                PairingStatusRow(light: light)
            }
            step(1, "link",
                 "When macOS shows a Connection Request for the bulb, click Connect.")
            step(2, "iphone",
                 "No dialog? The bulb only accepts a new pairing while it is discoverable. On your phone open the Hue app → Settings → Voice Assistants → Amazon Alexa (or Google Home) → Make Discoverable — this works without a Bridge and the phone app keeps working — then click Retry here within a minute or two. If the phone app stays connected, background it right after tapping Make Discoverable.")
            step(3, "arrow.counterclockwise",
                 "Last resort: factory-reset the bulb (switch it off and on 5 times, ending on; it blinks on the last cycle). This also unpairs the phone app and gives the bulb a new Bluetooth address, so re-add it with Add Light → “Add as replacement for…” and forget any old “Hue Lamp” in System Settings → Bluetooth.")
            step(4, "xmark.octagon",
                 "Bulbs joined to a Hue Bridge cannot be controlled over Bluetooth.")
        }
    }

    private func step(_ number: Int, _ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text("\(number). \(text)")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PairingStatusRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var light: HueLight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: light.connection.isReady ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(light.connection.isReady ? Color.green : Color.secondary)
                Text(light.connection.label)
                    .font(.callout.weight(.semibold))
            }
            if let error = light.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !light.connection.isReady {
                    Button("Retry") { model.central.cycle(light) }
                }
                Button("Open Bluetooth Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!)
                }
            }
            .controlSize(.small)
        }
        .padding(.bottom, 4)
    }
}
