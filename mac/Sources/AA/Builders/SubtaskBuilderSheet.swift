// Spec: 06 §D BUILD-041 (window: header, help, saved-lists strip without Manage, Close = Flush), BUILD-042 (panes and
//       tooltips), BUILD-043 (rows: name struck when complete, deadline yyyy-MM-dd), BUILD-044 (behaviour = §A with
//       subtask wording, log kind "Subtask" / detail = parent task name, Edit opens the subtask editor), BUILD-045
//       (one level; deeper levels carried along when moved and deleted with their parent), BUILD-046 (hosts: Task
//       Specifics and quick work "Open full builder"), 03 T-KB-45 (⌘W / ⎋ close and persist), §8 R1 (resolved by id).
import AppKit
import SwiftUI
import AACore

/// The subtask builder's state: the task is re-resolved by id on every read (subtasks included, so a nested task
/// can have its own builder).
@MainActor @Observable
final class BuilderSubtaskModel {
    let taskID: UUID
    @ObservationIgnored let store: AppStore
    var selection: Set<UUID> = []
    @ObservationIgnored private(set) var engine: BuilderEngine<TaskItem>!

    init(taskID: UUID, store: AppStore) {
        self.taskID = taskID
        self.store = store
        engine = BuilderEngine(store: store, kind: .subtasks, logKind: "Subtask",
                               owner: { [unowned self] in self.task?.name ?? "" },
                               read: { [unowned self] in self.task?.subtasks },
                               write: { [unowned self] in self.task?.subtasks = $0 })
    }

    var task: TaskItem? { store.task(id: taskID) }
}

extension BuilderUI {
    /// BUILD-043 row display (shared with the task editor's nested Subtasks section).
    static func subtaskRow(_ t: TaskItem) -> BuilderRowDisplay {
        BuilderRowDisplay(id: t.id, title: t.name, struck: t.isComplete, trailing: t.deadline?.format(.isoDate) ?? "",
                          nested: t.subtasks.count)
    }
}

struct SubtaskBuilderSheet: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismiss) private var dismiss
    @State private var model: BuilderSubtaskModel?
    @State private var committed = false

    init(taskID: UUID) { self.taskID = taskID }

    var body: some View {
        VStack(spacing: 0) {
            if let model {
                if let task = model.task {
                    BuilderSheetHeader(title: "Subtask builder — \(task.name)",
                                       subtitle: "Type one subtask per line on the left and click 'Add all'. Use the right "
                                           + "panel to reorder, edit (deadline / recurrence / status / notes) and delete "
                                           + "subtasks. Close to save.",
                                       symbol: "hammer")
                        .padding(.horizontal, AASpacing.l)
                        .padding(.top, AASpacing.l)
                        .padding(.bottom, AASpacing.m)
                    Divider()
                    BuilderItemsPane(engine: model.engine, strings: .subtaskList, display: BuilderUI.subtaskRow,
                                     edit: { id in await edit(id) }, selection: Bindable(model).selection)
                } else {
                    BuilderOrphanState(what: "This task").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack {
                    if let task = model.task {
                        let nested = task.subtasks.reduce(0) { $0 + $1.subtasks.count }
                        if nested > 0 {
                            Label("\(nested) deeper subtask\(nested == 1 ? "" : "s") travel with their parents.",
                                  systemImage: "arrow.turn.down.right")
                                .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
                                .help("Open a subtask's editor to work on its own subtasks.")
                        }
                    }
                    Spacer()
                    Button("Close") { commit(); dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .aaProminent()
                        .frame(minWidth: 80)
                }
                .padding(.horizontal, AASpacing.l)
                .padding(.vertical, AASpacing.m)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 780, idealWidth: 780, maxWidth: .infinity, minHeight: 560, idealHeight: 640, maxHeight: .infinity)
        .background(AAColor.bg)
        .onAppear { if model == nil { model = BuilderSubtaskModel(taskID: taskID, store: env.store) } }
        .onDisappear { commit() }
        .aaSheet(.closeType, onClose: { commit() })
    }

    /// BUILD-044: Edit opens the subtask editor; then Flush and refresh.
    private func edit(_ id: UUID) async {
        await dialogs.presentSheet(.closeType) { _ in TaskItemEditorSheet(taskID: id) }
        BuilderUI.flush(env)
    }

    /// BUILD-041: closing = Flush.
    private func commit() {
        guard !committed else { return }
        committed = true
        env.flushAllEditors()
        BuilderUI.flush(env)
    }
}
