# W-HIER — progress (Hierarchy pages & item windows)

Owner card: OWNERSHIP §3 "W-HIER". Feature IDs (OWNERSHIP §4): **98 / 98 implemented**, 0 remaining.

| Group | IDs | Done |
|---|---|---|
| 04 hierarchy pages | HIER-001–006, 010–027, 030–034, 040–044, 050–058, 060–064, 070–073, 080–087, 090, 100, 110–117, 121–122, 124–125, 133–135, 140–141, 150, M01–M05, M07 | 86 / 86 |
| 02 repository callers | REPO-023–026, 028, 043, 051, 053, 075, 106 | 10 / 10 |
| 07 shared batch menus | VIEW-200, VIEW-201 | 2 / 2 |
| Caller rows | VIEW-212 rows 7–12 (group move / rename / delete pickers, Add relationship, Pick procedures, Pick tasks; VIEW-215 normalisation); BUILD-144/145 prompt callers of the hierarchy pages | all |

Not done: none. Not applicable: none.

## Audit (independent re-check of all 98 IDs against 04 / 02 / 07 and the C#)
- Gate from a clean build: `swift build` and `swift test` green (warnings as errors), `check-placeholders.sh W-HIER`
  empty. `check-ownership.sh` fails on one path only: `Docs/Progress/W-HIER.md` (REQ-W-HIER-01 — the F1 script has no
  rule for the progress files the lead's REQ-F1-01 ruling requires; every other check of the script passes).
- 98 IDs checked: 98 fully implemented after the audit fixes. Partial before the audit (fixed): HIER-120 child
  selection (DECISIONS 02 Q-11: components never selected, nested subtasks ignored, the request never consumed),
  HIER-056 (the main-pane editor was not re-loaded on Lock Now), HIER-112 (the item window could bind its editor
  before the main pane parked), HIER-M03 (double-click on empty sidebar space opened the details item).
- New contract request: REQ-W-HIER-02 (`ProcedureChecklistSection` cannot select a navigated step; W-BUILD).

## Contracts
- AACore (ARCH §6.8): `TagParser` (parse / display / matches) — real; `HierarchyContractStatus.wHierImplemented = true`.
- AA (ARCH §7.7): `HierarchyTabView(kind:)`, `ItemWindowView(itemID:)`, `LockGateView(itemID:)`, `ItemLockSheet(itemID:)`,
  `BatchContextMenuItems(selection:refresh:done:deadline:)`, `BatchActions.markDone / setDeadline / confirmAndTrash`.
- `Scripts/check-placeholders.sh W-HIER`: empty.

## Tests (in-worktree acceptance)
36 tests in 4 suites under `Tests/AACoreTests/Hierarchy/`: 04 §7.1 TagParser, §7.7 sidebar build (order, A→Z,
placeholders, search incl. `#tag`, Id sectioning, expand keys, hints, 5 000-row scale), §7.9 safe file names,
§7.11 relationships (incl. Q-B one-way rows, candidate order), §7.12 messages, HIER-058 lock validation, §3.5
duration text, HIER-080 range coercion against the model, group / link / component / subtask operations, Ui keys,
and the router inputs the pages publish (T-KB-02/03/24/25/35/36/49…51), and child selection after navigation (DECISIONS 02 Q-11). Full gate: 435 tests / 72 suites green.

## Snapshots (both appearances; `scratchpad/snapshots/W-HIER/`)
Equipment (Container, Relationships, Specifics), Tasks (Schedule & Subtasks, locked item → lock gate), Procedures
(Checklist fields), Vessels (vessel tabs), empty Tasks page, item window (light, dark), Item-lock sheet (Change mode),
component editor. Fixture: `Tests/AACoreTests/Fixtures/ui/w-hier/`. Snapshot aid: `AA_SNAPSHOT_HIER_TAB=<tab>`
(DEBUG only) picks the initial details tab.

## Post-merge (Stage V)
Container tab / item window / component editor with W-CONT's real editor; Relationships tab with W-FILES'
`FileBacklinksSection`; procedure checklist (W-BUILD) and its export buttons (W-PDF); subtask builder and subtask
editor sheets (W-BUILD); vessel tabs and Tools ▸ Vessel actions (W-VESSEL); Export PDF… flow (W-PDF); Lock Now flow
(W-SHELL calls `ItemLockService.relockAll`, the pages and item windows re-gate by observation).

## Fix round 1 (FIX-W-HIER, verification findings V-04 / V-05 / V-10 / V-DESIGN)
- HIER-025: typing after Return no longer rebuilds/re-sorts the sidebar per keystroke (`commitRename(stillEditing:)`,
  `HierRenameState`; `HierStructureSignature` moved to AACore so it is tested).
- CONT-060…062 / D-4: the editor identity no longer flips on every password-session change; it re-loads on relock
  (Lock Now) and on unlock only for a waiting legacy body (`HierEditorReload`, `HierEditorReloadCounter`) — a gate
  prompt from inside the editor keeps caret, scroll and undo.
- VESSEL-005 / DECISIONS 10 Q5: Tools ▸ Vessel commands withheld for a detached vessel.
- HIER-085: subtasks table columns fit (Name/When flexible, Status 96, Done 44); names wrap without a 2-line cap.
- HIER-010: group headers wrap (no truncation), PanelAlt band, aligned with the rows (non-pinned header rows).
- V-DESIGN: sidebar header is one icon bar (plus-menu, trash, sort toggle, overflow) — `HierToolbarFlow` /
  `HierFlowLayout` removed; rows aaMono 13 (font on the Text); page title aaMono 16 bold; item window uses
  `AAKindBadge` and a footer bar; no zebra rows (relationships, components, subtasks); raw `.system(size:)` text
  replaced with tokens (lock gate, lock sheet, component editor, drag preview, subtask builder button).
- Tests: `Tests/AACoreTests/Hierarchy/HierPageStateTests.swift` (3 tests). Gate: 1,589 tests green.
- Snapshots (light + dark): `scratchpad/snapshots/fix1-W-HIER/` — eq4 (sidebar), task-narrow (1100×760, subtasks),
  itemwin (item window); before-* for comparison.

## Fix round 2 (FIX2-W-HIER, verification findings V2-SCALE / V2-COMPAT / V2-DESIGN)
Counts: 4 findings — 2 fixed, 1 not fixed (framework), 1 rejected.
- Fixed (V2-SCALE, HIER-121 / §3.2 reveal): the selected row is centred (`scrollTo(anchor: .center)`), the jump is
  repeated over ~0.3 s so lazily measured wrapping rows settle on it, and the request is honoured when the sidebar
  appears (`.task(id:)`), so the restored `Ui.Selected{Kind}Id` is revealed at launch. A collapsed group reveals
  its header (`HierSidebar.revealRowID`). Large data (500 equipment / 5 000 tasks): Task 0245, Equipment 072
  (Navigation), launch Equipment 000 and Task 0000 all centred.
- Fixed (V2-COMPAT, items sharing an Id): rows, List selection and the page index are keyed by `HierRowKey` (the Id,
  or a derived key for a later duplicate); the details are keyed by object. The "(DUP)" task shows, selects and
  renames on its own; stored ids stay real (Deviations: "V2-COMPAT (dup Ids)").
- Not fixed (V2-SCALE "reentrant operation in its NSTableView delegate"): a SwiftUI/AppKit defect on macOS 27.0.1.
  A 40-line standalone app with a plain `List` of 500 `Text` rows (no AA code) logs the same warning with the same
  stack (`OutlineListCoordinator.diffRows → NSTableRowData endUpdates → _keepTopRowStableAtLeastOnce → rowAtPoint →
  NSTableRowHeightData _cacheRowSpansInRange`); ~200 rows or fewer do not. In AA, fixed-height single-line rows,
  rows equal to the table's 24-pt estimate, no sections, no drag / context menu / overlay / list style / commands,
  and a fixed sidebar width all still log it; capping the list to ~60 rows silences it. Fixed heights would only
  have broken HIER-018 (wrapping names). Removing it means replacing the SwiftUI `List` with an AppKit table (lead
  decision; ARCH §9.7 / HIER-019 name a lazy `List`).
- Rejected (V2-DESIGN rule 6, item-window labels): `HierItemWindowFields.label(_:)` already is
  `.font(.aaMono(AAType.body))`, `AAColor.muted`, trailing in a fixed 90-pt column, and item-task-light.png shows
  mono labels.
- Tests: `Tests/AACoreTests/Hierarchy/HierRowKeyTests.swift` (3 tests: keys, duplicate-Id journey, reveal target).
  Gate: 1,657 tests green, check-ownership OK.
- Snapshots (light + dark where UI changed): `scratchpad/snapshots/fix2-W-HIER/` — tasks245, eq072, eqlaunch,
  taskslaunch (large data), dup-tasks (duplicate Ids), small-tasks / small-eq (snapdata-full); base-* = before.
