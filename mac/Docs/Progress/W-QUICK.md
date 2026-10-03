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

## Verification fixes (FIX-W-QUICK, 2026-10-03)
Findings: **9 / 9 fixed**, 0 remaining.
- V-01 DATA-174: Trash `Put Back`, `Delete Immediately…`, `Empty Trash…` (footer, context menu, double-click,
  ⌘⌫ family) are disabled in a read-only copy (`env.isReadOnlyInstance || settings.isWriteGated`), with help
  `Not available in a read-only copy of AA.` (`TrashText.help(_:readOnly:)`) and a leading lock note in the footer;
  the actions also guard on it.
- V-02 REPO-078: the Trash Name column shows the raw `Name` (no `(unnamed)`), as the WPF list binds it.
- V-07: new suite `QuickWorkPickerVectorTests` (13 tests) pins 07 P5, P6, P12, P13; K7b–K7g through the quick-work
  bucket path (`preselectedBuckets` → `ShellPickerSelection` as `pickItems` drives it → `applyBuckets`); SL2
  (picker + `BoardSavedListAdd.apply`); B9 (`BoardModel.setStatus` → `save()` → `reconcileRecurrences`); DATA-174 help.
- V-08 QUICK-041: the quick-work split is an HStack with an 8-pt drag handle (`QuickWorkSplit`,
  `QuickWorkSplitGeometry`): the list opens at 360 pt (snapshot: 360 pt list at 1200×800), draggable
  (list ≥ 300, detail ≥ 420), not persisted. `HSplitView` ignored `idealWidth`.
- V-08 QUICK-010/020: due rows use `.pointerStyle(.link)` (and the grip `.pointerStyle(.frameResize)`) instead of
  `NSCursor.push/pop`, so ticking a row off under the mouse cannot leak a pushed cursor.
- V-08 QUICK-102: per-kind switcher chip kept and recorded in `Deviations/W-QUICK.md` (with the Search Where badge).
- V-DESIGN tables: Search, Trash, Activity log and the children list have stripes off; empty → `AAEmptyState` over a
  plain background (no table).
- V-DESIGN Activity log: Name is the flexible column (ideal 214, 12-pt mono, wraps ≤ 2 lines); no time column truncates.
- V-PACKAGE: the switcher's resign-key close skips only when `LaunchCoordinator.shared.snapshotMode` (DEBUG-only), not on
  a release `--snapshot` argument.
- Design rules applied across the owned views: brand mono for content (rows, meta, counts, dates with
  `.monospacedDigit`), tokens for spacing, label column muted / trailing in the quick-work detail, item actions as
  small bordered buttons, `BuilderSheetHeader` + Divider + 44-pt footer in the Trash, rounded-bezel query field in
  Search, `AASelBg/AASelFg` selection in the switcher, dynamic overdue red (`overdueMeta`) in the quick-work list.
- Snapshots (light + dark): `scratchpad/snapshots/fix1-W-QUICK/` — quick-work (+ task selected), due, switcher,
  activity-log, search window, sheets trash and search.
