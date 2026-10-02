// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: DECISIONS 10 Q4 (per-device path-mapping table), 01 §6.6, 05 §6.9, ARCH §9.4. Compiling stub created by F1;
// W-PERSIST replaces this file in place. The stub maps nothing (ARCH §11).
import Foundation
import Observation

public struct PathMapping: Codable, Sendable, Hashable {
    public var windowsPrefix: String
    public var macPath: String

    public init(windowsPrefix: String, macPath: String) {
        self.windowsPrefix = windowsPrefix; self.macPath = macPath
    }
}

@MainActor @Observable public final class PathMapper {
    public static let shared = PathMapper()

    /// Persisted per Mac in UserDefaults "aa.pathMappings".
    public var mappings: [PathMapping] = []

    public init() {}

    /// `^[A-Za-z]:[\\/]` or `^\\\\`.
    public nonisolated static func isWindowsPath(_ s: String) -> Bool {
        // PLACEHOLDER(W-PERSIST)
        false
    }

    public func macURL(for windowsPath: String) -> URL? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }

    public nonisolated static func smbURL(forUNC s: String) -> URL? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }
}
