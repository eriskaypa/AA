// Spec: 05 §6.9 (drag rows OUT to Finder / Mail as file URLs; ⌘C in AA, ⌘V in Finder / Mail), 05 CONT-092 (Rename
//       changes the display name only), CONT-097 (copies are stored as `files/<32hex>_<sanitised leaf>`),
//       ARCHITECTURE.md §2.1 (the AA target never touches files itself — staging lives here, in AACore).
// A file bank entry leaves AA under its display name (`FileItem.Name`), never as the GUID-prefixed stored leaf: the
// stored file is cloned (APFS copy-on-write; a plain copy on other volumes) into a private staging folder under that
// name, and the drag / pasteboard carries the staged URL. Staged URLs remember where they came from, so a row dragged
// from one AA file bank into another is still referenced (not duplicated) and keeps its display name.
import Foundation
import Synchronization

public enum FileBankExport {
    /// What a staged file was made from.
    public struct Origin: Equatable, Sendable {
        /// The stored file (inside `files/` for a copy, the live target for a link in place).
        public var source: URL
        /// The entry's display name (`FileItem.Name`).
        public var name: String
        public init(source: URL, name: String) { self.source = source; self.name = name }
    }

    private struct Key: Hashable { let source: String; let name: String; let modified: Double }

    private static let registry = Mutex<(byKey: [Key: URL], byStaged: [String: Origin])>(([:], [:]))

    // MARK: Names

    /// The file name an entry is exported under: the display name with `/` and `:` replaced by `-` and leading dots
    /// dropped (no hidden files), the stored file's extension appended when the display name does not already end in
    /// it (a rename to "Main engine manual (rev 3)" still exports as a `.pdf`), at most 255 UTF-8 bytes. A blank name
    /// falls back to the stored leaf without its 32-hex import prefix.
    public static func exportName(displayName: String, sourceLeaf: String) -> String {
        var name = NetText.trim(displayName)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\u{0}", with: "")
        while name.hasPrefix(".") { name.removeFirst() }
        name = NetText.trim(name)
        if name.isEmpty { name = FileBankImporter.displayName(ofStoredLeaf: sourceLeaf) }
        let ext = (sourceLeaf as NSString).pathExtension
        if !ext.isEmpty, (name as NSString).pathExtension.lowercased() != ext.lowercased() { name += "." + ext }
        return fitted(name, maxBytes: 255)
    }

    private static func fitted(_ name: String, maxBytes: Int) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        var base = String((name as NSString).deletingPathExtension)
        while !base.isEmpty, base.utf8.count + suffix.utf8.count > maxBytes { base.removeLast() }
        return base + suffix
    }

    // MARK: Staging

    /// The URL to hand to Finder / Mail for a local file shown as `displayName`: `source` itself when its name already
    /// is the export name (or it is a folder / package, exported as is), else a clone named after the entry. The
    /// clone is reused while the source is unchanged. Falls back to `source` when staging fails.
    public static func exportURL(for source: URL, displayName: String) -> URL {
        (try? stage(source, displayName: displayName)) ?? source
    }

    /// See `exportURL(for:displayName:)`; throws when the clone could not be made.
    public static func stage(_ source: URL, displayName: String) throws -> URL {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir), !isDir.boolValue else {
            return source
        }
        let name = exportName(displayName: displayName, sourceLeaf: source.lastPathComponent)
        if name == source.lastPathComponent { return source }
        let modified = (try? source.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?
            .timeIntervalSince1970 ?? 0
        let key = Key(source: source.standardizedFileURL.path, name: name, modified: modified)
        if let hit = registry.withLock({ $0.byKey[key] }), FileManager.default.fileExists(atPath: hit.path) { return hit }
        let folder = try stagingFolder(for: source)
        let staged = folder.appending(path: name)
        try FileManager.default.copyItem(at: source, to: staged)          // clonefile(2) on APFS, else a copy
        let origin = Origin(source: source.standardizedFileURL, name: displayName)
        registry.withLock {
            $0.byKey[key] = staged
            $0.byStaged[staged.standardizedFileURL.resolvingSymlinksInPath().path] = origin
        }
        return staged
    }

    /// The entry a staged URL was exported from (nil for every other URL).
    public static func origin(of url: URL) -> Origin? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return registry.withLock { $0.byStaged[path] }
    }

    /// The real file behind `url`: the source of a staged export, else `url` itself.
    public static func sourceURL(of url: URL) -> URL { origin(of: url)?.source ?? url }

    /// A fresh, private folder on the source's volume (so APFS clones instead of copying), one per staged file so
    /// equal display names never collide. The system cleans `TemporaryItems`; the folder is never inside the data
    /// folder.
    private static func stagingFolder(for source: URL) throws -> URL {
        let fm = FileManager.default
        if let dir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: source, create: true) {
            return dir
        }
        let dir = fm.temporaryDirectory.appending(path: "AA File Bank Export", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
