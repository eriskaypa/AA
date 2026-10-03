// Spec: 05 CONT-080 (columns per tab, multi-selection, context menu Open / Open containing folder / Rename... /
//       Link to items... / — / Remove, double-click opens), 05 §6.9 (Table with icons/thumbnails, Space = Quick Look,
//       Return / double-click open, ⌘⌫ remove, ⌘C/⌘X/⌘V on the file-bank clipboard, drag rows OUT to Finder/Mail —
//       file URLs, links as URLs; context-menu additions Quick Look, Copy Path, Open With ▸), 03 SHELL-669 (Space),
//       SHELL-671 (⌘↓ open), SHELL-543 (⌘Y via ListCommands), SHELL-516/670 + T-KB-04/05 (⌘⌫ = Remove without
//       confirmation; plain ⌫ does nothing), SHELL-667 (↩ = Open), SHELL-677 (⌘A / ⌘-click / ⇧-click);
//       ARCHITECTURE.md §7.6 (`.aaListCommands`).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// Row-level actions (ids are resolved against the rows of the current render).
struct FileBankRowActions {
    var editable: Bool
    var open: (Set<FileBankRow.ID>) -> Void
    var showInFinder: (Set<FileBankRow.ID>) -> Void
    var quickLook: (Set<FileBankRow.ID>, _ toggle: Bool) -> Void
    var rename: (Set<FileBankRow.ID>) -> Void
    var linkToItems: (Set<FileBankRow.ID>) -> Void
    var remove: (Set<FileBankRow.ID>) -> Void
    var copyPath: (Set<FileBankRow.ID>) -> Void
    var cut: (Set<FileBankRow.ID>) -> Void
    var copy: (Set<FileBankRow.ID>) -> Void
    /// Fill the file-bank clipboard for the system Edit ▸ Copy / Cut (SwiftUI then writes the providers).
    var copyForPasteboard: (Set<FileBankRow.ID>) -> [FileItem]
    var cutForPasteboard: (Set<FileBankRow.ID>) -> [FileItem]
    var paste: () -> Void
    var showOwner: (Set<FileBankRow.ID>) -> Void
    var openWith: (URL, URL) -> Void
    var openWithOther: (URL) -> Void
}

// MARK: - Context menu (CONT-080 + 05 §6.9 additions)

struct FileBankContextMenu: View {
    let ids: Set<FileBankRow.ID>
    let rows: [FileBankRow]
    let isShared: Bool
    let actions: FileBankRowActions

    var body: some View {
        let picked = rows.filter { ids.contains($0.id) }
        if !picked.isEmpty {
            Button(FileBankText.menuOpen) { actions.open(ids) }
            Button(FileBankText.menuShowInFinder) { actions.showInFinder(ids) }
            Button(FileBankText.menuQuickLook) { actions.quickLook(ids, false) }
                .disabled(!picked.contains { $0.visual.localURL != nil })
            if let url = picked.first?.visual.localURL, picked.first?.visual.glyph == .file {
                Menu(FileBankText.menuOpenWith) {
                    ForEach(FileBankOpening.applications(for: url), id: \.self) { app in
                        Button {
                            actions.openWith(url, app)
                        } label: {
                            Label {
                                Text(FileManager.default.displayName(atPath: app.path))
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            }
                        }
                    }
                    Divider()
                    Button(FileBankText.menuOtherApp) { actions.openWithOther(url) }
                }
            }
            Divider()
            if isShared {
                Button(FileBankText.menuGoToOwner) { actions.showOwner(ids) }
                Button(FileBankText.copy) { actions.copy(ids) }
                Button(FileBankText.menuCopyPath) { actions.copyPath(ids) }
            } else {
                Button(FileBankText.menuRename) { actions.rename(ids) }.disabled(!actions.editable)
                Button(FileBankText.menuLinkToItems) { actions.linkToItems(ids) }.disabled(!actions.editable)
                Button(FileBankText.menuCopyPath) { actions.copyPath(ids) }
                Divider()
                Button(FileBankText.cut) { actions.cut(ids) }.disabled(!actions.editable)
                Button(FileBankText.copy) { actions.copy(ids) }
                Button(FileBankText.paste) { actions.paste() }.disabled(!actions.editable)
                Divider()
                Button(FileBankText.menuRemove, role: .destructive) { actions.remove(ids) }.disabled(!actions.editable)
            }
        } else if !isShared {
            Button(FileBankText.paste) { actions.paste() }.disabled(!actions.editable)
        }
    }
}

// MARK: - List view (Table)

struct FileBankTable: View {
    let rows: [FileBankRow]
    let columns: [FileBankColumn]
    let isShared: Bool
    @Binding var selection: Set<FileBankRow.ID>
    let actions: FileBankRowActions
    @State private var keys = FileBankKeyMonitor()

    var body: some View {
        Table(of: FileBankRow.self, selection: $selection) {
            TableColumn(FileBankText.columnName) { r in nameCell(r) }
                .width(min: 140, ideal: 280)
            if columns.contains(.kind) {
                TableColumn(FileBankText.columnKind) { r in
                    Text(FileBankDisplay.kindName(r.file.kind)).foregroundStyle(AAColor.fg)
                }
                .width(min: 50, ideal: 80, max: 120)
            }
            if columns.contains(.source) {
                TableColumn(FileBankText.columnSource) { r in FileBankSourceLabel(file: r.file) }
                    .width(min: 56, ideal: 76, max: 110)
            }
            if columns.contains(.added) {
                TableColumn(FileBankText.columnAdded) { r in
                    Text(r.added).monospacedDigit().foregroundStyle(AAColor.muted).lineLimit(1)
                }
                .width(min: 90, ideal: 140, max: 200)
            }
            if isShared {
                TableColumn(FileBankText.sharedFromColumn) { r in
                    Text(r.owner?.label ?? FileBankText.unknownContainer).foregroundStyle(AAColor.fg).lineLimit(1)
                        .truncationMode(.middle).help(r.owner?.label ?? "")
                }
                .width(min: 100, ideal: 220)
            }
            if columns.contains(.linkedTo) {
                TableColumn(FileBankText.linkedToColumn) { r in linkedCell(r) }
                    .width(min: 70, ideal: 160)
            }
            if columns.contains(.path) {
                TableColumn(FileBankText.columnPath) { r in pathCell(r.file.path) }
                    .width(min: 100, ideal: 500)
            }
            if columns.contains(.url) {
                TableColumn(FileBankText.columnURL) { r in pathCell(r.file.path) }
                    .width(min: 100, ideal: 500)
            }
        } rows: {
            ForEach(rows) { r in
                TableRow(r)
                    .itemProvider { [url = r.dragURL, web = r.isWeb] in FileBankTable.provider(url, web: web) }
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
        .environment(\.defaultMinListRowHeight, 22)
        .contextMenu(forSelectionType: FileBankRow.ID.self) { ids in
            FileBankContextMenu(ids: ids, rows: rows, isShared: isShared, actions: actions)
        } primaryAction: { ids in
            actions.open(ids)                                            // ↩ and double-click (CONT-089, SHELL-667)
        }
        .onCopyCommand { providers(for: actions.copyForPasteboard(selection)) }
        .onCutCommand { isShared ? [] : providers(for: actions.cutForPasteboard(selection)) }
        .onPasteCommand(of: [.item]) { _ in if !isShared { actions.paste() } }
        .background(FileBankKeyAnchor(monitor: keys, onSpace: { actions.quickLook(selection, true) },
                                      onOpen: { if !selection.isEmpty { actions.open(selection) } }))
        .onAppear { keys.install() }
        .onDisappear { keys.remove() }
        .aaListCommands(listCommands)
    }

    private var listCommands: ListCommands {
        FileBankTable.listCommands(rows: rows, selection: selection, isShared: isShared, actions: actions)
    }

    /// The router publication of a file-bank list (Table or icon grid), decided by `FileBankListPolicy`.
    static func listCommands(rows: [FileBankRow], selection sel: Set<FileBankRow.ID>, isShared: Bool,
                             actions: FileBankRowActions) -> ListCommands {
        let hasLocal = rows.contains { sel.contains($0.id) && $0.visual.localURL != nil }
        let canRemove = FileBankListPolicy.removeAvailable(editable: actions.editable, isShared: isShared)
        return ListCommands(role: .fileBank, selectionCount: sel.count, deleteTitle: FileBankListPolicy.deleteTitle,
                            delete: canRemove ? { actions.remove(sel) } : nil,
                            deleteConfirms: FileBankListPolicy.deleteConfirms,
                            quickLook: FileBankListPolicy.quickLookAvailable(selectionHasLocalFile: hasLocal)
                                ? { actions.quickLook(sel, false) } : nil,
                            primary: { actions.open(sel) })
    }

    private func providers(for files: [FileItem]) -> [NSItemProvider] {
        let ids = selection
        let urls = rows.filter { ids.contains($0.id) }.compactMap { r -> (URL, Bool)? in r.dragURL.map { ($0, r.isWeb) } }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !files.isEmpty { FileBankClipboard.shared.mirroredPasteboardChangeCount = NSPasteboard.general.changeCount }
            }
        }
        return urls.compactMap { FileBankTable.provider($0.0, web: $0.1) }
    }

    nonisolated static func provider(_ url: URL?, web: Bool) -> NSItemProvider? {
        guard let url else { return nil }
        if web { return NSItemProvider(object: url as NSURL) }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
    }

    private func nameCell(_ r: FileBankRow) -> some View {
        HStack(spacing: 6) {
            FileBankFileIcon(visual: r.visual, size: 16)
            Text(r.file.name).foregroundStyle(AAColor.fg).lineLimit(1).truncationMode(.middle)
        }
        .help(r.file.name)
    }

    @ViewBuilder private func linkedCell(_ r: FileBankRow) -> some View {
        if r.linkedSummary.isEmpty {
            Text("—").foregroundStyle(AAColor.muted.opacity(0.6))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "link").imageScale(.small).foregroundStyle(AAColor.tint)
                Text(r.linkedSummary).foregroundStyle(AAColor.fg).lineLimit(1).truncationMode(.tail)
            }
            .help(r.linkedSummary)
        }
    }

    private func pathCell(_ path: String) -> some View {
        Text(path).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).lineLimit(1).truncationMode(.middle)
            .help(path)
    }
}

// MARK: - Icon view (grid)

struct FileBankGrid: View {
    let rows: [FileBankRow]
    let isShared: Bool
    @Binding var selection: Set<FileBankRow.ID>
    let actions: FileBankRowActions
    @State private var anchorID: FileBankRow.ID?
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 6, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(rows) { r in
                    tile(r)
                }
            }
            .padding(AASpacing.s)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AAColor.panel)
        .contentShape(Rectangle())
        .onTapGesture { selection = [] }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { actions.quickLook(selection, true); return .handled }
        .onKeyPress(.return) { if !selection.isEmpty { actions.open(selection) }; return .handled }
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if !selection.isEmpty { actions.open(selection) }
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            step(press.key == .rightArrow ? 1 : -1, extend: press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            selection = Set(rows.map(\.id))
            return .handled
        }
        .onCopyCommand { FileBankGrid.providers(rows, actions.copyForPasteboard(selection), selection) }
        .onCutCommand { isShared ? [] : FileBankGrid.providers(rows, actions.cutForPasteboard(selection), selection) }
        .onPasteCommand(of: [.item]) { _ in if !isShared { actions.paste() } }
        .aaListCommands(FileBankTable.listCommands(rows: rows, selection: selection, isShared: isShared, actions: actions))
    }

    static func providers(_ rows: [FileBankRow], _ files: [FileItem], _ ids: Set<FileBankRow.ID>) -> [NSItemProvider] {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !files.isEmpty { FileBankClipboard.shared.mirroredPasteboardChangeCount = NSPasteboard.general.changeCount }
            }
        }
        return rows.filter { ids.contains($0.id) }.compactMap { FileBankTable.provider($0.dragURL, web: $0.isWeb) }
    }

    private func tile(_ r: FileBankRow) -> some View {
        let selected = selection.contains(r.id)
        return VStack(spacing: 4) {
            FileBankFileIcon(visual: r.visual, size: 56)
                .frame(width: 64, height: 60)
                .padding(4)
                .background(selected ? AAColor.selectionBg.opacity(0.55) : .clear,
                            in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
            Text(r.file.name)
                .font(.system(size: AAType.caption, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : AAColor.fg)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(selected ? AAColor.tint : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            HStack(spacing: 3) {
                if !r.file.linkedItemIds.isEmpty {
                    Image(systemName: "link").imageScale(.small).foregroundStyle(AAColor.tint)
                }
                Text(isShared ? (r.owner?.label ?? "") : r.file.sourceLabel)
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(AAColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help(r.linkedSummary.isEmpty ? r.file.name : "\(r.file.name)\n\(FileBankText.linkedToColumn): \(r.linkedSummary)")
        .onTapGesture(count: 2) {
            selection = [r.id]
            actions.open([r.id])
        }
        .onTapGesture { click(r) }
        .onDrag { FileBankTable.provider(r.dragURL, web: r.isWeb) ?? NSItemProvider() }
        .contextMenu {
            let ids = selection.contains(r.id) ? selection : [r.id]
            FileBankContextMenu(ids: ids, rows: rows, isShared: isShared, actions: actions)
        }
    }

    /// Finder clicks: plain = select, ⌘ = toggle, ⇧ = extend the range from the anchor.
    private func click(_ r: FileBankRow) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(r.id) { selection.remove(r.id) } else { selection.insert(r.id) }
            anchorID = r.id
        } else if flags.contains(.shift), let a = anchorID, let ia = rows.firstIndex(where: { $0.id == a }),
                  let ib = rows.firstIndex(where: { $0.id == r.id }) {
            selection = Set(rows[min(ia, ib)...max(ia, ib)].map(\.id))
        } else {
            selection = [r.id]
            anchorID = r.id
        }
    }

    private func step(_ delta: Int, extend: Bool) {
        guard !rows.isEmpty else { return }
        let current = anchorID.flatMap { a in rows.firstIndex { $0.id == a } }
            ?? rows.firstIndex { selection.contains($0.id) }
        let next = min(max((current ?? (delta > 0 ? -1 : rows.count)) + delta, 0), rows.count - 1)
        if extend { selection.insert(rows[next].id) } else { selection = [rows[next].id] }
        anchorID = rows[next].id
    }
}

// MARK: - Space / ⌘↓ on the Table (NSTableView consumes Space for type-select, so a local monitor handles them)

@MainActor final class FileBankKeyMonitor {
    weak var anchor: NSView?
    var onSpace: () -> Void = {}
    var onOpen: () -> Void = {}
    private var token: Any?

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
            let windowNumber = event.windowNumber
            let swallow = MainActor.assumeIsolated {
                self?.handle(keyCode: key, flags: NSEvent.ModifierFlags(rawValue: flags), windowNumber: windowNumber) ?? false
            }
            return swallow ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    /// True when the key was handled (the event is swallowed).
    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let anchor, let w = anchor.window, w.windowNumber == windowNumber, w.isKeyWindow,
              let table = w.firstResponder as? NSTableView, table.window === w else { return false }
        let a = anchor.convert(anchor.bounds, to: nil)
        let t = table.convert(table.visibleRect, to: nil)
        guard a.contains(CGPoint(x: t.midX, y: t.midY)) else { return false }
        if keyCode == 49, flags.isEmpty {                                            // Space (SHELL-669)
            onSpace()
            return true
        }
        if keyCode == 125, flags == .command {                                      // ⌘↓ (SHELL-671)
            onOpen()
            return true
        }
        return false
    }
}

/// The NSView behind the table, used to tell whether the focused NSTableView is this file bank's. Every render hands
/// the monitor fresh handlers (they resolve ids against the rows of that render) and installs it while on screen.
struct FileBankKeyAnchor: NSViewRepresentable {
    let monitor: FileBankKeyMonitor
    let onSpace: () -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        apply(v)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { apply(nsView) }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {}

    private func apply(_ v: NSView) {
        monitor.anchor = v
        monitor.onSpace = onSpace
        monitor.onOpen = onOpen
    }
}
