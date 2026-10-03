// Spec: 07 §3.2 VIEW-040…056 (Task Board: header, four status columns with counts, every task and nested subtask as a
//       card, search, hide done, drag a card to change status, visible multi-selection per column, double-click
//       editor, context menu, open all files, delete, + New task, + From saved list, refresh triggers), §7.2 (Mac
//       structure), DECISIONS 02 Q-4 / 07 Q-01 (delete through the Trash), 07 Q-03 (logged creation), W-01 / W-04
//       fixes, 03 T-KB-06 (⌘⌫ "Delete Task" on a focused column), ARCHITECTURE.md §7.6, §9.4 (internal drag type
//       `com.eriskay.aa.task-ref`, files opened through AttachmentOpener).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

@MainActor @Observable
final class BoardPageModel {
    var query = ""
    var hideDone = false
    /// Selected card ids per column (VIEW-048: per-column extended selection).
    var selection: [Int: Set<UUID>] = [:]
    /// Anchor of a ⇧-click range per column.
    @ObservationIgnored var anchors: [Int: UUID] = [:]
    let cards = CalLive<[BoardCard]>([])
    @ObservationIgnored private(set) weak var store: AppStore?

    func attach(_ store: AppStore) {
        if self.store === store { cards.refresh(); return }
        self.store = store
        cards.bind { [weak self] in
            guard let self, let store = self.store else { return [] }
            return BoardModel.filter(BoardModel.flatten(store.data), query: self.query, hideDone: self.hideDone)
        }
    }

    func cards(in status: WorkStatus) -> [BoardCard] { BoardModel.cards(cards.value, in: status) }

    func selected(_ status: WorkStatus) -> Set<UUID> { selection[status.rawValue] ?? [] }

    /// Click (plain → only this card; ⌘ → toggle; ⇧ → range from the anchor) inside one column.
    func click(_ card: BoardCard, in status: WorkStatus, modifiers: EventModifiers) {
        let col = status.rawValue
        var sel = selection[col] ?? []
        if modifiers.contains(.command) {
            if sel.contains(card.id) { sel.remove(card.id) } else { sel.insert(card.id) }
            anchors[col] = card.id
        } else if modifiers.contains(.shift), let anchor = anchors[col] {
            let ids = cards(in: status).map(\.id)
            if let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: card.id) {
                sel = Set(ids[min(a, b)...max(a, b)])
            } else {
                sel = [card.id]
            }
        } else {
            sel = [card.id]
            anchors[col] = card.id
        }
        selection = [col: sel]
    }

    /// §2.5 right-click rule: an unselected card becomes the only selection; a selected one keeps the set.
    func targets(for card: BoardCard, in status: WorkStatus) -> [TaskItem] {
        let col = status.rawValue
        let sel = selection[col] ?? []
        if sel.contains(card.id) {
            return cards(in: status).filter { sel.contains($0.id) }.map(\.task)
        }
        selection = [col: [card.id]]
        anchors[col] = card.id
        return [card.task]
    }

    func selectAll(_ status: WorkStatus) {
        selection = [status.rawValue: Set(cards(in: status).map(\.id))]
    }
}

struct BoardTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model = BoardPageModel()
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CalPageHeader(title: BoardModel.title, subtitle: BoardModel.hint, symbol: "rectangle.split.3x1") {
                headerControls
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(BoardModel.columns) { spec in
                    BoardColumnView(spec: spec, model: model, actions: actions)
                }
            }
            .padding(AASpacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AAColor.bg)
        .onAppear { model.attach(env.store) }
        .onChange(of: env.store.generation) { _, _ in
            model.selection = [:]
            model.attach(env.store)
        }
        .aaSectionCommands(.board, SectionCommands(focusSearchField: { findFocused = true },
                                                   searchFieldIsFocused: findFocused))
    }

    private var headerControls: some View {
        HStack(spacing: AASpacing.s) {
            Text(BoardModel.findLabel).font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted).fixedSize()
            AASearchField(text: $model.query, prompt: "Find")
                .frame(width: 180)
                .focused($findFocused)
            Toggle(BoardModel.hideDoneLabel, isOn: $model.hideDone)
                .toggleStyle(.checkbox)
                .fixedSize()
            Button {
                Task { @MainActor in await CalPersist.addFromSavedList(env: env, dialogs: dialogs) }
            } label: {
                Label(BoardModel.fromSavedListTitle, systemImage: "list.bullet.rectangle")
            }
            .help(BoardModel.fromSavedListHelp)
            .fixedSize()
            Button {
                Task { @MainActor in await actions.newTask() }
            } label: {
                Text(BoardModel.newTaskTitle)
            }
            .aaProminent()
            .fixedSize()
        }
    }

    private var actions: BoardActions { BoardActions(env: env, dialogs: dialogs, model: model) }
}

// MARK: Actions (the store is resolved at action time — W-01)

@MainActor
struct BoardActions {
    let env: AppEnvironment
    let dialogs: DialogPresenter
    let model: BoardPageModel

    /// VIEW-053: "New Task" / "Name:"; a non-blank name (raw) → a To Do task, logged, saved.
    func newTask() async {
        let r = await dialogs.prompt(TextPromptRequest(title: BoardModel.newTaskPromptTitle,
                                                       prompt: BoardModel.newTaskPromptLabel))
        guard case .ok(let text) = r, let t = BoardModel.createTask(named: text, store: env.store) else { return }
        CalPersist.saveNow(env, dialogs)
        model.cards.refresh()
        model.selection = [WorkStatus.todo.rawValue: [t.id]]
    }

    /// VIEW-047: a dropped card takes the column's status; saved immediately.
    func drop(taskID: UUID, on status: WorkStatus) -> Bool {
        guard let t = env.store.task(id: taskID) else { return false }
        if BoardModel.setStatus(t, status) {
            CalPersist.saveNow(env, dialogs)
            withAnimation(.snappy) { model.cards.refresh() }
            model.selection = [status.rawValue: [taskID]]
        }
        return true
    }

    /// VIEW-049: the subtask editor, then flush and refresh.
    func edit(_ taskID: UUID) {
        Task { @MainActor in
            await CalPersist.editTask(taskID, env: env, dialogs: dialogs)
            model.cards.refresh()
        }
    }

    /// VIEW-051: the task's own files; > 15 asks first; unreachable targets are skipped silently.
    func openAllFiles(_ taskID: UUID) async {
        guard let t = env.store.task(id: taskID) else { return }
        let files = t.container.files
        if files.isEmpty {
            await dialogs.info(BoardModel.noFilesTitle, BoardModel.noFilesMessage)
            return
        }
        if BoardModel.openAllNeedsConfirmation(fileCount: files.count) {
            let ok = await dialogs.confirm(BoardModel.noFilesTitle,
                                           BoardModel.openAllConfirmation(count: files.count, name: t.name),
                                           confirm: "Open All")
            guard ok else { return }
        }
        for f in files {
            _ = AttachmentOpener.open(stored: f.path, isLink: f.isLink, dataStore: env.dataStore)
        }
    }

    /// VIEW-052 + DECISIONS 02 Q-4: same confirmation text, then the card goes to the Trash (⌘Z restores it). After
    /// the confirmation the open editors are flushed first (so the Trash payload holds the last edits), the task is
    /// re-resolved and trashed, and its detached item window is closed — the same steps as the batch path
    /// (`BatchActions.confirmAndTrash`).
    func delete(_ taskID: UUID) async {
        guard let t = env.store.task(id: taskID) else { return }
        let ok = await dialogs.confirm(BoardModel.confirmTitle, BoardModel.deleteMessage(t), confirm: "Move to Trash",
                                       destructive: true, defaultIsCancel: true)
        guard ok else { return }
        env.flushAllEditors()
        guard let live = env.store.task(id: taskID) else { return }
        let name = live.name
        guard BoardModel.moveToTrash(live, store: env.store) else { return }
        CalPersist.saveNow(env, dialogs)
        env.store.detachedItemIDs.remove(taskID)
        SceneOpener.shared.itemWindow(taskID)?.close()
        env.status.post(BatchDelete.statusAfterDelete(count: 1, firstName: name))
        env.refreshAfterTrashChange()
        model.selection = [:]
        withAnimation(.snappy) { model.cards.refresh() }
    }

    /// ⌘⌫ with several cards selected in a column: the shared batch delete (one undoable batch).
    func deleteMany(_ ids: [UUID]) async {
        let items: [AnyObject] = ids.compactMap { env.store.task(id: $0) }
        let n = await BatchActions.confirmAndTrash(items, env: env, dialogs: dialogs)
        if n > 0 { model.selection = [:] }
        model.cards.refresh()
    }
}

// MARK: Column (VIEW-041, VIEW-046, VIEW-047)

private struct BoardColumnView: View {
    let spec: BoardColumnSpec
    @Bindable var model: BoardPageModel
    let actions: BoardActions
    @State private var targeted = false

    var body: some View {
        let color = calHexColor(spec.colorHex)
        let cards = model.cards(in: spec.status)
        let selected = model.selected(spec.status)
        VStack(spacing: 0) {
            HStack {
                Text(spec.title)
                    .font(.aaMono(14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(cards.count)")
                    .font(.aaMono(13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        BoardCardView(card: card, color: color, selected: selected.contains(card.id))
                            .onTapGesture(count: 2) { actions.edit(card.id) }
                            .onTapGesture { model.click(card, in: spec.status, modifiers: calCurrentModifiers()) }
                            .onDrag {
                                CalDragSession.shared.taskID = card.id
                                return NSItemProvider.calPayload(card.id.netString, type: .aaTaskRef)
                            } preview: {
                                BoardCardView(card: card, color: color, selected: true)
                                    .frame(width: 240)
                            }
                            .contextMenu { menu(for: card) }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(6)
                .animation(.snappy, value: cards.map(\.id))
            }
            // VIEW-041 padding 6 on all sides: with "Show scroll bars: Always" a legacy scroller gutter (~16 pt) was
            // added on the right of every column, even one that does not scroll. The list scrolls with the wheel /
            // trackpad; the header count and the cut-off last card show that more cards follow.
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .overlay {
                if cards.isEmpty {
                    Text(model.query.isEmpty ? "No cards" : "No matches")
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.muted)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(AAColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: AARadius.boardCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AARadius.boardCard, style: .continuous)
                .strokeBorder(targeted ? color : AAColor.border, lineWidth: targeted ? 2.5 : 1)
                .shadow(color: targeted ? color.opacity(0.5) : .clear, radius: 6)
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.aaTaskRef], delegate: BoardDropDelegate(status: spec.status, targeted: $targeted,
                                                                   actions: actions))
        .focusable()
        .focusEffectDisabled()
        .onCommand(#selector(NSResponder.selectAll(_:))) { model.selectAll(spec.status) }
        .aaListCommands(listCommands(cards: cards, selected: selected))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(spec.title) column, \(cards.count) cards")
    }

    /// T-KB-06: one selected card → "Delete Task" (VIEW-052 flow); several → the shared batch delete.
    private func listCommands(cards: [BoardCard], selected: Set<UUID>) -> ListCommands {
        let ids = cards.filter { selected.contains($0.id) }.map(\.id)
        let delete: (() -> Void)?
        if ids.count == 1, let id = ids.first {
            delete = { Task { @MainActor in await actions.delete(id) } }
        } else if ids.count > 1 {
            delete = { Task { @MainActor in await actions.deleteMany(ids) } }
        } else {
            delete = nil
        }
        return ListCommands(role: .boardColumn, selectionCount: ids.count,
                            deleteTitle: ids.count > 1 ? "Delete Tasks" : BoardModel.deleteMenuTitle,
                            delete: delete,
                            primary: ids.count == 1 ? { actions.edit(ids[0]) } : nil)
    }

    /// VIEW-050: eight entries, in order.
    @ViewBuilder
    private func menu(for card: BoardCard) -> some View {
        Button(BoardModel.openEditTitle, systemImage: "pencil") {
            _ = model.targets(for: card, in: spec.status)
            actions.edit(card.id)
        }
        Button(BoardModel.openAllFilesTitle, systemImage: "doc.on.doc") {
            Task { @MainActor in await actions.openAllFiles(card.id) }
        }
        Divider()
        BatchContextMenuItems(selection: { model.targets(for: card, in: spec.status) as [AnyObject] },
                              refresh: { model.cards.refresh() })
        Divider()
        Button(BoardModel.deleteTitle, systemImage: "trash", role: .destructive) {
            Task { @MainActor in await actions.delete(card.id) }
        }
    }
}

private struct BoardDropDelegate: DropDelegate {
    let status: WorkStatus
    @Binding var targeted: Bool
    let actions: BoardActions

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.aaTaskRef]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if let id = MainActor.assumeIsolated({ CalDragSession.shared.taskID }) {
            MainActor.assumeIsolated { CalDragSession.shared.taskID = nil }
            return MainActor.assumeIsolated { actions.drop(taskID: id, on: status) }
        }
        guard let provider = info.itemProviders(for: [UTType.aaTaskRef]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.aaTaskRef.identifier) { data, _ in
            guard let data, let text = try? JSONDecoder().decode(String.self, from: data),
                  let id = UUID(netString: text) else { return }
            Task { @MainActor in _ = actions.drop(taskID: id, on: status) }
        }
        return true
    }
}

// MARK: Card (VIEW-043)

private struct BoardCardView: View {
    @Environment(AppEnvironment.self) private var env
    let card: BoardCard
    let color: Color
    let selected: Bool
    @State private var hovering = false
    /// #6B6B6B (VIEW-043) in light; a lighter grey in dark for contrast (07 §7.2).
    static let metaColor = AAColor.dyn("boardMeta", "#6B6B6B", "#9E9E9E")

    var body: some View {
        let t = card.task
        let today = env.store.clock.today()
        let meta = BoardModel.meta(t, today: today)
        let parts = BoardModel.metaParts(t, today: today)
        let badges = BoardModel.badges(t)
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 6)
            VStack(alignment: .leading, spacing: 0) {
                if let parent = card.parentLine {
                    Text(parent)
                        .font(.aaMono(11.5))
                        .foregroundStyle(AAColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                        .help(BoardModel.parentHelp)
                }
                Text(t.name.isEmpty ? " " : t.name)
                    .font(.aaMono(15, weight: .bold))
                    .strikethrough(t.isComplete)
                    .foregroundStyle(t.isComplete ? AAColor.muted : AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                if !meta.isEmpty {
                    // Dates, an OVERDUE chip, then the recurrence: each part wraps as a unit, so the chip never
                    // lands on a line of its own behind a dangling separator. The Windows string stays the
                    // accessibility label and tooltip.
                    CalFlowLayout(spacing: AASpacing.s, lineSpacing: AASpacing.xs) {
                        if let dates = parts.dates {
                            Text(dates)
                                .foregroundStyle(parts.overdue ? AAColor.Status.overdueMeta : Self.metaColor)
                        }
                        if parts.overdue {
                            AAStatusCapsule(text: BoardModel.overdueWord, symbol: "exclamationmark.triangle.fill",
                                            color: AAColor.Status.overdueMeta)
                        }
                        if let recurrence = parts.recurrence {
                            Label(recurrence, systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Self.metaColor)
                        }
                    }
                    .font(.aaMono(12.5).monospacedDigit())
                    .padding(.top, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(meta)
                    .help(meta)
                }
                if !badges.isEmpty {
                    Text(badges)
                        .font(.aaMono(12.5))
                        .foregroundStyle(AAColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(selected ? AAColor.selectionBg.opacity(0.55) : (hovering ? AAColor.hover : AAColor.panel))
        .clipShape(RoundedRectangle(cornerRadius: AARadius.boardCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AARadius.boardCard, style: .continuous)
                .strokeBorder(selected ? AAColor.tint : AAColor.border, lineWidth: selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.04), radius: hovering ? 4 : 1, y: hovering ? 2 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: AARadius.boardCard))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
