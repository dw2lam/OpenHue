import Foundation
import AppKit
import IOKit.pwr_mgt
import ServiceManagement

enum PowerManagement {
    // MARK: Sleep assertion

    /// Holds a `kIOPMAssertionTypePreventUserIdleSystemSleep` assertion until released/deinit.
    final class SleepAssertion {
        let reason: String
        private var assertionID: IOPMAssertionID = 0
        private var released = false

        init?(reason: String) {
            self.reason = reason
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     reason as CFString,
                                                     &id)
            guard result == kIOReturnSuccess else {
                hueLog("Sleep assertion “\(reason)” failed: IOReturn \(result)", level: .warning)
                return nil
            }
            assertionID = id
            hueLog("Sleep assertion acquired: \(reason)", level: .debug)
        }

        func release() {
            guard !released else { return }
            released = true
            let result = IOPMAssertionRelease(assertionID)
            if result != kIOReturnSuccess {
                hueLog("Sleep assertion release failed: IOReturn \(result)", level: .warning)
            } else {
                hueLog("Sleep assertion released: \(reason)", level: .debug)
            }
        }

        deinit { release() }
    }

    // MARK: Login item

    /// Launch-at-login via `SMAppService.mainApp`. Registers the app at its current bundle path.
    enum LoginItem {
        static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

        static func setEnabled(_ enabled: Bool) throws {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            hueLog("Launch at login \(enabled ? "enabled" : "disabled")")
        }
    }

    // MARK: pmset wake

    enum PmsetError: LocalizedError {
        case noDays
        case failed(status: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .noDays:
                return "Pick at least one day."
            case .failed(let status, let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty ? "pmset failed (exit \(status))." : detail
            }
        }
    }

    /// `pmset repeat wakeorpoweron` managed through an admin-privileged osascript call.
    ///
    /// `apply` / `cancel` block until the administrator-password dialog is dismissed; call them
    /// off the main actor (e.g. `Task.detached`) to keep the UI responsive.
    enum PmsetWake {
        /// pmset's canonical day order.
        private static let dayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

        static func command(days: Set<Weekday>, time: HourMinute) -> String {
            let codes = dayOrder.filter { days.contains($0) }.map(\.pmsetCode).joined()
            return "/usr/bin/pmset repeat wakeorpoweron \(codes) " + String(format: "%02d:%02d:00", time.hour, time.minute)
        }

        static func apply(days: Set<Weekday>, time: HourMinute) throws {
            guard !days.isEmpty else { throw PmsetError.noDays }
            let cmd = command(days: days, time: time)
            hueLog("pmset: \(cmd)")
            try runPrivileged(cmd)
        }

        static func cancel() throws {
            hueLog("pmset: repeat cancel")
            try runPrivileged("/usr/bin/pmset repeat cancel")
        }

        /// Output of `pmset -g sched`, for display.
        static func currentSchedule() -> String? {
            guard let result = try? run("/usr/bin/pmset", ["-g", "sched"]), result.status == 0 else { return nil }
            let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        /// Runs `shellCommand` through `osascript … with administrator privileges` (shows the
        /// system's admin password prompt). Throws with the stderr text on non-zero exit.
        private static func runPrivileged(_ shellCommand: String) throws {
            let escaped = shellCommand
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"
            let result = try run("/usr/bin/osascript", ["-e", script])
            guard result.status == 0 else {
                hueLog("pmset via osascript failed (\(result.status)): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))", level: .error)
                throw PmsetError.failed(status: result.status, stderr: result.stderr)
            }
        }

        private static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()
            // Drain both pipes before waiting so a chatty child can't fill a pipe buffer and stall.
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus,
                    String(decoding: outData, as: UTF8.self),
                    String(decoding: errData, as: UTF8.self))
        }
    }

    // MARK: Sleep / wake notifications

    /// NSWorkspace sleep/wake notifications, delivered on the main actor.
    final class WakeObserver {
        private var tokens: [NSObjectProtocol] = []

        init(onWake: @escaping @MainActor () -> Void, onSleep: (@MainActor () -> Void)? = nil) {
            let center = NSWorkspace.shared.notificationCenter
            tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onWake() }
            })
            if let onSleep {
                tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { onSleep() }
                })
            }
        }

        deinit {
            let center = NSWorkspace.shared.notificationCenter
            tokens.forEach { center.removeObserver($0) }
        }
    }
}
