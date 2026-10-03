# W-PLAN — deviations and P2 fixes

Spec 07 (Calendar, Board, Planner, Buckets, Relationship Map) + 02 REPO-031, 05 CONT-050, 06 BUILD-101 / BUILD-145
B3·B4, 09 CREW-091. Format of the deviation tables: ID · spec reference · one line. Stage V merges them into
`Docs/DEVIATIONS.md`.

## Progress record

Moved to `Docs/Progress/W-PLAN.md` (REQ-W-PLAN-01).

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
| VIEW-001 | Calendar sidebar: a Today button, the selected day, and a colour key; header line with the item / overdue count (distinct items — an Agenda fan-out counts once, so Agenda and All Upcoming agree; FIX2); empty state "Nothing scheduled". Status cells coloured by state (regular weight, rule 2 — Windows semi-bold); overdue "When" dates red. The graphical mini-month carries the `en_CA` locale (DECISIONS Stage V ruling: ISO date pickers; weeks start on Sunday like the Calendar / Planner week math). |
| VIEW-020 | Ui keys are written when they change (selected date — only when the user picks one — and mode without MarkDirty, like CaptureUiState; font size with MarkDirty; map focus without MarkDirty). Sections are created lazily (ARCH §7.2), so a page that was never opened leaves its keys untouched (Windows rewrote CalendarViewMode / CalendarSelectedDate / MapFocusedItemId at every capture). |
| VIEW-207 | Every page re-initialises from `Ui` (Calendar date/mode/font, Planner Day + today, Map focus) when `store.generation` changes; selections are kept by id where the item still exists. |
| VIEW-040 | Board column header counts animate; "No cards" / "No matches" placeholders; hover lift on cards; drop target glows in the column colour; card-shaped drag preview. |
| VIEW-051 | The >15-files confirmation uses Open All / Cancel buttons (same message and title). |
| VIEW-087 | Day / Week columns fill the pane: Day never narrower than 700; Week shrinks to fit the 7 days down to 96 pt (Windows a fixed 132), so the default 1280 × 820 window shows Sunday→Saturday with the hour gutter (FIX2); only a pane narrower than 52 + 7 × 96 scrolls horizontally, and then every rebuild scrolls today's column into view (centred), like the 07:00 vertical scroll. Block geometry uses the actual width. A red "now" line in today's column; a dashed ghost block at the snapped time while dragging over the hour grid; month cells highlight as drop targets; block/chip context menu Edit… (or Show in Procedures) and Unschedule (same effect as a pool drop). |
| VIEW-141 | Buckets list context menu (Rename / Set category... / Delete) and empty states for the members pane; members show kind glyphs. |
| VIEW-170 | Map: dot-grid canvas, zoom (buttons, pinch, 35–250 %), Fit, Center, drag-to-pan, hover highlight of a node's edges, double-click / context menu "Show in {Section}", "Open in New Window", "Focus Here"; animated recentre (nodes glide, edges interpolate); a colour key in a footer bar under the canvas (never over a node; hidden with no graph — FIX2); no scroll indicators on the canvas (rule 17: no legacy corner square; it pans by drag, wheel / trackpad, Fit and Center). |
| ⌥⌘F | Board Find, Planner Search jobs..., Map Inspect search are published through `SectionCommands.focusSearchField` (REQ-W-PLAN-02). |
| VIEW-001 / 083 / 140 / 170 | The 6-wide GridSplitter is `CalSplitView` (resizable, width not persisted, double-click restores the default). Default leading widths: Calendar 232 (Windows 320; the graphical month picker needs ~160; in a narrow pane the selected day moves under the Today button), Planner 256, Buckets 340, Map 260. |
| VIEW-011 | Calendar column widths come from `CalColumnWidths` (Windows 56 / 210 / 120 / 420 / 110): Done, When ("yyyy-MM-dd →" per line — a range wraps after the arrow), Status ("In Progress") and Recurrence hug their content (maximum = ideal) and only Task grows with a wider pane, so names no longer wrap beside empty When / Recurrence space (FIX2). Minimums scale with the text size (Task holds a 14-character word, so A+ never breaks words) and never fall below the header text. At the default size the ideals (45 / 124 / 115 / 164 / 88) fit an 1100-pt window; larger text scrolls horizontally. Rows have no zebra stripes (hairline separators, V-DESIGN rule 5); the Task name is regular weight (V-DESIGN rule 2; Windows semi-bold). |
| VIEW-004 / 017 | Page header controls (Text: A- / A+, the five view-mode segments, Board Find / Hide done / buttons) sit beside the title when they fit; otherwise they flow onto their own lines under it (`CalFlowLayout`), and in a very narrow Calendar pane the five segments become a pop-up with the same five choices and tooltips. Nothing is clipped. |
| VIEW-012 | Status column shows the friendly labels "To Do", "In Progress", "Blocked", "Done" (Windows: enum names `Todo`, `InProgress`, …) and Recurrence the friendly label (same words) — DECISIONS 04 Q-G / 08 OQ-10 outrank VIEW-012. Steps / crew items keep "Step" / "Done". Stored integers unchanged. |
| VIEW-017 | A- / A+ are enabled whenever a click would change the size (`CalFontScale.canStep`), so a stored 10 or 30 (C18) steps back into 11…28 with the buttons as well as ⌘− / ⌘+. |
| VIEW-043 | Board card meta: the dates, then a red "OVERDUE" status chip (⚠ symbol), then the recurrence with a repeat symbol; each part wraps as a unit, so OVERDUE never lands alone behind a dangling "·". The exact Windows string (`"Due …  ·  OVERDUE   ·   Weekly"`) is the meta line's tooltip and VoiceOver label. |
| VIEW-052 | Single-card "Delete task" (context menu, ⌘⌫ with one card) flushes open editors after the confirmation, re-resolves and trashes the task, saves, closes its detached item window and drops it from `detachedItemIDs` — the same steps as the multi-card batch path (`BatchActions.confirmAndTrash`); the "Confirm" / "Delete task '{name}'?" text is unchanged. |
| VIEW-141 | Buckets header: title with the bucket count, then one icon bar — `plus` ("+ New bucket"), `trash` ("Delete"), and a trailing `ellipsis.circle` menu with "Rename" and "Set category..." (tooltip kept) — instead of the Windows wrap panel of text buttons (V-DESIGN rule 4). Bucket names regular weight (Windows semi-bold); members list without zebra stripes. |
| VIEW-084 | Pool row: the `{JobName}` part wraps to two lines before it truncates; the `   ·   {DurFmt}` part never truncates and sits trailing (same string, tooltip shows it whole). |
| VIEW-170 | Map Inspect rows: `"[{Kind}] {Name}"` wraps to two lines, then truncates in the middle (string intact, tooltip shows it whole). |
| ⌘+ / ⌘− | Calendar text size through `SectionCommands.calendarFontScale` / `setCalendarFontScale` (SHELL-605/606, T-KB-26/27); ⌘← / ⇧⌘T / ⌘→ through the planner closures (SHELL-632…634). |
| VIEW-089 | All-day strip: a day whose chips do not all fit the 108-pt cap shows a "+N more" row (N = chips cut or hidden, measured); clicking it expands the strip up to 324 pt, and "Show less" restores 108 (Windows: a scroll bar only; the Mac's overlay scrollers gave no cue). The per-day stacks scroll without indicators (the row is the cue). The expansion resets when the range changes (FIX2). |
| VIEW-090 / 098 | Chip text uses the brand mono (11, rule 1). The ghost opacity (0.6 all-day / 0.55 month) fades the fill only; a ghost chip's label is the foreground colour (white on the faded fill fell under 3:1, rule 13), a full chip keeps white (FIX2). |
| VIEW-041 | Board column card lists show no scroll indicators: with "Show scroll bars: Always" the legacy scroller added a ~16-pt gutter on the right of every column (padding 6 on all sides now holds). The lists scroll with wheel / trackpad; the header count and the cut-off last card show more cards follow (FIX2). |
| VIEW-141 | Buckets icon bar: `plus` / `trash` use the accessory-bar style and the overflow `ellipsis.circle` is `.secondary`-tinted, so every icon in the bar is grey (rule 4; they were accent blue — FIX2). |
