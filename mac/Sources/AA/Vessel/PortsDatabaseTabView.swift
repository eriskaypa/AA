// Spec: 10 §F (VESSEL-250 layout: two panes, 320-pt left column, header, description, search, list, status; right:
//       header + visits list), VESSEL-251 (rows, filter, order), 252 (status text), 253 (visits pane, order, columns),
//       254 (selection retention), 255 (refresh triggers; the Mac re-derives live), 256 (read-only), VESSEL-007 (the
//       "Ports" main tab), §6.5; DECISIONS 10 Q8 (`1 visit`); ARCHITECTURE.md §7.7, §8.5 (`ferry` for the ⚓ header).
import AppKit
import SwiftUI
import AACore

/// The global Ports Database (main section "Ports").
struct PortsDatabaseTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var ports: [PortRecord] = []
    @State private var status = ""

    private var session: VesselSessionState { VesselSessionState.shared }

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            rightPane
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .padding(AASpacing.m)
        .background(AAColor.bg)
        .onAppear {
            #if DEBUG
            if let name = ProcessInfo.processInfo.environment["AA_SNAPSHOT_PORT"],
               let p = env.store.data.ports.first(where: { $0.name == name }) { session.databaseSelection = p.id }
            #endif
            refresh()
        }
        .onChange(of: session.revision) { _, _ in refresh() }
        .onChange(of: env.store.generation) { _, _ in refresh() }
        .onChange(of: env.store.data.ports.count) { _, _ in refresh() }
        .onChange(of: session.databaseQuery) { _, _ in refresh() }               // each keystroke (VESSEL-251)
    }

    /// `Refresh()`: filter + order, keep the selection when still listed, status line (VESSEL-251…254).
    private func refresh() {
        let all = env.store.data.ports
        ports = PortsAnalysis.databasePorts(all, query: session.databaseQuery)
        let keep = PortsAnalysis.retainedSelection(session.databaseSelection, in: ports)
        if keep != session.databaseSelection { session.databaseSelection = keep }
        status = PortsAnalysis.databaseStatus(all, shown: ports.count)
    }

    private var selectedPort: PortRecord? {
        guard let id = session.databaseSelection else { return nil }
        return ports.first { $0.id == id }
    }

    // MARK: Left pane

    private var leftPane: some View {
        @Bindable var s = session
        return VStack(alignment: .leading, spacing: 0) {
            Label(PortsAnalysis.dbTitle.replacingOccurrences(of: "⚓ ", with: ""), systemImage: AASymbol.portsHeader)
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, AASpacing.m)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(AAColor.panelAlt)
                .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
            VStack(alignment: .leading, spacing: AASpacing.s) {
                AAHelpText(PortsAnalysis.dbDescription)
                AASearchField(text: $s.databaseQuery, prompt: PortsAnalysis.searchPlaceholder)
                    .aaFilterField(for: .main)
            }
            .padding(AASpacing.m)
            List(selection: $s.databaseSelection) {
                ForEach(ports) { port in
                    PortsDatabaseRow(port: port).tag(port.id)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .overlay {
                if ports.isEmpty {
                    if env.store.data.ports.isEmpty {
                        AAEmptyState(title: "No ports yet", symbol: AASymbol.portsHeader,
                                     message: "Import a ports-of-call list on any vessel’s “Ports” tab.")
                    } else {
                        AAEmptyState(title: "No matching ports", symbol: "magnifyingglass",
                                     message: "Clear the search to see every port.")
                    }
                }
            }
            Divider()
            Text(status)
                .font(.aaMono(AAType.caption))
                .monospacedDigit()
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AASpacing.m)
                .padding(.vertical, AASpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .padding(.trailing, 5)
    }

    // MARK: Right pane (VESSEL-253)

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            if let port = selectedPort {
                Text(PortsAnalysis.visitsHeader(port))
                    .font(.aaMono(AAType.body, weight: .semibold))
                    .foregroundStyle(AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                PortsDatabaseVisitsTable(visits: PortsAnalysis.orderedVisits(port))
            } else {
                Text(PortsAnalysis.dbNoSelectionHeader)
                    .font(.aaMono(AAType.body, weight: .semibold))
                    .foregroundStyle(AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                AAEmptyState(title: "No port selected", symbol: AASymbol.portsHeader,
                             message: "Choose a port on the left to list the vessels that called and when.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(AASpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .padding(.leading, 5)
    }
}

/// `Display` (semi-bold, wrapped) and the trailing visit count (VESSEL-251).
struct PortsDatabaseRow: View {
    let port: PortRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text(port.display)
                .font(.aaMono(AAType.body))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AASpacing.s)
            Text(PortsAnalysis.visitCountText(port.visits.count))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.vertical, AASpacing.xs)
        .frame(minHeight: 22)
    }
}

/// The read-only visits list (not sortable, no context menu — VESSEL-253).
struct PortsDatabaseVisitsTable: View {
    let visits: [PortVisit]

    private struct Row: Identifiable {
        let id: Int
        let visit: PortVisit
    }

    var body: some View {
        let rows = visits.enumerated().map { Row(id: $0.offset, visit: $0.element) }
        let c = PortsAnalysis.visitsColumns
        Table(rows) {
            TableColumn(c[0].title) { r in
                Text(r.visit.vesselName)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)          // wrapped VesselName (VESSEL-253)
                    .help(r.visit.vesselName)
            }
            .width(min: c[0].minWidth, ideal: c[0].idealWidth)
            TableColumn(c[1].title) { r in Text(r.visit.arrivalDisplay).monospacedDigit() }
                .width(min: c[1].minWidth, ideal: c[1].idealWidth)
            TableColumn(c[2].title) { r in Text(r.visit.departureDisplay).monospacedDigit() }
                .width(min: c[2].minWidth, ideal: c[2].idealWidth)
            TableColumn(c[3].title) { r in
                Text(r.visit.importedAt).font(.aaMono(AAType.caption)).monospacedDigit().foregroundStyle(AAColor.muted)
            }
                .width(min: c[3].minWidth, ideal: c[3].idealWidth)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .font(.aaMono(AAType.body))
    }
}
