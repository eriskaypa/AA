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

## Tests (Tests/AACoreTests/Vessel) — 58 tests (+3 gated on W-PERSIST)

10 §7.1 NormDate (15 vectors), §7.2 NormTime (10), §7.3 split/keys/displays, §7.4/§7.5 POC layouts (fixtures copied to
`Fixtures/vessel/`), §7.6 scenarios 1–8 (7–8 per DECISIONS Q3), §7.7 lossy re-import (35/12/35), §7.8 ExcelDate /
ParseBool / Overdue Days, §7.9 header detection, §7.10 upsert, §7.11 DueInfo + DST, §7.12 summary + bar, §7.13 filters
and sort, §7.14 quick cards, §7.15 JSON round trip, §7.16 export → import round trip, X.8.1 columns C·D / C·T,
X.8.9, 2 524-row parse < 1 s, notification dedup with `FixedClock`, every exact user-visible string of the three
panels, the editor and the Ports Database (`VesselUserStringTests`).

## Snapshots (both appearances checked)

`TabPorts` (Ports Database, with and without a selection — `AA_SNAPSHOT_PORT`), `--sheet w-vessel.quick-cards`
(also empty, `AA_SNAPSHOT_VESSEL="BW Lilac"`), `w-vessel.work-orders` (also empty), `w-vessel.ports`,
`w-vessel.quick-card-editor` (+ `-new`); fixture `Fixtures/ui/w-vessel/sample-data.json`. Render the 1320-wide panel
sheets with `--size 1480x900` (the default 1280-wide window clips them).

## Audit (independent pass)

All 91 IDs re-checked against 10 §2–§7 and the C# (`PortCallReader.cs`, `ShippalmReader.cs`, `PortsPanel.xaml.cs`):
91 OK after fixes, 0 partial, 0 missing. Fixed in the audit: Ports Database visits table clipped the `Imported`
column (fixed widths); Work Orders toolbar orphaned `shown OFF` on a third row (regrouped); editor sheet lacked the
`Quick card` title (VESSEL-040); export save panels showed their title only in an invisible title bar; added the
X.7.3 Finder drop-to-import on Work Orders / Ports; added exact-string tests.

## Gate

`swift build` and `swift test` (-j 3, warnings as errors) green: 460 tests, 0 failures (3 W-PERSIST-gated skipped).
`Scripts/check-placeholders.sh W-VESSEL` prints nothing. `Scripts/check-ownership.sh` fails on one path only:
`Docs/Progress/W-VESSEL.md` (required by DECISIONS REQ-F1-01, not encoded in F1's script — REQ-W-VESSEL-01).

## Fix round 1 (FIX-W-VESSEL, verifier findings V-03 / V-10 / V-DESIGN)

| Finding | Result |
|---|---|
| V-03 SHELL-157: 03 §7.1 boundary vectors untested | Fixed — `readableForegroundBoundaryVectors` asserts all six rows (#999999 → white at exactly 0.6, #9A9A9A → #1A1A1A, #FDD835, #26A69A, #9E9E9E, #EEEEEE) and the boundary expression. |
| V-10 VESSEL-025: UNC targets had no Connect to Server… / retry | Fixed in W-VESSEL code — `QuickCardOpen` (AACore) + `VesselFlows.openQuickCard`: Connect to Server… (UNC, polls 15 s, then retries), Locate… (stores mapping, retries), Open File Links Settings…, Cancel, keeping the VESSEL-025 `Open failed` / `Not found:` texts. `PersistOpenFlow.recover` is private and uses other titles, so it is not reused (no cross-owner change needed). |
| V-10 VESSEL-051: opening Edit… rewrote Width/Height | Fixed — the size fields are populated through `State(initialValue:)` in the sheet's init, so no `onChange` fires; only typing changes the card. |
| V-10 DATA-174: vessel imports / drops / Import a copy ignored the write gate | Fixed — `VesselFlows.isWriteGated` (read-only instance or Stop Editing Here); buttons disabled with the DATA-174 help, drops accept nothing, flows refuse as a backstop. Snapshot `w-vessel.work-orders-readonly`, `w-vessel.quick-card-editor-readonly`. |
| V-10 VESSEL-025: folder cards revealed the folder in its parent | Fixed — existing folder targets open with `NSWorkspace.open` (`QuickCardOpenStep.openFolder`). |
| V-10 VESSEL-109/207: wrapped columns truncated | Fixed — the five columns wrap. |
| V-DESIGN: Ports Database in system font | Fixed — aaMono hierarchy (title 16 bold, heading 13 semibold, rows 13, counts 11 muted). |
| V-DESIGN: striped empty tables, flush-left text | Fixed — no stripes on any vessel table/list; empty vessels show AAEmptyState instead of the table; 16-pt pane margins. The x = 0 text in the old snapshot came from 1320-wide snapshot frames clipped by the 1280 window — frames are now 1180 wide and pick the first vessel with data (or `AA_SNAPSHOT_VESSEL` = name or Id). |

Also per the design rules: quick-card header in mono, editor header = `BuilderSheetHeader` with a 44-pt footer.
Tests: +7 (`VesselQuickCardOpenTests` 6, boundary vectors 1). Snapshots (light + dark, looked at):
`w-vessel.work-orders`, `-readonly`, `w-vessel.ports`, `w-vessel.quick-cards`, `w-vessel.quick-card-editor`,
`-readonly`, `TabPorts` (with and without selection).

## Fix round 2 (FIX2-W-VESSEL, verifier findings V2-J5 / V2-DESIGN)

| Finding | Result |
|---|---|
| V2-J5 VESSEL-253: visits Vessel column truncated `BW Pavilion…` | Fixed — the Vessel cell wraps (`BW Pavilion` / `Aranda`), full name also in the tooltip. Rejected part: the claimed ~400 pt of free width does not exist (the original snapshot has ~10 pt to spare), and the suggested 220-pt ideal pushed `Imported` past the pane edge at 1280 pt (checked in a snapshot), so the widths stay fitted to the pane: Vessel 110 / Arrival 130 / Departure 130 / Imported 126 from `PortsAnalysis.visitsColumns` (DEVIATIONS VESSEL-253). |
| V2-DESIGN rule 17: scroller corner square in the Quick Cards canvas | Fixed — `.scrollIndicators(.never)` on the two-axis canvas (overrides "Show scroll bars: Always"); checked with `-AppleShowScrollBars Always` per process. The Relationship Map half (`Sources/AA/Board/RelationshipMapTabView.swift`) is W-PLAN's — cross-owner request. |
| V2-DESIGN rule 11: Quick Cards header hint truncated | Fixed — `AAHelpText`, wraps to a second line, no `lineLimit(1)`; the `+ Quick card` button is `fixedSize` so it never truncates instead. The SIRE body hint half (`Sources/AA/Sire/SireDetailPane.swift`) is W-SIRE's — cross-owner request. |

Tests: +5 (`VesselDesignRound2Tests`: column specs and pane budget, header-width fit, the visits table wires the
shared widths and wraps the vessel name, the header hint wraps, the canvas hides its scrollers). Snapshots (light +
dark, looked at, no runtime warnings in the logs): `TabPorts` with `AA_SNAPSHOT_PORT=Bonny`, `TabVessels --select`
(Quick Cards), `--sheet w-vessel.quick-cards`, both with and without `-AppleShowScrollBars Always`.

