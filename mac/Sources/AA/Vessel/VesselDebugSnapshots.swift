// Contract: ARCHITECTURE.md §9.6 — W-VESSEL's debug snapshot registrations (`--sheet w-vessel.<name>`). The three
// vessel panels are hosted by W-HIER's vessel detail tabs in the real app; here they are shown in a sheet at a
// realistic size so they can be verified in isolation (fixture data: Tests/AACoreTests/Fixtures/ui/w-vessel/).
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_VESSEL() {
        register("w-vessel.quick-cards") { env in
            AnyView(VesselSnapshotFrame(width: 1180, height: 720) { id in QuickCardsPanel(vesselID: id) }.environment(env))
        }
        register("w-vessel.work-orders") { env in
            AnyView(VesselSnapshotFrame(width: 1180, height: 700) { id in WorkOrdersPanel(vesselID: id) }.environment(env))
        }
        register("w-vessel.ports") { env in
            AnyView(VesselSnapshotFrame(width: 1180, height: 620) { id in VesselPortsPanel(vesselID: id) }.environment(env))
        }
        // DATA-174 check: the same panel in a read-only copy (imports, drops and "Import a copy" disabled).
        register("w-vessel.work-orders-readonly") { env in
            env.isReadOnlyInstance = true
            return AnyView(VesselSnapshotFrame(width: 1180, height: 700) { id in WorkOrdersPanel(vesselID: id) }.environment(env))
        }
        register("w-vessel.quick-card-editor-readonly") { env in
            env.isReadOnlyInstance = true
            let card = env.store.data.vessels.lazy.compactMap(\.quickCards.first).first?.clone()
                ?? QuickCardLayout.newCard(existingCount: 0)
            return AnyView(QuickCardEditorSheet(card: card) { _ in }.environment(env))
        }
        register("w-vessel.quick-card-editor") { env in
            let source = env.store.data.vessels.lazy.compactMap(\.quickCards.first).first
            let card = source?.clone() ?? QuickCardLayout.newCard(existingCount: 0)
            return AnyView(QuickCardEditorSheet(card: card) { _ in }.environment(env))
        }
        register("w-vessel.quick-card-editor-new") { env in
            AnyView(QuickCardEditorSheet(card: QuickCardLayout.newCard(existingCount: 0)) { _ in }.environment(env))
        }
    }
}

/// Hosts a panel for a vessel of the data folder (see `wanted` below).
private struct VesselSnapshotFrame<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: (UUID) -> Content
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // `AA_SNAPSHOT_VESSEL` = a vessel name or Id; otherwise the first vessel that has cards, jobs or ports.
        let wanted = ProcessInfo.processInfo.environment["AA_SNAPSHOT_VESSEL"]
        let all = env.store.data.vessels
        let vessel = wanted.flatMap { w in all.first { $0.id.uuidString.lowercased() == w.lowercased() || $0.name == w } }
            ?? all.first { !$0.quickCards.isEmpty || !$0.jobs.isEmpty || !$0.portCalls.isEmpty }
            ?? all.first
        Group {
            if let vessel { content(vessel.id) } else { VesselMissingPlaceholder() }
        }
        .frame(width: width, height: height)
        .background(AAColor.bg)
    }
}
#endif
