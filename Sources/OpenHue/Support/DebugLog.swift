import Foundation
import os

/// In-memory ring buffer (shown in Diagnostics) mirrored to the unified log:
/// `log stream --predicate 'subsystem == "com.davidlam.openhue"'`
@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()
    static let subsystem = "com.davidlam.openhue"

    enum Level: String {
        case debug, info, warning, error
        var symbol: String {
            switch self {
            case .debug: return "·"
            case .info: return "i"
            case .warning: return "!"
            case .error: return "✗"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    let capacity = 500
    private let logger = Logger(subsystem: DebugLog.subsystem, category: "app")

    func append(_ message: String, level: Level = .info) {
        entries.append(Entry(date: Date(), level: level, message: message))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    func clear() { entries.removeAll() }

    var text: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "\(f.string(from: $0.date)) [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
    }
}

/// Global convenience. Safe to call from any thread; entries land on the main actor.
func hueLog(_ message: String, level: DebugLog.Level = .info) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { DebugLog.shared.append(message, level: level) }
    } else {
        Task { @MainActor in DebugLog.shared.append(message, level: level) }
    }
}
