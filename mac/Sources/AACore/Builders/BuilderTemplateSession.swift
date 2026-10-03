// Spec: 06 BUILD-063 (TemplateEditorWindow: the template's items materialised as detached steps with `ToSteps`, bound
//       to the builder with log kind "Saved-list item", written back with `WriteBackFromSteps` on close), §8 D3 (write
//       back only when changed; if the template vanished meanwhile, offer "Save as new list"), R1 (the template is
//       re-resolved by id on every write-back, so a reload in between writes into the new object), 03 T-KB-40 (⌘Q
//       with a builder open: the editor is flushed before the quit pipeline), T-KB-45 (⌘W / ⎋ persists), DECISIONS
//       02 Q-12 (no no-op write-backs).
// The model side of the saved-list host of the checklist builder (the template editor). The AA view keeps one session
// per open editor, registers `writeBack` with the editor flush center and calls `finish` on every close path.
import Foundation

@MainActor public final class BuilderTemplateSession {
    public let store: AppStore
    public let templateID: UUID
    /// The template's items as detached steps (`ToSteps`, cloned containers) — what the builder edits.
    public var steps: [ChecklistStep]
    public private(set) var isFinished = false
    /// The template object last resolved by id. Kept after a delete so the rescue list carries the name the list had
    /// when it vanished (a rename mutates this same object in place), not the name the editor opened with (D3).
    private var lastResolved: ChecklistTemplate?

    public init(store: AppStore, templateID: UUID) {
        self.store = store
        self.templateID = templateID
        if let t = store.template(id: templateID) {
            steps = ChecklistTemplateService.toSteps(t)
            lastResolved = t
        } else {
            steps = []
        }
    }

    /// The live template (nil when it was deleted or a reload dropped it). Every successful resolution is remembered
    /// (R1: a reload's new object replaces the old one).
    public var template: ChecklistTemplate? {
        let t = store.template(id: templateID)
        if let t { lastResolved = t }
        return t
    }

    /// The template's latest known name: the live name, or the name it had when it vanished (renames made through
    /// "Manage saved lists…" while the editor was open included). `""` when it never resolved.
    public var lastKnownName: String { template?.name ?? lastResolved?.name ?? "" }

    /// BUILD-001 owner name of the saved-list host: the live name (a rename through "Manage saved lists…" shows at
    /// once), else the name it had when it vanished.
    public var ownerName: String { lastKnownName }

    /// Whether writing back now would change the template.
    public var hasChanges: Bool {
        guard let t = template else { return !steps.isEmpty }
        return ChecklistTemplateService.hasChanges(t, steps: steps)
    }

    /// BUILD-063 write-back: the template's items are replaced by clones of the edited steps (deadline / done
    /// dropped) only when something changed (D3, Q-12); MarkDirty. Returns false when the template no longer exists.
    @discardableResult
    public func writeBack() -> Bool {
        guard let t = template else { return false }
        if ChecklistTemplateService.hasChanges(t, steps: steps) {
            ChecklistTemplateService.writeBackFromSteps(t, steps: steps)
            store.markDirty()
        }
        return true
    }

    /// The one commit of the editor (idempotent): write back, then the caller saves ([persist: Save]). Returns false
    /// when the template vanished — the caller then offers `saveAsNewList()` (D3).
    @discardableResult
    public func finish() -> Bool {
        guard !isFinished else { return true }
        isFinished = true
        return writeBack()
    }

    /// D3 rescue: the edited items captured as a new list (named as the vanished one, latest name), appended at the end of
    /// `ChecklistTemplates`, ungrouped, logged `Added / "Saved list" / name / "{n} item(s)"` like "Save as list".
    @discardableResult
    public func saveAsNewList() -> ChecklistTemplate {
        let t = ChecklistTemplateService.captureFromSteps(name: lastKnownName, steps: steps)
        store.data.checklistTemplates.append(t)
        store.logAdded(kind: "Saved list", name: t.name, detail: "\(t.items.count) item(s)")
        return t
    }
}
