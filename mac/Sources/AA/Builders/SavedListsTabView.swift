// Spec: 06 §G BUILD-070…090 (Saved Lists tab: groups, arranged order, A–Z, rename, delete, duplicate, edit items via
//       the template editor, read-only item viewer, export buttons → W-PDF), BUILD-A10, §6.3 (Mac layout; Export ALL
//       always reachable — R3), §8 D1 (group by Id), D2 (Move to group preselects the current group, OK needs a
//       choice), 02 REPO-130…134 (order, guards, messages), 03 SHELL-540 ("New List…" ⇧⌘N), SHELL-544/581…583 via
//       ListCommands role `savedLists` (T-KB-33: ⌃⌘↑ / ⇧⌘M disabled while Sort A–Z is on), 07 VIEW-212 rows 4–6;
//       ARCHITECTURE.md §7.2 (HSplitView inside a section), §7.7 (`SavedListsTabView()` for F3).
import AppKit
import SwiftUI
import AACore

struct SavedListsTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var selection: Set<UUID> = []
    @State private var statusOverride: String?
    @State private var busy = false
    @State private var itemSelection: Set<UUID> = []
    /// The list to bring into view after + List, Duplicate and reorders (BUILD-080, 083, 085).
    @State private var scrollTarget: UUID?

    init() {}

    /// Debug snapshots: open with a list already selected.
    init(initialSelection: Set<UUID>) { _selection = State(initialValue: initialSelection) }

    var body: some View {
        let data = env.store.data
        let sortAZ = BuilderSavedLists.isSortAZ(data)
        let sections = BuilderSavedLists.sections(data, sortAZ: sortAZ)
        let primary = BuilderSavedLists.primary(sections, ids: selection, data: data)
        return HSplitView {
            sidebar(sections: sections, sortAZ: sortAZ)
                .frame(minWidth: 290, idealWidth: 340, maxWidth: 520, minHeight: 0, maxHeight: .infinity)
            detail(primary)
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .background(AAColor.bg)
        .onAppear { statusOverride = nil }
        .onChange(of: env.store.generation) { _, _ in
            // A reload replaced the data: keep only selections that still resolve (ARCH §2.4).
            let ids = Set(env.store.data.checklistTemplates.map(\.id))
            selection = selection.filter { ids.contains($0) }
        }
        .aaSectionCommands(.lists, SectionCommands(newItemTitle: "New List…", newItem: { run { await newList() } }))
    }

    // MARK: Sidebar (BUILD-071…073, 088, 090)

    private func sidebar(sections: [BuilderSavedListSection], sortAZ: Bool) -> some View {
        let reorder = reorderAvailability(sortAZ: sortAZ)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved Lists").font(.aaMono(AAType.title, weight: .bold)).foregroundStyle(AAColor.accent)
                Spacer()
                Text("\(env.store.data.checklistTemplates.count)")
                    .font(.aaMono(AAType.caption)).monospacedDigit().foregroundStyle(AAColor.muted)
                    .accessibilityLabel("\(env.store.data.checklistTemplates.count) saved lists")
            }
            .padding(.horizontal, AASpacing.m)
            .padding(.top, AASpacing.m)
            .padding(.bottom, AASpacing.xs)
            toolbar(sortAZ: sortAZ)
                .padding(.horizontal, AASpacing.m)
                .padding(.bottom, AASpacing.s)
            Divider()
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                BuilderSavedListRowView(row: row).tag(row.id)
                                    .listRowSeparator(.visible)
                            }
                            .onMove(perform: sortAZ ? nil : { src, dst in dropMove(section, src, dst) })
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: section.groupID == nil ? "tray" : "folder")
                                    .foregroundStyle(AAColor.muted)
                                Text(section.title).font(.aaMono(AAType.small, weight: .bold))
                                    .foregroundStyle(AAColor.accent)
                                Text("(\(section.count))").font(.aaMono(AAType.caption)).monospacedDigit()
                                    .foregroundStyle(AAColor.muted)
                            }
                        }
                    }
                }
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
                    scrollTarget = nil
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .overlay {
                if sections.isEmpty {
                    AAEmptyState(title: "No saved lists", symbol: "list.bullet.rectangle",
                                 message: "Build a checklist anywhere and click Save as list…, or click + List.")
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenu(ids)
            } primaryAction: { ids in
                selection = ids
                run { await editItems() }
            }
            .aaListCommands(ListCommands(role: .savedLists, selectionCount: selection.count, deleteTitle: "Delete",
                                         delete: { run { await deleteList() } }, deleteConfirms: true,
                                         canMoveUp: reorder.up, canMoveDown: reorder.down,
                                         move: { dir in run { await nudge(up: dir == .up) } },
                                         moveTo: sortAZ || selection.isEmpty ? nil : { run { await moveToPosition() } },
                                         primary: { run { await editItems() } }))
            Divider()
            Text(statusOverride ?? BuilderSavedLists.statusLine(lists: env.store.data.checklistTemplates.count,
                                                                groups: env.store.data.listGroups.count))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AASpacing.m)
                .padding(.vertical, AASpacing.s)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: statusOverride)
        }
        .background(AAPaneBackground())
    }

    /// V-DESIGN rule 4 icon bar: create (List / Group), delete, Sort A-Z, ↑ / ↓, then every remaining command by
    /// its spec name in the trailing overflow menu — including "Export ALL (PDF)…", which never needs a selection
    /// (06 §6.5, R3, PDF-022). As on Windows the selection commands stay enabled and answer "Select a saved list
    /// first." with nothing selected; ↑ / ↓ / Move to position are disabled only while Sort A-Z is on (T-KB-33).
    private func toolbar(sortAZ: Bool) -> some View {
        HStack(spacing: 2) {
            Menu {
                Button("New List…", systemImage: "list.bullet.rectangle") { run { await newList() } }
                    .help("Create a new empty saved list.")
                Button("New Group…", systemImage: "folder.badge.plus") { run { await newGroup() } }
                    .help("Create a new List Group to bundle saved lists together.")
            } label: {
                Image(systemName: "plus").symbolRenderingMode(.hierarchical)
            } primaryAction: {
                run { await newList() }
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .fixedSize()
            .help("+ List: create a new empty saved list. Use the arrow for + Group (a new List Group).")
            .accessibilityLabel("+ List")
            BuilderIconButton(command: BuilderBarCommand(title: "Delete", symbol: "trash",
                                                         help: "Delete the selected saved list.") {
                run { await deleteList() }
            })
            Toggle(isOn: Binding(get: { sortAZ }, set: { _ in toggleSortAZ() })) {
                Image(systemName: "arrow.up.arrow.down").symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .buttonStyle(.accessoryBar)
            .help("Sort A-Z: show lists alphabetically instead of your own order. Your arranged order is kept and is "
                  + "what exports use when this is off.")
            .accessibilityLabel("Sort A-Z")
            BuilderBarSeparator()
            BuilderIconButton(command: BuilderBarCommand(
                title: "Move up", symbol: "chevron.up",
                help: "Move the selected saved list(s) up within its group. This is the order they export in.",
                disabled: sortAZ) { run { await nudge(up: true) } })
            BuilderIconButton(command: BuilderBarCommand(
                title: "Move down", symbol: "chevron.down",
                help: "Move the selected saved list(s) down within its group. This is the order they export in.",
                disabled: sortAZ) { run { await nudge(up: false) } })
            Spacer(minLength: 0)
            Menu {
                Button("Edit items…", systemImage: "pencil") { run { await editItems() } }
                Button("Rename", systemImage: "character.cursor.ibeam") { run { await rename() } }
                    .help("Rename the selected saved list.")
                Button("Duplicate", systemImage: "plus.square.on.square") { run { await duplicate() } }
                Button("Move to group…", systemImage: "folder") { run { await assignGroup() } }
                    .help("Put the selected saved list into a group (or remove it from all groups).")
                Button("Manage groups…", systemImage: "folder.badge.gearshape") { run { await manageGroups() } }
                    .help("Rename or delete List Groups (lists inside a deleted group become ungrouped).")
                Divider()
                Button("Move to position…", systemImage: "arrow.up.and.down.text.horizontal") {
                    run { await moveToPosition() }
                }
                .disabled(sortAZ)
                .help("Move the selected saved list(s) to a chosen position within its group.")
                Divider()
                Button(PdfExportCommand.savedList.title, systemImage: PdfExportCommand.savedList.symbol) { run { await exportList() } }
                Button(PdfExportCommand.savedGroup.title, systemImage: PdfExportCommand.savedGroup.symbol) { run { await exportGroup() } }
                Button(PdfExportCommand.savedAll.title, systemImage: PdfExportCommand.savedAll.symbol) { run { await exportAll() } }
            } label: {
                Image(systemName: "ellipsis.circle").symbolRenderingMode(.hierarchical)
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More saved-list commands (rename, groups, position, exports).")
            .accessibilityLabel("More")
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func contextMenu(_ ids: Set<UUID>) -> some View {
        if ids.isEmpty {
            Button("New List…", systemImage: "list.bullet.rectangle") { run { await newList() } }
            Button("New Group…", systemImage: "folder.badge.plus") { run { await newGroup() } }
        } else {
            Button("Edit items…", systemImage: "pencil") { selection = ids; run { await editItems() } }
            Button("Rename", systemImage: "character.cursor.ibeam") { selection = ids; run { await rename() } }
            Button("Duplicate", systemImage: "plus.square.on.square") { selection = ids; run { await duplicate() } }
            Button("Move to group…", systemImage: "folder") { selection = ids; run { await assignGroup() } }
            Divider()
            Button("Move up", systemImage: "chevron.up") { selection = ids; run { await nudge(up: true) } }
            Button("Move down", systemImage: "chevron.down") { selection = ids; run { await nudge(up: false) } }
            Button("Move to position…", systemImage: "arrow.up.and.down.text.horizontal") {
                selection = ids; run { await moveToPosition() }
            }
            Divider()
            Button(PdfExportCommand.savedListMenu.title, systemImage: PdfExportCommand.savedListMenu.symbol) { selection = ids; run { await exportList() } }
            Button("Delete", systemImage: "trash", role: .destructive) { selection = ids; run { await deleteList() } }
        }
    }

    // MARK: Detail (BUILD-074…076)

    @ViewBuilder
    private func detail(_ t: ChecklistTemplate?) -> some View {
        if let t {
            VStack(alignment: .leading, spacing: AASpacing.m) {
                BuilderCard {
                    VStack(alignment: .leading, spacing: AASpacing.s) {
                        Text(BuilderSavedLists.displayName(t))
                            .font(.aaMono(18, weight: .bold))
                            .foregroundStyle(AAColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(BuilderSavedLists.detailSub(t, groups: env.store.data.listGroups))
                            .font(.aaMono(AAType.small))
                            .foregroundStyle(AAColor.muted)
                        BuilderFlowLayout(spacing: 8, lineSpacing: 8) {
                            Button { run { await editItems() } } label: { Label("Edit items…", systemImage: "pencil") }
                                .aaProminent()
                                .help("Edit the items in this saved list (title, duration, notes & files).")
                            Button { run { await duplicate() } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button { run { await exportList() } } label: {
                                Label(PdfExportCommand.savedList.title, systemImage: PdfExportCommand.savedList.symbol)
                            }
                            .accessibilityLabel(PdfExportCommand.savedList.accessibilityLabel)
                            Button { run { await exportGroup() } } label: {
                                Label(PdfExportCommand.savedGroup.title, systemImage: PdfExportCommand.savedGroup.symbol)
                            }
                            .accessibilityLabel(PdfExportCommand.savedGroup.accessibilityLabel)
                            Button { run { await exportAll() } } label: {
                                Label(PdfExportCommand.savedAll.title, systemImage: PdfExportCommand.savedAll.symbol)
                            }
                            .accessibilityLabel(PdfExportCommand.savedAll.accessibilityLabel)
                        }
                        .controlSize(.regular)
                        .padding(.top, AASpacing.xs)
                    }
                }
                itemsCard(t)
            }
            .padding(AASpacing.l)
        } else {
            VStack(spacing: AASpacing.m) {
                AAEmptyState(title: "Select a saved list", symbol: "list.bullet.rectangle",
                             message: "Pick a list on the left to see its items, edit it or export it.")
                // Always enabled (PDF-022 / DEV-10): with no saved lists the flow answers "No saved lists to export."
                Button { run { await exportAll() } } label: { Label(PdfExportCommand.savedAll.title, systemImage: PdfExportCommand.savedAll.symbol) }
                    .accessibilityLabel(PdfExportCommand.savedAll.accessibilityLabel)
                Spacer(minLength: AASpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func itemsCard(_ t: ChecklistTemplate) -> some View {
        let rows = t.items.enumerated().map { i, it in
            BuilderTemplateItemRow(id: it.id, index: i + 1, title: BuilderSavedLists.itemTitle(it),
                                   meta: BuilderSavedLists.itemMeta(it))
        }
        return VStack(alignment: .leading, spacing: AASpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Items").font(.aaMono(AAType.body, weight: .bold)).foregroundStyle(AAColor.fg)
                Text("\(rows.count)").font(.aaMono(AAType.caption, weight: .semibold)).foregroundStyle(AAColor.muted)
                Spacer()
                Text("Double-click an item to view its notes and files.")
                    .font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
            }
            List(selection: $itemSelection) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
                        Text("\(row.index).").font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
                            .monospacedDigit().frame(minWidth: 22, alignment: .trailing)
                        Text(row.title).font(.aaMono(AAType.body)).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !row.meta.isEmpty {
                            Text(row.meta).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).fixedSize()
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(row.id)
                    .listRowSeparator(.visible)
                    .help("Double-click an item to view its notes and files (read-only) — links open straight from there.")
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if rows.isEmpty {
                    Text("This saved list has no items yet — click Edit items… to add some.")
                        .font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted).allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Button("View notes and files…", systemImage: "doc.text.magnifyingglass") { openViewer(t, ids) }
                }
            } primaryAction: { ids in
                openViewer(t, ids)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Helpers

    private func run(_ body: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            await body()
            busy = false
        }
    }

    private var primary: ChecklistTemplate? {
        let data = env.store.data
        return BuilderSavedLists.primary(BuilderSavedLists.sections(data, sortAZ: BuilderSavedLists.isSortAZ(data)),
                                         ids: selection, data: data)
    }

    private func needSelection() async {
        await dialogs.info(BuilderSavedLists.selectFirstTitle, BuilderSavedLists.selectFirstMessage)
    }

    /// Whether ↑ / ↓ can do something for the current selection (enables the menu rows; T-KB-33).
    private func reorderAvailability(sortAZ: Bool) -> (up: Bool, down: Bool) {
        guard !sortAZ, case .ok(let picks) = BuilderSavedLists.checkReorder(env.store.data, ids: selection) else {
            return (false, false)
        }
        return BuilderSavedLists.reorderAvailability(env.store.data, picks: picks)
    }

    /// A Refresh() of the Windows page: the temporary status text goes back to the counts.
    private func refreshed() { statusOverride = nil }

    private func select(_ id: UUID) {
        withAnimation(.snappy(duration: 0.2)) { selection = [id] }
        scrollTarget = id
    }

    // MARK: Actions — groups (BUILD-077, 078, 079)

    private func newGroup() async {
        guard let raw = await BuilderUI.prompt(dialogs, title: "New List Group", prompt: "Group name:"),
              BuilderSavedLists.newGroup(env.store, rawName: raw) != nil else { return }
        BuilderUI.save(env)
        refreshed()
    }

    private func manageGroups() async {
        let data = env.store.data
        if data.listGroups.isEmpty {
            await dialogs.info("Manage groups", "No groups yet. Click '+ Group' to create one.")
            return
        }
        let rows = BuilderSavedLists.manageGroupRows(data).map { (display: $0.display, tag: $0.id) }
        guard let gid = await BuilderUI.pickOne(dialogs, prompt: "Manage groups — pick one", rows: rows),
              let g = env.store.data.listGroups.first(where: { $0.id == gid }) else { return }
        let choice = await BuilderUI.threeWay(dialogs, title: "Manage group",
                                              message: "'\(g.name)'.\n\nYes = rename\nNo = delete (its lists become ungrouped)\nCancel = nothing",
                                              first: "Rename…", second: "Delete…", secondDestructive: true)
        switch choice {
        case .first:
            guard let raw = await BuilderUI.prompt(dialogs, title: "Rename group", prompt: "New name:", initial: g.name),
                  BuilderSavedLists.renameGroup(env.store, g, rawName: raw) else { return }
            BuilderUI.save(env)
            refreshed()
        case .second:
            guard await BuilderUI.confirmDelete(dialogs, title: "Delete group",
                                                message: "Delete group '\(g.name)'? Its saved lists are kept (they become ungrouped).")
            else { return }
            BuilderSavedLists.deleteGroup(env.store, g)
            BuilderUI.save(env)
            refreshed()
        case .cancel:
            return
        }
    }

    /// BUILD-079 (primary selection only; D2: the current group is preselected and OK needs a choice).
    private func assignGroup() async {
        guard let t = primary else { await needSelection(); return }
        let data = env.store.data
        let rows = BuilderSavedLists.moveToGroupRows(data).map { (display: $0.display, tag: $0.id) }
        let current: UUID? = BuilderSavedLists.resolvedGroup(t, groups: data.listGroups)?.id
        guard let picked = await BuilderUI.pickOne(dialogs, prompt: "Move '\(t.name)' to group", rows: rows,
                                                   preselected: [current]),
              env.store.template(id: t.id) === t else { return }
        BuilderSavedLists.assign(env.store, t, toGroup: picked)
        BuilderUI.save(env)
        refreshed()
    }

    // MARK: Actions — lists (BUILD-080…084)

    private func newList() async {
        guard let raw = await BuilderUI.prompt(dialogs, title: "New saved list", prompt: "Name:"),
              let t = BuilderSavedLists.newList(env.store, rawName: raw) else { return }
        BuilderUI.save(env)
        refreshed()
        select(t.id)
    }

    private func rename() async {
        guard let t = primary else { await needSelection(); return }
        guard let raw = await BuilderUI.prompt(dialogs, title: "Rename saved list", prompt: "New name:", initial: t.name),
              env.store.template(id: t.id) === t,
              BuilderSavedLists.rename(env.store, t, rawName: raw) else { return }
        BuilderUI.save(env)
        refreshed()
    }

    private func deleteList() async {
        guard let t = primary else { await needSelection(); return }
        guard await BuilderUI.confirmDelete(dialogs, title: "Delete saved list",
                                            message: BuilderWording.deleteListQuestion(name: t.name)),
              env.store.template(id: t.id) === t else { return }
        BuilderSavedLists.delete(env.store, t)
        BuilderUI.save(env)
        selection.remove(t.id)
        refreshed()
    }

    private func duplicate() async {
        guard let t = primary else { await needSelection(); return }
        let copy = BuilderSavedLists.duplicate(env.store, t)
        BuilderUI.save(env)
        refreshed()
        select(copy.id)
    }

    /// BUILD-084: the template editor (BUILD-063) for the primary selection; refresh afterwards.
    private func editItems() async {
        guard let t = primary else { await needSelection(); return }
        let id = t.id
        await dialogs.presentSheet(.closeType) { _ in ChecklistBuilderSheet(host: .savedList(id)) }
        refreshed()
    }

    // MARK: Actions — arranging (BUILD-085…089)

    /// Shows the BUILD-089 message for a refused reorder; returns the picks when it may run.
    private func reorderPicks() async -> [ChecklistTemplate]? {
        switch BuilderSavedLists.checkReorder(env.store.data, ids: selection) {
        case .ok(let picks): return picks
        case .sortAZ: await dialogs.info(BuilderSavedLists.arrangeTitle, BuilderSavedLists.sortAZFirstMessage)
        case .noSelection: await needSelection()
        case .mixedGroups: await dialogs.info(BuilderSavedLists.arrangeTitle, BuilderSavedLists.mixedGroupsMessage)
        case .groupOfOne: break
        }
        return nil
    }

    private func nudge(up: Bool) async {
        guard let picks = await reorderPicks() else { return }
        guard BuilderSavedLists.nudge(env.store.data, picks: picks, up: up) else { return }
        commitOrder(picks)
    }

    private func moveToPosition() async {
        guard let picks = await reorderPicks() else { return }
        let options = BuilderSavedLists.moveToPositionOptions(env.store.data, picks: picks)
        guard let target = await BuilderUI.pickOne(dialogs, prompt: BuilderWording.moveTitle(picks.count, noun: "list"),
                                                   rows: options.map { (display: $0.display, tag: $0.target) }),
              picks.allSatisfy({ p in env.store.data.checklistTemplates.contains { $0 === p } }),
              BuilderSavedLists.moveTo(env.store.data, picks: picks, targetInGroup: target)
        else { return }
        commitOrder(picks)
    }

    /// Drag within a group section (06 §6.2 additive) → `BuilderSavedLists.moveTo` (resolved group, D1) with the
    /// in-group target.
    private func dropMove(_ section: BuilderSavedListSection, _ source: IndexSet, _ destination: Int) {
        let data = env.store.data
        let ids = source.map { section.rows[$0].id }
        let picks = data.checklistTemplates.filter { ids.contains($0.id) }
        let target = BuilderSavedLists.dropTarget(sectionRowIDs: section.rows.map(\.id), destination: destination, data: data)
        guard !picks.isEmpty,
              BuilderSavedLists.moveTo(env.store.data, picks: picks, targetInGroup: target) else { return }
        commitOrder(picks)
    }

    /// BUILD-085: Save, refresh, re-select every moved list, status "Order saved — …".
    private func commitOrder(_ picks: [ChecklistTemplate]) {
        env.store.markDirty()
        BuilderUI.save(env)
        withAnimation(.snappy(duration: 0.2)) { selection = Set(picks.map(\.id)) }
        scrollTarget = picks.first?.id
        statusOverride = BuilderSavedLists.orderSavedStatus
    }

    /// BUILD-088: persisted in `Ui.SortAZ["savedlists"]`, Save, status text.
    private func toggleSortAZ() {
        let on = !BuilderSavedLists.isSortAZ(env.store.data)
        BuilderSavedLists.setSortAZ(env.store, on)
        BuilderUI.save(env)
        statusOverride = on ? BuilderSavedLists.sortAZOnStatus : BuilderSavedLists.sortAZOffStatus
    }

    // MARK: Actions — export (BUILD-091…095 are W-PDF's flows)

    private func exportList() async {
        guard let t = primary else { await needSelection(); return }
        await PdfExportFlows.exportSavedLists(.list(t.id), env: env, dialogs: dialogs)
    }

    private func exportGroup() async {
        guard let t = primary else { await needSelection(); return }
        await PdfExportFlows.exportSavedLists(.group(ofList: t.id), env: env, dialogs: dialogs)
    }

    private func exportAll() async {
        await PdfExportFlows.exportSavedLists(.all, env: env, dialogs: dialogs)
    }

    // MARK: Viewer (BUILD-076)

    private func openViewer(_ t: ChecklistTemplate, _ ids: Set<UUID>) {
        guard let item = t.items.first(where: { ids.contains($0.id) }) else { return }
        let title = BuilderSavedLists.itemTitle(item)
        let container = item.container
        let subtitle = BuilderSavedLists.viewerSubtitle(listName: t.name)
        run {
            await dialogs.presentSheet(.closeType) { _ in
                ContainerViewerSheet(title: title, container: container, subtitle: subtitle)
            }
        }
    }
}

/// One saved list in the sidebar (BUILD-071: name + right muted `"{n} items"`; regular weight so the bold group
/// headers stay the only bold text — V-DESIGN rule 2, DEVIATIONS W-BUILD "design").
struct BuilderSavedListRowView: View {
    let row: BuilderSavedListRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Image(systemName: "list.bullet").foregroundStyle(AAColor.muted).font(.aaMono(AAType.caption))
            Text(row.name)
                .font(.aaMono(AAType.body))
                .foregroundStyle(AAColor.fg)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.countText)
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.vertical, AASpacing.xs)
        .frame(minHeight: 22)
        .accessibilityElement(children: .combine)
    }
}

/// One item of the detail preview (BUILD-075).
struct BuilderTemplateItemRow: Identifiable, Hashable {
    let id: UUID
    let index: Int
    let title: String
    let meta: String
}
