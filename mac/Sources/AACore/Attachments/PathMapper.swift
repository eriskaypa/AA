// Spec: DECISIONS 10 Q4 (per-device path-mapping table, applied only when opening; UNC → smb:// fallback), 01 §6.6
//       (Windows live links: "Locate…" stores a Windows prefix → Mac folder mapping in UserDefaults, never in
//       settings.json; derivable from smb://srv/share), 05 §6.9, ARCHITECTURE.md §6.6, §9.4.
import Foundation
import Observation

public struct PathMapping: Codable, Sendable, Hashable {
    public var windowsPrefix: String
    public var macPath: String

    public init(windowsPrefix: String, macPath: String) {
        self.windowsPrefix = windowsPrefix; self.macPath = macPath
    }
}

/// The per-Mac table that turns stored Windows paths (`Z:\…`, `\\server\share\…`) into Mac locations when a file is
/// opened. Stored paths are never rewritten (01 DATA-061).
@MainActor @Observable public final class PathMapper {
    public static let shared = PathMapper(preferences: .shared)

    /// UserDefaults key (ARCHITECTURE.md §6.6).
    public static let preferencesKey = MacPreferences.Key("aa.pathMappings")

    @ObservationIgnored private let preferences: MacPreferences?

    /// Persisted per Mac in UserDefaults "aa.pathMappings" (every change is written immediately).
    public var mappings: [PathMapping] = [] {
        didSet { preferences?.setCodable(mappings, PathMapper.preferencesKey) }
    }

    /// `preferences == nil` → an in-memory table (tests).
    public init(preferences: MacPreferences?) {
        self.preferences = preferences
        mappings = preferences?.codable(PathMapper.preferencesKey, as: [PathMapping].self) ?? []
    }

    public convenience init() { self.init(preferences: nil) }

    // MARK: Recognition

    /// `^[A-Za-z]:[\\/]` or `^\\\\`.
    public nonisolated static func isWindowsPath(_ s: String) -> Bool {
        let u = Array(s.utf16)
        if u.count >= 3, PersistPaths.isASCIILetter(u[0]), u[1] == 0x3A, u[2] == 0x5C || u[2] == 0x2F { return true }
        return u.count >= 2 && u[0] == 0x5C && u[1] == 0x5C
    }

    /// The canonical form used for matching: `\` separators, no trailing separator, drive letter upper-cased
    /// (`z:/x/` → `Z:\x`, `\\srv\share\` → `\\srv\share`).
    public nonisolated static func canonicalPrefix(_ s: String) -> String {
        var t = NetText.trim(s).replacingOccurrences(of: "/", with: "\\")
        while t.hasSuffix("\\"), !(t == "\\\\") { t.removeLast() }
        let u = Array(t.utf16)
        if u.count >= 2, PersistPaths.isASCIILetter(u[0]), u[1] == 0x3A {
            t = NetText.toUpperInvariant(String(t.prefix(1))) + t.dropFirst()
        }
        return t
    }

    /// A usable Windows prefix for the table: a drive (`Z:`, `Z:\Manuals`) or a share (`\\server\share[\…]`).
    public nonisolated static func isValidPrefix(_ s: String) -> Bool {
        let t = canonicalPrefix(s)
        let u = Array(t.utf16)
        if u.count >= 2, PersistPaths.isASCIILetter(u[0]), u[1] == 0x3A { return u.count == 2 || u[2] == 0x5C }
        return uncParts(t) != nil
    }

    /// The path components after the server/share or drive of a Windows path (`Z:\a\b` → `["a","b"]`).
    nonisolated static func components(_ s: String) -> [String] {
        s.replacingOccurrences(of: "/", with: "\\").split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
    }

    /// `\\server\share\rest` → (server, share, rest components); nil for anything else.
    public nonisolated static func uncParts(_ s: String) -> (server: String, share: String, rest: [String])? {
        let t = s.replacingOccurrences(of: "/", with: "\\")
        guard t.hasPrefix("\\\\") else { return nil }
        let parts = components(String(t.dropFirst(2)))
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1], Array(parts.dropFirst(2)))
    }

    // MARK: Mapping

    /// The longest mapping whose Windows prefix matches `windowsPath` on a component boundary (case-insensitive),
    /// with the remaining components appended to its Mac path. Without a mapping, a UNC path falls back to
    /// `/Volumes/<share>/<rest>` when that exists (a share mounted by Finder). nil when nothing applies.
    public func macURL(for windowsPath: String) -> URL? {
        let path = PathMapper.canonicalPrefix(windowsPath)
        var best: (PathMapping, String)?
        for m in mappings {
            let prefix = PathMapper.canonicalPrefix(m.windowsPrefix)
            guard !prefix.isEmpty, !NetText.isBlank(m.macPath) else { continue }
            guard let rest = PersistPaths.dropPrefixIgnoringCase(path, prefix: prefix) else { continue }
            guard rest.isEmpty || rest.hasPrefix("\\") || prefix.hasSuffix(":") || prefix.hasSuffix("\\") else { continue }
            if let b = best, PathMapper.canonicalPrefix(b.0.windowsPrefix).utf16.count >= prefix.utf16.count { continue }
            best = (m, rest)
        }
        if let (m, rest) = best {
            return PathMapper.join(macPath: m.macPath, rest: PathMapper.components(rest))
        }
        if let unc = PathMapper.uncParts(windowsPath) {
            let volume = URL(fileURLWithPath: "/Volumes", isDirectory: true).appending(path: unc.share)
            let candidate = unc.rest.reduce(volume) { $0.appending(path: $1) }
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The mapping a "Locate…" answer implies: the user picked `chosen` on the Mac for the Windows path `windowsPath`.
    /// The shared trailing components are dropped from both sides, so `Z:\Manuals\Pump.pdf` located at
    /// `/Volumes/Ship/Manuals/Pump.pdf` maps `Z:` → `/Volumes/Ship`; with nothing in common the whole parent
    /// folders are mapped.
    public nonisolated static func inferredMapping(windowsPath: String, chosen: URL) -> PathMapping? {
        guard isWindowsPath(windowsPath) else { return nil }
        let root: String
        if let unc = uncParts(windowsPath) {
            root = "\\\\" + unc.server + "\\" + unc.share
        } else {
            root = canonicalPrefix(String(windowsPath.prefix(2)))
        }
        var winRest = uncParts(windowsPath)?.rest ?? components(String(windowsPath.dropFirst(2)))
        var macParts = chosen.standardizedFileURL.pathComponents
        if macParts.first == "/" { macParts.removeFirst() }
        // Drop the shared tail (case-insensitive).
        while let w = winRest.last, let m = macParts.last, NetText.equalsIgnoreCase(w, m) {
            winRest.removeLast(); macParts.removeLast()
        }
        if winRest.isEmpty && macParts.isEmpty { return nil }
        let prefix = ([root] + winRest).joined(separator: "\\")
        let mac = "/" + macParts.joined(separator: "/")
        return PathMapping(windowsPrefix: canonicalPrefix(prefix), macPath: mac)
    }

    /// Adds or replaces (same canonical Windows prefix) a mapping.
    public func upsert(_ m: PathMapping) {
        let key = PathMapper.canonicalPrefix(m.windowsPrefix)
        let clean = PathMapping(windowsPrefix: key, macPath: NetText.trim(m.macPath))
        if let i = mappings.firstIndex(where: { NetText.equalsIgnoreCase(PathMapper.canonicalPrefix($0.windowsPrefix), key) }) {
            mappings[i] = clean
        } else {
            mappings.append(clean)
        }
    }

    // MARK: UNC → smb://

    /// `\\server\share\rest` → `smb://server/share/rest` (components percent-encoded). nil when `s` is not UNC.
    public nonisolated static func smbURL(forUNC s: String) -> URL? {
        guard let unc = uncParts(s) else { return nil }
        let enc: (String) -> String = { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? $0 }
        let host = unc.server.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? unc.server
        let path = ([unc.share] + unc.rest).map(enc).joined(separator: "/")
        return URL(string: "smb://\(host)/\(path)")
    }

    /// `\\server\share\…` → `smb://server/share` (what "Connect to Server…" mounts).
    public nonisolated static func smbShareURL(forUNC s: String) -> URL? {
        guard let unc = uncParts(s) else { return nil }
        return smbURL(forUNC: "\\\\" + unc.server + "\\" + unc.share)
    }

    /// A Mac path written as `smb://server/share/x` is accepted in the table: it is used as the base URL and
    /// opening it lets Finder mount the share.
    nonisolated static func join(macPath: String, rest: [String]) -> URL? {
        let base = NetText.trim(macPath)
        if base.lowercased().hasPrefix("smb://") || base.lowercased().hasPrefix("afp://") {
            guard var url = URL(string: base) else { return nil }
            for r in rest { url = url.appending(path: r) }
            return url
        }
        var url = URL(fileURLWithPath: (base as NSString).expandingTildeInPath, isDirectory: true)
        for r in rest { url = url.appending(path: r) }
        return url.standardizedFileURL
    }
}
