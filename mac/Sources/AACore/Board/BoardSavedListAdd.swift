// Spec: 07 VIEW-202, VIEW-214, VIEW-216 (rows tagged (templateId, itemIndex), resolved at OK time), VIEW-054/105,
//       05 CONT-050, 06 BUILD-101 (Board "+ From saved list" / Planner "+ Saved list"), 02 REPO-144 (ItemToTask),
//       DECISIONS 07 Q-03 (log the created tasks — Mac addition).
import Foundation

/// The picker tag of one saved-list item: `ChecklistTemplateItem` has no id, so a row is (template id, index).
public struct BoardSavedListTag: Hashable, Sendable {
    public var templateID: UUID
    public var index: Int
    public init(templateID: UUID, index: Int) { self.templateID = templateID; self.index = index }
}

@MainActor
public enum BoardSavedListAdd {
    public static let title = "Add from saved list"
    public static let noListsMessage = "You have no saved lists yet. Build one in the Saved Lists tab first."
    public static let noItemsMessage = "Your saved lists don't have any items yet."
    public static let prompt = "Search saved lists \u{2014} pick items to add as tasks"

    public enum Candidates {
        case noLists
        case noItems
        case rows([(display: String, tag: BoardSavedListTag)])
    }

    /// One row per item of every list, lists in `ChecklistTemplates` order, items in order.
    public static func candidates(_ data: AppData) -> Candidates {
        guard !data.checklistTemplates.isEmpty else { return .noLists }
        var rows: [(display: String, tag: BoardSavedListTag)] = []
        for t in data.checklistTemplates {
            for (i, it) in t.items.enumerated() {
                rows.append((display(listName: t.name, title: it.title, isJob: it.isJob),
                             BoardSavedListTag(templateID: t.id, index: i)))
            }
        }
        return rows.isEmpty ? .noItems : .rows(rows)
    }

    /// `"{list name or (unnamed list)}  ›  {item title or (untitled)}"` + `"   · schedulable"` for a job.
    public static func display(listName: String, title: String, isJob: Bool) -> String {
        let list = listName.isEmpty ? "(unnamed list)" : listName
        let item = title.isEmpty ? "(untitled)" : title
        return "\(list)  \u{203A}  \(item)" + (isJob ? "   \u{00B7} schedulable" : "")
    }

    /// VIEW-214: every picked item becomes a new top-level task via `ItemToTask`, appended in pick (selection)
    /// order; tags whose list or item no longer resolves are skipped (06 R1). Each new task is logged
    /// `Added / Task / {title} / from saved list '{list}'` (DECISIONS 07 Q-03). The saved lists are not modified.
    /// The caller saves once when anything was created.
    @discardableResult
    public static func apply(_ tags: [BoardSavedListTag], store: AppStore) -> [TaskItem] {
        var created: [TaskItem] = []
        for tag in tags {
            guard let t = store.template(id: tag.templateID), t.items.indices.contains(tag.index) else { continue }
            let task = ChecklistTemplateService.itemToTask(t.items[tag.index])
            store.data.tasks.append(task)
            store.logAdded(kind: "Task", name: task.name, detail: "from saved list '\(t.name)'")
            created.append(task)
        }
        if !created.isEmpty { store.markDirty() }
        return created
    }
}
