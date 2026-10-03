// Spec: 10 §D (VESSEL-100 layout, 101 import, 102 upsert, 103 export, 104 debounced search, 105 combos, 106 completion,
//       107 due/overdue, 108 notify-only, 109 columns, 110 due cell, 111 sorting, 112 Done, 113 Notify, 114 mark
//       completed / active, 115 context notify, 116 shown ON / OFF, 117 delete, 118 context menu, 119 summary, 120
//       notifications bar + master switch, 121 scope, 122 selection kept by identity, 123 performance), §3.5, §6.4;
//       VESSEL-003 (session state), VESSEL-004 (lock gate); ARCHITECTURE.md §7.6 (`.aaFilterField(for: .main)`,
//       ListCommands role `workOrders`), §9.7 (memoised rebuilds, 200 ms debounce).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// The per-vessel Shippalm work-orders panel ("Work Orders" tab).
struct WorkOrdersPanel: View {
    let vesselID: UUID

    init(vesselID: UUID) { self.vesselID = vesselID }

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let vessel = env.store.vessel(id: vesselID) {
            if env.locks.isGated(vessel) {
                VesselLockedPlaceholder()
            } else {
                WorkOrdersPanelContent(vessel: vessel)
                    .id(ObjectIdentifier(vessel))
            }
        } else {
            VesselMissingPlaceholder()
        }
    }
}

/// One table row (recreated on every rebuild; selection is kept by job identity — VESSEL-122).
struct WorkOrderRowItem: Identifiable {
    let job: ShipJob
    let id: ObjectIdentifier
    let dueText: String
    let tone: WorkOrderTone
    let days: Int?

    // Sort-key snapshots (the Table only reports which header was clicked; the order itself is VESSEL-111's).
    let doneKey: Int, notifyKey: Int, dueKey: Int
    let jobNoKey: String, titleKey: String, intervalKey: String, statusKey: String, dueStatusKey: String
    let categoryKey: String, rankKey: String, functionKey: String

    @MainActor init(job: ShipJob, dueText: String, tone: WorkOrderTone, days: Int?) {
        self.job = job; id = ObjectIdentifier(job); self.dueText = dueText; self.tone = tone; self.days = days
        doneKey = job.isCompleted ? 1 : 0; notifyKey = job.notify ? 1 : 0; dueKey = days ?? Int.max
        jobNoKey = job.jobNo; titleKey = job.title; intervalKey = job.interval; statusKey = job.status
        dueStatusKey = job.dueStatus; categoryKey = job.category; rankKey = job.responsibleRank
        functionKey = job.functionDescription
    }

    static let columnKeyPaths: [(WorkOrderColumn, PartialKeyPath<WorkOrderRowItem>)] = [
        (.done, \WorkOrderRowItem.doneKey), (.notify, \WorkOrderRowItem.notifyKey), (.jobNo, \WorkOrderRowItem.jobNoKey),
        (.title, \WorkOrderRowItem.titleKey), (.due, \WorkOrderRowItem.dueKey), (.interval, \WorkOrderRowItem.intervalKey),
        (.status, \WorkOrderRowItem.statusKey), (.dueStatus, \WorkOrderRowItem.dueStatusKey),
        (.category, \WorkOrderRowItem.categoryKey), (.responsible, \WorkOrderRowItem.rankKey),
        (.function, \WorkOrderRowItem.functionKey),
    ]

    static func column(for kp: PartialKeyPath<WorkOrderRowItem>) -> WorkOrderColumn? {
        columnKeyPaths.first { $0.1 == kp }?.0
    }

    static func comparator(_ c: WorkOrderColumn, descending: Bool) -> KeyPathComparator<WorkOrderRowItem> {
        let order: SortOrder = descending ? .reverse : .forward
        switch c {
        case .done: return KeyPathComparator(\.doneKey, order: order)
        case .notify: return KeyPathComparator(\.notifyKey, order: order)
        case .jobNo: return KeyPathComparator(\.jobNoKey, order: order)
        case .title: return KeyPathComparator(\.titleKey, order: order)
        case .due: return KeyPathComparator(\.dueKey, order: order)
        case .interval: return KeyPathComparator(\.intervalKey, order: order)
        case .status: return KeyPathComparator(\.statusKey, order: order)
        case .dueStatus: return KeyPathComparator(\.dueStatusKey, order: order)
        case .category: return KeyPathComparator(\.categoryKey, order: order)
        case .responsible: return KeyPathComparator(\.rankKey, order: order)
        case .function: return KeyPathComparator(\.functionKey, order: order)
        }
    }
}

/// Memoised rows, combos, summary and bar of one vessel (rebuilt explicitly, like the Windows `BuildView`).
@MainActor @Observable
final class WorkOrdersPanelModel {
    let vessel: Vessel
    private(set) var rows: [WorkOrderRowItem] = []
    private(set) var statusItems: [String] = [WorkOrderAnalysis.allStatuses]
    private(set) var categoryItems: [String] = [WorkOrderAnalysis.allCategories]
    private(set) var rankItems: [String] = [WorkOrderAnalysis.allRanks]
    private(set) var summary = ""
    private(set) var bar = WorkOrderBarState(text: "", borderTone: .gray, textTone: .gray)

    init(vessel: Vessel) { self.vessel = vessel }

    /// VESSEL-105 `PopulateFilters`: repopulate the three combos, keeping identical previous selections.
    func populateFilters() {
        let s = VesselSessionState.shared
        statusItems = WorkOrderAnalysis.statusItems(vessel.jobs)
        categoryItems = WorkOrderAnalysis.categoryItems(vessel.jobs)
        rankItems = WorkOrderAnalysis.rankItems(vessel.jobs)
        let st = WorkOrderAnalysis.keepSelection(s.workStatus, in: statusItems)
        let ca = WorkOrderAnalysis.keepSelection(s.workCategory, in: categoryItems)
        let rk = WorkOrderAnalysis.keepSelection(s.workRank, in: rankItems)
        if st != s.workStatus { s.workStatus = st }
        if ca != s.workCategory { s.workCategory = ca }
        if rk != s.workRank { s.workRank = rk }
    }

    /// `BuildView`: filter → sort → rows with DueInfo, then the summary and the notifications bar.
    func rebuild(today: CivilDate) {
        let s = VesselSessionState.shared
        let keyed = WorkOrderAnalysis.keyed(vessel.jobs, today: today)
        let shown = WorkOrderAnalysis.sort(WorkOrderAnalysis.filter(keyed, s.workFilter), by: s.workSortColumn,
                                           descending: s.workSortDescending)
        rows = shown.map { k in
            let info = WorkOrderAnalysis.dueInfo(k.job, days: k.days)
            return WorkOrderRowItem(job: k.job, dueText: info.text, tone: info.tone, days: k.days)
        }
        refreshSummaryAndBar(today: today)
    }

    func refreshSummaryAndBar(today: CivilDate) {
        summary = WorkOrderAnalysis.summary(vessel: vessel, shown: rows.count, today: today)
        bar = WorkOrderAnalysis.notificationBar(vessel: vessel, today: today)
    }

    var shownJobs: [ShipJob] { rows.map(\.job) }

    func jobs(for ids: Set<ObjectIdentifier>) -> [ShipJob] {
        rows.filter { ids.contains($0.id) }.map(\.job)
    }
}

struct WorkOrdersPanelContent: View {
    let vessel: Vessel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model: WorkOrdersPanelModel
    @State private var selection = Set<ObjectIdentifier>()
    @State private var sortOrder: [KeyPathComparator<WorkOrderRowItem>]
    @State private var searchDebounce: Task<Void, Never>?
    @State private var dropTargeted = false

    init(vessel: Vessel) {
        self.vessel = vessel
        _model = State(initialValue: WorkOrdersPanelModel(vessel: vessel))
        let s = VesselSessionState.shared
        _sortOrder = State(initialValue: [WorkOrderRowItem.comparator(s.workSortColumn, descending: s.workSortDescending)])
    }

    private var session: VesselSessionState { VesselSessionState.shared }
    private var today: CivilDate { env.clock.today() }
    private var busy: Bool { session.busyWorkOrders.contains(vessel.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            toolbar
            notificationsBar
            VesselSummaryBox(text: busy ? WorkOrderAnalysis.readingSummary : model.summary, busy: busy)
            table
        }
        .padding(AASpacing.m)
        .overlay { VesselDropHighlight(active: dropTargeted).padding(4) }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            VesselWorkbookDrop.handle(providers) { url in
                Task { await VesselFlows.importWorkOrders(vesselID: vessel.id, env: env, dialogs: dialogs, file: url) }
            }
        }
        .onAppear {
            model.populateFilters()
            model.rebuild(today: today)
        }
        .onChange(of: session.revision) { _, _ in
            model.populateFilters()
            rebuild()
        }
        .onChange(of: env.store.generation) { _, _ in rebuild() }
        .onChange(of: session.workStatus) { _, _ in rebuild() }
        .onChange(of: session.workCategory) { _, _ in rebuild() }
        .onChange(of: session.workRank) { _, _ in rebuild() }
        .onChange(of: session.workCompletion) { _, _ in rebuild() }
        .onChange(of: session.workDueSoonOnly) { _, _ in rebuild() }
        .onChange(of: session.workNotifyOnly) { _, _ in rebuild() }
        .onChange(of: session.workQuery) { _, _ in
            // VESSEL-104: restart a 200 ms one-shot timer on every keystroke.
            searchDebounce?.cancel()
            searchDebounce = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                rebuild()
            }
        }
        .onChange(of: sortOrder) { _, new in applyHeaderClick(new) }
    }

    private func rebuild() {
        model.rebuild(today: today)
        let live = Set(model.rows.map(\.id))
        if !selection.isSubset(of: live) { selection.formIntersection(live) }
    }

    // MARK: Toolbar (VESSEL-100 row 1)

    /// Two wrapping rows: file actions, search and the selection actions; then the filters and the "shown" actions.
    /// Same controls, words and tooltips as the Windows wrap panel (VESSEL-100), grouped so nothing is orphaned.
    private var toolbar: some View {
        @Bindable var s = session
        return VStack(alignment: .leading, spacing: AASpacing.s) {
            VesselFlowLayout(spacing: AASpacing.s) {
                Button {
                    Task { await VesselFlows.importWorkOrders(vesselID: vessel.id, env: env, dialogs: dialogs) }
                } label: {
                    Label("Import Shippalm (.xlsx)…", systemImage: AASymbol.importFile)
                }
                .aaProminent()
                .disabled(busy)
                .help("Import a Shippalm Work Order List export into THIS ship. Jobs are keyed by job number (No.).")
                Button {
                    Task { await VesselFlows.exportWorkOrders(vesselID: vessel.id, env: env, dialogs: dialogs) }
                } label: {
                    Label("Export (.xlsx)…", systemImage: AASymbol.export)
                }
                .help("Export THIS ship's work orders (including notify & completion choices) to an .xlsx that can be re-imported.")
                AASearchField(text: $s.workQuery, prompt: WorkOrderAnalysis.searchPlaceholder)
                    .frame(width: 240)
                    .aaFilterField(for: .main)
                Divider().frame(height: 18)
                Button { setCompleted(true, ids: []) } label: { Label("Mark completed", systemImage: AASymbol.markDone) }
                    .help("Mark the selected work orders (or all shown, if none selected) as completed.")
                Button { setCompleted(false, ids: []) } label: { Label("Mark active", systemImage: "arrow.uturn.backward") }
                    .help("Clear the completed flag on the selected work orders (or all shown, if none selected).")
                Button(role: .destructive) { delete(ids: selection) } label: { Label("Delete", systemImage: AASymbol.delete) }
                    .help("Delete the selected work orders from this ship (permanent).")
            }
            VesselFlowLayout(spacing: AASpacing.s) {
                combo(items: model.statusItems, selection: $s.workStatus, width: 135, help: "Filter by Work Order Status.")
                combo(items: model.categoryItems, selection: $s.workCategory, width: 135, help: "Filter by Work Order Category.")
                combo(items: model.rankItems, selection: $s.workRank, width: 120, help: "Filter by Responsible rank.")
                Picker("", selection: $s.workCompletion) {
                    ForEach(WorkOrderCompletionFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 130)
                .help("Show all, only active (not completed), or only completed work orders.")
                Toggle("Due/overdue only", isOn: $s.workDueSoonOnly)
                    .toggleStyle(.button)
                    .help("Show only jobs that are overdue or due within 90 days.")
                Toggle("Notify on only", isOn: $s.workNotifyOnly)
                    .toggleStyle(.button)
                    .help("Show only jobs set to raise notifications.")
                Divider().frame(height: 18)
                Button { setNotifyShown(true) } label: { Label("shown ON", systemImage: AASymbol.notifyOn) }
                    .help("Turn ON notifications for every job currently shown.")
                Button { setNotifyShown(false) } label: { Label("shown OFF", systemImage: AASymbol.notifyOff) }
                    .help("Turn OFF notifications for every job currently shown.")
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.regular)
    }

    private func combo(items: [String], selection: Binding<String?>, width: CGFloat, help: String) -> some View {
        let binding = Binding<String>(
            get: { selection.wrappedValue ?? items[0] },
            set: { selection.wrappedValue = ($0 == items[0]) ? nil : $0 })
        return Picker("", selection: binding) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Text(item).tag(item)
                if i == 0 && items.count > 1 { Divider() }
            }
        }
        .pickerStyle(.menu).labelsHidden().frame(width: width)
        .help(help)
    }

    // MARK: Notifications bar (VESSEL-120)

    private var notificationsBar: some View {
        let bar = model.bar
        let accent = VesselTone.color(bar.borderTone)
        return HStack(alignment: .firstTextBaseline, spacing: AASpacing.m) {
            Toggle(isOn: Binding(get: { vessel.notificationsEnabled }, set: { setMasterSwitch($0) })) {
                Label(WorkOrderAnalysis.masterSwitchTitle.replacingOccurrences(of: "🔔 ", with: ""),
                      systemImage: vessel.notificationsEnabled ? AASymbol.notifyOn : AASymbol.notifyOff)
                    .font(.system(size: AAType.small, weight: .semibold))
            }
            .toggleStyle(.checkbox)
            .help(WorkOrderAnalysis.masterSwitchHelp)
            .fixedSize()
            Text(bar.text)
                .font(.system(size: AAType.small, weight: bar.borderTone == .red || bar.borderTone == .orange ? .semibold : .regular))
                .foregroundStyle(bar.textTone.map(VesselTone.color) ?? AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .padding(.bottom, 3)
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(accent).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: bar)
    }

    // MARK: Table (VESSEL-109…118)

    private var table: some View {
        Table(model.rows, selection: $selection, sortOrder: $sortOrder) {
            Group {
            TableColumn("Done", sortUsing: WorkOrderRowItem.comparator(.done, descending: false)) { row in
                Toggle("", isOn: Binding(get: { row.job.isCompleted }, set: { toggleDone(row.job, $0) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .help("Mark this work order completed. Completed jobs are excluded from due/overdue counts and notifications.")
                    .frame(maxWidth: .infinity)
            }
            .width(min: 40, ideal: 48, max: 60)
            TableColumn("Notify", sortUsing: WorkOrderRowItem.comparator(.notify, descending: false)) { row in
                Toggle("", isOn: Binding(get: { row.job.notify }, set: { toggleNotify(row.job, $0) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .help("Raise a due/overdue notification for this recurring job.")
                    .frame(maxWidth: .infinity)
            }
            .width(min: 44, ideal: 52, max: 64)
            TableColumn("Job No.", sortUsing: WorkOrderRowItem.comparator(.jobNo, descending: false)) { row in
                Text(row.job.jobNo).font(.aaMono(AAType.small)).textSelection(.enabled)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Title", sortUsing: WorkOrderRowItem.comparator(.title, descending: false)) { row in
                AAStrikeText(row.job.title, struck: row.job.isCompleted).help(row.job.title)
            }
            .width(min: 120, ideal: 260)
            TableColumn("Due", sortUsing: WorkOrderRowItem.comparator(.due, descending: false)) { row in
                Text(row.dueText)
                    .font(.system(size: AAType.small, weight: .bold))
                    .foregroundStyle(VesselTone.color(row.tone))
                    .help(row.dueText)
            }
            .width(min: 120, ideal: 205)
            }
            Group {
            TableColumn("Interval", sortUsing: WorkOrderRowItem.comparator(.interval, descending: false)) { row in
                Text(row.job.interval)
            }
            .width(min: 50, ideal: 80)
            TableColumn("Status", sortUsing: WorkOrderRowItem.comparator(.status, descending: false)) { row in
                Text(row.job.status)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Due Status", sortUsing: WorkOrderRowItem.comparator(.dueStatus, descending: false)) { row in
                Text(row.job.dueStatus)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Category", sortUsing: WorkOrderRowItem.comparator(.category, descending: false)) { row in
                Text(row.job.category)
            }
            .width(min: 50, ideal: 80)
            TableColumn("Responsible", sortUsing: WorkOrderRowItem.comparator(.responsible, descending: false)) { row in
                Text(row.job.responsibleRank)
            }
            .width(min: 70, ideal: 130)
            TableColumn("Function", sortUsing: WorkOrderRowItem.comparator(.function, descending: false)) { row in
                Text(row.job.functionDescription).help(row.job.functionDescription)
            }
            .width(min: 100, ideal: 220)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .font(.system(size: AAType.small))
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            let target = ids.isEmpty ? selection : ids
            Button { setCompleted(true, ids: target) } label: { Label("Mark completed", systemImage: AASymbol.markDone) }
            Button { setCompleted(false, ids: target) } label: { Label("Mark active", systemImage: "arrow.uturn.backward") }
            Divider()
            Button { setNotify(true, ids: target) } label: { Label("Notify ON", systemImage: AASymbol.notifyOn) }
            Button { setNotify(false, ids: target) } label: { Label("Notify OFF", systemImage: AASymbol.notifyOff) }
            Divider()
            Button(role: .destructive) { delete(ids: target) } label: { Label("Delete…", systemImage: AASymbol.delete) }
        }
        .aaListCommands(ListCommands(role: .workOrders, selectionCount: selection.count,
                                     deleteTitle: "Delete Work Orders…", delete: { delete(ids: selection) }))
        .overlay {
            if model.rows.isEmpty && !vessel.jobs.isEmpty {
                AAEmptyState(title: "No matching work orders", symbol: "line.3.horizontal.decrease.circle",
                             message: "Clear the search or filters to see this ship's work orders.")
            } else if vessel.jobs.isEmpty && !busy {
                AAEmptyState(title: "No work orders", symbol: "wrench.and.screwdriver",
                             message: "Import a Shippalm Work Order List export to analyse and track this ship's jobs.")
            }
        }
    }

    // MARK: Header clicks (VESSEL-111)

    private func applyHeaderClick(_ new: [KeyPathComparator<WorkOrderRowItem>]) {
        guard let first = new.first, let clicked = WorkOrderRowItem.column(for: first.keyPath) else { return }
        let s = session
        let wantDesc = first.order == .reverse
        if clicked == s.workSortColumn && wantDesc == s.workSortDescending && new.count == 1 { return }
        let next: (column: WorkOrderColumn, descending: Bool) =
            clicked == s.workSortColumn ? (clicked, wantDesc) : (clicked, false)
        s.workSortColumn = next.column
        s.workSortDescending = next.descending
        let normalized = [WorkOrderRowItem.comparator(next.column, descending: next.descending)]
        if new != normalized { sortOrder = normalized }
        rebuild()
    }

    // MARK: Actions

    /// VESSEL-112: flip, stamp/clear the date, debounced save, full rebuild.
    private func toggleDone(_ job: ShipJob, _ on: Bool) {
        WorkOrderAnalysis.toggleDone(job, to: on, today: today)
        env.store.markDirty()
        rebuild()
    }

    /// VESSEL-113: debounced save; rebuild only under "Notify on only", else refresh the summary and bar.
    private func toggleNotify(_ job: ShipJob, _ on: Bool) {
        job.notify = on
        env.store.markDirty()
        if session.workNotifyOnly { rebuild() } else { model.refreshSummaryAndBar(today: today) }
    }

    /// VESSEL-114 (selected rows, or every shown row when none is selected; no confirmation).
    private func setCompleted(_ done: Bool, ids: Set<ObjectIdentifier>) {
        let pick = ids.isEmpty ? selection : ids
        let target = WorkOrderAnalysis.targets(selected: model.jobs(for: pick), shown: model.shownJobs)
        if target.isEmpty {
            env.status.post(WorkOrderAnalysis.noTargetsHint)
            return
        }
        WorkOrderAnalysis.setCompleted(target, done: done, today: today)
        VesselFlows.save(env)
        rebuild()
        env.status.post(WorkOrderAnalysis.markedHint(count: target.count, done: done))
    }

    /// VESSEL-115 (context menu: selected or shown; nothing when empty).
    private func setNotify(_ on: Bool, ids: Set<ObjectIdentifier>) {
        let target = WorkOrderAnalysis.targets(selected: model.jobs(for: ids), shown: model.shownJobs)
        guard !target.isEmpty else { return }
        for j in target { j.notify = on }
        VesselFlows.save(env)
        rebuild()
        env.status.post(WorkOrderAnalysis.notifyTargetHint(count: target.count, on: on))
    }

    /// VESSEL-116 (toolbar: every shown row, ignoring the selection).
    private func setNotifyShown(_ on: Bool) {
        let shown = model.shownJobs
        guard !shown.isEmpty else { return }
        for j in shown { j.notify = on }
        VesselFlows.save(env)
        rebuild()
        env.status.post(WorkOrderAnalysis.notifyShownHint(count: shown.count, on: on))
    }

    /// VESSEL-117 (selected rows only; confirmation; permanent).
    private func delete(ids: Set<ObjectIdentifier>) {
        let target = model.jobs(for: ids)
        if target.isEmpty {
            env.status.post(WorkOrderAnalysis.selectToDeleteHint)
            return
        }
        Task {
            let ok = await dialogs.confirm("Delete work orders",
                                           WorkOrderAnalysis.deleteConfirmMessage(count: target.count, vessel: vessel.name),
                                           confirm: "Delete", destructive: true, defaultIsCancel: true)
            guard ok else { return }
            WorkOrderAnalysis.delete(target, from: vessel)
            VesselFlows.save(env)
            model.populateFilters()
            rebuild()
            env.status.post(WorkOrderAnalysis.deletedHint(count: target.count, vessel: vessel.name))
        }
    }

    /// VESSEL-120: the per-ship master switch saves immediately.
    private func setMasterSwitch(_ on: Bool) {
        vessel.notificationsEnabled = on
        VesselFlows.saveNow(env)
        model.refreshSummaryAndBar(today: today)
    }
}
