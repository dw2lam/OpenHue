import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if model.central.managerState != .poweredOn {
                    BluetoothBanner(state: model.central.managerState)
                    Divider()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { AppDelegate.openMainWindow = { openWindow(id: "main") } }
        .sheet(isPresented: $model.isDiscoveryPresented) {
            DiscoveryView()
                .environmentObject(model)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Lights") {
                Label("All Lights", systemImage: "lightbulb.2")
                    .tag(AppModel.SidebarItem.allLights)
                ForEach(model.lights) { light in
                    LightRow(light: light)
                        .tag(AppModel.SidebarItem.light(light.id))
                }
            }
            Section("Library") {
                Label("Scenes", systemImage: "theatermasks")
                    .tag(AppModel.SidebarItem.scenes)
                Label("Timer", systemImage: "timer")
                    .tag(AppModel.SidebarItem.sleepTimer)
                Label("Schedules", systemImage: "clock")
                    .tag(AppModel.SidebarItem.schedules)
            }
            Section("Tools") {
                Label("Diagnostics", systemImage: "stethoscope")
                    .tag(AppModel.SidebarItem.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Light…", systemImage: "plus") {
                    model.isDiscoveryPresented = true
                }
                .help("Find and pair a Hue Bluetooth bulb")
            }
        }
    }

    // MARK: Detail router

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .allLights {
        case .allLights:
            if model.lights.isEmpty {
                NoLightsView()
            } else {
                AllLightsView()
            }
        case .light(let id):
            if let light = model.light(id: id) {
                LightDetailView(light: light)
                    .id(id)
            } else if model.lights.isEmpty {
                NoLightsView()
            } else {
                EmptyStateView("Light not found", systemImage: "lightbulb.slash",
                               description: "This light is no longer remembered.") {
                    Button("Show All Lights") { model.selection = .allLights }
                }
            }
        case .scenes:
            ScenesView()
        case .sleepTimer:
            SleepTimerView()
        case .schedules:
            SchedulesView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
}

// MARK: - Sidebar row

/// Observes its light directly so the dot and swatch update without re-rendering the whole sidebar.
struct LightRow: View {
    @ObservedObject var light: HueLight
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(connection: light.connection)
                .frame(width: 16)
            Text(light.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if light.state.on {
                Circle()
                    .fill(light.state.displayColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            }
        }
        .help(light.connection.label)
        .contextMenu {
            Button("Identify") { light.identify() }
                .disabled(!light.connection.isReady)
            if light.connection.isConnectedOrBusy {
                Button("Disconnect") { model.central.disconnect(light) }
            } else {
                Button("Connect") { model.central.connect(light) }
            }
        }
    }
}

// MARK: - Empty state

private struct NoLightsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EmptyStateView("No lights yet", systemImage: "lightbulb",
                       description: "Pair a Philips Hue Bluetooth bulb to control it from this Mac — no bridge needed.") {
            Button("Add Light…", systemImage: "plus") {
                model.isDiscoveryPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Bluetooth banner

private struct BluetoothBanner: View {
    let state: CBManagerState

    private struct Action {
        let title: String
        let url: URL
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message)
            Spacer()
            if isStarting {
                ProgressView()
                    .controlSize(.small)
            }
            if let action {
                Link(action.title, destination: action.url)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
    }

    private var isStarting: Bool { state == .unknown || state == .resetting }

    private var symbol: String {
        switch state {
        case .poweredOff: return "antenna.radiowaves.left.and.right.slash"
        case .unauthorized: return "lock.shield"
        case .unsupported: return "xmark.octagon"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    private var tint: Color {
        switch state {
        case .poweredOff, .unauthorized, .unsupported: return .orange
        default: return .secondary
        }
    }

    private var message: String {
        switch state {
        case .poweredOff: return "Bluetooth is off."
        case .unauthorized: return "OpenHue needs Bluetooth access to talk to your bulbs."
        case .unsupported: return "This Mac has no Bluetooth LE radio."
        default: return "Starting Bluetooth…"
        }
    }

    private var action: Action? {
        switch state {
        case .poweredOff:
            return URL(string: "x-apple.systempreferences:com.apple.Bluetooth")
                .map { Action(title: "Open Bluetooth Settings", url: $0) }
        case .unauthorized:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
                .map { Action(title: "Open Privacy Settings", url: $0) }
        default:
            return nil
        }
    }
}
