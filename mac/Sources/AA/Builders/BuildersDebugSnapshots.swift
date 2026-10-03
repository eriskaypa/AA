// Spec: ARCHITECTURE.md §9.6 (W-BUILD's debug sheets for the snapshot hook; ids "w-build.<name>"); OWNERSHIP W-BUILD
//       acceptance (snapshots of every builder host and editor). Fixture data: Tests/AACoreTests/Fixtures/ui/w-build/.
// Each registration resolves its target from the loaded data folder by position, so any data folder works (an empty
// one shows the orphan / empty states).
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_BUILD() {
        register("w-build.checklist-builder") { env in
            let id = env.store.data.procedures.first?.id ?? UUID()
            return AnyView(ChecklistBuilderSheet(host: .procedure(id)))
        }
        register("w-build.crew-checklist") { env in
            let id = env.store.data.crew.first?.id ?? UUID()
            return AnyView(ChecklistBuilderSheet(host: .crew(id)))
        }
        register("w-build.template-editor") { env in
            let id = env.store.data.checklistTemplates.first?.id ?? UUID()
            return AnyView(ChecklistBuilderSheet(host: .savedList(id)))
        }
        register("w-build.subtask-builder") { env in
            let id = env.store.data.tasks.first?.id ?? UUID()
            return AnyView(SubtaskBuilderSheet(taskID: id))
        }
        register("w-build.step-editor") { env in
            let steps = env.store.data.procedures.first?.steps ?? []
            let id = (steps.count > 2 ? steps[2] : steps.first)?.id ?? UUID()
            return AnyView(ChecklistStepEditorSheet(stepID: id))
        }
        register("w-build.step-editor-saved-list") { env in
            let t = env.store.data.checklistTemplates.first
            let step = t.map { ChecklistTemplateService.toSteps($0) }?.first ?? ChecklistStep(title: "Item")
            return AnyView(ChecklistStepEditorSheet(step: step, savedListID: t?.id) { _ in })
        }
        register("w-build.task-editor") { env in
            let id = env.store.data.tasks.first?.id ?? UUID()
            return AnyView(TaskItemEditorSheet(taskID: id))
        }
        register("w-build.subtask-editor") { env in
            let id = env.store.data.tasks.first?.subtasks.dropFirst().first?.id ?? UUID()
            return AnyView(TaskItemEditorSheet(taskID: id))
        }
        register("w-build.procedure-checklist") { env in
            let id = env.store.data.procedures.first?.id ?? UUID()
            return AnyView(BuilderSnapshotFrame(title: "Procedure ▸ Checklist") {
                ProcedureChecklistSection(procedureID: id)
            })
        }
        register("w-build.saved-lists-selected") { env in
            let id = env.store.data.checklistTemplates.first?.id
            return AnyView(BuilderSnapshotFrame(title: "Saved Lists (Deck rounds selected)", size: CGSize(width: 1100, height: 700)) {
                SavedListsTabView(initialSelection: id.map { [$0] } ?? [])
            })
        }
        register("w-build.crew-checklist-embedded") { env in
            let id = env.store.data.crew.first?.id ?? UUID()
            return AnyView(BuilderSnapshotFrame(title: "Crew editor ▸ Checklist") {
                ChecklistBuilderView(host: .crew(id))
            })
        }
    }
}

/// A sheet-sized frame for embedded W-BUILD views (debug snapshots only).
struct BuilderSnapshotFrame<Content: View>: View {
    let title: String
    var size = CGSize(width: 900, height: 600)
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text(title).font(.aaMono(AAType.small, weight: .semibold)).foregroundStyle(AAColor.muted)
            content()
        }
        .padding(AASpacing.l)
        .frame(width: size.width, height: size.height)
        .background(AAColor.bg)
        .aaSheet(.closeType)
    }
}
