// Spec: 06 §B BUILD-020 (layout and tooltips), BUILD-021 (live writes, opening never marks dirty), BUILD-022 / A5
//       (duration validation), BUILD-023 (close = FlushPending + Flush), BUILD-024 (BucketIds / TaskIds / EquipmentIds /
//       ScheduledStart untouched), BUILD-025 (reused from Calendar, Planner, Buckets, quick work, Specifics), BUILD-063 +
//       §8 D3 (in a saved list Deadline/Done are not stored: shown disabled with "Set when the list is applied"),
//       04 HIER-095 (linked tasks / equipment are visible in the step editor), 07 VIEW-206; ARCHITECTURE.md §7.5, §7.7
//       (store-owned steps by id; internal detached overload for the template editor).
import AppKit
import SwiftUI
import AACore

struct ChecklistStepEditorSheet: View {
    let stepID: UUID?
    let detachedStep: ChecklistStep?
    let onCommit: ((ChecklistStep) -> Void)?
    /// The saved list a detached step belongs to (its notes pane is hosted as `.savedListItem`).
    let savedListID: UUID?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var durationText = ""
    @State private var loaded = false
    @State private var committed = false

    /// Store-owned procedure and crew steps (resolved with `store.step(id:)`).
    init(stepID: UUID) { self.stepID = stepID; detachedStep = nil; onCommit = nil; savedListID = nil }

    /// Internal overload for detached template steps (06 BUILD-063).
    init(step: ChecklistStep, onCommit: @escaping (ChecklistStep) -> Void) {
        self.init(step: step, savedListID: nil, onCommit: onCommit)
    }

    /// The template editor's form of the overload: the notes pane knows which saved list it edits.
    init(step: ChecklistStep, savedListID: UUID?, onCommit: @escaping (ChecklistStep) -> Void) {
        stepID = nil; detachedStep = step; self.onCommit = onCommit; self.savedListID = savedListID
    }

    private var isSavedListItem: Bool { detachedStep != nil }

    /// The live step (re-resolved on every render — ARCH §2.4) and its owner label.
    private var resolved: (step: ChecklistStep, owner: String)? {
        if let s = detachedStep {
            let name = savedListID.flatMap { env.store.template(id: $0)?.name }
            return (s, name.map { "Saved-list item · \($0.isEmpty ? "(unnamed)" : $0)" } ?? "Saved-list item")
        }
        guard let id = stepID, let hit = env.store.step(id: id) else { return nil }
        switch hit.owner {
        case .procedure(let pid):
            let name = (env.store.item(id: pid))?.name ?? ""
            return (hit.step, "Checklist step of procedure “\(name)”")
        case .crew(let cid):
            let name = env.store.crewMember(id: cid)?.fullName ?? ""
            return (hit.step, "Checklist item of \(name)")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let r = resolved {
                editor(r.step, owner: r.owner)
            } else {
                BuilderOrphanState(what: "This checklist step")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(nil)
            }
        }
        .frame(minWidth: 760, idealWidth: 900, maxWidth: .infinity, minHeight: 560, idealHeight: 700, maxHeight: .infinity)
        .background(AAColor.bg)
        .onDisappear { commit() }
        .aaSheet(.closeType, onClose: { commit() })
    }

    // MARK: Layout (BUILD-020)

    private func editor(_ step: ChecklistStep, owner: String) -> some View {
        VStack(spacing: 0) {
            BuilderSheetHeader(title: "Edit checklist step — \(step.title)", subtitle: owner, symbol: "checklist")
                .padding(.horizontal, AASpacing.l)
                .padding(.top, AASpacing.l)
                .padding(.bottom, AASpacing.m)
            form(step)
                .padding(.horizontal, AASpacing.l)
                .padding(.bottom, AASpacing.m)
            Divider()
            ContainerEditorView(container: step.container,
                                context: ContainerEditorContext(title: step.title, host: notesHost(step)))
                .id(ObjectIdentifier(step.container))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer(step)
        }
        .onAppear { load(step) }
    }

    private func notesHost(_ step: ChecklistStep) -> EditorHost {
        if let savedListID { return .savedListItem(savedListID) }
        return .step(step.id)
    }

    private func form(_ step: ChecklistStep) -> some View {
        BuilderCard {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AASpacing.m, verticalSpacing: AASpacing.s) {
                GridRow {
                    BuilderFormLabel("Title:")
                    TextField("", text: Binding(get: { step.title },
                                                set: { BuilderEditing.setTitle(env.store, step, $0) }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Title")
                }
                GridRow {
                    BuilderFormLabel("Deadline:")
                    HStack(spacing: AASpacing.s) {
                        if isSavedListItem {
                            Text(step.deadline?.format(.isoDate) ?? "—").foregroundStyle(AAColor.muted)
                            Text("Set when the list is applied")
                                .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
                        } else {
                            OptionalDatePicker(value: Binding(get: { step.deadline },
                                                              set: { BuilderEditing.setDeadline(env.store, step, $0) }))
                        }
                    }
                    .help("Optional per-step due date — the step then behaves like a task subtask (shows in the Calendar "
                          + "and the floating due-dates window).")
                }
                GridRow {
                    BuilderFormLabel("Status:")
                    HStack(spacing: AASpacing.s) {
                        Toggle("Done", isOn: Binding(get: { step.done },
                                                     set: { BuilderEditing.setDone(env.store, step, $0) }))
                            .toggleStyle(.checkbox)
                            .disabled(isSavedListItem)
                        if isSavedListItem {
                            Text("Set when the list is applied")
                                .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
                        }
                    }
                }
                GridRow {
                    BuilderFormLabel("Job:")
                    HStack(spacing: AASpacing.m) {
                        Toggle("Schedulable job", isOn: Binding(get: { step.isJob },
                                                                set: { BuilderEditing.setJob(env.store, step, $0) }))
                            .toggleStyle(.checkbox)
                            .help("Tag this step as a Job so it can be dragged onto the Planner.")
                        Text("Duration (min):").foregroundStyle(AAColor.muted)
                        BuilderDurationField(text: $durationText, valid: BuilderDuration.parse(durationText) != nil)
                            .onChange(of: durationText) { _, new in
                                guard loaded else { return }
                                BuilderEditing.setDuration(env.store, step, text: new)
                            }
                    }
                }
                if !isSavedListItem {
                    let links = BuilderProcedureSteps.linkedSummary(env.store, step: step)
                    if !links.tasks.isEmpty || !links.equipment.isEmpty {
                        GridRow {
                            BuilderFormLabel("Linked:")
                            BuilderLinkedChips(tasks: links.tasks, equipment: links.equipment)
                        }
                    }
                }
            }
        }
    }

    private func footer(_ step: ChecklistStep?) -> some View {
        HStack {
            Text("Changes save as you type — closing keeps them.")
                .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
            Spacer()
            Button("Close") {
                commit()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .aaProminent()
            .frame(minWidth: 80)
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
    }

    // MARK: State

    /// Initial population is suppressed so opening never marks dirty (BUILD-021).
    private func load(_ step: ChecklistStep) {
        guard !loaded else { return }
        durationText = String(step.durationMinutes)
        DispatchQueue.main.async { loaded = true }
    }

    /// BUILD-023: FlushPending (every live editor) then Flush; detached steps report back to the template editor.
    private func commit() {
        guard !committed else { return }
        committed = true
        env.flushAllEditors()
        BuilderUI.flush(env)
        if let s = detachedStep { onCommit?(s) }
    }
}

/// The 80-px duration box: shows the invalid text but leaves the model unchanged (BUILD-022, no error UI on Windows —
/// the Mac adds a subtle red hairline only).
struct BuilderDurationField: View {
    @Binding var text: String
    let valid: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 80)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(AAColor.Status.danger.opacity(valid ? 0 : 0.7), lineWidth: 1))
            .help("Approximate duration in minutes (a whole number above 0).")
            .accessibilityLabel("Duration in minutes")
    }
}

/// Read-only chips of a step's linked tasks and equipment/areas (HIER-095).
struct BuilderLinkedChips: View {
    let tasks: [String]
    let equipment: [String]

    var body: some View {
        BuilderFlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { _, t in chip(t, kind: .task) }
            ForEach(Array(equipment.enumerated()), id: \.offset) { _, e in chip(e, kind: .equipment) }
        }
    }

    private func chip(_ text: String, kind: ItemKind) -> some View {
        HStack(spacing: 4) {
            Circle().fill(AAColor.kind(kind)).frame(width: 7, height: 7)
            Text(text.isEmpty ? "(unnamed)" : text).font(.system(size: AAType.caption)).lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(AAColor.kind(kind).opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(AAColor.border, lineWidth: 0.5))
    }
}
