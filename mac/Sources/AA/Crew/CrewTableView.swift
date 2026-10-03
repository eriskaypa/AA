// Spec: 09 §I CREW-100…106 (table window: all crew in the roster's sort order; date format + separator; column chooser
//       with ticks, ↑/↓, All/None; read-only grid of the ticked columns; every rebuild and close persists the choices;
//       Export to Excel with the exact shown columns/order/formatting; Close / Esc), §3.9, §4.5, §6.4 (Window scene,
//       chooser with drag-to-reorder + ↑/↓/All/None, SwiftUI Table with dynamic columns, Columns menu bound to the same
//       state, Export complete → Open / Show in Finder / Done); 03 §6.5.1.10 (crewTableColumns: ⌃⌘↑/↓, Space toggles);
//       ARCHITECTURE.md §7.1 (`crew-table` scene "Crew — Table View"), §7.7.
import AppKit
import SwiftUI
import AACore

/// One grid row: the member id and the text of every catalog column that is shown.
struct CrewTableRow: Identifiable, Hashable {
    let id: UUID
    let cells: [String: String]
}

/// Chooser / format state of the table window (rebuilt from `Ui` on open).
@MainActor @Observable
final class CrewTableModel {
    var choices: [CrewColumnChoice] = []
    var format: CrewDateFormat = .iso
    var separator = "-"
    var selectedKey: String?
    var loaded = false
    @ObservationIgnored private weak var attachedStore: AppStore?
    @ObservationIgnored private var replaceSubscription: EventSubscription?

    /// CREW-104 across a reload (shared-save pull, reload from disk, Flash Sync apply, Drive import — DATA-093 carries
    /// the CrewTable* Ui keys): the open window re-reads the four keys of the NEW data instead of writing its pre-reload
    /// choices back over them on the next rebuild or on close.
    func attach(_ store: AppStore) {
        guard attachedStore !== store else { return }
        attachedStore = store
        replaceSubscription = store.dataReplaced.subscribe { [weak self, weak store] _ in
            guard let self, let store, self.loaded else { return }
            self.reload(store.data.ui)
        }
    }

    func detach() {
        replaceSubscription?.cancel()
        replaceSubscription = nil
        attachedStore = nil
    }

    /// Re-reads the stored choices, keeping the chooser's selected row when that column still exists.
    func reload(_ ui: UiState) {
        let keep = selectedKey
        load(ui)
        selectedKey = keep.flatMap { k in choices.contains { $0.column.key == k } ? k : nil }
    }

    var shownColumns: [CrewColumn] { choices.filter(\.shown).map(\.column) }

    /// CREW-101/102: format, separator and chooser from the stored Ui keys.
    func load(_ ui: UiState) {
        format = CrewDateFormat(persisted: ui.crewTableDateFormat)
        separator = CrewColumns.loadedSeparator(ui.crewTableDateSeparator)
        choices = CrewColumns.buildChoices(order: ui.crewTableColumns, shown: ui.crewTableShownColumns)
        loaded = true
    }

    /// CREW-104: every rebuild writes the four keys (merely opening the window makes the choice explicit).
    func persist(_ ui: UiState, store: AppStore) {
        guard loaded else { return }
        let lists = CrewColumns.persistedLists(choices)
        var changed = false
        if ui.crewTableColumns != lists.order { ui.crewTableColumns = lists.order; changed = true }
        if ui.crewTableShownColumns != lists.shown { ui.crewTableShownColumns = lists.shown; changed = true }
        if ui.crewTableDateFormat != format.name { ui.crewTableDateFormat = format.name; changed = true }
        if ui.crewTableDateSeparator != separator { ui.crewTableDateSeparator = separator; changed = true }
        if changed { store.markDirty() }
    }

    var selectedIndex: Int? { selectedKey.flatMap { k in choices.firstIndex { $0.column.key == k } } }

    /// ↑/↓ move the selected row one place (no-op at the ends) and keep it selected.
    func move(_ direction: MoveDirection) {
        guard let i = selectedIndex else { return }
        let j = direction == .up ? i - 1 : i + 1
        guard choices.indices.contains(j) else { return }
        choices.swapAt(i, j)
    }

    func setAll(_ shown: Bool) {
        var c = choices
        for k in c.indices { c[k].shown = shown }
        choices = c                                             // one rebuild
    }

    func toggle(_ key: String) {
        if let i = choices.firstIndex(where: { $0.column.key == key }) { choices[i].shown.toggle() }
    }
}

struct CrewTableView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = CrewTableModel()
    @State private var fitted = false

    /// The chooser's widest split position (HSplitView hands the chooser its maximum on open).
    static let chooserMaxWidth: CGFloat = 280
    /// Per-column cell padding / intercell spacing of the inset `Table`, and the table's own side insets.
    static let columnChrome: CGFloat = 20, tableInsets: CGFloat = 32

    var body: some View {
        Group {
            if env.store.data.crew.isEmpty {
                VStack(spacing: AASpacing.m) {
                    AAEmptyState(title: "No Crew Yet", symbol: "tablecells", message: CrewRoster.tableEmptyMessage)
                    closeBar
                }
            } else {
                content
            }
        }
        .frame(minWidth: 860, idealWidth: 1120, minHeight: 480, idealHeight: 640)
        .background(AAColor.bg, ignoresSafeAreaEdges: [])
        .onAppear {
            model.attach(env.store)
            if !model.loaded { model.load(env.store.data.ui) }
            model.persist(env.store.data.ui, store: env.store)
        }
        .task {
            guard !fitted else { return }
            fitted = true
            await fitWindowToShownColumns()
        }
        .onChange(of: model.choices) { _, _ in model.persist(env.store.data.ui, store: env.store) }
        .onChange(of: model.format) { _, _ in model.persist(env.store.data.ui, store: env.store) }
        .onChange(of: model.separator) { _, s in
            let clamped = CrewColumns.clampSeparator(s)
            if clamped != s { model.separator = clamped; return }
            model.persist(env.store.data.ui, store: env.store)
        }
        .onDisappear {
            model.persist(env.store.data.ui, store: env.store)
            CrewPersist.flush(env)                                // CREW-100: FlushIfDirty on close
            model.detach()
        }
    }

    private var rows: [CrewTableRow] {
        let today = env.clock.today()
        let crew = CrewSort.sorted(env.store.data.crew, mode: CrewSortMode(persisted: env.store.data.ui.crewSortMode),
                                   today: today)
        let cols = model.shownColumns
        return crew.map { m in
            var cells: [String: String] = [:]
            for c in cols { cells[c.key] = CrewColumns.cell(c, m, format: model.format, separator: model.separator, today: today) }
            return CrewTableRow(id: m.id, cells: cells)
        }
    }

    private var content: some View {
        let rows = rows
        let shown = model.shownColumns
        return VStack(spacing: 0) {
            topBar(crewCount: rows.count, columns: shown.count)
            Divider()
            HSplitView {
                chooser
                    .frame(minWidth: 220, idealWidth: 236, maxWidth: Self.chooserMaxWidth)
                grid(rows, shown)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            closeBar
        }
    }

    // MARK: CREW-101 top bar

    private func topBar(crewCount: Int, columns: Int) -> some View {
        HStack(spacing: AASpacing.s) {
            Text("Date format:").font(.aaMono(AAType.small))
            Picker("Date format:", selection: $model.format) {
                ForEach(CrewDateFormat.allCases) { f in Text(f.label).tag(f) }
            }
            .labelsHidden()
            .frame(width: 185)
            Text("Separator:").font(.aaMono(AAType.small)).padding(.leading, AASpacing.xs)
            TextField("", text: $model.separator)
                .textFieldStyle(.roundedBorder)
                .font(.aaMono(AAType.small))
                .frame(width: 46)
                .help("Character(s) placed between date parts, e.g. - / .")
            Menu {
                ForEach(model.choices) { c in
                    Toggle(c.column.header, isOn: Binding(get: { c.shown }, set: { _ in model.toggle(c.column.key) }))
                }
                Divider()
                Button("Show All") { model.setAll(true) }
                Button("Hide All") { model.setAll(false) }
            } label: {
                Label("Columns", systemImage: "rectangle.split.3x1")
            }
            .fixedSize()
            .help("Show or hide columns (same as the ticks on the left).")
            Spacer(minLength: AASpacing.s)
            Text(CrewColumns.countText(crew: crewCount, columns: columns))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
            Button { Task { await export() } } label: {
                Label("Export to Excel (.xlsx)…", systemImage: "square.and.arrow.up")
            }
            .aaProminent()
        }
        .controlSize(.small)
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.s)
    }

    // MARK: CREW-102 chooser

    private var chooser: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Text("Columns — tick to show, \u{2191}/\u{2193} to reorder")
                .font(.aaMono(AAType.small, weight: .bold))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
            List(selection: $model.selectedKey) {
                ForEach($model.choices) { $choice in
                    Toggle(isOn: $choice.shown) {
                        Text(choice.column.header).font(.aaMono(AAType.small))
                    }
                    .toggleStyle(.checkbox)
                    .tag(choice.column.key)
                }
                .onMove { from, to in model.choices.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .onKeyPress(.space) {
                guard let k = model.selectedKey else { return .ignored }
                model.toggle(k)
                return .handled
            }
            .aaListCommands(ListCommands(role: .crewTableColumns, selectionCount: model.selectedKey == nil ? 0 : 1,
                                         canMoveUp: (model.selectedIndex ?? 0) > 0,
                                         canMoveDown: model.selectedIndex.map { $0 < model.choices.count - 1 } ?? false,
                                         move: { model.move($0) }))
            HStack(spacing: 6) {
                Button { model.move(.up) } label: { Image(systemName: "arrow.up") }
                    .help("Move selected column up")
                    .disabled((model.selectedIndex ?? 0) == 0)
                Button { model.move(.down) } label: { Image(systemName: "arrow.down") }
                    .help("Move selected column down")
                    .disabled(model.selectedIndex.map { $0 >= model.choices.count - 1 } ?? true)
                Spacer()
                Button("All") { model.setAll(true) }
                Button("None") { model.setAll(false) }
            }
            .controlSize(.small)
        }
        .padding(AASpacing.m)
        .background(AAPaneBackground())
    }

    // MARK: CREW-103 grid

    private func grid(_ rows: [CrewTableRow], _ shown: [CrewColumn]) -> some View {
        Group {
            if shown.isEmpty {
                AAEmptyState(title: "No Columns Shown", symbol: "rectangle.dashed",
                             message: "Tick at least one column on the left.")
            } else {
                Table(rows) {
                    TableColumnForEach(shown) { col in
                        TableColumn(col.header) { (row: CrewTableRow) in
                            Text(row.cells[col.key] ?? "")
                                .font(.aaMono(AAType.small))
                                .foregroundStyle(cellColor(col, row))
                                .textSelection(.enabled)
                        }
                        .width(min: 44, ideal: Self.idealWidth(col))
                    }
                }
                .tableStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
            }
        }
    }

    /// CREW-103: starting widths sized so the nine default columns — Sign-Off Date and Contract Status included —
    /// fit the default window without horizontal scrolling (WPF auto-sized them); every column stays resizable.
    static func idealWidth(_ c: CrewColumn) -> CGFloat {
        switch c.key {
        case "FullName", "Company", "Vessel", "SourceFile": return 150
        case "Rank": return 110
        case "PlaceOfBirth", "NokRelationship", "NokFirstName", "NokLastName": return 120
        case "LastName", "FirstName", "MiddleName": return 96
        case "Nationality", "ImportedAt": return 92
        case "ContractStatus": return 112
        case "Cid", "Gender", "Height", "EyesColor", "HairColor", "UserType", "ChecklistCount", "RankCode",
             "DaysUntilSignOff", "SignedOnOff": return 60
        default: return 100
        }
    }

    /// The width the grid needs for the shown columns at their ideal widths, plus the chooser.
    static func neededWindowWidth(_ shown: [CrewColumn]) -> CGFloat {
        chooserMaxWidth + 1 + tableInsets + shown.reduce(0) { $0 + idealWidth($1) + columnChrome }
    }

    /// CREW-103: WPF's DataGrid auto-sized the columns into view. On open the window grows (never shrinks, never past
    /// the screen) so the shown columns — with the defaults, Sign-Off Date and Contract Status — need no scrolling.
    private func fitWindowToShownColumns() async {
        var window: NSWindow?
        for _ in 0..<20 {
            window = SceneOpener.shared.window(for: .crewTable)
            if window != nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let target = min(Self.neededWindowWidth(model.shownColumns), visible.width)
        guard window.frame.width < target else { return }
        var f = window.frame
        f.origin.x = max(visible.minX, min(f.origin.x - (target - f.width) / 2, visible.maxX - target))
        f.size.width = target
        window.setFrame(f, display: true, animate: false)
    }

    /// The Contract Status / Days columns pick up the roster's expiry colours (display only).
    private func cellColor(_ c: CrewColumn, _ row: CrewTableRow) -> Color {
        guard c.key == "ContractStatus" || c.key == "DaysUntilSignOff",
              let status = row.cells["ContractStatus"] ?? contractStatus(row) else { return AAColor.fg }
        switch status {
        case "Expired": return AAColor.Status.danger
        case "Critical": return AAColor.Status.dueSoon
        case "DueSoon": return AAColor.Status.warning
        case "Ok": return AAColor.Status.ok
        default: return AAColor.muted
        }
    }

    private func contractStatus(_ row: CrewTableRow) -> String? {
        env.store.crewMember(id: row.id).map { CrewStoredDate.contractStatus($0, today: env.clock.today()).name }
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            Button("Close") { dismissWindow(id: SceneID.crewTable.rawValue) }
                .keyboardShortcut(.cancelAction)
                .frame(minWidth: 90)
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.s)
    }

    // MARK: CREW-105 export

    private func export() async {
        let cols = model.shownColumns
        guard !cols.isEmpty else {
            await dialogs.info("Export to Excel", "Tick at least one column to export.")
            return
        }
        let today = env.clock.today()
        let config = SavePanelConfig(title: "Export crew table to Excel",
                                     defaultName: CrewColumns.exportFileName(today: today), allowedTypes: [.xlsx])
        guard let url = await dialogs.savePanel(config) else { return }
        let crew = CrewSort.sorted(env.store.data.crew, mode: CrewSortMode(persisted: env.store.data.ui.crewSortMode),
                                   today: today)
        let table = CrewColumns.rows(crew, columns: cols, format: model.format, separator: model.separator, today: today)
        do {
            try CrewColumns.export(to: url, headers: cols.map(\.header), rows: table)
        } catch {
            await dialogs.error("Export failed", "Could not export the workbook:\n\n\(error.localizedDescription)")
            return
        }
        let spec = AlertSpec(title: "Export complete",
                             message: CrewColumns.exportedMessage(count: table.count, path: url.path),
                             style: .informational,
                             buttons: [AlertButton(title: "Open", role: .default), AlertButton(title: "Show in Finder"),
                                       AlertButton(title: "Done", role: .cancel)])
        switch await dialogs.alert(spec) {
        case 0: NSWorkspace.shared.open(url)
        case 1: NSWorkspace.shared.activateFileViewerSelecting([url])
        default: break
        }
    }
}
