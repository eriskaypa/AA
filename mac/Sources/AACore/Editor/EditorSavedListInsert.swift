// Spec: 05 CONT-047 (insert saved list: refusals, placement, one undo unit), CONT-048 / §3.4 (dialog: arranged order,
//       groups by first occurrence, "Ungrouped", search on name or any item title, preview, footer, pluralisation),
//       §7.3; 06 BUILD-100, BUILD-A18 (line building), §7.12 (vector).
import Foundation

/// The values the "Insert saved list" dialog needs from one saved-list item.
public struct EditorSavedListItemInfo: Sendable, Equatable {
    public var title: String
    public var minutes: Int
    /// `!IsNullOrWhiteSpace(Container.RichTextXaml)` (raw string test, BUILD-A18).
    public var hasNotes: Bool
    public var fileCount: Int

    public init(title: String, minutes: Int, hasNotes: Bool = false, fileCount: Int = 0) {
        self.title = title; self.minutes = minutes; self.hasNotes = hasNotes; self.fileCount = fileCount
    }
}

/// One row of the dialog's list.
public struct EditorSavedListRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var display: String
    public var groupName: String

    public init(id: UUID, display: String, groupName: String) {
        self.id = id; self.display = display; self.groupName = groupName
    }
}

/// A group header with its rows (headers in order of first occurrence in the arranged order).
public struct EditorSavedListGroup: Sendable, Equatable, Identifiable {
    public var name: String
    public var rows: [EditorSavedListRow]
    public var id: String { name }

    public init(name: String, rows: [EditorSavedListRow]) { self.name = name; self.rows = rows }
}

public enum EditorSavedListInsert {
    // Exact Windows texts (CONT-047/048, BUILD-100).
    public static let windowTitle = "Insert saved list"
    public static let header = "Insert a saved list"
    public static let subText = "The list is added where your cursor is. Nothing already in the note is changed, and one ⌘Z removes the whole list again."
    public static let searchPlaceholder = "Search saved lists..."
    public static let bulletsTitle = "• Bullets"
    public static let numberedTitle = "1. Numbered"
    public static let durationTitle = "Include each item's duration"
    public static let durationHelp = "Appends e.g. (60 min) to each line."
    public static let previewTitle = "Preview"
    public static let noItemsPreview = "(this saved list has no items)"
    public static let noListsFooter = "You have no saved lists yet. Build one in the Saved Lists tab first."
    public static let ungrouped = "Ungrouped"
    public static let withheldTitle = "Nothing inserted"
    public static let withheldText = "This note can't be edited right now because its saved content isn't loaded — unlock it first (Tools ▸ Set / change password, then reopen)."
    public static let buttonHelp = "Insert a saved list here as bullets or numbers. Your existing notes are not changed."

    /// BUILD-A18: titles trimmed, blanks dropped; with durations the k-th kept title maps back to the k-th non-blank
    /// item and gets `"  ({m} min)"` when m > 0.
    public static func lines(_ items: [EditorSavedListItemInfo], includeDuration: Bool) -> [String] {
        var out: [String] = []
        for it in items {
            let t = NetText.trim(it.title)
            guard !t.isEmpty else { continue }
            out.append(includeDuration && it.minutes > 0 ? "\(t)  (\(it.minutes) min)" : t)
        }
        return out
    }

    /// The preview text: `• line` / `n. line` per line, or `(this saved list has no items)`.
    public static func preview(_ lines: [String], numbered: Bool) -> String {
        guard !lines.isEmpty else { return noItemsPreview }
        return lines.enumerated().map { (numbered ? "\($0.offset + 1). " : "• ") + $0.element }.joined(separator: "\n")
    }

    /// `{n} line{s} will be inserted.` + ` Not carried over: {k} item has notes / items have notes, {f} attached file{s}.`
    public static func footer(lineCount n: Int, items: [EditorSavedListItemInfo]) -> String {
        let withNotes = items.filter(\.hasNotes).count
        let withFiles = items.reduce(0) { $0 + $1.fileCount }
        var notes: [String] = []
        if withNotes > 0 { notes.append("\(withNotes) item\(withNotes == 1 ? " has" : "s have") notes") }
        if withFiles > 0 { notes.append("\(withFiles) attached file\(withFiles == 1 ? "" : "s")") }
        let head = "\(n) line\(n == 1 ? "" : "s") will be inserted."
        return notes.isEmpty ? head : "\(head) Not carried over: \(notes.joined(separator: ", "))."
    }

    /// Item infos of one saved list.
    @MainActor public static func infos(_ t: ChecklistTemplate) -> [EditorSavedListItemInfo] {
        t.items.map {
            EditorSavedListItemInfo(title: $0.title, minutes: $0.durationMinutes,
                                    hasNotes: !NetText.isBlank($0.container.richTextXaml),
                                    fileCount: $0.container.files.count)
        }
    }

    /// CONT-048 search: trimmed query; empty → every list; else the name or any item title contains it
    /// (case-insensitive).
    @MainActor public static func matches(_ t: ChecklistTemplate, query: String) -> Bool {
        let q = NetText.trim(query)
        if q.isEmpty { return true }
        return NetText.containsIgnoreCase(t.name, q) || t.items.contains { NetText.containsIgnoreCase($0.title, q) }
    }

    /// The dialog's grouped rows in arranged order (`Data.ChecklistTemplates`), headers in order of first occurrence;
    /// group name = the List Group's name (exact id match) or "Ungrouped".
    @MainActor public static func groups(templates: [ChecklistTemplate], listGroups: [ListGroup],
                                         query: String) -> [EditorSavedListGroup] {
        var names: [UUID: String] = [:]
        for g in listGroups where names[g.id] == nil { names[g.id] = g.name }
        var order: [String] = []
        var rows: [String: [EditorSavedListRow]] = [:]
        for t in templates where matches(t, query: query) {
            let g = t.groupId.flatMap { names[$0] } ?? ungrouped
            if rows[g] == nil { order.append(g); rows[g] = [] }
            rows[g]?.append(EditorSavedListRow(id: t.id, display: t.display, groupName: g))
        }
        return order.map { EditorSavedListGroup(name: $0, rows: rows[$0] ?? []) }
    }
}
