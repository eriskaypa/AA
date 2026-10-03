// Spec: 09 CREW-001 (Crew section; refresh on selection), CREW-005 (navigate in), §B CREW-010…018 (roster: header,
//       toolbar — one icon bar per the design rules —, search, three-line rows, expiring filter, sort, status line, selection), §F CREW-060/061
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

    var body: some View {
        @Bindable var model = model
        // The shell lays the shortcut strip out below the section (REQ-W-CREW-01), so the panes need no inset.
        HSplitView {
            CrewRosterPane(model: model)
                .frame(minWidth: CrewLayout.rosterMinWidth, idealWidth: CrewLayout.rosterIdealWidth,
                       maxWidth: CrewLayout.rosterMaxWidth)
            CrewCardPane(model: model)
                .frame(minWidth: CrewLayout.cardMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        // V2-J5: an HSplitView that runs under the floating sidebar hands the sidebar's leading safe-area inset to
        // EACH pane's hosting view, so its minimum width grew by twice the sidebar (290 + 420 + 2 × 228 = 1167 pt) and
        // the section overflowed — and was clipped on both sides — in any window narrower than ~1170 pt. A leading
        // padding lays the split view out inside the safe area (as the Ports section's padding does), so its minimum is
        // just the two panes. The 1-pt edge sits under the sidebar's own shadow.
        .padding(.leading, CrewLayout.splitLeadingInset)
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
            model.attach(env.store)
            if !model.importing { model.refresh(today: env.clock.today()) }   // CREW-001: selecting the tab refreshes
            consumeNavigation()
        }
        .onChange(of: env.navigator.selectedSection) { _, s in
            if s == .crew, !model.importing { model.refresh(today: env.clock.today()) }   // CREW-001 / CREW-016
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
            iconBar
                .padding(.horizontal, AASpacing.s)
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

    // CREW-010 — one compact row: title, the expiring capsule, the member count (trailing, muted).
    private func header(count: Int, expiring: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text("Crew")
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
            if expiring > 0 {
                AAStatusCapsule(text: "\u{26A0} \(expiring)", color: AAColor.Status.dueSoon)
                    .help(CrewExpiry.badgeText(expiring))
                    .accessibilityLabel("\(expiring) crew contracts expiring")
            }
            Spacer(minLength: AASpacing.s)
            Text("\(count)")
                .font(.aaMono(AAType.caption))
                .monospacedDigit()
                .foregroundStyle(AAColor.muted)
                .accessibilityLabel("\(count) crew")
        }
        .padding(.horizontal, AASpacing.m)
        .frame(minHeight: 36)
        .padding(.top, AASpacing.xs)
    }

    // CREW-010 / CREW-011 as ONE icon bar (design rule 4): Import COMPAS… · Delete │ Sort · Expiring Only · Contract
    // Expiries … overflow (Table View…, Clear All…). Every command keeps its spec name (accessibility label / menu
    // title) and tooltip; the row context menu and the Tools menu keep theirs.
    private var iconBar: some View {
        let gated = CrewActions.importGated(env)
        return HStack(spacing: 2) {
            CrewIconButton(title: "Import COMPAS…", symbol: "square.and.arrow.down.on.square",
                           help: CrewActions.importHelp(env)) {
                Task { await CrewActions.importCompas(env: env, dialogs: dialogs) }
            }
            .disabled(model.importing || gated)

            CrewIconButton(title: "Delete", symbol: "trash", help: "Remove the selected crew member.") {
                Task { await deleteSelected() }
            }
            .disabled(model.selectedID == nil)

            CrewIconBarDivider()

            Menu {
                Picker("Sort", selection: Binding(get: { sortMode }, set: setSort)) {
                    ForEach(CrewSortMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .tint(.secondary)
            .buttonStyle(.accessoryBar)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Order the roster by last name, first name, CID, birth date or sign-off date. (Sort: \(sortMode.label))")
            .accessibilityLabel("Sort: \(sortMode.label)")

            Toggle(isOn: $model.expiringOnly.animation(.snappy)) {
                Label("Expiring Only", systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.iconOnly)
                    .symbolVariant(model.expiringOnly ? .fill : .none)
                    .frame(width: 24, height: 24)
            }
            .toggleStyle(.button)
            .buttonStyle(.accessoryBar)
            .help("Show only crew whose contract is overdue or within 60 days.")
            .accessibilityLabel("Expiring Only")

            CrewIconButton(title: "Contract Expiries", symbol: "exclamationmark.triangle",
                           help: "List crew whose contracts (sign-off dates) are due soon or overdue.") {
                Task { await CrewActions.checkExpiries(env: env, dialogs: dialogs, showWhenNone: true) }
            }

            Spacer(minLength: AASpacing.s)

            Menu {
                Button {
                    openTable()
                } label: {
                    Label("Table View…", systemImage: "tablecells")
                }
                .help("Open all crew in a tabulated window: choose columns and order, set the date format, and export to Excel.")
                Divider()
                Button(role: .destructive) {
                    Task { await clearAll() }
                } label: {
                    Label("Clear All…", systemImage: "trash.slash")
                }
                .disabled(env.store.data.crew.isEmpty)
                .help("Remove every crew member from the roster.")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .tint(.secondary)
            .buttonStyle(.accessoryBar)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More crew commands: Table View…, Clear All…")
            .accessibilityLabel("More")
        }
        .symbolRenderingMode(.hierarchical)
        .fontWeight(.regular)
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
                                       AlertButton(title: "Cancel", role: .cancel)])   // ⎋ cancels (as Move to Trash)
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
                .font(.aaMono(AAType.body))
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
                    .font(.aaMono(AAType.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(CrewPalette.color(row.tone))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AASpacing.xs)
        .frame(minHeight: 22, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A 24-pt borderless icon button of a list icon bar (design rule 4): the spec name is the accessibility label, the spec
/// tooltip the help.
struct CrewIconButton: View {
    let title: String
    let symbol: String
    let help: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.accessoryBar)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// The hairline between icon groups.
struct CrewIconBarDivider: View {
    var body: some View {
        Rectangle().fill(AAColor.border).frame(width: 1, height: 16).padding(.horizontal, AASpacing.xs)
    }
}
