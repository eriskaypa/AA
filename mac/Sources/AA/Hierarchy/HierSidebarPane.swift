// Spec: 04 HIER-001…006 (title, + New / Delete, wrapping toolbar with tooltips, search box, empty hints), HIER-010…020
//       (grouped list, headers "name (N)", placeholders, A→Z, expand persistence, multi-selection, wrapped names,
//       virtualised scale, context menu), HIER-M01 (drag to group), HIER-M02 (⌘⌫ / ⌫ delete), HIER-M03 (double-click
//       opens a window), HIER-M05 (lock glyph), §6.2 (Mac sidebar), §8 Q-02, Q-29, Q-30; 03 §6.5.1.10 (list role
//       hierarchySidebar: ⌘⌫ "Move to Trash", ↩ = Rename, X-8: double-click = Open in New Window), T-KB-02/03/24/25.
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
            HierToolbarFlow(spacing: 6, lineSpacing: 6) { toolbarButtons }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text(HierText.pageTitle(model.kind))
                .font(.aaMono(15, weight: .bold))
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

    @ViewBuilder private var toolbarButtons: some View {
        Button {
            model.newItem(dialogs: dialogs)
        } label: {
            Label(HierText.newButton, systemImage: "plus").labelStyle(.titleOnly)
        }
        .aaProminent()
        .help(SectionID.section(for: model.kind).newItemTitle ?? HierText.newButton)
        Button(role: .destructive) {
            Task { await model.deleteSelection(dialogs: dialogs) }
        } label: {
            Label(HierText.deleteButton, systemImage: "trash")
        }
        .disabled(model.selection.isEmpty && model.primaryItem == nil)
        .help(HierText.deleteSelectedHelp)
        Toggle(isOn: Binding(get: { model.sortAZ }, set: { model.setSortAZ($0) })) {
            Label(HierText.sortAZ, systemImage: "textformat.abc").labelStyle(.titleOnly)
        }
        .toggleStyle(.button)
        .help(HierText.sortAZHelp)
        Button {
            Task { await model.newGroup(dialogs: dialogs) }
        } label: { Label(HierText.newGroupButton, systemImage: "folder.badge.plus") }
            .help(HierText.newGroupHelp)
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
    }
}

/// Small bordered buttons that wrap like the Windows WrapPanel.
struct HierToolbarFlow<Content: View>: View {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        HierFlowLayout(spacing: spacing, lineSpacing: lineSpacing) { content() }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: AAType.caption))
    }
}

/// A left-aligned wrapping layout.
struct HierFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + lineSpacing; line = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + lineSpacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
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
                    } header: {
                        HierSectionHeader(section: section, model: model)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UUID.self) { ids in
                menu(for: ids)
            } primaryAction: { ids in
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
            .onChange(of: model.revealRequest?.token) { _, _ in
                guard let id = model.revealRequest?.id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id.netString) }
            }
        }
    }

    private func dragIDs(for id: UUID) -> [UUID] {
        model.selection.contains(id) ? model.selectedItems.map(\.id) : [id]
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
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy) { model.setExpanded(section, !expanded) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AAColor.muted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse \(section.title)" : "Expand \(section.title)")
            Image(systemName: section.groupID == nil ? "tray" : "folder")
                .imageScale(.small)
                .foregroundStyle(AAColor.muted)
            Text(section.title)
                .font(.aaMono(AAType.small, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("(\(section.count))")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .fill(targeted ? AAColor.tint.opacity(0.18) : Color.clear))
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
            if item.name.isEmpty {
                Text("(unnamed)").italic().foregroundStyle(AAColor.muted)
            } else {
                Text(item.name)
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
        .font(.aaMono(AAType.body))
        .padding(.vertical, 1)
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
        .font(.system(size: AAType.small, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
