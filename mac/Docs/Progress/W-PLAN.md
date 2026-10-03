# W-PLAN — progress

Moved verbatim from `Docs/Deviations/W-PLAN.md` once `check-ownership.sh` mapped `Docs/Progress/<id>.md` (REQ-W-PLAN-01, f556cb5).

| Count | Value |
|---|---|
| Feature IDs assigned (OWNERSHIP §4) | 103 |
| Done | 103 |
| Remaining | 0 |
| Not applicable | 0 |
| AACoreTests added (Calendar/, Board/) | 72 (`CalendarRowBuilderTests` 19, `PlannerTests` 20, `CalendarLayoutTests` 9, `BoardModelTests` 13, `BucketsModelTests` 5, `MapLayoutTests` 6) |
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

Fix pass FIX2-W-PLAN (2026-10-03, Stage V round-2 findings V2-J1 / V2-J2 / V2-DESIGN / V2-SCALE; 10 of 11 fixed, 1
informational): new `Sources/AACore/Calendar/CalendarLayout.swift` holds the layout decisions, tested by
`CalendarLayoutTests` (9 tests).
* V2-J1 Relationship Map: the colour key moved from a floating capsule over the canvas into a footer bar under it
  (never covers a node; hidden with no graph); the canvas shows no scroll indicators (no legacy corner square);
* V2-J2 Planner Week: columns shrink to fit the pane down to 96 pt (`PlannerGeometry.fittedDayWidth`), so the default
  window shows Sunday→Saturday with the gutter; a narrower pane scrolls today's column into view on every rebuild
  (`initialScrollX`);
* V2-J2 Planner due strip: a "+N more" row (hidden chips counted from measured frames, `hiddenChipCount`) expands the
  strip to 324 pt, "Show less" collapses it; stacks scroll without indicators (an overflowing day's chips were also
  narrowed by a legacy scroller);
* V2-J2 Calendar columns (`CalColumnWidths`): When / Status / Recurrence / Done hug their content, Task takes the spare
  width; minimums scale with the text size (no broken words at A+ 28) and never fall below the header ("Done",
  "Recurrence" no longer truncated);
* V2-J2 Calendar header count counts distinct items (`CalSchedule.summaryLine`): Agenda and All Upcoming both read
  "53 items · 12 overdue" on the snapshot data (Agenda said 73);
* V2-J2 Board columns: no scroll indicators, so cards sit 6 pt from both borders with "Show scroll bars: Always";
* V2-DESIGN Calendar mini-month: `.environment(\.locale, CalDateText.pickerLocale)` (en_CA) per the Stage V ruling;
* V2-DESIGN Buckets icon bar grey (accessory-bar buttons, `.secondary` overflow menu); the same overflow fix for the
  Hierarchy, Saved Lists and quick-work bars is requested from W-HIER / W-BUILD / W-QUICK;
* V2-DESIGN Planner chips: opacity on the fill only, ghost labels in the foreground colour, brand mono 11;
* V2-DESIGN Calendar Status cells regular weight;
* V2-SCALE timings: informational, no change.
Snapshots (light + dark, `snapdata-full`, 1280 × 820 unless noted) under `scratchpad/snapshots/fix2-W-PLAN/`: Map
(focus Main engine), Planner Day / Week / Week 1000 × 760 / Month, Board, Buckets (none / selected), Calendar Day
(1280 and 1100 × 720) / Agenda / All Upcoming at 15 and 28 / Agenda at 19.5 — no AppKit / SwiftUI runtime warnings
(a `.id(fontScale)` on the table, tried first, caused a reentrant NSTableView delegate warning and was dropped).

