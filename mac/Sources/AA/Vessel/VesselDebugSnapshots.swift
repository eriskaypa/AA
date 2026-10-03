// Contract: ARCHITECTURE.md §9.6 — W-VESSEL's debug snapshot registrations (`--sheet w-vessel.<name>`). The three
// vessel panels are hosted by W-HIER's vessel detail tabs in the real app; here they are shown in a sheet at a
// realistic size so they can be verified in isolation (fixture data: Tests/AACoreTests/Fixtures/ui/w-vessel/).
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_VESSEL() {
        register("w-vessel.quick-cards") { env in
            AnyView(VesselSnapshotFrame(width: 1180, height: 720) { id in QuickCardsPanel(vesselID: id) }.environment(env))
        }
        register("w-vessel.work-orders") { env in
            AnyView(VesselSnapshotFrame(width: 1320, height: 760) { id in WorkOrdersPanel(vesselID: id) }.environment(env))
        }
        register("w-vessel.ports") { env in
            AnyView(VesselSnapshotFrame(width: 1320, height: 640) { id in VesselPortsPanel(vesselID: id) }.environment(env))
        }
        register("w-vessel.quick-card-editor") { env in
            let source = env.store.data.vessels.first?.quickCards.first
            let card = source?.clone() ?? QuickCardLayout.newCard(existingCount: 0)
            return AnyView(QuickCardEditorSheet(card: card) { _ in }.environment(env))
        }
        register("w-vessel.quick-card-editor-new") { env in
            AnyView(QuickCardEditorSheet(card: QuickCardLayout.newCard(existingCount: 0)) { _ in }.environment(env))
        }
    }
}

/// Hosts a panel for the first vessel of the data folder (or `AA_SNAPSHOT_VESSEL` = a vessel name).
private struct VesselSnapshotFrame<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: (UUID) -> Content
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let wanted = ProcessInfo.processInfo.environment["AA_SNAPSHOT_VESSEL"]
        let vessel = env.store.data.vessels.first { wanted == nil || $0.name == wanted } ?? env.store.data.vessels.first
        Group {
            if let vessel { content(vessel.id) } else { VesselMissingPlaceholder() }
        }
        .frame(width: width, height: height)
        .background(AAColor.bg)
    }
}
