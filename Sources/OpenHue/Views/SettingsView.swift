import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ScheduleSettingsTab()
                .tabItem { Label("Schedules", systemImage: "clock") }
            WakeMacSettingsTab()
                .tabItem { Label("Wake Mac", systemImage: "power") }
            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "folder") }
        }
        .frame(width: 460)
    }
}

// MARK: - Helpers

/// Two-way binding into `AppSettings` that routes every change through `updateSettings`
/// so side effects (login item, sleep assertion, keep-alive, pmset) are applied.
@MainActor
private func settingBinding<T>(_ model: AppModel, _ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
    Binding(
        get: { model.settings[keyPath: keyPath] },
        set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
    )
}

private struct SettingToggle: View {
    let title: String
    let caption: String?
    @Binding var isOn: Bool

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Startup") {
                SettingToggle("Launch at login",
                              caption: "Needed for schedules to run on days you haven't opened the app yourself.",
                              isOn: settingBinding(model, \.launchAtLogin))
                if let error = model.loginItemError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                SettingToggle("Open window at launch",
                              caption: "Off: the app starts in the menu bar only.",
                              isOn: settingBinding(model, \.openWindowAtLaunch))
            }
            Section("Connection") {
                SettingToggle("Keep lights connected",
                              caption: "Faster commands. A bulb accepts one connected device at a time, so the Hue phone app can't reach it meanwhile — use Disconnect All (Data tab) to hand it over.",
                              isOn: settingBinding(model, \.keepLightsConnected))
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

// MARK: - Schedules

private struct ScheduleSettingsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HueInfoCallout("Schedules run on this Mac (the bulbs can't store them): the Mac must be awake, OpenHue running, and the bulbs within Bluetooth range.")
            }
            Section("Sleep") {
                SettingToggle("Keep this Mac awake while OpenHue is running",
                              caption: "Prevents idle sleep so morning schedules can fire. Battery impact on laptops.",
                              isOn: settingBinding(model, \.keepMacAwakeWhileRunning))
                SettingToggle("Keep this Mac awake while a timer counts down",
                              caption: "Released the moment the lights switch off.",
                              isOn: settingBinding(model, \.keepMacAwakeForSleepTimers))
                FadeOutPicker(label: "Timer fade-out")
            }
            Section {
                Stepper(value: settingBinding(model, \.missedGraceOnMinutes), in: 0...180, step: 5) {
                    LabeledContent("Run missed on-schedules if the Mac wakes within",
                                   value: "\(model.settings.missedGraceOnMinutes) min")
                }
                Stepper(value: settingBinding(model, \.missedGraceOffHours), in: 0...24) {
                    LabeledContent("Run missed off-schedules within",
                                   value: "\(model.settings.missedGraceOffHours) h")
                }
            } header: {
                Text("Missed schedules")
            } footer: {
                Text("A wake-up fade that starts late is resumed mid-ramp. Set a value to 0 to never run that kind of missed schedule.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 530)
    }
}

// MARK: - Wake this Mac

private struct WakeMacSettingsTab: View {
    @EnvironmentObject var model: AppModel

    /// Edited locally and applied with one click, because every `pmset` change asks for an admin password.
    @State private var draft = WakeMacSetting()
    @State private var wakeTime = Date()
    @State private var currentSchedule: String?

    private var isDirty: Bool { draft != model.settings.wakeMac }

    private var weeklySchedules: [(days: Set<Weekday>, time: HourMinute)] {
        model.schedules.compactMap { schedule in
            guard schedule.isEnabled, case .weekly(let days, let time) = schedule.trigger, !days.isEmpty else { return nil }
            return (days, time)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Wake this Mac for schedules", isOn: $draft.enabled)
                LabeledContent("Days") {
                    HueWeekdayPicker(days: $draft.days)
                }
                .disabled(!draft.enabled)
                DatePicker("Time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    .disabled(!draft.enabled)
                Button("Suggest from schedules") { suggest() }
                    .disabled(weeklySchedules.isEmpty)
                    .help("Every day used by an enabled weekly schedule, 2 minutes before the earliest one")
            } header: {
                Text("Scheduled wake")
            } footer: {
                Text("Uses `pmset repeat wakeorpoweron`; macOS asks for your administrator password once. Wakes the Mac ~2 minutes before your earliest schedule. Doesn't work with the lid closed unless power and an external display are connected.")
            }

            Section("Command") {
                Text(commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = model.pmsetError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("Current pmset schedule") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentSchedule?.isEmpty == false ? currentSchedule! : "No repeating wake events scheduled.")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Refresh") { refreshCurrent() }
                            .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Revert") { load() }
                        .disabled(!isDirty)
                    Button("Apply") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isDirty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .onAppear {
            load()
            refreshCurrent()
        }
        .onChange(of: model.settings.wakeMac) { load() }
        .onChange(of: wakeTime) { draft.time = HourMinute(date: wakeTime) }
    }

    private var commandPreview: String {
        if draft.enabled {
            return PowerManagement.PmsetWake.command(days: draft.days, time: draft.time)
        }
        return "pmset repeat cancel   # removes the repeating wake (all repeating pmset events)"
    }

    private func load() {
        draft = model.settings.wakeMac
        wakeTime = draft.time.date()
    }

    private func apply() {
        let value = draft
        model.updateSettings { $0.wakeMac = value }
        refreshCurrent()
    }

    private func refreshCurrent() {
        currentSchedule = PowerManagement.PmsetWake.currentSchedule()
    }

    private func suggest() {
        let weekly = weeklySchedules
        guard !weekly.isEmpty else { return }
        let days = weekly.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }
        let earliest = weekly.map { $0.time.hour * 60 + $0.time.minute }.min() ?? 0
        let adjusted = (earliest - 2 + 1440) % 1440
        draft.enabled = true
        draft.days = days
        draft.time = HourMinute(hour: adjusted / 60, minute: adjusted % 60)
        wakeTime = draft.time.date()
    }
}

// MARK: - Data

private struct DataSettingsTab: View {
    @EnvironmentObject var model: AppModel

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case (let v?, let b?) where v != b: return "\(v) (\(b))"
        case (let v?, _): return v
        default: return "development build"
        }
    }

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Folder") {
                    Text(Store.directory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                Button("Open folder") { model.openDataFolder() }
                Text("lights.json, scenes.json, schedules.json and settings.json — plain JSON, safe to back up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Lights") {
                HStack {
                    Button("Disconnect all lights") { model.central.disconnectAll() }
                    Button("Reconnect all") { model.central.connectAll() }
                }
                Text("Disconnecting lets the Hue phone app connect (bulbs accept one device at a time). Lights reconnect when you use them here or when a schedule runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("About") {
                LabeledContent("Version", value: versionString)
                LabeledContent("Lights remembered", value: "\(model.lights.count)")
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }
}
