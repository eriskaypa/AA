# 04 — Hierarchy pages (Equipment/Area · Tasks · Procedures · Vessels)

Feature-ID prefix: **HIER-**. Status: porting contract for the Swift/macOS build. Written from a full read of the
C# sources listed in §0; every quoted string is copied verbatim from them (including typographic quotes, em dashes,
ellipses and emoji). Where the Windows build behaves in a way that is clearly accidental, §8 lists it with a
recommended Mac decision — the implementer must follow the decision column, not silently "fix" or "keep" on a whim.

---

## 0. Sources read (complete)

| File | Lines | Role |
|---|---|---|
| `AA/Views/HierarchyPage.xaml` | 221 | Page layout: sidebar, header bar, details tabs, lock overlay |
| `AA/Views/HierarchyPage.xaml.cs` | 1424 | All page logic (sidebar, groups, CRUD, lock gate, relationships, per-kind Specifics, exports, detach) |
| `AA/Views/ItemWindow.xaml(.cs)` | 49 / 128 | "Open in new window" — name/description/tags + notes & file bank |
| `AA/Views/ContainerViewerWindow.xaml(.cs)` | 63 / 114 | Read-only notes + file-bank viewer (used by Saved Lists) |
| `AA/Views/ItemPickerWindow.xaml(.cs)` | 21 / 55 | Shared searchable single/multi picker + `PickerItem` |
| `AA/Views/ComponentEditorWindow.xaml(.cs)` | 29 / 44 | Equipment component editor |
| `AA/Views/ItemLockWindow.xaml(.cs)` | 37 / 48 | Set/change per-item password lock |
| `AA/Views/PromptWindow.xaml(.cs)` | 21 / 20 | Shared one-line text prompt |
| `AA/Views/DatePromptWindow.xaml(.cs)` | 23 / 41 | Shared "set deadline" date prompt |
| `AA/Views/BatchDeadlineMenu.cs` | 62 | "📅 Set deadline for selected…" menu entry |
| `AA/Views/BatchDeleteMenu.cs` | 111 | Batch delete confirmation + run |
| `AA/Views/BatchDoneMenu.cs` | 52 | "✓/○ Mark selected as (not) done" + right-click selection rule |
| Supporting (read for the call graph) | | `Models/Models.cs`, `Services/AppRepository.cs`, `Services/BatchDelete.cs`, `Services/BatchDone.cs`, `Services/BatchDeadline.cs`, `Services/ItemLockService.cs`, `Services/WorkRange.cs`, `Services/PasswordService.cs`, `Services/ChecklistExporter.cs`, `Services/DataStore.cs` (JSON options, `ResolveFilePath`), `Services/ThemeManager.cs`, `App.xaml`, `Views/UiTree.cs`, `Views/Converters.cs`, `Views/ContainerEditor.xaml.cs` (`Load`/`FlushPending`/`PersistRichText`), `MainWindow.xaml(.cs)` (hosting, item-window registry, navigation, shortcuts, Lock now, UI-state capture), `PROGRESS.md` (sections listed in the structured summary), `QR_SYNC_PROTOCOL.md` (`Ui` rules). |

Line references below are `file:line` into the files as of commit `37cdab0` (branch `mac-port`).

---

## 1. Overview

### 1.1 Purpose
The four "hierarchy" tabs are the heart of AA: the user's library of **Equipment/Areas**, **Tasks**, **Procedures**
and **Vessels**. One generic page (`HierarchyPage`) is instantiated four times, parameterised by `ItemKind`. Each
instance shows:

* a **sidebar** of items of that kind, grouped into user-defined **sidebar groups** (collapsible), filterable by a
  search box, optionally sorted A→Z, multi-selectable, with a context menu (open in window, group moves, batch
  delete);
* a **details pane** for the selected item: a header (Name / Description / Tags + Lock / Lock again / Export PDF),
  then tabs: **Container** (rich-text notes + file bank), **Relationships** (two-way links + backlinks) and a
  per-kind **Specifics** tab (Equipment: components / linked procedures / linked tasks; Task: schedule & subtasks;
  Procedure: checklist). Vessels instead get **Quick Cards / Work Orders / Ports** tabs and no Specifics;
* a **per-item password lock gate** that hides the whole details pane until the item is unlocked this session;
* the ability to **open an item in its own window** (multi-window), with a strict one-editor-per-container rule.

### 1.2 Where it sits
* `MainWindow.xaml:155-166` hosts four `HierarchyPage` instances as the first four main tabs, in default order
  **Equipment/Area** (`TabEquipment`/`EquipmentPage`), **Tasks** (`TabTasks`/`TasksPage`), **Procedures**
  (`TabProcedures`/`ProceduresPage`), **Vessels** (`TabVessels`/`VesselsPage`). Tabs can be reordered by the user
  (main-shell spec); Ctrl+1…9 selects by display position.
* `MainWindow.InitPagesAndRestoreUi` (`MainWindow.xaml.cs:1190`) calls `Init(repo, kind)` on each, wires
  `OpenInWindow`/`ItemsDeleted` (`HookItemWindows`, :186) and `Navigate = NavigateToItem` (:1205-1208), then
  restores each page's selection from `Ui.Selected{Equipment,Task,Procedure,Vessel}Id`.
* Other parts of the app navigate *into* these pages through `MainWindow.NavigateToItem` (:313): relationship and
  backlink rows, global search (Ctrl+F), quick switcher (Ctrl+O), Calendar, Buckets tab, SIRE, quick-work window,
  floating due-dates window.

### 1.3 Anatomy (Windows layout)

```
┌─ Sidebar (280 px, resizable via 6 px splitter) ─┐┌─ Details (fills) ───────────────────────────────────────────┐
│ [PageTitle: "Tasks"]          [+ New] [Delete] ││ Name:  [NameBox……………………] [🔒 Lock again] [🔒 Lock] [Export PDF...] │
│ [A→Z] [+ Group] [Assign group...]              ││ Description: [DescBox……………………………………………………………]            │
│ [Rename group...] [Delete group]  (WrapPanel)  ││ Tags:        [TagsBox……………………………………………………………]            │
│ [SearchBox]                                    │├──────────────────────────────────────────────────────────────┤
│ ▾ Engine room (3)                              ││ [Quick Cards][Work Orders][Ports]  ← vessels only            │
│     Change oil filter                          ││ [Container][Relationships][<Specifics header per kind>]      │
│     Check purifier                             ││                                                              │
│ ▾ Ungrouped (12)                               ││   …tab content…   (LockOverlay covers this area when gated)  │
│     …                                          ││                                                              │
└────────────────────────────────────────────────┘└──────────────────────────────────────────────────────────────┘
```

### 1.4 Ownership boundaries (what this spec does NOT own)
These are *used* here and specified elsewhere; this spec fixes only the contract at the seam:
* **ContainerEditor** (rich-text notes + file bank; `Load(Container, AppRepository?)`, `FlushPending()`) → container-editor spec. The XAML vocabulary it produces is owned there; §4.8 lists what *this* subsystem's viewer consumes.
* **SubtaskBuilderWindow**, **SubtaskEditorWindow**, **ChecklistBuilderWindow**, **ChecklistStepEditorWindow** → builders/editors spec.
* **QuickCardsPanel**, **ShipJobsPanel**, **PortsPanel** (vessel sub-tabs) → vessels spec.
* **PdfExporter.Export** (item PDF layout) → export spec. **ChecklistExporter** is small and is specified here (§3.9) because only this subsystem calls it.
* Trash window, Undo (Ctrl+Z) dispatcher, status bar, tab shell, Lock now menu → main-shell spec (integration points listed in §5).

---

## 2. Feature checklist

Legend: *Persist* = what is written and when. **MarkDirty** = debounced autosave (750 ms after last change, write off
the UI thread). **Save** = immediate synchronous save. **Flush** = `MarkDirty` + `FlushIfDirty` (immediate save if
dirty). Strings are exact.

### A. Page shell

**HIER-001 — One generic page, four kinds.** `Init(repo, kind)` (`HierarchyPage.xaml.cs:44`) sets:
* Page title (`PageTitle`, bold 15 pt, Accent colour): Equipment → `"Equipment/Area"`, Task → `"Tasks"`,
  Procedure → `"Procedures"`, Vessel → `"Vessels"`, otherwise `"Items"`.
* Specifics tab header: Equipment → `"Components / Procedures / Tasks"`, Task → `"Schedule & Subtasks"`,
  Procedure → `"Checklist"`, otherwise `"Specifics"`.
* Specifics tab hidden for Vessel; Quick Cards / Work Orders / Ports tabs visible **only** for Vessel.
* Non-vessel pages front the **Container** tab on Init (selected by reference, not index — PROGRESS "tab-index
  shift" fix).
* A→Z toggle state read from `Ui.SortAZ[kind.ToString()]` (missing = off).
* Builds the sidebar (`RefreshList`).
* `Init` can run again on every data reload/import; it must be idempotent (the Mac equivalent is simply re-binding
  to the new store).

**HIER-002 — Split layout.** Sidebar column fixed 280 px, a 6 px `GridSplitter` (user-draggable, not persisted),
details fill the rest. Sidebar and details are rounded (radius 4) bordered panels. The details root is **disabled**
(greyed) whenever nothing is selected.

**HIER-003 — Top-of-sidebar actions.** Accent button **`+ New`** (HIER-021) and button **`Delete`** (HIER-022).

**HIER-004 — Sidebar toolbar** (a wrapping row), each with tooltip:
* ToggleButton **`A→Z`** — tooltip `"Sort items alphabetically (otherwise list order is preserved)."` (HIER-013)
* **`+ Group`** — `"Create a new group in this sidebar."` (HIER-030)
* **`Assign group...`** — `"Move the selected item into a group (or out of all groups)."` (HIER-031)
* **`Rename group...`** — `"Rename a sidebar group."` (HIER-033)
* **`Delete group`** — `"Delete a sidebar group. Items inside it become ungrouped."` (HIER-034)

**HIER-005 — Search box.** A plain text box under the toolbar (its `Tag="Search..."` is not rendered as a
placeholder on Windows; the Mac search field should show the placeholder `"Search..."`). Every keystroke rebuilds
the list (`SearchBox_TextChanged` → `RefreshList`). Filter rule: query = text **trimmed**; if non-empty, keep items
whose **Name** contains the query, **case-insensitive ordinal** (`StringComparison.OrdinalIgnoreCase`). Tags,
description and notes are **not** searched (see §9 Q-5). Empty query shows all.

**HIER-006 — Empty-state hint** (`UpdateEmptyHint`, :149), a centred muted 13 pt wrapped text (max width 220),
overlaid on the list, not hit-testable:
* When the kind has **zero items at all** (regardless of search):
  * Equipment: `"No equipment or areas yet.\n\nClick “+ New” to add your first one."`
  * Task: `"No tasks yet.\n\nClick “+ New” to add a task, or Ctrl+N for the quick-work window."`
  * Procedure: `"No procedures yet.\n\nClick “+ New” to build your first checklist procedure."`
  * Vessel: `"No vessels yet.\n\nClick “+ New” to add a vessel, then import its work orders and ports."`
  * fallback: `"Nothing here yet.\n\nClick “+ New” to add one."`
* Else, when searching and no real item matches: `"No items match your search."`
* Else hidden. (Mac: replace "Ctrl+N" with "⌘N" in the Task hint — see §6.10.)

### B. Sidebar list

**HIER-010 — Grouped list.** Every row belongs to a section keyed by its group: the group's **name** if
`item.GroupId` resolves to a group of this kind, else the synthetic `"Ungrouped"` section. The `Ungrouped` section
exists even when the user has no groups (so a page with no groups shows a single `Ungrouped (N)` header). Section
header: group name in **bold Accent**, followed by ` (N)` in Muted, on a `PanelAlt` band (padding 6,3). Items are
indented 14 px under the header. Each header is a collapsible expander, default expanded (HIER-015).

**HIER-011 — Section order.** Real groups alphabetically by name (ordinal, case-insensitive), `Ungrouped` always
last (sort key `"￿" + "Ungrouped"`). Groups whose item set is empty get a placeholder row (HIER-014).

**HIER-012 — Row order within a section.** Placeholder rows always last. Real rows: if A→Z is on, by Name ordinal
case-insensitive; if off, **data order** (the order of `Data.Equipment/Tasks/Procedures/Vessels`, i.e. creation
order, with restored/recurrence-spawned items appended at the end). See §3.1 for the stability caveat.

**HIER-013 — A→Z toggle.** Clicking writes `Ui.SortAZ[kindName] = isOn` (`kindName` ∈ `"Equipment"`, `"Task"`,
`"Procedure"`, `"Vessel"`), **MarkDirty**, rebuilds the list. Persisted per kind; synced between devices as a shared
UI preference (Flash Sync `UiChanges`).

**HIER-014 — Empty-group placeholder.** For each group of this kind with no rows in the (filtered) row set, a
non-item row `"  (empty — right-click an item to assign)"` (two leading spaces, em dash) is added so the header
still renders. Placeholders are selectable in WPF but carry no item (selecting one clears the details pane and is
ignored by every action). (Mac: make them non-selectable — §8.)

**HIER-015 — Group expand/collapse persistence.** Expanding/collapsing a section writes
`Ui.GroupExpanded["{Kind}|{SectionName}"] = bool` (e.g. `"Task|Engine room"`, `"Equipment|Ungrouped"`) and
**MarkDirty**, but only when the value actually changes. On render, a stored value is applied; a missing key means
**expanded**. Keys are by *name*, so renaming a group forgets its state and deleting a group leaves a stale key
(harmless; keep writing/reading the same key format). `GroupExpanded` is **per-device** (never sent by Flash Sync)
but lives in `data.json` and therefore travels in shared-save and `.aaz` bundles.

**HIER-016 — Multi-selection.** Extended selection: click, Ctrl/⌘-click toggles, Shift-click ranges, Ctrl+A all.
The details pane shows `ItemsList.SelectedItem`, which in WPF Extended mode is the **first-selected** item of the
selection (anchor), not the last clicked. Actions that take "the selection" use every selected real item
(`SelectedHierarchyItems`, :282 — placeholders dropped).

**HIER-017 — Right-click selection rule** (`BatchDoneMenu.RightClickSelect`, `BatchDoneMenu.cs:34`, called from
`PreviewMouseRightButtonDown`): if the right-clicked row is already selected, keep the whole selection (the menu
acts on all of it); if it is not selected, clear the selection and select just that row; a right-click that is not
on a row leaves the selection untouched (the menu then acts on the current selection).

**HIER-018 — Wrapped names.** Rows show `Name` in a wrapping text block; no horizontal scrolling. Long names wrap
to the sidebar width.

**HIER-019 — Scale.** The list is UI-virtualised even when grouped (`VirtualizingPanel.IsVirtualizingWhenGrouping`,
recycling, pixel scrolling). Mac must stay smooth with thousands of rows (lazy `List`, memoised section build).

**HIER-020 — Sidebar context menu** (attached to the whole list, so it also opens on empty space and on headers):
1. **`Open in new window`** — tooltip `"Open this item in its own window so you can work on several at once. Its notes and files move to that window until you close it."` (HIER-110)
2. separator
3. **`Move to group...`** (same handler as *Assign group...*, HIER-031)
4. **`Remove from group`** (HIER-032)
5. separator
6. **`New group...`** (HIER-030)
7. separator
8. **`🗑 Delete selected...`** — tooltip `"Move every selected item to the Trash. Restore from File ▸ Trash, or undo with Ctrl+Z."` (HIER-022)

There is **no drag-and-drop** anywhere in the Windows sidebar (no drag-to-group, no reorder). Grouping is done only
through *Assign group… / Move to group…*. See HIER-M01 for the optional Mac addition.

### C. Item CRUD

**HIER-021 — New item** (`New_Click`, :351). Creates `Equipment{Name="New Equipment/Area"}`,
`TaskItem{Name="New Task"}`, `Procedure{Name="New Procedure"}` or `Vessel{Name="New Vessel"}` (all other fields
default; ungrouped), **appends** it to the kind's collection, logs `Added` with kind label
(`"Equipment/Area"|"Task"|"Procedure"|"Vessel"`) and empty detail, **Save**, rebuilds the list and selects the new
item by id. Focus is *not* moved to the name field on Windows (Mac: see HIER-M04). If a search filter is active and
does not match the default name the new item is neither shown nor selected (§8 Q-06).

**HIER-022 — Delete.** Two entry points share one path (`DeleteItems`, :403):
* Toolbar **`Delete`** (`Delete_Click`, :385): if the list has no real selected items but the details pane has an
  item, delete that one; otherwise delete the whole selection.
* Context **`🗑 Delete selected...`**: delete the selection.
Flow: `BatchDeleteMenu.Run` (HIER-135) confirms and soft-deletes; if it returns 0 (cancelled / nothing eligible) stop.
Otherwise: forget every picked id from the detached set, raise `ItemsDeleted(ids)` so their item windows close
(HIER-115), clear the details selection (pane disabled), rebuild the list, and set the status text:
* one deleted: `"'{picks[0].Name}' moved to Trash — Ctrl+Z to undo."`
* several: `"{n} items moved to Trash — Ctrl+Z to undo them all."`
(`n` = number actually trashed; `picks[0]` is the first *picked* item even if it was a skipped locked one — §8 Q-20.)

**HIER-023 — Batch delete confirmation contents.** See HIER-135 for the exact dialog text. Locked (gated) items are
never deleted; they are counted and skipped.

**HIER-024 — Undo of a delete.** Not handled by the page: global Ctrl+Z (when no text box/password box has focus)
calls `AppRepository.UndoLastDelete`, which restores the newest Trash entry — or the **whole batch** when the newest
entry has a non-empty `BatchId` — and the shell reloads every affected page (`ReloadList`). Status:
`"Nothing to undo."`, `"Restored {n} deleted items (Ctrl+Z)."` (n>1) or `"Restored the last deleted item (Ctrl+Z)."`.
Restored items are **not** re-selected.

**HIER-025 — Rename.** `NameBox` (right of the `"Name:"` label, 80 px label column):
* Every keystroke: `item.Name = text` (no trimming; empty allowed), **MarkDirty**, and the selected row's text is
  refreshed **in place** (no list rebuild, so focus and selection are kept).
* **Enter** in the box, or the box **losing focus**, commits: rebuild the list (re-sort / re-group) and re-select the
  item by id. Enter is consumed (does not bubble).
* **F2** (global, only when no TextBox/PasswordBox has focus, only when a hierarchy tab is active and something is
  selected): focus the name box and select all its text (`BeginRename`, :490).

**HIER-026 — Description.** Single-line `DescBox` under `"Description:"`; each keystroke sets
`item.Description`, **MarkDirty**. (Descriptions may contain newlines if edited in the item window, HIER-111.)

**HIER-027 — Tags.** `TagsBox` under `"Tags:"`, tooltip
`"Comma- or space-separated tags. Used for filtering, global search and the quick switcher (Ctrl+O)."`
* Each keystroke: `item.Tags` is **replaced** by `ParseTags(text)` (§3.4), **MarkDirty**.
* On focus loss the box text is normalised to `string.Join(", ", item.Tags)`.
* Displayed on selection as `", "`-joined tags.

### D. Sidebar groups (`ItemGroup`, per kind)

**HIER-030 — New group** (`NewGroup_Click`, :183; toolbar `+ Group` and context `New group...`). Prompt
(HIER-130) title `"New group"`, label `"Name:"`. If OK and the value is not null/whitespace: `CreateGroup(kind,
value)` (name **trimmed**; duplicates allowed), **Save**, rebuild list, status
`"Group '{name}' created. Right-click an item and choose 'Move to group...' to fill it."`. The new empty group shows
immediately with its placeholder row.

**HIER-031 — Assign / Move to group** (`AssignGroup_Click`, :246). Acts on the selected real items; if none, does
nothing (silently). Opens the picker (HIER-131) in **single-select** mode:
* title: one item → `"Move '{name}' to group"`; several → `"Move {n} items to group"`;
* rows: first `"(Ungrouped)"` (tag = empty GUID), then this kind's groups **in `Data.Groups` order** (creation
  order, not alphabetical), display = group name;
* preselection: if every picked item has the same group (ungrouped counts as the empty GUID) that row is
  preselected, otherwise nothing.
On OK: the picked tag (or the empty GUID when **nothing** was selected — §8 Q-08) → `GroupId` (`null` for empty
GUID) for every picked item, **Save**, rebuild, re-select all picked items and scroll the first into view.

**HIER-032 — Remove from group** (`UngroupItem_Click`, :198). For each selected real item with a group set
`GroupId = null`. If none changed, nothing is saved. Else **Save**, rebuild, re-select the same items.

**HIER-033 — Rename group** (`RenameGroup_Click`, :308). If the kind has no groups: message box
`"No groups to rename in this tab yet."`, title `"Rename group"`, Information. Else single-select picker
`"Pick a group to rename"` (groups in creation order); if a group was picked, prompt title `"Rename group"`,
label `"New name:"`, pre-filled with the current name (all selected). If OK and non-blank: rename (trimmed),
**Save**, rebuild.

**HIER-034 — Delete group** (`DeleteGroup_Click`, :333). If no groups: silently nothing. Else single-select picker
`"Pick a group to delete (items inside become ungrouped)"`; then confirm `"Delete group '{name}'?"`, title
`"Confirm"`, Yes/No, Question. On Yes: every item **of any kind** whose `GroupId` equals the group id is ungrouped,
the group is removed, **Save**, rebuild.

### E. Details pane

**HIER-040 — Selection binds the details** (`ItemsList_SelectionChanged`, :497), in this order:
1. Flush the Container editor's pending rich-text edit (so it lands on the **previous** item).
2. Resolve the selected item (first-selected; placeholder → none). Details root enabled iff an item is selected.
3. No item: hide the lock overlay, show tabs and header, hide the Lock button; stop (fields keep stale text but are
   disabled — Mac: show an empty state instead, §8 Q-01).
4. Populate Name, Description and Tags (with change handlers suppressed).
5. If the item is **detached** (open in its own window): bind the Container editor to a throw-away empty container,
   disable the whole details root, show the Container-tab note
   `"This item is open in its own window. Close that window to edit it here again."`, stop.
6. Otherwise hide that note, bind the Container editor to `item.Container` (with the repository, so edits persist),
   rebuild the relationship lists (HIER-060/063) and the Specifics tab (HIER-070…096).
7. Vessel: load Quick Cards, Work Orders and Ports panels for this vessel and **front the Quick Cards tab**.
   Non-vessels keep whichever details tab was showing.
8. Apply the lock gate (HIER-050).

**HIER-041 — Header bar.** `Name:` / `Description:` / `Tags:` rows (80 px label column). To the right of the name
box, left→right: **`🔒 Lock again`** (HIER-055, hidden unless applicable), **Lock button** (HIER-053/054), and
**`Export PDF...`** (tooltip `"Export this item, its hierarchy and relationships to an A4 PDF."`, HIER-044).

**HIER-042 — Details tabs** (in this order): `Quick Cards`, `Work Orders`, `Ports` (vessel only), `Container`,
`Relationships`, Specifics (header per HIER-001; hidden for vessels). The selected details tab is not persisted.

**HIER-043 — Container tab.** Hosts the shared ContainerEditor for `item.Container` (rich-text notes + file bank).
While the item is detached, the editor is parked on an empty container and the centred note of HIER-040 step 5 is
shown over it (bordered `PanelAlt` card, max width 360, centred text).

**HIER-044 — Export PDF (item).** `ExportPdf_Click` (:755):
1. Gated item → message `"Unlock this entry before exporting it to PDF."`, title `"Locked"`, Information; stop.
2. Flush the Container editor, then `FlushIfDirty` (so the PDF reflects the latest text).
3. Save dialog: title `"Export to PDF"`, filter `"PDF document (*.pdf)|*.pdf"`, default name
   `"{Kind}-{safeName}.pdf"` where Kind is the enum name (`Equipment`, `Task`, `Procedure`, `Vessel`) and
   `safeName` replaces every Windows-invalid filename character with `_` (§3.8).
4. Wait cursor; `PdfExporter.Export(item, repo, path)`. On exception: `"Failed to export PDF:\n{message}"`, title
   `"Export error"`, Error; stop.
5. Open the PDF with the default viewer (failure ignored).

### F. Per-item password lock

**HIER-050 — Lock gate** (`ApplyLockGate`, :561). An item is *gated* when it has a lock (`LockHash` and `LockSalt`
both non-empty) and has not been unlocked in this app session. When gated:
* the details tabs are hidden (layout kept) and an overlay (Panel background, border, radius 4) shows, centred,
  max width 460: a 44 pt `🔒`, bold 17 pt `"This {kindWord} is locked."` (`kindWord` = `equipment/area`, `task`,
  `procedure`, `vessel`, fallback `entry`), muted `"Enter its password (or the master password) to view and edit it."`,
  a 280 px password box, an error line (colour `#D45050`), buttons **`Show hint`** and accent **`🔓 Unlock`**, and a
  hidden muted hint line;
* the **header bar is collapsed** (Name/Description/Tags/Lock/Export are all hidden) so nothing is visible or
  editable;
* the password box, error and hint are cleared and the password box receives keyboard focus.
Not gated: overlay hidden, tabs and header visible. The lock button state is refreshed every time (HIER-053).

**HIER-051 — Unlock.** `🔓 Unlock` or **Enter** in the password box → `ItemLockService.TryUnlock`. Success: clear
the box, re-apply the gate (overlay disappears), status `"'{name}' unlocked for this session."`. Failure: error line
`"Wrong password. Use the entry's password or the master password (“redemption”)."`; the typed password stays.
The master password is the constant **`redemption`** (ordinal, case-sensitive) and always unlocks any item.

**HIER-052 — Show hint.** Shows `"Hint: {LockHint}"`, or `"(No hint was set.)"` when the hint is null/blank.

**HIER-053 — Lock button (unprotected item).** Content `"🔒 Lock"`, tooltip
`"Password-protect this entry (with an optional hint). The master password always unlocks."`. Click → Item-lock
dialog in *Set* mode (HIER-058) → `Protect(item, password, hint)` (item is gated immediately) → **Save** → status
`"'{name}' is now locked."` → re-apply gate (padlock appears at once).

**HIER-054 — Manage lock (protected & unlocked item).** Content `"🔓 Locked"`, tooltip
`"This entry is password-protected. Click to change the password/hint or remove the lock."`. Click → message box:
`"This entry is locked.\n\nYes  = Change the password / hint\nNo   = Remove the lock\nCancel = keep it as is"`
(note the padding spaces), title `"Manage lock"`, Yes/No/Cancel, Question.
* **Yes** → Item-lock dialog in *Change* mode pre-filled with the current hint → `Protect` (new salt+hash; item is
  gated immediately) → **Save** → status `"Lock updated."` → re-apply gate.
* **No** → `RemoveProtection` (hash, salt, hint → null) → **Save** → `"Lock removed."` → re-apply gate.
* **Cancel** / close → nothing.
While gated the Lock button is hidden (the overlay handles unlocking). With no selection it is hidden.

**HIER-055 — Lock again.** Button `"🔒 Lock again"`, tooltip
`"Re-gate this entry now — it will need the password again to open (this session)."`, visible only when the item is
protected **and** currently unlocked. Click → `ItemLockService.Relock(item)` → re-apply gate → status
`"'{name}' locked again — the password is needed to open it."`. Nothing persisted.

**HIER-056 — Tools ▸ Lock now integration.** The shell clears the app password session and calls
`ItemLockService.RelockAll()`, sets status `"Locked. Locked containers and entries will require re-unlocking."`,
then calls `RelockCurrent()` (:548) on all four pages: flush the Container editor; if the current item is not gated,
re-load its container into the editor (so text-level locks re-render); re-apply the gate. Selection is preserved.

**HIER-057 — Lock guards.** While an item is gated: PDF export refuses (HIER-044), open-in-window refuses
(`"Unlock this entry before opening it in its own window."`, title `"Locked"`, Information), batch delete skips it
(HIER-135), global search indexes only its name (search spec). The item is still listed in the sidebar and in
relationship pickers/lists by name, can still be moved between groups, and can be navigated to (it opens on the
lock screen). Session unlocks are process-wide (shared by all pages and windows) and are forgotten on relaunch.

**HIER-058 — Item-lock dialog** (`ItemLockWindow`, 470×330, not resizable, centred on owner). Window title
`"Lock entry"`. Bold 15 pt title and muted prompt:
* *Set* mode: `Lock “{itemName}”` / `"Set a password for this entry. It will be required to view or edit the entry. The app master password always unlocks it."`
* *Change* mode: `Change lock on “{itemName}”` / `"Enter a new password (and, optionally, a new hint). The master password always unlocks it."`
Fields: `"Password:"` (password box, focused on open), `"Confirm password:"` (password box),
`"Hint (optional — shown on the lock screen, never the password):"` (text box, pre-filled with the existing hint in
Change mode, empty in Set mode). Error line (`#D45050`). Buttons `Cancel`, accent `OK` (default, Enter).
Validation on OK, first failure wins, dialog stays open:
1. empty password → `"Password cannot be empty."`
2. length < 4 (UTF-16 code units) → `"Password must be at least 4 characters."`
3. confirm differs (ordinal) → `"Passwords do not match."`
Success returns `Password` and `Hint = hint.Trim()`; `Protect` then stores a null hint when it is blank.

### G. Relationships tab

**HIER-060 — Related items list.** Top row: accent **`Add relationship...`**, **`Remove`**, and muted text
`"Related items (double-click to open). Removing breaks the link both ways."`. List rows display
`"[{Kind}] {Name}"` (Kind = enum name: `Equipment`, `Task`, `Procedure`, `Vessel`). Content =
`AppRepository.RelatedItems(item)` (§3.6): the item's `RelatedIds`, plus — for Equipment — its `ProcedureIds` and
`TaskIds`, de-duplicated, missing ids skipped.

**HIER-061 — Add relationship** (`AddRel_Click`, :808). Candidates: every top-level item of every kind except the
item itself, ordered by kind (Equipment, Task, Procedure, Vessel) then Name (ordinal ignore-case), displayed
`"[{Kind}] {Name}"`. Multi-select picker `"Pick related items"`, no preselection. On OK: `AddRelation(item, pick)`
for each pick (two-way, no duplicates, self ignored), **Save**, refresh both lists. Deselecting in the picker never
removes anything.

**HIER-062 — Remove relationship** (`RemoveRel_Click`, :832). With a row selected: `RemoveRelation(item, other)`
(removes each id from the other's `RelatedIds`), **Save**, refresh. Rows that exist only because of an Equipment's
one-way `ProcedureIds`/`TaskIds` are **not** removed by this (they reappear) — §8 Q-14.

**HIER-063 — Backlinks.** Bold Accent heading `"↩ Referenced by (backlinks) — items that point to this one:"`,
then a 160 px list of `"[{Kind}] {Name}"` rows from `AppRepository.ReferencedBy(item)` (§3.6): items whose
`RelatedIds` contain it, Equipment whose `ProcedureIds`/`TaskIds` contain it, Procedures with a step whose
`TaskIds`/`EquipmentIds` contain it.

**HIER-064 — Navigate by double-click.** Double-clicking a related or backlink row calls
`Navigate(targetItem)` → `MainWindow.NavigateToItem`: switch to the target kind's tab and select the item
(deferred to after the tab switch). Works across kinds.

Relationship lists are rebuilt on selection change and after local add/remove and after Specifics picks/creations;
they are not live-updated when other windows change links (Mac: live via observation).

### H. Equipment specifics (`BuildEquipmentSpecifics`, :875)

Three stacked sections with equal-height lists (margin 6), inside a vertical scroller.

**HIER-070 — Components.** Bold `"Components"` header with buttons **`+ Add`**, **`Remove`**, **`Edit...`**
(tooltip `"Open this component in a dedicated editor with its own rich-text container and file bank."`). A two-column
list (single selection, virtualised): **Name** (260) and **Notes** (360) — the component's one-line `Notes`, not its
rich text. The heavy `Container` is never realised in the list.
* `+ Add` → prompt title `"New Component"`, label `"Name:"`; if non-blank, append `Component{Name=value}`
  (**not trimmed**), **Save**. No activity-log entry.
* `Remove` → removes the selected component (with its notes/files container) immediately — **no confirmation, no
  Trash, no log** — **Save**.
* `Edit...` or double-click a row → Component editor (HIER-071) modal; the list re-reads on close.

**HIER-071 — Component editor** (`ComponentEditorWindow`, 900×700, centred on owner, modal). Title
`"Edit component — {name}"` (updates live while typing). `"Name:"` box (100 px label) → `Name`, **MarkDirty**;
`"Short notes:"` box (tooltip `"One-line summary shown in the components list. Use the rich-text area below for the full container content."`)
→ `Notes`, **MarkDirty**; the full ContainerEditor bound to `component.Container`; bottom-right **`Close`**. On
closing: flush the editor and `FlushIfDirty`.

**HIER-072 — Related procedures.** Bold header `"Related Procedures (auto-relates sub-hierarchy)"`, buttons
**`Pick...`** and **`+ New procedure`** (tooltip `"Create a new Procedure and auto-link it to this Equipment/Area."`).
List rows = `Label(id)` for each id in `ProcedureIds` (`"[Procedure] {Name}"` or `"(missing)"`), in stored order.
No double-click action.
* `Pick...` → multi-select picker `"Pick procedures"` over **all** procedures in data order (display = bare name),
  preselected = current `ProcedureIds`. On OK the list is **replaced** by the picker's selection (selection order),
  **Save**, refresh this list and the Relationships tab. (Ids of procedures no longer present are dropped.)
* `+ New procedure` → prompt `"New Procedure"` / `"Name:"`; if non-blank: new `Procedure{Name=value}` (not trimmed)
  appended to `Data.Procedures`, its id appended to `ProcedureIds`, log `Added`/`"Procedure"`/name/
  `"linked to {equipmentName}"`, **Save**, refresh list + Relationships. (Procedures sidebar is not refreshed on
  Windows — §8 Q-07.)

**HIER-073 — Related tasks.** Bold `"Related Tasks"`, buttons **`Pick...`** and **`+ New task`** (tooltip
`"Create a new Task and auto-link it to this Equipment/Area."`). Identical to HIER-072 over top-level `Data.Tasks`
and `TaskIds`: picker `"Pick tasks"`; prompt `"New Task"` / `"Name:"`; log `Added`/`"Task"`/name/
`"linked to {equipmentName}"`.

### I. Task specifics (`BuildTaskSpecifics`, :999) — tab "Schedule & Subtasks"

A vertical stack (margin 8) in a scroller; 120 px label column.

**HIER-080 — Deadline + optional working range.** `"Deadline:"` date picker (160 px, tooltip
`"Due date — also the LAST day of the working range."`) and `"Start (optional):"` date picker (160 px, tooltip
`"Optional first day of the working range. Leave empty for a single-day task."`). Both nullable (clearable). On a
change of either picker, `WorkRange.Coerce` (§3.3) is applied against the **model's** partner value (never the
sibling control, which may be stale), both pickers are re-set to the coerced pair without re-entry, the model's
`RangeStart`/`Deadline` are written, **MarkDirty**. Consequences: a start after the deadline pushes the deadline to
the start; a deadline before the start pulls the start to the deadline; a start with no deadline sets the deadline to
the start; clearing the deadline while a start exists re-sets the deadline to the start (clear the start first).

**HIER-081 — Recurrence.** `"Recurrence:"` combo (200 px) listing the enum names `None`, `Daily`, `Weekly`,
`Monthly`, `Yearly`; selection → `Recurrence`, **MarkDirty**. Completing a recurring top-level task spawns its next
occurrence after the next save (§3.10).

**HIER-082 — Status ⇄ Completed.** `"Status:"` combo (200 px, tooltip
`"Workflow status used by the Board (Done keeps Completed in sync)."`) listing `Todo`, `InProgress`, `Blocked`,
`Done`, and a **`Completed`** checkbox. Changing either writes the model and re-syncs the other control from the
model (guarded against loops), **MarkDirty**. Model rule: `Status=Done` ⇔ `IsComplete=true`; un-completing a Done
task sets `Todo`; setting a non-Done status clears completion; un-completing an `InProgress`/`Blocked` task is a no-op
on status.

**HIER-083 — Schedulable job.** Checkbox **`Schedulable job`** (tooltip
`"Tag this task as a Job so it can be dragged onto the Planner."`) → `IsJob`, **MarkDirty**; then
`"Duration (min):"` text box (80 px) showing `DurationMinutes` (default 60). A keystroke writes only when the text
parses as an integer **> 0** (§3.5); invalid text is left in the box and ignored.

**HIER-084 — Comprehensive Subtask Builder.** Full-width bold 14 pt accent button
`"🛠  Open Comprehensive Subtask Builder"` (two spaces after the emoji; padding 14,8), tooltip
`"Open a dedicated window to bulk-create, reorder, edit and delete subtasks."` → `SubtaskBuilderWindow(task, repo)`
modal (builders spec). It edits the same `Subtasks` collection the list below shows.

**HIER-085 — Subtasks list.** Bold `"Subtasks"` heading; a 220 px, multi-select (extended), virtualised table with
columns: **Name** (280, wrapping, **struck through when `IsComplete`**), **When** (190, `WhenText` §3.7),
**Status** (110, enum name), **Done** (60, the bool as text `True`/`False` on Windows — Mac: read-only check glyph).
Direct children only.

**HIER-086 — Subtask buttons.** **`+ Add`** → prompt `"New Subtask"` / `"Name:"`; non-blank → append
`TaskItem{Name=value}` (not trimmed), log `Added`/`"Subtask"`/name/`{parentTaskName}`, **Save**.
**`Remove`** → the (first) selected subtask: log `Removed`/`"Subtask"`/name/`{parentTaskName}`, remove (with its own
subtree; no confirmation, no Trash), **Save**. **`Edit...`** (tooltip
`"Open this subtask in a dedicated editor with its own deadline, container and files."`) or double-click →
`SubtaskEditorWindow(subtask, repo)` modal; the list re-reads after close.

**HIER-087 — Subtask context menu** (with the right-click rule of HIER-017): `✓ Mark selected as done`,
`○ Mark selected as not done`, separator, `📅 Set deadline for selected…` (HIER-133/134).

### J. Procedure specifics (`BuildProcedureSpecifics`, :1163) — tab "Checklist"

**HIER-090 — Procedure fields** (120 px labels):
* `"Deadline:"` date picker (200 px, tooltip `"Optional deadline for this procedure. Shown in the Calendar-style floating due-dates window."`) → `Deadline` (nullable; no range for procedures), **MarkDirty**.
* `"Recurrence:"` combo (as HIER-081) → `Recurrence`, **MarkDirty**.
* `"Status:"` combo (tooltip `"Workflow status for this procedure."`) → `Status`, **MarkDirty**. (No Completed box;
  a procedure is "done" iff `Status == Done`.)
* Checkbox **`Mark this procedure as a schedulable job`** (tooltip
  `"Tag the whole procedure as a Job so it can be dragged onto the Planner."`) → `IsJob`, **Flush** (immediate);
  `"Duration (min):"` (80 px) as HIER-083 → `DurationMinutes`, **MarkDirty**.

**HIER-091 — Checklist heading & builder banner.** Bold `"Checklist Steps"`; then a row whose right side holds
**`Export checklist (PDF)`** (tooltip `"Export ONLY the checklist (no notes, no relationships) as a printable A4 PDF."`)
and **`Export checklist (Excel)`** (tooltip `"Export ONLY the checklist as an Excel workbook (.xlsx)."`), and whose
remaining width is a bold 14 pt accent button `"🛠  Open Comprehensive Checklist Builder"` (tooltip
`"Open a dedicated window to bulk-create, reorder, edit and delete checklist steps."`) →
`ChecklistBuilderWindow(procedure, repo)` modal; the step list re-reads after close.

**HIER-092 — Checklist-only export.** See §3.9 (PDF and XLSX layouts, file names, errors).

**HIER-093 — Steps list** (multi-select, virtualised, fills remaining height). Columns:
* **Done** (50) — live checkbox two-way bound to `step.Done`; click → **Flush**.
* **Job** (44) — live checkbox bound to `step.IsJob`, tooltip `"Mark this step as a schedulable Job (set its duration in the step editor)."`; click → **Flush**.
* **Title** (300) — wrapping, **struck through when `Done`**.
* **Deadline** (120) — `yyyy-MM-dd` or empty.

**HIER-094 — Step buttons** (row under the banner): **`+ Step`** → prompt `"New Step"` / `"Title:"`; non-blank →
append `ChecklistStep{Title=value}` (not trimmed), log `Added`/`"Checklist step"`/title/`{procedureName}`, **Save**.
**`Remove`** → first selected step: log `Removed`/`"Checklist step"`/title/`{procedureName}`, remove (no
confirmation, no Trash), **Save**. **`Edit...`** (tooltip
`"Open this checklist step in a dedicated editor with its own rich-text container and file bank."`) or double-click →
`ChecklistStepEditorWindow(step, repo)` modal; list re-reads after close.

**HIER-095 — Step links.**
* **`Link tasks...`** — requires a selected step (else silently nothing); multi-select picker
  `"Pick tasks for this step"` over all top-level tasks (bare names, data order), preselected = `step.TaskIds`; OK
  replaces `step.TaskIds` with the selection, **Save**.
* **`+ New task`** (tooltip `"Create a new Task and auto-link it to the selected checklist step."`) — with no
  selected step: message `"Select a checklist step first."`, title `"New task"`, Information. Else prompt
  `"New Task"` / `"Name:"`; non-blank → new top-level `TaskItem` appended to `Data.Tasks`, its id appended to
  `step.TaskIds`, log `Added`/`"Task"`/name/`"linked to step '{stepTitle}'"`, **Save**.
* **`Link equipment/area...`** — as *Link tasks* over `Data.Equipment`, picker
  `"Pick equipment/area for this step"`, writes `step.EquipmentIds`.
The steps list has no column for linked tasks/equipment (visible in the step editor, exports and backlinks).

**HIER-096 — Steps context menu**: `✓ Mark selected as done`, `○ Mark selected as not done`, separator,
`📅 Set deadline for selected…` (HIER-133/134), with the HIER-017 right-click rule.

### K. Vessels

**HIER-100 — Vessel details.** Tabs `Quick Cards`, `Work Orders`, `Ports`, `Container`, `Relationships` (no
Specifics). Every time a vessel is selected the three vessel panels are (re)loaded for it and the **Quick Cards** tab
is brought to the front. Panel behaviour is owned by the vessels spec. Vessels participate in groups, search, A→Z,
lock, relationships, backlinks, PDF export, open-in-window and batch delete exactly like other kinds.

### L. Multi-window

**HIER-110 — Open in new window.** Context-menu entry (HIER-020). Target: the first selected real item, else the
details item; none → nothing. Gated → HIER-057 message. Otherwise the page raises `OpenInWindow(item)`; the shell
(`OpenItemWindow`, `MainWindow.xaml.cs:194`):
1. if a window for that id is already open → activate it, stop;
2. flush all editors (so buffered main-pane text is in the model before handing over);
3. create the item window (owned by the main window), subscribe `NameChanged → page.ReloadList()` and
   `Closed → registry.remove(id); page.ReattachItem(id)`;
4. register it under the item id, `page.DetachItem(id)`, show it (modeless).

**HIER-111 — Item window** (`ItemWindow`, 900×720, centred on owner). Title `"{Kind} — {name}"`, `(unnamed)` when
the name is empty (updates while typing). Top line: bold Accent kind name (`Task`) and a muted state text. Fields
(muted labels): `Name`, `Description` (multi-line, wraps, 2–4 visible lines, Enter inserts newline), `Tags`
(tooltip `"Comma-separated."`). Bottom muted note:
`"Schedule, subtasks, steps and relationships stay in the main window — this window covers the notes and file bank."`
The rest is the ContainerEditor bound (with repository) to the item's container. Edits: Name → **MarkDirty** +
`NameChanged(id)`; Description → **MarkDirty**; Tags → replaced by splitting on `,` only, trimming, dropping empties
(no `#` stripping, no de-duplication — §8 Q-15) → **MarkDirty**. Closing flushes the editor (guarded so it can never
cancel the close).

**HIER-112 — One editor per container (detach/reattach).** Invariant: at most one live rich-text editor is ever
bound to a given container, because the editor persists by serialising the whole document over the container text
with no dirty check (last writer silently wins). `DetachItem(id)` (:450): add to the detached set; if it is the
current details item, flush, park the details editor on a throw-away container, disable the details root and show
the detached note. `ReattachItem(id)` (:461): remove from the set, hide the note, rebuild the list preserving
selection; if it is the current item, re-bind the editor to the real container, re-enable, and re-populate
Name/Description/Tags from the model (the window may have changed them). Selecting a detached item later also shows
the parked state (HIER-040 step 5).

**HIER-113 — One window per item.** The registry is keyed by item id; opening an already-open item focuses its
window.

**HIER-114 — Reload safety.** Windows hold the item **id**, never a long-lived model reference. After any data
reload (File ▸ Reload, import, shared-save pull, Flash Sync apply, ZIP import) the shell calls `SetRepo(newRepo)` on
every item window: flush, re-resolve the item by id among top-level items; if found, re-bind all fields; if not, go
*orphaned*: state text `"This item is no longer in the loaded data — nothing typed here will be saved."`, and
Name/Description/Tags and the editor are disabled; `Flush()` becomes a no-op.

**HIER-115 — Delete closes windows.** After a successful delete the page raises `ItemsDeleted(ids)`; the shell
orphans (stop writing) and closes each window in the set.

**HIER-116 — Flush everywhere.** The shell's `FlushAllEditors` flushes all four pages' editors, the SIRE body, and
every item window; it runs before sync/export/reload and on open-in-window. On app exit, every item window is flushed
and closed **before** the final save and shared-bundle push. (Ctrl+S and the 5-minute autosave flush only the four
page editors on Windows — Mac must flush all editors on every save path, §8 Q-31.)

**HIER-117 — Rename propagation.** Every keystroke in an item window's Name raises `NameChanged` → the owning page
rebuilds its sidebar (preserving selection) so the row label follows.

### M. Navigation & integration

**HIER-120 — Navigate to item.** `NavigateToItem(item)` switches the main tab to the item's kind page and, after
the switch is processed, calls `page.SelectItemById(id)` which selects that row (replacing the selection). If the
item is hidden by the page's search filter it is **not** selected (§8 Q-05). The row is not scrolled into view on
Windows (Mac must reveal it).

**HIER-121 — Selection persistence.** On save/autosave/close the shell writes `Ui.SelectedEquipmentId`,
`SelectedTaskId`, `SelectedProcedureId`, `SelectedVesselId` from each page's current item (null → key omitted); on
load each page re-selects it. `ReloadList()` (:482) rebuilds and re-selects the current item by id; used after
undo/restore, recurrence spawning, SIRE quick-add, item-window rename/close, and Trash restore.

**HIER-122 — F2 rename** (HIER-025).

**HIER-123 — Ctrl+Z undo delete** (HIER-024). Ignored when a text box or password box has focus (their own text
undo applies).

**HIER-124 — Status messages.** All page messages go to the main window's status text (`StatusBlock`); exact
strings are listed in each feature.

**HIER-125 — Cross-page refresh points.** Other features that mutate these collections call `ReloadList` on the
affected pages: undo/restore (per restored type), recurrence reconcile after every save (Tasks + Procedures), SIRE
(`RefreshHierarchyPages`, all four). Everything else (inline creation from another page, Board, quick-work window…)
does **not** refresh the sidebars on Windows; the Mac must be live (observation) — §8 Q-07.

### N. Shared dialogs & menus (also used by other subsystems)

**HIER-130 — Prompt** (`PromptWindow`, 440×170, not resizable). Window title = bold 14 pt title = `title`; label
= `prompt`; one text box pre-filled with `initial` (all selected, focused). Buttons `Cancel`, accent `OK` (default:
Enter). Returns the raw text (**not trimmed**); callers test `IsNullOrWhiteSpace`. Cancel/close → false.

**HIER-131 — Item picker** (`ItemPickerWindow`, 500×500). Window title `"Pick items"`; bold prompt label = the
caller's prompt; a search box; a list of `PickerItem.Display` strings; buttons `Cancel`, accent `OK` (default).
* Multi mode: each click **toggles** a row (no modifier needed). Single mode: radio-like single row.
* Preselection: rows whose `Tag` equals any preselect value (multi → all; single → first match).
* Search: trimmed query, rows whose `Display` contains it (ordinal ignore-case); empty → all rows. Changing the
  filter replaces the list, and WPF drops the selection of rows that are filtered out (§8 Q-13).
* OK → `SelectedTags` = tags of the selected rows, **in selection order**; Cancel → false.
Callers in this subsystem: group move/rename/delete (single), relationships, procedure/task picks, step links
(multi). Other callers: Board, Buckets, Calendar, checklist builder control, quick-work, saved-list picker, SIRE,
schedule builder, subtask builder, quick cards editor, container editor.

**HIER-132 — Date prompt** (`DatePromptWindow`, 420×200, not resizable). Window title and bold title = `title`;
wrapping label = `prompt`; a nullable date picker (200 px) pre-set to `initial`. Buttons: **`Clear deadline`**
(tooltip `"Remove the deadline from every selected item."`) → result true with date null; `Cancel` → false; accent
`OK` (default) → if no date picked: message `"Pick a date, or use \"Clear deadline\" to remove it."`, title
`"Set deadline"`, Information (dialog stays); else result true with the date (time stripped).

**HIER-133 — Batch done menu** (`BatchDoneMenu.Add`). Appends `✓ Mark selected as done` and
`○ Mark selected as not done` (optionally after a separator when the menu already has items). Click → evaluate the
selection **at click time** → `BatchDone.SetDoneAll(items, done)` (§3.11); if anything changed, **Flush**; then the
caller's refresh.

**HIER-134 — Batch deadline menu** (`BatchDeadlineMenu.Add`, separator first by default). Entry
`📅 Set deadline for selected…`, tooltip `"Give every selected item the same deadline (or clear it)."`. Click →
selection at click time; empty → message `"Select one or more items first, then set the deadline."`, title
`"Set deadline"`. Else date prompt: title `"Set deadline"`, prompt
`"Apply one deadline to {n} selected item{s}:"` (`item` when n = 1), initial = the one deadline shared by all
selected items if they all share one (null counts as a value, so all-undated → empty). OK/Clear →
`BatchDeadline.SetDeadlineAll(items, date)` (§3.12); if anything changed, **Flush**; always refresh.

**HIER-135 — Batch delete** (`BatchDeleteMenu.Run`). Selection → `BatchDelete.Describe` (§3.13):
* nothing selected (no items and no locked items): `"Select one or more items first."`, title `"Delete selected"`,
  Information → 0.
* everything selected is locked: `"That item is locked. Unlock it before deleting it."` (1) or
  `"All {n} selected items are locked. Unlock them before deleting."`, title `"Nothing deleted"` → 0.
* otherwise confirm (title `"Confirm delete"`, Yes/No, Warning, **default No**) with the prompt of §3.13; No → 0;
  Yes → `BatchDelete.TrashAll` (one undo batch, locked skipped); if n > 0 **Save**; return n.
`BatchDeleteMenu.Add` (a context-menu builder) exists but is unused in the current build.

**HIER-136 — Read-only container viewer** (`ContainerViewerWindow`, 820×620). Used by the Saved Lists tab
(double-click an item) to show a container without any way to edit it. Window title `"View — {title}"`; header card
with bold 16 pt Accent title and a muted 11 pt subtitle (default
`"Read-only view — click a link to open it. Editing is disabled."`; Saved Lists passes
`"Saved-list item · {listName} — read-only. Click a link to open it; double-click a file to open it."` or without
` · {listName}` when the list is unnamed). Body: read-only rich text on the light "paper" colours (EditorBg
`#FCFCFC`, EditorFg `#1A1A1A`, main font, 14 pt, padding 8) — empty/whitespace XAML → grey `"(no notes)"`;
`enc:`-prefixed (legacy encrypted) → grey `"(locked content)"`; unparseable XAML → the raw text as one paragraph.
Hyperlinks are clickable (single click) and open via the OS. A 6 px splitter, then a 180 px files pane headed
`"Files — none"` or `"Files ({n}) — double-click to open"`, table columns **Name** (260), **Kind** (80, FileKind
name), **Source** (70: `Web link` / `Live` / `Copy`), **Path / URL** (380, stored path). Double-click opens a file.
Bottom-right: **`Open all files`** (tooltip `"Open every file listed below."`) and **`Close`** (default and cancel:
Enter/Esc). Open-all with no files: `"This item has no files."`, title `"Open all files"`; more than 15 files: confirm
`"Open all {n} files?"` (Yes/No). Opening a missing copy/live file: `"That file is missing:\n\n{path}"`, title
`"Open file"`, Warning. Launch failure: `"Could not open:\n\n{target}\n\n{error}"`, title `"Open"`, Warning.

### O. Persistence & logging

**HIER-140 — Persistence triggers** (summary):

| Action | Persistence |
|---|---|
| Name / Description / Tags typing (page and item window), component name/notes | MarkDirty |
| A→Z toggle, group expand/collapse | MarkDirty |
| New item; group create/rename/delete/assign/ungroup; add/remove relationship; component add/remove; procedure/task Pick… and + New; subtask add/remove; step add/remove/link/+New task; lock set/change/remove | Save |
| Task deadline/start/recurrence/status/completed/job/duration; procedure deadline/recurrence/status/duration | MarkDirty |
| Procedure "schedulable job" checkbox; step Done/Job checkbox; batch done/deadline (when changed) | Flush |
| Batch delete (when n>0) | Save |
| Unlock / Lock again / Lock now | nothing (session only) |
| Export PDF | editor flush + FlushIfDirty before export; checklist export: FlushIfDirty |
| Component/subtask/step editors close | editor flush + FlushIfDirty |
| Rich text (ContainerEditor) | ~400 ms debounce → MarkDirty |

**HIER-141 — Activity log entries written here** (`Data.Log`, UTC, max 10 000, name trimmed, blank → `(unnamed)`):
`Added`/`Equipment/Area|Task|Procedure|Vessel`/name/`""` (New); `Added`/`Procedure`/name/`linked to {eq}`;
`Added`/`Task`/name/`linked to {eq}`; `Added`/`Task`/name/`linked to step '{step}'`; `Added`/`Subtask`/name/`{task}`;
`Removed`/`Subtask`/name/`{task}`; `Added`/`Checklist step`/title/`{procedure}`;
`Removed`/`Checklist step`/title/`{procedure}`; and via Trash: `Removed`/`{KindLabel}`/name/`moved to Trash`.
Components are not logged.

### P. Theming

**HIER-150 — Dark mode.** All chrome uses theme tokens: light = pure white surfaces, black text/accents/borders,
hover `#EFEFEF`, selection `#CCE8FF`; dark = Bg `#1E1E1E`, Panel `#252526`, PanelAlt `#2D2D30`, Accent/SelFg
`#FFFFFF`, Fg `#F0F0F0`, Muted `#B0B0B0`, Border `#3F3F46`, hover `#3A3A3D`, selection `#094771`. Error text is
`#D45050` in both. The rich-text surfaces (ContainerEditor, ContainerViewer) stay light "paper" (`#FCFCFC` /
`#1A1A1A`) in **both** themes so user colours/highlights remain readable. Context menus and date-picker popups are
themed (dark popups with white text in dark mode). Accent buttons are bold. Primary font Consolas 13 pt.

### Q. Mac-only additions (optional; not in Windows — must not replace any feature above)

* **HIER-M01 — Drag to group.** Drag one or more sidebar rows onto a section header (or into a section) to set their
  `GroupId` (Ungrouped header → null); **Save**; same result as HIER-031. (Requested in the port brief; absent on
  Windows.)
* **HIER-M02 — ⌘⌫ / Edit ▸ Delete** runs HIER-022 on the selection (same confirmation).
* **HIER-M03 — Double-click a sidebar row** opens it in its own window (HIER-110). Windows has no double-click action.
* **HIER-M04 — Focus the name field** (all selected) after `+ New`, so the user can type the name immediately.
* **HIER-M05 — Lock glyph** (`lock.fill`, secondary) on sidebar rows of protected items.
* **HIER-M06 — Quick Look** (space bar) on files in the read-only viewer.
* **HIER-M07 — "Bring window to front"** button on the detached note.

---

## 3. Logic & algorithms

### 3.1 Sidebar build — `RefreshList` (`HierarchyPage.xaml.cs:100`)
Inputs: kind's collection (data order), `Data.Groups` of this kind, query, A→Z flag.
```
q      = searchText.trim()
items  = collection                                   // data order
if q != "": items = items.filter { $0.Name.containsOrdinalIgnoreCase(q) }
groups = Data.Groups.filter { $0.Kind == kind }       // creation order
nameOf = dict(group.Id → group.Name)                  // duplicate Ids: first wins (ToDictionary would throw — see note)
rows   = items.map { Row(item: $0, key: nameOf[$0.GroupId] ?? "Ungrouped") }
populated = Set(rows.map(\.key))
for g in groups where !populated.contains(g.Name): rows.append(Row(item: nil, key: g.Name))   // placeholder
sections: group rows by key; order sections by sortKey(key) with OrdinalIgnoreCase,
          sortKey("Ungrouped") = "\u{FFFF}Ungrouped", else key
within section: placeholders last; if A→Z: by Name OrdinalIgnoreCase; else original (data) order
emptyHint(total: collection.count, shown: rows.count{ item != nil }, searching: q != "")
```
Notes:
* An item whose `GroupId` points at a missing group, or at a group of another kind, lands in `Ungrouped`.
* Two groups with the same name, or a user group literally named `Ungrouped`, share one section on Windows (key by
  name). **Mac decision:** section by group **Id** (with the synthetic Ungrouped as its own section), display name =
  group name — the same fix PROGRESS applied to buckets ("grouped by bucket name → collided → now by id"). Expanded
  state is still read/written under `"{Kind}|{Name}"`.
* WPF's `ListCollectionView.CustomSort` is fed an `IComparer` that returns 0 for "keep order"; WPF sorts with
  `ArrayList.Sort` (introsort, **not stable** for >16 elements), so the documented "list order is preserved" is not
  guaranteed on Windows for large groups. **Mac: use a stable sort** (data order) — that is the stated intent
  (tooltip) and what users see for small lists.
* `Data.Groups.ToDictionary(g => g.Id …)` would throw on duplicate group Ids (malformed data); Mac must not crash
  (first wins).
* Duplicate group names sort ties: Mac tie-break = creation order.

**OrdinalIgnoreCase comparison** (used for group order, A→Z, pickers' sort, search `Contains`): compare UTF-16 code
units after mapping each code unit to its **invariant simple uppercase** (`char.ToUpperInvariant`); no culture, no
normalisation, no natural-number ordering. Swift implementation: iterate `utf16`, map each unit through a
single-unit uppercase (e.g. `Character(Unicode.Scalar(u)).uppercased()` only when the result is one UTF-16 unit, else
keep the unit; surrogates unchanged), compare lexicographically. Do **not** use `localizedStandardCompare`,
`caseInsensitiveCompare` with locale, or `String.uppercased()` on whole strings (ß → SS changes lengths).

### 3.2 Selection helpers
* `SelectedHierarchyItems()` (:282): selected rows → their items, placeholders removed, in selection order.
* `SelectItemsByIds(ids)` (:290): clear selection; select every row whose item id ∈ ids (in list order); scroll the
  first into view.
* `SelectItemById(id)` (:30): select the row with that item id (replaces selection; no scroll). Not found → no-op.
* `ReloadList()` (:482): remember current details item id → rebuild → `SelectItemById`.

### 3.3 `WorkRange.Coerce(start, deadline, editedStart)` (`Services/WorkRange.cs:15`)
```
start = start?.date ; deadline = deadline?.date          // drop time-of-day
if let s = start {
    if deadline == nil         { deadline = s }           // a start alone makes a one-day range
    else if s > deadline!      { if editedStart { deadline = s } else { start = deadline } }
}
return (start, deadline)
```
The task-specifics handlers pass the **model's** partner (`t.RangeStart` when the deadline picker changed,
`t.Deadline` when the start picker changed) — never the other picker's value (PROGRESS: stale-sibling data-loss fix).

### 3.4 Tag parsing
* Main pane `ParseTags` (:739): split on any of `,` `;` `\n` `\r` `\t` space (U+0020 only); trim each part
  (`TrimEntries` trims Unicode whitespace); drop empties; strip **all leading `#`** (`TrimStart('#')`); drop parts that
  became empty; de-duplicate case-insensitively (ordinal ignore-case) keeping the **first** occurrence's spelling;
  preserve order.
* Item window (`ItemWindow.xaml.cs:118`): split on `,` only, trim, drop empties. No `#` strip, no de-dup.
* Display: `", "`-join.

### 3.5 Duration text (`BuildTaskSpecifics` :1085, `BuildProcedureSpecifics` :1212)
`int.TryParse(text, out m) && m > 0` (current culture, `NumberStyles.Integer`): leading/trailing whitespace allowed,
optional leading `+`/`-`, ASCII digits only, no thousands separators, must fit Int32. Only then write and
MarkDirty. Mac: `Int32(text.trimmingCharacters(in: .whitespaces))` accepting a leading `+`, and `> 0`.

### 3.6 Relationship queries (`AppRepository.cs`)
* `AllItems()` (:74): Equipment, then Tasks, then Procedures, then Vessels (each in data order). Top level only.
* `FindById(id)` (:82): first in `AllItems()` (subtasks/steps/components are not found).
* `Label(id)` (:143): `"[{Kind}] {Name}"` or `"(missing)"`.
* `RelatedItems(item)` (:150): ordered set = `RelatedIds` ∪ (Equipment: `ProcedureIds` ∪ `TaskIds`), first
  occurrence order; yield those that resolve.
* `ReferencedBy(target)` (:169): for each item in `AllItems()` except the target: `RelatedIds` contains target, or
  (Equipment) `ProcedureIds`/`TaskIds` contains it, or (Procedure) any step's `TaskIds`/`EquipmentIds` contains it.
* `AddRelation(a,b)` (:212): no-op when same id; append b.Id to a.RelatedIds and a.Id to b.RelatedIds if absent.
* `RemoveRelation(a,b)` (:219): remove both ids (all occurrences? — `ObservableCollection.Remove` removes the first
  occurrence only; duplicates cannot arise through the UI).
* `PurgeReferences(id)` (:186) is **not** run on soft delete (only when a Trash entry is permanently removed), so a
  restore brings every link back. Links to trashed items render as `(missing)` in Equipment lists and disappear from
  relationship/backlink lists until then.

### 3.7 `TaskItem.WhenText` (Models.cs:197)
`deadline == nil` → `""`; `start != nil && start.date < deadline.date` → `"{start:yyyy-MM-dd} → {deadline:yyyy-MM-dd}"`;
else `"{deadline:yyyy-MM-dd}"`. Invariant digits. Must re-render when either date changes.

### 3.8 Safe file names (`ExportPdf_Click` :769, `ExportChecklist` :1397)
Replace each char in the **Windows** `Path.GetInvalidFileNameChars()` set with `_`: `"` `<` `>` `|` `:` `*` `?` `\`
`/` and U+0000…U+001F. Everything else (including spaces, dots, emoji) is kept. Use this exact set on the Mac too (so
file names match and are portable to Windows shares). Name source: `item.Name` (`"item"`/`"procedure"` if null —
never null in practice; an empty name yields `Task-.pdf` / `checklist-.pdf`).

### 3.9 Checklist-only export (`ChecklistExporter`, called by `ExportChecklist` :1393)
Common: `FlushIfDirty`; save dialog title `"Export checklist to PDF"` / `"Export checklist to Excel"`, filter
`"PDF document (*.pdf)|*.pdf"` / `"Excel workbook (*.xlsx)|*.xlsx"`, default name `"checklist-{safe}.pdf|xlsx"`;
wait cursor; errors → `"Failed to export checklist:\n{message}"`, title `"Export error"`; then open the file.

**PDF** (A4 portrait, 2 cm margins, body Calibri 11): document title metadata `"Checklist - {name}"`, author `"AA"`;
footer right-aligned 9 pt grey (120,120,120) `"Page {n} / {N}"`; title = procedure name 22 pt bold (space after 2 pt);
subtitle `"Checklist"` grey, space after 10 pt. No steps → italic `"(no steps)"`. Else a table, 0.5 pt borders
(180,180,180), 3 pt padding, columns 0.9 / 1.0 / 7.2 / 2.2 / 5.0 cm, heading row (repeats on each page, shaded
235,235,235, bold): `#`, `Done`, `Step`, `Due`, `Tasks / Equipment-Area`. Rows: 1-based number; `[x]` or `[  ]`
(two spaces); title; deadline `yyyy-MM-dd` or empty; linked refs one per line: `T: {taskName}` for each resolvable
`TaskIds`, then `E/A: {equipmentName}` for each resolvable `EquipmentIds`.

**XLSX** (hand-written SpreadsheetML, DEFLATE entries): parts `[Content_Types].xml`, `_rels/.rels`,
`xl/workbook.xml` (one sheet named after the procedure: XML-escaped, then cut to 31 chars; blank → `Checklist`),
`xl/_rels/workbook.xml.rels`, `xl/styles.xml` (font 0 Calibri 11; font 1 bold; fill 1 solid `FFEEEEEE`; cellXfs 0
normal, 1 bold+fill), `xl/worksheets/sheet1.xml` (column widths 5, 7, 55, 14, 40, 40; every cell an inline string
with `xml:space="preserve"`, header style 1). Header row: `#`, `Done`, `Step`, `Due`, `Linked Tasks`,
`Linked Equipment/Area`. Data rows: number, `Yes`/`No`, title, `yyyy-MM-dd` or empty, task names joined with `"; "`,
equipment names joined with `"; "` (unresolvable ids skipped). Escaping: `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`,
`"`→`&quot;`. An existing file is deleted first. (Mac: reuse the in-house ZIP writer; keep the XML byte-for-byte
where practical; also fix the sheet-name hazards noted in §8 Q-27.)

### 3.10 Recurrence reconcile (context; owned by the repository spec)
After every successful save the shell runs `ReconcileRecurrences()`: each **top-level** Task with
`Recurrence != None && IsComplete && !RecurrenceSpawned` (and each top-level Procedure with `Status == Done`) is
flagged spawned and deep-cloned into a new occurrence (new ids, not complete / Todo, deadline advanced by the
recurrence from the old deadline or today, range length and child deadlines shifted by the same delta), appended to
the collection, logged `"Task (recurring)"` / `"Procedure (recurring)"`, then Tasks/Procedures pages `ReloadList`.
Therefore ticking *Completed* (HIER-082) on a recurring task makes a new sidebar row appear ~0.75 s later.

### 3.11 `BatchDone.SetDone(item, done)` (`Services/BatchDone.cs:16`) — returns true only on real change
* TaskItem: `IsComplete == done` → false; else set `IsComplete` (model syncs Status).
* ChecklistStep: `Done == done` → false; else set.
* Procedure: done → if already `Done` false, else `Status = Done`; not done → only a `Done` procedure becomes `Todo`
  (InProgress/Blocked/Todo untouched → false).
* anything else → false. `SetDoneAll` counts changes.

### 3.12 `BatchDeadline.SetDeadline(item, date)` (`Services/BatchDeadline.cs:16`) — true only on real change
`d = date?.date`.
* TaskItem: `d == nil` → if deadline and start already nil → false; else clear both. Otherwise
  `(ns, nd) = Coerce(t.RangeStart, d, editedStart: false)`; unchanged → false; else set `RangeStart = ns`,
  `Deadline = nd`.
* Procedure / ChecklistStep: equal → false; else set `Deadline = d`.
* else false.

### 3.13 `BatchDelete` (`Services/BatchDelete.cs`)
* `TopLevel(selection)` (:111): unwrap rows (`Item` property) → `HierarchyItem`s, de-dup by Id (first kept), then
  drop any item that is a descendant (`Subtasks`, recursive, cycle-guarded) of another selected TaskItem.
* `Describe(repo, selection)` (:51): for each top-level item: gated → `Locked++` (nothing else counted); else kind
  counter++, `Descendants +=` components count (Equipment) / all nested subtasks (Task) / steps count (Procedure) / 0
  (Vessel); `WithAttachments++` if the item's container or any component/descendant/step container has files
  (Vessel: own container only); `LinkedFromElsewhere++` if `ReferencedBy(item)` is non-empty.
  `Total = Equipment+Tasks+Procedures+Vessels`; `IsEmpty = Total == 0 && Locked == 0`.
* `KindBreakdown()`: parts in the order tasks, procedures, equipment, vessels: `"{n} task(s)"`,
  `"{n} procedure(s)"`, `"{n} equipment/area(s)"`, `"{n} vessel(s)"` (singular when 1); joined `", "`; none →
  `"nothing"`.
* `TrashAll(repo, selection)` (:85): top-level, not gated → `repo.TrashHierarchyItems` (one new `BatchId` shared by
  all; each item serialised to `PayloadJson`, removed from its collection, logged `Removed`/kind label/name/
  `moved to Trash`, Trash pruned to 90 days / 200 entries — eviction scrubs references). Does not save.
* Confirmation prompt (`BatchDeleteMenu.BuildPrompt`), lines joined by `\n`, detail lines indented 4 spaces:
```
Move {Total} items to the Trash?            ← "Move 1 item to the Trash?" when Total == 1
<blank>
    {KindBreakdown}
    {D} subtask/step/component{s} inside them will be deleted too.                 (if D > 0)
    {A} of them ha{s|ve} attached files (the files stay on disk).                  (if A > 0; "has" when 1)
    {L} {is|are} linked from other items; those links show "(missing)" until the Trash is emptied.   (if L > 0)
    {K} locked item{ is| s are} selected and will be skipped.                     (if K > 0)
    Note: the Trash holds 200 items, so the {after-200} oldest will be permanently removed.   (if after > 200)
<blank>
You can restore them from File ▸ Trash, or undo with Ctrl+Z.
```
  where `after = Trash.Count + Total` (current Trash size before deleting).

### 3.14 Lock service (`Services/ItemLockService.cs`)
* Constants: master password `"redemption"`; PBKDF2-HMAC-SHA256, **100 000** iterations, **16-byte** random salt,
  **32-byte** key. Password bytes = **UTF-8** of the string (no BOM, no normalisation).
* `Protect(item, pw, hint)`: empty pw → error; new random salt; `LockHash = base64(pbkdf2)`, `LockSalt =
  base64(salt)` (standard Base64 with padding); `LockHint = blank ? nil : hint.trimmed`; remove from session
  unlocked set (gated at once).
* `RemoveProtection`: hash/salt/hint → nil; remove from unlocked set.
* `Verify(item, pw)`: `pw == "redemption"` (ordinal) → true (even for an unprotected item); not protected or empty
  pw → false; else constant-time compare of PBKDF2(pw, base64decode(salt)) with base64decode(hash); any decode error →
  false.
* `TryUnlock`: Verify then add id to the session set. `IsGated = IsLockProtected && !unlocked.contains(id)`.
  `Relock(item)`: remove id. `RelockAll()`: clear. Session set is in memory only (process-wide).
* `IsLockProtected` = `LockHash` and `LockSalt` both non-null and non-empty (a hint alone is not a lock).

### 3.15 Item-window registry (`MainWindow.xaml.cs:186-243`) — see HIER-110…117.

---

## 4. Data formats

### 4.1 Serializer facts (must be matched exactly — see architecture brief)
`DataStore.Opts`: **no naming policy** (PascalCase keys = C# property names), **no enum converter** (enums are
**integers**), `DefaultIgnoreCondition = WhenWritingNull` (null members omitted), compact, `IgnoreCycles`.
`[JsonIgnore]` members (`Kind`, `IsLockProtected`, `HasRange`, `RangeFirst`, `WhenText`, `JobName`, `SourceLabel`, …)
are never written. `BucketId` (legacy) is never written (getter returns null) but is **read** and migrated into
`BucketIds`. Property names are case-sensitive on read in .NET (Mac should read tolerantly but write exactly).
Property **order**: System.Text.Json walks the type hierarchy from the most-derived type upward, so a derived type's
own properties are written before `HierarchyItem`'s (verify against a Windows-written `data.json` fixture before
relying on it; readers must be order-independent **except** for setter side-effects — see 4.4).

Enum values:
| Enum | Values |
|---|---|
| `ItemKind` | Equipment 0, Task 1, Procedure 2, Vessel 3 |
| `RecurrenceKind` | None 0, Daily 1, Weekly 2, Monthly 3, Yearly 4 |
| `WorkStatus` | Todo 0, InProgress 1, Blocked 2, Done 3 |
| `FileKind` | Document 0, Image 1, Video 2, Link 3, Other 4 |

GUIDs: lowercase `8-4-4-4-12`. `Guid.Empty` = `"00000000-0000-0000-0000-000000000000"` (written, e.g. `BatchId`).

Dates: `DateTime` ISO-8601. Date pickers yield `Kind=Unspecified` midnight → written `"2026-10-01T00:00:00"` (no
offset, no fraction). `DateTime.Now`/`Today` values are `Local` → `"…+hh:mm"`; `UtcNow` → `"…Z"`; fractions up to
7 digits when non-zero. **Mac rule for every date this subsystem writes (task `Deadline`/`RangeStart`, procedure
`Deadline`, step `Deadline` via batch):** local calendar date at midnight, *Unspecified* form, no offset. When
reading a value with an offset, convert to local time like .NET does before taking the date.

### 4.2 Fields read/written by this subsystem

`AppData` collections: `Equipment`, `Tasks`, `Procedures`, `Vessels` (arrays, data order = sidebar order),
`Groups`, `Log`, `Trash`, `Ui`.

**`HierarchyItem`** (common to all four kinds):
| Key | Type | Notes |
|---|---|---|
| `Id` | guid | new random on create |
| `Name` | string | default `""`; not trimmed |
| `Description` | string | `""` |
| `Container` | object | `{Id, RichTextXaml, Files[], SharedWithContainerIds[], IsLocked}` (container spec) |
| `RelatedIds` | guid[] | two-way links |
| `Tags` | string[] | HIER-027 |
| `GroupId` | guid? | omitted when ungrouped |
| `BucketIds` | guid[] | **not edited here** (Buckets / quick-work); must round-trip untouched |
| `LockHash`, `LockSalt` | string? (base64) | omitted when unlocked; both required for a lock |
| `LockHint` | string? | omitted when none |

**`Equipment`**: `ProcedureIds` (guid[], one-way), `TaskIds` (guid[], one-way), `Components`
(`[{Id, Name, Notes, Container}]`).
**`TaskItem`**: `Deadline` (date?), `RangeStart` (date?, omitted when null — zero migration), `IsJob` (bool),
`DurationMinutes` (int, default 60), `ScheduledStart` (datetime?, Planner), `Recurrence` (int), `RecurrenceSpawned`
(bool), `IsComplete` (bool), `Status` (int), `Subtasks` (TaskItem[] recursive).
**`Procedure`**: `Steps`, `Deadline`, `Recurrence`, `RecurrenceSpawned`, `Status`, `IsJob`, `DurationMinutes`,
`ScheduledStart`.
**`ChecklistStep`**: `Id`, `Title`, `BucketIds`, `Done`, `Deadline`, `IsJob`, `DurationMinutes`, `ScheduledStart`,
`TaskIds`, `EquipmentIds`, `Container`.
**`Vessel`**: `QuickCards`, `Jobs`, `NotificationsEnabled`, `PortCalls` (vessels spec) + common fields.
**`ItemGroup`** (`AppData.Groups`): `Id`, `Kind` (int), `Name`, `Expanded` (bool, default `true`, **unused by the UI**
— preserve whatever was read; write `true` for new groups).
**`UiState`** keys used: `SortAZ` (`{"Equipment":true,"Task":false,…}` — shared preference), `GroupExpanded`
(`{"Task|Engine room":false,…}` — per-device, never sent by Flash Sync), `SelectedEquipmentId`, `SelectedTaskId`,
`SelectedProcedureId`, `SelectedVesselId` (per-device).
**`LogEntry`**: `TimestampUtc` (UTC, `Z`), `Action` (`"Added"|"Removed"`), `Kind`, `Name`, `Detail`.
**`TrashedItem`**: `Id`, `ItemType` (`"Equipment"|"Task"|"Procedure"|"Vessel"|"Crew"`), `ItemId`, `BatchId`, `Name`,
`KindLabel`, `DeletedUtc`, `PayloadJson` (a JSON **string** containing the item serialised with the same options,
full subtree).

### 4.3 Example (formatted for reading; the real file is compact)
```json
{
  "Equipment": [{
    "ProcedureIds": ["5b1c…"], "TaskIds": [], "Components": [
      {"Id":"0d4e…","Name":"Purifier bowl","Notes":"Alfa Laval MOPX","Container":{"Id":"…","RichTextXaml":"","Files":[],"SharedWithContainerIds":[],"IsLocked":false}}],
    "Id":"9a7f…","Name":"Engine room","Description":"","Container":{…},"RelatedIds":[],"Tags":["machinery"],
    "GroupId":"c3d2…","BucketIds":[]
  }],
  "Tasks": [{
    "Deadline":"2026-10-01T00:00:00","RangeStart":"2026-09-28T00:00:00","IsJob":true,"DurationMinutes":90,
    "Recurrence":3,"RecurrenceSpawned":false,"IsComplete":false,"Status":1,"Subtasks":[],
    "Id":"7e21…","Name":"Monthly fire drill","Description":"","Container":{…},"RelatedIds":["9a7f…"],
    "Tags":["safety","drill"],"BucketIds":[],
    "LockHash":"murxLdSppVnVeZbxy4IbgWXYCiM9PftQyX18mD8jBNE=","LockSalt":"AAECAwQFBgcICQoLDA0ODw==","LockHint":"usual"
  }],
  "Groups": [{"Id":"c3d2…","Kind":0,"Name":"Machinery","Expanded":true}],
  "Ui": {"SortAZ":{"Task":true},"GroupExpanded":{"Equipment|Machinery":false},"SelectedTaskId":"7e21…"},
  "Log": [{"TimestampUtc":"2026-09-29T08:15:02.1234567Z","Action":"Added","Kind":"Task","Name":"Monthly fire drill","Detail":""}]
}
```

### 4.4 Cross-version / compatibility rules
* **Status ⇄ IsComplete setter coupling** is applied during deserialisation in JSON key order (Windows setters run
  as properties are read). The Mac model loader must reproduce the final state .NET would reach for the same key
  order (models spec). This subsystem only writes consistent pairs.
* Unknown members must survive a load/save (Mac preserves them on every object; Windows on `AppData`/`UiState`).
* Groups are matched to pages by `Kind`; a group is **not** deleted when it becomes empty.
* `GroupExpanded` keys use the enum *name* (`Equipment`, not `Equipment/Area`) and the group *name*.
* Locks: hashes written by the Mac must verify on Windows and vice versa (identical PBKDF2 parameters, UTF-8,
  standard Base64). The master password must remain `redemption` for compatibility.
* Soft-deleted items keep their links (no purge) so a restore on either platform is lossless.

### 4.5 Files written
* Item PDF: `"{Kind}-{safe}.pdf"` via `PdfExporter.Export` (export spec).
* Checklist PDF/XLSX: §3.9.

### 4.6 Rich-text XAML consumed here
The ContainerViewer (HIER-136) loads `Container.RichTextXaml` exactly as the editor stores it:
`TextRange.Save(DataFormats.Xaml)` output, i.e. a `<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" …>`
root carrying document-level font/colour attributes, containing `Paragraph`, `List`/`ListItem` (with `MarkerStyle`),
`Table`/`TableRowGroup`/`TableRow`/`TableCell`, and inlines `Run`, `Span`, `Bold`, `Italic`, `Underline`,
`Hyperlink` (`NavigateUri`), `LineBreak`, with attributes such as `FontFamily`, `FontSize`, `FontWeight`, `FontStyle`,
`Foreground`, `Background` (the edit-lock sentinel `#FFFFE699` on runs), `TextDecorations`, `TextAlignment`,
`Margin`. The full vocabulary and its NSAttributedString mapping are owned by the container-editor spec; the viewer
must use the same XAML→NSAttributedString converter, render read-only, and make `Hyperlink.NavigateUri` clickable.
Special values: empty/whitespace → `(no notes)`; prefix `enc:` → `(locked content)`; parse failure → raw text.
The item window and component editor write XAML only through the shared ContainerEditor.

---

## 5. Dependencies

### 5.1 Calls out of this subsystem
| Target | Functions |
|---|---|
| `AppRepository` | `Data`, `AllItems`, `FindById`, `Label`, `RelatedItems`, `ReferencedBy`, `AddRelation`, `RemoveRelation`, `GroupsFor`, `CreateGroup`, `RenameGroup`, `DeleteGroup`, `LogAdded`, `LogRemoved`, `KindLabel`, `MarkDirty`, `Save`, `FlushIfDirty`, `TrashHierarchyItems` (via BatchDelete), `MaxTrashItems`, `Data.Trash.Count` |
| `ItemLockService` | `IsGated`, `Protect`, `RemoveProtection`, `TryUnlock`, `Relock` (`RelockAll` from shell) |
| `WorkRange` | `Coerce` |
| `BatchDone` / `BatchDeadline` / `BatchDelete` | `SetDoneAll` / `SetDeadlineAll` / `Describe`, `TrashAll` |
| `ContainerEditor` | `Load(container, repo)`, `FlushPending()`, `IsEnabled` |
| `QuickCardsPanel`, `ShipJobsPanel`, `PortsPanel` | `Load(vessel, repo)` |
| `SubtaskBuilderWindow`, `SubtaskEditorWindow`, `ChecklistBuilderWindow`, `ChecklistStepEditorWindow`, `ComponentEditorWindow` | constructors `(model, repo)`, shown modally |
| `PdfExporter` | `Export(item, repo, path)` |
| `ChecklistExporter` | `ExportPdf(proc, repo, path)`, `ExportXlsx(proc, repo, path)` |
| `PasswordService` | `IsEncrypted` (viewer) |
| `DataStore` | `ResolveFilePath` (viewer) |
| `UiTree` | `FindAncestor<ListBoxItem>` (right-click rule) |
| Shell (`MainWindow`) | status text `StatusBlock` (found by name from the page) |

### 5.2 Calls into this subsystem (public surface of `HierarchyPage`)
`Init(repo, kind)`, `SelectedItemId`, `SelectItemById(id)`, `ReloadList()`, `FlushPendingEditors()`,
`BeginRename()`, `RelockCurrent()`, `DetachItem(id)`, `ReattachItem(id)`, `IsDetached(id)`; callbacks set by the
shell: `Navigate`, `OpenInWindow`, `ItemsDeleted`. `ItemWindow`: `ItemId`, `SetRepo`, `Flush`, `GoOrphaned`,
`NameChanged`. Shared dialogs/menus (§2 N) are used by Board, Calendar, Buckets, Saved Lists, quick-work, SIRE,
schedule builder, subtask builder, checklist builder control, quick-card editor, container editor.

### 5.3 Windows-only APIs used here
`Microsoft.Win32.SaveFileDialog`; `Process.Start(… UseShellExecute = true)` (open PDF/XLSX/files/links);
`Mouse.OverrideCursor = Wait`; `MessageBox.Show` (Yes/No/Cancel semantics, icons, default button);
WPF `Window.Owner` + `ShowDialog` (modal windows) and owned modeless windows; `Dispatcher.BeginInvoke` with
priorities (focus the unlock box at `Input` priority; select after tab switch at `Background`);
`Path.GetInvalidFileNameChars` (Windows set); `System.Security.Cryptography` (`Rfc2898DeriveBytes.Pbkdf2`,
`RandomNumberGenerator`, `CryptographicOperations.FixedTimeEquals`); WPF `RichTextBox` + `TextRange.Load(Xaml)`
(viewer), `Hyperlink.RequestNavigate`; `ListCollectionView` grouping/sorting; `GridView`/`ListView`;
`DatePicker` (nullable); `Expander`; `ToggleButton`; `PasswordBox`. No DPAPI, Win32 P/Invoke, OpenCV or
DirectShow in this subsystem.

---

## 6. macOS adaptation

### 6.1 Structure
* `HierarchyTabView(kind:)` — one SwiftUI view reused for the four main tabs. Content: a two-column layout,
  sidebar + detail. Prefer `NavigationSplitView(columnVisibility:) { sidebar } detail: { detail }` with
  `.navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 480)`; if nesting inside the main tab shell misbehaves,
  use `HSplitView` with the same widths. The split position may be remembered per kind (not persisted on Windows;
  harmless addition via `@SceneStorage`).
* Pure, testable logic in `AACore`: `HierarchySidebarBuilder.sections(kind:items:groups:query:sortAZ:)`,
  `TagParser.parse(_:)`, `TagParser.parseCommaOnly(_:)`, `WorkRange.coerce`, `BatchDone`, `BatchDeadline`,
  `BatchDelete.describe/trashAll/prompt`, `ItemLockService`, `SafeFileName.windowsSafe(_:)`,
  `OrdinalIgnoreCase.compare/contains`, `ChecklistExporter.pdf/xlsx`.
* State: `@Observable @MainActor AppStore` owns data; views bind directly to model objects (reference types) so the
  sidebar, detail, Board, Calendar etc. are always live (fixes the Windows stale-sidebar cases).

### 6.2 Sidebar
* `List(selection: $selection)` (`Set<UUID>`, multi-select) with `.listStyle(.sidebar)`; one `Section(isExpanded:)`
  per sidebar section; header `HStack { Text(name).bold(); Text("(\(count))").foregroundStyle(.secondary) }` where
  `count` = real items (0 for an empty group — §8 Q-02). `isExpanded` binds to `Ui.GroupExpanded["\(kind)|\(name)"]`
  (missing ⇒ true), writing + `markDirty()` only on change.
* Placeholder rows: `Text("(empty — right-click an item to assign)").foregroundStyle(.secondary)` with
  `.selectionDisabled()`.
* Rows: `Text(item.name)` with unlimited lines (wrapping). Optional lock glyph (HIER-M05).
* Search: `.searchable(text:placement: .sidebar, prompt: "Search...")`; live filtering per keystroke (Windows is
  synchronous per keystroke; fine for thousands of rows — memoise the section build keyed on the inputs).
* Sidebar toolbar: a compact control row above the list (or `.toolbar` items when the sidebar has focus): a
  `Toggle("A→Z", isOn:)` with `.toggleStyle(.button)` (SF Symbol `textformat.abc`), `+ Group` (`folder.badge.plus`),
  `Assign group…` (`folder`), `Rename group…` (`pencil`), `Delete group` (`folder.badge.minus`); keep the Windows
  captions as labels and tooltips via `.help(...)`. `+ New` (`plus`, prominent) and `Delete` (`trash`) at the top.
* Context menu: `.contextMenu(forSelectionType: UUID.self) { ids in … } primaryAction: { ids in /* HIER-M03 */ }`.
  This gives exactly the HIER-017 rule (right-click inside the selection targets the whole selection; outside it
  targets only the clicked row) without changing the selection — the native Mac idiom (Windows actually changes the
  selection; accepted difference). Empty-area right-click yields an empty set: show `New group…` enabled and item
  actions disabled.
* Drag to group (HIER-M01): rows `.draggable(item.id)` (or `onDrag` with multi-selection ids); section headers
  `.dropDestination(for: UUID.self)`.
* Keyboard: ⌘A select all; Return or F2 → rename (focus name field); ⌘⌫ → delete (HIER-M02); arrow keys native.

### 6.3 Detail pane
* Empty selection: `ContentUnavailableView("No Selection", systemImage: "sidebar.left", description: Text("Select an item in the sidebar."))`
  instead of the disabled stale pane.
* Header: `TextField("Name", text:)` (large, `.font(.title3)`), `TextField("Description", text:, axis: .vertical)`
  (1–4 lines, Return commits, ⌥Return newline), Tags as a text field with the same live parsing and on-blur
  normalisation (a token field is acceptable only if it preserves the exact parse/normalise semantics and the
  `", "` display). Commit on `.onSubmit` and on focus loss (`@FocusState`) → re-sort/re-section preserving
  selection **without** resetting the vessel's selected sub-tab (§8 Q-32).
* Header trailing buttons: `Button("Lock Again", systemImage: "lock")` (conditional), Lock button
  (`Label("Lock", systemImage: "lock")` / `Label("Locked", systemImage: "lock.open")`), `Button("Export PDF…",
  systemImage: "doc.richtext")`. These may alternatively live in the window toolbar while the tab is active.
* Tabs: `TabView(selection:)` with Mac-style tabs (or a segmented `Picker` above the content): vessel-only tabs
  first, then "Container" (label it **"Notes & Files"** on Mac only if the other specs agree; otherwise keep
  "Container"), "Relationships", Specifics title per kind. Front Quick Cards when a vessel is selected; keep the
  current tab for other kinds.
* Detached state: a centred card with the Windows text + "Bring Window to Front" (HIER-M07); header and tabs
  disabled; Relationships/Specifics must show the *selected* item (or be hidden), never the previous item's (§8 Q-16).

### 6.4 Lock gate
* Overlay view over the tabs, header hidden: `Image(systemName: "lock.fill").font(.system(size: 44))`, title,
  subtitle, `SecureField` (280 pt, `.onSubmit` unlock, focused via `@FocusState` on appear), error `Text` in
  `#D45050`, buttons `Show Hint` and `Unlock` (`.borderedProminent`, `.keyboardShortcut(.defaultAction)`), hint text.
  Background `.regularMaterial` or the Panel token.
* `ItemLockService` is a `@MainActor` singleton holding `Set<UUID>`; views observe it so every page and window
  re-gates instantly.
* PBKDF2 via CommonCrypto `CCKeyDerivationPBKDF(kCCPBKDF2, pw, pwLen, salt, 16, kCCPRFHmacAlgSHA256, 100_000,
  out, 32)`; random salt via `SecRandomCopyBytes`; constant-time compare (XOR-accumulate). Run the derivation off the
  main actor (100 k iterations ≈ tens of ms) but keep the UI state change on main.
* Manage-lock choice: `.confirmationDialog("Manage lock", …)` with message
  `"This entry is locked."` and buttons "Change Password / Hint…", "Remove Lock" (`.destructive`), "Cancel" — or an
  `NSAlert` reproducing the Windows text verbatim. Either way the three outcomes must match HIER-054.
* Touch ID: **not** added by default (it would be a new unlock factor; see §9).

### 6.5 Dialogs → sheets
| Windows | Mac |
|---|---|
| `PromptWindow` | `.sheet` with title, label, `TextField` (focused, text selected), Cancel (Esc) / OK (Return, `.defaultAction`). Returns raw text. |
| `ItemPickerWindow` | `.sheet` (min 420×460): prompt as header, `TextField` search (focused), `List` with checkboxes (multi) or radio (single), Cancel/OK. Keep a selection **set independent of the filter** (§8 Q-13); OK returns tags in selection order. Double-click in single mode = OK (addition). |
| `DatePromptWindow` | `.sheet`: title, prompt, an optional-date control (graphical `DatePicker` + "no date" state since `DatePicker` cannot be empty), buttons Clear deadline / Cancel / OK with the same result semantics and the same "Pick a date…" message when OK has no date. |
| `ItemLockWindow` | `.sheet` with two `SecureField`s + hint `TextField`, inline red error, Cancel/OK. |
| `ComponentEditorWindow` | large `.sheet` (≈900×700) or a modal window: Name, Short notes, embedded Mac ContainerEditor, "Close" (`.defaultAction`/Esc); flush + `flushIfDirty()` on dismiss. |
| `MessageBox` | `.alert`/`NSAlert` with the same text; destructive confirmations default to **Cancel** (batch delete default = No). |
| `SaveFileDialog` | `NSSavePanel` (`allowedContentTypes` `.pdf` / `UTType(filenameExtension: "xlsx")`, `nameFieldStringValue` from §3.8, title as Windows). |
| `Process.Start(file)` | `NSWorkspace.shared.open(url)`; Windows paths in-place links → per architecture brief (UNC → `smb://`). |
| Wait cursor | `ProgressView` overlay / disabled buttons while exporting off the main actor from a snapshot. |

Every modal that on Windows lacks `IsCancel` must still cancel on **Esc** on the Mac (standard behaviour).

### 6.6 Specifics tabs
* Tables: SwiftUI `Table(selection:)` with `TableColumn`s and `.contextMenu(forSelectionType:)`. Components: Name,
  Notes (single selection). Subtasks: Name (wrapping, `.strikethrough(item.isComplete)`), When, Status (enum name),
  Done (read-only `checkmark` glyph). Steps: Done (`Toggle` in cell → flush), Job (`Toggle`, `.help(...)` → flush),
  Title (wrapping, strikethrough when done), Deadline (`yyyy-MM-dd`). Double-click via `primaryAction:` opens the
  editor (exclude clicks on the toggles — §8 Q-23).
* Optional dates: build an `OptionalDateField` (shows `—` + "Set…"; when set, a compact `DatePicker` plus a clear
  (`xmark.circle.fill`) button). Deadline/Start pickers call `WorkRange.coerce` against the model on every change.
* Recurrence/Status: `Picker` with the enum names as shown on Windows (`Todo`, `InProgress`, …) — or friendlier
  labels ("To Do", "In Progress") **only** if every other spec does the same; values must map to the same integers.
* Duration: `TextField` with the §3.5 parse; invalid input is ignored (keep the text; optional red outline).
* Banner buttons: `Button { } label: { Label("Open Comprehensive Subtask Builder", systemImage: "hammer") }`
  full-width `.borderedProminent`, `.controlSize(.large)`.

### 6.7 Item windows (multi-window)
* Scene: `WindowGroup("Item", id: "item", for: UUID.self) { $id in ItemWindowView(itemID: id) }` with
  `.defaultSize(width: 900, height: 720)` and **`.restorationBehavior(.disabled)`** (Windows never reopens item
  windows after restart; restoring them would also need the detach registry rebuilt at launch).
  `openWindow(id: "item", value: item.id)` focuses an existing window for the same id (HIER-113).
* Registry: `AppStore.detachedItemIDs: Set<UUID>` — insert in the window's `onAppear` (before binding its editor)
  and after flushing the main pane; remove in `onDisappear` after the window's editor flushed; the main pane observes
  it (detach/reattach become automatic).
* Orphaning: the window resolves `store.item(id:)` on every render; `nil` ⇒ orphaned (read-only + message). This
  covers reloads **and** deletion from any path (Board, quick-work) — fixes §8 Q-19.
* Title: `.navigationTitle("\(kindName) — \(name.isEmpty ? "(unnamed)" : name)")`.
* Flush registry: every Mac ContainerEditor registers a flush closure with `EditorFlushCenter`; save (⌘S), autosave,
  sync, export, reload, quit and open-in-window call `flushAll()`.
* Lock now: flush and gate (overlay the lock gate inside) any open item window whose item is now gated (§8 Q-18).

### 6.8 Read-only viewer
`Window`/sheet with a non-editable, selectable `NSTextView` (via `NSViewRepresentable`) showing the converted
attributed string on the fixed light paper colours in both appearances; links open through
`textView(_:clickedOnLink:at:)` → `NSWorkspace.open`; files in a `Table` with the four columns; double-click opens;
space = Quick Look (`QLPreviewPanel`) as an addition; "Open All Files" / "Close" (`.cancelAction` + `.defaultAction`).

### 6.9 Keyboard map
| Windows | Mac |
|---|---|
| F2 (rename, not while typing) | F2 **and** Return on a focused sidebar row |
| Enter in Name box | Return (commit + re-sort) |
| Enter in unlock box | Return |
| Ctrl+Z (undo delete, not while typing) | ⌘Z via the window `UndoManager` / Edit ▸ Undo "Undo Delete" calling `UndoLastDelete` when no text view is first responder; text views keep their own undo |
| Ctrl+A in lists | ⌘A |
| Ctrl+1…9 (tabs) | ⌘1…⌘9 (shell) |
| Ctrl+N / Ctrl+O / Ctrl+F / Ctrl+S / Ctrl+R | ⌘N (quick work) / ⌘O / ⌘F / ⌘S / ⌘R (shell) |
| — | ⇧⌘N "New {kind}" (+ New), ⌘⌫ delete selection (additions) |
| Esc in dialogs (not supported on Windows) | Esc cancels every sheet |

User-visible strings that mention Windows shortcuts (`Ctrl+Z`, `Ctrl+N`, `Ctrl+O`) are rendered with the Mac
equivalents (`⌘Z`, `⌘N`, `⌘O`); `File ▸ Trash` stays if the Mac menu keeps Trash under File.

### 6.10 Visual & dark mode
* Follow the tokens of HIER-150 (translated to `Color` tokens that follow both the system appearance and the app's
  own dark toggle); sidebar may use the standard sidebar material. Keep rich-text surfaces light paper in dark mode.
* SF Symbols replace emoji used as icons (`🔒`→`lock`, `🔓`→`lock.open`, `🗑`→`trash`, `✓`→`checkmark.circle`,
  `○`→`circle`, `📅`→`calendar`, `🛠`→`hammer`, `↩`→`arrow.uturn.backward`), keeping the text captions.
* Animations: section expand/collapse and lock-overlay cross-fade (`.animation(.snappy)`); avoid animating list
  rebuilds while typing in the search field.

### 6.11 Genuinely impossible / different on macOS
Nothing here is impossible. Accepted platform differences: (1) right-click does not change the selection (native
contextMenu targeting); (2) owned-window z-order (Windows item windows float above the main window) is not replicated
— Mac windows are peers; (3) Windows date pickers accept typed free text — the Mac uses native date fields.

---

## 7. Test vectors / verification

### 7.1 Tag parsing (`TagParser.parse`)
| Input | Output |
|---|---|
| `"pump, #Engine;  main\tpump"` | `["pump","Engine","main"]` |
| `"##a b"` | `["a","b"]` |
| `"#"` / `", ,;"` / `""` | `[]` |
| `"a,A,a"` | `["a"]` |
| `"Été été ÉTÉ"` | `["Été"]` (ordinal ignore-case folds é/É) |
| `"x\r\ny"` | `["x","y"]` |
Display join: `["a","b"]` → `"a, b"`.
Item-window parse (`parseCommaOnly`): `"#a b, c ,,d, c"` → `["#a b","c","d","c"]`.

### 7.2 `WorkRange.coerce`
| start | deadline | editedStart | → start | → deadline |
|---|---|---|---|---|
| nil | nil | any | nil | nil |
| 2026-01-05 | nil | true | 2026-01-05 | 2026-01-05 |
| 2026-01-10 | 2026-01-05 | true | 2026-01-10 | 2026-01-10 |
| 2026-01-10 | 2026-01-05 | false | 2026-01-05 | 2026-01-05 |
| 2026-01-03 | 2026-01-05 | any | 2026-01-03 | 2026-01-05 |
| nil | 2026-01-05 | any | nil | 2026-01-05 |
| 2026-01-03 | nil (deadline cleared) | false | 2026-01-03 | 2026-01-03 |
| 2026-01-05 15:30 | 2026-01-07 08:00 | any | 2026-01-05 00:00 | 2026-01-07 00:00 |

### 7.3 `WhenText`
deadline nil → `""`; deadline 2026-10-01 → `"2026-10-01"`; start 2026-09-28 + deadline 2026-10-01 →
`"2026-09-28 → 2026-10-01"`; start == deadline → `"2026-10-01"`; start 2026-10-05 > deadline 2026-10-01 (bad data) →
`"2026-10-01"`.

### 7.4 Batch deadline
* Task start 01-10, deadline 01-12; set 01-08 → start 01-08, deadline 01-08, returns true.
* Task start 01-10, deadline 01-12; set 01-11 → start 01-10, deadline 01-11, true.
* Task with deadline+start; clear → both nil, true; clear again → false.
* Procedure deadline 01-05; set 01-05 (with time 13:00) → false (date equal).
* Mixed `[task, step, procedure, "string"]` set 02-01 → 3 changed.
* Prefill: selection deadlines `[nil, nil]` → initial nil; `[01-05, 01-05]` → 01-05; `[01-05, nil]` → nil.
* Prompt text: 1 → `"Apply one deadline to 1 selected item:"`; 3 → `"Apply one deadline to 3 selected items:"`.

### 7.5 Batch done
* Task InProgress, not complete, set not-done → false, status stays InProgress.
* Task Done, set not-done → true, `IsComplete=false`, `Status=Todo`.
* Task Todo, set done → true, `Status=Done`.
* Procedure Blocked, not-done → false; Procedure Done, not-done → true (`Todo`); Procedure InProgress, done → true.
* Step done→done → false.

### 7.6 Batch delete
* Selection: Task A (subtasks B→[C], D), Procedure P (4 steps, one step with a file), Equipment E (2 components),
  locked Task L (gated). `Describe` → Tasks 1, Procedures 1, Equipment 1, Locked 1, Descendants 3+4+2 = 9,
  WithAttachments 1, LinkedFromElsewhere = count of those with backlinks, Total 3.
  `KindBreakdown` = `"1 task, 1 procedure, 1 equipment/area"`.
* `KindBreakdown` with 2 equipment → `"2 equipment/areas"`; with nothing → `"nothing"`.
* Prompt with Total 3, D 9, A 1, L 2, K 1, Trash.Count 199:
```
Move 3 items to the Trash?

    1 task, 1 procedure, 1 equipment/area
    9 subtask/step/components inside them will be deleted too.
    1 of them has attached files (the files stay on disk).
    2 are linked from other items; those links show "(missing)" until the Trash is emptied.
    1 locked item is selected and will be skipped.
    Note: the Trash holds 200 items, so the 2 oldest will be permanently removed.

You can restore them from File ▸ Trash, or undo with Ctrl+Z.
```
* All-locked selection of 2 → message `"All 2 selected items are locked. Unlock them before deleting."`.
* Selecting a task and its own subtask (e.g. from another list) → the subtask is dropped by `TopLevel`.
* After `TrashAll` of 3 items: 3 Trash entries share one non-empty `BatchId`; one `UndoLastDelete` restores all 3
  (same ids, **new** objects) and returns the distinct item types.

### 7.7 Sidebar build
* Groups `["beta","Alpha"]`, items `x`(beta), `y`(none), `z`(Alpha) → sections `Alpha[z]`, `beta[x]`, `Ungrouped[y]`.
* No groups, items `[b, A, c]`, A→Z off → one section `Ungrouped [b, A, c]`; on → `[A, b, c]`.
* A→Z on, names `["_x","Zed","apple","10","9"]` → `["10","9","apple","Zed","_x"]` (ordinal upper: `1`<`9`<`A`<`Z`<`_`).
* Empty group `Spare` + query `"pump"` with no matches in `Spare` → section `Spare` with only the placeholder
  (Windows); Mac decision §8 Q-03: hide groups with no matches while searching.
* Query `"  PuMp "` matches `"Fuel pump"` (trimmed, case-insensitive), not tags.
* Item with `GroupId` of a deleted group → `Ungrouped`.
* Expanded keys: collapsing `Ungrouped` on Tasks writes `GroupExpanded["Task|Ungrouped"] = false`.

### 7.8 Locks (PBKDF2-HMAC-SHA256, 100 000 iterations, 32 bytes, salt = bytes 0x00…0x0F = `AAECAwQFBgcICQoLDA0ODw==`)
| password | expected `LockHash` |
|---|---|
| `hunter22` | `murxLdSppVnVeZbxy4IbgWXYCiM9PftQyX18mD8jBNE=` |
| `pässwörd` (UTF-8) | `trmn14eaJqetmcWSJJwUWVLKUOyf765hiEQzeYnvalM=` |
| `abcd` | `x/xHrQBjPHyVN9hXauwnarZ7Z/VWb/IqpliZy1EAn64=` |
| `redemption` | `1+930ag9iT2JBP4/zxFyJccLLHJhA+CvurBLnPPS7Hc=` |
* `Verify(item{hash(hunter22), salt}, "hunter22")` → true; `"Hunter22"` → false; `""` → false;
  `"redemption"` → true; `"Redemption"` → false; unprotected item + `"redemption"` → true; unprotected + other → false;
  corrupt Base64 salt → false (no crash).
* `Protect` with hint `"   "` → `LockHint` nil (omitted from JSON); with `"  my dog "` → `"my dog"`.
* Lock dialog validation: `""` → `"Password cannot be empty."`; `"abc"` → `"Password must be at least 4 characters."`;
  `"abcd"`/`"abce"` → `"Passwords do not match."`; `"😀😀"` (4 UTF-16 units) passes the length rule.
* Gate: protect → gated; TryUnlock → not gated; Relock → gated; RelockAll → all gated; RemoveProtection → not gated
  and hash/salt/hint nil.

### 7.9 Safe file names
`"Pump: A/B?"` (Task) → `"Task-Pump_ A_B_.pdf"`; `"Fire drill"` (Procedure checklist) → `"checklist-Fire drill.xlsx"`;
`""` (Vessel) → `"Vessel-.pdf"`; `"a\tb"` → `"a_b"` (tab is a control char).

### 7.10 Checklist XLSX
Procedure `"Fire & rescue"` with steps `[{Title:"Muster", Done:true, Deadline:2026-10-01, TaskIds:[t1(“Count crew”)], EquipmentIds:[missing]}, {Title:"<Brief>", Done:false}]` →
sheet name `Fire &amp; rescue`; rows: header; `["1","Yes","Muster","2026-10-01","Count crew",""]`;
`["2","No","&lt;Brief&gt;","","",""]` (escaped in XML). Re-open the zip and assert entry names and header cells.

### 7.11 Relationships
* A.RelatedIds=[B], B.RelatedIds=[A]; RemoveRelation(A,B) → both empty.
* Equipment E with ProcedureIds [P], RelatedIds [P, T] → `RelatedItems(E)` = [P, T] (deduped, first-occurrence order).
* `ReferencedBy(T)` where procedure Q has a step with TaskIds [T] and E.TaskIds contains T → [E, Q] (AllItems order:
  Equipment before Procedures).
* `Label(missingId)` → `"(missing)"`; `Label(E.Id)` → `"[Equipment] {E.Name}"`.
* Add-relationship candidate order for items [Vessel "a", Task "B", Equipment "c", Task "a"] (self excluded) →
  `[Equipment] c`, `[Task] a`, `[Task] B`, `[Vessel] a`.

### 7.12 Messages
Delete n=1 name `Pump` → status `"'Pump' moved to Trash — Ctrl+Z to undo."` (Mac: `⌘Z`); n=4 →
`"4 items moved to Trash — Ctrl+Z to undo them all."`. Assign title for 1 item `Pump` → `"Move 'Pump' to group"`;
for 3 → `"Move 3 items to group"`. Unlock failure text exact per HIER-051.

### 7.13 Multi-window (UI tests / manual)
Open two tasks and a procedure in windows; type in each; ⌘S in the main window; quit; relaunch → all three notes
present. Open the same item twice → one window. Delete a detached item (sidebar, Board, quick-work) → its window
becomes read-only with the orphan message. Reload data while a window is open → the window re-binds to the new
object (edit persists after save). Main pane of a detached item shows the detached card, never a second editor.

---

## 8. Known Windows quirks → Mac decisions

| # | Windows behaviour (observed in code) | Mac decision |
|---|---|---|
| Q-01 | Any list rebuild (search keystroke, A→Z, group create/rename/delete) replaces every row object, which **clears the selection**; the details pane then disables with stale text. | Keep the selection when the item is still visible; if it is filtered out, show the empty state. |
| Q-02 | An empty group's header shows `(1)` (the placeholder is counted). | Show `(0)`. |
| Q-03 | While searching, groups whose items are all filtered out show the "(empty …)" placeholder. | While a query is active, omit sections with no matches (placeholders only when not searching). |
| Q-04 | `NavigateToItem` selects the main tab by fixed index 0–3, which is wrong after the user reorders tabs. | Select the tab by identity (kind). |
| Q-05 | `SelectItemById` does not scroll and silently fails when the target is hidden by the search filter. | Clear the page's search if needed, select, and scroll the row into view. |
| Q-06 | `+ New` while a non-matching search is active: the new item is invisible and not selected. | Clear the search before selecting the new item. |
| Q-07 | Items created from another page (Equipment "+ New procedure/task", step "+ New task") or other windows don't appear in the other sidebar until something rebuilds it. | Live via observation. |
| Q-08 | Group picker OK with nothing selected ungroups the items. | Disable OK until a row is chosen ("(Ungrouped)" remains available). |
| Q-09 | *Delete group* with no groups does nothing; *Rename group* explains. | Show `"No groups to delete in this tab yet."` (new string) or disable the button. |
| Q-10 | Renaming a group drops its expanded state; deleting leaves a stale `GroupExpanded` key. | Keep (compat); optionally migrate the key on rename. |
| Q-11 | Same-named groups (or a group named "Ungrouped") merge into one section. | Section by Id (§3.1). |
| Q-12 | "Preserve list order" uses an unstable sort in WPF. | Stable sort. |
| Q-13 | Picker filtering drops selections that are filtered out; with *Pick…* (replace semantics) this silently unlinks. | Keep hidden selections; OK returns all selected. |
| Q-14 | Relationships *Remove* on a row that exists only via Equipment `ProcedureIds`/`TaskIds` does nothing (row reappears) though a save occurs. | See §9 Q-B. Default: disable Remove for such rows with help text "Linked from the Specifics tab — use Pick… there." |
| Q-15 | Tag parsing differs between main pane (multi-delimiter, `#` strip, de-dup) and item window (comma only). | See §9 Q-A. Default: use the main-pane parser in both places. |
| Q-16 | Selecting a detached item returns before relationships/specifics/lock gate are refreshed, so those tabs (and a previous item's lock overlay) can show stale content. | Always render the selected item (disabled) or hide those tabs; lock gate evaluated for the selected item. |
| Q-17 | `RelockCurrent` re-binds the main editor to the container of a detached item (two editors on one container). | Respect the detached state. |
| Q-18 | Tools ▸ Lock now does not gate item windows that are already open. | Gate them (overlay) after flushing. |
| Q-19 | Deleting a detached task from the Board / quick-work (hard delete) doesn't orphan its window; edits go to an orphan. | Window orphans itself when its id disappears. |
| Q-20 | Delete status uses `picks[0].Name` even if that item was skipped (locked); windows of skipped locked items are closed too. | Name the first item actually trashed; close windows only for trashed ids. |
| Q-21 | Unlock error text reveals the master password. | Keep (product decision; compat). |
| Q-22 | Deadline cannot be cleared while a start exists (snaps to start). | Keep (Coerce semantics); optionally show a hint. |
| Q-23 | Double-clicking a step's Done/Job checkbox also opens the step editor. | Ignore double-clicks that land on the toggles. |
| Q-24 | Prompt / picker / date / lock dialogs don't close on Esc. | Esc cancels. |
| Q-25 | Invalid duration text is silently ignored. | Keep behaviour; optional red outline. |
| Q-26 | `Save()` exceptions in page handlers are unhandled (crash dialog). | Catch and show "Save failed" with the error; keep data dirty. |
| Q-27 | Checklist XLSX sheet name: escaped then truncated (can cut an entity) and not stripped of Excel-illegal `[]:*?/\`. | Strip illegal chars, truncate **before** escaping. Keep everything else identical. |
| Q-28 | Subtask Done column prints `True`/`False`. | Read-only check glyph. |
| Q-29 | Right-clicking a placeholder row clears the selection. | Placeholders not selectable/targetable. |
| Q-30 | Empty-state hint overlays group placeholders when the kind has no items but has groups. | Show the hint below the (empty) group headers or hide placeholders in that case. |
| Q-31 | Ctrl+S and the 5-min autosave flush only the four page editors, not item windows or modal editors. | Flush every registered editor on every save path. |
| Q-32 | Committing a rename (focus loss) rebuilds the list and re-runs selection, which re-fronts a vessel's Quick Cards tab. | Commit without re-running the selection side effects. |
| Q-33 | Detail pane shows the first-selected item of a multi-selection. | Keep (show the primary = first-selected); optionally show a "N items selected" banner. |

---

## 9. Open questions (for the lead)

* **Q-A** Unify tag parsing in the item window with the main pane (recommended), or keep the comma-only parser for
  fidelity?
* **Q-B** Relationships *Remove* on an Equipment one-way link: disable (recommended), or remove it from
  `ProcedureIds`/`TaskIds` (changes data semantics vs Windows)?
* **Q-C** Keep picker selections across filtering (recommended; prevents accidental unlinking) — confirm this
  deliberate divergence.
* **Q-D** Lock now with open item windows: gate in place (recommended) or close them?
* **Q-E** Sidebar search: Windows matches names only although the Tags tooltip says tags are "used for filtering".
  Add `#tag` matching (query starting with `#` matches tags ordinal-ignore-case) as an addition?
* **Q-F** Offer Touch ID as an alternative to the master password for per-item locks? (Not recommended by default:
  it adds an unlock factor Windows doesn't have.)
* **Q-G** Enum display labels (`InProgress` vs "In Progress") must be decided once for all specs.
* **Q-H** Tab label "Container" vs "Notes & Files" on Mac (cross-spec consistency).
