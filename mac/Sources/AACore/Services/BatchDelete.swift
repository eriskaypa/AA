// Spec: 02 REPO-073…075, §3.7 (BatchDelete), 04 §3.13, §7.6; 03 §6.5.1.9 (user-visible key names via
//       `MacKeyStrings`); OC-11 / 01 DATA-094 (locks gate through `isGated`).
import Foundation

/// Describe-then-trash a multi-selection as one undoable batch. Pure over the model; the UI confirms and saves.
@MainActor public enum BatchDelete {
    /// The confirmation summary of a selection (02 §3.7 `Summary`).
    nonisolated public struct Description: Sendable, Equatable {
        public var equipment, tasks, procedures, vessels, descendants, withAttachments, linkedFromElsewhere, locked: Int

        public init(equipment: Int = 0, tasks: Int = 0, procedures: Int = 0, vessels: Int = 0, descendants: Int = 0,
                    withAttachments: Int = 0, linkedFromElsewhere: Int = 0, locked: Int = 0) {
            self.equipment = equipment; self.tasks = tasks; self.procedures = procedures; self.vessels = vessels
            self.descendants = descendants; self.withAttachments = withAttachments
            self.linkedFromElsewhere = linkedFromElsewhere; self.locked = locked
        }

        /// Top-level items that will be deleted (locked ones excluded).
        public var total: Int { equipment + tasks + procedures + vessels }
        /// Nothing at all was selected (no deletable and no locked item).
        public var isEmpty: Bool { total == 0 && locked == 0 }

        /// "{n} task{s}, {n} procedure{s}, {n} equipment/area{s}, {n} vessel{s}" — non-zero kinds only, in that
        /// order; `"nothing"` when none.
        public func kindBreakdown() -> String {
            var parts: [String] = []
            if tasks > 0 { parts.append("\(tasks) task\(tasks == 1 ? "" : "s")") }
            if procedures > 0 { parts.append("\(procedures) procedure\(procedures == 1 ? "" : "s")") }
            if equipment > 0 { parts.append("\(equipment) equipment/area\(equipment == 1 ? "" : "s")") }
            if vessels > 0 { parts.append("\(vessels) vessel\(vessels == 1 ? "" : "s")") }
            return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
        }
    }

    /// REPO-074: unwraps rows, keeps `HierarchyItem`s, de-duplicates by id (first kept), then drops any item that
    /// is a (cycle-guarded) descendant of a selected task. Output = first-seen order.
    public static func topLevel(_ selection: [AnyObject]) -> [HierarchyItem] {
        var items: [HierarchyItem] = []
        var seen = Set<UUID>()
        for o in selection {
            guard let h = SvcSelection.unwrap(o) as? HierarchyItem, seen.insert(h.id).inserted else { continue }
            items.append(h)
        }
        var covered = Set<UUID>()
        for case let t as TaskItem in items {
            for d in t.repoDescendantsByID() { covered.insert(d.id) }
        }
        return items.filter { !covered.contains($0.id) }
    }

    /// REPO-073: counts per kind, descendants (components / all nested subtasks / steps / 0), items carrying files
    /// anywhere in their subtree, items with backlinks; a gated (locked, not unlocked) item only counts as locked.
    public static func describe(_ selection: [AnyObject], store: AppStore,
                                isGated: (HierarchyItem) -> Bool) -> Description {
        var d = Description()
        for item in topLevel(selection) {
            if isGated(item) { d.locked += 1; continue }
            switch item {
            case let e as Equipment:
                d.equipment += 1
                d.descendants += e.components.count
            case let t as TaskItem:
                d.tasks += 1
                d.descendants += t.repoDescendantsByID().count
            case let p as Procedure:
                d.procedures += 1
                d.descendants += p.steps.count
            case is Vessel:
                d.vessels += 1
            default:
                break
            }
            if hasAttachments(item) { d.withAttachments += 1 }
            if !store.referencedBy(item).isEmpty { d.linkedFromElsewhere += 1 }
        }
        return d
    }

    /// REPO-075 step 3: the confirmation body (lines joined by `\n`, details indented four spaces), with the Mac
    /// key names (`⌘Z`, 03 §6.5.1.9). `trashCount` = the Trash size before deleting.
    public static func confirmationMessage(_ d: Description, trashCount: Int) -> String {
        var lines: [String] = []
        lines.append(d.total == 1 ? "Move 1 item to the Trash?" : "Move \(d.total) items to the Trash?")
        lines.append("")
        lines.append("    " + d.kindBreakdown())
        if d.descendants > 0 {
            lines.append("    \(d.descendants) subtask/step/component\(d.descendants == 1 ? "" : "s") inside them will be deleted too.")
        }
        if d.withAttachments > 0 {
            lines.append("    \(d.withAttachments) of them \(d.withAttachments == 1 ? "has" : "have") attached files (the files stay on disk).")
        }
        if d.linkedFromElsewhere > 0 {
            lines.append("    \(d.linkedFromElsewhere) \(d.linkedFromElsewhere == 1 ? "is" : "are") linked from other items; those links show \"(missing)\" until the Trash is emptied.")
        }
        if d.locked > 0 {
            lines.append(d.locked == 1 ? "    1 locked item is selected and will be skipped."
                                       : "    \(d.locked) locked items are selected and will be skipped.")
        }
        let after = trashCount + d.total
        if after > AppStore.maxTrashItems {
            lines.append("    Note: the Trash holds \(AppStore.maxTrashItems) items, so the \(after - AppStore.maxTrashItems) oldest will be permanently removed.")
        }
        lines.append("")
        lines.append("You can restore them from File \u{25B8} Trash, or undo with Ctrl+Z.")
        return MacKeyStrings.render(lines.joined(separator: "\n"))
    }

    /// REPO-075 steps 1–2: nil when there is something to delete; else the info alert (title, message).
    public static func nothingToDeleteMessage(_ d: Description) -> (title: String, message: String)? {
        if d.isEmpty { return ("Delete selected", "Select one or more items first.") }
        if d.total == 0 {
            return ("Nothing deleted", d.locked == 1 ? "That item is locked. Unlock it before deleting it."
                                                     : "All \(d.locked) selected items are locked. Unlock them before deleting.")
        }
        return nil
    }

    /// REPO-075 step 4: trashes the non-gated top-level picks as ONE batch; returns how many. Does not save.
    @discardableResult public static func trashAll(_ selection: [AnyObject], store: AppStore,
                                                   isGated: (HierarchyItem) -> Bool) -> Int {
        let picks = topLevel(selection).filter { !isGated($0) }
        return picks.isEmpty ? 0 : store.trashItems(picks)
    }

    /// REPO-075 step 5 status line (Mac key names).
    public static func statusAfterDelete(count: Int, firstName: String) -> String {
        MacKeyStrings.render(count == 1 ? "'\(firstName)' moved to Trash — Ctrl+Z to undo."
                                        : "\(count) items moved to Trash — Ctrl+Z to undo them all.")
    }

    static func hasAttachments(_ item: HierarchyItem) -> Bool {
        if !item.container.files.isEmpty { return true }
        switch item {
        case let e as Equipment: return e.components.contains { !$0.container.files.isEmpty }
        case let t as TaskItem: return t.repoDescendantsByID().contains { !$0.container.files.isEmpty }
        case let p as Procedure: return p.steps.contains { !$0.container.files.isEmpty }
        default: return false
        }
    }
}
