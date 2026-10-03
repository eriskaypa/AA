// Spec: 01 §6.8, OC-52, 03 BD.4.9 — Mac-only preferences live in UserDefaults, never in settings.json/data.json;
//       ARCHITECTURE.md §6.1, §12.2 (keys "aa.<area>.<name>", declared by each owner in its own files);
//       DECISIONS "Stage V rulings" (tests use an in-memory store and never create a UserDefaults suite on disk).
import Foundation

/// The key-value store behind `MacPreferences`: `UserDefaults` in the app, `InMemoryPreferences` in tests.
public protocol MacPreferencesBackend: AnyObject {
    func object(forKey key: String) -> Any?
    func bool(forKey key: String) -> Bool
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: MacPreferencesBackend {}

/// A process-local, never-persisted backend (tests, previews). Reads follow the `UserDefaults` conversions the app
/// relies on: a Bool reads from a Bool or a number, a String from a String or a number.
public final class InMemoryPreferences: MacPreferencesBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    public init() {}

    public func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    public func bool(forKey key: String) -> Bool {
        switch object(forKey: key) {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["yes", "true", "1"].contains(s.lowercased())
        default: return false
        }
    }
    public func string(forKey key: String) -> String? {
        switch object(forKey: key) {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
    public func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    public func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
    public func removeObject(forKey key: String) { set(nil, forKey: key) }
}

public final class MacPreferences: @unchecked Sendable {
    /// UserDefaults domain `com.eriskay.aa` (the app's own domain when bundled; a named suite under `swift run`).
    public static let shared = MacPreferences(defaults: MacPreferences.appDefaults())

    private let defaults: any MacPreferencesBackend

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public init(backend: any MacPreferencesBackend) { defaults = backend }

    /// A fresh store that lives only in this process (tests never touch `~/Library/Preferences`).
    public static func inMemory() -> MacPreferences { MacPreferences(backend: InMemoryPreferences()) }

    static func appDefaults() -> UserDefaults {
        if Bundle.main.bundleIdentifier == Identifiers.bundleID { return .standard }
        return UserDefaults(suiteName: Identifiers.bundleID) ?? .standard
    }

    public struct Key: Hashable, Sendable {
        public let rawValue: String
        public init(_ raw: String) { rawValue = raw }
    }

    public func bool(_ k: Key, default d: Bool) -> Bool {
        defaults.object(forKey: k.rawValue) == nil ? d : defaults.bool(forKey: k.rawValue)
    }
    public func set(_ v: Bool, _ k: Key) { defaults.set(v, forKey: k.rawValue) }

    public func string(_ k: Key) -> String? { defaults.string(forKey: k.rawValue) }
    public func set(_ v: String?, _ k: Key) {
        if let v { defaults.set(v, forKey: k.rawValue) } else { defaults.removeObject(forKey: k.rawValue) }
    }

    public func data(_ k: Key) -> Data? { defaults.data(forKey: k.rawValue) }
    public func set(_ v: Data?, _ k: Key) {
        if let v { defaults.set(v, forKey: k.rawValue) } else { defaults.removeObject(forKey: k.rawValue) }
    }

    public func codable<T: Codable>(_ k: Key, as type: T.Type) -> T? {
        guard let d = defaults.data(forKey: k.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    public func setCodable<T: Codable>(_ v: T?, _ k: Key) {
        guard let v, let d = try? JSONEncoder().encode(v) else { defaults.removeObject(forKey: k.rawValue); return }
        defaults.set(d, forKey: k.rawValue)
    }
}
