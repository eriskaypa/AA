// Spec: 04 HIER-136 / §4.6 / §6.8 (read-only viewer body: blank → grey "(no notes)", `enc:` → grey "(locked content)",
//       unparseable → the raw text as one paragraph, otherwise the editor's XAML → NSAttributedString converter with
//       clickable links), 05 CONT-098, 05 §XD.2.8 (`XamlContext.containerViewer`), 01 OC-12 (the missing-file text
//       and the open-error text name the RESOLVED path: `IsLink ? Path : ResolveFilePath(Path)`).
import AppKit

/// What the read-only viewer shows as its body.
public enum FileBankViewerBody {
    /// A grey placeholder line (`(no notes)` / `(locked content)`).
    case placeholder(String)
    /// The converted document (hyperlinks carry `.link`).
    case document(NSAttributedString)
    /// XAML that could not be parsed, shown literally.
    case raw(String)

    /// Decides the body exactly like `ContainerViewerWindow.LoadBody`.
    @MainActor public static func make(xaml: String) -> FileBankViewerBody {
        if NetText.isBlank(xaml) || LegacyBodyCrypto.isEncrypted(xaml) {
            return .placeholder(LegacyBodyCrypto.isEncrypted(xaml) ? FileBankText.viewerLocked : FileBankText.viewerNoNotes)
        }
        switch XamlReader.read(xaml, context: .containerViewer) {
        case .empty: return .placeholder(FileBankText.viewerNoNotes)
        case .document(let s, _): return .document(s)
        case .unparseable(let raw): return .raw(raw)
        }
    }

    public var isPlaceholder: Bool { if case .placeholder = self { return true }; return false }
}

/// Resolution of a file entry to what Open / Quick Look / Show in Finder act on, composed only from W-PERSIST's
/// contract (`AttachmentOpener`, `AttachmentStore`, `PathMapper`) — the file bank never re-implements it.
@MainActor public enum FileBankResolve {
    public enum State: Equatable, Sendable {
        /// A web link (never "missing").
        case web(URL?)
        /// A file or folder present on this Mac.
        case present(URL)
        /// A copy or live file that is not at its resolved location.
        case missing(String)
        /// A Windows drive-letter / UNC path with no mapping on this Mac (ARCH §9.4).
        case windowsUnmapped(String)
    }

    /// The text `{target}` of the OC-12 messages: the stored URL for links, else the resolved path.
    public static func target(of f: FileItem, dataStore: DataStore) -> String {
        if f.isLink { return f.path }
        if let u = AttachmentOpener.url(forStored: f.path, isLink: false, dataStore: dataStore), u.isFileURL {
            return u.path
        }
        return AttachmentStore.resolveFilePath(dataStore, stored: f.path)
    }

    /// The local file URL of a copy / live entry when it resolves to an absolute path (nil for links and for
    /// unmapped Windows paths).
    public static func fileURL(of f: FileItem, dataStore: DataStore) -> URL? {
        guard !f.isLink else { return nil }
        if let u = AttachmentOpener.url(forStored: f.path, isLink: false, dataStore: dataStore), u.isFileURL { return u }
        if PathMapper.isWindowsPath(f.path) { return PathMapper.shared.macURL(for: f.path) }
        let resolved = AttachmentStore.resolveFilePath(dataStore, stored: f.path)
        guard resolved.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: resolved)
    }

    public static func state(of f: FileItem, dataStore: DataStore) -> State {
        if f.isLink {
            return .web(AttachmentOpener.normalizeWebLink(f.path) ?? URL(string: f.path))
        }
        if let u = fileURL(of: f, dataStore: dataStore) {
            return FileManager.default.fileExists(atPath: u.path) ? .present(u) : .missing(u.path)
        }
        if PathMapper.isWindowsPath(f.path) { return .windowsUnmapped(f.path) }
        return .missing(target(of: f, dataStore: dataStore))
    }

    /// The local files among `files`, for Quick Look (links and missing files are skipped).
    public static func previewURLs(_ files: [FileItem], dataStore: DataStore) -> [URL] {
        files.compactMap { f in
            if case .present(let u) = state(of: f, dataStore: dataStore) { return u }
            return nil
        }
    }

    /// The drive (`Z:`) or share (`\\server\share`) named by an unmapped Windows path, for the alert text.
    public nonisolated static func windowsRoot(of path: String) -> String {
        if path.hasPrefix("\\\\") {
            let parts = path.dropFirst(2).split(separator: "\\", omittingEmptySubsequences: true)
            return "\\\\" + parts.prefix(2).joined(separator: "\\")
        }
        return String(path.prefix(2)).uppercased()
    }
}
