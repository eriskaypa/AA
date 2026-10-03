// Spec: 08 §2.2 (QUICK-040…084), §3.2 (`RefreshPending`, selection restore, `SetRepo`), §6.2-B, §6.3, Q-11 / Q-13
//       (the Mac may refresh live while keeping selection and focus); DECISIONS 02 Q-4 (deletes via the Trash);
//       ARCHITECTURE.md §2.4 (hold ids, re-resolve after a reload), §9.7 (rows built once per refresh, not per row).
import AppKit
import SwiftUI
import AACore

/// The quick-work window's state: filter, search, the left-list rows, the pinned tiles and the current item.
/// Rows are rebuilt explicitly after every action (and when the window becomes key or the data is reloaded), never
/// per render, so typing in the detail pane never rebuilds the list (QUICK-049, QUICK-074 focus protection).
@MainActor @Observable
final class QuickWorkModel {
    var filter: QuickWorkFilter = .all { didSet { if filter != oldValue { refresh() } } }
    var query = "" { didSet { if query != oldValue { refresh() } } }
    var selection = Set<String>() { didSet { if selection != oldValue { selectionChanged(from: oldValue) } } }

    private(set) var listing = QuickWorkListing()
    private(set) var tiles: [QuickWorkTile] = []
    /// `_selected`: the detail pane's item (kept even when the current filter hides its row).
    private(set) var currentID: UUID?
    /// `_selectedBucketKey`: which group the current row was picked in (two-bucket items show twice).
    private(set) var currentBucketKey = ""
    /// Bumped whenever the detail pane must be rebuilt (selection change, create, delete, reload).
    private(set) var detailToken = UUID()

    @ObservationIgnored weak var env: AppEnvironment?
    @ObservationIgnored private var suppress = false
    @ObservationIgnored private var lastGeneration = -1

    func attach(_ env: AppEnvironment) {
        self.env = env
        if lastGeneration != env.store.generation {
            lastGeneration = env.store.generation
            refresh()
        }
    }

    // MARK: Refresh (QUICK-043…049, QUICK-061)

    /// `RefreshPending()` + `RefreshPinned()`: rows, groups, count line, tiles (pruning dead pins), then restore
    /// the selection — the same item in the same bucket group, else any row of it, else none (the detail keeps its
    /// item).
    func refresh() {
        guard let env else { return }
        let today = env.clock.today()
        listing = QuickWorkRows.build(store: env.store, filter: filter, query: query, today: today)
        tiles = QuickWorkRows.pinnedTiles(store: env.store, today: today)
        restoreSelection()
    }

    /// QUICK-083 `SetRepo`: after a reload, re-resolve the current item by id (nil if it vanished) and rebuild both
    /// panes.
    func reloaded() {
        guard let env else { return }
        lastGeneration = env.store.generation
        if let id = currentID, env.store.item(id: id) == nil { currentID = nil }
        refresh()
        detailToken = UUID()
    }

    private func restoreSelection() {
        suppress = true
        defer { suppress = false }
        guard let id = currentID else {
            if !selection.isEmpty { selection = [] }
            return
        }
        let live = Set(listing.rows.map(\.id))
        let kept = selection.filter { live.contains($0) }
        if !kept.isEmpty {
            if kept != selection { selection = kept }
            return
        }
        let row = listing.rows.first { $0.itemID == id && $0.bucketKey == currentBucketKey }
            ?? listing.rows.first { $0.itemID == id }
        selection = row.map { [$0.id] } ?? []
    }

    /// The "primary" row of a multi-selection: the row the user just added, else the current one if still selected,
    /// else the first selected row in display order.
    private func selectionChanged(from old: Set<String>) {
        guard !suppress else { return }
        let added = selection.subtracting(old)
        let pick: QuickWorkRow?
        if let a = added.first, added.count == 1 {
            pick = listing.rows.first { $0.id == a }
        } else if let id = currentID, let r = listing.rows.first(where: { $0.itemID == id && selection.contains($0.id) }) {
            pick = r
        } else {
            pick = listing.rows.first { selection.contains($0.id) }
        }
        guard let pick else { return }
        if pick.itemID != currentID {
            currentID = pick.itemID
            detailToken = UUID()
        }
        currentBucketKey = pick.bucketKey
    }

    /// `SelectItem`: make an item current (e.g. after + Task, or a tile click) and select its row.
    func select(_ id: UUID?) {
        if id != currentID { detailToken = UUID() }
        currentID = id
        currentBucketKey = ""
        selection = []
        restoreSelection()
    }

    /// The current item, re-resolved by id (ARCH §2.4).
    var currentItem: HierarchyItem? {
        guard let id = currentID, let env else { return nil }
        return env.store.item(id: id)
    }

    /// The distinct items of the selected rows (display order).
    var selectedItems: [HierarchyItem] {
        guard let env else { return [] }
        var seen = Set<UUID>()
        return listing.rows.filter { selection.contains($0.id) && seen.insert($0.itemID).inserted }
            .compactMap { env.store.item(id: $0.itemID) }
    }

    /// Items for a context-menu invocation: the clicked rows (SwiftUI passes the selection when the clicked row is in
    /// it, else the clicked row — the WPF `RightClickSelect` rule).
    func items(forRowIDs ids: Set<String>) -> [HierarchyItem] {
        guard let env else { return [] }
        var seen = Set<UUID>()
        return listing.rows.filter { ids.contains($0.id) && seen.insert($0.itemID).inserted }
            .compactMap { env.store.item(id: $0.itemID) }
    }

    func isPinned(_ id: UUID) -> Bool {
        guard let env else { return false }
        return QuickWorkActions.isPinned(id, store: env.store)
    }

    /// Selected children of the detail pane are held by the detail view; this is the shared clear after a delete.
    func itemDeleted(_ id: UUID) {
        if currentID == id {
            currentID = nil
            detailToken = UUID()
        }
        refresh()
    }
}
