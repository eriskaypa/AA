# 11 — PDF & Checklist Export (porting spec)

Subsystem: **pdf-checklist-export** · Feature-ID prefix: **PDF-** · Target: native macOS app in Swift 6.4 (SwiftUI + AppKit where needed), macOS 26+.

Windows sources this spec is derived from (all paths relative to `/Users/eriskay/erisdev/AA/AA`):

| File | Role |
|---|---|
| `Services/PdfExporter.cs` (1113 lines) | Item PDF (Equipment/Area, Task, Procedure, Vessel), saved-list/group/all PDF, the whole rich-text → PDF pipeline (lists, tables, links, highlight, strike, fonts). |
| `Services/ChecklistExporter.cs` (260 lines) | Checklist-only PDF and checklist-only `.xlsx` for a Procedure. |
| `Views/HierarchyPage.xaml` L128 / `.xaml.cs` L754-796 (`ExportPdf_Click`), L1219-1319 (`BuildProcedureSpecifics` buttons), L1393-1420 (`ExportChecklist`) | Entry points for item PDF and checklist PDF/XLSX. |
| `Views/SavedListsPage.xaml` L79, L102-104 / `.xaml.cs` L252-475 | Entry points for saved-list PDF (one list / group / all), ordering. |
| `Views/ListStylePromptWindow.xaml(.cs)` | "Bulleted or numbered?" prompt. |
| `Services/SavedListOrder.cs` | `GroupEntries`, `AllEntries` — the order a group/all export prints in. |
| `Services/AppRepository.cs` L74-82 (`AllItems`, `FindById`), L150-163 (`RelatedItems`) | Look-ups the exporters depend on. |
| `Services/ItemLockService.cs` L77 (`IsGated`) | Export refusal for locked entries. |
| `Services/XlsxWriter.cs` | Sibling xlsx writer (same package layout; safer escaping) — reference for the Mac shared writer. |
| `Views/ContainerEditor.xaml(.cs)`, `Services/ListFormatting.cs`, `Services/HtmlToXamlConverter.cs` | Producers of the XAML shapes the PDF pipeline consumes (documented in §4.3). |
| `Models/Models.cs` | Every model field read by the exporters. |

Library facts about MigraDoc/PDFsharp 6.2 (the Windows engine) that change the visible result were checked against the upstream source (empira/PDFsharp) and are stated where they matter (page-setup defaults, default cell padding, `AddText` splitting, space-before suppression, margin collapsing, repeated header rows).

Wording convention: **MUST** = required for parity; **SHOULD** = strongly recommended Mac behaviour; **DEV-nn** = a sanctioned, explicitly listed deviation from the Windows output (see §6.9). Anything not marked DEV must match Windows.

---

## 1. Overview

### 1.1 Purpose

This subsystem turns data from the app's model into **files for people to read or print**. Nothing is ever read back in, so these outputs do not affect data compatibility with the Windows app. What must match is **what the files look like and contain**, because crews exchange and print these files.

There are five products:

| # | Product | Engine (Windows) | Where it is started |
|---|---|---|---|
| A | **Item PDF**: one Equipment/Area, Task, Procedure or Vessel, with its notes, kind-specific details, relationships and attached-file list | `PdfExporter.Export` (MigraDoc) | **Export PDF...** button in the item header (Equipment/Area, Tasks, Procedures and Vessels tabs) |
| B | **Saved-lists PDF**: one saved list, one List Group, or all saved lists | `PdfExporter.ExportSavedLists` | **Saved Lists** tab: **📄 Export this list (PDF)...**, **📄 Export group (PDF)...**, **📄 Export ALL (PDF)...**, context-menu **Export this list (PDF)...** |
| C | **Checklist-only PDF** of a Procedure (a printable tick sheet as a table) | `ChecklistExporter.ExportPdf` | Procedure ▸ **Specifics** tab ▸ **Export checklist (PDF)** |
| D | **Checklist-only Excel (.xlsx)** of a Procedure | `ChecklistExporter.ExportXlsx` (hand-written SpreadsheetML zip) | Procedure ▸ **Specifics** tab ▸ **Export checklist (Excel)** |
| E | (shared) **Rich-text → PDF pipeline**: the stored WPF-XAML notes (`Container.RichTextXaml`) rendered with colours, fonts, sizes, alignment, indentation, lists, tables, highlight, strike-through and clickable links | `PdfExporter.WriteContainerBody` and helpers | Used by A (item notes, subtask notes, step notes) and B (saved-list item notes) |

### 1.2 Where it sits

- The Hierarchy pages (Equipment/Area, Tasks, Procedures, Vessels tabs) share a details pane. Its header bar (`HeaderBar`) holds **Name**, **Description**, **Tags** plus the buttons **Export PDF...**, **🔒 Lock** and **🔒 Lock again**. The Mac equivalent is the detail column of the `NavigationSplitView` for each kind (see spec for the hierarchy page).
- The Procedure **Specifics** tab (built in code by `BuildProcedureSpecifics`) has a top bar with the full-width accent banner **🛠  Open Comprehensive Checklist Builder** and, docked to the right of the same row, **Export checklist (PDF)** and **Export checklist (Excel)**.
- The **Saved Lists** main tab has a detail panel with the three export buttons, and the list has a context menu.
- All exports run **synchronously on the UI thread** on Windows. Items and checklists show a wait cursor during export. The finished file opens in the default viewer, either immediately (items, checklists) or after asking (saved lists).

### 1.3 Non-goals / what is NOT exported (important for parity — do not "improve" silently)

- Tags, groups, buckets, job flag/duration of items, schedule times, lock hints, Quick Cards, Work Orders, Ports, crew data: **never** printed in any PDF.
- Components' own rich-text containers (`Component.Container`) are **not** printed. Only `Component.Name` and `Component.Notes` (a plain string) appear.
- A Procedure's own `Deadline`, `Recurrence`, `Status` and `IsJob` are **not** printed. A Task's `Status` is printed only as Completed/Open, derived from `IsComplete`.
- Files attached to subtasks, steps or components are **not** listed. Only the item's own file bank is listed (saved-list items list their file *names*).
- The saved-list item's `DurationMinutes` is **deliberately not printed**. Commit `ce8f54d` removed the leftover `~60m` meta, and PROGRESS still mentions "duration" from before that removal. Do not add it back.
- Checklist-only exports carry **no** notes, relationships or files.

---

## 2. Feature checklist

IDs are stable. Each entry gives the exact user-visible strings. `…` inside quotes stands for runtime data. Windows shows `...` (three ASCII dots) in button captions. On the Mac, captions SHOULD use the typographic ellipsis `…` as macOS convention (HIG) requires. That is the only allowed caption change.

### 2.1 Item PDF — UI flow (Hierarchy pages)

**PDF-001 — "Export PDF..." button on every item.**
Button caption `Export PDF...`, tooltip `Export this item, its hierarchy and relationships to an A4 PDF.` It sits in the item header bar, docked right of the Name box (order right-to-left: Export PDF..., 🔒 Lock, 🔒 Lock again). It is present for all four kinds: Equipment/Area, Task, Procedure, Vessel. It is disabled when no item is selected (`DetailsRoot.IsEnabled = false`) and while the item is detached into its own window (`DetachItem` disables `DetailsRoot`). It is hidden while the item is gated by its password lock (`ApplyLockGate` collapses `HeaderBar`). There is no keyboard shortcut on Windows.
*Mac:* toolbar button in the item detail view (SF Symbol `arrow.up.doc` or `doc.richtext`, label "Export PDF…") **and** a menu command **File ▸ Export as PDF…** that acts on the focused item (SHOULD be ⌥⌘E, an addition since Windows has none; it must not collide with other specs' shortcuts). Both are disabled under the same conditions as on Windows.

**PDF-002 — Lock gate refusal.**
If `ItemLockService.IsGated(item)` is true (the item has `LockHash`+`LockSalt` and has not been unlocked this session), the export is refused with a message box. Text `Unlock this entry before exporting it to PDF.`, title `Locked`, OK button, Information icon. The file dialog is never shown. This check stays even though the button is hidden while gated (defence in depth, e.g. for the Mac menu command).

**PDF-003 — Flush before export.**
Before building, the page flushes its rich-text editor (`ContainerCtrl.FlushPending()`, which clears the 400 ms debounce) and calls `_repo.FlushIfDirty()`, so the PDF reflects the latest typing.
*Windows gap:* detached `ItemWindow` editors are not flushed by this handler. *Mac (DEV-09):* flush **all** editors, including detached item windows (the equivalent of `MainWindow.FlushAllEditors`).

**PDF-004 — Save dialog (item).**
Title `Export to PDF`. Filter `PDF document (*.pdf)|*.pdf`, DefaultExt `.pdf`, AddExtension. Default file name `{Kind}-{safe}.pdf`:
- `{Kind}` is the raw enum name: `Equipment`, `Task`, `Procedure` or `Vessel`. It is **not** "Equipment/Area", because `/` is illegal in a file name.
- `{safe}` is `item.Name` (or `item` when Name is null) with every character from Windows `Path.GetInvalidFileNameChars()` replaced by `_`. That set is U+0000–U+001F plus `" < > | : * ? \ /`. An empty name gives `Task-.pdf`.
- Cancelling the dialog aborts silently.
*Mac:* `NSSavePanel` presented as a sheet on the window, `allowedContentTypes = [.pdf]`, `nameFieldStringValue` = the same default name computed with the **same Windows character set**, so both platforms suggest identical names. The standard overwrite confirmation is fine.

**PDF-005 — Busy state and failure.**
During export the mouse cursor is overridden to Wait. On any exception: message `Failed to export PDF:\n{exception message}`, title `Export error`, OK, Error icon, and the file is not opened.
*Mac:* SHOULD render off the main actor (see §6.2) and show an indeterminate progress indicator (sheet or toolbar spinner). The error is an `NSAlert` (critical style) with messageText `Export error` and informativeText `Failed to export PDF:` + newline + `localizedDescription`.

**PDF-006 — Auto-open.**
After a successful export the PDF opens with the OS default handler (`Process.Start(path){UseShellExecute=true}`). Failures to open are swallowed ("user can open it manually").
*Mac:* `NSWorkspace.shared.open(url)`, errors ignored.

**PDF-007 — Nothing is persisted.**
Export never mutates the model and never marks it dirty. The only disk writes are the flush of pending edits (PDF-003) and the output file.

### 2.2 Checklist-only export — UI flow (Procedure ▸ Specifics)

**PDF-010 — Buttons.**
Two buttons, horizontal, docked right in the same row as the full-width accent banner `🛠  Open Comprehensive Checklist Builder` (two spaces after the emoji). Each button has Margin 6,0,0,0 and Padding 10,6,10,6:
- `Export checklist (PDF)`, tooltip `Export ONLY the checklist (no notes, no relationships) as a printable A4 PDF.`
- `Export checklist (Excel)`, tooltip `Export ONLY the checklist as an Excel workbook (.xlsx).`
Not lock-checked in code, but unreachable while gated because the Specifics tab is hidden.
*Mac:* a trailing button group (or a single `Menu("Export Checklist")` with "PDF…" and "Excel…" entries) in the Specifics header next to the builder banner. Both captions SHOULD remain visible as text; do not hide them behind an icon only.

**PDF-011 — Save dialog (checklist).**
`_repo.FlushIfDirty()` first. There is no rich-text flush because notes are not exported.
- PDF: title `Export checklist to PDF`, filter `PDF document (*.pdf)|*.pdf`, default name `checklist-{safe}.pdf`.
- Excel: title `Export checklist to Excel`, filter `Excel workbook (*.xlsx)|*.xlsx`, default name `checklist-{safe}.xlsx`.
- `{safe}` is `p.Name` (or `procedure` when null), sanitized with the same invalid-char set as PDF-004.
*Mac:* `allowedContentTypes` is `.pdf`, or `UTType(filenameExtension: "xlsx")` (`org.openxmlformats.spreadsheetml.sheet`).

**PDF-012 — Busy/failure/open (checklist).**
Wait cursor during export. On error: `Failed to export checklist:\n{message}`, title `Export error`, Error icon. On success the file auto-opens (errors swallowed), in Excel/Numbers for .xlsx.

### 2.3 Saved-lists PDF — UI flow (Saved Lists tab)

**PDF-020 — Export this list.**
Detail-panel button `📄 Export this list (PDF)...` and list context-menu item `Export this list (PDF)...`. It uses the **single** selected list (`ListsBox.SelectedItem`, the primary selection even when several are selected). With no selection: message `Select a saved list first.`, title `Saved Lists`, Information icon.
Document title: `t.Name` if non-empty, else `Saved list`. It exports one entry with **group = null**, so no group heading is printed even when the list belongs to a group.

**PDF-021 — Export group.**
Button `📄 Export group (PDF)...`. It uses the group of the selected list:
- The list's `GroupId` resolves to an existing `ListGroup`: title = `grp.Name` (may be empty), entries = `SavedListOrder.GroupEntries(data, gid)`. That is every template with that GroupId, in collection order, each tagged with the group name, or `null` if the name is empty.
- Otherwise (ungrouped, or a dangling GroupId): title `Ungrouped lists`, entries = `GroupEntries(data, null)`, meaning every template whose GroupId is null. *Edge:* a list whose GroupId dangles is itself **not** included (its GroupId is not null). If nothing qualifies, the result is PDF-026 "Nothing to export.".
No selection gives the same message as PDF-020.

**PDF-022 — Export ALL.**
Button `📄 Export ALL (PDF)...`. If `ChecklistTemplates` is empty: message `No saved lists to export.`, title `Export`, Information. Entries come from `SavedListOrder.AllEntries(data)` (PDF-027). Title `All saved lists`.
*Windows quirk:* all three buttons sit in `DetailRoot`, which is disabled until a list is selected, so Export ALL needs a selection and the "No saved lists" message is effectively unreachable. *Mac (DEV-10):* Export All SHOULD be available without a selection (e.g. also in the tab's toolbar overflow menu / File menu when the Saved Lists tab is active). Keep the message for the empty case.

**PDF-023 — Bulleted or numbered prompt (every time).**
After the entries are built and non-empty, and **before** the save dialog, a modal `ListStylePromptWindow` appears:
- Window title `List style`, width 430, no resize, centered on owner.
- Prompt text: when there is one entry, `How should the items in this list be shown in the PDF?`. Otherwise `How should the items in these {n} lists be shown in the PDF?`, where n is the entry count. The window's built-in default prompt, never seen here, is `How should the items be listed?`.
- Radio 1, **preselected**: bold `• Bulleted` with muted wrapped caption `Every item marked with a bullet. Best when the order does not matter.`
- Radio 2: bold `1. Numbered` with caption `Items numbered in order. Best for steps that run in sequence.`
- Buttons: `Cancel` (IsCancel: Esc) and bold `Continue` (IsDefault: Return).
- The choice is **never remembered**. Every export asks again, with bullets preselected (rationale: numbering claims an order). Cancel aborts the export **before** the save dialog.
- The API parameter `numbered` on the exporter has **no default value**, so no caller can inherit numbering. In Swift: `numbered: Bool` with no default argument.
*Mac:* a sheet with `Picker(selection:) { … }.pickerStyle(.radioGroup)`, each option with a secondary-colour caption, Cancel (`.cancelAction`) and Continue (`.defaultAction`).

**PDF-024 — Save dialog (saved lists).**
Title `Export saved lists to PDF`, filter `PDF document (*.pdf)|*.pdf`, DefaultExt `.pdf`, file name `Sanitize(title) + ".pdf"`. `Sanitize` replaces each Windows invalid file-name char with `_`. If the result is whitespace-only it becomes `saved-lists`, otherwise it is `Trim()`med. Examples: `All saved lists.pdf`, `Ungrouped lists.pdf`, empty group name gives `saved-lists.pdf`. There is no wait cursor for this flow.

**PDF-025 — Completion prompt and failure (saved lists).**
On success: message `Exported to:\n{full path}\n\nOpen it now?`, title `Export complete`, Yes/No, Information icon. Yes opens the file with the default handler.
On failure: `Could not export the PDF:\n\n{message}` (note the **blank line**), title `Export failed`, Error icon.
*Windows quirk:* the open call is inside the same `try`, so a failure to *open* is reported as "Could not export the PDF". *Mac (DEV-12):* report only real export failures, and ignore open failures.
*Mac button labels:* keep the message text verbatim. Buttons SHOULD be `Open` (default) / `Not Now` (HIG verbs), mapping to Yes/No. A `Show in Finder` third button is an allowed addition.

**PDF-026 — Empty entry set.**
If the entry list is empty (possible only for group export, see PDF-021): message `Nothing to export.`, title `Export`, Information. The prompt and dialog are not shown.

**PDF-027 — Export order.**
The order in the PDF is the user's arranged order, which is the order of `AppData.ChecklistTemplates` in data.json. It is **not** the on-screen A–Z order: the tab's **Sort A-Z** toggle (`Ui.SortAZ["savedlists"]`) only changes the display. For **Export ALL** (`SavedListOrder.AllEntries`), sorting is **stable**:
- primary key: named groups first, ordered by `groupName.ToLowerInvariant()`; ungrouped lists last (Windows uses the sentinel key `"\uFFFF"`);
- secondary key: position in `ChecklistTemplates`.
- Group name for an entry: `ListGroups.First(id).Name`, or `""` if the group id dangles. An entry with `GroupId == null` has group `null`.
This keeps each group's lists **contiguous**, which PDF-052 relies on.
*Mac:* implement with an explicit tuple key `(isUngrouped: Bool, lowerName: String, index: Int)` and a plain code-point comparison of `lowerName`. Do **not** rely on a `"\u{FFFF}"` sentinel, because culture-aware comparison may treat U+FFFF as ignorable. The intended and tested result is "ungrouped last".

### 2.4 Item PDF — document content (product A)

**PDF-030 — Page setup.**
A4 portrait (21.0 × 29.7 cm = 595.276 × 841.890 pt). Margins: top/bottom/left/right **2 cm**. Header distance **1 cm** (from top page edge to header top). Footer distance **1 cm** (from bottom page edge to footer bottom). Printable width **17 cm**. One section, so header and footer appear on every page including page 1.

**PDF-031 — Running header.**
One paragraph: 9 pt, colour RGB(120,120,120), style `Header`. `Header` inherits `Normal` (§3.3), so it is also Calibri-resolved with SpaceAfter 3 pt and line spacing ×1.15. It has a **right-aligned tab stop at 16 cm** (measured from the left margin, which is **1 cm short of the right margin**). Content: `{KindLabel}: {item.Name}` ⟶ TAB ⟶ `yyyy-MM-dd HH:mm` (local time at export).
KindLabel: Equipment → `Equipment/Area`. Task/Procedure/Vessel → `Task`/`Procedure`/`Vessel`.
Example: `Equipment/Area: Main engine` … `2026-09-29 14:05`.
If the left text runs past 16 cm, the line wraps like any paragraph and the timestamp goes to the next line (tolerance acceptable).

**PDF-032 — Footer.**
One paragraph, right-aligned **at the right margin** (17 cm), 9 pt, RGB(120,120,120): `Page {current} / {total}`, for example `Page 3 / 7`. Two-pass on the Mac, because the total is needed on every page.

**PDF-033 — Document info.**
PDF Title `{item.Kind} - {item.Name}`, using the **raw enum name**, e.g. `Equipment - Main engine` and not "Equipment/Area". Author `AA`.
*Mac:* `kCGPDFContextTitle`, `kCGPDFContextAuthor = "AA"`. Creator free (e.g. `AA for Mac`).

**PDF-034 — Title block.**
1. Paragraph style `Title`: `item.Name`.
2. Paragraph style `Subtitle`: KindLabel.
3. If `item.Description` is not null/whitespace: paragraph style `BodyItalic` with the description text. `\n` becomes a line break and `\t` a tab (PDF-101).

**PDF-035 — Section order.**
Title block → **Notes** (PDF-036) → kind specifics (PDF-037…PDF-043) → **Relationships** (PDF-044) → **Attached Files** (PDF-045). A section is omitted entirely when it has nothing to show, following each section's own rule.

**PDF-036 — Notes.**
`WriteContainerBody(sec, item.Container, "Notes")`. If `RichTextXaml` is null/whitespace, or parses to a document with no visible (non-whitespace) text, nothing is printed, not even the heading. Otherwise it prints H1 `Notes` followed by the rich text rendered per §3.5. There is no extra indent.

**PDF-037 — Equipment/Area details.**
Skipped entirely when `Components`, `ProcedureIds` and `TaskIds` are all empty. Otherwise:
- H1 `Equipment/Area Details`.
- If `Components.Count > 0`: H2 `Components ({count})`, then a table:
  - Borders 0.5 pt RGB(180,180,180).
  - Cell padding left/right 3 pt, top/bottom 2 pt.
  - Columns 5 cm | 11 cm.
  - Header row: shading RGB(235,235,235), `HeadingFormat=true` (repeats at the top of each continuation page), bold `Component` | `Notes`.
  - Then one row per component: `Name ?? ""` | `Notes ?? ""`, plain strings with `\n`/`\t` splitting.
- If `ProcedureIds.Count > 0`: H2 `Linked Procedures ({ProcedureIds.Count})`. The count is **raw**, so dangling ids are counted. Then for each id that resolves via `FindById` to a **Procedure**:
  - H3 procedure name;
  - if the description is non-blank, a `BodyItalic` paragraph;
  - one `Bullet`-style paragraph per step: `{n}. [x] {Title}` or `{n}. [ ] {Title}`, n from 1. This is plain text with no due date, links or notes.
  - Ids that do not resolve, or resolve to a non-Procedure, are skipped silently.
- If `TaskIds.Count > 0`: H2 `Linked Tasks ({TaskIds.Count})` (raw count). Then for each id resolving to a **TaskItem**: *Task summary* (PDF-040).

**PDF-038 — Task details.**
Always printed for a Task, even an empty one: H1 `Task Details`, then a 2-column key/value table: no borders (width 0), columns 4 cm | 12 cm, MigraDoc default cell padding (1.2 mm left/right, 0 top/bottom). Rows in order:
1. `Working range` → `{RangeStart:yyyy-MM-dd} → {Deadline:yyyy-MM-dd}` (U+2192 with spaces). Present **only** when RangeStart and Deadline both exist and `RangeStart.Date < Deadline.Date`.
2. `Deadline` → `yyyy-MM-dd`, or `(none)`.
3. `Recurrence` → enum name: `None`, `Daily`, `Weekly`, `Monthly` or `Yearly`.
4. `Status` → `Completed` if `IsComplete`, else `Open`. InProgress/Blocked are **not** shown.
Key cells are bold, RGB(80,80,80). Value cells use the Normal style.
If `Subtasks.Count > 0`: H2 `Subtasks ({direct child count})`, then each subtask rendered by PDF-039 at depth 1.

**PDF-039 — Subtask (recursive, with per-subtask notes).**
For a subtask at `depth` (1 = direct child):
- indent = `min(depth, 4) × 0.6 cm`, so depth 1 → 0.6, 2 → 1.2, 3 → 1.8, 4 and deeper → 2.4 cm.
- Head paragraph (Normal style): LeftIndent = indent, SpaceBefore **6 pt when depth == 1, else 3 pt**, SpaceAfter 2 pt, **KeepWithNext**. Content:
  - bold `[x] ` or `[ ] ` (from `IsComplete`), then bold `Name ?? ""`;
  - if meta exists: two spaces, then a grey RGB(120,120,120) italic run `({meta joined by ", "})`. Meta is `TaskWhen(t)` (PDF-041) if non-null, then `recurrence.lowercased()` if Recurrence ≠ None (e.g. `weekly`).
  - Example: `[ ] Replace filter  (2026-07-08 – 2026-07-10, monthly)`.
- If Description is non-blank: `Muted` paragraph (10 pt grey) with LeftIndent = indent.
- The subtask's rich-text notes: `WriteContainerBody(…, heading: "", leftIndent: indent)` (PDF-074), with no heading.
- Then each child subtask at depth+1, in stored order.
Subtasks' own file banks, IsJob and Status are not printed.

**PDF-040 — Task summary (used under Equipment "Linked Tasks").**
A `Bullet`-style paragraph: bold `[x] `/`[ ] `, bold `Name`, then optional `  ({meta})` in grey italic (same meta as PDF-039). If Description is non-blank: a `Muted` paragraph with LeftIndent 0.6 cm. No subtasks and no notes.

**PDF-041 — "When" meta (`TaskWhen`).**
No Deadline → none. If RangeStart exists and `RangeStart.Date < Deadline.Date` → `{RangeStart:yyyy-MM-dd} – {Deadline:yyyy-MM-dd}` (**EN DASH U+2013** with spaces; note this differs from the `→` in the Working-range row). Otherwise → `due {Deadline:yyyy-MM-dd}`.

**PDF-042 — Procedure checklist.**
Skipped when the procedure has 0 steps. Otherwise H1 `Checklist ({n} step)` when n == 1, else `Checklist ({n} steps)`. For each step, with numbering from 1:
- Head paragraph: SpaceBefore 6 pt, SpaceAfter 2 pt, **KeepWithNext**. Content:
  - a bold run `{n}. [x] ` (done) in **green RGB(0,120,0)**, or `{n}. [ ] ` in grey RGB(100,100,100);
  - bold `Title ?? ""` in the default colour;
  - if the step has a Deadline, an italic grey RGB(100,100,100) run `   (due yyyy-MM-dd)` (**three** leading spaces).
- If `EquipmentIds.Count > 0`: `Muted` paragraph, LeftIndent 0.6 cm, italic `Equipment/Area: `, then the names of ids that resolve (any kind) joined by `, `. If none resolve, the label is followed by nothing.
- If `TaskIds.Count > 0`: same shape with the label `Tasks: `.
- The step's rich-text notes: `WriteContainerBody(…, "", "0.6cm")`.
Step job flags, buckets and step file banks are not printed.

**PDF-043 — Vessel.**
No kind-specific section. A Vessel PDF contains title block, Notes, Relationships and Files only.

**PDF-044 — Relationships.**
`related = repo.RelatedItems(item)`:
- Collect a de-duplicated set of ids from `item.RelatedIds`, plus `ProcedureIds` and `TaskIds` when the item is an Equipment, in that insertion order.
- Resolve each via `FindById`. `FindById` only searches top-level Equipment, Tasks, Procedures and Vessels, **not** subtasks. Drop ids that do not resolve.
- Distinct.
If the result is empty the section is omitted. Otherwise:
- H1 `Relationships ({count})`.
- A `BodyItalic` paragraph: `Items linked to this one, grouped by tab.`
- For each kind, in the fixed order **Equipment → Task → Procedure → Vessel**, if any exist: H2 `{KindLabel} ({n})`. The labels are singular: `Equipment/Area (2)`, `Task (1)`, `Procedure (3)`, `Vessel (1)`.
- Within a kind, items are sorted by Name with **ordinal, case-insensitive** comparison (stable sort, so ties keep set order).
- Each item is a `Bullet`-style paragraph (**no marker glyph**, so the text simply starts at 0.2 cm): bold `Name`. If its description is non-blank, it is followed by ` — ` (EM DASH U+2014 with spaces) and `Shorten(description, 180)` (PDF-102).
- A self-reference in RelatedIds lists the item itself (faithful).

**PDF-045 — Attached Files.**
Only `item.Container.Files`. Omitted when empty. Otherwise:
- H1 `Attached Files ({count})`.
- A table with borders 0.5 pt RGB(200,200,200), padding 3/3/2/2 pt, columns 5 cm | 2 cm | 9 cm.
- Header row: shading RGB(235,235,235), HeadingFormat, bold `Name` | `Kind` | `Path / Link`.
- One row per file: `Name ?? ""` | `Kind` enum name (`Document`, `Image`, `Video`, `Link` or `Other`) | `Path ?? ""` at **9 pt**.
- The path is printed **exactly as stored**, which may be relative `files/<name>`, a live absolute path (LinkInPlace) or a URL. It is not clickable and not resolved.

### 2.5 Saved-lists PDF — document content (product B)

**PDF-050 — Page scaffolding.**
Same page setup, styles, header and footer as PDF-030…032, with these differences:
- Header text is `Saved lists: {docTitle}` ⟶ TAB ⟶ `yyyy-MM-dd HH:mm`.
- PDF Title = `docTitle`, Author `AA`.

**PDF-051 — Title + subtitle.**
`Title`-style paragraph `docTitle`. `Subtitle`-style paragraph `Saved checklists  ·  {N} list` when N == 1, else `… {N} lists`. There are **two spaces**, a MIDDLE DOT U+00B7, then two spaces. N = entry count.

**PDF-052 — Group headings (contiguity rule).**
Iterate entries in order and track `lastGroup` (starting as none) and `started=false`. For each entry, g = group, or null if the group is null/whitespace.
- If `!started || g != lastGroup` (ordinal string compare):
  - if g is non-null, print H1 `g`;
  - else if already started, print H1 `Ungrouped`;
  - then set lastGroup = g and started = true.
Consequences (all MUST match):
- A null first entry prints **no** heading. This covers single-list export, "Ungrouped lists" export, and Export ALL when every list is ungrouped.
- Export ALL with groups prints each group name once, and `Ungrouped` before the trailing ungrouped lists.
- Two different groups with the **same name** that end up adjacent merge under one heading.
- Groups whose names differ only in case sort together by lowercased key, so they may alternate headings. This is faithful.
- A group with an empty name counts as "no group" (null). It sorts first in Export ALL (its key is `""`), so its lists print with **no** heading at the top.

**PDF-053 — List heading.**
H2 `{name}   ({count} item)` / `… items)`. Name is `tpl.Name` or `(unnamed list)` if blank. There are **three spaces** before `(`. An empty list prints the heading `(0 items)` and nothing else.

**PDF-054 — List items.**
Numbering restarts at 1 for each list. Each item is a `Bullet`-style paragraph (LeftIndent 0.6 cm, FirstLineIndent −0.4 cm):
- Marker: bold `{n}. ` when numbered, or bold `•  ` (U+2022 + **two** spaces) when bulleted.
- Then `Title ?? ""` as plain text, with `\n`/`\t` splitting.
- If `IsJob`: two spaces plus a grey RGB(120,120,120) italic run `(schedulable)`.
- Duration is **not** printed (see §1.3).

**PDF-055 — Item notes and files.**
After each item:
- `WriteContainerBody(item.Container, heading: "", leftIndent: "0.6cm")`: rich-text notes shifted 0.6 cm.
- If the container has ≥1 file: a `Muted` paragraph (10 pt grey), LeftIndent 0.6 cm, italic `Files: `, then file **names** joined by `, `.

### 2.6 Rich-text fidelity (pipeline E; applies wherever notes are printed)

**PDF-060 — Parse, with a never-leak-tags fallback.**
The stored `RichTextXaml` (WPF `TextRange.Save(DataFormats.Xaml)` output, a `<Section xmlns=…>` root) is loaded into an empty FlowDocument with `TextRange.Load(…, DataFormats.Xaml)`. If loading throws for any reason (invalid XML, non-XAML text, legacy `enc:` blob), the **fallback** is used:
- `StripXamlTags` (§3.4.2);
- split on `\r\n`→`\n`, then `\n`;
- skip blank lines;
- each remaining line becomes a plain Normal paragraph.
Raw markup must never reach the PDF by any path.

**PDF-061 — Skip empty bodies.**
When the parsed document's plain text is empty or whitespace, the whole call prints nothing (no heading). In the fallback path, an empty stripped string also prints nothing.

**PDF-062 — Paragraph alignment.**
`TextAlignment` Left / Center / Right / Justify map to the same alignment. Anything else is Left.

**PDF-063 — Indentation preserved as-is.**
`Margin.Left > 0` adds a left indent. A **positive** `TextIndent` also adds to the left indent (whole-paragraph shift, matching what the editor shows). A **negative** `TextIndent` becomes a first-line (hanging) indent. `Margin.Right > 0` becomes a right indent. Units: 1 WPF px = 1/96 in = 0.026458 cm = 0.75 pt. `Margin.Top`/`Bottom`, `Padding`, `LineHeight` and paragraph borders are ignored.

**PDF-064 — Highlight.**
(a) Paragraph `Background` (solid, non-transparent) shades the paragraph box.
(b) **Whole-line highlight:** if *every* text-bearing Run in the paragraph has the same effective background colour (§3.5.6), the paragraph is shaded with that colour, overriding (a).
(c) **Partial highlight** (only some runs) is **not** representable on Windows and is dropped (see DEV-05 for the Mac option).
(d) The edit-lock sentinel **RGB(255,230,153)** (`#FFFFE699`, pale gold) is **never** used as a whole-line highlight: rule (b) returns "none" when the uniform colour equals it. Rule (a) has no such exclusion.
(e) (b) applies to top-level and table-cell paragraphs only, **not** to list-item paragraphs. List items still get (a).

**PDF-065 — Empty paragraph = blank line.**
A paragraph whose inlines produce no text gets a single space so it keeps its height, in the Normal style (Calibri-resolved 11 pt, ×1.15, +3 pt after), regardless of the editor font size.

**PDF-066 — Run formatting.**
For every Run, using **effective (inherited) values**:
- **bold** if OpenType weight ≥ 600 (SemiBold counts, Medium does not). Otherwise explicitly **not bold**.
- **italic** if FontStyle is Italic or Oblique.
- **underline** only if the Run's **own** `TextDecorations` contains Underline (see DEV-01).
- **colour** = Foreground if it is a solid brush with alpha ≠ 0. The alpha value is otherwise ignored.
- **font family** = `ResolveFontName(FontFamily.Source)` (PDF-076).
- **size** = `FontSize × 0.75` pt (WPF px → pt). For example, the editor default of 14 px gives 10.5 pt.
Overline and baseline decorations, BaselineAlignment (sub/superscript), Typography.*, FontStretch and FlowDirection are ignored.

**PDF-067 — Strikethrough.**
A Run whose own `TextDecorations` contains Strikethrough is drawn with a line through each **non-whitespace, non-control** character. Spaces are **not** struck, which avoids a stray stroke at a soft-wrap boundary. Surrogate pairs such as emoji are handled per code point. It is never rendered as underline.
Windows implementation: U+0336 COMBINING LONG STROKE OVERLAY after each such character. *Mac (DEV-04):* use the native strikethrough attribute on those characters only.

**PDF-068 — Line breaks & tabs.**
`<LineBreak/>` becomes a line break. Any `\n` inside plain text becomes a line break and `\t` advances to the next default tab stop (PDF-101).

**PDF-069 — Lists.**
- `List.MarkerStyle` in {Decimal, LowerLatin, UpperLatin, LowerRoman, UpperRoman} → **numbered**, always printed as Arabic `1. 2. 3.` (**not** a./i. even though the editor shows them). Any other style (Disc, Circle, Square, Box, **None**) → bullet `• ` (U+2022 + one space).
- Each list paragraph: LeftIndent = `0.6 cm + 0.6 cm × nesting level`, FirstLineIndent **−0.4 cm** (marker hangs), alignment/background/right indent from the paragraph.
- Paragraph Margin.Left/TextIndent inside list items are **overridden**.
- The marker is Normal-style text (Calibri-resolved 11 pt black), independent of the item's run fonts.
- Numbering counts **paragraphs**, not ListItems: a ListItem with two paragraphs consumes two numbers and both get a marker.
- A nested List inside a ListItem is rendered one level deeper with its **own** counter starting at 1. The outer counter continues after it.
- `List.StartIndex` is ignored (always starts at 1).
- A non-Paragraph, non-List block inside a ListItem (Table, Section) is rendered at the current level with no marker; a Table there is not indented.

**PDF-070 — Tables** (editor "Insert table", or pasted from Excel/Word/web).
Rendered as a real table with:
- all rows of all row groups;
- a **true column count** computed by simulating the occupancy grid (§3.5.9);
- column widths from absolute px widths, else an even split of 16 cm (§3.5.10);
- `ColumnSpan`/`RowSpan` → merge right/down, clamped to the grid;
- per-cell border = max side thickness **in points, taken 1:1 from the WPF px value** (e.g. `0.6` → 0.6 pt), colour from BorderBrush or default RGB(120,120,120). Thickness ≤ 0 means no border;
- cell Background → shading;
- cell effective FontWeight ≥ 600 → whole-cell bold (the editor's header row);
- cell content rendered recursively (paragraphs, lists, nested sections);
- an empty cell keeps an empty paragraph so it does not collapse.
The table-level border is off. Row and table backgrounds, CellSpacing, cell Padding and table Margin are ignored. Default cell padding is 1.2 mm left/right and 0 top/bottom. There is no header-row repetition. Tables are **not** shifted by the extra leftIndent of PDF-074.

**PDF-071 — Formal hyperlinks.**
A `<Hyperlink NavigateUri="…">` with a non-blank target becomes a **clickable** link: the whole display text is the link. Target normalisation: trim; a target starting with `www.` (case-insensitive) gets an `https://` prefix. Link text keeps the run's bold/italic, font and size and strike, but is forced to **underline + colour RGB(11,97,164)** (`#0B61A4`). `mailto:` and other schemes pass through as-is.

**PDF-072 — Targetless hyperlinks.**
A Hyperlink with a null or blank NavigateUri is rendered as ordinary inline content, so auto-linking (PDF-073) makes only a URL/e-mail substring clickable, not the whole label.

**PDF-073 — Bare URLs and e-mails become links.**
In every plain Run (not inside a formal link), `http://`, `https://` and `www.` URLs and e-mail addresses that start a token are turned into clickable links (blue + underline as PDF-071). The rest of the run keeps its formatting. Trailing sentence punctuation `. , ; : ! ? ) ] } ' "` is excluded from the link. `www.` links get `https://`. E-mails get `mailto:`. Mid-token text such as `backup_www.tar.gz` is **not** linked. The regex is exact and in §3.5.12. Performance: linear; a 40 000-char pathological token must render in well under 1 s (Windows: ~60 ms).

**PDF-074 — Extra indent for nested notes.**
When notes are printed under a subtask, a checklist step or a saved-list item, every **paragraph** produced by that body (including fallback lines and list paragraphs) has its LeftIndent increased by the context indent (0.6 cm for steps and saved-list items, `min(depth,4)×0.6` cm for subtasks). The paragraph's own indent is added, so nested bullets keep their relative nesting. Tables are not shifted.

**PDF-075 — Unsupported content is dropped silently.**
Images and other embedded UI (`InlineUIContainer`, `BlockUIContainer`), `Figure`/`Floater` (and their contents), gradient/image brushes (treated as no colour), paragraph borders (an `<hr>` paste becomes an empty paragraph → a blank line), and paragraph-level TextDecorations.

**PDF-076 — Font resolution.**
Windows (`ResolveFontName`):
1. `null`/blank gives `Calibri`.
2. Otherwise split the WPF family source on `,`. For each part, trim whitespace and then `'` and `"`, map aliases (below), and return the first name that is **installed** (case-insensitive).
3. If none is installed: `Calibri` if installed, else `Arial` if installed, else `Segoe UI`.
Aliases: `Sans Serif`/`Sans-Serif`/`SansSerif` → Arial; `Serif` → Times New Roman; `Monospace` → Consolas; `Cursive` → Comic Sans MS; `Fantasy` → Impact; `system-ui` → Segoe UI.
The Normal style's font is `ResolveFontName("Calibri")`. *Mac:* see §6.4 for the required mapping table. The editor's default font is **Consolas** (`MainFont`), so most notes arrive as `Consolas` and must stay monospaced on the Mac.

**PDF-077 — Colours.**
Only solid colours are considered (`SolidColorBrush`). A fully transparent colour (A == 0) means "no override". The alpha channel is otherwise dropped, so a semi-transparent colour prints as opaque RGB. Named colours and `#RGB`/`#ARGB`/`#RRGGBB`/`#AARRGGBB` are all valid inputs (§4.3).

### 2.7 Checklist-only PDF (product C)

**PDF-080 — Page setup.**
A4 portrait. Margins 2 cm on all sides (explicit). Header/footer distance is the **MigraDoc default of 1.25 cm**, because this exporter does not set it. **No running header.** Footer: right-aligned 9 pt RGB(120,120,120) `Page X / Y`. PDF Title `Checklist - {proc.Name}`, Author `AA`.

**PDF-081 — Title block.**
- Normal style: font `Calibri` (Mac: resolve per §6.4), 11 pt, **no** SpaceAfter and **single** line spacing (this exporter does not use PdfExporter's styles).
- Title: `proc.Name`, 22 pt bold, SpaceAfter 2 pt.
- Subtitle: `Checklist`, colour RGB(120,120,120), 11 pt, SpaceAfter 10 pt.

**PDF-082 — Empty state.**
0 steps → a single italic paragraph `(no steps)`, with no table.

**PDF-083 — Table.**
- Borders 0.5 pt RGB(180,180,180). Padding 3 pt on all four sides.
- Columns: `#` 0.9 cm | `Done` 1.0 cm | `Step` 7.2 cm | `Due` 2.2 cm | `Tasks / Equipment-Area` 5.0 cm, totalling 16.3 cm.
- Header row: shading RGB(235,235,235), **repeats on every page** (HeadingFormat), bold labels exactly `#`, `Done`, `Step`, `Due`, `Tasks / Equipment-Area`.

**PDF-084 — Rows.**
One row per step, in stored order:
- `#` = 1-based index.
- `Done` = `[x]` if done, else `[  ]` (**two** spaces, unlike PdfExporter's `[ ]`).
- `Step` = `Title ?? ""`.
- `Due` = `yyyy-MM-dd` or empty.
- `Tasks / Equipment-Area`: `T: {name}` for each TaskId that resolves via FindById (any kind), then `E/A: {name}` for each EquipmentId that resolves, joined with `\n` so each is on its own line. Unresolved ids are dropped. Empty cell if none.
Rows are never split across pages (§3.2).

### 2.8 Checklist-only Excel (product D)

**PDF-090 — Package.**
A ZIP (DEFLATE, "Optimal") with exactly these 6 entries **in this order**:
1. `[Content_Types].xml`
2. `_rels/.rels`
3. `xl/workbook.xml`
4. `xl/_rels/workbook.xml.rels`
5. `xl/styles.xml`
6. `xl/worksheets/sheet1.xml`
All are UTF-8 **without BOM**. There is no `docProps/`, no sharedStrings, and no theme. An existing file at the path is deleted first. Byte content is in §4.5.

**PDF-091 — Sheet name.**
`proc.Name`, or `Checklist` if blank. It is XML-escaped **then** truncated to 31 UTF-16 units.
*Windows defects:* the truncation can cut an entity in half, and the Excel-forbidden characters `: \ / ? * [ ]` are not sanitized, so both produce a workbook Excel must "repair". *Mac (DEV-03):* sanitize first, then truncate, then escape (§3.6.2).

**PDF-092 — Columns & header.**
- Row 1 (style 1: **bold** Calibri 11 + solid fill `FFEEEEEE`): `#`, `Done`, `Step`, `Due`, `Linked Tasks`, `Linked Equipment/Area`.
- Custom widths: A=5, B=7, C=55, D=14, E=40, F=40.
- No freeze panes, no autofilter.

**PDF-093 — Data rows.**
Every cell is an **inline string** (`t="inlineStr"`), including `#` and Due. Numbers and dates are therefore text, not serials. Per step:
- `#` = index;
- `Done` = `Yes`/`No`;
- `Step` = `Title ?? ""`;
- `Due` = `yyyy-MM-dd` or `""`;
- `Linked Tasks` = resolved names joined `"; "`;
- `Linked Equipment/Area` = resolved names joined `"; "`.
Missing ids are dropped. Unlike the PDF there are no `T:`/`E/A:` prefixes. A procedure with 0 steps produces a header-only sheet.

**PDF-094 — Escaping.**
Windows escapes `& < > "` only. Control characters are not stripped, so a stray U+000B in a title yields an unreadable workbook. *Mac (DEV-03):* also drop XML-1.0-illegal characters (< U+0020 except TAB, LF, CR), exactly as `XlsxWriter.Esc` does.

### 2.9 Cross-cutting

**PDF-100 — Pagination rules** (MigraDoc behaviours that shape the output; §3.2 has the details).
- Automatic word-wrap; text never clips horizontally.
- Paragraphs split across pages line by line, with widow/orphan control on (at least 2 lines at each end).
- Headings (H1/H2/H3), subtask heads and step heads are **KeepWithNext**.
- Table rows are atomic and never split. A row plus the rows it merges down into are kept together.
- HeadingFormat rows repeat at the top of each continuation page.
- SpaceBefore is dropped for the first element on a page.
- Vertical space between blocks = max(prev.SpaceAfter, next.SpaceBefore).

**PDF-101 — Plain-text splitting.**
Every plain string added to the PDF (names, titles, descriptions, component notes, paths, meta, rich-text runs) is split on `\n` into line breaks and on `\t` into tabs. MigraDoc `ParagraphElements.AddText` does this. `\r` is not a break on Windows; the Mac MUST treat `\r\n` and lone `\r` as `\n` (DEV-13). Default tab stops every 1.25 cm from the paragraph's left edge.

**PDF-102 — `Shorten(s, max)`.**
Replace `\r` and `\n` each with a space, `Trim()`. If the length is ≤ max return it, else return the first `max−1` UTF-16 units + `…` (U+2026). Used only for relationship descriptions (max 180). *Mac:* never split a surrogate pair or grapheme cluster; back off to the previous boundary. This is allowed because the difference is invisible for ASCII.

**PDF-103 — Date/time formatting.**
All dates print as `yyyy-MM-dd` and timestamps as `yyyy-MM-dd HH:mm` (24 h, local time at export). The Mac MUST use `Locale(identifier: "en_US_POSIX")`, `Calendar(identifier: .gregorian)` and the current time zone for the timestamp, so the separator is always `:` and the year is always Gregorian. Windows would follow the user's culture for `:` and calendar, which is an unintentional variance. Stored model dates (Deadline, RangeStart, step Deadline) are formatted from their **stored wall-clock components** with no UTC conversion (see the data-model spec for JSON `DateTime` parsing).

**PDF-104 — Theme independence.**
PDF and XLSX output is identical in light and dark mode. All colours are fixed sRGB values. The editor's "paper" colours are theme-independent: `EditorBg #FFFCFCFC`, `EditorFg #FF1A1A1A`, so XAML text colour is normally `#FF1A1A1A` and prints near-black. *Mac:* the PDF renderer MUST consume the stored XAML (or a colour-resolved model of it), never a live `NSAttributedString` that may carry dynamic colours such as `NSColor.textColor`, which would print white in dark mode.

**PDF-105 — Null-safety.**
On Windows several `AddText(null)` calls would throw `ArgumentNullException` and surface as "Failed to export PDF", for example a relationship or linked task with a null Name from hand-edited JSON. *Mac:* treat every nil string as `""`. This is a harmless robustness difference.

---

## 3. Logic & algorithms

### 3.1 Units and constants

| Constant | Value | Where |
|---|---|---|
| px → cm | `2.54 / 96` = 0.0264583… | `ApplyParagraphFormat`, `ComputeColumnWidthsCm` |
| px → pt (font size) | `× 0.75` | `AddRun`, `AddLinkedText` |
| cm → pt | 28.346456… | Mac conversions |
| A4 | 21 × 29.7 cm | all |
| Printable width | 17 cm (21 − 2 − 2) | all |
| Right tab stop (header) | 16 cm | `hp.Format.TabStops.AddTabStop("16cm", Right)` |
| Rich-table total width | 16.0 cm | `ComputeColumnWidthsCm(wt, colCount, 16.0)` |
| List indent step | 0.6 cm/level; hanging −0.4 cm | `RenderBlock` |
| Subtask indent | `min(depth,4) × 0.6` cm | `WriteSubtaskDetailed` L407 |
| Link colour | RGB(11,97,164) | `LinkBlue` L916 |
| Lock sentinel | RGB(255,230,153) | `UniformInlineBackground` L1044; `ContainerEditor.LockedColor` |
| Default cell border colour | RGB(120,120,120) | `ApplyCellBorders` |
| Relationship desc limit | 180 | `WriteRelationships` |
| Combining strike | U+0336 | `CombiningStrikeChar` |
| Muted grey | RGB(120,120,120) | header, footer, meta, Subtitle, Muted |
| Table header shading | RGB(235,235,235) | components, files, checklist |

### 3.2 MigraDoc behaviours the Mac layout engine must reproduce

Verified against empira/PDFsharp 6.x source.

1. **PageSetup defaults** (used by ChecklistExporter, which sets only format, orientation and margins): HeaderDistance **1.25 cm**, FooterDistance **1.25 cm**. PdfExporter sets both to 1 cm.
2. **Header/Footer style.** Paragraphs added to a header or footer get style `Header`/`Footer`, both based on `Normal` with **no default tab stops**. So in PdfExporter the header's font is the resolved Calibri, with SpaceAfter 3 pt and ×1.15 line spacing, overridden to 9 pt grey.
3. **Normal defaults** (before the app overrides them): Arial 10, black, no spacing, single line spacing, **WidowControl = true**.
4. **Text splitting.** `AddText(s)` splits on `'\n'` → `AddLineBreak()` and on `'\t'` → `AddTab()`. Empty segments add nothing. `AddText(null)` throws.
5. **Space before at page top.** On document level, a page's first element has SpaceBefore = 0.
6. **Margin collapsing.** When both are ≥ 0, the gap between consecutive elements is `max(prev.SpaceAfter, next.SpaceBefore)`, otherwise their sum.
7. **KeepWithNext.** If an element and the chain of following KeepWithNext elements, up to and including the first non-KWN element's first line/row, do not fit in the remaining area, the element moves to the next page. Mac: implement "keep heading with the first line of the next block".
8. **Tables.**
   - Default Left/RightPadding 1.2 mm; Top/Bottom 0 unless set.
   - Rows are never split. Rows linked by MergeDown stay together.
   - HeadingFormat rows re-render at the top of every page the table continues onto.
   - A row taller than a page is placed anyway and overflows. See DEV-08.
   - `Borders.Visible = false` or width 0 draws no border.
9. **Paragraph borders** (H1 bottom rule): drawn at the paragraph's bottom edge across the paragraph width, from left indent to right indent.
10. **Shading** fills the paragraph's content box between its indents, for the height of its lines.
11. **Line spacing Multiple 1.15.** Line height = 1.15 × the font's natural line height (ascent + descent + leading). The Mac uses CoreText metrics; small metric differences are acceptable (tolerance: page count may differ by ±1 page for very long documents; content and order must not).
12. **Hyperlinks** (`HyperlinkType.Web`) produce a PDF `/Link` annotation with a `/URI` action over the linked text, one rectangle per line fragment when wrapped.
13. **Fields.** `AddPageField` gives the current page number (Arabic, starting at 1). `AddNumPagesField` gives the total page count of the document.

### 3.3 Styles (`DefineStyles`, PdfExporter.cs L243-298)

All styles derive from `Normal`, which is overridden to `ResolveFontName("Calibri")`, 11 pt, SpaceAfter 3 pt, LineSpacingRule Multiple, LineSpacing 1.15.

| Style | Font | Colour | Paragraph |
|---|---|---|---|
| `Normal` | resolved Calibri 11 | black | SpaceAfter 3 pt, ×1.15, WidowControl |
| `Title` | 26 **bold** | RGB(20,20,20) | SpaceAfter 4 pt |
| `Subtitle` | 12 | RGB(120,120,120) | SpaceAfter 12 pt |
| `H1` | 16 **bold** | black | SpaceBefore 16 pt, SpaceAfter 6 pt, KeepWithNext, **bottom border 0.75 pt RGB(60,60,60)** |
| `H2` | 13 **bold** | black | SpaceBefore 10 pt, SpaceAfter 4 pt, KeepWithNext |
| `H3` | 11 **bold** | RGB(60,60,60) | SpaceBefore 6 pt, SpaceAfter 2 pt, KeepWithNext |
| `BodyItalic` | 11 *italic* | RGB(80,80,80) | inherits |
| `Bullet` | 11 | black | LeftIndent 0.6 cm, FirstLineIndent −0.4 cm |
| `Muted` | 10 | RGB(120,120,120) | inherits |
| `Header`/`Footer` | inherit Normal; the app sets 9 pt RGB(120,120,120) on the paragraph | | footer: Alignment Right |

Direct formatting used in code: bold/italic `FormattedText`; per-run colour; the `Format` overrides listed in PDF-039/042.

`ChecklistExporter` does **not** call `DefineStyles`. Its Normal is `"Calibri"` (unresolved) 11 pt with MigraDoc default spacing (0/0, single).

### 3.4 Item and saved-list builders (function-by-function)

#### 3.4.1 `PdfExporter`

| Function (file:line) | Behaviour |
|---|---|
| static ctor (L38-47) | Enables Windows fonts for PDFsharp. Caches installed families (`System.Windows.Media.Fonts.SystemFontFamilies[].Source`, case-insensitive set). |
| `ResolveFontName(string?)` (L66-80) | PDF-076. |
| `Export(item, repo, path)` (L82-88) | `BuildDocument`, render, `Save(path)` (overwrites). |
| `ExportSavedLists(docTitle, entries, path, numbered)` (L95-181) | PDF-050…055. |
| `BuildDocument(item, repo)` (L185-241) | PDF-030…036, then `WriteSpecifics`, `WriteRelationships`, `WriteFileBank`. |
| `DefineStyles(doc)` (L243-298) | §3.3. |
| `WriteSpecifics` (L302-310) | Switch: Equipment → L312, TaskItem → L381, Procedure → L441. Vessel: nothing. |
| `WriteEquipmentSpecifics` (L312-369) | PDF-037. |
| `TaskWhen(t)` (L373-379) | PDF-041. |
| `WriteTaskSpecifics` (L381-400) | PDF-038. |
| `WriteSubtaskDetailed(sec, t, depth)` (L405-439) | PDF-039. The indent string is formatted `"{x:0.##}cm"`. MigraDoc's `Unit` parser accepts `,` as a decimal separator too, so culture does not matter. Mac: use numbers. |
| `WriteProcedureSpecifics` (L441-484) | PDF-042. |
| `WriteTaskSummary` (L486-508) | PDF-040. |
| `WriteRelationships` (L512-542) | PDF-044. |
| `WriteFileBank` (L546-572) | PDF-045. |
| `WriteContainerBody(sec, c, heading, leftIndent?)` (L576-637) | §3.5.1. |
| `ParseLengthCm(s)` (L639-642) | `Unit.Parse(s).Centimeter`, 0 on error. |
| `StripXamlTags(xaml)` (L644-656) | §3.4.2. |
| `RenderBlock(target, block, listLevelCm=0)` (L658-717) | §3.5.2. |
| `RenderTable` (L721-762), `TrueColumnCount` (L767-787), `RenderCellContent` (L789-794), `ApplyCellBorders` (L796-803), `ComputeColumnWidthsCm` (L807-829) | §3.5.8-10. |
| `ApplyParagraphFormat(par, wp)` (L831-859) | §3.5.3. |
| `RenderInline(par, inline)` (L861-902) | §3.5.4. |
| `AddRun(par, source, text)` (L904-912) | §3.5.5. |
| `AddRunAutoLinked` (L930-942), `AddLinkedText` (L946-954), `ScanLinks` (L958-974), `ToUri` (L976-979), `NormalizeLinkUri` (L982-987) | §3.5.11-12. |
| `ResolveFormat(source)` (L989-1000) | NotBold, then \|Bold if weight ≥ 600, \|Italic if Italic/Oblique, \|Underline if the Run's own decorations include Underline. |
| `HasDecoration(s, loc)` (L1002-1003) | Any `TextDecoration` in the **element's own** `TextDecorations` with that location. |
| `ApplyStrike(source, text)` (L1009-1025) | §3.5.7. |
| `UniformInlineBackground(p)` (L1029-1046), `EnumRuns` (L1048-1055), `EffectiveBackground` (L1059-1069) | §3.5.6. |
| `TryGetColor(brush, out color)` (L1071-1083) | PDF-077. |
| `H1/H2/H3/Italic` (L1087-1090) | `sec.AddParagraph(text)` + style (`Italic` = `BodyItalic`). |
| `KindLabel(k)` (L1092-1096) | Equipment → `Equipment/Area`, else the enum name. |
| `AddKV(tbl, key, value)` (L1098-1105) | Adds a row: key paragraph bold RGB(80,80,80); value paragraph plain. |
| `Shorten(s, max)` (L1107-1112) | PDF-102. |

#### 3.4.2 `StripXamlTags` (exact)

```
inTag = false; out = ""
for ch in xaml:
  if ch == '<': inTag = true; continue
  if ch == '>': inTag = false; out += ' '; continue   // a space for EVERY '>' (even outside a tag)
  if !inTag: out += ch
return HtmlDecode(out).Trim()
```

`HtmlDecode` = `System.Net.WebUtility.HtmlDecode`, which decodes named HTML entities (`&amp; &lt; &gt; &quot; &apos; &nbsp;` …) and numeric `&#NN;`/`&#xHH;` references. Invalid or unknown entities are left as-is. *Mac:* implement XML's five, numeric references, `&nbsp;`, and the HTML5 named entities that `WebUtility` knows (a table of ~250). At minimum the first three groups, since the stored XAML only ever contains XML escapes.

#### 3.4.3 `ChecklistExporter`

| Function (file:line) | Behaviour |
|---|---|
| `ExportPdf(proc, repo, path)` (L22-105) | PDF-080…084. |
| `Render(doc, path)` (L107-112) | Render + save. |
| `ExportXlsx(proc, repo, path)` (L116-139) | Builds `rows` (header + one per step), deletes any existing file, writes a ZIP with 6 entries (§4.5). |
| `WriteEntry(zip, name, content)` (L141-147) | `CompressionLevel.Optimal`, UTF-8 bytes (no BOM). |
| `ContentTypesXml/RootRelsXml/WorkbookRelsXml/StylesXml` (L149-208) | Constant XML (§4.5). |
| `WorkbookXml(sheetName)` (L167-179) | PDF-091. |
| `SheetXml(rows)` (L210-240) | §4.5.6. |
| `ColRef(index)` (L242-253) | 0-based → Excel letters (0 → A, 25 → Z, 26 → AA, 701 → ZZ, 702 → AAA). |
| `Esc(s)` (L255-259) | `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;` (in that order; `&` first). |

#### 3.4.4 UI-side helpers

- `ExportPdf_Click` (HierarchyPage.xaml.cs L755-796): PDF-001…006.
- `ExportChecklist(p, asExcel)` (L1393-1420): PDF-011/012.
- `SavedListsPage.ExportList_Click/ExportGroup_Click/ExportAll_Click/ExportToPdf/Sanitize` (L388-474): PDF-020…026.
- `SavedListOrder.GroupEntries(data, groupId)`: templates with `GroupId == groupId` in collection order. Group = the ListGroup's Name, or null if the name is null/empty (note **IsNullOrEmpty**, not whitespace; the exporter then treats whitespace as null too).
- `SavedListOrder.AllEntries(data)`: PDF-027.
- `ListStylePromptWindow.Ask(owner, prompt)`: returns `true` (numbered), `false` (bulleted) or `null` (cancelled).

### 3.5 Rich-text → PDF pipeline (the heart of fidelity)

#### 3.5.1 `WriteContainerBody(sec, c, heading, leftIndent)`

```
if c == nil or c.RichTextXaml is null/whitespace: return
fd = try Load(xaml) (TextRange.Load into a new FlowDocument; any throw → fd = nil)
firstNew = sec.Elements.count
if fd == nil:
    plain = StripXamlTags(xaml); if plain is blank: return
    if heading != "": H1(heading)
    for line in plain.replace("\r\n","\n").split("\n"): if !line.isBlank: sec.AddParagraph(line)   // Normal style, line kept untrimmed
else:
    if plainText(fd) is blank: return
    if heading != "": H1(heading)
    for block in fd.Blocks: RenderBlock(sec.Elements, block, 0)
if leftIndent != "":
    base = cm(leftIndent)
    for each element i in firstNew..<sec.Elements.count where element is Paragraph:
        element.LeftIndent = base + element.LeftIndent(cm, 0 if unset)
```

`plainText(fd)` is WPF `TextRange.Text` of the whole document. Only its "is blank" status matters. Mac equivalent: "no Run/Hyperlink text contains a non-whitespace character" (LineBreaks count as whitespace).

*Load semantics the Mac XAML reader must emulate:*
- `TextRange.Load` accepts `Section`-rooted fragments, as the editor saves, as well as `FlowDocument`-rooted documents and other valid block/inline XAML.
- The root's inheritable properties (FontFamily, FontSize, FontWeight, FontStyle, Foreground, TextAlignment …) flow down to all content.
- A `Section`, at root or nested, is a transparent container: `RenderBlock` recurses into it, passing the same list level.
- An empty loaded document has one empty Paragraph, which is blank and therefore skipped.
- Anything that fails XML/XAML parsing (unknown element, missing xmlns, invalid nesting such as a Run directly in a Section, plain text, `enc:` blobs) → fallback.
- *Uncertainty:* WPF may append a trailing empty Paragraph after a trailing Table when loading. That shows as one extra blank line. Verifiers MUST tolerate ±1 trailing blank paragraph after a table.

#### 3.5.2 `RenderBlock(target, block, listLevelCm)`

- **Paragraph:**
  - `par = target.AddParagraph()` (Normal);
  - `ApplyParagraphFormat(par, p)`;
  - if `UniformInlineBackground(p)` is a colour, it becomes the paragraph shading;
  - `anyText = OR over p.Inlines of RenderInline(par, inline)`;
  - if `!anyText`, `par.AddText(" ")`.
- **List:**
  - `numbered = MarkerStyle ∉ {None, Disc, Box, Circle, Square}`;
  - `levelLeft = 0.6 + listLevelCm`;
  - `idx = 1`;
  - for each ListItem li, for each block b in li.Blocks:
    - Paragraph lp:
      - `par = AddParagraph()`; `ApplyParagraphFormat(par, lp)`;
      - `par.LeftIndent = levelLeft`; `par.FirstLineIndent = −0.4`;
      - `par.AddText(numbered ? "\(idx). " : "\u{2022} ")`, then `idx += 1` (numbered only);
      - `RenderInline` for each inline;
      - no uniform-highlight step and no blank-space fallback, since the marker is always text.
    - List nested → `RenderBlock(target, nested, listLevelCm + 0.6)`.
    - else → `RenderBlock(target, b, listLevelCm)`.
- **Table** → `RenderTable(target, table)`.
- **Section** → `RenderBlock(target, child, listLevelCm)` for each child.
- **BlockUIContainer / anything else** → ignored.

#### 3.5.3 `ApplyParagraphFormat(par, wp)`

```
alignment = {Center→center, Right→right, Justify→justify, else→left}[wp.TextAlignment]
if solidColour(wp.Background) → shading
k = 2.54/96
leftCm = wp.Margin.Left > 0 ? wp.Margin.Left*k : 0          // NaN/Auto → 0
firstCm = 0
if wp.TextIndent > 0: leftCm += wp.TextIndent*k
elif wp.TextIndent < 0: firstCm = wp.TextIndent*k
if leftCm > 0: par.LeftIndent = leftCm
if firstCm != 0: par.FirstLineIndent = firstCm
if wp.Margin.Right > 0: par.RightIndent = wp.Margin.Right*k
```

The editor's Indent/Outdent buttons change `Margin.Left` by 24 px (`ListFormatting.IndentStep`), i.e. 0.635 cm per step, and reset TextIndent to 0. Older data may carry the shift on TextIndent instead.

#### 3.5.4 `RenderInline(par, inline) → Bool` (returns "emitted any text")

Order matters: **Hyperlink is tested before Span**, because Hyperlink is a Span.
- **Run**: empty text → false. Else `AddRunAutoLinked(par, run)`.
- **LineBreak**: `par.AddLineBreak()` → true.
- **Hyperlink**: `uri = NormalizeLinkUri(NavigateUri?.ToString())`.
  - uri == nil → render children as ordinary inlines and return their OR (PDF-072).
  - else `link = par.AddHyperlink(uri, Web)`; for each child:
    - a Run with non-empty text → `AddLinkedText(link, run, run.Text)` (**no** auto-link scanning inside);
    - any other child (Span, LineBreak, nested Hyperlink) → `RenderInline(par, child)`, appended to the **paragraph**, not the link. See DEV-02 about the resulting order.
  - Returns true if anything was emitted. A link whose runs are all empty produces an empty link element.
  - *.NET detail:* `Uri.ToString()` returns the canonical, **unescaped** form and adds `/` to a bare authority (`https://example.com` → `https://example.com/`). See DEV-11.
- **Span** (includes `Bold`, `Italic`, `Underline` elements): OR of the children.
- **InlineUIContainer, Figure, Floater, other** → false.

#### 3.5.5 `AddRun` / `AddLinkedText`

```
AddRun(par, src, text):
  ft = par.AddFormattedText(ApplyStrike(src, text), ResolveFormat(src))
  if solidColour(src.Foreground) → ft.Color
  ft.FontName = ResolveFontName(src.FontFamily.Source)       // effective (inherited) family, always present
  ft.FontSize = src.FontSize * 0.75                           // effective size > 0 always
AddLinkedText(link, src, text):
  ft = link.AddFormattedText(ApplyStrike(src, text), ResolveFormat(src) | Underline)
  ft.Color = RGB(11,97,164)
  ft.FontName / FontSize as above
```

The effective Foreground, FontFamily, FontSize, FontWeight and FontStyle come from the nearest ancestor that sets them (Run → Span/Hyperlink → Paragraph/ListItem/List/TableCell/TableRow/Table/Section → document root). Defaults when nothing sets them: FontFamily `Segoe UI` (WPF `SystemFonts.MessageFontFamily`), FontSize 12 px, FontWeight Normal, FontStyle Normal, Foreground black. Editor-saved XAML always sets them on the root Section, typically `FontFamily="Consolas" FontSize="14" Foreground="#FF1A1A1A"`.

`TextDecorations` and `Background` are **not** inherited in WPF (Background is handled specially, §3.5.6).

#### 3.5.6 Highlight helpers

```
EffectiveBackground(run):   // walk up; stop AFTER checking the Paragraph (never reach table cell/row)
  d = run
  while d is TextElement:
    if d.Background != nil: return d.Background
    if d is Paragraph: break
    d = d.Parent
  return nil
EnumRuns(inlines): depth-first; yields Runs, descending into Span (and therefore Hyperlink); skips other inlines
UniformInlineBackground(p):
  found = nil; anyText = false
  for run in EnumRuns(p.Inlines) where run.Text non-empty:
     anyText = true
     c = solidColour(EffectiveBackground(run)) else return nil
     if found == nil: found = c elif found != c: return nil
  if !anyText or found == nil: return nil
  if found == RGB(255,230,153): return nil       // edit-lock sentinel
  return found
```

A paragraph whose own Background is set therefore makes every run "highlighted" with that colour, so the result equals rule (a) anyway.

#### 3.5.7 `ApplyStrike` (Windows reference algorithm)

```
if text empty or run's own TextDecorations lacks Strikethrough: return text
for each UTF-16 position i:
   n = (text[i] is high surrogate and text[i+1] is low surrogate) ? 2 : 1
   append text[i..<i+n]
   if !isControl(text[i]) && !isWhiteSpace(text[i]): append U+0336
   i += n
```

.NET `char.IsWhiteSpace` covers Unicode `Zs/Zl/Zp` plus U+0009–U+000D, U+0085 and U+00A0. `char.IsControl` covers `Cc`.
*Mac (DEV-04):* apply `NSUnderlineStyle.single` strikethrough (colour = run colour) to exactly those characters that Windows would overlay, i.e. every Character whose first scalar is not whitespace/control. Whitespace stays unstruck. The same predicate MUST be used so the visual gaps match.

#### 3.5.8 `RenderTable(target, wt)`

```
rows = wt.RowGroups.flatMap(\.Rows); if rows.isEmpty: return
colCount = max(wt.Columns.count, TrueColumnCount(rows)); if colCount < 1: colCount = 1
mt = target.AddTable(); mt.Borders.Visible = false
widths = ComputeColumnWidthsCm(wt, colCount, 16.0); add columns
add rows.count rows
occupied[rows.count][colCount] = false
for r in rows.indices:
  col = 0
  for wc in rows[r].Cells:
     while col < colCount && occupied[r][col]: col += 1
     if col >= colCount: break                               // remaining cells of this row dropped
     cs = clamp(max(1, wc.ColumnSpan), 1, colCount - col)
     rs = clamp(max(1, wc.RowSpan), 1, rows.count - r)
     cell = mt[r][col]; cell.MergeRight = cs-1; cell.MergeDown = rs-1
     ApplyCellBorders(cell, wc)                              // w = max(L,R,T,B); w<=0 → none; else width w pt, colour BorderBrush or RGB(120,120,120)
     if solidColour(wc.Background) → cell.Shading
     if wc.FontWeight (effective) >= 600 → cell.Format.Font.Bold = true
     RenderCellContent(cell, wc)                             // RenderBlock(cell.Elements, b) for each block; add empty paragraph if none produced
     mark occupied[r..r+rs-1][col..col+cs-1]
     col += cs
```

*Nested tables* (a Table inside a TableCell) are passed to `RenderTable` with the cell as target. MigraDoc does not officially support tables inside cells, so the Windows result is uncertain: it may throw and fail the export, or drop the table. *Mac:* render the nested table inside the cell (open question Q4).

#### 3.5.9 `TrueColumnCount(rows)`

```
occupied = Set<(r,c)>; maxCol = 0
for r in rows.indices:
  col = 0
  for wc in rows[r].Cells:
     while occupied.contains((r,col)): col += 1
     cs = max(1, wc.ColumnSpan); rs = max(1, wc.RowSpan)
     for dr in 0..<rs, dc in 0..<cs: occupied.insert((r+dr, col+dc))
     col += cs; maxCol = max(maxCol, col)
return maxCol
```

This grid is unbounded, with no clamping. Rowspans that extend past the last row are harmless.

#### 3.5.10 `ComputeColumnWidthsCm(wt, colCount, totalCm=16)`

```
k = 2.54/96; w = [Double](repeating: 0, count: colCount); anyAbs = false
for c in 0..<min(colCount, wt.Columns.count):
   if wt.Columns[c].Width is absolute (px) and value > 0: w[c] = value*k; anyAbs = true
if !anyAbs: return Array(repeating: totalCm/colCount, count: colCount)
known = sum(w where >0); missing = count(w where <=0)
each = missing > 0 ? max(1.0, (totalCm - known)/missing) : 0
fill w[c] <= 0 with each
tot = sum(w); if tot > totalCm: w = w.map { $0 * totalCm/tot }
return w
```

WPF `GridLength` from XAML: `"123"` or `"123px"` = absolute px; `"1in"`, `"2cm"`, `"12pt"` = absolute, converted to px; `"Auto"` = not absolute; `"*"`/`"2*"` = star, not absolute. A missing Width attribute is not absolute. Pasted RTF (Word) tables usually carry absolute widths; the editor's Insert-table and HTML pastes do not.

#### 3.5.11 Links: `NormalizeLinkUri`, `ToUri`, `AddRunAutoLinked`

```
NormalizeLinkUri(s): if s blank → nil; s = trim(s); return s.lowercased().hasPrefix("www.") ? "https://"+s : s
ToUri(t, isMail): isMail ? "mailto:"+t : (t.lowercased().hasPrefix("www.") ? "https://"+t : t)
AddRunAutoLinked(par, run):
   any = false
   for (seg, uri) in ScanLinks(run.Text) where !seg.isEmpty:
      if uri != nil: AddLinkedText(par.AddHyperlink(uri, Web), run, seg) else AddRun(par, run, seg)
      any = true
   return any
```

The scan is **per Run**. A URL split across two runs (e.g. part bold) is scanned piecewise. `^` in the lookbehind is the **start of the run**, so a run that begins with `https://…` links even if the previous run ended in a letter. The Mac MUST scan per run with identical semantics.

#### 3.5.12 `ScanLinks(text)` and the regex (exact)

.NET pattern (options `IgnoreCase | Compiled`):

```
(?<=^|[\s(\[<"'])(?:(?<url>(?:https?://|www\.)[^\s<>()]+)|(?<mail>(?>[A-Za-z0-9._%+\-]+)@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}))
```

(In C# source it appears with `""` for the double quote inside a verbatim string.)

Semantics:
- **Start-of-token lookbehind:** the match must begin at text start or right after Unicode whitespace or one of `( [ < " '`. A comma, colon, slash, backslash, underscore or letter before it prevents a match. This is what stops `backup_www.tar.gz`, `C:\svc\www.cache\x` and `mailto:joe@x.com` from linking. It also makes the scan effectively linear: non-boundary positions fail in O(1).
- **url** branch: `http://`, `https://` or `www.` (any case), then one or more characters that are not whitespace, `<`, `>`, `(` or `)`.
- **mail** branch: an **atomic** local part `[A-Za-z0-9._%+-]+`, `@`, a label `[A-Za-z0-9-]+`, zero or more `.label`, then a final `.` and a TLD of ≥ 2 ASCII letters.

```
ScanLinks(text):
  if empty: return []
  last = 0; out = []
  for m in regex.matches(text) (left-to-right, non-overlapping on the RAW match):
     len = m.length
     while len > 0 && ".,;:!?)]}'\"".contains(m.value[len-1]): len -= 1
     if len == 0: continue
     linkText = m.value.prefix(len)
     if m.index > last: out.append((text[last..<m.index], nil))
     out.append((linkText, ToUri(linkText, m.group("mail").matched)))
     last = m.index + len          // trimmed punctuation flows into the next plain segment
  if last < text.count: out.append((text[last...], nil))
  return out
```

*Swift implementation note:* use `NSRegularExpression` (ICU) with `.caseInsensitive`. ICU supports the bounded lookbehind `(?<=^|[…])`, atomic groups `(?>…)` and named groups `(?<url>…)`. All indices are UTF-16 offsets; convert ranges with `Range(nsRange, in: text)`. ICU's `\s` matches `[\t\n\f\r\p{Z}]` and U+0085/U+000B, a close match for .NET `\s` (the differences are irrelevant here). Do **not** use Swift `Regex` literals unless lookbehind support is confirmed on the target toolchain.

### 3.6 XLSX specifics

#### 3.6.1 Rows

```
rows = [["#","Done","Step","Due","Linked Tasks","Linked Equipment/Area"]]
for (i, s) in proc.Steps.enumerated():
   tasks = s.TaskIds.compactMap { repo.FindById($0)?.Name }.joined("; ")
   eqs   = s.EquipmentIds.compactMap { repo.FindById($0)?.Name }.joined("; ")
   rows.append([String(i+1), s.Done ? "Yes" : "No", s.Title ?? "", s.Deadline?.yyyyMMdd ?? "", tasks, eqs])
```

#### 3.6.2 Mac sheet-name rule (DEV-03)

```
raw = name.isBlank ? "Checklist" : name
raw = raw.replacing any of [ : \ / ? * [ ] ] with "_" and drop XML-illegal chars
raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))   // Excel forbids leading/trailing apostrophe
if raw.isEmpty || raw.caseInsensitiveCompare("History") == .orderedSame: raw = "Checklist"
raw = prefix(raw, 31 UTF-16 units, not splitting a surrogate pair)
sheetName = xmlEscape(raw)
```

This yields the same name as Windows for every name Windows handled correctly.

---

## 4. Data formats

### 4.1 JSON fields read (data.json — read-only in this subsystem)

System.Text.Json with default options plus `DefaultIgnoreCondition = WhenWritingNull`, `ReferenceHandler.IgnoreCycles`, `WriteIndented = false`:
- property names are **PascalCase** as declared;
- **enums are integers**, since there is no `JsonStringEnumConverter`;
- `DateTime` is ISO-8601 (`2026-07-10T00:00:00`, optionally with `Z` or an offset);
- `Guid` is the standard 36-char string;
- null-valued properties are omitted.
This subsystem never writes data.json.

| Model (JSON path) | Keys used | Notes |
|---|---|---|
| `AppData` | `Equipment[]`, `Tasks[]`, `Procedures[]`, `Vessels[]`, `ChecklistTemplates[]`, `ListGroups[]`, `Ui.SortAZ` (key `"savedlists"`, display only) | `FindById` searches only the four item arrays, in that order, first match wins. |
| `HierarchyItem` (all 4) | `Id`, `Name`, `Description`, `Container`, `RelatedIds[]`, `LockHash`, `LockSalt` | Kind is implied by which array the item is in. `Kind` is `[JsonIgnore]`. |
| `Equipment` | `Components[]`, `ProcedureIds[]`, `TaskIds[]` | |
| `Component` | `Name`, `Notes` | `Container` **not** read. |
| `TaskItem` | `Deadline?`, `RangeStart?`, `Recurrence` (int: 0 None, 1 Daily, 2 Weekly, 3 Monthly, 4 Yearly), `IsComplete`, `Subtasks[]` (recursive TaskItem), `Container` | `Status` (0 Todo, 1 InProgress, 2 Blocked, 3 Done) not read. Completed/Open comes from `IsComplete`. |
| `Procedure` | `Steps[]` | Own Deadline/Recurrence/Status not read. |
| `ChecklistStep` | `Title`, `Done`, `Deadline?`, `TaskIds[]`, `EquipmentIds[]`, `Container` | |
| `Container` | `RichTextXaml` (string, WPF XAML, §4.3), `Files[]` | `IsLocked`/`SharedWithContainerIds` not read. |
| `FileItem` | `Name`, `Path`, `Kind` (int: 0 Document, 1 Image, 2 Video, 3 Link, 4 Other) | Printed as the enum **name**. |
| `ChecklistTemplate` | `Id`, `Name`, `Items[]`, `GroupId?` | Array order = user arrangement (PDF-027). |
| `ChecklistTemplateItem` | `Title`, `IsJob`, `Container` | `DurationMinutes` deliberately not printed. |
| `ListGroup` | `Id`, `Name` | |

Enum-name tables the Mac needs for printing (must match exactly): Recurrence `None/Daily/Weekly/Monthly/Yearly` (lower-cased in subtask meta); FileKind `Document/Image/Video/Link/Other`; ItemKind raw names `Equipment/Task/Procedure/Vessel`.

### 4.2 Date handling

- `Deadline`, `RangeStart` and step `Deadline` are printed with their **stored calendar date** (`yyyy-MM-dd`). Range comparisons use `.Date` (drop the time): "start < deadline" compares calendar days only.
- The export timestamp in headers is the **local** "now".
- There is no UTC conversion anywhere in this subsystem.

### 4.3 XAML shapes consumed (for the XAML ⇄ model converter)

Stored `RichTextXaml` is WPF `TextRange.Save(DataFormats.Xaml)` output. Typical shape (attributes abbreviated):

```xml
<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve"
         TextAlignment="Left" LineHeight="Auto" IsHyphenationEnabled="False" xml:lang="en-us"
         FlowDirection="LeftToRight" NumberSubstitution.CultureSource="User" NumberSubstitution.Substitution="AsCulture"
         FontFamily="Consolas" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="14"
         Foreground="#FF1A1A1A" Typography.StandardLigatures="True" … >
  <Paragraph Margin="24,0,0,0" TextAlignment="Center">
    <Run FontWeight="Bold" Foreground="#FFC00000">Warning</Run><Run> see </Run>
    <Hyperlink NavigateUri="https://www.imo.org/"><Run>IMO</Run></Hyperlink><LineBreak/>
    <Run TextDecorations="Strikethrough">old value</Run><Run Background="#FFFFFF00"> highlighted</Run>
  </Paragraph>
  <List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0">
    <ListItem><Paragraph Margin="0,1,0,1"><Run>item</Run></Paragraph>
      <List MarkerStyle="Circle" Margin="0,0,0,0" Padding="24,0,0,0"><ListItem><Paragraph><Run>sub</Run></Paragraph></ListItem></List>
    </ListItem>
  </List>
  <Table CellSpacing="0" Margin="0,4,0,4">
    <Table.Columns><TableColumn Width="160"/><TableColumn/></Table.Columns>
    <TableRowGroup>
      <TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1" FontWeight="Bold" ColumnSpan="2"><Paragraph><Run>Head</Run></Paragraph></TableCell></TableRow>
    </TableRowGroup>
  </Table>
</Section>
```

Element/attribute support table for the **PDF** consumer:

| Element | Attributes that affect the PDF | Attributes ignored |
|---|---|---|
| `Section` (root or nested; `FlowDocument` root also accepted) | inheritable: `FontFamily`, `FontSize`, `FontWeight`, `FontStyle`, `Foreground`, `TextAlignment` (inherited by paragraphs) | `Background` (not inherited), `LineHeight`, `xml:lang`, `FlowDirection`, `Typography.*`, `NumberSubstitution.*`, `IsHyphenationEnabled`, `FontStretch`, `Margin`, `Padding`, borders |
| `Paragraph` | `TextAlignment`, `Margin` (Left, Right), `TextIndent`, `Background`, inheritable font props, `Foreground` | `Margin` Top/Bottom, `Padding`, `BorderThickness`/`BorderBrush` (hr), `LineHeight`, `TextDecorations`, `KeepTogether`, `KeepWithNext`, `BreakPageBefore` |
| `List` | `MarkerStyle` (None, Disc, Circle, Square, Box, LowerRoman, UpperRoman, LowerLatin, UpperLatin, Decimal), inheritable props | `StartIndex`, `MarkerOffset`, `Margin`, `Padding` |
| `ListItem` | inheritable props | `Margin`, `Padding` |
| `Table` | inheritable props | `CellSpacing`, `Margin`, `Background`, borders |
| `Table.Columns`/`TableColumn` | `Width` (absolute px or length units only) | `Background` |
| `TableRowGroup`, `TableRow` | inheritable props | `Background` |
| `TableCell` | `ColumnSpan`, `RowSpan`, `BorderThickness` (1/2/4-value Thickness), `BorderBrush`, `Background`, `FontWeight` (and other inheritable props) | `Padding`, `TextAlignment` (only inherited by child paragraphs), `LineHeight` |
| `Run` | text (element content or `Text=""`), `FontWeight`, `FontStyle`, `TextDecorations` (`Underline`, `Strikethrough`, comma-combined; `OverLine`/`Baseline` ignored), `Foreground`, `Background`, `FontFamily`, `FontSize` | `BaselineAlignment`, `Typography.*`, `FontStretch`, `xml:lang` |
| `Span`, `Bold`, `Italic`, `Underline` | inheritable props flow to child runs (`Bold` ⇒ FontWeight Bold, `Italic` ⇒ FontStyle Italic); `Background` (read via `EffectiveBackground`) | the Span's own `TextDecorations` (so the `Underline` element's underline is lost on Windows, DEV-01) |
| `Hyperlink` | `NavigateUri`; children | `TargetName`, `ToolTip`, the Hyperlink's own Foreground (links are forced blue) |
| `LineBreak` | line break | |
| `InlineUIContainer`, `BlockUIContainer`, `Figure`, `Floater` | dropped with their contents | |

Value formats the reader must accept:
- **Colours** (BrushConverter): `#RGB`, `#ARGB`, `#RRGGBB`, `#AARRGGBB` (hex, case-insensitive), named colours (the WPF `Colors` set, e.g. `Red`, `Transparent`), `sc#a,r,g,b` (scRGB floats). Property-element brushes such as `<Run.Background><SolidColorBrush Color="…"/></Run.Background>` count as solid. Gradient/Image/Visual brushes count as "no colour".
- **Lengths** (FontSize, Margin, TextIndent, Width): a plain number = px (1/96 in), or suffixed `px`, `in` (×96), `cm` (×96/2.54), `pt` (×96/72). `Auto`/`NaN` count as not set.
- **Thickness**: `a`, `h,v` or `l,t,r,b`, comma- or space-separated.
- **FontWeight**: named (`Thin`=100, `ExtraLight`/`UltraLight`=200, `Light`=300, `Normal`/`Regular`=400, `Medium`=500, `DemiBold`/`SemiBold`=600, `Bold`=700, `ExtraBold`/`UltraBold`=800, `Black`/`Heavy`=900, `ExtraBlack`/`UltraBlack`=950) or a number.
- **FontStyle**: `Normal`, `Italic`, `Oblique`.
- `xml:space="preserve"`: whitespace in Run text is significant.

### 4.4 PDF output

- PDF produced by PDFsharp 6.2 on Windows with Unicode and embedded, subsetted TrueType fonts.
- Info dictionary: `/Title`, `/Author (AA)`.
- One page size (A4), portrait.
- Link annotations are `/Subtype /Link` with `/A << /S /URI /URI (…) >>`.
- There are no bookmarks/outlines, no tagged structure, no form fields and no encryption.
- *Mac:* generate with `CGContext(url:mediaBox:auxiliaryInfo:)` (PDF context), `beginPDFPage/endPDFPage`, text with CoreText, and links with `CGPDFContextSetURLForRect`. Fonts are embedded by Core Graphics automatically. Adding a PDF outline is **optional** (an addition).

### 4.5 XLSX output (byte content; Mac must match text exactly, apart from line endings)

The line breaks inside the constant strings are LF in the repo source (a Windows checkout may make them CRLF). Line endings are not significant, and verifiers MUST parse the XML rather than byte-compare. There is no BOM.

4.5.1 `[Content_Types].xml`

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
```

4.5.2 `_rels/.rels`

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
```

4.5.3 `xl/workbook.xml` (`{safe}` per PDF-091 / §3.6.2)

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="{safe}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
```

4.5.4 `xl/_rels/workbook.xml.rels`

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
```

4.5.5 `xl/styles.xml` (identical to `XlsxWriter.StylesXml`)

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFEEEEEE"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
```

Note: fill index 1 is a solid fill; Excel's reserved `gray125` fill at index 1 is absent. Excel tolerates this and shows fill 1 as light grey `#EEEEEE`. Keep it exactly as is.

4.5.6 `xl/worksheets/sheet1.xml`

```
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<cols>
<col min="1" max="1" width="5" customWidth="1"/>
<col min="2" max="2" width="7" customWidth="1"/>
<col min="3" max="3" width="55" customWidth="1"/>
<col min="4" max="4" width="14" customWidth="1"/>
<col min="5" max="5" width="40" customWidth="1"/>
<col min="6" max="6" width="40" customWidth="1"/>
</cols>
<sheetData>
<row r="1"><c r="A1" t="inlineStr" s="1"><is><t xml:space="preserve">#</t></is></c>…<c r="F1" t="inlineStr" s="1"><is><t xml:space="preserve">Linked Equipment/Area</t></is></c></row>
<row r="2"><c r="A2" t="inlineStr" s="0"><is><t xml:space="preserve">1</t></is></c>…</row>
</sheetData>
</worksheet>
```

- Each `<row>` is on one line.
- Cells are ordered A..F.
- Style `s="1"` applies to row 1 only, `s="0"` to all other rows.
- Every cell is written even when empty (`<t xml:space="preserve"></t>`).
- Cell text is escaped with `Esc` (and, on the Mac, illegal-char stripping per DEV-03).

4.5.7 ZIP container

- Standard ZIP with entries as listed, compression method 8 (DEFLATE), no encryption, no directory entries, UTF-8 names (all ASCII).
- Timestamps are the local time of writing (irrelevant).
- *Mac:* reuse the app's shared ZIP writer (the one used for `.aaz`/`.zip` bundles), or write it with Apple's `Compression` framework (`COMPRESSION_ZLIB`, which emits raw DEFLATE as ZIP needs) plus a CRC-32 table. Write to a temp file in the same directory, then atomically replace the destination.

### 4.6 Cross-version compatibility rules

- Exports are outputs only. Nothing in data.json, settings or bundles changes, so there is no data-compat risk.
- Because the Mac reads the **same** model, the same data must produce the **same** document structure, strings and ordering on both platforms. This is what the test vectors in §7 pin down.
- The xlsx column headers (`#`, `Done`, `Step`, `Due`, `Linked Tasks`, `Linked Equipment/Area`) and values (`Yes`/`No`, `yyyy-MM-dd` text) are a de-facto interchange contract (users filter and pivot on them). They MUST be identical.

---

## 5. Dependencies

### 5.1 Called by

| Caller | Call | Notes |
|---|---|---|
| `HierarchyPage.ExportPdf_Click` | `PdfExporter.Export(_selected, _repo, path)` | after `ItemLockService.IsGated`, `ContainerCtrl.FlushPending()`, `_repo.FlushIfDirty()` |
| `HierarchyPage.ExportChecklist` | `ChecklistExporter.ExportPdf` / `ExportXlsx` | after `_repo.FlushIfDirty()` |
| `SavedListsPage.ExportToPdf` | `PdfExporter.ExportSavedLists(title, entries, path, numbered)` | after `ListStylePromptWindow.Ask` |

### 5.2 Calls into

| Dependency | Functions used |
|---|---|
| `AppRepository` | `FindById(Guid)` (top-level items only), `RelatedItems(item)` |
| `SavedListOrder` | `GroupEntries(data, gid?)`, `AllEntries(data)` |
| `ItemLockService` | `IsGated(item)` (UI side only) |
| `ContainerEditor` | `FlushPending()` (UI side); lock sentinel colour `#FFFFE699` (shared constant) |
| `ListStylePromptWindow` | `Ask(owner, prompt) -> bool?` |
| Models | §4.1 |

### 5.3 Windows-only APIs and libraries used

| API | Use | Mac replacement |
|---|---|---|
| **PDFsharp-MigraDoc-gdi 6.2** (GDI+ build) | document model, layout, pagination, PDF writing | Custom Swift layout engine on **CoreText** + **CGContext PDF** (§6.1) |
| **WPF `FlowDocument` / `TextRange.Load(DataFormats.Xaml)`** | parse stored rich text | Shared Swift XAML reader (Foundation `XMLParser` or `XMLDocument`) producing a FlowDocument-like tree (§6.3). Owned by the rich-text/XAML converter spec. |
| `System.Windows.Media.Fonts.SystemFontFamilies` | installed-font test | `NSFontManager.shared.availableFontFamilies` / `CTFontManagerCopyAvailableFontFamilyNames()` |
| `PdfSharp.Fonts.GlobalFontSettings.UseWindowsFontsUnderWindows` | font discovery | n/a (CoreText) |
| `Microsoft.Win32.SaveFileDialog` | save dialogs | `NSSavePanel` (sheet) / SwiftUI `.fileExporter` |
| `MessageBox.Show` | messages | `NSAlert` (sheet) / SwiftUI `.alert` |
| `Mouse.OverrideCursor = Wait` | busy state | progress indicator; async export |
| `Process.Start(path){UseShellExecute}` | open result | `NSWorkspace.shared.open(url)` |
| `Path.GetInvalidFileNameChars()` (Windows set) | default file names | hard-coded Windows set (for identical suggestions) |
| `System.IO.Compression.ZipArchive` | xlsx container | shared Swift ZIP writer / `Compression` framework |
| `System.Net.WebUtility.HtmlDecode` | fallback text | small Swift entity decoder |
| `System.Text.RegularExpressions` (.NET) | link scan | `NSRegularExpression` |
| `ListStylePromptWindow` (WPF window) | prompt | SwiftUI sheet |

There is no DPAPI, OpenCV, DirectShow or Win32 P/Invoke in this subsystem.

---

## 6. macOS adaptation notes

### 6.1 PDF engine — recommended architecture

There is no MigraDoc on macOS. The output relies on MigraDoc semantics (styles, KeepWithNext, repeated table header rows, merged cells, per-cell borders, page/num-pages fields, clickable links) that neither `NSTextView` printing nor PDFKit reproduce reliably. **Build a small MigraDoc-like engine in Swift.** It keeps the exporters a line-by-line port and makes the output unit-testable.

```
AAExport (Swift package / module)
 ├─ PdfDOM.swift          // value types mirroring MigraDoc: Document(info, styles, sections)
 │                        // Section(pageSetup, header:[Paragraph], footer:[Paragraph], elements:[Block])
 │                        // Block = .paragraph(Paragraph) | .table(Table)
 │                        // Paragraph(style, format overrides, inlines:[Inline])
 │                        // Inline = .text(String, CharFormat) | .lineBreak | .tab | .pageField | .numPagesField
 │                        //          | .link(url: String, [Inline])
 │                        // Table(columns:[CGFloat], borders, padding, rows:[Row(headingFormat, shading, cells:[Cell])])
 │                        // Cell(mergeRight, mergeDown, borders, shading, bold, blocks:[Block])
 ├─ PdfStyles.swift       // style sheet + inheritance (Normal → Title/H1/…); §3.3 values
 ├─ FontResolver.swift    // §6.4
 ├─ LinkScanner.swift     // §3.5.11-12 (pure, unit-tested)
 ├─ RichTextToPdf.swift   // FlowDoc tree (from the shared XAML reader) → [Block]; §3.5 exactly
 ├─ ItemPdfBuilder.swift        // port of BuildDocument + Write* (§3.4.1)
 ├─ SavedListsPdfBuilder.swift  // port of ExportSavedLists
 ├─ ChecklistPdfBuilder.swift   // port of ChecklistExporter.ExportPdf
 ├─ ChecklistXlsxWriter.swift   // §4.5 (shares XlsxPackage with the crew export's XlsxWriter port)
 ├─ PdfLayoutEngine.swift  // CoreText measurement + top-down pagination (§3.2 rules) → [PageDisplayList]
 └─ PdfRenderer.swift      // draws display lists into a CGContext PDF; link annotations; fields resolved in pass 2
```

Engine rules:
- **Measurement and line breaking:** build an `NSAttributedString` per paragraph (font, colour, underline, strike, kern 0) and use `CTTypesetterSuggestLineBreak` with the available width. Line 1 width = content width − leftIndent − firstLineIndent − rightIndent; later lines = content width − leftIndent − rightIndent. Handle `.tab` as advancing to the next multiple of 1.25 cm from the paragraph's left edge (MigraDoc default tab interval; explicit tab stops only in the header).
- **Line height:** `1.15 × (ascent + descent + leading)` of the largest font on the line for PdfExporter documents; `1.0 ×` for the checklist PDF.
- **Pagination:** top-down, with the §3.2 rules. Widow/orphan control of 2 lines. KeepWithNext chain. Tables row-atomic with repeated heading rows. Page-top SpaceBefore suppression. Max-collapse of spacing.
- **Pass 1** lays out with a placeholder for `numPagesField` sized for the widest plausible value (e.g. `"999"`). **Pass 2** draws with the real total. The footer is right-aligned, so the text simply re-aligns.
- **Links:** after drawing each `CTLine`, compute the typographic bounds of glyph runs that carry the link attribute. Call `CGPDFContextSetURLForRect(ctx, url as CFURL, rectInPageSpace)` once per line fragment. Only add a link when `URL(string:)` succeeds; for strings with spaces, percent-encode first (DEV-11).
- **Colours:** create with `CGColor(srgbRed:green:blue:alpha:)` from the fixed RGB triples.
- **Info:** `auxiliaryInfo: [kCGPDFContextTitle: title, kCGPDFContextAuthor: "AA", kCGPDFContextCreator: "AA"]`.

Rejected alternatives (for the record):
- `NSTextView` + `NSPrintOperation` → PDF: no repeated table header rows, no KeepWithNext, and `NSTextTable` can't express MigraDoc's merged-cell border resolution faithfully.
- WebKit HTML → PDF (`WKWebView.createPDF`): loses exact metrics and page fields.
- PDFKit alone: it has no layout engine.

PDFKit **is** recommended for **tests**. Use `PDFDocument(url:)` to count pages, extract text (`page.string`), and read `PDFAnnotation`s of type `.link` with their `.url`, mirroring the Windows harness that verified `/URI` annotations.

### 6.2 Concurrency & UX

- Snapshot on the main actor: flush editors (DEV-09), then copy the needed model subgraph into `Sendable` value snapshots.
- Build the DOM and render off-main: `Task.detached(priority: .userInitiated)`.
- Show progress: a small sheet with `ProgressView("Exporting PDF…")`, or a toolbar spinner. Export is typically < 1 s; show the indicator only after ~300 ms to avoid flicker.
- Errors come back to the main actor as `NSAlert` sheets with the exact strings of PDF-005/012/025.
- `NSSavePanel` MUST be shown as a **sheet** on the window that invoked the export. After a successful save, `NSWorkspace.shared.open(url)` for items and checklists (auto-open), or the "Open it now?" alert for saved lists.
- Optional Mac additions, not required for parity:
  - **File ▸ Print…** (⌘P) on an item: build the same PDF into memory (`CGDataConsumer` over `NSMutableData`) and print with `PDFDocument(data:)?.printOperation(for:scalingMode:.pageScaleNone, autoRotate:false)`.
  - A **Share** button (`NSSharingServicePicker`) using the exported file.
- **Keyboard:** Windows has no shortcut. Mac: ⌥⌘E "Export as PDF…" for the focused item (coordinate with the global Commands spec). No shortcut for checklist or saved-list exports.
- **SF Symbols:** item export `arrow.up.doc`; checklist PDF `list.bullet.rectangle.portrait`; Excel `tablecells`; saved lists `doc.on.doc`.

### 6.3 XAML input

The PDF pipeline MUST work from the **stored XAML string**, parsed by the app-wide XAML reader (owned by the rich-text spec) into an element tree that keeps WPF semantics:
- element kinds (Section, Paragraph, List, ListItem, Table…, Run, Span, Bold, Italic, Underline, Hyperlink, LineBreak, UI containers);
- **inheritable** property resolution (FontFamily, FontSize, FontWeight, FontStyle, Foreground, TextAlignment);
- **non-inherited** Background and TextDecorations per element;
- parent links, which `EffectiveBackground` needs.
Do **not** go through `NSAttributedString`. It flattens lists and tables, and it may carry dynamic (dark-mode) colours (PDF-104). If the reader throws, use the `StripXamlTags` fallback (PDF-060).

### 6.4 Fonts on macOS (MUST — DEV-06)

Windows always has Calibri, Consolas and Segoe UI; a stock Mac has none of them. Following the Windows fallback literally ("not installed → Calibri → Arial") would turn every Consolas note into proportional Arial. That is a visible fidelity loss, since the editor's default font is Consolas. The Mac `FontResolver` therefore resolves in three steps:

1. Split the source on `,`, trim whitespace then `'`/`"`, apply the **Windows alias map** (PDF-076).
2. If the name is installed (`NSFontManager.shared.availableFontFamilies`, case-insensitive), use it. This covers Consolas/Calibri when MS Office is installed.
3. Otherwise apply the **Mac substitution map** and use the first installed candidate:

| Requested | Mac candidates in order |
|---|---|
| Calibri | Carlito, Helvetica Neue, Helvetica |
| Consolas | Menlo, SF Mono, Monaco, Courier New |
| Segoe UI, Segoe UI Semibold, system-ui | the system UI font (`NSFont.systemFont(ofSize:)`, the `.AppleSystemUIFont` family), Helvetica Neue |
| Cambria | Charter, Georgia, Times New Roman |
| Candara, Corbel, Tahoma, Microsoft Sans Serif | Verdana (if Tahoma), Helvetica Neue |
| Courier New, Arial, Times New Roman, Georgia, Verdana, Trebuchet MS, Comic Sans MS, Impact | these ship with macOS; use them directly |
| anything else | the resolved Normal font (below) |

4. If nothing matched: the Normal font = resolve("Calibri") per this table, i.e. Helvetica Neue on a stock Mac.

Bold/italic: request traits via `CTFontCreateCopyWithSymbolicTraits`. If the family lacks a bold or italic face, synthesise (stroke/obliquing) as PDFsharp does. Glyph fallback: CoreText's cascade list renders characters missing from the chosen font (CJK, emoji). PDFsharp would show missing-glyph boxes, so this is DEV-07, allowed. Optional: bundle **Carlito** (OFL, metric-compatible with Calibri) so page breaks match Windows more closely. Decide in open question Q2.

### 6.5 Mapping of Windows UI → Mac UI

| Windows | Mac |
|---|---|
| Header bar button `Export PDF...` | Toolbar item "Export PDF…" in the item detail + File ▸ Export as PDF… |
| Procedure Specifics buttons `Export checklist (PDF)` / `(Excel)` | Buttons (or an "Export Checklist" menu button) in the Specifics header row, trailing the "Open Comprehensive Checklist Builder" banner |
| Saved Lists buttons + context menu | Same three buttons in the detail header (bordered, `.controlSize(.regular)`) + list context menu "Export This List (PDF)…"; "Export All (PDF)…" also in the tab toolbar menu (DEV-10) |
| `ListStylePromptWindow` | Sheet with radio group, captions in `.secondary` |
| SaveFileDialog | NSSavePanel sheet |
| MessageBox | NSAlert sheet (informational: `.informational`; errors: `.critical`) |
| Wait cursor | ProgressView / spinner; async export |
| Process.Start | NSWorkspace.open |

Dark mode: the export controls follow system appearance, and output files are appearance-independent (PDF-104).

### 6.6 Accessibility

Mac buttons need accessibility labels identical to the captions. The PDF is untagged (as on Windows). Adding PDF structure tags is optional and not required.

### 6.7 Performance

- The link regex must stay linear (lookbehind first). Test with a 40k-char token.
- Do not re-parse the same XAML twice per export.
- Resolve `FindById` via a dictionary built once per export (`[UUID: ItemSnapshot]`). Windows does a linear scan, but results are identical because ids are unique and only the first match counts. Build the dictionary with first-wins semantics in the order Equipment → Tasks → Procedures → Vessels.

### 6.8 Genuinely impossible / different on macOS

Nothing is impossible. Differences that are unavoidable or deliberate:
1. Exact glyph metrics and hence exact line and page breaks (different font rasterisers, and possibly different fonts per §6.4). Structure, strings, order, colours and indents MUST match; page count may differ slightly.
2. The ':' separator and calendar in timestamps are fixed on the Mac (PDF-103).

### 6.9 Sanctioned deviations (DEV list)

| ID | Windows behaviour | Mac behaviour | Why |
|---|---|---|---|
| DEV-01 | Underline/strike set on an enclosing `Span`/`Underline` element (not on the Run) is not printed, because only the Run's own decorations are read | **Default: same as Windows.** Open question Q1 proposes also honouring ancestor-Span decorations up to the Paragraph (what the editor displays) | fidelity bug; needs owner decision |
| DEV-02 | In a targeted Hyperlink with mixed children [Run A, Span B, Run C], the output order is A C B, and B is not clickable | Preserve document order; make every text descendant of a targeted Hyperlink part of the link (blue/underlined, no auto-scan) | the Windows order is a bug; order must be right |
| DEV-03 | XLSX sheet name escaped-then-truncated, with forbidden chars and control chars kept, so Excel may need to repair the file | Sanitize → truncate → escape (§3.6.2); strip XML-illegal chars in all cells | avoid corrupt workbooks; identical output for valid names |
| DEV-04 | Strike via U+0336 combining overlay per glyph | Native strikethrough attribute on the same characters (not whitespace) | same look; clean copy-paste text |
| DEV-05 | Partial highlights dropped | **Optional:** draw per-run background rectangles behind the glyphs, never with the lock sentinel colour. Default = Windows behaviour unless the owner approves (Q3) | CoreText can do it; parity by default |
| DEV-06 | Missing fonts fall back to Calibri → Arial → Segoe UI | Mac substitution table §6.4 | a stock Mac lacks Windows fonts |
| DEV-07 | No glyph fallback (tofu) | CoreText cascade fallback | strictly better |
| DEV-08 | Table row taller than a page overflows the page | SHOULD split such a row across pages at line boundaries; normal rows stay atomic | the "text never clips" promise |
| DEV-09 | Item export flushes only the page's own editor | Flush all editors incl. detached item windows | include the last ≤400 ms of typing |
| DEV-10 | Export ALL disabled until a list is selected | Always available | UX; the message for zero lists stays |
| DEV-11 | Formal link target = `Uri.ToString()` (unescaped, trailing `/` on bare host) | Use the trimmed `NavigateUri` string (www. → https://). If `URL(string:)` fails, percent-encode, then retry | valid URIs in the PDF |
| DEV-12 | "Open it now?" failure reported as "Could not export the PDF" | Ignore open failures | correctness |
| DEV-13 | `\r` left in text (invisible or tofu) | CRLF/CR → LF before `\n` splitting | invisible on Windows anyway |

---

## 7. Test vectors / verification

All vectors are expressed against pure functions or against the **DOM** produced by the builders (`PdfDOM`), so they need no pixel comparison. Integration checks use PDFKit on the rendered file.

### 7.1 `LinkScanner.scan` (ScanLinks)

Output is a list of `(text, uri?)`.

| # | Input | Expected |
|---|---|---|
| L1 | `Visit https://example.com.` | `("Visit ",nil)`, `("https://example.com","https://example.com")`, `(".",nil)` |
| L2 | `www.imo.org/en` | `("www.imo.org/en","https://www.imo.org/en")` |
| L3 | `Mail ops@ship.co.uk, thanks` | `("Mail ",nil)`, `("ops@ship.co.uk","mailto:ops@ship.co.uk")`, `(", thanks",nil)` |
| L4 | `backup_www.tar.gz` | `("backup_www.tar.gz",nil)` |
| L5 | `C:\svc\www.cache\x` | whole string, nil |
| L6 | `(see http://a.b/c)` | `("(see ",nil)`, `("http://a.b/c","http://a.b/c")`, `(")",nil)` |
| L7 | `"https://x.y/z"` (with the quotes) | `("\"",nil)`, `("https://x.y/z","https://x.y/z")`, `("\"",nil)` |
| L8 | `HTTPS://EXAMPLE.COM` | `("HTTPS://EXAMPLE.COM","HTTPS://EXAMPLE.COM")` |
| L9 | `WWW.Example.com` | `("WWW.Example.com","https://WWW.Example.com")` |
| L10 | `mailto:joe@x.com` | whole string, nil |
| L11 | `a,https://x.y` | whole string, nil |
| L12 | `https://en.wikipedia.org/wiki/Foo_(bar)` | `("https://en.wikipedia.org/wiki/Foo_", same)`, `("(bar)",nil)` |
| L13 | `user@host` | nil |
| L14 | `x@y.c` | nil |
| L15 | `first.last+tag@sub.example.org!` | `("first.last+tag@sub.example.org","mailto:first.last+tag@sub.example.org")`, `("!",nil)` |
| L16 | `www..` | `("www","www")`, `("..",nil)` — quirk: trimming leaves `www`, which lacks the `www.` prefix, so no scheme is added |
| L17 | `Go to https://a.com/x?y=1;` | `("Go to ",nil)`, `("https://a.com/x?y=1","https://a.com/x?y=1")`, `(";",nil)` |
| L18 | `\thttps://a.b` | `("\t",nil)`, `("https://a.b","https://a.b")` |
| L19 | `` (empty) | `[]` |
| L20 | `https://` | nil (needs ≥1 char after the scheme) |
| L21 | `<https://a.b>` | `("<",nil)`, `("https://a.b","https://a.b")`, `(">",nil)` |
| L22 | `[www.a.io]` | `("[",nil)`, `("www.a.io","https://www.a.io")`, `("]",nil)` |
| L23 | `a@b.co and c@d.io` | `("a@b.co","mailto:a@b.co")`, `(" and ",nil)`, `("c@d.io","mailto:c@d.io")` |
| L24 | `"a"` × 40 000 + `@` (no domain) | nil; completes in < 1 s (target < 100 ms) |
| L25 | `x` + `www.a.b` × 10 000 (no spaces) | nil (never at token start); < 1 s |
| L26 | `\u{00A0}https://a.b` (NBSP before) | NBSP plain, then link |

### 7.2 `NormalizeLinkUri` / formal links

| Input NavigateUri | Result |
|---|---|
| nil, `""`, `"   "` | nil → targetless path (auto-scan the label) |
| `" www.x.com "` | `https://www.x.com` |
| `WWW.X.COM` | `https://WWW.X.COM` |
| `mailto:a@b.co` | `mailto:a@b.co` |
| `https://example.com` | Mac: `https://example.com` (Windows: `https://example.com/`, DEV-11) |

A targetless `<Hyperlink><Run>see https://a.b now</Run></Hyperlink>` gives `see ` plain, `https://a.b` linked, ` now` plain.

### 7.3 Strike predicate (DEV-04) / `ApplyStrike` (Windows reference)

| Text | Windows `ApplyStrike` | Mac: struck characters |
|---|---|---|
| `ab c` | `a\u0336b\u0336 c\u0336` | `a`, `b`, `c` (not the space) |
| `😀x` | `😀\u0336x\u0336` | `😀`, `x` |
| `\t` | `\t` | none |
| `` | `` | none |
| `a\u00A0b` | `a\u0336\u00A0b\u0336` | `a`, `b` |

### 7.4 `Shorten(s, 180)`

| Input | Output |
|---|---|
| `abc` | `abc` |
| `"x" × 200` | `"x" × 179 + "…"` (length 180) |
| `a\r\nb` | `a  b` |
| `"  x  "` | `x` |
| `"x" × 180` | unchanged |

### 7.5 `TaskWhen` and task details

| RangeStart | Deadline | TaskWhen | Working-range row |
|---|---|---|---|
| nil | nil | nil | absent; Deadline `(none)` |
| nil | 2026-07-10 | `due 2026-07-10` | absent |
| 2026-07-08 | 2026-07-10 | `2026-07-08 – 2026-07-10` | `2026-07-08 → 2026-07-10` |
| 2026-07-10T09:00 | 2026-07-10T00:00 | `due 2026-07-10` | absent (same day) |
| 2026-07-12 | 2026-07-10 | `due 2026-07-10` | absent (out of order) |
| 2026-07-08 | nil | nil | absent |

Subtask meta example: Deadline 2026-07-10, Recurrence Monthly(3), not complete, Name "Replace filter" → head inlines: bold `[ ] `, bold `Replace filter`, `  `, grey italic `(due 2026-07-10, monthly)`.

Status: IsComplete true → `Completed`; false with Status=InProgress(1) → `Open`.

### 7.6 Indentation

| Case | LeftIndent (cm) | FirstLine (cm) | RightIndent (cm) |
|---|---|---|---|
| Margin 24,0,0,0 | 0.635 | 0 | — |
| TextIndent 24 | 0.635 | 0 | — |
| Margin.Left 24, TextIndent −12 | 0.635 | −0.3175 | — |
| Margin.Left 48, TextIndent 24 | 1.905 | 0 | — |
| Margin 0,0,20,0 | — | — | 0.529 |
| Margin "Auto" | — | — | — |
| Plain paragraph under a subtask at depth 2 | 1.2 | — | — |
| Paragraph with Margin 24 under a step (0.6) | 1.235 | — | — |

Subtask indents: depth 1 → 0.6, 2 → 1.2, 3 → 1.8, 4 → 2.4, 7 → 2.4 cm. SpaceBefore: depth 1 → 6 pt, depth ≥ 2 → 3 pt.

### 7.7 Lists

| XAML | Expected paragraphs (marker text, LeftIndent, FirstLine) |
|---|---|
| `List(Disc)[a, b]` | (`• a`, 0.6, −0.4), (`• b`, 0.6, −0.4) |
| `List(Decimal)[a, b]` | (`1. a`), (`2. b`) |
| `List(LowerLatin)[a]` | `1. a` (never `a.`) |
| `List(None)[a]` | `• a` |
| `List(Decimal)[ LI(P a, List(LowerLatin)[x, y]), LI(P b) ]` | `1. a`@0.6, `1. x`@1.2, `2. y`@1.2, `2. b`@0.6 |
| `List(Decimal)[ LI(P p1, P p2), LI(P q) ]` | `1. p1`, `2. p2`, `3. q` |
| `List(Disc)[a]` inside notes of a saved-list item | `• a` @ 1.2 cm |
| `List(Disc)[LI(Table…)]` | table rendered, no marker, no indent |

Markers are Normal-style text (resolved Calibri 11 pt, black). Item runs keep their own font and size.

### 7.8 Tables

| Input | Expected |
|---|---|
| Editor 3×3 insert (no widths, border 0.6 #FF9AA0A6, row 0 FontWeight Bold) | 3 columns × 16/3 cm; every cell border 0.6 pt RGB(154,160,166); row 0 cells bold; empty cells contain one empty paragraph |
| Columns `[Width=96, (none), (none)]` | widths [2.54, 6.73, 6.73] |
| Columns `[480, 480]` | [8.0, 8.0] (scaled from 12.7 + 12.7) |
| Columns `[600, (none)]` | before scale [15.875, 1.0] → scaled ×(16/16.875) → [15.0519, 0.9481] |
| 4 true columns, `Table.Columns` = `[96, 96]` | [2.54, 2.54, 5.46, 5.46] |
| Rows `[A(RowSpan 2), B]`, `[C, D]`, Columns.Count 2 | TrueColumnCount 3 → colCount 3; A @(0,0) MergeDown 1; B @(0,1); C @(1,1); D @(1,2) |
| Rows `[A(ColumnSpan 5)]`, Columns 2 | TrueColumnCount 5 → 5 columns of 3.2 cm; A MergeRight 4 |
| Cell BorderThickness `0,0,0,0` | no borders |
| Cell BorderThickness `1,2,1,1`, no brush | width 2 pt, RGB(120,120,120) on all sides |
| Cell Background `#FFFFFF00` | shading RGB(255,255,0) |
| Cell Background `#00FFFFFF` | no shading |
| Table with 0 rows | nothing emitted |

### 7.9 Highlight

| Paragraph runs (effective backgrounds) | Shading |
|---|---|
| all `#FFFFFF00` | RGB(255,255,0) |
| one run without background | none (unless the paragraph Background is set) |
| all `#FFFFE699` (locked) | none |
| `#FFFFFF00` + `#FF00FF00` | none |
| Span Background `#FFFFFF00` wrapping all runs | RGB(255,255,0) |
| Paragraph Background `#FFFFE699` | RGB(255,230,153) (rule (a) has no exclusion; faithful) |
| empty paragraph | none; one space is emitted |

### 7.10 Font resolution

Windows reference (`ResolveFontName` on a PC with the standard fonts):

| Source | Result |
|---|---|
| nil / `""` | Calibri |
| `Calibri, Arial` | Calibri |
| `'Times New Roman'` | Times New Roman |
| `Sans Serif` | Arial |
| `Monospace` | Consolas |
| `Global User Interface` | Calibri |
| `NoSuchFont, Georgia` | Georgia |

Mac, on a stock macOS 26 without Office:

| Source | Result |
|---|---|
| `Consolas` | Menlo |
| `Calibri` | Helvetica Neue (Carlito if bundled or installed) |
| `Segoe UI` | system UI font |
| `Monospace` | Menlo (via Consolas) |
| `Arial` | Arial |
| `Times New Roman, serif` | Times New Roman |
| `Global User Interface` | Helvetica Neue (the Normal fallback) |

Font sizes: 14 px → 10.5 pt; 12 px → 9 pt; 16 px → 12 pt; `12pt` (=16 px) → 12 pt; 22 px → 16.5 pt.

### 7.11 Fallback parsing

| RichTextXaml | Result |
|---|---|
| `""` / `"   "` | nothing (no heading) |
| `<Section xmlns="…presentation"><Paragraph><Run>  </Run></Paragraph></Section>` | nothing (blank body) |
| `<Section><Paragraph>Hi &amp; bye</Paragraph></Section>` (no xmlns → parse fails) | fallback → one paragraph `Hi & bye`; with heading "Notes" → H1 `Notes` first |
| `plain text\r\nline2\r\n\r\n` | fallback → paragraphs `plain text`, `line2` |
| `enc:QUJD…` (legacy encrypted) | fallback → paragraph `enc:QUJD…` (faithful; see Q5) |
| `<b>x</b> > y` (not valid XAML → fallback) | paragraph `x    y` (four spaces) |

Derivation of the last row (`StripXamlTags`): `<b` is skipped and the `>` appends ' ' → `" "`. Then `x` → `" x"`. `</b` is skipped and its `>` appends ' ' → `" x "`. The literal space → `" x  "`. The bare `>` also appends ' ' → `" x   "`. The literal space → `" x    "`. Then `y` → `" x    y"`, and `Trim` gives `x    y`.

### 7.12 Saved-lists document structure

Given:
- groups G1 "Deck" (id g1), G2 "engine" (id g2);
- templates in collection order: T1 "Mooring" (g2, 2 items, item 1 IsJob), T2 "Ungrp A" (null, 0 items), T3 "Anchoring" (g1, 1 item), T4 "Bunkering" (g2, 1 item).

| Export | Title | Heading / paragraph sequence |
|---|---|---|
| ALL, bulleted | `All saved lists` | Title `All saved lists`; Subtitle `Saved checklists  ·  4 lists`; H1 `Deck`; H2 `Anchoring   (1 item)`; `•  …`; H1 `engine`; H2 `Mooring   (2 items)`; `•  item1  (schedulable)`; `•  item2`; H2 `Bunkering   (1 item)`; `•  …`; H1 `Ungrouped`; H2 `Ungrp A   (0 items)` |
| ALL, numbered | same | markers `1. `, `2. ` (restart per list) |
| Group (T4 selected) | `engine` | H1 `engine`; H2 `Mooring…`; H2 `Bunkering…` (collection order T1, T4) |
| This list (T3) | `Anchoring` | no H1; H2 `Anchoring   (1 item)` |
| Group (T2 selected) | `Ungrouped lists` | no H1 (first entry null); H2 `Ungrp A   (0 items)` |

Group order in ALL: `deck` < `engine` (lowercased keys); ungrouped last. Contiguity holds even if the collection interleaves groups (T1 g2, T3 g1, T4 g2 → g1 block then g2 block).

Header strings: `Saved lists: All saved lists` + TAB + timestamp. File names: `All saved lists.pdf`, `engine.pdf`, `Anchoring.pdf`, `Ungrouped lists.pdf`.

The numbered and bulleted outputs MUST differ, as the Windows harness asserted "byte-different". On the Mac, assert that the DOM marker strings differ.

### 7.13 Item PDF structure (DOM-level golden)

**Task** "Pump overhaul":
- Description "Yearly job";
- Notes: one paragraph "See https://x.io";
- Deadline 2026-07-10, RangeStart 2026-07-08, Recurrence Yearly, IsComplete false;
- one subtask "Drain" (Deadline 2026-07-09, notes "Use tray", with child "Check level" without deadline);
- RelatedIds → Equipment "Pump room" (desc "Aft"), Procedure "LOTO";
- one file `manual.pdf` (Document, `files/manual.pdf`).

Expected sequence:
1. Header: `Task: Pump overhaul` ⟶ TAB ⟶ `yyyy-MM-dd HH:mm`.
2. Title `Pump overhaul`, Subtitle `Task`, BodyItalic `Yearly job`.
3. H1 `Notes`; paragraph [`See `, link(`https://x.io` → `https://x.io`)].
4. H1 `Task Details`; KV rows `Working range`/`2026-07-08 → 2026-07-10`, `Deadline`/`2026-07-10`, `Recurrence`/`Yearly`, `Status`/`Open`.
5. H2 `Subtasks (1)`.
6. Head @0.6 cm: `[ ] `, `Drain`, `  (due 2026-07-09)`.
7. Paragraph `Use tray` @0.6 cm (+ its own indent).
8. Head @1.2 cm, SpaceBefore 3 pt: `[ ] `, `Check level` (no meta).
9. H1 `Relationships (2)`; BodyItalic `Items linked to this one, grouped by tab.`
10. H2 `Equipment/Area (1)`; Bullet [bold `Pump room`, ` — `, `Aft`].
11. H2 `Procedure (1)`; Bullet [bold `LOTO`].
12. H1 `Attached Files (1)`; table header `Name | Kind | Path / Link`; row `manual.pdf | Document | files/manual.pdf` (9 pt).

PDF info Title `Task - Pump overhaul`; default file name `Task-Pump overhaul.pdf`.

**Procedure** "LOTO": steps
- S1 done, "Isolate", Deadline 2026-07-01, EquipmentIds [Pump room], TaskIds [Pump overhaul, <dangling>];
- S2 not done, "Tag".

Expected:
- H1 `Checklist (2 steps)`.
- S1 head [green bold `1. [x] `, bold `Isolate`, grey italic `   (due 2026-07-01)`]; Muted @0.6 [italic `Equipment/Area: `, `Pump room`]; Muted @0.6 [italic `Tasks: `, `Pump overhaul`].
- S2 head [grey bold `2. [ ] `, bold `Tag`].

Checklist-only PDF rows:
- `1 | [x] | Isolate | 2026-07-01 | T: Pump overhaul⏎E/A: Pump room`
- `2 | [  ] | Tag |  | `
Header labels exactly `# | Done | Step | Due | Tasks / Equipment-Area`; Title `LOTO` 22 pt; Subtitle `Checklist`.

XLSX rows:
- `["#","Done","Step","Due","Linked Tasks","Linked Equipment/Area"]`
- `["1","Yes","Isolate","2026-07-01","Pump overhaul","Pump room"]`
- `["2","No","Tag","","",""]`
Sheet name `LOTO`.

**Equipment** "Pump room":
- Components [("Impeller","Check wear")], ProcedureIds [LOTO, <dangling>], TaskIds [].
Expected:
- H1 `Equipment/Area Details`.
- H2 `Components (1)`; table header `Component | Notes`, row `Impeller | Check wear`.
- H2 `Linked Procedures (2)` (raw count); H3 `LOTO`; Bullet `1. [x] Isolate`; Bullet `2. [ ] Tag`.
- No "Linked Tasks" heading.
- Relationships (computed from ProcedureIds, even when RelatedIds is empty): H1 `Relationships (1)`; H2 `Procedure (1)`; `LOTO`.
Header `Equipment/Area: Pump room`; info Title `Equipment - Pump room`; file name `Equipment-Pump room.pdf`.

**Vessel** "MV Aurora" with no notes, no relations, no files → Title, Subtitle `Vessel`, nothing else. A 1-page PDF with `Page 1 / 1`.

### 7.14 XLSX package checks

- Unzip → exactly 6 entries in order (PDF-090); each parses as XML; no BOM.
- `workbook.xml` sheet name for `Pump & Valve` → `Pump &amp; Valve`.
- Name `A/B: [x]*?` → Mac `A_B_ _x___` (DEV-03).
- Name 40 × `a` → 31 × `a`.
- Name = 29 × `a` followed by `&b` (31 characters). Windows escapes first (35 chars: 29 × `a` + `&amp;b`), then truncates to 31, giving 29 × `a` + `&a`: a **broken entity**, invalid XML. Mac: the raw 31 chars are within the limit, so the name stays whole and is then escaped to 29 × `a` + `&amp;b`.
- `ColRef`: 0→`A`, 25→`Z`, 26→`AA`, 51→`AZ`, 52→`BA`, 701→`ZZ`, 702→`AAA`.
- Title containing U+000B → the Mac drops it; the workbook opens in Numbers/Excel.
- Row 1 cells `s="1"`, rows ≥ 2 `s="0"`; `<cols>` widths 5/7/55/14/40/40.

### 7.15 File-name defaults

| Kind / title | Name | Default |
|---|---|---|
| Task | `Check: A/B` | `Task-Check_ A_B.pdf` |
| Equipment | `` | `Equipment-.pdf` |
| Procedure checklist | `Pre-arrival <v2>` | `checklist-Pre-arrival _v2_.pdf` / `.xlsx` |
| Saved lists | `   ` | `saved-lists.pdf` |
| Saved lists | ` Deck ` | `Deck.pdf` (trimmed) |
| Saved lists | `a*b` | `a_b.pdf` |

### 7.16 Integration checks with PDFKit (rendered file)

1. Page size = 595.28 × 841.89 pt on every page.
2. Every page's text contains `Page N / M` with the right N and M; the header text appears on every page (item and saved-list PDFs); the checklist PDF has no header text.
3. Link annotations: a note with a plain URL, an e-mail, a bare `www.` URL and a formal hyperlink yields ≥ 4 `PDFAnnotation`s of subtype Link, with URLs `https://…`, `mailto:…`, `https://www.…` and the formal target (the Windows harness check).
4. A mid-token `backup_www.tar.gz` yields **no** link annotation.
5. A 60-row checklist spans ≥ 2 pages, and the header row text `Tasks / Equipment-Area` appears on each page (HeadingFormat repeat).
6. An H1 is never the last line on a page (KeepWithNext). Test: fill a page so that a heading falls in the last 2 lines and assert it moved.
7. Strike: text extraction of struck runs contains no U+0336 (DEV-04). Visual inspection shows no strike over spaces.
8. The Title and Author info keys match PDF-033/050/080.
9. Dark mode: exporting with `NSApp.appearance = .darkAqua` produces byte-identical DOM and the same colours as light mode.
10. Performance: an item whose notes contain a 40k-character single token exports in < 1 s.

---

## 8. Open questions

- **Q1 (DEV-01):** Should underline/strike applied on an enclosing `Span`/`Underline` element (not the Run) be printed? The editor shows it; Windows PDF drops it. The default in this spec is Windows parity.
- **Q2 (§6.4):** Bundle the Carlito font (OFL) so Calibri-based layout matches Windows metrics? Otherwise Helvetica Neue.
- **Q3 (DEV-05):** Render partial (few-word) highlights on the Mac, which CoreText can do, or keep Windows parity (dropped)?
- **Q4 (§3.5.8):** Nested tables inside table cells are unsupported or uncertain on Windows (MigraDoc does not officially support tables in cells, so the export may fail or omit them). Confirm that the Mac should render them inside the cell.
- **Q5:** A legacy `enc:`-prefixed (whole-document encrypted) `RichTextXaml` not yet migrated prints as its ciphertext text through the fallback path. Should the Mac instead print nothing, or a placeholder such as "(encrypted notes)"?
- **Q6 (security/consistency):** Exporting an unlocked item prints **names and descriptions of related or linked items that are themselves password-gated**, including linked procedure step titles and linked task descriptions. Global search deliberately indexes only the Name of gated items. Should the Mac print only the Name for gated related items, consistent with search? Windows currently leaks them.
- **Q7:** The Windows header time uses the user's culture time separator and calendar. This spec fixes it to `HH:mm` Gregorian on the Mac (PDF-103). Confirm this is desired.
- **Q8:** Should the Mac add a PDF outline (bookmarks for H1/H2)? It is an optional addition, off by default for parity.
