// Spec: 08 §2.4 (QUICK-120…125), §3.4 (BuildHighlighted — exact clamping), §7.4 (T-SR-4, T-SR-10); 02 REPO-100;
//       08 §2.6 (QUICK-170…178), 02 REPO-078, 01 DATA-113, DECISIONS 02 Q-5 (Finder wording "Put Back" / "Delete
//       Immediately", "Restore" in tooltips), 03 SHELL-675 (in-sheet keys); 08 §2.7 (QUICK-190…196), 01 DATA-100…104,
//       DECISIONS 01 Q-3 ("Other data"); 08 §2.3 (QUICK-100…107).
import Foundation

// MARK: Search window

public enum SearchWindowText {
    public static let windowTitle = "Search"
    public static let queryLabel = "Search:"
    public static let searchButton = "Search"
    public static let searching = "Searching\u{2026}"
    public static let queryPrompt = "Name, tag, note text, file name\u{2026}"
    public static let whereColumn = "Where"
    public static let matchColumn = "Match"

    /// Rule 17 (V2-DESIGN): the status bar under the results shows only while a search runs or there are hits. Before
    /// the first search it would be an empty strip, and with no hits the empty state already carries the status.
    public static func showsStatusBar(isRunning: Bool, hitCount: Int) -> Bool { isRunning || hitCount > 0 }

    /// `No results for "{query}".` / `{n} result for "{query}".` / `{n} results for "{query}".` (query trimmed).
    public static func status(count: Int, query: String) -> String {
        count == 0 ? "No results for \"\(query)\"." : "\(count) result\(count == 1 ? "" : "s") for \"\(query)\"."
    }
}

/// 08 §3.4 `BuildHighlighted`: `start` outside `[0, length]` → 0; `end = min(length, start + max(0, len))`; runs
/// prefix (if start > 0), match (if end > start), suffix (if end < length). Offsets are UTF-16 units.
public struct SearchHighlight: Sendable, Hashable {
    public var prefix: String
    public var match: String
    public var suffix: String

    public init(prefix: String, match: String, suffix: String) {
        self.prefix = prefix; self.match = match; self.suffix = suffix
    }

    public static func split(_ text: String, start: Int, length: Int) -> SearchHighlight {
        let u = Array(text.utf16)
        var s = start
        if s < 0 || s > u.count { s = 0 }
        var e = min(u.count, s + max(0, length))
        // Never split a surrogate pair (Swift cannot hold a lone surrogate).
        if s > 0, s < u.count, UTF16.isTrailSurrogate(u[s]) { s -= 1 }
        if e > s, e < u.count, UTF16.isTrailSurrogate(u[e]) { e += 1 }
        return SearchHighlight(prefix: String(decoding: u[0..<s], as: UTF16.self),
                               match: String(decoding: u[s..<e], as: UTF16.self),
                               suffix: String(decoding: u[e..<u.count], as: UTF16.self))
    }
}

// MARK: Trash

public enum TrashText {
    public static let windowTitle = "Trash"
    public static let info = "Deleted items are kept here so a mistake can be undone. Restore puts an item (with its whole subtree) back where it was. Items are auto-removed after 90 days, or once there are more than 200."
    public static let menuHelp = "Restore items you deleted, or remove them for good. Deletes go here instead of vanishing \u{2014} \u{2318}Z undoes the last one."
    public static let columns = ["Name", "Kind", "Deleted"]
    /// DECISIONS 02 Q-5: Finder wording, "Restore" kept in the tooltip.
    public static let putBack = "Put Back"
    public static let putBackHelp = "Restore: put the selected item(s) back where they were."
    public static let deleteImmediately = "Delete Immediately\u{2026}"
    public static let deleteImmediatelyHelp = "Remove the selected item(s) from the Trash for good (cannot be undone)."
    public static let emptyTrash = "Empty Trash\u{2026}"
    public static let emptyTrashHelp = "Permanently remove everything in the Trash."
    public static let close = "Close"
    public static let restoreFailedTitle = "Restore"
    public static let restoreFailed = "Couldn't restore the selected item(s)."
    public static let deleteTitle = "Delete permanently"
    public static let emptyTitle = "Empty Trash"
    public static let emptyListMessage = "The Trash is empty."
    /// The empty state's one-line next step (Mac addition, V-DESIGN rule 12).
    public static let emptyListHint = "Items you delete land here. Put them back from this window, or undo the last delete with \u{2318}Z."

    /// 01 DATA-174: Put Back, Delete Immediately and Empty Trash are disabled in a read-only copy of AA, with the shared
    /// help text instead of their own tooltips.
    public static func help(_ normal: String, readOnly: Bool) -> String {
        readOnly ? PersistReadOnlyText.disabledHelp : normal
    }

    public static func deleteMessage(_ n: Int) -> String {
        "Permanently delete \(n) item(s) from the Trash? This cannot be undone."
    }

    public static func emptyMessage(_ n: Int) -> String {
        "Permanently remove all \(n) item(s) in the Trash? This cannot be undone."
    }

    /// Footer count (Mac addition).
    public static func count(_ n: Int) -> String { n == 1 ? "1 item in the Trash" : "\(n) items in the Trash" }
}

@MainActor public enum TrashActions {
    /// 08 QUICK-174 / 02 REPO-078: restores each entry (looked up again by id in the live Trash); returns the
    /// distinct restored types in restore order (empty = nothing restored → the warning). Partial failures are
    /// silent. The caller saves once when anything was restored.
    public static func restore(entryIDs: [UUID], store: AppStore) -> [TrashItemType] {
        var types: [TrashItemType] = []
        for id in entryIDs {
            guard let e = store.data.trash.first(where: { $0.id == id }) else { continue }
            if let t = store.restore(e), !types.contains(t) { types.append(t) }
        }
        return types
    }

    /// 08 QUICK-175: purges each selected entry (references scrubbed). Returns how many were removed.
    @discardableResult
    public static func purge(entryIDs: [UUID], store: AppStore) -> Int {
        var n = 0
        for id in entryIDs {
            guard let e = store.data.trash.first(where: { $0.id == id }) else { continue }
            store.purge(e)
            n += 1
        }
        return n
    }
}

// MARK: Review changes (import preview)

public enum ReviewChangesText {
    public static let windowTitle = "Review changes before importing"
    public static let explanation = "Review what this import will do, then choose Import to overwrite your current data or Cancel to keep it."
    public static let noDifferences = "No differences detected \u{2014} the incoming data appears identical to your current data."
    public static let cancel = "Cancel"
    public static let importButton = "Import (Overwrite)"
    public static let otherDataToggle = "Show other data (crew, saved lists, schedules, ports, SIRE)"
    public static let otherDataHeader = "Other data"
    public static let otherDataHelp = "Not part of the Windows preview: crew members, saved lists, saved schedules, the ports database and the SIRE session. The import replaces these too."
    public static let otherDataNone = "No differences in other data."

    /// `Importing from: {sourceName}`.
    public static func source(_ name: String) -> String { "Importing from: \(name)" }

    /// 08 QUICK-191 (spaces exactly 3, 5, 5, 3, 2; glyphs U+FF0B, U+FF5E, U+FF0D) or the no-difference line.
    public static func summary(_ d: DiffResult) -> String {
        d.hasChanges
            ? "This import will   \u{FF0B} add \(d.added)     \u{FF5E} change \(d.changed)     \u{FF0D} remove \(d.removed)   item(s).  Expand a row to see details."
            : noDifferences
    }

    /// The same counts for the "Other data" section (Mac addition).
    public static func otherSummary(_ d: DiffResult) -> String {
        d.hasChanges
            ? "Other data:   \u{FF0B} add \(d.added)     \u{FF5E} change \(d.changed)     \u{FF0D} remove \(d.removed)   record(s)."
            : otherDataNone
    }

    /// 08 QUICK-192 glyphs.
    public static func glyph(_ c: DiffNode.Change) -> String {
        switch c {
        case .added: return "\u{FF0B}"
        case .removed: return "\u{FF0D}"
        case .changed: return "\u{FF5E}"
        }
    }
}

// MARK: Quick switcher

public enum SwitcherText {
    public static let windowTitle = "Go to item"
    public static let prompt = "Type a name, kind or #tag..."
    public static let hint = "Enter to open  \u{00B7}  \u{2191} / \u{2193} to move  \u{00B7}  Esc to close"
    public static let noMatches = "No matching items."
    public static let menuHelp = "Fuzzy-jump to any item by name, kind or #tag \u{2014} Obsidian-style. Type, then Enter."

    /// `#a  #b` — each tag prefixed `#`, joined by two spaces (08 QUICK-102).
    public static func tags(_ tags: [String]) -> String { tags.map { "#" + $0 }.joined(separator: "  ") }

    /// 08 §3.3.4 `Move(delta)`: nothing selected → 0; else clamp(selected + delta) — never wraps.
    public static func move(selected: Int?, delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let i = selected.map { $0 + delta } ?? 0
        return min(max(i, 0), count - 1)
    }
}
