// Spec: 04 HIER-070 (Components: + Add prompt, Remove without confirmation/Trash/log, Edit… / double-click, two-column
//       list Name / Notes), HIER-071 (component editor: live title, Name, Short notes, the full container editor, Close;
//       flush + FlushIfDirty on close), HIER-072 (Related Procedures: Pick… replace semantics, + New procedure),
//       HIER-073 (Related Tasks), HIER-140 (Save after each), §6.5/§6.6; 02 REPO-023…026; 07 VIEW-212 rows 11–12 and
//       VIEW-215 (selection order, normalised on OK); 03 §6.5.1.10 (components list role: Remove, ↩ = Edit…).
import AppKit
import SwiftUI
import AACore

struct HierEquipmentSpecifics: View {
    let equipment: Equipment
    let model: HierPageModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var selectedComponent: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AASpacing.l) {
                components
                linkSection(title: HierText.relatedProcedures, ids: equipment.procedureIds,
                            newTitle: HierText.newProcedureButton, newHelp: HierText.newProcedureHelp,
                            pick: { await pickProcedures() }, create: { await newProcedure() })
                linkSection(title: HierText.relatedTasks, ids: equipment.taskIds,
                            newTitle: HierText.newTaskButton, newHelp: HierText.newTaskHelp,
                            pick: { await pickTasks() }, create: { await newTask() })
            }
            .padding(AASpacing.l)
        }
        .onAppear { revealChild() }
        .onChange(of: model.pendingChildID) { _, _ in revealChild() }
    }

    /// A navigation that names a component selects its row (DECISIONS 02 Q-11).
    private func revealChild() {
        guard let child = model.pendingChildID else { return }
        model.pendingChildID = nil
        if let c = HierPageOps.component(of: equipment, id: child) { selectedComponent = c.id }
    }

    // MARK: Components (HIER-070)

    private var components: some View {
        HierBlock(title: HierText.components, symbol: "gearshape.2") {
            HStack(spacing: AASpacing.s) {
                Button(HierText.add) { Task { await addComponent() } }
                Button(HierText.remove) { removeComponent() }
                    .disabled(selectedComponent == nil)
                Button(HierText.edit) { editComponent(selectedComponent) }
                    .disabled(selectedComponent == nil)
                    .help(HierText.componentEditHelp)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } content: {
            Table(equipment.components, selection: $selectedComponent) {
                TableColumn(HierText.nameColumn) { (c: Component) in
                    Text(c.name).lineLimit(1).truncationMode(.tail)
                }
                .width(min: 120, ideal: 260)
                TableColumn(HierText.notesColumn) { (c: Component) in
                    Text(c.notes).foregroundStyle(AAColor.muted).lineLimit(1).truncationMode(.tail)
                }
                .width(min: 120, ideal: 360)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button(HierText.edit) { editComponent(id) }
                    Button(HierText.remove, role: .destructive) { selectedComponent = id; removeComponent() }
                }
            } primaryAction: { ids in
                editComponent(ids.first)
            }
            .overlay {
                if equipment.components.isEmpty {
                    Text("No components yet.").font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 170)
            .aaListCommands(ListCommands(role: .components, selectionCount: selectedComponent == nil ? 0 : 1,
                                         deleteTitle: HierText.remove,
                                         delete: selectedComponent == nil ? nil : { removeComponent() },
                                         deleteConfirms: false,
                                         primary: selectedComponent == nil ? nil : { editComponent(selectedComponent) }))
        }
    }

    private func addComponent() async {
        guard let name = await HierDialogs.prompt(dialogs, title: HierText.newComponentTitle, label: HierText.nameLabel),
              let c = HierPageOps.addComponent(store: env.store, named: name, to: equipment) else { return }
        HierPersist.save(env, dialogs: dialogs)
        selectedComponent = c.id
    }

    private func removeComponent() {
        guard let id = selectedComponent, let c = equipment.components.first(where: { $0.id == id }) else { return }
        env.flushAllEditors()
        env.store.removeComponent(c, from: equipment)
        HierPersist.save(env, dialogs: dialogs)
        selectedComponent = nil
    }

    private func editComponent(_ id: UUID?) {
        guard let id else { return }
        let presenter = dialogs
        let equipmentID = equipment.id
        Task { @MainActor in
            await presenter.presentSheet(.closeType) { dismiss in
                HierComponentEditorSheet(equipmentID: equipmentID, componentID: id, close: dismiss)
            }
        }
    }

    // MARK: Linked procedures / tasks (HIER-072, HIER-073)

    private func linkSection(title: String, ids: [UUID], newTitle: String, newHelp: String,
                             pick: @escaping () async -> Void, create: @escaping () async -> Void) -> some View {
        HierBlock(title: title, symbol: "link") {
            HStack(spacing: AASpacing.s) {
                Button(HierText.pick) { Task { await pick() } }
                Button(newTitle) { Task { await create() } }.help(newHelp)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } content: {
            let rows = HierLinkPicker.labels(store: env.store, ids: ids)
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text("Nothing linked yet.")
                        .font(.aaMono(AAType.small))
                        .foregroundStyle(AAColor.muted)
                        .padding(AASpacing.s)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack {
                            Text(row.label)
                                .foregroundStyle(row.exists ? AAColor.fg : AAColor.muted)
                                .italic(!row.exists)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AASpacing.s)
                        .padding(.vertical, 5)
                        .background(i % 2 == 1 ? AAColor.hover.opacity(0.5) : Color.clear)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control).strokeBorder(AAColor.border, lineWidth: 1))
        }
    }

    private func pickProcedures() async {
        let candidates = HierLinkPicker.procedureCandidates(store: env.store)
        let request = ItemPickerRequest(prompt: HierText.pickProcedures,
                                        rows: candidates.map { ItemPickerRow(display: $0.display, tag: $0.id) },
                                        preselected: equipment.procedureIds, mode: .multi)
        guard let picked = await dialogs.pickItems(request) else { return }
        HierPageOps.replaceProcedureLinks(store: env.store, picked, on: equipment)
        HierPersist.save(env, dialogs: dialogs)
    }

    private func pickTasks() async {
        let candidates = HierLinkPicker.taskCandidates(store: env.store)
        let request = ItemPickerRequest(prompt: HierText.pickTasks,
                                        rows: candidates.map { ItemPickerRow(display: $0.display, tag: $0.id) },
                                        preselected: equipment.taskIds, mode: .multi)
        guard let picked = await dialogs.pickItems(request) else { return }
        HierPageOps.replaceTaskLinks(store: env.store, picked, on: equipment)
        HierPersist.save(env, dialogs: dialogs)
    }

    private func newProcedure() async {
        guard let name = await HierDialogs.prompt(dialogs, title: HierText.newProcedureTitle, label: HierText.nameLabel),
              HierPageOps.newLinkedProcedure(store: env.store, named: name, for: equipment) != nil else { return }
        HierPersist.save(env, dialogs: dialogs)
    }

    private func newTask() async {
        guard let name = await HierDialogs.prompt(dialogs, title: HierText.newTaskTitle, label: HierText.nameLabel),
              HierPageOps.newLinkedTask(store: env.store, named: name, for: equipment) != nil else { return }
        HierPersist.save(env, dialogs: dialogs)
    }
}

/// HIER-071 component editor (a large close-type sheet). Commits by id: a component that vanished in a reload shows
/// a notice instead of editing a detached object.
struct HierComponentEditorSheet: View {
    let equipmentID: UUID
    let componentID: UUID
    let close: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    private var resolved: (component: Component, equipment: Equipment)? { env.store.component(id: componentID) }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            if let component = resolved?.component {
                Text(HierText.componentEditorTitle(component.name))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AASpacing.s, verticalSpacing: 6) {
                    GridRow {
                        Text(HierText.nameLabel).foregroundStyle(AAColor.muted).frame(width: 100, alignment: .trailing)
                        TextField("", text: Binding(get: { component.name }, set: { v in
                            if !Ordinal.equals(component.name, v) { component.name = v; env.store.markDirty() }
                        }))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(HierText.shortNotesLabel).foregroundStyle(AAColor.muted).frame(width: 100, alignment: .trailing)
                        TextField("", text: Binding(get: { component.notes }, set: { v in
                            if !Ordinal.equals(component.notes, v) { component.notes = v; env.store.markDirty() }
                        }))
                        .textFieldStyle(.roundedBorder)
                        .help(HierText.shortNotesHelp)
                    }
                }
                ContainerEditorView(container: component.container,
                                    context: ContainerEditorContext(title: component.name, host: .component(component.id)))
                    .id(ObjectIdentifier(component.container))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AAEmptyState(title: "Component not found", symbol: "questionmark.square.dashed",
                             message: HierText.orphaned)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button(HierText.close) { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AASpacing.l)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 700)
        .aaSheet(.closeType, onClose: { flush() })
    }

    private func flush() {
        env.flushAllEditors()
        do { try env.store.flushIfDirty() } catch {
            let message = error.localizedDescription
            let presenter = env.mainDialogs
            Task { @MainActor in await presenter.error(HierText.saveFailedTitle, message) }
        }
    }

    private func finish() {
        flush()
        close()
    }
}
