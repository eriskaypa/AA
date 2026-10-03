// PLACEHOLDER(W-VESSEL) — contract: ARCHITECTURE.md §7.7
// Spec: 10, 03 SHELL-654 (Tools ▸ Vessel). Compiling stub created by F3; W-VESSEL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum VesselTab { case quickCards, workOrders, ports }

@MainActor enum VesselActions {
    static func menuActions(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter,
                            selectTab: @escaping (VesselTab) -> Void) -> VesselMenuActions {
        // PLACEHOLDER(W-VESSEL)
        VesselMenuActions(importWorkOrders: {}, exportWorkOrders: {}, importPorts: {}, exportPorts: {}, newQuickCard: {})
    }
}

@MainActor enum WorkOrderNotifications {
    static func runDigest(env: AppEnvironment, today: CivilDate) {
        // PLACEHOLDER(W-VESSEL)
    }
}
