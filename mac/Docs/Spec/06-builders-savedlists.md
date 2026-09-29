# 06 — Builders & Saved Lists (feature prefix `BUILD-`)

Porting spec for the **checklist / subtask / schedule builders** and the **Saved Lists** (reusable
checklist templates) subsystem of the WPF app `AA`, for the native macOS Swift port (SwiftUI + AppKit,
macOS 26+, Swift 6.4 toolchain, see `mac/Docs/ARCHITECTURE-BRIEF.md`).

This document is a contract. Every string in `"double quotes"` below is the exact text the Windows build
shows (C# escapes such as `\n` are line breaks). Where the Mac build should deliberately differ, the
difference is called out as **Mac deviation** together with the reason, and never removes a capability.

---

## 0. Sources read

All paths relative to `/Users/eriskay/erisdev/AA/AA` unless noted.

| File | Role |
|---|---|
| `Views/ChecklistBuilderControl.xaml` / `.xaml.cs` (79 / 286 lines) | The shared "comprehensive checklist builder" UserControl (bulk entry, reorder, per-item editor, saved-list bar). |
| `Views/ChecklistBuilderWindow.xaml` / `.xaml.cs` | Procedure host window for the control. |
| `Views/ChecklistStepEditorWindow.xaml` / `.xaml.cs` | Per-step editor (title, deadline, done, job, duration, notes + files). |
| `Views/SubtaskBuilderWindow.xaml` / `.xaml.cs` | Comprehensive subtask builder for a Task. |
| `Views/SubtaskEditorWindow.xaml` / `.xaml.cs` | Per-subtask (any `TaskItem`) editor incl. working range. |
| `Views/TemplateEditorWindow.xaml` / `.xaml.cs` | Edits a saved list by round-tripping it through the builder. |
| `Views/ScheduleBuilderControl.xaml` / `.xaml.cs` | Crew schedule timeline builder + schedule templates. |
| `Views/SavedListsPage.xaml` / `.xaml.cs` | The **Saved Lists** main tab. |
| `Services/ChecklistTemplateService.cs` | Capture / apply / clone / write-back of saved lists. |
| `Services/SavedListOrder.cs` | Arranged order of saved lists (reorder within group, export ordering). |
| `Services/ScheduleService.cs` | Schedule template capture / apply / JSON export & import. |
| `Services/WorkRange.cs` | Start/deadline coercion used by the subtask editor. |
| `Services/PdfExporter.cs` (`ExportSavedLists`, `DefineStyles`, `WriteContainerBody`, `StripXamlTags`, `H1/H2`) | Saved-list PDF. |
| `Services/ChecklistExporter.cs` | Procedure checklist-only PDF + XLSX (reached from the procedure checklist area). |
| `Services/ListFormatting.cs` (`Build`, `ApplySpacing`) | XAML list shape produced by "insert saved list into a note". |
| `Services/AppRepository.cs` (`MarkDirty`, `Save`, `FlushIfDirty`, `LogAdded/LogRemoved`, `AllContainers`, `AllJobs`, `ReconcileRecurrences`) | Persistence + log semantics. |
| `Services/DataStore.cs` (`Opts`, `SerializeForSave`, `EnumerateContainers`, `ResolveFilePath`) | JSON options, bundling of template containers. |
| `Views/InsertSavedListWindow.*`, `Views/SavedListPicker.cs`, `Views/ListStylePromptWindow.*`, `Views/ContainerViewerWindow.*`, `Views/PromptWindow.*`, `Views/ItemPickerWindow.*` | Dialogs this subsystem uses / saved-list consumers. |
| `Views/HierarchyPage.xaml.cs` lines 999–1161 (`BuildTaskSpecifics`) and 1163–1423 (`BuildProcedureSpecifics`, `ExportChecklist`) | Hosts: task subtasks area and procedure "Checklist Steps" area (step ↔ task/equipment links = the brief's "banked tasks"). |
| `Views/CrewEditorWindow.xaml` / `.cs`, `Views/CrewPage.xaml.cs` (re-import) | Crew host (Checklist + Schedule tabs). |
| `Views/QuickWorkWindow.xaml.cs` lines 540–740 | Ctrl+N inline builder that reuses the saved-list flows. |
| `Models/Models.cs`, `Models/CrewMember.cs` | All models touched. |
| `/Users/eriskay/erisdev/AA/PROGRESS.md` sections: "Arrange the order saved lists appear in (and export in)", "Saved-list PDF export asks bulleted or numbered, every time", "Insert a saved list into a note…", "Hierarchy ▸ III. Procedures", "Per-subtask deadline and container", "Per-step container on every checklist step", "Checklist builder window", "Checklist-only export (PDF + Excel)", "Jobs (approximate duration) + Planner", "Strikethrough on completed checklist items / tasks", "Update (2026-07-04): checklist steps act like subtasks", "Update (2026-07-04): comprehensive subtask builder", "Per-crew-member checklist", "Reusable saved lists (templates) in every builder", "Saved Lists tab + List Groups", "PDF export (lists & groups)", "Per-crew scheduler", "Update (2026-07-18) 1./2.", "Optional working date-range on tasks & subtasks", "Deadline a whole checklist at once + read-only saved-list item viewer", "buckets rework" | Rationale and history. |
| `/Users/eriskay/erisdev/AA/QR_SYNC_PROTOCOL.md` §10 (change sets, `Order`, `Ui` merge) | How template order and `Ui.SortAZ` travel. |
| `/Users/eriskay/erisdev/AA/Create a Windows WPF C# application.txt` | Brief: "Each procedure can then have 1. Checklists 2. Logic to add tasks and equipment for each step" / "Each checklist in each procedure may use banked tasks, or the user may create one". |

---

## 1. Overview

The subsystem is everything that **builds ordered lists of work items** and everything that **saves such a
list for reuse**:

1. **Checklist builder** (`ChecklistBuilderControl`) — a two-pane editor over any
   `ObservableCollection<ChecklistStep>`. Three hosts:
   * **Procedure** → `ChecklistBuilderWindow` (modal), opened from the Procedures tab ▸ item ▸ *Specifics*
     tab ▸ "🛠  Open Comprehensive Checklist Builder", and from the Ctrl+N quick-work window ("Open full builder").
   * **Crew member** → the *Checklist* tab of `CrewEditorWindow` (Crew tab ▸ edit member / "🗒 Open checklist...").
   * **Saved list** → `TemplateEditorWindow` (modal), opened from the Saved Lists tab ▸ "✎ Edit items...".
2. **Checklist step editor** (`ChecklistStepEditorWindow`) — full editor for one `ChecklistStep`
   (title, per-step deadline, done, schedulable job + duration, rich-text notes + file bank). Also opened
   from Calendar, Planner, Buckets tab, Ctrl+N window and the procedure Specifics tab.
3. **Procedure "Checklist Steps" area** (in `HierarchyPage.BuildProcedureSpecifics`) — inline step grid with
   Done/Job/Title/Deadline, add/remove, **link existing ("banked") tasks**, **create a new task auto-linked to
   the step**, **link equipment/areas**, batch done/deadline menu, and checklist-only PDF/XLSX export. (Overlaps
   the hierarchy spec; specified here because the brief defines it as the procedure checklist feature.)
4. **Subtask builder** (`SubtaskBuilderWindow`) — the same two-pane builder for a Task's direct `Subtasks`,
   each a full `TaskItem`; opened from Tasks tab ▸ *Specifics* ▸ "🛠  Open Comprehensive Subtask Builder" and
   from Ctrl+N.
5. **Subtask editor** (`SubtaskEditorWindow`) — full editor for any `TaskItem` (used for subtasks, and by
   Board/Calendar/Planner/Buckets for tasks): name, description, deadline + optional working-range start,
   recurrence, status ⇄ completed sync, job + duration, notes + files.
6. **Saved lists** (`ChecklistTemplate`) — reusable "full copies" of a checklist (title, duration, schedulable
   flag, notes + files per item; never deadlines/done). Saved from / loaded into every builder, managed in the
   **Saved Lists** main tab (groups, arranged order, A–Z view, rename, duplicate, edit items, read-only item
   viewer, PDF export of one list / a group / all, bulleted-or-numbered prompt every time). Also consumed by
   "insert saved list into a note" (rich-text editor) and "add tasks from saved lists" (Board, Planner).
7. **Crew schedule builder** (`ScheduleBuilderControl`) — the *Schedule* tab of the crew editor: a dated
   timeline of notes / task / procedure / equipment references, linked vessel, and reusable **schedule
   templates** (save / apply / export `.aasched.json` / import).

Everything persists into `data.json` (`AppData.Procedures[].Steps`, `Tasks[].Subtasks`, `Crew[].Checklist`,
`Crew[].Schedule`, `Crew[].ScheduleVesselId`, `ChecklistTemplates`, `ListGroups`, `ScheduleTemplates`,
`Ui.SortAZ["savedlists"]`, `Log`). Template item containers are bundled with attachments in `.aaz/.zip`
exports and shared saves (they are in `DataStore.EnumerateContainers` and `AppRepository.AllContainers`).

---

## 2. Feature checklist

Notation: **[persist: X]** = how the change reaches disk: `MarkDirty` (750 ms debounced background save),
`Save` (immediate synchronous save), `Flush` (`FlushIfDirty`: immediate save only if dirty). Log entries are
written with `AppRepository.LogAdded/LogRemoved(kind, name, detail)` (see BUILD-135).

### A. Shared checklist builder (`ChecklistBuilderControl`)

**BUILD-001 — Builder binding & hosting.**
`Bind(steps, repo, ownerName, logKind = "Checklist step")` (ChecklistBuilderControl.xaml.cs:27). `ownerName`
is used as the activity-log detail and as the default name offered by "Save as list". `logKind` labels log
entries. Hosts pass:

| Host | `steps` | `ownerName` | `logKind` |
|---|---|---|---|
| `ChecklistBuilderWindow` | `proc.Steps` | `proc.Name` | `"Checklist step"` |
| `CrewEditorWindow` Checklist tab | `member.Checklist` | `member.FullName` | `"Crew checklist item"` |
| `TemplateEditorWindow` | detached clone steps (`ToSteps`) | `template.Name` | `"Saved-list item"` |

The control operates directly on the live collection (so any other view bound to the same collection, e.g.
the procedure Specifics grid, reflects changes). All actions silently no-op when not bound.

**BUILD-002 — Layout.**
Top: a "saved lists" strip (background `PanelAlt`, bottom border `BorderB`, padding 6,5) containing the
bold accent label `"Saved lists:"`, buttons `"💾 Save as list..."` (tooltip `"Save the current checklist to the
database as a reusable saved list."`), `"📋 Load a saved list..."` (tooltip `"Insert a saved list (reuse it over
and over). You choose whether to append or replace."`), `"Manage saved lists..."` (tooltip `"Rename or delete
saved lists in the database."`). Below: two equal columns separated by an 8-px draggable splitter.
Left column: bold header `"Bulk entry (one item per line)"`; row with accent button `"Add all"`, button
`"Clear"`, checkbox `"Replace existing"` (tooltip `"Replace all existing items instead of appending."`,
unchecked by default, not persisted); a multi-line, no-wrap, both-scrollbars text box in **Consolas**.
Right column: bold header `"Current items"`; a wrapping button bar: `"+ Item"` (tooltip `"Append a new item to
the end of the list."`), `"Insert before"` (`"Insert a new item immediately above the (first) selected item."`),
`"Insert after"` (`"Insert a new item immediately below the (last) selected item."`), `"Edit..."` (`"Open the
full editor for the selected item — deadline, done, notes & files."`), `"↑"` (min width 32, `"Move selected
item(s) up."`), `"↓"` (`"Move selected item(s) down."`), `"Move to..."` (`"Move selected item(s) to a specific
position."`), `"Delete"` (no tooltip); then the items list (extended multi-select).

**BUILD-003 — Current-items row rendering.**
Each row: the step `Title` (wrapping) with **strikethrough when `Done`** (live — toggling Done elsewhere
updates the decoration); right-aligned muted 11-pt text `"due yyyy-MM-dd"` when `Deadline` is set, nothing
otherwise. No Done checkbox in this list (done is changed in the editor). Rows have the global thin separator
line.

**BUILD-004 — Bulk add ("Add all").** (`AddAll_Click`, :59)
Split the text box on `\n` after replacing `\r\n` with `\n`; trim each line; drop empty lines. If no lines →
no-op. If "Replace existing" is checked → clear the collection first (**no confirmation**, removed items are
not logged). Append one `new ChecklistStep { Title = line }` per line (defaults: `Done=false`,
`DurationMinutes=60`, `IsJob=false`, fresh `Id`, empty container). Clear the text box (the checkbox keeps its
state). Log `LogAdded(logKind, "{n} added (bulk)", ownerName)`. [persist: MarkDirty]. Refresh keeping the
previous selection by Id.

**BUILD-005 — Clear.** Clears the bulk text box only.

**BUILD-006 — "+ Item".** Prompt (`PromptWindow`) title `"New item"`, prompt `"Title:"`, empty initial. OK with
non-whitespace text → insert `new ChecklistStep { Title = <value as typed, NOT trimmed> }` at the end.
Log `LogAdded(logKind, title, ownerName)` (the log trims the name). [persist: MarkDirty]. The new item becomes
the only selection and is scrolled into view. Cancel / blank → nothing.

**BUILD-007 — "Insert before".** Same prompt; insert at the index of the **first** selected item (lowest
index); with no selection insert at index 0.

**BUILD-008 — "Insert after".** Same prompt; insert at (index of the **last** selected item) + 1; with no
selection append at the end. Index always clamped to `0…count`.

**BUILD-009 — Selection model.** Extended selection (click, Shift-range, Ctrl-toggle, Ctrl+A). After every
mutation the list is rebuilt and the selection restored **by Id** (`RefreshList`, :36). After add/insert and
Move-to the selection is set to exactly the affected items and the first is scrolled into view
(`SelectByReference`, :50).

**BUILD-010 — Edit ("Edit..." / double-click).** Opens `ChecklistStepEditorWindow` (modal) for the
`SelectedItem` (the primary selected item). Double-click anywhere on the list opens the editor for the current
selected item. After the editor closes: [persist: Flush], rebuild list (title/strike/due refresh).
No selection → no-op.

**BUILD-011 — "↑" move up.** Selected indices ascending; if none, or the first selected is already at index 0,
**nothing moves** (even if other selected items could). Otherwise each selected item moves up one position
(processed ascending). Contiguous blocks move as a block; separated items each move one. [persist: MarkDirty].

**BUILD-012 — "↓" move down.** Mirror: no-op if the last selected is at the end; else each moves down one,
processed descending. [persist: MarkDirty].

**BUILD-013 — "Move to...".** Requires ≥1 selected. Opens single-select `ItemPickerWindow` titled
`"Move {n} item to..."` / `"Move {n} items to..."` with options, in order:
`"(Move to top)"` (tag 0); for every **unselected** item at index *i*: `"Before: {Shorten(title, 60)}"` (tag *i*);
`"(Move to bottom)"` (tag = count). OK with a choice → `MoveStepsTo` (BUILD-A3 algorithm): the selected items
move as a block, keeping relative order, to that position. Selection = moved items. [persist: MarkDirty].
Cancel / OK with nothing chosen → nothing.

**BUILD-014 — Delete.** Requires ≥1 selected. Confirmation (Yes/No, question icon) title `"Confirm"`, text
`"Delete {n} item?"` / `"Delete {n} items?"`. Yes → `LogRemoved(logKind, "{n} removed", ownerName)`, remove all
selected. [persist: MarkDirty]. **Permanent** — builder deletions do not go to the Trash and there is no undo.

**BUILD-015 — "💾 Save as list...".** (`SaveTemplate_Click`, :194)
Empty checklist → info box title `"Save list"`: `"Add some items first, then save the list."`.
Otherwise prompt title `"Save as reusable list"`, prompt `"Name for this saved list:"`, initial = `ownerName`
(or empty). OK with non-blank → `ChecklistTemplateService.CaptureFromSteps(name, steps)` (name trimmed; see
BUILD-060), appended to the **end** of `ChecklistTemplates`, ungrouped. Log `LogAdded("Saved list", name,
"{n} item(s)")`. [persist: Save]. Info box title `"Saved list"`: `"Saved '{name}' ({n} item(s)). You can reuse it
from any checklist builder."` (literal "item(s)").

**BUILD-016 — "📋 Load a saved list...".** (`LoadTemplate_Click`, :214)
No templates → info title `"Load a saved list"`: `"No saved lists yet. Build a list and click 'Save as list...' to
create one."`. Otherwise single-select picker titled `"Insert a saved list"` listing every template in
**collection (arranged) order**, display `ChecklistTemplate.Display` = `"{name or (unnamed)}  ·  {n} item"` /
`"… items"`. Then Yes/No/Cancel box title `"Insert a saved list"`:
`"Insert '{name}' ({n} item(s)).\n\nYes = replace the current items\nNo = append to the end\nCancel = do nothing"`.
Yes → clear then add; No → append. Items are created by `ApplyToSteps` (BUILD-061). Log
`LogAdded(logKind, "{n} added (from saved list '{name}')", ownerName)`. [persist: MarkDirty].

**BUILD-017 — "Manage saved lists...".** (only in this control; not in the subtask builder)
No templates → info title `"Manage saved lists"`: `"No saved lists yet."`. Else single-select picker
`"Manage saved lists — pick one"` (Display strings, arranged order). Then Yes/No/Cancel title
`"Manage saved list"`: `"'{name}' ({n} item(s)).\n\nYes = rename\nNo = delete\nCancel = nothing"`.
* Rename: prompt `"Rename saved list"` / `"New name:"` / initial = name → non-blank → name = trimmed;
  [persist: Save]; not logged.
* Delete: warning Yes/No title `"Delete saved list"`: `"Delete saved list '{name}'? This does not affect any
  checklist already built from it."` → remove from `ChecklistTemplates`, `LogRemoved("Saved list", name)`,
  [persist: Save]. Permanent (not trashed).

**BUILD-018 — Procedure host window (`ChecklistBuilderWindow`).** Title `"Checklist builder"`, 820×640,
centered on owner, app icon. Header (15 pt bold) `"Checklist builder — {proc.Name}"`; muted wrapping help:
`"Type one item per line on the left and click 'Add all'. Use the right panel to reorder, fully edit (deadline,
notes, files) and delete items. Save the list to reuse it anywhere. Close to save."`. Bottom-right `"Close"`
(min width 80). On closing: [persist: Flush]. The opener refreshes the procedure's step grid afterwards.

**BUILD-019 — Crew host (Checklist tab).** Tab header `"Checklist"` (second tab of the crew editor, selected
directly when opened via "🗒 Open checklist..."). Muted help: `"This crew member's personal checklist. Give an
item a due date (in its full editor) and it shows in the 📌 due-dates window and the Calendar. Checklist changes
save immediately — they are not undone by Cancel."`. Crew-editor Cancel does **not** revert checklist changes.

### B. Checklist step editor (`ChecklistStepEditorWindow`)

**BUILD-020 — Layout.** Window title `"Edit checklist step — {title}"` (updated live as the title is typed),
900×700, centered on owner. Top form (label column width 100):
`"Title:"` text box; `"Deadline:"` date picker (width 200, tooltip `"Optional per-step due date — the step then
behaves like a task subtask (shows in the Calendar and the floating due-dates window)."`); `"Status:"` checkbox
`"Done"`; `"Job:"` checkbox `"Schedulable job"` (tooltip `"Tag this step as a Job so it can be dragged onto the
Planner."`) followed by `"Duration (min):"` and an 80-px text box. Bottom-right `"Close"`. The rest of the window
is the full `ContainerEditor` (rich-text notes + file bank) bound to `step.Container`.

**BUILD-021 — Live field writes.** Every change writes straight to the model and marks dirty (no OK/Cancel;
closing is saving): Title (every keystroke, untrimmed; empty allowed), Deadline (set/cleared, no range for
steps), Done, IsJob. Initial population is suppressed so opening never marks dirty.

**BUILD-022 — Duration validation.** On each text change: if `int.TryParse(text)` succeeds **and** value > 0 →
`DurationMinutes = value`, mark dirty. Otherwise the model is silently left unchanged (text box keeps the invalid
text; no error UI). Initial text = current `DurationMinutes` (default 60).

**BUILD-023 — Close.** On closing: `ContainerEditor.FlushPending()` (writes any debounced rich-text edit) then
[persist: Flush].

**BUILD-024 — Step fields not edited here.** `BucketIds` (≤2 bucket ids; assigned in the Ctrl+N quick-work
window), `TaskIds` / `EquipmentIds` (procedure Specifics, BUILD-034/036), `ScheduledStart` (Planner drag-drop)
are preserved untouched by this editor.

**BUILD-025 — Editor reuse.** The same window is opened (modal, owner = caller) from: the builder (BUILD-010),
procedure Specifics grid (BUILD-037), Calendar row double-click, Planner job double-click, Buckets tab member
double-click, Ctrl+N builder "Edit". In the saved-list editor (BUILD-063) the Deadline/Done set here are
discarded on write-back.

### C. Procedure "Checklist Steps" area (host inside Procedure *Specifics* tab)

(`HierarchyPage.BuildProcedureSpecifics`, HierarchyPage.xaml.cs:1163; procedure-level deadline, recurrence,
status and job fields above it belong to the hierarchy spec.)

**BUILD-030 — Header & builder banner.** Bold `"Checklist Steps"`. Banner row: accent, bold 14-pt, stretched
button `"🛠  Open Comprehensive Checklist Builder"` (two spaces after the emoji; tooltip `"Open a dedicated window
to bulk-create, reorder, edit and delete checklist steps."`) → modal `ChecklistBuilderWindow`; after it closes
the grid refreshes. Right side of the banner: `"Export checklist (PDF)"` (tooltip `"Export ONLY the checklist
(no notes, no relationships) as a printable A4 PDF."`) and `"Export checklist (Excel)"` (tooltip `"Export ONLY
the checklist as an Excel workbook (.xlsx)."`).

**BUILD-031 — Step grid.** Extended multi-select, virtualized (recycling). Columns:
1. `"Done"` (50 px) — checkbox bound two-way to `Done`; clicking it [persist: MarkDirty + Flush] immediately.
2. `"Job"` (44 px) — checkbox bound to `IsJob`, tooltip `"Mark this step as a schedulable Job (set its duration in
   the step editor)."`; click → [persist: MarkDirty + Flush].
3. `"Title"` (300 px) — wrapping, strikethrough when `Done`.
4. `"Deadline"` (120 px) — `yyyy-MM-dd` or blank, read-only (edited in the step editor).

**BUILD-032 — "+ Step".** Prompt `"New Step"` / `"Title:"` → append `ChecklistStep { Title = value }` (untrimmed),
`LogAdded("Checklist step", title, procName)`, [persist: Save].

**BUILD-033 — "Remove".** Removes only the **primary** selected step, **without confirmation**;
`LogRemoved("Checklist step", title, procName)`; [persist: Save]. No selection → no-op.

**BUILD-034 — "Link tasks..." (banked tasks).** Requires a selected step (silently no-op otherwise). Multi-select
`ItemPickerWindow` titled `"Pick tasks for this step"` listing **top-level** `Data.Tasks` (data order, display =
task name; subtasks are not offered), pre-selected = the step's current `TaskIds`. OK → `TaskIds` replaced by the
picked set (order = order in which the items were selected in the picker; pre-selected ones first in list order).
[persist: Save]. Not logged. This implements the brief's "Each checklist in each procedure may use banked
tasks".

**BUILD-035 — "+ New task".** Tooltip `"Create a new Task and auto-link it to the selected checklist step."`.
No step selected → info title `"New task"`: `"Select a checklist step first."`. Else prompt `"New Task"` /
`"Name:"` → new top-level `TaskItem { Name = value }` appended to `Data.Tasks`, its Id appended to the step's
`TaskIds`, `LogAdded("Task", name, "linked to step '{step.Title}'")`, [persist: Save]. ("…or the user may create
one".)

**BUILD-036 — "Link equipment/area...".** Same as BUILD-034 but picker `"Pick equipment/area for this step"` over
`Data.Equipment`, writing `EquipmentIds`.

**BUILD-037 — "Edit..." / double-click.** Tooltip `"Open this checklist step in a dedicated editor with its own
rich-text container and file bank."` → `ChecklistStepEditorWindow` for the primary selection, then grid refresh.

**BUILD-038 — Context menu (right-click).** Right-click on an unselected row selects just it; on a selected row
keeps the multi-selection. Items: `"✓ Mark selected as done"`, `"○ Mark selected as not done"` (BatchDone; only
real changes mark dirty; then Flush + refresh), `"📅 Set deadline for selected…"` (BatchDeadline via
`DatePromptWindow`; pick / Clear / Cancel). (Specified in the batch-actions spec.)

**BUILD-039 — Export checklist (PDF).** Flush first. Save dialog title `"Export checklist to PDF"`, filter
`"PDF document (*.pdf)|*.pdf"`, default name `"checklist-{safeName}.pdf"` where `safeName` = procedure name with
every Windows-invalid filename char replaced by `_` (null name → `"procedure"`). Busy cursor while writing. Error
→ `"Failed to export checklist:\n{message}"` title `"Export error"`. Success → the file is opened with the default
app (failure to open is ignored). Layout: BUILD-C1.

**BUILD-040 — Export checklist (Excel).** As BUILD-039 with title `"Export checklist to Excel"`, filter
`"Excel workbook (*.xlsx)|*.xlsx"`, name `"checklist-{safeName}.xlsx"`. Layout: BUILD-C2.

### D. Subtask builder (`SubtaskBuilderWindow`)

**BUILD-041 — Window.** Title `"Subtask builder"`, 780×640, centered on owner. Header `"Subtask builder —
{task.Name}"`; muted help: `"Type one subtask per line on the left and click 'Add all'. Use the right panel to
reorder, edit (deadline / recurrence / status / notes) and delete subtasks. Close to save."`. Saved-lists strip:
`"Saved lists:"`, `"💾 Save as list..."` (tooltip `"Save the current subtasks to the database as a reusable saved
list."`), `"📋 Load a saved list..."` (tooltip `"Insert a saved list as subtasks (append or replace)."`) — **no
Manage button**. Bottom `"Close"`; on closing [persist: Flush].

**BUILD-042 — Panes.** Left: `"Bulk entry (one subtask per line)"`, `"Add all"` (accent), `"Clear"`, checkbox
`"Replace existing"` (tooltip `"Replace all existing subtasks instead of appending."`), Consolas no-wrap box.
Right: `"Current subtasks"`; single-row (non-wrapping) button bar: `"+ Subtask"` (`"Append a new subtask to the end
of the list."`), `"Insert before"` (`"Insert a new subtask immediately above the (first) selected subtask."`),
`"Insert after"` (`"Insert a new subtask immediately below the (last) selected subtask."`), `"Edit..."` (`"Open
the full subtask editor (deadline / recurrence / status / notes / files)."`), `"↑"` (`"Move selected subtask(s) up
by one position."`), `"↓"` (`"Move selected subtask(s) down by one position."`), `"Move to..."` (`"Move selected
subtask(s) to a specific position (top / bottom / before another subtask)."`), `"Delete"`.

**BUILD-043 — Row rendering.** `Name` (wrap) with strikethrough when `IsComplete`; right muted `Deadline` as
`yyyy-MM-dd` (no "due" prefix); blank when none. (The working range start is **not** shown here.)

**BUILD-044 — Behaviours identical to A** with these differences: items are `new TaskItem { Name = line }`
(defaults `Status=Todo`, `IsComplete=false`, `DurationMinutes=60`, `Recurrence=None`); prompts `"New subtask"` /
`"Name:"`; log kind always `"Subtask"`, detail = parent task name; Move-to title `"Move {n} subtask(s) to..."`
(singular when 1); delete confirmation `"Delete {n} subtask?"` / `"… subtasks?"` title `"Confirm"` (shown without
an owner window); Save default name = task name, empty message `"Add some subtasks first, then save the list."`;
Load message `"Insert '{name}' ({n} item(s)).\n\nYes = replace the current subtasks\nNo = append to the end\nCancel
= do nothing"`, applied via `ApplyToSubtasks`, logged `LogAdded("Subtask", "{n} added (from saved list '{name}')",
taskName)`; Edit opens `SubtaskEditorWindow`.

**BUILD-045 — Nesting scope.** The builder edits exactly one level (`task.Subtasks`). A subtask's own
`Subtasks` (deeper levels arriving via data from SIRE quick-add, sync or older builds) are carried along
untouched when moved, and deleted with it. `CaptureFromSubtasks` captures only the direct children (their
nested children are **not** saved into the list). The subtask editor has no subtasks list. The Specifics
subtasks grid is bound to the same collection, so it updates live.

**BUILD-046 — Hosts.** Task *Specifics*: accent, bold, 14-pt, stretched button `"🛠  Open Comprehensive Subtask
Builder"` (tooltip `"Open a dedicated window to bulk-create, reorder, edit and delete subtasks."`) above the
inline subtasks grid. Ctrl+N: "Open full builder".

### E. Subtask editor (`SubtaskEditorWindow`)

**BUILD-050 — Layout.** Title `"Edit subtask — {name}"` (live), 900×700. Form (label width 100):
`"Name:"`, `"Description:"` (single-line box), `"Deadline:"` picker (150 px, tooltip `"The task's due date — also
the LAST day of the working range."`) + `"Start (optional):"` picker (150 px, tooltip `"Optional first day of the
range you'll work on this. Leave empty for a single-day task; the deadline stays the last day."`) + button
`"Clear range"` (tooltip `"Remove the start date (keeps the deadline)."`) + muted range hint; `"Recurrence:"`
combo (200 px; items `None, Daily, Weekly, Monthly, Yearly`); `"Status:"` combo (200 px; items `Todo, InProgress,
Blocked, Done`; tooltip `"Workflow status used by the Board (Done keeps the Completed box in sync)."`);
`"Completed:"` checkbox `"Mark as done"`; `"Job:"` checkbox `"Schedulable job"` (tooltip `"Tag this task as a
Job so it can be dragged onto the Planner."`) + `"Duration (min):"` box. `"Close"` bottom-right; the rest is
`ContainerEditor` on `task.Container`.

**BUILD-051 — Name / Description.** Live writes, untrimmed, mark dirty; window title follows the name.

**BUILD-052 — Deadline + working range.** Changing either picker calls
`WorkRange.Coerce(startPicker, deadlinePicker, editedStart)` (BUILD-A6), writes the coerced pair back into both
pickers (suppressed) and into `RangeStart`/`Deadline`, marks dirty, refreshes the range UI. Consequences the user
sees: picking a start with no deadline sets the deadline to the same day; moving the start past the deadline pushes
the deadline out to the start; moving the deadline before the start pulls the start onto the deadline; **clearing
the deadline while a start exists refills the deadline with the start date** (use "Clear range" first).

**BUILD-053 — Range UI.** "Clear range" visible only while `RangeStart` has a value; click → start picker cleared
(suppressed), `RangeStart = null`, mark dirty. Hint text: `"range · {n} days"` where n = whole days
`Deadline − RangeStart` + 1, shown only when `HasRange` (start date < deadline date); otherwise empty (a start
equal to the deadline shows the button but no hint). Impossible days are greyed in the popups: deadline calendar
starts at `RangeStart`; start calendar ends at `Deadline`.

**BUILD-054 — Recurrence.** Writes `Recurrence`. (Only **top-level** tasks regenerate on completion —
`AppRepository.ReconcileRecurrences` scope; a subtask's recurrence is stored and shown but inert.)

**BUILD-055 — Status ⇄ Completed.** Status change → `Status = x` (model sets `IsComplete = (x == Done)`),
checkbox re-synced. Checkbox change → `IsComplete = b` (model: true ⇒ `Status = Done`; false on a Done task ⇒
`Status = Todo`; false on a non-Done status leaves it). Combo re-synced. Both mark dirty.

**BUILD-056 — Job + duration.** As BUILD-021/022.

**BUILD-057 — Close.** `FlushPending()` then [persist: Flush].

### F. Saved-list semantics (`ChecklistTemplateService`)

**BUILD-060 — What a saved list stores ("full copy").** Per item: `Title`, `DurationMinutes`, `IsJob`, and a
deep-cloned `Container` (rich-text XAML string verbatim, `IsLocked`, every `FileItem` cloned with a new Id,
`SharedWithContainerIds` copied). **Never stored:** deadline, working-range start, done/complete state, status,
recurrence, scheduled start, bucket ids, step task/equipment links, description, nested subtasks, item ids.
Template name is trimmed at capture; `CreatedUtc = now (UTC)`; `GroupId = null`. File attachments are **not
duplicated on disk** — clones reference the same relative `files/…` path; removing a file from any container only
removes the reference, never the physical file.

**BUILD-061 — Applying a saved list.** Each item becomes a brand-new step (`ChecklistStep { Title, DurationMinutes,
IsJob, Container = clone }`) or subtask (`TaskItem { Name = Title, DurationMinutes, IsJob, Container = clone }`)
with fresh Ids and defaults for everything else (Done false / Status Todo, no deadline). Replace mode clears the
target first. Returns the template's item count (used in logs), even when appending.

**BUILD-062 — Cross-kind reuse.** A list captured from procedure steps can be applied as task subtasks, to a crew
checklist, in Ctrl+N, and vice versa; the Title ⇄ Name mapping is the only conversion.

**BUILD-063 — Editing a saved list (`TemplateEditorWindow`).** Window title `"Edit saved list"`, 820×640. Header
`"Edit saved list — {name or (unnamed)}"`; muted help `"Edit the items in this saved list (title, duration, notes &
files). Deadlines, working-ranges and done aren't stored in a saved list — they're set when you apply it. Close to
save."`; `"Close"`. The template's items are materialised as detached `ChecklistStep`s (`ToSteps`, cloned
containers) and bound to a `ChecklistBuilderControl` (log kind `"Saved-list item"`, owner = template name), so the
full builder is available (bulk add, insert, reorder, edit with notes/files, delete, and the saved-lists strip).
On closing (any way): `WriteBackFromSteps` replaces the template's items with clones of the edited steps
(dropping deadline/done), then [persist: Save]. Template `Id`, `Name`, `GroupId`, `CreatedUtc` are unchanged.
Quirks to preserve or guard (see §8): write-back always happens (container/file Ids change every open/close); the
strip's "Manage saved lists..." can rename or delete the very template being edited (a delete makes the write-back
land on an orphan, i.e. the edits vanish); "Load a saved list..." can insert the template's own *pre-edit* items.

**BUILD-064 — Item to standalone task.** `ItemToTask(item)` → `TaskItem { Name = Title, DurationMinutes, IsJob,
Container = clone, Status = Todo }` (used by BUILD-101).

### G. Saved Lists tab (`SavedListsPage`)

**BUILD-070 — Placement.** Main tab header `"Saved Lists"` (tab name `TabLists`, between Crew and Buckets in the
default order; user-reorderable/colourable like all tabs). `Init(repo)` on every data load; `Refresh()` every time
the tab is selected.

**BUILD-071 — Left pane.** Fixed 330 px, rounded (4) `Panel` card; 6-px splitter; detail on the right.
Title strip (PanelAlt): `"Saved Lists"` bold 15 pt accent. Toolbar (wrap): `"+ Group"` (tooltip `"Create a new List
Group to bundle saved lists together."`), `"+ List"` (`"Create a new empty saved list."`), `"Rename"`, `"Delete"`,
`"Move to group..."` (`"Put the selected saved list into a group (or remove it from all groups)."`), `"Manage
groups..."` (`"Rename or delete List Groups (lists inside a deleted group become ungrouped)."`), separator, `"↑"`
(`"Move the selected saved list(s) up within its group. This is the order they export in."`), `"↓"` (`"Move the
selected saved list(s) down within its group. This is the order they export in."`), `"Move to position..."`
(`"Move the selected saved list(s) to a chosen position within its group."`), toggle `"Sort A-Z"` (`"Show lists
alphabetically instead of your own order. Your arranged order is kept and is what exports use when this is off."`).
List: extended multi-select, grouped. Row = `Name` (semi-bold, wrap; `"(unnamed)"` when empty) + right muted 11-pt
`"{count} items"` (always plural: "1 items"). Group header (PanelAlt strip): group name bold accent + muted
`" ({n})"` (lists in that group). Groups are not collapsible. Status line at the bottom (muted, wrap).

**BUILD-072 — Grouping & order.** Group key/label: the group's name (`"(unnamed group)"` if the name is empty) when
`GroupId` resolves to an existing `ListGroup`; `"Ungrouped"` when `GroupId` is null **or dangling**. Groups are
ordered by lower-cased name (culture comparison); real ungrouped (`GroupId == null`) sorts **last**. Within a group:
arranged order (= index in `ChecklistTemplates`) or, when Sort A-Z is on, by displayed name. **Empty groups do not
appear** in the list (only in pickers). Groups are keyed by *name*, so two groups with the same name render as one
header (see §8).

**BUILD-073 — Status line.** No lists: `"No saved lists yet. Build a checklist anywhere and click 'Save as list...',
or click '+ List'."`; else `"{lists} saved list(s)  ·  {groups} group(s)"` (literal "(s)", two spaces around the
middle dot). Temporarily replaced by the messages of BUILD-085/088 after those actions.

**BUILD-074 — Detail pane.** Disabled (all controls greyed) when nothing is selected. Card 1: `DetailName` (18 pt
bold, wrap) — `"Select a saved list"` or the name / `"(unnamed)"`; `DetailSub` muted:
`"{n} item(s)"` + (`"  ·  ungrouped"` if no group or the group's name is blank/unresolvable, else
`"  ·  group: {groupName}"`) + `"  ·  created {CreatedUtc→local, yyyy-MM-dd}"`. Buttons: accent `"✎ Edit
items..."`, `"Duplicate"`, `"📄 Export this list (PDF)..."`, `"📄 Export group (PDF)..."`, `"📄 Export ALL
(PDF)..."`. Card 2: bold `"Items"` + items preview list. The detail always shows the **primary** selection.

**BUILD-075 — Items preview.** One row per template item: title (`"(untitled)"` if empty, wrap) + right muted 11-pt
meta joined by `"  ·  "` from, in order: `"job"` if `IsJob`; `"notes"` if `Container.RichTextXaml` is not
null/whitespace (raw string test — an emptied note still counts); `"{n} file"` / `"{n} files"` if the container has
files. **Duration is deliberately not shown** (PROGRESS 2026-07-18 #1). Tooltip `"Double-click an item to view its
notes and files (read-only) — links open straight from there."`.

**BUILD-076 — Read-only item viewer.** Double-click an item → `ContainerViewerWindow` (modal) with title =
row title and subtitle `"Saved-list item · {listName} — read-only. Click a link to open it; double-click a file to
open it."` (`" · {listName}"` omitted when the list name is blank). Window title `"View — {title}"`, 820×620.
Header card: title (16 pt bold accent), subtitle (11 pt muted; default `"Read-only view — click a link to open it.
Editing is disabled."`). Body: read-only rich text (hyperlinks clickable, fixed light "paper" colours in both
themes, 14 pt); `"(no notes)"` in grey when empty; `"(locked content)"` when the body is an `enc:` blob; if the XAML
fails to parse, the raw string is shown as plain text. Splitter; files pane (180 px) with header `"Files — none"` /
`"Files ({n}) — double-click to open"` and columns `"Name"`, `"Kind"`, `"Source"` (`"Web link"` / `"Live"` /
`"Copy"`), `"Path / URL"`. Buttons `"Open all files"` (tooltip `"Open every file listed below."`) and `"Close"`
(default + cancel ⇒ Enter/Esc close). Open-all: none → `"This item has no files."` (title `"Open all files"`);
>15 → confirm `"Open all {n} files?"`. Opening a non-link whose resolved path is missing → warning `"That file is
missing:\n\n{path}"` (title `"Open file"`); launch failure → `"Could not open:\n\n{target}\n\n{error}"` (title
`"Open"`). Nothing in the saved list can be modified from here.

**BUILD-077 — "+ Group".** Prompt `"New List Group"` / `"Group name:"` → `ListGroups.Add(new ListGroup { Name =
trimmed })` (appended; `CreatedUtc = now UTC`). [persist: Save]. Not logged. The new group is invisible in the list
until a list is moved into it.

**BUILD-078 — "Manage groups...".** No groups → info title `"Manage groups"`: `"No groups yet. Click '+ Group' to
create one."`. Else single-select picker `"Manage groups — pick one"` listing groups in creation order as
`"{name}  ·  {k} list(s)"`. Then Yes/No/Cancel title `"Manage group"`: `"'{name}'.\n\nYes = rename\nNo = delete (its
lists become ungrouped)\nCancel = nothing"`. Rename: prompt `"Rename group"` / `"New name:"` → trimmed →
[persist: Save]. Delete: warning Yes/No title `"Delete group"`: `"Delete group '{name}'? Its saved lists are kept
(they become ungrouped)."` → every template with that `GroupId` gets `GroupId = null` (flat positions unchanged),
group removed, [persist: Save]. Not logged.

**BUILD-079 — "Move to group...".** Needs a selection (else BUILD-089 "select first" box). Acts on the **primary
selection only**. Single-select picker `"Move '{name}' to group"`: `"(No group — ungrouped)"` then every group
name (creation order). OK → `GroupId` = chosen group's Id, or **null for "(No group…)" or when OK is pressed with
nothing chosen**. [persist: Save]. The list keeps its flat position, so it appears inside the target group wherever
that position falls relative to the group's other lists (not necessarily last).

**BUILD-080 — "+ List".** Prompt `"New saved list"` / `"Name:"` → append `ChecklistTemplate { Name = trimmed }`
(ungrouped, empty), `LogAdded("Saved list", name, "empty")`, [persist: Save], select + scroll to it.

**BUILD-081 — "Rename".** Primary selection; prompt `"Rename saved list"` / `"New name:"` / current → trimmed,
[persist: Save]. Not logged.

**BUILD-082 — "Delete".** Primary selection only; warning Yes/No title `"Delete saved list"`: `"Delete saved list
'{name}'? This does not affect any checklist already built from it."` → remove, `LogRemoved("Saved list", name)`,
[persist: Save]. Permanent.

**BUILD-083 — "Duplicate".** Primary selection → `Clone(t, t.Name + " (copy)")`: new Id, same `GroupId`, new
`CreatedUtc`, all items cloned; appended at the **end of the collection** (so last in its group's arranged order).
`LogAdded("Saved list", copyName, "{n} item(s)")`, [persist: Save], select the copy.

**BUILD-084 — "Edit items..." / "✎ Edit items...".** Opens `TemplateEditorWindow` (BUILD-063) for the primary
selection; refresh afterwards.

**BUILD-085 — Arranged order.** The order of `AppData.ChecklistTemplates` **is** the user's arrangement; there is no
sort field. It drives the tab (when A-Z is off), the builder pickers, the insert-into-note picker, and every
export. After a successful reorder: [persist: Save], refresh, re-select the moved lists (all of them, first
scrolled into view), status `"Order saved — this is the order the group exports in."`.

**BUILD-086 — "↑" / "↓" / context "Move up" / "Move down".** Guards (BUILD-089), then `SavedListOrder.Nudge`
(BUILD-A7). Multi-select moves as a block within the group; returns false (nothing happens, no message) when the
block is already at that end or the group has < 2 lists.

**BUILD-087 — "Move to position...".** Guards, then single-select picker `"Move {n} list to..."` / `"… lists
to..."` with options `"(Move to top of group)"` (0), `"Before: {Shorten(name, 60)}"` for every non-selected list of
the group at group position p (tag p), `"(Move to bottom of group)"` (tag = group size). → `SavedListOrder.MoveTo`
(BUILD-A8).

**BUILD-088 — "Sort A-Z".** Toggle persisted in `Ui.SortAZ["savedlists"]` (bool) [persist: Save]. While on: the
list sorts by displayed name within each group, and `↑`, `↓`, `Move to position...` toolbar buttons are disabled
(context-menu equivalents stay enabled but refuse with a message). Status after toggling on: `"Showing A-Z. Your
arranged order is kept, and is what exports use — switch this off to see it."`; off: `"Showing your arranged
order. This is the order lists appear in when you export a group."`. The arrangement underneath is never changed.

**BUILD-089 — Guards & messages.** No selection (for Rename, Delete, Duplicate, Edit items, Move to group,
reorders, Export this list, Export group) → info title `"Saved Lists"`: `"Select a saved list first."`.
Reorder while A-Z on → info title `"Arrange lists"`: `"Turn off \"Sort A-Z\" first — while it is on you are seeing
alphabetical order, not your own."`. Selection spanning groups → info title `"Arrange lists"`: `"Those lists are in
different groups. Lists are arranged within their own group, so select lists from one group at a time."`.
Group of one → silently nothing.

**BUILD-090 — Context menu on the list.** `"Edit items..."`, `"Rename"`, `"Duplicate"`, `"Move to group..."`, ——,
`"Move up"`, `"Move down"`, `"Move to position..."`, ——, `"Export this list (PDF)..."`, `"Delete"`. (Right-click
selects the row under the cursor if it is not already selected.)

**BUILD-091 — Export this list (PDF).** Title = list name or `"Saved list"` when empty; entries = `[(no group,
list)]`.

**BUILD-092 — Export group (PDF).** If the primary selection's `GroupId` resolves: title = group name, entries =
`GroupEntries(gid)` (every list of that group in arranged order, each tagged with the group name, or no tag if the
name is empty). Otherwise title `"Ungrouped lists"`, entries = `GroupEntries(null)` (lists whose `GroupId` is null
— a dangling-group list is itself **not** included, §8).

**BUILD-093 — Export ALL (PDF).** No templates → info title `"Export"`: `"No saved lists to export."`. Title
`"All saved lists"`, entries = `AllEntries` (BUILD-A9). (Button lives in the disabled-when-empty detail pane, so a
list must be selected to reach it.)

**BUILD-094 — Bulleted or numbered — asked every time.** Empty entries → info `"Nothing to export."` (title
`"Export"`). Then `ListStylePromptWindow` (title `"List style"`, 430 px wide, not resizable) with prompt `"How should
the items in this list be shown in the PDF?"` (1 entry) or `"How should the items in these {n} lists be shown in
the PDF?"`; radio 1 (pre-selected): bold `"• Bulleted"` + muted `"Every item marked with a bullet. Best when the
order does not matter."`; radio 2: bold `"1. Numbered"` + muted `"Items numbered in order. Best for steps that run
in sequence."`; buttons `"Cancel"` (Esc) and bold `"Continue"` (Enter). **Never remembered**; cancelling aborts the
export before the file dialog.

**BUILD-095 — Save dialog & result.** Save dialog title `"Export saved lists to PDF"`, filter `"PDF document
(*.pdf)|*.pdf"`, default name `Sanitize(title) + ".pdf"` (BUILD-A11). Success → Yes/No title `"Export complete"`:
`"Exported to:\n{path}\n\nOpen it now?"` → Yes opens with the default viewer. Failure → error title `"Export
failed"`: `"Could not export the PDF:\n\n{message}"`.

**BUILD-096 — Saved-list PDF layout.** See BUILD-C3.

### H. Saved-list consumers elsewhere

**BUILD-100 — Insert a saved list into a note.** Rich-text toolbar button `"≔"` (tooltip `"Insert a saved list here
as bullets or numbers. Your existing notes are not changed."`) in every `ContainerEditor`. Refuses with
`"This note can't be edited right now because its saved content isn't loaded — unlock it first (Tools ▸ Set / change
password, then reopen)."` (title `"Nothing inserted"`) when the body is withheld, and with the lock hint when the
caret/selection touches locked text. Dialog `InsertSavedListWindow`: title `"Insert saved list"`, 760×560; bold
accent `"Insert a saved list"`; muted `"The list is added where your cursor is. Nothing already in the note is
changed, and one Ctrl+Z removes the whole list again."`. Left (290 px): search box (placeholder tag `"Search saved
lists..."`), list grouped by List Group (header = group name, `"Ungrouped"` for none; groups appear in order of their
first list in the **arranged** order; rows = `Display`). Right: radios `"• Bullets"` (default) / `"1. Numbered"`,
checkbox `"Include each item's duration"` (tooltip `"Appends e.g. (60 min) to each line."`), muted `"Preview"`,
bordered Consolas preview. Footer note + `"Cancel"` / bold `"Insert"` (default). Behaviour:
* No saved lists: footnote `"You have no saved lists yet. Build one in the Saved Lists tab first."`, Insert and
  search disabled.
* First list pre-selected; search = case-insensitive (current culture) substring on list name **or any item
  title**; after each search the first match is selected.
* Lines = item titles trimmed, blanks dropped; with duration: `"{title}  ({mins} min)"` when mins > 0.
* Preview: lines prefixed `"{i}. "` or `"• "` joined by newlines; `"(this saved list has no items)"` when empty
  (Insert disabled).
* Footnote: `"{n} line(s) will be inserted."` (`"line"` when 1) + optional `" Not carried over: {parts}."` where
  parts = `"{k} item has notes"` / `"{k} items have notes"` and `"{m} attached file(s)"` (`"file"` when 1), joined
  by `", "`.
* Insert → the editor inserts a real list after the caret's block (one undo step) — mechanics and XAML in the
  rich-text spec; shape summary in §4.6.

**BUILD-101 — Add tasks from saved lists (Board "+ From saved list", Planner "+ Saved list").**
`SavedListPicker.PickAndAddTasks`. No templates → info (no owner) title `"Add from saved list"`: `"You have no saved
lists yet. Build one in the Saved Lists tab first."`. No items in any list → `"Your saved lists don't have any items
yet."`. Else **multi-select** searchable picker `"Search saved lists — pick items to add as tasks"` over every item
of every list (arranged order, item order): `"{listName or (unnamed list)}  ›  {title or (untitled)}"` + `"   ·
schedulable"` if IsJob. Each pick → `ItemToTask` → appended to `Data.Tasks` (To Do, top-level); [persist: Save] if
any. **Not logged.** Templates unchanged.

**BUILD-102 — Ctrl+N quick-work inline builder.** Uses the same capture/apply services and the same strings as
BUILD-015/016 (`"Save as reusable list"`, `"Name for this saved list:"`, `"Add some items first, then save the
list."`, `"Saved '{name}' ({n} item(s)). You can reuse it from any checklist builder."`, `"No saved lists yet. Build a
list and click 'Save as list...' to create one."`, `"Insert a saved list"`, `"Insert '{name}' ({n} item(s)).\n\nYes =
replace the current items\nNo = append to the end\nCancel = do nothing"`); logs `"Subtask"` / `"Checklist step"`
with the item's name as detail. (Owned by the quick-work spec; listed so the shared service is designed for it.)

### I. Crew schedule builder (`ScheduleBuilderControl`)

**BUILD-110 — Hosting.** Third tab `"Schedule"` of the crew editor. Muted help: `"A timeline for this crew member —
add tasks, procedures, equipment or free notes on a date. Save/export the schedule to reuse it on any crew, and link
it to a vessel. Changes save immediately."`. `Bind(crew, repo)` on open; crew-editor Cancel does not revert schedule
changes.

**BUILD-111 — Top bar.** (PanelAlt strip, wrap) `"Linked vessel:"` + combo (180 px, tooltip `"Link this schedule to a
vessel (optional)."`) listing `"(none)"` then every vessel in data order (`"(unnamed)"` for blank names); selection
reflects `ScheduleVesselId` (a dangling id shows `"(none)"` but is kept until changed). Changing it writes
`ScheduleVesselId` (null for none) [persist: Save]. Buttons: `"💾 Save as..."` (`"Save this schedule as a reusable
one that can be applied to any crew."`), `"📋 Apply saved..."` (`"Apply a saved schedule to this crew member (append
or replace)."`), `"📤 Export..."` (`"Export this schedule to a file you can share/import elsewhere."`), `"📥
Import..."` (`"Import a schedule file and apply it to this crew member."`).

**BUILD-112 — Add row.** Bold `"Add:"`; date picker (130 px, defaults to **today** on every `Bind`; may be cleared);
time box (60 px, tooltip `"Time (HH:mm), optional."`; no visible placeholder on Windows); kind combo (110 px, items
`Note, Task, Procedure, Equipment`, default `Note`); title box (200 px); `"Pick item..."` (tooltip `"Pick an existing
Task / Procedure / Equipment to schedule."`, **disabled when kind = Note**); accent `"+ Add"`.

**BUILD-113 — Kind change.** Clears the pending picked-item reference (the title text is kept) and re-evaluates the
Pick button.

**BUILD-114 — Pick item.** Source by kind: top-level `Data.Tasks` / `Data.Procedures` / `Data.Equipment`, sorted by
name (ordinal, case-insensitive). None → info title `"Pick item"`: `"No {Kind} items exist yet to schedule."` (enum
name, e.g. `"No Task items exist yet to schedule."`). Else single-select picker `"Pick a {Kind} to schedule"`. OK →
title box = item name, pending ref = item Id (the user may still edit the title).

**BUILD-115 — "+ Add".** Title = trimmed title box; empty → info title `"Add entry"`: `"Type what to schedule (or pick
an item)."`. Creates `ScheduleEntry { Title, Kind, RefId = (Kind == Note ? null : pendingRef), Date = picked date as
"yyyy-MM-dd" or "", Time = NormTime(timeBox) }` appended to `crew.Schedule`; [persist: Save]; title box cleared,
pending ref cleared (date, time and kind stay); refresh. Not logged.

**BUILD-116 — Timeline.** Grouped list, horizontal scroll disabled. Group per entry: `"(no date)"` when `Date` is
empty/unparseable; `"Today"`; `"Tomorrow"`; else `"{ddd}, yyyy-MM-dd"` (abbreviated weekday in the **current
culture**, e.g. `"Fri, 2026-10-02"`). Sorted by date (`yyyy-MM-dd` of the parsed date; undated last) then by time
(`Time` or `"00:00"` when empty — untimed entries sort first in their day). Group header (PanelAlt strip): accent
`"🗓 "` + bold accent label + muted `" ({count})"`.

**BUILD-117 — Timeline row.** Left: checkbox bound two-way to `Done` (click → [persist: MarkDirty] + refresh);
`Time` (46 px, Consolas, muted); kind icon (20 px): Task `"✓"`, Procedure `"📋"`, Equipment `"⚙"`, Note `"•"`;
`Title` (wrap, strikethrough when Done). Right: flat hand-cursor buttons `"✎"` (tooltip `"Edit title/notes"`) and
`"✕"` (tooltip `"Delete this entry"`). Entries do not navigate to their referenced item.

**BUILD-118 — Edit entry.** Prompt `"Edit entry"` / `"Title:"` / current title → non-blank → trimmed title,
[persist: Save], refresh. (Only the title is editable, despite the tooltip.)

**BUILD-119 — Delete entry.** Immediate, **no confirmation**, [persist: Save], refresh. Not logged.

**BUILD-120 — Count line.** Muted, bottom: empty → `"No entries yet — pick a date, choose what, and click “+ Add”."`
(curly quotes); else `"{n} entry"` / `"{n} entries"` + (`" · {d} done"` when d > 0; single spaces).

**BUILD-121 — "💾 Save as...".** Empty → info title `"Save schedule"`: `"Add some entries first."`. Prompt `"Save
schedule"` / `"Name for this reusable schedule:"` / initial = crew full name → `ScheduleService.CaptureFromCrew`
(BUILD-A12) appended to `ScheduleTemplates`; `LogAdded("Schedule", name, "{n} entry|entries")`; [persist: Save];
info `"Saved '{name}'. You can apply it to any crew member."` (title `"Save schedule"`).

**BUILD-122 — "📋 Apply saved...".** None → info title `"Apply schedule"`: `"No saved schedules yet. Build one and click
'Save as...'."`. Picker `"Apply a saved schedule"` with `ScheduleTemplate.Display` = `"{name or (unnamed)}  ·  {n}
entry|entries"` + `"  ·  {VesselName}"` when set. Then Yes/No/Cancel title `"Apply schedule"`: `"Apply '{name}'
({n} entries) to {crewFullName}.\n\nYes = replace this crew's schedule\nNo = append\nCancel = nothing"` (always
"entries"). → `ApplyToCrew` (BUILD-A13), [persist: Save], re-`Bind` (vessel combo + timeline refresh; the add-row
date resets to today), info `"Applied {n} entry|entries to {crewFullName}."` (title `"Apply schedule"`). Not logged.

**BUILD-123 — "📤 Export...".** Empty → info title `"Export"`: `"No schedule to export."`. Save dialog title
`"Export schedule"`, filter `"AA schedule (*.aasched.json)|*.aasched.json|JSON (*.json)|*.json"`, default name
`"Schedule-{Sanitize(fullName)}.aasched.json"` (fallback `"crew"`), default ext `.aasched.json`. Writes
`CaptureFromCrew(fullName + " schedule")` as indented JSON (§4.5). Success → `"Exported to:\n{path}"` (title
`"Export complete"`); error → `"Could not export:\n\n{message}"` (title `"Export failed"`).

**BUILD-124 — "📥 Import...".** Open dialog title `"Import schedule"`, filter `"AA schedule
(*.aasched.json;*.json)|*.aasched.json;*.json|All files (*.*)|*.*"`. Parse (BUILD-A14) → the template (fresh Ids) is
**added to `ScheduleTemplates` and saved first**, then the Apply confirmation of BUILD-122 runs (Cancel still keeps
the imported template). Any exception (parse, save, apply) → `"Could not import the schedule:\n\n{message}"` (title
`"Import failed"`).

**BUILD-125 — Schedule-template management gaps.** There is **no UI** to rename, delete, reorder or view schedule
templates; `ScheduleEntry.EndDate`, `EndTime`, `Notes` have no UI but are preserved through capture/apply/export.
Crew schedules are not shown in the Calendar, due-dates window or Planner.

### J. Shared dialogs & cross-cutting

**BUILD-130 — Prompt dialog (`PromptWindow`).** Title = caption, 440×170, not resizable; bold 14-pt caption,
prompt label, single-line text box pre-filled and fully selected; `"Cancel"` and accent `"OK"` (Enter = OK; **Esc
does nothing** on Windows). Returns the raw text (callers decide on trimming).

**BUILD-131 — Item picker (`ItemPickerWindow`).** Window title always `"Pick items"`, 500×500; the string each
caller passes (written as "picker titled …" throughout this spec) is the **bold prompt label** at the top; search
box; list (`Display`); `"Cancel"` / accent `"OK"` (Enter). On the Mac the caller's string becomes the sheet's
heading. Multi mode = click-toggle selection; single mode = one. Search is a
case-insensitive substring filter on `Display`; **changing the filter replaces the list and drops any selection**.
OK returns the tags of the selected rows (possibly none — callers then no-op, except BUILD-079).

**BUILD-132 — Modal/owner behaviour.** All builders, editors and pickers are modal, centered on their owner.

**BUILD-133 — Undo.** None of the builder, step/subtask editor, saved-list or schedule operations are undoable and
none use the Trash.

**BUILD-134 — Dark mode.** All chrome uses theme brushes (`Panel`, `PanelAlt`, `BorderB`, `Accent`, `Muted`,
`AccentButton` style); the read-only viewer's document surface uses fixed light paper colours (`EditorBg`/`EditorFg`)
in both themes so user-applied text colours stay readable; strikethrough via a bool→decoration converter.

**BUILD-135 — Activity-log entries emitted by this subsystem.** (`LogEntry { TimestampUtc, Action, Kind, Name,
Detail }`; `Name` trimmed, `"(unnamed)"` if blank; log capped at 10 000 entries, oldest dropped.)

| Action | Kind | Name | Detail | Where |
|---|---|---|---|---|
| Added | logKind | `"{n} added (bulk)"` | owner | builder Add all |
| Added | logKind | item title | owner | builder add/insert |
| Removed | logKind | `"{n} removed"` | owner | builder Delete |
| Added | logKind | `"{n} added (from saved list '{name}')"` | owner | builder Load |
| Added | `"Saved list"` | list name | `"{n} item(s)"` | Save as list, Duplicate |
| Added | `"Saved list"` | list name | `"empty"` | + List |
| Removed | `"Saved list"` | list name | `""` | Delete (tab or Manage) |
| Added / Removed | `"Checklist step"` | step title | procedure name | Specifics + Step / Remove |
| Added | `"Task"` | task name | `"linked to step '{title}'"` | Specifics + New task |
| Added | `"Schedule"` | template name | `"{n} entry|entries"` | Save schedule |

`logKind`/owner per BUILD-001; subtask builder uses `"Subtask"`/task name.

---

## 3. Logic & algorithms

### BUILD-A1 — Selected indices / first / last (ChecklistBuilderControl.xaml.cs:273–278; SubtaskBuilderWindow.xaml.cs:233–250)
`SelectedIndicesAscending` = indices of selected items in the collection, ≥0, ascending. First = [0] or −1; Last =
[^1] or −1.

### BUILD-A2 — Up / Down (ChecklistBuilderControl:115/125; SubtaskBuilderWindow:154/163)
```
up:   picks = asc; if picks empty or picks[0]==0 → return
      for i in picks (ascending): coll.move(from: i, to: i-1)
down: if picks empty or picks.last == count-1 → return
      for i in picks (descending): coll.move(from: i, to: i+1)
```
`move(from,to)` = ObservableCollection.Move: remove at `from`, insert at `to`.

### BUILD-A3 — Builder Move-to (ChecklistBuilderControl:159 `MoveStepsTo`; SubtaskBuilderWindow:197 `MoveItemsTo`)
```
picksOrdered = picks.map{(item, coll.index(item))}.filter{idx>=0}.sorted(by idx)
if empty → return
shift    = picksOrdered.count{ idx < targetIndex }
adjusted = clamp(targetIndex - shift, 0, coll.count - picksOrdered.count)
remove picks from highest idx to lowest
for k in 0..<n: coll.insert(picksOrdered[k].item, at: adjusted + k)
```
`targetIndex` is the flat index of the "Before:" item, 0 for top, `count` for bottom.

### BUILD-A4 — `Shorten` (two variants)
* Builders (ChecklistBuilderControl:280, SubtaskBuilderWindow:252): null/empty → `""`; replace `\r` and `\n` each
  with a space; trim; if length ≤ max return it, else first `max−1` UTF-16 units + `"…"`.
* Saved Lists (SavedListsPage:381): `(s ?? "").Trim()`; empty → `"(unnamed)"`; then same truncation (no newline
  replacement).
Swift: truncate on `String.utf16` units to match .NET exactly (or on Characters — differences only appear with
surrogate pairs/combining marks at the cut; prefer Character-safe truncation and accept the benign difference).

### BUILD-A5 — Duration parsing (ChecklistStepEditorWindow:58; SubtaskEditorWindow:135)
`int.TryParse(text)` with current culture, `NumberStyles.Integer` (leading/trailing whitespace, leading sign
allowed; no thousands separators, no decimals); accept only `m > 0`. Swift: trim whitespace, allow a leading `+`,
parse `Int32` of ASCII digits; reject ≤0 / overflow.

### BUILD-A6 — `WorkRange.Coerce(start?, deadline?, editedStart)` (Services/WorkRange.cs:15)
```
start = start?.dateOnly; deadline = deadline?.dateOnly
if let s = start {
   if deadline == nil { deadline = s }
   else if s > deadline! { if editedStart { deadline = s } else { start = deadline } }
}
return (start, deadline)
```
The subtask editor feeds it the **sibling picker's** value (safe because the window is modal and short-lived); the
long-lived Specifics pane and Ctrl+N feed it the **model's** partner value (a fixed data-loss bug — keep that rule
anywhere a date pane outlives a single edit session).

### BUILD-A7 — `SavedListOrder.Nudge(all, picks, up)` (Services/SavedListOrder.cs:30)
```
guard picks non-empty and all picks share one GroupId g else false
span = indices i where all[i].GroupId == g          // flat indices of the group, in order
guard span.count >= 2 else false
at = picks.map{ span.firstIndex(of: all.index(of: $0)) }.filter{>=0}.sorted()
guard !at.isEmpty; if up && at[0]==0 → false; if !up && at.last == span.count-1 → false
for pos in (up ? at : at.reversed()): all.move(from: span[pos], to: span[up ? pos-1 : pos+1])
return true
```
`span` is computed once, before the moves. Nothing is ever created/removed; other groups' relative orders are
untouched (fuzz-verified, 20 000 random cases).

### BUILD-A8 — `SavedListOrder.MoveTo(all, picks, targetInGroup)` (:49)
```
guard same group g; span = GroupSpan(all, g); guard span.count >= 2
moving = Set(picks); ordered = span.map{all[$0]}; guard moving ⊆ ordered
before    = ordered.prefix(clamp(target, 0, ordered.count)).count{ moving.contains }
remaining = ordered.filter{ !moving.contains }
inOrder   = ordered.filter{ moving.contains }          // movers keep relative order
remaining.insert(contentsOf: inOrder, at: clamp(target - before, 0, remaining.count))
for pos in 0..<span.count {
   from = all.index(of: remaining[pos]); if from != span[pos] { all.move(from: from, to: span[pos]) }
}
return true
```
The re-anchoring loop uses live indices after each move, so the flat positions of *other* groups' lists can shift;
only group subsequences are guaranteed. Reproduce exactly (see §7.4 vectors) so flat order matches Windows
byte-for-byte after identical operations.

### BUILD-A9 — Export entry lists (:75 `GroupEntries`, :88 `AllEntries`)
* `GroupEntries(data, gid)`: `name` = group name if `gid` resolves, else nil; returns every template with
  `GroupId == gid` in collection order, tagged `name` (nil when name is null/empty).
* `AllEntries(data)`: stable sort of the collection by key = (`GroupId == nil` ? `"\u{FFFF}"` :
  groupName(lowercased-invariant), where a dangling id yields `""`), ties by collection index; tag = group name
  for non-nil `GroupId` (dangling → `""`), nil otherwise. Group keys compare with the **current-culture** string
  comparer (LINQ default). Mac: compare with `localizedCompare`, and force nil-group last explicitly rather than
  relying on U+FFFF collation.

### BUILD-A10 — Saved Lists tab rows (SavedListsPage:47 `Refresh`)
Row: `GroupName` (BUILD-072), `GroupSort` = `GroupId == nil ? "\u{FFFF}" : GroupName.lowercased()` (note: a
dangling id gives `"ungrouped"`, so its rows sort among named groups but land in the "Ungrouped" header), `SortIdx`
= collection index, `Name` = display name. Sort: GroupSort ↑ then (A-Z ? Name ↑ : SortIdx ↑); group by GroupName in
first-appearance order. Selection kept by Id (primary only) across refreshes; after reorders all moved ids are
reselected (`Reselect`, :370).

### BUILD-A11 — Filename sanitising
`Sanitize(s)` (SavedListsPage:470; ScheduleBuilderControl:247): replace **each Windows invalid filename char**
(`"` `<` `>` `|` NUL, U+0001–U+001F, `:` `*` `?` `\` `/`) with `_`; if the result is null/whitespace return the
fallback (`"saved-lists"` / `"crew"`); else return it trimmed. Note tab (U+0009) is replaced *before* the whitespace
test. Use the Windows set on the Mac too, so default filenames match across platforms. Procedure checklist export
uses the same char set without trimming/fallback (`"checklist-{name}.pdf"`; null name → `"procedure"`).

### BUILD-A12 — `ScheduleService.CaptureFromCrew(name, crew, data)` (Services/ScheduleService.cs:26)
`ScheduleTemplate { Name = name.trim, VesselId = crew.ScheduleVesselId, VesselName = vessel name if the id resolves
else "", Entries = crew.Schedule.map(CloneEntry), CreatedUtc = now UTC, Id = new }`.
`CloneEntry` (:14) copies Title, Kind, RefId, Date, Time, EndDate, EndTime, Notes; **new Id, Done = false**.

### BUILD-A13 — `ApplyToCrew(t, crew, replace)` (:35)
replace → clear; append `CloneEntry` of each (new Ids, not done); **if `t.VesselId != nil` then
`crew.ScheduleVesselId = t.VesselId`** (even if that vessel does not exist locally; a nil template id leaves the
crew link unchanged). Returns entry count.

### BUILD-A14 — Schedule JSON export/import (:43/:48)
Export: `JsonSerializer.Serialize(t, new JsonSerializerOptions { WriteIndented = true })` → UTF-8 (no BOM) via
`File.WriteAllText`. **Default options**: nulls ARE written, enums as integers, PascalCase, default escaping,
2-space indent, CRLF newlines on Windows. Import: `Deserialize<ScheduleTemplate>(ReadAllText)` with default
options (**case-sensitive** property names; unknown members ignored; a JSON string where a number enum is expected
throws). `null` result → `InvalidDataException("This file is not a valid schedule.")`. Then `t.Id = new`, every
entry `Id = new`; `CreatedUtc`, `Done` flags and everything else kept as in the file. An object with no known
members imports as an empty unnamed template.

### BUILD-A15 — `NormTime(s)` (ScheduleBuilderControl:141)
Trim; regex `^(\d{1,2}):(\d{2})$`; match → `"{int(hour):00}:{minutes}"`, else `""`. No range validation
(`"25:99"` stays). .NET `\d` matches any Unicode decimal digit and `int.Parse` then throws on non-ASCII digits (a
crash on Windows); Mac: use `[0-9]`.

### BUILD-A16 — Timeline grouping (ScheduleBuilderControl:55)
`when = CrewMember.ParseDate(Date)`: exact `yyyy-MM-dd`, `yyyy/MM/dd`, `yyyy.MM.dd` (invariant), else a general
invariant parse (month-first for ambiguous `a/b/yyyy`), else nil. Group label per BUILD-116 comparing
`when.date` to local today/tomorrow; `GroupSort = when?.yyyy-MM-dd ?? "\u{FFFF}"`; `TimeSort = Time.isEmpty ?
"00:00" : Time`. Sort GroupSort ↑, TimeSort ↑ (ties: unspecified on Windows; Mac: stable by collection order).
`Date` is written with `ToString("yyyy-MM-dd")` in the current culture — Mac must always write Gregorian,
`en_US_POSIX`.

### BUILD-A17 — Saved-list PDF heading state machine (PdfExporter.cs:95)
```
lastGroup = nil; started = false
for (group, tpl) in entries {
   g = group.isBlank ? nil : group
   if !started || g != lastGroup {
       if g != nil { H1(g) } else if started { H1("Ungrouped") }
       lastGroup = g; started = true
   }
   H2("{name or (unnamed list)}   ({n} item|items)")
   n = 1
   for it in tpl.Items { paragraph(style Bullet): bold(numbered ? "\(n). " : "•  "); n += 1 (numbered only)
       text(it.Title); if it.IsJob { "  " + italic grey "(schedulable)" }
       container body at +0.6 cm (skipped when no visible text)
       if files { Muted para, indent 0.6 cm: italic "Files: " + names joined ", " } }
}
```
Numbering restarts at 1 for every list. Group comparisons are exact string equality (case-sensitive).

### BUILD-A18 — Insert-into-note line building (InsertSavedListWindow.xaml.cs:114)
`titles = items.map{ ($0.Title ?? "").trim }.filter{ !isEmpty }`; with duration each kept title maps back to its
item (the k-th non-blank) and gets `"  ({mins} min)"` when `mins > 0`. Notes count = items whose raw XAML is
non-whitespace (including blank-titled items); files = sum of all items' file counts.

### BUILD-A19 — `ChecklistTemplateService.CloneContainer` (:133) / `CloneFile` (:144)
New `Container` (new Id) with `RichTextXaml` copied **as a string** (never parsed/re-serialised), `IsLocked` copied,
each file cloned (new `FileItem.Id`; Name, Path, Kind, Added, IsLink, LinkInPlace, LinkedItemIds copied),
`SharedWithContainerIds` copied. Null source → empty container.

### BUILD-A20 — Persistence helpers (AppRepository.cs)
`MarkDirty()` — sets dirty, restarts a 750 ms debounce; on tick: stamp `LastModified = now (local)`, serialise on
the UI thread, write on a background thread (chained writes). `Save()` — stop debounce, stamp, serialise, write and
**wait** (15 s timeout → throws). `FlushIfDirty()` — `Save()` iff dirty. None of the builders catch Save
exceptions (a failing disk surfaces as an unhandled-exception dialog on Windows).

### BUILD-A21 — Checklist-only exports (Services/ChecklistExporter.cs) — see BUILD-C1/C2.

---

## 4. Data formats

### 4.1 JSON options (data.json)
`DataStore.Opts`: `WriteIndented = false`, `ReferenceHandler.IgnoreCycles`, `DefaultIgnoreCondition =
WhenWritingNull`; **no** enum-string converter (enums are integers), **no** naming policy (PascalCase = C# names),
**case-sensitive** on read, default encoder (non-ASCII and the HTML-sensitive characters `<` `>` `&` `'` `"` `+`
and backtick written as `\uXXXX`, e.g. a XAML body starts `"<Section xmlns="http…"`). `[JsonIgnore]` members
are never written. GUIDs lowercase `D` format. `DateTime` ISO-8601: Kind Unspecified → `"2026-07-18T00:00:00"`,
Utc → `"…Z"`, Local → `"…+02:00"`; fractional seconds up to 7 digits, trailing zeros trimmed, omitted when zero.
Collections/objects that are missing in JSON keep their C# initialiser defaults (empty collections, `DurationMinutes
= 60`, `Kind = Note`, etc.).

### 4.2 Models touched (declaration = serialisation order)

```jsonc
// ChecklistStep   (Procedure.Steps[], CrewMember.Checklist[])
{ "Id":"guid", "Title":"", "BucketIds":["guid"], "Done":false,
  "Deadline":"2026-07-18T00:00:00",        // omitted when null; date-only, Kind usually Unspecified
  "IsJob":false, "DurationMinutes":60,
  "ScheduledStart":"2026-07-18T09:15:00",  // omitted when null (Planner)
  "TaskIds":["guid"], "EquipmentIds":["guid"], "Container":{…} }        // JobName is [JsonIgnore]

// Container
{ "Id":"guid", "RichTextXaml":"<Section xmlns=…>…</Section>", "Files":[FileItem…],
  "SharedWithContainerIds":["guid"], "IsLocked":false }

// FileItem
{ "Id":"guid", "Name":"", "Path":"files/…|abs path|URL", "Kind":0, "Added":"2026-07-08T10:20:30.1234567+02:00",
  "IsLink":false, "LinkInPlace":false, "LinkedItemIds":["guid"] }       // Kind: 0 Document,1 Image,2 Video,3 Link,4 Other

// ChecklistTemplateItem   (no Id!)
{ "Title":"", "DurationMinutes":60, "IsJob":false, "Container":{…} }

// ChecklistTemplate   (AppData.ChecklistTemplates[] — ARRAY ORDER = user's arrangement)
{ "Id":"guid", "Name":"", "Items":[…], "CreatedUtc":"2026-07-08T10:20:30.1234567Z",
  "GroupId":"guid" }                      // GroupId omitted when null; Display is [JsonIgnore]

// ListGroup   (AppData.ListGroups[] — creation order)
{ "Id":"guid", "Name":"", "CreatedUtc":"…Z" }

// ScheduleEntry   (CrewMember.Schedule[], ScheduleTemplate.Entries[])
{ "Id":"guid", "Title":"", "Kind":0, "RefId":"guid", "Date":"2026-09-29", "Time":"09:00",
  "EndDate":"", "EndTime":"", "Done":false, "Notes":"" }
  // Kind: 0 Note, 1 Task, 2 Procedure, 3 Equipment. RefId omitted when null in data.json.
  // When / KindIcon / WhenDisplay are [JsonIgnore].

// ScheduleTemplate   (AppData.ScheduleTemplates[])
{ "Id":"guid", "Name":"", "VesselId":"guid", "VesselName":"", "Entries":[…], "CreatedUtc":"…Z" }

// CrewMember (subset)
{ "Id":"guid", "Checklist":[ChecklistStep…], "Schedule":[ScheduleEntry…], "ScheduleVesselId":"guid", … }

// TaskItem (subset edited here) — see hierarchy spec for full shape
{ …, "Name":"", "Description":"", "Deadline":"…", "RangeStart":"…", "IsJob":false, "DurationMinutes":60,
  "ScheduledStart":"…", "Recurrence":0, "RecurrenceSpawned":false, "IsComplete":false, "Status":0,
  "Subtasks":[…], "Container":{…}, "BucketIds":[…] }
  // Recurrence: 0 None,1 Daily,2 Weekly,3 Monthly,4 Yearly. Status: 0 Todo,1 InProgress,2 Blocked,3 Done.
  // RangeStart omitted when null (zero-migration); legacy "BucketId" read-only migration into BucketIds.

// UiState (subset)
"Ui": { …, "SortAZ": { "savedlists": true, "Task": false, … } }   // shared preference (syncs)

// LogEntry
{ "TimestampUtc":"…Z", "Action":"Added|Removed", "Kind":"Saved list", "Name":"…", "Detail":"…" }
```

**Date-only fields** (`Deadline`, `RangeStart`) come from pickers as Kind Unspecified (no offset), but other code
paths (e.g. recurrence from `DateTime.Today`) may write a Local offset. Mac reader: accept all three forms and take
the **literal calendar date** as written (never convert time zones — that can shift the day). Mac writer: keep the
Kind that was read; new values written as Unspecified (`yyyy-MM-dd'T'HH:mm:ss`).
**UTC stamps** (`CreatedUtc`, `TimestampUtc`): written with `Z`; a value without offset is treated as UTC by
`ToLocalTime()`; display local `yyyy-MM-dd`.

### 4.3 Cross-version / cross-device rules
* `ChecklistTemplates` order is meaningful and is carried by array order in data.json/.aaz and by Flash Sync's
  `Order` map (QR_SYNC_PROTOCOL §10: templates are an Id-bearing collection, so a reorder produces
  `Order.ChecklistTemplates`). Never re-sort the array on load/save.
* Template items have no `Id`; the whole template travels as one object in Flash Sync `Sets`.
* Template item containers are included in bundle file enumeration (`EnumerateContainers`) so their attachments are
  zipped and path-normalised (`files/…` relative). The Mac container enumeration must include
  `ChecklistTemplates[].Items[].Container` and `Crew[].Checklist[].Container`.
* `Ui.SortAZ` is merged key-by-key by Flash Sync (not in the per-device denylist).
* Unknown members on any of these objects must be preserved by the Mac build (architecture brief).

### 4.4 Rich text (XAML) in this subsystem
* **Stored**: `Container.RichTextXaml` = WPF `TextRange.Save(DataFormats.Xaml)` output — a `<Section
  xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve" …>` root with
  `Paragraph`/`List`/`ListItem`/`Table`/`Run`/`Span`/`Bold`/`Italic`/`Underline`/`Hyperlink`/`LineBreak` children;
  or `""`; or a legacy `"enc:…"` blob. Full vocabulary: rich-text spec.
* **Copied verbatim** (clone/capture/apply/write-back) — never parse and re-emit during cloning; Windows keeps the
  exact string, so must the Mac.
* **Consumed** read-only by the item viewer (BUILD-076) and the saved-list PDF (BUILD-C3) through the
  XAML→NSAttributedString converter. Empty-visible-text documents render nothing in the PDF.
* **Detection** of "has notes" is a raw `IsNullOrWhiteSpace` string test (BUILD-075, BUILD-100).
* **Produced** by "insert saved list into a note" (§4.6).

### 4.5 `.aasched.json` (portable schedule template)
UTF-8, indented (2 spaces), nulls written, integers for `Kind`. Example as Windows writes it (`\r\n` line ends):
```json
{
  "Id": "5b0c8f5e-6a4e-4a7a-9f7e-2d1a1c7b9e11",
  "Name": "Jane Doe schedule",
  "VesselId": null,
  "VesselName": "",
  "Entries": [
    {
      "Id": "0f6d3c1a-2b3c-4d5e-8f90-1a2b3c4d5e6f",
      "Title": "Fire drill",
      "Kind": 2,
      "RefId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "Date": "2026-10-02",
      "Time": "09:00",
      "EndDate": "",
      "EndTime": "",
      "Done": false,
      "Notes": ""
    }
  ],
  "CreatedUtc": "2026-09-29T08:12:44.5123456Z"
}
```
Mac export must be readable by Windows' case-sensitive default deserializer: exact PascalCase keys, integer enums,
GUID strings, ISO dates; `null` allowed. Mac import must accept Windows files (CRLF, optional BOM, nulls, missing
keys), and also `.json` files.

### 4.6 XAML shape produced by "insert saved list into a note"
`ListFormatting.Build(lines, numbered)` builds `List(MarkerStyle = Disc|Decimal, Padding = 24,0,0,0, Margin =
0,6,0,6)` → per line `ListItem` → `Paragraph(Margin = 0,1,0,1)` → `Run(text)`; it is inserted after the caret's block
(an empty `Paragraph` is appended after it when it becomes the last block) and saved through `TextRange.Save`,
giving XAML like
`<List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Check A</Run></Paragraph></ListItem>…</List><Paragraph/>`
inside the `<Section>` (WPF may add inherited attributes). The Mac converter must emit an equivalent `List` for an
`NSTextList` (disc ↔ `Disc`, decimal ↔ `Decimal`) with these margins/padding so a Windows reader sees the same list.

### 4.7 Checklist-only PDF (BUILD-C1)
A4 portrait, margins 2 cm, Calibri 11 (`Normal`). Footer right 9 pt grey (120,120,120) `"Page X / Y"`. Title =
procedure name 22 pt bold (space after 2 pt); subtitle `"Checklist"` grey (space after 10 pt). No steps → italic
`"(no steps)"`. Else a table, borders 0.5 pt (180,180,180), cell padding 3 pt, columns 0.9 / 1.0 / 7.2 / 2.2 / 5.0 cm;
heading row (repeats on each page, shading 235,235,235, bold) `"#"`, `"Done"`, `"Step"`, `"Due"`, `"Tasks /
Equipment-Area"`; rows: index from 1, `"[x]"` or `"[  ]"` (two spaces), title, deadline `yyyy-MM-dd` or blank, then
`"T: {taskName}"` lines followed by `"E/A: {equipmentName}"` lines joined by `\n` (unresolvable ids skipped).
`doc.Info.Title = "Checklist - {name}"`, Author `"AA"`.

### 4.8 Checklist-only XLSX (BUILD-C2)
ZIP (deflate "Optimal") with parts in this order: `[Content_Types].xml`, `_rels/.rels`, `xl/workbook.xml`,
`xl/_rels/workbook.xml.rels`, `xl/styles.xml`, `xl/worksheets/sheet1.xml` (UTF-8, no BOM; exact XML text in
`Services/ChecklistExporter.cs:149–240`). Sheet name = XML-escaped procedure name (or `"Checklist"`), **then**
truncated to 31 chars. Styles: font 0 Calibri 11, font 1 bold; fill 1 solid `FFEEEEEE`; `cellXfs` 0 = normal, 1 =
bold+fill (header). Columns widths 5, 7, 55, 14, 40, 40. Header row: `"#"`, `"Done"`, `"Step"`, `"Due"`, `"Linked
Tasks"`, `"Linked Equipment/Area"`; data rows: index, `"Yes"`/`"No"`, title, `yyyy-MM-dd` or `""`, task names joined
`"; "`, equipment names joined `"; "`. Every cell is `t="inlineStr"` with `<is><t xml:space="preserve">…</t></is>`
and `s="1"` on row 1 else `s="0"`; cell refs via `ColRef` (A…Z, AA…). Escaping: `& < > "` only. An existing target
file is deleted first.

### 4.9 Saved-list PDF (BUILD-C3)
A4 portrait; margins 2 cm; header/footer distance 1 cm. Styles: `Normal` = resolved font (Calibri → Arial →
Segoe UI), 11 pt, space after 3 pt, line spacing ×1.15; `Title` 26 pt bold (20,20,20), space after 4 pt; `Subtitle`
12 pt grey (120,120,120), space after 12 pt; `H1` 16 pt bold, space before 16 / after 6 pt, keep-with-next, bottom
border 0.75 pt (60,60,60); `H2` 13 pt bold, before 10 / after 4 pt, keep-with-next; `Bullet` left indent 0.6 cm,
first-line indent −0.4 cm; `Muted` 10 pt grey (120,120,120). Header (every page) 9 pt grey: `"Saved lists:
{docTitle}"` + right tab at 16 cm + `DateTime.Now "yyyy-MM-dd HH:mm"`. Footer right 9 pt grey `"Page X / Y"`.
Body: Title = doc title; Subtitle `"Saved checklists  ·  {n} list"` / `"… lists"`; then BUILD-A17. Container bodies
use the full rich-text renderer (colours, fonts, sizes, alignment, lists with per-level indent, tables, clickable
links incl. auto-linked URLs/e-mails, strike overlay, whole-line highlight — see PDF spec) with every produced
paragraph's left indent increased by 0.6 cm. Info: Title = doc title, Author `"AA"`.

---

## 5. Dependencies

**Calls out to**
* `AppRepository`: `Data`, `MarkDirty`, `Save`, `FlushIfDirty`, `LogAdded`, `LogRemoved`, `FindById` (checklist
  export), `IsDirty`.
* `ChecklistTemplateService` (Capture*/Apply*/Clone/ToSteps/WriteBackFromSteps/ItemToTask/CloneContainer).
* `SavedListOrder` (GroupSpan/Nudge/MoveTo/GroupEntries/AllEntries), `ScheduleService`, `WorkRange`.
* `PdfExporter.ExportSavedLists`, `ChecklistExporter.ExportPdf/ExportXlsx`.
* Views: `PromptWindow`, `ItemPickerWindow`/`PickerItem`, `ListStylePromptWindow.Ask`, `ContainerEditor`
  (`Load(container, repo)`, `FlushPending()`), `ContainerViewerWindow`, `ChecklistStepEditorWindow`,
  `SubtaskEditorWindow`, `TemplateEditorWindow`, `BatchDoneMenu`/`BatchDeadlineMenu` (procedure grid).
* `DataStore.ResolveFilePath` (viewer), `PasswordService.IsEncrypted` (viewer).
* `CrewMember.ParseDate`, `CrewMember.FullName`.

**Called by**
* `MainWindow` (`ListsPg.Init`, `ListsPg.Refresh` on tab select).
* `HierarchyPage.BuildProcedureSpecifics` / `BuildTaskSpecifics` (builders, editors, exports).
* `CrewEditorWindow` (`Builder.Bind`, `ScheduleCtrl.Bind`).
* `QuickWorkWindow` (editors, builders, template flows), `CalendarPage`, `PlannerPage`, `BucketsPage`,
  `BoardPage` (editors; `SavedListPicker`), `ContainerEditor` (`InsertSavedListWindow`).

**Data read by other subsystems** — steps' `Deadline`/`Done` (Calendar, due-dates window, overdue), `IsJob`/
`DurationMinutes`/`ScheduledStart` (Planner via `AllJobs`), `TaskIds`/`EquipmentIds` (Relationship map, backlinks,
`PurgeReferences`, DataDiff), `BucketIds` (Buckets, Ctrl+N), recurring-procedure renewal (resets step Done, shifts
step deadlines).

**Windows-only APIs used**
| API | Where |
|---|---|
| `Microsoft.Win32.SaveFileDialog` / `OpenFileDialog` | PDF/XLSX export, schedule export/import |
| `Process.Start(… UseShellExecute = true)` | open exported PDF / XLSX, viewer file & link launch |
| `System.Windows.MessageBox` (Yes/No/Cancel semantics) | all confirmations |
| WPF `DatePicker` (`DisplayDateStart/End`), `ListCollectionView` grouping/sorting, `GridSplitter`, `ToggleButton` | UI |
| WPF `RichTextBox` + `TextRange.Load/Save(DataFormats.Xaml)` | viewer, editor, PDF parsing |
| MigraDoc / PDFsharp (`UseWindowsFontsUnderWindows`, `System.Windows.Media.Fonts.SystemFontFamilies`) | PDFs |
| `System.IO.Compression.ZipArchive` | XLSX |
| `Mouse.OverrideCursor` | busy cursor during checklist export |
| `Path.GetInvalidFileNameChars()` (Windows set) | filename sanitising |

---

## 6. macOS adaptation notes

### 6.1 Architecture (per ARCHITECTURE-BRIEF)
* `AACore/SavedLists/`: `ChecklistTemplateService`, `SavedListOrder`, `ScheduleService`, `WorkRange`,
  `ScheduleTime.normalize`, `WindowsFileName.sanitize(_:fallback:)`, `SavedListsPDFExporter`,
  `ChecklistExporter` (PDF + XLSX) — pure, unit-tested, no SwiftUI. Implement `move(from:to:)` with exact
  ObservableCollection semantics (remove then insert) as an `Array` extension shared by all reorder code.
* One generic builder: `ChecklistBuilderView<Item: BuilderItem>` where `BuilderItem` abstracts title/name key path,
  done/complete key path, deadline, `make(title:)`, editor presentation, `logKind`, owner and noun strings
  ("item"/"subtask"). Configure: `showsManageSavedLists` (true for step hosts, false for subtasks), `buttonBarWraps`.
  Reused by the procedure window, crew tab, template editor, subtask builder, and the Ctrl+N inline builder.
* Editors: `ChecklistStepEditorView`, `TaskItemEditorView` — each embeds the shared `ContainerEditorView`
  (rich-text + file bank, see container spec); both expose a `mode` (`.live`, `.savedListItem`).
* Model objects are `@Observable` reference types; builders should hold the **owner's Id** and re-resolve through the
  store after any data reload (shared-save pull, Flash Sync apply, import) instead of holding object references —
  or the store should defer pulls while a builder/editor sheet is open (see §8, R1).

### 6.2 Presentation
| Windows | macOS |
|---|---|
| `ChecklistBuilderWindow`, `SubtaskBuilderWindow`, `TemplateEditorWindow` (modal windows) | Resizable **sheets** on the owning window (min 780×560, remember size), header = large title + secondary help text; "Close" as the sheet's primary action (⌘W / Esc also close — closing is saving). Alternatively a `Window` scene per owner Id when opened from Ctrl+N (single instance per Id). |
| Left bulk pane + splitter + right list | `HSplitView` (AppKit-backed, draggable divider) — left `TextEditor` in the brief's monospaced font (Consolas → SF Mono) with "Add all" (`.borderedProminent`, ⌘↩), "Clear", `Toggle("Replace existing")`; right `List(selection: Set<ID>)` |
| Button bar `+ Item … Delete` | A compact bar of labelled buttons with SF Symbols: `plus` "+ Item", `arrow.up.to.line.compact` "Insert before", `arrow.down.to.line.compact` "Insert after", `pencil` "Edit…", `chevron.up`, `chevron.down`, `arrow.up.and.down.text.horizontal` "Move to…", `trash` "Delete". Keep the Windows tooltips as `.help()`. Also expose the same commands in the row `.contextMenu` |
| "Saved lists:" strip | A header bar (material background) with `square.and.arrow.down` "Save as list…", `list.bullet.clipboard` "Load a saved list…", `folder.badge.gearshape` "Manage saved lists…" |
| `PromptWindow` | Small sheet with title, prompt, `TextField` (pre-filled, selected), Cancel (Esc) / OK (↩, disabled while blank). Returns raw text; trimming stays at the call site to keep BUILD-006 vs BUILD-015 differences |
| `ItemPickerWindow` | Sheet with `.searchable` `List` (single or multi selection), Cancel / OK. **Mac deviation (improvement):** keep selection across search filtering (Windows drops it — a usability bug, no capability lost) |
| `MessageBox` Yes/No/Cancel "Yes = replace / No = append" | `NSAlert` / `.confirmationDialog` with explicit buttons **"Replace"**, **"Append"**, **"Cancel"** (message text keeps the Windows sentence; informative text keeps the name/count). Mapping is fixed: Replace ⇔ Yes, Append ⇔ No. Manage dialogs: "Rename…", "Delete…", "Cancel". Destructive buttons use `.destructive` role |
| Info/warning/error `MessageBox` | `NSAlert` sheet with matching style (informational / warning / critical) and the exact Windows text |
| WPF `DatePicker` (nullable, typeable) | `OptionalDatePicker`: `DatePicker(.field)` + clear (`xmark.circle.fill`) button + "no date" state; greyed ranges via `in:` (`start...` / `...deadline`) |
| Enum combos | `Picker` with the raw enum names shown as on Windows (`Todo`, `InProgress`, …). *Optional Mac deviation:* friendlier labels ("To Do", "In Progress") — display only |
| Strikethrough | `.strikethrough(item.done)` (live via Observation) |
| Double-click to edit | `List` `.contextMenu(forSelectionType:primaryAction:)` — primary action (double-click / ↩) opens the editor for the primary selected item |
| Emoji button glyphs | SF Symbols + the same text (brief: emoji become symbols unless user data) — 💾 `square.and.arrow.down`, 📋 `list.clipboard`, 📤 `square.and.arrow.up`, 📥 `square.and.arrow.down.on.square`, 📄 `doc.richtext`, ✎ `pencil`, 🛠 `hammer`, 🗓 `calendar`, ≔ `list.bullet.indent` |

**Keyboard (Mac mapping; Windows has no explicit shortcuts here beyond list defaults and Enter = OK):**
⌘A select all · ↩ / double-click Edit · ⌫ Delete (with the BUILD-014 confirmation) · ⌥⌘↑ / ⌥⌘↓ move up/down
(Writer-style, matching the rich-text list reorder gesture) · ⇧⌘M Move to… · ⌘↩ Add all (in the bulk editor) ·
Esc/⌘W close sheet · Esc cancels prompts (Windows PromptWindow ignores Esc — harmless improvement).

**Drag & drop (additive):** rows reorderable by drag in the builders (`.onMove` → BUILD-A3 with the drop index) and
within a group in the Saved Lists sidebar (→ `SavedListOrder.MoveTo` with the in-group target); dropping a list on
another group's section header = "Move to group". Disabled while Sort A-Z is on. These call the same algorithms so
results equal the button paths.

### 6.3 Saved Lists tab
`NavigationSplitView`:
* **Sidebar** (min 280, ideal 330): `List(selection: $selection)` with a `Section` per group — header = name +
  count badge; Ungrouped last (explicitly, not via U+FFFF); rows = name + trailing secondary `"{n} items"`
  (keep the literal Windows text). Footer = the status line (BUILD-073). `.contextMenu(forSelectionType:)` with the 10
  BUILD-090 items. Toolbar: `Menu` "+" (New List / New Group), Rename, Delete, Move to Group…, Manage Groups…,
  a ControlGroup ↑ ↓ Move to Position…, and a `Toggle` "Sort A-Z" (`textformat.abc`). Group by **Id** internally
  (display names may collide — §8 Q3), while keeping the Windows ordering rules.
* **Detail**: header (large title name, secondary subtitle BUILD-074), action row (`✎ Edit items…` prominent,
  Duplicate, Export `Menu` or three buttons), items `Table` (Title | meta) with primary action → **read-only viewer**
  presented as a sheet or a `Window(for: Container.ID)` scene (NSTextView `isEditable = false`, links via
  `textView(_:clickedOnLink:at:)` → `NSWorkspace.shared.open`; files `Table` with Name/Kind/Source/Path; double-click
  opens; Quick Look (space) on a file row is an additive nicety). Empty detail = `ContentUnavailableView("Select a
  saved list", systemImage: "list.bullet.rectangle")`.
* **Mac deviation (improvement, flag):** "Export ALL (PDF)…" enabled even with no selection (Windows greys it because
  the whole pane is disabled).
* Refresh on tab selection is implicit with Observation; still recompute derived rows on every model change.

### 6.4 Exports & files
* Save panels: `NSSavePanel` with `nameFieldStringValue` = the Windows default name, `allowedContentTypes` `[.pdf]`
  / `[UTType(filenameExtension:"xlsx")]` / `[.json]` (keeps `Schedule-X.aasched.json` intact; set
  `allowsOtherFileTypes = true`, `isExtensionHidden = false`). Import: `NSOpenPanel` `[.json]` plus an accessory popup
  "AA schedule (*.aasched.json, *.json)" / "All files".
* "Open it now?" / auto-open → `NSWorkspace.shared.open(url)`.
* PDF: implement in AACore with **CoreText + CGContext PDF** (`CGContext(url:mediaBox:)`, A4 = 595.28×841.89 pt,
  2 cm = 56.69 pt, 1 cm = 28.35 pt). Two passes (layout to count pages for `"Page X / Y"`, then draw). Headings with
  keep-with-next, hanging indents via `NSParagraphStyle.headIndent/firstLineHeadIndent`, links via
  `CGPDFContextSetURLForRect` for every `.link` run. Fonts: Calibri if installed (Office), else Arial (ships with
  macOS) — the same fallback order as Windows. Rich-text bodies come from the XAML→`NSAttributedString` converter
  (+0.6 cm to every paragraph's indents). Real strikethrough can be drawn natively (Windows overlays U+0336 only
  because MigraDoc cannot) — acceptable fidelity improvement.
* XLSX: the in-house ZIP writer (Compression framework raw DEFLATE + CRC-32) emitting byte-identical XML text.
  **Mac deviation (fix, flag):** truncate the sheet name to 31 *characters before escaping* and replace `[]:*?/\`
  with `_`, since Windows can emit invalid XML/sheet names (§8 D5).
* PDF preview: offer `QLPreviewPanel` / open in Preview after export.

### 6.5 Schedule builder (crew editor Schedule tab)
Form-style top bar: `Picker("Linked vessel", …)`, buttons with SF Symbols; add row: `OptionalDatePicker` (default
today), `TextField` with placeholder "HH:mm" (**Mac deviation:** visible placeholders "HH:mm" and "What… (or pick an
item)" — the WPF `Tag` values were intended as placeholders but never rendered), kind `Picker`, title field, "Pick
item…" (disabled for Note), "+ Add" prominent (↩ submits). Timeline: `List` with `Section` per date group (header
`calendar` symbol + label + count), rows: `Toggle(.checkbox)`, monospaced time, kind glyph (keep ✓ 📋 ⚙ • or map to
`checkmark.circle`, `list.clipboard`, `gearshape`, `circle.fill`), title with strikethrough, hover-revealed
`pencil`/`xmark` buttons. Weekday abbreviation from `Locale.current` with the **Gregorian** calendar; stored dates
always `en_US_POSIX` Gregorian `yyyy-MM-dd`.

### 6.6 Nothing is impossible on macOS
Every capability maps to native APIs. The only platform-specific items are Windows paths inside `FileItem.Path` for
live links (kept verbatim; resolution per container spec) and fonts (Calibri availability).

---

## 7. Test vectors (turn into Swift tests)

### 7.1 `WorkRange.coerce` (dates `yyyy-MM-dd`)
| start | deadline | editedStart | → start | → deadline |
|---|---|---|---|---|
| nil | nil | any | nil | nil |
| nil | 07-10 | any | nil | 07-10 |
| 07-10 | nil | true | 07-10 | 07-10 |
| 07-10 | nil | false | 07-10 | 07-10 (clearing the deadline refills it) |
| 07-05 | 07-10 | any | 07-05 | 07-10 |
| 07-15 | 07-10 | true | 07-15 | 07-15 |
| 07-15 | 07-10 | false | 07-10 | 07-10 |
| 07-10 09:30 | 07-10 18:00 | any | 07-10 00:00 | 07-10 00:00 (times stripped) |

Range hint: start 07-08, deadline 07-10 → `"range · 3 days"`; start = deadline → `""` (Clear range still visible).

### 7.2 `ScheduleTime.normalize` (NormTime)
`"7:05"`→`"07:05"`; `" 9:30 "`→`"09:30"`; `"09:30"`→`"09:30"`; `"25:99"`→`"25:99"`; `"123:45"`→`""`;
`"9:5"`→`""`; `"930"`→`""`; `"12:345"`→`""`; `""`→`""`; `"٩:٣٠"` (Arabic-Indic) → `""` on Mac (Windows crashes).

### 7.3 Builder reorder (flat list `A B C D E`)
| op | selection | result |
|---|---|---|
| up | B,C | B C A D E |
| up | B,D | B A D C E |
| up | A,C | unchanged (first at top) |
| down | B,D | A C B E D |
| down | C,E | unchanged |
| move-to "Before: E" (tag 4) | B,D | A C B D E |
| move-to top (0) | B,D | B D A C E |
| move-to bottom (5) | B,D | A C E B D |
| move-to "Before: B" (1) | E | A E B C D |
| move-to "Before: D" (3) | A,B | C A B D E |
Move-to options for `A B C D E` with B,D selected: `(Move to top)`/0, `Before: A`/0, `Before: C`/2, `Before: E`/4,
`(Move to bottom)`/5; dialog title `"Move 2 items to..."`.

### 7.4 `SavedListOrder` (notation `name(group)`; `-` = ungrouped)
| start | op | result (flat) | returns |
|---|---|---|---|
| A(g1) X(g2) B(g1) C(g1) | Nudge up [C] | A X C B | true |
| A(g1) X(g2) B(g1) C(g1) | Nudge down [A,B] | X C A B | true |
| A(g1) X(g2) B(g1) C(g1) | Nudge up [A] | unchanged | false |
| A(g1) X(g2) B(g1) C(g1) | Nudge up [A,X] (cross-group) | unchanged | false |
| A(g1) X(g2) B(g1) C(g1) | Nudge up [X] (group of one) | unchanged | false |
| A B C D (all g1) | Nudge up [B,D] | B A D C | true |
| A B C D (all g1) | Nudge down [A,C] | B A D C | true |
| U(-) A(g1) V(-) X(g2) B(g1) | Nudge up [V] | V U A X B | true |
| A B C D (g1) | MoveTo [B,D] → 2 ("Before: C") | A B D C | true |
| A B C D (g1) | MoveTo [B,D] → 0 | B D A C | true |
| A B C D (g1) | MoveTo [B,D] → 4 | A C B D | true |
| A X B Y C D (A,B,C,D g1; X,Y g2) | MoveTo [D] → 0 | D X A Y B C | true |
| same | MoveTo [A,C] → 4 | B D X Y A C | true |
| same | MoveTo [A,B] → 3 | C X A Y B D | true |
| A(g1) X(g2) B(g1) | MoveTo [A,X] → 0 | unchanged | false |
Invariants to fuzz: permutation (no loss/dup); other groups' subsequences unchanged; moved group's subsequence
equals the documented target.

### 7.5 Export ordering & headings
Groups: Beta (id b), alpha (id a). Collection: T1(b) T2(-) T3(a) T4(b) T5(-).
`AllEntries` → [(alpha,T3), (Beta,T1), (Beta,T4), (nil,T2), (nil,T5)]; PDF headings: H1 "alpha", H2 T3, H1 "Beta",
H2 T1, H2 T4, H1 "Ungrouped", H2 T2, H2 T5. Only-ungrouped export: no H1 at all. `GroupEntries(b)` → [(Beta,T1),
(Beta,T4)], doc title "Beta", first H1 "Beta". Group named "" → entries untagged, file name `saved-lists.pdf`.
Tab display (A-Z off): sections alpha[T3], Beta[T1,T4], Ungrouped[T2,T5]; status `"5 saved list(s)  ·  2
group(s)"`.

### 7.6 Strings
* `ChecklistTemplate.Display`: ("Deck rounds", 1 item) → `"Deck rounds  ·  1 item"`; ("", 0) → `"(unnamed)  ·  0
  items"`.
* `ScheduleTemplate.Display`: ("Rotation A", 1, "MV Atlas") → `"Rotation A  ·  1 entry  ·  MV Atlas"`; ("", 3, "")
  → `"(unnamed)  ·  3 entries"`.
* Items preview meta: IsJob, XAML non-blank, 2 files → `"job  ·  notes  ·  2 files"`; 1 file only → `"1 file"`;
  nothing → `""`.
* DetailSub: 3 items, group "Deck", created `2026-07-08T23:30:00Z` viewed in UTC+2 → `"3 item(s)  ·  group: Deck  ·
  created 2026-07-09"`.
* PDF H2: ("Deck", 1) → `"Deck   (1 item)"`; ("", 0) → `"(unnamed list)   (0 items)"`.
* Saved-list picker (BUILD-101): list "Deck", item "Check A" job → `"Deck  ›  Check A   · schedulable"`; list "",
  item "" → `"(unnamed list)  ›  (untitled)"`.
* Count line: 0 → `"No entries yet — pick a date, choose what, and click “+ Add”."`; 1 → `"1 entry"`; 3 with 1 done →
  `"3 entries · 1 done"`.

### 7.7 `Shorten`
Builder: `("", 60)`→`""`; `("Line1\r\nLine2", 60)`→`"Line1  Line2"`; 61×`"a"` → 59×`"a"` + `"…"` (60 chars).
Saved lists: `(nil, 60)`/`("   ", 60)` → `"(unnamed)"`; `("  Deck  ", 60)` → `"Deck"`.

### 7.8 `Sanitize`
Saved lists: `"Deck/Engine: daily?"`→`"Deck_Engine_ daily_"`; `""`→`"saved-lists"`; `"   "`→`"saved-lists"`;
`" A "`→`"A"`; `"a|b"`→`"a_b"`; `"  \t "`→`"_"`. Schedule: `""`→`"crew"` → file `"Schedule-crew.aasched.json"`.
Checklist export: name `"Pump: A/B"` → `"checklist-Pump_ A_B.pdf"`.

### 7.9 Timeline grouping (today = 2026-09-29, Tuesday, en-US)
Entries (Date, Time): ("2026-10-02","09:00"), ("2026-09-29",""), ("2026-09-29","08:30"), ("2026-09-30","07:00"),
("",""), ("garbage","10:00"), ("2026/10/03","") →
groups in order: `"Today"` [(""→"00:00"), 08:30], `"Tomorrow"` [07:00], `"Fri, 2026-10-02"` [09:00],
`"Sat, 2026-10-03"` [""], `"(no date)"` [(""), ("garbage")] — "(no date)" order by TimeSort: "" (00:00) then 10:00.
Header counts: Today (2), Tomorrow (1), …, (no date) (2).

### 7.10 Capture / apply
Step S {Id s1, Title "Check A", Done true, Deadline 2026-07-10, IsJob true, DurationMinutes 45, BucketIds [b1],
TaskIds [t1], EquipmentIds [e1], ScheduledStart set, Container {Id c1, RichTextXaml X, IsLocked false, Files [F{Id
f1, Path "files/a.pdf"}]}} → `CaptureFromSteps(" Deck ", [S])` → Template {Name "Deck", GroupId nil, Items [{Title
"Check A", DurationMinutes 45, IsJob true, Container {Id ≠ c1, RichTextXaml == X (identical string), Files [{Id ≠ f1,
Path "files/a.pdf"}]}}]}. `ApplyToSteps(t, target, replace:false)` → new step {Id ≠ s1, Done false, Deadline nil,
BucketIds [], TaskIds [], EquipmentIds [], ScheduledStart nil, DurationMinutes 45, IsJob true}, returns 1.
`ApplyToSubtasks` → TaskItem {Name "Check A", Status Todo, IsComplete false, Recurrence None}. `ItemToTask` → same,
`Status = Todo`. `Clone(t, "Deck (copy)")` → new Id, same GroupId, new CreatedUtc.
`CaptureFromSubtasks` on a subtask that has its own subtasks → captured item has no trace of the grandchildren.

### 7.11 Schedule service
Crew {Schedule [E1 {Id e1, Done true, RefId r1, Kind 2, Date "2026-10-02", Time "09:00", Notes "n"}],
ScheduleVesselId v1 (vessel "MV Atlas")} → `CaptureFromCrew(" Rot ")` → {Name "Rot", VesselId v1, VesselName "MV
Atlas", Entries [{Id ≠ e1, Done false, RefId r1, Kind 2, Notes "n"}]}. `ApplyToCrew(t, crewB(link v9),
replace:true)` → crewB.Schedule = 1 fresh entry, `ScheduleVesselId = v1`; template with `VesselId nil` → crewB link
stays v9. Import of §4.5 JSON → template Id and entry Ids regenerated, `CreatedUtc` kept; `"null"` file → error
`"This file is not a valid schedule."`; `{"name":"x"}` (wrong case) → empty unnamed template.

### 7.12 Insert-into-note lines
Items: ("Check A", 60), ("  ", 30, has notes), ("Check B", 0, 1 file) with duration on, numbered →
lines `["Check A  (60 min)", "Check B"]`, preview `"1. Check A  (60 min)\n2. Check B"`, footnote `"2 lines will be
inserted. Not carried over: 1 item has notes, 1 attached file."`.

### 7.13 XLSX helpers
`ColRef`: 0→A, 5→F, 25→Z, 26→AA, 27→AB, 51→AZ, 52→BA, 701→ZZ, 702→AAA. Sheet name (Windows behaviour):
`"R&D procedure with a very long name"` → `"R&amp;D procedure with a very l"`; `"Engine room daily checks 2026 &
more"` → `"Engine room daily checks 2026 &"` (**invalid XML** on Windows — Mac fix per §6.4).

### 7.14 JSON round-trip fixtures
* A Windows `data.json` containing templates in a non-alphabetical order, one with `GroupId` to a deleted group,
  `Ui.SortAZ.savedlists = true`, and a step with a `Deadline` carrying `+02:00` → load + save on Mac leaves array
  order, dangling id, SortAZ and the literal date unchanged; `GroupId: null` never written.
* A template item container with an `enc:` body round-trips byte-identical.

---

## 8. Quirks, defects & open questions

**Behaviours to preserve (they are the Windows contract):** trimming differences (items untrimmed, list/group names
trimmed); "item(s)" literals; "N items" always plural in the tab; Replace-existing without confirmation; builder
deletes permanent; saved lists never store deadlines/done; export order = arranged order even when A-Z is on;
bulleted/numbered asked every time with bullets preselected; empty groups hidden in the tab.

**Defects / risks found (recommendation in brackets):**
* **D1** Saved Lists tab groups by *name*: two groups with the same (or both empty) names merge into one header, a
  group literally named "Ungrouped" merges with real ungrouped lists; a list with a dangling `GroupId` shows under
  "Ungrouped" but sorts among named groups and is excluded from "Export group". [Mac: group by Id, treat dangling ids
  as ungrouped everywhere; data unchanged.]
* **D2** "Move to group…" with OK and nothing chosen ungroups the list. [Mac: preselect the current group; OK
  disabled with no choice.]
* **D3** Template editor: write-back on every close changes container/file Ids (spurious sync diffs); "Manage saved
  lists…" inside it can delete the template being edited (edits silently lost); Deadline/Done editable but discarded.
  [Mac: write back only when changed; if the template disappears, warn and offer "Save as new list"; in
  `.savedListItem` mode show Deadline/Done disabled with the caption "Set when the list is applied".]
* **D4** Saved-list PDF prints a legacy `enc:` note as stripped ciphertext text. [Mac: print `"(locked content)"`
  like the viewer.]
* **D5** XLSX sheet name truncated after escaping (can cut `&amp;` → invalid workbook); Excel-illegal characters
  not replaced. [Mac: fix as in §6.4.]
* **D6** `NormTime` crashes on non-ASCII digits (Windows). [Mac: `[0-9]`.]
* **D7** Schedule/Date strings written via current culture (non-Gregorian cultures would write e.g. Buddhist years).
  [Mac: POSIX Gregorian.]
* **D8** `SavedListPicker` (Board/Planner) creates tasks without an activity-log entry; schedule add/delete/apply
  not logged; group create/rename/delete and list rename not logged. [Keep parity unless the lead decides otherwise.]
* **D9** COMPAS crew re-import (`CrewPage.ImportCompas`) preserves `Id` and `Checklist` but **drops `Schedule` and
  `ScheduleVesselId`** of an existing member. [Crew spec: preserve both on the Mac; flag to the crew-spec owner.]
* **D10** Schedule timeline "✎" tooltip promises notes editing; only the title is editable; `Notes`/`EndDate`/
  `EndTime` have no UI; schedule templates cannot be renamed/deleted. [Keep fields round-tripping; optional additive
  UI.]
* **R1** A shared-save pull (`CheckSharedFileForUpdate`) can reload the whole model while a modal builder/editor is
  open (timers keep running in modal loops); the builder then edits orphaned objects and the edits are lost. [Mac:
  pause pulls while a builder/editor sheet is presented, or re-resolve by Id and close/refresh the sheet.]
* **R2** `ItemPickerWindow` filtering drops selections (e.g. while linking tasks to a step, searching after ticking
  some tasks unticks them). [Mac: keep selection across filters.]
* **R3** "Export ALL" unreachable with no selection. [Mac: always enabled.]

**Open questions for the lead**
1. "Banked tasks" in the task brief: interpreted as the brief's *task bank* — linking existing top-level Tasks to a
   procedure step (BUILD-034) plus creating a new auto-linked task (BUILD-035). No other "banked tasks" concept
   exists in the C# source. Confirm.
2. "Nested subtasks" in the task brief: the Windows builder/editor edit one level only; deeper levels are only
   carried. Should the Mac subtask editor gain its own nested "Subtasks" section (additive)?
3. Accept the Mac deviations flagged above (D1–D7 fixes, R1–R3, visible placeholders, Replace/Append button labels,
   optional friendlier enum labels, drag-and-drop reorder)? None removes a capability or changes stored data shape.
4. Should a crew schedule surface in the Calendar / due-dates window on the Mac? (Windows: no.)

---

## Addendum: Erratum: PromptWindow Mac contract must keep OK enabled for blank input

> **Status: normative erratum (2026-09-30).** This addendum **supersedes** the words *"disabled while blank"* in the
> §6.2 Presentation table, row `PromptWindow` (line 1140 of this file when the erratum was written). Everything else in
> that row still applies: a small sheet with a title, a prompt and a pre-filled, selected `TextField`; Cancel (Esc) and
> OK (↩); the raw text is returned; trimming happens at the call site. The row now reads:
>
> **`PromptWindow`** → **`TextPromptSheet`**: title, prompt, `TextField` (pre-filled, all text selected), Cancel
> (Esc) / OK (↩, **always enabled, including for empty or whitespace-only text**). Returns the raw, untrimmed text.
> Trimming and blank handling stay at the call site (BUILD-144).
>
> The Mac `TextPromptSheet` has **one** contract across the whole app. It is the contract written in **HIER-130**
> (`04-hierarchy-pages.md:627-629`, Mac row `04:1152`) and **SHELL-162** (`03-main-shell-theme.md:834-837`).
> BUILD-130 (this file) and VESSEL-046a (`10-vessel-ports-jobs-cards.md:338-341`) say the same thing. The Mac adds only
> two things: Esc cancels (BUILD-139) and the prompt label wraps (BUILD-141). This addendum overrides any text in any
> spec that implies a caller may disable OK for blank input.

Numbering continues this spec's prefix: features **BUILD-136…BUILD-150**, algorithms **BUILD-A22…BUILD-A28**, and
test vectors **TV-PR-xx** (§Add.7).

### Add.0 Sources read for this addendum

| Source | What was checked |
|---|---|
| `AA/Views/PromptWindow.xaml` (21 lines) | 440×170, `ResizeMode="NoResize"`, `WindowStartupLocation="CenterOwner"`, app icon. Grid rows: bold 14-pt `LblTitle` (margin `0,0,0,8`), `LblPrompt` (margin `0,0,0,4`, no wrapping), `TextBox Tb` (top-aligned), then a right-aligned button row (margin `0,10,0,0`): `Cancel` (80 wide, margin `0,0,8,0`, **no `IsCancel`**) and `OK` (80 wide, `AccentButton`, `IsDefault="True"`). **OK has no `IsEnabled` binding, validation rule or converter.** |
| `AA/Views/PromptWindow.xaml.cs` (20 lines) | `public string Value => Tb.Text;` returns the raw text. The constructor sets `Title`, `LblTitle.Text` (both = `title`), `LblPrompt.Text = prompt`, `Tb.Text = initial`, `Tb.Focus()`, `Tb.SelectAll()`. `Ok_Click` → `DialogResult = true; Close()`, with no check. `Cancel_Click` → `DialogResult = false; Close()`. |
| `grep -rn "new PromptWindow(" AA` → **33** hits; `grep -rn "PromptWindow(" AA` adds **2** in `MainWindow.xaml.cs`, which use the namespace-qualified `new Views.PromptWindow(` | Every one of the **35** call sites was read together with its handler (BUILD-144). The task's grep misses the two `MainWindow` callers, and those are exactly the two where blank matters most. |
| `AA/Services/DataStore.cs:85-90, 123-141, 185-198, 236-275` | `DefaultIdentity`, `LoadSettings`, `SetGeminiApiKey`, `SetAppIdentity`, `WriteSettings` (including the `?? existing` fallback), settings `Opts` (`WhenWritingNull`). |
| `AA/Services/AppRepository.cs:650-661` | `CreateGroup` (blank → `"New group"`, else trim) and `RenameGroup` (blank → return, else trim). |
| `AA/Services/ChecklistTemplateService.cs:16-35`, `AA/Services/ScheduleService.cs:26-32` | `CaptureFromSteps`, `CaptureFromSubtasks` and `CaptureFromCrew` all `Trim()` the name. |
| `AA/Views/QuickCardsPanel.xaml.cs:195-215` | The Quick Card editor saves on OK and reverts its snapshot on Cancel, so the Web-link prompt's change reaches disk only when the card editor is confirmed. |
| `AA/App.xaml.cs:20` | Unhandled UI exceptions → `ReportCrash` (relevant only to the Insert-table overflow quirk). |
| Specs | 06 §6.2 row (06:1140), BUILD-006/015/130, 06:1153 (Esc); 04 HIER-030/033/070/072/073/086/094/095/130 and §6.5 (04:1152); 03 SHELL-068 (03:523-527), SHELL-100 (03:641-644), SHELL-162 (03:834-837), prompts P1/P2 (03:1959-1960), Settings row (03:1433), machine name (03:1669); 12 SIRE-038 (12:286-291) and §6.9; 08 QUICK-055 (08:312-314), QUICK-077, QUICK-080, 08:1225; 10 VESSEL-046/046a (10:333-341), 10:1478 (`WebLinkPromptSheet`), 10:1534; 05 CONT-031/032/086/092, K-14 (05:1508), §7.3; 07 VIEW-053 (07:399), VIEW-147…149 (07:616-629), 07:1220; 09 CREW-082/083; 01 DATA-048; 02 whitespace note (02:1067-1068). |

### Add.1 Overview: what was wrong and why it matters

1. Windows **never** disables OK. `Value` is `Tb.Text`, unchanged. `ShowDialog()` returns `true` for OK whatever the
   text is, including `""`, and `false` for Cancel, the title-bar close box and Alt+F4. Each caller decides what an
   empty value means.
2. Thirty of the 35 callers treat blank like Cancel. **Five give blank a meaning** (BUILD-145):

| Key | Caller | Blank means | What an always-disabled OK would break |
|---|---|---|---|
| **B1** | File ▸ `Set app identity...` (SHELL-068, DATA-048) | **Reset** the identity to the machine name. | The prompt is pre-filled with the current identity. On Windows the only way back to the default is to empty the box and press OK. **Unreachable.** |
| **B2** | Tools ▸ `Set Gemini API key...` (SHELL-100, SIRE-038) | **Clear** (remove) the key. | The prompt is the only Windows UI for the key. **Unreachable** from the command. |
| **B3** | Buckets ▸ `Set category...` (VIEW-149) | **Clear** the bucket's category. The label itself says `blank clears it`. | Cancel keeps the old category, and there is no other way to clear it. **Unreachable.** |
| **B4** | Buckets ▸ `+ New bucket`, second prompt `Category (optional)` (VIEW-147) | **None**: the bucket is created uncategorised. The label says `leave blank for none`. | The outcome can still be reached with Cancel, but the sheet would refuse what its own label tells the user to do. |
| **B5** | Rich-text `▦` Insert table (CONT-032) | **Default** 3×3 table: the size regex fails to match, so the fallback applies. | Reachable only by typing junk. |

3. Mac-only extras do **not** replace the menu command's blank behaviour. Examples: the Settings pane's Clear button
   for the Gemini key (12 §6.9) and the identity field in the Settings scene (03:1433). The command, its prompt and
   its blank semantics are part of the parity contract ("every function, feature and intricacy must be retained").

### Add.2 Feature checklist

**BUILD-136 — One shared prompt component.** Every Windows `PromptWindow` use (35 call sites, BUILD-144) maps to a
single Mac view, `TextPromptSheet` (§Add.6). Other specs name per-feature prompts, and all of them are this view:
- 10's `WebLinkPromptSheet` (10:1478, 10:1534);
- the "sheet with `TextField` + Cancel/OK" in 08:1225;
- the rows in 04 §6.5;
- the "New Task" sheet in 07:1220;
- the rename, link and table prompts in 05.

Those names may survive as thin wrappers that only supply title, prompt and initial text; they may not change the
contract. `DatePromptWindow`, `ListStylePromptWindow`, `PasswordWindow`, `ItemLockWindow` and `ItemPickerWindow` are
different dialogs, and this addendum does not cover them.

**BUILD-137 — OK is always enabled.** OK is enabled for every value, including `""`, `"   "` and whitespace such as
`"\u{00A0}"`. Do not use `.disabled(…)`, a greyed state, a "required" badge or error, or a shake animation. OK with a
blank field returns `.ok("")` (or the whitespace exactly as typed), and the caller applies its own rule
(BUILD-144 / BUILD-145). This supersedes "disabled while blank" in 06:1140.

**BUILD-138 — The value is returned raw.** The sheet returns the field's text **exactly** as it is:
- no trimming;
- no Unicode normalisation (NFC/NFD);
- no smart-quote, smart-dash or text-replacement substitution;
- no autocorrection or capitalisation.

WPF `TextBox` does none of these, so the Mac field must have them all switched off (§Add.6).

The **only** filtering is of line breaks. The Windows field is a single-line `TextBox` (`AcceptsReturn=false`): Return
presses OK, and pasted multi-line text is cut at the first line break (WPF's `TextEditor._FilterText`, BUILD-A28). The
Mac field must likewise never hold or return a line break. Paste of `"Line 1\nLine 2"` → `"Line 1"`.

**BUILD-139 — Keyboard.**
- Return (also Enter) = OK, including when the field is blank. OK fires **exactly once** per sheet.
- Esc and ⌘. = Cancel. This is a Mac improvement: on Windows the Cancel button is not `IsCancel`, so Esc does nothing
  (already accepted in 06:1153 and 10:338-341).
- With Full Keyboard Access on, Tab cycles field → Cancel → OK.
- There are no other shortcuts.

**BUILD-140 — Focus and selection.** When the sheet appears, the field is first responder and **all** of the initial
text is selected (Windows `Tb.Focus(); Tb.SelectAll()`). Typing therefore replaces the pre-filled value, such as
`https://`, `3x3`, the current name or the current identity. With an empty initial value, only the caret shows.

**BUILD-141 — Layout and exact strings.**
- **Heading:** the caller's `title`, bold 14 pt. On Windows this is also the window title. Sheets have no title bar,
  so the heading is the only visible title; also use it as the sheet's accessibility label.
- **Prompt label:** the caller's `prompt`, **verbatim**. **Mac deviation (display only):** it wraps, where WPF clips
  long prompts at the window edge (SHELL-162; affects P2, the two bucket-category prompts, the new-bucket name prompt
  and the Gemini prompt).
- **Field:** one single-line field, full width.
- **Buttons:** right-aligned, **`Cancel`** then **`OK`**. OK is the default and prominent (accent) button. These exact
  labels are used for every caller: no "Save", "Create" or "Rename" variants, because there is one contract.
- **Size:** minimum width 440 pt; height fits the content; not user-resizable (Windows `NoResize`); padding 14 pt.

**BUILD-142 — Cancel paths.** All of these return `.cancelled`, never `.ok`:
- Cancel, Esc and ⌘.;
- the sheet being dismissed in any other way, for example when its parent window or sheet closes.

Callers never read the text after a cancel. The only Windows caller that runs code after a cancel is B4, and it
substitutes `""` (BUILD-145).

**BUILD-143 — Secure-entry variant (Gemini key only).** SIRE-038 and 12 §6.9 ask for a `SecureField` with a reveal
toggle for the Gemini key; Windows shows the key in clear text. `TextPromptSheet(isSecure: true)` provides this:
- An `eye` / `eye.slash` toggle swaps a `SecureField` and a `TextField` that are bound to the same string.
- The pre-filled current key is selected on appear wherever AppKit allows it.
- It is **display only**. OK stays enabled for blank text (blank clears the key, B2) and the value is returned raw.
- No other caller uses it.

**BUILD-144 — Caller registry.** §Add.2.1 lists all 35 callers. The Mac handler for each must reproduce the columns
"Non-blank stored as" and "Blank / whitespace-only" **exactly**. **Blank** means .NET
`string.IsNullOrWhiteSpace(value)` on the **raw** value (BUILD-A23), except where the table names a different test
(regex, `Uri.TryCreate`, or no test at all).

**BUILD-145 — The five blank-meaningful paths.**
- **B1 — App identity** (`MainWindow.xaml.cs:1507-1516` → `DataStore.SetAppIdentity`, `DataStore.cs:194-198`).
  - Prompt: title `App identity`; label P2
    `Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save:`;
    initial = the current `AppIdentity`.
  - OK with any value: `AppIdentity = IsNullOrWhiteSpace(v) ? DefaultIdentity() : v.Trim()` → `WriteSettings()` →
    window title `AA — {AppIdentity}` → status `App identity set: {AppIdentity}`. The status shows the **resolved**
    value, i.e. the machine name after a reset.
  - `DefaultIdentity()` is `Environment.MachineName`, or `"AA"` if that throws.
  - The settings file then holds the machine name **as a literal string**. If the machine is renamed later, the
    identity keeps the old name until the user resets it again. This is the Windows behaviour; keep it.
  - Cancel → nothing: no status, no title change, no settings write.
  - **Mac:** the same logic. The machine name is `Host.current().localizedName`, or `SCDynamicStoreCopyComputerName`
    (03:1669). Store the resolved string, not a "use default" flag. If the Settings scene has an identity field,
    committing it blank must also reset. A "Use Mac Name" button there is an optional extra.
- **B2 — Gemini API key** (`MainWindow.xaml.cs:1496-1504` → `DataStore.SetGeminiApiKey`, `DataStore.cs:187-191`).
  - Prompt: title `Gemini API key`; label P1
    `Paste your Google Gemini API key (stored locally in settings.json, never committed):`; initial = the current key
    or `""`.
  - OK: `GeminiApiKey = IsNullOrWhiteSpace(v) ? null : v.Trim()` → `WriteSettings()` → status
    `Gemini API key cleared.` when `IsNullOrWhiteSpace(v)` (tested on the **raw** value), else
    `Gemini API key saved.`.
  - Windows quirk Q-5 (12): `WriteSettings` writes `GeminiApiKey ?? existing?.GeminiApiKey`, so a cleared key comes
    back after the next load.
  - Cancel → nothing.
  - **Mac:**
    - Label per SIRE-038: `Paste your Google Gemini API key (stored securely in this Mac's Keychain, never synced):`.
    - `isSecure: true`.
    - Blank **deletes** the Keychain item (`SecItemDelete`, service `"{bundleID}.gemini"`, account `"GeminiApiKey"`).
      The key stays gone after relaunch, which fixes Q-5.
    - Same two status strings.
- **B3 — Set category** (`BucketsPage.xaml.cs:147-152`).
  - With no bucket selected, `Need()` shows the "Select a bucket first." info box titled `Buckets` (VIEW-148).
  - Prompt: title `Set category`; label `Category (e.g. Location, Rank) — blank clears it:`; initial = `b.Category`.
  - OK: `b.Category = v?.Trim() ?? ""` → `Save()` → `Refresh()`.
    - This runs on **every** OK, even if the value did not change. The redundant save is harmless because the data is
      identical; see Q-E2.
    - Blank or whitespace → `""`, i.e. uncategorised.
  - Cancel → nothing.
- **B4 — New bucket, category prompt** (`BucketsPage.xaml.cs:125-138`).
  - Prompt 1: title `New bucket`, label `Bucket name (e.g. a location or a rank):`, initial `""`. Blank or Cancel
    aborts the whole flow, and prompt 2 is not shown.
  - Prompt 2: title `Category (optional)`, label
    `What does it represent? (e.g. Location, Rank) — leave blank for none:`, initial `""`.
    `category = ShowDialog()==true ? (v?.Trim() ?? "") : ""`, so **OK+blank and Cancel give the same `""`**.
  - Then create `QuickBucket { Name = name.Trim(), Category = category }`, append it,
    `LogAdded("Bucket", name, category)`, `Save()`, `Refresh()`, and select and scroll to the new bucket.
  - **Mac:** Cancel on prompt 2 must **still create** the bucket; it must not abort the flow.
- **B5 — Insert table** (`ContainerEditor.xaml.cs:727-768`).
  - Prompt: title `Insert table`; label `Size as rows x columns (e.g. 3x4):`; initial `3x3`.
  - OK: match `^\s*(\d+)\s*[xX*]\s*(\d+)\s*$` against `v ?? ""`.
    - No match, including `""` and whitespace-only → rows 3, cols 3.
    - Match → rows clamped to 1…50, cols clamped to 1…20.
  - Then insert the table (CONT-032) and persist immediately. Cancel → nothing.
  - **Mac:** the same, plus the safe-parse rules of 05 §7.3. Oversized numbers clamp: `99999999999x2` → (50,2), where
    Windows throws. Non-ASCII digits: .NET `\d` matches them but `int.Parse` throws; on the Mac treat them as no match
    → (3,3).

**BUILD-146 — No validation inside the shared sheet.** `TextPromptSheet` has **no** validation or "can submit" hook.
A caller that wants inline validation must use its own dedicated sheet. It may do that **only** where every input the
sheet would reject is a silent no-op on Windows.
- This keeps 05 K-14 legal. K-14 is a Mac Insert-hyperlink sheet that disables *Insert* until the URL parses. On
  Windows, a blank or unparseable URL does nothing (`Uri.TryCreate` fails), so no capability is lost.
- If K-14 is not adopted, Insert hyperlink uses `TextPromptSheet` with the Windows behaviour (CONT-031).
- The five B-callers must **never** use a validating or disabling sheet.

**BUILD-147 — Where the sheet appears.**
- The sheet attaches to the window, or sheet, that the command came from. SwiftUI allows a sheet on top of a sheet,
  so builder sheets can present it (e.g. "+ Item" inside the Checklist builder sheet).
- The Ctrl+N quick-work window and the Quick Card editor present it on their own window.
- Two Windows prompts have **no owner**: ContainerEditor Insert hyperlink (:706) and Add link (:894). On the Mac they
  become sheets on the editor's window too. This is a Mac improvement; on Windows they are not centred on the editor.
- Menu commands (B1, B2) present the sheet on the key main window. If no main window exists, bring one forward first,
  or fall back to an app-modal `NSAlert` whose `accessoryView` is an `NSTextField`. The same contract applies: OK
  always enabled, raw value, Esc cancels.
- The parent is blocked while the sheet is up, like `ShowDialog`.

**BUILD-148 — Optional Mac helper line (additive; lead decision Q-E1).** The Windows labels for B1 and B2 do not say
what blank does. The Mac may add one muted line under the field, through a display-only `helpText` parameter,
without changing the Windows prompt text:
- B1: `Leave blank to use this Mac's name ({machineName}).`
- B2: `Leave blank and click OK to remove the key.`

B3 and B4 already say it in their labels. **Recommendation:** show both lines.

**BUILD-149 — Dark mode and accessibility.**
- The system sheet material and semantic colours work in both themes. OK uses the app accent (Windows `AccentButton`).
- VoiceOver: the sheet is labelled with the heading, and the field's accessibility label is the prompt.
- The field is **not** marked as required.

**BUILD-150 — Persistence and undo.**
- The sheet itself persists nothing. Each caller persists as its row in §Add.2.1 says:
  - `Save` = immediate synchronous save;
  - `MarkDirty` = 750 ms debounced save;
  - `Settings` = immediate settings-store write;
  - `Card-OK` = when the Quick Card editor is confirmed, reverted on its Cancel;
  - `RTF` = ContainerEditor `PersistRichText`, immediate.
- No prompt-driven change can be undone on Windows (BUILD-133). An `UndoManager` action on the Mac is an optional
  extra, not a requirement of this addendum.

#### Add.2.1 Caller registry: all 35 `PromptWindow` call sites

Legend:
- **raw**: stored exactly as typed, surrounding spaces kept ("create raw").
- **trim**: .NET `Trim()` (BUILD-A23), applied either by the caller or by the named service.
- **no-op**: nothing changes, nothing is saved and no message is shown, exactly like Cancel.

On Cancel, every caller does nothing, except #24 (see B4). Blank = `IsNullOrWhiteSpace(raw)` unless the row says
otherwise.

| # | Call site (`AA/…:line`, handler) | Opened from (precondition) | Title | Label | Initial | Non-blank stored as | Blank / whitespace-only | Persist | Spec IDs |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `MainWindow.xaml.cs:1498` `MenuSetGemini_Click` | Tools ▸ `Set Gemini API key...` | `Gemini API key` | P1 (B2) | current key or `""` (clear text on Windows) | **trim** (`SetGeminiApiKey`) → `GeminiApiKey` | **CLEAR** → `null`; status `Gemini API key cleared.` | Settings | SHELL-100, SIRE-038 |
| 2 | `MainWindow.xaml.cs:1509` `MenuSetIdentity_Click` | File ▸ `Set app identity...` | `App identity` | P2 (B1) | current identity | **trim** (`SetAppIdentity`) | **RESET** → machine name; title + status updated | Settings | SHELL-068, DATA-048 |
| 3 | `Views/QuickWorkWindow.xaml.cs:223` `NewTask_Click` | Ctrl+N window `+ Task` | `New Task` | `Name:` | `""` | **raw** `TaskItem.Name`; log `Added`/`Task` | no-op | Save | QUICK-055 |
| 4 | `Views/QuickWorkWindow.xaml.cs:234` `NewProc_Click` | Ctrl+N window `+ Procedure` | `New Procedure` | `Name:` | `""` | **raw** `Procedure.Name`; log `Added`/`Procedure` | no-op | Save | QUICK-055 |
| 5 | `Views/QuickWorkWindow.xaml.cs:705` `AskTemplateName` | Ctrl+N detail `💾 Save as list...`, for both task and procedure (collection must be non-empty) | `Save as reusable list` | `Name for this saved list:` | owner's `Name` | **trim** (in `AskTemplateName`, again in `CaptureFrom*`) | no-op (returns `null`) | Save | QUICK-080 |
| 6 | `Views/QuickWorkWindow.xaml.cs:778` `BuildChildren` `+ {noun}` | Ctrl+N detail `+ subtask` / `+ step` | `New subtask` / `New step` | `Name:` (also for steps) | `""` | **raw** `TaskItem.Name` / `ChecklistStep.Title`; log `Added`/`Subtask`\|`Step` | no-op | Save | QUICK-077 |
| 7 | `Views/ScheduleBuilderControl.xaml.cs:156` `Edit_Click` | Crew ▸ Schedule tab row `✎` | `Edit entry` | `Title:` | `entry.Title` | **trim** `ScheduleEntry.Title` | no-op (title kept) | Save | BUILD-118, CREW-082 |
| 8 | `Views/ScheduleBuilderControl.xaml.cs:185` `Save_Click` | Crew ▸ Schedule `💾 Save as...` (schedule must be non-empty) | `Save schedule` | `Name for this reusable schedule:` | crew `FullName` | **trim** (`CaptureFromCrew`) | no-op | Save | BUILD-121, CREW-083 |
| 9 | `Views/HierarchyPage.xaml.cs:186` `NewGroup_Click` | Hierarchy sidebar `+ Group` / `New group...` | `New group` | `Name:` | `""` | **trim** (`CreateGroup`) | no-op; `CreateGroup`'s own `"New group"` fallback is never reached from here | Save | HIER-030 |
| 10 | `Views/HierarchyPage.xaml.cs:324` `RenameGroup_Click` | `Rename group...` (a group picked first) | `Rename group` | `New name:` | group name | **trim** (`RenameGroup`) | no-op | Save | HIER-033 |
| 11 | `Views/HierarchyPage.xaml.cs:907` (Components `+ Add`) | Equipment Specifics ▸ Components `+ Add` | `New Component` | `Name:` | `""` | **raw** `Component.Name`; no log | no-op | Save | HIER-070 |
| 12 | `Views/HierarchyPage.xaml.cs:951` (`+ New procedure`) | Equipment Specifics ▸ Related Procedures | `New Procedure` | `Name:` | `""` | **raw**; linked to the equipment; log `linked to {eq}` | no-op | Save | HIER-072 |
| 13 | `Views/HierarchyPage.xaml.cs:987` (`+ New task`) | Equipment Specifics ▸ Related Tasks | `New Task` | `Name:` | `""` | **raw**; linked to the equipment | no-op | Save | HIER-073 |
| 14 | `Views/HierarchyPage.xaml.cs:1127` (subtasks `+ Add`) | Task Specifics ▸ subtasks | `New Subtask` | `Name:` | `""` | **raw** `TaskItem.Name`; log `Added`/`Subtask` | no-op | Save | HIER-086 |
| 15 | `Views/HierarchyPage.xaml.cs:1323` (`+ Step`) | Procedure Specifics ▸ Checklist Steps | `New Step` | `Title:` | `""` | **raw** `ChecklistStep.Title`; log `Added`/`Checklist step` | no-op | Save | HIER-094, BUILD-032 |
| 16 | `Views/HierarchyPage.xaml.cs:1356` (`+ New task`) | Procedure Specifics (a step must be selected, else `Select a checklist step first.` / `New task`) | `New Task` | `Name:` | `""` | **raw**; linked to the step | no-op | Save | HIER-095, BUILD-035 |
| 17 | `Views/ChecklistBuilderControl.xaml.cs:92` `AddAt` | Checklist builder `+ Item`, `Insert before`, `Insert after` (procedure, crew checklist and template-editor hosts) | `New item` | `Title:` | `""` | **raw** `ChecklistStep.Title` | no-op | MarkDirty | BUILD-006/007/008 |
| 18 | `Views/ChecklistBuilderControl.xaml.cs:203` `SaveTemplate_Click` | Checklist builder `💾 Save as list...` (list must be non-empty) | `Save as reusable list` | `Name for this saved list:` | `ownerName` (or `""`) | **trim** (`CaptureFromSteps`) | no-op | Save | BUILD-015 |
| 19 | `Views/ChecklistBuilderControl.xaml.cs:259` `ManageTemplates_Click` | `Manage saved lists...` → pick → **Yes = rename** | `Rename saved list` | `New name:` | `tpl.Name` | **trim** | no-op | Save | BUILD-017 |
| 20 | `Views/QuickCardEditorWindow.xaml.cs:120` `WebLink_Click` | Quick Card editor `🌐 Web link...` | `Web link` | `URL:` | `https://` | **trim** → `Target`; `IsLink=true, LinkInPlace=false, IsFolder=false`; not validated | no-op (card unchanged) | Card-OK | VESSEL-046 |
| 21 | `Views/SubtaskBuilderWindow.xaml.cs:39` `SaveTemplate_Click` | Subtask builder `💾 Save as list...` (non-empty) | `Save as reusable list` | `Name for this saved list:` | task `Name` | **trim** (`CaptureFromSubtasks`) | no-op | Save | BUILD-044 (≙ BUILD-015) |
| 22 | `Views/SubtaskBuilderWindow.xaml.cs:131` `AddAt` | Subtask builder `+ Subtask`, `Insert before`, `Insert after` | `New subtask` | `Name:` | `""` | **raw** `TaskItem.Name` | no-op | MarkDirty | BUILD-044 (≙ BUILD-006…008) |
| 23 | `Views/BucketsPage.xaml.cs:128` `New_Click` (prompt 1) | Buckets `+ New bucket` | `New bucket` | `Bucket name (e.g. a location or a rank):` | `""` | **trim** `QuickBucket.Name` | **abort** (prompt 2 not shown) | (see #24) | VIEW-147 |
| 24 | `Views/BucketsPage.xaml.cs:130` `New_Click` (prompt 2) | right after #23 | `Category (optional)` | `What does it represent? (e.g. Location, Rank) — leave blank for none:` | `""` | **trim** `QuickBucket.Category` (no blank test) | **NONE**: bucket still created with `Category = ""`, same as Cancel | Save | VIEW-147 (B4) |
| 25 | `Views/BucketsPage.xaml.cs:143` `Rename_Click` | Buckets `Rename` (selection required) | `Rename bucket` | `New name:` | `b.Name` | **trim** | no-op | Save | VIEW-148 |
| 26 | `Views/BucketsPage.xaml.cs:150` `SetCategory_Click` | Buckets `Set category...` (selection required) | `Set category` | `Category (e.g. Location, Rank) — blank clears it:` | `b.Category` | **trim** (no blank test) | **CLEAR** → `Category = ""` | Save (every OK) | VIEW-149 (B3) |
| 27 | `Views/SavedListsPage.xaml.cs:147` `NewGroup_Click` | Saved Lists `+ Group` | `New List Group` | `Group name:` | `""` | **trim** `ListGroup.Name` | no-op | Save | BUILD-077 |
| 28 | `Views/SavedListsPage.xaml.cs:174` `ManageGroups_Click` | `Manage groups...` → pick → **Yes = rename** | `Rename group` | `New name:` | `grp.Name` | **trim** | no-op | Save | BUILD-078 |
| 29 | `Views/SavedListsPage.xaml.cs:206` `NewList_Click` | Saved Lists `+ List` | `New saved list` | `Name:` | `""` | **trim** `ChecklistTemplate.Name`; log `Added`/`Saved list`/…/`empty` | no-op | Save | BUILD-080 |
| 30 | `Views/SavedListsPage.xaml.cs:219` `Rename_Click` | Saved Lists `Rename` (selection required) | `Rename saved list` | `New name:` | `t.Name` | **trim** | no-op | Save | BUILD-081 |
| 31 | `Views/ContainerEditor.xaml.cs:532` `RenameSelected` | File bank `Rename` | `Rename` | `New name:` | `fi.Name` | **raw** `FileItem.Name` (display name only; the file on disk is not renamed) | no-op | MarkDirty | CONT-092 |
| 32 | `Views/ContainerEditor.xaml.cs:706` `InsertLink_Click` (**no Owner**) | Rich-text `🔗` | `Insert hyperlink` | `URL:` | `https://` | raw text → `Uri.TryCreate(…, Absolute)`; the XAML stores the **normalised** `uri.ToString()` | no-op (TryCreate fails; also for bare `https://` and any non-URL) | RTF | CONT-031 (Mac: 05 K-14 / BUILD-146) |
| 33 | `Views/ContainerEditor.xaml.cs:729` `InsertTable_Click` | Rich-text `▦` | `Insert table` | `Size as rows x columns (e.g. 3x4):` | `3x3` | regex parse, clamp 1…50 × 1…20 | **DEFAULT** 3×3 table inserted | RTF | CONT-032 (B5) |
| 34 | `Views/ContainerEditor.xaml.cs:894` `AddLink_Click` (**no Owner**) | File bank `Add link` | `Add link` | `URL:` | `https://` | **raw** → `FileItem { Name = v, Path = v, Kind = Link, IsLink = true }`; not validated (bare `https://` accepted) | no-op | MarkDirty | CONT-086 |
| 35 | `Views/BoardPage.xaml.cs:189` `NewTask_Click` | Board `+ New task` | `New Task` | `Name:` | `""` | **raw** `TaskItem.Name`, `Status = Todo`; **no** log | no-op | Save | VIEW-053 |

**Counts** (used by the conformance test TV-PR-40):
- By blank result: no-op 29 + abort 1 (#23) = 30; **clear** 2 (#1, #26); **reset** 1 (#2); **none** 1 (#24);
  **default** 1 (#33). Total 35.
- By storage of a non-blank value: **raw** 14 (#3, 4, 6, 11, 12, 13, 14, 15, 16, 17, 22, 31, 34, 35); **trim** 19
  (#1, 2, 5, 7, 8, 9, 10, 18, 19, 20, 21, 23, 24, 25, 26, 27, 28, 29, 30); **parsed** 2 (#32 URI, #33 regex).
  Total 35.

### Add.3 Logic & algorithms

**BUILD-A22 — `PromptWindow` (`Views/PromptWindow.xaml.cs:5-20`).**
```
init(title, prompt, initial = ""):
    window.Title = title; LblTitle.Text = title; LblPrompt.Text = prompt
    Tb.Text = initial; Tb.Focus(); Tb.SelectAll()
Value            -> Tb.Text                 // raw; never null in practice (callers still write Value?.Trim() ?? "")
OK click / Enter -> DialogResult = true; Close()   // no check of any kind (IsDefault)
Cancel click     -> DialogResult = false; Close()
close box/Alt+F4 -> ShowDialog() == false
Esc              -> nothing (Cancel is not IsCancel)
```
Swift contract:
```swift
struct TextPromptRequest: Equatable, Sendable {
    var title: String            // heading (= Windows window title)
    var prompt: String           // label, verbatim
    var initial: String = ""     // pre-filled, fully selected
    var isSecure: Bool = false   // BUILD-143, Gemini only; display only
    var helpText: String? = nil  // BUILD-148, optional muted line; display only
}
enum TextPromptResult: Equatable, Sendable { case ok(String), cancelled }   // .ok carries the RAW text

@MainActor protocol TextPrompting {                    // injectable, so the 35 handlers are unit-testable
    func prompt(_ request: TextPromptRequest) async -> TextPromptResult
}
```
There is deliberately **no** `validate:`, `canSubmit:` or `trimsWhitespace:` parameter (BUILD-146).

**BUILD-A23 — Blank and trim with .NET parity.**
```swift
func isNetBlank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
func netTrim(_ s: String) -> String   { s.trimmingCharacters(in: .whitespacesAndNewlines) }
```
.NET `char.IsWhiteSpace` = Unicode Zs ∪ Zl ∪ Zp ∪ {U+0009…U+000D, U+0085}. Foundation's `.whitespacesAndNewlines` =
Zs ∪ {U+0009} ∪ {U+000A…U+000D, U+0085, U+2028 (Zl), U+2029 (Zp)}. The two sets are **identical** (02:1067-1068).
Neither counts U+200B ZERO WIDTH SPACE or U+FEFF as whitespace. Use these two helpers everywhere a C# caller uses
`IsNullOrWhiteSpace` / `Trim()`. Do not use `.whitespaces` (it misses newlines) or a hand-written `" "` check.

**BUILD-A24 — Caller outcome patterns** (pseudo-Swift; `p` is the injected `TextPrompting`).
```swift
// (a) blank = no-op, stored RAW (#3,4,6,11-17,22,31,34,35)
guard case .ok(let v) = await p.prompt(.init(title: "New Task", prompt: "Name:")), !isNetBlank(v) else { return }
let t = TaskItem(name: v)                                   // NOT trimmed

// (b) blank = no-op, stored TRIMMED (#5,7-10,18-21,23,25,27-30); trimming may live in the service (CaptureFrom*, createGroup)
guard case .ok(let v) = await p.prompt(req), !isNetBlank(v) else { return }
tpl.name = netTrim(v)

// (c) blank = CLEAR, no blank test (#26)
guard case .ok(let v) = await p.prompt(req) else { return }
bucket.category = netTrim(v); repo.save(); refresh()

// (d) blank = RESET / CLEAR inside a settings setter (#1, #2)
guard case .ok(let v) = await p.prompt(req) else { return }
settings.setAppIdentity(v)                                  // B1: isNetBlank → machine name, else netTrim
settings.setGeminiApiKey(v); status = isNetBlank(v) ? "Gemini API key cleared." : "Gemini API key saved."   // B2

// (e) blank = NONE, Cancel = NONE (#24)
let category: String
if case .ok(let v) = await p.prompt(req) { category = netTrim(v) } else { category = "" }   // flow continues either way

// (f) blank = DEFAULT (#33)
guard case .ok(let v) = await p.prompt(req) else { return }
let (rows, cols) = TableSize.parse(v)                       // (3,3) when no match; 05 §7.3 rules

// (g) blank = no-op via parse failure (#32)
guard case .ok(let v) = await p.prompt(req), let url = DotNetUri.absolute(v) else { return }
```

**BUILD-A25 — `SetAppIdentity(identity)` (`Services/DataStore.cs:194-198`) and identity loading.**
- Set: `AppIdentity = IsNullOrWhiteSpace(identity) ? DefaultIdentity() : identity.Trim(); WriteSettings()`.
- Load (`:133`): `AppIdentity = IsNullOrWhiteSpace(s?.AppIdentity) ? DefaultIdentity() : s.AppIdentity`. The loaded
  value is **not** trimmed; it was trimmed when set.
- No settings file, or an exception while loading (`:123`, `:141`) → `DefaultIdentity()`.
- `DefaultIdentity()` (`:87-90`) = `Environment.MachineName`, or `"AA"` if that throws.

**BUILD-A26 — `SetGeminiApiKey(key)` (`Services/DataStore.cs:187-191`) and `WriteSettings` (`:236-264`).**
- Set: `GeminiApiKey = IsNullOrWhiteSpace(key) ? null : key.Trim(); WriteSettings()`.
- `WriteSettings` rebuilds `Settings` with `GeminiApiKey = GeminiApiKey ?? existing?.GeminiApiKey`. That is the
  Windows Q-5 defect: clearing does not reach the file. `AppIdentity` has no fallback.
- The settings JSON uses `WhenWritingNull`, so a null key is omitted.
- Mac: a Keychain write, or a Keychain delete when blank. No fallback.

**BUILD-A27 — Status text for B1 and B2.** B2 picks its status from `IsNullOrWhiteSpace(rawValue)`. This is equivalent
to "the stored key is nil" because the setter uses the same test. B1's status interpolates the **stored**
`AppIdentity`: the trimmed value, or the machine name after a reset.

**BUILD-A28 — Single-line filtering.**
- WPF `TextBox` with `AcceptsReturn=false`:
  - Return never inserts a line break; it activates the default button.
  - Pasted text is cut at the first line-break character, following WPF's `TextEditor._FilterText`. The line-break set
    is `\n`, `\r`, and, per the WPF sources, also `\v`, `\f`, U+0085, U+2028 and U+2029. **Verify on Windows**
    (Q-E3); if WPF differs, copy Windows.
- Mac: apply the same cut in the field's change handler, or in `NSTextFieldDelegate`
  `control(_:textView:shouldChangeTextIn:replacementString:)`. The returned value can then never contain a line
  break.
- No other characters are filtered, and there is **no maximum length** (WPF `MaxLength = 0`).

### Add.4 Data formats

**settings.json** (per machine; never in `data.json`, never in bundles; `AppIdentity` and `GeminiApiKey` are
excluded from Flash Sync, PROGRESS "Never carries credentials"):

| Key | Type | Written by | Rule |
|---|---|---|---|
| `AppIdentity` | string | #2 | Trimmed text, or after a blank reset the machine name **as a literal**. It is never written empty from this path. On load, missing or blank → machine name. The resolved value is also stamped into bundle `source.json` `"Identity"` (03:1210) and Google Drive appProperties and file names. |
| `GeminiApiKey` | string / absent | #1 | Trimmed key. Blank → `null` → omitted (`WhenWritingNull`), but Windows then re-inserts the old value (Q-5). **Mac:** Keychain only (12 §6.9); import from a Windows settings file per 12 §4.3. |

**data.json** fields written by prompt callers. Key names are as System.Text.Json writes them (PascalCase, enums as
integers, 06 §4.1):

| JSON path | Callers | Value rule |
|---|---|---|
| `Tasks[].Name` | #3, #13, #16, #35 | raw |
| `Tasks[].Status` | #35 | `0` (`WorkStatus.Todo`) |
| `Procedures[].Name` | #4, #12 | raw |
| `Tasks[]…Subtasks[].Name` | #6 (subtask), #14, #22 | raw |
| `Procedures[].Steps[].Title`, `Crew[].Checklist[].Title` | #6 (step), #15, #17 | raw (#17 also edits the template editor's working copy, written back per BUILD-063) |
| `Equipment[].Components[].Name` | #11 | raw |
| `Equipment[].ProcedureIds[]` / `Equipment[].TaskIds[]` / `Procedures[].Steps[].TaskIds[]` | #12 / #13 / #16 | new item's `Id` appended (lowercase GUID) |
| `Groups[].Name` (`ItemGroup`) | #9, #10 | trim |
| `ListGroups[].Name` | #27, #28 | trim |
| `ChecklistTemplates[].Name` | #5, #18, #19, #21, #29, #30 | trim |
| `ScheduleTemplates[].Name` | #8 | trim |
| `Crew[].Schedule[].Title` | #7 | trim |
| `QuickBuckets[].Name` / `QuickBuckets[].Category` | #23, #25 / #24, #26 | trim. `Category` `""` = uncategorised; it is written as `""`, not omitted, because it is not null. |
| `Vessels[].QuickCards[].Target` (+ `IsLink`, `LinkInPlace`, `IsFolder`) | #20 | trim; `true` / `false` / `false` |
| `….Container.Files[].Name` / `.Path` | #31 (`Name` only), #34 (both) | raw. #34 also writes `Kind: 3` (`FileKind.Link`) and `IsLink: true` |
| `….Container.RichTextXaml` | #32, #33 | XAML `Hyperlink` / `Table`; the exact shapes are in 05 §4 (and the S-4 fixture) |
| `Log[]` | #3–#6, #8, #12–#18, #21, #22, #24, #29 | `Name` trimmed by `LogAction` (`"(unnamed)"` if blank; unreachable from prompts, which reject blank first) |

**Cross-version rules.**
1. A **raw** field may start or end with whitespace, whichever platform wrote it. The Mac must never trim it on
   decode, display, edit round-trip or encode. A Windows `"Name":"  Pump 2 "` must be re-saved by the Mac
   byte-identical, and a Mac raw caller must write `"  Pump 2 "` exactly as Windows would.
2. Both platforms apply the same blank rules, so neither can create a blank-named item **from a prompt**. Blank names
   can still arrive by other routes (bulk add, import, Flash Sync) and must be tolerated as before.
3. Settings are per machine and never cross platforms by themselves. This erratum has no bundle or wire-format
   impact.

### Add.5 Dependencies

- **Called by:** the 35 call sites in §Add.2.1. They live in `MainWindow`, `QuickWorkWindow`,
  `ScheduleBuilderControl`, `HierarchyPage`, `ChecklistBuilderControl`, `QuickCardEditorWindow`,
  `SubtaskBuilderWindow`, `BucketsPage`, `SavedListsPage`, `ContainerEditor` and `BoardPage`.
- **Calls:** nothing; the prompt is pure UI.
- **Downstream of callers:**
  - `DataStore.SetAppIdentity`, `SetGeminiApiKey`, `WriteSettings`;
  - `AppRepository.CreateGroup`, `RenameGroup`, `LogAdded`, `Save`, `MarkDirty`;
  - `ChecklistTemplateService.CaptureFromSteps`, `CaptureFromSubtasks`;
  - `ScheduleService.CaptureFromCrew`;
  - `System.Uri.TryCreate`;
  - `Regex.Match` / `int.Parse` / `Math.Clamp`.
- **Windows-only APIs:** WPF `Window.ShowDialog` / `DialogResult` / `IsDefault` / `WindowStartupLocation.CenterOwner`;
  `Environment.MachineName`; the settings file under `%LOCALAPPDATA%` (03). All have direct Mac equivalents (§Add.6).

### Add.6 macOS adaptation notes

**Component sketch** (SwiftUI; an AppKit field where SwiftUI cannot guarantee a behaviour):
```swift
struct TextPromptSheet: View {
    let request: TextPromptRequest
    let finish: (TextPromptResult) -> Void
    @State private var text: String
    @State private var reveal = false
    @State private var done = false                        // BUILD-139: fire exactly once
    init(request: TextPromptRequest, finish: @escaping (TextPromptResult) -> Void) {
        self.request = request; self.finish = finish; _text = State(initialValue: request.initial)
    }
    private func complete(_ r: TextPromptResult) { guard !done else { return }; done = true; finish(r) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.title).font(.system(size: 14, weight: .bold))
            Text(request.prompt).fixedSize(horizontal: false, vertical: true)       // wraps (BUILD-141)
            RawSingleLineField(text: $text, secure: request.isSecure && !reveal)     // NSViewRepresentable, see below
            if let help = request.helpText { Text(help).font(.callout).foregroundStyle(.secondary) }
            HStack {
                if request.isSecure { Toggle(isOn: $reveal) { Image(systemName: reveal ? "eye.slash" : "eye") }.toggleStyle(.button) }
                Spacer()
                Button("Cancel") { complete(.cancelled) }.keyboardShortcut(.cancelAction)
                Button("OK") { complete(.ok(text)) }.keyboardShortcut(.defaultAction)   // NO .disabled(…) — BUILD-137
            }
        }
        .padding(14).frame(minWidth: 440)
        .onDisappear { complete(.cancelled) }             // any other dismissal = Cancel (no-op if already done)
        .accessibilityLabel(request.title)
    }
}
```
`RawSingleLineField` wraps `NSTextField` or `NSSecureTextField`:
- **Select all on appear:** make it first responder, then call `currentEditor()?.selectAll(nil)` on the next run-loop
  turn (BUILD-140). SwiftUI `@FocusState` alone does not guarantee select-all.
- **Raw text:** on its field editor (`NSTextView`), switch off `isAutomaticQuoteSubstitutionEnabled`,
  `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled`, `isAutomaticSpellingCorrectionEnabled`
  and `isAutomaticCapitalizationEnabled` (BUILD-138).
- **Line breaks:** apply the BUILD-A28 line-break cut.
- **Return:** let Return reach the default button. Do not also call `complete` from `controlTextDidEndEditing`
  without the `done` guard.

**Async presenter.** A `@MainActor final class SheetTextPrompter: TextPrompting` stores the pending request plus a
`CheckedContinuation`. The window's root view presents it with `.sheet(item:)`. Unit tests inject
`ScriptedPrompter(results:)`, which returns pre-set results and **records every request**, so tests can assert the
exact title, label and initial text of each caller (TV-PR-40).

**Menu-driven prompts (B1, B2).** They are commands on the main scene's `Commands` (03 menu map). They present on the
key main window; with no main window, use the `NSAlert` + `accessoryView` fallback (BUILD-147). The Settings scene
(03:1433) may *also* edit the identity and the key, with the same blank semantics. It is an extra route, never a
substitute.

**How other specs read after this erratum** (no edits to them are required, only this reading):

| Spec location | Reading |
|---|---|
| 06:1140 (§6.2 row) | Superseded wording; see the status box at the top of this addendum. |
| 04:627-629 (HIER-130), 04:1152 (§6.5) | Already correct; this is the contract. |
| 03:834-837 (SHELL-162), 03:523-527 (SHELL-068), 03:641-644 (SHELL-100) | Already correct; B1 and B2 depend on it. |
| 12:286-291 (SIRE-038), 12 §6.9 | The `SecureField` + reveal = `TextPromptSheet(isSecure: true)`; blank on OK **must** still clear. |
| 10:338-341 (VESSEL-046a), 10:1478 `WebLinkPromptSheet`, 10:1534 | A wrapper over `TextPromptSheet`; blank → no-op in the caller (#20). |
| 08:1225, 08:312-314 (QUICK-055) | `TextPromptSheet`; blank → no-op; names stored raw. |
| 07:1220 (Board new-task sheet), 07:616-629 (VIEW-147…149) | `TextPromptSheet`; B3 and B4 as above. |
| 05 CONT-031/032/086/092, K-14 (05:1508) | #31, #33, #34 use `TextPromptSheet`. Insert hyperlink may use the dedicated K-14 sheet (BUILD-146). |

**Mac-native polish that keeps every capability:**
- the standard sheet slide-in and the system sheet material (Liquid Glass on macOS 26);
- Return and Esc as above;
- the prompt label wraps;
- the optional helper line (BUILD-148);
- the Gemini reveal toggle.

Nothing here is impossible on macOS.

### Add.7 Test vectors (turn into Swift tests)

**Sheet level** (UI tests on `TextPromptSheet`, or unit tests on its view model):

| ID | Setup / action | Expected |
|---|---|---|
| TV-PR-01 | initial `""`; press OK at once | OK is enabled; result `.ok("")` |
| TV-PR-02 | initial `"Deck"`; ⌘A, Delete; press Return | `.ok("")`; `finish` called exactly once |
| TV-PR-03 | type `"   "` | OK enabled; `.ok("   ")` (not trimmed) |
| TV-PR-04 | type `"  Pump 1  "` | `.ok("  Pump 1  ")` |
| TV-PR-05 | type `"\u{00A0}"` | OK enabled; `.ok("\u{00A0}")` |
| TV-PR-06 | Esc / ⌘. / Cancel / parent window closes | `.cancelled` (each case) |
| TV-PR-07 | paste `"Line 1\nLine 2"` into an empty field | field shows `"Line 1"`; OK → `.ok("Line 1")` |
| TV-PR-08 | initial `"https://"`; type `"x"` straight away | `.ok("x")` (initial text was fully selected) |
| TV-PR-09 | type `"it's -- \"ok\""` with the system smart quotes/dashes on | `.ok("it's -- \"ok\"")`: ASCII apostrophe, quotes and dashes kept |
| TV-PR-10 | `isSecure: true`, initial `"AIzaOld"`; clear it; OK | OK enabled; `.ok("")` |
| TV-PR-11 | a long prompt (P2) | the whole label is visible, wrapped; width ≥ 440 |

**Blank / trim helpers:**

| ID | Input | `isNetBlank` | `netTrim` |
|---|---|---|---|
| TV-PR-20 | `nil` | true | n/a |
| TV-PR-21 | `""` | true | `""` |
| TV-PR-22 | `" \t\r\n"` | true | `""` |
| TV-PR-23 | `"\u{00A0}\u{2003}\u{3000}"` | true | `""` |
| TV-PR-24 | `"\u{0085}\u{2028}\u{2029}\u{000B}\u{000C}"` | true | `""` |
| TV-PR-25 | `"\u{200B}"` | **false** | `"\u{200B}"` |
| TV-PR-26 | `"\u{FEFF}"` | **false** | `"\u{FEFF}"` |
| TV-PR-27 | `"\u{00A0}Deck 3\u{3000}"` | false | `"Deck 3"` |

**Caller outcomes** (inject `ScriptedPrompter`):

| ID | Caller | Prompt result | Expected |
|---|---|---|---|
| TV-PR-30 | #2 App identity (current `"Bridge"`) | `.ok("")` | `AppIdentity` = machine name (e.g. `"Eris's MacBook Pro"`); settings store holds that literal; window title `AA — Eris's MacBook Pro`; status `App identity set: Eris's MacBook Pro` |
| TV-PR-31 | #2 | `.ok("   ")` | same as TV-PR-30 |
| TV-PR-32 | #2 | `.ok("  MV Aurora  ")` | `AppIdentity = "MV Aurora"`; status `App identity set: MV Aurora` |
| TV-PR-33 | #2 | `.cancelled` | nothing changes; no settings write; status unchanged |
| TV-PR-34 | #1 Gemini (key `"AIzaOld"`) | `.ok("")` | Keychain item deleted; key `nil` **after relaunch too** (Q-5 fixed); status `Gemini API key cleared.` |
| TV-PR-35 | #1 | `.ok("  AIzaNew\t")` | key `"AIzaNew"`; status `Gemini API key saved.` |
| TV-PR-36 | #26 Set category (`"Location"`) | `.ok("")` / `.ok("  ")` / `.ok(" Rank ")` | `Category` `""` / `""` / `"Rank"`; saved each time |
| TV-PR-37 | #23 + #24 New bucket | `.ok("  Galley ")`, then `.ok("")` | bucket `Name "Galley"`, `Category ""`; log `Added`/`Bucket`/`Galley`/`""` (compare 07 K5) |
| TV-PR-38 | #23 + #24 | `.ok("Galley")`, then `.cancelled` | bucket **created**, `Category ""` |
| TV-PR-39 | #23 | `.ok("   ")` | no bucket; prompt 2 never requested |
| TV-PR-40 | **Registry conformance:** for every row #1–#35 feed `.ok("")`, `.ok("   ")`, `.ok("\u{00A0}")`, `.ok("  X  ")` and `.cancelled` | Each recorded request's title, label and initial text equals §Add.2.1 exactly. Outcomes match the "Blank" and "Non-blank stored as" columns: raw callers store `"  X  "`, trim callers store `"X"`, #33 builds 3×3 for the three blank inputs, #32 inserts nothing for all four `.ok` inputs (`"  X  "` is not an absolute URI). Tally: 30 no-op/abort, 2 clear, 1 reset, 1 none, 1 default. |
| TV-PR-41 | #33 Insert table | `.ok("")`, `.ok("   ")`, `.ok("3×4")` (U+00D7), `.ok("abc")` | 3×3 in each case |
| TV-PR-42 | #33 | `.ok(" 2 X 5 ")`, `.ok("2*5")`, `.ok("0x0")`, `.ok("100x100")`, `.ok("99999999999x2")` | (2,5), (2,5), (1,1), (50,20), (50,2); see 05 §7.3 |
| TV-PR-43 | #32 Insert hyperlink | `.ok("")`, `.ok("https://")`, `.ok("not a url")` | document unchanged; nothing persisted |
| TV-PR-44 | #32 | `.ok("https://example.com")` | hyperlink text `https://example.com/` (normalised, CONT-031) |
| TV-PR-45 | #3 / #35 New Task | `.ok("  Pump  ")` | `Name "  Pump  "` (raw); #3 logs name `"Pump"` (the log trims); #35 writes no log and `Status 0` |
| TV-PR-46 | #9 New group | `.ok("   ")` | no group created (the service's `"New group"` fallback is **not** used) |
| TV-PR-47 | #29 New saved list | `.ok("  Deck rounds ")` | `Name "Deck rounds"`; log detail `empty` |
| TV-PR-48 | #20 Web link | `.ok("  https://x.io  ")` / `.ok("")` | `Target "https://x.io"`, `IsLink true` / card unchanged |
| TV-PR-49 | #34 Add link | `.ok(" https://x.io ")` / `.ok("https://")` | `Name` = `Path` = `" https://x.io "` (raw), `Kind 3` / a link `"https://"` is added (unvalidated) |
| TV-PR-50 | #31 File rename | `.ok(" Manual.pdf")` / `.ok("")` | display name `" Manual.pdf"` (raw) / unchanged |
| TV-PR-51 | JSON round-trip | load a Windows `data.json` with `"Name":"  Pump 2 "` and `"Category":""`; save without edits | the two values are byte-identical in the output |

### Add.8 Quirks and open questions for this erratum

**Behaviours to preserve:**
- OK is always enabled.
- Raw return value.
- Per-caller trimming as tabled: 14 raw, 19 trim, 2 parsed.
- Blank = reset (B1), clear (B2, B3), none (B4), default (B5).
- #26 saves on every OK.
- #24's Cancel creates the bucket anyway.
- #34 accepts a bare `https://`.
- #35 writes no log.
- The identity is stored as the literal machine name after a reset.

**Windows quirks with an agreed Mac treatment:**
- Esc does nothing on Windows → the Mac cancels.
- Long prompts are clipped on Windows → the Mac wraps them.
- #32 and #34 have no owner window on Windows → the Mac attaches them as sheets on the editor.
- Gemini Q-5 (a cleared key comes back) → the Mac really deletes it.
- Insert-table overflow and non-ASCII digits throw on Windows → the Mac parses them safely.

**Open questions:**
- **Q-E1:** Adopt the optional helper lines of BUILD-148 for B1 and B2? Recommended: yes. They are display only and
  make the reachable-by-blank paths discoverable.
- **Q-E2:** #26 Set category saves even when the value did not change. Keep the redundant save for strict parity, or
  skip it when the value is unchanged? The data is identical either way; skipping avoids a no-op shared-save push.
  Default: keep parity.
- **Q-E3:** Confirm on a Windows machine which characters WPF's single-line `TextBox` treats as line breaks when
  pasting (BUILD-A28), and whether `Uri.TryCreate` accepts leading and trailing spaces for #32. .NET's `Uri` is
  believed to ignore surrounding whitespace, so on the Mac trim before parsing unless the check shows otherwise.
