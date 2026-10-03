// Spec: 03 SHELL-523 (Help ▸ AA Keyboard Shortcuts: the registry grouped by menu, a search field, columns Command,
//       Mac, Windows and Menu; generated from the registry so it can never drift), §6.5.1.11 (registry data format),
//       SHELL-630 (section items take their titles from the tab order), §6.5.1.4 (in-window keys).
import Foundation

/// One row of the Keyboard Shortcuts window.
public struct ShellXShortcutEntry: Sendable, Hashable, Identifiable {
    public var id: String
    public var command: CommandID
    public var title: String
    /// Key equivalent and hidden aliases in glyph notation (`⇧⌘S`, `⌘↩, ⌥⌘⌫`); "" when the row has no key.
    public var mac: String
    /// The individual chords of `mac` (first = the key equivalent), for keycap rendering.
    public var chords: [String]
    public var windows: String
    /// `File ▸ Shared Save`, or the scope for in-window rows.
    public var menu: String
    public var symbol: String?
    public var help: String?

    public init(id: String, command: CommandID, title: String, mac: String, chords: [String], windows: String,
                menu: String, symbol: String?, help: String?) {
        self.id = id; self.command = command; self.title = title; self.mac = mac; self.chords = chords
        self.windows = windows; self.menu = menu; self.symbol = symbol; self.help = help
    }
}

/// One menu's rows.
public struct ShellXShortcutGroup: Sendable, Hashable, Identifiable {
    public var id: String { title }
    public var title: String
    public var entries: [ShellXShortcutEntry]

    public init(title: String, entries: [ShellXShortcutEntry]) {
        self.title = title; self.entries = entries
    }
}

public enum ShellXShortcutCatalog {
    /// The group of rows that are not menu items (§6.5.1.4).
    public static let inWindowGroupTitle = "In-Window Keys"
    /// Menu-path separator (U+25B8, as in the specs' "File ▸ Save").
    public static let menuSeparator = " ▸ "

    /// Builds one entry. `sectionTitles` are the 13 section titles in display order (SHELL-630); when given, the
    /// View-menu items "Section n" show the section's real name.
    public static func entry(_ row: ShortcutRow, sectionTitles: [String]? = nil) -> ShellXShortcutEntry {
        var title = row.title
        if let pos = row.command.sectionPosition, let titles = sectionTitles, pos < titles.count {
            title = titles[pos]
        }
        var chords: [String] = []
        if !row.keyDisplay.isEmpty { chords.append(row.keyDisplay) }
        chords.append(contentsOf: row.aliases)
        let menu = row.isMenuItem ? row.menuPath.joined(separator: menuSeparator) : row.scope
        return ShellXShortcutEntry(id: row.id, command: row.command, title: title, mac: chords.joined(separator: ", "),
                                   chords: chords, windows: row.windowsGesture, menu: menu, symbol: row.symbol,
                                   help: row.help)
    }

    /// The registry grouped by top-level menu in menu-bar order (AA, File, Edit, Format, View, Tools, Window, Help),
    /// then the in-window keys; rows keep registry order. `query` filters case-insensitively on the command, the Mac
    /// keys, the Windows gesture and the menu path; empty groups are dropped.
    public static func groups(_ rows: [ShortcutRow] = ShortcutRegistry.rows, sectionTitles: [String]? = nil,
                              query: String = "") -> [ShellXShortcutGroup] {
        let q = NetText.trim(query)
        var order: [String] = []
        var byGroup: [String: [ShellXShortcutEntry]] = [:]
        for row in rows {
            let e = entry(row, sectionTitles: sectionTitles)
            if !q.isEmpty && !matches(e, q) { continue }
            let g = row.isMenuItem ? (row.menuPath.first ?? "") : inWindowGroupTitle
            if byGroup[g] == nil { order.append(g) }
            byGroup[g, default: []].append(e)
        }
        // Menu-bar order is the registry's first-appearance order; the in-window group always comes last.
        let menus = order.filter { $0 != inWindowGroupTitle }
        let tail = order.contains(inWindowGroupTitle) ? [inWindowGroupTitle] : []
        return (menus + tail).compactMap { g in byGroup[g].map { ShellXShortcutGroup(title: g, entries: $0) } }
    }

    static func matches(_ e: ShellXShortcutEntry, _ q: String) -> Bool {
        NetText.containsIgnoreCase(e.title, q) || NetText.containsIgnoreCase(e.mac, q)
            || NetText.containsIgnoreCase(e.windows, q) || NetText.containsIgnoreCase(e.menu, q)
    }

    /// Number of entries across groups.
    public static func count(_ groups: [ShellXShortcutGroup]) -> Int { groups.reduce(0) { $0 + $1.entries.count } }
}
