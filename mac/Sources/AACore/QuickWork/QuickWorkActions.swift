// Spec: 08 §2.2 (QUICK-051…055, QUICK-062 tile Done, QUICK-064 pins, QUICK-073 delete, QUICK-074 header fields,
//       QUICK-075…081 children builder, saved lists), §3.2 (`Move<T>`, `SetItemDone`, saved-list helpers — exact),
//       §3.8 (WorkRange / BatchDone / BatchDeadline semantics), §4.5 (log lines produced here), §7.2 (T-QW-7…13),
//       QUICK-231 (bucket picker flow, cap in selection order); 07 VIEW-153, VIEW-213 (selection order), VIEW-215;
//       06 BUILD-102 (same capture/apply services and strings as the builders); 02 REPO-081 + DECISIONS 02 Q-4
//       (the Ctrl+N delete goes through the Trash on the Mac).
// Every function mutates the live store on the main actor and never saves: the view saves exactly where Windows
// calls `Save()` (and reports a failed save, 08 QUICK-214).
import Foundation

public enum QuickWorkText {
    public static let windowTitle = "Quick work \u{2014} all tasks & procedures"
    public static let listHeader = "All tasks & procedures"
    public static let newTask = "+ Task"
    public static let newProcedure = "+ Procedure"
    public static let sortIntoBuckets = "Sort into Buckets\u{2026}"
    public static let sortIntoBucketsHelp = "Put the selected task/procedure into up to two predefined buckets. Define buckets in the Buckets tab."
    public static let removeFromBuckets = "Remove from Buckets"
    public static let removeFromBucketsHelp = "Take the selected task/procedure out of all buckets."
    public static let searchPrompt = "Search tasks & procedures..."
    public static let markDone = "Mark Selected as Done"
    public static let markNotDone = "Mark Selected as Not Done"
    public static let setDeadline = "Set Deadline for Selected\u{2026}"
    public static let setDeadlineHelp = "Give every selected item the same deadline (or clear it)."
    public static let pinnedHeader = "Pinned"
    public static let pinnedHint = "Select a task or procedure below and click \u{201C}\u{1F4CC} Pin\u{201D} to keep it here as a square. Marking a square done (or editing it) applies everywhere."
    public static let tileHelp = "Click to edit. Tick \u{201C}Done\u{201D} to mark it complete everywhere."
    public static let unpinHelp = "Unpin (remove this square). The task/procedure itself is kept."
    public static let detailEmpty = "Select a task or procedure on the left (or create one) to build it out here."
    public static let pin = "Pin"
    public static let unpin = "Unpin"
    public static let pinHelp = "Pin this as a square in the board above."
    public static let unpinDetailHelp = "Remove this from the pinned squares above."
    public static let delete = "Delete\u{2026}"
    public static let openInMain = "Open in Main Window"
    public static let deadlineHelp = "Due date \u{2014} for a task this is also the LAST day of the working range."
    public static let rangeStartHelp = "Optional first day of the working range. Leave empty for a single-day task; the deadline stays the last day."
    public static let replaceExisting = "Replace existing"
    public static let addAll = "Add all"
    public static let edit = "Edit\u{2026}"
    public static let deleteChildren = "Delete"
    public static let buckets = "Buckets\u{2026}"
    public static let openFullBuilder = "Open Full Builder\u{2026}"
    public static let saveAsList = "Save as List\u{2026}"
    public static let loadSavedList = "Load a Saved List\u{2026}"

    // Messages (08 QUICK-052…081, QUICK-231 — Windows text verbatim).
    public static let setDeadlineTitle = "Set deadline"
    public static let setDeadlineNoSelection = "Select one or more items first, then set the deadline."
    public static let bucketsTitle = "Sort into buckets"
    public static let bucketsNoSelection = "Select a task or procedure first, then sort it into buckets."
    public static let noBuckets = "No buckets are defined yet. Open the Buckets tab to create some (e.g. a location or a rank)."
    public static let bucketCap = "An item can be in at most two buckets \u{2014} keeping the first two you picked."
    public static let newTaskTitle = "New Task"
    public static let newProcedureTitle = "New Procedure"
    public static let namePrompt = "Name:"
    public static let deleteTitle = "Delete"
    public static let confirmTitle = "Confirm"
    public static let saveListTitle = "Save list"
    public static let saveListEmpty = "Add some items first, then save the list."
    public static let saveAsListTitle = "Save as reusable list"
    public static let saveAsListPrompt = "Name for this saved list:"
    public static let savedListTitle = "Saved list"
    public static let loadListTitle = "Load a saved list"
    public static let noSavedLists = "No saved lists yet. Build a list and click 'Save as list...' to create one."
    public static let insertListTitle = "Insert a saved list"

    /// `Apply one deadline to {n} selected item{s}:`
    public static func setDeadlinePrompt(_ n: Int) -> String { "Apply one deadline to \(n) selected item\(n == 1 ? "" : "s"):" }

    /// DECISIONS 02 Q-4 / 08 OQ-1: the Windows text, extended to say where the item goes.
    public static func deleteMessage(_ name: String) -> String {
        "Delete '\(name)' and everything under it? This removes it everywhere \u{2014} it goes to the Trash (put it back from File \u{25B8} Trash\u{2026}, or undo with \u{2318}Z)."
    }

    /// `Delete {n} subtask(s)?` / `Delete {n} step(s)?`
    public static func deleteChildrenMessage(_ n: Int, noun: String) -> String { "Delete \(n) \(noun)(s)?" }

    /// `Sort '{label}' into buckets (pick up to 2)`
    public static func bucketPrompt(_ label: String) -> String { "Sort '\(label)' into buckets (pick up to 2)" }

    /// `Select a {noun} first, then sort it into buckets.`
    public static func childBucketsNoSelection(noun: String) -> String { "Select a \(noun) first, then sort it into buckets." }

    /// `Saved '{name}' ({n} item(s)). You can reuse it from any checklist builder.`
    public static func savedList(_ name: String, _ n: Int) -> String {
        "Saved '\(name)' (\(n) item(s)). You can reuse it from any checklist builder."
    }

    /// The Yes/No/Cancel question with the Mac verb buttons (Replace / Append / Cancel) named in the body.
    public static func insertListMessage(_ name: String, _ n: Int) -> String {
        "Insert '\(name)' (\(n) item(s)).\n\nReplace = replace the current items\nAppend = append to the end\nCancel = do nothing"
    }

    public static func builderHeading(noun: String) -> String { "Comprehensive \(noun) builder" }
    public static func bulkLabel(noun: String) -> String { "Bulk add \u{2014} one \(noun) per line:" }
    public static func newChildTitle(noun: String) -> String { "New \(noun)" }
    public static func addChild(noun: String) -> String { "+ \(noun)" }
}

/// Which children a quick-work item has (subtasks of a task, steps of a procedure).
public enum QuickWorkChildKind: Sendable, Hashable {
    case subtask, step

    public var noun: String { self == .subtask ? "subtask" : "step" }
    /// `Cap(noun)` — the Kind of the builder's log lines (08 §4.5).
    public var logKind: String { self == .subtask ? "Subtask" : "Step" }
    /// The Kind logged by "Load a saved list" (08 QUICK-081).
    public var templateLogKind: String { self == .subtask ? "Subtask" : "Checklist step" }
}

/// One child row of the builder list.
public struct QuickWorkChild: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID, title: String, isDone: Bool) { self.id = id; self.title = title; self.isDone = isDone }
}

@MainActor public enum QuickWorkActions {
    // MARK: Create (QUICK-055)

    /// The RAW entered name (not trimmed) appended to `Data.Tasks`, logged `Added / Task / name`. Blank → nil.
    public static func createTask(named name: String, store: AppStore) -> TaskItem? {
        guard !NetText.isBlank(name) else { return nil }
        return store.createTopLevelTask(named: name, logKind: "Task")
    }

    /// As `createTask` for `Data.Procedures` (`Added / Procedure / name`).
    public static func createProcedure(named name: String, store: AppStore) -> Procedure? {
        guard !NetText.isBlank(name) else { return nil }
        return store.createTopLevelProcedure(named: name)
    }

    // MARK: Pins (QUICK-061, QUICK-064)

    public static func isPinned(_ id: UUID, store: AppStore) -> Bool { store.data.ui.quickViewPinIds.contains(id) }

    /// Removes the id if present, else appends it; marks dirty. Returns whether it is pinned now.
    @discardableResult
    public static func togglePin(_ id: UUID, store: AppStore) -> Bool {
        let ui = store.data.ui
        let pinned: Bool
        if let k = ui.quickViewPinIds.firstIndex(of: id) { ui.quickViewPinIds.remove(at: k); pinned = false }
        else { ui.quickViewPinIds.append(id); pinned = true }
        store.markDirty()
        return pinned
    }

    // MARK: Done (QUICK-062 tile, QUICK-051 batch)

    /// Tile "Done": task `IsComplete = done` (Status follows), procedure `Status = done ? Done : Todo`; marks dirty.
    public static func setItemDone(_ item: HierarchyItem, done: Bool, store: AppStore) {
        if let t = item as? TaskItem { t.isComplete = done }
        else if let p = item as? Procedure { p.status = done ? .done : .todo }
        store.markDirty()
    }

    // MARK: Delete (QUICK-073 via the Trash, DECISIONS 02 Q-4)

    /// Unpins the item and moves it (whole subtree) to the Trash — undoable with ⌘Z, references kept for a lossless
    /// Put Back. Returns the Trash entry (nil when the item is no longer top level).
    @discardableResult
    public static func moveToTrash(_ item: HierarchyItem, store: AppStore) -> TrashedItem? {
        let ui = store.data.ui
        ui.quickViewPinIds.removeAll { $0 == item.id }
        return store.trash(item)
    }

    // MARK: Header fields (QUICK-074) — both pickers coerce against the MODEL

    /// Deadline picker: a procedure sets `Deadline`; a task runs `WorkRange.coerce(model.RangeStart, picked,
    /// editedStart: false)` and writes both. Marks dirty.
    public static func setDeadline(_ item: HierarchyItem, picked: NetDateTime?, store: AppStore) {
        if let t = item as? TaskItem {
            let (s, d) = WorkRange.coerce(start: t.rangeStart, deadline: picked, editedStart: false)
            t.rangeStart = s
            t.deadline = d
        } else if let p = item as? Procedure {
            p.deadline = picked.map(\.asCalendarDate)
        }
        store.markDirty()
    }

    /// Range-start picker (tasks only): `WorkRange.coerce(picked, model.Deadline, editedStart: true)`. Marks dirty.
    public static func setRangeStart(_ t: TaskItem, picked: NetDateTime?, store: AppStore) {
        let (s, d) = WorkRange.coerce(start: picked, deadline: t.deadline, editedStart: true)
        t.rangeStart = s
        t.deadline = d
        store.markDirty()
    }

    /// Status combo (task: `IsComplete` follows). Marks dirty.
    public static func setStatus(_ item: HierarchyItem, _ s: WorkStatus, store: AppStore) {
        if let t = item as? TaskItem { t.status = s } else if let p = item as? Procedure { p.status = s }
        store.markDirty()
    }

    /// Recurrence combo. Marks dirty.
    public static func setRecurrence(_ item: HierarchyItem, _ r: RecurrenceKind, store: AppStore) {
        if let t = item as? TaskItem { t.recurrence = r } else if let p = item as? Procedure { p.recurrence = r }
        store.markDirty()
    }

    /// Name box: every keystroke writes `Name` and marks dirty.
    public static func setName(_ item: HierarchyItem, _ name: String, store: AppStore) {
        guard item.name != name else { return }
        item.name = name
        store.markDirty()
    }

    // MARK: Children (QUICK-075…079)

    public static func childKind(of item: HierarchyItem) -> QuickWorkChildKind? {
        if item is TaskItem { return .subtask }
        if item is Procedure { return .step }
        return nil
    }

    public static func children(of item: HierarchyItem) -> [QuickWorkChild] {
        if let t = item as? TaskItem { return t.subtasks.map { QuickWorkChild(id: $0.id, title: $0.name, isDone: $0.isComplete) } }
        if let p = item as? Procedure { return p.steps.map { QuickWorkChild(id: $0.id, title: $0.title, isDone: $0.done) } }
        return []
    }

    /// The live child model (TaskItem / ChecklistStep) with that id, for editors and batch menus.
    public static func childModel(_ id: UUID, of item: HierarchyItem) -> AnyObject? {
        if let t = item as? TaskItem { return t.subtasks.first { $0.id == id } }
        if let p = item as? Procedure { return p.steps.first { $0.id == id } }
        return nil
    }

    /// 08 QUICK-075: `\r\n` → `\n`, split on `\n`, trim each line, drop empty lines.
    public nonisolated static func bulkLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { NetText.trim(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// 08 QUICK-075 `Add all`: nothing when no line survives; `replace` clears the collection first (no
    /// confirmation); appends one child per line; logs `Added / Subtask|Step / "{n} added (bulk)" / owner`. Returns n.
    @discardableResult
    public static func bulkAdd(_ text: String, replace: Bool, to item: HierarchyItem, store: AppStore) -> Int {
        let lines = bulkLines(text)
        guard !lines.isEmpty, let kind = childKind(of: item) else { return 0 }
        if let t = item as? TaskItem {
            if replace { t.subtasks.removeAll() }
            t.subtasks.append(contentsOf: lines.map { TaskItem(name: $0) })
        } else if let p = item as? Procedure {
            if replace { p.steps.removeAll() }
            p.steps.append(contentsOf: lines.map { ChecklistStep(title: $0) })
        }
        store.logAdded(kind: kind.logKind, name: "\(lines.count) added (bulk)", detail: item.name)
        return lines.count
    }

    /// 08 QUICK-077 `+ subtask` / `+ step`: blank → nil; appends the raw name; logs `Added / Subtask|Step / name /
    /// owner`. Returns the new child's id.
    @discardableResult
    public static func addChild(named name: String, to item: HierarchyItem, store: AppStore) -> UUID? {
        guard !NetText.isBlank(name), let kind = childKind(of: item) else { return nil }
        let id: UUID
        if let t = item as? TaskItem {
            let c = TaskItem(name: name); t.subtasks.append(c); id = c.id
        } else if let p = item as? Procedure {
            let c = ChecklistStep(title: name); p.steps.append(c); id = c.id
        } else {
            return nil
        }
        store.logAdded(kind: kind.logKind, name: name, detail: item.name)
        return id
    }

    /// 08 QUICK-077 `Delete`: removes the selected children (hard); logs `Removed / Subtask|Step / "{n} removed" /
    /// owner`. Returns n (0 → nothing logged).
    @discardableResult
    public static func deleteChildren(_ ids: Set<UUID>, from item: HierarchyItem, store: AppStore) -> Int {
        guard let kind = childKind(of: item) else { return 0 }
        let n: Int
        if let t = item as? TaskItem {
            n = t.subtasks.filter { ids.contains($0.id) }.count
            guard n > 0 else { return 0 }
            store.logRemoved(kind: kind.logKind, name: "\(n) removed", detail: item.name)
            t.subtasks.removeAll { ids.contains($0.id) }
        } else if let p = item as? Procedure {
            n = p.steps.filter { ids.contains($0.id) }.count
            guard n > 0 else { return 0 }
            store.logRemoved(kind: kind.logKind, name: "\(n) removed", detail: item.name)
            p.steps.removeAll { ids.contains($0.id) }
        } else {
            return 0
        }
        return n
    }

    /// 08 QUICK-078 `Move<T>`: selected indices ascending; up → nothing when the first is 0, else each i → i−1 in
    /// ascending order; down → nothing when the last is the last position, else each i → i+1 in descending order.
    /// Gaps are preserved. Returns the new order (nil = unchanged).
    public nonisolated static func moved<T>(_ items: [T], selected: Set<Int>, up: Bool) -> [T]? {
        let picks = selected.filter { $0 >= 0 && $0 < items.count }.sorted()
        guard let first = picks.first, let last = picks.last else { return nil }
        var a = items
        if up {
            if first == 0 { return nil }
            for i in picks { a.swapAt(i, i - 1) }
        } else {
            if last == items.count - 1 { return nil }
            for i in picks.reversed() { a.swapAt(i, i + 1) }
        }
        return a
    }

    /// Moves the children with these ids one position (MarkDirty only). Returns whether anything moved.
    @discardableResult
    public static func moveChildren(_ ids: Set<UUID>, in item: HierarchyItem, up: Bool, store: AppStore) -> Bool {
        if let t = item as? TaskItem {
            let sel = Set(t.subtasks.indices.filter { ids.contains(t.subtasks[$0].id) })
            guard let m = moved(t.subtasks, selected: sel, up: up) else { return false }
            t.subtasks = m
        } else if let p = item as? Procedure {
            let sel = Set(p.steps.indices.filter { ids.contains(p.steps[$0].id) })
            guard let m = moved(p.steps, selected: sel, up: up) else { return false }
            p.steps = m
        } else {
            return false
        }
        store.markDirty()
        return true
    }

    /// Drag reorder (`.onMove`, Mac addition with the same effect as repeated ↑/↓). MarkDirty only.
    public static func moveChildren(fromOffsets: IndexSet, toOffset: Int, in item: HierarchyItem, store: AppStore) {
        func apply<T>(_ a: inout [T]) {
            let moving = fromOffsets.sorted().filter { $0 < a.count }.map { a[$0] }
            var rest: [T] = []
            var insertAt = toOffset
            for (k, x) in a.enumerated() {
                if fromOffsets.contains(k) { if k < toOffset { insertAt -= 1 } } else { rest.append(x) }
            }
            insertAt = min(max(insertAt, 0), rest.count)
            rest.insert(contentsOf: moving, at: insertAt)
            a = rest
        }
        if let t = item as? TaskItem { apply(&t.subtasks) } else if let p = item as? Procedure { apply(&p.steps) }
        store.markDirty()
    }

    // MARK: Saved lists (QUICK-080, QUICK-081; BUILD-102)

    /// Captures the direct children (Title, DurationMinutes, IsJob, deep-cloned Container), appends the template to
    /// `Data.ChecklistTemplates` (collection order = the user's arrangement) and logs `Added / Saved list / name /
    /// "{n} item(s)"`. The name is trimmed by the caller's prompt rule. The caller saves.
    @discardableResult
    public static func saveAsList(named name: String, from item: HierarchyItem, store: AppStore) -> ChecklistTemplate? {
        let tpl: ChecklistTemplate
        if let t = item as? TaskItem { tpl = ChecklistTemplateService.captureFromSubtasks(name: name, subtasks: t.subtasks) }
        else if let p = item as? Procedure { tpl = ChecklistTemplateService.captureFromSteps(name: name, steps: p.steps) }
        else { return nil }
        store.data.checklistTemplates.append(tpl)
        store.logAdded(kind: "Saved list", name: tpl.name, detail: "\(tpl.items.count) item(s)")
        return tpl
    }

    /// Replace (clear then add) or append fresh children from the template; logs `Added / Subtask|Checklist step /
    /// "{n} added (from saved list '{name}')" / owner`; marks dirty (not Save). Returns n.
    @discardableResult
    public static func insertList(_ tpl: ChecklistTemplate, into item: HierarchyItem, replace: Bool, store: AppStore) -> Int {
        guard let kind = childKind(of: item) else { return 0 }
        let n: Int
        if let t = item as? TaskItem {
            var subs = t.subtasks
            n = ChecklistTemplateService.applyToSubtasks(tpl, subtasks: &subs, replace: replace)
            t.subtasks = subs
        } else if let p = item as? Procedure {
            var steps = p.steps
            n = ChecklistTemplateService.applyToSteps(tpl, steps: &steps, replace: replace)
            p.steps = steps
        } else {
            return 0
        }
        store.logAdded(kind: kind.templateLogKind, name: "\(n) added (from saved list '\(tpl.name)')", detail: item.name)
        store.markDirty()
        return n
    }

    // MARK: Buckets (QUICK-053, QUICK-054, QUICK-231)

    /// Picker rows: every bucket in collection order, displayed `{Name}  ·  {Category}` / `{Name}` / `(unnamed)`.
    public static func bucketChoices(store: AppStore) -> [(display: String, id: UUID)] {
        store.data.quickBuckets.map { ($0.display, $0.id) }
    }

    /// Pre-selected: the buckets the target is already in, in `QuickBuckets` order.
    public static func preselectedBuckets(for target: Bucketable, store: AppStore) -> [UUID] {
        let current = Set(target.bucketIds)
        return store.data.quickBuckets.filter { current.contains($0.id) }.map(\.id)
    }

    /// OK in the picker: keeps the first two in selection order (`capped` → the info message), replaces `BucketIds`
    /// (0 picked = out of every bucket; stale ids dropped). The caller saves.
    @discardableResult
    public static func applyBuckets(_ picked: [UUID], to target: Bucketable) -> (ids: [UUID], capped: Bool) {
        var ordered: [UUID] = []
        for id in picked where !ordered.contains(id) { ordered.append(id) }
        let capped = ordered.count > 2
        let kept = Array(ordered.prefix(2))
        target.bucketIds = kept
        return (kept, capped)
    }

    /// QUICK-054: clears `BucketIds` (the caller saves).
    public static func removeFromBuckets(_ target: Bucketable) {
        target.bucketIds.removeAll()
    }
}
