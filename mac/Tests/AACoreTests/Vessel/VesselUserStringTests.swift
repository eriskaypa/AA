// TV: 10 VESSEL-010/012/024/025/042/053 (quick-card texts), VESSEL-101…120 (work-order hints, dialogs, summary and
//     bar texts), VESSEL-200…253 (ports hints, dialogs, summaries, Ports DB texts), §3.6 export names — every exact
//     user-visible string the panels show, pinned verbatim (P1 parity).
import Foundation
import Testing
@testable import AACore

@Suite("W-VESSEL — exact user-visible strings")
@MainActor struct VesselUserStringTests {
    @Test func quickCardTexts() {
        #expect(QuickCardLayout.headerTitle == "Quick Cards")
        #expect(QuickCardLayout.headerHint
                == "Double-click a card to open it. Drag to move, drag the corner to resize, right-click to edit.")
        #expect(QuickCardLayout.addButtonTitle == "+ Quick card")
        #expect(QuickCardLayout.emptyText
                == "No quick cards yet for this vessel.\nClick '+ Quick card' to add a shortcut to a file, folder, or web link.")
        #expect(QuickCardLayout.noTargetTitle == "Quick card")
        #expect(QuickCardLayout.noTargetMessage
                == "This card has no target yet. Right-click ▸ Edit to point it at a file, folder, or web link.")
        #expect(QuickCardLayout.openFailedTitle == "Open failed")
        #expect(QuickCardLayout.editorTip
                == "Tip: on the vessel screen, drag a card to move it and drag its bottom-right corner to resize.")
        #expect(QuickCardLayout.targetDisplay("") == "(none — pick a file, folder, or web link)")
        #expect(QuickCardLayout.targetDisplay("files/a_b.pdf") == "files/a_b.pdf")
        #expect(QuickCardLayout.targetTypeLabel(target: " ", kind: .webLink) == "")
        #expect(QuickCardLayout.targetTypeLabel(target: "https://a", kind: .webLink) == "Web link")
        #expect(QuickCardLayout.previewTitle("  ") == "(untitled)")
        #expect(QuickCardLayout.deletePrompt(title: "PMS", icon: "⚓") == "Delete quick card 'PMS'?")
        #expect(QuickCardLayout.tooltip(title: "PMS", target: "/Volumes/sh/x.pdf", kind: .liveFile)
                == "PMS\nFile (live): /Volumes/sh/x.pdf\nDouble-click to open • drag to move • drag corner to resize")
        #expect(QuickCardLayout.tooltip(title: "", target: "C:\\Docs", kind: .folder)
                == "(untitled)\nFolder (live): C:\\Docs\nDouble-click to open • drag to move • drag corner to resize")
    }

    @Test func workOrderTexts() {
        #expect(WorkOrderAnalysis.allStatuses == "(all statuses)")
        #expect(WorkOrderAnalysis.allCategories == "(all categories)")
        #expect(WorkOrderAnalysis.allRanks == "(all ranks)")
        #expect(WorkOrderCompletionFilter.allCases.map(\.label) == ["All", "Active only", "Completed only"])
        #expect(WorkOrderAnalysis.noJobsSummary
                == "No work orders imported yet for this ship. Click “Import Shippalm (.xlsx)...”.")
        #expect(WorkOrderAnalysis.summary(vessel: nil, shown: 0, today: VesselTestClock.today) == "No ship selected.")
        #expect(WorkOrderAnalysis.readingSummary == "Reading Shippalm export… (large files take a few seconds)")
        #expect(WorkOrderAnalysis.searchPlaceholder == "Search job no / title / function...")
        #expect(WorkOrderAnalysis.noTargetsHint
                == "No work orders to update — select rows, or clear filters so some are shown.")
        #expect(WorkOrderAnalysis.selectToDeleteHint == "Select one or more work orders to delete.")
        #expect(WorkOrderAnalysis.exportEmptyMessage == "No work orders to export for this ship.")
        #expect(WorkOrderAnalysis.exportedHint(count: 30, vessel: "V") == "Exported 30 work orders for V.")
        #expect(WorkOrderAnalysis.notifyTargetHint(count: 2, on: true) == "Notifications turned ON for 2 work order(s).")
        #expect(WorkOrderAnalysis.notifyTargetHint(count: 2, on: false) == "Notifications turned OFF for 2 work order(s).")
        #expect(WorkOrderAnalysis.notifyShownHint(count: 5, on: true) == "Notifications turned ON for 5 shown job(s).")
        #expect(WorkOrderAnalysis.notifyShownHint(count: 5, on: false) == "Notifications turned OFF for 5 shown job(s).")
        #expect(WorkOrderAnalysis.deletedHint(count: 3, vessel: "V") == "Deleted 3 work order(s) from V.")
        #expect(WorkOrderAnalysis.importDialogTitle("V") == "Import Shippalm Work Order List for V")
        #expect(WorkOrderAnalysis.exportDialogTitle("V") == "Export work orders for V")
        #expect(WorkOrderAnalysis.barOffText == "Off — turn on to track this ship's due / overdue work orders here.")
        #expect(WorkOrderAnalysis.barNoneText
                == "On — no active flagged jobs. Tick the Notify box (or “🔔 shown ON”) on the recurring jobs you want tracked.")
        #expect(WorkOrderAnalysis.masterSwitchTitle == "🔔 Notifications for this ship")
        #expect(WorkOrderAnalysis.masterSwitchHelp == "Master on/off switch for THIS ship's work-order notifications.")
        #expect(WorkOrderShippalmReader.headerMissingMessage
                == "Could not find the Shippalm header row (expected 'No.' and 'Title').")
        #expect(WorkOrderColumn.allCases.map(\.rawValue)
                == ["Done", "Notify", "Job No.", "Title", "Due", "Interval", "Status", "Due Status", "Category",
                    "Responsible", "Function"])
        #expect(WorkOrderColumn.allCases.map(\.width) == [48, 52, 110, 260, 150, 80, 90, 90, 80, 130, 220])
        #expect(WorkOrderTone.red.hex == "#FFD45050" && WorkOrderTone.orange.hex == "#FFE8890C"
                && WorkOrderTone.amber.hex == "#FFC9A227" && WorkOrderTone.green.hex == "#FF2E9E5B"
                && WorkOrderTone.gray.hex == "#FF8A8A8A")
    }

    @Test func portsTexts() {
        #expect(PortsAnalysis.searchPlaceholder == "Search port / country / UN-LOCODE...")
        #expect(PortsAnalysis.noCallsSummary == "No ports imported yet for this vessel. Click “Import ports (.xlsx)...”.")
        #expect(PortsAnalysis.selectToDeleteHint == "Select one or more ports to delete.")
        #expect(PortsAnalysis.exportEmptyMessage == "No ports to export for this vessel.")
        #expect(PortsAnalysis.exportDialogTitle == "Export ports of call")
        #expect(PortsAnalysis.importDialogTitle("V") == "Import ports of call for V")
        #expect(PortsAnalysis.exportedHint(count: 14, vessel: "V") == "Exported 14 port(s) for V.")
        #expect(PortsAnalysis.deleteConfirmMessage(count: 2, vessel: "V")
                == "Delete 2 port call(s) from V? Their visit is also removed from the ports database.")
        #expect(PortsAnalysis.deletedHint(count: 2) == "Deleted 2 port call(s).")
        #expect(PortsAnalysis.dbTitle == "⚓ Ports Database")
        #expect(PortsAnalysis.dbDescription
                == "Every port any vessel has called, built from the ports imported on each vessel's Ports tab. Select a port to see which vessels called and when.")
        #expect(PortsAnalysis.dbNoSelectionHeader == "Select a port to see the vessels that called.")
        #expect(PortColumn.allCases.map(\.rawValue)
                == ["Port", "Country", "UN/LOCODE", "Arrival", "Departure", "Sec P", "Sec V", "SSP", "Port Facility",
                    "Special measures"])
        #expect(PortColumn.allCases.map(\.width) == [150, 120, 90, 130, 130, 55, 55, 50, 180, 200])
        #expect(VesselText.workOrdersExportName(nil) == "WorkOrders-vessel.xlsx")
        #expect(VesselText.portsExportName("A/B") == "Ports-A_B.xlsx")
    }
}
