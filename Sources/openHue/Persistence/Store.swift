import Foundation

/// JSON persistence in ~/Library/Application Support/openHue/. One file per collection,
/// wrapped in a versioned envelope, written atomically.
@MainActor
final class Store {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("openHue", isDirectory: true)
    }()

    enum File: String {
        case lights = "lights.json"
        case scenes = "scenes.json"
        case schedules = "schedules.json"
        case settings = "settings.json"
    }

    private struct Envelope<T: Codable>: Codable {
        var version: Int
        var items: T
    }

    static let currentVersion = 1

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        try? FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
    }

    func url(for file: File) -> URL { Store.directory.appendingPathComponent(file.rawValue) }

    func load<T: Codable>(_ file: File, default defaultValue: T) -> T {
        let url = url(for: file)
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        do {
            return try decoder.decode(Envelope<T>.self, from: data).items
        } catch {
            hueLog("Store: failed to decode \(file.rawValue): \(error)", level: .error)
            return defaultValue
        }
    }

    func save<T: Codable>(_ value: T, to file: File) {
        do {
            let data = try encoder.encode(Envelope(version: Store.currentVersion, items: value))
            try data.write(to: url(for: file), options: .atomic)
        } catch {
            hueLog("Store: failed to save \(file.rawValue): \(error)", level: .error)
        }
    }
}
