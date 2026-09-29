# 09 — Crew subsystem (COMPAS import, crew cards, contract expiry, table view + Excel export, per-crew checklist & schedule)

> Porting spec for the Swift/SwiftUI macOS app. Written from the Windows (WPF, .NET 10) sources on branch
> `mac-port` @ `37cdab0`. Everything below is a **contract**: a Swift implementer who never saw the C# must be
> able to reproduce the behaviour, the on-screen text and the persisted data byte-compatibly (at the JSON-tree
> level) from this document alone.
>
> Feature-ID prefix: **CREW-**. Line references are `file:line` relative to `/Users/eriskay/erisdev/AA/AA/`.

## 0. Sources read

| File | Lines | Role |
|---|---|---|
| `Views/CrewPage.xaml` / `.xaml.cs` | 67 / 653 | Crew tab: roster + read-only info card, import, expiries, delete/clear, sort, table-view launcher |
| `Views/CrewEditorWindow.xaml` / `.xaml.cs` | 46 / 132 | Modal editor: Details / Checklist / Schedule tabs |
| `Views/CrewTableWindow.xaml` / `.xaml.cs` | 75 / 215 | Tabulated all-crew window: column chooser/order, date format + separator, `.xlsx` export |
| `Models/CrewMember.cs` | 152 | `CrewMember`, `CrewReviewFlag`, `CrewFlagSeverity`, `ContractStatus`, `ParseDate` |
| `Services/CrewColumns.cs` | 129 | `CrewSortMode`, `CrewDateFormat`, column catalog, cell formatting, date pattern builder |
| `Services/CrewConverter.cs` | 283 | COMPAS row → `CrewMember`, review flags, date handling via `DateResolver` |
| `Services/CrewMapping.cs` | 121 | `CrewText.Norm`, rank / nationality / port / relationship / gender tables |
| `Services/CompasReader.cs` | 88 | `.xlsx` reader (ClosedXML): sheet choice, header-row detection, cell→string |
| `Services/DateResolver.cs` | 314 | Any-format date reader + dd/mm vs mm/dd inference |
| `Services/XlsxWriter.cs` | 171 | Dependency-free single-sheet SpreadsheetML writer |
| Also read for the call graph | | `Views/ScheduleBuilderControl.xaml(.cs)` (252), `Services/ScheduleService.cs` (57), `Views/ChecklistBuilderControl.xaml(.cs)` (286), `Views/ItemPickerWindow.*`, `Views/PromptWindow.*`, `Models/Models.cs` (ChecklistStep, ScheduleEntry, ScheduleTemplate, TrashedItem, AppData, UiState, LogEntry), `Services/AppRepository.cs` (TrashCrew, RestoreTrash, UndoLastDelete, Log*, Save/MarkDirty, AllJobs, AllContainers), `Services/DataStore.cs` (JSON options, EnumerateContainers), `Services/ReminderService.cs`, `Views/FloatingTasksWindow.xaml.cs`, `Views/CalendarPage.xaml.cs`, `Views/PlannerPage.xaml.cs`, `MainWindow.xaml(.cs)`, `Services/ThemeManager.cs`, `App.xaml`, `QR_SYNC_PROTOCOL.md` §10, `PROGRESS.md` (sections listed in §8) |

Related specs (other subsystems) that this one leans on: the **checklist builder / step editor / saved lists**
spec (shared `ChecklistBuilderControl`, `ChecklistStepEditorWindow`, `ChecklistTemplate`), the **rich-text
editor** spec (the XAML stored in each checklist step's `Container.RichTextXaml`), the **data store / bundles**
spec (`data.json`, `.aaz`/`.zip`, attachments), the **trash / undo** spec, the **due-dates window / calendar /
planner / reminders** specs, and the **Flash Sync** spec.

---

## 1. Overview

The Crew subsystem keeps a **roster of seafarers imported from COMPAS** (a crewing system that exports an
`.xlsx` "report"). Each row of the report becomes a **crew card** (`CrewMember`) whose values are translated into
DNV-style controlled vocabularies (rank names, country names, UN/LOCODEs, genders, relationships, ISO dates).
Anything guessed or missing is recorded as a colour-coded **review note** — nothing is silently invented.

The **sign-off date** (COMPAS "Sign Off Date") is the contract end; it drives **contract-expiry tracking**:
buckets Expired / Critical (≤ 30 d) / Due-soon (≤ 60 d) / OK, a colour-coded line per roster row, a CONTRACT
banner on the card, a `Crew ⚠ n` badge on the tab, an on-demand "Contract expiries" report, a report after each
import, and a crew count in the tray reminder / daily digest.

Cards are **read-only** ("accidental-edit-proof"); the only way to change data is the explicit **✎ Edit...**
modal editor (Details apply on Save, discard on Cancel). The editor also hosts a **per-crew checklist** (shared
comprehensive checklist builder; dated items surface in the due-dates window, Calendar, Planner and reminders)
and a **per-crew schedule/timeline** (dated entries that can link to a Task/Procedure/Equipment, saveable as
reusable templates, exportable to `.aasched.json`, linkable to a vessel).

A **Table view** window shows all crew in a grid with a user-chosen column set and order (40-column catalog),
a date format (Y-M-D / D-M-Y / M-D-Y / D-Mon-Y) and separator, and exports exactly that table to `.xlsx`
via a dependency-free writer.

Where it sits:
- Main window tab **"Crew"** (`TabItem x:Name="CrewTab"`, 9th tab in default order → Ctrl+9; header becomes
  `Crew  ⚠ n` when contracts are expiring). Content = `CrewPage`.
- **Tools** menu: `Import COMPAS _crew (.xlsx)...` and `Check crew contract e_xpiries` (both switch to the Crew tab first).
- **Due-dates window** (📌, Ctrl+R) and **Calendar** list crew checklist items; clicking a crew row navigates to the Crew tab and selects that member.
- **Tray reminder / daily digest** include the expiring-contract count.
- **File ▸ Trash** / **Ctrl+Z** restore a deleted crew member.

---

## 2. Feature checklist

Legend: *Persist* = what is written and when. Autosave = `AppRepository.MarkDirty()` → 750 ms debounced background
save. `Save()` = synchronous immediate save. All user-visible strings are quoted **exactly** (including double
spaces, typographic characters and emoji). `{x}` = interpolation.

### A. Entry points, tab, navigation

**CREW-001 Crew tab.** Main tab titled `Crew`, hosting the Crew page. Tab name key is `CrewTab` (used by
`UiState.TabOrder` and `UiState.TabColors`; the Tab-colours dialog labels it `Crew` regardless of the badge).
Selecting the tab calls `CrewPage.Refresh()` (recomputes day counts against today — the only automatic
day-rollover refresh).

**CREW-002 Tab badge.** `MainWindow.UpdateCrewTabHeader` (`MainWindow.xaml.cs:905`): header = `Crew  ⚠ {n}`
(two spaces before ⚠) when `n = ExpiringCount > 0`, else `Crew`. `ExpiringCount` = number of crew whose
`DaysUntilSignOff(today)` is non-null and `<= 60` (overdue included). Recomputed when: the page raises `Changed`
(after import, delete, clear all, editor close), after every data (re)load/Init, and after a Trash restore of a
crew member. **Not** recomputed on day rollover by itself.

**CREW-003 Tools ▸ Import COMPAS crew.** Menu item `Import COMPAS _crew (.xlsx)...` (underscore = access key C),
tooltip `Import a COMPAS crew report and keep each member as an info card; tracks contract sign-off expiries.`
Action: select Crew tab, then CREW-030 (`ImportCompas`).

**CREW-004 Tools ▸ Check crew contract expiries.** Menu item `Check crew contract e_xpiries`, tooltip
`List crew whose contracts (sign-off dates) are due soon or overdue.` Action: select Crew tab, then
`CheckExpiries(interactive: true)` (CREW-050).

**CREW-005 Navigate to a crew member from elsewhere.** `MainWindow.NavigateToCrew(m)` selects the Crew tab, then
(deferred, Background priority) `CrewPage.SelectMember(m)`: clears the *Expiring only* toggle (unchecks it) and
the search box if set, refreshes, selects the row whose `Member.Id == m.Id`, else the first row whose `Key ==
m.Key`, and scrolls it into view. Used by the due-dates window (crew checklist rows, crew step jobs).

**CREW-006 No startup popup.** The app deliberately does **not** show the contract-expiry report at launch
(removed in commit `0568657`). Expiries surface passively (badge), on demand (CREW-004/CREW-050), after import
(CREW-039), and via reminders (CREW-092).

### B. Roster (left pane, 320 px wide, 6 px splitter, card on the right)

**CREW-010 Roster header.** Title `Crew` (bold, 15 pt, accent colour). Right-aligned buttons:
`Import COMPAS...` (accent style; tooltip `Import a COMPAS crew report (.xlsx) and keep each member as an info card.`)
and `Delete` (tooltip `Remove the selected crew member.`).

**CREW-011 Roster toolbar (wrapping row).**
- `Contract expiries` (tooltip `List crew whose contracts (sign-off dates) are due soon or overdue.`) → CREW-050 interactive.
- Toggle `Expiring only` (tooltip `Show only crew whose contract is overdue or within 60 days.`) → CREW-014.
- `Clear all` (tooltip `Remove every crew member from the roster.`) → CREW-061.
- Label `Sort:` + combo (130 px; tooltip `Order the roster by last name, first name, CID, birth date or sign-off date.`) → CREW-015.
- `▦ Table view…` (tooltip `Open all crew in a tabulated window: choose columns and order, set the date format, and export to Excel.`) → CREW-100.

**CREW-012 Search box.** Single-line text box above the list. Its `Tag` is `Search name / rank / nationality / ID...`
— on Windows this is **not rendered** (no watermark style exists); on the Mac use it as the search field
placeholder/prompt. Every keystroke (no debounce) re-runs `Refresh()`. Query = text trimmed; when non-empty a
member matches if **any** of `FullName`, `Rank` (the translated rank name, not the code), `Nationality`,
`EmployeeId` contains the query, **case-insensitive ordinal**. Vessel, ports, rank code, passport numbers etc.
are **not** searched.

**CREW-013 Roster row.** Three lines per member:
1. **Name** (bold, wraps): `FullName`, or `(unnamed)` when `FullName` is empty.
2. **Sub** (muted, 11 pt, wraps): `RankDisplay`, `Nationality`, `Vessel` — blanks skipped — joined with
   `"   ·   "` (3 spaces, U+00B7, 3 spaces); then, if the member has review flags, append `"   ⚑ {flagCount}"`
   (3 spaces, U+2691). `RankDisplay` = `Rank` when `RankCode` is blank, else `"{Rank} ({RankCode})"`.
3. **Expiry line** (bold, 11 pt, coloured, wraps) — text/colour from CREW-051. Empty text when no parseable sign-off date.

**CREW-014 Expiring-only filter.** When on, keep only members with `DaysUntilSignOff(today) <= 60` (non-null;
overdue included). Applied after search. State is per page instance, **not persisted**, survives data reloads
(Init does not reset it), cleared by CREW-005.

**CREW-015 Sort modes.** Combo items, in this order, with these labels:
`Sign-off date` (default), `Last name`, `First name`, `CID`, `Birth date`. Choosing one stores the enum name in
`UiState.CrewSortMode` (`"SignOffDate"`, `"LastName"`, `"FirstName"`, `"Cid"`, `"BirthDate"`), autosaves, and
refreshes. On Init the saved value is parsed (`Enum.TryParse`, case-sensitive; unparseable/null → `SignOffDate`)
and the combo is set without triggering a save. Exact ordering rules in §3.7 `SortCrew`. Blank/unparseable keys
always sink to the bottom. The same order is used for the Table view.

**CREW-016 Status line (bottom of roster, muted, wraps).**
- No crew at all: `No crew yet — click “Import COMPAS...” to load a crew report.` (U+2014 dash, U+201C/U+201D quotes).
- Otherwise: `{total} crew` + (if expiring > 0) `"  ·  ⚠ {expiring} contract(s) expiring ≤60d"` (U+2264).
  `total` and `expiring` count the **whole** roster, not the filtered view.
- Overwritten by the import summary after an import (CREW-038) until the next `Refresh()`.

**CREW-017 Selection behaviour.** Single selection. On every `Refresh()`: remember the selected member's `Key`
*before* rebuilding; rebuild rows; re-select the first row with that `Key`; if none (or nothing was selected),
select the first row; if the list is empty, nothing is selected and the card pane is blank. Consequence: if a
search/filter hides the selected member, the selection is lost (the next refresh selects the first row). Selecting
a row rebuilds the card (CREW-020).

**CREW-018 Empty state.** With zero crew: empty list, blank card pane, status text from CREW-016.

### C. Read-only info card (right pane, scrollable, 14 px padding)

**CREW-020 Card header.** `FullName` or `(unnamed)` — 22 pt bold, wraps — with a right-docked button
`✎ Edit...` (tooltip `Edit this crew member's details (including the sign-off / contract date).`) → CREW-070.
Below it (only if non-empty) a muted subtitle: `RankDisplay`, `Nationality`, `Vessel` joined by `"   ·   "`.

**CREW-021 CONTRACT banner.** Box with `PanelAlt` background, corner radius 4, padding 12/8, **3 px bottom border**
coloured with the expiry colour (grey when unknown). Caption `CONTRACT` (11 pt bold grey). Body (15 pt bold):
the CREW-051 expiry text in its colour, or — when `SignOffDateValue` is null (blank **or unparseable**) —
`No sign-off date on file — contract expiry can't be tracked.` in grey.

**CREW-022 Checklist summary box.** `PanelAlt` box; right-docked button `🗒 Open checklist...` (tooltip
`Build this crew member's checklist — items with a due date show in the due-dates window and Calendar.`) → opens
the editor on the Checklist tab (CREW-070 with `showChecklist`). Title `✅  Checklist` (two spaces; bold accent).
Line (grey, wraps):
- 0 items: `No items yet — open to add tasks (each can have a due date).`
- else `{total} item(s), {done} done` + (if there is a next item) `"   ·   next due {yyyy-MM-dd} — {title}"`
  where *next* = the not-done item with a non-null `Deadline` having the smallest deadline (ties: list order), and
  `{title}` = its title, or if longer than 40 UTF-16 units its first 39 units + `…` (U+2026).

**CREW-023 Detail sections.** Six bordered boxes (radius 4, padding 10). Header = `"{glyph}  {title}"` (two
spaces; bold accent). Then a two-column grid: label column 170 px (grey, wraps), value column (wraps). A blank
(null/whitespace) value shows `—` (U+2014). Sections and rows, in order:

| Section (glyph) | Rows (label → value) |
|---|---|
| `🪪  Identity` | `First name`, `Middle name`, `Last name`, `Employee ID`, `Nationality` → `Nationality` + (`RawNationality` non-blank **and** ≠ `Nationality` ? `"   (COMPAS: {RawNationality})"` : ""), `Date of birth`, `Place of birth`, `Gender` |
| `⚓  Employment & Sign-On / Sign-Off` | `Rank` → RankDisplay, `User type`, `Status` → `SignedOnOff`, `Company`, `Vessel`, `Sign-on date`, `Sign-on port` → PortDisplay(SignOnPort, SignOnPortRaw), `Sign-off date`, `Sign-off port` → PortDisplay(SignOffPort, SignOffPortRaw) |
| `🛂  Travel Documents` | `Passport no.`, `Passport issued`, `Passport expiry`, `Seaman's book no.`, `Seaman's book issued`, `Seaman's book expiry` |
| `📜  Certificates & Medical` | `CoC number`, `CoC issued` → CocIssue, `CoC expiry`, `Health cert. expiry` |
| `📏  Physical` | `Height (cm)`, `Eyes`, `Hair` |
| `👥  Next of Kin` | `First name` → NokFirstName, `Last name` → NokLastName, `Relationship` |

`PortDisplay(code, raw)`: both blank → `""` (shows `—`); raw blank or `raw == code` (ordinal) → `code`; else
`"{code}   (COMPAS: {raw})"` (3 spaces). Dates are shown **as stored** (normally `yyyy-MM-dd`; unparseable raw text as-is).

**CREW-024 Review notes box.** Only when the member has ≥ 1 flag. Title `⚑ Review notes ({count})` (bold). One
row per flag in stored order: a `●` bullet coloured by severity (Error = red `#D45050`, Warning = orange
`#E8890C`, Info = grey `#8A8A8A`) and the text `"{Field}: {Message}"`. Note: date flags already start with
`"{field}: "` inside `Message`, so they render with a doubled prefix, e.g.
`Sign-off date: Sign-off date: read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first` — faithful behaviour, keep.
Flags are never cleared by editing.

**CREW-025 Provenance footer.** If `ImportedAt` or `SourceFile` non-blank: grey 11 pt
`"Imported {ImportedAt}"` + (SourceFile non-blank ? `" from {SourceFile}"` : ""). (Blank ImportedAt with a source
yields `Imported  from X` — faithful.)

**CREW-026 Read-only guarantee.** No control on the card edits data. Only the Edit dialog (CREW-070) and the
checklist/schedule tabs inside it mutate a member. (Mac: values may be made *selectable* for copy — that does not
break the guarantee.)

### D. COMPAS import

**CREW-030 Pick file.** Open dialog title `Select COMPAS crew report`, filters `Excel workbook (*.xlsx)` (`*.xlsx`)
and `All files (*.*)`. Cancel → nothing. Wait cursor while reading.

**CREW-031 Read workbook** (§3.3). Worksheet named `report` (case-insensitive) else the first sheet. Header row =
first of rows 1..20 containing normalised cells `first name` **and** `surname`. Columns addressed by normalised
header text (order-independent). Data rows = every later row where `First name` or `Surname` is non-blank.
Failure to find the header → error `Could not find the COMPAS header row (expected 'First name' and 'Surname').`

**CREW-032 Learn the date convention from the whole file** (§3.5 `LearnDateFormat`, §3.6). Before converting any
row, every value in the 10 date columns of every row is observed: a numeric `a/b/y` with `a > 12` proves
day-first; with `b > 12` proves month-first. Result: DayFirst, MonthFirst, Conflicted (both proved) or Unknown
(neither).

**CREW-033 Ask when unsettled.** If the result is **Unknown or Conflicted**, the cursor is restored and a
Yes/No/Cancel question box (default = Cancel, Question icon) titled `Which way round are the dates?` is shown.
Body lines joined with the platform newline:
```
{file name}

{why}

Is a date like 03/04/2026 the 3rd of April, or the 4th of March?

Yes  =  day first (03/04 is 3 April)
No   =  month first (03/04 is 4 March)
Cancel  =  do not import

Getting this wrong shifts contract dates by weeks, so check the file if you are unsure.
```
`{why}` =
- Conflicted: `This file writes dates BOTH ways - some are clearly day-first and others clearly month-first, so no single reading fits all of them.` (ASCII hyphen-minus with spaces)
- Unknown: `Every date in this file could be read either way (nothing has a day above 12), so AA cannot tell which convention it uses.`

Yes → DayFirst, No → MonthFirst, Cancel/close → **import nothing** (no data change, no log). After Yes/No the
converter re-learns with the answer as fallback. **Quirks that must be preserved** (see §8 Q1/Q2):
(a) the question appears whenever *no witness* exists — including files whose dates are all ISO / typed Excel
dates / month names and files with zero data rows — not only when an ambiguous value exists;
(b) for a **Conflicted** file the answer has **no effect** (re-learning re-observes both kinds of witness and stays
Conflicted); only Cancel matters.

**CREW-034 Convert rows** (§3.5). Each row → new `CrewMember` (new random `Id`, empty Checklist/Schedule) with
translated values + review flags; `ImportedAt` = local now `yyyy-MM-dd HH:mm` (one stamp for the whole import),
`SourceFile` = file name only (no directory).

**CREW-035 Upsert by identity key.** For each converted member in file order: find the first existing roster
member with the same `Key` (ordinal, case-sensitive; `Key` = EmployeeId if non-blank else `First|Last` trimmed of
`|`). If found: the new member **takes over the existing member's `Id` and `Checklist`** and replaces it **at the
same index** (counts as *updated*). Else appended at the end (*added*). Consequences to preserve: manual edits and
old flags are overwritten by the file; two rows with the same key in one file collapse (second "updates" the
first); a member in the Trash is not matched (a restore can later create a duplicate key). **Windows does NOT
carry over `Schedule` / `ScheduleVesselId`** — see §8 Q3 (recommended Mac behaviour: carry them over too).

**CREW-036 Persist + log.** Activity log `Added` / Kind `Crew import` / Name `{added} added, {updated} updated` /
Detail `{file name}`; then synchronous `Save()`; `Refresh()`; raise `Changed` (badge).

**CREW-037 Second log entry.** After the save: log `Added` / Kind `Crew import dates` / Name = `DateSummary()`
(§3.5) / Detail `{file name}` (autosaved by debounce). Purpose: explains a wrong relief date months later.

**CREW-038 Import status line.** Roster status becomes
`Imported {memberCount} from {file name} ({added} new, {updated} updated) — {DateSummary}; {flagTotal} review note(s).`
where `flagTotal` = sum of flags over the members converted in this import.

**CREW-039 Post-import expiry report.** `CheckExpiries(interactive: false)`: shows the CREW-050 warning list only
if something is overdue or due within 60 days; silent otherwise.

**CREW-040 Import failure.** Any exception (unreadable/locked file, not an xlsx, header missing, …): error box
title `Import failed`, text `Could not import the COMPAS file:\n\n{exception message}`; nothing is changed (the
exception happens before the upsert loop in practice). Cursor restored in all paths.

### E. Contract-expiry tracking & notification

**CREW-050 Contract expiries report.** `CheckExpiries(interactive)`: due = members with `DaysUntilSignOff(today)`
non-null and `<= 60`, ordered by days ascending (stable; most overdue first). If none: when interactive, info box
title `Contract expiries`, text `No crew contracts are overdue or due within 60 days.`; when non-interactive,
nothing. Otherwise a **Warning** box titled `Contract expiries`:
```
{n} crew contract(s) overdue or due within 60 days:

  •  {FullName}  ({RankDisplay})  —  {SignOffDate}  [{when}]
  ...
```
(each line: two spaces, U+2022, two spaces …; two spaces around `({RankDisplay})`; `  —  ` with U+2014;
`FullName` raw — may be empty; `SignOffDate` as stored.) `{when}` = `OVERDUE by {-d}d` (d < 0) /
`signs off TODAY` (d == 0) / `in {d}d`. Lines joined with `\n`.

**CREW-051 Expiry text & colour** (`CrewPage.Expiry`, `CrewPage.xaml.cs:206`), with `d = DaysUntilSignOff(today)`:

| Condition | Text | Colour |
|---|---|---|
| d null (blank/unparseable) | `""` | grey `#8A8A8A` |
| d < 0 | `⚠ Contract ended {-d}d ago  ({SignOffDate})` | red `#D45050` |
| d == 0 | `⚠ Signs off today  ({SignOffDate})` | red |
| 1 ≤ d ≤ 30 | `⚠ Signs off in {d}d  ({SignOffDate})` | orange `#E8890C` |
| 31 ≤ d ≤ 60 | `Signs off in {d}d  ({SignOffDate})` | amber `#C9A227` |
| d > 60 | `Signs off in {d}d  ({SignOffDate})` | green `#2E9E5B` |

(Two spaces before the parenthesis.) Colours are fixed hex, identical in light and dark themes.

**CREW-052 Contract status enum** (`ContractStatusOn`, used by the table's `Contract Status` column): Unknown (no
date), Expired (d < 0), Critical (0 ≤ d ≤ 30), DueSoon (31..60), Ok (> 60). Rendered with its enum name:
`Unknown`, `Expired`, `Critical`, `DueSoon`, `Ok`.

**CREW-053 Warn / critical thresholds.** `WarnDays = 60` (public const), `CriticalDays = 30`. Not user-configurable.

### F. Delete, clear, trash, undo

**CREW-060 Delete (soft).** `Delete` button, requires a selection (else no-op, no message). Confirm (Yes/No,
Question) titled `Confirm`:
`Move {FullName} to the Trash?\n\nYou can restore them from File ▸ Trash, or undo with Ctrl+Z.`
Yes → `AppRepository.TrashCrew(member)` (Trash entry `ItemType "Crew"`, `KindLabel "Crew member"`, `Name` =
FullName or, if blank, LastName; payload = the member's full JSON incl. checklist & schedule; removed from roster;
log `Removed` / `Crew member` / name / `moved to Trash`; trash pruned to 200 entries / 90 days), clear selection,
`Save()`, refresh, raise `Changed`.

**CREW-061 Clear all (hard).** No-op if the roster is empty. Confirm (Yes/No, **Warning**) titled
`Confirm clear`, text `Remove ALL crew from the roster?`. Yes → log `Removed` / Kind `Crew` / Name
`all {count} member(s)` / Detail `""`; **clear the collection (NOT sent to Trash, NOT undoable)**; `Save()`;
refresh; `Changed`. Checklist attachments stay on disk (no file cleanup anywhere in AA).

**CREW-062 Restore / undo.** File ▸ Trash restore or global **Ctrl+Z** (when no text box has focus) restores the
newest Trash entry (or its whole batch). For `"Crew"`: deserialize the payload; append to the roster **only if no
member with the same `Id` exists** (Key collisions are not checked); remove the entry from the Trash; log `Added`
/ `Crew member` / name / `restored from Trash`; the main window refreshes the Crew page and badge; status bar
`Restored the last deleted item (Ctrl+Z).` (or `Restored {n} deleted items (Ctrl+Z).`).

### G. Crew editor (modal, `CrewEditorWindow`, 640 × 720, centred on owner)

**CREW-070 Open editor.** From `✎ Edit...` (Details tab) or `🗒 Open checklist...` (Checklist tab, index 1). Window
title `Edit crew member`; heading (bold 15) `Edit crew member — {FullName or (unnamed)}` (FullName at open time).
Three tabs: `Details`, `Checklist`, `Schedule`. Bottom-right: `Cancel` (90 px) and `Save` (90 px, accent,
**default button** → Enter in a single-line field saves). There is **no** cancel key binding: Esc does nothing;
closing via the title-bar X = Cancel.

**CREW-071 Details tab.** Hint (muted): `Change any field and click Save. Dates use a calendar picker. Cancel discards changes to these details.`
Scrollable form; section headings (bold accent, top margin 12) and rows (label 170 px + editor):

| Heading | Fields (label → property; D = date row) |
|---|---|
| `Identity` | `First name`→FirstName, `Middle name`→MiddleName, `Last name`→LastName, `Employee ID`→EmployeeId, `Nationality`→Nationality, D `Date of birth`→DateOfBirth, `Place of birth`→PlaceOfBirth, `Gender`→Gender |
| `Employment & Sign-On / Sign-Off` | `Rank`→Rank, `Rank code`→RankCode, `Status (On/Off)`→SignedOnOff, `Company`→Company, `Vessel`→Vessel, D `Sign-on date`→SignOnDate, `Sign-on port`→SignOnPort, D **`Sign-off date  (contract)`** (two spaces; label bold + accent)→SignOffDate, `Sign-off port`→SignOffPort |
| `Travel Documents` | `Passport no.`→PassportNumber, D `Passport issued`→PassportIssued, D `Passport expiry`→PassportExpiry, `Seaman's book no.`→SeamansBookNumber, D `Seaman's book issued`→SeamansBookIssued, D `Seaman's book expiry`→SeamansBookExpiry |
| `Certificates & Medical` | `CoC number`→CocNumber, D `CoC issued`→CocIssue, D `CoC expiry`→CocExpiry, D `Health cert. expiry`→HealthCertExpiry |
| `Physical` | `Height (cm)`→Height, `Eyes`→EyesColor, `Hair`→HairColor |
| `Next of Kin` | `First name`→NokFirstName, `Last name`→NokLastName, `Relationship`→NokRelationship |

Not editable anywhere: `Id`, `UserType`, `SignOnPortRaw`, `SignOffPortRaw`, `RawNationality`, `Flags`,
`ImportedAt`, `SourceFile`, `ScheduleVesselId` (set in the Schedule tab).

**CREW-072 Text rows.** Plain single-line text box pre-filled with the stored value. On Save: value = text
**trimmed** (null → "").

**CREW-073 Date rows.** Label | calendar date picker (fills) | free-text box (130 px, right, tooltip
`Free-text form of the date (kept in sync with the picker).`). Initial: text box = the stored string verbatim;
picker = `CrewMember.ParseDate(stored)` (may be empty). Sync is **one-way**: picking a date writes
`yyyy-MM-dd` into the text box; typing in the text box does not move the picker; clearing the picker does not clear
the text. **The text box is the source of truth on Save**: `t = text.Trim()`; if `ParseDate(t)` succeeds store
`yyyy-MM-dd` of that date (normalising e.g. `2026-3-4` → `2026-03-04`, dropping any time), else store `t`
verbatim (so an unparseable legacy value survives untouched, and an emptied box stores `""`).
⚠ Because `ParseDate` falls back to month-first parsing, pressing Save re-normalises any ambiguous legacy text
such as `03/04/2026` to `2026-03-04` (4 March) even if the user did not touch it (§8 Q4). Faithful behaviour.

**CREW-074 Save / Cancel semantics.** Save: apply every Details row (in form order) to the live member, close with
result true → caller does `Save()` (sync). Cancel/X: nothing from Details is applied → caller does
`FlushIfDirty()` (persists live Checklist/Schedule edits made meanwhile). Either way the caller sets the selection
to this member, `Refresh()` (re-sort, recompute expiry, rebuild card incl. checklist summary) and raises `Changed`
(badge). No activity-log entry for detail edits. Editing the EmployeeId/names changes the member's `Key`; the
selection follows because the caller selects by the member's new Key.

**CREW-075 Checklist tab.** Hint (muted, wraps): `This crew member's personal checklist. Give an item a due date (in its full editor) and it shows in the 📌 due-dates window and the Calendar. Checklist changes save immediately — they are not undone by Cancel.`
Hosts the shared **checklist builder** bound to `member.Checklist`, owner name = FullName (at open time), log kind
`Crew checklist item`. Features (shared control — full spec lives in the checklist spec; summary for completeness):
- Top bar `Saved lists:` + `💾 Save as list...` (tooltip `Save the current checklist to the database as a reusable saved list.`),
  `📋 Load a saved list...` (tooltip `Insert a saved list (reuse it over and over). You choose whether to append or replace.`),
  `Manage saved lists...` (tooltip `Rename or delete saved lists in the database.`).
- Left: `Bulk entry (one item per line)`, buttons `Add all` (accent), `Clear`, check box `Replace existing`
  (tooltip `Replace all existing items instead of appending.`); monospaced multi-line box. Add all: split lines,
  trim, drop blanks, (replace → clear first), append `ChecklistStep{Title}` each; log `Added` / `Crew checklist item`
  / `{n} added (bulk)` / owner.
- Right: `Current items`; buttons `+ Item`, `Insert before`, `Insert after`, `Edit...`, `↑`, `↓`, `Move to...`, `Delete`
  (tooltips: `Append a new item to the end of the list.`, `Insert a new item immediately above the (first) selected item.`,
  `Insert a new item immediately below the (last) selected item.`, `Open the full editor for the selected item — deadline, done, notes & files.`,
  `Move selected item(s) up.`, `Move selected item(s) down.`, `Move selected item(s) to a specific position.`).
  Multi-select list; each row shows the title (struck through when done) and, right-aligned, `due {yyyy-MM-dd}` when a deadline exists. Double-click = Edit.
- New item prompt `New item` / `Title:`; delete confirm `Delete {n} item(s)?` (`item`/`items`) titled `Confirm`.
- Edits autosave (`MarkDirty`); Save-as / Manage use `Save()`. Item full editor = shared `ChecklistStepEditorWindow`
  (`Edit checklist step`, 900 × 700): `Title:`, `Deadline:` picker, `Status:` `Done`, `Job:` `Schedulable job` +
  `Duration (min):`, the rich-text notes (XAML) + file bank container, `Close`. (Buckets / linked task & equipment
  ids on a `ChecklistStep` are edited elsewhere — preserve them.)

**CREW-076 Schedule tab.** Hint (muted, wraps): `A timeline for this crew member — add tasks, procedures, equipment or free notes on a date. Save/export the schedule to reuse it on any crew, and link it to a vessel. Changes save immediately.`
Hosts the schedule builder (section H). All schedule edits are live and saved immediately (not undone by Cancel).

### H. Per-crew schedule builder (`ScheduleBuilderControl`, crew-only)

**CREW-080 Vessel link bar.** `Linked vessel:` + combo (180 px, tooltip `Link this schedule to a vessel (optional).`)
listing `(none)` then every vessel in `Data.Vessels` order (display = name or `(unnamed)`). Initial selection =
vessel whose Id == `ScheduleVesselId`, else `(none)` (a dangling id shows `(none)` but stays stored until changed).
Changing it sets `ScheduleVesselId` (null for none) and `Save()`s. Buttons: `💾 Save as...`
(tooltip `Save this schedule as a reusable one that can be applied to any crew.`), `📋 Apply saved...`
(tooltip `Apply a saved schedule to this crew member (append or replace).`), `📤 Export...`
(tooltip `Export this schedule to a file you can share/import elsewhere.`), `📥 Import...`
(tooltip `Import a schedule file and apply it to this crew member.`).

**CREW-081 Add row.** `Add:` (bold) · date picker (130 px, defaults to **today** at bind time) · time box (60 px,
tooltip `Time (HH:mm), optional.`, placeholder tag `HH:mm`) · kind combo (110 px; items `Note`, `Task`,
`Procedure`, `Equipment`; default `Note`) · title box (200 px, placeholder tag `What... (or pick an item)`) ·
`Pick item...` (tooltip `Pick an existing Task / Procedure / Equipment to schedule.`; **disabled when kind = Note**) ·
`+ Add` (accent).
- Changing kind clears any pending picked item.
- Pick: items of that kind (`Data.Tasks` top-level only / `Data.Procedures` / `Data.Equipment`), sorted by name
  (case-insensitive ordinal). None → info `No {kind} items exist yet to schedule.` titled `Pick item`. Otherwise a
  single-select searchable picker titled/prompted `Pick a {kind} to schedule`; OK → title box = item name, pending
  RefId = item Id.
- Add: title trimmed; empty → info `Type what to schedule (or pick an item).` titled `Add entry`. New entry:
  `Title`, `Kind`, `RefId` = (kind == Note ? null : pending id — may be null if nothing was picked), `Date` = picker
  date `yyyy-MM-dd` or `""`, `Time` = NormTime(time box) (§3.11). Append, `Save()`, clear title box and pending id
  (date/time/kind keep their values), refresh.

**CREW-082 Timeline.** Entries grouped by date label, groups ordered by `yyyy-MM-dd` ascending with undated last;
inside a group ordered by time (`""` sorts as `00:00`). Group header (PanelAlt strip) `🗓 {label} ({count})` in
accent + muted count. Label = `(no date)` | `Today` | `Tomorrow` | `ddd, yyyy-MM-dd` (e.g. `Tue, 2026-09-29`).
Past dates are shown (not hidden). Row: done check box · time (46 px, monospaced, muted) · kind icon
(`✓` Task, `📋` Procedure, `⚙` Equipment, `•` Note) · title (strikethrough when done) · `✎` (tooltip
`Edit title/notes`) · `✕` (tooltip `Delete this entry`).
- Done toggle → autosave + refresh.
- `✎` → prompt `Edit entry` / `Title:` pre-filled; non-blank → trimmed title, `Save()`. (Notes are **not** editable despite the tooltip.)
- `✕` → removed immediately, **no confirmation, no undo**, `Save()`.
- Footer: 0 entries → `No entries yet — pick a date, choose what, and click “+ Add”.`; else
  `{n} entr{y|ies}` + (done > 0 ? ` · {done} done` : ``).
- Entries do not navigate to linked items and do **not** appear in Calendar / due-dates / Planner / reminders.

**CREW-083 Save as (template).** Empty schedule → info `Add some entries first.` titled `Save schedule`. Prompt
`Save schedule` / `Name for this reusable schedule:` default = FullName; blank/cancel → abort. Creates a
`ScheduleTemplate` (name trimmed, `VesselId` = crew's link, `VesselName` = that vessel's current name or `""`,
entries cloned: new Ids, `Done=false`), appends to `Data.ScheduleTemplates`, log `Added` / `Schedule` / name /
`{n} entr{y|ies}`, `Save()`, info `Saved '{name}'. You can apply it to any crew member.` titled `Save schedule`.

**CREW-084 Apply saved.** No templates → info `No saved schedules yet. Build one and click 'Save as...'.` titled
`Apply schedule`. Single-select picker `Apply a saved schedule`, rows =
`{name or (unnamed)}  ·  {n} entr{y|ies}` + (`VesselName` non-empty ? `  ·  {VesselName}` : ``). Then question
(Yes/No/Cancel) titled `Apply schedule`:
`Apply '{name}' ({count} entries) to {FullName}.\n\nYes = replace this crew's schedule\nNo = append\nCancel = nothing`
(always "entries"). Yes → clear then add clones; No → append clones; if the template has a `VesselId` it
overwrites the crew's `ScheduleVesselId`. `Save()`, rebind the control (date picker back to today, vessel combo
refreshed), info `Applied {n} entr{y|ies} to {FullName}.` titled `Apply schedule`. Dates are absolute (copied, not shifted).

**CREW-085 Export.** Empty → info `No schedule to export.` titled `Export`. Save dialog title `Export schedule`,
filters `AA schedule (*.aasched.json)` and `JSON (*.json)`, default name `Schedule-{Sanitize(FullName)}.aasched.json`,
default ext `.aasched.json`. Writes a template named `{FullName} schedule` (trimmed) as indented JSON (§4.8). Info
`Exported to:\n{path}` titled `Export complete`; error `Could not export:\n\n{msg}` titled `Export failed`. Export does
not add a saved template.

**CREW-086 Import.** Open dialog title `Import schedule`, filters `AA schedule (*.aasched.json;*.json)` and
`All files (*.*)`. Parse (§4.8); JSON `null` → error text `This file is not a valid schedule.`; assign fresh Ids to
the template and each entry; append to `Data.ScheduleTemplates` (kept even if the next step is cancelled); `Save()`;
then CREW-084's Yes/No/Cancel apply question. Error box `Could not import the schedule:\n\n{msg}` titled
`Import failed`. No log entry on import.

### I. Table view & Excel export (`CrewTableWindow`, 1120 × 640, centred on owner, modal)

**CREW-100 Open.** From `▦ Table view…`. Empty roster → info `No crew yet — import a COMPAS report first.` titled
`Table view`. Otherwise opens modally with **all** crew (ignores search / expiring filter) in the roster's current
sort order, snapshotted at open. Window title `Crew — table view`. On close the page calls `FlushIfDirty()`.

**CREW-101 Top bar.** `Date format:` combo (185 px) with, in order:
`2026-03-15  (Y-M-D)`, `15-03-2026  (D-M-Y)`, `03-15-2026  (M-D-Y)`, `15-Mar-2026  (D-Mon-Y)` (two spaces before
the parenthesis) → enum `Iso`, `DayMonthYear`, `MonthDayYear`, `DayMonthName`. Initial = parse of
`UiState.CrewTableDateFormat` (enum name; invalid/null → Iso). `Separator:` text box (46 px, **max 3 chars**,
tooltip `Character(s) placed between date parts, e.g. - / .`), initial = `UiState.CrewTableDateSeparator` or `-`
when null/empty. `📄 Export to Excel (.xlsx)…` (accent). Muted count text
`{crewCount} crew  ·  {k} column` + (k == 1 ? `` : `s`).

**CREW-102 Column chooser (left, 270 px).** Header `Columns — tick to show, ↑/↓ to reorder`. One check box per
catalog column (label = header). Build rules (§3.9 `BuildChoices`): if `CrewTableColumns` is empty → the 9 default
columns ticked in default order, then every other catalog column unticked in catalog order; else the saved full
order with ticks from `CrewTableShownColumns` (unknown keys dropped, duplicates ignored), then catalog columns
missing from the saved order appended unticked. Buttons: `↑` (tooltip `Move selected column up`), `↓` (tooltip
`Move selected column down`), `All`, `None`. ↑/↓ move the *selected row* one place (no-op at the ends) and keep it
selected. All/None tick/untick everything with a single rebuild.

**CREW-103 Grid (right).** One column per ticked choice in chooser order, header = column header text; one row per
crew member; cell text = `CrewColumns.Cell(col, member, format, separator)` (§3.9). Rebuilt on every change
(format, separator keystroke, tick, move, all/none). Grid is read-only; no header-click sorting; WPF lets the user
drag/resize grid headers but that is not persisted. The **Days to Sign-Off** and **Contract Status** columns use
today's date.

**CREW-104 Persistence of table choices.** Every rebuild (including the initial one at open) and window close
writes: `CrewTableColumns` = all keys in chooser order; `CrewTableShownColumns` = ticked keys in order;
`CrewTableDateFormat` = enum name; `CrewTableDateSeparator` = current separator text; then autosave. So merely
opening the window turns the "never configured" state into an explicit one. An empty separator is persisted as
`""` but reloads as `-` (IsNullOrEmpty) — faithful quirk. "None" (all unticked) is persisted and respected (not
reset to defaults).

**CREW-105 Export to Excel.** No ticked columns → info `Tick at least one column to export.` titled
`Export to Excel`. Save dialog title `Export crew table to Excel`, filter `Excel workbook (*.xlsx)`, default ext
`.xlsx`, default file name `crew-{local today yyyy-MM-dd}.xlsx`. Writes `XlsxWriter.Write(path, "Crew", headers,
rows)` with exactly the shown columns/order/formatting (§3.10, §4.10). Then question (Yes/No, Information) titled
`Export complete`: `Exported {n} crew to:\n{path}\n\nOpen it now?` → Yes opens the file with the default app.
Failure → error `Could not export the workbook:\n\n{msg}` titled `Export failed`.

**CREW-106 Close.** `Close` button (min 90 px) at bottom right; **Esc** closes (cancel button).

### J. Integration with the rest of the app

**CREW-090 Crew checklist items in the due-dates window.** Not-done crew checklist steps with a deadline appear in
OVERDUE (deadline date < today; sub `Crew checklist · {FullName or (unnamed)} · {d}d overdue (was due {ddd, dd MMM})`),
TODAY/TOMORROW/NEXT 7 DAYS (icon `🧑‍✈️`, sub `Crew checklist · {FullName or (unnamed)}`, purple accent `#9C6ADE`).
A row's done checkbox marks the step done; clicking the row → CREW-005. A schedulable crew step placed on the
Planner shows as `Crew step job · {name}`.

**CREW-091 Calendar & Planner.** Every crew checklist step with a deadline is a Calendar row titled
`{Title}   ·  👤 {FullName or (unnamed)}` (3 spaces, `·`, 2 spaces) whose completion toggles `Done`. Planner
places crew checklist steps by deadline / scheduled start; `AppRepository.AllJobs()` includes crew steps with
`IsJob`.

**CREW-092 Reminders.** Tray reminder check (every 30 min + at startup) and the once-a-day digest compute
`crew = ExpiringCount`. If nothing else is due and `crew == 0` → nothing. Balloon text =
`ReminderService` headline + (crew > 0 ? `"  ·  {crew} crew contract(s) expiring"` : ""), title `AA — due soon`;
dedup key `{yyyy-MM-dd}|{overdue}|{dueToday}|{dueWeek}|{crew}`. Crew checklist deadlines are also counted inside
`ReminderService` (overdue / today / next 7 days, not-done only).

**CREW-093 Persistence, backup, sync.** Crew live in `AppData.Crew` inside `data.json` and therefore travel with
Save, ZIP/`.aaz` bundles, shared-save, Google-Drive backups and Flash Sync (`Crew` and `ScheduleTemplates` are
Id-keyed collections → per-item `Sets`/`Deletes`; the five crew `Ui` keys are *shared* preferences → `UiChanges`).
Checklist-step containers (notes + files) are enumerated by `DataStore.EnumerateContainers` /
`AppRepository.AllContainers` so attachments are bundled and path-normalised. Crew are **not** indexed by global
search (Ctrl+F), the quick switcher, or the import change-preview diff.

---

## 3. Logic & algorithms

### 3.1 `CrewMember` (`Models/CrewMember.cs`)

- `FullName` (105): `FirstName`, `MiddleName`, `LastName` with null/whitespace-only parts skipped, joined by a single
  space. Parts are **not** trimmed (a part `" A"` keeps its space). `[JsonIgnore]`.
- `Key` (110): `EmployeeId` if not null/whitespace (returned **untrimmed**) else `"{FirstName}|{LastName}".Trim('|')`
  (only leading/trailing `|` removed: `John|` → `John`, `|Smith` → `Smith`, `|` → `""`). `[JsonIgnore]`.
- `HasFlags` = `Flags.Count > 0`; `HasErrors` = any flag with Severity Error (unused by UI).
- `SignOffDateValue` = `ParseDate(SignOffDate)`.
- `DaysUntilSignOff(today)` (123): null if no parseable sign-off; else `(int)(d.Date − today.Date).TotalDays`
  (whole calendar days; both local, date-only, no time-zone math). **Swift:** compute with a civil-date type
  (e.g. days-from-civil / Julian day number), never by dividing `TimeInterval`s (DST breaks it).
- `ContractStatusOn(today, criticalDays = 30, soonDays = 60)` (131): null → Unknown; `< 0` Expired; `<= 30` Critical;
  `<= 60` DueSoon; else Ok.
- `ParseDate(s)` (142) — **shared helper used app-wide** (also by `ScheduleEntry.When`, port-call arrivals,
  Shippalm due dates): null/whitespace → null; trim; try exact `yyyy-MM-dd`, `yyyy/MM/dd`, `yyyy.MM.dd`
  (InvariantCulture, **exactly** 4-digit year and 2-digit month/day, the stated separator); else
  `DateTime.TryParse(s, InvariantCulture, None)` (the .NET general parser — **month-first** for ambiguous numeric
  input, 2-digit years pivot at 2049, accepts month names, day names, times, ISO `T`/`Z` forms); else null. The
  result may carry a time of day (callers use `.Date`). Required Swift behaviour — see §6.3 and test vectors §7.1.

### 3.2 `CrewText.Norm` (`Services/CrewMapping.cs:11`)

`null`/`""` → `""`. Replace `’` (U+2019) with `'`; replace `\n` and `\r` with a space; collapse every run of regex
`\s+` (Unicode whitespace incl. NBSP U+00A0, tabs) to one space; `Trim()` (Unicode whitespace); `ToLowerInvariant()`.
Used for COMPAS header matching, demonym/port/relationship lookups (and by the Shippalm reader — shared helper).

### 3.3 `CompasReader.Read(path)` (`Services/CompasReader.cs:26`)

1. Open workbook (ClosedXML 0.104.2). Worksheet = first whose name equals `report` case-insensitively, else the
   first worksheet.
2. `RangeUsed()` (cells with contents; formatting-only cells ignored). None → return empty list.
   `lastRow`, `lastCol` = absolute row/column numbers of the used range's last row/column. Iteration always starts at
   row 1 / column 1 regardless of where the used range starts.
3. Header row = the first `r` in `1 ... min(lastRow, 20)` for which the **set** of `Norm(CellString(cell(r,c)))`
   over `c = 1...lastCol` contains both `first name` and `surname`. None → throw
   `InvalidDataException("Could not find the COMPAS header row (expected 'First name' and 'Surname').")`.
4. Headers: for each column `c`, `h = Norm(CellString(cell(headerRow, c)))`; keep non-empty.
5. For each row after the header up to `lastRow`: dictionary `normalisedHeader → CellString(cell)`. If two
   columns share a normalised header, **the right-most wins** (later assignment overwrites). Keep the row iff
   `Has("first name") || Has("surname")` (non-whitespace).
6. `CompasRow.Get(header)` looks up `Norm(header)` → value or `""`. `Has(header)` = `Get` is not null/whitespace.

`CellString(cell)` (70): empty cell → `""`; by ClosedXML data type:
- **Number** → if integral (`d == floor(d)`) → `((long)d)` invariant (e.g. `12345`, no `.0`); else shortest
  round-trip invariant (`180.5`, `0.30000000000000004`; exponent form `1E-07`).
- **DateTime** (a number cell whose number format is a date format; ClosedXML honours the 1904 date system) →
  `yyyy-MM-dd` (time dropped).
- **Boolean** → `TRUE` / `FALSE`.
- Anything else (Text, TimeSpan, Error) → `GetString().Trim()` (text trimmed; error cells give their error text,
  e.g. `#N/A`, which DateResolver treats as a placeholder; time-only cells give their time text).

### 3.4 `CrewMappingTables` (verbatim; all dictionaries are case-insensitive ordinal)

**Rank** (COMPAS code → DNV rank, Approximate):
```
MAST  → Master            false     ETOF  → Electrician       true
COFF  → Chief Officer     false     BOSN  → Bosun             false
2OFF  → Second Officer    false     AB    → Able Seaman       false
3OFF  → Third Officer     false     OS    → Ordinary Seaman   false
3OFT  → Third Officer     true      EFTR  → Fitter            false
CENG  → Chief Engineer    false     MTM   → Motorman          false
2ENG  → Second Engineer   false     WPR   → Wiper             false
3ENG  → Third Engineer    false     COOK  → Cook              false
4ENG  → Fourth Engineer   false     MSM   → Messman           false
CADE  → Cadet             false     CG3C2 → Other             true
                                     CGOT  → Other             true
```
**ISO-3 nationality → country:** IND India, PHL Philippines, CHN China, ROU Romania, IDN Indonesia, UKR Ukraine,
RUS Russia, MMR Myanmar, HRV Croatia, POL Poland, GBR United Kingdom, NOR Norway, GRC Greece, ITA Italy, ESP Spain,
PRT Portugal, TUR Turkey, BGD Bangladesh, LKA Sri Lanka, PAK Pakistan, VNM Vietnam, KOR South Korea, MYS Malaysia,
SGP Singapore, USA United States, NLD Netherlands, DEU Germany, FRA France. (28)

**Demonym (normalised) → country:** indian India, filipino Philippines, chinese China, romanian Romania,
indonesian Indonesia, ukrainian Ukraine, russian Russia, burmese Myanmar, croatian Croatia, polish Poland,
british United Kingdom, norwegian Norway, greek Greece, italian Italy, turkish Turkey, bangladeshi Bangladesh,
`sri lankan` Sri Lanka, pakistani Pakistan, vietnamese Vietnam, korean South Korea, malaysian Malaysia,
singaporean Singapore, american United States, dutch Netherlands, german Germany, french France,
portuguese Portugal, spanish Spain. (28)

**Port (normalised name) → UN/LOCODE, Verify:**
```
freeport (usa)        USFPO  false     singapore (sgp)       SGSIN  false
freeport              USFPO  false     cochin                INCOK  false
dunkirk               FRDKK  false     botas (ceyhan) oil t  TRCEY  false
milford haven (gbr)   GBMLF  false     marmara (tur)         TRMER  true
aliaga                TRALI  false     saros, turkey         TRGEL  true
corpus christi (usa)  USCRP  false     elba islan            USELI  true
lake charles          USLCH  false     montevideo (ury)      UYMVD  false
lake charles (usa)    USLCH  false
eemshaven             NLEEM  false
savannah (usa)        USSAV  false
```
(`botas (ceyhan) oil t` and `elba islan` are COMPAS's own truncations — keep verbatim.)

**Relationship (normalised grade → relationship):** spouse/wife/husband → Spouse; mother → Mother; father →
Father; sister → Sister; brother → Brother; son → Son; daughter → Daughter; partner → Partner; parent → Parent;
child → Child; `not specified` → Other.

**Gender:** M → Male, F → Female.

### 3.5 `CrewConverter` (`Services/CrewConverter.cs`)

Constructor (50): `_sourceFile` = file name; `_importedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm")` (local; Swift:
`en_US_POSIX`, Gregorian, `:` separator). Owns one `DateResolver`.

`DateColumns` (22) — observed for inference, with roles:
`Date of Birth` PastOnly · `Joining Date` Any · `Sign Off Date` FutureLikely · `Passport Expiry Date` FutureLikely ·
`Passport Issued Date` PastOnly · `Seaman Book Expiry Date` FutureLikely · `Seaman Book Issue Date` PastOnly ·
`Licence Expiry Date` FutureLikely · `Licence Issue Date` PastOnly · `Medical Examination Expiry` FutureLikely.
(The roles listed here are informational; `Convert` passes the role explicitly per field — same values.)

`LearnDateFormat(rows, fallback = Unknown)` (62): for every row × every DateColumns column → `Observe(row.Get(col))`;
then `Infer(fallback)`. Calling it twice re-observes (witness lists are append-only, capped at 50 each).

`DateOrder` → `_dates.Order`; `DateEvidence` → `DecisiveCount`; counters `UnreadableDates`, `OrderDependentDates`
(the latter is not displayed anywhere).

`DateSummary()` (71): `"dates read " + how + tail` where
- DayFirst: `day first (dd/mm), proved by {N} value` + (N == 1 ? `` : `s`)
- MonthFirst: `month first (mm/dd), proved by {N} value(s)` (same pluralisation)
- Conflicted: `inconsistently — this file writes dates BOTH ways, so ambiguous ones were left unread`
- Unknown: `in unambiguous formats only; nothing in the file said whether 03/04 means 3 April or 4 March`
- tail = `UnreadableDates > 0 ? ", {UnreadableDates} could not be read" : ""`.
`N` = `DecisiveCount` (0 when the order came from the user's answer; max 50).

`Convert(row)` (84) — field by field, **in this order** (flags are appended in this order):

| # | Target | Rule |
|---|---|---|
| 1 | FirstName | `Get("First name")` |
| 2 | LastName | `Get("Surname")` |
| 3 | MiddleName | `DeriveMiddle(row)` (below) |
| 4 | EmployeeId | first non-whitespace of `Get("Code")`, `Get("CMS ID Number")`, `Get("Passport Number")`, else `""` |
| 5 | Nationality | `code = Get("Nationality code").Trim().ToUpperInvariant()`; if in ISO-3 table → country; else if `Norm(Get("Nationality"))` in demonym table → country; else raw `Get("Nationality")`. `RawNationality = Get("Nationality")` |
| 6 | DateOfBirth | `FmtDate(Get("Date of Birth"), "Date of birth", PastOnly)` |
| 7 | PlaceOfBirth | `Get("Place of Birth")` |
| 8 | Gender | `g = Get("Gender").Trim().ToUpperInvariant()`; table hit → Male/Female else `""`; if `g` non-empty and no hit → **Info** flag Field `Gender`: `Gender code '{g}' not recognised.` |
| 9 | Height, EyesColor, HairColor | `Get("Height")`, `Get("Eyes Colour")`, `Get("Hair Colour")` |
| 10 | UserType, SignedOnOff | constants `Crew`, `On` (COMPAS arrival list = currently onboard) |
| 11 | Company, Vessel | `Get("Source")`, `Get("Last Vessel")` |
| 12 | RankCode, Rank | `raw = Get("Rank").Trim().ToUpperInvariant()`; `RankCode = raw`. Hit → `Rank = Dnv`, and if Approximate → **Warning** `Rank`: `Rank code '{raw}' → '{Dnv}' (approximate — verify).` Miss with non-empty raw → `Rank = "Other"` + **Warning** `Rank`: `Unknown rank code '{raw}' → 'Other' (set manually).` Empty → `Rank = "Other"` + **Error** `Rank`: `No rank in COMPAS → 'Other' (mandatory, set manually).` |
| 13 | SignOnDate | `FmtDate(Get("Joining Date"), "Sign-on date", Any)` |
| 14 | SignOnPortRaw / SignOnPort | raw = `Get("Joining Port")`; `SignOnPort = MapPort(raw, "Sign-on port")` (always called) |
| 15 | SignOffDate | `FmtDate(Get("Sign Off Date"), "Sign-off date", FutureLikely)` |
| 16 | SignOffPortRaw / SignOffPort | raw = `Get("SignOff Port")`; only if non-whitespace: `SignOffPort = MapPort(raw, "Sign-off port")` (else stays `""`) |
| 17 | (flag) | if SignOffDate is whitespace/empty → **Info** `Sign-off date`: `No sign-off date in COMPAS — contract expiry can't be tracked until it's filled in.` (not raised when the value was unreadable, because the raw text is kept) |
| 18 | PassportNumber / Expiry / Issued | `Get("Passport Number")`; `FmtDate(Get("Passport Expiry Date"), "Passport expiry", FutureLikely)`; `FmtDate(Get("Passport Issued Date"), "Passport issued", PastOnly)` |
| 19 | SeamansBook* | `Get("Seaman Book Number")`; `FmtDate(Get("Seaman Book Expiry Date"), "Seaman's book expiry", FutureLikely)`; `FmtDate(Get("Seaman Book Issue Date"), "Seaman's book issued", PastOnly)` |
| 20 | Coc* | **only if `Has("Licence Number")`**: `CocNumber = Get("Licence Number")`; `FmtDate(Get("Licence Expiry Date"), "CoC expiry", FutureLikely)`; `FmtDate(Get("Licence Issue Date"), "CoC issue", PastOnly)`. Otherwise all three stay `""` and licence dates are neither stored nor flagged (they *were* observed for inference). |
| 21 | HealthCertExpiry | `FmtDate(Get("Medical Examination Expiry"), "Health cert. expiry", FutureLikely)` |
| 22 | NoK names | `SplitName(Get("Next of Kin - Name"))` → NokFirstName, NokLastName |
| 23 | NokRelationship | `grade = Norm(Get("Next of Kin - Grade"))`; if non-empty: table hit → value else `Other`; if result `Other` and `grade != "not specified"` → **Info** `Next of kin`: `Relationship '{grade}' → 'Other'.` (`grade` is the *normalised*, lower-case text). Empty grade → stays `""`. |
| 24 | CheckMandatory | for each (value, label) in FirstName/`First name`, LastName/`Last name`, EmployeeId/`Employee ID`, Rank/`Rank`, SignOnDate/`Sign-on date`, SignOnPort/`Sign-on port`: whitespace → **Error** Field=label: `Mandatory field '{label}' is empty — missing in COMPAS, fill manually.` (Rank is never empty at this point.) |

`DeriveMiddle(row)` (210): `explicit = Get("Original middle name").Trim()`; if non-empty and ≠ `-` → return it.
Else `name = Regex("\s+" → " ")(Get("Name").Trim())`, `first` likewise from `Get("First name")`; if both non-empty and
`name` starts with `first` (ordinal ignore-case, **no word-boundary check**) → `name.Substring(first.Length)
.Trim(' ', '-').Trim()`; else `""`.

`SplitName(full)` (225): whitespace → `("", "")`; collapse `\s+` to one space after `Trim()`, split on `' '`;
1 part → `(part, "")`; else `(all but last joined by " ", last)`.

`MapPort(value, field)` (233): whitespace → `""` (no flag). `key = Norm(value)`. Hit → if Verify, **Warning**
`{field}`: `Port '{value}' → {Unlocode} (UN/LOCODE best-guess — verify).`; return Unlocode. Miss → **Warning**
`{field}`: `Port '{value}' has no UN/LOCODE mapping — left as name, set manually.`; return **the original value**
(un-normalised).

`FmtDate(value, field, role)` (254): `r = _dates.Resolve(value, role)`.
- `r.Value == nil`: if `r.Raw` non-empty → `UnreadableDates += 1` and **Error** Field=field, Message
  `"{field}: {r.Note ?? "could not read '{r.Raw}'"} — left as-is, set it by hand."`; return `r.Raw` (the cleaned,
  time-stripped text — may differ from the cell, see §7.2). Empty raw (blank / placeholder / zero-date) → return `""`, no flag.
- `r.Value != nil`: if `r.DependedOnOrder` → `OrderDependentDates += 1` and **Warning** `field`: `"{field}: {r.Note}"`.
  Return `ToStorage()` = `yyyy-MM-dd`.

### 3.6 `DateResolver` (`Services/DateResolver.cs`) — every rule

State: `_dayWitnesses`, `_monthWitnesses` (lists of cleaned strings, each capped at 50 entries), `Order`
(default Unknown). `DecisiveCount` = count of the witness list matching `Order` (DayFirst → day list, MonthFirst →
month list, else 0). `Adopt(order)` sets Order directly (unused by the import). `IsConflicted`.

Regexes (all anchored; `\d` must be treated as **ASCII 0-9** in Swift — .NET `\d` also matches other Unicode
digits but `int.Parse` would then throw; see §8 Q8):
- `Numeric   = ^(\d{1,2})([/.\-])(\d{1,2})\2(\d{2}|\d{4})$` — same separator twice (backreference).
- `YearFirst = ^(\d{4})([/.\-])(\d{1,2})\2(\d{1,2})$`
- `ShortYearFirst = ^(\d{2})([/.\-])(\d{1,2})\2(\d{1,2})$`

`MonthNameFormats` (tried in this order, .NET exact parse, InvariantCulture, month names case-insensitive,
`d`/`M` = 1–2 digits, `dd` = exactly 2, `yy` = exactly 2, `yyyy` = exactly 4, `MMM` = Jan…Dec, `MMMM` = January…December):
`d MMM yyyy`, `d MMMM yyyy`, `dd MMM yyyy`, `dd MMMM yyyy`, `MMM d yyyy`, `MMMM d yyyy`, `d-MMM-yyyy`,
`dd-MMM-yyyy`, `d-MMM-yy`, `dd-MMM-yy`, `d MMM yy`, `dd MMM yy`, `yyyy MMM d`.

`Placeholders` (case-insensitive) → "no date", no warning:
`-`, `--`, `---`, `n/a`, `na`, `n.a.`, `nil`, `none`, `tbc`, `tba`, `tbd`, `pending`, `unknown`, `?`, `x`, `#n/a`,
`#ref!`, `#value!`, `null`.

`ZeroDates` (case-insensitive) → empty with note `empty date`:
`0`, `00/00/0000`, `00-00-0000`, `1900-01-01`, `1899-12-30`, `01/01/1900`, `30/12/1899`.

`Clean(raw)` = `(raw ?? "")`, replace U+00A0 NBSP with space, `Trim()`.

**`Observe(raw)`** (113): `s = Clean(raw)`; empty → return. If `s` doesn't match `Numeric` → return (ISO, month
names, text, values with times contribute no evidence). `c1 = g1`, `c2 = g3`. If `c1 > 31 || c2 > 31 || (c1 > 12 &&
c2 > 12)` → return. If `c1 > 12` → append to day witnesses (if < 50). Else if `c2 > 12` → append to month
witnesses (if < 50). (No validity check: `31/02/2026` is a day witness.)

**`Infer(fallback = Unknown)`** (129): day && month → **Conflicted** (never majority); day → DayFirst; month →
MonthFirst; neither → `fallback`.

**`Resolve(raw, role = Any)`** (142) — returns `(Value: Date?, Raw: String, DependedOnOrder: Bool, Note: String?)`:
1. `s = Clean(raw)`; empty → `(nil, "", false, nil)`.
2. `s` ∈ Placeholders → `(nil, "", false, nil)`.
3. `s` ∈ ZeroDates → `(nil, "", false, "empty date")`.
4. `s = StripTime(s)`:
   - `t = s.firstIndex("T")` (**uppercase T only**, first occurrence); if `t >= 8` → `s = s[..<t]`.
   - `sp = s.firstIndex(" ")`; if `sp > 0` and `s[sp+1...]` contains `:` → `s = s[..<sp]` (cut at the **first** space).
   - `s = s.trimEnd("Z","z").trim()`.
5. **YearFirst** match and `TryMake(g1, g3, g4)` → `(date, s)`.
6. **Compact**: `s.count == 8`, all digits, `TryMake(s[0..<4], s[4..<6], s[6..<8])` → `(date, s)`.
7. **TryMonthName(s, role)** → `(date, s)`:
   - `t = s` with regex `\bSEPT\b` (ignore case) → `Sep`; then `(?<=\d)(st|nd|rd|th)\b` (ignore case) → `""`;
     then `,` → space; then `\s+` → one space; trim.
   - Try each MonthNameFormat in order; first success wins. If the format contains `yy` but not `yyyy`, rebuild the
     date with year `ExpandYear(parsedYear % 100, role)` (same month/day). ⚠ .NET throws if that makes an invalid
     date (29 Feb in a non-leap expanded year, e.g. `29-Feb-00` with FutureLikely → 2100) — the exception aborts the
     whole import (§8 Q9). 4-digit-year formats are **not** range-checked (`12 Mar 1850` → 1850-03-12).
   - Else, only if `t` contains 3 consecutive ASCII letters (`[A-Za-z]{3}`) → .NET general parse
     `DateTime.TryParse(t, InvariantCulture)` (no year expansion; missing year → current year; may accept day names
     if consistent). This fallback must never see bare numeric input (guaranteed by the letters test).
8. **ShortYearFirst** match and `g1 > 31` and `TryMake(ExpandYear(g1, role), g3, g4)` → `(date, s)`.
9. **Numeric**: no match → `(nil, s, false, "'{s}' is not a date AA recognises")`.
   `a = g1`, `b = g3`, `fullYear = g4.count == 4`, `year = ExpandYear(g4, role, fullYear)`.
   - `a > 12 && b <= 12` → `TryMake(year, b, a)` ? `(date, s)` : `(nil, s, false, "'{s}' is not a real date")`.
   - `b > 12 && a <= 12` → `TryMake(year, a, b)` ? `(date, s)` : not a real date.
   - `a > 12 && b > 12` → not a real date.
   - Both ≤ 12 (ambiguous):
     - Order DayFirst and `TryMake(year, b, a)` → `(date, s, true, "read as {date:d MMM yyyy} (day first); would be {alt} if month first")`,
       `alt` = `TryMake(year, a, b)` formatted `d MMM yyyy`, else `an invalid date`.
     - Order MonthFirst and `TryMake(year, a, b)` → `(date, s, true, "read as {date:d MMM yyyy} (month first); would be {alt} if day first")`,
       `alt` = `TryMake(year, b, a)`.
     - Order Conflicted → `(nil, s, true, "'{s}' left unread — this file writes dates both ways, so neither reading is safe")`.
     - Otherwise (Unknown, or the chosen reading was invalid, e.g. a 0 component) →
       `(nil, s, true, "'{s}' could be {a} {Month(b)} or {b} {Month(a)}, and nothing in the file says which")`,
       numbers without leading zeros, `Month(m)` = `Jan`…`Dec` or `?` outside 1…12.
   - `d MMM yyyy` formatting in notes uses **the Windows current culture** (English UI → `3 Apr 2026`). Mac: always
     `en_US_POSIX` → `3 Apr 2026`.

`ExpandYear(y, role, alreadyFull = false)` (290): `alreadyFull || y > 99` → `y`. `c = y <= 68 ? 2000 + y : 1900 + y`.
PastOnly and `c > today.year` → `c − 100`. FutureLikely and `c < today.year − 5` → `c + 100`. Else `c`.
(Uses **today's local year** — Swift must inject "today" for tests.)

`TryMake(y, m, d)` (303): valid iff `1900 <= y <= 2199`, `1 <= m <= 12`, `1 <= d <= daysInMonth(y, m)` (proleptic Gregorian).

`FromExcelSerial(serial, use1904 = false)` (234) — public, **not used by the import path**: NaN/∞ → nil;
`serial < 1 || serial > 73051` → nil; epoch 1899-12-30 (or 1904-01-01) + `floor(serial)` days.

`IsPlaceholder(s)` (242) — public, unused: `Clean(s)` non-empty and in Placeholders ∪ ZeroDates.

### 3.7 `CrewPage` (`Views/CrewPage.xaml.cs`)

- `Init(repo)` (49): store repo, clear selection, read sort mode from `Ui.CrewSortMode` (§CREW-015), populate the
  sort combo once, select the matching option without persisting, `Refresh()`. Called on every data (re)load.
- `SortCrew(crew, today)` (87) — stable sorts (ties keep roster order):
  - **SignOffDate** (default): key `DaysUntilSignOff(today) ?? Int.max` ascending, then `FullName` (ordinal ignore-case).
  - **LastName**: `isBlank(LastName)` (false first), then `LastName` OIC, then `FirstName` OIC.
  - **FirstName**: `isBlank(FirstName)`, then `FirstName` OIC, then `LastName` OIC.
  - **Cid**: `isBlank(EmployeeId)`, then `EmployeeId` OIC (**string order**: `100` < `20` < `3`), then `FullName` OIC.
  - **BirthDate**: `ParseDate(DateOfBirth) ?? DateTime.MaxValue` ascending (full date-time), then `FullName` OIC.
  - Any unrecognised mode value → SignOffDate branch.
  "OIC" = .NET `StringComparer.OrdinalIgnoreCase`: compare UTF-16 code units after simple invariant upper-casing
  (so `_` sorts after letters, `a` == `A`). Swift: implement exactly this (not `localizedStandardCompare`).
- `Refresh()` (147): see CREW-012…017. Row construction per CREW-013. Status per CREW-016.
- `ExpiringCount` (120): §CREW-002.
- `SelectMember(m)` (132): §CREW-005.
- `ImportCompas()` (238): §D. Sequence: dialog → wait cursor → read → converter → learn → (ask) → convert all →
  upsert → log → `Save()` → Refresh → Changed → status → log dates → `CheckExpiries(false)`; any exception →
  error box; cursor reset in `finally`.
- `AskDateOrder(situation, file)` (310): §CREW-033.
- `CheckExpiries(interactive)` (349): §CREW-050.
- `Delete_Click` (382), `ClearAll_Click` (396): §F.
- `EditCrew(m, showChecklist)` (411): §CREW-074.
- `BuildChecklistSummary` (427), `BuildCard` (461), `BuildContractBanner` (545), `BuildFlags` (569),
  `Section` (597), `PortDisplay` (631): §C.
- `Changed` event: raised after import, delete, clear all, and editor close.

### 3.8 `CrewEditorWindow` (`Views/CrewEditorWindow.xaml.cs`)

Constructor (19): heading, `BuildForm()`, bind checklist builder (`member.Checklist`, repo, `FullName`,
`"Crew checklist item"`), bind schedule builder (member, repo), select tab 1 when `showChecklist`.
`BuildForm` (30) registers an ordered list of apply-closures; `Save_Click` runs them all in registration order then
closes with `true`; `Cancel_Click` closes with `false`. `Date(...)` (94): see CREW-073.

### 3.9 `CrewColumns` + `CrewTableWindow`

Catalog `CrewColumns.All` (`Services/CrewColumns.cs:29`) — **order, keys, headers, date flag**:

| # | Key | Header | Date? | Value |
|---|---|---|---|---|
| 1 | `LastName` | `Last Name` | | LastName |
| 2 | `FirstName` | `First Name` | | FirstName |
| 3 | `MiddleName` | `Middle Name` | | MiddleName |
| 4 | `FullName` | `Full Name` | | FullName |
| 5 | `Cid` | `CID` | | EmployeeId |
| 6 | `Rank` | `Rank` | | Rank |
| 7 | `RankCode` | `Rank Code` | | RankCode |
| 8 | `Nationality` | `Nationality` | | Nationality |
| 9 | `Gender` | `Gender` | | Gender |
| 10 | `DateOfBirth` | `Date of Birth` | ✓ | DateOfBirth |
| 11 | `PlaceOfBirth` | `Place of Birth` | | PlaceOfBirth |
| 12 | `Height` | `Height` | | Height |
| 13 | `EyesColor` | `Eyes` | | EyesColor |
| 14 | `HairColor` | `Hair` | | HairColor |
| 15 | `UserType` | `User Type` | | UserType |
| 16 | `SignedOnOff` | `Signed On/Off` | | SignedOnOff |
| 17 | `Company` | `Company` | | Company |
| 18 | `Vessel` | `Vessel` | | Vessel |
| 19 | `SignOnDate` | `Sign-On Date` | ✓ | SignOnDate |
| 20 | `SignOnPort` | `Sign-On Port` | | SignOnPort (code only) |
| 21 | `SignOffDate` | `Sign-Off Date` | ✓ | SignOffDate |
| 22 | `SignOffPort` | `Sign-Off Port` | | SignOffPort (code only) |
| 23 | `DaysUntilSignOff` | `Days to Sign-Off` | | `DaysUntilSignOff(today)` as integer text (e.g. `-3`), `""` if null |
| 24 | `ContractStatus` | `Contract Status` | | `ContractStatusOn(today)` enum name |
| 25 | `PassportNumber` | `Passport No.` | | |
| 26 | `PassportExpiry` | `Passport Expiry` | ✓ | |
| 27 | `PassportIssued` | `Passport Issued` | ✓ | |
| 28 | `SeamansBookNumber` | `Seaman's Book No.` | | |
| 29 | `SeamansBookExpiry` | `Seaman's Book Expiry` | ✓ | |
| 30 | `SeamansBookIssued` | `Seaman's Book Issued` | ✓ | |
| 31 | `CocNumber` | `CoC No.` | | |
| 32 | `CocExpiry` | `CoC Expiry` | ✓ | |
| 33 | `CocIssue` | `CoC Issue` | ✓ | |
| 34 | `HealthCertExpiry` | `Health Cert Expiry` | ✓ | |
| 35 | `NokFirstName` | `Next of Kin (First)` | | |
| 36 | `NokLastName` | `Next of Kin (Last)` | | |
| 37 | `NokRelationship` | `Next of Kin (Relation)` | | |
| 38 | `ChecklistCount` | `Checklist Items` | | `Checklist.Count` |
| 39 | `ImportedAt` | `Imported At` | | ImportedAt (not a date column) |
| 40 | `SourceFile` | `Source File` | | SourceFile |

`Defaults` = `LastName, FirstName, Cid, Rank, Nationality, DateOfBirth, SignOnDate, SignOffDate, ContractStatus`.

`Resolve(keys)` (81, unused by UI): map keys to columns dropping unknown; empty → defaults.

`Cell(col, m, fmt, sep)` (93): `raw = value ?? ""`; if not a date column or `raw == ""` → `raw`;
`d = ParseDate(raw)`; nil → `raw` (unparseable shown verbatim); else format `d` with `Pattern(fmt, sep)` in
InvariantCulture.

`Pattern(fmt, sep)` (105): `s = LiteralSeparator(sep)`; DayMonthYear `dd{s}MM{s}yyyy`; MonthDayYear
`MM{s}dd{s}yyyy`; DayMonthName `dd{s}MMM{s}yyyy` (MMM = `Jan`…`Dec`); anything else (Iso) `yyyy{s}MM{s}dd`.
`LiteralSeparator` (117): null → `-`; `""` → `""`; else `'` + sep with each `'` replaced by `\'` + `'` (quoted .NET
literal so `/`, `:`, letters are verbatim). **Effective output = the separator verbatim**, except that a backslash
inside the separator escapes the next character (dropped) and a trailing backslash makes .NET throw (§8 Q10).
Swift: build the string from components (`dd`, `sep`, `MM`, `sep`, `yyyy`) — do not build a DateFormatter
pattern from user text.

`CrewTableWindow`:
- `BuildChoices` (74): CREW-102.
- `ShownColumns` (106): ticked choices mapped back to catalog columns.
- `Rebuild` (112): skipped while `_loading`; rebuild columns and rows (`Dictionary<key, text>` per crew), count
  text, `Persist()`.
- `Persist` (140): CREW-104.
- `Move(dir)` (157), `SetAll` (170), `Export_Click` (178): CREW-102/105.

### 3.10 `XlsxWriter.Write(path, sheetName, headers, rows)` (`Services/XlsxWriter.cs:16`)

- All rows = `[headers] + rows`. If `path` exists it is deleted first, then created (overwrite).
- ZIP (DEFLATE, "optimal"), entries written **in this order**: `[Content_Types].xml`, `_rels/.rels`,
  `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/styles.xml`, `xl/worksheets/sheet1.xml`. Contents are UTF-8
  **without BOM**. No `docProps/*`, no shared strings, no theme. Exact content in §4.10.
- Sheet name: `sheetName` blank → `Sheet1`; XML-escaped **then** truncated to 31 chars (can split an entity — only
  `Crew` is ever passed).
- Worksheet: `<cols><col min="1" max="{headers.count}" width="20" customWidth="1"/></cols>` only when
  `headers.count > 0`. Each row `r` (1-based) → `<row r="{r}">` and each cell `c` (0-based) of **that row's own
  length** (short/long rows tolerated) → `<c r="{ColRef(c)}{r}" t="inlineStr" s="{r == 1 ? 1 : 0}"><is><t xml:space="preserve">{Esc(text)}</t></is></c>`.
  Empty strings still produce a cell. All values are strings (dates are the formatted text; numbers such as
  `Days to Sign-Off` are text, not numeric cells).
- `ColRef(i)`: bijective base-26 from 0: `A`…`Z`, `AA`…`AZ`, `BA`…, `ZZ`, `AAA`.
- `Esc(s)`: drop every char `< 0x20` except TAB, LF, CR; escape `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;`;
  `'` is **not** escaped. (Lone surrogates / U+FFFE/FFFF are not filtered.)

### 3.11 Schedule builder + `ScheduleService`

- `Bind(crew, repo)` (`ScheduleBuilderControl.xaml.cs:31`): suppress events; date picker = today; vessel choices;
  select current link; update Pick button; refresh.
- `NormTime(s)` (141): trim; regex `^(\d{1,2}):(\d{2})$` → `"{h zero-padded to 2}:{mm}"`; otherwise `""`. **No range
  check** (`25:99` stays `25:99`).
- Timeline sort keys: `GroupSort` = `When?.ToString("yyyy-MM-dd")` else U+FFFF; `TimeSort` = `Time` or `00:00`;
  grouped by label. `When` = `CrewMember.ParseDate(Date)`.
- `ScheduleService.CloneEntry(e)` (14): new `ScheduleEntry` (new Id, `Done=false`) copying Title, Kind, RefId, Date,
  Time, EndDate, EndTime, Notes.
- `CaptureFromCrew(name, crew, data)` (26): `Name = name.Trim()`, `VesselId = crew.ScheduleVesselId`, `VesselName`
  = current vessel name or `""`, clones of all entries, new template Id, `CreatedUtc = now UTC`.
- `ApplyToCrew(t, crew, replace)` (35): replace → clear; append clones; if `t.VesselId` non-null → overwrite
  `crew.ScheduleVesselId`; return `t.Entries.Count`.
- `ExportJson(t, path)` (43): `JsonSerializer.Serialize(t, WriteIndented = true)` (default options: nulls written,
  enums as numbers, default escaping) → `File.WriteAllText` (UTF-8, no BOM).
- `ImportJson(path)` (48): default deserializer (case-sensitive property names; unknown properties ignored); `null`
  → `InvalidDataException("This file is not a valid schedule.")`; new Ids.
- `Sanitize(s)` (247): replace each Windows-invalid file-name char (`"`, `<`, `>`, `|`, NUL, U+0001–U+001F, `:`,
  `*`, `?`, `\`, `/`) with `_`; if whitespace → `crew`; else trim.

---

## 4. Data formats

### 4.1 JSON serializer settings (data.json)

`DataStore.Opts`: `WriteIndented = false`, `ReferenceHandler.IgnoreCycles`,
`DefaultIgnoreCondition = WhenWritingNull`, **no naming policy** (PascalCase property names = C# names), **no enum
converter** (enums are **integers**), default `JavaScriptEncoder` (Windows escapes every non-ASCII char and
`< > & ' + \``` as `\uXXXX` — e.g. `—` → `—`, `→` → `→`, `'` → `'`). Property-name matching on read is
**case-sensitive**; unknown properties inside a `CrewMember` are **dropped** by Windows (no extension data at that
level); unknown top-level / `Ui` keys are preserved.

Swift rules:
- Emit the exact key names below; emit enums as integers; omit keys whose value is null (`ScheduleVesselId`,
  `RefId` in data.json); never emit keys that are `[JsonIgnore]` (FullName, Key, HasFlags, HasErrors,
  SignOffDateValue, KindIcon, When, WhenDisplay, Display, JobName).
- Writing raw UTF-8 instead of `\u` escapes is valid JSON and is read correctly by Windows; key order is not
  significant to either reader (Flash Sync compares parsed trees), but keep declaration order for diff-friendliness.
- GUIDs: write **lower-case** 8-4-4-4-12 (`uuidString.lowercased()`); read case-insensitively.
- Missing keys → model defaults (listed below). A JSON `null` for a string property: Windows would store null (and
  could crash later); Swift should coerce to `""`.
- Preserve unknown keys inside a crew object if convenient (superset; harmless to Windows, which drops them).

### 4.2 `CrewMember` JSON (element of top-level `"Crew": [...]`)

Keys in serialization order, all strings unless noted, default in brackets:

```
Id                (GUID string)            [new random GUID if absent — legacy files had none]
Checklist         (array of ChecklistStep) [[]]
Schedule          (array of ScheduleEntry) [[]]
ScheduleVesselId  (GUID string, omitted when null)
EmployeeId, FirstName, MiddleName, LastName, Nationality, DateOfBirth, PlaceOfBirth,
Gender, Height, EyesColor, HairColor                                         [""]
UserType          ["Crew"]
Rank, RankCode                                                               [""]
SignedOnOff       ["On"]
Company, Vessel, SignOnDate, SignOnPort, SignOnPortRaw, SignOffDate, SignOffPort, SignOffPortRaw,
PassportNumber, PassportExpiry, PassportIssued, SeamansBookNumber, SeamansBookExpiry, SeamansBookIssued,
CocNumber, CocExpiry, CocIssue, HealthCertExpiry, NokFirstName, NokLastName, NokRelationship,
RawNationality                                                               [""]
Flags             (array of CrewReviewFlag) [[]]
ImportedAt        ["" ; import stamp "yyyy-MM-dd HH:mm" local]
SourceFile        ["" ; file name only]
```

Value formats:
- All date fields are **strings**: canonical `yyyy-MM-dd` (Gregorian) when parsed; otherwise whatever raw text was
  kept (unreadable import value or a user-typed unparseable value). **Never re-interpret stored dates on load**
  (PROGRESS: "Existing stored dates are not re-interpreted").
- `Height` etc. are raw COMPAS text (numbers rendered per §3.3).
- `SignOnPort`/`SignOffPort` are UN/LOCODEs when mapped, else the raw port name.
- `Rank` is a DNV rank name or `Other`; `RankCode` is the upper-cased trimmed COMPAS code.

Example (Mac may write raw UTF-8):
```json
{"Id":"0b6f1c9e-5d0a-4f7e-9a51-2c3d4e5f6a7b","Checklist":[],"Schedule":[],"EmployeeId":"12345",
 "FirstName":"JUAN","MiddleName":"CARLOS","LastName":"DELA CRUZ","Nationality":"Philippines",
 "DateOfBirth":"1990-05-12","PlaceOfBirth":"MANILA","Gender":"Male","Height":"175","EyesColor":"BROWN",
 "HairColor":"BLACK","UserType":"Crew","Rank":"Able Seaman","RankCode":"AB","SignedOnOff":"On",
 "Company":"ACME CREWING","Vessel":"MT EXAMPLE","SignOnDate":"2026-05-01","SignOnPort":"SGSIN",
 "SignOnPortRaw":"Singapore (SGP)","SignOffDate":"2026-11-01","SignOffPort":"","SignOffPortRaw":"",
 "PassportNumber":"P1234567","PassportExpiry":"2030-01-31","PassportIssued":"2020-02-01",
 "SeamansBookNumber":"","SeamansBookExpiry":"","SeamansBookIssued":"","CocNumber":"","CocExpiry":"",
 "CocIssue":"","HealthCertExpiry":"2027-04-30","NokFirstName":"MARIA","NokLastName":"DELA CRUZ",
 "NokRelationship":"Spouse","RawNationality":"FILIPINO",
 "Flags":[{"Severity":1,"Field":"Sign-off date","Message":"Sign-off date: read as 1 Nov 2026 (day first); would be 11 Jan 2026 if month first"}],
 "ImportedAt":"2026-09-29 10:15","SourceFile":"COMPAS.xlsx"}
```

### 4.3 `CrewReviewFlag`
`{"Severity": int, "Field": string, "Message": string}` — Severity `0` Info, `1` Warning, `2` Error. Order in the
array = creation order (§3.5). Flags are only ever written by import (replaced wholesale on re-import).

### 4.4 Nested types (owned by other specs, listed for completeness)

`ChecklistStep` (checklist spec): `Id`, `Title`, `BucketIds` (GUID[]), `Done` (bool), `Deadline` (DateTime, omitted
when null; written by .NET as `"2026-10-01T00:00:00"` — no offset, local calendar date), `IsJob` (bool),
`DurationMinutes` (int, default 60), `ScheduledStart` (DateTime, omitted when null), `TaskIds` (GUID[]),
`EquipmentIds` (GUID[]), `Container` (`{Id, RichTextXaml, Files[], SharedWithContainerIds[], IsLocked}`).

`ScheduleEntry`: `Id` (GUID), `Title` (string), `Kind` (int: 0 Note, 1 Task, 2 Procedure, 3 Equipment), `RefId`
(GUID, omitted when null in data.json), `Date` (`yyyy-MM-dd` or `""`), `Time` (`HH:mm` or `""`), `EndDate` (`""`,
never set by UI), `EndTime` (`""`, never set by UI), `Done` (bool), `Notes` (`""`, never set by UI — but preserve).

`ScheduleTemplate` (top-level `"ScheduleTemplates": [...]`): `Id`, `Name`, `VesselId` (GUID, omitted when null in
data.json), `VesselName` (string), `Entries` (ScheduleEntry[]), `CreatedUtc` (DateTime UTC, e.g.
`"2026-09-29T10:15:03.1234567Z"` — .NET writes up to 7 fractional digits with trailing zeros trimmed; read 0–7
digits and `Z`/offset/none).

### 4.5 `UiState` keys owned by this subsystem (inside top-level `"Ui"`)

| Key | Type | Default / absent | Values |
|---|---|---|---|
| `CrewSortMode` | string or omitted (null) | null → SignOffDate | `SignOffDate` `LastName` `FirstName` `Cid` `BirthDate` (enum names; .NET also accepts numeric strings `"0"`…`"4"` — Swift should too) |
| `CrewTableColumns` | string[] (always written, `[]` when unconfigured) | `[]` = never configured | full chooser order of catalog keys (§3.9) |
| `CrewTableShownColumns` | string[] | `[]` | ticked keys in display order; `[]` with non-empty order = "none ticked" |
| `CrewTableDateFormat` | string or omitted | null → `Iso` | `Iso` `DayMonthYear` `MonthDayYear` `DayMonthName` |
| `CrewTableDateSeparator` | string or omitted | null/`""` → `-` | 0–3 chars |

All five are **shared preferences** for Flash Sync (not in the per-device denylist) and must be merged key-by-key.

### 4.6 Trash payload for a crew member
`TrashedItem` in top-level `"Trash"`: `{"Id": GUID, "ItemType": "Crew", "ItemId": <member Id>, "BatchId":
"00000000-0000-0000-0000-000000000000", "Name": FullName-or-LastName, "KindLabel": "Crew member", "DeletedUtc":
DateTime UTC, "PayloadJson": "<CrewMember JSON as a string>"}`. `PayloadJson` is serialised with compact
output + `WhenWritingNull` (same shape as §4.2). A Mac restore must accept Windows payloads and vice-versa.

### 4.7 Activity-log entries written by this subsystem (`"Log"`: `{TimestampUtc, Action, Kind, Name, Detail}`)

| When | Action | Kind | Name | Detail |
|---|---|---|---|---|
| Import | `Added` | `Crew import` | `{a} added, {u} updated` | file name |
| Import (after save) | `Added` | `Crew import dates` | `DateSummary()` | file name |
| Delete | `Removed` | `Crew member` | FullName or LastName (`(unnamed)` if blank) | `moved to Trash` |
| Restore | `Added` | `Crew member` | same | `restored from Trash` |
| Clear all | `Removed` | `Crew` | `all {n} member(s)` | `""` |
| Checklist bulk add / insert / load / delete | `Added`/`Removed` | `Crew checklist item` | `{n} added (bulk)` / title / `{n} added (from saved list '{name}')` / `{n} removed` | owner FullName |
| Checklist save-as | `Added` | `Saved list` | name | `{n} item(s)` |
| Schedule save-as | `Added` | `Schedule` | name | `{n} entr{y/ies}` |

`Name` is trimmed; blank → `(unnamed)`. Log bounded to 10 000 entries (oldest removed).

### 4.8 `.aasched.json` (schedule export/import)

UTF-8, indented with 2 spaces (Windows newline CRLF; LF is fine), **nulls written** (not omitted), enums as
integers. Example:
```json
{
  "Id": "6a1f…",
  "Name": "JUAN CARLOS DELA CRUZ schedule",
  "VesselId": null,
  "VesselName": "",
  "Entries": [
    {
      "Id": "9c2e…",
      "Title": "Drill briefing",
      "Kind": 0,
      "RefId": null,
      "Date": "2026-10-01",
      "Time": "08:00",
      "EndDate": "",
      "EndTime": "",
      "Done": false,
      "Notes": ""
    }
  ],
  "CreatedUtc": "2026-09-29T10:15:03.1234567Z"
}
```
Reader: case-sensitive keys; missing keys → defaults; unknown keys ignored; top-level `null` → error; regenerate all
Ids. A file written by the Mac must round-trip into Windows (integers for `Kind`, GUID strings, ISO date-time).

### 4.9 COMPAS `.xlsx` input contract

- Sheet `report` (any case) else first sheet; header row within the first 20 rows; header text compared after
  `Norm` (case/space/newline/curly-apostrophe insensitive).
- Headers read (normalised form in brackets): `First name`, `Surname`, `Original middle name`, `Name`, `Code`,
  `CMS ID Number`, `Passport Number`, `Nationality code`, `Nationality`, `Date of Birth`, `Place of Birth`,
  `Gender`, `Height`, `Eyes Colour`, `Hair Colour`, `Source`, `Last Vessel`, `Rank`, `Joining Date`,
  `Joining Port`, `Sign Off Date`, `SignOff Port` (no space between Sign and Off), `Passport Expiry Date`,
  `Passport Issued Date`, `Seaman Book Number`, `Seaman Book Expiry Date`, `Seaman Book Issue Date`,
  `Licence Number`, `Licence Expiry Date`, `Licence Issue Date`, `Medical Examination Expiry`,
  `Next of Kin - Name`, `Next of Kin - Grade`. All other columns are ignored.
- Cells may be text, numbers, typed dates (1900 or 1904 system), booleans, formulas (cached value), errors.

### 4.10 Exported `.xlsx` — exact package parts

(Newlines inside the constant parts are the source file's newlines — LF in the repo, CRLF if checked out with
autocrlf; the worksheet mixes `AppendLine` (platform newline) and `\n`. Any newline is fine for Excel/Numbers; Swift
should emit `\n`. The constant parts have **no trailing newline**.)

`[Content_Types].xml`
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
`_rels/.rels`
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
```
`xl/workbook.xml` (`{safe}` = escaped/truncated sheet name, `Crew` here)
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="{safe}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
```
`xl/_rels/workbook.xml.rels`
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
```
`xl/styles.xml` (style 0 = Calibri 11; style 1 = bold Calibri 11 on solid `FFEEEEEE` fill)
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
`xl/worksheets/sheet1.xml` for headers `["Last Name","CID"]`, one row `["O'Neil & Co","<1>"]`:
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<cols>
<col min="1" max="2" width="20" customWidth="1"/>
</cols>
<sheetData>
<row r="1"><c r="A1" t="inlineStr" s="1"><is><t xml:space="preserve">Last Name</t></is></c><c r="B1" t="inlineStr" s="1"><is><t xml:space="preserve">CID</t></is></c></row>
<row r="2"><c r="A2" t="inlineStr" s="0"><is><t xml:space="preserve">O'Neil &amp; Co</t></is></c><c r="B2" t="inlineStr" s="0"><is><t xml:space="preserve">&lt;1&gt;</t></is></c></row>
</sheetData>
</worksheet>
```
(Trailing newline after `</worksheet>`.) The same part set/format is used by the procedure checklist exporter
(`ChecklistExporter.ExportXlsx`) — a shared Swift `XlsxWriter` should serve both.

### 4.11 Rich text (XAML)
The crew subsystem itself neither produces nor parses XAML. The only rich text reachable from it is each crew
checklist step's `Container.RichTextXaml` (WPF `TextRange.Save(DataFormats.Xaml)` FlowDocument, or an `enc:`
blob when the container is locked), edited in the shared step editor — see the rich-text editor spec for the XAML
shapes. The crew code copies containers only via saved-list templates (`CloneContainer`).

### 4.12 Cross-version compatibility rules
1. Stored date strings are opaque; interpret them only through `ParseDate` semantics identical on both platforms.
2. Enum integers must match: `CrewFlagSeverity` 0/1/2, `ScheduleKind` 0–3. `ContractStatus`, `CrewSortMode`,
   `CrewDateFormat`, `DateOrder`, `DateRole` are never persisted as integers (sort/format are persisted as names).
3. A member written by an older Windows build may lack `Id`, `Checklist`, `Schedule`, `ScheduleVesselId` — default them.
4. Upsert identity (`Key`) and restore identity (`Id`) semantics must match so re-imports on either platform keep
   the same member Ids (Flash Sync keys crew by `Id`).
5. Flag `Message` strings are data (displayed verbatim on the other platform) — generate the exact English texts
   of §3.5/§3.6 (with `d MMM yyyy` in English).

---

## 5. Dependencies

### 5.1 Calls out of the subsystem
- `AppRepository`: `Data.Crew`, `Data.Ui.*`, `Data.Vessels/Tasks/Procedures/Equipment` (schedule pickers),
  `Data.ScheduleTemplates`, `Data.ChecklistTemplates`, `Save()`, `MarkDirty()`, `FlushIfDirty()`, `LogAdded`,
  `LogRemoved`, `TrashCrew`.
- `CompasReader.Read` → ClosedXML; `CrewConverter` → `DateResolver`, `CrewMappingTables`, `CrewText`.
- `CrewColumns.Cell/Pattern`, `XlsxWriter.Write`.
- Shared UI: `ChecklistBuilderControl` (+ `ChecklistStepEditorWindow`, `ChecklistTemplateService`),
  `ScheduleBuilderControl` (+ `ScheduleService`), `ItemPickerWindow` (searchable picker; prompt text, OK/Cancel),
  `PromptWindow` (title, prompt, initial text, OK/Cancel).

### 5.2 Calls into the subsystem
- `MainWindow`: `CrewPg.Init`, `Refresh`, `ImportCompas`, `CheckExpiries(true)`, `ExpiringCount` (badge, tray
  reminder, digest), `SelectMember` (navigation), `Changed` event; `RefreshAfterRestore("Crew")`.
- `FloatingTasksWindow` (crew checklist steps; navigation callback), `CalendarPage` (`ScheduleRow.ForCrewStep`),
  `PlannerPage` (`AllSchedulable` includes crew steps), `ReminderService` (crew step deadlines),
  `AppRepository.AllJobs` / `AllContainers`, `DataStore.EnumerateContainers`, `BatchDone` / `BatchDeadline`
  (operate on crew `ChecklistStep`s), `AppRepository.RestoreTrash` / `UndoLastDelete`.
- Shared helpers consumed elsewhere: `CrewMember.ParseDate` (ports, Shippalm jobs, schedule entries),
  `CrewText.Norm` (Shippalm reader).

### 5.3 Windows-only APIs used
| API | Where | Purpose |
|---|---|---|
| `Microsoft.Win32.OpenFileDialog` / `SaveFileDialog` | import, table export, schedule import/export | file pickers |
| `System.Windows.MessageBox` (OK / YesNo / YesNoCancel, icons, default result) | everywhere | confirmations, errors, the date-order question |
| `Mouse.OverrideCursor = Wait` | import | busy cursor |
| `Process.Start(UseShellExecute)` | table export | open the `.xlsx` in the default app |
| ClosedXML (.NET library) | `CompasReader` | xlsx reading, date-format detection |
| `System.IO.Compression.ZipArchive` | `XlsxWriter` | zip/DEFLATE |
| WPF `DatePicker`, `ListView/GridView`, `ListCollectionView` grouping | editor, table, schedule | UI |
| WinForms `NotifyIcon.ShowBalloonTip` | MainWindow reminders | crew count in tray balloon |
| `DispatcherTimer` (750 ms autosave, 30 min reminders) | repo / main window | timing |
| `DateTime.TryParse(InvariantCulture)` general parser | `ParseDate`, `TryMonthName` fallback | no 1:1 Swift equivalent (§6.3) |
| Current-culture `ToString("yyyy-MM-dd")`/`"d MMM yyyy"`/`"ddd, yyyy-MM-dd"` | several | culture-dependent on Windows; Mac uses en_US_POSIX Gregorian |

---

## 6. macOS adaptation notes (Swift 6.4, SwiftUI, macOS 26+)

### 6.1 Architecture
- Put all pure logic in a testable module (e.g. `CrewKit`): `CrewMember` (Codable, `@Observable` wrapper in the
  app layer), `CrewReviewFlag`, `DateResolver`, `CrewConverter`, `CrewMappingTables`, `CrewText.norm`,
  `CompasReader`, `CrewColumns`, `XlsxWriter`, `ScheduleService`, `CivilDate`. Inject a `today: CivilDate` (and a
  `now` clock) everywhere the C# uses `DateTime.Today/Now` — needed for `ExpandYear`, expiry math and tests.
- Keep dates as **strings** in the model (as Windows does) with computed parsed values; introduce
  `struct CivilDate: Comparable { year, month, day }` with `daysBetween` via days-from-civil to avoid DST/time-zone bugs.
- Swift 6 strict concurrency: run `CompasReader` + conversion in a detached `Task` (off the main actor; Windows
  blocks the UI thread) and hop back to `@MainActor` for the date-order question and the upsert. Keep the
  two-phase flow (learn → ask → convert) exactly.

### 6.2 Reading COMPAS `.xlsx` without ClosedXML
- Unzip with a small zip reader (ZIPFoundation via SPM, or a custom central-directory reader + Apple
  `Compression` framework `COMPRESSION_ZLIB`, which is raw DEFLATE) and parse parts with `XMLParser` (SAX; fast).
- Resolve the sheet via `xl/workbook.xml` (`<sheet name r:id>`) + `xl/_rels/workbook.xml.rels`; pick `report`
  case-insensitively else the first `<sheet>`.
- Read `xl/sharedStrings.xml` (concatenate all `<t>` of an `<si>`, including rich-text runs `<r><t>`, excluding
  phonetic `<rPh>`), `xl/styles.xml` (`cellXfs` → `numFmtId`; custom `numFmts`), `workbookPr date1904`.
- Cell typing to mimic ClosedXML → `CellString`: `t="s"`/`inlineStr`/`str` → text (trim); `t="b"` → `TRUE`/`FALSE`;
  `t="e"` → error text (e.g. `#N/A`); `t="d"` (ISO) → date → `yyyy-MM-dd`; number → **date if the cell's number
  format is a date format** (built-in ids 14–22, 27–36, 45–47, 50–58; or a custom code that, after removing quoted
  literals, `\x` escapes and `[...]` sections, contains `d`, `y`, or an `m` that is a month, i.e. not adjacent to
  `h`/`s`) → serial → date (1900 system epoch 1899-12-30 incl. the fictitious 1900-02-29 handling as Excel does;
  1904 system epoch 1904-01-01) → `yyyy-MM-dd`; time-only formats → time text `HH:mm:ss`; else integral →
  `Int64` text, non-integral → shortest round-trip text (use `.NET`-style exponent `1E-07` if you want exactness;
  COMPAS never produces it). Formula cells: use the cached `<v>`; none → `""`.
- Used range = min/max row/col over cells that have a value (ignore style-only cells); honour missing `r`
  attributes (sequential). Merged cells: take the top-left value only (ClosedXML semantics).

### 6.3 `ParseDate` without .NET's general parser
Implement: (1) exact `yyyy-MM-dd` / `yyyy/MM/dd` / `yyyy.MM.dd` (4-2-2 digits); (2) a deterministic fallback that
reproduces the .NET InvariantCulture results for the realistic shapes — `yyyy[-/.]M[-/.]d` (1–2 digit parts, also
mixed separators), `M[-/.]d[-/.]yyyy` and `M/d/yy` (**month-first**, 2-digit pivot: `yy <= 49` → 20yy else 19yy),
month-name forms (`d MMM yyyy`, `d MMMM yyyy`, `MMM d, yyyy`, `MMMM d yyyy`, `yyyy MMM d`, `d-MMM-yy`, with
optional leading day name that must match the date), ISO date-times (`…T…`, space + `HH:mm[:ss]`; a trailing `Z`
or offset converts to **local** time exactly as .NET does, which can move the day), `M/d` without year (current
year). Anything else → nil. Document any residual divergence in tests. Month-first is essential: stored legacy text
like `03/04/2026` must yield **4 March** on both platforms (§8 Q4/Q5).

### 6.4 UI mapping (keep every capability, make it feel native)
- **Navigation:** Crew is a sidebar destination in the main `NavigationSplitView` (Label "Crew", SF Symbol
  `person.2.badge.gearshape` or `person.3`), with `.badge(expiringCount)` (tinted warning) replacing
  `Crew  ⚠ n`; keep the string `Crew  ⚠ n` for accessibility/tooltips. Recompute the badge also on
  `NSCalendarDayChanged` (harmless improvement over Windows).
- **Roster + card:** content column = `List(selection:)` with the three-line rows (colours as §CREW-051);
  detail column = scrollable card. Search via `.searchable(text:placement: .sidebar, prompt: "Search name / rank / nationality / ID...")`.
  Toolbar (`.toolbar` on the content column): **Import COMPAS…** (`square.and.arrow.down`, ⇧⌘I), **Contract Expiries**
  (`exclamationmark.triangle`), **Expiring Only** toggle (`line.3.horizontal.decrease.circle`), **Sort** `Picker`
  menu (`arrow.up.arrow.down`) with the five labels, **Table View…** (`tablecells`, ⌥⌘T), **Delete** (`trash`,
  ⌘⌫ and the Delete key on the list), **Clear All…** in an overflow/`Menu` (destructive role). Status line as a
  bottom bar (`.safeAreaInset(edge: .bottom)`), muted.
- **Row context menu** (new, maps to existing actions): Edit…, Open Checklist…, Move to Trash… (same confirmation).
- **Card:** `ScrollView` of `GroupBox` sections; `Grid` with a 170 pt label column; section titles keep the exact
  English titles, glyphs may become SF Symbols (`person.text.rectangle`, `ferry`, `book.closed`/`doc.text`,
  `cross.case`, `ruler`, `person.2`); CONTRACT banner as a rounded `.background(.quaternary)` box with a 3 pt coloured
  bottom rule; review notes with coloured `circle.fill` bullets. `.textSelection(.enabled)` on values.
- **Editor:** a sheet (or a dedicated `Window` scene keyed by member Id) with a `TabView` (Details / Checklist /
  Schedule). Buttons `Cancel` (`.keyboardShortcut(.cancelAction)` → Esc; Windows had no Esc — acceptable superset)
  and `Save` (`.keyboardShortcut(.defaultAction)`). Details edits go into a draft copy; apply on Save only.
  Checklist/Schedule tabs mutate the live model and save immediately (as Windows). Date rows: SwiftUI `DatePicker`
  (`.field` + calendar popover) **plus** the 130 pt raw text field with identical one-way sync and Save rules.
- **Dialogs:** `NSAlert`/`.alert`/`.confirmationDialog` with the exact texts. For the date-order question use three
  explicit buttons — `Day First (03/04 = 3 April)`, `Month First (03/04 = 4 March)`, `Cancel Import` — while keeping
  the full explanatory body (the Yes/No/Cancel legend lines may be dropped since the buttons are self-describing;
  mapping must stay identical). Replace "Ctrl+Z" with "⌘Z" in the delete confirmation text.
- **Busy state:** instead of a wait cursor, show a progress indicator in the toolbar / an inline `ProgressView`
  during import; disable Import while running.
- **Table view:** a separate `Window` scene ("Crew — Table View") or sheet. Left: an `.inspector`/sidebar column
  chooser — `List` with checkboxes, drag-to-reorder (`.onMove`) **and** the ↑/↓/All/None buttons. Right: a SwiftUI
  `Table` using `TableColumnForEach` for dynamic columns (or an `NSTableView` via `NSViewRepresentable` for
  `allowsColumnReordering`; if header-drag reorder is offered, feed it back into the persisted order — an
  improvement Windows lacks). Top: format `Picker`, separator `TextField` limited to 3 chars, **Export to Excel…**
  button. Also add the table header context menu for show/hide columns, bound to the same state.
- **Export:** `NSSavePanel` (`allowedContentTypes: [.init(filenameExtension: "xlsx")!]`, default name
  `crew-yyyy-MM-dd.xlsx`); after writing, alert "Export complete" with **Open**, **Show in Finder**
  (`NSWorkspace.activateFileViewerSelecting`), **Done** (superset of Yes/No). Open = `NSWorkspace.shared.open(url)`
  (Numbers/Excel/whatever owns `.xlsx`).
- **Import panel:** `NSOpenPanel` (`.fileImporter`) with `allowedContentTypes` = xlsx UTType
  (`org.openxmlformats.spreadsheetml.sheet`) and an "All files" option (`allowsOtherFileTypes`); security-scoped URL
  access if sandboxed.
- **Menus / Commands:** Tools menu items "Import COMPAS Crew (.xlsx)…" and "Check Crew Contract Expiries" via
  `CommandMenu("Tools")`; both select the Crew destination first.
- **Notifications:** tray balloon → `UNUserNotificationCenter` notification (title `AA — due soon`, body including
  `  ·  {n} crew contract(s) expiring`), same dedup key; clicking opens the due-dates window. (Owned by the
  reminders spec; crew contributes `expiringCount`.)
- **Dark mode:** Windows theme is monochrome (accent = black in light, white in dark; Panel/PanelAlt white or dark
  greys). Use semantic colours (`.primary` for "accent" headings, `.secondary` for muted, `.separator` borders,
  `Color(nsColor: .controlBackgroundColor)` panels). Keep the five contract/severity hex colours identical in both
  appearances (optionally raise contrast slightly in dark mode while keeping hue).
- **Undo:** crew delete participates in the app-level "undo last delete" (⌘Z when no text field is focused) from
  the Trash spec; Clear All stays non-undoable (faithful) — consider an extra warning line on the Mac confirmation.

### 6.5 Genuinely impossible / non-identical on macOS
- **.NET `DateTime.TryParse` bit-exactness** for arbitrary strings — approximate per §6.3 with a documented subset.
- **Culture-dependent Windows output** (month names in flag notes, `ddd` day names, non-Gregorian calendars on
  e.g. Thai Windows): Mac always uses English/Gregorian; Windows English is the reference.
- **.NET exceptions as messages** (e.g. the 29-Feb expansion crash, locked-file IOException texts): Mac shows its own
  error text; see §8 Q9 for the recommended non-crashing behaviour.
- Nothing else in this subsystem is Windows-exclusive.

---

## 7. Test vectors / verification

Unless noted, **today = 2026-09-29** (so `today.year − 5 = 2021`).

### 7.1 `CrewMember.ParseDate`
| Input | Expected |
|---|---|
| `nil`, `""`, `"   "` | nil |
| `2026-03-15` / `2026/03/15` / `2026.03.15` | 2026-03-15 (exact path) |
| ` 2026-03-15 ` | 2026-03-15 (trimmed) |
| `2026-3-5` | 2026-03-05 (general parser) |
| `03/04/2026`, `03-04-2026`, `03.04.2026` | **2026-03-04** (month-first) — verify on Windows |
| `3/4/26` | 2026-03-04; `3/4/50` → 1950-03-04 (pivot 2049) — verify |
| `15/07/2026` | nil |
| `15 Jul 2026`, `Jul 15, 2026`, `July 15 2026` | 2026-07-15 |
| `2026-03-15T10:30:00` | 2026-03-15 (time kept, `.Date` used) |
| `2026-02-30` | nil |
| `garbage`, `12` | nil — verify |

### 7.2 `DateResolver.Resolve` (role Any unless stated; Order Unknown unless stated)
| Input | Value | Raw | Dep | Note |
|---|---|---|---|---|
| `""`, `" "`, `" "` | nil | `""` | f | nil |
| `N/A`, `tbc`, `#N/A`, `-`, `Null` | nil | `""` | f | nil |
| `0`, `00/00/0000`, `1899-12-30`, `30/12/1899` | nil | `""` | f | `empty date` |
| `1900-01-01 00:00` | **1900-01-01** (zero-date check happens before time strip) | `1900-01-01` | f | nil |
| `2026-03-04`, `2026/3/4`, `2026.03.04` | 2026-03-04 | same | f | nil |
| `2026-03-04T10:30:00Z` | 2026-03-04 | `2026-03-04` | f | nil |
| `2026-03-04 10:30` | 2026-03-04 | `2026-03-04` | f | nil |
| `2026-03/04` | nil | same | f | `'2026-03/04' is not a date AA recognises` |
| `2026-02-29` | nil | same | f | `'2026-02-29' is not a date AA recognises` |
| `2024-02-29` | 2024-02-29 | | f | |
| `1899-12-31` | nil | | f | `… is not a date AA recognises` |
| `20260304` | 2026-03-04 | | f | |
| `04032026` | nil | | f | `'04032026' is not a date AA recognises` |
| `12 Mar 2026`, `12 MARCH 2026`, `12 march 2026` | 2026-03-12 | | f | |
| `March 4, 2026`, `Mar 4 2026` | 2026-03-04 | | f | |
| `4th March 2026`, `1ST Mar 2026` | 2026-03-04 / 2026-03-01 | | f | |
| `12-SEPT-26` | 2026-09-12 | | f | |
| `2026 Mar 4` | 2026-03-04 | | f | |
| `12 AUG 98` PastOnly / FutureLikely | 1998-08-12 / 2098-08-12 | | f | |
| `12-MAR-20` FutureLikely | **2120-03-12** | | f | |
| `12 Mar 1850` | 1850-03-12 (no range check on month-name path) | | f | |
| `12 AUGUST 2026` | nil (uppercase `T` at index 8 cuts to `12 AUGUS`) | `12 AUGUS` | f | `'12 AUGUS' is not a date AA recognises` — verify |
| `DECEMBER 1ST 2026` | nil (`T` at index 11) | `DECEMBER 1S` | f | `… is not a date AA recognises` — verify |
| `12 Mar 2026 10:00` | nil (cut at first space) | `12` | f | `'12' is not a date AA recognises` |
| `98-03-04` Any / PastOnly / FutureLikely | 1998-03-04 / 1998-03-04 / 2098-03-04 | | f | |
| `45/12/31` Any / PastOnly | 2045-12-31 / 1945-12-31 | | f | |
| `26-03-04` | **2004-03-26** (first ≤ 31 → Numeric, a=26 day-first) | | f | |
| `15/07/2026`, `15.07.26`, `07/15/2026` | 2026-07-15 | | f | |
| `15-07-98` PastOnly | 1998-07-15 | | f | |
| `31/02/2026`, `13/13/2026`, `02/30/2026`, `31/04/2026` | nil | same | f | `'…' is not a real date` |
| `3/4/2026` DayFirst | 2026-04-03 | | **t** | `read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first` |
| `3/4/2026` MonthFirst | 2026-03-04 | | t | `read as 4 Mar 2026 (month first); would be 3 Apr 2026 if day first` |
| `3/4/2026` Conflicted | nil | `3/4/2026` | t | `'3/4/2026' left unread — this file writes dates both ways, so neither reading is safe` |
| `03/04/2026` Unknown | nil | | t | `'03/04/2026' could be 3 Apr or 4 Mar, and nothing in the file says which` |
| `12/12/2026` DayFirst | 2026-12-12 | | **t** (still flagged) | `read as 12 Dec 2026 (day first); would be 12 Dec 2026 if month first` |
| `00/05/2026` DayFirst | nil | | t | `'00/05/2026' could be 0 May or 5 ?, and nothing in the file says which` |
| `3/4/26` DayFirst | 2026-04-03 | | t | `read as 3 Apr 2026 …` |
| `15/07/202` | nil | | f | `… is not a date AA recognises` |

### 7.3 `Observe`/`Infer`
| Observed values | Order | DecisiveCount |
|---|---|---|
| `15/07/2026`, `03/04/2026` | DayFirst | 1 |
| `07/15/2026`, `03/04/2026` | MonthFirst | 1 |
| `15/07/2026`, `07/15/2026` | Conflicted | 0 |
| `03/04/2026`, `2026-07-15`, `12 Mar 2026` | Unknown (fallback) | 0 |
| `15/07/2026 10:00` | Unknown (time not stripped in Observe) | 0 |
| `45/03/2026`, `13/13/2026`, `15/07/202` | Unknown (ignored) | 0 |
| `31/02/2026` | DayFirst (not validated) | 1 |
| 60 × `15/07/2026` | DayFirst | **50** (cap) |
| Unknown + `Infer(DayFirst)` | DayFirst | 0 |
| Conflicted evidence + `Infer(DayFirst)` | **Conflicted** | 0 |

### 7.4 `ExpandYear` (today.year 2026)
Any: 26→2026, 68→2068, 69→1969, 0→2000. PastOnly: 26→2026, 27→1927, 98→1998, 5→2005. FutureLikely: 20→**2120**,
21→2021, 30→2030, 98→2098, 69→2069. `alreadyFull`/`y > 99` → unchanged.

### 7.5 `DateSummary`
- DayFirst, 1 witness, 0 unreadable → `dates read day first (dd/mm), proved by 1 value`
- DayFirst, 3, 2 unreadable → `dates read day first (dd/mm), proved by 3 values, 2 could not be read`
- MonthFirst chosen by user → `dates read month first (mm/dd), proved by 0 values`
- Conflicted → `dates read inconsistently — this file writes dates BOTH ways, so ambiguous ones were left unread`
- Unknown → `dates read in unambiguous formats only; nothing in the file said whether 03/04 means 3 April or 4 March`

### 7.6 `CrewConverter.Convert`
| Input cells | Result |
|---|---|
| Rank ` mast ` | Rank `Master`, RankCode `MAST`, no flag |
| Rank `3oft` | `Third Officer`; Warning Rank `Rank code '3OFT' → 'Third Officer' (approximate — verify).` |
| Rank `XYZ` | `Other`; Warning `Unknown rank code 'XYZ' → 'Other' (set manually).` |
| Rank blank | `Other`, RankCode `""`; Error `No rank in COMPAS → 'Other' (mandatory, set manually).` |
| Nationality code `phl` | `Philippines`; RawNationality = `Nationality` cell |
| code blank, Nationality `Filipino` | `Philippines`, Raw `Filipino` |
| code `XXX`, Nationality `Martian` | `Martian` |
| Gender `m` / `X` | `Male` / `""` + Info Gender `Gender code 'X' not recognised.` |
| Joining Port `Singapore (SGP)` | SignOnPort `SGSIN`, Raw `Singapore (SGP)` |
| Joining Port `Marmara (TUR)` | `TRMER` + Warning Sign-on port `Port 'Marmara (TUR)' → TRMER (UN/LOCODE best-guess — verify).` |
| Joining Port `Rotterdam` | `Rotterdam` + Warning `Port 'Rotterdam' has no UN/LOCODE mapping — left as name, set manually.` |
| Joining Port blank | `""`, no port flag; Error `Mandatory field 'Sign-on port' is empty — missing in COMPAS, fill manually.` |
| SignOff Port blank | SignOffPort `""`, no flag |
| Sign Off Date blank | Info Sign-off date `No sign-off date in COMPAS — contract expiry can't be tracked until it's filled in.` |
| Sign Off Date `03/04/2026`, file Conflicted | SignOffDate `03/04/2026`; Error `Sign-off date: '03/04/2026' left unread — this file writes dates both ways, so neither reading is safe — left as-is, set it by hand.`; UnreadableDates+1; **no** "No sign-off date" Info |
| Sign Off Date `03/04/2026`, DayFirst | `2026-04-03`; Warning `Sign-off date: read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first` |
| NoK Name `Maria  Clara   Santos` | NokFirstName `Maria Clara`, NokLastName `Santos` |
| NoK Name `Maria` | (`Maria`, `""`) |
| NoK Grade `WIFE` / `Cousin` / `Not Specified` / blank | `Spouse` / `Other` + Info Next of kin `Relationship 'cousin' → 'Other'.` / `Other` (no flag) / `""` |
| Original middle name `-`, Name `JUAN  CARLOS`, First `Juan` | MiddleName `CARLOS` |
| Name `JUANITO`, First `JUAN` | MiddleName `ITO` (no word boundary — faithful) |
| Name `JUAN - CARLOS`, First `JUAN` | `CARLOS` |
| Name `PEDRO`, First `JUAN` | `""` |
| Code blank, CMS blank, Passport Number `P1` | EmployeeId `P1` |
| First name blank | Error First name `Mandatory field 'First name' is empty — missing in COMPAS, fill manually.` (last in flag order) |
| No `Licence Number` but Licence dates present | CocNumber/Expiry/Issue all `""`, no licence flags |

### 7.7 `CompasReader`
- Sheets `Summary`, `REPORT` → reads `REPORT`. Sheets `A`, `B` → reads `A`.
- Title rows 1–3, headers on row 4 (`First Name`, `SURNAME`, `Sign Off Date`) → header row 4.
- Headers on row 21 only → throws the header error message.
- Header cell `First\nname` or `First  Name` or `FIRST NAME` → matches `first name`.
- Numeric cell `12345.0` → `12345`; `180.5` → `180.5`; boolean true → `TRUE`; date-formatted serial 46096 → `2026-03-15`;
  text `  ABC  ` → `ABC`.
- Row with blank First name and Surname but other data → skipped.
- Two `Rank` columns → the right-most wins.

### 7.8 `Key`, `FullName`, `ContractStatus`, expiry text (today 2026-09-29)
- Key: EmployeeId `123` → `123`; EmployeeId ``, First `Juan`, Last `` → `Juan`; ``/``/`Cruz` → `Cruz`; all blank → `""`.
- FullName: `Juan`, ` `, `Cruz` → `Juan Cruz`.
| SignOffDate | days | status | roster text | colour |
|---|---|---|---|---|
| `2026-09-28` | −1 | Expired | `⚠ Contract ended 1d ago  (2026-09-28)` | red |
| `2026-09-29` | 0 | Critical | `⚠ Signs off today  (2026-09-29)` | red |
| `2026-10-29` | 30 | Critical | `⚠ Signs off in 30d  (2026-10-29)` | orange |
| `2026-10-30` | 31 | DueSoon | `Signs off in 31d  (2026-10-30)` | amber |
| `2026-11-28` | 60 | DueSoon | `Signs off in 60d  (2026-11-28)` | amber |
| `2026-11-29` | 61 | Ok | `Signs off in 61d  (2026-11-29)` | green |
| `` / `garbage` | nil | Unknown | `` (banner: `No sign-off date on file — contract expiry can't be tracked.`) | grey |
- `ExpiringCount` over the table above = 5 (−1, 0, 30, 31, 60).
- CheckExpiries line for `Juan Cruz`, Rank `Master`/`MAST`, `2026-09-28`:
  `  •  Juan Cruz  (Master (MAST))  —  2026-09-28  [OVERDUE by 1d]`.

### 7.9 Sorting (today 2026-09-29)
Crew A {Last `Smith`, First `John`, CID `20`, DOB `1990-01-01`, SignOff `2026-10-01`}, B {Last ``, First `Ann`,
CID ``, DOB ``, SignOff ``}, C {Last `adams`, First `Zed`, CID `100`, DOB `1985-05-05`, SignOff `2026-09-01`}:
SignOffDate → C, A, B · LastName → C, A, B · FirstName → B, A, C · Cid → C (`100`), A (`20`), B · BirthDate → C, A, B.

### 7.10 Search
`phil` matches Nationality `Philippines`; `123` matches EmployeeId `A1234`; `mast` matches Rank `Master`;
`COFF` does not match `Chief Officer` (codes not searched); `SGSIN` matches nothing; `  juan  ` ≡ `juan`.

### 7.11 Table cells (`2026-03-15` stored)
| Format | Sep | Cell |
|---|---|---|
| Iso | `-` | `2026-03-15` |
| Iso | `/` | `2026/03/15` |
| Iso | `` | `20260315` |
| Iso | `'` | `2026'03'15` |
| Iso | `m` | `2026m03m15` |
| DayMonthYear | `.` | `15.03.2026` |
| MonthDayYear | `/` | `03/15/2026` |
| DayMonthName | `-` | `15-Mar-2026` |
| DayMonthName | ` ` | `15 Mar 2026` |
Stored `15/07/2026` (unparseable) → `15/07/2026` in every format. Stored legacy `03/04/2026` → Iso `2026-03-04`.
Non-date column → raw text. `Pattern(Iso, "-")` = `yyyy'-'MM'-'dd`; `Pattern(Iso, "")` = `yyyyMMdd`;
`Pattern(Iso, "'")` = `yyyy'\''MM'\''dd`.

### 7.12 Column chooser
- `CrewTableColumns = []` → 9 defaults ticked (in default order) then the other 31 unticked in catalog order.
- `CrewTableColumns = ["Vessel","Bogus","LastName","Vessel"]`, shown `["LastName"]` → `Vessel` (unticked),
  `LastName` (ticked), then the remaining 38 catalog columns unticked; `Bogus` and the duplicate dropped.
- Shown `[]` with non-empty order → zero columns shown; count text `N crew  ·  0 columns`; export refused.
- One shown → `… 1 column`.

### 7.13 `XlsxWriter`
- `ColRef`: 0→`A`, 25→`Z`, 26→`AA`, 27→`AB`, 51→`AZ`, 52→`BA`, 701→`ZZ`, 702→`AAA`.
- `Esc`: `a\u0001b` → `ab`; `x\ty` → `x\ty`; `"` → `&quot;`; `'` unchanged; `&<>` → `&amp;&lt;&gt;`.
- Sheet name `""` → `Sheet1`; `A&B` → `A&amp;B`.
- Round-trip: unzip the output, assert the 6 entry names in order, the constant parts byte-equal (modulo newline
  style), `sheet1.xml` as §4.10, and that Excel/Numbers open it (manual) with a bold shaded header.

### 7.14 Schedule
- `NormTime`: `8:05`→`08:05`, `08:05`→`08:05`, ` 7:30 `→`07:30`, `8:5`→``, `0730`→``, `25:99`→`25:99`, ``→``.
- Timeline order: entries (`2026-10-02`,`09:00`), (`2026-10-01`,``), (``,`08:00`), (`2026-10-01`,`07:30`) →
  groups `Thu, 2026-10-01` [`` (as 00:00), `07:30`], `Fri, 2026-10-02` [`09:00`], `(no date)` [`08:00`];
  with today = 2026-09-30 the first two labels become `Tomorrow` and `Fri, 2026-10-02`.
- `ApplyToCrew(replace:false)` appends clones with new Ids and `Done=false`; template `VesselId` overwrites the
  crew link; `VesselId` null leaves it unchanged.
- `ImportJson` of `null` → error `This file is not a valid schedule.`; of a Windows export → same titles/dates/kinds,
  fresh Ids.
- `Sanitize("Juan/Cruz:")` → `Juan_Cruz_`; `Sanitize("  ")` → `crew`.

### 7.15 Upsert / persistence
- Existing member {Id X, EmployeeId `123`, Checklist [s1], Schedule [e1]} + import row with Code `123` → roster
  position unchanged, Id X, Checklist [s1] kept, detail fields & flags from the file; Windows: Schedule `[]`
  (see §8 Q3); counts `(0 new, 1 updated)`.
- Same file containing Code `123` twice → one member, counts `(1 new, 1 updated)`.
- Delete then Ctrl+Z → member back with same Id, checklist, schedule; a second restore of the same Id is a no-op.
- JSON round-trip: decode the §4.2 example, re-encode, decode on Windows (manual) → identical values; Severity stays integer.

---

## 8. Known quirks, divergences and open questions

Default rule: **replicate Windows behaviour** so the same file/data yields the same result on both platforms;
items marked *Recommend* need a product decision (ideally fixed on both platforms together).

- **Q1 — Date-order question asked with nothing ambiguous.** Unknown ⇒ ask, even when the file has no ambiguous
  numeric dates at all (all ISO/typed/month-name) or no rows. The answer then only changes the `DateSummary`
  wording (`… proved by 0 values`). *Recommend:* only ask when at least one ambiguous value was seen (needs a
  counter in `Observe`); keep as-is until decided.
- **Q2 — Conflicted file ignores the user's answer.** The dialog asks day/month, but `Infer` keeps Conflicted;
  ambiguous values stay unread (Error flags). Only Cancel has an effect. *Recommend:* either reword the conflicted
  dialog as "Import anyway (ambiguous dates left unread) / Cancel", or make the answer `Adopt` the order. Replicate
  until decided.
- **Q3 — Re-import wipes the crew Schedule.** Upsert preserves `Id` + `Checklist` only; `Schedule` and
  `ScheduleVesselId` (added later) are lost on re-import. *Recommend (Mac):* also carry over `Schedule` and
  `ScheduleVesselId` — data-compatible, strictly safer; flag for a matching Windows fix.
- **Q4 — Unread ambiguous dates are later read month-first.** An import leaves `03/04/2026` as raw text with an
  Error flag, but `ParseDate` (expiry math, table, sort) then reads it as 4 March, and pressing Save in the editor
  normalises it to `2026-03-04` silently. Must be replicated for cross-platform consistency; flagged.
- **Q5 — `ParseDate` fallback semantics** must match .NET InvariantCulture (month-first, pivot 2049, `Z` → local).
- **Q6 — Uppercase `T` / time stripping bugs** (`12 AUGUST 2026`, `DECEMBER 1ST 2026`, `12 Mar 2026 10:00`) make
  valid dates unreadable and store a truncated raw value (`12 AUGUS`, `12`). Replicate (import parity); *recommend*
  fixing on both sides (strip `T` only when preceded by a digit; strip time only when the text after the space
  matches `^\d{1,2}:\d{2}`), and store the original cell text when unreadable.
- **Q7 — `FromExcelSerial` is unused.** PROGRESS claims Excel serials are read, but the import path only sees
  ClosedXML-typed dates; a date stored as a plain number (no date format) arrives as e.g. `46096` and is
  unreadable. Replicate; optional joint improvement: treat 5-digit integers in date columns as serials.
- **Q8 — Non-ASCII digits** in date cells make .NET `int.Parse` throw → the whole import fails with an error box.
  Swift uses ASCII-only `[0-9]` (value becomes "not a date AA recognises"). Accepted divergence (Mac more robust).
- **Q9 — 29 Feb year-expansion crash** (`29-Feb-00` FutureLikely → 2100-02-29) aborts the Windows import.
  *Recommend (Mac):* treat as unreadable with the standard Error flag instead of aborting. Accepted divergence.
- **Q10 — Separator with backslash** in the table view: .NET drops the backslash / throws on a trailing one. Mac
  outputs the separator verbatim. Accepted divergence (display/export only).
- **Q11 — Empty separator not remembered** (`""` persisted, reloads as `-`). Replicate.
- **Q12 — Card shows doubled field prefix** for date flags. Replicate (message strings are data).
- **Q13 — Clear all is a hard delete** (not trashed, not undoable) while single delete is soft. Replicate;
  consider a stronger Mac warning text (no behaviour change).
- **Q14 — Schedule entry delete has no confirmation and no undo; `✎` tooltip says "title/notes" but edits title
  only; `Notes`, `EndDate`, `EndTime` are never set by the UI** — replicate, preserve the fields.
- **Q15 — Badge does not refresh at midnight** on Windows; Mac may refresh on day change (improvement).
- **Q16 — Restore can duplicate a Key** (member re-imported while in the Trash, then restored). Replicate.
- **Q17 — `OrderDependentDates` counter is computed but never shown.** Port it (harmless) for parity/tests.

PROGRESS.md sections folded into this spec: "No crew-expiry popup at startup"; "Crew date parser: reads any
format, and works out dd/mm vs mm/dd"; "Crew roster sort + tabulated table view with Excel export";
"Update (2026-07-03) … COMPAS crew import & contract-expiry tracking" / "Import COMPAS crew reports → crew cards,
with contract-expiry tracking & notification"; "Editable crew cards (accidental-edit-proof)"; "Update (2026-07-08)
per-crew-member checklists …" (Per-crew-member checklist; Reusable saved lists; Crew items in due-dates &
everywhere necessary; Adversarial review fix #1); "Per-crew scheduler" (2026-07-17); "Undo + soft-delete Trash";
"Background reminders"; Planner "deadline-aware" (crew steps placed).
