# W-HIER — progress (Hierarchy pages & item windows)

Owner card: OWNERSHIP §3 "W-HIER". Feature IDs (OWNERSHIP §4): **98 / 98 implemented**, 0 remaining.

| Group | IDs | Done |
|---|---|---|
| 04 hierarchy pages | HIER-001–006, 010–027, 030–034, 040–044, 050–058, 060–064, 070–073, 080–087, 090, 100, 110–117, 121–122, 124–125, 133–135, 140–141, 150, M01–M05, M07 | 86 / 86 |
| 02 repository callers | REPO-023–026, 028, 043, 051, 053, 075, 106 | 10 / 10 |
| 07 shared batch menus | VIEW-200, VIEW-201 | 2 / 2 |
| Caller rows | VIEW-212 rows 7–12 (group move / rename / delete pickers, Add relationship, Pick procedures, Pick tasks; VIEW-215 normalisation); BUILD-144/145 prompt callers of the hierarchy pages | all |

Not done: none. Not applicable: none.

## Contracts
- AACore (ARCH §6.8): `TagParser` (parse / display / matches) — real; `HierarchyContractStatus.wHierImplemented = true`.
- AA (ARCH §7.7): `HierarchyTabView(kind:)`, `ItemWindowView(itemID:)`, `LockGateView(itemID:)`, `ItemLockSheet(itemID:)`,
  `BatchContextMenuItems(selection:refresh:done:deadline:)`, `BatchActions.markDone / setDeadline / confirmAndTrash`.
- `Scripts/check-placeholders.sh W-HIER`: empty.

## Tests (in-worktree acceptance)
35 tests in 4 suites under `Tests/AACoreTests/Hierarchy/`: 04 §7.1 TagParser, §7.7 sidebar build (order, A→Z,
placeholders, search incl. `#tag`, Id sectioning, expand keys, hints, 5 000-row scale), §7.9 safe file names,
§7.11 relationships (incl. Q-B one-way rows, candidate order), §7.12 messages, HIER-058 lock validation, §3.5
duration text, HIER-080 range coercion against the model, group / link / component / subtask operations, Ui keys,
and the router inputs the pages publish (T-KB-02/03/24/25/35/36/49…51). Full gate: 434 tests / 72 suites green.

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
