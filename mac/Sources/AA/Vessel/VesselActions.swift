// Spec: 10 §6.8 (optional Vessel menu: Import Shippalm Work Orders…, Import Ports of Call…, Export Work Orders…,
//       Export Ports of Call…, New Quick Card — enabled when a vessel is selected), 03 SHELL-654 (Tools ▸ Vessel via
//       `SectionCommands.vessel`), VESSEL-001/002 (`VesselTab`: Quick Cards / Work Orders / Ports), DECISIONS 10 Q7
//       (system notifications for flagged overdue work orders, per-ship master switch), 10 §9 Q7; ARCHITECTURE.md §7.7
//       (exact signatures), §9.3 (`ReminderCenter` calls `runDigest` on every digest).
import AppKit
import SwiftUI
import AACore

/// The three vessel-only detail tabs, in display order (VESSEL-001); Quick Cards is the vessel's first screen.
enum VesselTab { case quickCards, workOrders, ports }

/// Builds the Tools ▸ Vessel menu actions for one vessel (W-HIER publishes them through `SectionCommands.vessel`).
@MainActor enum VesselActions {
    static func menuActions(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter,
                            selectTab: @escaping (VesselTab) -> Void) -> VesselMenuActions {
        VesselMenuActions(
            importWorkOrders: {
                selectTab(.workOrders)
                Task { await VesselFlows.importWorkOrders(vesselID: vesselID, env: env, dialogs: dialogs) }
            },
            exportWorkOrders: {
                selectTab(.workOrders)
                Task { await VesselFlows.exportWorkOrders(vesselID: vesselID, env: env, dialogs: dialogs) }
            },
            importPorts: {
                selectTab(.ports)
                Task { await VesselFlows.importPorts(vesselID: vesselID, env: env, dialogs: dialogs) }
            },
            exportPorts: {
                selectTab(.ports)
                Task { await VesselFlows.exportPorts(vesselID: vesselID, env: env, dialogs: dialogs) }
            },
            newQuickCard: {
                selectTab(.quickCards)
                Task { await VesselFlows.addQuickCard(vesselID: vesselID, env: env, dialogs: dialogs) }
            })
    }
}

/// DECISIONS 10 Q7: a notification for flagged (`Notify`), active, overdue work orders of every vessel whose
/// `NotificationsEnabled` is on — at most once per vessel / job / day (MacPreferences `aa.vessel.notified`).
/// Called by W-SHELL's `ReminderCenter` on every digest, so it works without visiting Vessels.
@MainActor enum WorkOrderNotifications {
    static func runDigest(env: AppEnvironment, today: CivilDate) {
        guard !env.isSafeMode, !env.isReadOnlyInstance else { return }
        let prefs = MacPreferences.shared
        var notified = WorkOrderAlerts.storedKeys(prefs, today: today)
        let alerts = WorkOrderAlerts.pending(vessels: env.store.data.vessels, today: today, alreadyNotified: notified)
        guard !alerts.isEmpty else { return }
        for a in alerts {
            if NotificationCenterBridge.isAvailable {
                NotificationCenterBridge.post(id: a.identifier, title: a.title, body: a.body, onClick: .item(a.vesselID))
            } else {
                env.status.post(a.body)                               // unbundled runs: the status line (§9.3)
            }
            notified.formUnion(a.newKeys)
        }
        WorkOrderAlerts.storeKeys(notified, prefs, today: today)
    }
}
