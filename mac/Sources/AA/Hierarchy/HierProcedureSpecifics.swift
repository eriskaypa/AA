// Spec: 04 HIER-090 (Deadline — no range, Recurrence, Status — no Completed box, "Mark this procedure as a schedulable
//       job" → Flush, Duration → MarkDirty), the "Checklist" tab body = W-BUILD's ProcedureChecklistSection (HIER-091,
//       093…096 incl. the export buttons, OC-48), DECISIONS 04 Q-G, DECISIONS Q-6; ARCHITECTURE.md §7.7.
import AppKit
import SwiftUI
import AACore

struct HierProcedureSpecifics: View {
    let procedure: Procedure
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var durationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HierFormRow(label: HierText.deadlineLabel, help: HierText.procedureDeadlineHelp) {
                    OptionalDatePicker(value: Binding(get: { procedure.deadline }, set: { v in
                        let d = v.map { $0.date.asCalendarDate }
                        guard procedure.deadline != d else { return }
                        procedure.deadline = d
                        env.store.markDirty()
                    }))
                }
                HierFormRow(label: HierText.recurrenceLabel) {
                    Picker("", selection: Binding(get: { procedure.recurrence }, set: { v in
                        guard procedure.recurrence != v else { return }
                        procedure.recurrence = v
                        env.store.markDirty()
                    })) {
                        ForEach(HierTaskSpecifics.recurrenceChoices(procedure.recurrence), id: \.self) { r in
                            Text(r.friendlyLabel).tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200, alignment: .leading)
                }
                HierFormRow(label: HierText.statusLabel, help: HierText.procedureStatusHelp) {
                    Picker("", selection: Binding(get: { procedure.status }, set: { v in
                        guard procedure.status != v else { return }
                        procedure.status = v
                        env.store.markDirty()
                    })) {
                        ForEach(HierTaskSpecifics.statusChoices(procedure.status), id: \.self) { s in
                            Text(s.friendlyLabel).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200, alignment: .leading)
                }
                HierFormRow(label: "") {
                    Toggle(HierText.procedureJob, isOn: Binding(get: { procedure.isJob }, set: { v in
                        guard procedure.isJob != v else { return }
                        procedure.isJob = v
                        HierPersist.flush(env, dialogs: dialogs)                     // HIER-090: Flush (immediate)
                    }))
                    .toggleStyle(.checkbox)
                    .help(HierText.procedureJobHelp)
                    Text(HierText.durationLabel).foregroundStyle(AAColor.muted).padding(.leading, AASpacing.m)
                    HierDurationField(text: $durationText) { text in
                        if HierPageOps.setDuration(text, current: procedure.durationMinutes,
                                                   write: { procedure.durationMinutes = $0 }) {
                            env.store.markDirty()
                        }
                    }
                }
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.m)
            Divider()
            ProcedureChecklistSection(procedureID: procedure.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { durationText = String(procedure.durationMinutes) }
        .onChange(of: procedure.durationMinutes) { _, v in
            if HierDuration.parse(durationText) != v { durationText = String(v) }
        }
    }
}
