# 08 — Quick & Floating Windows (porting spec)

Feature-ID prefix: **`QUICK-`**
Subsystem: the seven secondary windows that sit around the main window —

| # | WPF window | Purpose (one line) |
|---|---|---|
| A | `Views/FloatingTasksWindow` | Always-on-top "📌 Due dates" popup: OVERDUE / TODAY / TOMORROW / NEXT 7 DAYS across tasks, subtasks, procedures, checklist steps, crew checklist items and scheduled Planner jobs; tick items done from the window. |
| B | `Views/QuickWorkWindow` | Ctrl+N power window: every task & procedure on the left (grouped by bucket, done sinks), a comprehensive builder on the right, pinned "square" tiles on top. |
| C | `Views/QuickSwitcherWindow` | Ctrl+O Obsidian-style fuzzy "Go to item". |
| D | `Views/SearchWindow` (+ `Services/SearchService`) | Ctrl+F global full-text search with highlighted snippets. |
| E | `Views/ActivityLogWindow` | Viewer / filter / CSV export / clear for the UTC activity log. |
| F | `Views/TrashWindow` | Restore / permanently delete / empty soft-deleted items. |
| G | `Views/DiffWindow` (+ `Services/DataDiff`) | "Review changes before importing" deep drill-down tree shown before any import overwrites data. |

Sources read completely: all 14 files above (`.xaml` + `.xaml.cs`), `Services/SearchService.cs`, `Services/DataDiff.cs`,
`Services/AppRepository.cs`, `Services/BatchDone.cs`, `Services/BatchDeadline.cs`, `Services/WorkRange.cs`,
`Services/ItemLockService.cs`, `Services/ChecklistTemplateService.cs`, `Services/ReminderService.cs`,
`Views/BatchDoneMenu.cs`, `Views/BatchDeadlineMenu.cs`, `Views/UiTree.cs`, `Views/PromptWindow.*`,
`Views/DatePromptWindow.*`, `Views/ItemPickerWindow.*`, `Views/Converters.cs`, `Models/Models.cs`,
`Models/CrewMember.cs` (relevant parts), `MainWindow.xaml` + the relevant parts of `MainWindow.xaml.cs`, `App.xaml`,
`Services/ThemeManager.cs`, `Services/DataStore.cs` (JSON options, `PeekZipData`), `FlashSync/FlashChangeSet.cs`
(Ui split), `QR_SYNC_PROTOCOL.md` (Log/Trash/Ui rules) and every PROGRESS.md section listed in §9.

Conventions used below:
* "file:line" references are relative to `/Users/eriskay/erisdev/AA/AA/`.
* Exact user-visible strings are in `code quotes`; `·` is U+00B7 MIDDLE DOT, `—` is U+2014 EM DASH, `…` is U+2026,
  `›` is U+203A, `→` is U+2192. Double spaces inside strings are significant and intentional.
* "Save" = `AppRepository.Save()` (synchronous, immediate write, throws on failure, fires `Saved`).
  "MarkDirty" = debounced save 750 ms after the last call. "Flush" = `FlushIfDirty()` (Save only if dirty).
* Ctrl+X shortcuts map to Cmd+X on the Mac unless stated otherwise (§6.1).

---------------------------------------------------------------------------------------------------------------------

## 1. Overview

### 1.1 Where each window sits

| Window | How it opens (Windows) | Modality / instancing | Owner | Default size |
|---|---|---|---|---|
| A Floating due dates | Header button `📌 Due`; Tools ▸ `Floating _due-dates window`; **Ctrl+R** (`NavigationCommands.Refresh`); tray balloon click; once-a-day digest at startup | Modeless, **single instance** (re-open = `Activate()` + `Refresh()`) | MainWindow | 350 × 480 (min 260 × 220), persisted |
| B Quick work | **Ctrl+N** (`ApplicationCommands.New`); Tools ▸ `Quick _work window (Ctrl+N)` | Modeless, **single instance** (re-open = `Activate()`) | MainWindow | 1200 × 800, centered on owner |
| C Quick switcher | **Ctrl+O** (`ApplicationCommands.Open`); Tools ▸ `Quick s_witcher (Ctrl+O)`; header button `Go to (Ctrl+O)` | **Modal** (`ShowDialog`), new each time, `ShowInTaskbar=False` | MainWindow | 620 × 480, centered on owner |
| D Search | **Ctrl+F** (`ApplicationCommands.Find`); header button `Search (Ctrl+F)` (no menu item) | Modeless, **a NEW window every time** (several may coexist) | MainWindow | 900 × 640, centered on owner |
| E Activity log | Tools ▸ `_Activity log...` | Modeless, **a NEW window every time** | MainWindow | 860 × 620, centered on owner |
| F Trash | File ▸ `_Trash (restore deleted items)...` | **Modal** (`ShowDialog`) | MainWindow | 680 × 480, centered on owner |
| G Diff / import review | Automatically, from every import path (§2.7) | **Modal**, returns true (Import) / false (Cancel/close) | MainWindow | 760 × 580, centered on owner |

Menu tooltips (quote exactly if the Mac shows help tags):
* Tools ▸ Floating due-dates window — `Show a small always-on-top window of items due today and tomorrow.`
* Header `📌 Due` — `Show a small floating window of tasks and procedures due today and tomorrow. (Ship work-order notifications live in each vessel's Work Orders tab.)`
* Tools ▸ Quick work — `Big window: all tasks & procedures on the left (active first), a comprehensive builder on the right.`
* Tools ▸ Quick switcher — `Fuzzy-jump to any item by name, kind or #tag — Obsidian-style. Type, then Enter.`
* Header `Go to (Ctrl+O)` — `Quick switcher — fuzzy-jump to any item by name, kind or #tag.`
* Tools ▸ Activity log — `UTC-timestamped log of every entry added and removed.`
* File ▸ Trash — `Restore items you deleted, or remove them for good. Deletes go here instead of vanishing — Ctrl+Z undoes the last one.`

Shortcut-bar strip at the bottom of the main window (hideable, `UiState.ShowShortcutBar`) advertises:
`Ctrl+S Save · Ctrl+F Search · Ctrl+N Quick work · Ctrl+O Go to (quick switcher) · Ctrl+R Due-dates window · Ctrl+1…9 Switch tab · F2 Rename · Ctrl+Z Undo delete`
(each key bold, separated by `   ·   `). The Mac strip must show the Cmd equivalents (§6.1).

### 1.2 Data flow in one paragraph
All seven windows read/write the single in-memory `AppData` owned by `AppRepository` (`_repo.Data`). None hold private
copies of model data except: Search (hit list snapshot), Activity log (row snapshot), Quick switcher (row snapshot),
Diff (a pre-computed `DataDiff.Result`). The floating window subscribes to `AppRepository.Saved` and rebuilds after every
successful save; the quick-work window does **not** subscribe (it refreshes only after its own actions). After any data
reload/import (`InitPagesAndRestoreUi`, MainWindow.xaml.cs:1216-1217) the main window re-points the two long-lived
windows (`_floating?.SetRepo(_repo)`, `_quickWork?.SetRepo(_repo)`), because a reload replaces every model object.
Navigation out of these windows always goes through two MainWindow callbacks: `NavigateToItem(HierarchyItem)` and
`NavigateToCrew(CrewMember)` (§2.8).

---------------------------------------------------------------------------------------------------------------------

## 2. FEATURE CHECKLIST

### 2.1 Floating due-dates window (A) — `Views/FloatingTasksWindow.xaml(.cs)`

**QUICK-001 Single instance, open/re-open.** `MainWindow.OpenDueDatesWindow` (MainWindow.xaml.cs:915): if a window
already exists → `Activate()` then `Refresh()`; else create `new FloatingTasksWindow(_repo, NavigateToItem, NavigateToCrew) { Owner = this }`,
clear the field on `Closed`, `Show()`. Entry points: `📌 Due` header button, Tools menu item, Ctrl+R, tray balloon
click (`_tray.BalloonTipClicked`, MainWindow.xaml.cs:1598), and the daily digest (`ShowDailyDigestIfDue`,
MainWindow.xaml.cs:1624 — once per local calendar day per PC, `Ui.LastDigestDate = yyyy-MM-dd`, opens the window only if
`ReminderService.Compute` finds anything overdue/due today/due within 7 days, or crew contracts expiring).

**QUICK-002 Window chrome.** Title (not visible, used by OS): `Overdue, today & tomorrow`. Borderless
(`WindowStyle=None`, `AllowsTransparency=True`, transparent background), **always on top** (`Topmost=True`, i.e. above
every app's normal windows, not just AA's), **not in the taskbar** (`ShowInTaskbar=False`), resizable. Content is a
`Border` with `CornerRadius=12`, background theme `Panel`, 1 px `BorderB` border, drop shadow (blur 18, depth 3,
opacity 0.35, black).

**QUICK-003 Header.** Top band with a diagonal linear gradient `#3A7BD5` (0,0) → `#00A88E` (1,1), top corners radius 12,
padding 14/12. Left: title `📌  Due dates` (two spaces; white, bold, 17 pt) and a subtitle (`HeaderSub`, colour
`#EAF6FF`, 11 pt; initial text `Today & tomorrow`, replaced on every refresh — QUICK-011). Right: two borderless white
glyph buttons 26×26: `⟳` (15 pt, tooltip `Refresh`) and `✕` (14 pt, tooltip `Close`). Pressing the left mouse button
anywhere on the header band drags the window (`DragMove`). Only the header drags; the body does not.

**QUICK-004 Size: default, minimum, restore.** Default 350 × 480; minimum 260 × 220. On `Loaded`: if
`Ui.DueWindowWidth ≥ MinWidth` use it; if `Ui.DueWindowHeight ≥ MinHeight` use it (values below the minimum are
ignored, not clamped).

**QUICK-005 Initial position.** On every `Loaded` (i.e. every time the window is created — position is NOT persisted):
`Left = WorkArea.Right − Width − 16`, `Top = WorkArea.Bottom − Height − 16` (bottom-right corner of the primary
screen's work area, 16 px inset).

**QUICK-006 Resize grip + persistence.** An explicit 18×18 grip at the bottom-right (margin 0,0,2,2), cursor
diagonal-resize (NW–SE), tooltip `Drag to resize`, drawn as three diagonal strokes (`M16,4 L4,16  M16,9 L9,16
M16,14 L14,16`, stroke theme `Muted`, 1.5 px). Every drag delta: `Width = max(MinWidth, Width + dx)`,
`Height = max(MinHeight, Height + dy)`, then `Ui.DueWindowWidth = Width`, `Ui.DueWindowHeight = Height`, `MarkDirty()`.
(Persisting *during* the drag is deliberate — PROGRESS "Adversarial review (9 agents) → 3 fixes" #3: writing only on close
missed the debounce if the app shut down.) The OS window edges also resize (ResizeMode=CanResize) but only the grip
persists the size.

**QUICK-007 Live refresh.** `Refresh()` runs: on `Loaded`; on `⟳`; after every `AppRepository.Saved` event **only while
the window is visible** (`OnDataSaved`); in `SetRepo` (only if already loaded); when re-opened (QUICK-001); after a
row's done checkbox (QUICK-022, deferred). "Today" is evaluated at refresh time (`DateTime.Today`, local) — there is no
midnight timer; a window left open across midnight shows yesterday's view until the next save/refresh.

**QUICK-008 Sections and order.** The scrollable body (vertical auto scrollbar, 12 px margin) lists, in order:
1. `OVERDUE` — only when it has ≥ 1 item.
2. `TODAY` — always.
3. `TOMORROW` — always.
4. `NEXT 7 DAYS` — only when it has ≥ 1 item (covers today+2 … today+7 inclusive).

Section header text: `{LABEL}   ({count})` (three spaces), bold 12 pt, colour `#E05252` for OVERDUE, `Muted` otherwise;
margin: left 2, bottom 6, top 0 for the very first element in the body and 14 otherwise. An empty TODAY/TOMORROW shows
the line `— nothing —` (muted, 11 pt, left margin 6).

**QUICK-009 Global empty state.** When all four lists are empty, after the (empty) TODAY and TOMORROW sections the body
appends a centered, wrapped, muted line with top margin 24: `Nothing overdue, or due in the next 7 days 🎉`.

**QUICK-010 Row layout.** Each item is a card: background theme `PanelAlt`, **left border 4 px in the row's accent colour**,
corner radius 4, padding 8/6, bottom margin 5, hand cursor if clickable. Contents left→right: a done checkbox (QUICK-022,
top-aligned, margin right 6, tooltip `Mark done`), the icon glyph (15 pt, 24 px wide, centered, coloured with the
accent), then a stack of title (semi-bold, wraps, theme `Fg`) and subtitle (11 pt, wraps, fixed `#8A8A8A`).

| Kind | Icon | Accent (TODAY/TOMORROW/NEXT) |
|---|---|---|
| top-level task | `✓` (U+2713) | amber `#FFB74D` |
| subtask (any depth) | `↳` (U+21B3) | amber `#FFB74D` |
| procedure | `📋` | green `#2E9E5B` |
| procedure checklist step | `☑` (U+2611) | green `#2E9E5B` |
| crew checklist item | `🧑‍✈️` (U+1F9D1 U+200D U+2708 U+FE0F) | purple `#9C6ADE` |
| scheduled Planner job | `🕒` | blue `#4FC3F7` |
| **any row in OVERDUE** | same icons | red `#E05252` |

**QUICK-011 Header subtitle.** After each refresh: `"{n} overdue  ·  "` (only when n > 0) +
`"Today {today:ddd, dd MMM}  ·  Tomorrow {tomorrow:ddd, dd MMM}"`, e.g. `2 overdue  ·  Today Tue, 29 Sep  ·  Tomorrow Wed, 30 Sep`.
`ddd`/`MMM` are culture-abbreviated names (current culture).

**QUICK-012 OVERDUE rules** (`CollectOverdue`, FloatingTasksWindow.xaml.cs:254). Everything whose **deadline** date is
strictly before today and is not done:
* Tasks and subtasks, recursively (depth-first pre-order): `!IsComplete && Deadline.Date < today`. A task still inside its
  working range (deadline ≥ today) is never overdue. A completed parent does NOT hide its incomplete subtasks.
* Procedures: `Status != Done && Deadline.Date < today`; then **each of its steps regardless of the procedure's status**:
  `!Done && Deadline.Date < today`.
* Crew checklist items: `!Done && Deadline.Date < today`.
* Scheduled jobs are NOT considered for overdue (only deadlines).
Subtitle: `"{kind} · {days}d overdue (was due {due:ddd, dd MMM})"` where kind is `Task`, `Subtask · {top-level owner name}`,
`Procedure`, `Checklist step · {procedure name}`, `Crew checklist · {FullName or (unnamed)}`; days =
whole calendar days between due date and today. Sorted oldest deadline first (stable; ties keep collection order:
all tasks, then procedures with their steps, then crew). Dedupe by `Id` within the section.

**QUICK-013 TODAY / TOMORROW — tasks & subtasks** (`CollectTask`, :226). For day D: `!IsComplete && t.CoversDay(D)`.
`CoversDay`: no deadline → false; else range = [RangeStart.Date if RangeStart ≤ Deadline else Deadline.Date … Deadline.Date].
Subtitle `Task` or `Subtask · {TOP-LEVEL owner name}` (owner = the root task, not the immediate parent), and when the
task `HasRange` (RangeStart.Date < Deadline.Date) append `· ends today` if D = deadline day, else `· starts today` if
D = start day, else `· ongoing` (formatted as `Task · ongoing`). Navigation target = top-level owner task.
Recursion continues into subtasks even when the current task is complete or not on D.

**QUICK-014 TODAY / TOMORROW — procedures & steps** (:176-183). Procedure: `Status != Done && Deadline.Date == D` →
title = procedure name, subtitle `Procedure`. Each step (regardless of procedure status): `!Done && Deadline.Date == D` →
title = step title, subtitle `Checklist step · {procedure name}`, navigates to the procedure.

**QUICK-015 Crew checklist items** (:187-201). For every crew member, each checklist step `!Done && Deadline.Date == D` →
title = step title, subtitle `Crew checklist · {FullName}` (FullName = First/Middle/Last joined by single spaces,
skipping blanks; `(unnamed)` if empty). Clicking jumps to the Crew tab and selects that member (`NavigateToCrew`).

**QUICK-016 Scheduled Planner jobs** (:205-219). For every job from `AppRepository.AllJobs()` (IsJob tasks & subtasks
recursively, IsJob procedures, IsJob procedure steps, IsJob crew steps) with `ScheduledStart.Date == D`, not done, and
not already listed for D → icon `🕒`, title = `JobName` (task/procedure Name or step Title), subtitle
`Scheduled {HH:mm}` + ` · {ctx}` where ctx is:
* task (incl. subtask) → `Task job`, navigates to **that task object** (see quirk Q-3 for subtasks),
* procedure → `Procedure job`, navigates to it,
* procedure step → `Step job · {procedure name}`, navigates to the owning procedure,
* crew step → `Crew step job · {FullName|(unnamed)}`, click → NavigateToCrew,
* orphan step → `Step job` (not clickable).

**QUICK-017 Dedupe rules.**
* Within one day's collection (`Collect(D)`), a `HashSet<Guid>` ensures each Id appears once; order of precedence is
  tasks → procedures → procedure steps (interleaved per procedure) → crew steps → jobs. Hence an item due AND scheduled on
  the same day shows once, as its deadline row.
* TODAY and TOMORROW are collected independently: a ranged task covering both days (or a job scheduled today with a
  deadline tomorrow) appears in **both** sections.
* NEXT 7 DAYS excludes any model object (by reference identity) already shown in OVERDUE, TODAY or TOMORROW, and shows
  each object once, at the first day in today+2…today+7 where it is collected.

**QUICK-018 NEXT 7 DAYS** (`CollectUpcoming`, :148). Iterate D = today+2 … today+7; for each row of `Collect(D)` not yet
shown, append ` · due {D:ddd, dd MMM}` to its subtitle. Note the range wording from QUICK-013 is relative to D, so a
ranged task starting on Thursday reads `Task · starts today · due Thu, 01 Oct`; a job row reads
`Scheduled 09:00 · Task job · due Fri, 02 Oct` (the "due" date is the collection day even for a schedule).

**QUICK-019 Ship work orders excluded.** Shippalm work-order notifications (Vessel.Jobs) are intentionally never shown here
(they live in each vessel's Work Orders tab with a per-ship switch). Do not add them.

**QUICK-020 Row click → navigate.** Left-button-up anywhere on a clickable row (except on its checkbox or any
descendant of it) calls the row's custom action if set (crew rows) else `NavigateToItem(Nav)`. The floating window stays
open. Rows with neither are not clickable (arrow cursor).

**QUICK-022 Tick done from the window.** Every row carries its completable model (task, procedure, step, crew step, job)
and shows a checkbox, initially unchecked (done items are never listed). Checking it calls `BatchDone.SetDone(item, true)`
(tasks: `IsComplete=true` which also sets `Status=Done`; steps: `Done=true`; procedures: `Status=Done`); if that changed
anything → `MarkDirty()` + `FlushIfDirty()` (immediate save). The list is then rebuilt (deferred with
`Dispatcher.BeginInvoke` so the checkbox isn't destroyed inside its own event; the `Saved` event also triggers a refresh).
The item disappears. Unchecking (only reachable in theory) calls `SetDone(item,false)`, which demotes only a *completed*
item and preserves InProgress/Blocked for procedures. Completing a recurring task/procedure spawns its next occurrence via
MainWindow's `OnRepoSaved → ReconcileRecurrences` (the new occurrence may then appear in the window).

**QUICK-023 Close.** `✕` closes; on `Closed` the window unsubscribes from `Saved`. Because it is owned by MainWindow it is
hidden when the main window is minimized and closed when the main window closes.

**QUICK-024 Re-point after reload.** `SetRepo(repo)`: unsubscribe old `Saved`, subscribe new, refresh if loaded.

**QUICK-025 Dark mode.** The header gradient, row accent colours, the fixed muted grey `#8A8A8A` for subtitles and the
overdue red are theme-independent; card background (`PanelAlt`), outer panel (`Panel`), border (`BorderB`), title text
(`Fg`), section-header grey (`Muted`) and the grip stroke (`Muted`) follow the light/dark theme live.

### 2.2 Quick work window (B) — `Views/QuickWorkWindow.xaml(.cs)`

**QUICK-040 Open / single instance.** `MainWindow.OpenQuickWork` (MainWindow.xaml.cs:293): if open → `Activate()` only (no
refresh); else create with `(_repo, NavigateToItem)`, `Owner = MainWindow`, null the field on `Closed`, `Show()`. Title
`Quick work — all tasks & procedures`, 1200 × 800, centered on owner, app icon.

**QUICK-041 Layout.** Outer 10 px margin. Row 0 (auto height): **Pinned board** (QUICK-060…). Row 1 (fill): three columns —
left panel fixed initial 360 px, an 8 px `GridSplitter` (draggable; not persisted), right detail panel (fill). Each panel
is a bordered (`BorderB`), rounded (4) `Panel`-coloured box with a `PanelAlt` header strip.

**QUICK-042 Left panel header & controls.**
* Header strip text `All tasks & procedures` (bold, 15 pt, `Accent`).
* Row of radio buttons (one group): `All` (default checked), `Tasks`, `Procedures`; then buttons `+ Task`, `+ Procedure`.
* Row of buttons: `🪣 Sort into buckets...` (tooltip `Put the selected task/procedure into up to two predefined buckets. Define buckets in the Buckets tab.`),
  `Remove from buckets` (tooltip `Take the selected task/procedure out of all buckets.`).
* A search box (intended placeholder `Search tasks & procedures...` — stored in `Tag`, never rendered on Windows; the Mac
  SHOULD show it as a real placeholder).
* The list (fill), and a count line at the bottom (muted, wraps, margin 8/6).
Radio changes re-run the list build (guarded by `IsLoaded` so the initial XAML check doesn't double-build). Search box
re-runs on every keystroke (no debounce).

**QUICK-043 Candidate set & search.** Top-level `Data.Tasks` (if All/Tasks) then `Data.Procedures` (if All/Procedures) —
**all** of them including completed/done (PROGRESS "Follow-up (2026-07-08): Ctrl+N shows ALL tasks & procedures").
Subtasks and steps are not listed as rows. Search = `Name` contains the trimmed query, case-insensitive (ordinal ignore
case); an empty query shows all.

**QUICK-044 Row content.** Title = name, or `(unnamed)` when the name is blank/whitespace; bold, wraps, **struck through
when done** (task `IsComplete`, procedure `Status == Done`). Subtitle (muted, 11 pt, wraps) — QUICK-045. Rows have
the global thin bottom separator line, hover background `HoverBg`, selected background `SelBg`/foreground `SelFg`.

**QUICK-045 Row subtitle** (`Subtitle`, :142). Parts joined by `"  ·  "` (two spaces each side):
1. `Task` or `Procedure`;
2. `✓ completed` when done;
3. if a deadline exists, with `days = calendar days from today to deadline`:
   `days < 0` → `due {yyyy-MM-dd} (OVERDUE {−days}d)` (shown even for completed items);
   `days == 0` → `due today`; `days > 0` → `due {yyyy-MM-dd} (in {days}d)`;
4. if the item has direct children: `{n} subtask(s)` (tasks) or `{n} step(s)` (procedures) — the literal `(s)` is always printed.
Example: `Task  ·  ✓ completed  ·  due 2026-09-25 (OVERDUE 4d)  ·  3 subtask(s)`.

**QUICK-046 Grouping by bucket.** When at least one bucket is defined (`Data.QuickBuckets.Count > 0`) the list is grouped.
Each item yields **one row per distinct valid bucket it belongs to** (max two by design; ids that no longer resolve to a
bucket are ignored; a duplicated id on one item is collapsed). An item in no (valid) bucket yields one row in the
`(No bucket)` group. Groups are keyed by **bucket Id** (never name — two buckets sharing a name stay separate).
Group header: a `PanelAlt` strip (padding 6/3, margin top 4 bottom 2) reading `🪣 ` + bucket display name + ` ({rowCount})`
(icon and name in `Accent`, name bold, count muted). Display name = bucket `Name`, or `(unnamed bucket)` if empty, or
`(No bucket)`. With no buckets defined: a flat, ungrouped list.

**QUICK-047 Sort order.** When grouped: group by bucket name lower-cased ascending (culture-aware), then bucket Id string
ascending (tie-break for same-named buckets), with `(No bucket)` always **last**. Within a group (and for the flat list):
active before done → deadline ascending (no deadline sorts after every dated item) → title ascending (culture-aware).

**QUICK-048 Count line.** Counts distinct items after filter+search (not rows): if any done →
`{n} item(s) — {active} active, {done} completed/done.` else `{n} item(s).`

**QUICK-049 Selection model.** Extended multi-select (Shift/Ctrl-click). The "current item" (`_selected`) is the list's
primary selected row's item; changing it rebuilds the detail pane (QUICK-070). Right-click first selects the clicked
row — unless it is already part of the selection, in which case the whole selection is kept (so the context menu acts on
what was clicked; `BatchDoneMenu.RightClickSelect`). Every list rebuild restores the previous selection: the same item in
the **same bucket group** if still present, else any row of that item, else nothing (but `_selected` keeps pointing at the
item, e.g. a just-created task hidden by the current filter still shows in the detail pane). Rebuilds never rebuild the
detail pane (so an edit in progress keeps focus).

**QUICK-050 Left-list context menu.** Items in order:
`✓ Mark selected as done` · `○ Mark selected as not done` · `📅 Set deadline for selected…` (tooltip
`Give every selected item the same deadline (or clear it).`) · separator · `🪣 Sort into buckets...` · `Remove from buckets`.

**QUICK-051 Mark selected done / not done.** Applies `BatchDone.SetDoneAll` to every selected row's item (an item selected
under two groups is simply processed twice; the second is a no-op). If anything changed → MarkDirty + Flush. Rebuild the
list (done rows strike through and sink). The detail pane is not rebuilt (its Status combo may be stale until reselect —
the Mac may update it live).

**QUICK-052 Set deadline for selected.** No selection → info box title `Set deadline`, text
`Select one or more items first, then set the deadline.` Otherwise open the date prompt (QUICK-230) titled `Set deadline`
with prompt `Apply one deadline to {n} selected item` + (`s` when n ≠ 1) + `:`, pre-filled with the common deadline if all
selected items share exactly one value (including "all have none" → empty). OK → `BatchDeadline.SetDeadlineAll(items, date)`
(date or null = clear; tasks keep their working range valid — §3.8). If n changed > 0 → MarkDirty + Flush. Then re-seed the
detail pane's date pickers from the model (`SyncDetailDates`) and rebuild the list.

**QUICK-053 Sort into buckets (top-level item).** Acts on `_selected` only (the detail item), not the whole multi-selection.
Nothing selected → info `Select a task or procedure first, then sort it into buckets.` title `Sort into buckets`.
Else run the bucket picker (QUICK-231) with label = name or `this item`. If the assignment changed → rebuild the list.

**QUICK-054 Remove from buckets.** Acts on `_selected`; silently does nothing when none. Clears `BucketIds`, **Save**,
rebuild. No confirmation.

**QUICK-055 + Task / + Procedure.** Prompt titled `New Task` / `New Procedure`, label `Name:`. Cancel or blank → nothing.
Otherwise create with the **raw** entered name (not trimmed), append to the end of `Data.Tasks` / `Data.Procedures`,
log `Added` / `Task`|`Procedure` / name, **Save**, then select it (rebuild list + rebuild detail).

**QUICK-060 Pinned board.** A `Panel` box with a `PanelAlt` header strip containing `📌 Pinned` (bold, `Accent`) and — only
when there are no live pins — the hint (muted, 11 pt, single line with ellipsis):
`Select a task or procedure below and click “📌 Pin” to keep it here as a square. Marking a square done (or editing it) applies everywhere.`
Below: a wrapping flow of tiles inside a vertical scroller capped at **240 px** height, 8 px padding.

**QUICK-061 Pin storage & pruning.** Pins are `Ui.QuickViewPinIds` (ordered list of Guids; toggling appends/removes).
On every pinned-board rebuild each id is resolved with `FindById` (top-level items); ids that do not resolve to a
TaskItem or Procedure are **removed** from the list and `MarkDirty()` is called (deleted items drop off automatically).
The board rebuilds at the end of every left-list rebuild. Tile order: active before done, then name ascending
(ordinal, case-insensitive). Pins ignore the left list's filter/search.

**QUICK-062 Tile.** 172 px wide, min height 156 (grows with a wrapped name — never clipped), margin right/bottom 8,
corner radius 8, padding 9, hand cursor, tooltip `Click to edit. Tick “Done” to mark it complete everywhere.`
Background `Panel` (active) or `PanelAlt` (done); opacity 1.0 or 0.72 (done). Border: 2 px `Accent` when it is the current
item, else 1 px `BorderB`. Rows:
1. Header: `✓ Task` or `📋 Procedure` (11 pt, muted) on the left; on the right a borderless `📌` button (12 pt), tooltip
   `Unpin (remove this square). The task/procedure itself is kept.` → toggles the pin off (QUICK-064).
2. Name: bold, wraps, top/bottom margin 4, `(unnamed)` if empty, **strikethrough when done**.
3. Progress: when the item has direct children (task: `Subtasks`, procedure: `Steps`): text
   `{done}/{total} subtask done` / `…subtasks done` / `…step done` / `…steps done` (plural when total ≠ 1; e.g.
   `1/3 subtasks done`, `0/1 step done`) in 11 pt muted, then a 5 px progress bar (track `PanelAlt` with 0.6 px `BorderB`
   border, radius 3; fill `Accent`, width = track width × done/total, updated on resize). Without children: `completed`
   (done) or `no items yet` (11 pt muted).
4. Footer (top margin 6): right-docked checkbox `Done` (checked = item done); left, if a deadline exists: `OVERDUE {MM-dd}`
   in red `#D45050` when (deadline < today AND not done) else `due {MM-dd}` muted (e.g. `due 09-29`).
Clicking anywhere on the tile that is not a button/checkbox selects the item (list selection + detail).
Ticking `Done` → task `IsComplete = checked` (status syncs), procedure `Status = checked ? Done : Todo`; MarkDirty +
**Save**; rebuild list (+ board); rebuild detail if it is the current item.

**QUICK-064 Pin / Unpin toggle.** From the tile's `📌` or the detail pane's pin button: remove the id if present else append;
MarkDirty + **Save**; rebuild board; rebuild detail if the toggled item is the current one (updates the button label).

**QUICK-070 Detail pane — empty state.** Centered, muted, wrapped, top margin 20:
`Select a task or procedure on the left (or create one) to build it out here.` (scroll viewer, 14 px padding).

**QUICK-071 Detail title row.** Left: `Task` or `Procedure` (20 pt bold `Accent`). Right, visually left→right:
`📌 Pin` / `📌 Unpin` (bold; tooltip `Pin this as a square in the board above.` / `Remove this from the pinned squares above.`),
`🗑 Delete`, `Open in main window ↗`. Bottom margin 10.

**QUICK-072 Open in main window.** Calls `NavigateToItem(current item)`. The quick-work window stays open (and, being an
owned window, stays above the main window on Windows).

**QUICK-073 Delete (HARD delete, no Trash).** Confirm (Yes/No, warning) title `Delete`, text
`Delete '{name}' and everything under it? This removes it everywhere.` On Yes: log `Removed` / `Task`|`Procedure` / name
(no detail); remove from its collection; `PurgeReferences(id)` (scrub RelatedIds, Equipment ProcedureIds/TaskIds, step
TaskIds/EquipmentIds, every file's LinkedItemIds); remove its pin; clear current item if it was the one; **Save**; rebuild
list and detail. **Not undoable** and not in the Trash (documented as intentional-pending in PROGRESS "Batch delete…
Not yet attached": "the Board and Ctrl+N quick window delete tasks *hard*"). See open question OQ-1.

**QUICK-074 Header fields** (label column 100 px wide; controls 200 px wide left-aligned except Name which fills):
* `Name:` — text box; every keystroke writes `Name` and MarkDirty. The left list title is **not** refreshed per keystroke
  (focus protection); it updates on the next rebuild.
* `Deadline:` — date picker (tooltip `Due date — for a task this is also the LAST day of the working range.`).
  Procedure: sets `Deadline` directly. Task: runs `WorkRange.Coerce(model.RangeStart, picked, editedStart:false)`, writes
  both results to the model and both pickers (guarded against re-entrancy). MarkDirty.
* `Range start:` — **tasks only**; date picker (tooltip
  `Optional first day of the working range. Leave empty for a single-day task; the deadline stays the last day.`);
  runs `WorkRange.Coerce(picked, model.Deadline, editedStart:true)`, writes both. MarkDirty.
  Both pickers coerce against the **model**, never against the sibling control (fixes a stale-sibling data-loss bug —
  PROGRESS "Deadline a whole checklist at once…").
* `Status:` — combo of `Todo`, `InProgress`, `Blocked`, `Done` (raw enum names); sets Status (task: also syncs IsComplete).
  MarkDirty.
* `Recurrence:` — combo of `None`, `Daily`, `Weekly`, `Monthly`, `Yearly`; MarkDirty.
Then a separator (10 px above/below).

**QUICK-075 Children builder — header & bulk add.** Heading `Comprehensive subtask builder` / `Comprehensive step builder`
(bold 14 pt `Accent`). Label `Bulk add — one subtask per line:` / `Bulk add — one step per line:`. A multi-line text box
(96 px tall, no wrap, monospaced Consolas, vertical scrollbar auto). Row: accent button `Add all` + checkbox
`Replace existing`. `Add all`: split on `\n` (after `\r\n`→`\n`), trim each line, drop empty lines; none → nothing; if
`Replace existing` is ticked, **clear the collection first (no confirmation)**; append one child per line
(TaskItem{Name}/ChecklistStep{Title}); clear the text box; log `Added` / `Subtask`|`Step` / `{n} added (bulk)` / owner name;
**Save**; rebuild list. The checkbox state persists until the detail pane is rebuilt.

**QUICK-076 Children list.** 300 px tall, extended multi-select, bound live to the real collection (`Subtasks` / `Steps`),
item text = Name / Title, wraps, **strikethrough when done** (live — bound to `IsComplete`/`Done`). Double-click = `Edit...`.

**QUICK-077 Children buttons** (wrapping row, in this order):
* `+ subtask` / `+ step` — prompt titled `New subtask` / `New step`, label `Name:`; blank/cancel → nothing; append; log
  `Added` / `Subtask`|`Step` / child name / owner name; **Save**; rebuild list.
* `Edit...` — first selected child → modal `SubtaskEditorWindow(child, repo)` / `ChecklistStepEditorWindow(child, repo)`
  (other subsystem); afterwards Flush + rebuild list. No selection → nothing.
* `↑` / `↓` — move all selected children one position (QUICK-078). MarkDirty only.
* `Delete` — selected children; none → nothing; confirm (Yes/No, question) title `Confirm`, text
  `Delete {n} subtask(s)?` / `Delete {n} step(s)?`; log `Removed` / `Subtask`|`Step` / `{n} removed` / owner name; remove
  (hard); **Save**; rebuild list.
* `🪣 Buckets...` — first selected child (subtasks and steps are bucketable) → bucket picker (QUICK-231) with label =
  child Name/Title (may be empty → `Sort '' into buckets (pick up to 2)`); if changed → rebuild list. No selection →
  info `Select a subtask first, then sort it into buckets.` / `Select a step first, …` title `Sort into buckets`.
* `Open full builder...` — modal `SubtaskBuilderWindow(task, repo)` / `ChecklistBuilderWindow(procedure, repo)`; then rebuild list.
* `💾 Save as list...` — QUICK-080.
* `📋 Load a saved list...` — QUICK-081, then rebuild list.

**QUICK-078 Reorder semantics** (`Move`, :831). Collect selected indices ascending. Up: if the first selected index is 0,
do nothing at all; else move each selected index i → i−1 in ascending order. Down: if the last selected index is the last
position, do nothing; else move each i → i+1 in descending order. Non-contiguous selections move as individual items
(gaps preserved). MarkDirty.

**QUICK-079 Children context menu.** `✓ Mark selected as done`, `○ Mark selected as not done`, separator,
`📅 Set deadline for selected…` (same tooltip as QUICK-050). Same right-click selection rule as QUICK-049. Done/not done
→ `BatchDone`; deadline → `BatchDeadlineMenu` flow (same messages/prompt as QUICK-052, the "no selection" message box is
owned by this window); each: if changed → MarkDirty + Flush; then rebuild list (the list itself is live-bound). Marking all
subtasks done does NOT complete the parent.

**QUICK-080 Save as reusable list.** Collection empty → info title `Save list`, text `Add some items first, then save the list.`
Else prompt titled `Save as reusable list`, label `Name for this saved list:`, pre-filled with the owner's name; cancel or
blank → nothing; name is trimmed. Capture (`ChecklistTemplateService.CaptureFromSubtasks/CaptureFromSteps`: Title,
DurationMinutes, IsJob, deep-cloned Container — no deadlines/done), append to `Data.ChecklistTemplates`, log `Added` /
`Saved list` / name / `{n} item(s)`, **Save**, info title `Saved list`, text
`Saved '{name}' ({n} item(s)). You can reuse it from any checklist builder.`

**QUICK-081 Load a saved list.** None saved → info title `Load a saved list`, text
`No saved lists yet. Build a list and click 'Save as list...' to create one.` Else single-select picker titled
`Insert a saved list`, rows = templates in **collection order** (that order *is* the user's arrangement from the Saved
Lists tab), display `{name or (unnamed)}  ·  {n} item` + `s` when n ≠ 1. Then a Yes/No/Cancel question titled
`Insert a saved list`: `Insert '{name}' ({n} item(s)).\n\nYes = replace the current items\nNo = append to the end\nCancel = do nothing`.
Yes → replace (clear then add), No → append. Log `Added` / `Subtask` (tasks) or `Checklist step` (procedures) /
`{n} added (from saved list '{name}')` / owner name. MarkDirty (not Save). Rebuild list.

**QUICK-082 Flush on close.** Window `Closing` → `FlushIfDirty()`.

**QUICK-083 Re-point after reload.** `SetRepo(repo)`: remember the current item's Id, swap repo, re-resolve the item with
`FindById` (null if gone), rebuild list and detail.

**QUICK-084 Dark mode.** Everything uses theme keys (`Panel`, `PanelAlt`, `BorderB`, `Accent`, `Muted`, `Fg`, `HoverBg`,
`SelBg`, `SelFg`) except the tile overdue red `#D45050`.

### 2.3 Quick switcher (C) — `Views/QuickSwitcherWindow.xaml(.cs)`

**QUICK-100 Open.** `new QuickSwitcherWindow(_repo, NavigateToItem) { Owner = this }.ShowDialog()` (modal). Title
`Go to item`, 620 × 480, centered on owner, not in taskbar, 10 px margin.

**QUICK-101 Layout.** Top: search box, 16 pt, padding 6/4, focused on load (advertised placeholder
`Type a name, kind or #tag...` — not rendered on Windows; the Mac SHOULD render it). Bottom: hint (11 pt, 60 % opacity)
`Enter to open  ·  ↑ / ↓ to move  ·  Esc to close`. Middle: virtualized list (8 px top margin).

**QUICK-102 Row.** Left: a kind chip — rounded (3) `PanelAlt` background, padding 6/1, text = `KindLabel` (`Equipment/Area`,
`Task`, `Procedure`, `Vessel`) 11 pt in `Accent`. Right: tags `#a  #b` (each prefixed `#`, joined by two spaces; empty
when no tags) at 60 % opacity, 11 pt. Middle: item name, semi-bold, single line with ellipsis (no `(unnamed)` fallback).

**QUICK-103 Candidates.** `AppRepository.AllItems()` = top-level Equipment, then Tasks, then Procedures, then Vessels.
No subtasks, steps, components, crew or saved lists. Password-locked items are included (name/tags/description all used
for ranking; nothing protected is displayed).

**QUICK-104 Query normalization.** `q = text.Trim().TrimStart('#')` — strips **all** leading `#` (tags are stored without
`#`). Note `# pump` → ` pump` (the space after the hash is kept).

**QUICK-105 Scoring & ranking** (§3.3.1). Empty q → every item scores 1. Otherwise keep items with score > 0. Order by
score descending, then name ascending (ordinal ignore-case). Keep the first **80**. Re-ranked on every keystroke. The first
row is selected after every refresh (when any).

**QUICK-106 Keyboard (in the search box).** `↓` next row, `↑` previous row (clamped at both ends, never wraps; if nothing
selected, either key selects row 0), scroll into view; `Enter` opens the selected row; `Esc` closes. All four are
consumed. Double-click on a row opens it.

**QUICK-107 Open.** Close the switcher first, **then** `NavigateToItem(item)` (main window switches tab and selects it).

### 2.4 Global search (D) — `Views/SearchWindow.xaml(.cs)`, `Services/SearchService.cs`

**QUICK-120 Open.** `new SearchWindow(_repo, NavigateToItem) { Owner = this }.Show()` — a new window each time. Title
`Search`, 900 × 640, centered on owner, 10 px margin. Query box focused on load.

**QUICK-121 Query bar.** Label `Search:` (60 px), text box (fill), button `Search` (min width 80, default button).
Search runs only on `Search` click or `Enter` — **not** as-you-type.

**QUICK-122 Run.** Trim the query; empty → clear the results and the status text, stop. Otherwise cancel any previous
run's token, set status `Searching…`, disable the button, snapshot the Ids of top-level items that are password-locked and
not unlocked this session (`ItemLockService.IsGated` over Equipment, Tasks, Procedures, Vessels — on the UI thread), run
`SearchService.Search(data, query, 500, lockedIds)` on a background thread, and if not superseded, show the rows and set
status `No results for "{query}".` or `{n} result for "{query}".` / `{n} results for "{query}".` (the displayed query is
the trimmed one). The button is re-enabled when that run finishes.

**QUICK-123 What is searched** (in this order — which is also result order) for each top-level item (Equipment → Tasks →
Procedures → Vessels):
1. `Name`; 2. `Tags` (joined `, `); — **if the item is locked, stop here for this item** —
3. `Description`; 4. `Notes` (plain text of `Container.RichTextXaml`); 5. for each file in the item's container: file name
(`File › {Kind}`) then file path (`File › {Kind} › Path`), Kind = `Document`/`Image`/`Video`/`Link`/`Other`;
6. kind-specific: Equipment components (per component: `Component › Name`, `Component › Notes`,
`Component › Container`, then per file `Component › File`); Task subtasks recursively depth-first (per subtask:
`Subtask › Name`, `Subtask › Description`, `Subtask › Container`, per file `Subtask › File`, then its own subtasks);
Procedure steps (per step: `Step › Title`, `Step › Container`, per file `Step › File`). Vessels have nothing extra
(QuickCards, work orders, port calls are not searched). Crew, saved lists, SIRE, ports, buckets, log and trash are not
searched.
Matching: case-insensitive ordinal `IndexOf` of the trimmed query; **one hit per field** (first occurrence only).
Stops once 500 hits are collected.

**QUICK-124 Results table.** Two columns: `Where` (230 px): line 1 bold `[{Kind}] {owner name}` where Kind is the raw enum
name (`Equipment`, `Task`, `Procedure`, `Vessel` — *not* "Equipment/Area"); line 2 the `Where` label (11 pt, 70 % opacity).
`Match` (600 px): the snippet on one line with ellipsis trimming; the matched span has background `#FFE066`, black text,
bold. Virtualized list.

**QUICK-125 Activate.** Double-click a row, or `Enter` with the list focused → `NavigateToItem(owner)` (the top-level
item — never the specific subtask/step/component). The search window stays open.

### 2.5 Activity log (E) — `Views/ActivityLogWindow.xaml(.cs)`

**QUICK-150 Open.** Tools ▸ Activity log → `new ActivityLogWindow(_repo) { Owner = this }.Show()` (new each time). Title
`Activity log`, 860 × 620, centered on owner, 12 px margin.

**QUICK-151 Header.** Left `Activity log` (bold 16 pt `Accent`). Right: filter box 190 px (advertised placeholder
`Filter action / kind / name...`, not rendered on Windows), buttons `Export (.csv)...` and `Clear log`. Below, a muted
wrapped line: `Every entry added or removed is recorded with a UTC timestamp (newest first). Local time is shown alongside for convenience.`

**QUICK-152 Table.** Columns: `Time (UTC)` 170 (`yyyy-MM-dd HH:mm:ss UTC`), `Local time` 150 (`yyyy-MM-dd HH:mm:ss`, local),
`Action` 80, `Kind` 130, `Name` 200 (wraps), `Detail` 200 (wraps, muted). Virtualized. Newest first = **reverse of stored
order** (not a timestamp sort). Not live: rows are a snapshot rebuilt on open and on each filter keystroke.

**QUICK-153 Filter.** Trimmed text; empty → all; else keep entries where Action, Kind, Name **or Detail** contains it
(case-insensitive). Count line (bottom, muted): `{shown} of {total} log entries.`

**QUICK-154 Clear log.** Empty log → nothing. Else confirm (Yes/No, warning) title `Clear activity log`, text
`Clear all {n} activity-log entries? This can't be undone.` → clear, **Save**, refresh. Clearing is not itself logged.

**QUICK-155 Export CSV.** Save dialog title `Export activity log`, filters `CSV file (*.csv)` / `All files (*.*)`, default
name `aa-activity-log-{UTC now:yyyyMMdd-HHmmss}.csv`. Writes **all** entries in **stored (chronological)** order,
ignoring the filter (§4.6 format). Then opens the file with the default app (failures ignored). Write failure → error
box title `Export failed`, text = exception message.

**QUICK-156 What the log contains (producer contract).** `LogEntry{TimestampUtc, Action ("Added"|"Removed"), Kind, Name, Detail}`
appended by `AppRepository.LogAdded/LogRemoved` (AppRepository.cs:230-248): name trimmed, blank → `(unnamed)`, detail null →
`""`; capped at **10 000** entries (oldest removed first); each append calls MarkDirty. Entries produced by this subsystem:
see §4.5.

### 2.6 Trash (F) — `Views/TrashWindow.xaml(.cs)`

**QUICK-170 Open.** File ▸ Trash → `new TrashWindow(_repo) { Owner = this }`, `Restored += RefreshAfterRestore`, `ShowDialog()`.
Title `Trash`, 680 × 480, centered on owner, 12 px margin, window background/foreground follow the theme.

**QUICK-171 Info text** (top, muted, wraps):
`Deleted items are kept here so a mistake can be undone. Restore puts an item (with its whole subtree) back where it was. Items are auto-removed after 90 days, or once there are more than 200.`

**QUICK-172 List.** Bound live to `Data.Trash` (stored order = oldest deletion first; no sort). Extended multi-select.
Columns `Name` 300, `Kind` 160 (`KindLabel`: `Equipment/Area`, `Task`, `Procedure`, `Vessel`, `Crew member`),
`Deleted` 150 (`DeletedUtc` converted to local, `yyyy-MM-dd HH:mm`). No empty-state text.

**QUICK-173 Buttons** (bottom-right): `↩ Restore` (accent; tooltip `Put the selected item(s) back where they were.`),
`Delete permanently` (tooltip `Remove the selected item(s) from the Trash for good (cannot be undone).`),
`Empty Trash` (tooltip `Permanently remove everything in the Trash.`, 18 px gap after it), `Close` (min width 80).

**QUICK-174 Restore.** No selection → nothing. For each selected entry `AppRepository.RestoreTrash` (§3.6.1). If none
restored → warning title `Restore`, text `Couldn't restore the selected item(s).` (partial failures are silent). Else
**Save** and raise `Restored(type)` once per distinct type (`Equipment`/`Task`/`Procedure`/`Vessel`/`Crew`) → MainWindow
reloads the matching page (`RefreshAfterRestore`, MainWindow.xaml.cs:1475; Crew also refreshes the tab badge). The window
stays open; restored entries vanish from the list.

**QUICK-175 Delete permanently.** No selection → nothing. Confirm (Yes/No, warning) title `Delete permanently`, text
`Permanently delete {n} item(s) from the Trash? This cannot be undone.` → `PurgeTrash` each (remove + `PurgeReferences` +
MarkDirty) → **Save**.

**QUICK-176 Empty Trash.** Empty → nothing. Confirm title `Empty Trash`, text
`Permanently remove all {n} item(s) in the Trash? This cannot be undone.` → `EmptyTrash` (purge references for every
entry, clear) → **Save**.

**QUICK-177 Close** button closes. No keyboard shortcut is wired (no Esc handling).

**QUICK-178 Relationship with Ctrl+Z.** Outside this window, Ctrl+Z (when no text box has focus) restores the newest
Trash entry — or the whole batch sharing its non-empty `BatchId` — via `UndoLastDelete` (status bar:
`Restored {n} deleted items (Ctrl+Z).` / `Restored the last deleted item (Ctrl+Z).` / `Nothing to undo.`). Items restored
in the Trash window are therefore no longer undoable by Ctrl+Z (they left the Trash).

### 2.7 Import change preview (G) — `Views/DiffWindow.xaml(.cs)`, `Services/DataDiff.cs`

**QUICK-190 When it appears.** `MainWindow.ReviewAndConfirmImport(incoming, incomingLast, sourceName)`
(MainWindow.xaml.cs:629) is called by every overwrite path:
| Path | sourceName | incomingLast |
|---|---|---|
| File ▸ Import from file (.json) | file name | `data.LastModified` |
| File ▸ Import data folder (ZIP/.aaz) | file name | `PeekZipData(file)?.LastModified` |
| File ▸ Load backup from Google Drive (OAuth) | `Google Drive: {backup name}` | incoming `LastModified` |
| Sync pull of a newer Drive save | `Google Drive (newer save)` | the remote `LastModified` from Drive metadata |
If `incoming` could not be read (null), a plain Yes/No warning replaces the window: title `Confirm import`, text
`Replace your current data with '{sourceName}'?\n(Could not read a change preview for this source.)`.
The shared-save-file auto-pull does **not** use this window.

**QUICK-191 Header.** `Importing from: {sourceName}` (bold 14, wraps); a bordered `PanelAlt` box (radius 4, padding 8/6) with
the age text (QUICK-196); summary line (bold, wraps):
`This import will   ＋ add {A}     ～ change {C}     － remove {R}   item(s).  Expand a row to see details.` (spaces exactly
as shown: 3, 5, 5, 3, 2; glyphs U+FF0B, U+FF5E, U+FF0D) or, when there are no roots,
`No differences detected — the incoming data appears identical to your current data.`; then muted:
`Review what this import will do, then choose Import to overwrite your current data or Cancel to keep it.`
A/C/R count **top-level items only**.

**QUICK-192 Tree.** One row per `DataDiff.Node`: glyph column 20 px (bold, top-aligned) + text (wraps at 640 px).
Glyphs/colours: Added `＋` `#2E7D32`, Removed `－` `#C62828`, Changed `～` `#EF6C00`. **Top-level rows start expanded**;
all deeper rows start collapsed; the user expands/collapses freely.

**QUICK-193 Buttons.** `Cancel` (min 90, **Esc**) → false; `Import (overwrite)` (accent, min 150, **Enter**, enabled even
when there are no differences) → true. Closing the window any other way = false. Caller then imports (smart bundle
import / JSON replace) or reports the cancel.

**QUICK-194 What the diff covers** — see §3.7 for the full algorithm. Summary: items matched by Id across
Equipment/Tasks/Procedures/Vessels; name, description, notes (plain text), files (by Name|Path) for every item; task
deadline / start / recurrence / status and subtasks (recursive); equipment components (+ their name, notes line, notes,
files) and linked procedures/tasks; procedure steps (title, done, notes, files, linked tasks, linked equipment). **Not
covered** (a change there shows "No differences detected"): tags, relationships (`RelatedIds`), groups, buckets, locks,
procedure deadline/status/recurrence, step deadline, job fields (IsJob/Duration/ScheduledStart), vessel quick cards/work
orders/port calls, crew, saved lists, SIRE, ports, schedule templates, trash, log, Ui.

**QUICK-195 Ordering.** Roots: Added, then Changed, then Removed; within each, text ascending ordinal ignore-case.
Children: insertion order (fields first, then files added, files removed, then per child collection: added, removed,
changed, in collection order).

**QUICK-196 Age verdict** (`AgeVerdict`, MainWindow.xaml.cs:645):
```
Incoming saved: {incoming:yyyy-MM-dd HH:mm:ss | (no save date)}
Current saved:  {current:yyyy-MM-dd HH:mm:ss | (no save date)}
{verdict}
```
(note the two spaces after `Current saved:`). Verdicts:
`➜ The incoming data is NEWER than your current data.` / `…is OLDER than…` / `➜ The incoming data is the SAME age as your current data.`
(both dated, compared exactly); `➜ Your current data has no save date; relative age is unknown.` (only incoming dated);
`➜ The incoming data has no save date (older format); it may be older.` (only current dated);
`➜ Neither copy has a save date; relative age is unknown.`

### 2.8 Cross-cutting

**QUICK-210 Navigation contract `NavigateToItem(item)`** (MainWindow.xaml.cs:313): switch the main tab by the item's kind
(Equipment → index 0, Task → 1, Procedure → 2, Vessel → 3), then (deferred, background priority) `page.SelectItemById(item.Id)`
which only finds **top-level** rows. Known defect: uses fixed indices although the user can reorder tabs (`Ui.TabOrder`) —
see Q-2. **`NavigateToCrew(member)`** (:924): select the Crew tab, deferred `CrewPg.SelectMember(m)` which clears the
crew filters/search, rebuilds, selects by `Id` (fallback: by `Key`) and scrolls into view.

**QUICK-211 Shortcuts.** Ctrl+F search, Ctrl+N quick work, Ctrl+O quick switcher, Ctrl+R due-dates window are
**main-window** input bindings (they fire when the main window has focus, even inside a rich-text box). Inside the
windows: Quick switcher ↑/↓/Enter/Esc; Search Enter (query box → search, results list → open); Diff Enter/Esc.
PROGRESS claims `Esc`/`Ctrl+W` close tool windows, but no such handler exists in these files (only the switcher's Esc and
the diff's Cancel=Esc). The Mac gets Cmd+W / Esc naturally (§6.1).

**QUICK-212 Theming.** Light theme is monochrome (white panels, black text/borders/accent); dark: Bg `#1E1E1E`, Panel
`#252526`, PanelAlt `#2D2D30`, Accent `#FFFFFF`, Fg `#F0F0F0`, Muted `#B0B0B0`, Border `#3F3F46`, Hover `#3A3A3D`,
SelBg `#094771`, SelFg `#FFFFFF` (`ThemeManager.Apply`). App font is Consolas 13 pt. Theme switches live.

**QUICK-213 Safe mode.** When the data file was unreadable at startup, `SuspendSaving` makes Save/MarkDirty no-ops, so every
action in these windows mutates memory only and nothing is written; no extra UI in these windows.

**QUICK-214 Save failures.** `Save()` throws on a failed/timed-out write; none of these windows catch it — the global
`DispatcherUnhandledException` handler logs to `crash.log`, shows the error and keeps the app running. The Mac must catch
and present an alert instead (same outcome: app keeps running, data stays dirty for retry).

**QUICK-230 Date prompt** (`DatePromptWindow`, shared). Modal 420 × 200, title/heading as given, prompt text, one date
picker, buttons `Clear deadline` (tooltip `Remove the deadline from every selected item.`) → returns OK with null,
`Cancel`, `OK` (default) → requires a date, else info `Pick a date, or use "Clear deadline" to remove it.` title
`Set deadline`; returns the date part only.

**QUICK-231 Bucket picker flow** (`SortIntoBuckets`, QuickWorkWindow.xaml.cs:468). No buckets defined → info title
`Sort into buckets`, text `No buckets are defined yet. Open the Buckets tab to create some (e.g. a location or a rank).`
→ false. Else multi-select `ItemPickerWindow` (500 × 500, a filter box, `Cancel`/`OK`) with prompt
`Sort '{label}' into buckets (pick up to 2)`, options = all buckets in collection order displayed as
`{Name}  ·  {Category}` (category non-empty) else `{Name}` or `(unnamed)`, pre-selected = buckets already assigned.
Cancel → false. OK with > 2 picked → info `An item can be in at most two buckets — keeping the first two you picked.`
and keep the first two in selection order (pre-selected ones first, in list order, then newly clicked in click order).
Then replace the item's `BucketIds` with the picked ids (0 picked = remove from all; stale ids are dropped), **Save**,
return true.

---------------------------------------------------------------------------------------------------------------------

## 3. LOGIC & ALGORITHMS

### 3.1 FloatingTasksWindow (`Views/FloatingTasksWindow.xaml.cs`)

| Function | Lines | Behaviour |
|---|---|---|
| ctor | 31-39 | store navigate callbacks; `SetRepo`; hook `Loaded`, `Closed`. |
| `OnClosed` | 41-44 | unsubscribe `Saved`. |
| `SetRepo` | 47-53 | swap subscription; `Refresh()` if loaded. |
| `OnDataSaved` | 55-59 | `if (IsVisible) Refresh()`. |
| `OnLoaded` | 61-71 | restore size (≥ min only), position bottom-right (`SystemParameters.WorkArea`, 16 px inset), refresh. |
| `Header_Drag` | 73-76 | left button → `DragMove()`. |
| `ResizeGrip_DragDelta` | 81-93 | clamp to min, persist to `Ui.DueWindowWidth/Height`, `MarkDirty`. |
| `Refresh` | 112-144 | builds the four sections (below). |
| `CollectUpcoming` | 148-162 | today+2..today+7, dedupe by reference against `alreadyShown`, append ` · due {ddd, dd MMM}`. |
| `Collect(day)` | 164-224 | tasks → procedures(+steps) → crew steps → jobs, per-day Guid dedupe. |
| `CollectTask` | 226-250 | recursive; owner = root; range wording. |
| `CollectOverdue` | 254-283 | overdue tasks/procs/steps/crew; `OrderBy(SortDate)` (stable). |
| `CollectOverdueTask` | 285-295 | recursive; `Deadline.Date < today`. |
| `MkOverdue` | 297-312 | `days = (int)(today − due.Date).TotalDays`; sub `"{kind} · {days}d overdue (was due {due:ddd, dd MMM})"`; red accent; `SortDate = due.Date`. |
| `JobDone` | 314-320 | Task→IsComplete, Step→Done, Procedure→Status==Done. |
| `JobNav` | 325-341 | (nav, onClick, ctx) per §2.1 QUICK-016; step owner lookup: first procedure whose `Steps` contains the step (reference), else first crew member whose `Checklist` contains it. |
| `AddSection` | 343-363 | header + rows or `— nothing —`. |
| `BuildRow` | 365-424 | card; checkbox; click handler ignores clicks whose original source is inside a CheckBox (`UiTree.FindAncestor<CheckBox>`). |
| `IsItemDone` | 426-432 | as `JobDone`. |
| `CompleteItem` | 436-441 | `BatchDone.SetDone`; if changed MarkDirty+Flush; `BeginInvoke(Refresh)`. |

`Refresh` pseudo-code (exact):
```
today = local date; tomorrow = today+1
overdue  = CollectOverdue()                         // sorted oldest first
todayL   = Collect(today); tomorrowL = Collect(tomorrow)
shown    = identity-set of .Item over overdue ∪ todayL ∪ tomorrowL
upcoming = CollectUpcoming(today+2, today+7, shown)
HeaderSub = (overdue.count>0 ? "\(overdue.count) overdue  ·  " : "")
          + "Today \(fmt(today))  ·  Tomorrow \(fmt(tomorrow))"          // fmt = "ddd, dd MMM"
if overdue non-empty: section("OVERDUE", overdue)
section("TODAY", todayL); section("TOMORROW", tomorrowL)
if upcoming non-empty: section("NEXT 7 DAYS", upcoming)
if all four empty: append "Nothing overdue, or due in the next 7 days 🎉"
```
Performance: 8 `Collect` passes + 1 overdue pass, each O(tasks+subtasks+procs+steps+crew steps+jobs). Rebuilt on every
save while visible — keep it a pure function over a snapshot (§6.3) and diff the SwiftUI list by stable ids.

Date semantics: every comparison uses `.Date` (drop time of day) of local/unspecified `DateTime` values. `days` is a
wall-clock calendar-day difference (no DST effect in .NET because `DateTime` subtraction on non-UTC values is pure tick
arithmetic). **Swift must compute calendar days with `Calendar.current.dateComponents([.day], from: startOfDay(a), to: startOfDay(b))`,
never `timeInterval / 86400`** (a DST night would otherwise give 0 or 1 day off).

### 3.2 QuickWorkWindow (`Views/QuickWorkWindow.xaml.cs`)

| Function | Lines | Behaviour |
|---|---|---|
| ctor | 33-40 | `RefreshPending()`; `Closing → FlushIfDirty`. |
| `SetRepo` | 44-51 | re-resolve current by Id; rebuild list + detail. |
| `RefreshPending` | 67-140 | build rows, sort/group, restore selection under `_suppress`, count line, `RefreshPinned()`. |
| `Subtitle` | 142-156 | QUICK-045. |
| `Pending_SelectionChanged` | 161-168 | ignored while `_suppress`; set `_selected`, `_selectedBucketKey`; `BuildDetail()`. |
| `List_RightButtonSelect` | 173-176 | `BatchDoneMenu.RightClickSelect`. |
| `SetSelectedDeadline_Click` | 178-199 | QUICK-052. |
| `SyncDetailDates` | 202-209 | re-seed pickers from the model under `_qwDateSync`. |
| `MarkSelected` | 213-219 | QUICK-051. |
| `NewTask_Click` / `NewProc_Click` | 221-241 | QUICK-055. |
| `SelectItem` | 243-248 | set `_selected`; `RefreshPending()`; `BuildDetail()`. |
| `TogglePin` | 254-261 | QUICK-064. |
| `RefreshPinned` | 264-284 | QUICK-061. |
| `BuildTile` | 290-414 | QUICK-062. |
| `ChildProgress` | 416-421 | direct children only: task `(Subtasks.Count(IsComplete), Subtasks.Count)`, procedure `(Steps.Count(Done), Steps.Count)`. |
| `SetItemDone` | 425-433 | tile Done. |
| `DeleteItem` | 439-452 | QUICK-073. |
| `MoveToBucket_Click` | 455-464 | QUICK-053. |
| `SortIntoBuckets` | 468-491 | QUICK-231. |
| `RemoveFromBucket_Click` | 493-499 | QUICK-054. |
| `BuildDetail` | 502-577 | QUICK-070/071/074 + `BuildChildren`. |
| `MakeNameBox` | 587-599 | per-keystroke Name + MarkDirty. |
| `MakeDeadlinePicker` | 601-621 | Coerce(model.RangeStart, picked, false) for tasks. |
| `MakeRangeStartPicker` | 623-638 | Coerce(picked, model.Deadline, true). |
| `MakeStatusCombo` / `MakeRecurrenceCombo` | 640-654 | enum combos. |
| Saved-list helpers | 657-738 | QUICK-080/081. |
| `BuildChildren<T>` | 740-829 | QUICK-075…079. |
| `Move<T>` | 831-846 | QUICK-078. |
| accessors | 853-859 | `IsDone`, `Deadline`, `SetDeadline`, `Status`, `SetStatus`, `Recurrence`, `SetRecurrence` for TaskItem/Procedure. |

`RefreshPending` row building (exact):
```
q = search.trimmed
items = (All|Tasks ? Tasks : []) + (All|Procedures ? Procedures : [])
if q != "": items = items.filter { $0.Name.localizedStandardContains?  NO → ordinal case-insensitive contains }
for i in items:
   title = Name.isBlank ? "(unnamed)" : Name
   dl    = Deadline(i) ?? +∞
   buckets = i.BucketIds.compactMap(bucketById).uniqued(by: id)          // preserve BucketIds order
   if buckets.empty: row(bucket:"(No bucket)", key:"", sort:"\u{FFFF}")
   else for b in buckets: row(bucket: b.Name.isEmpty ? "(unnamed bucket)" : b.Name,
                              key: b.Id.uuidString(lowercase), sort: bucketName.lowercased())
grouped = QuickBuckets.count > 0
sort keys = grouped ? [BucketSort, BucketKey] : [] + [IsDone(false<true), DeadlineSort, Title]
```
WPF sorts strings through `ListCollectionView` with the element's culture (culture-sensitive, case-sensitive tiebreak) and
relies on ICU placing U+FFFF last. **Swift: implement "(No bucket) last" explicitly**, compare bucket names with
`localizedCompare`-style locale collation (`compare(_:options:[], range:nil, locale: .current)`), titles likewise.

Selection restore: `keep = rows.first{ id==sel && key==selKey } ?? rows.first{ id==sel }`; set list selection to keep with
notifications suppressed; `_selected = keep?.Item ?? _selected`.

Pinned tile deadline chip: `days = calendarDays(today → deadline)`; overdue = `days < 0 && !done`; text uses `MM-dd`.

### 3.3 QuickSwitcherWindow (`Views/QuickSwitcherWindow.xaml.cs`)

#### 3.3.1 `Score(item, q)` (:55-71) — exact
```
if q.isEmpty → 1
s = 0; name = item.Name ?? ""
if name.hasPrefix(q, ignoringCase)        s += 120
else if name.contains(q, ignoringCase)    s += 60
else if isSubsequence(q, name)            s += 25
if any tag hasPrefix(q, ignoringCase)     s += 45
else if any tag contains(q, ignoringCase) s += 22
if KindLabel(item.Kind).contains(q, ignoringCase)  s += 8      // "Equipment/Area" | "Task" | "Procedure" | "Vessel"
if description non-empty && description.contains(q, ignoringCase) s += 5
return s
```
"ignoringCase" = .NET `StringComparison.OrdinalIgnoreCase` (per-UTF-16-unit simple upper-casing; no locale, no
normalization). Swift: compare `String.uppercased()`-free — use `range(of:options:[.caseInsensitive, .literal])` (literal
= no Unicode normalization equivalence, closest to ordinal).

#### 3.3.2 `IsSubsequence(needle, haystack)` (:73-79)
Greedy scan: `j = 0; for each char c in haystack while j < needle.count: if lower(c) == lower(needle[j]) j += 1`;
return `j == needle.count`. Lowercasing is per UTF-16 unit, invariant (`char.ToLowerInvariant`). Spaces count as characters
(a space in the query must match a space in the name).

#### 3.3.3 `Refresh` (:36-51)
`q = text.trim().trimLeading("#")` → map scores → filter (`q.isEmpty || score > 0`) → sort (score desc, name asc
ordinal-ignore-case) → take 80 → select index 0 if any. Runs synchronously on each keystroke over all items.

#### 3.3.4 `Move(delta)` (:92-99)
`n = count; if n == 0 return; i = selectedIndex < 0 ? 0 : selectedIndex + delta; select clamp(i, 0, n-1); scrollIntoView`.

### 3.4 SearchWindow + SearchService

`SearchWindow.RunAsync` (SearchWindow.xaml.cs:44-86) — §2.4 QUICK-122. Cancellation only discards superseded results
(the scan itself is not interruptible). `BuildHighlighted(text, start, len)` (:88-108): clamp `start` to `[0, text.length]`
(out of range → 0), `end = min(text.length, start + max(0, len))`; runs: prefix (if start > 0), match (if end > start;
bg `#FFE066`, fg black, bold), suffix (if end < length).

`SearchService.Search` (Services/SearchService.cs:35-115) — §2.4 QUICK-123. Each `Add(owner, kind, where, text, childId)`:
return if 500 reached or text empty; `idx = text.IndexOf(q, OrdinalIgnoreCase)`; skip if < 0; `(snippet, start) = MakeSnippet(text, idx, q.Length)`;
append `Hit{Owner, Kind, Where, Snippet, MatchStart:start, MatchLength:q.Length, ChildId}`. `HitKind` (Item, Component,
Subtask, Step, File) and `ChildId` are produced but unused by the UI (the Mac may use `ChildId` to select the child — optional
enhancement, not required).

`MakeSnippet(text, idx, len)` (:131-147) — exact:
```
around = 60
start = max(0, idx - 60); end = min(text.length, idx + len + 60)
s = (start > 0 ? "…" : "") + text[start..<end] + (end < text.length ? "…" : "")
compact = s.replacing(regex: \s+, with: " ")                 // .NET \s = Unicode whitespace incl. U+00A0, U+0085
newIdx = compact.indexOf(text[idx..<idx+len], ordinalIgnoreCase)
if newIdx < 0: newIdx = (start > 0 ? 1 : 0) + (idx - start)  // fallback when the match itself contained a collapsed run
return (compact, newIdx)
```
All lengths/indices are **UTF-16 code units** (the Swift port must index in UTF-16 or convert carefully; the highlight
uses NSRange/AttributedString ranges built from UTF-16 offsets).

`PlainTextFromXaml(xaml)` (:152-179) — the XAML shape this subsystem **consumes** (§4.8):
```
if empty → ""
try XmlReader(IgnoreWhitespace=false):
   for each node:
     Text or SignificantWhitespace → append(value) + " "
     Element named Paragraph | LineBreak | ListItem (start tag, incl. empty element) → append " "
     (Whitespace nodes outside xml:space="preserve", CDATA, comments, attributes → ignored)
catch (malformed XML, e.g. "enc:…" locked blob) → regex replace "<[^>]+>" with " " (no entity decoding)
```
Consequence (must be replicated for parity): text split across two `<Run>`s gets a space inserted, so `Hel|lo` in two runs
does not match `Hello` (see Q-6).

### 3.5 ActivityLogWindow (`Views/ActivityLogWindow.xaml.cs`)

| Function | Lines | Behaviour |
|---|---|---|
| `Refresh` | 25-38 | reverse stored order; filter Action/Kind/Name/Detail contains (ignore case); count line. |
| `Clear_Click` | 42-50 | QUICK-154. |
| `Export_Click` | 52-74 | QUICK-155 / §4.6. |
| `Csv(s)` | 76-82 | null → ""; if contains `,` or `"` or `\n` → `"` + s with `"`→`""` + `"`; else raw. **`\r` alone does not trigger quoting.** |

### 3.6 TrashWindow + repository trash operations

| Function | Lines | Behaviour |
|---|---|---|
| `TrashWindow` ctor | TrashWindow.xaml.cs:20-25 | bind list to live `Data.Trash`. |
| `Restore_Click` | :27-45 | QUICK-174. |
| `DeletePermanent_Click` | :47-55 | QUICK-175. |
| `Empty_Click` | :57-64 | QUICK-176. |

#### 3.6.1 `AppRepository.RestoreTrash(ti)` (AppRepository.cs:422)
Deserialize `ti.PayloadJson` into the type named by `ItemType` (`Equipment`, `Task`→TaskItem, `Procedure`, `Vessel`,
`Crew`→CrewMember) with options {IgnoreCycles, WhenWritingNull}; null or exception → return null (entry stays in Trash).
If **no live item with the same Id** exists, append it to the end of its collection (otherwise it is silently not added —
but the entry is still removed and logged). Remove the entry from `Data.Trash`; `LogAdded(ti.KindLabel, ti.Name, "restored from Trash")`;
MarkDirty; return ItemType. References were never scrubbed at trash time, so relationships come back intact.

#### 3.6.2 `PurgeTrash(ti)` (:520) / `EmptyTrash()` (:525) / `PruneTrash()` (:398)
Purge: if removed → `PurgeReferences(ti.ItemId)` + MarkDirty. Empty: purge references for every entry, clear, MarkDirty.
Prune (called on every trash add and once at startup): evict entries with `DeletedUtc < UtcNow − 90 days` (walk from the end),
then while count > 200 evict the oldest by `DeletedUtc`; each eviction scrubs references; MarkDirty if anything changed.

#### 3.6.3 `PurgeReferences(id)` (:186)
For every top-level item: remove id from `RelatedIds`; Equipment: from `ProcedureIds`, `TaskIds`; Procedure: from every
step's `TaskIds`, `EquipmentIds`. Then for every container in `AllContainers()` (items, components, nested subtasks, steps,
vessels, crew checklist steps, saved-list items) remove id from each file's `LinkedItemIds`.

### 3.7 DataDiff (`Services/DataDiff.cs`) — exact algorithm

```
Compare(current, incoming):
  names = {}  ; for i in Items(current): names[i.Id]=i.Name ; for i in Items(incoming): names[i.Id]=i.Name  (incoming wins)
  cur = ordered dict Id→item of Items(current)   (last duplicate wins)
  inc = ordered dict Id→item of Items(incoming)
  for (id,i) in inc where id ∉ cur:  Added++,   root(Added,  Root(i)) + ContentChildren(i, Added)
  for (id,i) in cur where id ∉ inc:  Removed++, root(Removed,Root(i)) + ContentChildren(i, Removed)
  for (id,b) in inc where a = cur[id]: kids = CompareItem(a,b); if kids nonEmpty: Changed++, root(Changed, Root(b)) + kids
  sort roots by (Order(change): Added 0 < Changed 1 < Removed 2, then text ordinal-ignore-case)
Items(d) = Equipment + Tasks + Procedures + Vessels (top-level only)
Root(i)  = "[" + (Equipment ? "Equipment/Area" : kind enum name) + "] " + i.Name
```
`ContentChildren(i, c)` (all nodes carry change c):
* each file of `i.Container.Files` → `file: {Name}`;
* Task: each subtask → `subtask: {Name}` with children = its files (`file: …`) then its subtasks recursively;
* Equipment: each component → `component: {Name}` with its files; then each `ProcedureIds` → `linked procedure: {name}`,
  each `TaskIds` → `linked task: {name}`;
* Procedure: each step → `step: {Title}` with children: files, then `linked task: {name}` per step TaskId, then
  `linked equipment/area: {name}` per step EquipmentId.
* Vessel: files only.
`{name}` = `names[id]` or `(unknown)`.

`CompareItem(a, b)` → list of nodes:
1. `AddHierarchyFields`:
   * `a.Name != b.Name` → Changed `name: "{a}" → "{b}"`
   * `(a.Description ?? "") != (b.Description ?? "")` → `description: "{Snip(a)}" → "{Snip(b)}"`
   * `PlainText(a.notes) != PlainText(b.notes)` → `notes: "{Snip(pa)}" → "{Snip(pb)}"`
   * `DiffFiles`: key = `Name + "|" + Path`; in b not a → Added `file: {Name}`; in a not b → Removed `file: {Name}`
     (a renamed/moved file shows as one added + one removed; duplicate keys within one container throw in .NET —
     `ToDictionary` — Swift should keep the last and not crash, see Q-8).
2. Task (both tasks): `Deadline` differs → `deadline: {Fmt a} → {Fmt b}`; `RangeStart` → `start: …`;
   `Recurrence` → `recurrence: {A} → {B}` (enum names); `Status` → `status: {A} → {B}`; then `DiffTasks(subtasks,"subtask")`.
   Deadline/RangeStart comparison is **exact DateTime equality including time of day** (while `Fmt` prints only the date,
   so `deadline: 2026-09-29 → 2026-09-29` is possible).
3. Equipment: `DiffComponents`, `DiffLinks(ProcedureIds,"linked procedure")`, `DiffLinks(TaskIds,"linked task")`.
4. Procedure: `DiffSteps`.
`DiffTasks(a, b, label)`: by Id: added (in b) → Added `{label}: {Name}` + TaskContentChildren; removed → Removed + content;
common → recurse `CompareItem`; non-empty → Changed `{label}: {b.Name}` with kids.
`DiffComponents`: added/removed with file children; common: `name: "…" → "…"`, `notes line: "{Snip}" → "{Snip}"` (the
component's plain `Notes` string), `notes: …` (container plain text), `DiffFiles` → Changed `component: {b.Name}`.
`DiffSteps`: added/removed with StepContentChildren; common: `title: "…" → "…"`, `done: {False|True} → {False|True}`
(C# `bool.ToString()` — capitalised), `notes: …`, `DiffFiles`, `DiffLinks(TaskIds,"linked task")`,
`DiffLinks(EquipmentIds,"linked equipment/area")` → Changed `step: {b.Title}`.
`DiffLinks(a, b, label)`: as sets; ids in b∖a → Added `{label}: {name}` (in b's enumeration order), a∖b → Removed.

Helpers: `Fmt(d)` = `yyyy-MM-dd` or `(none)`. `Snip(s)`: null→"", replace `\r` and `\n` each with a space, trim; if
length ≤ 40 keep else first 40 UTF-16 units + `…`. `PlainText(xaml)`: empty → ""; replace regex `<[^>]+>` with " "; HTML-decode
entities (`WebUtility.HtmlDecode`: named HTML entities incl. `&amp; &lt; &gt; &quot; &apos; &nbsp;` and numeric `&#NN; &#xHH;`);
collapse `\s+` to a single space; trim. Note this differs from `SearchService.PlainTextFromXaml`. Formatting-only edits
(bold, colour) do not register as a notes change. A locked container (`enc:…`) compares/prints its ciphertext text.

### 3.8 Shared services used here

`BatchDone.SetDone(item, done)` (Services/BatchDone.cs:16): Task: no-op if `IsComplete == done` else set (Status follows:
done → Done; undone from Done → Todo). Step: no-op if equal else set `Done`. Procedure: done → no-op if already Done else
`Status = Done`; undone → no-op unless Status == Done, then `Status = Todo` (preserves InProgress/Blocked). Returns
whether it changed. `SetDoneAll` counts changes.

`BatchDeadline.SetDeadline(item, date)` (Services/BatchDeadline.cs:16): `d = date?.Date`. Task: `d == nil` → if both
Deadline and RangeStart already nil → no-op, else clear **both**; otherwise `(s, dd) = WorkRange.Coerce(RangeStart, d, editedStart:false)`,
no-op if unchanged, else write both. Procedure / Step: no-op if equal else set.

`WorkRange.Coerce(start, deadline, editedStart)` (Services/WorkRange.cs:15): strip times; if start set: deadline nil →
deadline = start; else if start > deadline → (editedStart ? deadline = start : start = deadline). Start nil → unchanged.
Note in the quick-work pane clearing the Deadline picker of a task that has a Range start re-fills the deadline with the
start date (Coerce(start, nil) → (start, start)); the user must clear Range start first (test vector T-QW-7).

`TaskItem.CoversDay(day)` (Models.cs:204), `HasRange` (:190) — §2.1 QUICK-013. `IsComplete`/`Status` setters keep each
other in sync (Models.cs TaskItem).

`AppRepository.AllJobs()` (AppRepository.cs:121): tasks (recursive, pre-order) with IsJob; per procedure: the procedure if
IsJob, then its IsJob steps; per crew member: IsJob checklist steps.

`AppRepository.KindLabel` (:250): Equipment → `Equipment/Area`, others their enum name.

### 3.9 MainWindow glue (for the Mac app shell)
`ReviewAndConfirmImport` (:629) and `AgeVerdict` (:645) — §2.7. `OpenDueDatesWindow` (:915), `OpenQuickWork` (:293),
`OpenQuickSwitcher` (:285), `OpenSearch` (:307), `MenuActivityLog_Click` (:301), `MenuTrash_Click` (:1528),
`RefreshAfterRestore` (:1475), `NavigateToItem` (:313), `NavigateToCrew` (:924), `ShowDailyDigestIfDue` (:1624),
tray `BalloonTipClicked` (:1598), re-point fan-out (:1216-1217).

---------------------------------------------------------------------------------------------------------------------

## 4. DATA FORMATS

### 4.1 Serializer facts (data.json, trash payloads)
`System.Text.Json` with `WriteIndented=false`, `ReferenceHandler.IgnoreCycles`, `DefaultIgnoreCondition=WhenWritingNull`,
default (PascalCase = C# property name) naming, **case-sensitive** property matching on read, **enums as integers**
(no `JsonStringEnumConverter` anywhere), default encoder (non-ASCII and HTML-sensitive characters written as `\uXXXX` —
the Mac may write raw UTF-8; both parse). Nulls are omitted; empty collections are written as `[]`. `[JsonIgnore]`
computed properties must never be written by the Mac (listed in 4.9).

| Type | JSON form written by Windows | Mac read rule | Mac write rule |
|---|---|---|---|
| `Guid` | `"3f2504e0-4f89-11d3-9a0c-0305e82c3301"` (lower-case, hyphenated) | case-insensitive | **lower-case** (Swift `uuidString` is upper-case — lowercase it) |
| Date-only (`Deadline`, `RangeStart` from pickers) | `"2026-09-29T00:00:00"` (Kind Unspecified — no offset) | treat as a *floating local* date-time; never shift by time zone | write back without offset |
| `ScheduledStart` | `"2026-09-29T14:30:00"` (Unspecified) | floating local | no offset |
| `LastModified` (`DateTime.Now`) | `"2026-09-29T14:03:12.1234567+03:00"` (Local with offset; fraction trimmed of trailing zeros, omitted if zero) | parse offset → absolute instant; display in local zone | write local time with offset, 7-digit max fraction |
| `TimestampUtc`, `DeletedUtc`, `CreatedUtc` | `"2026-09-29T11:03:12.1234567Z"` | UTC | `Z` form |
| `double?` (`DueWindowWidth`) | `350` or `412.5`; omitted when null | Double | omit when nil |
| enums | integers (table 4.2) | Int | Int |

Equality of timestamps (e.g. SAME age in the diff, QUICK-196) is .NET tick-exact (100 ns). Keep an integer tick
representation (or at least parse the 7 fractional digits into an Int64) instead of a `Double`-based `Date` when exact
equality matters.

### 4.2 Enums (integers on disk)
| Enum | Values |
|---|---|
| `WorkStatus` | 0 Todo, 1 InProgress, 2 Blocked, 3 Done |
| `RecurrenceKind` | 0 None, 1 Daily, 2 Weekly, 3 Monthly, 4 Yearly |
| `FileKind` | 0 Document, 1 Image, 2 Video, 3 Link, 4 Other |
| `ItemKind` (not persisted on items — implied by the containing array) | 0 Equipment, 1 Task, 2 Procedure, 3 Vessel |

UI strings for these enums are their C# names (`Todo`, `InProgress`, …) — used verbatim in the Status/Recurrence combos,
in the diff (`status: Todo → Done`, `recurrence: None → Weekly`) and in search `Where` labels (`File › Document`).

### 4.3 Persisted fields read or written by this subsystem
* `Tasks[]` (TaskItem, recursive via `Subtasks[]`): `Id`, `Name`, `Description`, `Container{Id, RichTextXaml, Files[], SharedWithContainerIds[], IsLocked}`,
  `RelatedIds[]`, `Tags[]`, `GroupId?`, `BucketIds[]`, `LockHash?`, `LockSalt?`, `LockHint?`, `Deadline?`, `RangeStart?`,
  `IsJob`, `DurationMinutes` (default 60), `ScheduledStart?`, `Recurrence`, `RecurrenceSpawned`, `IsComplete`, `Status`, `Subtasks[]`.
  Read-only legacy key `BucketId` (single Guid) must be **migrated on read** into `BucketIds` (append if absent) and **never written**.
* `Procedures[]`: hierarchy fields + `Steps[]`, `Deadline?`, `Recurrence`, `RecurrenceSpawned`, `Status`, `IsJob`, `DurationMinutes`, `ScheduledStart?`.
* `ChecklistStep` (procedure `Steps[]` and crew `Checklist[]`): `Id`, `Title`, `BucketIds[]`, `Done`, `Deadline?`, `IsJob`, `DurationMinutes`,
  `ScheduledStart?`, `TaskIds[]`, `EquipmentIds[]`, `Container`.
* `Equipment[]` (read by search/diff): `Components[]{Id, Name, Notes, Container}`, `ProcedureIds[]`, `TaskIds[]`.
* `Vessels[]` (read by search/diff/switcher): hierarchy fields only.
* `Crew[]`: `Id`, `FirstName`, `MiddleName`, `LastName` (FullName is computed), `Checklist[]`.
* `QuickBuckets[]`: `Id`, `Name`, `Category`, `CreatedUtc`.
* `ChecklistTemplates[]`: `Id`, `Name`, `Items[]{Title, DurationMinutes, IsJob, Container}`, `CreatedUtc`, `GroupId?`. New
  templates are **appended** (collection order = user arrangement).
* `Log[]` — §4.5. `Trash[]` — §4.7.
* `Ui.QuickViewPinIds` — `List<Guid>` (always written, `[]` when empty). `Ui.DueWindowWidth`, `Ui.DueWindowHeight` — `double?`.
* `LastModified` — read for the diff's age verdict (§2.7).

### 4.4 How these keys travel between machines
* **Shared save / .zip / .aaz bundles / Drive backups** carry the whole `data.json` including all of `Ui` (so a Windows
  `DueWindowWidth` can arrive on the Mac and vice-versa; clamp to the visible screen).
* **Flash Sync** (`FlashSync/FlashChangeSet.cs`, QR_SYNC_PROTOCOL.md): `Ui` never travels as a block; shared Ui keys are diffed
  key by key — `QuickViewPinIds` **travels**; `DueWindowWidth`/`DueWindowHeight` are in the per-device denylist
  (`PerDeviceUiKeys`) and **never travel / are never overwritten**. `Log` has no `Id` → ships as one whole block.
  `Trash`, `QuickBuckets`, `ChecklistTemplates`, `Tasks`, `Procedures`, `Crew` are per-item by `Id`. The Mac Flash Sync
  implementation must keep the identical denylist.

### 4.5 Activity-log entries produced in this subsystem
| Trigger | Action | Kind | Name | Detail |
|---|---|---|---|---|
| QW `+ Task` | Added | `Task` | name | `` |
| QW `+ Procedure` | Added | `Procedure` | name | `` |
| QW 🗑 Delete | Removed | `Task`/`Procedure` | name | `` |
| QW `+ subtask`/`+ step` | Added | `Subtask`/`Step` | child name | owner name |
| QW `Add all` (bulk) | Added | `Subtask`/`Step` | `{n} added (bulk)` | owner name |
| QW children `Delete` | Removed | `Subtask`/`Step` | `{n} removed` | owner name |
| QW `💾 Save as list...` | Added | `Saved list` | list name | `{n} item(s)` |
| QW `📋 Load a saved list...` | Added | `Subtask` / `Checklist step` | `{n} added (from saved list '{name}')` | owner name |
| Trash `↩ Restore` (and Ctrl+Z) | Added | trash entry `KindLabel` | entry `Name` | `restored from Trash` |
(Name is trimmed and blank → `(unnamed)` by `LogAction`. Renames, status/deadline edits, pin toggles, bucket changes,
done toggles, permanent trash deletes and log clearing are **not** logged.)

`LogEntry` JSON: `{"TimestampUtc":"2026-09-29T11:03:12.1234567Z","Action":"Added","Kind":"Task","Name":"Fire drill","Detail":""}`
(`TimeUtc`/`TimeLocal` are `[JsonIgnore]`). Cap: after each append, drop from the front while count > 10 000.

### 4.6 Activity-log CSV export (byte format)
* Encoding UTF-8 **without BOM** (`File.WriteAllText` default).
* Line terminator **CRLF** (`StringBuilder.AppendLine` on Windows) after every line including the last.
* Header: `TimestampUTC,LocalTime,Action,Kind,Name,Detail`
* One line per entry in stored order: `Csv(TimeUtc),Csv(TimeLocal),Csv(Action),Csv(Kind),Csv(Name),Csv(Detail)` where
  `TimeUtc` = `yyyy-MM-dd HH:mm:ss UTC` and `TimeLocal` = local `yyyy-MM-dd HH:mm:ss` (evaluated at export time, current
  zone), `Csv` = §3.5. The Mac must produce byte-identical output for identical data and time zone.

### 4.7 Trash entry format (`TrashedItem`)
```json
{"Id":"<guid>","ItemType":"Task","ItemId":"<guid>","BatchId":"00000000-0000-0000-0000-000000000000",
 "Name":"Pump overhaul","KindLabel":"Task","DeletedUtc":"2026-09-29T11:03:12.1234567Z",
 "PayloadJson":"{\"Id\":\"…\",\"Name\":\"Pump overhaul\",…}"}
```
* `ItemType` ∈ `Equipment`, `Task`, `Procedure`, `Vessel`, `Crew`; `KindLabel` ∈ `Equipment/Area`, `Task`, `Procedure`, `Vessel`, `Crew member`.
* `BatchId` = `Guid.Empty` for single deletes and legacy entries; shared by one batch delete.
* `PayloadJson` is a **JSON string** containing the full serialized object (whole subtree) with the same PascalCase keys,
  enum ints, date formats and null-omission as data.json (options: IgnoreCycles + WhenWritingNull). Windows deserializes it
  case-sensitively into the concrete type — a Mac-written payload must use the exact key names. `DeletedLocal`/`Display`
  are `[JsonIgnore]`.
* Crew `Name` = FullName, or LastName if FullName is blank.

### 4.8 XAML consumed (rich text) — no XAML is produced by this subsystem
This subsystem only **reads** `Container.RichTextXaml` to derive plain text, with two different algorithms:
1. Search (`SearchService.PlainTextFromXaml`): an XML parse of the WPF `TextRange.Save(DataFormats.Xaml)` output, i.e. shapes like
   ```xml
   <Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
     <Paragraph><Run>Main </Run><Run FontWeight="Bold">engine</Run><LineBreak/><Run>lube oil</Run></Paragraph>
     <List MarkerStyle="Disc"><ListItem><Paragraph><Run>Step one</Run></Paragraph></ListItem></List>
     <Table><TableRowGroup><TableRow><TableCell><Paragraph><Run>A1</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>
   </Section>
   ```
   Every text node (and significant whitespace) contributes `value + " "`; `<Paragraph>`, `<LineBreak>`, `<ListItem>` start
   tags contribute `" "`. Attribute values are ignored.
2. Diff (`DataDiff.PlainText`): strip `<…>` tags → HTML-decode → collapse whitespace → trim.
3. Locked bodies are an `enc:`-prefixed blob (not XML): search falls back to tag stripping (the blob text itself); the diff
   prints it raw (snipped).

**Cross-subsystem requirement for the Mac XAML writer** (NSAttributedString → XAML): run text MUST be emitted as element
content (`<Run>text</Run>`), never as a `Text="…"` attribute, and paragraphs/line breaks/list items MUST use the element
names above with `xml:space="preserve"` on the root — otherwise both the Windows and Mac searches and diffs silently miss
the text.

### 4.9 `[JsonIgnore]` members that must never be written
`HierarchyItem.Kind`, `IsLockProtected`; `TaskItem.HasRange`, `RangeFirst`, `WhenText`, `JobName`; `Procedure.JobName`;
`ChecklistStep.JobName`; `FileItem.SourceLabel`; `ChecklistTemplate.Display`; `QuickBucket.Display`;
`TrashedItem.DeletedLocal`, `Display`; `LogEntry.TimeUtc`, `TimeLocal`; `CrewMember.FullName`, `Key`, `HasFlags`.
`HierarchyItem.BucketId` getter always returns null (so it is never written).

---------------------------------------------------------------------------------------------------------------------

## 5. DEPENDENCIES

### 5.1 Called by this subsystem
| Callee | Used by | Functions |
|---|---|---|
| `AppRepository` | all | `Data`, `Save`, `MarkDirty`, `FlushIfDirty`, `Saved` event, `AllItems`, `FindById`, `AllJobs`, `LogAdded`, `LogRemoved`, `PurgeReferences`, `RestoreTrash`, `PurgeTrash`, `EmptyTrash`, static `KindLabel` |
| `BatchDone` | A, B | `SetDone`, `SetDoneAll` |
| `BatchDeadline` | B | `SetDeadlineAll` |
| `BatchDoneMenu` / `BatchDeadlineMenu` | B | `Add`, `RightClickSelect` |
| `WorkRange` | B | `Coerce` |
| `ChecklistTemplateService` | B | `CaptureFromSubtasks`, `CaptureFromSteps`, `ApplyToSubtasks`, `ApplyToSteps` |
| `SearchService` | D | `Search`, `PlainTextFromXaml` |
| `ItemLockService` | D | `IsGated` (session unlock set) |
| `DataDiff` | G (via MainWindow) | `Compare` |
| `UiTree` | A, B | `FindAncestor<T>` (content-element-safe ancestor walk) |
| Dialogs | B, E | `PromptWindow`, `DatePromptWindow`, `ItemPickerWindow`/`PickerItem`, `SubtaskEditorWindow`, `ChecklistStepEditorWindow`, `SubtaskBuilderWindow`, `ChecklistBuilderWindow`, `MessageBox`, `SaveFileDialog` |
| MainWindow callbacks | A–D | `NavigateToItem`, `NavigateToCrew` |
| Converters | B | `BoolToStrike` |

### 5.2 Calls into this subsystem
`MainWindow`: openers (§3.9), `_floating.Refresh/SetRepo`, `_quickWork.SetRepo`, `TrashWindow.Restored`,
`ReviewAndConfirmImport → DiffWindow`. `ReminderService` shares the floating window's definition of "due" (overdue /
today / next 7 days over tasks, subtasks, procedures, steps, crew steps; ship work orders excluded) — keep the two
consistent. Recurrence reconciliation (`OnRepoSaved → ReconcileRecurrences`) reacts to completions made here.

### 5.3 Windows-only APIs in this subsystem
| API | Where | Mac replacement (§6) |
|---|---|---|
| WPF `Window` `WindowStyle=None` + `AllowsTransparency` + `Topmost` + `ShowInTaskbar=False` + `DragMove` + `Thumb` resize + `DropShadowEffect` | A | `NSPanel` (borderless, `.floating` level, `hidesOnDeactivate=false`), `NSVisualEffectView`/SwiftUI background, `WindowDragGesture`, native resize |
| `SystemParameters.WorkArea` | A | `NSScreen.main!.visibleFrame` |
| Owned windows (`Owner=`) | all | independent `NSWindow`s / sheets |
| `ShowDialog` modality | C, F, G, dialogs | sheets / `NSPanel` / async `confirmationDialog` |
| `ListCollectionView` grouping/sorting + virtualization | B | SwiftUI `List` with `Section`s over a precomputed array |
| `GridSplitter` | B | `HSplitView` / `NSSplitViewController` |
| `ContextMenu`, `PreviewMouseRightButtonDown` | B | `.contextMenu(forSelectionType:)` |
| `Microsoft.Win32.SaveFileDialog` | E | `NSSavePanel` / `.fileExporter` |
| `Process.Start(file){UseShellExecute}` | E | `NSWorkspace.shared.open(url)` |
| `MessageBox` | B, E, F, G | `NSAlert` / `.alert` / `.confirmationDialog` |
| `Dispatcher.BeginInvoke`, `DispatcherTimer` (repo debounce) | A, MainWindow | `Task { @MainActor … }`, `DispatchQueue.main.async`, a debounced task |
| `Task.Run` + `CancellationTokenSource` | D | `Task.detached` + cancellation, generation counter |
| `XmlReader`, `Regex`, `WebUtility.HtmlDecode` | D, G | `XMLParser`, `NSRegularExpression`/Swift `Regex`, a small entity decoder |
| `System.Windows.Forms.NotifyIcon` balloon → opens A | MainWindow | `UNUserNotificationCenter` notification tap → open A; optional `MenuBarExtra` |
| DPAPI, OpenCV, Win32 | — | not used here |

---------------------------------------------------------------------------------------------------------------------

## 6. macOS ADAPTATION NOTES

### 6.1 Commands, menus and shortcuts
| Windows | Mac | Menu placement |
|---|---|---|
| Ctrl+R — due-dates window | **⌘R** | View (or Window) ▸ `Due Dates` (also a toolbar button, SF Symbol `pin` / `calendar.badge.exclamationmark`) |
| Ctrl+N — quick work | **⌘N** (keeps the WPF `ApplicationCommands.New` binding) | File ▸ `Quick Work…` and Tools ▸ `Quick Work Window` |
| Ctrl+O — quick switcher | **⌘O**, plus **⇧⌘O** alias ("Open Quickly" convention) | File ▸ `Go to Item…`, Tools ▸ `Quick Switcher`; toolbar `Go to` |
| Ctrl+F — global search | **⌘F** (see OQ-4 for the rich-text find conflict) | Edit ▸ Find ▸ `Search All Items…`; toolbar search button |
| Tools ▸ Activity log | Tools ▸ `Activity Log…` (no shortcut, as on Windows) | |
| File ▸ Trash | File ▸ `Trash…` | |
| Ctrl+Z undo delete | ⌘Z when no text view is first responder (Edit ▸ `Undo Delete`) | |
| Esc / Enter in dialogs | `.cancelAction` / `.defaultAction` | |
| (none) | **⌘W closes** every window here; Esc closes the switcher, the Trash sheet and cancels the diff | |
Implement with SwiftUI `Commands` (`CommandMenu("Tools")`, `CommandGroup(after: .newItem)` etc.). The shortcut strip at
the bottom of the main window must list the ⌘ forms.

### 6.2 Window architecture (macOS 26, Swift 6.4)
* **A — Due dates:** an `NSPanel` subclass hosting SwiftUI via `NSHostingView` (gives exact control):
  `styleMask = [.borderless, .resizable]` — do **not** add `.nonactivatingPanel`, so clicking it gives it focus exactly
  like the WPF window; override `canBecomeKey = true` (borderless windows refuse key status by default); `level = .floating`; `isFloatingPanel = true`; `hidesOnDeactivate = false` (WPF Topmost stays
  above other apps); `collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]`; `isOpaque = false`,
  `backgroundColor = .clear`, `hasShadow = true`; content clipped to a 12 pt rounded rectangle with a `.regularMaterial`
  (or `Panel` token) background and a 1 pt separator stroke. `contentMinSize = 260×220`. Title set to
  `Overdue, today & tomorrow` (Window menu / accessibility). Header drag: `WindowDragGesture()` on the header only
  (macOS 15+), or `window.performDrag(with:)`. Keep the custom corner grip (visual affordance) but also allow native edge
  resizing; persist size from `windowDidResize` (content size, points) into `Ui.DueWindowWidth/Height` with MarkDirty on
  every change (like WPF). Initial frame: size from Ui (if ≥ min), origin `x = vf.maxX − w − 16`, `y = vf.minY + 16`
  (AppKit y grows upward) of `NSScreen.main.visibleFrame`. Do **not** make it a child window of the main window (child
  windows move with their parent). Single instance held by an app-level controller; re-open = `makeKeyAndOrderFront` +
  refresh. Pure-SwiftUI alternative on macOS 26: `Window(id:"due")` + `.windowStyle(.plain)` + `.windowLevel(.floating)` +
  `.defaultWindowPlacement` + `.windowResizability(.contentMinSize)` + `.restorationBehavior(.disabled)` — acceptable if
  size persistence to data.json and "restore persisted size" are implemented (read the NSWindow via an
  `NSViewRepresentable` accessor).
  Visual refinements that keep all capability: SF Symbols instead of emoji (`checkmark.circle` task, `arrow.turn.down.right`
  subtask, `list.clipboard` procedure, `checklist` step, `person.crop.circle.badge.checkmark` crew, `clock` job) tinted with
  the same accent colours; section headers as small-caps secondary text; `Toggle(.checkbox)` for done; subtle
  `.animation(.default, value: rows)` removal when an item is ticked; refresh button `arrow.clockwise`, close `xmark`.
  Also recommended: observe `NSCalendarDayChanged` (`.NSCalendarDayChanged` notification) to refresh at midnight (fixes the
  stale-day quirk; additive).
* **B — Quick work:** `Window("Quick work — all tasks & procedures", id: "quick-work")` (single instance; `openWindow(id:)`
  focuses an existing one), default size 1200×800. Layout: `VStack` { pinned board (collapsible `DisclosureGroup`-style
  header `📌 Pinned`, `ScrollView` max height 240 containing a flow/`LazyVGrid(.adaptive(minimum:172, maximum:172))` of
  tiles), `HSplitView` { left 360 pt list, right detail `ScrollView` } }. Left: toolbar-like controls (a segmented `Picker`
  All/Tasks/Procedures is acceptable for the radios), `+ Task`/`+ Procedure` buttons, bucket buttons, `.searchable`-style
  field; `List(selection: Set<RowID>)` with `Section` per bucket (header `🪣 name (n)`), `RowID = itemId + "|" + bucketKey`,
  `.contextMenu(forSelectionType: RowID.self)` implementing the WPF right-click rule (if the clicked row is in the
  selection, act on all; else act on it — SwiftUI's forSelectionType already passes exactly that set). Strikethrough via
  `.strikethrough(isDone)`. Detail: `Form`/`Grid` with `TextField`, two `DatePicker`s with an explicit "none" state
  (a checkbox or a clear button — `DatePicker` has no nil value; see OQ-5), `Picker`s for Status/Recurrence, the children
  builder (`TextEditor` in monospaced font for bulk add, a `List` with multi-select + `.onMove` in addition to ↑/↓ buttons,
  double-click via `.contextMenu(primaryAction:)`), buttons as in QUICK-077. Tile: `RoundedRectangle(8)`, `ProgressView(value:)`
  (linear) for the bar, `Toggle("Done")`, pin button `pin.slash`. Name edits write-through with MarkDirty and must not
  rebuild the list per keystroke (focus). With Observation the left list can update live — allowed as long as selection and
  focus are preserved. Close = flush (`onDisappear` + `NSWindow.willCloseNotification`).
* **C — Quick switcher:** an "Open Quickly"-style `NSPanel` (titled `Go to item`, 620×480, centered over the main window,
  `.floating`, closes on Esc and on resign-key) hosting a SwiftUI view: large `TextField` (16 pt) with the placeholder,
  `List` of rows (kind capsule, name, tags), footer hint. Keys via `.onKeyPress(.upArrow/.downArrow/.return/.escape)` on
  the field (or `NSTextField` delegate `moveUp:`/`moveDown:`/`insertNewline:`/`cancelOperation:`). WPF modality (main
  window blocked) is not required; a sheet on the main window is an acceptable alternative that preserves it exactly.
* **D — Search:** `WindowGroup("Search", id: "search", for: UUID.self)` so each ⌘F opens a new window (faithful; see OQ-3).
  `Table` with columns `Where` and `Match`; the snippet as `Text(AttributedString)` with the match run
  `backgroundColor #FFE066`, `foregroundColor .black`, bold; `.lineLimit(1)` + `.truncationMode(.tail)`. Search button +
  Return (`.onSubmit`), status line, `ProgressView` optional. Run on `Task.detached` over a Sendable snapshot (§6.3);
  keep a generation counter so a superseded run's results are dropped; re-enable the button when the *latest* run ends
  (fixes Q-10). Double-click / Return → navigate (`.contextMenu(primaryAction:)` or `onKeyPress(.return)`).
* **E — Activity log:** `WindowGroup("Activity log", id: "activity-log")` (new window per open, faithful), `Table` with the six
  columns (sortable columns are an optional enhancement; default order must be newest-first by insertion), filter field in
  the toolbar (`.searchable`), toolbar buttons `Export (.csv)…` (`NSSavePanel`, `allowedContentTypes: [.commaSeparatedText]`,
  default name as §2.5) and `Clear log` (`.confirmationDialog` with a destructive button). After export
  `NSWorkspace.shared.open(url)`.
* **F — Trash:** a **sheet** on the main window (modal like WPF), `Table` with multi-select, bottom bar buttons
  (`arrow.uturn.backward` Restore as `.borderedProminent`, destructive confirmations via `.confirmationDialog`), Close /
  Esc. Restores publish a notification or call the page refreshers (with Observation, pages update automatically — still
  honour the "refresh affected pages" contract for any cached view models).
* **G — Diff:** a **sheet** on the main window returning `Bool` through an `async` continuation (callers `await`), title
  `Review changes before importing`. Tree: `List { OutlineGroup }` or recursive `DisclosureGroup`s with
  `isExpanded` bound to per-node state initialised `true` for roots, `false` otherwise. Glyph column fixed width 20 pt,
  colours as QUICK-192 (consider slightly lighter variants in dark appearance for contrast — `#66BB6A`/`#EF5350`/`#FFA726` —
  only if the design system allows; semantics unchanged). Buttons: `Cancel` `.keyboardShortcut(.cancelAction)`,
  `Import (overwrite)` `.keyboardShortcut(.defaultAction)` `.buttonStyle(.borderedProminent)`.
* Dialog equivalents: `PromptWindow` → sheet with `TextField` + Cancel/OK; `DatePromptWindow` → sheet with graphical
  `DatePicker` + `Clear deadline`/Cancel/OK and the same validation message; `ItemPickerWindow` → sheet with filter field +
  multi/single-select `List` + Cancel/OK, returning selections **in selection order** (needed for "first two you picked").

### 6.3 Concurrency & performance (Swift 6 strict concurrency)
* All model mutation on `@MainActor`. Background search must not touch live model objects (the WPF version races with the
  UI thread): build an immutable `Sendable` snapshot of the searchable fields on the main actor (strings are CoW, so this
  is cheap), then scan in `Task.detached(priority: .userInitiated)`.
* The due-list, quick-work rows, switcher scoring and diff should be **pure functions** (`DueListBuilder.build(data:, today:)`,
  `QuickWorkRows.build(...)`, `QuickSwitcher.score(_:_:)`, `DataDiff.compare(_:_:)`) — deterministic and unit-testable with
  an injected `today` and `TimeZone`.
* Diff on large databases: run `DataDiff.compare` off the main actor over value snapshots; show a progress indicator if > ~200 ms.
* Lists: SwiftUI `List`/`Table` are lazily rendered; provide stable `Identifiable` ids (item id + bucket key for B; for A use
  `"\(section)|\(item id)"` since TODAY and TOMORROW can contain the same object).

### 6.4 Dark mode / appearance
The app has its own persisted theme toggle (`settings.json` `DarkMode`); apply it globally via `NSApp.appearance`
(`.darkAqua` / `.aqua`) and define colour tokens (`Bg`, `Panel`, `PanelAlt`, `Accent`, `Fg`, `Muted`, `BorderB`, `HoverBg`,
`SelBg`, `SelFg`) as dynamic `NSColor`s with the §2.8 QUICK-212 values, so these windows follow the same light/dark
palette. Fixed colours listed in QUICK-025/084/124/192 stay fixed. The search highlight must keep black text on yellow in
both appearances.

### 6.5 Things that are not possible 1:1 on macOS (and the faithful alternative)
* "Owned window stays above its owner and minimizes with it" — not a Mac concept; use normal window layering (and for A, the
  floating level). No capability is lost. When navigating from B/C/D to the main window, bring the main window forward
  (`makeKeyAndOrderFront`) — on Windows the owned window covered it.
* `Topmost` over *every* app including full-screen apps: use `.floating` + `.fullScreenAuxiliary`; above a full-screen app
  in another Space it cannot appear (OS limitation) — document.
* Tray balloon click → open A: replace with a `UNUserNotificationCenter` notification whose default action opens A
  (reminders spec), optionally a `MenuBarExtra` that shows the same due list (additive).
* Per-window taskbar suppression (`ShowInTaskbar=False`): Mac has no taskbar; exclude A and C from the Window menu
  (`isExcludedFromWindowsMenu = true`) to mirror it.

---------------------------------------------------------------------------------------------------------------------

## 7. TEST VECTORS / VERIFICATION

All vectors assume `TimeZone = Europe/Athens` (UTC+3 in September), locale `en_US`, and **today = Tue 2026-09-29** unless stated.

### 7.1 Due-dates window (`DueListBuilder`)
* **T-DUE-1 Overdue task.** Task "Hull survey", Deadline 2026-09-27, not complete → OVERDUE row, icon ✓, red accent,
  sub `Task · 2d overdue (was due Sun, 27 Sep)`; header sub starts `1 overdue  ·  `.
* **T-DUE-2 Overdue ordering.** Step deadline 2026-09-20 in procedure P, task deadline 2026-09-25 → OVERDUE order: step
  (`Checklist step · P · 9d overdue (was due Sun, 20 Sep)`) then task.
* **T-DUE-3 Ranged task ongoing.** RangeStart 09-28, Deadline 09-30 → TODAY `Task · ongoing`, TOMORROW `Task · ends today`,
  not in NEXT 7 DAYS, not overdue.
* **T-DUE-4 Ranged task starting today.** 09-29..10-02 → TODAY `Task · starts today`, TOMORROW `Task · ongoing`, excluded
  from NEXT 7.
* **T-DUE-5 Future range.** 10-01..10-03 → only NEXT 7 DAYS, once: `Task · starts today · due Thu, 01 Oct`.
* **T-DUE-6 Subtask owner.** Top-level "Engine" (no deadline) › "Filters" › "Replace gasket" (Deadline 09-29) → TODAY row
  `↳ Replace gasket`, sub `Subtask · Engine`, click navigates to "Engine".
* **T-DUE-7 Completed parent.** Task "Drill" IsComplete with incomplete subtask due today → subtask listed; completed
  subtask due today → not listed.
* **T-DUE-8 Done procedure, open step.** Procedure P Status=Done, Deadline today; step S Done=false, Deadline today →
  TODAY lists only S (`Checklist step · P`).
* **T-DUE-9 Job + deadline same day.** Task J IsJob, ScheduledStart 2026-09-29T14:30:00, Deadline 2026-09-29 → TODAY one row
  `✓ J`, sub `Task`.
* **T-DUE-10 Job today, deadline tomorrow.** Same J but Deadline 09-30 → TODAY `🕒 J` `Scheduled 14:30 · Task job`, TOMORROW
  `✓ J` `Task`.
* **T-DUE-11 Crew step.** Member with empty first/middle/last, checklist item "Medical" due 09-30 → TOMORROW
  `🧑‍✈️ Medical`, sub `Crew checklist · (unnamed)`, purple; click → NavigateToCrew.
* **T-DUE-12 Crew step job.** Crew step IsJob scheduled 2026-10-02T08:00:00, no deadline, member "Ann Lee" → NEXT 7 DAYS
  `🕒`, sub `Scheduled 08:00 · Crew step job · Ann Lee · due Fri, 02 Oct`.
* **T-DUE-13 Time-of-day deadlines.** Deadline 2026-09-29T23:59:00 → TODAY (date part only); Deadline 2026-09-28T23:59:00 → OVERDUE 1d.
* **T-DUE-14 Nothing.** Empty data → sections `TODAY   (0)` + `— nothing —`, `TOMORROW   (0)` + `— nothing —`, then
  `Nothing overdue, or due in the next 7 days 🎉`; no OVERDUE / NEXT 7 headers; header sub `Today Tue, 29 Sep  ·  Tomorrow Wed, 30 Sep`.
* **T-DUE-15 DST.** TimeZone Europe/Athens, today = 2026-10-26 (day after DST end 2026-10-25), task deadline 2026-10-24 →
  `2d overdue` (never 1d or 3d).
* **T-DUE-16 Tick done.** Tick T-DUE-1 row → task IsComplete=true, Status=Done, saved immediately, row gone, `1 overdue`
  prefix gone.
* **T-DUE-17 Size restore.** Ui.DueWindowWidth=200 (below min) → default 350 used; 400 → 400.
* **T-DUE-18 Next-7 boundary.** Deadline today+7 (10-06) → NEXT 7 DAYS; today+8 → nowhere.

### 7.2 Quick work
* **T-QW-1 Subtitle.** today 09-29: done task, deadline 09-25, 3 subtasks →
  `Task  ·  ✓ completed  ·  due 2026-09-25 (OVERDUE 4d)  ·  3 subtask(s)`; procedure due 09-29, no steps →
  `Procedure  ·  due today`; task due 10-04 → `Task  ·  due 2026-10-04 (in 5d)`; undated procedure with 1 step →
  `Procedure  ·  1 step(s)`.
* **T-QW-2 Sort (no buckets).** Items: A(active, due 10-01), B(active, undated), C(done, due 09-01), D(active, due 09-30) →
  order D, A, B, C.
* **T-QW-3 Grouping.** Buckets b1 "Deck" and b2 "deck" (distinct ids) and b3 "Engine"; item X in [b2, b1], Y in [] →
  groups: "Deck"/"deck" (order by id string between them), "Engine" (empty → absent), `(No bucket)` last containing Y;
  X appears in both deck groups. Count line counts X once.
* **T-QW-4 Stale bucket id.** Item with BucketIds [deletedId] → `(No bucket)`.
* **T-QW-5 Count line.** 12 items, 3 done → `12 item(s) — 9 active, 3 completed/done.`; 0 done → `12 item(s).`
* **T-QW-6 Tile progress text.** 1 of 3 subtasks complete → `1/3 subtasks done`; 0 of 1 step → `0/1 step done`; none +
  done → `completed`; none + active → `no items yet`; deadline 09-28 active → `OVERDUE 09-28`; same but done → `due 09-28`.
* **T-QW-7 Deadline/range coercion (model-based).** Task Deadline 10-05, RangeStart nil: set Range start 10-08 →
  (10-08, 10-08). Then set Deadline 10-01 → (10-01, 10-01). Task range 10-01..10-05, clear Deadline picker → Deadline
  becomes 10-01 again (Coerce(10-01, nil)). Clear Range start → (nil, 10-01).
* **T-QW-8 Batch deadline.** Task range 09-25..09-30 + batch date 09-20 → (09-20, 09-20). Batch "Clear deadline" on it →
  both nil. Procedure InProgress batch "not done" → unchanged (0 changes → no save).
* **T-QW-9 Bulk add.** Text `"  a \r\n\r\nb\n  \n c"` with Replace unticked → appends `a`, `b`, `c`; log Name `3 added (bulk)`.
* **T-QW-10 Move.** Steps [s0,s1,s2,s3], select {s1,s3}, ↑ → [s1,s0,s3,s2]; select {s0,s2} ↑ → no change.
* **T-QW-11 Bucket cap.** Picker returns [b3, b1, b2] → info message shown, BucketIds = [b3, b1].
* **T-QW-12 Pin pruning.** QuickViewPinIds = [t1, deletedId, p1] → after refresh [t1, p1], MarkDirty called.
* **T-QW-13 Delete.** Delete task T linked from equipment E.TaskIds and pinned → T gone from Tasks, E.TaskIds without T,
  pin removed, log `Removed Task T`, Trash unchanged.

### 7.3 Quick switcher (`score`)
* **T-QS-1** Equipment "Equipment Pump", q `eqpump` → 25 (subsequence only).
* **T-QS-2** Task "Pump room", tags ["pumps"], q `pump` → 120 + 45 = 165.
* **T-QS-3** Task "Main pump", q `pump` → 60.
* **T-QS-4** Task "Fire drill", q `task` → 8 (kind label only).
* **T-QS-5** Equipment "Deck", q `area` → 8 (`Equipment/Area`).
* **T-QS-6** Vessel "Aurora", description "Aframax tanker", q `tanker` → 5.
* **T-QS-7** Query `##Safety` → normalized `Safety`; item tag "safety-walk" → +45.
* **T-QS-8** Query `#` → empty → all items (score 1), sorted by name ignore-case, first 80.
* **T-QS-9** Ties: "b pump", "A pump" both 60 → "A pump" first.
* **T-QS-10** `isSubsequence("", "x")` = true; `isSubsequence("ab", "ba")` = false; `isSubsequence("MP", "main pump")` = true.
* **T-QS-11** Navigation: 3 rows, index 0, ↑ → stays 0; ↓↓↓ → 2.

### 7.4 Search
* **T-SR-1 Snippet short.** text `The main engine lube oil pump was overhauled` (44 units), q `pump` → snippet = text,
  MatchStart 25, MatchLength 4.
* **T-SR-2 Snippet long.** 200×`a` + `PUMP` + 200×`b`, q `pump` → snippet `…` + 60×`a` + `PUMP` + 60×`b` + `…`
  (126 units), MatchStart 61, highlighted `PUMP`.
* **T-SR-3 Whitespace collapse.** `a\r\n\r\nPUMP` → snippet `a PUMP`, MatchStart 2.
* **T-SR-4 Collapsed match fallback.** text `x  y` (two spaces), q `x  y` → snippet `x y`, IndexOf fails → MatchStart 0
  (prefix 0 + (0−0)), MatchLength 4 → highlight clamped to `x y`.
* **T-SR-5 Plain text from XAML.** `<Section xml:space="preserve" xmlns="…"><Paragraph><Run>Hel</Run><Run>lo</Run></Paragraph></Section>`
  → ` Hel lo ` ; q `Hello` → no hit; q `lo` → hit.
* **T-SR-6 Entities.** `<Paragraph><Run>AT&amp;T</Run></Paragraph>` → ` AT&T ` (one text node; the Swift `XMLParser`
  implementation must concatenate `foundCharacters` chunks of one node before appending the trailing space).
* **T-SR-7 Whitespace nodes.** Without `xml:space="preserve"`, `<Paragraph>\n  <Run>x</Run>\n</Paragraph>` → ` x ` (indentation
  whitespace ignored); with preserve, a `<Run>   </Run>` contributes `"    "`.
* **T-SR-8 Locked.** Gated task "Secret plan" with description "valve codes": q `valve` → no hit; q `secret` → `Name` hit;
  tag "codes" → `Tags` hit on q `codes`.
* **T-SR-9 Order & limit.** Equipment name hit precedes a task hit; 600 matching items → exactly 500 rows.
* **T-SR-10 Status text.** 1 hit → `1 result for "pump".`; 0 → `No results for "pump".`
* **T-SR-11 enc blob.** Container RichTextXaml `enc:QUJD` → notes text `enc:QUJD` (regex fallback).
* **T-SR-12 Where labels.** File Kind Image named `deck.jpg` at `files/1_deck.jpg`, q `deck` → two hits `File › Image`,
  `File › Image › Path`.

### 7.5 Activity log
* **T-AL-1 CSV quoting.** Name `Pump, "main"` → `"Pump, ""main"""`; Detail `a\rb` → unquoted `a\rb`; Detail `a\nb` → `"a\nb"`.
* **T-AL-2 Line.** Entry 2026-09-29T11:03:12Z Added/Task/Fire drill/"" in Athens →
  `2026-09-29 11:03:12 UTC,2026-09-29 14:03:12,Added,Task,Fire drill,` + CRLF; file begins with the header, no BOM.
* **T-AL-3 Order.** Stored [e1,e2,e3] → UI shows e3,e2,e1; CSV writes e1,e2,e3 regardless of filter.
* **T-AL-4 Filter.** filter `bulk` matches entries whose Name is `3 added (bulk)`; filter `restored` matches Detail
  `restored from Trash`; count `2 of 57 log entries.`
* **T-AL-5 Cap.** 10 000 entries + 1 append → 10 000, first removed.
* **T-AL-6 Name normalization.** LogAdded("Task", "  x  ") → Name `x`; LogAdded("Task", "") → `(unnamed)`.

### 7.6 Trash
* **T-TR-1 Restore.** Trash entry Task T (payload with 2 subtasks) → Tasks gains T with both subtasks; entry removed;
  log `Added / Task / T / restored from Trash`; Restored("Task") raised once.
* **T-TR-2 Restore collision.** A live task already has T.Id → not duplicated; entry still removed and logged.
* **T-TR-3 Corrupt payload.** PayloadJson `{` → RestoreTrash null, entry kept; if it was the only selection →
  `Couldn't restore the selected item(s).`
* **T-TR-4 Mixed restore.** Task + Crew selected → Restored("Task") and Restored("Crew"), one Save.
* **T-TR-5 Permanent delete scrubs.** Entry for procedure P referenced by equipment E.ProcedureIds → after Delete permanently,
  E.ProcedureIds lacks P.
* **T-TR-6 Prune.** Entry DeletedUtc = now − 91 days → evicted on PruneTrash; 201 entries → oldest evicted.
* **T-TR-7 Payload round-trip compatibility.** A Mac-written PayloadJson for a TaskItem with enum ints, lower-case Guids,
  unspecified-kind deadline strings deserializes in the Windows harness (`JsonSerializer.Deserialize<TaskItem>`) to an
  equal object (cross-platform CI check).

### 7.7 Diff
* **T-DF-1 Task field changes.** Current T{Name "Pump check", Deadline 2026-09-01, Status Todo}; incoming same Id with
  Deadline 2026-09-05, Status Done → one root `～ [Task] Pump check` with children `deadline: 2026-09-01 → 2026-09-05`,
  `status: Todo → Done`; summary `This import will   ＋ add 0     ～ change 1     － remove 0   item(s).  Expand a row to see details.`
* **T-DF-2 Added equipment content.** Incoming-only Equipment "Deck crane" with component "Winch" (file manual.pdf) and
  TaskIds [T] → root `＋ [Equipment/Area] Deck crane` › `component: Winch` › `file: manual.pdf`; `linked task: Pump check`.
* **T-DF-3 Step done.** Step done false → true → `step: Test alarms` › `done: False → True`.
* **T-DF-4 Snip.** Description 45 chars `0123456789…` → `"{first 40}…"`; `line1\r\nline2` → `line1  line2` (two spaces).
* **T-DF-5 Formatting-only.** Notes `<Paragraph><Run>Hi</Run></Paragraph>` vs `<Paragraph><Run FontWeight="Bold">Hi</Run></Paragraph>`
  → no notes node (no root if nothing else changed).
* **T-DF-6 Ordering.** Roots added "b", changed "A", removed "c", added "a" → `＋ a`, `＋ b`, `～ A`, `－ c` (text includes the
  `[Kind] ` prefix: compare `[Task] a` etc.).
* **T-DF-7 Unknown link.** Step link to an id in neither DB → `linked task: (unknown)`.
* **T-DF-8 File rename.** `a.pdf|files/1_a.pdf` → `b.pdf|files/1_a.pdf` → `＋ file: b.pdf`, `－ file: a.pdf`.
* **T-DF-9 Not covered.** Only a tag added → `No differences detected — the incoming data appears identical to your current data.`
* **T-DF-10 Age verdict.** incoming 2026-09-29 14:00:00+03:00, current 2026-09-28 10:00:00+03:00 →
  `Incoming saved: 2026-09-29 14:00:00\nCurrent saved:  2026-09-28 10:00:00\n➜ The incoming data is NEWER than your current data.`;
  incoming nil, current set → `Incoming saved: (no save date)` … `➜ The incoming data has no save date (older format); it may be older.`;
  identical ticks → `SAME age`; differing only in the 7th fractional digit → NEWER/OLDER (tick-exact).
* **T-DF-11 Time-of-day deadline change.** Deadline 2026-09-01T00:00 → 2026-09-01T12:00 → `deadline: 2026-09-01 → 2026-09-01`.

### 7.8 Verification checklist for the Mac build (manual)
1. ⌘R opens the due panel bottom-right, above other apps; resize, quit, relaunch, ⌘R → same size.
2. Tick an overdue row → it disappears; main window, Calendar and ⌘N window show it done.
3. ⌘N → pin two items → tiles show progress; tick a tile Done → struck through and sinks; quit/relaunch → pins remain;
   Flash Sync to iPhone carries `QuickViewPinIds` but not the due-window size.
4. ⌘O, type `#tag`, ↓, Return → main window selects the item.
5. ⌘F, search a word inside a subtask's notes → `Subtask › Container` hit, highlighted; locked item hides it.
6. Activity log export opens in Numbers/TextEdit; bytes match the Windows export for the same data.
7. Delete an item (main window) → Trash sheet → Restore → item back with subtree and links.
8. Import a Windows-made .aaz → diff sheet shows expected tree; Esc cancels, Return imports.

---------------------------------------------------------------------------------------------------------------------

## 8. QUIRKS, KNOWN DEFECTS AND OPEN QUESTIONS

Default policy: **replicate** Windows behaviour (data compatibility and user expectations); items marked *fix* are
recommended low-risk corrections that change no data format — confirm with the product owner (OQ list).

* **Q-1** Quick-work 🗑 Delete is a hard delete (no Trash, no undo), unlike the main window. *(OQ-1)*
* **Q-2** `NavigateToItem` selects the main tab by fixed index 0–3, so after the user reorders tabs it opens the wrong tab
  (the item is still selected on its page). *Fix on Mac:* select the tab by identity.
* **Q-3** Floating window: a scheduled *subtask* job navigates to the subtask itself, which is not a top-level row → nothing
  gets selected. *Fix:* navigate to the root task (as deadline rows do).
* **Q-4** Floating window's range wording in NEXT 7 DAYS is relative to the collection day (`starts today · due Thu`), and job
  rows get a `due` suffix even though it is a schedule date. Replicate (strings are user-facing but harmless) or reword
  `starts Thu 01 Oct` *(OQ-6)*.
* **Q-5** No midnight refresh in the floating window. *Fix (additive):* refresh on day change.
* **Q-6** Search cannot match across formatting runs (`Hel|lo`). Replicate by default so Windows and Mac return the same
  hits; a fix would join adjacent runs within a paragraph without a space *(OQ-7)*.
* **Q-7** Quick switcher ranks locked items by their description (+5) — information-leak-by-ranking only; nothing is shown.
  Replicate or gate it like search *(OQ-8)*.
* **Q-8** `DataDiff.DiffFiles` throws (`ToDictionary` duplicate key) if one container holds two files with identical
  Name|Path; the exception would abort the import preview (caller falls to the crash handler). Mac: keep last, never crash.
* **Q-9** Diff omits many fields (QUICK-194). Replicate; extending it is a pure-UI enhancement *(OQ-9)*.
* **Q-10** Search: a newer run started while an older one is running re-enables the Search button when the older finishes.
  Mac: tie the button state to the latest generation.
* **Q-11** Activity log and Quick-work lists are snapshots (not live). Mac may make them live (Observation) provided
  selection/focus/scroll are preserved.
* **Q-12** Trash restore of an entry whose Id already exists removes the entry and logs "restored" without adding anything.
  Replicate (it only happens after a Flash Sync/import brought the item back).
* **Q-13** Quick-work detail's Status combo is not refreshed after a batch done from the context menu. Mac bindings will be
  live — acceptable.
* **Q-14** The TextBox `Tag` placeholders (`Search tasks & procedures...`, `Type a name, kind or #tag...`,
  `Filter action / kind / name...`) were never rendered on Windows; render them on the Mac.
* **Q-15** PROGRESS claims Esc/Ctrl+W close all tool windows; only the switcher (Esc) and the diff (Esc=Cancel) do on
  Windows. Mac: ⌘W everywhere, Esc for switcher/trash/diff/dialogs.
* **Q-16** Quick-work item deletion does not close a detached `ItemWindow` for that item (the main-window delete path does).
  Mac: notify the item-window registry on any hard delete.
* **Q-17** Culture-dependent date formats: `ddd, dd MMM` uses the current culture's abbreviations (keep `Locale.current`);
  `yyyy-MM-dd`, `MM-dd`, `HH:mm`, `yyyy-MM-dd HH:mm:ss` must be rendered with the Gregorian calendar and
  `en_US_POSIX` (on Windows a non-Gregorian default culture would change them — do not replicate that).

### Open questions
* **OQ-1** Should the Mac quick-work Delete go to the Trash (undoable, `TrashHierarchyItem`) instead of hard-deleting? Data
  format is unaffected either way; the confirmation text would change to mention the Trash.
* **OQ-2** Should Quick switcher be window-modal (sheet, faithful) or an Open-Quickly floating panel (more Mac-like)?
* **OQ-3** Search and Activity log open a new window on every invocation on Windows. Keep multi-window (WindowGroup) or make
  ⌘F focus an existing search window?
* **OQ-4** ⌘F for global search conflicts with the rich-text editor's native Find bar. Proposal: ⌘F = global search (faithful);
  ⌥⌘F = find in the current note.
* **OQ-5** SwiftUI `DatePicker` has no empty state; confirm the UX for "no deadline" / "no range start" (checkbox-enabled
  picker vs. a trailing clear button).
* **OQ-6** Keep the exact Windows wording for ranged tasks in NEXT 7 DAYS, or reword?
* **OQ-7** Fix cross-run search matching on both platforms together?
* **OQ-8** Gate description ranking of locked items in the quick switcher?
* **OQ-9** Extend DataDiff to tags/relationships/procedure dates/crew (would be a shared change with Windows for parity)?
* **OQ-10** Status/Recurrence combos: show raw enum names (`InProgress`) exactly as Windows, or friendly labels
  (`In Progress`) while writing the same integers?

---------------------------------------------------------------------------------------------------------------------

## 9. PROGRESS.md sections folded into this spec
`Data-safety, reminders & housekeeping batch (9 improvements)` (Trash, reminders, digest, NEXT 7 DAYS),
`Batch delete for tasks, procedures and equipment/areas` (BatchId, hard-delete note for Ctrl+N),
`Global highlighted search`, `Change preview before any import/overwrite`, `Deeper drill-down preview (tree)`,
`Deep, drill-down change preview`, `Light / Dark theme (sleek dark mode)`, `Strikethrough on completed checklist items / tasks`,
`Floating due-dates window (today & tomorrow)`, `Follow-up (2026-07-04): per-vessel export + notifications kept inside the vessel tab`,
`Update (2026-07-04): checklist steps act like subtasks (per-step deadlines)`,
`Update (2026-07-06): procedures on the calendar, scheduled jobs in the floating window, resizeable floating window, planner search`,
`Update (2026-07-06): shared-save verified, activity log, unit converter, Ctrl+N quick-work`,
`Quick switcher (Ctrl+O)` + review fix #3 (`#tag`), `Follow-up (2026-07-08): Ctrl+N shows ALL tasks & procedures (not just pending)`,
`Reusable saved lists (templates) in every builder`, `Crew items in due-dates & everywhere necessary`,
`Due-dates window resize + Ctrl+R + shortcut bar`, `Adversarial review (9 agents) → 3 fixes`,
`Hotfix (2026-07-08): app failed to start after login (invalid Ctrl+R command)`,
`Update (2026-07-08): pinned squares in the Ctrl+N quick-work window`,
`Update (2026-07-08): quick-work window — strike-through on done, and "buckets"`,
`Update (2026-07-08): buckets rework — predefined, own tab, up-to-two, every level` + its adversarial fixes,
`Optional working date-range on tasks & subtasks (the last date IS the deadline)`,
`Batch "mark as done" (right-click) + tab-drag crash fix`, `Shared-save cadence + complete items from the floating window`,
`Deadline a whole checklist at once + read-only saved-list item viewer`, `Floating due-dates window now shows OVERDUE`,
`Arrange the order saved lists appear in (and export in)` (picker order),
`Flash Sync: verified against the iPhone, and the Ui split fixed on both sides` (per-device Ui keys).
