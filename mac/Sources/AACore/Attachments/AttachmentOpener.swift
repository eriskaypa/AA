// Spec: ARCHITECTURE.md §9.4 (open / reveal resolution table), 01 DATA-061–063, §6.6 (Windows live links on the Mac:
//       mapping table, "Windows path — not available on this Mac", Finder reveal), 05 §6.9 (web links without a
//       scheme, UNC → /Volumes/share → smb://), OC-12 (missing file message shows the resolved path),
//       DECISIONS 10 Q4.
import Foundation
import AppKit

public enum OpenOutcome: Sendable, Equatable {
    case opened, notFound(String), windowsPathUnmapped(String), failed(String)
}

@MainActor public enum AttachmentOpener {
    /// Test seams: the NSWorkspace calls (never launch apps from unit tests).
    static var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    static var reveal: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    static var mapper: PathMapper { mapperOverride ?? PathMapper.shared }
    static var mapperOverride: PathMapper?

    /// The Mac URL a stored path resolves to (§9.4 table), or nil when it cannot be resolved here (blank, an
    /// unmapped Windows path, an unparsable link).
    public static func url(forStored stored: String, isLink: Bool, dataStore: DataStore) -> URL? {
        let s = NetText.trim(stored)
        if s.isEmpty { return nil }
        if isLink { return normalizeWebLink(s) }
        if PersistPaths.isWebLink(s) { return URL(string: s) }
        if PathMapper.isWindowsPath(s) { return mapper.macURL(for: s) }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        if PersistPaths.isRooted(s) { return nil }                 // `C:foo` / `\foo`: Windows-only forms
        return URL(fileURLWithPath: AttachmentStore.resolveFilePath(dataStore, stored: s))
    }

    /// Opens a stored attachment or link with its default app (NSWorkspace). Folders are revealed in Finder;
    /// packages open like files.
    public static func open(stored: String, isLink: Bool, dataStore: DataStore) -> OpenOutcome {
        let s = NetText.trim(stored)
        guard let url = url(forStored: s, isLink: isLink, dataStore: dataStore) else {
            if !isLink, PathMapper.isWindowsPath(s) || PersistPaths.isRooted(s) && !s.hasPrefix("/") {
                return .windowsPathUnmapped(s)
            }
            return .failed(isLink ? "“\(s)” is not a link AA can open." : "The file location is empty.")
        }
        if !url.isFileURL {
            return openURL(url) ? .opened : .failed("Could not open \(url.absoluteString).")
        }
        let path = url.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return .notFound(path) }
        if isDir.boolValue, !NSWorkspace.shared.isFilePackage(atPath: path) {
            reveal([url])
            return .opened
        }
        return openURL(url) ? .opened : .failed("Could not open \(path).")
    }

    /// "Open containing folder" → Finder selects the item (works for folders too).
    public static func revealInFinder(stored: String, dataStore: DataStore) -> OpenOutcome {
        let s = NetText.trim(stored)
        guard let url = url(forStored: s, isLink: false, dataStore: dataStore) else {
            return PathMapper.isWindowsPath(s) ? .windowsPathUnmapped(s) : .failed("The file location is empty.")
        }
        guard url.isFileURL else { return .failed("“\(s)” is a web link, not a file.") }
        guard FileManager.default.fileExists(atPath: url.path) else { return .notFound(url.path) }
        reveal([url])
        return .opened
    }

    /// `www.` / domain-like → `https://`; `x@y` → `mailto:`; a URL with a scheme → as is. nil for blank text or
    /// text with spaces that is not a URL.
    public static func normalizeWebLink(_ s: String) -> URL? {
        let t = NetText.trim(s)
        if t.isEmpty { return nil }
        if PersistOpenerText.hasScheme(t) { return URL(string: t) ?? URL(string: t.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? t) }
        if t.contains(" ") { return nil }
        if t.contains("@"), !t.contains("/") { return URL(string: "mailto:" + t) }
        if NetText.toLowerInvariant(t).hasPrefix("www.") || t.contains(".") { return URL(string: "https://" + t) }
        return nil
    }
}

/// Texts and predicates of the opener (W-PERSIST).
public enum PersistOpenerText {
    /// `scheme:` per RFC 3986 (letter, then letters/digits/`+-.`), excluding a drive letter `C:`.
    public static func hasScheme(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let scheme = s[..<colon]
        guard scheme.count >= 2, let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    /// OC-12 / HIER-136: `That file is missing:\n\n{resolved path}`.
    public static func missing(_ resolvedPath: String) -> String { "That file is missing:\n\n\(resolvedPath)" }

    /// 01 §6.6 / 05 §6.9: a Windows path with no mapping on this Mac.
    public static func unmapped(_ windowsPath: String) -> String {
        if let unc = PathMapper.uncParts(windowsPath) {
            return "This file is on a Windows network share (\\\\\(unc.server)\\\(unc.share)). Windows path — not available on this Mac.\n\nConnect to the share, or map it to a folder on this Mac in Settings ▸ File Links."
        }
        let drive = String(windowsPath.prefix(2))
        return "This file is on a Windows drive (\(drive)). Map the drive letter to a folder on this Mac in Settings ▸ File Links."
    }
}
