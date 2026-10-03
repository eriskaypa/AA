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

/// One row of the Keyboard Shortcuts table: a menu's title row followed by its entries. The window shows the groups as
/// rows of one flat table, not as `Section`s: a SwiftUI `Table` with sections is an outline view whose section
/// expansion re-enters `NSTableView`'s row-height cache while the view is being made, which AppKit reports as
/// "reentrant operation in its NSTableView delegate" (Stage V round 2, design rule 18).
public enum ShellXShortcutTableRow: Sendable, Hashable, Identifiable {
    case header(title: String, count: Int, isFirst: Bool)
    case entry(ShellXShortcutEntry)

    public var id: String {
        switch self {
        case .header(let title, _, _): return "group:" + title
        case .entry(let e): return "entry:" + e.id
        }
    }

    public var entry: ShellXShortcutEntry? {
        if case .entry(let e) = self { return e }
        return nil
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
                                   chords: chords, windows: windowsText(row.windowsGesture), menu: menu,
                                   symbol: row.symbol, help: row.help)
    }

    /// The registry's Windows column as a user reads it: spec cross-references in parentheses (`(SHELL-115)`,
    /// `(Mac addition, §6.4)`, `(… — W-12)`) and WPF access-key underscores (`E_xit` → `Exit`) are dropped; a
    /// reference-only cell becomes `—`. Keys in parentheses such as `(Ctrl+S)` stay.
    public static func windowsText(_ raw: String) -> String {
        var s = raw
        let ns = s as NSString
        var removals: [NSRange] = []
        for m in referenceGroup.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            removals.append(m.range)
        }
        for r in removals.reversed() { s = (s as NSString).replacingCharacters(in: r, with: "") }
        s = accessKey.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                               withTemplate: "$1")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = NetText.trim(s)
        while let last = s.last, last == ";" || last == "," { s.removeLast(); s = NetText.trim(s) }
        if s.isEmpty || bareReference.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil {
            return "—"
        }
        return s
    }

    /// A cell that is nothing but spec IDs (`CONT-063`, `SHELL-056/082`).
    private static let bareReference = try! NSRegularExpression(pattern: #"^[A-Z]{1,5}-[A-Z]?\d+[a-z]?(?:\s*[/,]\s*(?:[A-Z]{1,5}-)?[A-Z]?\d+[a-z]?)*$"#)

    /// A parenthesised group holding a spec reference: an ID (`SHELL-115`, `HIER-M06`, `W-12`, `X-16`, `R-70`), a
    /// section sign, `DECISIONS`, or a two-digit spec number followed by a space (`05 §6.9`, `06 New List`).
    private static let referenceGroup = try! NSRegularExpression(
        pattern: #"\s*\((?=[^()]*(?:\b[A-Z]{1,5}-[A-Z]?\d|§|DECISIONS|\b\d{2} ))[^()]*\)"#)
    /// A WPF access-key marker: `_` before a letter or digit.
    private static let accessKey = try! NSRegularExpression(pattern: #"_([A-Za-z0-9])"#)

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

    /// The groups flattened into table rows: each group's header row, then its entries, in group order.
    public static func tableRows(_ groups: [ShellXShortcutGroup]) -> [ShellXShortcutTableRow] {
        var rows: [ShellXShortcutTableRow] = []
        for (i, g) in groups.enumerated() {
            rows.append(.header(title: g.title, count: g.entries.count, isFirst: i == 0))
            rows.append(contentsOf: g.entries.map { .entry($0) })
        }
        return rows
    }

    /// Number of entries across groups.
    public static func count(_ groups: [ShellXShortcutGroup]) -> Int { groups.reduce(0) { $0 + $1.entries.count } }
}
