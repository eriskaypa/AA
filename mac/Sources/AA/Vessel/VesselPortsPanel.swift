// PLACEHOLDER(W-VESSEL) — contract: ARCHITECTURE.md §7.7
// Spec: 10 §C (ports of call). Compiling stub created by F3; W-VESSEL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct VesselPortsPanel: View {
    let vesselID: UUID

    init(vesselID: UUID) { self.vesselID = vesselID }

    var body: some View {
        // PLACEHOLDER(W-VESSEL)
        AAEmptyState(title: "Ports of call — not yet implemented", symbol: "mappin.and.ellipse", message: "PLACEHOLDER(W-VESSEL)")
    }
}
