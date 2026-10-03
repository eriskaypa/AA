// Spec: 09 §G CREW-070…076 (modal editor 640×720: heading, Details / Checklist / Schedule tabs, Cancel + default Save;
//       Details = a draft applied on Save only — text trimmed, the free-text date box is the source of truth with a
//       one-way picker → text sync; Checklist and Schedule edit the live member and save immediately), §6.4 (sheet with
//       a TabView, Esc = Cancel as a Mac superset, OptionalDatePicker + 130-pt text box per date row); DECISIONS 06
//       (commit by id, warn if the target vanished; a reload re-bases the draft and Save never writes a stale
//       untouched row back); DECISIONS 09 Q4 (inline hint for ambiguous date text);
//       ARCHITECTURE.md §7.5 (sheet contract), §7.7 (W-BUILD `ChecklistBuilderView(host: .crew(id))`).
import AppKit
import SwiftUI
import AACore

/// The editor's Details draft (a reference so the `dataReplaced` subscription can rebase it, DECISIONS 06 R1).
@MainActor @Observable
final class CrewEditorDraft {
    /// The text of every Details row.
    var values: [String: String] = [:]
    /// What the form was filled with (re-based after a reload) — Save writes untouched rows only when the stored value
    /// is still this one (`CrewEditorForm.apply(_:original:to:)`).
    var original: [String: String] = [:]
    var pickers: [String: NetDateTime] = [:]
    var heading = ""
    var subtitle = ""
    /// Shown above the form after the roster was reloaded under the open editor.
    var reloadNote: String?
    @ObservationIgnored var subscription: EventSubscription?

    func fill(from m: CrewMember?) {
        heading = CrewEditorForm.heading(fullName: m?.fullName ?? "")
        subtitle = m.map(CrewRoster.subtitle) ?? ""
        guard let m else { return }
        values = CrewEditorForm.draft(of: m)
        original = values
        syncPickers()
    }

    /// `store.dataReplaced`: untouched rows show the reloaded values, edited rows keep the user's text.
    func rebase(onto m: CrewMember?) {
        guard let m else {
            reloadNote = CrewEditorSheet.vanishedNote
            return
        }
        var v = values, o = original
        CrewEditorForm.rebase(draft: &v, original: &o, onto: m)
        values = v
        original = o
        heading = CrewEditorForm.heading(fullName: m.fullName)
        subtitle = CrewRoster.subtitle(m)
        syncPickers()
        reloadNote = CrewEditorSheet.reloadedNote
    }

    private func syncPickers() {
        var p: [String: NetDateTime] = [:]
        for f in CrewEditorForm.allFields where f.isDate {
            if let d = CrewEditorForm.pickerDate(values[f.key] ?? "") { p[f.key] = .calendarDate(d) }
        }
        pickers = p
    }
}

struct CrewEditorSheet: View {
    let memberID: UUID
    let initialTab: CrewEditorTab
    /// true = Save, false = Cancel / closed.
    var onClose: (Bool) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dialogs) private var dialogs
    @State private var tab: CrewEditorTab = .details
    @State private var draft = CrewEditorDraft()
    @State private var loaded = false
    @State private var finished = false

    static let reloadedNote = "The roster was reloaded while this editor was open. Fields you have not changed now show the reloaded values; Save writes only your changes."
    static let vanishedNote = "This crew member is no longer in the roster (it was deleted or the data was reloaded). Save will not write anything."
    static let vanishedMessage = "This crew member is no longer in the roster (it was deleted or the data was reloaded), so the changes could not be saved."

    /// The sheet is the 640-pt Windows editor; the Checklist tab grows to the 780-pt minimum of W-BUILD's builder
    /// (bulk pane + list) plus the tab inset, like the template / procedure / subtask builder sheets.
    static func width(for tab: CrewEditorTab) -> CGFloat { tab == .checklist ? 860 : 640 }

    init(memberID: UUID, initialTab: CrewEditorTab = .details, onClose: @escaping (Bool) -> Void = { _ in }) {
        self.memberID = memberID
        self.initialTab = initialTab
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            BuilderSheetHeader(title: draft.heading, subtitle: draft.subtitle.isEmpty ? nil : draft.subtitle,
                               symbol: "person.crop.rectangle")
                .padding(.horizontal, AASpacing.l)
                .padding(.top, AASpacing.l)
                .padding(.bottom, AASpacing.m)

            Picker("", selection: $tab) {
                Text("Details").tag(CrewEditorTab.details)
                Text("Checklist").tag(CrewEditorTab.checklist)
                Text("Schedule").tag(CrewEditorTab.schedule)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, AASpacing.m)

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
                    Label("Checklist and schedule changes are saved immediately.", systemImage: "info.circle")
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.muted)
                        .symbolRenderingMode(.hierarchical)
                        .lineLimit(2)
                }
                Spacer(minLength: AASpacing.s)
                Button("Cancel") { finish(saved: false) }
                    .keyboardShortcut(.cancelAction)
                    .frame(minWidth: 90)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .frame(minWidth: 90)
            }
            .padding(.horizontal, AASpacing.l)
            .frame(height: 44)
        }
        .frame(width: Self.width(for: tab), height: 720)
        .background(AAColor.bg, ignoresSafeAreaEdges: [])
        .aaSheet(.decision)
        .onAppear(perform: load)
        .onDisappear {
            draft.subscription?.cancel()
            draft.subscription = nil
            if !finished { finished = true; onClose(false) }
        }
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        tab = initialTab
        draft.fill(from: env.store.crewMember(id: memberID))
        // DECISIONS 06 R1: a reload while the editor is open must never let Save overwrite the newer data.
        let id = memberID
        draft.subscription = env.store.dataReplaced.subscribe { [weak d = draft, weak store = env.store] _ in
            d?.rebase(onto: store?.crewMember(id: id))
        }
    }

    private func save() async {
        guard let m = env.store.crewMember(id: memberID) else {
            await dialogs.warning(CrewEditorForm.windowTitle, Self.vanishedMessage)
            finish(saved: false)
            return
        }
        CrewEditorForm.apply(draft.values, original: draft.original, to: m)   // CREW-074: form order
        finish(saved: true)
    }

    private func finish(saved: Bool) {
        guard !finished else { return }
        finished = true
        draft.subscription?.cancel()
        draft.subscription = nil
        onClose(saved)
        dismiss()
    }

    // MARK: Details (CREW-071…073)

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let note = draft.reloadNote {
                    Label(note, systemImage: "arrow.triangle.2.circlepath")
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.fg)
                        .symbolRenderingMode(.hierarchical)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AASpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AAColor.Status.dueSoon.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                            .strokeBorder(AAColor.Status.dueSoon.opacity(0.5), lineWidth: 1))
                        .padding(.bottom, AASpacing.s)
                        .transition(.opacity)
                }
                AAHelpText(CrewEditorForm.detailsHint)
                    .padding(.bottom, AASpacing.xs)
                ForEach(CrewEditorForm.sections) { section in
                    Text(section.heading)
                        .font(.aaMono(AAType.small, weight: .bold))
                        .foregroundStyle(AAColor.accent)
                        .padding(.top, AASpacing.m)
                        .padding(.bottom, AASpacing.s)
                    VStack(alignment: .leading, spacing: AASpacing.s) {
                        ForEach(section.fields) { f in
                            if f.isDate { dateRow(f) } else { textRow(f) }
                        }
                    }
                }
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.m)
            .animation(.snappy, value: draft.reloadNote)
        }
    }

    private func label(_ f: CrewEditorField) -> some View {
        Text(f.label)
            .font(.aaMono(AAType.body, weight: f.emphasised ? .bold : .regular))
            .foregroundStyle(f.emphasised ? AAColor.accent : AAColor.muted)
            .lineLimit(1)
            .frame(width: Self.labelWidth, alignment: .trailing)
    }

    /// The Windows 170-px label column, widened so the monospaced `Sign-off date  (contract)` label fits one line.
    static let labelWidth: CGFloat = 212

    private func text(_ key: String) -> Binding<String> {
        let d = draft
        return Binding(get: { d.values[key] ?? "" }, set: { d.values[key] = $0 })
    }

    private func textRow(_ f: CrewEditorField) -> some View {
        HStack(spacing: AASpacing.s) {
            label(f)
            // Blank prompt: an empty value shows an empty box (as on Windows), never the label as a fake value.
            TextField(f.label, text: text(f.key), prompt: Text(""))
                .textFieldStyle(.roundedBorder)
                .font(.aaMono(AAType.body))
                .labelsHidden()
                .onSubmit { Task { await save() } }
        }
    }

    private func dateRow(_ f: CrewEditorField) -> some View {
        let d = draft
        let picker = Binding<NetDateTime?>(
            get: { d.pickers[f.key] },
            set: { v in
                d.pickers[f.key] = v
                if let v { d.values[f.key] = v.civilDate.iso }     // one-way: picker → text (CREW-073)
            })
        let hint = CrewEditorForm.dateHint(d.values[f.key] ?? "")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AASpacing.s) {
                label(f)
                OptionalDatePicker(value: picker)
                    .environment(\.locale, Locale(identifier: "en_CA"))   // ISO yyyy-MM-dd (DECISIONS, Stage V ruling)
                Spacer(minLength: AASpacing.s)
                TextField("yyyy-MM-dd", text: text(f.key))
                    .textFieldStyle(.roundedBorder)
                    .font(.aaMono(AAType.body))
                    .monospacedDigit()
                    .frame(width: 130)
                    .help(CrewEditorForm.dateTextHelp)
                    .onSubmit { Task { await save() } }
            }
            if let hint {
                Label(hint, systemImage: "exclamationmark.triangle.fill")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.Status.dueSoon)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.leading, Self.labelWidth + AASpacing.s)
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
