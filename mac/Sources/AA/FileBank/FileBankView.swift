// Spec: 05 §2.5 CONT-080 (panel, tabs, columns, context menu), CONT-082…093 (actions), CONT-094 (source label),
//       CONT-095 + DECISIONS 05 (shared containers UI; "Linked to" column), CONT-096 + 05 §6.9 (thumbnails, Quick
//       Look, drag out, empty state, per-tab counts, ⌘X/⌘C/⌘V, list/icon views), CONT-097; 03 SHELL-669 (Space =
//       Quick Look), SHELL-671 (⌘↓ = Open), SHELL-679 (drop modifiers), SHELL-516/670 (⌘⌫ "Remove" without
//       confirmation, plain ⌫ does nothing), SHELL-577 (Edit ▸ Cut/Copy/Paste); ARCHITECTURE.md §7.7 (exact contract:
//       `FileBankView(container:context:)`, `FileBankContext`, `FileBankOperations`), §7.6 (ListCommands), §2.4.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

// MARK: - Contract (ARCH §7.7)

struct FileBankContext {
    var host: EditorHost
    var isEnabled = true
}

/// The OneDrive-like file bank of one container (hosted by W-CONT's `ContainerEditorView`).
struct FileBankView: View {
    let container: Container
    let context: FileBankContext
    private let initial: FileBankInitialState

    init(container: Container, context: FileBankContext) {
        self.container = container
        self.context = context
        self.initial = FileBankInitialState()
    }

    /// Debug snapshots and previews only: start in a given scope / view mode with the first rows selected.
    init(container: Container, context: FileBankContext, initial: FileBankInitialState) {
        self.container = container
        self.context = context
        self.initial = initial
    }

    var body: some View {
        FileBankPane(container: container, context: context, initial: initial)
            .id(ObjectIdentifier(container))
    }
}

@MainActor enum FileBankOperations {
    /// W-CONT's image paste/drop (DECISIONS 05): an entry for bytes already stored by `AttachmentStore.importData`
    /// — classification by the display name, `Added = now`, MarkDirty. Open file banks of the container refresh
    /// through observation.
    static func addImported(storedPath: String, displayName: String, to container: Container, env: AppEnvironment) -> FileItem {
        let item = FileBankImporter(dataStore: env.dataStore)
            .addImported(storedPath: storedPath, displayName: displayName, to: container, now: env.clock.now())
        env.store.markDirty()
        return item
    }

    /// CONT-082/083/084/085: copies (folders recursively, packages zipped by `AttachmentStore`) or links in place
    /// (folders as one "(folder)" entry). Marks the store dirty when anything was added. Throws
    /// `FileBankImportError` when some copies failed (the others are already added) so the caller can offer
    /// "Link in Place Instead" (K-9).
    @discardableResult
    static func addFiles(_ urls: [URL], linkInPlace: Bool, to container: Container, env: AppEnvironment) throws -> [FileItem] {
        let importer = FileBankImporter(dataStore: env.dataStore)
        let now = env.clock.now()
        if linkInPlace {
            let added = importer.linkInPlace(urls, into: container, now: now)
            if !added.isEmpty { env.store.markDirty() }
            return added
        }
        let outcome = importer.importCopies(urls, into: container, now: now)
        if !outcome.added.isEmpty { env.store.markDirty() }
        if !outcome.failures.isEmpty {
            throw FileBankImportError(failures: outcome.failures, added: outcome.added.count)
        }
        return outcome.added
    }
}

// MARK: - State

/// Which entries the pane lists: one of the six Windows tabs, or the additive "Shared" view (files of the containers
/// that share with this one).
enum FileBankScope: Hashable {
    case tab(FileBankTab)
    case shared
}

enum FileBankViewMode: String, CaseIterable {
    case list, icons

    static let preferenceKey = MacPreferences.Key("aa.filebank.viewMode")

    static var stored: FileBankViewMode {
        MacPreferences.shared.string(preferenceKey).flatMap(FileBankViewMode.init(rawValue:)) ?? .list
    }
}

struct FileBankInitialState {
    var scope: FileBankScope = .tab(.all)
    var mode: FileBankViewMode? = nil
    var selectFirst = 0
}

/// One listed entry (rows are identified by container + entry identity + occurrence: FileItem ids are not unique,
/// 05 §4.1).
struct FileBankRow: Identifiable {
    struct ID: Hashable {
        let container: ObjectIdentifier
        let file: ObjectIdentifier
        let occurrence: Int
    }

    let id: ID
    let file: FileItem
    let container: Container
    let owner: FileBankOwner?
    let visual: FileBankVisual
    let linkedSummary: String
    let added: String

    /// What a drag out carries: the local file, or the web URL.
    var dragURL: URL? {
        switch visual.state {
        case .present(let u): return u
        case .web(let u): return u
        default: return nil
        }
    }

    var isWeb: Bool { if case .web = visual.state { return true }; return false }
}

/// Everything one render needs (built once per body, ARCH §9.7).
@MainActor struct FileBankSnapshot {
    var rows: [FileBankRow] = []
    var counts: [FileBankTab: Int] = [:]
    var sharedInCount = 0
    var lockedSharers: [String] = []
    var columns: [FileBankColumn] = []
    var isShared = false

    init(container: Container, scope: FileBankScope, env: AppEnvironment) {
        let ds = env.dataStore
        let index = FileBankItemIndex(store: env.store)
        let formatter = FileBankDisplay.addedFormatter()
        for t in FileBankTab.allCases { counts[t] = t.filter(container.files).count }
        let sharers = env.store.allContainers().filter {
            $0 !== container && $0.sharedWithContainerIds.contains(container.id)
        }
        func isGated(_ owner: FileBankOwner) -> Bool {
            guard let gate = owner.gatingItemID, let item = env.store.item(id: gate) else { return false }
            return env.locks.isGated(item)
        }
        var occurrences: [ObjectIdentifier: Int] = [:]
        func row(_ f: FileItem, in c: Container, owner: FileBankOwner?) -> FileBankRow {
            let key = ObjectIdentifier(f)
            let n = occurrences[key, default: 0]
            occurrences[key] = n + 1
            return FileBankRow(id: .init(container: ObjectIdentifier(c), file: key, occurrence: n), file: f, container: c,
                               owner: owner, visual: FileBankVisual(f, dataStore: ds),
                               linkedSummary: index.linkedSummary(f.linkedItemIds), added: FileBankDisplay.added(f.added, formatter: formatter))
        }
        switch scope {
        case .tab(let t):
            columns = t.columns
            rows = t.filter(container.files).map { row($0, in: container, owner: nil) }
            if !sharers.isEmpty {
                let dir = FileBankDirectory(store: env.store)
                for e in dir.sharedInto(container) {
                    if isGated(e.owner) { lockedSharers.append(e.owner.label) } else { sharedInCount += e.container.files.count }
                }
            }
        case .shared:
            isShared = true
            columns = [.name, .kind, .source, .linkedTo, .path]
            let dir = FileBankDirectory(store: env.store)
            for e in dir.sharedInto(container) {
                if isGated(e.owner) {
                    lockedSharers.append(e.owner.label)
                    continue
                }
                rows.append(contentsOf: e.container.files.map { row($0, in: e.container, owner: e.owner) })
            }
            sharedInCount = rows.count
        }
    }
}

// MARK: - The pane

struct FileBankPane: View {
    let container: Container
    let context: FileBankContext
    let initial: FileBankInitialState

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var scope: FileBankScope
    @State private var mode: FileBankViewMode
    @State private var selection: Set<FileBankRow.ID> = []
    @State private var dropState = FileBankDropState()
    @State private var appliedInitialSelection = false

    init(container: Container, context: FileBankContext, initial: FileBankInitialState) {
        self.container = container
        self.context = context
        self.initial = initial
        _scope = State(initialValue: initial.scope)
        _mode = State(initialValue: initial.mode ?? FileBankViewMode.stored)
    }

    private var controller: FileBankController { FileBankController(container: container, env: env, dialogs: dialogs) }
    private var editable: Bool { context.isEnabled }

    var body: some View {
        let snap = FileBankSnapshot(container: container, scope: scope, env: env)
        let selected = snap.rows.filter { selection.contains($0.id) }
        VStack(spacing: 0) {
            FileBankHeaderBar(title: FileBankText.title, total: container.files.count, editable: editable,
                              canEditSelection: editable && !snap.isShared && !selected.isEmpty,
                              canCut: editable && !snap.isShared,
                              hasSelection: !selected.isEmpty, hasShown: !snap.rows.isEmpty,
                              actions: headerActions(snap: snap, selected: selected))
            Divider()
            FileBankScopeBar(scope: $scope, mode: modeBinding, counts: snap.counts, sharedInCount: snap.sharedInCount,
                             showsShared: snap.sharedInCount > 0 || !snap.lockedSharers.isEmpty || scope == .shared) { compact in
                FileBankSharingMenu(container: container, controller: controller, editable: editable, compact: compact)
            }
            content(snap)
                .overlay { FileBankDropOverlay(state: dropState) }
            FileBankFooter(shown: snap.rows.count, selected: selected.count, isShared: snap.isShared,
                           lockedSharers: snap.isShared ? snap.lockedSharers : [])
        }
        .background(AAColor.panel)
        .onDrop(of: [.fileURL, .url], delegate: FileBankDropDelegate(state: dropState, enabled: editable) { files, webs, link in
            Task { await controller.handleDrop(fileURLs: files, webURLs: webs, linkInPlace: link) }
        })
        .onChange(of: scope) { _, _ in selection = [] }
        .onChange(of: selection) { _, _ in followQuickLook(snap) }
        .onAppear {
            guard !appliedInitialSelection else { return }
            appliedInitialSelection = true
            if initial.selectFirst > 0 { selection = Set(snap.rows.prefix(initial.selectFirst).map(\.id)) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FileBankText.title)
    }

    private var modeBinding: Binding<FileBankViewMode> {
        Binding(get: { mode }, set: { new in
            withAnimation(.snappy(duration: 0.2)) { mode = new }
            MacPreferences.shared.set(new.rawValue, FileBankViewMode.preferenceKey)
        })
    }

    @ViewBuilder private func content(_ snap: FileBankSnapshot) -> some View {
        let actions = rowActions(snap)
        ZStack {
            if snap.rows.isEmpty {
                emptyState(snap)
            } else if mode == .list {
                FileBankTable(rows: snap.rows, columns: snap.columns, isShared: snap.isShared, selection: $selection,
                              actions: actions)
            } else {
                FileBankGrid(rows: snap.rows, isShared: snap.isShared, selection: $selection, actions: actions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func emptyState(_ snap: FileBankSnapshot) -> some View {
        if snap.isShared {
            AAEmptyState(title: FileBankText.sharedEmptyTitle, symbol: "folder.badge.person.crop",
                         message: FileBankText.sharedEmptyMessage)
        } else if case .tab(let t) = scope, t != .all, !container.files.isEmpty {
            AAEmptyState(title: FileBankText.emptyTitle, symbol: t.symbol, message: FileBankText.emptyTabMessage(t.title))
        } else {
            AAEmptyState(title: FileBankText.emptyTitle, symbol: "tray", message: FileBankText.emptyMessage)
        }
    }

    // MARK: Actions wiring

    private func headerActions(snap: FileBankSnapshot, selected: [FileBankRow]) -> FileBankHeaderActions {
        let c = controller
        let files = selected.map(\.file)
        let shown = snap.rows.map(\.file)
        return FileBankHeaderActions(
            addFile: { Task { await c.addFiles() } },
            linkInPlace: { Task { await c.linkInPlace() } },
            addFolder: { Task { await c.addFolder() } },
            addLink: { Task { await c.addLink() } },
            cut: { if snap.isShared { NSSound.beep() } else { c.cut(files) } },
            copy: { copy(selected) },
            paste: { Task { await c.paste() } },
            remove: { if !snap.isShared { c.remove(files) } },
            open: { Task { await c.open(files) } },
            openAll: { Task { await c.openAll(shown) } })
    }

    private func copy(_ rows: [FileBankRow]) {
        if rows.isEmpty { FileBankClipboard.shared.clear(); return }       // CONT-087: empty selection empties it
        controller.copy(rows.map(\.file), from: rows.first?.container)
    }

    private func rowActions(_ snap: FileBankSnapshot) -> FileBankRowActions {
        let c = controller
        let env = env
        let dialogs = dialogs
        let shownFiles = snap.rows.map(\.file)
        func files(_ ids: Set<FileBankRow.ID>) -> [FileItem] { snap.rows.filter { ids.contains($0.id) }.map(\.file) }
        func first(_ ids: Set<FileBankRow.ID>) -> FileBankRow? { snap.rows.first { ids.contains($0.id) } }
        return FileBankRowActions(
            editable: editable && !snap.isShared,
            open: { ids in Task { await c.open(files(ids)) } },
            showInFinder: { ids in if let r = first(ids) { Task { await c.showInFinder(r.file) } } },
            quickLook: { ids, toggle in
                if toggle, QuickLookCoordinator.shared.isVisible { QuickLookCoordinator.shared.close(); return }
                let sel = files(ids)
                guard !sel.isEmpty else { NSSound.beep(); return }
                let pool = sel.count > 1 ? sel : shownFiles               // one selected: ← / → browse the tab
                FileBankOpening.quickLook(pool, selected: sel.first, env: env, toggle: false)
            },
            rename: { ids in if let r = first(ids) { Task { await c.rename(r.file) } } },
            linkToItems: { ids in if let r = first(ids) { Task { await c.linkToItems(r.file) } } },
            remove: { ids in if !snap.isShared { c.remove(files(ids)) } },
            copyPath: { ids in c.copyPath(files(ids)) },
            cut: { ids in if !snap.isShared { c.cut(files(ids)) } },
            copy: { ids in copy(snap.rows.filter { ids.contains($0.id) }) },
            copyForPasteboard: { ids in
                let fs = files(ids)
                if fs.isEmpty { FileBankClipboard.shared.clear() } else {
                    FileBankClipboard.shared.copy(fs, from: first(ids)?.container ?? container,
                                                  generation: env.store.generation)
                }
                return fs
            },
            cutForPasteboard: { ids in
                let fs = files(ids)
                guard !snap.isShared else { return [] }
                FileBankClipboard.shared.cut(fs, from: container, generation: env.store.generation)
                return fs
            },
            paste: { Task { await c.paste() } },
            showOwner: { ids in
                guard let o = first(ids)?.owner else { return }
                FileBankNavigation.reveal(o, env: env)
            },
            openWith: { url, app in FileBankOpening.open(url, with: app) },
            openWithOther: { url in Task { await FileBankOpening.chooseApplication(for: url, dialogs: dialogs) } })
    }

    private func followQuickLook(_ snap: FileBankSnapshot) {
        guard QuickLookCoordinator.shared.isVisible else { return }
        let sel = snap.rows.filter { selection.contains($0.id) }
        guard let first = sel.first else { return }
        let pool = sel.count > 1 ? sel : snap.rows
        let urls = pool.compactMap(\.visual.localURL)
        let idx = first.visual.localURL.flatMap { u in urls.firstIndex(of: u) } ?? 0
        QuickLookCoordinator.shared.updateIfVisible(urls, selectedIndex: idx)
    }
}

/// Navigation to a container's owner (backlinks "Show Owner", shared rows).
@MainActor enum FileBankNavigation {
    static func reveal(_ o: FileBankOwner, env: AppEnvironment) {
        if let item = o.itemID {
            env.navigator.navigate(to: item, childID: o.childID)
        } else if let m = o.crewMemberID {
            env.navigator.navigateToCrew(m)
        } else if o.savedListID != nil {
            env.navigator.select(.lists)
        }
    }
}
