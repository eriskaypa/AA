// Spec: 01 §6.8, OC-52, 03 BD.4.9 — Mac-only preferences live in UserDefaults, never in settings.json/data.json;
//       ARCHITECTURE.md §6.1, §12.2 (keys "aa.<area>.<name>", declared by each owner in its own files).
import Foundation

public final class MacPreferences: @unchecked Sendable {
    /// UserDefaults domain `com.eriskay.aa` (the app's own domain when bundled; a named suite under `swift run`).
    public static let shared = MacPreferences(defaults: MacPreferences.appDefaults())

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

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
