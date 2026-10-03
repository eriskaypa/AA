// Spec: 04 HIER-001…006 (title, + New / Delete, the toolbar commands with tooltips — one Mac icon bar, V-DESIGN
//       rule 4 —, search box, empty hints), HIER-010…020
//       (grouped list, headers "name (N)", placeholders, A→Z, expand persistence, multi-selection, wrapped names,
//       virtualised scale, context menu), HIER-M01 (drag to group), HIER-M02 (⌘⌫ / ⌫ delete), HIER-M03 (double-click
//       opens a window), HIER-M05 (lock glyph), §6.2 (Mac sidebar), §8 Q-02, Q-29, Q-30; 03 §6.5.1.10 (list role
//       hierarchySidebar: ⌘⌫ "Move to Trash", ↩ = Rename, X-8: double-click = Open in New Window), T-KB-02/03/24/25;
//       HIER-120/121 + §3.2 `SelectItemsByIds` (the selected row is revealed — at launch too; V2-SCALE), V2-COMPAT
//       (rows keyed by `HierRowKey`, so items sharing an Id keep their own rows).
import AppKit
import SwiftUI
import AACore

struct HierSidebarPane: View {
    @Bindable var model: HierPageModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HierSidebarIconBar(model: model)
                .padding(.horizontal, AASpacing.m)
                .padding(.bottom, AASpacing.s)
            AASearchField(text: $model.query, prompt: HierText.searchPrompt)
                .background(HierFieldAnchor(locator: model.searchLocator))
                .padding(.horizontal, AASpacing.m)
                .padding(.bottom, AASpacing.s)
            Divider()
            HierSidebarList(model: model)
        }
        .background(HierSidebarWatcher(model: model))
    }

    /// Title + count on one compact row (design rule 4).
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text(HierText.pageTitle(model.kind))
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .lineLimit(1)
            Spacer(minLength: AASpacing.xs)
            Text(model.sidebar.totalCount == 1 ? "1 item" : "\(model.sidebar.totalCount) items")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.top, AASpacing.m)
        .padding(.bottom, AASpacing.s)
    }
}

/// HIER-003/004 as one icon bar (design rule 4): `plus` (click = + New, arrow = + New / + Group), `trash` = Delete,
/// the A→Z toggle, and a trailing overflow menu with Assign group…, Rename group…, Delete group. Every command keeps
/// its spec name (accessibility label / menu title), tooltip and enablement; the row context menu and the menu bar
/// are unchanged.
struct HierSidebarIconBar: View {
    @Bindable var model: HierPageModel
    @Environment(\.dialogs) private var dialogs

    private var newHelp: String { SectionID.section(for: model.kind).newItemTitle ?? HierText.newButton }

    var body: some View {
        HStack(spacing: AASpacing.xs) {
            Menu {
                Button { model.newItem(dialogs: dialogs) } label: {
                    Label(HierText.newButton, systemImage: "plus")
                }
                .help(newHelp)
                Button { Task { await model.newGroup(dialogs: dialogs) } } label: {
                    Label(HierText.newGroupButton, systemImage: "folder.badge.plus")
                }
                .help(HierText.newGroupHelp)
            } label: {
                Label(HierText.newButton, systemImage: "plus")
            } primaryAction: {
                model.newItem(dialogs: dialogs)
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help(newHelp)
            .accessibilityLabel(HierText.newButton)

            Button(role: .destructive) {
                Task { await model.deleteSelection(dialogs: dialogs) }
            } label: {
                Label(HierText.deleteButton, systemImage: "trash")
            }
            .disabled(model.selection.isEmpty && model.primaryItem == nil)
            .help(HierText.deleteSelectedHelp)
            .accessibilityLabel(HierText.deleteButton)

            Toggle(isOn: Binding(get: { model.sortAZ }, set: { model.setSortAZ($0) })) {
                Label(HierText.sortAZ, systemImage: "arrow.up.arrow.down")
            }
            .toggleStyle(.button)
            .help(HierText.sortAZHelp)
            .accessibilityLabel(HierText.sortAZ)

            Spacer(minLength: 0)

            Menu {
                Button {
                    Task { await model.assignGroup(model.selectedItems, dialogs: dialogs) }
                } label: { Label(HierText.assignGroupButton, systemImage: "folder") }
                    .help(HierText.assignGroupHelp)
                Button {
                    Task { await model.renameGroup(dialogs: dialogs) }
                } label: { Label(HierText.renameGroupButton, systemImage: "pencil") }
                    .help(HierText.renameGroupHelp)
                Button {
                    Task { await model.deleteGroup(dialogs: dialogs) }
                } label: { Label(HierText.deleteGroupButton, systemImage: "folder.badge.minus") }
                    .help(HierText.deleteGroupHelp)
            } label: {
                Label(HierText.groupCommandsMenu, systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)                    // grey like its sibling icons (rule 4)
            }
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .help(HierText.groupCommandsHelp)
            .accessibilityLabel(HierText.groupCommandsMenu)
        }
        .labelStyle(.iconOnly)
        .symbolRenderingMode(.hierarchical)
        .fontWeight(.regular)
        .buttonStyle(.accessoryBar)
        .menuStyle(.button)
        .frame(height: 24)
    }
}

/// Rebuilds the sidebar whenever the kind's collection or groups change anywhere (HIER-125 / Q-07: live).
struct HierSidebarWatcher: View {
    let model: HierPageModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let sig = HierStructureSignature(store: env.store, kind: model.kind, editingNameID: model.editingNameID,
                                         includeTags: TagParser.isHashQuery(NetText.trim(model.query)))
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: sig) { _, _ in model.rebuild() }
    }
}

// MARK: The list

struct HierSidebarList: View {
    @Bindable var model: HierPageModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selection) {
                ForEach(model.sidebar.sections) { section in
                    Section {
                        // The header is a non-selectable row, not a pinned List header: a pinned (floating) header
                        // draws a full-width separator that does not line up with the row separators.
                        HierSectionHeader(section: section, model: model)
                            .id(HierSidebar.headerRowID(section.id))
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                            .accessibilityAddTraits(.isHeader)
                        if model.isExpanded(section) {
                        ForEach(section.rows) { row in
                            if let id = row.itemID, let item = model.item(id) {
                                HierSidebarRowView(item: item)
                                    .tag(id)
                                    .draggable(HierItemDrag(ids: dragIDs(for: id))) {
                                        HierDragPreview(count: dragIDs(for: id).count, name: item.name)
                                    }
                            } else {
                                Text(HierText.placeholderRow)
                                    .font(.aaMono(AAType.caption))
                                    .italic()
                                    .foregroundStyle(AAColor.muted)
                                    .selectionDisabled()
                                    .dropDestination(for: HierItemDrag.self) { (payloads: [HierItemDrag], _: CGPoint) -> Bool in
                                        model.drop(payloads.flatMap(\.ids), onto: section.groupID, dialogs: dialogs)
                                    }
                            }
                        }
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UUID.self) { ids in
                menu(for: ids)
            } primaryAction: { ids in
                guard !ids.isEmpty else { return }                                          // not on a row
                model.openInWindow(model.items(for: ids), dialogs: dialogs)                     // M03 / T-KB-25
            }
            .onKeyPress(.return) {                                                          // T-KB-24, 03 X-8
                guard model.primaryItem != nil else { return .ignored }
                model.beginRename()
                return .handled
            }
            .aaListCommands(ListCommands(
                role: .hierarchySidebar, selectionCount: model.selection.count, deleteTitle: HierText.moveToTrash,
                delete: { Task { await model.deleteSelection(dialogs: dialogs) } },
                primary: { model.beginRename() }))
            .overlay(alignment: model.sidebar.sections.isEmpty ? .center : .bottom) { hint }
            // HIER-121 restores the selection before this view exists, so the current request is honoured on
            // appear as well as on every new token (`.onChange` never sees the initial value).
            .task(id: model.revealRequest?.token) {
                guard model.revealRequest != nil else { return }
                await reveal(with: proxy)
            }
        }
    }

    /// Centres the requested row. The List measures its (wrapping, variable-height) rows lazily, so the first jump
    /// lands on estimated offsets in a long list; the jump is repeated once the rows around the target have been
    /// measured, which settles it on the row (V2-SCALE: 500 / 5 000-row sidebars).
    private func reveal(with proxy: ScrollViewProxy) async {
        for delay in HierSidebarList.revealPasses {
            if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
            guard !Task.isCancelled, let target = model.revealRowID else { return }
            proxy.scrollTo(target, anchor: .center)
        }
    }

    /// Delays (ms) before each scroll pass of a reveal.
    static let revealPasses = [0, 16, 80, 200]

    private func dragIDs(for id: UUID) -> [UUID] {
        model.selection.contains(id) ? model.rowKeys(model.selectedItems) : [id]       // row keys (V2-COMPAT)
    }

    @ViewBuilder private var hint: some View {
        if let text = model.sidebar.emptyHint {
            Text(text)
                .font(.aaMono(AAType.body))
                .foregroundStyle(AAColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
                .padding(AASpacing.l)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// HIER-020 (the native targeting: the clicked selection, or the clicked row; empty space → only New group…).
    @ViewBuilder private func menu(for ids: Set<UUID>) -> some View {
        let items = model.items(for: ids)
        Button {
            model.openInWindow(items, dialogs: dialogs)
        } label: { Label(HierText.openInNewWindow, systemImage: "macwindow.badge.plus") }
            .help(HierText.openInNewWindowHelp)
            .disabled(items.isEmpty)
        Divider()
        Button {
            Task { await model.assignGroup(items, dialogs: dialogs) }
        } label: { Label(HierText.moveToGroup, systemImage: "folder") }
            .disabled(items.isEmpty)
        Button {
            model.removeFromGroup(items, dialogs: dialogs)
        } label: { Label(HierText.removeFromGroup, systemImage: "folder.badge.minus") }
            .disabled(!items.contains { $0.groupId != nil })
        Divider()
        Button {
            Task { await model.newGroup(dialogs: dialogs) }
        } label: { Label(HierText.newGroupMenu, systemImage: "folder.badge.plus") }
        Divider()
        Button(role: .destructive) {
            Task { await model.delete(items, dialogs: dialogs) }
        } label: { Label(HierText.deleteSelected, systemImage: "trash") }
            .help(HierText.deleteSelectedHelp)
            .disabled(items.isEmpty)
    }
}

/// "name (N)" header (HIER-010) that accepts dropped rows (M01).
struct HierSectionHeader: View {
    let section: HierSidebarSection
    let model: HierPageModel
    @Environment(\.dialogs) private var dialogs
    @State private var targeted = false

    var body: some View {
        let expanded = model.isExpanded(section)
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.xs) {
            Button {
                withAnimation(.snappy) { model.setExpanded(section, !expanded) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.aaMono(AAType.caption, weight: .bold))
                    .imageScale(.small)
                    .foregroundStyle(AAColor.muted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse \(section.title)" : "Expand \(section.title)")
            Image(systemName: section.groupID == nil ? "tray" : "folder")
                .font(.aaMono(AAType.small))
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AAColor.muted)
            // HIER-010: the full group name wraps (never truncated), with the muted "(N)" following it.
            Text("\(Text(section.title).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.accent)) \(Text("(\(section.count))").font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).monospacedDigit())")
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .fill(targeted ? AAColor.tint.opacity(0.18) : AAColor.panelAlt))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .strokeBorder(targeted ? AAColor.tint : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { withAnimation(.snappy) { model.setExpanded(section, !expanded) } }
        .dropDestination(for: HierItemDrag.self) { payloads, _ in
            model.drop(payloads.flatMap(\.ids), onto: section.groupID, dialogs: dialogs)
        } isTargeted: { t in
            withAnimation(.easeOut(duration: 0.12)) { targeted = t }
        }
        .help(section.groupID == nil ? "Drop items here to take them out of every group."
                                     : "Drop items here to move them into “\(section.title)”.")
    }
}

/// One sidebar row: the wrapped name (HIER-018) and the lock glyph (M05). Observes the item, so typing a name
/// re-labels the row in place.
struct HierSidebarRowView: View {
    let item: HierarchyItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The font sits on the Text itself: the List row host replaces an inherited row font (design rule 2).
            if item.name.isEmpty {
                Text("(unnamed)").font(.aaMono(AAType.body)).italic().foregroundStyle(AAColor.muted)
            } else {
                Text(item.name)
                    .font(.aaMono(AAType.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
            Spacer(minLength: 0)
            if item.isLockProtected {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .help("Password-protected")
                    .accessibilityLabel("Password-protected")
            }
        }
        .padding(.vertical, 2)
    }
}

struct HierDragPreview: View {
    let count: Int
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: count > 1 ? "square.stack" : "doc")
            Text(count > 1 ? "\(count) items" : name).lineLimit(1)
        }
        .font(.aaMono(AAType.small, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
