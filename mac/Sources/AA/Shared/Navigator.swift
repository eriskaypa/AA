// Spec: 03 SHELL-140 (NavigateToItem — Mac: by kind/identity, never by index, W-6 fixed), SHELL-141 (NavigateToCrew),
//       SHELL-027 (selected tab persisted in memory, no MarkDirty), SHELL-028 (reorder → TabOrder + MarkDirty), SHELL-522,
//       04 HIER-120, 07 VIEW-205, 08 QUICK-210, DECISIONS 02 Q-11 (child selection); ARCHITECTURE.md §7.4.
import AppKit
import Observation
import AACore

struct ItemNavigationRequest: Identifiable, Equatable { let id: UUID; let itemID: UUID; let childID: UUID? }
struct CrewNavigationRequest: Identifiable, Equatable { let id: UUID; let memberID: UUID }

@MainActor @Observable
final class Navigator {
    @ObservationIgnored private let store: AppStore
    var selectedSection: SectionID = .equipment
    private var itemRequests: [Int: ItemNavigationRequest] = [:]
    private(set) var crewRequest: CrewNavigationRequest?

    init(store: AppStore) { self.store = store }

    /// `SectionID.applyTabOrder(ui.tabOrder)`.
    var sectionOrder: [SectionID] { SectionID.applyTabOrder(store.data.ui.tabOrder) }

    /// Selects a section, brings the main window to the front and records `SelectedMainTabIndex` (no dirty mark).
    func select(_ section: SectionID) {
        selectSilently(section)
        LaunchCoordinator.shared.env?.showMainWindow()
    }

    /// Same, without touching windows (restoring UI state, snapshots).
    func selectSilently(_ section: SectionID) {
        if selectedSection != section { selectedSection = section }
        if let i = sectionOrder.firstIndex(of: section) { store.data.ui.selectedMainTabIndex = i }
    }

    /// SHELL-028 / SHELL-522: drag reorder writes the 13 names (unknown stored names preserved) + MarkDirty.
    func moveSections(from: IndexSet, to: Int) {
        var order = sectionOrder
        order.move(fromOffsets: from, toOffset: to)
        applyOrder(order)
    }

    /// Writes a new display order (keeps the selected section selected; SHELL-028).
    func applyOrder(_ order: [SectionID]) {
        guard order != sectionOrder else { return }
        store.data.ui.tabOrder = SectionID.writeTabOrder(order, preserving: store.data.ui.tabOrder)
        if let i = order.firstIndex(of: selectedSection) { store.data.ui.selectedMainTabIndex = i }
        store.markDirty()
    }

    /// SHELL-140 / VIEW-205: switch by the item's kind (top-level owner for child ids) and ask the page to select it.
    func navigate(to itemID: UUID, childID: UUID? = nil) {
        var target = itemID
        var child = childID
        let item: HierarchyItem?
        if let direct = store.item(id: itemID) {
            item = direct
        } else if let owner = store.topLevelOwner(ofAnyID: itemID) {
            item = owner.owner
            target = owner.owner.id
            child = child ?? owner.childID ?? itemID
        } else {
            item = nil
        }
        guard let item else { return }
        select(SectionID.section(for: item.kind))
        itemRequests[item.kind.rawValue] = ItemNavigationRequest(id: UUID(), itemID: target, childID: child)
    }

    /// SHELL-141.
    func navigateToCrew(_ memberID: UUID) {
        select(.crew)
        crewRequest = CrewNavigationRequest(id: UUID(), memberID: memberID)
    }

    /// Observed by `HierarchyTabView(kind:)`.
    func request(for kind: ItemKind) -> ItemNavigationRequest? { itemRequests[kind.rawValue] }

    func consume(_ request: ItemNavigationRequest) {
        for (k, v) in itemRequests where v.id == request.id { itemRequests[k] = nil }
    }

    func consume(_ request: CrewNavigationRequest) {
        if crewRequest?.id == request.id { crewRequest = nil }
    }

    /// After a load: apply the order first, then select `order[SelectedMainTabIndex]` (W-1 fixed).
    func restoreSelection() {
        selectedSection = SectionID.restoredSelection(order: sectionOrder, selectedIndex: store.data.ui.selectedMainTabIndex)
    }

    /// The display-order index of the selected section (CaptureUiState).
    var selectedIndex: Int { sectionOrder.firstIndex(of: selectedSection) ?? 0 }
}

/// SHELL-022 status line: the latest message plus a short history (popover).
@MainActor @Observable
final class StatusCenter {
    private(set) var message = ""
    private(set) var history: [String] = []
    private(set) var postedAt: Date?

    func post(_ text: String) {
        message = text
        postedAt = Date()
        history.insert(text, at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
    }
}

/// OC-42: flush closures of every live editor and the one-editor-per-container rule (CONT-008).
@MainActor @Observable
final class EditorFlushCenter {
    struct Token: Hashable { let raw: UUID }

    private struct Entry {
        weak var container: Container?
        var containerID: ObjectIdentifier?
        var host: String
        var flush: @MainActor () -> Void
    }

    @ObservationIgnored private var entries: [Token: Entry] = [:]
    @ObservationIgnored private var order: [Token] = []
    /// Number of live editors (observed: UI may show it in debug views).
    private(set) var count = 0

    func register(container: Container?, host: String, flush: @escaping @MainActor () -> Void) -> Token {
        let t = Token(raw: UUID())
        entries[t] = Entry(container: container, containerID: container.map(ObjectIdentifier.init), host: host, flush: flush)
        order.append(t)
        count = entries.count
        return t
    }

    func rebind(_ token: Token, to container: Container?) {
        guard var e = entries[token] else { return }
        e.container = container
        e.containerID = container.map(ObjectIdentifier.init)
        entries[token] = e
    }

    func unregister(_ token: Token) {
        entries[token] = nil
        order.removeAll { $0 == token }
        count = entries.count
    }

    /// The token of the editor currently bound to `container` (first registered wins).
    func holder(of container: Container) -> Token? {
        let id = ObjectIdentifier(container)
        return order.first { entries[$0]?.containerID == id && entries[$0]?.container != nil }
    }

    /// Flushes every live editor (all exceptions are the editors' own business; flushes never throw).
    func flushAll() {
        for t in order { entries[t]?.flush() }
    }
}
