# W-CREW — progress (OWNERSHIP §3 card "W-CREW", §4 rows)

Feature IDs: **77 / 77 done**, 0 remaining (CREW 60 + BUILD-110…125 16 + REPO-155 1); algorithm ids BUILD-A15, A16 done.

| Group | IDs | Done | Where |
|---|---|---|---|
| Entry points, tab, navigation | CREW-001…006 | 6/6 | `AA/Crew/CrewTabView.swift`, `CrewActions.swift`, `AACore/Crew/CrewExpiry.swift` (badge text/count for F3) |
| Roster | CREW-010…018 | 9/9 | `CrewTabView.swift`, `CrewRosterModel.swift`, `AACore/Crew/CrewRoster.swift`, `CrewSort.swift` |
| Read-only card | CREW-020…026 | 7/7 | `CrewCardView.swift`, `CrewRoster.swift` |
| COMPAS import | CREW-030…040 | 11/11 | `CrewCompasReader.swift`, `CrewDateResolver.swift`, `CrewConverter.swift`, `CrewMappingTables.swift`, `CrewImport.swift`, `CrewActions.swift` |
| Expiry | CREW-050, 051, 053 | 3/3 | `CrewExpiry.swift`, `CrewStoredDate.swift` |
| Delete / clear / restore | CREW-060…062 | 3/3 | `CrewTabView.swift` over F2 Trash |
| Editor | CREW-070…076 | 7/7 | `CrewEditorSheet.swift`, `CrewEditorForm.swift` (Checklist tab embeds W-BUILD's `ChecklistBuilderView(host: .crew)`) |
| Schedule builder | CREW-080…086, BUILD-110…125, REPO-155, BUILD-A15/A16 | 24/24 | `CrewScheduleBuilderView.swift`, `CrewSchedule.swift` |
| Table + Excel | CREW-100…106 | 7/7 | `CrewTableView.swift`, `CrewColumns.swift` (F1 `XlsxWriter`) |

Not done: none.

Tests: `Tests/AACoreTests/Crew/` — 72 tests: 09 §7.2–§7.15 vectors (§7.8 ContractStatus rows asserted against F1's
model too), 06 §7.2 NormTime and §7.9 timeline, the DECISIONS 09 Q1/Q2/Q3/Q4/Q6/Q7/Q8/Q9 fixes, export bytes through the
F1 writer re-read with the F2 reader.

Snapshots (both appearances, fixture `Tests/AACoreTests/Fixtures/ui/w-crew/sample-data.json`): Crew tab (roster + card),
editor Details / Schedule, card review notes (`w-crew.card-notes`), crew table window.

Post-merge (Stage V): Checklist tab with W-BUILD's real builder and step editor; due-dates window / Calendar crew rows
navigating through `Navigator.navigateToCrew` (W-QUICK / W-PLAN); reminder crew count (W-SHELL) using `CrewExpiry`.

Requests: REQ-W-CREW-01 (HSplitView vs bottom inset), REQ-W-CREW-02 (snapshot split-item redraw) — both informational,
worked around locally.

## Independent audit (Stage W)

Audited all 77 / 77 IDs against 09, 06 §I, 02 REPO-155 and DECISIONS 09/06: 77 OK, 0 partial, 0 missing; 0 not done.
The 09 §7.2–§7.15 and 06 §7.2/§7.9 vectors have passing tests. §7.13 ColRef/Esc/sheet-name rows are asserted in
F1's `XlsxWriterTests`, and the crew export round trip is asserted here.
Fixes made in the audit:
- Import: a failed save after the upsert no longer reports "Import failed".
- Card: the subtitle no longer wraps beside Edit….
- Editor: the label column fits `Sign-off date  (contract)` on one line, and an empty field shows no placeholder.
- Schedule builder: the vessel bar and add row lay out cleanly at the sheet width, and the kind glyphs are SF Symbols.

Re-checked in light and dark: roster, card, card notes, editor Details / Schedule, table window.

Gate: build and 470 tests pass. `check-placeholders.sh W-CREW` prints nothing. `check-ownership.sh` steps 2–4 pass.
Step 1 flags only this file, because `Docs/Progress/*.md` has no owner rule (REQ-W-CREW-03, pending the lead).
