// Spec: 06 §E BUILD-050 (layout and tooltips), BUILD-051 (live name/description, title follows the name), BUILD-052 /
//       A6 (deadline + working range through WorkRange.coerce), BUILD-053 (Clear range, "range · n days" hint,
//       impossible days greyed), BUILD-054 (recurrence; only top-level tasks regenerate), BUILD-055 (Status ⇄
//       Completed), BUILD-056 (job + duration), BUILD-057 (close = FlushPending + Flush); DECISIONS 06 "the Mac subtask
//       editor gains a nested Subtasks section" (additive — the data is already nested, 06 BUILD-045); DECISIONS 04 Q-G
//       (friendly status / recurrence labels, same stored integers); 07 VIEW-206; ARCHITECTURE.md §7.7.
import AppKit
import SwiftUI
import AACore

/// The subtask editor, used for any task (subtasks, and tasks opened from the Board, Calendar, Planner, Buckets and
/// quick work).
struct TaskItemEditorSheet: View {
    let taskID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var durationText = ""
    @State private var loaded = false
    @State private var committed = false

    init(taskID: UUID) { self.taskID = taskID }

    var body: some View {
        VStack(spacing: 0) {
            if let task = env.store.task(id: taskID) {
                editor(task)
            } else {
                BuilderOrphanState(what: "This task").frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(minWidth: 820, idealWidth: 900, maxWidth: .infinity, minHeight: 600, idealHeight: 700, maxHeight: .infinity)
        .background(AAColor.bg)
        .onDisappear { commit() }
        .aaSheet(.closeType, onClose: { commit() })
    }

    private func ownerLine(_ task: TaskItem) -> String {
        if let parent = env.store.parentTask(of: task.id) {
            return "Subtask of “\(parent.name)”"
        }
        return "Task"
    }

    private func editor(_ task: TaskItem) -> some View {
        VStack(spacing: 0) {
            BuilderSheetHeader(title: "Edit subtask — \(task.name)", subtitle: ownerLine(task), symbol: "square.and.pencil")
                .padding(.horizontal, AASpacing.l)
                .padding(.top, AASpacing.l)
                .padding(.bottom, AASpacing.m)
            form(task)
                .padding(.horizontal, AASpacing.l)
                .padding(.bottom, AASpacing.m)
            Divider()
            HSplitView {
                ContainerEditorView(container: task.container,
                                    context: ContainerEditorContext(title: task.name, host: .subtask(task.id)))
                    .id(ObjectIdentifier(task.container))
                    .frame(minWidth: 420, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                BuilderNestedSubtasksPane(taskID: task.id)
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 420, minHeight: 0, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .onAppear { load(task) }
    }

    // MARK: Form (BUILD-050)

    private func form(_ task: TaskItem) -> some View {
        let store = env.store
        return BuilderCard {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AASpacing.m, verticalSpacing: AASpacing.s) {
                GridRow {
                    BuilderFormLabel("Name:")
                    TextField("", text: Binding(get: { task.name }, set: { BuilderEditing.setName(store, task, $0) }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Name")
                }
                GridRow {
                    BuilderFormLabel("Description:")
                    TextField("", text: Binding(get: { task.description },
                                                set: { BuilderEditing.setDescription(store, task, $0) }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Description")
                }
                GridRow {
                    BuilderFormLabel("Deadline:")
                    rangeRow(task)
                }
                GridRow {
                    BuilderFormLabel("Recurrence:")
                    Picker("", selection: Binding(get: { task.recurrence.rawValue },
                                                  set: { BuilderEditing.setRecurrence(store, task, RecurrenceKind(rawValue: $0)) })) {
                        ForEach(recurrenceChoices(task), id: \.rawValue) { r in Text(r.friendlyLabel).tag(r.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(store.parentTask(of: task.id) == nil
                          ? "Repeat this task when it is completed."
                          : "Stored with the subtask; only top-level tasks create their next occurrence.")
                }
                GridRow {
                    BuilderFormLabel("Status:")
                    Picker("", selection: Binding(get: { task.status.rawValue },
                                                  set: { BuilderEditing.setStatus(store, task, WorkStatus(rawValue: $0)) })) {
                        ForEach(statusChoices(task), id: \.rawValue) { s in Text(s.friendlyLabel).tag(s.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Workflow status used by the Board (Done keeps the Completed box in sync).")
                }
                GridRow {
                    BuilderFormLabel("Completed:")
                    Toggle("Mark as done", isOn: Binding(get: { task.isComplete },
                                                         set: { BuilderEditing.setComplete(store, task, $0) }))
                        .toggleStyle(.checkbox)
                }
                GridRow {
                    BuilderFormLabel("Job:")
                    HStack(spacing: AASpacing.m) {
                        Toggle("Schedulable job", isOn: Binding(get: { task.isJob },
                                                                set: { BuilderEditing.setJob(store, task, $0) }))
                            .toggleStyle(.checkbox)
                            .help("Tag this task as a Job so it can be dragged onto the Planner.")
                        Text("Duration (min):").foregroundStyle(AAColor.muted)
                        BuilderDurationField(text: $durationText, valid: BuilderDuration.parse(durationText) != nil)
                            .onChange(of: durationText) { _, new in
                                guard loaded else { return }
                                BuilderEditing.setDuration(store, task, text: new)
                            }
                    }
                }
            }
        }
    }

    /// BUILD-052/053: deadline + optional start, Clear range, hint; impossible days greyed.
    private func rangeRow(_ task: TaskItem) -> some View {
        let store = env.store
        return HStack(spacing: AASpacing.s) {
            OptionalDatePicker(value: Binding(get: { task.deadline },
                                              set: { BuilderEditing.setDeadline(store, task, $0) }),
                               earliest: BuilderEditing.deadlineEarliest(task))
                .help("The task's due date — also the LAST day of the working range.")
            Text("Start (optional):").foregroundStyle(AAColor.muted).padding(.leading, AASpacing.s)
            OptionalDatePicker(value: Binding(get: { task.rangeStart },
                                              set: { BuilderEditing.setStart(store, task, $0) }),
                               latest: BuilderEditing.startLatest(task))
                .help("Optional first day of the range you'll work on this. Leave empty for a single-day task; the "
                      + "deadline stays the last day.")
            if task.rangeStart != nil {
                Button("Clear range") { withAnimation(.snappy) { BuilderEditing.clearRange(store, task) } }
                    .controlSize(.small)
                    .help("Remove the start date (keeps the deadline).")
                    .transition(.opacity)
            }
            let hint = BuilderRange.hint(start: task.rangeStart, deadline: task.deadline)
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: AAType.caption, weight: .medium))
                    .foregroundStyle(AAColor.tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(AAColor.tint.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    /// Defined values, plus the stored one when it is outside the enum (round-trips unchanged).
    private func recurrenceChoices(_ task: TaskItem) -> [RecurrenceKind] {
        let all = RecurrenceKind.allKinds
        return all.contains(task.recurrence) ? all : all + [task.recurrence]
    }

    private func statusChoices(_ task: TaskItem) -> [WorkStatus] {
        let all = WorkStatus.allStatuses
        return all.contains(task.status) ? all : all + [task.status]
    }

    private var footer: some View {
        HStack {
            Text("Changes save as you type — closing keeps them.")
                .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
            Spacer()
            Button("Close") { commit(); dismiss() }
                .keyboardShortcut(.defaultAction)
                .aaProminent()
                .frame(minWidth: 80)
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
    }

    private func load(_ task: TaskItem) {
        guard !loaded else { return }
        durationText = String(task.durationMinutes)
        DispatchQueue.main.async { loaded = true }
    }

    /// BUILD-057: FlushPending then Flush.
    private func commit() {
        guard !committed else { return }
        committed = true
        env.flushAllEditors()
        BuilderUI.flush(env)
    }
}

/// DECISIONS 06: the nested "Subtasks" section of the subtask editor — the task's direct subtasks with add, edit
/// (recursing into the same editor), reorder, delete and a shortcut to the full subtask builder. Same rules and log
/// lines as the subtask builder (06 §D).
struct BuilderNestedSubtasksPane: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model: BuilderSubtaskModel?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            if let model {
                content(model)
            }
        }
        .padding(AASpacing.m)
        .background(AAPaneBackground())
        .onAppear { if model == nil { model = BuilderSubtaskModel(taskID: taskID, store: env.store) } }
    }

    @ViewBuilder
    private func content(_ model: BuilderSubtaskModel) -> some View {
        @Bindable var m = model
        let engine = model.engine!
        let rows = engine.items.map(BuilderUI.subtaskRow)
        HStack(alignment: .firstTextBaseline) {
            Label("Subtasks", systemImage: "list.bullet.indent")
                .font(.system(size: AAType.small, weight: .bold))
                .foregroundStyle(AAColor.fg)
            Text("\(rows.count)").font(.system(size: AAType.caption, weight: .semibold)).foregroundStyle(AAColor.muted)
            Spacer(minLength: 0)
            Button {
                run { await dialogs.presentSheet(.closeType) { _ in SubtaskBuilderSheet(taskID: taskID) } }
            } label: {
                Label("Builder…", systemImage: "hammer")
            }
            .controlSize(.small)
            .help("Open a dedicated window to bulk-create, reorder, edit and delete subtasks.")
        }
        List(selection: $m.selection) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                BuilderItemRowView(index: i + 1, row: row).tag(row.id)
            }
            .onMove { src, dst in
                let moved = engine.dropMove(from: src, to: dst)
                if !moved.isEmpty { model.selection = Set(moved) }
            }
        }
        .listStyle(.inset)
        .overlay {
            if rows.isEmpty {
                Text("No subtasks.").font(.system(size: AAType.small)).foregroundStyle(AAColor.muted)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button("Edit…", systemImage: "pencil") { edit(ids, model) }
                Button("Move Up", systemImage: "chevron.up") { model.selection = ids; engine.moveUp(ids) }
                    .disabled(!engine.canMoveUp(ids))
                Button("Move Down", systemImage: "chevron.down") { model.selection = ids; engine.moveDown(ids) }
                    .disabled(!engine.canMoveDown(ids))
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { run { await delete(ids, model) } }
            }
        } primaryAction: { ids in
            edit(ids, model)
        }
        .aaListCommands(ListCommands(role: .subtasks, selectionCount: model.selection.count, deleteTitle: "Delete",
                                     delete: { run { await delete(model.selection, model) } }, deleteConfirms: true,
                                     canMoveUp: engine.canMoveUp(model.selection),
                                     canMoveDown: engine.canMoveDown(model.selection),
                                     move: { dir in
                                         if dir == .up { engine.moveUp(model.selection) } else { engine.moveDown(model.selection) }
                                     },
                                     primary: { edit(model.selection, model) }))
        HStack(spacing: 6) {
            BuilderBarButton(title: "Subtask", symbol: "plus", help: "Append a new subtask to the end of the list.") {
                run { await add(model) }
            }
            BuilderBarButton(title: "Edit…", symbol: "pencil",
                             help: "Open the full subtask editor (deadline / recurrence / status / notes / files).",
                             disabled: model.selection.isEmpty) { edit(model.selection, model) }
            BuilderBarButton(title: "Move up", symbol: "chevron.up", help: "Move selected subtask(s) up by one position.",
                             iconOnly: true, disabled: !engine.canMoveUp(model.selection)) { engine.moveUp(model.selection) }
            BuilderBarButton(title: "Move down", symbol: "chevron.down",
                             help: "Move selected subtask(s) down by one position.", iconOnly: true,
                             disabled: !engine.canMoveDown(model.selection)) { engine.moveDown(model.selection) }
            BuilderBarButton(title: "Delete", symbol: "trash", help: "Delete the selected subtasks.", iconOnly: true,
                             disabled: model.selection.isEmpty) { run { await delete(model.selection, model) } }
        }
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            await body()
            busy = false
        }
    }

    private func add(_ model: BuilderSubtaskModel) async {
        guard model.engine.isBound,
              let name = await BuilderUI.nonBlankPrompt(dialogs, title: "New subtask", prompt: "Name:"),
              let id = model.engine.insert(title: name, at: model.engine.items.count) else { return }
        model.selection = [id]
    }

    private func edit(_ ids: Set<UUID>, _ model: BuilderSubtaskModel) {
        guard let first = model.engine.primary(ids) else { return }
        let id = first.id
        run {
            await dialogs.presentSheet(.closeType) { _ in TaskItemEditorSheet(taskID: id) }
            BuilderUI.flush(env)
        }
    }

    private func delete(_ ids: Set<UUID>, _ model: BuilderSubtaskModel) async {
        let n = model.engine.selectedIndices(ids).count
        guard n > 0, await BuilderUI.confirmDelete(dialogs, title: "Confirm",
                                                    message: BuilderWording.deleteQuestion(n, noun: "subtask")) else { return }
        model.engine.delete(ids)
        model.selection.subtract(ids)
    }
}
