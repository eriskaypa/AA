// Spec: 06 BUILD-A1 (selected indices), BUILD-A2 (up / down), BUILD-A3 (move-to), BUILD-A4 (Shorten, both variants),
//       BUILD-A5 (duration parsing), BUILD-004 (bulk lines), BUILD-007/008 (insert position), BUILD-013 (move-to
//       options), BUILD-053 (range hint), BUILD-044 (subtask wording); test vectors 06 §7.3, §7.7.
// Pure algorithms shared by every builder host (procedure, crew, saved-list, subtask). No model access here.
import Foundation

/// One option of the builders' "Move to…" picker (BUILD-013): the display text and the flat target index.
public struct BuilderMoveOption: Sendable, Hashable {
    public var display: String
    public var target: Int
    public init(display: String, target: Int) { self.display = display; self.target = target }
}

/// BUILD-A1…A3: the reorder rules of the checklist and subtask builders (ObservableCollection semantics: a move is
/// "remove at `from`, insert at `to`").
public enum BuilderReorder {
    /// BUILD-A1: indices of the selected ids in `ids`, ascending (ids that are not present are ignored).
    public static func selectedIndicesAscending(_ ids: [UUID], selection: Set<UUID>) -> [Int] {
        ids.indices.filter { selection.contains(ids[$0]) }
    }

    /// BUILD-007: "Insert before" → the first selected index, or 0 with no selection.
    /// BUILD-008: "Insert after" → the last selected index + 1, or the end with no selection. Always clamped.
    public static func insertIndex(before: Bool, picks: [Int], count: Int) -> Int {
        let sorted = picks.sorted()
        let raw: Int
        if before { raw = sorted.first ?? 0 } else { raw = sorted.last.map { $0 + 1 } ?? count }
        return min(max(raw, 0), count)
    }

    /// BUILD-A2 up: nothing moves when there is no pick or the first pick is already at the top (even if other picks
    /// could move). Otherwise every pick moves up one, processed ascending. Returns whether anything moved.
    @discardableResult
    public static func moveUp<T>(_ items: inout [T], picks: [Int]) -> Bool {
        let p = Array(Set(picks)).filter { items.indices.contains($0) }.sorted()
        guard let first = p.first, first > 0 else { return false }
        for i in p { move(&items, from: i, to: i - 1) }
        return true
    }

    /// BUILD-A2 down: the mirror of `moveUp`, processed descending.
    @discardableResult
    public static func moveDown<T>(_ items: inout [T], picks: [Int]) -> Bool {
        let p = Array(Set(picks)).filter { items.indices.contains($0) }.sorted()
        guard let last = p.last, last < items.count - 1 else { return false }
        for i in p.reversed() { move(&items, from: i, to: i + 1) }
        return true
    }

    /// BUILD-A3: the picks move as one block, keeping their relative (list) order, to `target` — the flat index of the
    /// "Before:" item, 0 for the top, `count` for the bottom. Returns the new indices of the moved block (empty when
    /// nothing was picked).
    @discardableResult
    public static func moveTo<T>(_ items: inout [T], picks: [Int], target: Int) -> [Int] {
        let ordered = Array(Set(picks)).filter { items.indices.contains($0) }.sorted()
        guard !ordered.isEmpty else { return [] }
        let shift = ordered.filter { $0 < target }.count
        let adjusted = min(max(target - shift, 0), items.count - ordered.count)
        let moving = ordered.map { items[$0] }
        for i in ordered.reversed() { items.remove(at: i) }
        items.insert(contentsOf: moving, at: adjusted)
        return Array(adjusted..<(adjusted + moving.count))
    }

    /// ObservableCollection.Move: remove at `from`, insert at `to`.
    public static func move<T>(_ items: inout [T], from: Int, to: Int) {
        guard from != to, items.indices.contains(from) else { return }
        let x = items.remove(at: from)
        items.insert(x, at: min(max(to, 0), items.count))
    }

    /// BUILD-013: `(Move to top)` (0), `Before: {Shorten(title, 60)}` for every UNselected item at its flat index,
    /// `(Move to bottom)` (count).
    public static func moveToOptions(titles: [String], selected: Set<Int>) -> [BuilderMoveOption] {
        var out = [BuilderMoveOption(display: "(Move to top)", target: 0)]
        for (i, t) in titles.enumerated() where !selected.contains(i) {
            out.append(BuilderMoveOption(display: "Before: \(BuilderShorten.builder(t, max: 60))", target: i))
        }
        out.append(BuilderMoveOption(display: "(Move to bottom)", target: titles.count))
        return out
    }

    /// A drag-and-drop move (`.onMove`, 06 §6.2 additive): the dragged rows land before the row at `destination`
    /// (SwiftUI's insertion index) — the same BUILD-A3 algorithm, so the result equals the button path.
    @discardableResult
    public static func dropMove<T>(_ items: inout [T], from source: IndexSet, to destination: Int) -> [Int] {
        moveTo(&items, picks: Array(source), target: destination)
    }
}

/// BUILD-A4: the two `Shorten` variants (Character-safe truncation on UTF-16 length; 06 §7.7).
public enum BuilderShorten {
    /// Builders: null/empty → `""`; CR and LF each become a space; trimmed; longer than `max` UTF-16 units → the
    /// first `max − 1` units (never splitting a character) + `…`.
    public static func builder(_ s: String?, max: Int) -> String {
        guard let s, !s.isEmpty else { return "" }
        var t = ""
        t.unicodeScalars.reserveCapacity(s.unicodeScalars.count)
        for sc in s.unicodeScalars { t.unicodeScalars.append(sc == "\r" || sc == "\n" ? " " : sc) }
        return cut(NetText.trim(t), max: max)
    }

    /// Saved Lists: trimmed; empty → `(unnamed)`; then the same truncation (no newline replacement).
    public static func savedLists(_ s: String?, max: Int) -> String {
        let t = NetText.trim(s ?? "")
        if t.isEmpty { return "(unnamed)" }
        return cut(t, max: max)
    }

    static func cut(_ s: String, max: Int) -> String {
        guard s.utf16.count > max else { return s }
        var out = ""
        var units = 0
        for ch in s {
            let n = ch.utf16.count
            if units + n > max - 1 { break }
            out.append(ch)
            units += n
        }
        return out + "…"
    }
}

/// BUILD-A5: `int.TryParse(text)` (NumberStyles.Integer) accepting only values > 0.
public enum BuilderDuration {
    /// Leading/trailing .NET number whitespace (U+0009–U+000D, U+0020) and one leading sign are allowed; ASCII digits
    /// only; Int32 range; result must be > 0. Anything else → nil (the model is left unchanged).
    public static func parse(_ text: String) -> Int? {
        let ws: Set<UInt16> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20]
        var u = Array(NetText.trim(text, characters: ws).utf16)
        guard !u.isEmpty else { return nil }
        var negative = false
        if u[0] == 0x2B || u[0] == 0x2D { negative = u[0] == 0x2D; u.removeFirst() }
        guard !u.isEmpty, u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        var value: Int64 = 0
        for d in u {
            value = value * 10 + Int64(d - 0x30)
            if value > Int64(Int32.max) + 1 { return nil }
        }
        if negative { value = -value }
        guard value >= Int64(Int32.min), value <= Int64(Int32.max), value > 0 else { return nil }
        return Int(value)
    }
}

/// BUILD-004: the bulk box's lines — `\r\n` → `\n`, split on `\n`, each trimmed, empty lines dropped.
public enum BuilderBulk {
    public static func lines(_ text: String) -> [String] {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalised.components(separatedBy: "\n").map(NetText.trim).filter { !$0.isEmpty }
    }
}

/// BUILD-053: the working-range hint of the task editor.
public enum BuilderRange {
    /// `"range · {n} days"` where n = whole days `Deadline − RangeStart` + 1, only when the start's date is before the
    /// deadline's date (`HasRange`); otherwise `""` (a start equal to the deadline shows no hint).
    public static func hint(start: NetDateTime?, deadline: NetDateTime?) -> String {
        guard let s = start, let d = deadline, s.civilDate < d.civilDate else { return "" }
        return "range · \(s.civilDate.days(to: d.civilDate) + 1) days"
    }
}

/// Exact Windows wording that depends on counts (06 BUILD-013/014/044, VIEW-212 rows 19/20).
public enum BuilderWording {
    /// `"Move {n} item to..."` / `"Move {n} items to..."` (noun `item`, `subtask`, `list`).
    public static func moveTitle(_ n: Int, noun: String) -> String {
        "Move \(n) \(noun)\(n == 1 ? "" : "s") to..."
    }

    /// `"Delete {n} item?"` / `"Delete {n} items?"` (noun `item` or `subtask`).
    public static func deleteQuestion(_ n: Int, noun: String) -> String {
        "Delete \(n) \(noun)\(n == 1 ? "" : "s")?"
    }

    /// `ChecklistTemplate.Display` used by every saved-list picker: `"{name or (unnamed)}  ·  {n} item|items"`.
    @MainActor public static func templateDisplay(_ t: ChecklistTemplate) -> String { t.display }

    /// The Replace/Append question of BUILD-016 / BUILD-044 (Windows text kept verbatim).
    public static func insertQuestion(name: String, count: Int, subtasks: Bool) -> String {
        "Insert '\(name)' (\(count) item(s)).\n\nYes = replace the current \(subtasks ? "subtasks" : "items")\n"
            + "No = append to the end\nCancel = do nothing"
    }

    /// BUILD-015 / BUILD-044 success text.
    public static func savedListMessage(name: String, count: Int) -> String {
        "Saved '\(name)' (\(count) item(s)). You can reuse it from any checklist builder."
    }

    /// BUILD-017 manage question.
    public static func manageListQuestion(name: String, count: Int) -> String {
        "'\(name)' (\(count) item(s)).\n\nYes = rename\nNo = delete\nCancel = nothing"
    }

    /// BUILD-017 / BUILD-082 delete confirmation.
    public static func deleteListQuestion(name: String) -> String {
        "Delete saved list '\(name)'? This does not affect any checklist already built from it."
    }
}
