// Spec: 07 §3.2 VIEW-040…056 (Task Board: columns, every task and nested subtask as a card, card anatomy, search,
//       hide done, counts, drag to change status, open all files, delete, new task), §4.2.1–4.2.6, §2.2, DECISIONS 02
//       Q-4 / 07 Q-01 (deletes go through the Trash — `trash` / `trashSubtask`), 07 Q-03 (log Board-created tasks),
//       W-01 (the store is resolved at action time, never captured).
import Foundation

/// One Board column (VIEW-041).
public struct BoardColumnSpec: Sendable, Hashable, Identifiable {
    public let status: WorkStatus
    public let title: String
    /// `#RRGGBB`, identical in light and dark.
    public let colorHex: String
    public var id: Int { status.rawValue }
}

/// A card (VIEW-043): a task or nested subtask with the ancestor path computed at flatten time.
@MainActor
public struct BoardCard: @MainActor Identifiable {
    public let task: TaskItem
    /// Ancestor names from the top-level task down, joined by `" › "`; empty for a top-level task.
    public let path: String
    public var id: UUID { task.id }

    public init(task: TaskItem, path: String) { self.task = task; self.path = path }

    public var isSubtask: Bool { !path.isEmpty }

    /// `"↳ {path}"` for subtasks; nil for top-level tasks.
    public var parentLine: String? { path.isEmpty ? nil : "\u{21B3} " + path }
}

@MainActor
public enum BoardModel {
    public static let title = "Task Board"
    public static let hint = "Drag cards between columns to set status"
    public static let findLabel = "Find:"
    public static let hideDoneLabel = "Hide done"
    public static let fromSavedListTitle = "+ From saved list"
    public static let fromSavedListHelp = "Search your saved lists and add items as real tasks"
    public static let newTaskTitle = "+ New task"
    public static let parentHelp = "This card is a subtask; its parent path is shown here."
    public static let openEditTitle = "Open / edit task"
    public static let openAllFilesTitle = "Open all files (routine)"
    public static let deleteTitle = "Delete task"
    /// The ⌘⌫ menu title for a focused column (T-KB-06).
    public static let deleteMenuTitle = "Delete Task"
    public static let noFilesTitle = "Open all files"
    public static let noFilesMessage = "This task has no files yet. Open the task and add some to the file bank."
    public static let confirmTitle = "Confirm"
    public static let newTaskPromptTitle = "New Task"
    public static let newTaskPromptLabel = "Name:"

    /// VIEW-041: To Do #546E7A, In Progress #1E88E5, Blocked #E53935, Done #2E7D32.
    public static let columns: [BoardColumnSpec] = [
        BoardColumnSpec(status: .todo, title: "To Do", colorHex: "#546E7A"),
        BoardColumnSpec(status: .inProgress, title: "In Progress", colorHex: "#1E88E5"),
        BoardColumnSpec(status: .blocked, title: "Blocked", colorHex: "#E53935"),
        BoardColumnSpec(status: .done, title: "Done", colorHex: "#2E7D32"),
    ]

    // MARK: Cards (§4.2.2)

    /// Every task in `Data.Tasks` and all descendants, pre-order; a visited-id set guards cycles and suppresses a
    /// second item with a duplicate id (B12). A blank ancestor name reads `"(unnamed)"` in the path.
    public static func flatten(_ data: AppData) -> [BoardCard] {
        var out: [BoardCard] = []
        var seen = Set<UUID>()
        func walk(_ t: TaskItem, _ path: String) {
            guard seen.insert(t.id).inserted else { return }
            out.append(BoardCard(task: t, path: path))
            let seg = NetText.isBlank(t.name) ? "(unnamed)" : t.name
            let child = path.isEmpty ? seg : path + " \u{203A} " + seg
            for s in t.subtasks { walk(s, child) }
        }
        for t in data.tasks { walk(t, "") }
        return out
    }

    /// VIEW-044 / 045: trimmed query, `Name` contains (OrdinalIgnoreCase); hide-done drops `Status == Done`.
    public static func filter(_ cards: [BoardCard], query: String, hideDone: Bool) -> [BoardCard] {
        let q = NetText.trim(query)
        return cards.filter { c in
            if !q.isEmpty && !NetText.containsIgnoreCase(c.task.name, q) { return false }
            if hideDone && c.task.status == .done { return false }
            return true
        }
    }

    /// The cards of one column, in flatten order (no sorting).
    public static func cards(_ cards: [BoardCard], in status: WorkStatus) -> [BoardCard] {
        cards.filter { $0.task.status == status }
    }

    // MARK: Card text (VIEW-043)

    /// Overdue = `Deadline.Date < Today && Status != Done` (keyed on the range end).
    public static func isOverdue(_ t: TaskItem, today: CivilDate) -> Bool {
        guard let d = t.deadline else { return false }
        return d.civilDate < today && t.status != .done
    }

    /// The card's meta line in parts (the Mac card draws OVERDUE as a chip after the dates so it never wraps onto a
    /// line of its own; `meta` keeps the exact Windows string for accessibility and help).
    public struct MetaParts: Equatable, Sendable {
        /// `"{start} → {end}"` when ranged, else `"Due {deadline}"`; nil without a deadline.
        public var dates: String?
        /// The dates are overdue (`"  ·  OVERDUE"` in the string form).
        public var overdue: Bool
        /// The recurrence label when not None.
        public var recurrence: String?
    }

    public static func metaParts(_ t: TaskItem, today: CivilDate) -> MetaParts {
        var parts = MetaParts(dates: nil, overdue: false, recurrence: nil)
        if let d = t.deadline {
            if let rs = t.rangeStart, rs.civilDate < d.civilDate {
                parts.dates = rs.format(.isoDate) + " \u{2192} " + d.format(.isoDate)
            } else {
                parts.dates = "Due " + d.format(.isoDate)
            }
            parts.overdue = isOverdue(t, today: today)
        }
        if t.recurrence != .none { parts.recurrence = t.recurrence.friendlyLabel }
        return parts
    }

    /// Parts joined by `"   ·   "`: the dates (`"{start} → {end}"` when ranged, else `"Due {deadline}"`, plus
    /// `"  ·  OVERDUE"`) and the recurrence name when not None.
    public static func meta(_ t: TaskItem, today: CivilDate) -> String {
        let m = metaParts(t, today: today)
        var parts: [String] = []
        if let dates = m.dates { parts.append(m.overdue ? dates + "  \u{00B7}  " + overdueWord : dates) }
        if let r = m.recurrence { parts.append(r) }
        return parts.joined(separator: "   \u{00B7}   ")
    }

    /// The overdue marker word (VIEW-043).
    public static let overdueWord = "OVERDUE"

    /// `"📎 {n} file(s)"` for the task's own files and `"☑ {done}/{total}"` over direct subtasks, joined by 4 spaces.
    public static func badges(_ t: TaskItem) -> String {
        var parts: [String] = []
        let n = t.container.files.count
        if n > 0 { parts.append("\u{1F4CE} \(n) " + (n == 1 ? "file" : "files")) }
        let total = t.subtasks.count
        if total > 0 { parts.append("\u{2611} \(t.subtasks.filter(\.isComplete).count)/\(total)") }
        return parts.joined(separator: "    ")
    }

    // MARK: Actions

    /// VIEW-047: dropping a card on a column of another status sets it (IsComplete follows); same status → false.
    @discardableResult
    public static func setStatus(_ t: TaskItem, _ status: WorkStatus) -> Bool {
        guard t.status != status else { return false }
        t.status = status
        return true
    }

    /// All descendants, recursively (VIEW-052 count).
    public static func countDescendants(_ t: TaskItem) -> Int { t.allSubtasksDepthFirst().count }

    /// `"Delete task '{name}'?"` + `"\n\nThis also deletes its {n} subtask(s)."` when it has descendants.
    public static func deleteMessage(_ t: TaskItem) -> String {
        let n = countDescendants(t)
        return "Delete task '\(t.name)'?" + (n > 0 ? "\n\nThis also deletes its \(n) subtask(s)." : "")
    }

    /// DECISIONS 02 Q-4: a top-level task goes through `trash(_:)`, a nested card through `trashSubtask(_:)`
    /// (references to it and its descendants purged; undoable with ⌘Z). Returns whether anything moved.
    @discardableResult
    public static func moveToTrash(_ t: TaskItem, store: AppStore) -> Bool {
        if store.data.tasks.contains(where: { $0 === t }) { return store.trash(t) != nil }
        return store.trashSubtask(t) != nil
    }

    /// VIEW-053: a non-blank name creates a top-level To Do task with the text as typed (not trimmed), logged
    /// `Added / Task / name` (DECISIONS 07 Q-03). Blank → nil.
    @discardableResult
    public static func createTask(named raw: String, store: AppStore) -> TaskItem? {
        guard !NetText.isBlank(raw) else { return nil }
        let t = store.createTopLevelTask(named: raw, logKind: "Task")
        t.status = .todo
        return t
    }

    /// VIEW-051 confirmation threshold: more than 15 files asks first.
    public static func openAllNeedsConfirmation(fileCount: Int) -> Bool { fileCount > 15 }

    public static func openAllConfirmation(count: Int, name: String) -> String { "Open all \(count) files for '\(name)'?" }
}
