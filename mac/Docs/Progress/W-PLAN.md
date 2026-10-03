# W-PLAN — progress

Moved verbatim from `Docs/Deviations/W-PLAN.md` once `check-ownership.sh` mapped `Docs/Progress/<id>.md` (REQ-W-PLAN-01, f556cb5).

| Count | Value |
|---|---|
| Feature IDs assigned (OWNERSHIP §4) | 103 |
| Done | 103 |
| Remaining | 0 |
| Not applicable | 0 |
| AACoreTests added (Calendar/, Board/) | 63 (`CalendarRowBuilderTests` 19, `PlannerTests` 20, `BoardModelTests` 13, `BucketsModelTests` 5, `MapLayoutTests` 6) |
| `Scripts/check-placeholders.sh W-PLAN` | empty |
| `ContractStatus.wPlanImplemented` | `true` |

IDs: VIEW-001–022 (22), VIEW-040–056 (17), VIEW-080–109 (30), VIEW-140–152 (13), VIEW-155, VIEW-170–182 (13),
VIEW-202, VIEW-207, VIEW-214, REPO-031, CONT-050, BUILD-101, CREW-091.

Vectors covered in-worktree: 07 §8.1 C1–C21, §8.2 B1–B13, §8.3 P1–P23, §8.4 K1–K5 / K8 (K6 is F1's migration,
K7 is W-QUICK's picker, VIEW-213), §8.5 M1–M7, A.7 R6 (map positions), SL1 / SL3, §8.7 JSON checks (as amended by
DECISIONS Q-6), 06 BUILD-101 display vector, 03 T-KB-06 (title/strings), T-KB-23 (navigation arithmetic),
T-KB-26 / T-KB-27 (font steps). §8.6 S1–S8 are F2's services (already tested there).

Snapshots checked (light and dark, `Fixtures/ui/w-plan/sample-data.json`, with `Ui.SelectedMainTabIndex` set to the
section rendered and `AA_SNAPSHOT_CACHE_DISPLAY=1` — see REQ-W-PLAN-03): Calendar Day / Week / Month / All Upcoming /
Agenda, Board, Planner Day / Week / Month, Buckets (selected / none), Relationship Map, saved-list picker and
bucket-category sheets (28 PNGs).

Independent audit (2026-10-02): gate re-run from a clean `.build` (green, 462 tests); all 103 IDs re-checked against
spec 07 (incl. the A.1 erratum / VIEW-208…216 rows that name W-PLAN), 02 REPO-031, 05 CONT-050, 06 BUILD-101 /
BUILD-145 B3·B4, 09 CREW-091 and the C# sources. Fixed in the audit:
* the four split pages (Calendar, Planner, Buckets, Map) used `HSplitView`, whose NSSplitView ignores the main
  window's bottom `safeAreaInset`: the panes ran under the shortcut strip (Buckets' status line and the strip text
  overlapped). They now use `CalSplitView` (pure SwiftUI: 6-pt splitter with hairline, resize cursor, drag, double-click
  resets, VoiceOver adjustable; panes clipped to their bounds);
* Planner Day/Week: day header and due strip moved into the pinned section header of the hour body's vertical scroll
  view, so the columns stay aligned when legacy (always-visible) scrollers take width (they were offset by half a
  scroller); the initial 07:00 scroll is retried until the body has laid out (it sometimes stayed at 00:00);
* Planner pool rows: the name truncates and the `   ·   {dur}` part stays visible (it was cut off at the default width);
* Calendar: default sidebar 264 pt and column ideals 56 / 216 / 112 / 340 / 110 so all five columns fit a 1440-pt
  window (Recurrence was scrolled off);
* Buckets: a new bucket is scrolled into view as well as selected (VIEW-147).

Post-merge (Stage V): editor sheets opened from Calendar / Planner / Board / Buckets (W-BUILD's
`TaskItemEditorSheet`, `ChecklistStepEditorSheet`), the batch context-menu items (W-HIER's
`BatchContextMenuItems` / `BatchActions`), Board "Open all files" through W-PERSIST's `AttachmentOpener`,
interactive drag and drop (not exercisable by the snapshot hook).

Fix pass FIX-W-PLAN (2026-10-03, verification findings V-07 / V-DESIGN; 7 of 7 fixed):
* V-07 Board single "Delete task" now runs the batch path's steps (flushAllEditors after the confirmation, re-resolve,
  trash, save, close the item window, drop from `detachedItemIDs`, status, Trash refresh) — VIEW-052, DECISIONS 02 Q-4;
* V-07 Calendar A- / A+ enablement uses `CalFontScale.canStep` (stored 10 → A- gives 11; stored 30 → A+ gives 28,
  C18); unit test extended;
* V-07 Calendar clipping: `CalPageHeader` flows its controls onto further lines in narrow panes (`CalFlowLayout`), the
  view-mode segments fall back to a pop-up, the sidebar default is 232 pt and the column ideals 40 / 150 / 92 / 160 /
  88 — all five columns visible at 1100 × 720 and the default 1280 × 820 (snapshots light + dark under
  `scratchpad/snapshots/fix1-W-PLAN/`); horizontal scroll only below ~1100 pt;
* V-DESIGN Calendar Status shows friendly labels (`WorkStatus.friendlyLabel`), Recurrence and the Board card meta use
  `RecurrenceKind.friendlyLabel`; test updated ("To Do", "In Progress");
* V-DESIGN Buckets header is one icon bar (`plus`, `trash`, overflow menu with Rename / Set category...);
* V-DESIGN Board cards draw OVERDUE as an `AAStatusCapsule` after the date (`BoardModel.metaParts`, test added);
* V-DESIGN Planner pool names and Map Inspect rows wrap to two lines (Map: middle truncation), Planner default
  column 256 pt.
Design-rule pass on the touched views: no zebra stripes (Calendar table, Buckets members), regular-weight row names
(Calendar Task, Buckets list), mono digits on dates / durations.
