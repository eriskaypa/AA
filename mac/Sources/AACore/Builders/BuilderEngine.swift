// Spec: 06 §A (BUILD-001, 004, 006…009, 011…016), §D (BUILD-041…045), BUILD-135 (activity-log entries), BUILD-A1…A3;
//       02 REPO-142 (apply), REPO-147 (save as list); 06 §6.1 (one generic builder over steps or subtasks) and R1
//       (builders hold the owner's id and re-resolve through the store — the `read` closure does that).
// The model operations behind every builder host. The UI asks for confirmation / names (prompts) and then calls one
// of these; each mutation logs exactly as 06 BUILD-135 says and marks the store dirty (the hosts' persistence rules —
// MarkDirty, Flush, Save — are applied by the caller where the spec says Save/Flush).
import Foundation

/// What distinguishes a checklist-step builder from a subtask builder (06 §6.1 `BuilderItem`).
@MainActor public struct BuilderItemKind<Item: AnyObject> {
    /// Singular noun used in counted texts: `item` (checklist builders) or `subtask`.
    public var noun: String
    /// New item with the given title/name (as typed, untrimmed — BUILD-006).
    public var make: (String) -> Item
    public var title: (Item) -> String
    public var id: (Item) -> UUID
    /// `CaptureFromSteps` / `CaptureFromSubtasks` (REPO-140/141).
    public var capture: (String, [Item]) -> ChecklistTemplate
    /// `ApplyToSteps` / `ApplyToSubtasks` (REPO-142).
    public var apply: (ChecklistTemplate, inout [Item], Bool) -> Int

    public init(noun: String, make: @escaping (String) -> Item, title: @escaping (Item) -> String,
                id: @escaping (Item) -> UUID, capture: @escaping (String, [Item]) -> ChecklistTemplate,
                apply: @escaping (ChecklistTemplate, inout [Item], Bool) -> Int) {
        self.noun = noun; self.make = make; self.title = title; self.id = id; self.capture = capture; self.apply = apply
    }
}

public extension BuilderItemKind where Item == ChecklistStep {
    /// Checklist steps (procedure, crew checklist and saved-list hosts): `new ChecklistStep { Title = line }`.
    static var steps: BuilderItemKind<ChecklistStep> {
        BuilderItemKind(noun: "item", make: { ChecklistStep(title: $0) }, title: { $0.title }, id: { $0.id },
                        capture: { ChecklistTemplateService.captureFromSteps(name: $0, steps: $1) },
                        apply: { ChecklistTemplateService.applyToSteps($0, steps: &$1, replace: $2) })
    }
}

public extension BuilderItemKind where Item == TaskItem {
    /// Direct subtasks of a task: `new TaskItem { Name = line }` (Todo, 60 min, no recurrence).
    static var subtasks: BuilderItemKind<TaskItem> {
        BuilderItemKind(noun: "subtask", make: { TaskItem(name: $0) }, title: { $0.name }, id: { $0.id },
                        capture: { ChecklistTemplateService.captureFromSubtasks(name: $0, subtasks: $1) },
                        apply: { ChecklistTemplateService.applyToSubtasks($0, subtasks: &$1, replace: $2) })
    }
}

/// The operations of one builder bound to one live collection (06 BUILD-001 `Bind`).
@MainActor public final class BuilderEngine<Item: AnyObject> {
    public let store: AppStore
    public let kind: BuilderItemKind<Item>
    /// Activity-log kind (`"Checklist step"`, `"Crew checklist item"`, `"Saved-list item"`, `"Subtask"`).
    public let logKind: String
    private let read: () -> [Item]?
    private let write: ([Item]) -> Void
    private let owner: () -> String

    /// `read` re-resolves the owner's collection on every call (nil = the owner vanished, e.g. after a reload);
    /// `write` stores the new order/contents back into the same owner; `owner` is the live owner name
    /// (log detail and the "Save as list" default name).
    public init(store: AppStore, kind: BuilderItemKind<Item>, logKind: String, owner: @escaping () -> String,
                read: @escaping () -> [Item]?, write: @escaping ([Item]) -> Void) {
        self.store = store; self.kind = kind; self.logKind = logKind; self.owner = owner; self.read = read
        self.write = write
    }

    /// Whether the builder is bound to a live collection (06 BUILD-001: every action silently no-ops otherwise).
    public var isBound: Bool { read() != nil }
    public var items: [Item] { read() ?? [] }
    public var ownerName: String { owner() }
    public var ids: [UUID] { items.map(kind.id) }

    public func item(id: UUID) -> Item? { items.first { kind.id($0) == id } }

    /// BUILD-A1: selected indices ascending.
    public func selectedIndices(_ selection: Set<UUID>) -> [Int] {
        BuilderReorder.selectedIndicesAscending(ids, selection: selection)
    }

    /// The primary selected item: the first selected one in list order.
    public func primary(_ selection: Set<UUID>) -> Item? {
        selectedIndices(selection).first.map { items[$0] }
    }

    // MARK: Adding

    /// BUILD-004 "Add all": the trimmed non-empty lines are appended (after clearing when `replace`, no confirmation,
    /// removed items not logged); logged `Added / logKind / "{n} added (bulk)" / owner`. Returns the new ids (empty =
    /// nothing happened).
    @discardableResult
    public func addAll(text: String, replace: Bool) -> [UUID] {
        guard var list = read() else { return [] }
        let lines = BuilderBulk.lines(text)
        guard !lines.isEmpty else { return [] }
        if replace { list.removeAll() }
        let added = lines.map(kind.make)
        list.append(contentsOf: added)
        write(list)
        store.logAdded(kind: logKind, name: "\(lines.count) added (bulk)", detail: owner())
        store.markDirty()
        return added.map(kind.id)
    }

    /// BUILD-006…008: inserts one item titled exactly `title` (untrimmed) at `index` (clamped 0…count), logged
    /// `Added / logKind / title / owner`. The caller has already rejected a blank title.
    @discardableResult
    public func insert(title: String, at index: Int) -> UUID? {
        guard var list = read() else { return nil }
        let item = kind.make(title)
        list.insert(item, at: min(max(index, 0), list.count))
        write(list)
        store.logAdded(kind: logKind, name: title, detail: owner())
        store.markDirty()
        return kind.id(item)
    }

    /// BUILD-007 / BUILD-008 insertion index for the current selection.
    public func insertIndex(before: Bool, selection: Set<UUID>) -> Int {
        BuilderReorder.insertIndex(before: before, picks: selectedIndices(selection), count: items.count)
    }

    // MARK: Reordering

    public func canMoveUp(_ selection: Set<UUID>) -> Bool {
        guard let first = selectedIndices(selection).first else { return false }
        return first > 0
    }

    public func canMoveDown(_ selection: Set<UUID>) -> Bool {
        guard let last = selectedIndices(selection).last else { return false }
        return last < items.count - 1
    }

    /// BUILD-011 (BUILD-A2 up); MarkDirty when something moved.
    @discardableResult
    public func moveUp(_ selection: Set<UUID>) -> Bool {
        guard var list = read() else { return false }
        guard BuilderReorder.moveUp(&list, picks: BuilderReorder.selectedIndicesAscending(list.map(kind.id), selection: selection))
        else { return false }
        write(list)
        store.markDirty()
        return true
    }

    /// BUILD-012 (BUILD-A2 down).
    @discardableResult
    public func moveDown(_ selection: Set<UUID>) -> Bool {
        guard var list = read() else { return false }
        guard BuilderReorder.moveDown(&list, picks: BuilderReorder.selectedIndicesAscending(list.map(kind.id), selection: selection))
        else { return false }
        write(list)
        store.markDirty()
        return true
    }

    /// BUILD-013 picker options for the current selection.
    public func moveToOptions(_ selection: Set<UUID>) -> [BuilderMoveOption] {
        let list = items
        let selected = Set(BuilderReorder.selectedIndicesAscending(list.map(kind.id), selection: selection))
        return BuilderReorder.moveToOptions(titles: list.map(kind.title), selected: selected)
    }

    /// BUILD-013 / BUILD-A3: moves the selection as a block to `target`; returns the moved ids (the new selection).
    @discardableResult
    public func moveTo(_ selection: Set<UUID>, target: Int) -> [UUID] {
        guard var list = read() else { return [] }
        let picks = BuilderReorder.selectedIndicesAscending(list.map(kind.id), selection: selection)
        let moved = BuilderReorder.moveTo(&list, picks: picks, target: target)
        guard !moved.isEmpty else { return [] }
        write(list)
        store.markDirty()
        return moved.map { kind.id(list[$0]) }
    }

    /// Drag-and-drop reorder (06 §6.2, additive): the same BUILD-A3 algorithm with SwiftUI's destination index.
    @discardableResult
    public func dropMove(from source: IndexSet, to destination: Int) -> [UUID] {
        guard var list = read() else { return [] }
        let moved = BuilderReorder.dropMove(&list, from: source, to: destination)
        guard !moved.isEmpty else { return [] }
        write(list)
        store.markDirty()
        return moved.map { kind.id(list[$0]) }
    }

    // MARK: Deleting

    /// BUILD-014: after the caller's confirmation — `Removed / logKind / "{n} removed" / owner`, then every selected
    /// item is removed (permanent; no Trash, no undo). Returns the number removed.
    @discardableResult
    public func delete(_ selection: Set<UUID>) -> Int {
        guard var list = read() else { return 0 }
        let n = list.filter { selection.contains(kind.id($0)) }.count
        guard n > 0 else { return 0 }
        store.logRemoved(kind: logKind, name: "\(n) removed", detail: owner())
        list.removeAll { selection.contains(kind.id($0)) }
        write(list)
        store.markDirty()
        return n
    }

    // MARK: Saved lists

    /// BUILD-015 / REPO-147: capture (name trimmed by the service), append at the END of `ChecklistTemplates`
    /// (ungrouped), log `Added / "Saved list" / name / "{n} item(s)"`. The caller saves and shows the message.
    @discardableResult
    public func saveAsList(name: String) -> ChecklistTemplate {
        let tpl = kind.capture(name, items)
        store.data.checklistTemplates.append(tpl)
        store.logAdded(kind: "Saved list", name: tpl.name, detail: "\(tpl.items.count) item(s)")
        return tpl
    }

    /// BUILD-016 / BUILD-044 / REPO-142: Replace (clear first) or Append, logged
    /// `Added / logKind / "{n} added (from saved list '{name}')" / owner`; MarkDirty. Returns the template's item count.
    @discardableResult
    public func apply(_ template: ChecklistTemplate, replace: Bool) -> Int {
        guard var list = read() else { return 0 }
        let n = kind.apply(template, &list, replace)
        write(list)
        store.logAdded(kind: logKind, name: "\(n) added (from saved list '\(template.name)')", detail: owner())
        store.markDirty()
        return n
    }
}
