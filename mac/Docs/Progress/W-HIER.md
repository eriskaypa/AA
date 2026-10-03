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
