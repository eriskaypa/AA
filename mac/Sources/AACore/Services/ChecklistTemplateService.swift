// Spec: 02 §2.N, §3.9 (REPO-140…146), 06 BUILD-A19 (CloneContainer/CloneFile), §7.10; DECISIONS 02 Q-12 (P2: skip
//       the "Edit items" write-back when nothing changed — 02 §8 D-17, recorded in Deviations/F2.md).
// A saved list is a FULL COPY: each item carries Title, DurationMinutes, IsJob and an independent Container; never a
// deadline, range, done state, links or buckets.
import Foundation

@MainActor public enum ChecklistTemplateService {
    /// REPO-140: new template (new Id, CreatedUtc now, no group, Name trimmed), one item per step in order.
    public static func captureFromSteps(name: String, steps: [ChecklistStep]) -> ChecklistTemplate {
        ChecklistTemplate(name: NetText.trim(name), items: steps.map {
            ChecklistTemplateItem(title: $0.title, durationMinutes: $0.durationMinutes, isJob: $0.isJob,
                                  container: cloneContainer($0.container))
        })
    }

    /// REPO-141: from DIRECT subtasks only (Title = Name); nested subtasks, descriptions, dates, status, recurrence,
    /// tags, relations and buckets are dropped.
    public static func captureFromSubtasks(name: String, subtasks: [TaskItem]) -> ChecklistTemplate {
        ChecklistTemplate(name: NetText.trim(name), items: subtasks.map {
            ChecklistTemplateItem(title: $0.name, durationMinutes: $0.durationMinutes, isJob: $0.isJob,
                                  container: cloneContainer($0.container))
        })
    }

    /// REPO-142: clears the target first when `replace` (hard removal), then appends one fresh step per item (new
    /// id, not done, no deadline or links, cloned container). Returns the template's item count.
    @discardableResult
    public static func applyToSteps(_ t: ChecklistTemplate, steps: inout [ChecklistStep], replace: Bool) -> Int {
        if replace { steps.removeAll() }
        steps.append(contentsOf: toSteps(t))
        return t.items.count
    }

    /// REPO-142: as `applyToSteps` with new `TaskItem`s (Name = Title, Todo).
    @discardableResult
    public static func applyToSubtasks(_ t: ChecklistTemplate, subtasks: inout [TaskItem], replace: Bool) -> Int {
        if replace { subtasks.removeAll() }
        subtasks.append(contentsOf: t.items.map(itemToTask))
        return t.items.count
    }

    /// REPO-143: new Id, `Name = newName` (not trimmed), the SAME GroupId, CreatedUtc now, deep-copied items.
    public static func clone(_ t: ChecklistTemplate, newName: String) -> ChecklistTemplate {
        ChecklistTemplate(name: newName, items: t.items.map {
            ChecklistTemplateItem(title: $0.title, durationMinutes: $0.durationMinutes, isJob: $0.isJob,
                                  container: cloneContainer($0.container))
        }, groupId: t.groupId)
    }

    /// REPO-144: a standalone task — Name = Title, duration, job flag, cloned container, Status Todo; no deadline,
    /// range or done state.
    public static func itemToTask(_ item: ChecklistTemplateItem) -> TaskItem {
        let task = TaskItem(name: item.title)
        task.durationMinutes = item.durationMinutes
        task.isJob = item.isJob
        task.container = cloneContainer(item.container)
        task.status = .todo
        return task
    }

    /// REPO-145: the items materialised as fresh `ChecklistStep`s (title, duration, job flag, cloned container).
    public static func toSteps(_ t: ChecklistTemplate) -> [ChecklistStep] {
        t.items.map { it in
            let s = ChecklistStep(title: it.title)
            s.durationMinutes = it.durationMinutes
            s.isJob = it.isJob
            s.container = cloneContainer(it.container)
            return s
        }
    }

    /// REPO-145: rebuilds `Items` from the edited steps (per-instance deadline/done dropped, containers cloned).
    /// DECISIONS 02 Q-12: when the steps carry exactly the template's content (titles, durations, job flags and
    /// container contents in order) nothing is rewritten, so an unchanged "Edit items…" round trip causes no churn.
    public static func writeBackFromSteps(_ t: ChecklistTemplate, steps: [ChecklistStep]) {
        if !hasChanges(t, steps: steps) { return }
        t.items = steps.map {
            ChecklistTemplateItem(title: $0.title, durationMinutes: $0.durationMinutes, isJob: $0.isJob,
                                  container: cloneContainer($0.container))
        }
    }

    /// True when writing `steps` back would change the template's content (Q-12 comparison).
    public static func hasChanges(_ t: ChecklistTemplate, steps: [ChecklistStep]) -> Bool {
        guard t.items.count == steps.count else { return true }
        for (it, s) in zip(t.items, steps) {
            if !Ordinal.equals(it.title, s.title) || it.durationMinutes != s.durationMinutes || it.isJob != s.isJob { return true }
            if !sameContent(it.container, s.container) { return true }
        }
        return false
    }

    /// REPO-146 / BUILD-A19: nil → a fresh empty container; else a new container (new Id) with the same
    /// `RichTextXaml` (copied as a string, never parsed — a legacy `enc:` blob too), `IsLocked`,
    /// `SharedWithContainerIds`, and each file cloned. Attachment paths are shared, never duplicated on disk.
    public static func cloneContainer(_ c: Container?) -> Container {
        guard let c else { return Container() }
        return Container(richTextXaml: c.richTextXaml, files: c.files.map(cloneFile),
                         sharedWithContainerIds: Array(c.sharedWithContainerIds), isLocked: c.isLocked)
    }

    /// REPO-146: a new `FileItem` (new Id) with the same Name, Path, Kind, Added, IsLink, LinkInPlace, LinkedItemIds.
    public static func cloneFile(_ f: FileItem) -> FileItem {
        FileItem(name: f.name, path: f.path, kind: f.kind, added: f.added, isLink: f.isLink,
                 linkInPlace: f.linkInPlace, linkedItemIds: Array(f.linkedItemIds))
    }

    static func sameContent(_ a: Container, _ b: Container) -> Bool {
        guard Ordinal.equals(a.richTextXaml, b.richTextXaml), a.isLocked == b.isLocked,
              a.sharedWithContainerIds == b.sharedWithContainerIds, a.files.count == b.files.count else { return false }
        for (x, y) in zip(a.files, b.files) {
            guard Ordinal.equals(x.name, y.name), Ordinal.equals(x.path, y.path), x.kind == y.kind, x.added.ticks == y.added.ticks,
                  x.isLink == y.isLink, x.linkInPlace == y.linkInPlace, x.linkedItemIds == y.linkedItemIds
            else { return false }
        }
        return true
    }
}
