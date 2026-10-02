// Spec: 03 BD.3.2 (resolveAppFolder), BD.3.3 (preflight), SHELL-193 (precedence), SHELL-194 (pre-flight alert texts),
//       01 DATA-010 (AA_DATA_DIR); ARCHITECTURE.md §6.9. Vectors: 03 BD.7.1.
import Foundation

public enum AppFolderSource: Sendable { case argument, environment, defaultLocation }

public enum DataDirError: Error, Sendable, Equatable {
    case windowsPath
    case volumeMissing(String)        // the /Volumes/<name> component that is not mounted
    case notAFolder
    case notWritable(String)          // strerror text
    case cannotCreate(String)         // error.localizedDescription
}

/// 03 BD.3.2 / BD.3.3 (SHELL-193/194). Pure apart from `preflight`, which touches the file system.
public enum AppFolderResolver {
    public static let environmentKey = "AA_DATA_DIR"

    /// The first non-blank of `--data-dir`, then `AA_DATA_DIR` (trimmed), with its source; nil = the default folder.
    public static func rawCandidate(_ o: LaunchOptions, environment: [String: String]) -> (value: String, source: AppFolderSource)? {
        func candidate(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }
        if let v = candidate(o.dataDir) { return (v, .argument) }
        if let v = candidate(environment[environmentKey]) { return (v, .environment) }
        return nil
    }

    /// `X:\…`, `X:/…`, `X:` and `\\server\…` are Windows paths (an error, never a relative path).
    public static func isWindowsShaped(_ value: String) -> Bool {
        let u = Array(value.utf8)
        if u.count >= 2, (u[0] >= 0x41 && u[0] <= 0x5A) || (u[0] >= 0x61 && u[0] <= 0x7A), u[1] == 0x3A {
            if u.count == 2 { return true }
            if u[2] == 0x5C || u[2] == 0x2F { return true }
        }
        return value.hasPrefix("\\\\")
    }

    /// `~`, `~/x` against `home`; `~user/x` through Foundation; everything else unchanged.
    static func expandTilde(_ value: String, home: URL) -> String {
        guard value.hasPrefix("~") else { return value }
        if value == "~" { return home.path }
        if value.hasPrefix("~/") { return home.path + String(value.dropFirst(1)) }
        return (value as NSString).expandingTildeInPath
    }

    /// The default folder: `<home>/Library/Application Support/AA`.
    public static func defaultFolder(home: URL) -> URL {
        home.appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "AA", directoryHint: .isDirectory)
    }

    public static func resolve(_ o: LaunchOptions, environment: [String: String], cwd: URL, home: URL)
        -> Result<(url: URL, source: AppFolderSource), DataDirError> {
        guard let (raw, source) = rawCandidate(o, environment: environment) else {
            return .success((defaultFolder(home: home), .defaultLocation))
        }
        if isWindowsShaped(raw) { return .failure(.windowsPath) }
        let value = expandTilde(raw, home: home)
        let url = value.hasPrefix("/")
            ? URL(fileURLWithPath: value, isDirectory: true)
            : URL(fileURLWithPath: value, isDirectory: true, relativeTo: URL(fileURLWithPath: cwd.path, isDirectory: true))
        return .success((normalized(url), source))
    }

    /// Absolute, `.`/`..` removed, no trailing "/", symlinks NOT resolved (`/tmp` stays `/tmp`).
    static func normalized(_ url: URL) -> URL {
        var parts: [String] = []
        for c in url.absoluteURL.path.split(separator: "/", omittingEmptySubsequences: true) {
            switch c {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(c))
            }
        }
        return URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: true)
    }

    /// 03 BD.3.3 — never `mkdir` under /Volumes when the volume is missing.
    public static func preflight(_ url: URL) throws(DataDirError) {
        let c = url.pathComponents                         // ["/", "Volumes", "STICK", …]
        if c.count >= 3, c[1] == "Volumes", !FileManager.default.fileExists(atPath: "/Volumes/" + c[2]) {
            throw .volumeMissing(c[2])
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            throw .notAFolder                                // BD.7.1 row 25: a regular file is not a folder
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .cannotCreate(error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw .notAFolder
        }
        guard access(url.path, W_OK) == 0 else {
            throw .notWritable(String(cString: strerror(errno)))
        }
    }

    // MARK: Alert texts (SHELL-194; Mac-only strings)

    public static let alertTitle = "AA can't open its data folder"
    public static let tryAgainButton = "Try Again"
    public static let quitButton = "Quit"

    public static func reason(_ e: DataDirError) -> String {
        switch e {
        case .volumeMissing(let name): return "The drive “\(name)” isn't connected. Connect it, then choose Try Again."
        case .windowsPath: return "That is a Windows path. On a Mac, use a folder such as /Volumes/DriveName/AA-data."
        case .notAFolder: return "That path is a file, not a folder."
        case .notWritable(let why): return why
        case .cannotCreate(let why): return why
        }
    }

    public static func sourceLine(_ s: AppFolderSource) -> String {
        switch s {
        case .argument: return "\n\nThe folder was given with --data-dir."
        case .environment: return "\n\nThe folder comes from the AA_DATA_DIR environment variable."
        case .defaultLocation: return ""
        }
    }

    public static func alertMessage(path: String, error: DataDirError, source: AppFolderSource) -> String {
        "AA couldn't open or create its data folder:\n\n\(path)\n\n\(reason(error))\(sourceLine(source))"
    }

    /// A Windows-path error offers only Quit; every other error offers Try Again (default) and Quit.
    public static func offersTryAgain(_ e: DataDirError) -> Bool { e != .windowsPath }
}
