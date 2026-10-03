// Spec: DECISIONS 05 ("item backlinks": every FileItem whose LinkedItemIds contains the item, with its container
//       owner; open / show in Finder), 05 CONT-093 (links are top-level item ids; the Mac surfaces them),
//       ARCHITECTURE.md §7.7 (`FileBacklinksSection(itemID:)`, embedded by W-HIER's Relationships tab), §2.4 (ids,
//       not references, across renders), 04 Q-F / PDF Q6 analogue (files of a password-gated owner are not listed:
//       only that a locked item links here).
import AppKit
import SwiftUI
import AACore

struct FileBacklinksSection: View {
    let itemID: UUID

    init(itemID: UUID) { self.itemID = itemID }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var selection: Set<String> = []
    @State private var keys = FileBankKeyMonitor()

    var body: some View {
        let model = FileBankBacklinksModel(itemID: itemID, env: env)
        VStack(alignment: .leading, spacing: AASpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(AAColor.tint)
                AASectionHeader(title: FileBankText.backlinksTitle, count: model.total)
            }
            if model.rows.isEmpty && model.locked.isEmpty {
                AAHelpText(FileBankText.backlinksEmpty)
            } else {
                list(model)
                    .frame(height: min(CGFloat(model.rows.count + model.locked.count) * 44 + 10, 280))
                AAHelpText(FileBankText.backlinksCount(model.total))
            }
        }
    }

    private func list(_ model: FileBankBacklinksModel) -> some View {
        List(selection: $selection) {
            ForEach(model.rows) { r in
                row(r)
                    .tag(r.id)
                    .onDrag { FileBankTable.provider(r.dragURL, web: r.isWeb) ?? NSItemProvider() }
            }
            ForEach(Array(model.locked.enumerated()), id: \.offset) { _, label in
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(AAColor.muted).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(FileBankText.lockedOwnerFiles).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
                        Text(label).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).lineLimit(1)
                    }
                }
                .selectionDisabled()
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds(.enabled)
        .contextMenu(forSelectionType: String.self) { ids in
            menu(model, ids)
        } primaryAction: { ids in
            open(model.rows.filter { ids.contains($0.id) })
        }
        .background(FileBankKeyAnchor(monitor: keys))
        .onAppear { wire(model); keys.install() }
        .onChange(of: selection) { _, _ in wire(model) }
        .onDisappear { keys.remove() }
        .aaListCommands(ListCommands(role: .other, selectionCount: selection.count,
                                     quickLook: { [sel = selection] in quickLook(model, sel, toggle: false) },
                                     primary: { [sel = selection] in open(model.rows.filter { sel.contains($0.id) }) }))
    }

    private func row(_ r: FileBankBacklinkRow) -> some View {
        HStack(spacing: 8) {
            FileBankFileIcon(visual: r.visual, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.link.file.name).font(.aaMono(AAType.body)).foregroundStyle(AAColor.fg).lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(FileBankText.backlinksInColumn).foregroundStyle(AAColor.muted)
                    Text(r.link.owner.label).foregroundStyle(AAColor.muted).lineLimit(1).truncationMode(.middle)
                }
                .font(.aaMono(AAType.caption))
            }
            Spacer(minLength: AASpacing.s)
            FileBankSourceLabel(file: r.link.file).font(.system(size: AAType.caption))
        }
        .padding(.vertical, 1)
        .help("\(r.link.file.name)\n\(FileBankText.backlinksInColumn) \(r.link.owner.label)")
    }

    @ViewBuilder private func menu(_ model: FileBankBacklinksModel, _ ids: Set<String>) -> some View {
        let picked = model.rows.filter { ids.contains($0.id) }
        if let first = picked.first {
            Button(FileBankText.menuOpen) { open(picked) }
            Button(FileBankText.menuShowInFinder) {
                Task { await FileBankOpening.showInFinder(first.link.file, env: env, dialogs: dialogs) }
            }
            Button(FileBankText.menuQuickLook) { quickLook(model, ids, toggle: false) }
                .disabled(!picked.contains { $0.visual.localURL != nil })
            Divider()
            Button(FileBankText.menuGoToOwner) { FileBankNavigation.reveal(first.link.owner, env: env) }
            Button(FileBankText.menuLinkToItems) {
                let c = FileBankController(container: first.link.container, env: env, dialogs: dialogs)
                Task { await c.linkToItems(first.link.file) }
            }
            Button("Unlink from This Item") { unlink(picked) }
        }
    }

    // MARK: Behaviour

    private func wire(_ model: FileBankBacklinksModel) {
        let sel = selection
        keys.onSpace = { quickLook(model, sel, toggle: true) }
        keys.onOpen = { open(model.rows.filter { sel.contains($0.id) }) }
    }

    private func open(_ rows: [FileBankBacklinkRow]) {
        Task { for r in rows { await FileBankOpening.open(r.link.file, env: env, dialogs: dialogs, style: .fileBank) } }
    }

    private func quickLook(_ model: FileBankBacklinksModel, _ ids: Set<String>, toggle: Bool) {
        if toggle, QuickLookCoordinator.shared.isVisible { QuickLookCoordinator.shared.close(); return }
        let sel = model.rows.filter { ids.contains($0.id) }.map(\.link.file)
        guard !sel.isEmpty else { NSSound.beep(); return }
        FileBankOpening.quickLook(sel.count > 1 ? sel : model.rows.map(\.link.file), selected: sel.first, env: env,
                                  toggle: false)
    }

    /// Removes this item from the picked files' `LinkedItemIds` (MarkDirty, like CONT-093).
    private func unlink(_ rows: [FileBankBacklinkRow]) {
        var changed = false
        for r in rows where r.link.file.linkedItemIds.contains(itemID) {
            r.link.file.linkedItemIds.removeAll { $0 == itemID }
            changed = true
        }
        if changed { env.store.markDirty() }
        selection = []
    }
}

struct FileBankBacklinkRow: Identifiable {
    let link: FileBankBacklink
    let visual: FileBankVisual
    let id: String

    @MainActor init(link: FileBankBacklink, visual: FileBankVisual) {
        self.link = link; self.visual = visual; self.id = link.id
    }

    var dragURL: URL? {
        switch visual.state {
        case .present(let u): return u
        case .web(let u): return u
        default: return nil
        }
    }
    var isWeb: Bool { if case .web = visual.state { return true }; return false }
}

/// Backlinks of one item for one render; files in password-gated owners collapse to one "locked" line per owner.
@MainActor struct FileBankBacklinksModel {
    var rows: [FileBankBacklinkRow] = []
    var locked: [String] = []
    /// Files hidden behind password-gated owners (counted, never named).
    var lockedFileCount = 0

    var total: Int { rows.count + lockedFileCount }

    init(itemID: UUID, env: AppEnvironment) {
        let dir = FileBankDirectory(store: env.store)
        var lockedOwners: [String] = []
        for b in dir.backlinks(to: itemID) {
            if let gate = b.owner.gatingItemID, let item = env.store.item(id: gate), env.locks.isGated(item) {
                if !lockedOwners.contains(b.owner.label) { lockedOwners.append(b.owner.label) }
                lockedFileCount += 1
                continue
            }
            rows.append(FileBankBacklinkRow(link: b, visual: FileBankVisual(b.file, dataStore: env.dataStore)))
        }
        locked = lockedOwners
    }
}
