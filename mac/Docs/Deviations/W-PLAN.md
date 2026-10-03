# W-PLAN — progress record, deviations and P2 fixes

Spec 07 (Calendar, Board, Planner, Buckets, Relationship Map) + 02 REPO-031, 05 CONT-050, 06 BUILD-101 / BUILD-145
B3·B4, 09 CREW-091. Format of the deviation tables: ID · spec reference · one line. Stage V merges them into
`Docs/DEVIATIONS.md`.

## Progress record (belongs in `Docs/Progress/W-PLAN.md` — see REQ-W-PLAN-01)

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

## P2 defect fixes (data stays readable by Windows with the same meaning)

| ID | Spec ref | Fix |
|---|---|---|
| W-01 | 07 §4.2.7 | Every Board / Calendar / Planner / Buckets action resolves the store and the target item by id at action time; nothing captures a repository or model object across a reload. |
| W-02 | 07 VIEW-013 | The Done checkbox writes the model first, then MarkDirty + FlushIfDirty. |
| W-03 | 07 §4.1.4 | Agenda occurrences read the live model, so ticking one occurrence updates its siblings at once. |
| W-04 | 07 VIEW-048 | Board cards show their selection (accent ring + selection fill); ⌘-click / ⇧-click per column, ⌘A selects the focused column. |
| W-05 | 07 VIEW-094 | The Planner day header and due strip scroll horizontally with the hour grid (one horizontal scroll view). |
| W-06 | 07 VIEW-083 | The pool search field shows its placeholder "Search jobs...". |
| W-07 | 07 VIEW-093 / 097 | Today is tinted (accent at 5–8 %) in both appearances in the header, due strip, hour column and month cell. |
| W-10 | 07 VIEW-205 | Calendar procedure rows, Planner procedures (Q-07), Buckets Task/Procedure members and Map nodes navigate through `Navigator.navigate(to:)` (by kind, never by tab index). |
| W-13 | 07 VIEW-179 / 181 | A node click also selects the item in the Inspect list; the map redraws live from the store (relationship edits, reloads). |
| W-15 | 07 VIEW-014 / 151 | Double-click acts only on the clicked row (Table / List `primaryAction`), never a stale selection; the Done checkbox is isolated from the row's double-click. |
| W-17 | 07 §2.4 | An immediate save that fails shows `Save failed` with the message (the store stays dirty and retries) instead of the crash dialog. |
| W-18 | 07 VIEW-095 | A timed block that runs past 24:00 is clipped at the bottom of its day. |
| W-19 | 07 §4.5.3 | An item that lists its own id in RelatedIds is not drawn as its own neighbour. |
| 07 Q-02 | VIEW-052 | Board deletes purge references to the whole subtree (F2 `trashSubtask` / `trash`). |

## Sanctioned decisions applied (DECISIONS 02 / 07)

| ID | Spec ref | Behaviour |
|---|---|---|
| 02 Q-4 / 07 Q-01 / W-11 | VIEW-052 | Board "Delete task" keeps the Windows confirmation text (`Confirm`, `Delete task '{name}'?` + `\n\nThis also deletes its {n} subtask(s).`) with buttons Move to Trash / Cancel (Cancel default), then moves the card to the Trash — `trash(_:)` for a top-level task, `trashSubtask(_:)` for a nested card — saves, and posts `'{name}' moved to Trash — ⌘Z to undo.`. ⌘⌫ on a focused column: one card → this flow (menu title `Delete Task`, T-KB-06); several cards → W-HIER's `BatchActions.confirmAndTrash` (one undo batch). |
| 07 Q-03 / W-12 | VIEW-053, VIEW-202 | Board "+ New task" logs `Added / Task / {name} / ""` (F2 `createTopLevelTask(logKind: "Task")`); each task created from a saved list logs `Added / Task / {title} / from saved list '{list}'` (new Detail string, modelled on REPO-091's `from saved list '{tpl}'`). |
| 07 Q-04 | §2.1 | Item locks are not enforced by these pages (parity). |
| 07 Q-06 / W-08 | VIEW-090, 095, 098 | Completed procedures, steps and crew items grey (#6B7785) like completed tasks; the pool strikes done rows. |
| 07 Q-07 / W-09 | VIEW-104 | Double-click on a procedure block/chip/pool row flushes and navigates to it in the Procedures section. |
| 07 Q-08 / W-16 | VIEW-202, 210, 214 | The saved-list picker is F3's shared picker: selections survive filtering, results come back in selection order and are appended to `Data.Tasks` in that order. |
| 07 Q-09 | VIEW-010, 082, 088, 097 | Weekday / month names in chrome use `Locale.current` (Gregorian), including the Planner Month header (Windows hard-coded "Sun…Sat"); tests pin en_US. Week math stays Sunday-start. |
| 07 Q-10 / W-14 | VIEW-178 | Map nodes use the per-kind pastel fills (Equipment #4FC3F7, Task #FFB74D, Procedure #A5D6A7, Vessel #CE93D8) with black text and border (centre 3 pt + an accent focus halo so it reads on the dark canvas). |
| 07 Q-11 | VIEW-142 | Bucket categories are grouped case-insensitively for display; the group label is the first spelling in sort order; stored strings are untouched. |
| 07 Q-12 / VIEW-019 | VIEW-008, 010 | All Upcoming and Agenda get a leading `Overdue` group (past-due, not complete, one row per item, never fanned out; Agenda sorts it by deadline then name). In All Upcoming the remaining rows sit under an `Upcoming` header when an Overdue group exists; without overdue items the list stays flat (parity). New Mac strings: `Overdue`, `Upcoming`. |
| Q-6 / 07 Q-05 | §5.3 | Planner placements (`ScheduledStart`, hour-grid range extensions, month moves and slides, point deadlines) are written as Unspecified calendar values (Windows wrote Local for day drops and kept the old kind on month slides). An untouched date keeps its original text. |
| 06 BUILD-145 B3 / B4 | VIEW-147, 149 | `Set category...` saves on every OK and blank clears; Cancel on `Category (optional)` still creates the bucket uncategorised. |

## Mac-grace additions (P4; no capability removed, no data change)

| Ref | Addition |
|---|---|
| VIEW-001 | Calendar sidebar: a Today button, the selected day, and a colour key; header line with the item / overdue count; empty state "Nothing scheduled". Status cells coloured by state; overdue "When" dates red. |
| VIEW-020 | Ui keys are written when they change (selected date — only when the user picks one — and mode without MarkDirty, like CaptureUiState; font size with MarkDirty; map focus without MarkDirty). Sections are created lazily (ARCH §7.2), so a page that was never opened leaves its keys untouched (Windows rewrote CalendarViewMode / CalendarSelectedDate / MapFocusedItemId at every capture). |
| VIEW-207 | Every page re-initialises from `Ui` (Calendar date/mode/font, Planner Day + today, Map focus) when `store.generation` changes; selections are kept by id where the item still exists. |
| VIEW-040 | Board column header counts animate; "No cards" / "No matches" placeholders; hover lift on cards; drop target glows in the column colour; card-shaped drag preview. |
| VIEW-051 | The >15-files confirmation uses Open All / Cancel buttons (same message and title). |
| VIEW-087 | Day / Week columns widen to fill a larger pane (never narrower than 700 / 132); block geometry uses the actual width. A red "now" line in today's column; a dashed ghost block at the snapped time while dragging over the hour grid; month cells highlight as drop targets; block/chip context menu Edit… (or Show in Procedures) and Unschedule (same effect as a pool drop). |
| VIEW-141 | Buckets list context menu (Rename / Set category... / Delete) and empty states for the members pane; members show kind glyphs. |
| VIEW-170 | Map: dot-grid canvas, zoom (buttons, pinch, 35–250 %), Fit, Center, drag-to-pan, hover highlight of a node's edges, double-click / context menu "Show in {Section}", "Open in New Window", "Focus Here"; animated recentre (nodes glide, edges interpolate); a colour key. |
| ⌥⌘F | Board Find, Planner Search jobs..., Map Inspect search are published through `SectionCommands.focusSearchField` (REQ-W-PLAN-02). |
| VIEW-001 / 083 / 140 / 170 | The 6-wide GridSplitter is `CalSplitView` (resizable, width not persisted, double-click restores the default). Default leading widths: Calendar 264 (Windows 320; the graphical month picker needs ~160, and the five columns then fit a 1440-pt window), Planner 230, Buckets 340, Map 260. |
| VIEW-084 | Pool row: the `{JobName}` part truncates, the `   ·   {DurFmt}` part never does (same string, tooltip shows it whole). |
| ⌘+ / ⌘− | Calendar text size through `SectionCommands.calendarFontScale` / `setCalendarFontScale` (SHELL-605/606, T-KB-26/27); ⌘← / ⇧⌘T / ⌘→ through the planner closures (SHELL-632…634). |
