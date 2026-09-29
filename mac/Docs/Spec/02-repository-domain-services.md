# 02 — Repository & Domain Services (`REPO-`)

> Porting spec for the Swift/macOS rewrite of **AA**. Contract for implementers and verifiers.
> Source of truth: the Windows WPF app (.NET 10, C#) at `AA/` in this repo, branch `mac-port`, commit `37cdab0`.
> This document describes behaviour **as it is**, including quirks. Where the C# has a latent defect, the
> defect is described exactly, then a recommendation is given (section 8). Nothing here is aspirational
> unless it is explicitly labelled **Mac addition** or **Recommended deviation**.

Files covered (all read completely):

| File | Lines | Role |
|---|---|---|
| `AA/Services/AppRepository.cs` | 675 | The model root: lookups, relations, activity log, debounced/explicit persistence orchestration, Trash + undo, recurrence regeneration, sidebar groups |
| `AA/Services/SearchService.cs` | 180 | Global full-text search (Ctrl+F) with snippets, lock-aware; XAML → plain text |
| `AA/Services/ScheduleService.cs` | 57 | Crew schedule templates: capture / apply / export / import (`.aasched.json`) |
| `AA/Services/ReminderService.cs` | 65 | Overdue / today / next-7-days counts for tray reminders + daily digest |
| `AA/Services/WorkRange.cs` | 37 | Keeps a task's `[RangeStart .. Deadline]` valid |
| `AA/Services/BatchDeadline.cs` | 56 | One deadline applied to a heterogeneous selection |
| `AA/Services/BatchDelete.cs` | 167 | Describe-then-trash a multi-selection as one undoable batch |
| `AA/Services/BatchDone.cs` | 49 | Done / not-done on a heterogeneous selection |
| `AA/Services/SavedListOrder.cs` | 111 | Arranged order of saved lists (templates) and export order |
| `AA/Services/ChecklistTemplateService.cs` | 158 | Saved lists: capture, apply, clone, item→task, edit round-trip, deep container copy |

Callers read to establish behaviour (not owned by this spec, but their use of these services is specified
here): `MainWindow.xaml(.cs)`, `Views/HierarchyPage.xaml(.cs)`, `Views/BatchDeleteMenu.cs`,
`Views/BatchDoneMenu.cs`, `Views/BatchDeadlineMenu.cs`, `Views/DatePromptWindow.xaml(.cs)`,
`Views/TrashWindow.xaml(.cs)`, `Views/ActivityLogWindow.xaml(.cs)`, `Views/SearchWindow.xaml(.cs)`,
`Views/QuickSwitcherWindow.xaml.cs`, `Views/FloatingTasksWindow.xaml.cs`, `Views/SavedListsPage.xaml(.cs)`,
`Views/ChecklistBuilderControl.xaml.cs`, `Views/SubtaskBuilderWindow.xaml.cs`,
`Views/TemplateEditorWindow.xaml.cs`, `Views/SavedListPicker.cs`, `Views/ScheduleBuilderControl.xaml.cs`,
`Views/QuickWorkWindow.xaml.cs`, `Views/BoardPage.xaml.cs`, `Views/CrewPage.xaml.cs`,
`Views/SubtaskEditorWindow.xaml.cs`, `Views/RelationshipMapPage.xaml.cs`, `Sire/SireToAa.cs`,
`Services/PdfExporter.cs`, `Services/ChecklistExporter.cs`, `Services/DataStore.cs`,
`Services/ItemLockService.cs`, `Models/Models.cs`, `Models/CrewMember.cs`, `App.xaml.cs`.

---

## 0. Conventions in this document

* `file:line` references are to the C# at the commit above.
* Quoted UI strings are **exact**, including Unicode punctuation: `…` (U+2026), `›` (U+203A), `·` (U+00B7),
  `—` (U+2014), `→` (U+2192), `▸` (U+25B8), `↩` (U+21A9), emoji. `\n` inside a message means a line break.
  `{x}` is an interpolation. `item{s}` means "item" when the count is 1 else "items" (the exact pluralisation
  rule is spelled out where it is irregular).
* "Top-level item" = an `Equipment`, `TaskItem`, `Procedure` or `Vessel` that lives directly in
  `AppData.Equipment` / `.Tasks` / `.Procedures` / `.Vessels`. Subtasks, checklist steps and components are
  **not** top-level items.
* "Save" = `AppRepository.Save()` (synchronous, confirmed write). "MarkDirty" = debounced autosave.
* Dates: the C# `DateTime` has a *Kind* (Unspecified / Local / Utc). Section 4.2 defines exactly how each
  field is written. "Day" comparisons in this subsystem always use the **wall-clock date** (`.Date`) and
  compare ticks without regard to Kind.
* MUST / SHOULD / MAY have their RFC meanings for the Swift port.

---

## 1. Overview

The repository-and-domain-services layer is **not one screen**; it is the model root and the business rules
that every tab calls into. `AppRepository` owns the single `AppData` graph that is serialised to `data.json`,
and the ten files in this spec implement every cross-cutting domain operation:

* **Lookup & traversal** — enumerate all top-level items, all rich-text/file containers, all schedulable jobs;
  find by id; human labels.
* **Relationships** — two-way `RelatedIds`; one-way Equipment→Procedure/Task links; one-way procedure-step
  →Task/Equipment links; backlinks ("Referenced by"); reference scrubbing on permanent deletion.
* **Persistence orchestration** — a 750 ms debounced background autosave with an ordered write chain, a
  synchronous confirmed `Save()`, `LastModified` stamping, safe-mode suspension, detach on reload.
* **Trash & undo** — soft-delete of top-level items and crew members (with the full serialized subtree),
  batch ids so one undo restores a whole batch, restore, permanent delete, empty, 90-day / 200-item pruning.
* **Activity log** — UTC-stamped "Added / Removed" records, bounded to 10 000.
* **Recurrence** — completing a recurring top-level Task/Procedure regenerates its next occurrence once.
* **Status/complete sync** — the single definition of "done" across tasks, subtasks, steps and procedures.
* **Deadlines & working ranges** — range coercion and batch dating.
* **Search** — global Ctrl+F full-text search with snippets and lock gating; plus the Ctrl+O quick switcher's
  scoring over names/tags.
* **Reminders** — overdue / due-today / due-this-week counts for the tray balloon and the once-a-day digest.
* **Saved lists (checklist templates)** — full-copy capture/apply, duplicate, item→task, edit round-trip,
  arranged order and export order.
* **Crew schedule templates** — capture/apply, portable `.aasched.json` export/import.
* **Sidebar groups** — create/rename/delete/assign.

Where it surfaces in the UI (Windows):

| Surface | Entry point |
|---|---|
| Trash | **File ▸ Trash (restore deleted items)...** (modal `TrashWindow`) |
| Undo last delete | **Ctrl+Z** anywhere in the main window when focus is *not* in a text box |
| Batch delete | Hierarchy sidebar right-click **🗑 Delete selected...** and the sidebar **Delete** button |
| Batch done / deadline | Right-click menus on subtasks, checklist steps, Board, Calendar, Ctrl+N lists |
| Activity log | **Tools ▸ Activity log...** |
| Global search | **Search (Ctrl+F)** header button, Ctrl+F |
| Quick switcher | **Ctrl+O**, **Tools ▸ Quick switcher (Ctrl+O)**, header **Go to (Ctrl+O)** |
| Relationships / backlinks | Every item's **Relationships** tab; Equipment/Procedure **Specifics** tab links |
| Reminders | Tray icon balloon every 30 min (deduped) + once-a-day digest at launch |
| Saved lists | **Saved Lists** tab (arrangement/export), and **💾 Save as list / 📋 Load a saved list / Manage** in every checklist builder |
| Crew schedule templates | Crew editor ▸ **Schedule** tab (Save / Apply / Export / Import) |
| Sidebar groups | Hierarchy sidebar **+ Group / Assign group... / Rename group... / Delete group** and right-click |

Mac placement (summary; details in §6): the repository becomes a `@MainActor @Observable final class
AppRepository`; the Trash becomes a Finder-like sheet/window reachable from **File ▸ Trash…** and the
sidebar; undo maps to **⌘Z** via the responder chain; search becomes a ⌘F search window (and optionally
`.searchable` on the main window); reminders become `UserNotifications` + an optional `MenuBarExtra`.

---

## 2. Feature checklist

IDs are stable. Each entry: **title** — precise behaviour. "Persist" states exactly what is written and when.

### 2.A Repository core & persistence orchestration

**REPO-001 — Single model root.** `AppRepository` wraps exactly one `AppData` (`Data`, read-only reference).
A reload / import / Flash-Sync apply builds a **new** `AppRepository` over a new `AppData`; model objects are
never reused across a reload (so windows must hold ids, not references — see REPO-006).

**REPO-002 — Debounced autosave (750 ms).** `MarkDirty()` (AppRepository.cs:301): if `SuspendSaving` → no-op.
Otherwise sets `_dirty = true`, stops and restarts a 750 ms timer (`DispatcherTimer`, UI thread). On tick the
timer stops and `BackgroundSaveIfDirty()` runs (AppRepository.cs:42):
1. If `SuspendSaving` or not dirty → return.
2. Remember `prevStamp = Data.LastModified`; set `Data.LastModified = DateTime.Now` (local kind).
3. Clear `_dirty`.
4. Serialize on the UI thread via `DataStore.SerializeForSave(Data)` (a consistent snapshot; this also
   normalises attachment paths and bumps `SchemaVersion` to ≥ 1). If serialization throws: restore
   `LastModified = prevStamp`, set `_dirty = true`, return (no retry is scheduled; the next `MarkDirty` or the
   5-minute autosave timer retries).
5. `await QueueWrite(json)` — the write runs on a background thread, chained after every earlier queued
   write (REPO-003a). On success raise `Saved`. On failure restore `LastModified = prevStamp` and set
   `_dirty = true` (again, no automatic retry until the next trigger).
Every keystroke-level edit in the app calls `MarkDirty()`, so typing stays O(1) per key.

**REPO-003 — Explicit confirmed save.** `Save()` (AppRepository.cs:261) is the "must be on disk now" path used
on close, before critical operations and after most discrete user actions (add/delete/link):
1. If `SuspendSaving` → **return silently** (no exception).
2. Stop the debounce timer.
3. Stamp `LastModified = DateTime.Now` (remember previous).
4. Serialize (on failure: restore stamp, **leave `_dirty` as it was**, rethrow).
5. Queue the write after all pending writes and **block up to 15 000 ms** for it.
   * Timeout → restore stamp, throw `TimeoutException("Timed out writing {DataStore.CurrentDataFile}.")`.
   * Write fault → restore stamp, rethrow the inner exception.
6. Only after a confirmed write: `_dirty = false`, raise `Saved`.
Note `Save()` always writes even when not dirty.

**REPO-003a — Ordered write chain.** `QueueWrite(json)` (AppRepository.cs:62): every write (debounced or
explicit) is appended to a single chain; each write awaits the previous one (ignoring its failure) and then
calls `DataStore.WriteData(json)` (atomic temp-file-then-rename, optional DPAPI encryption — see persistence
spec). Guarantees: writes commit strictly in enqueue order, so a newer snapshot can never be overwritten by an
older one; the chain never runs on the UI thread, so the UI may block on it without deadlock.

**REPO-004 — `LastModified` stamping.** Stamped with local `DateTime.Now` on every save attempt and **rolled
back** on any failed save, so the on-disk file and the in-memory stamp never disagree (the stamp drives
"newer/older" comparisons for shared save, Drive sync and imports).

**REPO-005 — Safe mode (`SuspendSaving`).** When the data file existed but could not be read at load
(`DataStore.LastLoadFailed`), `MainWindow` sets `SuspendSaving = true` (MainWindow.xaml.cs:1181). Then
`MarkDirty` and `Save` are no-ops, so the empty placeholder model can never overwrite the real file. Safe mode
also disables: startup Trash pruning, recurrence reconciliation, the daily digest, Ctrl+Z undo, and explicit
Save (the Save command shows **"Safe mode — not saving"**: "AA is in read-only safe mode because the data file
couldn't be read at startup, so saving is disabled to protect the file on disk. Close and reopen AA once the
file is available.").

**REPO-006 — Detach before discard.** `Detach()` (AppRepository.cs:293): sets `SuspendSaving = true`, stops the
debounce timer, clears all `Saved` subscribers. Called on the outgoing repository before every reload/import
(MainWindow.xaml.cs:556, :1177) so a stale timer can't tick after the swap and write discarded data over the
freshly loaded file, and so the old graph can be garbage-collected. Writes already queued still complete.

**REPO-007 — `Saved` event.** Raised on the UI thread after every successful save (both paths). Subscribers:
`MainWindow.OnRepoSaved` → recurrence reconcile (REPO-063); `FloatingTasksWindow.OnDataSaved` → refresh the
due-dates window if visible. Subscribers are dropped by `Detach()`.

**REPO-008 — `IsDirty` / `FlushIfDirty()`.** `IsDirty` exposes the pending-change flag. `FlushIfDirty()` calls
`Save()` only if dirty (and so throws on failure like `Save`). The common "persist this toggle now" idiom in the
app is `MarkDirty(); FlushIfDirty();`.

**REPO-009 — App-level save cadence (context).** `MainWindow` adds: a 5-minute autosave timer
(`DoAutosave`, MainWindow.xaml.cs:252) that flushes rich-text editors and calls `Save()` only if dirty (status
"Autosave — no changes (HH:mm:ss)" / "Autosaved HH:mm:ss" / "Autosave failed: {message}"), explicit Ctrl+S
(`DoSave`: "Saved HH:mm:ss"), and a final save on window close (errors ignored). These are specified in the
persistence/shell spec; they are listed here because they are the only retry paths after a failed debounced
write.

### 2.B Lookups

**REPO-010 — `AllItems()`** (AppRepository.cs:74): lazily yields every top-level item in this fixed order:
all `Equipment`, then all `Tasks`, then all `Procedures`, then all `Vessels`, each in collection order.
Nested subtasks/steps/components are **not** included.

**REPO-011 — `FindById(id)`** (:82): first item in `AllItems()` order whose `Id == id`, else nil. Linear scan.
(If a malformed file had the same id in two collections, Equipment wins, then Task, Procedure, Vessel.)

**REPO-012 — `AllContainers()`** (:86): every rich-text/file-bank `Container` in the model, skipping nil, in
this order: for each Equipment → its container, then each component's container; for each top-level Task →
its container then, depth-first pre-order, every nested subtask's container; for each Procedure → its
container, then each step's container; each Vessel's container; for each crew member → each checklist
step's container; for each saved list (checklist template) → each item's container. Used by
`PurgeReferences` to scrub file links everywhere.

**REPO-013 — `AllJobs()`** (:121): every object tagged `IsJob == true` (schedulable job), in order: for each
top-level Task, pre-order over the task and all nested subtasks; then for each Procedure → the procedure
itself if `IsJob`, then each of its steps with `IsJob`; then for each crew member → each checklist step with
`IsJob`. Feeds the Planner and the floating due window's "scheduled today" rows.

**REPO-014 — `Label(id)`** (:143): `"(missing)"` when `FindById` is nil, else `"[{Kind}] {Name}"` where
`{Kind}` is the **enum name** (`Equipment`, `Task`, `Procedure`, `Vessel`) — not the friendly label. Used for
the Equipment Specifics link lists, so a trashed-but-not-purged link shows as "(missing)".

**REPO-015 — `KindLabel(kind)`** (:250, static): `Equipment → "Equipment/Area"`, `Task → "Task"`,
`Procedure → "Procedure"`, `Vessel → "Vessel"`, otherwise the enum name. Used for the activity log, Trash
`KindLabel`, quick switcher, PDF.

### 2.C Relationships and auto-linking

The product brief's rules and how the code realises them:

| Brief rule | Implementation |
|---|---|
| "Each equipment can be related to any number of tasks or any procedures, which therefore automatically relates the equipment to any sub-hierarchy of that procedure or task." | One-way `Equipment.ProcedureIds` / `Equipment.TaskIds`. The linked item's own sub-hierarchy (a procedure's steps and their step links, a task's subtasks) is carried *implicitly* by the link: `RelatedItems(equipment)` includes the linked procedures/tasks, the equipment's PDF export prints each linked procedure's full checklist and each linked task's summary, and the Relationship Map draws them. **No `RelatedIds` entries are materialised and nothing is expanded recursively.** |
| "DO NOT automatically relate a task to any sub-hierarchy of a procedure or equipment." | Linking a task from equipment (`TaskIds`) or from a checklist step (`step.TaskIds`) **never** writes into the task's `RelatedIds`. `RelatedItems(task)` is the task's own `RelatedIds` only. The task can see who points at it only through **backlinks** (`ReferencedBy`). |
| "All tasks created for each equipment and/or procedure are automatically added to the task bank." | "+ New task" on Equipment/Step creates a **top-level** task in `Data.Tasks` and links it (REPO-026/027). |
| "All procedures created for each equipment are automatically added to the procedure bank." | "+ New procedure" on Equipment creates a top-level procedure in `Data.Procedures` and links it (REPO-025). |
| "Each checklist in each procedure may use banked tasks, or the user may create one." | Step **Link tasks...** picks from `Data.Tasks`; step **+ New task** creates one (REPO-027). |
| "The user should be able to build relationships … shown thru a 2D map." | Two-way `RelatedIds` via **Add relationship...** (REPO-020/028); map via `RelatedItems` (REPO-031). |

**REPO-020 — Two-way relation.** `AddRelation(a, b)` (:212): no-op if `a.Id == b.Id`; appends `b.Id` to
`a.RelatedIds` if absent and `a.Id` to `b.RelatedIds` if absent (no duplicates, append order preserved).
`RemoveRelation(a, b)` (:219): removes the **first occurrence** of each id from the other's `RelatedIds`
(no-op if absent). Neither saves; callers `Save()`.

**REPO-021 — `RelatedItems(item)`** (:150): collect ids into an insertion-ordered de-duplicating set:
`item.RelatedIds` (in order), then — only for `Equipment` — `ProcedureIds` then `TaskIds`. Resolve each with
`FindById`, skipping missing ones. Output order = that set's order. For Tasks, Procedures and Vessels the
result is `RelatedIds` only — in particular a Procedure's **step** links are *not* part of its
`RelatedItems`. Callers apply `.Distinct()` defensively.

**REPO-022 — Backlinks `ReferencedBy(target)`** (:169): every top-level item (in `AllItems()` order, excluding
the target itself) that references `target.Id` via any of: its `RelatedIds`; if Equipment, its
`ProcedureIds` or `TaskIds`; if Procedure, any step's `TaskIds` or `EquipmentIds`. Nested subtasks' own
`RelatedIds`, crew checklist step links and crew schedule `RefId`s are **not** consulted.
UI: the Relationships tab shows **"Related items (double-click to open). Removing breaks the link both
ways."**, the `RelList`, then the bold accent header **"↩ Referenced by (backlinks) — items that point to this
one:"** and the `BackRefList` (height 160). Rows display `"[{Kind}] {Name}"` (enum name). Double-click a row in
either list → navigate to that item (switches main tab and selects it).

**REPO-023 — Equipment → Procedures link (Specifics tab).** Section header **"Related Procedures
(auto-relates sub-hierarchy)"** with buttons **Pick...** and **+ New procedure**. The list shows
`Label(id)` for each id in `eq.ProcedureIds` (so a trashed procedure reads "(missing)"). **Pick...** opens a
multi-select picker titled **"Pick procedures"** over `Data.Procedures` (collection order, display = name),
pre-selecting the current links; on OK the link list is **replaced** by the selection (`ProcedureIds.Clear()`
then add each picked id), then `Save()`, refresh the list and the Relationships tab.

**REPO-024 — Equipment → Tasks link.** Header **"Related Tasks"**, buttons **Pick...** and **+ New task**,
picker title **"Pick tasks"** over `Data.Tasks` (top-level only), same replace semantics as REPO-023. The task
is not related back (brief rule).

**REPO-025 — Inline "+ New procedure" from Equipment.** Tooltip "Create a new Procedure and auto-link it to
this Equipment/Area.". Prompt title **"New Procedure"**, label **"Name:"**; blank/whitespace or cancel →
nothing. Else: create `Procedure { Name = value }` (value not trimmed), append to `Data.Procedures`, append its
id to `eq.ProcedureIds`, log `Added / "Procedure" / {name} / "linked to {eq.Name}"`, `Save()`, refresh the
procedure list and Relationships tab.

**REPO-026 — Inline "+ New task" from Equipment.** Tooltip "Create a new Task and auto-link it to this
Equipment/Area.". Prompt **"New Task"** / **"Name:"**. Creates `TaskItem { Name }` at the end of `Data.Tasks`,
appends id to `eq.TaskIds`, log `Added / "Task" / {name} / "linked to {eq.Name}"`, `Save()`, refresh.

**REPO-027 — Procedure step links.** On the Procedure Specifics checklist toolbar: **Link tasks...** (picker
**"Pick tasks for this step"** over `Data.Tasks`, pre-selecting `step.TaskIds`, replace semantics, `Save()`),
**+ New task** (tooltip "Create a new Task and auto-link it to the selected checklist step."; with no step
selected shows **"Select a checklist step first."** titled **"New task"**; else prompt "New Task"/"Name:",
append to `Data.Tasks`, append id to `step.TaskIds`, log `Added / "Task" / {name} / "linked to step
'{step.Title}'"`, `Save()`), **Link equipment/area...** (picker **"Pick equipment/area for this step"** over
`Data.Equipment`, replace semantics into `step.EquipmentIds`, `Save()`). Link tasks / equipment do nothing
without a selected step (no message).

**REPO-028 — "Add relationship..." / "Remove".** **Add relationship...** (accent button) opens a multi-select
picker titled **"Pick related items"** listing every top-level item except the current one, ordered by kind
(Equipment 0, Task 1, Procedure 2, Vessel 3) then by name (ordinal, case-insensitive), displayed
`"[{Kind}] {Name}"`, with **no pre-selection** (it only adds). Each pick → `AddRelation(current, pick)`;
then `Save()`, refresh. **Remove** acts on the selected row of `RelList`: `RemoveRelation(current, row)`,
`Save()`, refresh. Quirk (preserve): for Equipment the list also shows one-way `ProcedureIds`/`TaskIds`
entries; "Remove" on such a row calls `RemoveRelation`, which does not touch those one-way lists, so the row
stays (those links are removed via the Specifics pickers).

**REPO-029 — Reference scrubbing on permanent removal.** `PurgeReferences(deletedId)` (:186) removes the first
occurrence of `deletedId` from, for every top-level item: `RelatedIds`; if Equipment `ProcedureIds` and
`TaskIds`; if Procedure each step's `TaskIds` and `EquipmentIds`; and, for every container from
`AllContainers()`, each file's `LinkedItemIds`. It does **not** scrub: nested subtasks' `RelatedIds`, crew
checklist steps' `TaskIds`/`EquipmentIds`, crew `ScheduleEntry.RefId`, `Ui.QuickViewPinIds` (the Ctrl+N window
prunes stale pins lazily), `Ui.Selected*Id`, `Ui.MapFocusedItemId`. It does not save. Called only when an item
leaves the model for good: Trash eviction by pruning, "Delete permanently", "Empty Trash", and the hard-delete
paths of the Board and the Ctrl+N window (REPO-081). **Soft delete does not scrub** (REPO-070).

**REPO-030 — SIRE quick-add cross-linking (caller).** `SireToAa.SpawnTopLevelTasks` creates top-level Tasks
tagged "SIRE" and calls `AddRelation(parent, task)` (two-way); if the parent is Equipment it also appends
the task id to `eq.TaskIds` (if absent). The parent is logged `Added / KindLabel(parent) / {name} /
"from SIRE Q{n}"` or `"from SIRE ({count} questions)"`. (SIRE spec owns the rest.)

**REPO-031 — Relationship Map (caller).** Nodes = centre + `RelatedItems(centre).Distinct()` on a circle;
edges centre→each; dashed edges between two related nodes only if `related[i].RelatedIds` contains
`related[j].Id` (one direction checked, `RelatedIds` only). (Map spec owns rendering.)

### 2.D Add / remove operations (entry points and their side effects)

**REPO-035 — Catalogue of item-creating operations.** All create at the **end** of the target collection.

| Entry point | Creates | Log (Action / Kind / Name / Detail) | Persist |
|---|---|---|---|
| Hierarchy **+ New** | `"New Equipment/Area"` / `"New Task"` / `"New Procedure"` / `"New Vessel"` | Added / KindLabel / name / "" | `Save()` then select it |
| Equipment **+ New procedure / + New task** | named top-level item + link | see REPO-025/026 | `Save()` |
| Step **+ New task** | top-level task + step link | REPO-027 | `Save()` |
| Task Specifics subtasks **+ Add** (prompt "New Subtask"/"Name:") | `TaskItem` appended to `t.Subtasks` | Added / "Subtask" / name / parent name | `Save()` |
| Procedure **+ Step** (prompt "New Step"/"Title:") | `ChecklistStep` appended to `p.Steps` | Added / "Checklist step" / title / procedure name | `Save()` |
| Equipment components **+ Add** (prompt "New Component"/"Name:") | `Component` appended | *(none)* | `Save()` |
| Ctrl+N **New task / New procedure** | top-level item | Added / "Task" or "Procedure" / name / "" | `Save()` |
| Board / Planner **+ From saved list** | one Task per picked saved-list item (REPO-144) | *(none)* | `Save()` if ≥1 |
| SIRE quick-add | REPO-030 | REPO-030 | caller |
| Recurrence regeneration | REPO-061/062 | "Task (recurring)" / "Procedure (recurring)" | `MarkDirty()` |
| Trash restore / undo | REPO-076/077 | Added / KindLabel / name / "restored from Trash" | `Save()` by caller |

**REPO-036 — Catalogue of removal paths.** See REPO-070..081. Summary: top-level items and crew members in the
Hierarchy/Crew UI → **soft delete to Trash**; subtasks, steps and components → **hard removal** from their
owning collection (no Trash, no reference scrub; subtasks/steps are logged, components are not); Board card
delete and Ctrl+N delete → **hard delete** with `PurgeReferences`; crew **Clear all** → hard delete, logged
`Removed / "Crew" / "all {n} member(s)"`.

### 2.E Status / completion sync

**REPO-040 — Task `IsComplete` ⇄ `Status` sync** (Models.cs:226-250). `WorkStatus` = `Todo(0)`,
`InProgress(1)`, `Blocked(2)`, `Done(3)`.
* Setting `IsComplete = true` when it changes → if `Status != Done`, `Status = Done`.
* Setting `IsComplete = false` when it changes → if `Status == Done`, `Status = Todo`; an `InProgress` or
  `Blocked` status is preserved.
* Setting `Status` when it changes → `IsComplete = (Status == Done)` if that differs.
* Setters only act on an actual change, so there is no recursion.
* **Load rule (must be replicated by the Swift decoder):** `System.Text.Json` applies keys in **document
  order** through these setters, so for conflicting values the *later* key wins. Windows always writes
  `IsComplete` before `Status` (declaration order), so for every Windows-written file the net effect is: if
  `Status` is present it wins (`IsComplete := Status == Done`); if `Status` is absent (legacy file)
  `Status := IsComplete ? Done : Todo`; if `IsComplete` is absent, `IsComplete := Status == Done`. The Swift
  decoder MUST implement exactly that normalisation, **independent of key order** (Swift's `Codable` does not
  expose order). Only a foreign writer that emits `Status` *before* a *contradicting* `IsComplete` would be
  read differently by Windows (there `IsComplete` wins) — an accepted, documented divergence (§8 D-21).

**REPO-041 — Independent completion fields.** `Procedure.Status` (same enum) has **no** `IsComplete`; "done"
means `Status == Done`. `ChecklistStep.Done` is a plain bool (procedure steps and crew checklist items).
Completing a procedure does not complete its steps and vice versa. Parent/child tasks are independent (a
completed parent can have incomplete subtasks).

**REPO-042 — `BatchDone.SetDone(item, done)`** (BatchDone.cs:16) — the one shared definition of "mark
done / not done". Returns true only if state actually changed:
* `TaskItem`: if `IsComplete == done` → false (a no-op leaves `InProgress`/`Blocked` untouched); else set
  `IsComplete = done` (which syncs `Status` per REPO-040) → true.
* `ChecklistStep`: if `Done == done` → false; else set → true.
* `Procedure`: done=true: if `Status == Done` → false, else `Status = Done` → true. done=false: if
  `Status != Done` → false (preserves InProgress/Blocked/Todo); else `Status = Todo` → true.
* Anything else (including nil, Equipment, Vessel, strings) → false.
`SetDoneAll(items, done)` (:43) applies to each and returns the number actually changed.

**REPO-043 — Batch done context-menu entries** (`BatchDoneMenu.Add`). Appends (after a `Separator` when the
menu already has items and `separatorFirst`) **"✓ Mark selected as done"** and **"○ Mark selected as not
done"**. On click: evaluate the selection *at click time*, `SetDoneAll`; if n > 0 → `MarkDirty();
FlushIfDirty();` (immediate save); then always call the list's refresh callback. Attached to: task subtasks
list, procedure checklist steps list, Board cards, Calendar schedule rows (rows map to the underlying model),
Ctrl+N pending list and builder children list. **Right-click selection rule** (`RightClickSelect`): on
right-button-down over a row, if the row is already selected keep the whole multi-selection; otherwise clear
the selection and select just that row. (WPF does not select on right-click by itself.)

**REPO-044 — Completion from the floating due-dates window.** Each row's checkbox calls
`BatchDone.SetDone(item, done)`; on change `MarkDirty(); FlushIfDirty();` and the item drops off (a
completed item is neither overdue nor due). (Floating-window spec owns layout.)

### 2.F Deadlines and working ranges

**REPO-050 — `WorkRange.Coerce(start, deadline, editedStart)`** (WorkRange.cs:15). Normalises to dates
(`.Date`, time dropped, Kind preserved) and enforces `start <= deadline`, where the deadline is always the
**last** day of the range:
* start nil → return `(nil, deadline?.Date)` unchanged otherwise.
* start set, deadline nil → deadline := start (a one-day range).
* start > deadline → if `editedStart` (user moved the start) deadline := start; else (user moved the
  deadline) start := deadline.
* otherwise unchanged.
Never shows a dialog.

**REPO-051 — Range editors (callers).** Three editors keep a start picker and a deadline picker consistent by
calling `Coerce` after either changes and writing both values back to the model (`RangeStart`, `Deadline`),
then `MarkDirty()`: Task Specifics (HierarchyPage.xaml.cs:1018-1031), the Subtask editor window
(SubtaskEditorWindow.xaml.cs:75), the Ctrl+N detail pane (QuickWorkWindow.xaml.cs:606-637).
**Critical rule:** the long-lived panes (Task Specifics and Ctrl+N) MUST coerce against the **model's** partner
value (`t.RangeStart` / `t.Deadline`), never the sibling picker, because a batch deadline or a Board/Calendar
edit can leave the sibling picker stale; coercing against a stale picker silently wrote old dates back (a
confirmed high-severity data-loss bug that was fixed). The Ctrl+N pane also re-seeds its pickers after a
batch deadline (`SyncDetailDates`). Consequence of `Coerce` (preserve): clearing the deadline picker while a
start exists immediately re-fills the deadline with the start date; to remove the deadline the user first
clicks **Clear range** (subtask editor: sets `RangeStart = nil`, `MarkDirty`). Subtask editor extras: range
hint `"range · {days} days"` (days = deadline − start + 1, shown only when `HasRange`), the deadline picker
greys out days before the start and the start picker greys out days after the deadline.

**REPO-052 — `BatchDeadline.SetDeadline(item, date)`** (BatchDeadline.cs:16). `d = date?.Date`. Returns true
only on a real change:
* `TaskItem`: if d is nil → if both `Deadline` and `RangeStart` are already nil → false; else set **both** to
  nil (a range cannot exist without its end) → true. Else `(ns, nd) = Coerce(t.RangeStart, d, editedStart:
  false)`; if `Deadline == nd && RangeStart == ns` → false; else assign both → true. (So a start later than the
  new deadline is clamped onto it; an earlier start is kept.)
* `Procedure` / `ChecklistStep`: if `Deadline == d` → false; else assign → true.
* anything else → false.
Equality compares date-time ticks (Kind ignored). `SetDeadlineAll` returns the changed count.

**REPO-053 — "📅 Set deadline for selected…" menu** (`BatchDeadlineMenu`). Tooltip "Give every selected item
the same deadline (or clear it).". On click: empty selection → **"Select one or more items first, then set the
deadline."** (title **"Set deadline"**, info). Else open `DatePromptWindow` titled **"Set deadline"** with
prompt **"Apply one deadline to {n} selected item{s}:"**, pre-filled with the deadline shared by all selected
items if they all have the same value (all-nil pre-fills empty; non-dated objects count as nil). Dialog:
date picker; buttons **Clear deadline** (tooltip "Remove the deadline from every selected item."; returns
nil), **Cancel**, **OK** (default; with no date picked shows **"Pick a date, or use \"Clear deadline\" to
remove it."** titled "Set deadline" and stays open). OK/Clear → `SetDeadlineAll`; if n > 0 →
`MarkDirty(); FlushIfDirty();`; always refresh. Attached to subtasks, steps, Board, Calendar, both Ctrl+N
lists (the Ctrl+N toolbar variant is identical).

**REPO-054 — Range-derived task properties (model, used everywhere).** `HasRange` = `RangeStart` and
`Deadline` both set and `RangeStart.Date < Deadline.Date`. `RangeFirst` = `RangeStart ?? Deadline`.
`WhenText` = `""` when no deadline; `"{start:yyyy-MM-dd} → {deadline:yyyy-MM-dd}"` when `HasRange`; else
`"{deadline:yyyy-MM-dd}"`. `CoversDay(day)`: false without a deadline; else the range is
`[start .. end]` with `end = Deadline.Date` and `start = RangeStart.Date` if `RangeStart.Date <= end` else
`end` (an out-of-order range collapses to the deadline day); true iff `day.Date` is inside. Changing either
date raises change notifications for `HasRange`, `RangeFirst`, `WhenText`. `RangeStart` exists on `TaskItem`
only (top-level and nested); procedures and steps are point items.

### 2.G Recurrence

**REPO-060 — `NextOccurrence(from, r)`** (AppRepository.cs:535): `Daily` +1 day, `Weekly` +7 days,
`Monthly` +1 calendar month (end-of-month clamps: Jan 31 → Feb 28/29), `Yearly` +1 year (Feb 29 → Feb 28),
`None` → unchanged. Time-of-day is preserved. `RecurrenceKind` = `None(0)`, `Daily(1)`, `Weekly(2)`,
`Monthly(3)`, `Yearly(4)`.

**REPO-061 — Regenerate a completed recurring Task** (`ReconcileRecurrences`, :552-578). For each top-level
task in a snapshot of `Data.Tasks` where `Recurrence != None && IsComplete && !RecurrenceSpawned`:
1. Mark the **source** `RecurrenceSpawned = true` (never spawns twice for this completion, even if it is
   later un-completed and re-completed).
2. `clone = DeepClone(t)` (JSON round-trip with the Trash options — every persisted field is copied).
3. Renew the clone recursively (`RenewTaskForNextOccurrence`): new `Id`; new `Container.Id` (if a container
   exists); `RecurrenceSpawned = false`; `ScheduledStart = nil`; `IsComplete = false` (→ `Status` goes
   `Done → Todo` via REPO-040; a subtask that was `InProgress`/`Blocked` and not complete **keeps** that
   status); same for every nested subtask.
4. `next = NextOccurrence(t.Deadline ?? DateTime.Today, t.Recurrence)` (`DateTime.Today` is local midnight).
5. Working range: if the source had `RangeStart rs` and `Deadline dl` with `rs.Date < dl.Date` → clone
   `RangeStart = next − (dl.Date − rs.Date).Days days` (length preserved in whole days); otherwise clone
   `RangeStart = nil`.
6. clone `Deadline = next`.
7. If the source had a deadline: `delta = next.Date − oldDeadline.Date` (whole days); shift every nested
   subtask's `Deadline` and `RangeStart` (each only if set) by `delta`, recursively.
8. Collect the clone; log `Added / "Task (recurring)" / {clone.Name} / "next {Recurrence} occurrence →
   {next:yyyy-MM-dd}"` (e.g. `next Monthly occurrence → 2026-02-28`).
After the loop, append all clones to the end of `Data.Tasks` in source order.

What the clone **keeps** (preserve exactly): Name, Description, Tags, GroupId, BucketIds, `RelatedIds`
(one-directional — the related items do not get the clone's id back), password lock
(`LockHash`/`LockSalt`/`LockHint`), `IsJob`, `DurationMinutes`, `Recurrence`, container XAML, `IsLocked`,
`SharedWithContainerIds`, file entries (same `FileItem.Id`s and paths — only `Container.Id` is renewed),
subtasks' names/descriptions/containers/durations/job flags/recurrence/tags/buckets. What it does **not** get:
membership in any `Equipment.TaskIds`, step `TaskIds`, `Ui.QuickViewPinIds` (the completed source keeps
those).

**REPO-062 — Regenerate a completed recurring Procedure** (:580-601). For each procedure in a snapshot where
`Recurrence != None && Status == Done && !RecurrenceSpawned`: mark source spawned; deep-clone; renew
(`RenewProcedureForNextOccurrence`): new `Id`, new `Container.Id`, `RecurrenceSpawned = false`,
`ScheduledStart = nil`, `Status = Todo`, and for every step: new `Id`, new step `Container.Id`,
`Done = false`, `ScheduledStart = nil` (step `TaskIds`, `EquipmentIds`, `BucketIds`, `IsJob`, duration,
title kept). `next = NextOccurrence(p.Deadline ?? Today, p.Recurrence)`; clone `Deadline = next`; if the
source had a deadline shift every step `Deadline` (if set) by `next.Date − old.Date`. Log `Added /
"Procedure (recurring)" / {name} / "next {Recurrence} occurrence → {clone.Deadline:yyyy-MM-dd}"`. Append
clones after the loop. Equipment `ProcedureIds` are not updated.

**REPO-063 — When reconciliation runs.** Returns true if anything was generated; on true it calls
`MarkDirty()`. Triggers: (a) once at startup, after load and Trash pruning, at background dispatcher
priority, skipped in safe mode (MainWindow.xaml.cs:131-139); (b) after **every** successful save via the
`Saved` event (`OnRepoSaved`, :1573), with a re-entrancy guard (`_reconciling`) and a safe-mode guard. When
something was generated the Tasks and Procedures pages reload their lists (deferred). Sequence for the user:
tick a monthly task complete → `MarkDirty` → 750 ms later autosave → `Saved` → reconcile spawns next
month's copy → `MarkDirty` → saved again 750 ms later (reconcile then returns false). Only **top-level**
tasks/procedures recur; a subtask's `Recurrence` is stored and shown but never regenerates anything.

**REPO-064 — Upgrade migration (persistence-owned, recurrence-relevant).** On load of any file with
`SchemaVersion < 1` (`DataStore.MigrateSchema`, DataStore.cs:325): every task **and nested subtask** with
`Recurrence != None && IsComplete`, and every procedure with `Recurrence != None && Status == Done`, gets
`RecurrenceSpawned = true`, so upgrading never retro-spawns a backlog. Saves then stamp `SchemaVersion = 1`
(never lowered).

### 2.H Trash, soft delete and undo

**REPO-070 — Soft-delete a top-level item** (`TrashHierarchyItem`, :341). Only Equipment/Task/Procedure/Vessel
(`ItemType` "Equipment"/"Task"/"Procedure"/"Vessel"); anything else → nil. Builds a `TrashedItem { Id = new,
ItemType, ItemId = item.Id, BatchId = empty, Name = item.Name, KindLabel = KindLabel(kind), DeletedUtc =
UtcNow, PayloadJson = JSON of the item's runtime type (full subtree: subtasks, steps, components, containers,
files, links, lock) }`, removes the item from its live collection, appends the entry to `Data.Trash`, prunes
(REPO-079), logs `Removed / KindLabel / {name} / "moved to Trash"`, `MarkDirty()`, returns the entry.
**References are NOT scrubbed** — both sides of two-way links, one-way Equipment links and step links stay,
so a restore brings the graph back intact; meanwhile those links show "(missing)" (REPO-014) and resolve to
nothing in `RelatedItems`. Attachment files stay on disk.

**REPO-071 — Soft-delete a crew member** (`TrashCrew`, :371): `ItemType "Crew"`, `Name = FullName` (first,
middle, last joined by single spaces, blank parts skipped), or `LastName` when `FullName` is blank, `KindLabel "Crew
member"`, payload = the `CrewMember` JSON (incl. checklist and schedule); removes from `Data.Crew`; prunes;
logs `Removed / "Crew member" / {name} / "moved to Trash"`; `MarkDirty()`. UI (Crew tab **Delete**): confirm
**"Move {FullName} to the Trash?\n\nYou can restore them from File ▸ Trash, or undo with Ctrl+Z."** titled
**"Confirm"** (Yes/No, question); on Yes trash, `Save()`, refresh roster and tab badge.

**REPO-072 — Batch soft delete** (`TrashHierarchyItems`, :505). Snapshot the input, new `batchId`; trash each
(skipping non-trashable) and stamp every resulting entry with the same `BatchId`. Returns the count. The
caller must have confirmed. Each entry is still individually restorable from the Trash window.

**REPO-073 — Describe a deletion before it happens** (`BatchDelete.Describe`, BatchDelete.cs:51). For each
distinct top-level item of the selection (REPO-074): if gated by an item lock (`ItemLockService.IsGated`) →
`Locked++` and skip; else count by kind (Equipment/Tasks/Procedures/Vessels) and `Descendants` (+component
count for Equipment; + all nested subtasks for a Task, cycle-guarded; + step count for a Procedure; +0 for a
Vessel); `WithAttachments++` if the item or any descendant container has files (Equipment: own + components;
Task: own + all nested subtasks; Procedure: own + steps; Vessel: own); `LinkedFromElsewhere++` if
`ReferencedBy(item)` is non-empty. `Total = Equipment + Tasks + Procedures + Vessels`; `IsEmpty = Total == 0
&& Locked == 0`. `KindBreakdown()`: comma-joined, only non-zero kinds, in this order: `"{n} task{s}"`,
`"{n} procedure{s}"`, `"{n} equipment/area"` / `"{n} equipment/areas"`, `"{n} vessel{s}"`; `"nothing"` if
none.

**REPO-074 — Selection normalisation** (`TopLevel`, :111). Accept model objects or row wrappers (a wrapper
exposes the model through a property named `Item`); keep only `HierarchyItem`s; de-duplicate by `Id`
(first occurrence wins); then drop any `TaskItem` that is a (cycle-guarded) descendant of another selected
task, because deleting the parent already takes it. Output order = first-seen order.

**REPO-075 — Confirm-then-trash flow** (`BatchDeleteMenu.Run`, used by the sidebar **Delete** button and the
sidebar right-click **🗑 Delete selected...**, tooltip "Move every selected item to the Trash. Restore from File
▸ Trash, or undo with Ctrl+Z."):
1. `Describe`. If `IsEmpty` → **"Select one or more items first."** titled **"Delete selected"** (info), stop.
2. If `Total == 0` (everything locked) → **"That item is locked. Unlock it before deleting it."** (1 locked) or
   **"All {n} selected items are locked. Unlock them before deleting."**, titled **"Nothing deleted"**, stop.
3. Confirmation titled **"Confirm delete"**, Yes/No, warning icon, **default button No**. Body lines joined by
   `\n`:
   * `"Move 1 item to the Trash?"` or `"Move {Total} items to the Trash?"`
   * `""`
   * `"    " + KindBreakdown()` (4 leading spaces)
   * if Descendants > 0: `"    {n} subtask/step/component{s} inside them will be deleted too."`
   * if WithAttachments > 0: `"    {n} of them ha{s|ve} attached files (the files stay on disk)."` —
     `has` when n == 1 else `have`: `"    1 of them has attached files (the files stay on disk)."` /
     `"    3 of them have attached files (the files stay on disk)."`
   * if LinkedFromElsewhere > 0: `"    {n} is linked from other items; those links show \"(missing)\" until
     the Trash is emptied."` (`is` when n == 1, else `are`)
   * if Locked > 0: `"    1 locked item is selected and will be skipped."` / `"    {n} locked items are
     selected and will be skipped."`
   * if `Trash.Count + Total > 200`: `"    Note: the Trash holds 200 items, so the {excess} oldest will be
     permanently removed."`
   * `""`
   * `"You can restore them from File ▸ Trash, or undo with Ctrl+Z."`
4. On Yes: `BatchDelete.TrashAll` (non-locked top-level picks as one batch); if n > 0 `Save()`; refresh;
   return n.
5. The Hierarchy page then closes any detached item windows for the deleted ids, clears the detail pane,
   refreshes and sets the status line to **"'{first pick name}' moved to Trash — Ctrl+Z to undo."** (n == 1)
   or **"{n} items moved to Trash — Ctrl+Z to undo them all."**. The toolbar **Delete** with an empty list
   selection falls back to the item shown in the detail pane.

**REPO-076 — Restore one entry** (`RestoreTrash`, :422). Deserialize `PayloadJson` to the type named by
`ItemType` (with the Trash options). Any exception or nil → return nil (entry stays in the Trash). Unknown
`ItemType` → nil. If no live item in the target collection already has that `Id`, **append** the restored
object to the end of the collection (not its original position); if one does exist, it is **not** added but
the entry is still consumed. Then remove the entry from `Data.Trash`, log `Added / {entry.KindLabel} /
{entry.Name} / "restored from Trash"`, `MarkDirty()`, return the `ItemType`. The restored item has the same
`Id` but is a **new object** (anything holding the old reference is dead — see the multi-window spec).

**REPO-077 — Undo last delete (Ctrl+Z)** (`UndoLastDelete`, :471; UI MainWindow.xaml.cs:1447-1473).
* Trigger: Ctrl+Z in the main window when keyboard focus is **not** in a text-editing control (TextBox /
  RichTextBox / PasswordBox); there, Ctrl+Z remains the editor's own text undo. Ignored in safe mode.
* `newest` = the Trash entry with the greatest `DeletedUtc` (ties → earliest in collection order). None →
  status **"Nothing to undo."**.
* If `newest.BatchId` is empty → restore just it. Else restore **every** entry with that `BatchId`, ordered
  by `DeletedUtc` descending (so they are re-appended newest-first), continuing past individual failures.
* Returns the distinct list of restored `ItemType`s (a batch can span pages). `PendingUndoCount()` (:493) =
  0 if empty, 1 for a single, else the number of entries sharing the batch id — computed **before** undo.
* After undo the app refreshes each affected page (Equipment/Task/Procedure/Vessel list reload; "Crew" →
  roster refresh + tab badge), calls `Save()`, and sets the status to **"Restored {expected} deleted items
  (Ctrl+Z)."** when `expected > 1`, else **"Restored the last deleted item (Ctrl+Z)."**.
* Undo works across app restarts (it is driven by the persisted Trash, not an in-memory stack).

**REPO-078 — Trash window** (File ▸ Trash (restore deleted items)..., tooltip "Restore items you deleted, or
remove them for good. Deletes go here instead of vanishing — Ctrl+Z undoes the last one."). Modal, title
**"Trash"**, 680×480, centred on owner, themed. Top text: **"Deleted items are kept here so a mistake can be
undone. Restore puts an item (with its whole subtree) back where it was. Items are auto-removed after 90 days,
or once there are more than 200."**. A virtualised multi-select list bound live to `Data.Trash` (collection
order = deletion order, oldest first) with columns **Name** (300), **Kind** (160, `KindLabel`), **Deleted**
(150, `DeletedUtc` in local time `yyyy-MM-dd HH:mm`). Buttons (bottom-right):
* **↩ Restore** (accent; tooltip "Put the selected item(s) back where they were.") — restore each selected
  entry; if none succeeded → **"Couldn't restore the selected item(s)."** titled **"Restore"** (warning);
  else `Save()` and raise `Restored(type)` for each distinct type so the host refreshes those pages.
* **Delete permanently** (tooltip "Remove the selected item(s) from the Trash for good (cannot be undone).")
  — confirm **"Permanently delete {n} item(s) from the Trash? This cannot be undone."** titled **"Delete
  permanently"** (Yes/No, warning) → `PurgeTrash` each, `Save()`.
* **Empty Trash** (tooltip "Permanently remove everything in the Trash.") — no-op if empty; confirm
  **"Permanently remove all {n} item(s) in the Trash? This cannot be undone."** titled **"Empty Trash"** →
  `EmptyTrash()`, `Save()`.
* **Close**.
No selection → Restore/Delete do nothing.

**REPO-079 — Pruning** (`PruneTrash`, :398). (1) Walking from the end, evict every entry with
`DeletedUtc < UtcNow − 90 days`. (2) While `Count > 200`, evict the entry with the smallest `DeletedUtc`
(ties → earliest in collection order). Eviction = `PurgeReferences(entry.ItemId)` then remove the entry.
`MarkDirty()` only if something was evicted. Runs after every add to the Trash and once at startup
(background priority, not in safe mode) so retention holds even if the user never deletes again. Constants:
`MaxTrashItems = 200` (public), retention 90 days.

**REPO-080 — Permanent removal.** `PurgeTrash(entry)`: if the entry was in the Trash, remove it,
`PurgeReferences(entry.ItemId)`, `MarkDirty()`. `EmptyTrash()`: no-op when empty; else `PurgeReferences` for
every entry's `ItemId`, clear, `MarkDirty()`.

**REPO-081 — Hard-delete paths that bypass the Trash (preserve for parity; see §8).**
* **Board** card **Delete task** (can be a nested subtask): confirm **"Delete task '{name}'?"** plus
  **"\n\nThis also deletes its {n} subtask(s)."** when it has descendants, titled **"Confirm"** → remove from
  wherever it lives (recursive search), `PurgeReferences`, `Save()`. Not logged.
* **Ctrl+N** **🗑 Delete**: **"Delete '{name}' and everything under it? This removes it everywhere."** titled
  **"Delete"** → log `Removed / "Task"|"Procedure" / {name}`, remove from its collection, `PurgeReferences`,
  unpin, `Save()`.
* Subtask **Remove** / step **Remove** (Specifics, builders): removed from the owning collection, logged
  (`Removed / "Subtask"|"Checklist step" / {name} / {parent}` or `"{n} removed"` in builders), `Save()`; no
  reference scrub. Component **Remove**: not logged.
* Crew **Clear all**: **"Remove ALL crew from the roster?"** titled **"Confirm clear"** → hard clear.
* `BatchDelete.RemoveAll(owner, selection)` (:95) exists for nested items (removes each distinct
  selected object of the element type from the owning collection, returns count) but has **no caller** in the
  current build.

### 2.I Activity log

**REPO-090 — Logging API.** `LogAdded(kind, name, detail = "")` and `LogRemoved(...)` (:230/:233) append a
`LogEntry { TimestampUtc = UtcNow, Action = "Added"|"Removed", Kind = kind (as given), Name = name trimmed, or
"(unnamed)" if nil/whitespace, Detail = detail ?? "" }`, then trim from the **front** while `Count > 10 000`,
then `MarkDirty()`.

**REPO-091 — Log call-site catalogue** (exact Kind strings the Mac app must emit for the same actions):

| Kind | Name | Detail | Where |
|---|---|---|---|
| `Equipment/Area`, `Task`, `Procedure`, `Vessel` | item name | `""` | Hierarchy + New (Added) |
| same (KindLabel) | item name | `moved to Trash` | soft delete (Removed) |
| same / `Crew member` | entry name | `restored from Trash` | restore (Added) |
| `Crew member` | full name | `moved to Trash` | crew soft delete (Removed) |
| `Procedure` / `Task` | name | `linked to {eq.Name}` | Equipment inline create |
| `Task` | name | `linked to step '{step.Title}'` | step inline create |
| `Task`, `Procedure` | name | `""` | Ctrl+N create (Added) / delete (Removed) |
| `Subtask` | name | parent task name | Specifics add/remove, Subtask builder add |
| `Subtask` | `{n} added (bulk)` / `{n} removed` / `{n} added (from saved list '{tpl}')` | parent name | builders |
| `Checklist step` / `Crew checklist item` / `Saved-list item` | title, or `{n} added (bulk)`, `{n} removed`, `{n} added (from saved list '{tpl}')` | owner name | checklist builder (kind depends on host) |
| `Saved list` | list name | `{n} item(s)` / `empty` | save-as-list, + List, Duplicate (Added); delete (Removed, no detail) |
| `Task (recurring)` / `Procedure (recurring)` | name | `next {Recurrence} occurrence → yyyy-MM-dd` | recurrence |
| `Schedule` | template name | `{n} entry` / `{n} entries` | crew schedule save |
| `Bucket` | bucket name | category | Buckets tab |
| `Crew import` | `{a} added, {u} updated` | file name | COMPAS import |
| `Crew import dates` | date summary | file name | COMPAS import |
| `Crew` | `all {n} member(s)` | | crew Clear all (Removed) |
| `Ports import` | `{a} new, {u} updated` | `{vessel} · {format}` | Ports |
| SIRE: KindLabel(parent) | parent name | `from SIRE Q{n}` / `from SIRE ({n} questions)` | SIRE quick-add |
| Ctrl+N builder: capitalised noun | child name / `{n} added (bulk)` / `{n} removed` | owner | Ctrl+N |

**REPO-092 — Activity log window** (Tools ▸ Activity log..., tooltip "UTC-timestamped log of every entry added
and removed."). Non-modal, title **"Activity log"**, 860×620. Header **"Activity log"** (bold, 16, accent), a
filter box (width 190; its `Tag` holds **"Filter action / kind / name..."** but no style renders it — the Mac SHOULD
show it as the search-field prompt), **Export (.csv)...**, **Clear log**.
Muted text: **"Every entry added or removed is recorded with a UTC timestamp (newest first). Local time is
shown alongside for convenience."**. Virtualised list, **newest first**, columns **Time (UTC)** (170,
`yyyy-MM-dd HH:mm:ss 'UTC'` → e.g. `2026-09-29 08:15:30 UTC`), **Local time** (150, `yyyy-MM-dd HH:mm:ss`),
**Action** (80), **Kind** (130), **Name** (200, wrapping), **Detail** (200, wrapping, muted). Footer:
**"{shown} of {total} log entries."**. Filter: case-insensitive substring over Action, Kind, Name, Detail,
re-applied on every keystroke. The list is a snapshot taken when the window opens / filter changes (not live).
* **Clear log**: no-op when empty; confirm **"Clear all {n} activity-log entries? This can't be undone."**
  titled **"Clear activity log"** (Yes/No, warning) → clear, `Save()`, refresh.
* **Export (.csv)...**: save dialog title **"Export activity log"**, filter "CSV file (*.csv)|*.csv|All files
  (*.*)|*.*", default name `aa-activity-log-{UtcNow:yyyyMMdd-HHmmss}.csv`. Content: header
  `TimestampUTC,LocalTime,Action,Kind,Name,Detail`, then one line per entry in **chronological** order with the
  formatted `TimeUtc`, `TimeLocal`, Action, Kind, Name, Detail; a field is wrapped in `"` (inner `"` doubled)
  when it contains `,`, `"` or `\n`. Lines end with CRLF; UTF-8 without BOM. Then open the file with the
  default app. Failure → **"Export failed"** with the exception message.

### 2.J Global search (Ctrl+F) and navigation search

**REPO-100 — Search window.** Opened by the header button **Search (Ctrl+F)** or Ctrl+F (no menu item); non-modal
(a new window per invocation),
title **"Search"**, 900×640, query box focused on open. Row: label **"Search:"**, query box, **Search**
button (default button). Enter in the box or the button runs the search; an empty/whitespace query clears the
results and status. While running: status **"Searching…"** and the button disabled. Result status:
**"No results for \"{query}\"."** or **"{n} result{s} for \"{query}\"."** (query trimmed). A new search
cancels the previous one. Results list (virtualised) columns: **Where** (230: bold `"[{Kind}] {Owner.Name}"`
over a muted 11-pt `Where` label) and **Match** (600: the snippet, single line, trailing ellipsis if too wide,
with the matched text **bold, black on #FFE066** — the same in dark mode). Double-click or Enter on a row →
navigate to the owning top-level item (switch main tab, select it; a locked item opens on its lock screen).

**REPO-101 — Search scope, order and labels** (`SearchService.Search`, SearchService.cs:35). Query trimmed;
match = first **case-insensitive ordinal** substring occurrence per field (one hit per field at most). Items in
`Equipment, Tasks, Procedures, Vessels` order. Per item, fields in this order (`Where` label in quotes):
1. `"Name"` — item name.
2. `"Tags"` — tags joined with `", "` (only when the item has tags).
3. *(lock gate — REPO-102)*
4. `"Description"`.
5. `"Notes"` — plain text of the item container's `RichTextXaml` (REPO-104).
6. For each file in the item container: `"File › {Kind}"` (file name) then `"File › {Kind} › Path"` (stored
   path), `{Kind}` = `Document|Image|Video|Link|Other`.
7. Equipment: for each component → `"Component › Name"`, `"Component › Notes"`, `"Component › Container"`
   (plain text), then each component file name `"Component › File"`.
   Task: depth-first over nested subtasks → `"Subtask › Name"`, `"Subtask › Description"`,
   `"Subtask › Container"`, each file `"Subtask › File"`, then recurse into that subtask's subtasks.
   Procedure: for each step → `"Step › Title"`, `"Step › Container"`, each file `"Step › File"`.
   Vessel: nothing further (work orders, quick cards, ports are not searched).
Crew members, saved lists, schedules, buckets and the SIRE bank are **not** searched. A hit carries
`Owner` (always the top-level item), `Kind` (`Item|Component|Subtask|Step|File`), `Where`, `Snippet`,
`MatchStart`, `MatchLength` (= query length), and `ChildId` (component/subtask/step id; nil otherwise —
currently unused by the UI). At most **500** hits; scanning stops as soon as the cap is reached.

**REPO-102 — Lock-aware search.** Before scanning (on the UI thread), the window snapshots the ids of
top-level items that are password-locked and **not unlocked this session** (`ItemLockService.IsGated`). For
those items only **Name** and **Tags** are searched (tags carry no protected content); description, notes,
files and all child content are skipped, so snippets can never leak locked content.

**REPO-103 — Snippet** (`MakeSnippet`, :131): take up to 60 characters before and after the match; prefix `…`
if text was cut at the start, suffix `…` if cut at the end; collapse every run of whitespace (`\s+`, incl.
newlines/tabs) to a single space (no trimming); recompute the match offset by searching the compacted snippet
case-insensitively for the original matched text; if not found (the match itself contained collapsible
whitespace) fall back to `prefixLength + (idx − start)`. The highlighter clamps start/length to the snippet.

**REPO-104 — XAML → plain text for search** (`PlainTextFromXaml`, :152). Empty → `""`. Otherwise stream the
XML: append each **Text** and **SignificantWhitespace** node's value followed by one space; at the **start** of
every element whose local name is `Paragraph`, `LineBreak` or `ListItem` append one space. Everything else
(attributes, element names, comments, CDATA, insignificant whitespace) is ignored. Entities are decoded. On
any XML error (including a legacy `enc:` encrypted blob or a multi-root fragment) fall back to replacing every
`<[^>]+>` with a space (entities *not* decoded). Consequence (preserve): text in two paragraphs is separated
by two spaces, so a query spanning a paragraph break with a single space does not match.

**REPO-105 — Performance.** The scan runs off the UI thread on the live model (the model is not mutated during
the scan in practice) with a cancellation token checked after completion; container bodies are stripped with
a streaming reader, never loaded into a rich-text document.

**REPO-106 — Tags (input normalisation).** The item header **Tags** box (tooltip "Comma- or space-separated
tags. Used for filtering, global search and the quick switcher (Ctrl+O).") re-parses on every keystroke:
split on `, ; \n \r \t space`, trim, remove empty, strip leading `#`s, drop empties, de-duplicate
case-insensitively (first spelling kept). `Tags` is replaced with the result; `MarkDirty()`. On focus loss
the box is rewritten as the tags joined by `", "`.

**REPO-107 — Quick switcher (Ctrl+O) scoring.** Query = trimmed text with leading `#`s removed. Empty query →
every item scores 1 (all listed). Score (ordinal, case-insensitive): name starts with q **+120**, else name
contains q **+60**, else q is a subsequence of the name (per-char `ToLowerInvariant` compare) **+25**; any tag
starts with q **+45**, else any tag contains q **+22**; `KindLabel` contains q **+8**; description contains q
**+5**. Keep score > 0 (or all when empty), order by score descending then name (ordinal ignore-case), take
**80**, select the first. Rows show name, `KindLabel`, and tags as `"#a  #b"`. ↓/↑ move (clamped), Enter or
double-click opens (closes the switcher, navigates), Esc closes.

### 2.K Reminders and daily digest

**REPO-110 — `ReminderService.Compute(repo, today)`** (ReminderService.cs:30). `today` is local midnight.
Counts each dated, not-done deadline once:
* every top-level task and, recursively, every nested subtask with `!IsComplete` and a `Deadline`
  (recursion continues below completed parents);
* every procedure with `Status != Done` and a `Deadline`;
* every procedure step with `!Done` and a `Deadline` — **even when the procedure itself is Done**;
* every crew checklist step with `!Done` and a `Deadline`.
Bucket by `d.Date`: `< today` → Overdue; `== today` → DueToday; `<= today + 7 days` → DueWeek (i.e. 1–7 days
ahead). Ranged tasks count by their deadline only. Scheduled jobs (`ScheduledStart`), Shippalm work orders and
crew contracts are not counted here.

**REPO-111 — `Summary`.** `Total = Overdue + DueToday + DueWeek`; `Any = Total > 0`. `Headline()` joins the
non-zero parts with `"  ·  "` (two spaces each side): `"{n} overdue"`, `"{n} due today"`, `"{n} due this
week"`; `"Nothing due."` when all zero.

**REPO-112 — Tray reminders** (MainWindow.xaml.cs:1587-1620). A tray icon (tooltip text "AA", app icon) is
created at startup (best-effort). Balloon click → open the floating due-dates window; tray double-click →
show and activate the main window. `CheckReminders(force)`: compute; `crew` = number of crew whose sign-off is
≤ 60 days away or past (`CrewPage.ExpiringCount`). If nothing due and crew == 0 → reset the dedup key and stop.
Dedup key `"{today:yyyy-MM-dd}|{Overdue}|{DueToday}|{DueWeek}|{crew}"`; if not forced and equal to the last key
→ stop. Else balloon for 8 s, title **"AA — due soon"**, text `Headline()` plus `"  ·  {crew} crew contract(s)
expiring"` when crew > 0, info icon. Runs at startup (after the digest) and every **30 minutes**.

**REPO-113 — Once-a-day digest** (`ShowDailyDigestIfDue`, :1624). At startup only (not in safe mode): if
`Ui.LastDigestDate == today` (`yyyy-MM-dd`, local) → stop. Else set `Ui.LastDigestDate = today`,
`MarkDirty()` (set even when nothing is due), compute; if nothing due and crew == 0 → stop; else open the
floating due-dates window (overdue, today, tomorrow, next 7 days) and force a balloon. `LastDigestDate` is a
per-device key and never travels over Flash Sync.

**REPO-114 — Relationship to the floating due-dates window.** The window (own spec) uses the same inclusion
rules but different buckets: OVERDUE (deadline before today), TODAY, TOMORROW (ranged tasks appear on every
covered day), NEXT 7 DAYS (day+2..day+7, de-duplicated), plus Planner jobs scheduled that day. The counts in
REPO-110 therefore intentionally differ from the window's rows (tomorrow is inside "due this week";
ranged-task coverage and scheduled jobs are not counted).

### 2.L Sidebar groups (Hierarchy pages)

**REPO-120 — Group operations** (AppRepository.cs:647-674). `GroupsFor(kind)` = `Data.Groups` filtered by
`Kind` (collection order). `CreateGroup(kind, name)`: name trimmed, or `"New group"` when blank; appended;
returned. `RenameGroup(g, name)`: ignored when blank; else trimmed. `DeleteGroup(g)`: every top-level item of
**any** kind with `GroupId == g.Id` becomes ungrouped (`nil`), then the group is removed.
`AssignToGroup(items, groupId)`: sets `GroupId` (no caller currently; pages assign directly). None of these
save; callers `Save()`. (Sidebar UI — ordering "Ungrouped" last, empty-group placeholders, expand state in
`Ui.GroupExpanded["{Kind}|{groupName}"]`, `Ui.SortAZ["{Kind}"]` — belongs to the hierarchy spec.)
`ItemGroup.Expanded` is persisted (default true) but not used by the UI.

### 2.M Saved lists — arranged order and export order

**REPO-130 — Collection order is the arrangement.** There is no sort field: the order of
`AppData.ChecklistTemplates` *is* the user's arrangement and persists because JSON arrays keep order. Every
operation below is a pure permutation (nothing created, removed or duplicated). New lists (save-as, + List,
Duplicate, import) are appended at the end.

**REPO-131 — `GroupSpan(all, groupId)`** (SavedListOrder.cs:20): ascending indices in `all` of the lists whose
`GroupId == groupId` (nil = ungrouped). Reordering works on this subsequence so a list can never hop a group
boundary.

**REPO-132 — Nudge up/down** (`Nudge`, :30; buttons **↑** / **↓**, tooltips "Move the selected saved list(s)
up within its group. This is the order they export in." / "...down within its group..."). Returns false (and
the UI does nothing) when: picks empty or span different groups; the group has < 2 lists; up and the first
pick is already first in the group; down and the last pick is already last. Otherwise, for each pick's
position within the span (ascending for up, descending for down) move that collection element to the flat
index of the neighbouring span slot. Single picks and picks from a group whose members are **contiguous** in
the flat collection produce the intended result (each pick swaps with its neighbour in the group). **Known
defect:** a multi-selection in a group that is interleaved with other groups' lists in the flat collection can
produce a wrong order (see §8, D-1 and test vectors T-ORD-6/7).

**REPO-133 — Move to position** (`MoveTo`, :49; button **Move to position...**, tooltip "Move the selected
saved list(s) to a chosen position within its group."). UI picker (single-select) titled **"Move {n}
list{s} to..."** with options **"(Move to top of group)"** (target 0), **"Before: {name ≤ 60 chars, `…`
if cut}"** for each non-moving list in the group (target = its position), **"(Move to bottom of group)"**
(target = group size). Algorithm: same-group and ≥ 2 checks; `ordered` = the group's lists in order;
`before` = number of movers among `ordered[0 ..< clamp(target, 0, n)]`; `remaining` = non-movers;
insert all movers (keeping their relative order) into `remaining` at `clamp(target − before, 0,
remaining.count)`; then for each slot `pos` of the span, move the desired list into flat index `span[pos]`
if it isn't already there. Correct for all inputs (verified by simulation).

**REPO-134 — Guards and messages** (SavedListsPage). While **Sort A-Z** is on: **"Turn off \"Sort A-Z\" first
— while it is on you are seeing alphabetical order, not your own."** titled **"Arrange lists"**; ↑/↓/Move to
position are disabled. No selection: **"Select a saved list first."** titled **"Saved Lists"**. Mixed groups:
**"Those lists are in different groups. Lists are arranged within their own group, so select lists from one
group at a time."** titled **"Arrange lists"**. A group of one: silently nothing. After a successful move:
`Save()`, refresh, re-select the moved lists (scroll to first), status **"Order saved — this is the order the
group exports in."**. The selection is always taken in collection order. **Sort A-Z** (toggle, tooltip "Show
lists alphabetically instead of your own order. Your arranged order is kept and is what exports use when this
is off.") persists in `Ui.SortAZ["savedlists"]`, calls `Save()`, and shows **"Showing A-Z. Your arranged order
is kept, and is what exports use — switch this off to see it."** / **"Showing your arranged order. This is the
order lists appear in when you export a group."**.

**REPO-135 — `GroupEntries(data, groupId)`** (:75): the lists with that `GroupId` in collection order, each
paired with the group's name — or nil when `groupId` is nil, the group no longer exists, or its name is empty.
Used by **📄 Export group (PDF)...** (title = group name; if the selected list is ungrouped *or its group no
longer exists*, title **"Ungrouped lists"** and `GroupEntries(nil)` — which then does not include a list with
a dangling group id).

**REPO-136 — `AllEntries(data)`** (:88): every list, stably sorted by group key then collection position, so
each group's lists are **contiguous** (the PDF prints a heading only when the group changes). Group key:
ungrouped → sorts **last**; otherwise the group name lower-cased (a dangling group id → `""`, which sorts
**first** and is paired with group `""`, not nil). Paired group = the group's name (original case) or nil for
ungrouped. Two different groups with the same lower-cased name interleave into one run. Used by **📄 Export ALL
(PDF)...** (title "All saved lists"; "No saved lists to export." when empty).

### 2.N Saved lists — checklist template service ("full copy" semantics)

A saved list (`ChecklistTemplate`) is a **full copy**: each item carries `Title`, `DurationMinutes`, `IsJob`
and a complete, independent `Container` (rich text + file bank); it never carries a deadline, range,
done state, links or buckets (those are per-instance).

**REPO-140 — `CaptureFromSteps(name, steps)`** (ChecklistTemplateService.cs:16): new template (new `Id`,
`CreatedUtc = UtcNow`, `GroupId = nil`, `Name = name.Trim()`), one item per step in order: `Title`,
`DurationMinutes`, `IsJob`, `Container = CloneContainer(step.Container)`. Dropped: `Done`, `Deadline`,
`ScheduledStart`, `TaskIds`, `EquipmentIds`, `BucketIds`, step `Id`.

**REPO-141 — `CaptureFromSubtasks(name, subtasks)`** (:29): as above from **direct** subtasks only: `Title =
Name`, duration, job flag, cloned container. Dropped: nested sub-subtasks, `Description`, deadline/range,
status/complete, recurrence, tags, relations, buckets.

**REPO-142 — Apply** (`ApplyToSteps` :45 / `ApplyToSubtasks` :60): if `replace`, clear the target first (a hard
removal — no Trash, no reference scrub); then append one new object per template item: a `ChecklistStep`
(`Title`, duration, `IsJob`, cloned container; new id; `Done = false`; no deadline/links) or a `TaskItem`
(`Name = Title`, duration, `IsJob`, cloned container; new id; `Todo`). Returns `template.Items.Count`.
UI (all builders): **📋 Load a saved list** — none saved → **"No saved lists yet. Build a list and click 'Save
as list...' to create one."** titled **"Load a saved list"**; picker **"Insert a saved list"** (single-select,
rows `Display` = `"{name or (unnamed)}  ·  {n} item{s}"`, collection order); then **"Insert '{name}' ({n}
item(s)).\n\nYes = replace the current items\nNo = append to the end\nCancel = do nothing"** (subtask builder
says "replace the current subtasks") titled **"Insert a saved list"** (Yes/No/Cancel) → apply, log `Added /
{host kind} / "{n} added (from saved list '{name}')" / {owner}`, `MarkDirty()` (not an immediate save),
refresh.

**REPO-143 — Duplicate** (`Clone(t, newName)`, :75): new `Id`, `Name = newName` (not trimmed),
**same `GroupId`**, `CreatedUtc = UtcNow`, items deep-copied (containers cloned). UI **Duplicate** uses
`"{name} (copy)"`, appends, logs `Added / "Saved list" / {copy} / "{n} item(s)"`, `Save()`, selects the copy.

**REPO-144 — Saved-list item → standalone task** (`ItemToTask`, :91; `SavedListPicker.PickAndAddTasks`).
`TaskItem { Name = Title, DurationMinutes, IsJob, Container = CloneContainer(item.Container), Status = Todo }`
— no deadline, range or done state. Flow (**+ From saved list** on the Board, **+ Saved list** in the
Planner): no lists → **"You have no saved lists yet. Build one in the Saved Lists tab first."**; lists but no
items → **"Your saved lists don't have any items yet."** (both titled **"Add from saved list"**). Otherwise a
searchable multi-select picker **"Search saved lists — pick items to add as tasks"** over every item of every
list (collection order), rows `"{list name or (unnamed list)}  ›  {title or (untitled)}"` plus `"   ·
schedulable"` when `IsJob`. Each pick → new top-level task appended to `Data.Tasks`; `Save()` if any. Not
logged.

**REPO-145 — Edit a saved list's items** (`ToSteps` :104 / `WriteBackFromSteps` :115; **✎ Edit items...**):
materialise items as `ChecklistStep`s (title, duration, job flag, cloned container), edit them in the shared
checklist builder (host log kind **"Saved-list item"**), and on window close **always** rebuild `Items` from
the steps (clear + re-add with cloned containers — per-instance deadline/done set in the builder are dropped)
and `Save()`. Note: every open/close regenerates all item container ids and file-entry ids, so the template
always reads as "changed" to a diff/sync.

**REPO-146 — Deep container copy** (`CloneContainer`, :133; `CloneFile`, :144). Nil source → a fresh empty
container. Else a new container (new `Id`) with the same `RichTextXaml` (verbatim, including a legacy
`enc:` blob), the same `IsLocked`, the same `SharedWithContainerIds`, and each file copied into a **new**
`FileItem` (new `Id`) with the same `Name`, `Path`, `Kind`, `Added`, `IsLink`, `LinkInPlace` and
`LinkedItemIds`. Paths are shared: the physical attachment in `files/` is referenced by both copies and never
duplicated on disk. (Contrast: recurrence cloning keeps `FileItem.Id`s — REPO-061.)

**REPO-147 — Save as list** (every builder: procedure checklist, crew checklist, subtask builder, Ctrl+N).
Empty source → **"Add some items first, then save the list."** (checklist builder, Ctrl+N) or **"Add some
subtasks first, then save the list."** (subtask builder), titled **"Save list"**. Prompt title **"Save as reusable list"**, label **"Name for
this saved list:"**, default = the owner's name. Blank/cancel → nothing. Capture, append to
`Data.ChecklistTemplates`, log `Added / "Saved list" / {name} / "{n} item(s)"`, `Save()`, then **"Saved '{name}'
({n} item(s)). You can reuse it from any checklist builder."** titled **"Saved list"**.
**Manage** (checklist builder): picker **"Manage saved lists — pick one"**; then **"'{name}' ({n} item(s)).\n\nYes
= rename\nNo = delete\nCancel = nothing"** titled **"Manage saved list"**; rename prompt **"Rename saved list"** /
**"New name:"** (trimmed, `Save()`); delete confirm **"Delete saved list '{name}'? This does not affect any
checklist already built from it."** titled **"Delete saved list"** → remove, log `Removed / "Saved list" /
{name}`, `Save()`. With no lists: **"No saved lists yet."** titled **"Manage saved lists"**.

### 2.O Crew schedule templates

**REPO-150 — `CloneEntry(e)`** (ScheduleService.cs:14): new `ScheduleEntry` with a **new id**, `Done = false`,
and copies of `Title`, `Kind`, `RefId`, `Date`, `Time`, `EndDate`, `EndTime`, `Notes`.

**REPO-151 — `CaptureFromCrew(name, crew, data)`** (:26): new template (`Id`, `CreatedUtc = UtcNow`),
`Name = name.Trim()`, `VesselId = crew.ScheduleVesselId`, `VesselName` = that vessel's current name, or `""`
if none/not found; entries = cloned crew schedule entries in order.

**REPO-152 — `ApplyToCrew(t, crew, replace)`** (:35): clear the crew schedule if `replace`; append clones of
every template entry; if the template has a `VesselId` set it as `crew.ScheduleVesselId` (an unset template
vessel leaves the crew's link alone — even when the vessel doesn't exist locally). Returns entry count.

**REPO-153 — Export `.aasched.json`** (:43): the template serialised **indented** with default options (nulls
written, enums as numbers). UI: nothing to export → **"No schedule to export."** titled **"Export"**; save dialog
**"Export schedule"**, filter `AA schedule (*.aasched.json)|*.aasched.json|JSON (*.json)|*.json`, default name
`Schedule-{crew full name with invalid filename chars → _, or "crew"}.aasched.json`; the exported template is a
fresh capture named `"{FullName} schedule"`; success **"Exported to:\n{path}"** titled **"Export complete"**;
failure **"Could not export:\n\n{message}"** titled **"Export failed"**.

**REPO-154 — Import** (:48): parse with default options (case-sensitive keys); JSON `null` → error **"This file
is not a valid schedule."**; assign a fresh template `Id` and fresh entry ids (`CreatedUtc`, `VesselId`,
`VesselName` kept from the file). UI: open dialog **"Import schedule"**, filter `AA schedule
(*.aasched.json;*.json)|*.aasched.json;*.json|All files (*.*)|*.*`; the template is appended to
`Data.ScheduleTemplates` (kept as a reusable saved schedule), `Save()`, then the Apply flow (REPO-155) runs.
Failure → **"Could not import the schedule:\n\n{message}"** titled **"Import failed"**.

**REPO-155 — Save / Apply UI.** Save: empty → **"Add some entries first."** titled **"Save schedule"**; prompt
**"Save schedule"** / **"Name for this reusable schedule:"** (default crew full name) → capture, append, log
`Added / "Schedule" / {name} / "{n} entry"|"{n} entries"`, `Save()`, **"Saved '{name}'. You can apply it to any
crew member."** titled **"Save schedule"**. Apply: none saved → **"No saved schedules yet. Build one and click 'Save as...'."** titled
**"Apply schedule"**; picker **"Apply a saved schedule"** (rows `"{name or (unnamed)}  ·  {n} entry|entries"` +
`"  ·  {VesselName}"` when set); confirm **"Apply '{name}' ({n} entries) to {crew}.\n\nYes = replace this crew's
schedule\nNo = append\nCancel = nothing"** titled **"Apply schedule"** → apply, `Save()`, rebind, **"Applied {n}
entry|entries to {crew}."** titled **"Apply schedule"**. Vessel combo change → `crew.ScheduleVesselId`, `Save()`.

---

## 3. Logic & algorithms (function by function)

Pseudo-code is language-neutral; `⟨…⟩` marks an exact constant. All functions run on the main (UI) thread
unless stated otherwise.

### 3.1 `AppRepository` (AA/Services/AppRepository.cs)

#### 3.1.1 Construction and persistence

```
init(data):                                   // :31
    Data = data
    debounce = timer(interval ⟨750 ms⟩, on tick: stop(); backgroundSaveIfDirty())

markDirty():                                  // :301
    if SuspendSaving: return
    dirty = true; debounce.restart()

backgroundSaveIfDirty():  (async, UI thread)   // :42
    if SuspendSaving or !dirty: return
    prev = Data.LastModified
    Data.LastModified = now(local)
    dirty = false
    json = try DataStore.SerializeForSave(Data)  catch { Data.LastModified = prev; dirty = true; return }
    try await queueWrite(json); raise Saved
    catch { Data.LastModified = prev; dirty = true }

queueWrite(json) -> Task:                     // :62
    prev = writeChain
    mine = runOnBackground { try? await prev; DataStore.WriteData(json) }   // failure of prev ignored
    writeChain = mine
    return mine

save() throws:                                // :261
    if SuspendSaving: return                  // silent
    debounce.stop()
    prev = Data.LastModified; Data.LastModified = now(local)
    json = try SerializeForSave(Data)  catch e { Data.LastModified = prev; throw e }   // dirty untouched
    task = queueWrite(json)
    if !task.wait(⟨15 000 ms⟩): Data.LastModified = prev; throw Timeout("Timed out writing {CurrentDataFile}.")
    if task faulted with e:       Data.LastModified = prev; throw e
    dirty = false; raise Saved

flushIfDirty() throws: if dirty: save()       // :312
detach(): SuspendSaving = true; debounce.stop(); Saved = (no subscribers)   // :293
```

Notes for the port:
* `DataStore.SerializeForSave` mutates the model before serialising: normalises attachment paths and raises
  `SchemaVersion` to at least 1 (never lowers it). It must be called on the thread that owns the model.
* `DataStore.WriteData` writes to the **current** data file *at write time*; see §8 D-9 for why the Swift port
  should capture the destination when the write is enqueued.
* The `Saved` continuation runs on the UI thread (the await resumes on the UI context).
* There is no retry timer after a failed debounced write; retries come from the next `markDirty`, the 5-minute
  app autosave (only if dirty), explicit saves and close.

#### 3.1.2 Traversal

```
allItems():            yield* Equipment; yield* Tasks; yield* Procedures; yield* Vessels      // :74
findById(id):          first(allItems(), where: .Id == id)                                    // :82
allContainers():                                                                              // :86
    for eq in Equipment:  yield eq.Container?; for c in eq.Components: yield c.Container?
    for t in Tasks:       walkTaskContainers(t)   // t.Container?, then for st in t.Subtasks: walk(st)
    for p in Procedures:  yield p.Container?; for s in p.Steps: yield s.Container?
    for v in Vessels:     yield v.Container?
    for cm in Crew:       for s in cm.Checklist: yield s.Container?
    for tpl in ChecklistTemplates: for it in tpl.Items: yield it.Container?
    ("?": skip when nil)
allJobs():                                                                                    // :121
    for t in Tasks: jobsInTask(t)          // if t.IsJob yield t; for st in t.Subtasks: jobsInTask(st)
    for p in Procedures: if p.IsJob yield p; for s in p.Steps: if s.IsJob yield s
    for c in Crew: for s in c.Checklist: if s.IsJob yield s
label(id):  item = findById(id); item == nil ? ⟨"(missing)"⟩ : "[\(item.Kind enum name)] \(item.Name)"   // :143
kindLabel(kind): Equipment→"Equipment/Area", Task→"Task", Procedure→"Procedure", Vessel→"Vessel", else enum name
```

#### 3.1.3 Relationships

```
relatedItems(item):                                                                           // :150
    ids = OrderedSet(item.RelatedIds)
    if item is Equipment: ids.append(contentsOf: eq.ProcedureIds); ids.append(contentsOf: eq.TaskIds)
    for id in ids: if let x = findById(id): yield x
referencedBy(target):                                                                         // :169
    for i in allItems() where i.Id != target.Id:
        refs = i.RelatedIds.contains(target.Id)
        if !refs, i is Equipment: refs = eq.ProcedureIds.contains(id) || eq.TaskIds.contains(id)
        if !refs, i is Procedure: refs = p.Steps.any { $0.TaskIds.contains(id) || $0.EquipmentIds.contains(id) }
        if refs: yield i
purgeReferences(deletedId):                                                                   // :186
    for item in allItems():
        item.RelatedIds.removeFirst(deletedId)
        if Equipment: ProcedureIds.removeFirst(deletedId); TaskIds.removeFirst(deletedId)
        else if Procedure: for step: step.TaskIds.removeFirst(deletedId); step.EquipmentIds.removeFirst(deletedId)
    for c in allContainers(): for f in c.Files: f.LinkedItemIds.removeFirst(deletedId)
addRelation(a, b):  if a.Id == b.Id return; appendIfAbsent(a.RelatedIds, b.Id); appendIfAbsent(b.RelatedIds, a.Id)
removeRelation(a, b): a.RelatedIds.removeFirst(b.Id); b.RelatedIds.removeFirst(a.Id)
```
`removeFirst(x)` = remove the first element equal to x if any (C# `Collection.Remove`). None of these call
`markDirty`/`save`.

#### 3.1.4 Activity log

```
logAction(action, kind, name, detail):                                                        // :235
    Data.Log.append(LogEntry(TimestampUtc: nowUtc, Action: action, Kind: kind,
                             Name: isNilOrWhitespace(name) ? ⟨"(unnamed)"⟩ : name.trimmed,
                             Detail: detail ?? ""))
    while Data.Log.count > ⟨10 000⟩: Data.Log.removeFirst()
    markDirty()
logAdded(kind, name, detail = "")   = logAction(⟨"Added"⟩, …)
logRemoved(kind, name, detail = "") = logAction(⟨"Removed"⟩, …)
```
"Whitespace"/"trim" follow .NET `char.IsWhiteSpace` (Unicode White_Space); Swift `trimmingCharacters(in:
.whitespacesAndNewlines)` is equivalent for practical input.

#### 3.1.5 Trash

Constants: `MaxTrashItems = 200`, `TrashRetention = 90 days`. `TrashOpts` = compact JSON, ignore cycles, omit
nulls (identical in effect to the `data.json` options).

```
trashType(kind): Equipment→"Equipment", Task→"Task", Procedure→"Procedure", Vessel→"Vessel", else ""   // :329

trashHierarchyItem(item) -> TrashedItem?:                                                     // :341
    type = trashType(item.Kind); if type == "": return nil
    ti = TrashedItem(Id: new, ItemType: type, ItemId: item.Id, BatchId: empty, Name: item.Name,
                     KindLabel: kindLabel(item.Kind), DeletedUtc: nowUtc,
                     PayloadJson: json(item as its runtime type, TrashOpts))
    remove item from its collection        // C# ignores whether it was actually found (§8 D-2)
    addToTrash(ti)                         // append + pruneTrash()
    logRemoved(kindLabel(item.Kind), item.Name, ⟨"moved to Trash"⟩)
    markDirty(); return ti

trashCrew(m) -> TrashedItem:                                                                  // :371
    ti = TrashedItem(ItemType: "Crew", ItemId: m.Id,
                     Name: isNilOrWhitespace(m.FullName) ? m.LastName : m.FullName,
                     KindLabel: ⟨"Crew member"⟩, PayloadJson: json(m, TrashOpts), …defaults)
    Data.Crew.remove(m); addToTrash(ti); logRemoved("Crew member", ti.Name, "moved to Trash"); markDirty()

trashHierarchyItems(items) -> Int:                                                            // :505
    batch = newGuid(); n = 0
    for item in Array(items):  if let ti = trashHierarchyItem(item) { ti.BatchId = batch; n += 1 }
    return n

pruneTrash():                                                                                 // :398
    changed = false; cutoff = nowUtc − 90 days
    for i in (Trash.count−1 … 0): if Trash[i].DeletedUtc < cutoff { evictAt(i); changed = true }
    while Trash.count > 200:
        oldest = first element with minimal DeletedUtc (stable: earliest index among equals)
        evictAt(index(of: oldest)); changed = true
    if changed: markDirty()
evictAt(i): purgeReferences(Trash[i].ItemId); Trash.remove(at: i)

restoreTrash(ti) -> String?:                                                                  // :422
    do:
        switch ti.ItemType:
          "Equipment": x = decode(Equipment, ti.PayloadJson); if x == nil return nil
                       if !Data.Equipment.contains(where: .Id == x.Id): Data.Equipment.append(x)
          "Task" / "Procedure" / "Vessel" / "Crew": same against Tasks / Procedures / Vessels / Crew
          default: return nil
    catch: return nil
    Trash.remove(ti); logAdded(ti.KindLabel, ti.Name, ⟨"restored from Trash"⟩); markDirty(); return ti.ItemType

undoLastDelete() -> [String]:                                                                 // :471
    newest = Trash.stableSorted(by: DeletedUtc descending).first; if nil: return []
    batch = newest.BatchId == empty ? [newest]
          : Trash.filter { $0.BatchId == newest.BatchId }.stableSorted(by: DeletedUtc descending)
    types = []
    for ti in batch: if let t = restoreTrash(ti), !types.contains(t): types.append(t)
    return types
pendingUndoCount(): newest == nil ? 0 : (newest.BatchId == empty ? 1 : Trash.count(where: BatchId == newest.BatchId))
purgeTrash(ti):  if Trash.remove(ti) succeeded: purgeReferences(ti.ItemId); markDirty()        // :520
emptyTrash():    if Trash.isEmpty return; for ti in Trash: purgeReferences(ti.ItemId); Trash.removeAll(); markDirty()
```

#### 3.1.6 Recurrence

```
nextOccurrence(from, r):                                                                      // :535
    Daily: from + 1 day;  Weekly: from + 7 days
    Monthly: addMonths(from, 1)   // Gregorian; day clamped to the target month's length
    Yearly:  addYears(from, 1)    // Feb 29 → Feb 28
    None:    from
    (time-of-day and Kind preserved; pure calendar arithmetic, no DST adjustment)

deepClone(x) = decode(type(of: x), encode(x, TrashOpts), TrashOpts)                            // :544

reconcileRecurrences() -> Bool:                                                               // :552
    changed = false
    newTasks = []
    for t in Array(Tasks):
        if t.Recurrence == None || !t.IsComplete || t.RecurrenceSpawned: continue
        t.RecurrenceSpawned = true
        c = deepClone(t); renewTask(c)
        old = t.Deadline
        next = nextOccurrence(old ?? todayLocalMidnight, t.Recurrence)
        if let rs = t.RangeStart, let dl = old, rs.date < dl.date:
            c.RangeStart = next − wholeDays(dl.date − rs.date) days
        else: c.RangeStart = nil
        c.Deadline = next
        if let od = old: shiftChildDeadlines(c, delta: next.date − od.date)
        newTasks.append(c)
        logAdded(⟨"Task (recurring)"⟩, c.Name, "next \(t.Recurrence) occurrence → \(next:yyyy-MM-dd)")
        changed = true
    Tasks.append(contentsOf: newTasks)
    newProcs = []
    for p in Array(Procedures):
        if p.Recurrence == None || p.Status != Done || p.RecurrenceSpawned: continue
        p.RecurrenceSpawned = true
        c = deepClone(p); renewProcedure(c)
        old = p.Deadline; next = nextOccurrence(old ?? todayLocalMidnight, p.Recurrence)
        c.Deadline = next
        if let od = old: delta = next.date − od.date; for s in c.Steps: if let sd = s.Deadline { s.Deadline = sd + delta }
        newProcs.append(c)
        logAdded(⟨"Procedure (recurring)"⟩, c.Name, "next \(p.Recurrence) occurrence → \(c.Deadline:yyyy-MM-dd)")
        changed = true
    Procedures.append(contentsOf: newProcs)
    if changed: markDirty()
    return changed

renewTask(t):  t.Id = new; t.Container?.Id = new; t.RecurrenceSpawned = false; t.ScheduledStart = nil
               t.IsComplete = false   // setter: Done→Todo, other statuses untouched
               for st in t.Subtasks: renewTask(st)
shiftChildDeadlines(t, delta): for st in t.Subtasks:
               if st.Deadline != nil: st.Deadline += delta
               if st.RangeStart != nil: st.RangeStart += delta
               shiftChildDeadlines(st, delta)
renewProcedure(p): p.Id = new; p.Container?.Id = new; p.RecurrenceSpawned = false; p.ScheduledStart = nil
               p.Status = Todo
               for s in p.Steps: s.Id = new; s.Container?.Id = new; s.Done = false; s.ScheduledStart = nil
```
`{Recurrence}` in the log is the enum **name** (`Daily`, `Weekly`, `Monthly`, `Yearly`). Dates in log text are
formatted `yyyy-MM-dd` (the Swift port MUST use a fixed Gregorian/POSIX formatter).

#### 3.1.7 Sidebar groups

```
groupsFor(kind) = Groups.filter { $0.Kind == kind }
createGroup(kind, name): g = ItemGroup(Kind: kind, Name: isBlank(name) ? ⟨"New group"⟩ : name.trimmed); Groups.append(g); return g
renameGroup(g, name): if isBlank(name) return; g.Name = name.trimmed
deleteGroup(g): for i in allItems() where i.GroupId == g.Id: i.GroupId = nil; Groups.remove(g)
assignToGroup(items, gid): for i in items: i.GroupId = gid
```

### 3.2 `SearchService` (AA/Services/SearchService.cs)

```
search(data, query, maxResults = ⟨500⟩, lockedOwnerIds: Set<UUID>?) -> [Hit]:                 // :35
    if isBlank(query) || data == nil: return []
    q = query.trimmed
    add(owner, kind, where, text, childId = nil):
        if hits.count >= maxResults || text is empty: return
        idx = text.firstRange(of: q, caseInsensitiveOrdinal); if none: return
        (snippet, start) = makeSnippet(text, idx, q.length)
        hits.append(Hit(owner, kind, where, snippet, start, q.length, childId))
    for item in Equipment ++ Tasks ++ Procedures ++ Vessels:
        if hits.count >= maxResults: break
        add(item, .Item, "Name", item.Name)
        if !item.Tags.isEmpty: add(item, .Item, "Tags", item.Tags.joined(", "))
        if lockedOwnerIds?.contains(item.Id) == true: continue
        add(item, .Item, "Description", item.Description)
        add(item, .Item, "Notes", plainTextFromXaml(item.Container?.RichTextXaml))
        for f in item.Container?.Files ?? []:
            add(item, .File, "File › \(f.Kind)", f.Name)
            add(item, .File, "File › \(f.Kind) › Path", f.Path)
        switch item:
          Equipment: for c in Components:
                        add(eq, .Component, "Component › Name", c.Name, c.Id)
                        add(eq, .Component, "Component › Notes", c.Notes, c.Id)
                        add(eq, .Component, "Component › Container", plainText(c.Container?.RichTextXaml), c.Id)
                        for f in c.Container?.Files: add(eq, .Component, "Component › File", f.Name, c.Id)
          TaskItem:  walk(owner: t, t)
          Procedure: for s in Steps:
                        add(p, .Step, "Step › Title", s.Title, s.Id)
                        add(p, .Step, "Step › Container", plainText(s.Container?.RichTextXaml), s.Id)
                        for f in s.Container?.Files: add(p, .Step, "Step › File", f.Name, s.Id)
walk(owner, t): for st in t.Subtasks:
        add(owner, .Subtask, "Subtask › Name", st.Name, st.Id)
        add(owner, .Subtask, "Subtask › Description", st.Description, st.Id)
        add(owner, .Subtask, "Subtask › Container", plainText(st.Container?.RichTextXaml), st.Id)
        for f in st.Container?.Files: add(owner, .Subtask, "Subtask › File", f.Name, st.Id)
        walk(owner, st)
```
`caseInsensitiveOrdinal` = .NET `StringComparison.OrdinalIgnoreCase` (code-unit comparison after simple
upper-casing; no normalisation, no diacritic folding). Swift: `range(of: q, options: [.caseInsensitive])` is
the practical equivalent; do **not** add `.diacriticInsensitive`. Offsets are UTF-16 code units in C#; the
Swift port may use `String.Index` internally but must highlight the same characters.

```
makeSnippet(text, idx, len) -> (String, Int):                                                 // :131
    start = max(0, idx − ⟨60⟩); end = min(text.len, idx + len + ⟨60⟩)
    s = (start > 0 ? "…" : "") ; prefix = s.len
    s += text[start ..< end]; if end < text.len: s += "…"
    compact = s.replacingRegex(⟨\s+⟩, with: " ")
    newIdx = compact.firstIndex(ofCaseInsensitive: text[idx ..< idx+len]) ?? (prefix + (idx − start))
    return (compact, newIdx)

plainTextFromXaml(xaml) -> String:                                                            // :152
    if xaml nil/empty: return ""
    try:
        out = ""
        for node in XmlReader(xaml, ignoreWhitespace: false):   // document conformance, DTD prohibited
            if node is Text or SignificantWhitespace: out += node.value + " "
            else if node is Element(start) and localName in {"Paragraph", "LineBreak", "ListItem"}: out += " "
        return out
    catch: return xaml.replacingRegex(⟨<[^>]+>⟩, with: " ")
```
Swift note: Foundation `XMLParser` delivers character data in arbitrary chunks (it splits around entities and
buffer boundaries). The port MUST accumulate contiguous character data into one text node and append a single
`" "` when the text node ends (at the next element start/end), to reproduce `XmlReader` exactly (`"Fish &amp;
chips"` → `"Fish & chips "`, not `"Fish  &  chips "`). Treat whitespace-only character data as significant
only when inside an `xml:space="preserve"` scope (WPF writes that attribute on the root `Section`); ignore
CDATA and comments. Enable `shouldProcessNamespaces` so `localName` is namespace-free.

### 3.3 `ReminderService` (AA/Services/ReminderService.cs)

```
compute(repo, today) -> Summary:                                                              // :30
    overdue = dueToday = dueWeek = 0; weekEnd = today + 7 days
    for d in deadlines(repo):
        dd = d.date
        if dd < today: overdue += 1 else if dd == today: dueToday += 1 else if dd <= weekEnd: dueWeek += 1
    return Summary(overdue, dueToday, dueWeek)
deadlines(repo):
    for t in Tasks: taskDeadlines(t)      // if !t.IsComplete && t.Deadline: yield; recurse into ALL subtasks
    for p in Procedures:
        if p.Status != Done && p.Deadline: yield p.Deadline
        for s in p.Steps: if !s.Done && s.Deadline: yield s.Deadline
    for c in Crew: for s in c.Checklist: if !s.Done && s.Deadline: yield s.Deadline
Summary.headline(): parts = [overdue>0 ? "{n} overdue", dueToday>0 ? "{n} due today", dueWeek>0 ? "{n} due this week"]
                    return parts.isEmpty ? ⟨"Nothing due."⟩ : parts.joined(⟨"  ·  "⟩)
```

Caller (MainWindow.xaml.cs:1606 / :1624):
```
checkReminders(force):
    if repo == nil || tray == nil: return
    sum = compute(repo, todayLocal); crew = crewPage.expiringCount   // sign-off within ⟨60⟩ days or past
    if !sum.any && crew == 0: lastKey = nil; return
    key = "\(today:yyyy-MM-dd)|\(sum.overdue)|\(sum.dueToday)|\(sum.dueWeek)|\(crew)"
    if !force && key == lastKey: return
    lastKey = key
    text = sum.headline() + (crew > 0 ? "  ·  \(crew) crew contract(s) expiring" : "")
    balloon(timeout ⟨8000 ms⟩, title ⟨"AA — due soon"⟩, text, info)
showDailyDigestIfDue():
    if repo == nil || safeMode: return
    today = todayLocal.format("yyyy-MM-dd"); if Ui.LastDigestDate == today: return
    Ui.LastDigestDate = today; markDirty()
    sum = compute(…); crew = …; if !sum.any && crew == 0: return
    openDueDatesWindow(); checkReminders(force: true)
startup (not safe mode, background priority): pruneTrash(); if reconcileRecurrences() reload Tasks+Procedures lists;
    showDailyDigestIfDue(); checkReminders(false)
timer every ⟨30 min⟩: checkReminders(false)
```

### 3.4 `WorkRange.Coerce` (AA/Services/WorkRange.cs:15)

```
coerce(start, deadline, editedStart) -> (start?, deadline?):
    start = start?.date; deadline = deadline?.date
    if let s = start:
        if deadline == nil: deadline = s
        else if s > deadline!: if editedStart { deadline = s } else { start = deadline }
    return (start, deadline)
```

### 3.5 `BatchDeadline` (AA/Services/BatchDeadline.cs)

```
setDeadline(item, date) -> Bool:                                                              // :16
    d = date?.date
    switch item:
      TaskItem t:
        if d == nil:
            if t.Deadline == nil && t.RangeStart == nil: return false
            t.Deadline = nil; t.RangeStart = nil; return true
        (ns, nd) = coerce(t.RangeStart, d, editedStart: false)
        if t.Deadline == nd && t.RangeStart == ns: return false
        t.RangeStart = ns; t.Deadline = nd; return true
      Procedure p:     if p.Deadline == d return false; p.Deadline = d; return true
      ChecklistStep s: if s.Deadline == d return false; s.Deadline = d; return true
      default: return false
setDeadlineAll(items, date) = items.count { setDeadline($0, date) }
```
Equality is on the instant/ticks regardless of Kind (a Local-kind 2026-10-05 00:00 equals an Unspecified
2026-10-05 00:00).

### 3.6 `BatchDone` (AA/Services/BatchDone.cs) — see REPO-042 (the pseudo-code is the bullet list verbatim).

### 3.7 `BatchDelete` (AA/Services/BatchDelete.cs)

```
describe(repo, selection) -> Summary:                                                         // :51
    s = Summary()
    for item in topLevel(selection):
        if ItemLockService.isGated(item): s.Locked += 1; continue
        switch item:
          Equipment eq: s.Equipment += 1; s.Descendants += eq.Components.count
          TaskItem t:   s.Tasks += 1;     s.Descendants += descendants(t).count
          Procedure p:  s.Procedures += 1; s.Descendants += p.Steps.count
          Vessel:       s.Vessels += 1
        if hasAttachments(item): s.WithAttachments += 1
        if repo != nil && !repo.referencedBy(item).isEmpty: s.LinkedFromElsewhere += 1
    return s
trashAll(repo, selection) -> Int:                                                             // :85
    if repo == nil return 0
    picks = topLevel(selection).filter { !isGated($0) }
    return picks.isEmpty ? 0 : repo.trashHierarchyItems(picks)
removeAll<T>(owner, selection) -> Int:  doomed = distinct(selection of type T); count of owner.remove(x) successes
topLevel(selection):                                                                          // :111
    items = []; seen = Set()
    for o in selection: if let h = unwrap(o) as? HierarchyItem, seen.insert(h.Id).inserted: items.append(h)
    covered = Set(); for case let t as TaskItem in items: for d in descendants(t): covered.insert(d.Id)
    return items.filter { !covered.contains($0.Id) }
unwrap(o): o is HierarchyItem ? o : (o has property "Item" ? o.Item ?? o : o)
descendants(root): iterative DFS with a stack (push root.Subtasks, pop, skip already-seen ids, yield, push its Subtasks)
hasAttachments(item):
    Equipment: Container.Files nonEmpty || any component Container.Files nonEmpty
    TaskItem:  Container.Files nonEmpty || any descendant Container.Files nonEmpty
    Procedure: Container.Files nonEmpty || any step Container.Files nonEmpty
    Vessel:    Container.Files nonEmpty
Summary.kindBreakdown(): parts in order Tasks, Procedures, Equipment, Vessels:
    "{n} task{s}", "{n} procedure{s}", "{n} equipment/area" | "{n} equipment/areas", "{n} vessel{s}"
    return parts.isEmpty ? "nothing" : parts.joined(", ")
```
The `descendants` DFS yields in stack (LIFO) order; only its count and membership are used, so order is
irrelevant.

### 3.8 `SavedListOrder` (AA/Services/SavedListOrder.cs)

```
groupSpan(all, gid) = indices i where all[i].GroupId == gid (ascending)                       // :20
sameGroup(picks) -> (Bool, gid): picks non-empty and all picks share picks[0].GroupId          // :103

nudge(all, picks, up) -> Bool:                                                                 // :30
    guard sameGroup(picks) → gid; span = groupSpan(all, gid); guard span.count ≥ 2
    at = picks.map { span.firstIndex(of: all.firstIndex(of: $0)) }.compactMap.sorted()
    guard !at.isEmpty
    if up && at.first == 0: return false
    if !up && at.last == span.count − 1: return false
    for pos in (up ? at : at.reversed()): all.move(from: span[pos], to: span[up ? pos−1 : pos+1])
    return true
    // C#-exact; correct for single picks and for groups contiguous in `all`; see §8 D-1 for the fix.

moveTo(all, picks, target) -> Bool:                                                            // :49
    guard sameGroup(picks) → gid; span = groupSpan(all, gid); guard span.count ≥ 2
    moving = Set(picks); ordered = span.map { all[$0] }
    guard moving ⊆ Set(ordered)
    before = ordered[0 ..< clamp(target, 0, ordered.count)].count(where: moving.contains)
    remaining = ordered.filter { !moving.contains($0) }
    inOrder   = ordered.filter { moving.contains($0) }
    remaining.insert(contentsOf: inOrder, at: clamp(target − before, 0, remaining.count))
    for pos in 0 ..< span.count:
        from = all.firstIndex(of: remaining[pos])
        if from != span[pos]: all.move(from: from, to: span[pos])
    return true

groupEntries(data, gid) -> [(group: String?, template)]:                                       // :75
    name = gid == nil ? nil : data.ListGroups.first { $0.Id == gid }?.Name
    return data.ChecklistTemplates.filter { $0.GroupId == gid }.map { (isNilOrEmpty(name) ? nil : name, $0) }

allEntries(data) -> [(group: String?, template)]:                                              // :88
    nameFor(g) = g == nil ? "" : (data.ListGroups.first { $0.Id == g }?.Name ?? "")
    stableSort(data.ChecklistTemplates) by:
        key1 = t.GroupId == nil ? ⟨"\u{FFFF}"⟩ : nameFor(t.GroupId).lowercased(invariant)   // culture-sensitive compare
        key2 = index in ChecklistTemplates
    map { (t.GroupId == nil ? nil : nameFor(t.GroupId), t) }
```
`move(from:to:)` is `ObservableCollection.Move`: remove at `from`, insert at `to` (indices in the array as it
is *after* the removal).

Sort-key note: `"\u{FFFF}"` relies on ICU collation giving U+FFFF the highest weight; the Swift port MUST
instead sort "ungrouped" last explicitly, and compare group names with `localizedStandardCompare` or
`compare(_:options:[.caseInsensitive], locale: .current)` after lower-casing.

### 3.9 `ChecklistTemplateService` (AA/Services/ChecklistTemplateService.cs) — see REPO-140..146. Pseudo-code:

```
captureFromSteps(name, steps)    = Template(Name: name.trimmed, Items: steps.map { Item(Title: $0.Title, DurationMinutes: $0.DurationMinutes, IsJob: $0.IsJob, Container: cloneContainer($0.Container)) })
captureFromSubtasks(name, subs)  = Template(Name: name.trimmed, Items: subs.map { Item(Title: $0.Name, …same…) })
applyToSteps(t, target, replace)    { if replace target.removeAll(); for it in t.Items: target.append(Step(Title, Duration, IsJob, Container: clone)); return t.Items.count }
applyToSubtasks(t, target, replace) { if replace target.removeAll(); for it in t.Items: target.append(TaskItem(Name: it.Title, Duration, IsJob, Container: clone)); return t.Items.count }
clone(t, newName) = Template(Name: newName, GroupId: t.GroupId, Items: t.Items.map { Item(…, Container: clone) })   // new Id, CreatedUtc now
itemToTask(it)    = TaskItem(Name: it.Title, DurationMinutes, IsJob, Container: clone, Status: .Todo)
toSteps(t)        = t.Items.map { Step(Title, Duration, IsJob, Container: clone) }
writeBackFromSteps(t, steps) { t.Items.removeAll(); for s in steps: t.Items.append(Item(Title: s.Title, Duration, IsJob, Container: clone(s.Container))) }
cloneContainer(src?) = src == nil ? Container() : Container(Id: new, RichTextXaml: src.RichTextXaml, IsLocked: src.IsLocked,
                        Files: src.Files.map(cloneFile), SharedWithContainerIds: Array(src.SharedWithContainerIds))
cloneFile(f) = FileItem(Id: new, Name, Path, Kind, Added, IsLink, LinkInPlace, LinkedItemIds: Array(f.LinkedItemIds))
```

### 3.10 `ScheduleService` (AA/Services/ScheduleService.cs) — see REPO-150..154.

```
cloneEntry(e) = ScheduleEntry(Id: new, Title, Kind, RefId, Date, Time, EndDate, EndTime, Notes)   // Done = false
captureFromCrew(name, crew, data):
    t = ScheduleTemplate(Name: name.trimmed, VesselId: crew.ScheduleVesselId)
    t.VesselName = crew.ScheduleVesselId.flatMap { vid in data.Vessels.first { $0.Id == vid }?.Name } ?? ""
    t.Entries = crew.Schedule.map(cloneEntry)
applyToCrew(t, crew, replace): if replace crew.Schedule.removeAll(); crew.Schedule += t.Entries.map(cloneEntry)
                               if t.VesselId != nil: crew.ScheduleVesselId = t.VesselId; return t.Entries.count
exportJson(t, path): write json(t, indented: true, default options) to path (overwrite)
importJson(path): t = decode(ScheduleTemplate, file) ?? throw InvalidData("This file is not a valid schedule.")
                  t.Id = new; for e in t.Entries: e.Id = new; return t
```

### 3.11 Performance characteristics worth keeping

| Concern | C# behaviour | Port guidance |
|---|---|---|
| Per-keystroke cost | `MarkDirty` only restarts a timer (O(1)) | Same; never serialise on keystroke |
| Autosave | Serialize O(model) on UI thread every 750 ms of quiet; disk I/O off-thread | Same; encode on main actor, write on a serial background queue |
| `FindById` | Linear over ~all items | Linear is fine at AA scale; an id→object index MAY be added if invalidated on every collection mutation and it keeps "first match in Equipment/Task/Procedure/Vessel order" |
| `ReferencedBy` | O(items × steps) per call; `Describe` calls it per selected item | Acceptable; do not call per row while scrolling |
| Search | Off-UI-thread scan, streaming XML strip, 500-hit cap | Build a `Sendable` snapshot on the main actor, scan detached; MAY cache stripped text per `(container.Id, xaml.hashValue)` |
| Trash payload | Whole subtree serialised once at delete time | Same |
| Lists | Trash and Activity log lists virtualised | SwiftUI `Table`/`List` are lazy |

---

## 4. Data formats

### 4.1 Serializer settings (the compatibility contract)

`data.json` and every Trash payload are written by `System.Text.Json` with (DataStore.cs:267,
AppRepository.cs:323):

| Setting | Value | Consequence for the Swift port |
|---|---|---|
| Naming | Property names verbatim (**PascalCase**), no naming policy | Swift `CodingKeys` MUST use the exact C# names (`RelatedIds`, `ProcedureIds`, `RecurrenceSpawned`, …) |
| Case sensitivity on read | **Case-sensitive** (default) | Never emit camelCase |
| Enums | **Integers** (no string converter anywhere in the app) | Encode/decode raw `Int` values (tables in 4.6) |
| Nulls | `WhenWritingNull` — null properties are **omitted** | Use `encodeIfPresent`; treat a missing key as the C# default (4.5) |
| Indentation | none (compact) for `data.json` and payloads; **indented** for `.aasched.json` | Cosmetic |
| Cycles | `IgnoreCycles` (the model has none) | n/a |
| String escaping (write) | Default encoder: every non-ASCII char and `<`, `>`, `&`, `'`, `"`, `+`, `` ` `` are written as `\uXXXX` | Readers MUST accept escapes (any JSON parser does). The Swift writer MAY emit raw UTF-8 and SHOULD use `.withoutEscapingSlashes`; the Windows reader accepts both |
| Unknown members | Dropped on item types; preserved only at `AppData` / `UiState` / settings level (persistence spec) | Same — do not invent item-level extension data |
| Key order | Emitted in reflection order (derived-class members before base-class members, declaration order within a class). Readers do not depend on order **except** the `IsComplete`/`Status` interplay, which the load rule in REPO-040 normalises | The Swift encoder need not match the order; the decoder MUST apply REPO-040 |

### 4.2 `DateTime` encoding (per field)

Writer (`System.Text.Json`): ISO-8601 `yyyy-MM-ddTHH:mm:ss`, then a fractional part of up to 7 digits with
**trailing zeros trimmed** (omitted entirely when zero), then a suffix by Kind: `Z` for UTC, `±HH:mm` (the
machine's offset at that instant) for Local, nothing for Unspecified.
Reader: accepts ISO-8601 date-only (`2026-09-29`), minutes, seconds and fractions; `Z` → UTC; an offset →
converted to the reading machine's local time (Kind Local); no suffix → Unspecified (wall-clock kept).

| Field | Kind written | Example |
|---|---|---|
| `LogEntry.TimestampUtc` | UTC | `"2026-09-29T08:15:30.1234567Z"` |
| `TrashedItem.DeletedUtc` | UTC | `"2026-09-29T08:15:30.12Z"` |
| `ChecklistTemplate.CreatedUtc`, `ListGroup.CreatedUtc`, `ScheduleTemplate.CreatedUtc` | UTC | `"2026-07-08T10:00:00Z"` |
| `AppData.LastModified` | Local | `"2026-09-29T10:15:30.5+02:00"` |
| `TaskItem.Deadline`, `TaskItem.RangeStart`, `Procedure.Deadline`, `ChecklistStep.Deadline` | normally Unspecified midnight (date pickers, JSON round-trips, batch deadline) | `"2026-10-05T00:00:00"` |
| — deadline generated by recurrence when the source had **no** deadline | Local midnight (from `DateTime.Today`) | `"2026-09-30T00:00:00+02:00"` |
| `FileItem.Added` | Local | `"2026-09-29T10:15:30.1+02:00"` |

Swift model recommendation: a small value type (e.g. `DotNetDateTime`) holding the wall-clock components
(to 100 ns) plus `kind ∈ {unspecified, utc, local}`. Decode: `Z` → utc; offset → convert to the Mac's local
wall-clock, kind local (mirrors Windows); none → unspecified. Encode by kind as above. Day logic uses the
wall-clock date; comparisons use wall-clock ticks regardless of kind (as C# does). New deadlines produced by
the Mac SHOULD be written Unspecified (see §8 D-5).

### 4.3 GUIDs

Written lower-case "D" format (`3f2504e0-4f89-11d3-9a0c-0305e82c3301`). The Windows reader parses the 36-char D format
(hex case-insensitive); other GUID spellings are not guaranteed to load. Swift MUST write `uuid.uuidString.lowercased()` — Flash Sync and
diffs compare `Id` strings. `Guid.Empty` is written as `"00000000-0000-0000-0000-000000000000"` (it is not
null, so it is *not* omitted — e.g. `TrashedItem.BatchId` for a single delete).

### 4.4 JSON shapes touched by this subsystem

Only the members this subsystem reads or writes are listed; full model shapes live in the data-model spec.

**Top-level `AppData` keys used:** `Equipment`, `Tasks`, `Procedures`, `Vessels`, `Groups`, `Crew`, `Log`,
`ChecklistTemplates`, `ListGroups`, `ScheduleTemplates`, `Trash`, `Ui`, `LastModified`, `SchemaVersion`.

**Linking / relationship members:**

```jsonc
// on every HierarchyItem (Equipment, TaskItem, Procedure, Vessel — also nested subtasks)
"Id": "…", "Name": "…", "Description": "…", "Container": { … },
"RelatedIds": ["<guid>", …],            // two-way by convention (AddRelation writes both sides)
"Tags": ["SIRE", …],                    // stored WITHOUT a leading '#'
"GroupId": "<guid>",                    // omitted when ungrouped
"BucketIds": ["<guid>", …],
"LockHash": "…", "LockSalt": "…", "LockHint": "…"   // omitted when unlocked
// Equipment only
"ProcedureIds": ["<guid>", …], "TaskIds": ["<guid>", …], "Components": [ … ]
// Procedure.Steps[i] (ChecklistStep) and Crew[i].Checklist[j]
"TaskIds": ["<guid>", …], "EquipmentIds": ["<guid>", …]
// FileItem (inside any Container.Files)
"LinkedItemIds": ["<guid>", …]
```

**Completion / scheduling / recurrence members:**

```jsonc
// TaskItem (top-level and nested)
"Deadline": "2026-10-05T00:00:00", "RangeStart": "2026-10-01T00:00:00",   // omitted when null
"IsJob": false, "DurationMinutes": 60, "ScheduledStart": "…",              // ScheduledStart omitted when null
"Recurrence": 3, "RecurrenceSpawned": false, "IsComplete": false, "Status": 0, "Subtasks": [ … ]
// Procedure
"Steps": [ … ], "Deadline": "…", "Recurrence": 0, "RecurrenceSpawned": false, "Status": 0,
"IsJob": false, "DurationMinutes": 60, "ScheduledStart": "…"
// ChecklistStep
"Id": "…", "Title": "…", "BucketIds": [], "Done": false, "Deadline": "…", "IsJob": false,
"DurationMinutes": 60, "ScheduledStart": "…", "TaskIds": [], "EquipmentIds": [], "Container": { … }
```

**`Trash[i]` — `TrashedItem`:**

```json
{
  "Id": "8b0f2c55-2f7e-4a55-9d2b-4f6a2f0f7c11",
  "ItemType": "Task",
  "ItemId": "c1d7a0a2-7d7e-4f39-8a5d-0a4e5f2b9e10",
  "BatchId": "00000000-0000-0000-0000-000000000000",
  "Name": "Change fuel filter",
  "KindLabel": "Task",
  "DeletedUtc": "2026-09-29T08:15:30.1234567Z",
  "PayloadJson": "{\"Deadline\":\"2026-10-05T00:00:00\",\"IsJob\":false,\"DurationMinutes\":60,\"Recurrence\":0,\"RecurrenceSpawned\":false,\"IsComplete\":false,\"Status\":0,\"Subtasks\":[],\"Id\":\"c1d7a0a2-7d7e-4f39-8a5d-0a4e5f2b9e10\",\"Name\":\"Change fuel filter\",\"Description\":\"\",\"Container\":{\"Id\":\"…\",\"RichTextXaml\":\"\\u003CSection …\",\"Files\":[],\"SharedWithContainerIds\":[],\"IsLocked\":false},\"RelatedIds\":[],\"Tags\":[],\"BucketIds\":[]}"
}
```
* `ItemType` ∈ `"Equipment" | "Task" | "Procedure" | "Vessel" | "Crew"` — drives restore.
* `KindLabel` ∈ `"Equipment/Area" | "Task" | "Procedure" | "Vessel" | "Crew member"` — display + restore log.
* `PayloadJson` is a **string** containing the full compact JSON of the deleted object (runtime type: the
  Task's whole subtask tree, the Procedure's steps, the Equipment's components, the crew member's checklist and
  schedule), with the same key names/formats as in `data.json`. It is double-escaped inside `data.json`.
  The Swift port MUST read Windows payloads and MUST write payloads Windows can deserialize into the named
  type (same keys, enums as ints, GUID/date formats above).
* Entries are appended in deletion order; order is not otherwise meaningful.
* `BatchId` is `Guid.Empty` for single deletes and for entries written before batching existed.
* Display-only (not persisted): `DeletedLocal` = local `yyyy-MM-dd HH:mm`; `Display` =
  `"{Name or (unnamed)}   ·   {KindLabel}   ·   deleted {local yyyy-MM-dd HH:mm}"` (three spaces each side of
  each `·`; currently not bound anywhere — keep it for parity/debugging).

**`Log[i]` — `LogEntry`** (no `Id`; Flash Sync therefore ships `Log` as a whole block):

```json
{ "TimestampUtc": "2026-09-29T08:15:30.1234567Z", "Action": "Added", "Kind": "Task (recurring)",
  "Name": "Fire drill", "Detail": "next Monthly occurrence → 2026-10-31" }
```
Display-only: `TimeUtc` = `yyyy-MM-dd HH:mm:ss 'UTC'`, `TimeLocal` = local `yyyy-MM-dd HH:mm:ss`.

**`Groups[i]` — `ItemGroup`:** `{ "Id": "…", "Kind": 1, "Name": "Engine room", "Expanded": true }`
(`Kind` = `ItemKind` int; `Expanded` persisted, default `true`, unused by the UI).

**`ChecklistTemplates[i]` — `ChecklistTemplate` (array order = the user's arrangement):**

```json
{
  "Id": "…",
  "Name": "Daily rounds",
  "Items": [
    { "Title": "Check lube oil", "DurationMinutes": 15, "IsJob": true,
      "Container": { "Id": "…", "RichTextXaml": "…", "Files": [ { "Id": "…", "Name": "sop.pdf",
        "Path": "files/2f…_sop.pdf", "Kind": 0, "Added": "2026-09-01T09:00:00+02:00", "IsLink": false,
        "LinkInPlace": false, "LinkedItemIds": [] } ], "SharedWithContainerIds": [], "IsLocked": false } }
  ],
  "CreatedUtc": "2026-09-29T08:15:30Z",
  "GroupId": "…"
}
```
`ChecklistTemplateItem` has **no `Id`** (items are positional). `GroupId` omitted when ungrouped.
Display-only: `"{Name or (unnamed)}  ·  {n} item{s}"`.

**`ListGroups[i]` — `ListGroup`:** `{ "Id": "…", "Name": "Engine", "CreatedUtc": "…Z" }`.

**`ScheduleTemplates[i]` and `.aasched.json` — `ScheduleTemplate`:**

```json
{
  "Id": "5d1c…",
  "Name": "Rotation A",
  "VesselId": null,
  "VesselName": "",
  "Entries": [
    {
      "Id": "9a4e…",
      "Title": "Safety drill",
      "Kind": 1,
      "RefId": "c1d7a0a2-7d7e-4f39-8a5d-0a4e5f2b9e10",
      "Date": "2026-10-01",
      "Time": "09:00",
      "EndDate": "",
      "EndTime": "",
      "Done": false,
      "Notes": ""
    }
  ],
  "CreatedUtc": "2026-09-29T08:15:30.1234567Z"
}
```
* In `data.json` nulls are omitted (`VesselId`, `RefId` absent when null). In the exported `.aasched.json`
  (indented, default options) nulls **are** written as `null`, and non-ASCII is `\u`-escaped.
* `Date` is a string `yyyy-MM-dd`, `Time` `HH:mm`; `EndDate`/`EndTime` free strings (usually empty).
* `Kind` = `ScheduleKind` int; `RefId` = the linked Task/Procedure/Equipment id (nil for a Note).
* Import must accept both forms (with or without nulls, any key order, escaped or raw UTF-8).
* File name convention: `Schedule-{CrewFullName}.aasched.json` (double extension; `.json` is the real type).

**`Ui` members used here:** `LastDigestDate` (`"yyyy-MM-dd"` local, per-device, never synced),
`SortAZ` (dictionary; key `"savedlists"` for the Saved Lists tab, `"Equipment"|"Task"|"Procedure"|"Vessel"`
for the sidebars), `QuickViewPinIds` (list of guids; not scrubbed on delete).

### 4.5 Defaults for missing keys (decode rules)

`System.Text.Json` constructs the object with its C# initialisers and then overwrites only the keys present,
so a **missing key takes the C# default below**. The Swift decoder MUST reproduce these, because files from
older Windows builds and from iOS omit keys routinely.

| Type.member | Default when missing |
|---|---|
| `*.Id` (items, steps, containers, files, templates, groups, trash entries, schedule entries) | a **new random GUID** (not stable until the next save writes it back) |
| `HierarchyItem.Name` / `Description` | `""` |
| `HierarchyItem.Container` / `ChecklistStep.Container` / `ChecklistTemplateItem.Container` | new empty `Container` (new id) |
| `RelatedIds`, `Tags`, `BucketIds`, `ProcedureIds`, `TaskIds`, `EquipmentIds`, `LinkedItemIds`, `SharedWithContainerIds`, `Files`, `Subtasks`, `Steps`, `Components`, `Items`, `Entries` | empty |
| `DurationMinutes` (TaskItem, Procedure, ChecklistStep, ChecklistTemplateItem) | **60** |
| `Status` | `Todo` — then REPO-040: a legacy task with `IsComplete: true` and no `Status` becomes `Done` |
| `IsComplete`, `Done`, `IsJob`, `RecurrenceSpawned`, `IsLocked`, `IsLink`, `LinkInPlace` | false |
| `Recurrence` | `None` |
| `ItemGroup.Expanded` | true |
| `ChecklistTemplate.CreatedUtc`, `ListGroup.CreatedUtc`, `ScheduleTemplate.CreatedUtc`, `LogEntry.TimestampUtc`, `TrashedItem.DeletedUtc` | **now (UTC) at load time** (a Trash entry without `DeletedUtc` therefore restarts its 90-day clock on every load) |
| `FileItem.Added` | now (local) at load time |
| `FileItem.Kind` | `Document` (0) |
| `ScheduleEntry.Kind` | `Note` (0); strings `""` |
| `TrashedItem.BatchId` / `ItemId` | `Guid.Empty` |
| `HierarchyItem.BucketId` (legacy single bucket) | on read, appended to `BucketIds` if not present; never written |

An explicit JSON `null` for a non-optional collection/container is assigned as null by C# (and crashes some
paths); the Swift decoder SHOULD normalise such nulls to the default above (equivalent on the next save, since
C# omits nulls and would re-create the default on its next load).

### 4.6 Enum values (integers on the wire)

| Enum | Values |
|---|---|
| `ItemKind` | `Equipment = 0`, `Task = 1`, `Procedure = 2`, `Vessel = 3` |
| `WorkStatus` | `Todo = 0`, `InProgress = 1`, `Blocked = 2`, `Done = 3` |
| `RecurrenceKind` | `None = 0`, `Daily = 1`, `Weekly = 2`, `Monthly = 3`, `Yearly = 4` |
| `FileKind` | `Document = 0`, `Image = 1`, `Video = 2`, `Link = 3`, `Other = 4` |
| `ScheduleKind` | `Note = 0`, `Task = 1`, `Procedure = 2`, `Equipment = 3` |
| `SearchService.HitKind` (in-memory only) | `Item, Component, Subtask, Step, File` |

Enum **names** appear in user-visible text: `Label()` (`[Task] …`), the search/quick-switcher row headers,
the recurrence log detail (`next Monthly occurrence …`), the search `Where` for files (`File › Image`), and the
WPF combo boxes (`Todo`, `InProgress`, `Blocked`, `Done`; `None`, `Daily`, …).

### 4.7 Rich text (XAML) in this subsystem

This subsystem never renders or converts rich text:
* **Copied verbatim**: `Container.RichTextXaml` is copied byte-for-byte by `CloneContainer` (templates, apply,
  item→task, edit round-trip), by recurrence `DeepClone`, and inside Trash payloads. A legacy encrypted body
  (`"enc:" + base64`) is copied as-is.
* **Consumed for search** by `PlainTextFromXaml` (REPO-104): the WPF `TextRange.Save(DataFormats.Xaml)`
  shape — a single `<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
  xml:space="preserve" …>` root containing `Paragraph`, `List`/`ListItem`, `Table`/`TableRowGroup`/`TableRow`/
  `TableCell`, `Section`, `BlockUIContainer`, with inlines `Run`, `Span`, `Bold`, `Italic`, `Underline`,
  `Hyperlink`, `LineBreak`, `InlineUIContainer`. Only text nodes contribute text; `Paragraph`, `ListItem` and
  `LineBreak` element starts contribute a space; attributes (fonts, colours, `NavigateUri`) are ignored.
* Requirement on the Mac XAML writer (owned by the rich-text spec): keep `xml:space="preserve"` on the root
  and produce `Paragraph`/`ListItem`/`LineBreak` elements for block and line breaks, so that search text
  extracted on either platform is identical.

### 4.8 Cross-platform / cross-version rules

* **Flash Sync** (QR_SYNC_PROTOCOL.md): `Trash` entries carry `Id`, so they sync per item (a delete on one
  device appears in the other's Trash and can be restored there); `Log` has no `Id` and syncs as a whole block;
  `ChecklistTemplates` order is meaningful and is carried by the change set's `Order` map; `Ui.LastDigestDate`
  and `Ui.GroupExpanded` are per-device and never travel; `Ui.SortAZ` does travel (shared preference).
* **RecurrenceSpawned is part of the contract.** Both platforms MUST honour and set it, or a synced completed
  recurring item would be regenerated once per device. (Two devices completing the same occurrence before
  syncing will each spawn a copy with different ids — accepted limitation, same as Windows↔iOS today.)
* **Schema version**: this subsystem writes nothing new; `SchemaVersion` is raised to 1 on save by DataStore.
  The v0→v1 migration (REPO-064) MUST also run in the Mac loader for files with `SchemaVersion < 1`.
* **References to deleted items are allowed to dangle** while the item is in the Trash; readers MUST tolerate
  ids that resolve to nothing (render "(missing)" / skip).

### 4.9 Activity log CSV (export only)

```
TimestampUTC,LocalTime,Action,Kind,Name,Detail\r\n
2026-09-29 08:15:30 UTC,2026-09-29 10:15:30,Added,Task,Change fuel filter,\r\n
2026-09-29 08:16:02 UTC,2026-09-29 10:16:02,Removed,Task,"Pump, main",moved to Trash\r\n
```
UTF-8 without BOM; CRLF line ends; chronological; quoting only when the field contains `,` `"` or `\n`
(a bare `\r` does not trigger quoting).

---

## 5. Dependencies

### 5.1 What this subsystem calls

| Callee | Used for |
|---|---|
| `DataStore.SerializeForSave`, `DataStore.WriteData`, `DataStore.CurrentDataFile` | persistence (REPO-002/003) |
| `DataStore.MigrateSchema` (load path) | recurrence upgrade migration (REPO-064) |
| `ItemLockService.IsGated` | skip locked items in batch delete; search lock snapshot (by the window) |
| `System.Text.Json` | Trash payloads, deep clone, `.aasched.json` |
| `System.Xml.XmlReader`, `Regex` | search text extraction and snippets |
| `System.Windows.Threading.DispatcherTimer` | 750 ms debounce |
| `Task.Run` / thread pool | background writes; search scan (window) |

### 5.2 Who calls it (function → callers)

| Function | Callers |
|---|---|
| `MarkDirty`, `Save`, `FlushIfDirty`, `IsDirty` | virtually every view; MainWindow autosave/close |
| `Saved` event | MainWindow (`OnRepoSaved` → recurrence), FloatingTasksWindow (refresh) |
| `SuspendSaving`, `Detach` | MainWindow load/import/reload |
| `AllItems` | HierarchyPage (relationship picker), QuickSwitcherWindow, RelationshipMapPage, ContainerEditor ("Link to items…" candidates) |
| `FindById` | ItemWindow (re-resolve by id), QuickWorkWindow (pins), RelationshipMapPage, PdfExporter, ChecklistExporter |
| `AllJobs` | PlannerPage, FloatingTasksWindow |
| `Label` | HierarchyPage Equipment link lists |
| `RelatedItems` | HierarchyPage Relationships tab, RelationshipMapPage, PdfExporter |
| `ReferencedBy` | HierarchyPage backlinks, BatchDelete.Describe |
| `AddRelation` / `RemoveRelation` | HierarchyPage, SireToAa |
| `PurgeReferences` | Trash eviction/purge/empty, BoardPage.DeleteTask, QuickWorkWindow.DeleteItem |
| `LogAdded` / `LogRemoved` | see REPO-091 |
| `TrashHierarchyItems` | BatchDelete.TrashAll ← BatchDeleteMenu.Run ← HierarchyPage.DeleteItems |
| `TrashCrew` | CrewPage.Delete_Click |
| `RestoreTrash`, `PurgeTrash`, `EmptyTrash` | TrashWindow |
| `UndoLastDelete`, `PendingUndoCount` | MainWindow.UndoDelete (Ctrl+Z) |
| `PruneTrash`, `ReconcileRecurrences` | MainWindow startup; `ReconcileRecurrences` also after each save |
| `GroupsFor`, `CreateGroup`, `RenameGroup`, `DeleteGroup` | HierarchyPage sidebar |
| `SearchService.Search` | SearchWindow |
| `ReminderService.Compute` | MainWindow (`CheckReminders`, `ShowDailyDigestIfDue`) |
| `WorkRange.Coerce` | HierarchyPage task Specifics, SubtaskEditorWindow, QuickWorkWindow, BatchDeadline |
| `BatchDeadline.SetDeadlineAll` | BatchDeadlineMenu, QuickWorkWindow |
| `BatchDone.SetDone(All)` | BatchDoneMenu, QuickWorkWindow, FloatingTasksWindow |
| `BatchDelete.Describe/TrashAll` | BatchDeleteMenu |
| `SavedListOrder.*` | SavedListsPage |
| `ChecklistTemplateService.*` | ChecklistBuilderControl, SubtaskBuilderWindow, QuickWorkWindow, SavedListsPage, TemplateEditorWindow, SavedListPicker |
| `ScheduleService.*` | ScheduleBuilderControl |

### 5.3 Windows-only APIs in this area and their Mac replacements

| Windows API | Where | macOS replacement |
|---|---|---|
| `DispatcherTimer` | 750 ms debounce; 5-min autosave; 30-min reminders | `Task.sleep` debounce on `@MainActor`, or `DispatchSourceTimer` on the main queue; `Timer`/`Task` loops |
| `Task.Run` + `Task.Wait(15000)` | background write chain; blocking confirmed save | Serial `DispatchQueue` (FIFO) for writes; `DispatchWorkItem.wait(timeout:)` or `async throws` save |
| `System.Windows.Forms.NotifyIcon` balloons | tray reminders | `UNUserNotificationCenter` local notifications; optional `MenuBarExtra`; Dock badge |
| WPF `MessageBox` | every confirmation above | `NSAlert` (sheet) / SwiftUI `.alert` / `.confirmationDialog` with `.destructive` roles |
| `Microsoft.Win32.SaveFileDialog` / `OpenFileDialog` | CSV export, `.aasched.json` | `NSSavePanel` / `NSOpenPanel` or SwiftUI `.fileExporter` / `.fileImporter` |
| `Process.Start(UseShellExecute)` | open exported CSV | `NSWorkspace.shared.open(url)` |
| `Keyboard.FocusedElement is TextBoxBase/PasswordBox` | Ctrl+Z routing | responder chain: `NSText`/`NSTextView`/field editor as first responder handles `undo:` first |
| `ObservableCollection.Move` / `INotifyPropertyChanged` | model notifications | `@Observable` classes; `Array.move(fromOffsets:toOffset:)` |
| Reflection `GetProperty("Item")` (`BatchDelete.Unwrap`) | accept row wrappers | a protocol `ModelRow { var model: AnyObject { get } }` or pass models directly |
| `ListCollectionView` culture sort, U+FFFF sentinel | Saved Lists grouping | explicit comparator: ungrouped last, `localizedStandardCompare` |
| `System.Xml.XmlReader` | search text extraction | `XMLParser` with text coalescing (§3.2) |

---

## 6. macOS adaptation notes

### 6.1 Architecture (Swift 6.4, macOS 26)

* `@MainActor @Observable final class AppRepository` owning `var data: AppData`. Model types are
  `@Observable` **classes** (reference identity and in-place mutation are load-bearing: pickers, windows and
  lists all mutate the same objects). Mirror the C# hierarchy: `class HierarchyItem` (abstract) with
  `Equipment`, `TaskItem`, `Procedure`, `Vessel` subclasses; `kind` is computed, never encoded.
* `TaskItem.isComplete` / `status` must reproduce REPO-040 via `didSet`-style guarded setters (compare before
  assigning to avoid recursion), and the custom `init(from:)` applies the load rule.
* Keep every service in this spec as a **pure, testable** type (`enum BatchDone { static func setDone… }`, etc.)
  operating on the model, exactly as the C# does; views only confirm and refresh.
* Strict concurrency: nothing in the model is `Sendable`; background work (search, writes) receives
  `Sendable` snapshots (encoded `Data`, or value-type search documents) built on the main actor.

### 6.2 Persistence orchestration

* `markDirty()`: cancel the pending debounce `Task` and start a new one that sleeps 750 ms then calls
  `backgroundSaveIfDirty()`; guard with a `generation` counter so a cancelled/detached repository never
  writes.
* Write chain: one serial `DispatchQueue` per process (`label: "aa.data-writer"`); each work item writes the
  bytes it was given to the **URL captured at enqueue time** (fixes D-9) using temp-file + `rename(2)` +
  `fcntl(F_FULLFSYNC)` (persistence spec). FIFO order is guaranteed by the serial queue.
* `save()`: encode on main actor, enqueue, wait with a 15 s timeout (`DispatchWorkItem.wait(timeout:)`),
  restore `lastModified` and throw on timeout/failure, clear dirty and post `saved` only on success. On quit,
  `applicationShouldTerminate` returns `.terminateLater`, flushes editors, saves, pushes the shared bundle,
  then `reply(toApplicationShouldTerminate: true)`.
* `saved` as a Combine `PassthroughSubject<Void, Never>` or an `AsyncStream`; reconcile recurrences on each
  emission with the same re-entrancy and safe-mode guards.

### 6.3 Relationships and auto-linking

* Item inspector section **Relationships**: "Related" list (+ / − buttons, `link` SF Symbol) and a
  "Referenced By" list (`arrow.uturn.backward`), double-click or ⏎ opens the item (select in sidebar, switch
  tab). "Add Relationship…" = sheet with a searchable multi-select `List` sectioned by kind in the fixed order
  Equipment/Area, Tasks, Procedures, Vessels, names sorted case-insensitively.
* **Mac addition (non-breaking):** disable "Remove" (with help text "Linked from Specifics — change it there")
  for one-way Equipment rows instead of silently doing nothing; behaviour of the data is unchanged.
* Equipment Specifics link lists: `Table` rows showing `label(id)` ("(missing)" in secondary colour);
  "Pick…" = the same searchable multi-select sheet pre-selecting current links, replace semantics; "+ New
  Procedure/Task" = small name sheet → create at end, link, log, save.

### 6.4 Trash and undo

* **File ▸ Trash…** (⇧⌘⌫ is Finder's Empty Trash — do not reuse; no default shortcut needed) opens a window
  titled "Trash" with a SwiftUI `Table` (Name, Kind, Deleted — local `yyyy-MM-dd HH:mm`), multi-select,
  explanatory header text (REPO-078), and toolbar/footer buttons **Put Back** (Mac wording for "↩ Restore";
  keep the tooltip semantics), **Delete Immediately…** (Finder wording for "Delete permanently"), **Empty
  Trash…**, all destructive ones behind `NSAlert` with `hasDestructiveAction`. Messages keep the Windows text.
* Sidebar **⌘⌫ Move to Trash** (Mac addition: Finder's shortcut) and the context-menu item "Move to Trash…"
  both run the REPO-075 confirm-then-trash flow with the same prompt text; default button = Cancel
  (`keyEquivalent = "\r"` on Cancel, destructive red "Move to Trash").
* **⌘Z parity:** Windows' Ctrl+Z restores the newest Trash entry/batch **even after relaunch**. Implement as
  a responder in the main window's chain *after* text views (e.g. the root `NSViewController` or an
  `NSHostingView` subclass) that implements `undo(_:)` + `validateMenuItem`/`validateUserInterfaceItem`:
  if the first responder is a text view it never reaches us (text keeps its own undo); otherwise the Edit menu
  reads **"Undo Move to Trash"** (or "Undo Move to Trash (7 Items)" using `pendingUndoCount`) and invokes
  `undoLastDelete()`, refreshes, saves and shows the Windows status text. Do not rely solely on
  `UndoManager` (its stack is per-session).

### 6.5 Batch menus (done / deadline)

* SwiftUI `.contextMenu(forSelectionType:menu:primaryAction:)` on `Table`/`List` gives exactly REPO-043's
  right-click rule (acts on the selection when the clicked row is selected, else the clicked row).
* Items: "Mark as Done" (`checkmark.circle`) / "Mark as Not Done" (`circle`) and "Set Deadline…"
  (`calendar.badge.clock`). The deadline prompt becomes a popover/sheet with a graphical `DatePicker`, "Clear
  Deadline", "Cancel", "Set" (default); same prefill and "Pick a date…" validation (the Set button can simply be
  disabled until a date is chosen — same capability).
* Persist exactly as Windows: only when something changed, immediate save.

### 6.6 Search

* ⌘F opens the **Search** window (`Window("Search", id: "search")`, single instance, remembers size — Windows
  opens an additional window per invocation; a single reusable window is an accepted Mac refinement). The
  query field is focused; ⏎ runs; results in a `Table` (Where / Match). The match run is bold, black on
  `NSColor.findHighlightColor` (the system yellow) in both appearances — preserving the Windows "readable in
  dark mode" choice. Double-click/⏎ navigates.
* Scan: on ⏎, the main actor builds `[SearchDoc]` (owner id, owner header, locked flag, and the ordered list of
  `(kind, where, text, childId)` fields — with XAML already stripped, cached per container) and hands it to a
  detached task; cancel the previous task on a new query.
* **Shortcut conflict (open question Q-9):** in an editable note ⌘F conventionally opens the in-text find bar.
  Recommended: ⌘F = global search unless a rich-text editor is first responder (then the editor's find bar);
  ⇧⌘F = global search always.
* **Mac addition (optional):** reveal the matched child (select the subtask/step/component using `ChildId`).
* Quick switcher: ⌘O "Go to Item…" (mapped from Ctrl+O; AA has no document Open…), also ⇧⌘O alias. Panel
  styled like Spotlight (floating, `NSPanel`, `.ultraThinMaterial`), same scoring (REPO-107).

### 6.7 Reminders and digest

* Request notification authorisation lazily the first time something is due. Post one notification with a
  fixed identifier (`"aa.due-reminder"`, so a newer one replaces the older), title "AA — due soon", body =
  headline (+ crew suffix); tapping it opens the floating due-dates window (`UNUserNotificationCenterDelegate`);
  `willPresent` returns `.banner` so it shows while AA is frontmost (the Windows balloon always shows).
* Timers: every 30 min; also on `NSWorkspace.didWakeNotification` (Mac addition, harmless given the dedup key).
* Digest: at launch as on Windows; see Q-7 about also running at day rollover (`.NSCalendarDayChanged`).
* **Mac additions (optional, no capability change):** Dock badge = overdue count; a `MenuBarExtra` with the
  headline, "Open Due Dates…" and "Show AA" (replaces the tray double-click).

### 6.8 Activity log

`Window("Activity Log")` with `Table` (Time (UTC), Local Time, Action, Kind, Name, Detail), newest first,
`.searchable` filter (same four-field case-insensitive match), footer count text, toolbar "Export CSV…"
(`.fileExporter`, default name as Windows, CRLF, then `NSWorkspace.open`) and "Clear Log…" (destructive
alert). Snapshot on open / filter change, as Windows.

### 6.9 Saved lists arrangement

`List` with one `Section` per group (ungrouped last), `ForEach(...).onMove` **per section** (so a drag can
never cross a group boundary). Translate SwiftUI's `(IndexSet, toOffset)` directly into `moveTo(picks,
target: toOffset)` — the `before` adjustment in REPO-133 matches SwiftUI's "offset in the original array"
semantics. Keep ↑/↓ toolbar buttons (use the fixed nudge, §8 D-1), "Move to Position…", and add ⌥⌘↑/⌥⌘↓
(Mac addition). With "Sort A–Z" on, disable reordering and show the Windows message if invoked.

### 6.10 Schedule templates

`NSSavePanel` with `allowedContentTypes = [.json]` and `nameFieldStringValue = "Schedule-{name}.aasched.json"`;
`NSOpenPanel` accepting `.json`. Write with `JSONEncoder` `.prettyPrinted` (+ `.sortedKeys` NOT used — keep
declaration order for readability) and **write explicit `null`s** for `VesselId`/`RefId` to mirror Windows
(both forms are readable).

### 6.11 Things impossible or different on macOS

Nothing in this subsystem is impossible on macOS. Differences to note: tray *balloon* → notification banner
(needs user permission; if denied, fall back to the Dock badge + menu-bar extra, and the digest still opens the
due-dates window); Ctrl-key shortcuts → ⌘ equivalents (Ctrl+Z→⌘Z, Ctrl+F→⌘F, Ctrl+O→⌘O); Windows "Restore /
Delete permanently" wording MAY be shown as Finder's "Put Back / Delete Immediately…".

---

## 7. Test vectors (turn each into a Swift unit test)

Dates below are wall-clock dates (`2026-10-05` = Unspecified midnight) unless marked. "Today" is injected.

### 7.1 Relationships and lookups

| ID | Setup | Action | Expected |
|---|---|---|---|
| T-REL-1 | Task A, Task B | `addRelation(A, B)` twice | `A.RelatedIds == [B]`, `B.RelatedIds == [A]` (no duplicates) |
| T-REL-2 | A | `addRelation(A, A)` | unchanged |
| T-REL-3 | A↔B related | `removeRelation(A, B)` | both lists empty |
| T-REL-4 | Equipment E with `RelatedIds=[V]`, `ProcedureIds=[P]`, `TaskIds=[T, V]` | `relatedItems(E)` | `[V, P, T]` (V once, order preserved) |
| T-REL-5 | Procedure P with step s (`TaskIds=[T]`) | `relatedItems(P)` | `[]` — step links are not relations |
| T-REL-6 | E.TaskIds=[T]; P.step.TaskIds=[T]; X.RelatedIds=[T] | `referencedBy(T)` | `[E, P, X]` in `AllItems` order (Equipment, Task, Procedure, Vessel); `relatedItems(T) == []` |
| T-REL-7 | E.ProcedureIds=[P]; P trashed | `label(P.Id)` | `"(missing)"`; `relatedItems(E) == []` |
| T-REL-8 | Task T (`Kind` Task, Name "Pump") | `label(T.Id)` | `"[Task] Pump"` |
| T-REL-9 | E.RelatedIds=[D], E.ProcedureIds=[D], P.step.EquipmentIds=[D], file in a crew-step container `LinkedItemIds=[D]`, nested subtask S.RelatedIds=[D] | `purgeReferences(D)` | all removed **except** `S.RelatedIds` (nested subtasks not scrubbed) |
| T-REL-10 | Duplicate id in two collections (Equipment and Task share id Z) | `findById(Z)` | the Equipment |
| T-REL-11 | `allJobs` over: Task T(IsJob) with subtask S(IsJob) with sub-subtask SS(not job); Procedure P(not job) with steps s1(job), s2(not); crew c with step cs(job) | `allJobs()` | `[T, S, s1, cs]` |

### 7.2 Status sync and batch done

| ID | Input | Expected |
|---|---|---|
| T-DONE-1 | Task `IsComplete=false, Status=InProgress`; `setDone(t, true)` | returns true; `IsComplete=true, Status=Done` |
| T-DONE-2 | Task `IsComplete=false, Status=Blocked`; `setDone(t, false)` | false; still Blocked |
| T-DONE-3 | Task complete (Done); `setDone(t, false)` | true; `IsComplete=false, Status=Todo` |
| T-DONE-4 | Task; set `Status = InProgress` on a completed task | `IsComplete=false` |
| T-DONE-5 | Procedure `Status=InProgress`; `setDone(p, false)` | false; InProgress |
| T-DONE-6 | Procedure `Status=Done`; `setDone(p, false)` | true; Todo |
| T-DONE-7 | Procedure `Status=Blocked`; `setDone(p, true)` | true; Done |
| T-DONE-8 | Step `Done=true`; `setDone(s, true)` | false |
| T-DONE-9 | `setDoneAll([incompleteTask, doneStep, doneProc, "x", nil], true)` | 1 |
| T-DONE-10 | Decode `{"IsComplete":true}` (no Status) | `Status=Done`, complete |
| T-DONE-11 | Decode `{"IsComplete":true,"Status":1}` | `Status=InProgress`, `IsComplete=false` (Status wins) |
| T-DONE-12 | Decode `{"Status":3,"IsComplete":false}` (reverse key order, e.g. a foreign writer) | Swift: `Status=Done`, `IsComplete=true` (Status wins). Windows would yield Todo/false here (document order) — see D-21 |
| T-DONE-13 | Decode `{"Status":0}` | `IsComplete=false`, Todo |

### 7.3 Working range and batch deadline

| ID | Input | Expected |
|---|---|---|
| T-RNG-1 | `coerce(nil, nil, *)` | `(nil, nil)` |
| T-RNG-2 | `coerce(nil, 2026-10-05, *)` | `(nil, 2026-10-05)` |
| T-RNG-3 | `coerce(2026-10-01, nil, *)` | `(2026-10-01, 2026-10-01)` |
| T-RNG-4 | `coerce(2026-10-01, 2026-10-05, *)` | unchanged |
| T-RNG-5 | `coerce(2026-10-07, 2026-10-05, editedStart: true)` | `(2026-10-07, 2026-10-07)` |
| T-RNG-6 | `coerce(2026-10-07, 2026-10-05, editedStart: false)` | `(2026-10-05, 2026-10-05)` |
| T-RNG-7 | `coerce(2026-10-01 15:30, 2026-10-05 08:00, *)` | `(2026-10-01 00:00, 2026-10-05 00:00)` |
| T-RNG-8 | Task start 10-01, deadline 10-05: `HasRange`, `RangeFirst`, `WhenText`, `CoversDay(10-03)`, `CoversDay(10-06)` | true, 10-01, `"2026-10-01 → 2026-10-05"`, true, false |
| T-RNG-9 | Task start 10-07, deadline 10-05 (out of order, hand-edited file): `CoversDay(10-05)`, `CoversDay(10-06)`, `HasRange`, `WhenText` | true, false, false, `"2026-10-05"` |
| T-DL-1 | Task (nil, nil); `setDeadline(t, nil)` | false |
| T-DL-2 | Task start 10-01, deadline 10-05; `setDeadline(t, nil)` | true; both nil |
| T-DL-3 | same; `setDeadline(t, 10-03)` | true; start 10-01, deadline 10-03 |
| T-DL-4 | same; `setDeadline(t, 09-28)` | true; start **09-28**, deadline 09-28 (start clamped, not cleared) |
| T-DL-5 | Task deadline 10-05 00:00; `setDeadline(t, 10-05 14:00)` | false |
| T-DL-6 | Procedure deadline 10-05; `setDeadline(p, 10-05)` / `(p, nil)` | false / true (cleared) |
| T-DL-7 | `setDeadline(equipment, 10-05)` / `(nil, 10-05)` | false / false |
| T-DL-8 | Local-kind deadline 10-05 vs Unspecified 10-05 | considered equal → false |

### 7.4 Recurrence

| ID | Input (today = 2026-09-29 local) | Expected |
|---|---|---|
| T-REC-1 | `nextOccurrence(2026-01-31, Monthly)` | 2026-02-28 |
| T-REC-2 | `nextOccurrence(2024-02-29, Yearly)` | 2025-02-28 |
| T-REC-3 | `nextOccurrence(2026-12-31, Daily)` / `(2026-09-29, Weekly)` / `(x, None)` | 2027-01-01 / 2026-10-06 / x |
| T-REC-4 | `nextOccurrence(2026-03-31 09:30, Monthly)` | 2026-04-30 09:30 (time kept) |
| T-REC-5 | Task "Fire drill", Monthly, Deadline 2026-01-31, RangeStart 2026-01-29, complete, not spawned; subtask S (complete) deadline 2026-01-30, RangeStart 2026-01-28; subtask U (InProgress, incomplete) | returns true. Source: `RecurrenceSpawned=true`, unchanged otherwise. New task appended: new Id, new Container.Id, same FileItem ids, Deadline 2026-02-28, RangeStart 2026-02-26, `IsComplete=false`, Todo, `RecurrenceSpawned=false`, `ScheduledStart=nil`; S′: new id, deadline 2026-02-27, RangeStart 2026-02-25, Todo; U′: new id, **InProgress** kept. Log: `Added / "Task (recurring)" / "Fire drill" / "next Monthly occurrence → 2026-02-28"` |
| T-REC-6 | Run reconcile again | returns false, no new tasks |
| T-REC-7 | Daily task, complete, no deadline, subtask with deadline 2026-09-01 | clone Deadline 2026-09-30 (Windows writes it Local-kind); subtask deadline **unchanged** (no shift without a source deadline); RangeStart nil |
| T-REC-8 | Task with RangeStart == Deadline (10-05/10-05), Weekly, complete | clone RangeStart **nil**, Deadline 10-12 |
| T-REC-9 | Procedure "Weekly checks", Weekly, Deadline 2026-09-28, Status Done; step1 Done, deadline 2026-09-27, TaskIds [T]; step2 no deadline | clone: Status Todo, Deadline 2026-10-05, step1′ new id, Done=false, deadline 2026-10-04, TaskIds [T]; step2′ no deadline. Log detail `"next Weekly occurrence → 2026-10-05"` |
| T-REC-10 | Recurring task, complete, **already** spawned | nothing |
| T-REC-11 | Recurring task, IsComplete false | nothing |
| T-REC-12 | Recurring **subtask** complete inside a non-complete parent | nothing (only top-level tasks recur) |
| T-REC-13 | Clone relation symmetry: source.RelatedIds=[X], X.RelatedIds=[source] | clone.RelatedIds=[X]; X.RelatedIds unchanged ([source]); `referencedBy(X)` includes the clone |
| T-REC-14 | E.TaskIds=[source]; pins=[source] | after spawn E.TaskIds and pins still `[source]` only |
| T-REC-15 | Load a file with `SchemaVersion` 0 containing a complete Monthly task (and a complete Weekly subtask) with `RecurrenceSpawned` absent | after load both have `RecurrenceSpawned=true`; reconcile → false |

### 7.5 Trash and undo

| ID | Setup | Action | Expected |
|---|---|---|---|
| T-TR-1 | Task T (id X) related to E both ways, E.TaskIds=[X] | `trashHierarchyItem(T)` | T gone from Tasks; one entry `{ItemType "Task", ItemId X, KindLabel "Task", BatchId empty, Name T.Name}`; payload decodes to an equal task tree; E.RelatedIds and E.TaskIds **still contain X**; log `Removed / Task / {name} / moved to Trash`; dirty |
| T-TR-2 | T-TR-1 then `restoreTrash(entry)` | returns `"Task"`; Tasks gains a task with id X at the **end**; entry removed; log `Added / Task / {name} / restored from Trash`; `relatedItems(E)` includes it again |
| T-TR-3 | Entry whose `ItemId` already exists live | `restoreTrash` | returns the type; **not** added again; entry removed |
| T-TR-4 | Entry with `PayloadJson = "{"` | `restoreTrash` | nil; entry kept |
| T-TR-5 | Entry with `ItemType "Widget"` | `restoreTrash` | nil |
| T-TR-6 | `trashHierarchyItems([A, B, C])` (tasks) | | returns 3; three entries sharing one non-empty BatchId |
| T-TR-7 | Trash: a(t=1, single), b(t=2, batch K), c(t=3, batch K) | `pendingUndoCount()` then `undoLastDelete()` | 2; restores c then b (appended in that order); a stays; returns `["Task"]` (or the distinct types) |
| T-TR-8 | Trash: a(t=5, single), b(t=3, batch K) | undo | restores only a |
| T-TR-9 | Mixed batch: Equipment + Task + Procedure | undo | returns 3 distinct types in restore order |
| T-TR-10 | Empty Trash | undo | `[]`; UI "Nothing to undo." |
| T-TR-11 | Entry DeletedUtc = now − 91 days, E.RelatedIds contains its ItemId | `pruneTrash()` | entry evicted; E.RelatedIds scrubbed; dirty |
| T-TR-12 | 200 entries, add one more | | 200 remain; the oldest by `DeletedUtc` evicted and its references purged |
| T-TR-13 | Entry DeletedUtc = now − 89 days | prune | kept; not dirty |
| T-TR-14 | Crew m (First "Jan", Middle "", Last "Kowalski") | `trashCrew(m)` | Name "Jan Kowalski", KindLabel "Crew member", ItemType "Crew"; restore → appended to `Crew` |
| T-TR-15 | Crew with all names blank except Last "" | trashCrew | Name "" (Trash window shows empty; `Display` would show "(unnamed)") |
| T-TR-16 | `purgeTrash(e)` / `emptyTrash()` | | references to the ItemIds scrubbed; entries gone; dirty; `emptyTrash` on empty → not dirty |

### 7.6 Batch delete description

Setup: Task A with subtasks S1 (with sub-subtask S1a carrying 1 file) and S2; Procedure P with 3 steps,
referenced by Equipment X via `ProcedureIds`; Equipment L password-locked and gated; Vessel V whose container
has 1 file. Selection (as given by a list): `[A, S1, P, L, V, A]`.

| Field | Expected |
|---|---|
| Tasks / Procedures / Equipment / Vessels | 1 / 1 / 0 / 1 (S1 dropped as a descendant of A; duplicate A dropped) |
| Locked | 1 |
| Descendants | 3 (S1, S1a, S2) + 3 steps = **6** |
| WithAttachments | 2 (A via S1a; V) |
| LinkedFromElsewhere | 1 (P ← X) |
| Total / IsEmpty | 3 / false |
| KindBreakdown | `"1 task, 1 procedure, 1 vessel"` |

Prompt (Trash currently holds 199 entries):
```
Move 3 items to the Trash?

    1 task, 1 procedure, 1 vessel
    6 subtask/step/components inside them will be deleted too.
    2 of them have attached files (the files stay on disk).
    1 is linked from other items; those links show "(missing)" until the Trash is emptied.
    1 locked item is selected and will be skipped.
    Note: the Trash holds 200 items, so the 2 oldest will be permanently removed.

You can restore them from File ▸ Trash, or undo with Ctrl+Z.
```
`trashAll` → 3 entries with one BatchId (L untouched). Other cases: selection `[]` → IsEmpty ("Select one or
more items first."); `[L]` → Total 0, Locked 1 ("That item is locked. Unlock it before deleting it.");
`[L, L2]` both locked → "All 2 selected items are locked. Unlock them before deleting."; single Equipment
with 1 component → `"1 equipment/area"` and `"    1 subtask/step/component inside them will be deleted too."`.
Cycle guard: a task whose subtask list contains itself (malformed) → `describe` terminates.

### 7.7 Search

Data: Equipment "Main Engine" (Tags `["engine","ME"]`, component "Fuel pump" with Notes "check every 500 h"),
Task "Replace the fuel filter on the main engine" (subtask "Drain water", container text "Open the drain cock"),
Procedure "Bunkering" (step "Sample fuel"), Vessel "Aurora". Query `"FUEL"` (no locks):

| # | Owner | Where | Snippet | MatchStart | MatchLength |
|---|---|---|---|---|---|
| 1 | Main Engine | `Component › Name` | `Fuel pump` | 0 | 4 |
| 2 | Replace the fuel filter… | `Name` | `Replace the fuel filter on the main engine` | 12 | 4 |
| 3 | Bunkering | `Step › Title` | `Sample fuel` | 7 | 4 |

Query `"engine"` → Main Engine `Name` (5), Main Engine `Tags` (snippet `engine, ME`, 0), task `Name` (36).
With Main Engine locked (gated): `"FUEL"` drops hit #1; `"ME"` still matches its `Tags`. Query `"   "` → no
hits. 501 matching items → exactly 500 hits.

Snippets (`makeSnippet` via a search of one field):

| Text | Query | Snippet | Start |
|---|---|---|---|
| `"a"×100 + "needle" + "b"×100` | needle | `"…" + "a"×60 + "needle" + "b"×60 + "…"` (128 chars) | 61 |
| `"Line one\r\n\r\n   target here"` | target | `"Line one target here"` | 9 |
| `"one  two three"` | `one  two` | `"one two three"` | 0 (fallback), length 8 |
| `"x"×70 + "  \n\t  KEY " + "y"×10` | key | `"…" + "x"×54 + " KEY " + "y"×10` | 56 |
| `"Check " + "z"×55 + " pump pump"` | PUMP | `"…eck " + "z"×55 + " pump pump"` | 61 (first occurrence) |

`plainTextFromXaml` (`NS` = `xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve"`):

| Input | Output (· = space) |
|---|---|
| `nil` / `""` | `""` |
| `<Section NS><Paragraph><Run>Hello</Run></Paragraph><Paragraph><Run>World</Run></Paragraph></Section>` | `·Hello··World·` |
| `<Section NS><Paragraph><Run>A</Run><LineBreak /><Run>B</Run></Paragraph></Section>` | `·A··B·` |
| `<Section NS><List><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two</Run></Paragraph></ListItem></List></Section>` | `··One···Two·` |
| `<Section NS><Paragraph><Run>Fish &amp; chips</Run></Paragraph></Section>` | `·Fish & chips·` |
| `<Section NS><Paragraph><Run> </Run></Paragraph></Section>` | `···` (significant whitespace kept) |
| `enc:QUJD` | `enc:QUJD` (fallback, unchanged) |
| `<Paragraph><Run>Hi</Run>` (unclosed) | `··Hi·` (fallback: each tag → one space) |
| `<Run>a</Run><Run>b</Run>` (two roots) | `·a··b·` (fallback) |

### 7.8 Reminders

Today 2026-09-29. Tasks: T1 deadline 09-28 incomplete; T1's subtask S1 deadline 09-29 incomplete; T2
deadline 10-06 incomplete; T3 deadline 10-07; T4 deadline 09-20 **complete**; T5 range 09-25→10-02
incomplete. Procedures: P1 InProgress deadline 09-29 with step deadline 09-30 not done; P2 **Done** deadline
09-01 with a step deadline 09-02 not done. Crew step deadline 09-29 **done**.

`compute` → Overdue **2** (T1, P2-step), DueToday **2** (S1, P1), DueWeek **3** (T2, P1-step, T5 by its
deadline 10-02) → headline `"2 overdue  ·  2 due today  ·  3 due this week"`; key
`"2026-09-29|2|2|3|{crew}"`. All zero → `"Nothing due."`. Only week items → `"1 due this week"`.

Digest: `LastDigestDate == "2026-09-29"` → nothing; otherwise set to `"2026-09-29"` and mark dirty even when
nothing is due.

### 7.9 Saved list order

Notation: letters are lists; `(g)`/`(h)` the group; `·` ungrouped. **Assert per-group subsequences**, not
flat positions (flat positions of other groups' lists are not observable in the UI or the export).

| ID | `all` | Call | Returns | Group-order after |
|---|---|---|---|---|
| T-ORD-1 | A B C (g) | `nudge([B, C], up)` | true | g: B C A |
| T-ORD-2 | A B C (g) | `nudge([A], up)` / `nudge([C], down)` | false / false | unchanged |
| T-ORD-3 | A(g) X(h) | `nudge([A, X], up)` | false (different groups) | — |
| T-ORD-4 | A(g) | `nudge([A], down)` | false (group of one) | — |
| T-ORD-5 | A(g) X(h) B(g) | `nudge([B], up)` | true | g: B A; h: X |
| T-ORD-6 | A(g) X(h) B(g) C(g) | `nudge([B, C], up)` | true | **intended g: B C A** (C# yields B A C — defect D-1) |
| T-ORD-7 | A(g) B(g) X(h) C(g) | `nudge([A, B], down)` | true | **intended g: C A B** (C# yields A C B — defect D-1) |
| T-ORD-8 | A(g) X(h) B(g) | `moveTo([B], 0)` | true | g: B A (C# flat: B X A) |
| T-ORD-9 | A B C D (g) | `moveTo([A, C], 4)` | true | B D A C |
| T-ORD-10 | A B C D (g) | `moveTo([D], 1)` | true | A D B C |
| T-ORD-11 | A B C D (g) | `moveTo([B], 2)` | true | unchanged A B C D |
| T-ORD-12 | A B C (g) | `moveTo([A], 99)` | true | B C A |
| T-ORD-13 | any | `moveTo([], 0)` / picks not in group | false | — |
| T-ORD-14 | Templates T1(g2 "Beta"), T2(·), T3(g1 "alpha"), T4(g2), T5(g1) | `allEntries` | | `[("alpha",T3), ("alpha",T5), ("Beta",T1), ("Beta",T4), (nil,T2)]` |
| T-ORD-15 | + T6 with a dangling GroupId | `allEntries` | | `("",T6)` sorts **first** |
| T-ORD-16 | g1 named "" | `groupEntries(g1)` | | group component nil for each entry |
| T-ORD-17 | save → reload | | | collection order identical (order round-trips through JSON) |

### 7.10 Checklist templates

| ID | Input | Expected |
|---|---|---|
| T-TPL-1 | `captureFromSteps("  Daily rounds ", [step("Check oil", 15 min, job, Done, deadline, TaskIds [T], container{xaml X, files [f1]})])` | Name "Daily rounds", GroupId nil, 1 item: Title "Check oil", 15, IsJob true, container: **new** id, xaml X, same IsLocked, 1 file with **new** Id and the same Name/Path/Kind/Added/IsLink/LinkInPlace/LinkedItemIds; no deadline/done/links anywhere |
| T-TPL-2 | `captureFromSubtasks("L", [S1 (with nested S1a, Description "d")])` | 1 item "S1"; S1a and "d" dropped |
| T-TPL-3 | `applyToSteps(tpl(2 items), target [s0], replace: false)` | returns 2; target `[s0, n1, n2]`; n1/n2 new ids, `Done=false`, no deadline, containers are fresh clones (mutating n1's xaml doesn't touch the template) |
| T-TPL-4 | `applyToSubtasks(tpl, target [x, y], replace: true)` | returns count; target contains only the new tasks (Todo) |
| T-TPL-5 | `clone(t in group G, "L (copy)")` | new Id, same GroupId, new CreatedUtc, deep copies |
| T-TPL-6 | `itemToTask(item)` | TaskItem Name=Title, same duration/job flag, cloned container, Todo, no deadline |
| T-TPL-7 | `toSteps` then edit a step's title + deadline, `writeBackFromSteps` | titles updated; deadline dropped; item containers have new ids |
| T-TPL-8 | `cloneContainer(nil)` | fresh empty container |
| T-TPL-9 | `cloneContainer(c)` where `c.IsLocked = true`, xaml `"enc:QUJD"` | `IsLocked` true, xaml copied verbatim |

### 7.11 Schedule templates

| ID | Input | Expected |
|---|---|---|
| T-SCH-1 | Crew with 2 entries (one `Done=true`), ScheduleVesselId = vessel "Aurora" | `captureFromCrew(" Rota ", …)`: Name "Rota", VesselId = Aurora.Id, VesselName "Aurora", 2 entries with new ids, all `Done=false`, RefIds kept |
| T-SCH-2 | ScheduleVesselId = id not in `Vessels` | VesselName `""` |
| T-SCH-3 | `applyToCrew(t with VesselId nil, crew with vessel V, replace: false)` | entries appended; crew vessel still V; returns count |
| T-SCH-4 | `applyToCrew(t with VesselId W, crew, replace: true)` | schedule = clones only; crew vessel = W |
| T-SCH-5 | Export then import the same file | imported: new template Id, new entry ids, same Name/VesselId/VesselName/CreatedUtc/entry fields |
| T-SCH-6 | Import file content `null` | error "This file is not a valid schedule." |
| T-SCH-7 | Import a Windows-written file with `é` escapes and explicit nulls | decodes (`"Café"`); nil VesselId/RefId |
| T-SCH-8 | Swift-written export read by the Windows importer | keys PascalCase, Kind as int, GUIDs lower-case D, CreatedUtc ISO with `Z` |

### 7.12 Activity log

| ID | Input | Expected |
|---|---|---|
| T-LOG-1 | `logAdded("Task", "  Pump  ")` | Name "Pump", Detail "", Action "Added", TimestampUtc UTC |
| T-LOG-2 | `logRemoved("Task", "   ")` | Name "(unnamed)" |
| T-LOG-3 | 10 000 entries + 1 | count 10 000; the first (oldest) removed |
| T-LOG-4 | CSV of entry Name `Pump, main`, Detail `say "hi"` | `…,"Pump, main","say ""hi"""` + CRLF |
| T-LOG-5 | `TimeUtc` of 2026-09-29T08:15:30Z | `"2026-09-29 08:15:30 UTC"` |

### 7.13 Groups

| ID | Input | Expected |
|---|---|---|
| T-GRP-1 | `createGroup(.Task, "  ")` | Name "New group", Kind Task |
| T-GRP-2 | `renameGroup(g, "")` | unchanged |
| T-GRP-3 | Equipment e and Task t both with GroupId g (malformed cross-kind) | `deleteGroup(g)` ungroups **both** |

### 7.14 Quick switcher scoring

| Item | Query | Score |
|---|---|---|
| Name "Main Engine", tags ["engine"] | `eng` | name contains (not prefix) 60 + tag prefix 45 = **105** |
| Name "Equipment Pump" (Equipment) | `eqpump` | subsequence 25 + KindLabel "Equipment/Area" contains? no → **25** |
| Name "Pump" | `#pu` | query becomes `pu`; prefix → **120** |
| Anything | `` (empty) | 1 (all items listed, ordered by name) |

---

## 8. Known defects, recommended deviations, open questions

Each item states the Windows behaviour (what "parity" means), the recommendation, and whether it affects
data compatibility (none of them do, unless stated).

* **D-1 — `SavedListOrder.Nudge` mis-orders multi-selections in interleaved groups.** When the selected lists'
  group is not contiguous in `ChecklistTemplates` (normal after "Move to group…", which never moves the list in
  the array) and more than one list is selected, the per-pick `Move` uses stale slot indices (T-ORD-6/7).
  Single picks and contiguous groups are correct. **Recommendation:** implement nudge as "compute the intended
  group order by swapping each pick with its group neighbour (ascending for up, descending for down), then
  re-anchor exactly like `MoveTo`'s final loop". Verified by simulation (0 failures in 4 448 random cases).
  Data-compatible (any permutation is valid data).
* **D-2 — `TrashHierarchyItem` ignores whether removal succeeded.** Passing a nested subtask creates a Trash
  entry (and a "moved to Trash" log line) while the subtask stays in place; restoring it would then add a
  duplicate **top-level** task. Unreachable from the current UI (only top-level lists feed it).
  **Recommendation:** return nil and do nothing if the item was not found in its top-level collection.
* **D-3 — Reference scrubbing is partial.** `PurgeReferences` removes only the **first** occurrence and skips
  nested subtasks' `RelatedIds`, crew-step links, crew `ScheduleEntry.RefId`, `QuickViewPinIds`, `Ui.*Id`.
  **Recommendation:** remove *all* occurrences within the same scope (strict superset, safe); keep the scope
  unchanged unless the product owner agrees to widen it (Q-3).
* **D-4 — Recurrence clones are not re-linked.** The new occurrence is not added to `Equipment.TaskIds /
  ProcedureIds`, step `TaskIds` or pins; its `RelatedIds` are one-directional; file-entry ids are duplicated
  between the source and the clone; incomplete subtasks keep `InProgress/Blocked`. **Recommendation:** parity
  (replicate exactly) — both platforms reconcile the same shared data, and divergent spawn behaviour would be
  visible to users switching machines. Improvement is a product decision (Q-2).
* **D-5 — Recurrence without a deadline writes a Local-kind date.** `DateTime.Today` produces
  `"…T00:00:00+02:00"`, which a machine in another time zone reads as the previous/next wall-clock day.
  **Recommendation:** the Mac writes new deadlines as Unspecified midnight; on read it treats offset values like
  Windows does. Compatible both ways.
* **D-6 — Hard deletes bypass the Trash** (Board card delete, Ctrl+N delete, subtask/step/component removal,
  crew Clear all, template "replace"). **Recommendation:** parity for v1 (Q-4); if changed, route Board/Ctrl+N
  top-level deletes through `trashHierarchyItems` — data-compatible.
* **D-7 — Undo is Trash-driven, not session-driven.** Keep it (Ctrl+Z after relaunch restores the newest
  Trash entry). See §6.4 for the ⌘Z responder design.
* **D-8 — Digest only at launch.** Mac apps stay open for days; consider also running the digest on
  `NSCalendarDayChanged` (Q-7). `LastDigestDate` keeps it once per day either way.
* **D-9 — Queued writes resolve the target path at write time.** After a reload/import switches
  `CurrentDataFile`, a still-queued write from the detached repository could land in the new file.
  **Recommendation:** capture the URL at enqueue and drop writes whose repository generation is stale.
* **D-10 — Restore appends, batches restore newest-first.** A restored item goes to the end of its collection;
  a batch comes back in reverse deletion order. Parity (the order is only visible when the sidebar isn't
  sorted A→Z).
* **D-11 — Restore of an id that already exists silently consumes the Trash entry.** Parity; MAY show "An item
  with this id already exists — kept the current one." (Mac addition).
* **D-12 — `AllEntries` edge cases.** A dangling group id sorts first with group `""`; two groups with the same
  (case-insensitive) name merge into one PDF heading. Parity; low impact.
* **D-13 — Search text joins paragraphs with two spaces**, so a phrase across a paragraph break never matches.
  Parity (both platforms must extract identically).
* **D-14 — Culture-sensitive sorts and the U+FFFF sentinel.** Implement "ungrouped last" explicitly and use
  `localizedStandardCompare` for names (Windows uses the current culture); identical for ordinary names.
* **D-15 — `Save()` can block the UI up to 15 s.** Keep the timeout; on the Mac show a progress HUD if a save
  takes > 0.5 s (Mac addition).
* **D-16 — The Trash-cap warning ignores age pruning** (it may over-state how many will be removed). Parity.
* **D-17 — `WriteBackFromSteps` always rewrites** (new container/file ids on every "Edit items" close), creating
  sync churn. **Recommendation:** skip the write-back when nothing changed (compare titles, durations, job
  flags and containers by content) — compatible.
* **D-18 — `CaptureFromSubtasks` flattens to direct children** and drops descriptions. Parity (templates have
  no nesting on either platform).
* **D-19 — The 5-minute autosave and close are the only retries after a failed debounced write.** Parity; the
  Mac MAY additionally retry the debounce once after 5 s.
* **D-20 — `SavedListPicker` additions are not logged.** Parity.
* **D-21 — `IsComplete`/`Status` conflict resolution depends on key order in C#.** Swift uses the
  order-independent rule of REPO-040 ("Status wins"), which equals Windows for every file Windows writes.
  Writers on all platforms MUST keep the pair consistent (`IsComplete == (Status == Done)`).


### 8.1 Open questions for the product owner (referenced above as Q-n)

* **Q-1** Adopt the fixed saved-list nudge (D-1)? *Recommended: yes* (pure permutation, data-compatible).
* **Q-2** Should a regenerated recurring task/procedure inherit the source's Equipment/step links, pins and
  reciprocal relations (D-4)? *Recommended for v1: no — exact Windows parity*, revisit on both platforms
  together.
* **Q-3** Should permanent deletion also scrub nested-subtask `RelatedIds`, crew-step links, crew
  `ScheduleEntry.RefId` and `QuickViewPinIds`, and remove all duplicate occurrences (D-3)? *Recommended:
  remove-all yes; scope widening only together with Windows.*
* **Q-4** Should Board and Ctrl+N deletes go to the Trash on the Mac (D-6)? *Recommended for v1: parity (hard
  delete) with the same confirmation text; propose Trash routing for both platforms later.*
* **Q-5** Mac wording for Trash actions: Windows "↩ Restore / Delete permanently" vs Finder "Put Back / Delete
  Immediately…"? (Either keeps the capability.)
* **Q-6** Add ⌘⌫ "Move to Trash" in the sidebars and ⌥⌘↑/⌥⌘↓ for saved-list arrangement (Mac additions)?
* **Q-7** Also show the daily digest at local day rollover while AA stays open (D-8)?
* **Q-8** Write deadlines generated without a prior deadline as Unspecified midnight (D-5)? *Recommended: yes.*
* **Q-9** ⌘F: global search always (Windows parity) or in-note find when a note editor is focused, with ⇧⌘F for
  global search?
* **Q-10** Quick switcher on ⌘O (direct mapping of Ctrl+O) or ⇧⌘O ("Open Quickly")? *Recommended: both.*
* **Q-11** Should activating a search hit also select the matched subtask/step/component (`ChildId`)?
* **Q-12** Skip the saved-list write-back when "Edit items…" changed nothing (D-17)? *Recommended: yes.*
* **Q-13** When notification permission is denied, is the Dock badge + menu-bar extra an acceptable
  substitute for the Windows tray balloon?

---

## 9. Coverage cross-reference

**PROGRESS.md sections folded into this spec:** "Batch delete for tasks, procedures and equipment/areas";
"Arrange the order saved lists appear in (and export in)"; "Data-safety, reminders & housekeeping batch (9
improvements)" (undo + Trash, reminders, recurrence, safe mode); "Non-blocking autosave (fast typing at
scale) + per-item re-lock"; "Open a task / procedure / equipment in its own window" (restore yields a new
object under the same id); "Hierarchy" (I Equipment, II Tasks, III Procedures, IV Vessels); "Relationships";
"Performance & stability" (debounced save); "Inline task creation auto-linked"; "Inline procedure creation from
Equipment"; "Global highlighted search"; "Per-entry password lock" (search respects the lock); "Task workflow
status (model)"; "Update (2026-07-04): comprehensive subtask builder + procedure recurrence/status"; "Update
(2026-07-06): shared-save verified, activity log, unit converter, Ctrl+N quick-work" (activity log); "Tags
(Obsidian-style)"; "Backlinks ("Referenced by")"; "Quick switcher (Ctrl+O)"; "Two adversarial review passes"
(#6 `PurgeReferences`); "Reusable saved lists (templates) in every builder"; "Adversarial review (9 agents) →
3 fixes" (`CloneContainer` keeps `IsLocked`; crew jobs in `AllJobs`); "Saved Lists tab + List Groups"; "2. Add
tasks from saved lists"; "Optional working date-range on tasks & subtasks"; "Batch "mark as done"
(right-click)"; "Deadline a whole checklist at once + read-only saved-list item viewer"; "Floating due-dates
window now shows OVERDUE" (bucket rules); "Shared-save cadence + complete items from the floating window";
"Per-crew scheduler"; "Sidebar: alphabetical sort + groups"; "UX fixes (2026-06-07)" (empty groups);
"Per-crew-member checklist"; "Crew items in due-dates & everywhere necessary".

**Verification checklist for the Swift implementation** — a feature is done when its tests pass:

| Features | Tests |
|---|---|
| REPO-001..009 | persistence integration tests: debounce coalescing (10 `markDirty` in 500 ms → 1 write), ordered writes, failed write restores stamp + dirty, `save()` timeout, suspend/detach |
| REPO-010..015 | T-REL-7/8/10/11 |
| REPO-020..031 | T-REL-1..9, T-REC-13 |
| REPO-040..044 | T-DONE-1..13 |
| REPO-050..054 | T-RNG-1..9, T-DL-1..8 |
| REPO-060..064 | T-REC-1..15 |
| REPO-070..081 | T-TR-1..16, §7.6 |
| REPO-090..092 | T-LOG-1..5 |
| REPO-100..107 | §7.7, §7.14 |
| REPO-110..114 | §7.8 |
| REPO-120 | T-GRP-1..3 |
| REPO-130..136 | T-ORD-1..17 |
| REPO-140..147 | T-TPL-1..9 |
| REPO-150..155 | T-SCH-1..8 |
