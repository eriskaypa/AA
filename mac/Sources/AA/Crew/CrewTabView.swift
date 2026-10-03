// Spec: 09 CREW-001 (Crew section; refresh on selection), CREW-005 (navigate in), §B CREW-010…018 (roster: header,
//       wrapping toolbar, search, three-line rows, expiring filter, sort, status line, selection), §F CREW-060/061
//       (Move to Trash / Clear all — DECISIONS 09: one Trash batch), CREW-100 (table view launcher), §6.4 (Mac layout:
//       roster + card split, context menu, ⌘⌫ / ⌫ Move to Trash, ⌥⌘F search); 03 SHELL-516/517 (list and filter
//       publishing); ARCHITECTURE.md §7.2 (HSplitView inside sections), §7.6, §7.7, §8.
import AppKit
import SwiftUI
import AACore

struct CrewTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model = CrewRosterModel.shared
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        // The AppKit split view lays its panes out under SwiftUI safe-area insets (the shell's bottom shortcut strip),
        // so the measured inset is applied to each pane as padding.
        HSplitView {
            CrewRosterPane(model: model)
                .padding(.bottom, bottomInset)
                .frame(minWidth: 290, idealWidth: 340, maxWidth: 520)
            CrewCardPane(model: model)
                .padding(.bottom, bottomInset)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { bottomInset = g.safeAreaInsets.bottom }
                .onChange(of: g.safeAreaInsets.bottom) { _, v in bottomInset = v }
        })
        .overlay {
            if model.importing { AAProgressOverlay(text: "Importing the COMPAS crew report…") }
        }
        .sheet(item: $model.editor) { req in
            CrewEditorSheet(memberID: req.memberID, initialTab: req.tab) { saved in
                editorClosed(req.memberID, saved: saved)
            }
        }
        .aaSectionCommands(.crew, SectionCommands(focusSearchField: { CrewSearchFocus.focus() }))
        .onAppear {
            model.keyLookup = { [weak store = env.store] id in store?.crewMember(id: id)?.key }
            model.today = env.clock.today()
            consumeNavigation()
        }
        .onChange(of: env.navigator.selectedSection) { _, s in
            if s == .crew { model.today = env.clock.today() }            // CREW-001: refresh day counts
        }
        .onChange(of: env.navigator.crewRequest) { _, _ in consumeNavigation() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.today = env.clock.today()
        }
    }

    private func consumeNavigation() {
        guard let req = env.navigator.crewRequest else { return }
        env.navigator.consume(req)
        let key = env.store.crewMember(id: req.memberID)?.key
        model.statusOverride = nil
        model.select(memberID: req.memberID, key: key, clearFilters: true)
    }

    /// CREW-074: Save → confirmed save, Cancel → flush; either way select the member, refresh and update the badge.
    private func editorClosed(_ memberID: UUID, saved: Bool) {
        if saved { CrewPersist.save(env) } else { CrewPersist.flush(env) }
        model.statusOverride = nil
        if let m = env.store.crewMember(id: memberID) { model.select(memberID: m.id, key: m.key, clearFilters: false) }
    }
}

// MARK: Roster

struct CrewRosterPane: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Bindable var model: CrewRosterModel

    private var sortMode: CrewSortMode { CrewSortMode(persisted: env.store.data.ui.crewSortMode) }

    var body: some View {
        let crew = env.store.data.crew
        let rows = CrewRoster.rows(crew, query: model.query, expiringOnly: model.expiringOnly, mode: sortMode,
                                   today: model.today)
        let expiring = CrewExpiry.expiringCount(crew, today: model.today)
        VStack(alignment: .leading, spacing: 0) {
            header(count: crew.count, expiring: expiring)
            toolbar
                .padding(.horizontal, AASpacing.m)
                .padding(.bottom, AASpacing.s)
            AASearchField(text: $model.query, prompt: CrewRoster.searchPrompt)
                .padding(.horizontal, AASpacing.m)
                .padding(.bottom, AASpacing.s)
            Divider()
            list(rows)
            Divider()
            Text(model.statusOverride ?? CrewRoster.statusLine(total: crew.count, expiring: expiring))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AASpacing.m)
                .padding(.vertical, AASpacing.s)
                .textSelection(.enabled)
        }
        .background(AAPaneBackground())
        .onChange(of: rows.map(\.id), initial: true) { _, _ in model.reconcile(rows: rows) }
    }

    // CREW-010
    private func header(count: Int, expiring: Int) -> some View {
        HStack(alignment: .center, spacing: AASpacing.s) {
            Text("Crew").font(.aaMono(15, weight: .bold)).foregroundStyle(AAColor.accent)
            if expiring > 0 {
                AAStatusCapsule(text: "\u{26A0} \(expiring)", color: AAColor.Status.dueSoon)
                    .help(CrewExpiry.badgeText(expiring))
                    .accessibilityLabel("\(expiring) crew contracts expiring")
            }
            Spacer(minLength: AASpacing.s)
            Button {
                Task { await CrewActions.importCompas(env: env, dialogs: dialogs) }
            } label: {
                Label("Import COMPAS…", systemImage: "square.and.arrow.down")
            }
            .aaProminent()
            .controlSize(.small)
            .disabled(model.importing)
            .help("Import a COMPAS crew report (.xlsx) and keep each member as an info card.")
            Button {
                Task { await deleteSelected() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(model.selectedID == nil)
            .help("Remove the selected crew member.")
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, AASpacing.m)
        .padding(.top, AASpacing.m)
        .padding(.bottom, AASpacing.s)
    }

    // CREW-011
    private var toolbar: some View {
        CrewFlowLayout(spacing: 6, lineSpacing: 6) {
            Button {
                Task { await CrewActions.checkExpiries(env: env, dialogs: dialogs, showWhenNone: true) }
            } label: {
                Label("Contract Expiries", systemImage: "exclamationmark.triangle")
            }
            .help("List crew whose contracts (sign-off dates) are due soon or overdue.")

            Toggle(isOn: $model.expiringOnly.animation(.snappy)) {
                Label("Expiring Only", systemImage: "line.3.horizontal.decrease.circle")
            }
            .toggleStyle(.button)
            .help("Show only crew whose contract is overdue or within 60 days.")

            Menu {
                Picker("Sort", selection: Binding(get: { sortMode }, set: setSort)) {
                    ForEach(CrewSortMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Sort: \(sortMode.label)", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Order the roster by last name, first name, CID, birth date or sign-off date.")

            Button {
                openTable()
            } label: {
                Label("Table View…", systemImage: "tablecells")
            }
            .help("Open all crew in a tabulated window: choose columns and order, set the date format, and export to Excel.")

            Button(role: .destructive) {
                Task { await clearAll() }
            } label: {
                Label("Clear All…", systemImage: "trash.slash")
            }
            .disabled(env.store.data.crew.isEmpty)
            .help("Remove every crew member from the roster.")
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
    }

    private func list(_ rows: [CrewRosterRow]) -> some View {
        ScrollViewReader { proxy in
            List(selection: $model.selectedID) {
                ForEach(rows) { row in
                    CrewRosterRowView(row: row)
                        .tag(row.id)
                        .id(row.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if rows.isEmpty {
                    if env.store.data.crew.isEmpty {
                        AAEmptyState(title: "No Crew Yet", symbol: "person.3",
                                     message: "Import a COMPAS crew report to create a card for every seafarer.")
                    } else {
                        AAEmptyState(title: "No Matches", symbol: "magnifyingglass",
                                     message: model.expiringOnly ? "No crew contract is overdue or due within 60 days."
                                                                 : "No crew member matches the search.")
                    }
                }
            }
            .aaListCommands(ListCommands(role: .crewRoster, selectionCount: model.selectedID == nil ? 0 : 1,
                                         deleteTitle: "Move to Trash",
                                         delete: model.selectedID == nil ? nil : { Task { await deleteSelected() } }))
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1, let id = ids.first { rowMenu(id) }
            } primaryAction: { ids in
                if let id = ids.first { model.open(.details, for: id) }
            }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .center) }
                model.scrollTarget = nil
            }
        }
    }

    @ViewBuilder private func rowMenu(_ id: UUID) -> some View {
        Button { model.open(.details, for: id) } label: { Label("Edit…", systemImage: "pencil") }
        Button { model.open(.checklist, for: id) } label: { Label("Open Checklist…", systemImage: "checklist") }
        Button { model.open(.schedule, for: id) } label: { Label("Open Schedule…", systemImage: "calendar") }
        Divider()
        Button(role: .destructive) {
            model.selectedID = id
            Task { await deleteSelected() }
        } label: { Label("Move to Trash…", systemImage: "trash") }
    }

    // MARK: Actions

    private func setSort(_ mode: CrewSortMode) {
        let ui = env.store.data.ui
        guard CrewSortMode(persisted: ui.crewSortMode) != mode else { return }
        ui.crewSortMode = mode.name                                // CREW-015: enum name + autosave
        env.store.markDirty()
        model.statusOverride = nil
    }

    private func openTable() {
        if env.store.data.crew.isEmpty {                          // CREW-100
            Task { await dialogs.info(CrewRoster.tableEmptyTitle, CrewRoster.tableEmptyMessage) }
            return
        }
        env.open(.crewTable)
    }

    /// CREW-060 (soft delete through the Trash).
    private func deleteSelected() async {
        guard let id = model.selectedID, let m = env.store.crewMember(id: id) else { return }
        let ok = await dialogs.confirm(CrewRoster.deleteTitle, CrewRoster.deleteMessage(m), confirm: "Move to Trash")
        guard ok, let live = env.store.crewMember(id: id) else { return }
        env.store.trash(live)
        model.selectedID = nil
        model.statusOverride = nil
        CrewPersist.save(env)
    }

    /// CREW-061 with DECISIONS 09: every member to the Trash as one undoable batch.
    private func clearAll() async {
        let n = env.store.data.crew.count
        guard n > 0 else { return }
        let spec = AlertSpec(title: CrewRoster.clearTitle, message: CrewRoster.clearMessage(count: n), style: .warning,
                             buttons: [AlertButton(title: "Clear All", role: .destructive),
                                       AlertButton(title: "Cancel", role: .default)])
        guard await dialogs.alert(spec) == 0 else { return }
        env.store.trashAllCrew()
        model.selectedID = nil
        model.statusOverride = nil
        CrewPersist.save(env)
    }
}

/// CREW-013: name, sub line, coloured expiry line.
struct CrewRosterRowView: View {
    let row: CrewRosterRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.aaMono(AAType.body, weight: .bold))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
            if !row.sub.isEmpty {
                Text(row.sub)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !row.expiryText.isEmpty {
                Text(row.expiryText)
                    .font(.aaMono(AAType.caption, weight: .bold))
                    .foregroundStyle(CrewPalette.color(row.tone))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
