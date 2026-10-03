// Spec: 04 HIER-001 (one page per kind), HIER-012/013 (A→Z), HIER-015 (expand state), HIER-016 (multi-selection;
//       the detail shows the FIRST-selected item), HIER-021/022 (+ New / Delete), HIER-025 (rename commit rebuilds and
//       re-selects), HIER-030…034 (groups), HIER-040 (selection binds the details; flush first), HIER-110 (open in
//       new window), HIER-120/121 (navigation and selection persistence), HIER-125 (live refresh), M01 (drag to group),
//       M04 (focus the name after + New), §3.2 (selection helpers), §8 Q-01/Q-05/Q-06/Q-07/Q-08/Q-09/Q-29/Q-32;
//       V2-COMPAT (items sharing an Id: rows, selection and the index use `HierRowKey` keys), V2-SCALE (reveal);
//       ARCHITECTURE.md §2.4 (ids, never model references, across reloads), §9.7 (memoised build, O(1) lookups).
import AppKit
import SwiftUI
import AACore

/// The details tabs (HIER-042).
enum HierDetailTab: Hashable {
    case quickCards, workOrders, ports, container, relationships, specifics
}

/// The state of one hierarchy page (one per kind, kept alive while the main window lives).
@MainActor @Observable
final class HierPageModel {
    let kind: ItemKind
    @ObservationIgnored unowned let env: AppEnvironment

    /// The built sidebar (rebuilt on structural changes only, so typing a name never re-sorts under the cursor).
    private(set) var sidebar = HierSidebar.empty
    /// row key → item of this kind, rebuilt with the sidebar (O(1) row lookups, ARCH §9.7). The key is the item Id,
    /// except for a later item sharing an Id (`HierRowKey`), so every row resolves to its own object.
    @ObservationIgnored private(set) var index: [UUID: HierarchyItem] = [:]
    /// object → row key (the inverse of `index`), so an action on objects re-selects the very rows it touched.
    @ObservationIgnored private var keyByObject: [ObjectIdentifier: UUID] = [:]

    /// The List selection (row keys; the item Id except for a later item sharing an Id).
    var selection: Set<UUID> = [] { didSet { selectionDidChange(old: oldValue) } }
    /// Selection order (first-selected first, HIER-016).
    private(set) var selectionOrder: [UUID] = []
    /// The details item (first-selected).
    private(set) var primaryID: UUID?

    var query = "" { didSet { if query != oldValue { rebuild() } } }
    var detailTab: HierDetailTab
    /// The item whose name is being typed in the page's own Name box (excluded from the rebuild signature).
    var editingNameID: UUID?
    /// Asks the header of this item to focus the Name box with all text selected (F2 / ↩ / + New); the header
    /// clears it once honoured (it may be created after the request, e.g. right after + New).
    var pendingNameFocusID: UUID?
    /// Bumped to ask the sidebar to reveal a row. Set before the sidebar exists too (HIER-121 restore in `init`); the
    /// sidebar honours the current request when it appears and every later one (`.task(id:)`).
    private(set) var revealRequest: (id: UUID, token: Int)?

    /// The List identity to scroll to for the current reveal request (the row, or its collapsed section's header).
    var revealRowID: String? {
        guard let key = revealRequest?.id else { return nil }
        return sidebar.revealRowID(for: key) { isExpanded($0) }
    }
    /// A child (subtask / step / component) to reveal after a navigation (DECISIONS 02 Q-11).
    var pendingChildID: UUID?
    @ObservationIgnored let searchLocator = HierFieldLocator()

    @ObservationIgnored private var subscriptions: [EventSubscription] = []

    init(kind: ItemKind, env: AppEnvironment) {
        self.kind = kind
        self.env = env
        detailTab = kind == .vessel ? .quickCards : .container
        #if DEBUG
        // Snapshot hook aid (ARCH §9.6): AA_SNAPSHOT_HIER_TAB=relationships|specifics|… picks the initial details tab.
        if let raw = ProcessInfo.processInfo.environment["AA_SNAPSHOT_HIER_TAB"] {
            let map: [String: HierDetailTab] = ["quickCards": .quickCards, "workOrders": .workOrders, "ports": .ports,
                                                "container": .container, "relationships": .relationships,
                                                "specifics": .specifics]
            if let t = map[raw] { detailTab = t }
        }
        #endif
        subscriptions.append(env.store.dataReplaced.subscribe { [weak self] _ in self?.dataWasReplaced() })
        rebuild()
        restoreSelectionFromUi()
    }

    var store: AppStore { env.store }

    #if DEBUG
    static var snapshotTabPinned: Bool { ProcessInfo.processInfo.environment["AA_SNAPSHOT_HIER_TAB"] != nil }
    #else
    static var snapshotTabPinned: Bool { false }
    #endif

    // MARK: Sidebar build (HIER-010…015, §3.1)

    var sortAZ: Bool { HierUiState.sortAZ(store.data.ui, kind: kind) }

    func rebuild() {
        let items = store.items(of: kind)
        var idx: [UUID: HierarchyItem] = [:]
        var keys: [ObjectIdentifier: UUID] = [:]
        idx.reserveCapacity(items.count)
        keys.reserveCapacity(items.count)
        for (key, i) in zip(HierRowKey.keys(for: items.map(\.id)), items) {
            idx[key] = i
            keys[ObjectIdentifier(i)] = key
        }
        index = idx
        keyByObject = keys
        sidebar = HierSidebarBuilder.build(store: store, kind: kind, query: query, sortAZ: sortAZ)
        // Q-01: keep the selection while the items are still shown; drop what disappeared or was filtered out.
        let visible = Set(sidebar.visibleItemIDs)
        let kept = selection.filter { visible.contains($0) }
        if kept != selection { selection = kept }
    }

    func item(_ id: UUID?) -> HierarchyItem? {
        guard let id else { return nil }
        if let i = index[id], i.kind == kind { return i }
        return nil
    }

    /// The details item (the index is rebuilt synchronously on every structural change and reload).
    var primaryItem: HierarchyItem? { item(primaryID) }

    /// The selected real items in selection order (§3.2 `SelectedHierarchyItems`).
    var selectedItems: [HierarchyItem] { selectionOrder.compactMap { item($0) } }

    /// The row keys of these objects (their Ids for well-formed data).
    func rowKeys(_ items: [HierarchyItem]) -> [UUID] { items.map { keyByObject[ObjectIdentifier($0)] ?? $0.id } }

    /// Items for an explicit id set (context menus act on the clicked set), in display order.
    func items(for ids: Set<UUID>) -> [HierarchyItem] {
        let ordered = selectionOrder.filter { ids.contains($0) } + sidebar.visibleItemIDs.filter { ids.contains($0) && !selectionOrder.contains($0) }
        return ordered.compactMap { item($0) }
    }

    // MARK: Selection (HIER-016, HIER-040)

    private func selectionDidChange(old: Set<UUID>) {
        guard selection != old else { return }
        selectionOrder.removeAll { !selection.contains($0) }
        let added = sidebar.visibleItemIDs.filter { selection.contains($0) && !selectionOrder.contains($0) }
        selectionOrder.append(contentsOf: added)
        for id in selection where !selectionOrder.contains(id) { selectionOrder.append(id) }
        let newPrimary = selectionOrder.first
        if newPrimary != primaryID { primaryChanged(to: newPrimary) }
    }

    private func primaryChanged(to id: UUID?) {
        // HIER-040 step 1: pending rich-text edits land on the PREVIOUS item.
        env.flushAllEditors()
        if editingNameID != nil { editingNameID = nil }
        primaryID = id
        // HIER-121 (per device, no dirty mark): the item's real Id, never a derived row key.
        HierUiState.setSelectedID(store.data.ui, kind: kind, id.map { item($0)?.id ?? $0 })
        if kind == .vessel, id != nil, !Self.snapshotTabPinned { detailTab = .quickCards }   // HIER-040 step 7 / HIER-100
    }

    /// `SelectItemsByIds` (replaces the selection; first id becomes the primary; reveals the first).
    func select(_ ids: [UUID], reveal: Bool = true) {
        let visible = Set(sidebar.visibleItemIDs)
        let wanted = ids.filter { visible.contains($0) }
        selectionOrder = wanted
        primaryChangedIfNeeded(wanted.first)
        selection = Set(wanted)
        if reveal, let first = wanted.first { requestReveal(first) }
    }

    private func primaryChangedIfNeeded(_ id: UUID?) {
        if id != primaryID { primaryChanged(to: id) }
    }

    func requestReveal(_ id: UUID) {
        revealRequest = (id, (revealRequest?.token ?? 0) + 1)
    }

    func clearSelection() {
        selectionOrder = []
        primaryChangedIfNeeded(nil)
        selection = []
    }

    /// HIER-121 load: re-select `Ui.Selected{Kind}Id`.
    func restoreSelectionFromUi() {
        if let id = HierUiState.selectedID(store.data.ui, kind: kind), item(id) != nil {
            select([id], reveal: true)
        } else {
            clearSelection()
        }
    }

    private func dataWasReplaced() {
        editingNameID = nil
        rebuild()
        restoreSelectionFromUi()
    }

    // MARK: Search and navigation (HIER-120, Q-05)

    /// Selects an item of this page, clearing the search when it hides the item (Q-05), and reveals it.
    func navigate(to id: UUID, childID: UUID?) {
        guard store.item(id: id)?.kind == kind else { return }
        if !sidebar.visibleItemIDs.contains(id) {
            query = ""
            rebuild()
        }
        expandSection(containing: id)
        select([id])
        if let child = childID, child != id {
            pendingChildID = child
            if kind != .vessel { detailTab = .specifics }
        }
    }

    private func expandSection(containing id: UUID) {
        guard let s = sidebar.sections.first(where: { $0.rows.contains { $0.itemID == id } }) else { return }
        if !HierUiState.isExpanded(store.data.ui, key: s.expandKey) {
            HierUiState.setExpanded(store.data.ui, key: s.expandKey, true)
            store.markDirty()
        }
    }

    // MARK: Header (HIER-025)

    /// F2 / ↩ / after + New: focus the Name box with all text selected.
    func beginRename() {
        guard let id = primaryItem?.id else { return }
        pendingNameFocusID = id
    }

    /// Enter or focus loss: rebuild (re-sort / re-group) and re-select by id — without the selection side effects
    /// (Q-32: a vessel keeps its sub-tab). `stillEditing` is the item whose Name box keeps the focus after Return:
    /// it stays excluded from the rebuild signature, so later keystrokes re-label the row in place again instead of
    /// rebuilding (and re-sorting) the sidebar on every key (HIER-025).
    func commitRename(stillEditing: UUID? = nil) {
        editingNameID = nil
        rebuild()
        editingNameID = HierRenameState.editingAfterCommit(stillEditing: stillEditing, primary: primaryID)
    }

    // MARK: A→Z and expand (HIER-013, HIER-015)

    func setSortAZ(_ on: Bool) {
        if HierUiState.setSortAZ(store.data.ui, kind: kind, on) { store.markDirty() }
        rebuild()
    }

    func isExpanded(_ s: HierSidebarSection) -> Bool { HierUiState.isExpanded(store.data.ui, key: s.expandKey) }

    func setExpanded(_ s: HierSidebarSection, _ expanded: Bool) {
        if HierUiState.setExpanded(store.data.ui, key: s.expandKey, expanded) { store.markDirty() }
    }

    // MARK: + New (HIER-021, M04, Q-06)

    func newItem(dialogs: DialogPresenter) {
        env.flushAllEditors()
        let item = store.createItem(kind: kind)
        HierPersist.save(env, dialogs: dialogs)
        if !query.isEmpty && !HierSidebarBuilder.matches(
            HierSidebarItem(id: item.id, name: item.name, groupID: item.groupId, tags: item.tags),
            trimmedQuery: NetText.trim(query)) {
            query = ""                                                      // Q-06
        }
        rebuild()
        select([item.id])
        if kind == .vessel { detailTab = .quickCards }
        beginRename()                                                       // M04
    }

    // MARK: Delete (HIER-022, HIER-135, M02)

    func delete(_ items: [HierarchyItem], dialogs: DialogPresenter) async {
        guard !items.isEmpty else {
            await dialogs.info("Delete selected", "Select one or more items first.")
            return
        }
        let n = await BatchActions.confirmAndTrash(items, env: env, dialogs: dialogs)
        guard n > 0 else { return }
        clearSelection()
        rebuild()
    }

    /// The toolbar Delete: the selection, else the details item.
    func deleteSelection(dialogs: DialogPresenter) async {
        var items = selectedItems
        if items.isEmpty, let p = primaryItem { items = [p] }
        await delete(items, dialogs: dialogs)
    }

    // MARK: Open in new window (HIER-110, HIER-057, M03)

    func openInWindow(_ items: [HierarchyItem], dialogs: DialogPresenter) {
        guard let target = items.first ?? primaryItem else { return }
        if env.locks.isGated(target) {
            Task { @MainActor in await dialogs.info(HierText.lockedAlertTitle, HierText.unlockBeforeWindow) }
            return
        }
        env.open(.item(target.id))
    }

    // MARK: Groups (HIER-030…034, M01)

    func newGroup(dialogs: DialogPresenter) async {
        guard let name = await HierDialogs.prompt(dialogs, title: HierText.newGroupTitle, label: HierText.nameLabel),
              let g = HierPageOps.createGroup(store: store, kind: kind, name: name) else { return }
        HierPersist.save(env, dialogs: dialogs)
        rebuild()
        env.status.post(HierText.groupCreated(g.name))
    }

    func assignGroup(_ items: [HierarchyItem], dialogs: DialogPresenter) async {
        guard !items.isEmpty else { return }
        let choices = HierGroupPicker.assignChoices(store: store, kind: kind)
        let common = HierGroupPicker.commonGroup(items, store: store, kind: kind)
        let request = ItemPickerRequest(prompt: HierText.moveToGroupTitle(count: items.count, firstName: items[0].name),
                                        rows: choices.map { ItemPickerRow(display: $0.display, tag: $0.tag) },
                                        preselected: common.map { [$0] } ?? [], mode: .single)
        guard let picked = await dialogs.pickItems(request), let tag = picked.first else { return }   // Q-08
        HierPageOps.assign(store: store, items, to: HierGroupPicker.groupID(fromTag: tag))
        HierPersist.save(env, dialogs: dialogs)
        rebuild()
        select(rowKeys(items))
    }

    func removeFromGroup(_ items: [HierarchyItem], dialogs: DialogPresenter) {
        guard HierPageOps.removeFromGroup(store: store, items) > 0 else { return }
        HierPersist.save(env, dialogs: dialogs)
        rebuild()
        select(rowKeys(items))
    }

    /// M01: rows dropped onto a section header (nil = Ungrouped).
    func drop(_ ids: [UUID], onto groupID: UUID?, dialogs: DialogPresenter) -> Bool {
        let items = ids.compactMap { item($0) }
        guard !items.isEmpty else { return false }
        if HierPageOps.assign(store: store, items, to: groupID) > 0 {
            HierPersist.save(env, dialogs: dialogs)
            rebuild()
            select(rowKeys(items))
        }
        return true
    }

    func renameGroup(dialogs: DialogPresenter) async {
        let groups = store.groups(for: kind)
        guard !groups.isEmpty else {
            await dialogs.info(HierText.renameGroupTitle, HierText.noGroupsToRename)
            return
        }
        let request = ItemPickerRequest(prompt: HierText.pickGroupToRename,
                                        rows: groups.map { ItemPickerRow(display: $0.name, tag: $0.id) }, mode: .single)
        guard let id = await dialogs.pickItems(request)?.first, let g = groups.first(where: { $0.id == id }),
              let name = await HierDialogs.prompt(dialogs, title: HierText.renameGroupTitle, label: HierText.newNameLabel,
                                                  initial: g.name),
              !NetText.isBlank(name) else { return }
        store.renameGroup(g, to: name)
        HierPersist.save(env, dialogs: dialogs)
        rebuild()
    }

    func deleteGroup(dialogs: DialogPresenter) async {
        let groups = store.groups(for: kind)
        guard !groups.isEmpty else {
            await dialogs.info(HierText.deleteGroupTitle, HierText.noGroupsToDelete)        // Q-09
            return
        }
        let request = ItemPickerRequest(prompt: HierText.pickGroupToDelete,
                                        rows: groups.map { ItemPickerRow(display: $0.name, tag: $0.id) }, mode: .single)
        guard let id = await dialogs.pickItems(request)?.first, let g = groups.first(where: { $0.id == id }) else { return }
        guard await dialogs.confirm(HierText.confirmTitle, HierText.confirmDeleteGroup(g.name), confirm: "Delete Group",
                                    cancel: "Cancel", destructive: true, defaultIsCancel: true) else { return }
        store.deleteGroup(g)
        HierPersist.save(env, dialogs: dialogs)
        rebuild()
    }

    // MARK: Router inputs

    var hierarchySelectionState: HierarchySelectionState {
        let p = primaryItem
        return HierarchySelectionState(primary: p?.id, count: selection.count,
                                       gated: p.map { env.locks.isGated($0) } ?? false,
                                       detached: p.map { store.detachedItemIDs.contains($0.id) } ?? false)
    }
}
