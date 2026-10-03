// Spec: 04 HIER-080 (Deadline + optional Start, coerced against the MODEL's partner, MarkDirty), HIER-081 (Recurrence),
//       HIER-082 (Status ⇄ Completed), HIER-083 (Schedulable job + Duration, invalid text ignored), HIER-084 (the
//       Comprehensive Subtask Builder → W-BUILD's SubtaskBuilderSheet), HIER-085 (subtasks table: Name struck when
//       complete, When, Status, Done glyph — Q-28), HIER-086 (+ Add / Remove / Edit… → TaskItemEditorSheet),
//       HIER-087 (context menu = batch done / deadline with the native right-click rule), §6.6, DECISIONS 04 Q-G
//       (friendly labels, same integers), DECISIONS Q-6 (edited dates are calendar dates); 02 REPO-051.
import AppKit
import SwiftUI
import AACore

struct HierTaskSpecifics: View {
    let task: TaskItem
    let model: HierPageModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var durationText = ""
    @State private var selectedSubtasks = Set<UUID>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AASpacing.l) {
                schedule
                Button {
                    openBuilder()
                } label: {
                    Label(HierText.subtaskBuilder, systemImage: "hammer")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(HierText.subtaskBuilderHelp)
                subtasks
            }
            .padding(AASpacing.l)
        }
        .onAppear { durationText = String(task.durationMinutes) }
        .onChange(of: task.durationMinutes) { _, v in
            if HierDuration.parse(durationText) != v { durationText = String(v) }
        }
        .onChange(of: model.pendingChildID) { _, _ in revealChild() }
        .onAppear { revealChild() }
    }

    // MARK: Schedule (HIER-080…083)

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HierFormRow(label: HierText.deadlineLabel, help: HierText.taskDeadlineHelp) {
                OptionalDatePicker(value: Binding(get: { task.deadline }, set: { v in
                    if HierPageOps.setTaskDeadline(task, v) { env.store.markDirty() }
                }))
            }
            HierFormRow(label: HierText.startLabel, help: HierText.startHelp) {
                OptionalDatePicker(value: Binding(get: { task.rangeStart }, set: { v in
                    if HierPageOps.setTaskStart(task, v) { env.store.markDirty() }
                }))
                if task.hasRange, let s = task.rangeStart, let d = task.deadline {
                    Text("range · \(s.civilDate.days(to: d.civilDate) + 1) days")
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.muted)
                }
            }
            HierFormRow(label: HierText.recurrenceLabel) {
                Picker("", selection: Binding(get: { task.recurrence }, set: { v in
                    guard task.recurrence != v else { return }
                    task.recurrence = v
                    env.store.markDirty()
                })) {
                    ForEach(HierTaskSpecifics.recurrenceChoices(task.recurrence), id: \.self) { r in
                        Text(r.friendlyLabel).tag(r)
                    }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .leading)
            }
            HierFormRow(label: HierText.statusLabel, help: HierText.taskStatusHelp) {
                Picker("", selection: Binding(get: { task.status }, set: { v in
                    guard task.status != v else { return }
                    task.status = v
                    env.store.markDirty()
                })) {
                    ForEach(HierTaskSpecifics.statusChoices(task.status), id: \.self) { s in
                        Text(s.friendlyLabel).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .leading)
                Toggle(HierText.completed, isOn: Binding(get: { task.isComplete }, set: { v in
                    guard task.isComplete != v else { return }
                    task.isComplete = v
                    env.store.markDirty()
                }))
                .toggleStyle(.checkbox)
            }
            HierFormRow(label: "") {
                Toggle(HierText.schedulableJob, isOn: Binding(get: { task.isJob }, set: { v in
                    guard task.isJob != v else { return }
                    task.isJob = v
                    env.store.markDirty()
                }))
                .toggleStyle(.checkbox)
                .help(HierText.schedulableJobHelp)
                Text(HierText.durationLabel).foregroundStyle(AAColor.muted).padding(.leading, AASpacing.m)
                HierDurationField(text: $durationText) { text in
                    if HierPageOps.setDuration(text, current: task.durationMinutes, write: { task.durationMinutes = $0 }) {
                        env.store.markDirty()
                    }
                }
            }
        }
    }

    /// Enum values offered by the pickers (an undefined stored value stays visible and selected).
    static func recurrenceChoices(_ current: RecurrenceKind) -> [RecurrenceKind] {
        RecurrenceKind.allKinds.contains(current) ? RecurrenceKind.allKinds : RecurrenceKind.allKinds + [current]
    }

    static func statusChoices(_ current: WorkStatus) -> [WorkStatus] {
        WorkStatus.allStatuses.contains(current) ? WorkStatus.allStatuses : WorkStatus.allStatuses + [current]
    }

    // MARK: Subtasks (HIER-085…087)

    private var subtasks: some View {
        HierBlock(title: HierText.subtasks, symbol: "checklist") {
            HStack(spacing: AASpacing.s) {
                Button(HierText.add) { Task { await addSubtask() } }
                Button(HierText.remove) { removeSubtask() }
                    .disabled(selectedSubtasks.isEmpty)
                Button(HierText.edit) { editSubtask(firstSelected?.id) }
                    .disabled(selectedSubtasks.isEmpty)
                    .help(HierText.subtaskEditHelp)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } content: {
            Table(task.subtasks, selection: $selectedSubtasks) {
                TableColumn(HierText.nameColumn) { (s: TaskItem) in
                    AAStrikeText(s.name, struck: s.isComplete)
                        .lineLimit(2)
                }
                .width(min: 140, ideal: 280)
                TableColumn(HierText.whenColumn) { (s: TaskItem) in
                    Text(s.whenText).foregroundStyle(AAColor.muted).monospacedDigit()
                }
                .width(min: 90, ideal: 190)
                TableColumn(HierText.statusColumn) { (s: TaskItem) in
                    Text(s.status.friendlyLabel)
                }
                .width(min: 70, ideal: 110)
                TableColumn(HierText.doneColumn) { (s: TaskItem) in
                    Image(systemName: s.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(s.isComplete ? AAColor.Status.ok : AAColor.muted)
                        .accessibilityLabel(s.isComplete ? "Done" : "Not done")
                }
                .width(min: 40, ideal: 60, max: 70)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                BatchContextMenuItems(selection: { subtaskObjects(ids) }, refresh: {})
            } primaryAction: { ids in
                editSubtask(ids.first)
            }
            .overlay {
                if task.subtasks.isEmpty {
                    Text(HierText.noSubtasks).font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 220)
            .aaListCommands(ListCommands(role: .subtasks, selectionCount: selectedSubtasks.count,
                                         deleteTitle: HierText.remove,
                                         delete: selectedSubtasks.isEmpty ? nil : { removeSubtask() },
                                         deleteConfirms: false,
                                         primary: selectedSubtasks.isEmpty ? nil : { editSubtask(firstSelected?.id) }))
        }
    }

    /// The first selected subtask in list order (Windows' `SelectedItem`).
    private var firstSelected: TaskItem? { task.subtasks.first { selectedSubtasks.contains($0.id) } }

    /// Context-menu targets: the clicked set in list order, evaluated at click time.
    private func subtaskObjects(_ ids: Set<UUID>) -> [AnyObject] {
        task.subtasks.filter { ids.contains($0.id) }
    }

    private func revealChild() {
        guard let child = model.pendingChildID else { return }
        model.pendingChildID = nil
        // A nested hit selects the direct subtask that contains it (DECISIONS 02 Q-11).
        if let row = HierPageOps.directSubtask(of: task, revealing: child) { selectedSubtasks = [row.id] }
    }

    private func addSubtask() async {
        guard let name = await HierDialogs.prompt(dialogs, title: HierText.newSubtaskTitle, label: HierText.nameLabel),
              let s = HierPageOps.addSubtask(store: env.store, named: name, to: task) else { return }
        HierPersist.save(env, dialogs: dialogs)
        selectedSubtasks = [s.id]
    }

    /// HIER-086: the (first) selected subtask, with its subtree; no confirmation, no Trash; logged; Save.
    private func removeSubtask() {
        guard let s = firstSelected else { return }
        env.flushAllEditors()
        env.store.removeSubtask(s, from: task)
        HierPersist.save(env, dialogs: dialogs)
        selectedSubtasks.remove(s.id)
    }

    private func editSubtask(_ id: UUID?) {
        guard let id else { return }
        let presenter = dialogs
        Task { @MainActor in
            await presenter.presentSheet(.closeType) { _ in TaskItemEditorSheet(taskID: id) }
        }
    }

    private func openBuilder() {
        env.flushAllEditors()
        let presenter = dialogs
        let id = task.id
        Task { @MainActor in
            await presenter.presentSheet(.closeType) { _ in SubtaskBuilderSheet(taskID: id) }
        }
    }
}

/// HIER-083 duration box: shows the text as typed; writes only valid values > 0 (invalid input is kept and outlined).
struct HierDurationField: View {
    @Binding var text: String
    var onChange: (String) -> Void

    var body: some View {
        let invalid = !text.isEmpty && HierDuration.parse(text) == nil
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .monospacedDigit()
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(AAColor.Status.danger, lineWidth: invalid ? 1 : 0))
            .help(invalid ? "Enter a whole number of minutes greater than 0." : "")
            .onChange(of: text) { _, t in onChange(t) }
            .accessibilityLabel("Duration in minutes")
    }
}
