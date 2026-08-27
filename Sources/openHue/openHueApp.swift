import SwiftUI
import AppKit

@main
struct OpenHueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("OpenHue", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("OpenHue", systemImage: "lightbulb") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `AppModel.init` (from `AppSettings.openWindowAtLaunch`) before `applicationDidFinishLaunching` runs.
    /// nil = unknown, in which case the setting is read straight from the store.
    static var shouldHideWindowAtLaunch: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let asLoginItem = Self.launchedAsLoginItem()
        hueLog("App launched" + (asLoginItem ? " as a login item" : ""))
        guard asLoginItem else { return }

        let hide = Self.shouldHideWindowAtLaunch
            ?? !Store().load(Store.File.settings, default: AppSettings()).openWindowAtLaunch
        guard hide else { return }

        // The SwiftUI window may not exist yet on this turn of the run loop.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Self.mainWindow()?.close()
                hueLog("Login-item launch: main window stays closed (Settings → Open window at launch is off)")
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, let window = Self.mainWindow() {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Menu bar app: closing the window must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Apple's documented check: the `oapp` event carries `keyAELaunchedAsLogInItem` in its `keyAEPropData` parameter.
    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let prop = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else { return false }
        return prop.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    static func mainWindow() -> NSWindow? {
        let byIdentifier = NSApp.windows.first { window in
            guard let id = window.identifier?.rawValue else { return false }
            return id == "main" || id.hasPrefix("main-")
        }
        return byIdentifier ?? NSApp.windows.first { $0.title == "OpenHue" && !($0 is NSPanel) }
    }
}
