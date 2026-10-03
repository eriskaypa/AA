// Spec: 09 §G CREW-070…076 (modal editor 640×720: heading, Details / Checklist / Schedule tabs, Cancel + default Save;
//       Details = a draft applied on Save only — text trimmed, the free-text date box is the source of truth with a
//       one-way picker → text sync; Checklist and Schedule edit the live member and save immediately), §6.4 (sheet with
//       a TabView, Esc = Cancel as a Mac superset, OptionalDatePicker + 130-pt text box per date row); DECISIONS 06
//       (commit by id, warn if the target vanished); DECISIONS 09 Q4 (inline hint for ambiguous date text);
//       ARCHITECTURE.md §7.5 (sheet contract), §7.7 (W-BUILD `ChecklistBuilderView(host: .crew(id))`).
import AppKit
import SwiftUI
import AACore

struct CrewEditorSheet: View {
    let memberID: UUID
    let initialTab: CrewEditorTab
    /// true = Save, false = Cancel / closed.
    var onClose: (Bool) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dialogs) private var dialogs
    @State private var tab: CrewEditorTab = .details
    @State private var draft: [String: String] = [:]
    @State private var pickers: [String: NetDateTime] = [:]
    @State private var heading = ""
    @State private var loaded = false
    @State private var finished = false

    init(memberID: UUID, initialTab: CrewEditorTab = .details, onClose: @escaping (Bool) -> Void = { _ in }) {
        self.memberID = memberID
        self.initialTab = initialTab
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AASpacing.s) {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AAColor.Status.crewAccent)
                Text(heading)
                    .font(.aaMono(15, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.top, AASpacing.l)
            .padding(.bottom, AASpacing.s)

            Picker("", selection: $tab) {
                Text("Details").tag(CrewEditorTab.details)
                Text("Checklist").tag(CrewEditorTab.checklist)
                Text("Schedule").tag(CrewEditorTab.schedule)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, AASpacing.s)

            Divider()

            Group {
                switch tab {
                case .details: details
                case .checklist: checklistTab
                case .schedule: scheduleTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: AASpacing.s) {
                if tab != .details {
                    Text("Checklist and schedule changes are saved immediately.")
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.muted)
                }
                Spacer()
                Button("Cancel") { finish(saved: false) }
                    .keyboardShortcut(.cancelAction)
                    .frame(minWidth: 90)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .frame(minWidth: 90)
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.m)
        }
        .frame(width: 640, height: 720)
        .background(AAColor.bg, ignoresSafeAreaEdges: [])
        .aaSheet(.decision)
        .onAppear(perform: load)
        .onDisappear { if !finished { finished = true; onClose(false) } }
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        tab = initialTab
        guard let m = env.store.crewMember(id: memberID) else { heading = CrewEditorForm.heading(fullName: ""); return }
        heading = CrewEditorForm.heading(fullName: m.fullName)
        draft = CrewEditorForm.draft(of: m)
        for f in CrewEditorForm.allFields where f.isDate {
            if let d = CrewEditorForm.pickerDate(draft[f.key] ?? "") { pickers[f.key] = .calendarDate(d) }
        }
    }

    private func save() async {
        guard let m = env.store.crewMember(id: memberID) else {
            await dialogs.warning(CrewEditorForm.windowTitle,
                                  "This crew member is no longer in the roster (it was deleted or the data was reloaded), so the changes could not be saved.")
            finish(saved: false)
            return
        }
        CrewEditorForm.apply(draft, to: m)                      // CREW-074: form order
        finish(saved: true)
    }

    private func finish(saved: Bool) {
        guard !finished else { return }
        finished = true
        onClose(saved)
        dismiss()
    }

    // MARK: Details (CREW-071…073)

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AAHelpText(CrewEditorForm.detailsHint)
                    .padding(.bottom, AASpacing.xs)
                ForEach(CrewEditorForm.sections) { section in
                    Text(section.heading)
                        .font(.aaMono(AAType.body, weight: .bold))
                        .foregroundStyle(AAColor.accent)
                        .padding(.top, AASpacing.m)
                        .padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.fields) { f in
                            if f.isDate { dateRow(f) } else { textRow(f) }
                        }
                    }
                }
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.m)
        }
    }

    private func label(_ f: CrewEditorField) -> some View {
        Text(f.label)
            .font(.aaMono(AAType.small, weight: f.emphasised ? .bold : .regular))
            .foregroundStyle(f.emphasised ? AAColor.accent : AAColor.fg)
            .frame(width: 170, alignment: .leading)
    }

    private func text(_ key: String) -> Binding<String> {
        Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0 })
    }

    private func textRow(_ f: CrewEditorField) -> some View {
        HStack(spacing: AASpacing.s) {
            label(f)
            TextField(f.label, text: text(f.key))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit { Task { await save() } }
        }
    }

    private func dateRow(_ f: CrewEditorField) -> some View {
        let picker = Binding<NetDateTime?>(
            get: { pickers[f.key] },
            set: { v in
                pickers[f.key] = v
                if let v { draft[f.key] = v.civilDate.iso }       // one-way: picker → text (CREW-073)
            })
        let hint = CrewEditorForm.dateHint(draft[f.key] ?? "")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AASpacing.s) {
                label(f)
                OptionalDatePicker(value: picker)
                Spacer(minLength: AASpacing.s)
                TextField("yyyy-MM-dd", text: text(f.key))
                    .textFieldStyle(.roundedBorder)
                    .font(.aaMono(AAType.small))
                    .frame(width: 130)
                    .help(CrewEditorForm.dateTextHelp)
                    .onSubmit { Task { await save() } }
            }
            if let hint {
                Label(hint, systemImage: "exclamationmark.triangle.fill")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.Status.dueSoon)
                    .padding(.leading, 178)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: hint)
    }

    // MARK: Checklist (CREW-075) and Schedule (CREW-076)

    private var checklistTab: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            AAHelpText(CrewEditorForm.checklistHint)
            ChecklistBuilderView(host: .crew(memberID))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(AASpacing.m)
    }

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            AAHelpText(CrewEditorForm.scheduleHint)
            CrewScheduleBuilderView(crewID: memberID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(AASpacing.m)
    }
}
