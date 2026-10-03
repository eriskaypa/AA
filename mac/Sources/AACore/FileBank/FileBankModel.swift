// Spec: 05 CONT-080 (tabs, filters, columns and widths), CONT-082/084/085/086 (entry shapes), CONT-087 (copy-paste
//       entry), CONT-090 / HIER-136 (open-all threshold 15), CONT-094 (source label), 05 §6.9 + §8 K-17 (Added in
//       the user's locale), DECISIONS 05 ("Linked to" column, additive).
import Foundation

// MARK: - Tabs and columns (CONT-080)

/// The six category tabs of the Windows file bank, in Windows order.
public enum FileBankTab: String, CaseIterable, Sendable, Hashable {
    case all, documents, images, videos, links, other

    public var title: String {
        switch self {
        case .all: return "All"
        case .documents: return "Documents"
        case .images: return "Images"
        case .videos: return "Videos"
        case .links: return "Links"
        case .other: return "Other"
        }
    }

    /// SF Symbol shown beside the title in the category switcher.
    public var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .videos: return "film"
        case .links: return "globe"
        case .other: return "shippingbox"
        }
    }

    /// The exact CONT-080 filter. The tab never filters what a drop accepts (CONT-085).
    public func includes(kind: FileKind, isLink: Bool) -> Bool {
        switch self {
        case .all: return true
        case .documents: return kind == .document
        case .images: return kind == .image
        case .videos: return kind == .video
        case .links: return isLink
        case .other: return kind == .other && !isLink
        }
    }

    /// Entries shown in this tab, in collection (insertion) order — no sorting (CONT-080).
    @MainActor public func filter(_ files: [FileItem]) -> [FileItem] {
        self == .all ? files : files.filter { includes(kind: $0.kind, isLink: $0.isLink) }
    }

    /// Windows columns per tab, plus the additive "Linked to" column (DECISIONS 05) before Path/URL.
    public var columns: [FileBankColumn] {
        switch self {
        case .all: return [.name, .kind, .source, .added, .linkedTo, .path]
        case .documents: return [.name, .added, .linkedTo, .path]
        case .images, .videos: return [.name, .added, .linkedTo]
        case .links: return [.name, .linkedTo, .url]
        case .other: return [.name, .linkedTo, .path]
        }
    }
}

public enum FileBankColumn: String, CaseIterable, Sendable, Hashable {
    case name, kind, source, added, linkedTo, path, url

    public var title: String {
        switch self {
        case .name: return FileBankText.columnName
        case .kind: return FileBankText.columnKind
        case .source: return FileBankText.columnSource
        case .added: return FileBankText.columnAdded
        case .linkedTo: return FileBankText.linkedToColumn
        case .path: return FileBankText.columnPath
        case .url: return FileBankText.columnURL
        }
    }

    /// The WPF column width (px) used as the ideal width; Added is 150 on All and 160 elsewhere.
    public func idealWidth(in tab: FileBankTab) -> Double {
        switch self {
        case .name: return 280
        case .kind: return 80
        case .source: return 64
        case .added: return tab == .all ? 150 : 160
        case .linkedTo: return 180
        case .path, .url: return 500
        }
    }
}

// MARK: - Entry shapes (CONT-082…087)

@MainActor public enum FileBankEntries {
    /// Two spaces, then "(folder)" (CONT-085).
    public static let folderSuffix = "  (folder)"

    /// CONT-082 / CONT-083: an imported copy (`Path = files/{guid32}_{name}`; on a failed copy Windows stored the
    /// original path — the Mac offers link-in-place instead, K-9).
    public static func copy(name: String, storedPath: String, kind: FileKind, added: NetDateTime) -> FileItem {
        FileItem(name: name, path: storedPath, kind: kind, added: added, isLink: false, linkInPlace: false)
    }

    /// CONT-084: a file referenced at its original location.
    public static func linkedFile(name: String, storedPath: String, kind: FileKind, added: NetDateTime) -> FileItem {
        FileItem(name: name, path: storedPath, kind: kind, added: added, isLink: false, linkInPlace: true)
    }

    /// CONT-085: a folder linked in place → ONE entry `"{folder}  (folder)"`, Kind Other.
    public static func linkedFolder(folderName: String, storedPath: String, added: NetDateTime) -> FileItem {
        FileItem(name: folderName + folderSuffix, path: storedPath, kind: .other, added: added, isLink: false,
                 linkInPlace: true)
    }

    /// CONT-086: any non-whitespace text (unvalidated, untrimmed — even a bare `https://`) becomes a web link;
    /// nil for blank text (nothing is added).
    public static func webLink(_ text: String, added: NetDateTime) -> FileItem? {
        guard !NetText.isBlank(text) else { return nil }
        return FileItem(name: text, path: text, kind: .link, added: added, isLink: true, linkInPlace: false)
    }

    /// CONT-087 copy-mode paste: a new Id, the same Name/Path/Kind/IsLink/LinkInPlace, `Added = now`; the
    /// physical file is shared and `LinkedItemIds` are not copied.
    public static func pastedCopy(of f: FileItem, added: NetDateTime) -> FileItem {
        FileItem(name: f.name, path: f.path, kind: f.kind, added: added, isLink: f.isLink, linkInPlace: f.linkInPlace)
    }

    /// The display name of a folder linked in place (`DirectoryInfo.Name`; a volume root keeps its path).
    public nonisolated static func folderName(for url: URL) -> String {
        let leaf = url.standardizedFileURL.lastPathComponent
        return leaf.isEmpty ? url.path : leaf
    }
}

// MARK: - Display helpers

public enum FileBankDisplay {
    /// The Kind column shows the enum name (`Document`, `Image`, `Video`, `Link`, `Other`).
    public static func kindName(_ k: FileKind) -> String { k.name }

    /// Added column: the user's locale short date + time (05 §8 K-17; Windows printed en-US).
    public static func added(_ d: NetDateTime, locale: Locale = .current, zone: TimeZone = .current) -> String {
        added(d, formatter: addedFormatter(locale: locale, zone: zone))
    }

    /// One formatter per render (lists build it once, ARCH §9.7).
    public static func addedFormatter(locale: Locale = .current, zone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        f.calendar = Calendar(identifier: .gregorian)
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }

    public static func added(_ d: NetDateTime, formatter: DateFormatter) -> String {
        formatter.string(from: d.foundationDate(zone: formatter.timeZone ?? .current))
    }

    /// CONT-090 / HIER-136: more than 15 entries ask first.
    public static let openAllThreshold = 15
    public static func openAllNeedsConfirmation(_ count: Int) -> Bool { count > openAllThreshold }

    /// A path's file extension (lower-cased) for icons and Quick Look decisions.
    public static func pathExtension(_ path: String) -> String {
        let leaf = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
        guard let dot = leaf.lastIndex(of: "."), dot != leaf.startIndex else { return "" }
        return NetText.toLowerInvariant(String(leaf[leaf.index(after: dot)...]))
    }

    /// True when the stored path is a folder linked in place (its display name carries the folder suffix).
    @MainActor public static func isLinkedFolder(_ f: FileItem) -> Bool {
        f.linkInPlace && f.kind == .other && f.name.hasSuffix(FileBankEntries.folderSuffix)
    }
}

// MARK: - Router publishing (03 §6.5.1.10 list roles, SHELL-516, SHELL-670, T-KB-04/05)

/// What the file-bank and viewer tables publish to the command router: ⌘⌫ = "Remove" with **no confirmation**
/// (CONT-088), so plain ⌫/⌦ do nothing (`deleteConfirms == false` → no `.onDeleteCommand`); Space/⌘Y = Quick Look
/// only while the selection holds a local file (SHELL-543 enable rule); ↩ = Open. The viewer list has Open and
/// Quick Look only. The AA views build their `ListCommands` from these decisions.
public enum FileBankListPolicy {
    public static let role = "fileBank"
    public static let viewerRole = "viewerFiles"
    public static let deleteTitle = FileBankText.remove
    public static let deleteConfirms = false

    /// SHELL-543: `LIST(fileBank | viewerFiles)` "with a selection that has a local file".
    public static func quickLookAvailable(selectionHasLocalFile: Bool) -> Bool { selectionHasLocalFile }

    /// Remove is published only for an editable bank's own rows (never for the Shared view).
    public static func removeAvailable(editable: Bool, isShared: Bool) -> Bool { editable && !isShared }

    public static func state(selectionCount: Int, canRemove: Bool, selectionHasLocalFile: Bool = true) -> ShellListState {
        ShellListState(role: role, selectionCount: selectionCount, deleteTitle: deleteTitle, hasDelete: canRemove,
                       hasQuickLook: quickLookAvailable(selectionHasLocalFile: selectionHasLocalFile), hasPrimary: true)
    }

    public static func viewerState(selectionCount: Int, selectionHasLocalFile: Bool = true) -> ShellListState {
        ShellListState(role: viewerRole, selectionCount: selectionCount,
                       hasQuickLook: quickLookAvailable(selectionHasLocalFile: selectionHasLocalFile), hasPrimary: true)
    }
}
