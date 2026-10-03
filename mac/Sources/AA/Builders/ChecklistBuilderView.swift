// Spec: 06 §A BUILD-001 (Bind: steps / owner name / log kind per host), BUILD-002…017, BUILD-018 (procedure host
//       window), BUILD-019 (crew Checklist tab), BUILD-063 (TemplateEditorWindow — saved-list host: detached ToSteps
//       clones, write-back on close), §8 D3 (write back only when changed; warn + "Save as new list" if the template
//       vanished; Deadline/Done shown disabled), R1 (re-resolve by id after reloads), 02 REPO-145, 03 T-KB-40/45
//       (⌘W / ⎋ close the sheet and persist; the quit pipeline flushes an open template editor through
//       EditorFlushCenter), DECISIONS 06; ARCHITECTURE.md §7.5 (sheet contract), §7.7 (embed contract).
import AppKit
import SwiftUI
import AACore

/// Which checklist the builder edits (ARCH §7.7).
enum ChecklistBuilderHost: Hashable { case procedure(UUID), crew(UUID), savedList(UUID) }

/// The builder's state: the host binding (re-resolved by id on every read), the detached steps of a saved-list host,
/// and the selection.
@MainActor @Observable
final class BuilderChecklistModel {
    let host: ChecklistBuilderHost
    @ObservationIgnored let store: AppStore
    /// Saved-list host: the template editor session (detached `ToSteps` clones, write-back — BUILD-063, D3).
    @ObservationIgnored let session: BuilderTemplateSession?
    /// The detached steps (observed copy of the session's steps, so the list re-renders).
    var detached: [ChecklistStep] = []
    var selection: Set<UUID> = []
    @ObservationIgnored private(set) var committed = false
    @ObservationIgnored private var flushToken: EditorFlushCenter.Token?
    @ObservationIgnored private(set) var engine: BuilderEngine<ChecklistStep>!

    init(host: ChecklistBuilderHost, store: AppStore) {
        self.host = host
        self.store = store
        if case .savedList(let id) = host {
            let s = BuilderTemplateSession(store: store, templateID: id)
            session = s
            detached = s.steps
        } else {
            session = nil
        }
        engine = makeEngine()
    }

    /// The template's name when the editor opened (for the vanished-template rescue, D3).
    var templateName: String { session?.openedName ?? "" }

    // MARK: Host resolution (ARCH §2.4)

    var procedure: Procedure? {
        if case .procedure(let id) = host { return store.item(id: id) as? Procedure }
        return nil
    }

    var crew: CrewMember? {
        if case .crew(let id) = host { return store.crewMember(id: id) }
        return nil
    }

    var template: ChecklistTemplate? {
        if case .savedList(let id) = host { return store.template(id: id) }
        return nil
    }

    var isSavedList: Bool { if case .savedList = host { return true } else { return false } }

    /// BUILD-001 owner name (log detail; "Save as list" default name).
    var ownerName: String {
        switch host {
        case .procedure: return procedure?.name ?? ""
        case .crew: return crew?.fullName ?? ""
        case .savedList: return session?.ownerName ?? ""
        }
    }

    /// Whether the edited checklist still exists (a saved-list host keeps working on its detached copy).
    var isOrphaned: Bool {
        switch host {
        case .procedure: return procedure == nil
        case .crew: return crew == nil
        case .savedList: return false
        }
    }

    var orphanWhat: String {
        switch host {
        case .procedure: return "This procedure"
        case .crew: return "This crew member"
        case .savedList: return "This saved list"
        }
    }

    private func makeEngine() -> BuilderEngine<ChecklistStep> {
        let logKind: String
        switch host {
        case .procedure: logKind = "Checklist step"
        case .crew: logKind = "Crew checklist item"
        case .savedList: logKind = "Saved-list item"
        }
        return BuilderEngine(store: store, kind: .steps, logKind: logKind, owner: { [unowned self] in self.ownerName },
                             read: { [unowned self] in self.readSteps() },
                             write: { [unowned self] in self.writeSteps($0) })
    }

    private func readSteps() -> [ChecklistStep]? {
        switch host {
        case .procedure: return procedure?.steps
        case .crew: return crew?.checklist
        case .savedList: return detached
        }
    }

    private func writeSteps(_ steps: [ChecklistStep]) {
        switch host {
        case .procedure: procedure?.steps = steps
        case .crew: crew?.checklist = steps
        case .savedList: detached = steps; session?.steps = steps
        }
    }

    // MARK: Saved-list write-back (BUILD-063, D3)

    /// Registers the template editor with the flush center so ⌘S / the quit pipeline write the edits back (T-KB-40).
    func attach(flush: EditorFlushCenter) {
        guard isSavedList, flushToken == nil else { return }
        flushToken = flush.register(container: nil, host: "w-build.template-editor") { [weak self] in
            self?.writeBack()
        }
    }

    func detach(flush: EditorFlushCenter) {
        if let t = flushToken { flush.unregister(t) }
        flushToken = nil
    }

    /// Writes the detached steps back into the template when they differ (DECISIONS 02 Q-12). Returns false when
    /// the template no longer exists.
    @discardableResult
    func writeBack() -> Bool { session?.writeBack() ?? true }

    /// D3 rescue: the edited items saved as a new list named after the vanished one.
    @discardableResult
    func saveAsNewList() -> ChecklistTemplate? { session?.saveAsNewList() }

    /// Closing: the one commit of the sheet (idempotent). Saved-list host → write back + Save (BUILD-063); other
    /// hosts → Flush (BUILD-018). Returns false when a saved-list template vanished (the caller warns).
    func finish(_ env: AppEnvironment) -> Bool {
        guard !committed else { return true }
        committed = true
        detach(flush: env.flush)
        env.flushAllEditors()
        if isSavedList {
            guard writeBack() else { return false }
            BuilderUI.save(env)
        } else {
            BuilderUI.flush(env)
        }
        return true
    }
}

/// The embeddable builder (BUILD-001…017): the crew editor's Checklist tab hosts `ChecklistBuilderView(host: .crew)`.
struct ChecklistBuilderView: View {
    let host: ChecklistBuilderHost
    @Environment(AppEnvironment.self) private var env
    @State private var model: BuilderChecklistModel?

    init(host: ChecklistBuilderHost) { self.host = host }

    var body: some View {
        Group {
            if let model {
                BuilderChecklistContent(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil {
                let m = BuilderChecklistModel(host: host, store: env.store)
                m.attach(flush: env.flush)
                model = m
            }
        }
        .onDisappear {
            // An embedded saved-list builder commits when it goes away (a sheet commits through its Close paths).
            if let model, model.isSavedList, !model.finish(env) {
                BuilderChecklistSheetActions.warnVanished(model, env: env, dialogs: nil)
            }
        }
    }
}

/// The builder panes bound to a model (shared by the view and the sheet).
struct BuilderChecklistContent: View {
    @Bindable var model: BuilderChecklistModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        if model.isOrphaned {
            BuilderOrphanState(what: model.orphanWhat)
        } else {
            BuilderItemsPane(engine: model.engine, strings: .checklist, display: { step in
                BuilderRowDisplay(id: step.id, title: step.title, struck: step.done,
                                  trailing: step.deadline.map { "due " + $0.format(.isoDate) } ?? "")
            }, edit: { id in
                await editStep(id)
            }, selection: $model.selection)
        }
    }

    /// BUILD-010: the step editor (detached overload for the saved-list host), then Flush and refresh.
    private func editStep(_ id: UUID) async {
        guard let step = model.engine.item(id: id) else { return }
        if model.isSavedList {
            let templateID: UUID? = { if case .savedList(let t) = model.host { return t } else { return nil } }()
            await dialogs.presentSheet(.closeType) { _ in
                ChecklistStepEditorSheet(step: step, savedListID: templateID) { _ in }
            }
        } else {
            await dialogs.presentSheet(.closeType) { _ in ChecklistStepEditorSheet(stepID: step.id) }
        }
        BuilderUI.flush(env)
    }
}

/// The modal builder (BUILD-018 procedure host window, BUILD-063 template editor, crew checklist as a sheet).
struct ChecklistBuilderSheet: View {
    let host: ChecklistBuilderHost
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismiss) private var dismiss
    @State private var model: BuilderChecklistModel?

    init(host: ChecklistBuilderHost) { self.host = host }

    var body: some View {
        VStack(spacing: 0) {
            if let model {
                BuilderSheetHeader(title: header(model), subtitle: help, symbol: symbol)
                    .padding(.horizontal, AASpacing.l)
                    .padding(.top, AASpacing.l)
                    .padding(.bottom, AASpacing.m)
                Divider()
                BuilderChecklistContent(model: model)
                Divider()
                footer(model)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 780, idealWidth: 820, maxWidth: .infinity, minHeight: 560, idealHeight: 640, maxHeight: .infinity)
        .background(AAColor.bg)
        .onAppear {
            if model == nil {
                let m = BuilderChecklistModel(host: host, store: env.store)
                m.attach(flush: env.flush)
                model = m
            }
        }
        .onDisappear {
            // Any other way the sheet goes away still commits (closing is saving).
            if let model, !model.finish(env) { BuilderChecklistSheetActions.warnVanished(model, env: env, dialogs: nil) }
        }
        .aaSheet(.closeType, onClose: {
            if let model, !model.finish(env) { BuilderChecklistSheetActions.warnVanished(model, env: env, dialogs: nil) }
        })
    }

    private var symbol: String {
        switch host {
        case .procedure: return "hammer"
        case .crew: return "person.text.rectangle"
        case .savedList: return "list.bullet.rectangle"
        }
    }

    private func header(_ m: BuilderChecklistModel) -> String {
        switch host {
        case .procedure: return "Checklist builder — \(m.ownerName)"
        case .crew: return "Checklist — \(m.ownerName)"
        case .savedList:
            let name = m.ownerName
            return "Edit saved list — \(name.isEmpty ? "(unnamed)" : name)"
        }
    }

    private var help: String {
        switch host {
        case .procedure:
            return "Type one item per line on the left and click 'Add all'. Use the right panel to reorder, fully edit "
                + "(deadline, notes, files) and delete items. Save the list to reuse it anywhere. Close to save."
        case .crew:
            return "This crew member's personal checklist. Give an item a due date (in its full editor) and it shows in "
                + "the 📌 due-dates window and the Calendar. Checklist changes save immediately — they are not undone by Cancel."
        case .savedList:
            return "Edit the items in this saved list (title, duration, notes & files). Deadlines, working-ranges and "
                + "done aren't stored in a saved list — they're set when you apply it. Close to save."
        }
    }

    private func footer(_ m: BuilderChecklistModel) -> some View {
        HStack {
            if m.isSavedList {
                Label("Changes are written back to the saved list when you close.", systemImage: "info.circle")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
            }
            Spacer()
            Button("Close") {
                Task { @MainActor in
                    if !m.finish(env) {
                        await BuilderChecklistSheetActions.resolveVanished(m, env: env, dialogs: dialogs)
                    }
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .aaProminent()
            .frame(minWidth: 80)
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
    }
}

/// D3: what happens when the saved list being edited was deleted meanwhile.
@MainActor enum BuilderChecklistSheetActions {
    static let vanishedTitle = "Saved list not found"
    static func vanishedMessage(_ name: String) -> String {
        "The saved list '\(name)' was deleted while you were editing it, so your changes could not be written back. "
            + "Save them as a new list?"
    }

    /// Interactive form (Close button): ask in the sheet before it goes away.
    static func resolveVanished(_ m: BuilderChecklistModel, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard !m.detached.isEmpty else { return }
        let save = await dialogs.confirm(vanishedTitle, vanishedMessage(m.templateName), confirm: "Save as New List",
                                         cancel: "Discard Changes")
        if save {
            m.saveAsNewList()
            BuilderUI.save(env)
        }
    }

    /// Non-interactive close paths (⌘W / ⎋ / window teardown): ask on the window that becomes key afterwards.
    static func warnVanished(_ m: BuilderChecklistModel, env: AppEnvironment, dialogs: DialogPresenter?) {
        guard !m.detached.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let presenter = dialogs ?? NSApp.keyWindow.flatMap { SceneOpener.shared.dialogs(of: $0) } ?? env.mainDialogs
            await resolveVanished(m, env: env, dialogs: presenter)
        }
    }
}
