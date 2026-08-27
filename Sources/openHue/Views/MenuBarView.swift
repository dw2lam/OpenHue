import SwiftUI
import AppKit

/// Content of the `.window`-style menu bar extra: quick power/brightness, scenes, and app actions.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            allLightsRow
            if !model.lights.isEmpty {
                Divider()
                VStack(spacing: 6) {
                    ForEach(model.lights) { light in
                        LightMiniRow(light: light, sliderWidth: 104)
                    }
                }
            }
            Divider()
            scenesRow
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text("openHue")
                .font(.headline)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch model.central.managerState {
        case .poweredOn:
            return model.lights.isEmpty ? "No lights" : "\(model.readyLights.count)/\(model.lights.count) connected"
        case .poweredOff: return "Bluetooth off"
        case .unauthorized: return "No Bluetooth access"
        case .unsupported: return "No Bluetooth"
        default: return "Starting…"
        }
    }

    private var allLightsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.2")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text("All Lights")
                .fontWeight(.medium)
            Spacer(minLength: 8)
            LiveBrightnessSlider(value: model.allLightsBrightness, showsPercent: false) { model.setAll(brightness: $0) }
                .frame(width: 104)
                .disabled(model.readyLights.isEmpty)
            Toggle("All Lights", isOn: Binding(get: { model.anyLightOn }, set: { model.setAll(power: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(model.lights.isEmpty)
        }
        .opacity(model.readyLights.isEmpty ? 0.6 : 1)
    }

    private var scenesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.scenes.prefix(6))) { scene in
                    SceneQuickChip(scene: scene, compact: true) { model.apply(scene: scene) }
                }
            }
            .padding(.vertical, 1)
        }
        .disabled(model.lights.isEmpty)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open openHue", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                if anyConnected {
                    Button("Disconnect All") { model.central.disconnectAll() }
                        .help("Drop every link so the Hue phone app can connect (bulbs accept one controller at a time)")
                } else {
                    Button("Reconnect All") { model.central.connectAll() }
                        .disabled(model.lights.isEmpty)
                }
                Spacer()
                SettingsLink {
                    Text("Settings…")
                }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }

    private var anyConnected: Bool {
        model.lights.contains { $0.connection.isConnectedOrBusy }
    }
}
