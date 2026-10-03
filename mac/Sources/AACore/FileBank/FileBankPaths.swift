// Spec: 05 CONT-083 (Add Folder: every file of the folder and all sub-folders, flattened; empty folders ignored;
//       an access error stops the import), §8 K-8 (Mac skips `.DS_Store`, `._*` AppleDouble files and `Icon\r`;
//       other hidden files are imported), DECISIONS 05 (macOS packages are imported as ONE zipped entry by
//       `AttachmentStore.importFile`, so a scan never descends into a package), 05 §6.9 "Link in place on the Mac"
//       (store a Windows-openable form when one exists: the path-mapping table in reverse, else the UNC form of a
//       mounted SMB share derived from `volumeURLForRemounting`, else the POSIX path), CONT-097 (never rewritten).
import Foundation

// MARK: - Folder scan (CONT-083, K-8)

public enum FileBankFolderScan {
    /// Finder litter that a folder import skips (K-8).
    public static func isSkipped(name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._") || name == "Icon\r"
    }

    /// Every importable file below `folder`, flattened, in a stable order (directory entries sorted by name with
    /// the ordinal comparer, files before the next sub-folder's files as the walk reaches them). Packages
    /// (`.app`, `.pages`, `.rtfd`, …) are returned as single URLs and never entered; symbolic links to folders
    /// are not followed (no cycles); empty folders contribute nothing. Throws on the first unreadable folder
    /// (the caller keeps what it already imported, CONT-083).
    public static func importableFiles(in folder: URL) throws -> [URL] {
        var out: [URL] = []
        try walk(folder, into: &out)
        return out
    }

    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                                    .isRegularFileKey]

    private static func walk(_ dir: URL, into out: inout [URL]) throws {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [])
            .filter { !isSkipped(name: $0.lastPathComponent) }
            .sorted { Ordinal.compare($0.lastPathComponent, $1.lastPathComponent) == .orderedAscending }
        for child in children {
            let v = try? child.resourceValues(forKeys: keys)
            if v?.isSymbolicLink == true {
                // A link to a file is imported (its target is copied); a link to a folder is not followed.
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: child.path, isDirectory: &isDir), !isDir.boolValue { out.append(child) }
                continue
            }
            if v?.isDirectory == true {
                if v?.isPackage == true { out.append(child) } else { try walk(child, into: &out) }
            } else {
                out.append(child)
            }
        }
    }

    /// True for a directory that macOS presents as a single document (`isPackage`).
    public static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    /// True for a plain (non-package) directory.
    public static func isPlainDirectory(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return v?.isDirectory == true && v?.isPackage != true
    }
}

// MARK: - Stored path for a link in place (05 §6.9)

public enum FileBankLinkPath {
    /// The `FileItem.Path` to store for a file or folder linked in place at POSIX `path`:
    /// 1. a path under a mapped Mac folder → that mapping's Windows prefix + the rest with `\` separators (longest
    ///    Mac folder wins), so the Windows build opens the same file;
    /// 2. a path on a mounted SMB share (`remountURL` `smb://[user@]server/share[/sub]`, `volumePath` its mount
    ///    point) → `\\server\share[\sub]\rest`;
    /// 3. otherwise the POSIX path itself (Windows will report "Not found").
    public static func storedPath(posixPath path: String, mappings: [PathMapping], volumePath: String?,
                                  remountURL: URL?) -> String {
        let p = trimTrailingSlash(path)
        var best: (prefixLength: Int, windows: String)?
        for m in mappings {
            let mac = trimTrailingSlash(m.macPath)
            guard !mac.isEmpty, !NetText.isBlank(m.windowsPrefix) else { continue }
            guard let rest = remainder(of: p, under: mac) else { continue }
            if best == nil || mac.count > best!.prefixLength {
                best = (mac.count, joinWindows(m.windowsPrefix, rest))
            }
        }
        if let best { return best.windows }
        if let remountURL, let scheme = remountURL.scheme?.lowercased(), scheme == "smb" || scheme == "cifs",
           let host = remountURL.host(percentEncoded: false), !host.isEmpty,
           let volumePath, let rest = remainder(of: p, under: trimTrailingSlash(volumePath)) {
            let shareParts = remountURL.path(percentEncoded: false).split(separator: "/").map(String.init)
            if !shareParts.isEmpty {
                let unc = "\\\\" + host + "\\" + shareParts.joined(separator: "\\")
                return joinWindows(unc, rest)
            }
        }
        return path
    }

    /// Reads the volume of `url` and calls `storedPath(posixPath:…)`.
    public static func storedPath(for url: URL, mappings: [PathMapping]) -> String {
        let std = url.standardizedFileURL
        let v = try? std.resourceValues(forKeys: [.volumeURLKey, .volumeURLForRemountingKey])
        return storedPath(posixPath: std.path, mappings: mappings, volumePath: v?.volume?.path,
                          remountURL: v?.volumeURLForRemounting)
    }

    /// The path below `base` (`""` when equal), or nil when `path` is not inside `base` at a component boundary.
    static func remainder(of path: String, under base: String) -> String? {
        if base == "/" { return String(path.drop(while: { $0 == "/" })) }
        if path == base { return "" }
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    static func trimTrailingSlash(_ s: String) -> String {
        var t = s
        while t.count > 1, t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// `prefix` (trailing `\` or `/` removed) + `\` + rest with `/` → `\`; a drive prefix `Z:` gets its root `Z:\`.
    static func joinWindows(_ prefix: String, _ rest: String) -> String {
        var pre = prefix
        while let last = pre.last, last == "\\" || last == "/" { pre.removeLast() }
        let tail = rest.replacingOccurrences(of: "/", with: "\\")
        if tail.isEmpty { return pre.count == 2 && pre.hasSuffix(":") ? pre + "\\" : pre }
        return pre + "\\" + tail
    }
}
