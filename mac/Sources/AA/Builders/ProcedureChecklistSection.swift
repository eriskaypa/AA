// Spec: 06 §C BUILD-030 (header, builder banner, export buttons), BUILD-031 (step grid: Done / Job / Title / Deadline;
//       Done and Job clicks MarkDirty + Flush), BUILD-032 (+ Step), BUILD-033 (Remove), BUILD-034 (Link tasks… —
//       "banked tasks", DECISIONS 06), BUILD-035 (+ New task, auto-linked), BUILD-036 (Link equipment/area…),
//       BUILD-037 (Edit… / double-click), BUILD-038 (context menu = batch done / deadline, W-HIER's items),
//       BUILD-039/040 (export buttons → W-PDF's flows, flushed first); 04 HIER-091, HIER-093…096; 02 REPO-027;
//       07 VIEW-212 rows 13/14 + VIEW-215 (selection order, normalise, Save); 03 §6.5.1.10 role `steps`
//       (Remove has no confirmation → no plain ⌫, ⌘⌫ only). ARCHITECTURE.md §7.7 (embedded by W-HIER).
import AppKit
import SwiftUI
import AACore

struct ProcedureChecklistSection: View {
    let procedureID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var selection: Set<UUID> = []
    @State private var busy = false

    init(procedureID: UUID) { self.procedureID = procedureID }

    private var procedure: Procedure? { env.store.item(id: procedureID) as? Procedure }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            if let procedure {
                content(procedure)
            } else {
                BuilderOrphanState(what: "This procedure")
            }
        }
    }

    // MARK: Layout

    private func content(_ procedure: Procedure) -> some View {
        let rows = BuilderProcedureSteps.rows(procedure)
        let done = rows.filter(\.done).count
        return VStack(alignment: .leading, spacing: AASpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
                Text("Checklist Steps").font(.system(size: AAType.body, weight: .bold)).foregroundStyle(AAColor.fg)
                if !rows.isEmpty {
                    Text("\(done) of \(rows.count) done")
                        .font(.system(size: AAType.caption, weight: .medium))
                        .foregroundStyle(done == rows.count ? AAColor.Status.ok : AAColor.muted)
                        .monospacedDigit()
                    ProgressView(value: Double(done), total: Double(max(rows.count, 1)))
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                        .tint(done == rows.count ? AAColor.Status.ok : AAColor.tint)
                }
                Spacer(minLength: 0)
            }
            banner
            stepButtons
            grid(rows)
        }
    }

    /// BUILD-030 / HIER-091: the builder banner (stretched, accent, bold) and the two checklist-only exports.
    private var banner: some View {
        HStack(spacing: AASpacing.s) {
            Button {
                run {
                    await dialogs.presentSheet(.closeType) { _ in ChecklistBuilderSheet(host: .procedure(procedureID)) }
                }
            } label: {
                Label("Open Comprehensive Checklist Builder", systemImage: "hammer")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .aaProminent()
            .controlSize(.large)
            .help("Open a dedicated window to bulk-create, reorder, edit and delete checklist steps.")
            Button {
                run {
                    env.flushAllEditors()
                    BuilderUI.flush(env)
                    await PdfExportFlows.exportChecklistPDF(procedureID: procedureID, env: env, dialogs: dialogs)
                }
            } label: {
                Label("Export checklist (PDF)", systemImage: "doc.richtext")
            }
            .controlSize(.large)
            .help("Export ONLY the checklist (no notes, no relationships) as a printable A4 PDF.")
            Button {
                run {
                    env.flushAllEditors()
                    BuilderUI.flush(env)
                    await PdfExportFlows.exportChecklistXLSX(procedureID: procedureID, env: env, dialogs: dialogs)
                }
            } label: {
                Label("Export checklist (Excel)", systemImage: "tablecells")
            }
            .controlSize(.large)
            .help("Export ONLY the checklist as an Excel workbook (.xlsx).")
        }
    }

    /// HIER-094 / HIER-095 / BUILD-032…037 buttons.
    private var stepButtons: some View {
        BuilderFlowLayout(spacing: 6, lineSpacing: 6) {
            BuilderBarButton(title: "Step", symbol: "plus", help: "Append a new checklist step.") { run { await addStep() } }
            BuilderBarButton(title: "Remove", symbol: "minus", help: "Remove the selected checklist step.",
                             disabled: selection.isEmpty) { removeStep() }
            BuilderBarButton(title: "Edit…", symbol: "pencil",
                             help: "Open this checklist step in a dedicated editor with its own rich-text container and file bank.",
                             disabled: selection.isEmpty) { editPrimary(selection) }
            Divider().frame(height: 18)
            BuilderBarButton(title: "Link tasks…", symbol: "link",
                             help: "Link existing (banked) tasks to the selected checklist step.") { run { await linkTasks() } }
            BuilderBarButton(title: "New task", symbol: "plus.circle",
                             help: "Create a new Task and auto-link it to the selected checklist step.") { run { await newTask() } }
            BuilderBarButton(title: "Link equipment/area…", symbol: "wrench.and.screwdriver",
                             help: "Link equipment/areas to the selected checklist step.") { run { await linkEquipment() } }
        }
    }

    /// BUILD-031 / HIER-093 grid.
    private func grid(_ rows: [BuilderStepGridRow]) -> some View {
        Table(rows, selection: $selection) {
            TableColumn("Done") { row in
                Toggle("", isOn: Binding(get: { row.done }, set: { setDone(row.id, $0) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Done")
            }
            .width(min: 40, ideal: 50, max: 60)
            TableColumn("Job") { row in
                Toggle("", isOn: Binding(get: { row.isJob }, set: { setJob(row.id, $0) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Mark this step as a schedulable Job (set its duration in the step editor).")
                    .accessibilityLabel("Job")
            }
            .width(min: 36, ideal: 44, max: 56)
            TableColumn("Title") { row in
                Text(row.title)
                    .strikethrough(row.done)
                    .foregroundStyle(row.done ? AAColor.muted : AAColor.fg)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 160, ideal: 300)
            TableColumn("Deadline") { row in
                Text(row.deadline).monospacedDigit().foregroundStyle(AAColor.fg)
            }
            .width(min: 90, ideal: 120, max: 160)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 160, maxHeight: .infinity)
        .overlay {
            if rows.isEmpty {
                Text("No checklist steps yet — click + Step or open the builder.")
                    .font(.system(size: AAType.small)).foregroundStyle(AAColor.muted)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .contextMenu(forSelectionType: UUID.self) { ids in
            BatchContextMenuItems(selection: { steps(ids) as [AnyObject] }, refresh: {})
        } primaryAction: { ids in
            editPrimary(ids)
        }
        .aaListCommands(ListCommands(role: .steps, selectionCount: selection.count, deleteTitle: "Remove",
                                     delete: { removeStep() }, deleteConfirms: false,
                                     primary: { editPrimary(selection) }))
    }

    // MARK: Helpers

    private func steps(_ ids: Set<UUID>) -> [ChecklistStep] {
        procedure?.steps.filter { ids.contains($0.id) } ?? []
    }

    /// The primary selection: the first selected step in list order.
    private func primaryStep(_ ids: Set<UUID>) -> ChecklistStep? {
        procedure?.steps.first { ids.contains($0.id) }
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            await body()
            busy = false
        }
    }

    // MARK: Actions

    /// BUILD-031: the Done checkbox — MarkDirty + Flush.
    private func setDone(_ id: UUID, _ value: Bool) {
        guard let s = procedure?.steps.first(where: { $0.id == id }) else { return }
        BuilderEditing.setDone(env.store, s, value)
        BuilderUI.flush(env)
    }

    /// BUILD-031: the Job checkbox — MarkDirty + Flush.
    private func setJob(_ id: UUID, _ value: Bool) {
        guard let s = procedure?.steps.first(where: { $0.id == id }) else { return }
        BuilderEditing.setJob(env.store, s, value)
        BuilderUI.flush(env)
    }

    /// BUILD-032: prompt "New Step" / "Title:" → appended (untrimmed), logged, Save.
    private func addStep() async {
        guard let raw = await BuilderUI.nonBlankPrompt(dialogs, title: "New Step", prompt: "Title:"),
              let p = procedure,
              let step = BuilderProcedureSteps.addStep(env.store, to: p, rawTitle: raw) else { return }
        BuilderUI.save(env)
        withAnimation(.snappy(duration: 0.2)) { selection = [step.id] }
    }

    /// BUILD-033: the primary selection, no confirmation, logged, Save.
    private func removeStep() {
        guard let p = procedure, let step = primaryStep(selection) else { return }
        BuilderProcedureSteps.remove(env.store, step: step, from: p)
        BuilderUI.save(env)
        selection.remove(step.id)
    }

    /// BUILD-037: the step editor for the primary selection; refresh afterwards.
    private func editPrimary(_ ids: Set<UUID>) {
        guard let step = primaryStep(ids) else { return }
        let id = step.id
        run {
            await dialogs.presentSheet(.closeType) { _ in ChecklistStepEditorSheet(stepID: id) }
            BuilderUI.flush(env)
        }
    }

    /// BUILD-034: multi-select picker over top-level tasks, preselected = the step's TaskIds; OK replaces, Save.
    private func linkTasks() async {
        guard let step = primaryStep(selection) else { return }
        let stepID = step.id
        let rows = BuilderProcedureSteps.taskPickerRows(env.store.data).map { (display: $0.display, tag: $0.id) }
        guard let picked = await BuilderUI.pickMany(dialogs, prompt: "Pick tasks for this step", rows: rows,
                                                    preselected: step.taskIds),
              let live = env.store.step(id: stepID)?.step else { return }
        BuilderProcedureSteps.linkTasks(env.store, picked, to: live)
        BuilderUI.save(env)
    }

    /// BUILD-035: needs a selected step; prompt "New Task" / "Name:" → new top-level task linked to the step; Save.
    private func newTask() async {
        guard let step = primaryStep(selection) else {
            await dialogs.info("New task", "Select a checklist step first.")
            return
        }
        let stepID = step.id
        guard let raw = await BuilderUI.nonBlankPrompt(dialogs, title: "New Task", prompt: "Name:"),
              let live = env.store.step(id: stepID)?.step,
              BuilderProcedureSteps.newLinkedTask(env.store, rawName: raw, for: live) != nil else { return }
        BuilderUI.save(env)
    }

    /// BUILD-036: as Link tasks over Equipment/Areas, writing EquipmentIds.
    private func linkEquipment() async {
        guard let step = primaryStep(selection) else { return }
        let stepID = step.id
        let rows = BuilderProcedureSteps.equipmentPickerRows(env.store.data).map { (display: $0.display, tag: $0.id) }
        guard let picked = await BuilderUI.pickMany(dialogs, prompt: "Pick equipment/area for this step", rows: rows,
                                                    preselected: step.equipmentIds),
              let live = env.store.step(id: stepID)?.step else { return }
        BuilderProcedureSteps.linkEquipment(env.store, picked, to: live)
        BuilderUI.save(env)
    }
}
