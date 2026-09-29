# 07 — Calendar, Board, Planner, Buckets, Relationship Map (feature prefix `VIEW-`)

Porting spec for five main-window tabs of the WPF app **AA** that present the same underlying items
(tasks + nested subtasks, procedures, procedure checklist steps, crew checklist items, buckets,
relationships) through different lenses. This document is the contract for the Swift/macOS
implementation and for later verification. It describes what the Windows build **actually does**
(code is the source of truth; where `PROGRESS.md` disagrees, the difference is called out), then how to
make it Mac-native without losing anything.

Sources read completely:
`AA/Views/CalendarPage.xaml(.cs)`, `AA/Views/BoardPage.xaml(.cs)`, `AA/Views/PlannerPage.xaml(.cs)`,
`AA/Views/BucketsPage.xaml(.cs)`, `AA/Views/RelationshipMapPage.xaml(.cs)`; plus the call graph:
`Models/Models.cs`, `Models/CrewMember.cs` (FullName/Checklist), `Services/AppRepository.cs`,
`Services/BatchDone.cs`, `Services/BatchDeadline.cs`, `Services/WorkRange.cs`,
`Services/ChecklistTemplateService.cs` (`ItemToTask`, `CloneContainer`), `Services/DataStore.cs`
(JSON options, `ResolveFilePath`), `Services/ThemeManager.cs`, `Views/BatchDoneMenu.cs`,
`Views/BatchDeadlineMenu.cs`, `Views/SavedListPicker.cs`, `Views/ItemPickerWindow.xaml(.cs)`,
`Views/PromptWindow.xaml(.cs)`, `Views/DatePromptWindow.xaml(.cs)`, `Views/UiTree.cs`,
`Views/Converters.cs` (BoolToStrike), `Views/QuickWorkWindow.xaml.cs` (bucket assignment),
`MainWindow.xaml(.cs)` (hosting, refresh, navigation, UI-state capture), `App.xaml` (styles),
`FlashSync/FlashChangeSet.cs` + `QR_SYNC_PROTOCOL.md` (per-device Ui keys), `PROGRESS.md` (all
sections listed at the end), and the original product brief.

Related specs (other files in `mac/Docs/Spec/`) own: the data model / JSON layer, the hierarchy pages,
the subtask/checklist-step editors, the Ctrl+N quick-work window (where bucket *assignment* lives), the
floating due-dates window, saved lists, and Flash Sync. This spec references them by name.

---

## 0. Conventions used in this document

* `file:line` refers to the C# sources under `/Users/eriskay/erisdev/AA/AA/`.
* "Today" means `DateTime.Today` on Windows = the **local** calendar date at the moment the view is
  (re)built. It is never cached across refreshes. Mac: `Calendar.current.startOfDay(for: Date())`
  evaluated at refresh time.
* All date comparisons in this subsystem are **by local calendar day** (`.Date`), except where a full
  date-time is used for ordering (called out explicitly).
* "Week" always starts on **Sunday**, hard-coded (`d.AddDays(-(int)d.DayOfWeek)`), independent of the
  user's locale. The Mac port must keep Sunday-start for all filtering/grid math (display chrome such as
  the graphical date picker may follow the locale).
* WPF sizes are DIPs (1/96 in). Map **1 DIP → 1 pt** on the Mac (both are one logical pixel at 1×).
* Theme tokens (from `Services/ThemeManager.cs`) referenced below:

| Token | Light | Dark |
|---|---|---|
| `Bg` | #FFFFFF | #1E1E1E |
| `Panel` | #FFFFFF | #252526 |
| `PanelAlt` | #FFFFFF | #2D2D30 |
| `Accent` | #000000 | #FFFFFF |
| `Fg` | #000000 | #F0F0F0 |
| `Muted` | #000000 (sic — black in light) | #B0B0B0 |
| `BorderB` | #000000 | #3F3F46 |
| `HoverBg` | #EFEFEF | #3A3A3D |
| `SelBg` / `SelFg` | #CCE8FF / #000000 | #094771 / #FFFFFF |

  Note: in the light theme `Panel == PanelAlt == Bg == white` and `Muted == black`, so every "muted" or
  "alt background" cue described below is **invisible in light mode on Windows**. The Mac should render
  these cues with the semantic intent (secondary label colour, subtle alternate fill) in both appearances.
* Global font: Consolas (`App.xaml` `MainFont`), window default size 13. Mac: Consolas if installed else
  SF Mono, per `ARCHITECTURE-BRIEF.md`.

---

## 1. Overview

All five pages are `UserControl`s hosted as tabs in `MainWindow.xaml` `MainTabs` (default order, left to
right): Equipment/Area, Tasks, Procedures, Vessels, **Calendar** (`TabCalendar` → `CalendarPg`),
**Board** (`TabBoard` → `BoardPg`), **Planner** (`TabPlanner` → `PlannerPg`), **Relationship Map**
(`TabMap` → `MapPage`), Crew, Saved Lists, **Buckets** (`TabBuckets` → `BucketsPg`), Ports, SIRE 2.0.
Tabs can be reordered by drag (persisted in `UiState.TabOrder` by tab *name*), recoloured
(`UiState.TabColors`, keyed by tab name e.g. `"TabCalendar"`), and selected with Ctrl+1…9 (by current
display position). Those shell features belong to the main-window spec; the tab **names** above are data
keys and must be kept.

Lifecycle (`MainWindow.xaml.cs`):
* `InitPagesAndRestoreUi` (`:1190`) calls, on every data load/reload/import/shared-pull:
  `CalendarPg.Init(_repo, NavigateToItem)`, `BoardPg.Init(_repo)`, `PlannerPg.Init(_repo)`,
  `MapPage.Init(_repo)`, `BucketsPg.Init(_repo)` then `BucketsPg.Navigate = NavigateToItem`.
* `MainTabs_SelectionChanged` (`:1405`) refreshes the page being shown: Calendar → `Refresh()`,
  Board → `Refresh()`, Planner → `Refresh()`, Map → `RefreshSidebar()` (sidebar only — the map drawing
  is **not** redrawn), Buckets → `Refresh()`.
* `CaptureUiState` (`:1383`) — run on close, explicit save, dirty autosave, exports — writes
  `Ui.CalendarSelectedDate`, `Ui.CalendarViewMode`, `Ui.MapFocusedItemId` from the pages.
* `NavigateToItem` (`:313`) — used by Calendar (procedure rows) and Buckets (top-level members): selects
  main tab index 0/1/2/3 for Equipment/Task/Procedure/Vessel and then (dispatcher Background priority)
  calls that page's `SelectItemById(id)`. **Defect:** it uses fixed indexes, so after the user drags tabs
  into a different order it lands on the wrong tab. Mac: navigate by tab identity (see VIEW-205).

Purpose of each page:

| Page | Purpose |
|---|---|
| Calendar ("Schedule Matrix") | Month calendar + a list of every dated item (tasks, all nested subtasks, procedures, procedure steps, crew checklist items) filtered by Day / Week / Month / All Upcoming / Agenda; ranged tasks appear on every day they span; inline Done, batch done/deadline, double-click to edit. |
| Board ("Task Board") | Kanban of **every task and every nested subtask** in four status columns (To Do / In Progress / Blocked / Done); drag a card to change its status; search, hide-done, new task, add from saved lists, open all files, delete. |
| Planner | Drag-and-drop scheduler: Day/Week hour grid (15-min snap, duration-sized blocks, overlap columns), an all-day "due" strip, a Month grid; unscheduled-jobs pool with search; range-aware drags; add from saved lists. |
| Buckets | Define buckets (name + optional category, grouped by category); see and remove members (tasks, subtasks, procedures, checklist steps). Assignment ("up to two per item") happens in the Ctrl+N quick-work window. |
| Relationship Map | "Inspect" list of all top-level items; selected item drawn at the centre of a 2D canvas with its 1-hop related items on a circle, centre edges solid, neighbour↔neighbour edges dashed; click a node to recentre. |

---

## 2. Shared concepts

### 2.1 The item universe (which items each page sees)

| Item | Calendar | Board | Planner (placed) | Planner (unscheduled pool) | Buckets | Map |
|---|---|---|---|---|---|---|
| Top-level `TaskItem` (`Data.Tasks`) | if `Deadline != null` | always (one card) | if `ScheduledStart` or `Deadline` | if `IsJob` and neither | yes ("Task") | yes |
| Nested subtask (any depth, `Subtasks` recursive) | if `Deadline != null` | always (one card, with parent path) | if `ScheduledStart` or `Deadline` | if `IsJob` and neither | yes ("Subtask") | no |
| `Procedure` | if `Deadline != null` | no | if `ScheduledStart` or `Deadline` | if `IsJob` and neither | yes ("Procedure") | yes |
| Procedure `ChecklistStep` | if `Deadline != null` | no | if `ScheduledStart` or `Deadline` | if `IsJob` and neither | yes ("Checklist step") | no |
| Crew member `Checklist` item (`ChecklistStep`) | if `Deadline != null` | no | if `ScheduledStart` or `Deadline` | if `IsJob` and neither | **no** | no |
| `Equipment`, `Vessel` | no | no | no | no | no | yes |
| Crew `Schedule` entries, crew sign-off dates, Shippalm `ShipJob`s | **no** | no | no | no | no | no |

Trashed items are physically removed from their collections, so they never appear anywhere here.
Done/complete items are **not** filtered out by Calendar or Planner (only Board's "Hide done" filters).
Per-item password locks (`HierarchyItem.LockHash`) are **not** consulted by any of these pages — a
locked task still shows its name everywhere and can be opened in the subtask editor from Calendar,
Board, Planner or Buckets (see Open Questions).

### 2.2 Enumeration order (matters for stable sorts and card order)

* Tasks: `Data.Tasks` in collection order, each walked **depth-first pre-order** (task, then each
  subtask subtree in `Subtasks` order).
* Then procedures in `Data.Procedures` order, each procedure immediately followed by its `Steps` in order.
* Then crew members in `Data.Crew` order, each followed by its `Checklist` items in order.

LINQ `OrderBy`/`ThenBy` are **stable**, so ties keep this order. The Mac must use a stable sort.

### 2.3 Completion semantics (shared with the model spec)

* `TaskItem.IsComplete` ⇄ `TaskItem.Status` stay in sync (`Models.cs:226-250`): `IsComplete = true` →
  `Status = Done`; `IsComplete = false` while `Status == Done` → `Status = Todo`; setting `Status = Done`
  → `IsComplete = true`; any other status → `IsComplete = false`.
* `Procedure.Status` is the only completion state of a procedure (`Done` = complete).
* `ChecklistStep.Done` for steps and crew items.
* `BatchDone.SetDone` (`Services/BatchDone.cs`) — un-completing demotes only a *Done* item; an
  `InProgress`/`Blocked` item is left untouched; returns `true` only on a real change.

### 2.4 Persistence primitives (`Services/AppRepository.cs`)

* `MarkDirty()` (`:301`) — sets dirty and (re)starts a **750 ms** debounce; when it fires, the model is
  serialized on the UI thread and written on a background thread (`BackgroundSaveIfDirty`).
* `FlushIfDirty()` (`:312`) — if dirty, synchronous `Save()`.
* `Save()` (`:261`) — stamps `AppData.LastModified = DateTime.Now` (Local), serializes, queues the write
  behind any pending write, **blocks up to 15 s** for it; throws on failure (the callers in this subsystem
  do not catch — the app-level crash handler shows a dialog). Fires `Saved`.
* `Saved` → `MainWindow.OnRepoSaved` (`:1573`) → `ReconcileRecurrences()`: completing a recurring
  top-level task/procedure (Daily/Weekly/Monthly/Yearly) spawns its next occurrence (new ids, advanced
  deadline, range length and child deadlines shifted). Consequence here: ticking Done on a recurring
  top-level task in Calendar/Board creates a new task on the next save; the page shows it on its next
  refresh (the Windows pages are not refreshed by reconcile — only Tasks/Procedures lists are).
* Recurrence is **never projected** onto future dates in Calendar/Planner; only the materialised next
  occurrence (after completion) appears.

### 2.5 Right-click selection rule (`Views/BatchDoneMenu.cs` `RightClickSelect`)

On right mouse-down over a row/card: if that row is **not** already selected, clear the selection and
select just it; if it **is** selected, keep the whole (multi-)selection so the context-menu batch
actions apply to all selected. Used by Calendar and Board lists. Buckets' member list uses a simpler
rule (always select the clicked row, `BucketsPage.xaml.cs:173`).

---

## 3. FEATURE CHECKLIST

IDs are stable. Gaps are reserved for future additions within a page.
Ranges: Calendar 001–039, Board 040–079, Planner 080–139, Buckets 140–169, Map 170–199,
Shared/cross-cutting 200–239.

### 3.1 Calendar tab (`Views/CalendarPage.xaml`, `.xaml.cs`)

**VIEW-001 Layout.** Three columns: left panel fixed **320** wide, a **6**-wide `GridSplitter` (drag to
resize; width not persisted), right panel fills. Left panel (`Panel` bg, 1px `BorderB`, corner 4,
padding 8): header text **"Calendar"** (bold, 15, `Accent`) above a WPF `Calendar` month control
(`Cal`). Right panel: a header strip (`PanelAlt`, padding 8, bottom border) containing the title
`DayLabel` (bold 15 `Accent`) on the left and, on the right, `"Text:"` (muted) + **A-** + **A+** buttons +
five radio buttons; below it the schedule list `TaskGrid` (a `ListView`/`GridView`, font 15,
horizontal scrollbar disabled, rows padding 6, stretched content).

**VIEW-002 Initial title.** Before the first refresh `DayLabel` reads **"Schedule Matrix"** (it is
replaced on the first `Refresh`, which `Init` always performs).

**VIEW-003 Month calendar date selection.** Selecting a date in `Cal` (`SelectedDatesChanged`) re-runs
`Refresh()`. If no date is selected (WPF allows Ctrl+click deselect), `Refresh` uses Today. The calendar
control shows no per-day markers for items (plain month view). Initial selection on `Init`:
`Ui.CalendarSelectedDate ?? Today`.

**VIEW-004 View-mode radios.** Group "View": **"Day"** (default checked), **"Week"**, **"Month"**,
**"All Upcoming"**, **"Agenda"** (tooltip: *"All upcoming tasks grouped by day."*). Checking any radio
re-runs `Refresh()`. Mode string (`CalendarViewMode` getter, `:50-54`): `"Week"`, `"Month"`, `"All"`,
`"Agenda"`, else `"Day"`. On `Init` the persisted `Ui.CalendarViewMode` is matched exactly
(`"Week"`/`"Month"`/`"All"`/`"Agenda"`); anything else (null, unknown, `"Day"`) → Day.

**VIEW-005 Day view.** Rows whose working range covers the selected day `d` (`ScheduleRow.Covers(d)`:
`EffectiveStart.Date <= d.Date <= Deadline.Date`) — a ranged task shows on **every** day of its span,
a point item only on its deadline. Title: `"Schedule — {d:yyyy-MM-dd}"` (em dash U+2014, spaces around).

**VIEW-006 Week view.** `start = d − (int)d.DayOfWeek` (the Sunday on/before `d`), `end = start + 7`.
Interval overlap: rows with `EffectiveStart.Date < end.Date && Deadline.Date >= start.Date`.
Title: `"Schedule — week of {start:yyyy-MM-dd}"`.

**VIEW-007 Month view.** `monthStart = new DateTime(d.Year, d.Month, 1)`, `monthEnd = monthStart+1 month`.
Rows with `EffectiveStart.Date < monthEnd && Deadline.Date >= monthStart`. Title:
`"Schedule — {d:yyyy-MM}"`.

**VIEW-008 All Upcoming view.** Rows with `Deadline.Date >= Today || Covers(Today)` (the second clause is
subsumed by the first; effectively *deadline today or later*). **Past-due items are excluded even when
not done** — there is no overdue section on the Calendar. Done items are included. Title:
`"Schedule — all upcoming"`.

**VIEW-009 Ordering (Day/Week/Month/All).** `OrderBy(EffectiveStart).ThenBy(Deadline)` — full DateTime
comparison (time components participate; `EffectiveStart` of a ranged row is its start's `.Date`, of a
point row the raw `Deadline` value), stable over the enumeration order of §2.2. Flat list, no groups.

**VIEW-010 Agenda view.** Same filter as All Upcoming, then per-day **fan-out**: a non-ranged row yields
one occurrence (grouped by its deadline); a ranged row (`IsRanged`) yields one occurrence per covered day
from `max(EffectiveStart.Date, Today)` to `Deadline.Date` inclusive — unless that span is **more than 31
days** (`(to − from).TotalDays > 31`), in which case it yields a single occurrence on the deadline day.
Occurrences sorted by `GroupKey` (occurrence day, or deadline) then by `Name` (culture-sensitive default
string comparer), grouped by a day label: **"Today"**, **"Tomorrow"**, else `"{day:ddd, yyyy-MM-dd}"`
(culture day abbreviation, e.g. `"Thu, 2026-10-01"`; `"No date"` if null — unreachable). Group header:
label (bold 15 `Accent`) followed by `" ({count})"` (muted), on a `PanelAlt` strip with bottom border,
padding 8,5, top margin 4. Title: `"Agenda — upcoming by day"`.

**VIEW-011 Columns.** Headers and widths: **"Done"** 56 (checkbox, centred, top-aligned);
**"When"** 210 (`RangeDisplay`, wraps; tooltip *"Working range (start → deadline) when set, otherwise the
due date."*); **"Status"** 120 (semi-bold, wraps); **"Task"** 420 (`Name`, semi-bold, wraps,
**strikethrough when `IsComplete`**); **"Recurrence"** 110 (wraps). Columns are user-resizable/reorderable
(GridView default) but not persisted.

**VIEW-012 Row text per kind** (`ScheduleRow` factories, `:248-259`):

| Kind | Name (Task column) | When | Status | Recurrence | Done checkbox reflects / writes |
|---|---|---|---|---|---|
| Task / subtask | `t.Name` | `"yyyy-MM-dd → yyyy-MM-dd"` if ranged else `"yyyy-MM-dd"` | `t.Status` enum name: `Todo`, `InProgress`, `Blocked`, `Done` (no spaces) | `t.Recurrence` enum name incl. `"None"` | `t.IsComplete` |
| Procedure | `p.Name` | deadline `yyyy-MM-dd` | `p.Status` enum name | `p.Recurrence` enum name incl. `"None"` | `p.Status == Done`; tick → `Done`, untick → `Todo` |
| Procedure step | `"{s.Title}   ·  [{p.Name}]"` (3 spaces, U+00B7, 2 spaces; brackets even if the name is empty) | deadline | `"Done"` if `s.Done` else `"Step"` | `""` | `s.Done` |
| Crew checklist item | `"{s.Title}   ·  👤 {FullName}"`, `FullName` = non-blank First/Middle/Last joined by one space, or `"(unnamed)"` | deadline | `"Done"` / `"Step"` | `""` | `s.Done` |

The Status cell re-reads the **live** model after a Done toggle (it raises change for `Status`).

**VIEW-013 Inline Done toggle.** Clicking the checkbox writes through to the underlying item (table
above) and then persists **immediately** (`MarkDirty(); FlushIfDirty();`). Strikethrough and Status
update live. Mac requirement: update the model **first**, then save (the WPF event ordering may flush
before the binding writes back — see §9 Q-02).

**VIEW-014 Double-click to edit.** Double-click on a row (ignored on column headers,
`UiTree.FindAncestor<GridViewColumnHeader>`) opens, modally, the editor for the underlying item: task or
subtask → **Subtask editor** (`SubtaskEditorWindow`, title "Edit subtask — {name}"); procedure step or
crew item → **Checklist step editor** (`ChecklistStepEditorWindow`); procedure → **navigate** to it in the
Procedures tab (no editor, no refresh). After an editor closes: `FlushIfDirty()` then `Refresh()`.
WPF quirk: double-clicking empty list space re-opens the *currently selected* row; double-clicking the
Done checkbox toggles it twice and opens the editor.

**VIEW-015 Multi-select.** `SelectionMode="Extended"` (click, Ctrl+click, Shift+click, Ctrl+A).
Selection is lost on every refresh (the list is rebuilt).

**VIEW-016 Context menu** (built in `Init`, `:37-41`), acting on the selected rows' underlying items:
1. **"✓ Mark selected as done"**
2. **"○ Mark selected as not done"**
3. separator
4. **"📅 Set deadline for selected…"** (tooltip *"Give every selected item the same deadline (or clear
   it)."*)
Right-click selection follows §2.5. Behaviour of the entries: VIEW-200, VIEW-201.
Note: in Agenda the same item can be selected several times (one row per occurrence); the batch
services treat repeats as no-ops, but the deadline prompt's count text counts rows.

**VIEW-017 Text size stepper (A- / A+).** Buttons **"A-"** (tooltip *"Smaller list text"*) and
**"A+"** (tooltip *"Bigger list text"*), MinWidth 30. Step **±1.5**, clamped to **[11, 28]**; default
list size **15**. Each click sets `Ui.CalendarFontScale = size` and `MarkDirty()` (debounced save). On
`Init`, a stored value is applied only if `10 <= v <= 30` (note: wider than the stepper's clamp).
The size applies to the whole schedule list (all cells, and the count in Agenda headers; the Agenda
header label itself is fixed at 15). It does not refresh the list.

**VIEW-018 Ranged tasks across days.** A task/subtask with `RangeStart` (strictly before its deadline's
day) is "ranged": Day view shows it on each covered day; Week/Month use overlap; Agenda fans it out
(VIEW-010). An out-of-order range (`RangeStart > Deadline`, only possible via hand-edited/imported JSON)
degrades to a single-day point on the deadline (clamped, `ScheduleRow.EffectiveStart` `:200`).
`RangeStart` without a `Deadline` → the row is not created at all.

**VIEW-019 Overdue on the Calendar.** None: no colour, badge or section. Past-due items appear only in
Day/Week/Month views when the selected period covers them, never in All/Agenda.

**VIEW-020 Persistence of calendar UI state.** `Ui.CalendarSelectedDate` and `Ui.CalendarViewMode` are
written only by `CaptureUiState` (close/save/dirty autosave/exports), not on change;
`Ui.CalendarFontScale` on change. `CalendarSelectedDate` is **per-device** (never synced by Flash Sync);
`CalendarViewMode` and `CalendarFontScale` are shared preferences (travel key-by-key in `UiChanges`).

**VIEW-021 Refresh triggers.** Tab selected; date selected; mode changed; after an editor closes; after
a batch menu action; `Init` (data load/reload). Not refreshed when data changes in other windows while
the tab stays visible (e.g. the floating due window ticking an item) — the Mac may refresh live
(observation) without violating behaviour.

**VIEW-022 Dark mode.** List/headers follow the themed `ListViewItem`/`GridViewColumnHeader` styles
(selection `SelBg`/`SelFg`, hover `HoverBg`, 1px bottom row separator in `BorderB`). The month control is
"best-effort" dark on Windows.

### 3.2 Board tab (`Views/BoardPage.xaml`, `.xaml.cs`)

**VIEW-040 Header bar.** A bordered strip (`Panel`, 1px `BorderB`, corner 4, padding 10,8, bottom margin
6): **"Task Board"** (bold 16 `Accent`), then muted hint **"Drag cards between columns to set status"**
(left margin 14); right-aligned: **"Find:"** label, a text box (width 180), checkbox **"Hide done"**,
button **"+ From saved list"** (tooltip *"Search your saved lists and add items as real tasks"*),
button **"+ New task"** (AccentButton style = bold).

**VIEW-041 Columns.** Four equal-width columns (star widths), built once (`BuildColumns`, `:53`):

| # | Status (enum, JSON int) | Title | Header colour |
|---|---|---|---|
| 0 | `Todo` (0) | **"To Do"** | #546E7A |
| 1 | `InProgress` (1) | **"In Progress"** | #1E88E5 |
| 2 | `Blocked` (2) | **"Blocked"** | #E53935 |
| 3 | `Done` (3) | **"Done"** | #2E7D32 |

Each column: outer rounded box (`Panel` bg, 1px `BorderB`, corner 6; horizontal gap 3 between columns,
0 at the outer edges); header strip in the column colour (top corners 6, padding 10,6) with the title
(bold 14 white) on the left and a live **count** (bold, white, opacity 0.85) on the right; below, a
vertically scrolling list of cards (padding 6, no border, transparent). Colours are identical in light
and dark.

**VIEW-042 Every task and nested subtask is a card.** `FlattenTasks`/`WalkTasks` (`:164-181`): every
`TaskItem` in `Data.Tasks` and all descendants (depth-first pre-order), each placed in the column of its
**own** `Status` — a subtask lands in To Do regardless of deadline. A `HashSet<Guid>` of visited ids
guards against cycles and also suppresses a second item with a duplicate id. Card order within a column
= flatten order (no sorting, no manual ordering).

**VIEW-043 Card anatomy** (`CardTemplate` + `Card` class `:316-357`). Rounded box (`Panel` bg, 1px
`BorderB`, corner 6, bottom margin 8, hand cursor), a **6-px left stripe** in the column colour
(left corners 6), content margin 10,8, stacked:
1. **Parent path** (only for subtasks): `"↳ {path}"`, muted, 11.5, wraps, tooltip *"This card is a
   subtask; its parent path is shown here."* `path` = ancestor names from the top-level task down,
   joined by `" › "` (space, U+203A, space); a blank (whitespace-only) ancestor name is shown as
   `"(unnamed)"`.
2. **Name** — bold 15, wraps, **strikethrough when `IsComplete`**.
3. **Meta** (hidden if empty) — 12.5, wraps, top margin 4; colour #6B6B6B normally, **#D32F2F when
   overdue**. Parts joined by `"   ·   "` (3 spaces, U+00B7, 3 spaces):
   * if `Deadline` set: `"{RangeStart:yyyy-MM-dd} → {Deadline:yyyy-MM-dd}"` when
     `RangeStart.Date < Deadline.Date`, else `"Due {Deadline:yyyy-MM-dd}"`; plus `"  ·  OVERDUE"`
     (2 spaces, U+00B7, 2 spaces) when overdue;
   * if `Recurrence != None`: the enum name (`Daily`/`Weekly`/`Monthly`/`Yearly`).
   Overdue = `Deadline.Date < Today && Status != Done` (keyed on the deadline = range end; a task still
   inside its range is not overdue).
4. **Badges** (hidden if empty) — muted 12.5, top margin 3, parts joined by 4 spaces:
   `"📎 {n} file"`/`"📎 {n} files"` when the task's own container has n>0 files;
   `"☑ {done}/{total}"` over **direct** subtasks when total>0.

**VIEW-044 Search ("Find:").** Every keystroke re-runs `Refresh()` (no debounce). Query = trimmed text;
keeps cards whose `Name` contains it, **OrdinalIgnoreCase**. Parent path is not searched.

**VIEW-045 Hide done.** When checked, drops cards with `Status == Done` (so the Done column shows 0).
Neither Find nor Hide-done is persisted.

**VIEW-046 Column counts.** Count of cards currently shown in the column (after filters).

**VIEW-047 Drag a card to change status.** Press on a card and move beyond the system minimum drag
distance → drags **that one card** (not the multi-selection). Any column list accepts the drop (effect
Move for a card payload, None otherwise). On drop into a column whose status differs:
`task.Status = column status` (which also syncs `IsComplete`), `MarkDirty(); FlushIfDirty();`,
`Refresh()`. Dropping into the same column does nothing. No within-column reordering. Subtask cards
change only that subtask's status (parent unaffected).

**VIEW-048 Selection.** Each column list is `Extended` multi-select (per column; selections in different
columns are independent). **Windows quirk:** the card container style removes all selection chrome, so
selected cards look identical to unselected ones. Selection is lost on every refresh.

**VIEW-049 Double-click a card.** Opens the Subtask editor for the column's `SelectedItem` (modal); on
close `FlushIfDirty()`, `Refresh()`.

**VIEW-050 Card context menu** (one per column, `BuildCardMenu` `:119-136`), in order:
1. **"Open / edit task"** — acts on the column's `SelectedItem` (single) → VIEW-049 behaviour.
2. **"Open all files (routine)"** — single → VIEW-051.
3. separator
4. **"✓ Mark selected as done"**, 5. **"○ Mark selected as not done"** — all selected cards (VIEW-200).
6. **"📅 Set deadline for selected…"** — all selected cards (VIEW-201).
7. separator
8. **"Delete task"** — single → VIEW-052.
Right-click selection per §2.5.

**VIEW-051 Open all files (routine).** For the card's task (its **own** container only):
* no files → info box: **"This task has no files yet. Open the task and add some to the file bank."**
  title **"Open all files"**.
* more than 15 files → Yes/No question: **"Open all {n} files for '{name}'?"** title
  **"Open all files"**; No aborts.
* for each file: target = `Path` if `IsLink` (web URL) else `DataStore.ResolveFilePath(Path)` (relative
  `files/…` resolved under the data folder; rooted/in-place paths returned verbatim); a non-link whose
  target exists neither as file nor directory is **skipped silently**; otherwise shell-open it. Any
  exception is swallowed and the loop continues.

**VIEW-052 Delete task (hard delete).** Confirmation (Yes/No, question icon), title **"Confirm"**, text
`"Delete task '{name}'?"` plus, when it has descendants, `"\n\nThis also deletes its {n} subtask(s)."`
where n = all descendants recursively. On Yes: remove the task from wherever it lives
(`RemoveTaskAnywhere`: top-level collection or any nested `Subtasks`, first match by reference),
`PurgeReferences(task.Id)` (only the task's own id — descendants' ids are **not** purged), `Save()`,
`Refresh()`. **This bypasses the Trash** (not restorable, not undoable with Ctrl+Z) and writes **no
activity-log entry** — documented as deliberate-pending-decision in PROGRESS ("Board and Ctrl+N quick
window delete tasks hard").

**VIEW-053 + New task.** Prompt dialog title **"New Task"**, label **"Name:"** (empty initial). If OK
and the text is not blank/whitespace: append `new TaskItem { Name = <text as typed, not trimmed>,
Status = Todo }` to `Data.Tasks`, `Save()`, `Refresh()`. No activity-log entry.

**VIEW-054 + From saved list.** Runs the shared saved-list picker (VIEW-202); if any tasks were created,
`Refresh()`. The new tasks appear as To Do cards.

**VIEW-055 Refresh triggers.** Tab selected; Find text change; Hide-done toggle; after drop, editor
close, batch actions, new task, saved-list add, delete; `Init`.

**VIEW-056 Board shows tasks only.** Procedures, steps and crew items never appear on the Board.

### 3.3 Planner tab (`Views/PlannerPage.xaml`, `.xaml.cs`)

**VIEW-080 Header bar.** Strip like the Board's: **"Planner"** (bold 16 `Accent`), a muted range label
(`RangeLabel`, left margin 14); right-aligned: **"◀"** (MinWidth 34), **"Today"**, **"▶"** (MinWidth 34,
right margin 12), radios (group "PV") **"Day"** (default), **"Week"**, **"Month"**. Mode is **not**
persisted (always Day, anchored on Today, after every `Init`).

**VIEW-081 Navigation.** "◀"/"▶" move the anchor by 1 day (Day), 7 days (Week) or 1 calendar month
(Month, `AddMonths` — day clamped, e.g. Jan 31 → Feb 28/29). "Today" resets the anchor to Today (mode
kept). Each triggers `Refresh()`. Changing the mode radio re-renders around the current anchor.

**VIEW-082 Range label.** Day: `"{anchor:dddd, yyyy-MM-dd}"` (culture weekday name, e.g.
`"Tuesday, 2026-09-29"`). Week: `"Week of {sunday:yyyy-MM-dd}"`. Month: `"{anchor:MMMM yyyy}"`
(culture month name, e.g. `"September 2026"`).

**VIEW-083 Left panel: Unscheduled Jobs.** Fixed width 230, then a 6-wide splitter, then the grid host.
Header strip (`PanelAlt`, padding 8,6): **"Unscheduled Jobs"** (bold) with a right-docked button
**"+ Saved list"** (padding 6,1; tooltip *"Search your saved lists and add items as real, schedulable
tasks"*). Below: a search box (tooltip *"Filter the schedulable jobs by name."*; intended placeholder
**"Search jobs..."** — stored in `Tag`, which the WPF theme never renders, so on Windows the box shows
no placeholder); at the bottom a muted wrapping hint: **"Drag a job onto the grid to schedule it. Drag a
scheduled block back here to unschedule. Double-click to edit."**

**VIEW-084 Unscheduled pool contents.** `AppRepository.AllJobs()` (every `IsJob` top-level task, nested
subtask, procedure, procedure step and crew checklist item) filtered to those with **no
`ScheduledStart` and no `Deadline`**, then by the search text (trimmed; `JobName` contains query,
OrdinalIgnoreCase). Done items are not excluded. Row text: `"{JobName}   ·   {DurFmt(DurationMinutes)}"`
(3 spaces, U+00B7, 3 spaces), no wrap. Order = `AllJobs` enumeration order. Search re-filters on each
keystroke (does not rebuild the grid).

**VIEW-085 Placement rule ("deadline-aware").** `_placed` = every schedulable item
(`AllSchedulable()`: all tasks+subtasks, procedures, procedure steps, crew items — **not** only jobs)
with `ScheduledStart ?? Deadline != null`. An item with `ScheduledStart` is **timed** (hour grid / month
`HH:mm` chip) and never appears in the due strip even if it also has a deadline. An item with only a
`Deadline` is **due-only** (all-day strip / month `•`/range chip).

**VIEW-086 Due span.** `DueSpan(j)` (`:73-80`): `end = Deadline.Date`; `start = RangeStart.Date` if the
item is a `TaskItem` with `RangeStart` and `RangeStart.Date <= end`, else `end`. Procedures, steps and
crew items are always single-day points.

**VIEW-087 Day/Week time grid structure** (`BuildTimeGrid`, `:150-283`). Three rows: (1) sticky day-name
header, (2) all-day "due" strip, (3) scrollable hour grid. Day column width **700** in Day view, **132**
in Week view; gutter **52**; hour height **46**; hours **00–24** (total height 24×46 = **1104**).
Week view shows the 7 days Sunday→Saturday of the anchor's week.

**VIEW-088 Day-name header.** Blank gutter cell, then per day: Day view `"{d:dddd, MMM d}"`
(e.g. `"Tuesday, Sep 29"`), Week view `"{d:ddd}\n{d:MMM d}"` (two lines, e.g. `"Tue"` / `"Sep 29"`),
centred, padding 2,4; **today** bold in `Accent`, other days normal `Fg`.

**VIEW-089 All-day ("due") strip.** Background `PanelAlt`, bottom 1-px line (#22808080). Gutter cell
label **"due"** (font 10, muted, right-aligned, margin 0,5,6,0). Per day: vertical stack (margin 3) of
chips for every due-only item whose `DueSpan` covers that day, ordered by span start, then `JobName`
(OrdinalIgnoreCase); the stack scrolls vertically when taller than **108**.

**VIEW-090 All-day chip.** Rounded (3) block, padding 6,2, bottom margin 3, hand cursor; background
#6B7785 if the item is a **completed `TaskItem`**, else #1E88E5 (procedures/steps are never greyed —
see §9); text white, 11, **wraps**; text = `RangeGlyph + JobName`; bold when multi-day and this is the
deadline day; opacity **0.6** on non-deadline days of a multi-day span ("ghost"), else 1.0. Tooltip per
VIEW-099. Draggable with its **anchor day** (VIEW-101). Double-click opens the editor (VIEW-104).

**VIEW-091 Range glyphs** (`RangeGlyph`, `:490-496`): single-day item `"• "`; multi-day: deadline day
`"⚑ "`, start day `"▸ "`, middle days `"· "`.

**VIEW-092 Hour gutter.** Labels `"00:00"` … `"24:00"` (25 labels, `{h:00}:00`), font 11 muted, left 6,
top = `h×46 − 7`.

**VIEW-093 Day canvases.** One per day, height 1104, width = day width; background `PanelAlt` when the
day is Today, else transparent; horizontal 1-px lines (#22808080) at every hour 0…24; a 1-px vertical
separator at `x = width−1`. Each canvas accepts drops (VIEW-100).

**VIEW-094 Initial scroll.** When the hour grid first loads, it scrolls vertically to **07:00**
(offset 7×46 = 322). Horizontal scrolling of the body is independent (Windows quirk: the header and due
strip do not scroll horizontally with the body when the week is wider than the pane — the Mac must keep
them aligned).

**VIEW-095 Timed blocks** (`AddBlock`, `:323-362`). Items with `ScheduledStart.Date == day`.
`top = minutes since that day's midnight / 60 × 46`; `height = max(20, max(15, Duration)/60 × 46)`;
rounded 4, clipped, hand cursor; background #6B7785 if completed `TaskItem`, else #1E88E5. Content
(margin 5,3): `JobName` (white, bold 12, character ellipsis) and, only when `height >= 34`, a second line
`"{start:HH:mm}–{end:HH:mm}  ({DurFmt})"` (white, 10, opacity 0.9; en dash U+2013; 2 spaces before the
parenthesis). Tooltip: `"{JobName}\n{start:HH:mm}–{end:HH:mm} ({DurFmt})\nDrag to move • double-click
to edit"`. `end = start + max(15, Duration)` minutes. A block that runs past 24:00 is drawn only on its
start day and overflows the canvas bottom (effectively truncated).

**VIEW-096 Overlap layout.** Blocks in a day are clustered (transitively overlapping) and each cluster is
split into side-by-side columns (greedy first-fit). Algorithm §4.3.4. Block width
`max(24, colWidth − 3)`, left `col × colWidth + 1`, `colWidth = (dayWidth − 2) / columnsInCluster`.

**VIEW-097 Month grid** (`BuildMonth`, `:365-431`). 7 equal columns, a header row **"Sun" "Mon" "Tue"
"Wed" "Thu" "Fri" "Sat"** (hard-coded English, bold, centred, padding 4), then **6 rows** (42 days)
starting on the Sunday on/before the 1st. Cell: 0.5-px `BorderB` border, background `PanelAlt` when
Today; inner margin 3; day number at top (bold if Today; `Fg` in the anchor month, else `Muted` at
opacity 0.5); below, a vertically scrolling list of chips. Out-of-month cells still show chips and
accept drops.

**VIEW-098 Month chips** (`MakeChip`, `:433-459`). For each placed item on that cell: timed items whose
`ScheduledStart.Date` is the cell date; due-only items whose `DueSpan` covers the cell date. Order:
timed first, then by `ScheduledStart` (due-only use `DateTime.MinValue`, so among due-only chips only
the name orders), then `JobName` OrdinalIgnoreCase. Chip: rounded 3, top margin 2, padding 4,1, hand
cursor; background as VIEW-090; text white 11, **no wrap, character ellipsis**; timed text
`"{HH:mm} {JobName}"`; due-only text `RangeGlyph + JobName`, bold on the deadline day of a multi-day
span, opacity **0.55** on other span days. Tooltip VIEW-099. Draggable (timed: no anchor; due-only:
anchor = cell date). Double-click opens the editor.

**VIEW-099 Chip tooltips** (`ChipTip`, `:498-507`):
* timed: `"{JobName}\n{ScheduledStart:HH:mm} ({DurFmt})"`;
* multi-day `TaskItem` range: `"{JobName}\n{RangeStart:yyyy-MM-dd} → {Deadline:yyyy-MM-dd}  ({m} days)\n
  Drag in Month to move the whole range • double-click to edit"` with `m` = inclusive day count
  (`(deadline − start).TotalDays + 1`);
* otherwise: `"{JobName}\ndue {Deadline:yyyy-MM-dd} (no time)\nDrag onto the grid to give it a time •
  double-click to edit"`.
(The literal `\n` are newlines; there is no newline inside "Drag … edit".)

**VIEW-100 Drop on a Day/Week hour canvas** (`DayCanvas_Drop`, `:561-577`). Minutes from the drop
pointer's y: `round(y / 46 × 60 / 15) × 15` using **banker's rounding** (`Math.Round` default,
half-to-even), clamped to `[0, 1425]` (23:45). Sets `ScheduledStart = day + minutes` (the block's **top**
goes where the pointer is; no grab-offset). If the job is a `TaskItem` **with `RangeStart`**: if it has a
deadline and `day > Deadline.Date` → `Deadline = day`; if `day < RangeStart.Date` → `RangeStart = day`
(extends the window so the scheduled day is inside it). Then save+refresh (VIEW-106). Works for any
source: unscheduled row, timed block (move/reschedule, including to another day in Week view), or an
all-day chip (gives it a time; the deadline is kept, so dragging it back to the pool later returns it to
the strip).

**VIEW-101 Drop on a Month cell** (`MonthCell_Drop`, `:579-613`).
* Timed job (`ScheduledStart != null`): keep time-of-day, move to the cell date. (No range extension.)
* Else a `TaskItem` with **both** `RangeStart` and `Deadline` (including single-day ranges): slide the
  whole window by `delta = cellDate − anchorDay` (anchor carried by the dragged chip):
  `RangeStart = RangeStart.Date + delta`, `Deadline = Deadline.Date + delta` (length preserved). If no
  anchor is present (not reachable from the UI): `Deadline = cellDate`, `RangeStart = cellDate −
  (oldDeadline.Date − oldRangeStart.Date)`.
* Else (point item — task without range, procedure, step, crew item, **including an unscheduled job
  dragged from the pool**): `Deadline = cellDate` (becomes a due-only chip).
Then save+refresh.

**VIEW-102 Drop on the Unscheduled list** (`Unscheduled_Drop`). Sets `ScheduledStart = null`, then
save+refresh. Non-destructive for deadlines: an item that has a deadline returns to the due strip/month
chip rather than to the pool (the pool only lists items with neither).

**VIEW-103 Drag sources and payload.** Timed blocks, month chips, all-day chips and pool rows are drag
sources (system minimum drag distance). Payload: the job object (`"AAJob"`) plus, for due-only chips, the
day the chip represents (`"AAJobDay"`). Drag effect Move; any target shows Move only when an `"AAJob"`
payload is present.

**VIEW-104 Double-click to edit.** On a block/chip (second click of a double-click on mouse-down) or a
pool row: `TaskItem` → Subtask editor; `ChecklistStep` (procedure step or crew item) → Checklist step
editor; **`Procedure` → nothing opens** (still flush+refresh). After the dialog: `FlushIfDirty()`,
`Refresh()`.

**VIEW-105 + Saved list.** Shared picker (VIEW-202); on any creation → `Refresh()`. The created tasks
carry the template item's `IsJob`/duration, so schedulable items land in the pool (they have no date).

**VIEW-106 Save after every planner mutation.** `Save()` helper (`:640`): `MarkDirty(); FlushIfDirty();
Refresh();` — i.e. an immediate synchronous save (even when a drop changed nothing, e.g. dropping an
already-unscheduled item on the pool).

**VIEW-107 Refresh triggers.** Tab selected, navigation, mode change, every drop, editor close,
saved-list add, `Init`. `Refresh` rebuilds the whole grid (no incremental updates).

**VIEW-108 Durations.** `DurFmt` (`:509-514`): `< 60` → `"{m}m"` (includes 0 and negatives, e.g.
`"0m"`), else `"{h}h"` or `"{h}h {m}m"`. Layout always uses `max(15, Duration)` minutes. Duration is
edited only in the item editors (positive integers only there); default 60.

**VIEW-109 Dark mode.** Block/chip colours are fixed (#1E88E5 / #6B7785, white text) in both themes;
grid lines #22808080 (13 % grey) in both; header/gutter text follows `Fg`/`Muted`/`Accent`; today tint
`PanelAlt` is invisible in light mode on Windows.

### 3.4 Buckets tab (`Views/BucketsPage.xaml`, `.xaml.cs`)

**VIEW-140 Layout.** Left panel fixed 340 wide, 6-wide splitter, right panel fills.

**VIEW-141 Left header and help.** Header strip (`PanelAlt`): **"🪣 Buckets"** (bold 15 `Accent`). Muted
wrapping help text: **"Predefine buckets here — a location, a rank, a department, anything. Then sort
tasks & procedures into up to two of them (in the Ctrl+N quick-work window)."** Toolbar (wrap panel):
**"+ New bucket"** (accent), **"Rename"**, **"Set category..."** (tooltip *"Label what this bucket
represents (Location, Rank, ...). Buckets are grouped by category."*), **"Delete"**.

**VIEW-142 Bucket list.** Single-select list, grouped by **category**; group header = category name
(bold, `Accent`) + `" ({count})"` (muted) on a `PanelAlt` strip (padding 6,3, margin 0,4,0,2). Empty
category → group **"(Uncategorised)"**, always sorted last. Sorting: by category lower-cased (culture
compare), then by display name (culture compare). Grouping is by the **exact** category string
(case-sensitive), so "Location" and "location" form two groups that sort adjacent. Row: display name
(semi-bold, wraps; empty name → **"(unnamed)"**) and, right-aligned, `"{n} items"` (muted, 11; always
the plural word, e.g. `"1 items"`).

**VIEW-143 Item count per bucket.** Number of bucketable items whose `BucketIds` contains the bucket id,
over: all tasks and nested subtasks, all procedures and their steps. Crew checklist items are not
counted/listed.

**VIEW-144 Status line** (bottom, muted, wraps): no buckets → **"No buckets yet. Click “+ New bucket” to
define one (e.g. name “Engine room”, category “Location”)."** (curly quotes U+201C/U+201D); otherwise
`"{n} bucket(s)."`.

**VIEW-145 Selection persistence across refresh.** Refresh re-selects the previously selected bucket by
id (not persisted across launches).

**VIEW-146 Right panel (members).** Margin 10. Header (16 bold, wraps): when nothing selected **"Select a
bucket to see the tasks & procedures in it."**; otherwise
`"🪣 {name or (unnamed)}" + ("  ·  {category}" if category) + "   —   {n} item(s)"`. Muted sub-line:
**"Double-click an item to open it. Right-click to remove it from this bucket."** Member list (wrapping
rows): `"[{Kind}]  {Name}"` or, when it has a parent, `"[{Kind}]  {Name}   —   in {Parent}"`.
Kinds: **"Task"**, **"Subtask"** (parent = immediate parent task's raw name), **"Procedure"**,
**"Checklist step"** (parent = procedure's raw name). Empty names show **"(unnamed)"** (the parent name is
raw and may be empty). Sorted by Kind then Name, both OrdinalIgnoreCase (so order: Checklist step,
Procedure, Subtask, Task).

**VIEW-147 + New bucket.** Prompt 1: title **"New bucket"**, label **"Bucket name (e.g. a location or a
rank):"**. Cancel or blank → abort. Prompt 2: title **"Category (optional)"**, label **"What does it
represent? (e.g. Location, Rank) — leave blank for none:"** (cancel = no category; the bucket is still
created). Creates `QuickBucket { Name = trimmed name, Category = trimmed category }`, appends to
`Data.QuickBuckets`, logs `LogAdded("Bucket", name, category)`, `Save()`, `Refresh()`, selects the new
bucket and scrolls it into view.

**VIEW-148 Rename.** Requires a selection, else info box **"Select a bucket first."** title
**"Buckets"**. Prompt title **"Rename bucket"**, label **"New name:"**, pre-filled; OK with non-blank →
`Name = trimmed`, `Save()`, `Refresh()`. (Blank → no change.)

**VIEW-149 Set category.** Requires selection (same info box). Prompt title **"Set category"**, label
**"Category (e.g. Location, Rank) — blank clears it:"**, pre-filled; OK → `Category = trimmed` (blank
clears), `Save()`, `Refresh()`.

**VIEW-150 Delete bucket.** Requires selection. Warning Yes/No, title **"Delete bucket"**, text
`"Delete bucket '{Name}'? "` + (when it has members) `"Its {n} item(s) will be removed from it (the items
themselves are kept)."` (raw name; note the trailing space when there are no members). On Yes: remove
the bucket id from every member's `BucketIds`, remove the bucket, `LogRemoved("Bucket", name)`,
`Save()`, `Refresh()`.

**VIEW-151 Open member.** Double-click (anywhere in the list — Windows quirk: opens the selected row) or
context menu **"Open"**: Kind Task/Procedure → navigate to it in its tab (`Navigate` callback); Subtask →
Subtask editor (modal) then `FlushIfDirty()` + `Refresh()`; Checklist step → Checklist step editor then
`FlushIfDirty()` + `Refresh()`.

**VIEW-152 Remove member.** Context menu **"Remove from this bucket"**: removes the selected bucket's id
from that item's `BucketIds`, `Save()`, `Refresh()`. No confirmation. Right-click first selects the row
under the pointer.

**VIEW-153 Up to two buckets per item, at every level** (assignment UI is in the Ctrl+N quick-work
window — `QuickWorkWindow.xaml.cs:468` `SortIntoBuckets`; spec'd with that window, summarised here for the
contract). Applies to any `IBucketable`: task, subtask, procedure, checklist step. No buckets defined →
info **"No buckets are defined yet. Open the Buckets tab to create some (e.g. a location or a rank)."**
title **"Sort into buckets"**. Otherwise a multi-select picker titled
`"Sort '{label}' into buckets (pick up to 2)"` listing `QuickBucket.Display` (`"{Name}  ·  {Category}"`
or the name / `"(unnamed)"`), pre-selecting current buckets. More than two picked → info **"An item can be
in at most two buckets — keeping the first two you picked."** and keep the first two **in list order**;
then `BucketIds` is replaced (clear + add), `Save()`. "Remove from bucket" clears all. The cap is a UI
rule only — the model/JSON can hold more (e.g. merged data) and every page shows all of them.

**VIEW-154 Legacy migration.** Older saves have a single `"BucketId"` on tasks/procedures; on load its
value is **added** to `BucketIds` if not already present; `BucketId` is never written back.

**VIEW-155 Refresh triggers.** Tab selected; after every action above; `Init`.

### 3.5 Relationship Map tab (`Views/RelationshipMapPage.xaml`, `.xaml.cs`)

**VIEW-170 Layout.** Left panel 260 wide (header **"Inspect"** bold 15 `Accent` on `PanelAlt`; a search
box, margin 6; the item list), 6-wide splitter, right panel: header (`MapTitle`, bold 15 `Accent`) and a
scroll view (both scrollbars auto, background `Bg`) containing a fixed **1400 × 900** canvas
(background `Bg`).

**VIEW-171 Inspect list.** All top-level items in `AllItems()` order — Equipment, then Tasks, then
Procedures, then Vessels (collection order, unsorted; no subtasks/steps). Row text
`"[{Kind}] {Name}"` with the **enum** kind name: `Equipment`, `Task`, `Procedure`, `Vessel` (note:
"Equipment", not "Equipment/Area").

**VIEW-172 Search.** On every keystroke: trimmed query; keep rows whose display text contains it,
OrdinalIgnoreCase (so `"task"` matches every `"[Task] …"` row). Re-filtering clears the list selection
but leaves the map as drawn.

**VIEW-173 Select to inspect.** Selecting a row draws the map centred on that item (VIEW-175). Re-
selecting the same item redraws.

**VIEW-174 Title.** `"Relationship Map"` before anything is drawn; then `"Relationship Map — {centre
name}"` (em dash).

**VIEW-175 Graph content.** Nodes = centre + `RelatedItems(centre)` (1-hop): the centre's `RelatedIds`,
plus, when the centre is Equipment, its `ProcedureIds` and `TaskIds`; ids resolved among top-level items
(unresolvable ids dropped); deduplicated. Incoming one-way links (e.g. a task that an equipment points to)
are **not** shown on that task's map; nothing deeper than 1 hop (the brief's "sub-hierarchy" traversal is
not implemented).

**VIEW-176 Layout.** Centre at canvas centre (700, 450). Related nodes on a circle of radius
`min(700, 450) − 140 = 310`, node *i* of *n* at angle `2π·i/n` (i = 0 at 3 o'clock, increasing
**clockwise on screen** since y grows downward). Nodes are centred on their point using their measured
size. No collision avoidance; many neighbours overlap.

**VIEW-177 Edges.** Drawn beneath nodes: centre→each related: solid line, `Accent` brush, thickness 1.5,
opacity 0.65. Between related nodes i<j when `related[i].RelatedIds` contains `related[j].Id` (one
direction checked; Equipment `ProcedureIds/TaskIds` not considered): dashed [4,3], `Muted` brush,
thickness 1, opacity 0.6. Brushes are captured at draw time (a theme switch does not recolour an
existing drawing).

**VIEW-178 Node style (actual code).** Rounded rectangle (radius 8), **white fill, black border** (3 px
for the centre, 1 px otherwise), padding 10,6, hand cursor; two lines: kind enum name (size 10, black)
and item name (bold, black, default size, **no wrapping**, so long names make wide nodes). Same in dark
mode (white boxes on the dark `Bg`). **PROGRESS.md** claims colour-coding by kind (Equipment #4FC3F7,
Task #FFB74D, Procedure #A5D6A7); the code never implemented it — see §6.5 for the Mac decision.

**VIEW-179 Click to recentre.** Releasing the left mouse button on any node (including the centre)
redraws the map centred on that node. The Inspect list selection is **not** updated (Windows quirk).

**VIEW-180 Focus persistence.** `FocusedItemId` = current centre's id, written to `Ui.MapFocusedItemId`
by `CaptureUiState`. On `Init`, if that id resolves (`FindById` over top-level items), the page selects it
in the list and draws it. `MapFocusedItemId` is per-device (never synced).

**VIEW-181 Staleness.** Switching to the tab only rebuilds the sidebar; the drawing is not redrawn, so
relationship edits made elsewhere show only after re-selecting. After a data reload, `Init` redraws the
persisted focus against the new data.

**VIEW-182 No other interactions.** No drag of nodes, no zoom, no context menu, no keyboard shortcuts; no
external "show in map" entry points (the public `FocusOn` is called only from `Init`).

### 3.6 Shared / cross-cutting

**VIEW-200 Batch mark done / not done** (`BatchDoneMenu.Apply` → `BatchDone.SetDoneAll`): evaluates the
selection at click time; applies §2.3 semantics to each item; if **any** changed →
`MarkDirty(); FlushIfDirty();`; always calls the page's refresh.

**VIEW-201 Batch set deadline** (`BatchDeadlineMenu.Apply` → `BatchDeadline.SetDeadlineAll`):
* empty selection → info **"Select one or more items first, then set the deadline."** title
  **"Set deadline"**;
* otherwise the date dialog (VIEW-203) titled **"Set deadline"** with prompt
  `"Apply one deadline to {n} selected item"` + (`"s"` if n≠1) + `":"`, pre-filled with the deadline iff
  all selected items share exactly one distinct deadline value (null counts as a value);
* OK → date (`.Date`) or null (Clear); per item: task — null clears **both** `Deadline` and
  `RangeStart`; a date runs `WorkRange.Coerce(RangeStart, date, editedStart:false)` (start later than
  the new deadline is clamped onto it); procedure/step — set/clear `Deadline`; counts only real changes;
  any change → `MarkDirty(); FlushIfDirty();`; always refresh.

**VIEW-202 Add tasks from saved lists** (`Views/SavedListPicker.cs`, used by Board and Planner):
* no saved lists → info **"You have no saved lists yet. Build one in the Saved Lists tab first."** title
  **"Add from saved list"**;
* lists exist but no items → info **"Your saved lists don't have any items yet."** (same title);
* otherwise a searchable multi-select picker, prompt **"Search saved lists — pick items to add as
  tasks"**, one row per item of every list (lists in `ChecklistTemplates` order, items in order):
  `"{list name or (unnamed list)}  ›  {item title or (untitled)}"` + `"   · schedulable"` when
  `IsJob` (2 spaces, U+203A, 2 spaces);
* OK → each picked item becomes a new top-level task via `ChecklistTemplateService.ItemToTask`:
  `Name = Title`, `DurationMinutes`, `IsJob`, `Status = Todo`, `Container = CloneContainer(item.Container)`
  (rich text XAML copied verbatim, `IsLocked` copied, each file cloned with the **same stored path**
  (no physical copy) but a new file id, `LinkedItemIds` copied, `SharedWithContainerIds` copied, new
  container id); no deadline/range/done. Appended to `Data.Tasks` in pick order; one `Save()` if any.
  The saved lists are not modified. No activity-log entries.
* Picker quirk (Windows): typing in its search box replaces the list and drops earlier selections; only
  items selected in the final filtered view are returned.

**VIEW-203 Date dialog** (`DatePromptWindow`, 420×200, not resizable): title and bold heading = title,
wrapping prompt, a date picker (pre-filled), buttons **"Clear deadline"** (tooltip *"Remove the deadline
from every selected item."*), **"Cancel"**, **"OK"** (default). OK with no date → info **"Pick a date, or
use "Clear deadline" to remove it."** title **"Set deadline"** (stays open). Clear → result null. Both OK
and Clear close with success.

**VIEW-204 Text prompt dialog** (`PromptWindow`, 440×170, not resizable): bold title, label, single-line
text box (pre-filled, focused, all selected), **"Cancel"**, **"OK"** (default = Enter). Esc does not
cancel on Windows (no IsCancel button) — the Mac sheet should accept Esc as Cancel.

**VIEW-205 Navigate to item.** Calendar (procedure rows) and Buckets (top-level Task/Procedure members)
call the main window's navigator: switch to the item's kind tab and select the item in its list. Mac:
switch by tab identity (not index), select, scroll into view.

**VIEW-206 Editors opened from these pages** (owned by other specs): Subtask editor (tasks/subtasks),
Checklist step editor (procedure steps and crew items). They edit the live model (no Cancel/rollback),
debounce-save each change, flush on close. The calling page then calls `FlushIfDirty()` and refreshes.

**VIEW-207 Reload behaviour.** Every data reload/import/shared pull calls `Init` on all five pages with the
new repository. The Mac must re-point every page at the new store and discard all held model references
(resolve by id).

---

## 4. LOGIC & ALGORITHMS

### 4.1 Calendar (`Views/CalendarPage.xaml.cs`)

**4.1.1 `Init(repo, navigate)` — `:20-44`.** Stores repo/navigator; `Cal.SelectedDate =
Ui.CalendarSelectedDate ?? DateTime.Today`; checks the radio for `Ui.CalendarViewMode`; applies
`Ui.CalendarFontScale` if `10 <= v <= 30`; builds a **new** context menu bound to *this* repo
(BatchDone items without leading separator, then BatchDeadline with its separator); `Refresh()`.

**4.1.2 `SetFontSize(size)` — `:61-66`.** `size = clamp(size, 11, 28)`; apply; `Ui.CalendarFontScale =
size`; `MarkDirty()`. Called with `current ± 1.5`.

**4.1.3 `Refresh()` — `:68-147`.**
```
rows = []
for t in Data.Tasks: for ft in Flatten(t) (pre-order): if ft.Deadline != nil: rows += ForTask(ft)
for p in Data.Procedures:
    if p.Deadline != nil: rows += ForProcedure(p)
    for s in p.Steps: if s.Deadline != nil: rows += ForStep(s, p)
for c in Data.Crew: for s in c.Checklist: if s.Deadline != nil: rows += ForCrewStep(s, c)
d = Cal.SelectedDate ?? Today
switch mode:
  Day:    filtered = rows.filter { $0.covers(d) };                               title "Schedule — d"
  Week:   start = d - weekday(d) days (Sun=0); end = start+7
          filtered = rows.filter { $0.effectiveStart.day < end.day && $0.deadline.day >= start.day }
  Month:  ms = first of d's month; me = ms + 1 month
          filtered = rows.filter { $0.effectiveStart.day < me && $0.deadline.day >= ms }
  Agenda, All: filtered = rows.filter { $0.deadline.day >= today || $0.covers(today) }
if Agenda:
    occ = []
    for r in filtered:
        if !r.isRanged { occ += r; continue }
        from = max(r.effectiveStart.day, today); to = r.deadline.day
        if (to - from) > 31 days { occ += r.at(to); continue }
        for day in from...to: occ += r.at(day)
    list = stableSort(occ, by: groupKey asc, then name asc [culture compare])
    grouped by label(groupKey)
else:
    list = stableSort(filtered, by: effectiveStart asc, then deadline asc)
```
Note for `Month`: the comparison `EffectiveStart.Date < monthEnd` uses `monthEnd` at midnight (same
thing as `.Date`).

**4.1.4 `ScheduleRow` — `:187-260`.** Immutable wrapper `{Item, Name, Deadline, RangeStart, Recurrence,
OccurrenceDate, _isComplete, _apply}`.
* `EffectiveStart` = `RangeStart.Date` if `RangeStart` and `Deadline` both set and
  `RangeStart.Date <= Deadline.Date`, else **raw `Deadline`** (may carry a time).
* `IsRanged` = both set and `RangeStart.Date < Deadline.Date`.
* `Covers(day)` = `Deadline != nil && EffectiveStart.Date <= day.Date && Deadline.Date >= day.Date`.
* `RangeDisplay` = ranged ? `"{RangeStart:yyyy-MM-dd} → {Deadline:yyyy-MM-dd}"` : `"{Deadline:yyyy-MM-dd}"`
  (`→` U+2192 surrounded by single spaces).
* `GroupKey` = `OccurrenceDate ?? Deadline`.
* `Status` computed live from `Item` (task/procedure enum name; step `"Done"`/`"Step"`).
* `IsComplete` setter: if changed → store, call `_apply(value)`, notify `IsComplete` and `Status`.
* `AtOccurrence(day)` copies the row (sharing `_apply`, copying the current `_isComplete` snapshot) with
  `OccurrenceDate = day.Date`. Consequence: toggling Done on one Agenda occurrence doesn't update sibling
  occurrences of the same item until refresh.
* Only tasks carry `RangeStart`; procedure/step/crew rows pass null.

**4.1.5 `DateGroupConverter` — `:263-279`.** `DateTime → day = dt.Date`; `== Today` → `"Today"`;
`== Today+1` → `"Tomorrow"`; else `day.ToString("ddd, yyyy-MM-dd")` in the current culture; non-date →
`"No date"`.

**4.1.6 `TaskDone_Toggled` — `:156-161`.** `MarkDirty(); FlushIfDirty();` (immediate save).

**4.1.7 `TaskGrid_DoubleClick` — `:163-179`.** Header guard; kind dispatch (VIEW-014); after an editor:
`FlushIfDirty(); Refresh();` (procedure: navigate and return without refresh).

### 4.2 Board (`Views/BoardPage.xaml.cs`)

**4.2.1 `Refresh()` — `:138-160`.** `q = SearchBox.Text.Trim()`; `flat = FlattenTasks()`; if `q` non-empty
keep `Name.Contains(q, OrdinalIgnoreCase)`; if Hide done keep `Status != Done`; per column:
`cards = flat.filter { status == column }` → new `Card` objects (all view state rebuilt), count label.

**4.2.2 `WalkTasks(t, parentPath, seen)` — `:171-181`.**
```
if !seen.insert(t.Id): return
yield (t, parentPath)
seg = t.Name.isBlank ? "(unnamed)" : t.Name
childPath = parentPath.isEmpty ? seg : parentPath + " › " + seg
for st in t.Subtasks: WalkTasks(st, childPath, seen)
```
`seen` is shared across the whole board (one set per refresh).

**4.2.3 `Card` — `:316-357`.** Meta/overdue/badges exactly as VIEW-043. `Parent = "↳ " + path` when path
non-empty. `Done` binds `IsComplete` for the strike.

**4.2.4 Drag — `:268-306`.** Threshold = `SystemParameters.MinimumHorizontalDragDistance` /
`MinimumVerticalDragDistance` (both 4 px by default) from the last left-button-down position (window
coordinates); payload = the `Card` under the pointer; drop: parse the list's `Tag` (status name) →
`WorkStatus`; if different set `Status`; `MarkDirty(); FlushIfDirty(); Refresh()`.

**4.2.5 `DeleteTask` — `:238-250`**, `RemoveTaskAnywhere` — `:252-258` (depth-first search: remove from
this collection by reference if present, else recurse into each item's `Subtasks`, stop at first
success), `CountDescendants` — `:260-265` (sum of all nested subtasks).

**4.2.6 `OpenAllFiles` — `:214-236`.** As VIEW-051. `ResolveFilePath` (`DataStore.cs:485`): empty → "";
`http://`, `https://`, `mailto:` (case-insensitive) → verbatim; rooted → verbatim; else
`GetFullPath(Combine(AppFolder, stored))`.

**4.2.7 Stale-repository defect.** `BuildColumns` runs only once (`_built` guard), and the per-column
context menus capture the repository instance given to the **first** `Init`. After a reload/import/
shared-pull, `Init(newRepo)` does not rebuild them, so "Mark selected as done/not done" and "Set
deadline for selected…" mutate the *new* model (cards reference new objects) but call `MarkDirty`/
`FlushIfDirty` on the detached old repository (saving suspended) — the change is not persisted until some
other save (e.g. Ctrl+S or app close). The Mac must resolve the store at action time.

### 4.3 Planner (`Views/PlannerPage.xaml.cs`)

**4.3.1 Constants — `:22-30`.** `HourHeight = 46`, `GutterWidth = 52`, `DayStartHour = 0`,
`DayEndHour = 24`, `SnapMin = 15`; colours `BlockBrush #FF1E88E5`, `BlockDoneBrush #FF6B7785`,
`LineBrush #22808080` (ARGB). Day column width 700 (Day) / 132 (Week) (`:156`). All-day strip max height
108 (`:213`). Initial scroll 7 h (`:280`). Minimum block height 20 (`:327`), min duration 15 (`:285`),
subtitle threshold 34 (`:349`), min block width 24 (`:332`), block inset 3/1 (`:332`, `:359`).

**4.3.2 Helpers.** `AllSchedulable` `:52-58` (§2.1/§2.2 order), `DeadlineOf` `:64`,
`RangeStartOf` `:67` (tasks only), `WhenOf = ScheduledStart ?? Deadline` `:69`, `DueSpan` `:73-80`,
`JobEnd = ScheduledStart + max(15, Duration) min` `:285`, `DurFmt` `:509-514`, `SetDeadlineOf` `:516-524`
(task/procedure/step `Deadline`).

**4.3.3 `Refresh()` — `:118-147`.** `_jobs = AllJobs()`; `_placed = AllSchedulable().filter(WhenOf != nil)`;
`RefreshUnscheduled()`; clear host; build per mode (Week: 7 days from Sunday of anchor; Day: `[anchor]`;
Month: month grid). Label per VIEW-082.

**4.3.4 `LayoutDayBlocks(canvas, jobs, dayW, day)` — `:287-321`.**
```
items = jobs.filter { $0.scheduledStart != nil }.stableSorted { $0.scheduledStart }
i = 0
while i < items.count:
    cluster = [items[i]]; clusterEnd = end(items[i]); j = i + 1
    while j < items.count && items[j].start < clusterEnd:        // strict <: touching blocks don't cluster
        cluster.append(items[j]); clusterEnd = max(clusterEnd, end(items[j])); j += 1
    colEnds = []
    for it in cluster:
        c = first index where colEnds[c] <= it.start               // <=: back-to-back reuse a column
        if found: colEnds[c] = end(it) else: colEnds.append(end(it)); c = colEnds.count - 1
        col[it] = c
    cols = max(1, colEnds.count); w = (dayW - 2) / cols
    for it in cluster: addBlock(it, col[it], w)
    i = j
```

**4.3.5 `AddBlock` — `:323-362`.** `top = (start − day).TotalMinutes / 60 × 46` (`day` is midnight of
the column date); `h = max(20, max(15, dur)/60 × 46)`; `width = max(24, w − 3)`; `left = col × w + 1`;
done = `job is TaskItem && IsComplete`.

**4.3.6 `BuildMonth` — `:365-431`.** `first = new DateTime(anchor.Year, anchor.Month, 1)`;
`start = first − (int)first.DayOfWeek`; cells `start + (w×7 + dow)` for w∈0..5, dow∈0..6; chip
filter/order per VIEW-098.

**4.3.7 Drops.** `DayCanvas_Drop` `:561-577`, `MonthCell_Drop` `:579-613`, `Unscheduled_Drop` `:615-621`
exactly as VIEW-100/101/102. Snap:
```
mins = Int(roundHalfEven(y / 46.0 * 60.0 / 15.0)) * 15
mins = max(0, min(24*60 - 15, mins))
```
Swift: `(y / 46 * 60 / 15).rounded(.toNearestOrEven)`.

**4.3.8 Double-click detection** (`AttachDrag` `:529-545`): on left mouse-down with `ClickCount == 2` →
open editor and mark handled; otherwise record the drag start; mouse-move with the button held beyond
the threshold starts the drag (so a slow double-click with movement can become a drag).

### 4.4 Buckets (`Views/BucketsPage.xaml.cs`)

**4.4.1 `AllBucketableRows()` — `:50-68`.** Tasks: `TaskRows(t, parent: nil)` → row(Kind = parent==nil ?
"Task" : "Subtask", Name = NameOr(t.Name), Parent = parent) then each subtask with `parent = t.Name`
(raw). Procedures: row("Procedure"), then each step row("Checklist step", NameOr(s.Title),
Parent = p.Name). `NameOr(s) = s.isEmpty ? "(unnamed)" : s` (empty only, not whitespace).

**4.4.2 `Refresh()` — `:72-103`.** Keep selected id; materialise rows once; per bucket
`Count = rows.count { $0.item.BucketIds.contains(b.Id) }`, `Category = b.Category.isEmpty ?
"(Uncategorised)" : b.Category`, `CategorySort = b.Category.isEmpty ? "\u{FFFF}" :
b.Category.lowercased()` (invariant); sort by `CategorySort`, `Name` (culture compare); group by
`Category`; reselect kept id; status text; `ShowMembers()`.

**4.4.3 `ShowMembers()` — `:107-122`.** Members sorted by Kind, Name (OrdinalIgnoreCase); header text.

**4.4.4 Mutations** `New_Click :125`, `Rename_Click :140`, `SetCategory_Click :147`, `Delete_Click :154`,
`OpenMember_Click :179`, `RemoveMember_Click :199`, `SelectBucket :207`, `Need :214` — as VIEW-147…152.
All persist with `Save()` (synchronous).

### 4.5 Relationship Map (`Views/RelationshipMapPage.xaml.cs`)

**4.5.1 `RefreshSidebar()` `:35-40` / `ApplyFilter()` `:44-49`.** Build `[Kind] Name` rows for
`AllItems()`; filter as VIEW-172.

**4.5.2 `FocusOn(item)` `:56-62`.** Rebuild sidebar; select the row whose item **is** this object
(reference); `DrawMap(item)` (the selection change also draws it — drawn twice; harmless).

**4.5.3 `DrawMap(center)` `:64-111`.**
```
current = center; clear canvas; title
related = RelatedItems(center).distinct()        // HashSet order: RelatedIds, then ProcedureIds, TaskIds
cx = 1400/2 = 700; cy = 900/2 = 450
pos[center.id] = (cx, cy)
n = related.count; r = min(cx, cy) - 140 = 310
for i in 0..<n: a = 2π·i / max(1, n); pos[related[i].id] = (cx + r·cos a, cy + r·sin a)
for x in related: solidLine(pos[center], pos[x])
for i < j: if related[i].RelatedIds.contains(related[j].id): dashedLine(pos[i], pos[j])
for node in [center] + related: drawNode(node, pos[node.id], isCenter: node.id == center.id)
```
Edge case: if an item lists **its own id** in `RelatedIds` (only via hand-edited data), it appears in
`related`, its position overwrites the centre's, and it is drawn twice at the circle point (the centre
edge becomes a zero-length line). The Mac should exclude the centre from `related` (documented
deviation; no data impact).

`RelatedItems` (`AppRepository.cs:150-163`) builds a `HashSet<Guid>` from `RelatedIds` (+ Equipment
`ProcedureIds`, `TaskIds`) and yields `FindById` hits in set-enumeration order (in practice insertion
order, since nothing is removed from the set). Mac: ordered-set in that insertion order.

**4.5.4 `DrawNode` `:113-135`.** As VIEW-178; positioned at `(p.x − w/2, p.y − h/2)` using the measured
size; `MouseLeftButtonUp` → `DrawMap(item)`.

### 4.6 Shared services

* `BatchDone.SetDone/SetDoneAll` — §2.3.
* `BatchDeadline.SetDeadline/SetDeadlineAll` — VIEW-201.
* `WorkRange.Coerce(start, deadline, editedStart)` (`Services/WorkRange.cs`): both to `.Date`; if start
  set: no deadline → deadline = start; start > deadline → (editedStart ? deadline = start : start =
  deadline). Returns the pair.
* `ChecklistTemplateService.ItemToTask` (`:91`) / `CloneContainer` (`:133`) — VIEW-202.
* `AppRepository.AllJobs` (`:121`), `AllItems` (`:74`), `FindById` (`:82`, top-level only),
  `RelatedItems` (`:150`), `PurgeReferences` (`:186`: removes the id from every top-level item's
  `RelatedIds`, Equipment `ProcedureIds`/`TaskIds`, every procedure step's `TaskIds`/`EquipmentIds`, and
  every file's `LinkedItemIds` across `AllContainers()`), `LogAdded`/`LogRemoved` (`:230-248`: UTC stamp,
  blank name → "(unnamed)", trimmed; log capped at 10 000 oldest-first; `MarkDirty`).

---

## 5. DATA FORMATS

### 5.1 Serializer facts (`Services/DataStore.cs:267`)

`System.Text.Json` with `WriteIndented = false`, `ReferenceHandler = IgnoreCycles`,
`DefaultIgnoreCondition = WhenWritingNull`, **no** naming policy (PascalCase = C# property names), **no
enum converter** (enums are **integers**), no custom converters. `[JsonIgnore]` members are never
written. Missing keys on read → C# defaults. Guid → lowercase `"D"` format. Double → shortest
round-trip (`15`, `16.5`, not `15.0`).

DateTime → ISO-8601, trailing fractional zeros trimmed, suffix by `Kind`: Unspecified → none
(`"2026-09-29T00:00:00"`), Local → numeric offset (`"2026-09-29T09:15:00+03:00"`), Utc → `"Z"`.
On read, a value **with an offset is converted to the reading machine's local time** (Kind Local);
without offset → Unspecified wall-clock; `Z` → Utc.

Enum integers used here: `WorkStatus` Todo 0, InProgress 1, Blocked 2, Done 3;
`RecurrenceKind` None 0, Daily 1, Weekly 2, Monthly 3, Yearly 4. (`ItemKind` is `[JsonIgnore]` on items.)

### 5.2 Fields read/written by this subsystem

| Object (JSON path) | Key | Type / format | R/W here | Notes |
|---|---|---|---|---|
| `Tasks[]` and nested `Subtasks[]` | `Id` | guid | R | identity for board cycle-guard, purge |
| | `Name` | string | R/W (Board new task, saved-list add) | untrimmed on Board "+ New task" |
| | `Deadline` | DateTime? | R/W (Planner drops, batch deadline) | range END |
| | `RangeStart` | DateTime? | R/W (Planner drops, batch deadline) | omitted when null; may be > Deadline in foreign data |
| | `Status` | int | R/W (Board drag, Done toggles) | synced with IsComplete |
| | `IsComplete` | bool | R/W | |
| | `Recurrence` | int | R | label only |
| | `IsJob`, `DurationMinutes` (default 60) | bool, int | R (W via saved-list add) | |
| | `ScheduledStart` | DateTime? | R/W (Planner) | time-of-day matters |
| | `Container.Files[]` (`Path`, `IsLink`, `LinkInPlace`) | | R (Board Open all) | |
| | `BucketIds` | guid[] | R/W (remove member, delete bucket) | always written (`[]`) |
| | `BucketId` (legacy) | guid | R only | migrated into `BucketIds`, never written |
| | `RelatedIds` | guid[] | R (map), W (purge on Board delete) | |
| `Procedures[]` | `Deadline`, `Status`, `Recurrence`, `IsJob`, `DurationMinutes`, `ScheduledStart`, `BucketIds`, `RelatedIds`, `Name` | as above | R/W | no `RangeStart` |
| `Procedures[].Steps[]` | `Title`, `Done`, `Deadline`, `IsJob`, `DurationMinutes`, `ScheduledStart`, `BucketIds`, `TaskIds`, `EquipmentIds` | | R/W | purge touches `TaskIds`/`EquipmentIds` |
| `Crew[].Checklist[]` | same as a step | | R/W | FullName from `FirstName`/`MiddleName`/`LastName` |
| `Equipment[]` | `ProcedureIds`, `TaskIds`, `RelatedIds` | guid[] | R (map), W (purge) | |
| `Vessels[]` | `RelatedIds` | | R (map), W (purge) | |
| `QuickBuckets[]` | `Id`, `Name`, `Category`, `CreatedUtc` | guid, string, string, DateTime (Utc, `…Z`) | R/W | `Display` is `[JsonIgnore]` |
| `Log[]` | `TimestampUtc`, `Action`, `Kind`, `Name`, `Detail` | Utc DateTime, strings | W (buckets add/remove) | `"Added"`/`"Removed"`, Kind `"Bucket"`, Detail = category on add, `""` on remove |
| `ChecklistTemplates[].Items[]` | `Title`, `DurationMinutes`, `IsJob`, `Container` | | R (saved-list add) | |
| `Ui` | `CalendarSelectedDate` | DateTime? | R/W | per-device (Flash Sync denylist) |
| | `CalendarViewMode` | string? `"Day"`/`"Week"`/`"Month"`/`"All"`/`"Agenda"` | R/W | shared preference |
| | `CalendarFontScale` | double? (11…28 written; 10…30 accepted) | R/W | shared preference |
| | `MapFocusedItemId` | guid? | R/W | per-device |
| root | `LastModified` | DateTime (Local, with offset) | W (every `Save`) | |

Illustrative task after a Planner day-drop (key **order** is defined by the models spec; values are
what matters here):
```json
{"Id":"3f2b…","Name":"Overhaul pump","Description":"","Container":{…},"RelatedIds":[],"Tags":[],
 "BucketIds":["9a1c…"],"Deadline":"2026-10-08T00:00:00+03:00","RangeStart":"2026-10-03T00:00:00",
 "IsJob":true,"DurationMinutes":90,"ScheduledStart":"2026-10-08T09:15:00+03:00",
 "Recurrence":0,"RecurrenceSpawned":false,"IsComplete":false,"Status":1,"Subtasks":[]}
```
Bucket and log entry:
```json
{"Id":"9a1c…","Name":"Engine room","Category":"Location","CreatedUtc":"2026-07-08T10:11:12.1234567Z"}
{"TimestampUtc":"2026-07-08T10:11:12.2345678Z","Action":"Added","Kind":"Bucket","Name":"Engine room","Detail":"Location"}
```
UI keys:
```json
"Ui":{…,"CalendarSelectedDate":"2026-09-29T00:00:00","CalendarViewMode":"Week","CalendarFontScale":16.5,…,"MapFocusedItemId":"5d0e…",…}
```

### 5.3 DateTime Kind produced by each write path (cross-version compatibility)

| Write path | Field(s) | Kind on Windows | JSON shape |
|---|---|---|---|
| Planner Day/Week canvas drop | `ScheduledStart` | **Local** (days derive from `DateTime.Today`) | `…T09:15:00+03:00` |
| Planner Day/Week drop range-extension | `Deadline` / `RangeStart` = `day.Date` | **Local** | `…T00:00:00+03:00` |
| Planner Month drop, timed | `ScheduledStart` | Unspecified (grid dates from `new DateTime(y,m,1)`) | `…T14:30:00` |
| Planner Month drop, slide | `RangeStart`, `Deadline` = old `.Date + delta` | **inherits** each field's existing Kind | either |
| Planner Month drop, point / no-anchor | `Deadline` (and `RangeStart`) | Unspecified | `…T00:00:00` |
| Planner pool drop | `ScheduledStart = null` | — | key omitted |
| Batch deadline (DatePicker) | `Deadline`, `RangeStart` (via `Coerce`, `.Date` keeps Kind) | Unspecified for the new date; a kept start keeps its Kind | |
| Calendar `CalendarSelectedDate` | from the WPF calendar / `DateTime.Today` | Unspecified when clicked; possibly Local if the initial `Today` was never changed | either |
| Bucket `CreatedUtc`, log `TimestampUtc` | | Utc | `…Z` |
| `LastModified` | `DateTime.Now` | Local | `+hh:mm` |

**Compatibility rules for the Mac:**
1. Read all three forms. Offset forms are converted to local wall-clock (to match what Windows shows on
   the same machine); keep the original Kind on the in-memory value so an unchanged value re-serialises
   byte-identically (important: Flash Sync diffs JSON trees, so a spurious Kind change would ship every
   task as "changed").
2. For values **created** by these views, write the same Kind the Windows path would (table above), via
   the shared `NetDateTime` type from the model spec.
3. Known Windows hazard to be aware of (not to "fix" silently): a Local-kind date-only value
   (`…T00:00:00+03:00`) read on a machine in a *different* time zone lands on the previous/next day.
   See Q-05.

### 5.4 Files, zip, PDF, xlsx

None are produced by these five pages. Board "Open all files" only **opens** existing attachments. The
saved-list add clones container metadata (no file I/O).

### 5.5 Rich text (XAML)

These pages never parse, render or write `Container.RichTextXaml`. The only touch is
`CloneContainer`, which copies the XAML string **verbatim** (including an `enc:` encrypted body and the
`IsLocked` flag). The Mac XAML⇄NSAttributedString converter is not involved here.

### 5.6 Flash Sync interplay

`Tasks`, `Procedures`, `Crew`, `QuickBuckets`, `Log`, `ChecklistTemplates` are Id-collections diffed per
item (changed items travel whole). `Ui.CalendarViewMode` / `Ui.CalendarFontScale` travel as `UiChanges`;
`Ui.CalendarSelectedDate` / `Ui.MapFocusedItemId` never travel and are never overwritten on apply.

---

## 6. DEPENDENCIES

### 6.1 Calls out of this subsystem

| Caller | Callee |
|---|---|
| all | `AppRepository`: `Data`, `MarkDirty`, `FlushIfDirty`, `Save` |
| Calendar | `BatchDoneMenu.Add/RightClickSelect`, `BatchDeadlineMenu.Add`, `SubtaskEditorWindow`, `ChecklistStepEditorWindow`, navigator (`MainWindow.NavigateToItem`), `UiTree.FindAncestor` |
| Board | `BatchDoneMenu`, `BatchDeadlineMenu`, `SavedListPicker.PickAndAddTasks`, `PromptWindow`, `SubtaskEditorWindow`, `DataStore.ResolveFilePath`, `Process.Start`, `MessageBox`, `AppRepository.PurgeReferences`, `DragDrop`, `SystemParameters` |
| Planner | `AppRepository.AllJobs`, `SavedListPicker`, `SubtaskEditorWindow`, `ChecklistStepEditorWindow`, `DragDrop`, `SystemParameters` |
| Buckets | `PromptWindow`, `MessageBox`, `AppRepository.LogAdded/LogRemoved`, `SubtaskEditorWindow`, `ChecklistStepEditorWindow`, `Navigate` |
| Map | `AppRepository.AllItems/FindById/RelatedItems`, `PickerItem` |
| SavedListPicker | `ItemPickerWindow`, `ChecklistTemplateService.ItemToTask` |
| BatchDeadlineMenu | `DatePromptWindow`, `BatchDeadline`, `WorkRange` |

### 6.2 Calls into this subsystem

`MainWindow.InitPagesAndRestoreUi` (`Init` ×5, `Navigate` for Buckets), `MainTabs_SelectionChanged`
(refreshes), `CaptureUiState` (`CalendarSelectedDate`, `CalendarViewMode`, `FocusedItemId`). The
`Saved` event → `ReconcileRecurrences` (indirect effect of Done toggles).

### 6.3 Windows-only APIs / WPF specifics used

| Windows API | Where | Mac replacement |
|---|---|---|
| `Process.Start(UseShellExecute)` | Board Open all files | `NSWorkspace.shared.open(URL)`; UNC `\\srv\share\p` → `smb://srv/share/p` per brief; drive-letter paths that don't exist → skipped (same as Windows' existence check) |
| `MessageBox` | Board, Buckets, batch menus, pickers | `NSAlert` sheets / SwiftUI `.alert` / `.confirmationDialog` |
| WPF `DragDrop.DoDragDrop` with in-process objects (`Card`, `"AAJob"`, `"AAJobDay"`) | Board, Planner | SwiftUI `Transferable` with a private exported UTType carrying ids (VIEW mapping in §7) |
| `SystemParameters.MinimumHorizontal/VerticalDragDistance` | Board, Planner | system drag threshold (automatic with `.draggable`/`.onDrag`) |
| WPF `Calendar` control | Calendar | `DatePicker(...).datePickerStyle(.graphical)` |
| `ListView`/`GridView`, `ListCollectionView` grouping/sorting | Calendar, Buckets | SwiftUI `Table` / `List` with `Section`s, pre-sorted arrays |
| `GridSplitter` | Calendar, Planner, Buckets, Map | `HSplitView` / `NavigationSplitView` column widths |
| `Canvas` absolute layout | Planner, Map | SwiftUI `ZStack` + `.position`/`.offset` or `Canvas` |
| `CultureInfo.CurrentCulture` date formats `ddd`, `dddd`, `MMM`, `MMMM` | Calendar Agenda, Planner | `DateFormatter` with fixed `dateFormat` (`EEE`, `EEEE`, `MMM`, `MMMM`) and `Locale.current` |
| `Window.GetWindow(this)` owners | dialogs | sheet presentation on the main window |

No DPAPI, OpenCV, DirectShow, WinForms or Win32 calls in this subsystem.

---

## 7. macOS ADAPTATION NOTES

General principles: keep every control, text, rule and persistence trigger above; express them with
native idioms; ⌘ replaces Ctrl; SF Symbols replace decorative emoji **in chrome** while user-visible
computed strings (e.g. the Calendar row name `"… · 👤 Name"`, used for Agenda sorting) keep their exact
characters in the model/display string. All five pages are `@MainActor` SwiftUI views observing the
`AppStore`; they hold item **ids**, never model references across refreshes/reloads (fixes 4.2.7).
Mutations go through store methods that (1) change the model, (2) `markDirty()`, (3) `flushIfDirty()`
where the Windows code does, and surface a save failure with an alert instead of crashing.

### 7.1 Calendar

* **Structure:** `HSplitView { sidebar | detail }`. Sidebar (min 260, ideal 320): section title
  "Calendar" + `DatePicker("", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)`.
  Optionally decorate days that have items (dots) — an enhancement; not required.
* **Toolbar / header:** title (`DayLabel` string, exact text), a `Picker` in `.segmented` style with the
  five modes labelled exactly "Day", "Week", "Month", "All Upcoming", "Agenda" (Agenda's help tooltip),
  and "Text:" A-/A+ as a control group (`textformat.size.smaller` / `.larger` SF Symbols with the exact
  tooltips, plus text labels in accessibility). Map ⌘− / ⌘+ (and ⌘0 = reset to 15, optional) when the
  Calendar tab is focused.
* **List:** SwiftUI `Table(rows, selection: $sel)` with `TableColumn`s "Done" (Toggle checkbox; click is
  isolated from row double-click), "When", "Status", "Task" (strikethrough when complete), "Recurrence";
  column widths 56/210/120/420/110 as ideal widths; text wraps (use `.lineLimit(nil)`). Font = design-
  system mono at `CalendarFontScale` pt. Agenda: `Table` with `Section("Today (3)")`-style headers
  (label bold `accent` + muted count), or a `List` with sections if column headers are not wanted —
  keep the column layout.
* **Selection & menus:** `.contextMenu(forSelectionType: Row.ID.self, menu:, primaryAction:)` gives the
  exact right-click rule of §2.5 natively, and `primaryAction` = double-click/Return → VIEW-014. Menu
  items: "Mark selected as done" (`checkmark.circle`), "Mark selected as not done" (`circle`), Divider,
  "Set deadline for selected…" (`calendar.badge.clock`). Keep the WPF glyph prefixes in the titles
  ("✓ ", "○ ", "📅 ") or replace with SF Symbol images — the text after the glyph must be identical.
* **Agenda rows** must bind Done to the **model** (not a snapshot) so all occurrences of an item update
  together (fixes the sibling-staleness quirk; no behavioural loss).
* **Double-click** only on a row (never re-open a stale selection from empty space).
* **Dark mode:** use semantic colours (`.primary`, `.secondary`, `Color.accentColor`/app accent token),
  alternating row backgrounds optional; strikethrough uses `.strikethrough(isDone)`.

### 7.2 Board

* **Structure:** toolbar with "Task Board" title + hint text, `.searchable(text:)` labelled "Find"
  (placeholder "Find"), a "Hide done" toggle (`Toggle` checkbox style), "+ From saved list"
  (`list.bullet.rectangle` + text) and "+ New task" (prominent, `.borderedProminent`). Body: `HStack` of
  four equal columns (`GeometryReader` or `Grid` with equal widths), each a rounded material card
  (`.background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))`) with a coloured header
  capsule (exact colours) showing title + count, and a `ScrollView { LazyVStack(spacing: 8) }` of cards.
* **Cards:** rounded 6, 6-pt coloured leading stripe, exact texts; overdue meta in #D32F2F (in dark mode
  use a slightly lighter red such as #EF5350 for contrast, keeping the red semantic). Show **visible
  selection** (accent ring) — Windows hid it by accident; multi-select with ⌘-click / ⇧-click per column;
  ⌘A selects all cards in the focused column.
* **Drag & drop:** `.draggable(TaskRef(id:))` on each card with a card-shaped preview;
  `.dropDestination(for: TaskRef.self) { refs, _ in … }` on each column with an `isTargeted` highlight
  (column border glows in its colour). Drop sets status by id; animate the card moving
  (`withAnimation(.snappy)`). Dragging the selection as a group is an optional enhancement; the minimum
  requirement is single-card drag with identical semantics. Declare the private UTType
  (`com.eriskay.aa.task-ref`, conforming to `public.data`) in Info.plist `UTExportedTypeDeclarations`, or
  use `ProxyRepresentation` to a JSON string for in-app only.
* **Context menu:** same eight entries/order; "Open all files (routine)" uses `NSWorkspace.open` per file;
  confirmations via `NSAlert` (Yes/No → "Open"/"Cancel" buttons with the same message text; keep the
  message wording). Delete uses a destructive alert with the exact message (the `\n\n` line break kept).
  Optional: ⌫/⌘⌫ triggers "Delete task" with the same confirmation.
* **New task prompt:** sheet "New Task" with a "Name:" field; Return = OK, Esc = Cancel.

### 7.3 Planner

* **Structure:** toolbar: "Planner" title + range label; a navigation control group `‹ Today ›`
  (`chevron.left`, "Today", `chevron.right`; ⌘← / ⌘→ / ⌘T when the Planner is focused); segmented
  Day/Week/Month. Body: `HSplitView { pool (min 200, ideal 230) | grid }`.
* **Pool:** header "Unscheduled Jobs" + "+ Saved list" button; `TextField` with prompt **"Search jobs..."**
  (show the placeholder that Windows intended); `List` rows `"{name}   ·   {dur}"` (single line,
  truncation); footer hint text. The list is a drop destination (unschedule) with a highlight.
* **Hour grid:** a single `ScrollView([.horizontal, .vertical])` whose content is a `VStack` of pinned
  header + due strip + hour body is the easy way to keep header/strip/body aligned horizontally; use
  `LazyVStack(pinnedViews: [.sectionHeaders])` or an overlay header synced via `ScrollPosition` so the
  header and strip stay visible while the hour body scrolls vertically — the key requirement is that
  day columns line up at all times (fixes VIEW-094 quirk). Constants exactly: hour 46 pt, gutter 52,
  day width 700 / 132, block rules, colours. Scroll to 07:00 on first appearance of each rebuild
  (`ScrollViewReader.scrollTo(hour7, anchor: .top)`).
* **Drops with location:** `.dropDestination(for: JobRef.self) { refs, location in … }` on each day
  column gives the local point → minutes via §4.3.7 with **half-even** rounding. For a live preview, use
  `onDrop(of:delegate:)` with a `DropDelegate` whose `dropUpdated(info:)` draws a translucent ghost block
  at the snapped time (enhancement, strongly recommended: it makes the 15-min snap visible).
* **Payload:** `JobRef { id: UUID, kind: task|procedure|step|crewStep, anchorDay: LocalDate? }`; resolve
  by id at drop time across tasks (recursive), procedures, steps, crew checklists.
* **Blocks & chips:** `RoundedRectangle` fills #1E88E5 / #6B7785 with white text; ghost opacity 0.6 (all-
  day) / 0.55 (month); glyphs `• ⚑ ▸ ·` kept as text; `.help()` tooltips with exact strings.
  Clip blocks at 24:00 (optional continuation marker "↧" is an enhancement).
* **Today tint:** use a subtle accent-tinted background (e.g. accent at 6 % opacity) in both
  appearances (Windows' `PanelAlt` is invisible in light mode).
* **Double-click:** `.onTapGesture(count: 2)` (placed before the drag modifier) → editor; for a
  procedure, Windows does nothing — see Q-07.
* **Month:** `Grid`/`LazyVGrid` 7×(1+6); header "Sun…Sat" (keep English strings for parity, or localise
  via `Calendar.shortWeekdaySymbols` starting at Sunday — Q-09); cells are drop targets.

### 7.4 Buckets

* `HSplitView { sidebar | members }` or `NavigationSplitView` embedded in the tab. Sidebar: header
  "Buckets" with an SF Symbol (`tray.2` or `archivebox`) in place of 🪣 in chrome (the members header text
  keeps "🪣 " as it is a computed string — or render the symbol and keep the text after it identical);
  help text (replace "Ctrl+N" with "⌘N" — the shortcut mapping on Mac); toolbar buttons "+ New bucket",
  "Rename", "Set category...", "Delete"; `List(selection:)` with `Section(header: "Location (3)")` per
  category group, rows "Name" + trailing "{n} items"; status line at the bottom.
* Prompts as sheets with the exact titles/labels; delete via `NSAlert` warning style, buttons Yes/No →
  "Delete"/"Cancel" with the exact message.
* Members: `List` with `.contextMenu(forSelectionType:)` ("Open", "Remove from this bucket") and
  `primaryAction` (double-click) → open; double-click on empty space does nothing.
* Refresh live from the store (the page can observe changes, e.g. after ⌘N assignments), keeping
  selection by id.

### 7.5 Relationship Map

* `HSplitView { Inspect sidebar | map }`. Sidebar: title "Inspect", `.searchable`/`TextField` filter,
  `List(selection:)` of `"[Kind] Name"` rows (optionally with a small kind colour dot).
* Map: `ScrollView([.horizontal, .vertical])` containing a fixed 1400×900 `ZStack`: a `Canvas` for edges
  (solid accent 1.5 pt @ 0.65; dashed `[4,3]` secondary 1 pt @ 0.6) under node views placed with
  `.position(x:y:)`. Nodes: rounded 8, padding 10×6, centre border 3 pt else 1 pt, two text lines (kind
  size 10, name bold). **Colour per kind (Mac decision, per ARCHITECTURE-BRIEF "per-kind colours … map
  nodes"):** fill Equipment #4FC3F7, Task #FFB74D, Procedure #A5D6A7, Vessel #CE93D8 (proposed; the
  first three are from PROGRESS.md), text black, border black — all pastel fills keep black text legible
  in both appearances. Q-10 records this deviation from the monochrome WPF code.
* Clicking a node recentres **with animation** (`withAnimation(.spring(duration: 0.45))` — nodes keep
  their SwiftUI identity by item id, so they glide to their new positions; new nodes fade in, departing
  nodes fade out) and also selects the item in the Inspect list if present (fixes VIEW-179 quirk).
* Redraw on tab appearance and whenever the store changes, re-resolving the centre by id; if the centre
  no longer exists, clear the map and title.
* Optional enhancements (no data impact): pinch/⌘-scroll zoom (`MagnifyGesture` + `scaleEffect`),
  "Show in Relationship Map" context-menu command on items elsewhere (calls `focusOn(id)`).

### 7.6 Shared

* `DatePromptWindow` → sheet with a graphical/field `DatePicker`, buttons "Clear deadline",
  "Cancel" (Esc), "OK" (Return; disabled or alerting when no date — keep the alert text if a "no date"
  state is representable; a SwiftUI `DatePicker` always has a date, so model it as an optional with an
  explicit "No date" state to keep the message reachable, or disable OK until picked).
* `PromptWindow` → sheet with title, label, `TextField` pre-filled and selected, Cancel/OK.
* `ItemPickerWindow` (saved-list add) → sheet with a search field and a multi-selection `List`; **keep
  selections across filtering** (Windows drops them — Q-08), OK returns selected in list order.
* Editors (Subtask / Checklist step) → per the editor spec (sheet or `Window` scene); on dismiss the
  calling page flushes and refreshes.
* Keyboard: all Ctrl shortcuts → ⌘; nothing in these pages defines its own Ctrl shortcut besides list
  multi-select (Ctrl+A / Ctrl+click → ⌘A / ⌘-click).

### 7.7 Genuinely impossible / different on macOS

* Opening Windows drive-letter paths (`Z:\…`) stored as in-place links: impossible unless mounted at an
  equivalent location; the Mac skips unreachable targets silently, exactly like the Windows existence
  check (Board VIEW-051). UNC paths map to `smb://` as a convenience.
* WPF's invisible selection, unsynchronised planner header scroll, and missing placeholder are Windows
  rendering defects, deliberately not reproduced.

---

## 8. TEST VECTORS / VERIFICATION

Assume Today = **2026-09-29 (Tuesday)**, en-US locale, unless stated.

### 8.1 Calendar

| # | Setup | Expectation |
|---|---|---|
| C1 | Task T: RangeStart 2026-10-03, Deadline 2026-10-05 | Day view: absent on 10-02 and 10-06; present on 10-03, 10-04, 10-05. When = `"2026-10-03 → 2026-10-05"`. |
| C2 | Task with RangeStart 2026-10-08, Deadline 2026-10-05 (out of order) | `IsRanged` false; `EffectiveStart` = 10-05; covers only 10-05; When = `"2026-10-05"`. |
| C3 | RangeStart 2026-10-05, Deadline 2026-10-05 | Not ranged; point on 10-05. |
| C4 | RangeStart set, Deadline nil | No row. |
| C5 | Week, selected 2026-09-29 | start 2026-09-27, end 2026-10-04; title `"Schedule — week of 2026-09-27"`. Range 09-20→09-27 included; point 10-04 excluded; point 09-27 included; point 10-03 included. |
| C6 | Month, selected 2026-09-15 | window [09-01, 10-01); title `"Schedule — 2026-09"`; range 08-25→09-02 included; point 10-01 excluded. |
| C7 | All Upcoming; not-done task due 09-28; task due 09-29 done; range 09-20→09-29 | 09-28 excluded; 09-29 done included; range included. Title `"Schedule — all upcoming"`. |
| C8 | Agenda; range 09-25→10-01 | 3 occurrences: groups `"Today (…)"` 09-29, `"Tomorrow"` 09-30, `"Thu, 2026-10-01"`. |
| C9 | Agenda; range 09-29→10-31 (32 days) | One occurrence, group `"Sat, 2026-10-31"`. |
| C10 | Agenda; range 09-29→10-30 (31 days) | 32 occurrences 09-29 … 10-30. |
| C11 | Agenda; two rows same day named "b" and "A" | culture order: "A" before "b". |
| C12 | Step "Check oil" in procedure "Engine" | Task column `"Check oil   ·  [Engine]"`, Status `"Step"`, Recurrence `""`. After tick: Status `"Done"`, struck. |
| C13 | Crew item "Sign contract", member with blank names | `"Sign contract   ·  👤 (unnamed)"`. |
| C14 | Task status InProgress, Recurrence None | Status `"InProgress"`, Recurrence `"None"`. |
| C15 | Procedure Status Blocked, tick Done then untick | Done → Status 3; untick → Status 0 (Todo). |
| C16 | Font: start 15, A+ ×9 | 16.5, 18, 19.5, 21, 22.5, 24, 25.5, 27, 28 (then stays 28). |
| C17 | Font: 12, A- | 11 (10.5 clamped). |
| C18 | Stored `CalendarFontScale` 9 / 10 / 30 / 31 | 9 → ignored (15); 10 → 10; 30 → 30; 31 → ignored. From 30, A+ → 28; from 10, A- → 11. |
| C19 | Stored `CalendarViewMode` `"day"` (lower case) | Day (exact-match only). |
| C20 | Ordering (Day/Week/…): point task deadline 10-02T00:00, ranged 09-30→10-05, point 10-02T00:00 (second task) | ranged first (start 09-30), then the two points in enumeration order. |
| C21 | Batch deadline on 3 Agenda rows of the same task | prompt says "3 selected items"; result: one change. |

### 8.2 Board

| # | Setup | Expectation |
|---|---|---|
| B1 | Task due 2026-09-20, Todo, Weekly | Meta `"Due 2026-09-20  ·  OVERDUE   ·   Weekly"` in #D32F2F. |
| B2 | Same but Status Done | Meta `"Due 2026-09-20   ·   Weekly"` in #6B6B6B, name struck. |
| B3 | Range 09-25 → 10-02 | Meta `"2026-09-25 → 2026-10-02"` (not overdue). |
| B4 | Range 09-10 → 09-20, InProgress | `"2026-09-10 → 2026-09-20  ·  OVERDUE"`. |
| B5 | 1 file, 3 direct subtasks (1 complete) | Badges `"📎 1 file    ☑ 1/3"`; 2 files → `"📎 2 files"`. |
| B6 | Task "A" → subtask "" → subtask "C" | Card C parent `"↳ A › (unnamed)"`; card "" parent `"↳ A"`; card A no parent line. |
| B7 | Subtask with no deadline, Todo | Appears in To Do. |
| B8 | Delete task with 2 subtasks, one of which has 1 subtask | Message `"Delete task 'X'?\n\nThis also deletes its 3 subtask(s)."`. |
| B9 | Drag Todo card to Done | Status 3, IsComplete true, saved immediately; if recurring top-level → next occurrence created after save. |
| B10 | Drag Done card to Blocked | Status 2, IsComplete false. |
| B11 | Find "PUMP" | matches "Fuel pump overhaul" (ordinal ignore case). |
| B12 | Two tasks sharing an Id | Only the first (pre-order) gets a card. |
| B13 | Open all with 16 files | Confirmation `"Open all 16 files for 'X'?"`; with 15 → no confirmation. |

### 8.3 Planner

| # | Input | Expectation |
|---|---|---|
| P1 | `DurFmt` 0, 45, 60, 90, 125, −5 | `"0m"`, `"45m"`, `"1h"`, `"1h 30m"`, `"2h 5m"`, `"-5m"`. |
| P2 | Block duration 10 at 09:00 | end 09:15; height 20; no subtitle. |
| P3 | Duration 44 / 45 / 60 / 30 | height 33.73 (no subtitle) / 34.5 (subtitle) / 46 / 23. |
| P4 | Snap y = 0 / 100 / 28.75 / 51.75 / 1104 | 0 / 135 (8.695→9) / 30 (2.5→2, half-even) / 60 (4.5→4 → 60) / 1425. Check: 51.75/46×60/15 = 4.5 → 4 → 60 min. |
| P5 | Blocks A 09:00–10:00, B 09:30–10:30, C 10:00–11:00, D 11:00–11:30 (Day view, width 700) | Cluster {A,B,C}: A col0, B col1, C col0 → 2 cols, colWidth 349, widths 346; D alone col0 width 695. |
| P6 | A 09:00–10:00, B 10:00–11:00 | Separate clusters (10:00 < 10:00 false); both full width. |
| P7 | Duration 0 job at 09:00 and another at 09:10 | end 09:15 → they overlap → 2 columns. |
| P8 | Week view of Tue 2026-09-29 | columns Sun 09-27 … Sat 10-03; label `"Week of 2026-09-27"`; header `"Sun\nSep 27"`. |
| P9 | Day view label | `"Tuesday, 2026-09-29"`; header `"Tuesday, Sep 29"`. |
| P10 | Month Sept 2026 | label `"September 2026"`; grid starts Sun 2026-08-30, ends Sat 2026-10-10 (42 cells). |
| P11 | Anchor 2027-01-31, Month, ▶ | 2027-02-28. |
| P12 | Task range 10-03→10-05, due-only, Week of 09-27 | chips: 10-03 `"▸ name"` opacity .6, 10-04 `"· name"` .6, 10-05 `"⚑ name"` bold 1.0; tooltip `"name\n2026-10-03 → 2026-10-05  (3 days)\nDrag in Month to move the whole range • double-click to edit"`. |
| P13 | Month: drag that task's chip from cell 10-04 to 10-10 | RangeStart 10-09, Deadline 10-11. |
| P14 | Day canvas drop on 10-08 at y=414 (09:00) for task range 10-03→10-05 | ScheduledStart 10-08 09:00; Deadline 10-08; RangeStart 10-03. Drop on 10-01 instead → RangeStart 10-01, Deadline 10-05. |
| P15 | Task with deadline only (no range) dropped on hour grid 10-08 | ScheduledStart set; Deadline unchanged. |
| P16 | Timed ScheduledStart 10-03 14:30 dropped on month cell 10-07 | 10-07 14:30; deadline/range untouched. |
| P17 | Procedure due 10-03 dropped on month cell 10-07 | Deadline 10-07. |
| P18 | Unscheduled IsJob task dragged to month cell 10-07 | Deadline 10-07 (becomes due-only chip); leaves the pool. |
| P19 | Timed item dropped on pool | ScheduledStart null; if it had a deadline → back to due strip. |
| P20 | Pool filter | IsJob task no dates → listed; IsJob with deadline → not; non-job without dates → not; done IsJob without dates → listed. |
| P21 | Item with ScheduledStart 10-01 09:00 and Deadline 10-05 | Hour grid 10-01 only; not in due strip on 10-05; month shows `"09:00 name"` on 10-01 only. |
| P22 | Month ordering on one cell: due "beta", timed 08:00 "zeta", due "Alpha", timed 07:00 "x" | `07:00 x`, `08:00 zeta`, `• Alpha`, `• beta`. |
| P23 | All-day strip ordering: point "b" (10-05), range "a" 10-03→10-05, on 10-05 | range "a" (start 10-03) before "b". |

### 8.4 Buckets

| # | Setup | Expectation |
|---|---|---|
| K1 | Buckets: ("Engine room","Location"), ("Bridge","location"), ("Captain","Rank"), ("Misc","") | Order: Bridge [group "location"], Engine room [group "Location"], Captain [Rank], Misc [(Uncategorised), last]. |
| K2 | Bucket assigned to a task, its subtask and a procedure step | row `"3 items"`; members sorted: `[Checklist step]  …   —   in <proc>`, `[Subtask]  …   —   in <task>`, `[Task]  …`. |
| K3 | Bucket with 1 member | row text `"1 items"`; header `"🪣 Name  ·  Cat   —   1 item(s)"`. |
| K4 | Delete bucket with 2 members | message `"Delete bucket 'X'? Its 2 item(s) will be removed from it (the items themselves are kept)."`; members' BucketIds no longer contain the id; log entry Removed/Bucket/X/"". |
| K5 | New bucket "  Galley  ", category cancelled | Name "Galley", Category "", log Added/Bucket/Galley/"". |
| K6 | Legacy JSON task `{"BucketId":"g1"}` | loads with `BucketIds == ["g1"]`; saved JSON has `"BucketIds":["g1"]` and no `BucketId`. |
| K7 | Picker returns 3 buckets | info message; first two in list order kept. |
| K8 | No buckets | status line with curly quotes exactly. |

### 8.5 Relationship Map

| # | Setup | Expectation |
|---|---|---|
| M1 | Centre with 4 related | positions (1010,450), (700,760), (390,450), (700,140) (±1e-9). |
| M2 | Centre with 1 related | (1010,450). |
| M3 | Centre with 0 related | only centre drawn; title `"Relationship Map — {name}"`. |
| M4 | Equipment E with ProcedureIds [P], TaskIds [T], RelatedIds [V] | related order V, P, T; T's own map does not include E unless T.RelatedIds has E. |
| M5 | Related R1, R2 with R1.RelatedIds ∋ R2 | one dashed edge. With only R2.RelatedIds ∋ R1 and R1 before R2 → none. |
| M6 | Search "task" | all `[Task] …` rows. |
| M7 | `Ui.MapFocusedItemId` refers to a deleted item | nothing drawn; title "Relationship Map". |

### 8.6 Batch services

| # | Input | Expectation |
|---|---|---|
| S1 | `SetDone(task InProgress, false)` | false (no change). |
| S2 | `SetDone(procedure Blocked, true)` → then false | Done → Todo. |
| S3 | `SetDeadline(task start 10-10 deadline 10-12, 10-05)` | start 10-05, deadline 10-05 (clamped). |
| S4 | `SetDeadline(task start 10-01 deadline 10-12, nil)` | both nil. |
| S5 | `SetDeadline(task no dates, 10-05)` | deadline 10-05, start nil. |
| S6 | `WorkRange.Coerce(10-10, nil, true)` | (10-10, 10-10). |
| S7 | `WorkRange.Coerce(10-10, 10-05, true)` | (10-10, 10-10). `editedStart:false` → (10-05, 10-05). |
| S8 | `ItemToTask(item{Title:"Flush", Dur:30, IsJob:true, files:[f]})` | new task Name "Flush", 30, IsJob, Status 0, container new id, file same Path new Id. |

### 8.7 JSON round-trip checks

* Planner day-drop on a machine at UTC+3 writes `ScheduledStart` with `+03:00`; month-drop writes no
  offset. Re-reading and re-saving without edits yields byte-identical strings.
* `CalendarFontScale` 18 serialises as `18`, 16.5 as `16.5`.
* Enum `Status` serialises as an integer.

---

## 9. KNOWN WINDOWS QUIRKS & OPEN QUESTIONS

### 9.1 Quirks (decision for the Mac)

| ID | Quirk | Mac decision |
|---|---|---|
| W-01 | Board batch menus bound to the repo of the first `Init` (4.2.7) | **Fix**: resolve store at action time. |
| W-02 | Calendar Done checkbox may flush before the binding updates the model (WPF raises `Checked` in the property-changed callback before TwoWay source update) — unverified, plausible | **Fix**: mutate model, then mark dirty + flush. |
| W-03 | Agenda occurrences of one item don't update each other's Done | **Fix**: bind to model. |
| W-04 | Board card selection invisible | **Fix**: visible selection. |
| W-05 | Planner header/due strip don't scroll horizontally with the hour grid | **Fix**. |
| W-06 | Planner "Search jobs..." placeholder never shown | **Fix**: show it. |
| W-07 | Today tint (`PanelAlt`) invisible in light mode (Planner/Month) | **Fix**: subtle tint. |
| W-08 | Planner greys only completed **tasks**; done procedures/steps stay blue | Q-06. |
| W-09 | Planner double-click on a procedure does nothing | Q-07. |
| W-10 | `NavigateToItem` uses fixed tab indexes; wrong after tab reorder | **Fix**: navigate by tab identity. |
| W-11 | Board delete is permanent (no Trash/undo/log) | Q-01 (replicate by default). |
| W-12 | Board "+ New task"/saved-list add write no activity log | Replicate (no log) unless Q-03 says otherwise. |
| W-13 | Map node click doesn't select the Inspect row; map not redrawn on tab switch | **Fix** both (VIEW-179/181). |
| W-14 | Map monochrome vs PROGRESS colour-coding | Q-10 (Mac: per-kind colours). |
| W-15 | Double-click on empty list area opens the stale selection (Calendar, Buckets); double-click on the Done checkbox toggles twice + opens editor | **Fix**: act only on the clicked row; checkbox isolated. |
| W-16 | Saved-list picker drops selections when filtering | **Fix** (Q-08). |
| W-17 | Unhandled exceptions from `Save()` crash-dialog | **Fix**: alert "Couldn't save …" and keep dirty. |
| W-18 | Blocks past midnight overflow/truncate | Clip at 24:00. |
| W-19 | Self-relation drawn twice on the map | Exclude centre from related. |
| W-20 | Board search runs on every keystroke without debounce | Keep immediate filtering (SwiftUI is fast); optional 150 ms debounce for very large data. |

### 9.2 Open questions

* **Q-01** Board "Delete task": keep the Windows hard delete (permanent, not in Trash, no Ctrl+Z, no
  log), or route **top-level** tasks through the Trash (`TrashHierarchyItem`) for consistency with the
  Tasks tab? PROGRESS marks this "needs its own decision". Default for parity: hard delete, identical
  confirmation text.
* **Q-02** Descendant ids are not purged on Board delete (only the deleted task's id). Replicate (default)
  or purge the whole subtree's ids?
* **Q-03** Should Board/Planner-created tasks be written to the activity log on the Mac? (Default: no,
  for parity.)
* **Q-04** Per-item password locks are not honoured by these pages (names shown; editors open without
  unlock). Keep parity or gate the editors behind the lock prompt on the Mac? Default: parity, flagged
  to the lead.
* **Q-05** Local-kind date-only values written by Planner Day/Week drops shift by a day when read in
  another time zone (Windows behaviour). Keep exact Kind parity (default, per the brief), or write
  date-only fields as Unspecified on the Mac (safer, still readable by Windows)?
* **Q-06** Grey out completed procedures/steps in the Planner too? Default: yes on Mac is a visual-only
  improvement — lead to confirm.
* **Q-07** Planner double-click on a procedure: do nothing (parity) or navigate to it like the Calendar?
* **Q-08** Keep picker selections across searches (recommended).
* **Q-09** Month header "Sun…Sat" and all `ddd`/`MMMM` formats: English literals vs `Locale.current`.
  Windows uses the current culture for formatted dates but hard-coded English for the month header.
  Default: the same split.
* **Q-10** Map node colours: adopt the PROGRESS palette (+ proposed Vessel #CE93D8) as the Mac rendering,
  consistent with the shared per-kind colour tokens in the architecture brief.
* **Q-11** Bucket category grouping is case-sensitive ("Location" ≠ "location"). Keep (default) or merge
  case-insensitively?
* **Q-12** Calendar "All Upcoming"/"Agenda" exclude overdue-but-not-done items. Keep (default); an
  "Overdue" section like the floating window's would be an addition only if the lead approves.

---

## 10. PROGRESS.md sections folded into this spec

"Hierarchy › II. Tasks" (calendar inclusion), "Relationships", "Relationship Map (2D)", "Calendar /
Schedule Matrix", "Save / Load / Autosave" (UI-state restore), "Performance & stability" (debounce),
"UX fixes (2026-06-07)" (calendar wrap/double-click/inline done), "Link files in place (network-drive
routines) + Open all", "Task workflow status (model)", "Kanban Board (new top-level tab)", "Calendar:
more views, bigger + wrapped text", "Light / Dark theme (sleek dark mode)", "Full control theming",
"Jobs (approximate duration) + Planner (drag-drop scheduler)", "Strikethrough on completed checklist
items / tasks", "Update (2026-07-04): checklist steps act like subtasks", "Update (2026-07-06):
procedures on the calendar, scheduled jobs in the floating window, resizeable floating window, planner
search", "Crew items in due-dates & everywhere necessary", "Update (2026-07-08): quick-work window —
strike-through on done, and buckets", "Update (2026-07-08): buckets rework — predefined, own tab,
up-to-two, every level" (+ its adversarial-review fixes), "Update (2026-07-18): saved-list tasks in
Planner/Board, deadline-aware Planner" (items 2 and 3), "Optional working date-range on tasks &
subtasks", "Batch "mark as done" (right-click) + tab-drag crash fix", "Board shows every task and nested
subtask", "Deadline a whole checklist at once + read-only saved-list item viewer", "Batch delete for
tasks, procedures and equipment/areas" (Board hard-delete note), "Data-safety, reminders & housekeeping
batch" (Trash exclusion, recurrence), "Flash Sync: verified against the iPhone, and the `Ui` split fixed
on both sides" (per-device Ui keys).

---

## Addendum: Erratum: ItemPicker returns tags in selection order, not list order

This addendum corrects one wrong statement in this spec, and two others that repeat it. `ItemPickerWindow`
returns its tags in **selection order**, not list order. The addendum then states the full ordering contract of
the shared picker for **every** caller in the app, with the Mac decision for each. It also restates the agreed
"keep selections across filtering" improvement together with the ordering rule it needs. Nothing earlier in this
file has been deleted. Where this addendum and an earlier paragraph disagree, **this addendum wins**.

Sources read for this addendum:
* `AA/Views/ItemPickerWindow.xaml` (21 lines) and `ItemPickerWindow.xaml.cs` (55 lines), completely.
* `AA/Views/SavedListPicker.cs`, completely.
* Every construction site found by `grep -rn "ItemPickerWindow(" AA`: 26 sites, 25 of them `new ItemPickerWindow(`
  plus `new Views.ItemPickerWindow(` in `MainWindow.xaml.cs`. For each, the code that consumes `SelectedTags`,
  and the code that later displays or exports the resulting order: `AppRepository.RelatedItems`/`AddRelation`,
  `PdfExporter`, `ChecklistExporter`, `DataDiff`, `RelationshipMapPage`, `QuickWorkWindow` bucket rows, and
  `SirePage`.
* Cross-checked specs: 04 HIER-131 and §6.5; 04 Q-08 and Q-13; 05 CONT-093; 06 BUILD-034, BUILD-036, BUILD-131,
  D2 and R2; 08 QUICK-231, §6 (08:1227) and T-QW-11; 12 SIRE-030 and Q-11; 13 §3.11.9 (`DeepEquals`);
  14 TOOLS-018.
* PROGRESS.md: "Sidebar: alphabetical sort + groups" (why `singleSelect` exists), "Update (2026-07-08): buckets
  rework" ("capped at two via a multi-select picker") and "Update (2026-07-18)" item 2 (saved-list add).

### A.1 Erratum: what is corrected in this spec

| Where in 07 | Original text | Corrected statement |
|---|---|---|
| §7.6 Shared (07:1294-1295) | "`ItemPickerWindow` (saved-list add) → sheet … **keep selections across filtering** (Windows drops them — Q-08), OK returns selected in list order." | OK returns the selected tags **in selection order**. Pre-selected rows come first, in candidate-list order. Rows the user ticks afterwards follow in the order they were ticked. Ticking a row again after unticking it moves it to the end. Hidden (filtered-out) selections are kept on the Mac and keep their place in that sequence (VIEW-208, VIEW-210). The only deliberate exception is the SIRE candidate picker, which returns candidate order (VIEW-212, row 23). |
| VIEW-153 (07:653) | "…and keep the first two **in list order**" | Keep the first two **in selection order**. That means the item's current buckets first (in `QuickBuckets` order), then any newly ticked buckets in click order (VIEW-213). This matches 08 QUICK-231 and T-QW-11. |
| §8.4 K7 (07:1397) | "Picker returns 3 buckets → info message; first two in list order kept." | Replaced by vectors K7a–K7h in A.7. Example: ticking b3, b1, b2 on an unbucketed item gives `BucketIds = [b3, b1]`, **not** `[b1, b2]`. |
| VIEW-202 (07:750) | "Appended to `Data.Tasks` in pick order" | Correct. "Pick order" means selection order, which is click order because this caller pre-selects nothing (VIEW-214). |
| VIEW-202 quirk (07:752-753) | "typing in its search box replaces the list and drops earlier selections; only items selected in the final filtered view are returned" | Imprecise. A filter change deselects **only the rows the new filter hides**. Rows that stay visible keep their selection **and** their place in the sequence. A selection survives only if its row stayed visible through every later filter change. Clearing the search does **not** restore dropped selections (VIEW-209). |
| W-16 / Q-08 (07:1455, 07:1480) | "Saved-list picker drops selections when filtering → Fix (Q-08)"; "Keep picker selections across searches (recommended)" | **Agreed** app-wide, for every caller, not only the saved-list picker (VIEW-210). Q-08 is closed. The order rule for hidden selections is part of the decision. |

How other specs line up (informational only; those files are not edited here):

| Spec | Statement | Status |
|---|---|---|
| 04 HIER-131 | "OK → `SelectedTags` = tags of the selected rows, **in selection order**" | Correct. Its "Other callers" list is inaccurate: Board and Planner reach the picker only through `SavedListPicker`; the Calendar, the Buckets tab and the Quick Cards editor never open it. It also omits `MainWindow` (Drive backups), `ScheduleBuilderControl` and `ContainerEditor`. The authoritative list is VIEW-212. |
| 04 §6.5 (04:1154) | "Keep a selection set independent of the filter … OK returns tags in selection order" | Correct. VIEW-210 adds the ordering rule for hidden rows. |
| 04 Q-13, 06 R2, 12 Q-11 | Keep hidden selections | Same decision as VIEW-210. |
| 05 CONT-093 | LinkedItemIds "in selection order" | Correct. |
| 06 BUILD-034 (06:276) | "pre-selected ones first in list order" | Correct. |
| 06 BUILD-131 (06:695-700) | "changing the filter replaces the list and **drops any selection**" | Imprecise. See VIEW-209. |
| 08 QUICK-231 (08:665), 08:1227, T-QW-11 | "first two in selection order (pre-selected ones first, in list order, then newly clicked in click order)" | Correct. It is the reference wording for VIEW-213. |
| 12 SIRE-030 (12:231-240) | Mac adds in **candidate (display) order** | A deliberate deviation. It is recorded with its rationale in VIEW-212 row 23. |
| 14 TOOLS-018 | Single-selection backup picker | Order is not applicable (at most one tag). |

### A.2 FEATURE CHECKLIST (continued; Shared range 200–239)

**VIEW-208 Picker result order (Windows contract).** `ItemPickerWindow.SelectedTags` is
`Lb.SelectedItems.Cast<PickerItem>().Select(p => p.Tag)` (`ItemPickerWindow.xaml.cs:51`). WPF's
`SelectedItems` is kept in the order rows **entered** the selection:
1. **Pre-selection** (constructor, `:26-40`). In multi mode, every row whose `Tag` is in the preselect set is added
   by `Lb.SelectedItems.Add` while iterating `_all`, so these rows come first **in candidate-list order**. The order
   of the preselect sequence itself is **irrelevant**, because it is turned into a `HashSet<object>` at `:28`. In
   single mode only the **first** matching row in list order is selected (`Lb.SelectedItem = matches.FirstOrDefault()`,
   `:34`).
2. **User toggles.** In multi mode (`SelectionMode.Multiple`) each click (or Space on the focused row) toggles a row
   with no modifier needed. Ticking **appends** the row to the end. Unticking removes it. Ticking it again appends
   it at the end.
3. **Single mode.** Selecting another row replaces the selection, so the result holds at most one tag. Ctrl+click on
   the selected row deselects it, leaving zero.
4. **OK** (the `IsDefault` button, so Enter works from the search box too) returns the current sequence.
   **Cancel** returns `DialogResult = false`. There is no Esc binding (no `IsCancel`).

The result can be empty in either mode. What an empty OK does is caller-specific (VIEW-212).

**VIEW-209 Windows filtering: the exact drop rule.** `SearchBox_TextChanged` (`:43-48`) sets
`Lb.ItemsSource` to `_all` when the trimmed query is empty. Otherwise it sets it to a **new** `List` holding the
**same `PickerItem` instances** whose `Display` contains the query (`OrdinalIgnoreCase`). Each assignment to a
different list raises a collection Reset on the `ListBox`. WPF's `Selector` Reset handling then keeps selected
items that are still present in the new list and unselects those that are missing. The consequences are:
* A selected row hidden by the new query is **deselected at that moment**. It stays deselected when the query later
  changes or is cleared.
* A selected row that stays visible keeps its selection and its **position** in the sequence.
* This applies to single mode too: a selected row hidden by the filter leaves the picker with **no** selection.
* Typing the same query again assigns a new list, which is a no-op for the selection. Clearing to empty re-assigns
  `_all`, which is also a no-op, because every row is present.

Confidence: this is derived from the code (identical instances in both lists) and WPF `Selector` semantics. It
has not yet been reproduced in a WPF harness (Q-14). It is the **Windows baseline only**, because the Mac
deliberately changes it (VIEW-210).

**VIEW-210 Mac: keep selections across filtering (agreed improvement) and the ordering rule for hidden
selections.** This applies to **every** caller, in both modes. It supersedes W-16 and closes 07 Q-08, 04 Q-13,
06 R2 and 12 Q-11.
* The selection is a single **ordered sequence of candidate rows**. It is independent of the search text. Changing,
  typing or clearing the query **never** adds, removes or reorders anything in it.
* **Hidden selections keep their position.** A row selected before a filter hid it stays at the position where it
  was ticked. OK returns hidden and visible selected rows interleaved in that one sequence. Hidden rows are
  **not** moved to the front, not moved to the end, and not re-sorted into list order.
* Seeding, appending on tick, removing on untick and appending on re-tick all work exactly as in VIEW-208. As a
  result, with no search, the Mac returns **exactly** what Windows returns for the same clicks. The results differ
  only where Windows would have dropped a hidden selection.
* Bulk select, if offered (⌘A / Edit ▸ Select All while the list has focus, multi mode only): append every
  **visible**, not-yet-selected row in **display order** after the existing sequence. Hidden rows are not added.
  Windows has no Select All button. Whether WPF's own Ctrl+A select-all command is active in `Multiple` mode was
  not checked, and no Windows behaviour depends on it, so treat ⌘A as an addition. There is no bulk deselect;
  rows are unticked one at a time.
* **Visible feedback (required with this change).** Hidden selections are returned by OK, so the user must be able
  to see that they exist. The sheet shows a footer line in secondary label colour: `"{n} selected"`. When
  `k > 0` selected rows are hidden by the current query, the line reads `"{n} selected · {k} hidden by search"`.
  These are new, Mac-only strings, so flag them to localisation. Clearing the search shows those rows ticked.
* Rows **not** in the candidate list can never be selected. Examples are ids that point at deleted or trashed
  items, subtasks where only top-level tasks are offered, and stale bucket ids. They are dropped from the result
  exactly as on Windows (VIEW-215).

**VIEW-211 Mac: single-select contract.** At most one tag. Choosing a row replaces the choice, and the choice
survives filtering (VIEW-210), so a hidden choice is still returned. **OK is disabled until a row is chosen.**
Every single-mode caller treats "nothing chosen" as a no-op, except the two group pickers. For those, an empty OK
ungroups the items, which 04 Q-08 and 06 D2 already decided to prevent. Their explicit "(Ungrouped)" /
"(No group — ungrouped)" rows stay available. Double-click on a row means choose + OK, as 04 §6.5 adds. Return
means OK, and Esc means Cancel.

**VIEW-212 Per-caller order contract and Mac decision.** These are all 26 construction sites. "Order observable"
means the order of `SelectedTags` changes persisted data or something the user can see. **Default Mac decision:
keep selection order (VIEW-208/210).**

| # | Call site | Prompt (exact) | Mode | Preselect | How `SelectedTags` is consumed | Order observable? | Empty OK (Windows) | Mac decision | Spec |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `MainWindow.xaml.cs:782` | `Choose a backup to load from Google Drive (newest first)` | single | — | `FirstOrDefault() is DriveBackup` → download, review, import | No (≤ 1 tag) | returns silently | VIEW-211 | 14 TOOLS-018 |
| 2 | `Views/QuickWorkWindow.xaml.cs:478` (`SortIntoBuckets`; reached from `:463` for the selected item and `:801` for a builder child) | `Sort '{label}' into buckets (pick up to 2)` | multi | current buckets: `QuickBuckets.Where(b => target.BucketIds.Contains(b.Id))` | `OfType<QuickBucket>()`; if > 2, show the info message and `Take(2)`; `BucketIds.Clear()` then add in order; `Save()` | **Yes**: which two survive the cap; `BucketIds` array order (JSON, Flash Sync) | `BucketIds` emptied, `Save()` | **Selection order** (parity, VIEW-213) | 08 QUICK-231, 07 VIEW-153 |
| 3 | `QuickWorkWindow.xaml.cs:727` (`PickTemplate`; used by `:677` and `:687`) | `Insert a saved list` | single | — | `is ChecklistTemplate` → Replace/Append question | No | nothing | VIEW-211 | 08 QUICK-081 |
| 4 | `Views/SavedListsPage.xaml.cs:165` | `Manage groups — pick one` | single | — | `is ListGroup` → rename/delete question | No | nothing | VIEW-211 | 06 BUILD-078 |
| 5 | `SavedListsPage.xaml.cs:193` | `Move '{t.Name}' to group` | single | — (`Array.Empty`) | `pick is ListGroup g ? g.Id : null` → `GroupId`; `Save()` | No | **ungroups** the list | VIEW-211 (OK disabled). 06 D2 also pre-selects the current group | 06 BUILD-079 |
| 6 | `SavedListsPage.xaml.cs:348` | `Move {n} list to...` / `Move {n} lists to...` | single | — | `is int target` → `SavedListOrder.MoveTo` | No (the tag is a position) | nothing | VIEW-211 | 06 BUILD-087 |
| 7 | `Views/HierarchyPage.xaml.cs:268` (`AssignGroup_Click`) | `Move '{name}' to group` / `Move {n} items to group` | single | the common group (or `Guid.Empty` = "(Ungrouped)") when all picks share one | `Cast<Guid>().FirstOrDefault()`; `Guid.Empty` → `null`; set on every pick; `Save()` | No | `Guid.Empty` → **ungroups** all selected items | VIEW-211 (OK disabled) | 04 HIER-031, Q-08 |
| 8 | `HierarchyPage.xaml.cs:317` | `Pick a group to rename` | single | — | → rename prompt | No | nothing | VIEW-211 | 04 HIER-033 |
| 9 | `HierarchyPage.xaml.cs:338` | `Pick a group to delete (items inside become ungrouped)` | single | — | → confirm → delete | No | nothing | VIEW-211 | 04 HIER-034 |
| 10 | `HierarchyPage.xaml.cs:824` (`AddRel_Click`) | `Pick related items` | multi | — (additive) | `foreach tag: AddRelation(selected, tag)` appends to `selected.RelatedIds` (skipping ids already present) and appends `selected.Id` to the partner; `Save()` | **Yes**: `selected.RelatedIds` order drives the Relationships list (HIER-060, `RelatedItems` order) and the Relationship Map circle positions (VIEW-175/176). The item PDF is not affected (it sorts by kind and name). | nothing added; `Save()` still runs | **Selection order** | 04 HIER-061 |
| 11 | `HierarchyPage.xaml.cs:939` | `Pick procedures` | multi | `eq.ProcedureIds` (rows in `Data.Procedures` order) | replace `eq.ProcedureIds`; `Save()` | **Yes**: HIER-072 list, Relationships list (after `RelatedIds`), map, item PDF `Linked Procedures ({n})` | list cleared (unlinks all), `Save()` | **Selection order** + VIEW-215 | 04 HIER-072 |
| 12 | `HierarchyPage.xaml.cs:975` | `Pick tasks` | multi | `eq.TaskIds` (rows in `Data.Tasks` order, top-level only) | replace `eq.TaskIds`; `Save()` | **Yes**: HIER-073 list, Relationships, map, item PDF `Linked Tasks ({n})` | cleared, `Save()` | **Selection order** + VIEW-215 | 04 HIER-073 |
| 13 | `HierarchyPage.xaml.cs:1339` | `Pick tasks for this step` | multi | `st.TaskIds` (rows in `Data.Tasks` order) | replace `st.TaskIds`; `Save()` | **Yes**: item PDF step line `Tasks: a, b`; checklist PDF refs cell (`T: …` lines, then `E/A: …`, joined with `\n`); checklist xlsx `Linked Tasks` (joined with `"; "`) | cleared, `Save()` | **Selection order** + VIEW-215 | 04 HIER-095, 06 BUILD-034 |
| 14 | `HierarchyPage.xaml.cs:1367` | `Pick equipment/area for this step` | multi | `st.EquipmentIds` (rows in `Data.Equipment` order) | replace `st.EquipmentIds`; `Save()` | **Yes**: item PDF `Equipment/Area: ` line; checklist PDF `E/A:` lines; xlsx `Linked Equipment/Area` | cleared, `Save()` | **Selection order** + VIEW-215 | 04 HIER-095, 06 BUILD-036 |
| 15 | `Views/SavedListPicker.cs:46` (Board `BoardPage.xaml.cs:201`, Planner `PlannerPage.xaml.cs:114`) | `Search saved lists — pick items to add as tasks` | multi | — | each `ChecklistTemplateItem` → `ItemToTask` → `Data.Tasks.Add`, in order; one `Save()` if any | **Yes**: `Data.Tasks` order drives the Tasks sidebar (A→Z off), Board card order in a column (VIEW-042), the Planner pool (VIEW-084), stable-sort ties (§2.2) and JSON order | nothing created, no `Save()` | **Selection order** (VIEW-214) | 07 VIEW-202 |
| 16 | `Views/ScheduleBuilderControl.xaml.cs:114` | `Pick a {kind} to schedule` (enum name `Task`/`Procedure`/`Equipment`) | single | — | `is HierarchyItem` → title box + pending ref | No | nothing | VIEW-211 | 06 BUILD-114, 09 CREW-081 |
| 17 | `ScheduleBuilderControl.xaml.cs:199` | `Apply a saved schedule` | single | — | `is ScheduleTemplate` → apply question | No | nothing | VIEW-211 | 06 BUILD-122, 09 CREW-084 |
| 18 | `Views/SubtaskBuilderWindow.xaml.cs:58` | `Insert a saved list` | single | — | `is ChecklistTemplate` → Replace/Append | No | nothing | VIEW-211 | 06 BUILD-044/016 |
| 19 | `SubtaskBuilderWindow.xaml.cs:187` | `Move {n} subtask to...` / `Move {n} subtasks to...` | single | — | `is int` → `MoveItemsTo` (moved block keeps **list** order; picks are sorted by index) | No | nothing | VIEW-211 | 06 BUILD-044 |
| 20 | `Views/ChecklistBuilderControl.xaml.cs:150` | `Move {n} item to...` / `Move {n} items to...` | single | — | `is int` → `MoveStepsTo` | No | nothing | VIEW-211 | 06 BUILD-013 |
| 21 | `ChecklistBuilderControl.xaml.cs:224` | `Insert a saved list` | single | — | → Replace/Append | No | nothing | VIEW-211 | 06 BUILD-016 |
| 22 | `ChecklistBuilderControl.xaml.cs:249` | `Manage saved lists — pick one` | single | — | → rename/delete question | No | nothing | VIEW-211 | 06 BUILD-017 |
| 23 | `Views/SirePage.xaml.cs:429` (`PickAndAddTasks`; from `:389` Identified and `:418` AI Suggest) | `{n} tasks identified for Q {q} — tick to add:` / `Gemini suggested {n} tasks for Q {q} — tick to add:` | multi | **every** candidate | for each string in order: skip if empty or a case-insensitive duplicate of an existing task or of one added earlier in the batch; else `Sire.Tasks.Add`; `MarkDirty()` if any were added | **Yes**: `Sire.Tasks` order drives the question's task list (SIRE-026), SIRE exports and the `CreatedAt` sequence | nothing | **Deviation: candidate order** (see below) | 12 SIRE-030 |
| 24 | `SirePage.xaml.cs:455` (`PickKind`) | `Add to AA as which kind?` | single | the smart default kind | `is SireToAa.Kind` | No | `null` → add aborted | VIEW-211 | 12 SIRE-034 |
| 25 | `SirePage.xaml.cs:516` | `Choose a SIRE export:` | single | `Print Checklist` | `is string mode` | No | nothing | VIEW-211 | 12 SIRE-036 |
| 26 | `Views/ContainerEditor.xaml.cs:557` (`LinkSelectedToItems`, context `Link to items...`) | `Link '{fi.Name}' to items` | multi | `fi.LinkedItemIds` (rows sorted by kind — Equipment, Task, Procedure, Vessel — then by name, `OrdinalIgnoreCase`, stable) | replace `fi.LinkedItemIds`; `MarkDirty()` | Data only: not shown anywhere in the UI (CONT-093). JSON order, Flash Sync, and copies made by `CloneContainer` (saved lists, tasks created from them) | cleared, `MarkDirty()` | **Selection order** + VIEW-215 | 05 CONT-093 |

That is 26 sites: 9 multi-select (rows 2, 10–15, 23, 26) and 17 single-select. Order is observable only for the
nine multi-select sites.

**The one deliberate deviation: row 23 (SIRE candidate picker) returns candidate (display) order on the Mac.**
Rationale:
1. Every candidate is pre-selected, so on Windows selection order **equals** candidate order unless the user
   unticks and re-ticks a row. The Windows re-order in that case is a side effect of the widget, not a feature.
2. The candidates are generated in guidance-text order (offline identifier) or in Gemini's response order. That
   order is meaningful, and the SIRE task list cannot be reordered afterwards (SIRE-026: "Task text cannot be
   edited or reordered"). Candidate order is the only order the user can predict.
3. 12 SIRE-030 adds Select All / Select None to this sheet. With candidate order the result does not depend on how
   the user reached a given set of ticks.
4. Data compatibility is unaffected. `Sire.Tasks` is an ordered list that Windows reads in any order, and the
   deviation only changes the append order of new tasks, with `CreatedAt` following it.

The in-batch de-duplication (case-insensitive, first occurrence wins) is applied **after** re-ordering, so with
duplicate candidates the earliest one in candidate order is the one kept.

No other caller deviates. In particular the bucket cap (row 2) and the replace-semantics link pickers
(rows 11–14 and 26) keep Windows selection order. The same clicks must produce byte-identical arrays on both
platforms (A.4).

**VIEW-213 Bucket cap uses selection order (corrects VIEW-153).** After OK, `picked` is the selection sequence of
`QuickBucket`s. When more than two are picked, the info box titled `Sort into buckets` reads `An item can be in at
most two buckets — keeping the first two you picked.` and the code keeps `picked.Take(2)`. The consequences are:
* The item's current buckets always lead, so **ticking a third bucket on an item that already has two discards the
  new tick**. To swap a bucket, the user must untick one first.
* Opening the picker on merged data with more than two buckets and pressing OK unchanged keeps the first two in
  `QuickBuckets` order and shows the message.
* `BucketIds` is then rewritten in that order, even when unchanged (VIEW-215), and `Save()` runs on every OK.
* Mac parity: the same message, the same text and the same kept pair. A live hint when more than two are ticked is
  optional and display-only (Q-15). Ticking a third row must **not** be blocked, because that would make the
  message unreachable and change the result for merged data.

**VIEW-214 Saved-list add order (clarifies VIEW-202).** No pre-selection, so the order is click order. Each
picked item becomes a task **appended** to `Data.Tasks` in that order (`SavedListPicker.cs:50-55`), with one
`Save()` at `:56` if any were created. On the Mac, with VIEW-210, items ticked under different searches are all
added, in the order they were ticked.

**VIEW-215 Replace-semantics pickers normalise the stored list on every OK** (rows 2, 11, 12, 13, 14, 26;
Windows behaviour kept on the Mac). The picker seeds its selection from the stored ids, so an OK with no user
changes still:
1. **re-orders** the stored ids into candidate-list order. For rows 11/12/13/14 that is `Data.Procedures` /
   `Data.Tasks` / `Data.Equipment` order; for row 26 it is kind-then-name order; for row 2 it is `QuickBuckets`
   order;
2. **drops** ids that have no candidate row: deleted or trashed items, subtask ids (only top-level tasks are
   offered), and stale bucket ids;
3. **collapses duplicate ids** to one;
4. **persists**: `Save()` for rows 2 and 11–14, `MarkDirty()` for row 26. `LastModified` is stamped even when
   nothing changed.

The item's JSON changes only when (1)–(3) actually changed something. When it does change, Flash Sync treats the
item as changed (A.4). Whether the Mac should instead preserve the stored order is Q-13; the default is parity.

**VIEW-216 Row identity versus tag equality.** On Windows a row is a `PickerItem` **instance**. Pre-selection
matches tags with `object.Equals` through `HashSet<object>`, which means value equality for `Guid`, `string`,
`int` and enums, and **reference identity** for model objects (`QuickBucket`, `ChecklistTemplate`,
`ChecklistTemplateItem`, `ListGroup`, `ScheduleTemplate`, `HierarchyItem`, `DriveBackup`). Two rows may carry
equal tags. In that case both are pre-selected and both tags are returned: SIRE duplicate candidate strings, or
two items sharing an id in corrupted data. The Mac must:
* identify rows by **candidate index**, never by tag, so equal tags remain distinct rows;
* pre-select every row whose tag is in the preselect set;
* return tags (duplicates included) for the caller to de-duplicate, as SIRE does.

For model objects, use the model's id as the tag. `ChecklistTemplateItem` has **no id**, so tag it with
`(templateId, itemIndex)` and resolve it at OK time. Skip any tag whose template or item no longer resolves, for
example after a reload while the sheet was open (06 R1).

### A.3 LOGIC & ALGORITHMS

**A.3.1 `ItemPickerWindow` code walk** (`AA/Views/ItemPickerWindow.xaml.cs`).
* `:8-12` `PickerItem { string Display = ""; object Tag }`.
* `:19-41` constructor `(string prompt, IEnumerable<PickerItem> items, IEnumerable<object>? preselect = null,
  bool singleSelect = false)`:
  * `LblPrompt.Text = prompt`; `_all = items.ToList()` (materialised once, candidate order fixed);
    `SelectionMode = singleSelect ? Single : Multiple`; `ItemsSource = _all`.
  * If `preselect` is non-null: `set = preselect.ToHashSet()` and `matches = _all.Where(it => set.Contains(it.Tag))`
    in list order. Single mode: `SelectedItem = matches.FirstOrDefault()`. The comment at `:32-33` notes that
    `SelectedItems` is read-only in Single mode and would throw. Multi mode: `SelectedItems.Add(it)` for each match
    in order.
* `:43-48` `SearchBox_TextChanged`: `q = SearchBox.Text?.Trim() ?? ""`; `ItemsSource = q.IsEmpty ? _all :
  _all.Where(i => i.Display.Contains(q, OrdinalIgnoreCase)).ToList()`. There is no debounce.
* `:49-53` `Ok_Click`: `SelectedTags = Lb.SelectedItems.Cast<PickerItem>().Select(p => p.Tag).ToList()`;
  `DialogResult = true`.
* `:54` `Cancel_Click`: `DialogResult = false`. Closing the window also gives `false`.
* XAML (`ItemPickerWindow.xaml`): the title is always `Pick items`; the window is 500×500, `CenterOwner`;
  `LblPrompt` is bold, default text `Select items:` (always overwritten); `SearchBox` has no placeholder;
  `Lb` uses `DisplayMemberPath="Display"`; buttons are `Cancel` (80) and `OK` (80, `AccentButton`, `IsDefault`).

**A.3.2 Windows reference model (oracle for documentation and harness checks).**
```
state: order: [Row]            // selection sequence, no duplicates (rows are instances)
       visible: [Row] = all

init(preselect):  S = Set(preselect)
                  if single: order = [first r in all where S ∋ r.tag] (or [])
                  else:      order = [r in all where S ∋ r.tag]        // candidate order

click(r) multi:   if order ∋ r: order.remove(r) else order.append(r)
click(r) single:  order = [r]            // Ctrl+click on the selected row: order = []
query(q):         q' = trim(q); visible = q'.isEmpty ? all : all.filter { $0.display.containsOrdinalIgnoreCase(q') }
                  order.removeAll { !visible.contains($0) }   // Reset → unselect missing rows (VIEW-209)
ok():             return order.map(\.tag)
```

**A.3.3 Mac model (`OrderedPickerSelection`, a pure value type, unit-tested).**
```
struct OrderedPickerSelection {
  let single: Bool
  private(set) var order: [Int]          // candidate indices, in selection order
  private var members: Set<Int>

  init(tags: [Tag], preselect: some Sequence<Tag>, single: Bool)
      S = Set(preselect)
      matches = tags.indices.filter { S.contains(tags[$0]) }          // candidate order
      order = single ? Array(matches.prefix(1)) : matches

  mutating func toggle(_ i: Int)          // multi: remove if present, else append
  mutating func choose(_ i: Int)          // single: order = [i]
  mutating func selectAllVisible(_ visible: [Int])   // multi: append visible ∉ members, in display order
  func isSelected(_ i: Int) -> Bool
  func hiddenCount(visible: Set<Int>) -> Int         // for the footer
  func result(order policy: ResultOrder) -> [Int]    // .selection → order; .candidate → order.sorted()
}
```
Changing the query only recomputes `visible` and never touches `order`. For row 23, `result(.candidate)` sorts
the indices ascending, which is candidate order, before mapping them to tags. Every other caller uses
`.selection`.

**A.3.4 Search matching.** The trimmed query uses .NET `Trim()`, i.e. Unicode white space. An empty or blank query
shows every row. A row is visible when `Display` contains the query under `OrdinalIgnoreCase`. Use the shared
`containsOrdinalIgnoreCase` helper (04, pseudocode at 04:740; semantics as 02's `caseInsensitiveOrdinal`,
02:1238). Do **not** use `localizedStandardContains`, which is diacritic-insensitive and would show more rows
than Windows. Visible rows keep candidate order. Filtering runs on every keystroke with no debounce; the lists
are small.

**A.3.5 Consumers that depend on order** (Windows code, reproduced exactly on the Mac):
* Bucket cap, `QuickWorkWindow.xaml.cs:480-489`:
  `picked = tags.OfType<QuickBucket>(); if picked.count > 2 { info; picked = picked.prefix(2) };
  target.BucketIds = picked.map(\.Id); Save()`.
* Saved-list add, `SavedListPicker.cs:50-56`: `for it in tags { t = ItemToTask(it); Data.Tasks.append(t) }; if any { Save() }`.
* Relations, `HierarchyPage.xaml.cs:826-830` with `AppRepository.AddRelation` `:212-217`:
  `for x in tags { guard a.Id != x.Id; if !a.RelatedIds.contains(x.Id) { a.RelatedIds.append(x.Id) };
  if !x.RelatedIds.contains(a.Id) { x.RelatedIds.append(a.Id) } }; Save()`. Candidates exclude the current item,
  so the self-guard never triggers from this picker.
* Replace pickers (rows 11–14, 26): `list.removeAll(); list.append(contentsOf: tags)`, then `Save()` or
  `MarkDirty()`.
* SIRE, `SirePage.xaml.cs:430-439`: `existing = Set(caseInsensitive: tasksFor(q).map(\.Text));
  for s in tags { if s.isEmpty || existing ∋ s { continue }; Sire.Tasks.append(SireTask(q, s)); existing.insert(s) };
  if added > 0 { MarkDirty(); refresh }`. On the Mac `tags` is in candidate order (row 23).

**A.3.6 Where the resulting order surfaces** (so verifiers know what to look at):
* `AppRepository.RelatedItems` (`:150-163`) enumerates `RelatedIds`, then Equipment `ProcedureIds`, then `TaskIds`,
  through a `HashSet`, so an id that appears in two lists shows once, at its first position. This order feeds the
  Relationships list and `RelationshipMapPage.DrawMap` (node `i` at angle `2π·i/n`).
* `PdfExporter`: `Linked Procedures ({n})` and `Linked Tasks ({n})` iterate stored order (`:339-367`). Step
  `Equipment/Area: ` and `Tasks: ` lines are joined with `", "` in stored order (`:462-478`). `Relationships ({n})`
  is sorted by kind and then by name (`:514-525`), so it is **not** order-sensitive.
* `ChecklistExporter`: the PDF refs cell lists `T: {name}` for each `TaskIds` entry, then `E/A: {name}` for each
  `EquipmentIds` entry, joined with `"\n"` (`:93-100`). The xlsx columns `Linked Tasks` and
  `Linked Equipment/Area` are joined with `"; "` (`:125-126`).
* `DataDiff`: for added items it lists `linked procedure/task/equipment/area` nodes in stored order
  (`:104-105`, `:128-129`). For changed items `DiffLinks` (`:241-247`) is **set-based**, so a pure reorder shows no
  link change in the import review.
* Quick-work bucket grouping sorts groups by bucket name, so `BucketIds` order is not visible there.

### A.4 DATA FORMATS

Serializer facts are as in §5.1: `System.Text.Json`, no naming policy, Guid as lowercase `"D"`, arrays in list
order, nulls omitted.

| JSON location | Key | Element | Written by (VIEW-212 row) | Order semantics |
|---|---|---|---|---|
| any bucketable: `Tasks[]` (+ nested `Subtasks[]`), `Procedures[]`, `Procedures[].Steps[]` | `BucketIds` | guid string | 2 (replace) | selection order, with current buckets first in `QuickBuckets` order; ≤ 2 from this UI, any count accepted on read |
| every top-level item | `RelatedIds` | guid string | 10 (append) | existing ids untouched; new ids appended in selection order; each partner gets the current id appended |
| `Equipment[]` | `ProcedureIds`, `TaskIds` | guid string | 11, 12 (replace) | selection order; normalised per VIEW-215 |
| `Procedures[].Steps[]` | `TaskIds`, `EquipmentIds` | guid string | 13, 14 (replace) | selection order; normalised per VIEW-215 |
| `…Container.Files[]` (every container; path per 05) | `LinkedItemIds` | guid string | 26 (replace) | selection order; normalised per VIEW-215 |
| root | `Tasks` (array order) | task object | 15 (append) | new tasks appended in selection order |
| `Sire` | `Tasks` | `SireTask` object | 23 (append) | Windows: selection order. Mac: **candidate order** (deviation) |

Compatibility rules:
1. All of these are **ordered JSON arrays**. Neither platform sorts them or removes duplicates when loading.
   Swift models must decode them into arrays (`[UUID]`, `[TaskItem]` …), never into `Set`. Mac code must not
   "tidy" them on save.
2. **Flash Sync compares arrays element by element** (13 §3.11.9 `DeepEquals`: "arrays: … order matters"). A pure
   re-order therefore makes the owning item "changed", and the whole item is sent. That is why the Mac must produce
   Windows' order for the same interaction: identical clicks give byte-identical arrays, and a cross-platform
   interop harness snapshot stays equal. The known exceptions are the SIRE candidate order and cases where
   Windows would have dropped a hidden selection.
3. Windows reads any order and any count that the Mac writes, including `BucketIds` with more than two entries
   (the cap is UI-only; VIEW-153).
4. The Windows import-review diff (`DataDiff.DiffLinks`) ignores order, so it cannot be used to verify ordering.
   Compare raw JSON instead.
5. None of this touches rich text (XAML), files, zips, PDFs or xlsx *formats*. The PDF and xlsx outputs only
   *show* the order (A.3.6).

### A.5 DEPENDENCIES

* **Into the picker:** the 26 construction sites in VIEW-212, through `SavedListPicker.PickAndAddTasks` for Board
  and Planner, `QuickWorkWindow.SortIntoBuckets` / `PickTemplate`, and `SirePage.PickAndAddTasks` / `PickKind`.
* **Out of the picker:** nothing. It is pure UI, with no repository access, persistence or logging. All
  persistence (`Save()` / `MarkDirty()`) happens in the callers, as listed in VIEW-212.
* **Windows-only pieces relied on:**

| Windows mechanism | Used for | Mac equivalent |
|---|---|---|
| WPF `ListBox` `SelectionMode.Multiple` / `Single` | click-toggle multi select; single select | a SwiftUI `List` of rows with a checkbox `Toggle` (multi) or a radio-style row (single) bound to `OrderedPickerSelection`. Do **not** use `List(selection: Set<ID>)` as the source of truth: a `Set` has no order, and its behaviour when rows disappear from a filtered data source is not something to rely on. |
| `Selector.SelectedItems` insertion order | result order | `OrderedPickerSelection.order` |
| `ItemsSource` replacement → Reset → unselect missing rows | the Windows filter-drop quirk | **not reproduced** (VIEW-210) |
| `IsDefault` OK button; no `IsCancel` | Enter = OK | `.keyboardShortcut(.defaultAction)` on OK, plus `.cancelAction` on Cancel (Esc added) |
| `Window.ShowDialog()` with `Owner` | modal, centred | `.sheet` on the presenting window; an `async` result (`[Tag]?`, `nil` = Cancel) |

### A.6 macOS ADAPTATION NOTES

* **One generic sheet.** The API is `presentItemPicker(prompt:rows:preselect:mode:resultOrder:) async -> [Tag]?`
  with `Tag: Hashable & Sendable`, `mode: .single | .multi` and `resultOrder: .selection` (default) `| .candidate`
  (row 23 only). It is `@MainActor`. Callers resolve tags to live model objects by id **at OK time**. Rows are
  `(display: String, tag: Tag)` in the caller's candidate order; the sheet assigns candidate indices.
* **Layout.** The caller's prompt is the sheet heading, which replaces the Windows bold label; the window title
  `Pick items` has no Mac counterpart in a sheet. Below it is a search `TextField` with a `magnifyingglass` prefix,
  focused on appear, placeholder `Search`. This is an addition (Windows has no placeholder), and ⌘F focuses the
  field. The `List` rows wrap long text. Then comes the footer line (VIEW-210), and `Cancel` / `OK` at the bottom
  trailing edge. Minimum size is about 420×460 and the sheet is resizable (04 §6.5). Callers that have their own
  sheet (12 `TaskCandidatePickerSheet`) may still wrap this component.
* **Interaction.** In multi mode a click anywhere on the row toggles it (Windows parity: no modifier needed), and
  Space toggles the focused row. There is no double-click action in multi mode, where a double-click is simply two
  toggles, as on Windows. In single mode a click chooses and a double-click chooses and confirms. ⌘A (multi) is
  covered by VIEW-210 bulk-select. Return = OK, Esc = Cancel.
* **State ownership.** The sheet's `@State var selection: OrderedPickerSelection` and `@State var query` are the
  only state. `visible` is derived from them. With Swift 6 strict concurrency the sheet is `@MainActor`; no
  background work is needed.
* **Appearance.** Use system list and selection colours and SF Symbols (`checkmark.square.fill` / `square` or a
  native `Toggle(.checkbox)`; `largecircle.fill.circle` / `circle` for single mode). The footer uses secondary
  label colour. Dark mode needs nothing extra; there were no custom theme colours on Windows beyond
  `AccentButton` for OK, which maps to `.borderedProminent`.
* **Accessibility.** Each row is exposed as a toggle with its display text. The footer is an accessibility label
  that updates live ("3 selected, 1 hidden by search").
* **Nothing is impossible on macOS here.** The only behavioural differences from Windows are the deliberate ones:
  VIEW-210 (hidden selections kept, footer), VIEW-211 (single mode: OK disabled until chosen, Esc, double-click),
  row 23 (candidate order), and the optional ⌘A.

### A.7 TEST VECTORS

Unless a vector says otherwise, candidates are `[A, B, C, D]` with displays `"Alpha"`, `"Bravo"`, `"Charlie"`,
`"Delta"`. `order` lists the result tags.

**Selection model (`OrderedPickerSelection`, Mac):**

| # | Steps | Expected result |
|---|---|---|
| P1 | multi, preselect `{C, A}` (passed in that order) | initial `[A, C]`: candidate order, not preselect order |
| P2 | P1, then tick D, tick B, OK | `[A, C, D, B]` |
| P3 | P1, then untick A, tick A | `[C, A]` |
| P4 | P1, query `"br"` (only Bravo visible), tick B, OK | `[A, C, B]`: hidden A and C kept at their positions; footer `3 selected · 2 hidden by search` |
| P5 | multi, no preselect: tick C; query `"elt"` (Delta only); tick D; query `"alp"` (Alpha only); tick A; clear query; OK | `[C, D, A]`: C stayed first although it was hidden during both searches |
| P6 | preselect `{X}` where X is not a candidate | initial `[]`; OK → `[]` |
| P7 | candidates `["Check log", "Check log"]` (equal tags), preselect `{"Check log"}` | both rows selected; OK → `["Check log", "Check log"]` |
| P8 | single, candidates `[(Ungrouped), G1, G2]`, preselect `{G1}` | `[G1]`; choose G2 → `[G2]`; query `"zzz"` (nothing visible) → still `[G2]`, OK enabled |
| P9 | single, no preselect | OK disabled; choose G1 → enabled; OK → `[G1]` |
| P10 | multi, selection `[D]`; query `"r"` (visible Bravo, Charlie); ⌘A; clear; OK | `[D, B, C]`: visible rows appended in display order, hidden Alpha not added |
| P11 | `result(.candidate)` after ticking D, B, A | `[A, B, D]` |
| P12 | query `"  "` (spaces only) | all four rows visible |
| P13 | query `"ALPHA"` | Alpha visible (ordinal ignore-case) |

**Windows oracle (A.3.2), used to document and confirm the baseline (Q-14):**

| # | Steps | Windows result | Mac result |
|---|---|---|---|
| W1 | preselect `{A}`; tick C; query `"br"`; tick B; clear query; OK | `[B]` (A and C dropped when hidden) | `[A, C, B]` |
| W2 | preselect `{A, C}`; query `"alp"`; clear; OK | `[A]` | `[A, C]` |
| W3 | no query: tick C, A, B; OK | `[C, A, B]` | `[C, A, B]` (identical without filtering) |
| W4 | single, preselect `{G1}`; query that hides G1; OK | `[]` | `[G1]` |

**Buckets (corrected K7; `QuickBuckets = [b1 "Bridge", b2 "Engine room", b3 "Galley"]`):**

| # | Setup / steps | Expected |
|---|---|---|
| K7a | item `BucketIds []`; tick b3, b1, b2; OK | info `An item can be in at most two buckets — keeping the first two you picked.`; `BucketIds = [b3, b1]` (the old "list order" wording would have given `[b1, b2]`, which is wrong) |
| K7b | `BucketIds [b2, b1]`; OK unchanged | no message; `BucketIds = [b1, b2]` (normalised); `Save()`; JSON array changed, so Flash Sync ships the item |
| K7c | `BucketIds [b1, b2]`; tick b3; OK | message; `BucketIds = [b1, b2]` (the new tick is discarded) |
| K7d | `BucketIds [b1, b2]`; untick b2, tick b3; OK | `[b1, b3]`, no message |
| K7e | merged data `BucketIds [b3, b1, b2]`; OK unchanged | message; `[b1, b2]` |
| K7f | `BucketIds [<dangling id>, b2]`; OK unchanged | `[b2]` |
| K7g | Mac: `BucketIds [b1]`; query `"gal"`; tick b3; clear; OK | `[b1, b3]` (Windows: `[b3]`, b1 dropped while hidden) |
| K7h | untick everything; OK | `BucketIds = []`, `Save()` |

**Saved-list add** (lists `Engine = [Pump, Valve]`, `Deck = [Winch (IsJob)]`; rows `Engine  ›  Pump`,
`Engine  ›  Valve`, `Deck  ›  Winch   · schedulable`):

| # | Steps | Expected |
|---|---|---|
| SL1 | tick Winch, then Pump; OK | `Data.Tasks` gains `[…existing, "Winch", "Pump"]`; one `Save()`; Board To Do shows Winch before Pump |
| SL2 | Mac: query `"pump"`, tick Pump; query `"winch"`, tick Winch; OK | `[…, "Pump", "Winch"]` (Windows: only `"Winch"`) |
| SL3 | OK with nothing ticked | no tasks, no `Save()` |

**Replace and relation pickers:**

| # | Setup / steps | Expected |
|---|---|---|
| R1 | `Data.Procedures [P1, P2, P3]`, `E.ProcedureIds [P3, P1]`; Pick procedures; OK unchanged | `[P1, P3]` |
| R2 | R1, then tick P2; OK | `[P1, P3, P2]` |
| R3 | R2's state `[P1, P3, P2]`, reopen: seeded `[P1, P2, P3]`; untick P1, tick P1; OK | `[P2, P3, P1]` |
| R4 | step `TaskIds [<trashed id>, T1, T1]`; Pick tasks for this step; OK unchanged | `[T1]` |
| R5 | file `LinkedItemIds [Task "Zeta", Equipment "Alpha"]`; Link to items; OK unchanged | `[Alpha (Equipment), Zeta (Task)]` (kind order first); `MarkDirty()` |
| R6 | item X `RelatedIds [V]`; Pick related items: tick T, then E (E is listed above T); OK | `X.RelatedIds = [V, T, E]`; `T.RelatedIds` and `E.RelatedIds` each end with X; map positions V (1010, 450), T (545, 718.4679), E (545, 181.5321) (±1e-4) |
| R7 | X `RelatedIds [T]`; tick T, V; OK | `[T, V]` (T not duplicated) |
| R8 | Pick related items, OK with nothing ticked | nothing added; `Save()` still called |

**SIRE (row 23; candidates in order `["Check log", "Test alarm", "Verify seal"]`, all pre-ticked):**

| # | Steps | Windows | Mac |
|---|---|---|---|
| S1 | untick "Check log", re-tick it; OK | appends `Test alarm, Verify seal, Check log` | appends `Check log, Test alarm, Verify seal` |
| S2 | the question already has task "test ALARM"; OK | appends `Check log, Verify seal` | same |
| S3 | candidates `["Check log", "check LOG", ""]`; OK | appends `Check log` only | same |
| S4 | Mac: query `"seal"`, then OK | (Windows: only `Verify seal`) | all three, in candidate order |

**Single-mode callers:**

| # | Steps | Windows | Mac |
|---|---|---|---|
| G1 | Hierarchy "Move to group": all picks in group Pumps (pre-selected); query hides Pumps; OK | empty result → `Guid.Empty` → items **ungrouped** | `[Pumps]` → no change |
| G2 | Saved Lists "Move to group", OK without choosing | list ungrouped | OK disabled (06 D2) |
| G3 | "Choose a SIRE export:" opens | `Print Checklist` selected | same |

### A.8 Quirks and open questions (continuing §9)

| ID | Quirk | Mac decision |
|---|---|---|
| W-21 | Earlier text in this spec (§7.6, VIEW-153, K7) said the picker returns **list** order | Corrected by this addendum (A.1). Selection order is the contract. |
| W-22 | Replace-semantics pickers re-order and prune stored ids on an unchanged OK (VIEW-215) | Replicate (Q-13). |
| W-23 | Re-ticking a SIRE candidate moves it to the end of the new tasks | Mac uses candidate order (VIEW-212 row 23). |

* **Q-13** Rows 2, 11–14 and 26 rewrite stored order and drop dangling ids even when the user changed nothing.
  Keep parity (default: identical arrays on both platforms for the same interaction), or have the Mac preserve
  the stored order of untouched ids and append new ones? Parity is recommended. The alternative would make Mac and
  Windows produce different arrays for the same clicks, and would cause Flash Sync churn in mixed fleets.
* **Q-14** Confirm VIEW-209 (the precise Windows drop rule) in the WPF harness. Script: preselect A; tick C; type a
  query that shows only B; tick B; clear; OK. Expected `SelectedTags = [B]`. This only documents the baseline; the
  Mac behaviour (VIEW-210) does not depend on it.
* **Q-15** Optional display-only hint in the bucket picker when more than two rows are ticked (for example
  `Only the first two will be kept`, a new string). It must not block ticking or suppress the Windows message
  (VIEW-213).
* **Q-08** is **closed**: agreed as VIEW-210 for every caller.
