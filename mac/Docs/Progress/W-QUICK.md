# W-QUICK — progress (OWNERSHIP §3 "W-QUICK", §4 rows)

## Counts
- Feature IDs: **109 / 109 done**, 0 remaining, 0 N/A.
  - 08 QUICK-001–020, 022–025, 040–055, 060–062, 064, 070–084, 100–107, 120–125, 150–156, 170–178, 191–193,
    213–214, 231 (95)
  - 01 DATA-100, DATA-113; 02 REPO-044, 078, 092, 100, 114; 03 SHELL-672, 673, 675; 06 BUILD-102;
    07 VIEW-153, VIEW-213 (+ VIEW-212 caller rows 2–3); 09 CREW-090 (14)
- Placeholders: `Scripts/check-placeholders.sh W-QUICK` empty; `WindowsContractStatus.wQuickImplemented = true`.
- Tests: 55 (suites `DueListTests` 19, `QuickWorkTests` 16, `WindowsSearchTrashReviewTests` 13, `ActivityLogTests` 7).
- Swift: 18 files / ~4.9k lines (AACore models 4, AA views 10, tests 4).
- Gate: `swift build -j 3 -Xswiftc -warnings-as-errors` and `swift test -j 3 -Xswiftc -warnings-as-errors` green
  (454 tests, 72 suites, clean build); `Scripts/check-ownership.sh` reports exactly one failure — this file's path
  `Docs/Progress/W-QUICK.md`, which the lead's REQ-F1-01 ruling requires but the F1-owned script does not map yet
  (REQ-W-QUICK-01). Checks 2–4 (files, basenames, symbols) pass.

## Vectors covered (in-worktree acceptance)
- 08 §7.1 T-DUE-1…18 (T-DUE-17 via `DueWindowGeometry`), §7.2 T-QW-1…13 (T-QW-13 adapted to the Trash per
  DECISIONS 02 Q-4), §7.4 T-SR-1/4/8/10 (window side; F2 owns the service vectors), §7.5 T-AL-1…6 (+ 02 T-LOG-4),
  §7.6 T-TR-1…5 through `TrashActions`; 08 §7.7 summary lines (T-DF-1, T-DF-9); 03 T-KB-55/56/57 at model level.
- T-KB-08/09 (one reusable Search window): F3's single-instance `Window` scene + `SearchWindowActions.focusQuery`.

## Snapshots (both appearances, `scratchpad/snapshots/W-QUICK/`)
`due`, `switcher`, `quick-work --select <procedure>` / `<task>`, `activity-log`, sheets `w-quick.trash`,
`w-quick.review`, `w-quick.search` (+ registered `w-quick.review-empty`, `w-quick.switcher`, `w-quick.switcher-pump`).
Fixture: `Tests/AACoreTests/Fixtures/ui/w-quick/sample-data.json` (dates around 2026-10-02).

## Not done / post-merge (Stage V)
- "Open full builder…", "Edit…" and the children editors open W-BUILD's `SubtaskBuilderSheet`,
  `ChecklistBuilderSheet`, `TaskItemEditorSheet`, `ChecklistStepEditorSheet` — placeholders in this worktree; verify
  after the merge (card's post-merge item).
- Live key handling (⌘⌫ family in the Trash sheet, ↑↓↩⎋ in the switcher, ↩ in Search) is wired in the views and
  checked by snapshot / manual run only (no UI-test target).
- The snapshot hook renders Liquid Glass (switcher background) as a flat fill.

## Independent audit (2026-10-02)
All 109 IDs re-checked against the spec text and the C# (`FloatingTasksWindow`, `QuickWorkWindow`,
`ActivityLogWindow`, `TrashWindow`, `DiffWindow`): 106 were OK as built, 3 were fixed in the audit, 0 are missing.
- QUICK-001: re-opening the due panel through any entry point (including `SceneOpener.open(.due)`, which did not
  refresh) now runs `Activate()` + `Refresh()`.
- QUICK-152 / QUICK-155 (§4.6 byte parity): `TimeUtc` prints the stored wall clock unconverted, like
  `TimestampUtc.ToString("… 'UTC'")` (an offset-bearing stamp was being converted to UTC — different bytes from
  Windows). `Csv()` tests and doubles per scalar like .NET's per-char `Contains`, so `,`/`"` carrying a combining
  mark (one Swift `Character`) still quotes. Vectors added to `ActivityLogTests`.
- QUICK-192: the review tree's expansion state is seeded in `init` (it was set in `onAppear`, which made the outline
  re-enter its NSTableView delegate — AppKit warning in every render).
- Visual: the Activity log columns now fit the 860-pt window (Detail was pushed past the right edge and clipped);
  Kind/Name/Detail wrap inside the window.
Snapshots re-rendered in both appearances: `scratchpad/snapshots/W-QUICK/audit-*.png` (due, switcher, quick-work task /
procedure / none selected, activity log, trash, review, review-empty, search sheet, search window).
