// Spec: 06 §C (BUILD-030…038), 04 HIER-091, HIER-093…096, 02 REPO-027 (step links: "banked tasks" = linking existing
//       top-level Tasks to a step, + New task auto-linked — DECISIONS 06), 07 VIEW-212 rows 13/14 and VIEW-215
//       (replace-and-normalise: candidate rows define what can be kept; result in selection order).
// The procedure "Checklist Steps" area's model side. The view (AA/Builders/ProcedureChecklistSection) prompts and
// saves; these helpers mutate and log exactly as the spec says.
import Foundation

/// One row of the procedure step grid (BUILD-031 / HIER-093).
public struct BuilderStepGridRow: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var done: Bool
    public var isJob: Bool
    public var title: String
    /// `yyyy-MM-dd` or `""`.
    public var deadline: String
    public init(id: UUID, done: Bool, isJob: Bool, title: String, deadline: String) {
        self.id = id; self.done = done; self.isJob = isJob; self.title = title; self.deadline = deadline
    }
}

@MainActor public enum BuilderProcedureSteps {
    /// The grid rows of a procedure's steps, in order.
    public static func rows(_ procedure: Procedure) -> [BuilderStepGridRow] {
        procedure.steps.map {
            BuilderStepGridRow(id: $0.id, done: $0.done, isJob: $0.isJob, title: $0.title,
                               deadline: $0.deadline?.format(.isoDate) ?? "")
        }
    }

    /// BUILD-032 / HIER-094 `+ Step`: appended untrimmed, logged `Added / "Checklist step" / title / {procedure}`.
    /// Blank → nil (no-op). The caller saves.
    @discardableResult
    public static func addStep(_ store: AppStore, to procedure: Procedure, rawTitle: String) -> ChecklistStep? {
        guard !NetText.isBlank(rawTitle) else { return nil }
        return store.addStep(titled: rawTitle, to: procedure)
    }

    /// BUILD-033 `Remove`: the primary selected step, no confirmation, logged
    /// `Removed / "Checklist step" / title / {procedure}`. The caller saves.
    public static func remove(_ store: AppStore, step: ChecklistStep, from procedure: Procedure) {
        store.removeStep(step, from: procedure)
    }

    /// BUILD-034 picker rows: top-level tasks in data order, display = the task name (subtasks are not offered).
    public static func taskPickerRows(_ data: AppData) -> [(display: String, id: UUID)] {
        data.tasks.map { ($0.name, $0.id) }
    }

    /// BUILD-036 picker rows: equipment/areas in data order.
    public static func equipmentPickerRows(_ data: AppData) -> [(display: String, id: UUID)] {
        data.equipment.map { ($0.name, $0.id) }
    }

    /// BUILD-034 OK: `TaskIds` replaced by the picked ids (selection order). Not logged; the caller saves.
    public static func linkTasks(_ store: AppStore, _ ids: [UUID], to step: ChecklistStep) {
        store.linkTasks(ids, to: step)
        store.markDirty()
    }

    /// BUILD-036 OK: `EquipmentIds` replaced by the picked ids (selection order).
    public static func linkEquipment(_ store: AppStore, _ ids: [UUID], to step: ChecklistStep) {
        store.linkEquipment(ids, to: step)
        store.markDirty()
    }

    /// BUILD-035 `+ New task`: a new top-level task (name untrimmed) appended to `Data.Tasks`, its id appended to the
    /// step's `TaskIds`, logged `Added / "Task" / name / "linked to step '{title}'"`. Blank → nil. The caller saves.
    @discardableResult
    public static func newLinkedTask(_ store: AppStore, rawName: String, for step: ChecklistStep) -> TaskItem? {
        guard !NetText.isBlank(rawName) else { return nil }
        return store.createLinkedTask(named: rawName, for: step)
    }

    /// The names of a step's linked tasks / equipment (for the step editor's read-only "Linked" line); unresolvable
    /// ids are skipped.
    public static func linkedSummary(_ store: AppStore, step: ChecklistStep) -> (tasks: [String], equipment: [String]) {
        let tasks = step.taskIds.compactMap { id in store.data.tasks.first { $0.id == id }?.name }
        let equipment = step.equipmentIds.compactMap { id in store.data.equipment.first { $0.id == id }?.name }
        return (tasks, equipment)
    }

    /// BUILD-039/040 default file name part: every Windows-invalid character replaced by `_`, no trimming or
    /// fallback (`"checklist-{safeName}.pdf"`; a missing name → `"procedure"`).
    public static func safeName(_ name: String?) -> String {
        guard let name else { return "procedure" }
        var out = String.UnicodeScalarView()
        for sc in name.unicodeScalars {
            if sc.value < 0x20 || "\"<>|:*?\\/".unicodeScalars.contains(sc) { out.append("_") } else { out.append(sc) }
        }
        return String(out)
    }
}
