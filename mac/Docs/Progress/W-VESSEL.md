# W-VESSEL — progress (OWNERSHIP §3 W-VESSEL, §4)

**Feature IDs: 91 / 91 done** (VESSEL-001–007, 010–028, 040–055, 100–123, 200–212, 250–256, 281–282, 285, 046a;
SHELL-157). Remaining: 0. Not done: none.

Post-merge items (need other owners' real code, verified in Stage V — not part of in-worktree "done"):

| Item | Depends on | Where |
|---|---|---|
| VESSEL-001/002 tab strip order + Quick Cards selected on vessel selection; VESSEL-005 detached-vessel panels | W-HIER vessel detail tabs | host embeds `QuickCardsPanel` / `WorkOrdersPanel` / `VesselPortsPanel(vesselID:)` and publishes `VesselActions.menuActions` |
| VESSEL-025 opening targets, VESSEL-044 import a copy | W-PERSIST `AttachmentOpener` / `AttachmentStore` | gated tests `Vessel/VesselPostMergeTests.swift` (3) |
| Quick Look of file cards | W-FILES `QuickLookCoordinator` | manual |
| Work-order notifications (DECISIONS 10 Q7) | W-SHELL `ReminderCenter` + `NotificationCenterBridge` | manual |

## Delivered

* AACore/Vessel: `MaritimeIcons` (contract, ARCH §6.8), `QuickCardLayout` (canvas, cascade, drag/resize clamps,
  editor size parsing, tooltip/prompt texts, flag table), `VesselText` (NormDate/NormTime, safe export names),
  `PortCallReader` (both layouts, detection, errors, formula hint), `PortsService` (Apply, fixed RemoveCall, export),
  `PortsAnalysis` (panel filter/sort/summary, Ports DB list/status/visits), `WorkOrderShippalmReader` (read, ParseBool,
  Overdue Days, 16-column export), `WorkOrderAnalysis` (upsert, combos, filters, sort, DueInfo, summary, bar, bulk
  actions), `WorkOrderAlerts` (notification digest dedup). `ContractStatus.wVesselImplemented = true`.
* AA/Vessel: `QuickCardsPanel`, `QuickCardEditorSheet`, `WorkOrdersPanel`, `VesselPortsPanel`, `PortsDatabaseTabView`,
  `VesselActions` + `VesselTab`, `WorkOrderNotifications`, `VesselFlows` (shared panel/menu flows),
  `VesselSessionState` (VESSEL-003 session state, change revision, busy flags), `VesselDebugSnapshots`.

## Tests (Tests/AACoreTests/Vessel) — 55 tests (+3 gated on W-PERSIST)

10 §7.1 NormDate (15 vectors), §7.2 NormTime (10), §7.3 split/keys/displays, §7.4/§7.5 POC layouts (fixtures copied to
`Fixtures/vessel/`), §7.6 scenarios 1–8 (7–8 per DECISIONS Q3), §7.7 lossy re-import (35/12/35), §7.8 ExcelDate /
ParseBool / Overdue Days, §7.9 header detection, §7.10 upsert, §7.11 DueInfo + DST, §7.12 summary + bar, §7.13 filters
and sort, §7.14 quick cards, §7.15 JSON round trip, §7.16 export → import round trip, X.8.1 columns C·D / C·T,
X.8.9, 2 524-row parse < 1 s, notification dedup with `FixedClock`.

## Snapshots (both appearances checked)

`TabPorts` (Ports Database, with and without a selection), `--sheet w-vessel.quick-cards`, `w-vessel.work-orders`,
`w-vessel.ports`, `w-vessel.quick-card-editor` (+ `-new`); fixture `Fixtures/ui/w-vessel/sample-data.json`.
