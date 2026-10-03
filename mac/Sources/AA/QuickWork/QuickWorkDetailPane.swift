// Spec: 08 §2.2 QUICK-070…081 (empty state, title row Pin / Delete / Open in main window, header fields with model-
//       based WorkRange coercion, Status / Recurrence, children builder: bulk add, live list with strike-through,
//       + child, Edit…, ↑ ↓, Delete, Buckets…, Open full builder…, Save as list…, Load a saved list…, children context
//       menu), §6.2-B (TextEditor in monospaced font, List with multi-select + `.onMove`, double-click = Edit…, name
//       edits write through without rebuilding the list), Q-13 (live Status after a batch done); DECISIONS 08 OQ-5
//       (explicit "no date" state), OQ-10 (friendly Status labels, same integers); 06 BUILD-102; ARCHITECTURE.md §2.4.
import AppKit
import SwiftUI
import AACore

struct QuickWorkDetailPane: View {
    @Bindable var model: QuickWorkModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        QuickWorkPanelBox {
            HStack(spacing: 6) {
                Image(systemName: "hammer").symbolRenderingMode(.hierarchical).foregroundStyle(AAColor.muted)
                Text("Builder").font(.aaMono(AAType.body, weight: .semibold)).foregroundStyle(AAColor.accent)
            }
        } content: {
            if let item = model.currentItem {
                ScrollView {
                    QuickWorkDetailContent(model: model, item: item)
                        .id(model.detailToken)
                        .padding(AASpacing.l)
                }
            } else {
                // QUICK-070: the spec's empty-detail sentence, as the empty state's next step.
                AAEmptyState(title: "Nothing selected", symbol: "hammer", message: QuickWorkText.detailEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct QuickWorkDetailContent: View {
    @Bindable var model: QuickWorkModel
    let item: HierarchyItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow.padding(.bottom, 10)
            fields
            Divider().padding(.vertical, 10)
            QuickWorkChildrenBuilder(model: model, item: item)
        }
    }

    // MARK: Title row (QUICK-071, QUICK-072)

    private var titleRow: some View {
        let pinned = model.isPinned(item.id)
        return HStack(spacing: 8) {
            Text(item is TaskItem ? "Task" : "Procedure")
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
            Spacer(minLength: AASpacing.s)
            Button { QuickWorkFlows.togglePin(item.id, env: env, dialogs: dialogs, model: model) } label: {
                Label(pinned ? QuickWorkText.unpin : QuickWorkText.pin, systemImage: pinned ? "pin.slash" : "pin")
                    .fontWeight(.bold)
            }
            .help(pinned ? QuickWorkText.unpinDetailHelp : QuickWorkText.pinHelp)
            Button(role: .destructive) {
                Task { await QuickWorkFlows.delete(item, env: env, dialogs: dialogs, model: model) }
            } label: { Label(QuickWorkText.delete, systemImage: "trash") }
                .help("Move this item and everything under it to the Trash.")
            Button { env.navigator.navigate(to: item.id) } label: {
                Label(QuickWorkText.openInMain, systemImage: "arrow.up.forward.app")
            }
            .help("Show this item in the main window.")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .symbolRenderingMode(.hierarchical)
    }

    // MARK: Header fields (QUICK-074)

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 7) {
            GridRow {
                label("Name:")
                TextField("", text: Binding(get: { item.name },
                                            set: { QuickWorkActions.setName(item, $0, store: env.store) }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.refresh() }
            }
            GridRow {
                label("Deadline:")
                OptionalDatePicker(value: Binding(get: { QuickWorkRows.deadline(item) },
                                                  set: { QuickWorkActions.setDeadline(item, picked: $0, store: env.store) }))
                    .help(QuickWorkText.deadlineHelp)
                    .gridColumnAlignment(.leading)
            }
            if let t = item as? TaskItem {
                GridRow {
                    label("Range start:")
                    OptionalDatePicker(value: Binding(get: { t.rangeStart },
                                                      set: { QuickWorkActions.setRangeStart(t, picked: $0, store: env.store) }))
                        .help(QuickWorkText.rangeStartHelp)
                }
            }
            GridRow {
                label("Status:")
                Picker("", selection: Binding(get: { QuickWorkRows.status(item) },
                                              set: { QuickWorkActions.setStatus(item, $0, store: env.store) })) {
                    ForEach(WorkStatus.allStatuses, id: \.self) { Text($0.friendlyLabel).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .leading)
            }
            GridRow {
                label("Recurrence:")
                Picker("", selection: Binding(get: { QuickWorkRows.recurrence(item) },
                                              set: { QuickWorkActions.setRecurrence(item, $0, store: env.store) })) {
                    ForEach(RecurrenceKind.allKinds, id: \.self) { Text($0.friendlyLabel).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .leading)
            }
        }
        .onDisappear { model.refresh() }
    }

    /// V-DESIGN rule 2/6: aaMono 13, muted, trailing-aligned in a fixed label column.
    private func label(_ s: String) -> some View {
        Text(s).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted).frame(width: 100, alignment: .trailing)
    }
}

// MARK: - Children builder (QUICK-075…081)

struct QuickWorkChildrenBuilder: View {
    @Bindable var model: QuickWorkModel
    let item: HierarchyItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var bulk = ""
    @State private var replace = false
    @State private var selection = Set<UUID>()

    private var kind: QuickWorkChildKind { QuickWorkActions.childKind(of: item) ?? .subtask }
    private var children: [QuickWorkChild] { QuickWorkActions.children(of: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(QuickWorkText.builderHeading(noun: kind.noun))
                .font(.aaMono(AAType.body, weight: .semibold))
                .foregroundStyle(AAColor.accent)
            Text(QuickWorkText.bulkLabel(noun: kind.noun)).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
            TextEditor(text: $bulk)
                .font(.aaMono(AAType.body))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 96)
                .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control))
                .overlay(RoundedRectangle(cornerRadius: AARadius.control).strokeBorder(AAColor.border, lineWidth: 1))
            HStack(spacing: 10) {
                Button(QuickWorkText.addAll) { addAll() }
                    .aaProminent()
                    .disabled(QuickWorkActions.bulkLines(bulk).isEmpty)
                Toggle(QuickWorkText.replaceExisting, isOn: $replace).toggleStyle(.checkbox)
                Spacer()
                Text(progressText).font(.aaMono(AAType.caption)).monospacedDigit().foregroundStyle(AAColor.muted)
            }
            .padding(.bottom, 4)
            childList
            buttons
        }
    }

    private var progressText: String {
        let c = children
        guard !c.isEmpty else { return "" }
        return "\(c.filter(\.isDone).count)/\(c.count) done"
    }

    // MARK: List (QUICK-076, QUICK-079)

    private var childList: some View {
        List(selection: $selection) {
            ForEach(children) { c in
                HStack(spacing: 8) {
                    Image(systemName: c.isDone ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(c.isDone ? AAColor.Status.ok : AAColor.muted)
                    Text(c.title.isEmpty ? " " : c.title)
                        .font(.aaMono(AAType.body))
                        .strikethrough(c.isDone)
                        .foregroundStyle(c.isDone ? AAColor.muted : AAColor.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, AASpacing.xs)
                .frame(minHeight: 22)
                .tag(c.id)
            }
            .onMove { from, to in
                QuickWorkActions.moveChildren(fromOffsets: from, toOffset: to, in: item, store: env.store)
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds(.disabled)
        .frame(height: 300)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                let models = ids.compactMap { QuickWorkActions.childModel($0, of: item) }
                Button { QuickWorkFlows.markDone(models, done: true, env: env, dialogs: dialogs, model: model) } label: {
                    Label(QuickWorkText.markDone, systemImage: "checkmark.circle")
                }
                Button { QuickWorkFlows.markDone(models, done: false, env: env, dialogs: dialogs, model: model) } label: {
                    Label(QuickWorkText.markNotDone, systemImage: "circle")
                }
                Divider()
                Button { Task { await QuickWorkFlows.setDeadline(models, env: env, dialogs: dialogs, model: model) } } label: {
                    Label(QuickWorkText.setDeadline, systemImage: "calendar.badge.clock")
                }
                .help(QuickWorkText.setDeadlineHelp)
            }
        } primaryAction: { ids in
            if let id = firstSelected(in: ids) { edit(id) }
        }
        .overlay {
            if children.isEmpty {
                AAEmptyState(title: "No \(kind.noun)s yet", symbol: "checklist",
                             message: "Add one below or paste a list above.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AAColor.panel)
                    .allowsHitTesting(false)
            }
        }
        .aaListCommands(ListCommands(role: .quickWorkChildren, selectionCount: selection.count,
                                     deleteTitle: "Delete\u{2026}",
                                     delete: selection.isEmpty ? nil : { deleteSelected() },
                                     canMoveUp: canMove(up: true), canMoveDown: canMove(up: false),
                                     move: { move(up: $0 == .up) },
                                     primary: { if let id = firstSelected(in: selection) { edit(id) } }))
    }

    // MARK: Buttons (QUICK-077)

    private var buttons: some View {
        QuickWorkFlowLayout(spacing: 6) {
            Button(QuickWorkText.addChild(noun: kind.noun)) {
                Task {
                    if let id = await QuickWorkFlows.addChild(to: item, env: env, dialogs: dialogs, model: model) {
                        selection = [id]
                    }
                }
            }
            Button(QuickWorkText.edit) { if let id = firstSelected(in: selection) { edit(id) } }
                .disabled(selection.isEmpty)
            Button { move(up: true) } label: { Image(systemName: "arrow.up") }
                .help("Move the selected \(kind.noun)s up")
                .disabled(!canMove(up: true))
            Button { move(up: false) } label: { Image(systemName: "arrow.down") }
                .help("Move the selected \(kind.noun)s down")
                .disabled(!canMove(up: false))
            Button(QuickWorkText.deleteChildren) { deleteSelected() }
                .disabled(selection.isEmpty)
            Button { Task { await QuickWorkFlows.childBuckets(firstSelected(in: selection), of: item, env: env, dialogs: dialogs, model: model) } } label: {
                Label(QuickWorkText.buckets, systemImage: "tray.2")
            }
            Button(QuickWorkText.openFullBuilder) {
                Task { await QuickWorkFlows.openFullBuilder(item, env: env, dialogs: dialogs, model: model) }
            }
            Button { Task { await QuickWorkFlows.saveAsList(item, env: env, dialogs: dialogs) } } label: {
                Label(QuickWorkText.saveAsList, systemImage: "square.and.arrow.down")
            }
            Button { Task { await QuickWorkFlows.loadSavedList(item, env: env, dialogs: dialogs, model: model) } } label: {
                Label(QuickWorkText.loadSavedList, systemImage: "list.clipboard")
            }
        }
        .controlSize(.small)
        .padding(.top, 6)
    }

    // MARK: Helpers

    /// The first selected child in list order (`list.SelectedItem`).
    private func firstSelected(in ids: Set<UUID>) -> UUID? { children.first { ids.contains($0.id) }?.id }

    private func canMove(up: Bool) -> Bool {
        let idx = Set(children.indices.filter { selection.contains(children[$0].id) })
        return QuickWorkActions.moved(Array(children.indices), selected: idx, up: up) != nil
    }

    private func move(up: Bool) {
        withAnimation(.snappy) {
            _ = QuickWorkActions.moveChildren(selection, in: item, up: up, store: env.store)
        }
    }

    private func edit(_ id: UUID) {
        Task { await QuickWorkFlows.editChild(id, of: item, env: env, dialogs: dialogs, model: model) }
    }

    private func deleteSelected() {
        let ids = selection
        Task {
            if await QuickWorkFlows.deleteChildren(ids, of: item, env: env, dialogs: dialogs, model: model) {
                selection.removeAll()
            }
        }
    }

    /// QUICK-075 `Add all`; the text box clears and the Replace tick stays until the pane is rebuilt.
    private func addAll() {
        let n = QuickWorkActions.bulkAdd(bulk, replace: replace, to: item, store: env.store)
        guard n > 0 else { return }
        bulk = ""
        QuickWorkPersist.save(env, dialogs: dialogs)
        model.refresh()
    }
}
