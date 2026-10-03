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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AAColor.panelAlt)
                .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
            VStack(alignment: .leading, spacing: AASpacing.s) {
                AAHelpText(PortsAnalysis.dbDescription)
                AASearchField(text: $s.databaseQuery, prompt: PortsAnalysis.searchPlaceholder)
                    .aaFilterField(for: .main)
            }
            .padding(10)
            List(selection: $s.databaseSelection) {
                ForEach(ports) { port in
                    PortsDatabaseRow(port: port).tag(port.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if ports.isEmpty {
                    Text(env.store.data.ports.isEmpty ? "No ports yet" : "No matching ports")
                        .font(.system(size: AAType.small))
                        .foregroundStyle(AAColor.muted)
                }
            }
            Divider()
            Text(status)
                .font(.system(size: AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                PortsDatabaseVisitsTable(visits: PortsAnalysis.orderedVisits(port))
            } else {
                Text(PortsAnalysis.dbNoSelectionHeader)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                AAEmptyState(title: "No port selected", symbol: AASymbol.portsHeader,
                             message: "Choose a port on the left to list the vessels that called and when.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
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
                .font(.system(size: AAType.body, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AASpacing.s)
            Text(PortsAnalysis.visitCountText(port.visits.count))
                .font(.system(size: AAType.caption))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.vertical, 2)
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
        Table(rows) {
            TableColumn("Vessel") { r in Text(r.visit.vesselName).fontWeight(.medium) }
                .width(min: 120, ideal: 220)
            TableColumn("Arrival") { r in Text(r.visit.arrivalDisplay).font(.aaMono(AAType.small)) }
                .width(min: 100, ideal: 140)
            TableColumn("Departure") { r in Text(r.visit.departureDisplay).font(.aaMono(AAType.small)) }
                .width(min: 100, ideal: 140)
            TableColumn("Imported") { r in Text(r.visit.importedAt).font(.aaMono(AAType.small)).foregroundStyle(.secondary) }
                .width(min: 100, ideal: 140)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .font(.system(size: AAType.small))
    }
}
