// Spec: 10 VESSEL-003 (panel state survives vessel switches for the session only: Work Orders search, toggles,
//       completion filter, combos and sort; Ports search and sort; restart resets to Due ascending / Arrival
//       descending), VESSEL-255 (the Ports DB refreshes when imports happen elsewhere — §6.5 live refresh),
//       VESSEL-101/201 (busy state while a file is parsed); ARCHITECTURE.md §9.7 (memoised view models).
import Observation
import SwiftUI
import AACore

/// Session-only state shared by every instance of the vessel panels (one per process, never persisted).
@MainActor @Observable
final class VesselSessionState {
    static let shared = VesselSessionState()

    // MARK: Work Orders (VESSEL-003)
    var workQuery = ""
    var workStatus: String? = nil
    var workCategory: String? = nil
    var workRank: String? = nil
    var workCompletion: WorkOrderCompletionFilter = .all
    var workDueSoonOnly = false
    var workNotifyOnly = false
    var workSortColumn: WorkOrderColumn = .due
    var workSortDescending = false

    // MARK: Ports panel (VESSEL-003)
    var portsQuery = ""
    var portsSortColumn: PortColumn = .arrival
    var portsSortDescending = true

    // MARK: Ports Database (VESSEL-251, 254)
    var databaseQuery = ""
    var databaseSelection: UUID? = nil

    // MARK: Change notifications (VESSEL-255) and busy flags

    /// Bumped by every W-VESSEL flow that changes vessel jobs, cards, calls or the Ports DB.
    private(set) var revision = 0
    /// Vessels whose Shippalm / ports file is being parsed (the panels show a progress indicator).
    private(set) var busyWorkOrders: Set<UUID> = []
    private(set) var busyPorts: Set<UUID> = []

    func bump() { revision &+= 1 }

    func setBusy(workOrders vesselID: UUID, _ busy: Bool) {
        if busy { busyWorkOrders.insert(vesselID) } else { busyWorkOrders.remove(vesselID) }
    }

    func setBusy(ports vesselID: UUID, _ busy: Bool) {
        if busy { busyPorts.insert(vesselID) } else { busyPorts.remove(vesselID) }
    }

    var workFilter: WorkOrderFilter {
        WorkOrderFilter(query: workQuery, status: workStatus, category: workCategory, rank: workRank,
                        completion: workCompletion, dueSoonOnly: workDueSoonOnly, notifyOnly: workNotifyOnly)
    }
}

/// Fixed due / bar colours (VESSEL-110, VESSEL-120 — identical in both appearances).
enum VesselTone {
    static func color(_ t: WorkOrderTone) -> Color {
        switch t {
        case .red: return AAColor.Status.danger
        case .orange: return AAColor.Status.dueSoon
        case .amber: return AAColor.Status.warning
        case .green: return AAColor.Status.ok
        case .gray: return AAColor.Status.neutral
        }
    }
}

/// The `PanelAlt` summary box of the Work Orders and Ports panels (1-pt border, radius 4).
struct VesselSummaryBox: View {
    let text: String
    var busy = false

    var body: some View {
        HStack(alignment: .top, spacing: AASpacing.s) {
            if busy { ProgressView().controlSize(.small).padding(.top, 1) }
            Text(text)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: busy)
    }
}

/// A wrapping row (the WPF `WrapPanel` of the panel toolbars).
struct VesselFlowLayout: Layout {
    var spacing: CGFloat = AASpacing.s
    var lineSpacing: CGFloat = AASpacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0; lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        var line: [(LayoutSubview, CGSize, CGFloat)] = []
        func flush() {
            for (s, size, px) in line {
                s.place(at: CGPoint(x: px, y: y + (lineHeight - size.height) / 2), proposal: ProposedViewSize(size))
            }
            line.removeAll()
        }
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                flush()
                y += lineHeight + lineSpacing
                x = bounds.minX; lineHeight = 0
            }
            line.append((s, size, x))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        flush()
    }
}

/// The locked-vessel placeholder (VESSEL-004: nothing is viewable while the vessel is gated).
struct VesselLockedPlaceholder: View {
    var body: some View {
        AAEmptyState(title: "Locked", symbol: AASymbol.lockFill,
                     message: "Unlock this vessel to see its quick cards, work orders and ports.")
    }
}

/// Shown when a panel's vessel no longer exists (e.g. after a reload).
struct VesselMissingPlaceholder: View {
    var body: some View {
        AAEmptyState(title: "No vessel selected", symbol: "ferry", message: "Select a vessel to see this tab.")
    }
}
