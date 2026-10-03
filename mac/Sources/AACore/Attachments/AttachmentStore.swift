// Spec: 01 §F (DATA-060…068), §3.5–3.8, §6.6 (Windows-safe names, case-insensitive matching, Finder metadata),
//       §7.6 (path vectors); 05 CONT-081 (classification), §4.2, §7 Mac sanitiser vectors; DECISIONS 05 (packages are
//       zipped into one `files/` entry, pasted images go to the file bank); ARCHITECTURE.md §6.6.
import Foundation

@MainActor public enum AttachmentStore {
    // MARK: Import (DATA-060, §3.5)

    /// "files/<32hex>_<leaf>". A directory or a macOS package (`.app`, `.pages`, `.rtfd`, … — any URL whose
    /// resource values say isDirectory/isPackage) is ZIPPED into ONE entry `files/<32hex>_<name>.zip` (DECISIONS 05).
    /// The stored leaf is Windows-safe (01 §6.6) so a bundle made on this Mac always extracts on Windows.
    public static func importFile(_ ds: DataStore, from source: URL) throws -> String {
        let files = ds.filesFolder
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let src = source.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? src.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isFolder = (values?.isDirectory ?? false) || (values?.isPackage ?? false)
        let name = src.lastPathComponent
        let leaf = windowsSafeLeaf(UUID().netN + "_" + (isFolder ? name + ".zip" : name))
        let dest = files.appending(path: leaf)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        if isFolder {
            try PersistPackageZipper.zip(folder: src, to: dest)
        } else {
            try FileManager.default.copyItem(at: src, to: dest)
        }
        return "files/" + leaf
    }

    /// Pasted/dropped bytes without a file URL (images pasted into a note, DECISIONS 05): writes `data` directly to
    /// `files/<32hex>_<windowsSafeLeaf(suggestedName)>` (atomic) and returns the stored path. This is the only way
    /// the AA target gets such bytes into the data folder (§2.1: the AA target never writes temp files).
    public static func importData(_ ds: DataStore, _ data: Data, suggestedName: String) throws -> String {
        let files = ds.filesFolder
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let base = NetText.isBlank(suggestedName) ? "attachment" : suggestedName
        let leaf = windowsSafeLeaf(UUID().netN + "_" + base)
        try AtomicWrite.write(data, to: files.appending(path: leaf))
        return "files/" + leaf
    }

    // MARK: Resolve (DATA-063)

    /// `""` → `""`; `http://`, `https://`, `mailto:` (any case) → unchanged; rooted (POSIX, drive letter, UNC) →
    /// unchanged; otherwise `AppFolder/<stored>` with `\` turned into `/`, normalised like `Path.GetFullPath`.
    public static func resolveFilePath(_ ds: DataStore, stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return "" }
        if PersistPaths.isWebLink(stored) { return stored }
        if PersistPaths.isRooted(stored) { return stored }
        let rel = stored.replacingOccurrences(of: "\\", with: "/")
        return ds.appFolder.appending(path: rel).standardizedFileURL.path
    }

    // MARK: Normalise / migrate (DATA-064, DATA-065, §3.7, §3.8)

    /// Called by `DataStore` on every load and before every save (01 §3.7).
    public static func normalizeFilePaths(_ ds: DataStore, data: AppData) {
        try? FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        let appFull = PersistPaths.folderPrefix(ds.appFolder)
        for c in enumerateContainers(data) {
            for f in c.files {
                if f.isLink || f.linkInPlace { continue }
                let p = f.path
                if p.isEmpty || !PersistPaths.isRooted(p) { continue }
                // Case 1: an absolute POSIX path inside this AppFolder (case-insensitive like Windows).
                if p.hasPrefix("/") {
                    let full = URL(fileURLWithPath: p).standardizedFileURL.path
                    if let rest = PersistPaths.dropPrefixIgnoringCase(full, prefix: appFull) {
                        f.path = rest.replacingOccurrences(of: "\\", with: "/")
                        continue
                    }
                }
                // Case 2: a foreign absolute path ending in ".../files/<leaf>" whose leaf exists locally.
                if let rel = PersistPaths.filesRelative(p) {
                    let leaf = String(rel.dropFirst("files/".count))
                    if !leaf.isEmpty, FileManager.default.fileExists(atPath: ds.filesFolder.appending(path: leaf).path) {
                        f.path = rel
                    }
                }
            }
        }
    }

    /// Bundle import / Flash Sync apply: rewrite another workstation's absolute `files\` paths unconditionally.
    public static func migrateLegacyAbsolutePaths(_ ds: DataStore, data: AppData) {
        for c in enumerateContainers(data) {
            for f in c.files {
                if f.isLink || f.linkInPlace { continue }
                let p = f.path
                if p.isEmpty || !PersistPaths.isRooted(p) { continue }
                if let rel = PersistPaths.filesRelative(p) { f.path = rel }
            }
        }
    }

    // MARK: Classification (DATA-066, CONT-081)

    /// DATA-066 table: lower-cased extension (with the dot) of the last path segment.
    public nonisolated static func classify(path: String) -> FileKind {
        switch PersistPaths.extensionLowercased(path) {
        case ".pdf", ".docx", ".doc", ".xlsx", ".xls", ".pptx", ".ppt", ".txt", ".rtf": return .document
        case ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".heic", ".gif": return .image
        case ".mov", ".mp4", ".wmv", ".avi", ".mkv", ".m4v", ".webm": return .video
        default: return .other
        }
    }

    // MARK: Windows-safe names (01 §6.6)

    /// NFC; `< > : " / \ | ?  *` and U+0000–U+001F → `_`; trailing spaces and dots stripped; a reserved device stem
    /// (`CON PRN AUX NUL COM1–9 LPT1–9`, any case) gets a `_` prefix; capped at 150 UTF-16 units keeping the
    /// extension. Never empty (`_`).
    public nonisolated static func windowsSafeLeaf(_ name: String) -> String {
        let nfc = name.precomposedStringWithCanonicalMapping
        var scalars = String.UnicodeScalarView()
        for sc in nfc.unicodeScalars {
            if sc.value < 0x20 || "<>:\"/\\|?*".unicodeScalars.contains(sc) { scalars.append("_") } else { scalars.append(sc) }
        }
        var s = PersistPaths.trimTrailingSpacesAndDots(String(scalars))
        if s.isEmpty { return "_" }
        let stem = String(s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        if PersistPaths.isReservedDeviceName(stem) { s = "_" + s }
        if s.utf16.count > PersistPaths.maxLeafUnits {
            var ext = ""
            if let dot = s.lastIndex(of: "."), dot != s.startIndex {
                let e = String(s[dot...])
                if e.utf16.count < 32 { ext = e }
            }
            var stemPart = ext.isEmpty ? s : String(s.dropLast(ext.count))
            while stemPart.utf16.count + ext.utf16.count > PersistPaths.maxLeafUnits, !stemPart.isEmpty {
                stemPart.removeLast()
            }
            stemPart = PersistPaths.trimTrailingSpacesAndDots(stemPart)
            s = stemPart.isEmpty ? "_" + ext : stemPart + ext
        }
        return s
    }

    // MARK: Enumeration (DATA-068)

    /// Equipment (+ components), tasks (recursively through subtasks), procedures (+ steps), vessels, crew checklist
    /// steps and saved-list items — exactly the containers the Windows `EnumerateContainers` visits.
    public static func enumerateContainers(_ data: AppData) -> [Container] {
        var out: [Container] = []
        for eq in data.equipment {
            out.append(eq.container)
            for c in eq.components { out.append(c.container) }
        }
        func walk(_ t: TaskItem) {
            out.append(t.container)
            for st in t.subtasks { walk(st) }
        }
        for t in data.tasks { walk(t) }
        for p in data.procedures {
            out.append(p.container)
            for s in p.steps { out.append(s.container) }
        }
        for v in data.vessels { out.append(v.container) }
        for cm in data.crew { for s in cm.checklist { out.append(s.container) } }
        for tpl in data.checklistTemplates { for it in tpl.items { out.append(it.container) } }
        return out
    }
}

/// Path predicates shared by the attachment store, the bundle service and the opener (W-PERSIST).
public enum PersistPaths {
    /// 01 §6.6: the leaf cap in UTF-16 units.
    public static let maxLeafUnits = 150

    /// `http://`, `https://`, `mailto:` (case-insensitive) — the prefixes `ResolveFilePath` passes through.
    public static func isWebLink(_ s: String) -> Bool {
        for p in ["http://", "https://", "mailto:"] where s.utf16.count >= p.utf16.count {
            if NetText.equalsIgnoreCase(String(s.utf16.prefix(p.utf16.count)) ?? "", p) { return true }
        }
        return false
    }

    /// 01 §3.7 [MAC] rootedness: drive-qualified (`C:`, `C:\`, `C:/`), UNC (`\\`), root-relative (`\…`) or POSIX `/…`.
    public static func isRooted(_ s: String) -> Bool {
        let u = Array(s.utf16)
        guard let first = u.first else { return false }
        if first == 0x2F || first == 0x5C { return true }
        if u.count >= 2, u[1] == 0x3A, PersistPaths.isASCIILetter(first) { return true }
        return false
    }

    static func isASCIILetter(_ c: UInt16) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }

    /// `"<folder path>/"` with the folder standardised and trailing separators removed.
    public static func folderPrefix(_ folder: URL) -> String {
        var root = folder.standardizedFileURL.path
        while root.count > 1, root.hasSuffix("/") || root.hasSuffix("\\") { root.removeLast() }
        return root + "/"
    }

    /// The rest of `s` after `prefix` when `s` starts with it (OrdinalIgnoreCase), else nil.
    public static func dropPrefixIgnoringCase(_ s: String, prefix: String) -> String? {
        let su = Array(s.utf16), pu = Array(prefix.utf16)
        guard su.count >= pu.count else { return nil }
        for i in 0..<pu.count where NetText.simpleUpper(su[i]) != NetText.simpleUpper(pu[i]) { return nil }
        return String(decoding: su[pu.count...], as: UTF16.self)
    }

    /// `"files/<rest>"` for a path containing `/files/` (separators normalised, last occurrence, OrdinalIgnoreCase,
    /// the original case of the segment kept), else nil — the shared step of §3.7 case 2 and §3.8.
    public static func filesRelative(_ p: String) -> String? {
        let norm = Array(p.replacingOccurrences(of: "\\", with: "/").utf16)
        let needle = Array("/files/".utf16).map(NetText.simpleUpper)
        guard norm.count >= needle.count else { return nil }
        var i = norm.count - needle.count
        while i >= 0 {
            var match = true
            for j in 0..<needle.count where NetText.simpleUpper(norm[i + j]) != needle[j] { match = false; break }
            if match { return String(decoding: norm[(i + 1)...], as: UTF16.self) }
            i -= 1
        }
        return nil
    }

    /// `Path.GetExtension(path).ToLowerInvariant()` over `/` and `\` separators ("" when none).
    public static func extensionLowercased(_ path: String) -> String {
        let u = Array(path.utf16)
        var i = u.count - 1
        while i >= 0 {
            let c = u[i]
            if c == 0x2F || c == 0x5C || c == 0x3A { return "" }
            if c == 0x2E {
                if i == u.count - 1 { return "" }
                return NetText.toLowerInvariant(String(decoding: u[i...], as: UTF16.self))
            }
            i -= 1
        }
        return ""
    }

    static func trimTrailingSpacesAndDots(_ s: String) -> String {
        var t = s
        while let last = t.last, last == " " || last == "." { t.removeLast() }
        return t
    }

    static func isReservedDeviceName(_ stem: String) -> Bool {
        let up = NetText.toUpperInvariant(stem)
        if ["CON", "PRN", "AUX", "NUL"].contains(up) { return true }
        if up.count == 4, up.hasPrefix("COM") || up.hasPrefix("LPT"), let d = up.last, ("1"..."9").contains(d) {
            return true
        }
        return false
    }

    /// Finder metadata never bundled, counted, swept or zipped: `.DS_Store`, `._*`, `.localized`, `Icon\r`,
    /// anything under `__MACOSX/` (01 §6.6, §6.7).
    public static func isFinderMetadata(_ name: String) -> Bool {
        if ZipReader.isFinderMetadata(name) { return true }
        let last = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? name
        return last == ".localized"
    }
}

/// Zips a directory or package into one archive whose entries sit under the folder's own name (DECISIONS 05).
/// Regular files and empty directories are stored; Finder metadata is skipped; symbolic links are not followed
/// and not stored (Deviations/W-PERSIST.md).
enum PersistPackageZipper {
    static func zip(folder: URL, to dest: URL) throws {
        let fm = FileManager.default
        let root = folder.standardizedFileURL
        let top = root.lastPathComponent
        let writer: ZipWriter
        do { writer = try ZipWriter(url: dest) } catch { throw error }
        var ok = false
        defer { if !ok { try? fm.removeItem(at: dest) } }
        func add(_ dir: URL, rel: String) throws {
            let kids = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys:
                [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey], options: [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let visible = kids.filter { !PersistPaths.isFinderMetadata($0.lastPathComponent) }
            if visible.isEmpty {
                try writer.addDirectory(named: rel + "/")
                return
            }
            for k in visible {
                let v = try k.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                if v.isSymbolicLink == true { continue }
                let name = rel + "/" + k.lastPathComponent
                if v.isDirectory == true {
                    try add(k, rel: name)
                } else {
                    try writer.addFile(named: name, from: k, modified: v.contentModificationDate)
                }
            }
        }
        try add(root, rel: top)
        try writer.finish()
        ok = true
    }
}
