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

## Verification fixes (FIX-W-CREW, branch fix1/W-CREW)

9 findings: 9 fixed, 0 not fixed.

| Finding | IDs | Fix |
|---|---|---|
| Editor Save wrote a stale pre-reload draft (major) | CREW-072…074, DECISIONS 06 R1 | `CrewEditorDraft` subscribes to `store.dataReplaced` and re-bases (untouched rows take the reloaded values, edits kept, note shown); Save uses `CrewEditorForm.apply(_:original:to:)`, which never writes an untouched row whose stored value changed under the editor. Tests: `CrewEditorReloadTests` (4). |
| Import COMPAS… not gated in a read-only copy / stopped editing | CREW-003/010/030, DATA-174 | `CrewActions.importGated` (= the router's `writeGated`) disables the roster and empty-state buttons with `PersistReadOnlyText.disabledHelp`; `importCompas` itself refuses (status line). |
| Import summary survived a tab switch / reload | CREW-001, CREW-016 | `CrewRosterModel.refresh(today:)` on tab selection (and appear) clears the summary; the model subscribes to `dataReplaced` and clears it on every reload. |
| Import selected the first FILE row | CREW-017, CREW-034 | Explicit select removed; `CrewRosterModel.reconcile` keeps the Key or selects the first row in the roster's sort order. |
| Table window wrote stale chooser state after a reload | CREW-104 | `CrewTableModel.attach` re-reads the four Ui keys on `dataReplaced` (selection kept). |
| Clear All: Esc did not cancel | CREW-061 | Cancel has `role: .cancel` (⎋); Clear All stays the Return default like Move to Trash (Trash batch, ⌘Z). |
| Table: Sign-Off Date / Contract Status off-screen | CREW-103 | Starting column widths reduced; on open the window grows (never past the screen) to fit the shown columns; chooser max 280. Stripes off. |
| Editor too narrow for the checklist builder | BUILD-002/019, CREW-075 | Sheet grows from 640 to 860 pt on the Checklist tab. |
| Header: two rows of text buttons (design) | CREW-010/011 | One header row + one 24-pt icon bar + overflow menu, spec names as accessibility labels and spec tooltips as help. Card, editor and row restyled to the design rules (mono hierarchy, trailing muted labels, BuilderSheetHeader, 44-pt footer). |

Cross-owner request: F3 `AAApp.swift` — `crew-table` `.defaultSize(width: 1100, …)` → `1360` so the window opens at the
fitted width without the on-open grow (optional; the grow already handles it).

Snapshots (light + dark, `snapshots/fix1-W-CREW/`): roster, editor Details, editor Checklist, table window.

Gate: build, 1590 tests, `check-ownership.sh` pass.

## Round-2 verification fixes (FIX2-W-CREW, branch fix2/W-CREW)

6 findings: 6 fixed, 0 not fixed, 0 rejected. The two crew-table findings (V2-J5 and V2-DESIGN) were the same defect,
so one fix covers both.

| Finding | By | IDs | Fix |
|---|---|---|---|
| Blocker: duplicate `ScheduleEntry` ids crashed the Schedule tab (`Dictionary(uniqueKeysWithValues:)`) | V2-COMPAT | BUILD-116…119, ARCH §9.7 | `CrewScheduleGroup.entryOffsets` (parallel to `entryIDs`). The timeline resolves rows by position and identifies them by object (`ObjectIdentifier`), so it has no id-keyed dictionary. Two entries with the same Id show as two rows, and delete stays by reference. Repro (snapdata-full, crew[0] with two `55555555-…` entries, `--sheet w-crew.editor-schedule`): exit 0, both rows shown. |
| Major: the Crew section overflowed the main window below about 1170 pt (sidebar and card clipped, Edit… and Open Checklist… off-screen) | V2-J5 | CREW-010, CREW-020/022, 09 §6.4 | Cause: the section's `HSplitView` runs under the floating sidebar, so each pane's hosting view received the sidebar's leading safe-area inset. The minimum was therefore 290 + 420 + 2 × 228 = 1167 pt. The fix pads the split view 1 pt on the leading edge so it is laid out inside the safe area, and moves the geometry into `AACore/Crew/CrewLayout.swift`: roster minimum 240 (ideal 340), card minimum 340, section minimum 582, so 228 + 582 = 810 ≤ 860. The card's Edit… and Open Checklist… buttons are `fixedSize`. The checklist box moves the button under the summary when the card is narrow (`ViewThatFits`). Checked at 860 × 600, 900 × 640, 1100 × 720 and 1470 × 900: nothing is clipped. |
| Polish/minor: crew table headers and cells truncated (`Date of Bir…`, `Sign-Off Da…`, `Contract Stat…`, `United Kingd…`) | V2-J5, V2-DESIGN | CREW-103 | `CrewTableSizing.idealWidth`: the larger of the base width, the measured header (aaMono 13) + 22, and the widest cell (aaMono 12) + 14, with cell growth capped at 320 pt. `neededWindowWidth` uses the same values, so the open-time window fit grows with them. Snapshot: all nine default headers and cells are shown in full. |
| Polish: the card's Review notes header showed two flags | V2-J5 | CREW-024 | The header shows the `flag` symbol and `CrewRoster.reviewNotesLabel` (`Review notes (n)`). `reviewNotesTitle` (with ⚑) stays the accessibility label. |
| Polish: adopt the V2-J5 crew journey | V2-J5 | 09 §7, 06 §I | Adopted as `Tests/AACoreTests/Crew/V2J5CrewJourneyTests.swift`, together with `crewChecklistDeadlineReachesReminders` from the vessel journey. The vessel journey belongs to W-VESSEL (cross-owner request). |

Design rule 14 (ISO date pickers): the editor's date rows and the schedule add row set
`.environment(\.locale, en_CA)` on their `OptionalDatePicker`, so the picker shows `2026-10-03`.

Regression tests: `CrewRound2RegressionTests` (6: duplicate ids through a data.json round trip, offsets parallel to
ids, section minimum width, header and cell column widths with the cap, one flag) and `V2J5CrewJourney` (3).

Snapshots (light and dark) in `snapshots/fix2-W-CREW/`: Crew tab at 860/900/1100/1470, crew table, card notes,
editor Details, and Schedule with duplicate ids.

Gate: build, 1663 tests, `check-ownership.sh --owner W-CREW` pass.
