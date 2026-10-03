// Spec: 10 §E (VESSEL-200 layout, 201 import, 202 different-vessel prompt, 203 merge, 204 activity log, 205 export,
//       206 search (not debounced), 207 columns, 208 sorting incl. the `Special measures` quirk, 209 delete, 210 summary,
//       211 IMO / call sign not stored, 212 lossy re-import), §3.7, §6.5 (context menu Delete… and ⌫ additive);
//       VESSEL-003, VESSEL-004; ARCHITECTURE.md §7.6 (`.aaFilterField(for: .main)`, ListCommands role `portsOfCall`).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// The per-vessel ports-of-call panel ("Ports" tab).
struct VesselPortsPanel: View {
    let vesselID: UUID

    init(vesselID: UUID) { self.vesselID = vesselID }

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let vessel = env.store.vessel(id: vesselID) {
            if env.locks.isGated(vessel) {
                VesselLockedPlaceholder()
            } else {
                VesselPortsPanelContent(vessel: vessel)
                    .id(ObjectIdentifier(vessel))
            }
        } else {
            VesselMissingPlaceholder()
        }
    }
}

/// One row of the calls table (snapshot keys for the header → column mapping).
struct PortCallRowItem: Identifiable {
    let call: PortCall
    let id: ObjectIdentifier
    let portKey: String, countryKey: String, unLocodeKey: String, arrivalKey: String, departureKey: String
    let secPortKey: String, secVesselKey: String, sspKey: String, facilityKey: String, specialKey: String

    @MainActor init(_ c: PortCall) {
        call = c; id = ObjectIdentifier(c)
        portKey = c.portName; countryKey = c.country; unLocodeKey = c.unLocode; arrivalKey = c.arrivalDisplay
        departureKey = c.departureDisplay; secPortKey = c.securityLevelPort; secVesselKey = c.securityLevelVessel
        sspKey = c.sspFollowed; facilityKey = c.portFacility; specialKey = c.specialMeasures
    }

    static let columnKeyPaths: [(PortColumn, PartialKeyPath<PortCallRowItem>)] = [
        (.port, \PortCallRowItem.portKey), (.country, \PortCallRowItem.countryKey), (.unLocode, \PortCallRowItem.unLocodeKey),
        (.arrival, \PortCallRowItem.arrivalKey), (.departure, \PortCallRowItem.departureKey),
        (.secPort, \PortCallRowItem.secPortKey), (.secVessel, \PortCallRowItem.secVesselKey), (.ssp, \PortCallRowItem.sspKey),
        (.facility, \PortCallRowItem.facilityKey), (.special, \PortCallRowItem.specialKey),
    ]

    static func column(for kp: PartialKeyPath<PortCallRowItem>) -> PortColumn? { columnKeyPaths.first { $0.1 == kp }?.0 }

    static func comparator(_ c: PortColumn, descending: Bool) -> KeyPathComparator<PortCallRowItem> {
        let o: SortOrder = descending ? .reverse : .forward
        switch c {
        case .port: return KeyPathComparator(\.portKey, order: o)
        case .country: return KeyPathComparator(\.countryKey, order: o)
        case .unLocode: return KeyPathComparator(\.unLocodeKey, order: o)
        case .arrival: return KeyPathComparator(\.arrivalKey, order: o)
        case .departure: return KeyPathComparator(\.departureKey, order: o)
        case .secPort: return KeyPathComparator(\.secPortKey, order: o)
        case .secVessel: return KeyPathComparator(\.secVesselKey, order: o)
        case .ssp: return KeyPathComparator(\.sspKey, order: o)
        case .facility: return KeyPathComparator(\.facilityKey, order: o)
        case .special: return KeyPathComparator(\.specialKey, order: o)
        }
    }
}

struct VesselPortsPanelContent: View {
    let vessel: Vessel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var rows: [PortCallRowItem] = []
    @State private var summary = ""
    @State private var selection = Set<ObjectIdentifier>()
    @State private var sortOrder: [KeyPathComparator<PortCallRowItem>]
    @State private var dropTargeted = false

    init(vessel: Vessel) {
        self.vessel = vessel
        let s = VesselSessionState.shared
        _sortOrder = State(initialValue: [PortCallRowItem.comparator(s.portsSortColumn, descending: s.portsSortDescending)])
    }

    private var session: VesselSessionState { VesselSessionState.shared }
    private var busy: Bool { session.busyPorts.contains(vessel.id) }
    /// DATA-174 / DATA-180: the in-panel import and the workbook drop follow the menu rows' write gate.
    private var gated: Bool { VesselFlows.isWriteGated(env) }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            toolbar
            VesselSummaryBox(text: summary, busy: busy)
            if vessel.portCalls.isEmpty {
                // No zebra table behind the empty state (design rule 5): a plain surface with AAEmptyState.
                AAEmptyState(title: "No ports of call", symbol: "mappin.and.ellipse",
                             message: "Import a 'Last Ports of Call' or 'Port of Call List' workbook for this vessel.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(busy ? 0.5 : 1)
            } else {
                table
            }
        }
        .padding(AASpacing.l)
        .overlay { VesselDropHighlight(active: dropTargeted).padding(4) }
        .onDrop(of: gated ? [] : [.fileURL], isTargeted: $dropTargeted) { providers in
            guard !gated else { return false }
            return VesselWorkbookDrop.handle(providers) { url in
                Task { await VesselFlows.importPorts(vesselID: vessel.id, env: env, dialogs: dialogs, file: url) }
            }
        }
        .onAppear { buildView() }
        .onChange(of: session.revision) { _, _ in buildView() }
        .onChange(of: env.store.generation) { _, _ in buildView() }
        .onChange(of: session.portsQuery) { _, _ in buildView() }            // not debounced (VESSEL-206)
        .onChange(of: sortOrder) { _, new in applyHeaderClick(new) }
    }

    /// `BuildView`: filter, sort, summary.
    private func buildView() {
        let s = session
        let shown = PortsAnalysis.sort(PortsAnalysis.filter(vessel.portCalls, query: s.portsQuery),
                                       by: s.portsSortColumn, descending: s.portsSortDescending)
        rows = shown.map(PortCallRowItem.init)
        summary = PortsAnalysis.summary(vessel: vessel, shown: rows.count)
        let live = Set(rows.map(\.id))
        if !selection.isSubset(of: live) { selection.formIntersection(live) }
    }

    // MARK: Toolbar (VESSEL-200)

    private var toolbar: some View {
        @Bindable var s = session
        return VesselFlowLayout {
            Button {
                Task { await VesselFlows.importPorts(vesselID: vessel.id, env: env, dialogs: dialogs) }
            } label: {
                Label("Import ports (.xlsx)…", systemImage: AASymbol.importFile)
            }
            .aaProminent()
            .disabled(busy || gated)
            .help(gated ? PersistReadOnlyText.disabledHelp
                        : "Import a ports-of-call list for THIS vessel. Both the 'Last Ports of Call' and the 'Port of Call List' layouts are auto-detected.")
            Button {
                Task { await VesselFlows.exportPorts(vesselID: vessel.id, env: env, dialogs: dialogs) }
            } label: {
                Label("Export (.xlsx)…", systemImage: AASymbol.export)
            }
            .help("Export this vessel's ports of call to Excel.")
            AASearchField(text: $s.portsQuery, prompt: PortsAnalysis.searchPlaceholder)
                .frame(width: 290)
                .aaFilterField(for: .main)
            Button(role: .destructive) { delete(ids: selection) } label: { Label("Delete", systemImage: AASymbol.delete) }
                .help("Delete the selected port calls (also removes their visit from the ports database).")
        }
    }

    // MARK: Table (VESSEL-207)

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            Group {
                TableColumn("Port", sortUsing: PortCallRowItem.comparator(.port, descending: false)) { r in
                    Text(r.call.portName)
                }
                .width(min: 90, ideal: 130)
                TableColumn("Country", sortUsing: PortCallRowItem.comparator(.country, descending: false)) { r in
                    Text(r.call.country)
                }
                .width(min: 70, ideal: 110)
                TableColumn("UN/LOCODE", sortUsing: PortCallRowItem.comparator(.unLocode, descending: false)) { r in
                    Text(r.call.unLocode)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Arrival", sortUsing: PortCallRowItem.comparator(.arrival, descending: false)) { r in
                    Text(r.call.arrivalDisplay).monospacedDigit()
                }
                .width(min: 100, ideal: 124)
                TableColumn("Departure", sortUsing: PortCallRowItem.comparator(.departure, descending: false)) { r in
                    Text(r.call.departureDisplay).monospacedDigit()
                }
                .width(min: 100, ideal: 124)
            }
            Group {
                TableColumn("Sec P", sortUsing: PortCallRowItem.comparator(.secPort, descending: false)) { r in
                    Text(r.call.securityLevelPort)
                }
                .width(min: 40, ideal: 48)
                TableColumn("Sec V", sortUsing: PortCallRowItem.comparator(.secVessel, descending: false)) { r in
                    Text(r.call.securityLevelVessel)
                }
                .width(min: 40, ideal: 48)
                TableColumn("SSP", sortUsing: PortCallRowItem.comparator(.ssp, descending: false)) { r in
                    Text(r.call.sspFollowed)
                }
                .width(min: 36, ideal: 42)
                TableColumn("Port Facility", sortUsing: PortCallRowItem.comparator(.facility, descending: false)) { r in
                    Text(r.call.portFacility)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)      // wrapped (VESSEL-207)
                        .help(r.call.portFacility)
                }
                .width(min: 90, ideal: 170)
                TableColumn("Special measures", sortUsing: PortCallRowItem.comparator(.special, descending: false)) { r in
                    Text(r.call.specialMeasures)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)      // wrapped (VESSEL-207)
                        .help(r.call.specialMeasures)
                }
                .width(min: 90, ideal: 200)
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .font(.aaMono(AAType.small))                 // dense tables: the crew-table cell size
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            Button(role: .destructive) { delete(ids: ids.isEmpty ? selection : ids) } label: {
                Label("Delete…", systemImage: AASymbol.delete)
            }
            .disabled(ids.isEmpty && selection.isEmpty)
        }
        .aaListCommands(ListCommands(role: .portsOfCall, selectionCount: selection.count,
                                     deleteTitle: "Delete Port Calls…", delete: { delete(ids: selection) }))
        .overlay {
            if rows.isEmpty && !vessel.portCalls.isEmpty {
                AAEmptyState(title: "No matching ports", symbol: "magnifyingglass",
                             message: "Clear the search to see every port call.")
            }
        }
    }

    // MARK: Header clicks (VESSEL-208: same column toggles, another becomes ascending)

    private func applyHeaderClick(_ new: [KeyPathComparator<PortCallRowItem>]) {
        guard let first = new.first, let clicked = PortCallRowItem.column(for: first.keyPath) else { return }
        let s = session
        let wantDesc = first.order == .reverse
        if clicked == s.portsSortColumn && wantDesc == s.portsSortDescending && new.count == 1 { return }
        let next: (PortColumn, Bool) = clicked == s.portsSortColumn ? (clicked, wantDesc) : (clicked, false)
        s.portsSortColumn = next.0
        s.portsSortDescending = next.1
        let normalized = [PortCallRowItem.comparator(next.0, descending: next.1)]
        if new != normalized { sortOrder = normalized }
        buildView()
    }

    private func delete(ids: Set<ObjectIdentifier>) {
        let target = rows.filter { ids.contains($0.id) }.map(\.call)
        Task { await VesselFlows.deletePortCalls(target, vesselID: vessel.id, env: env, dialogs: dialogs) }
    }
}
