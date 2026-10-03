# W-CREW — P2 fixes and sanctioned deviations (ARCHITECTURE.md §12.2)

## P2 fixes / DECISIONS 09 rulings applied

| ID | Spec ref | Change |
|---|---|---|
| 09 Q1 | CREW-033, §8 Q1 | The date-order question is asked only when the file left the convention unsettled (Unknown or Conflicted) **and** at least one value actually depends on it (`CrewDateResolver.ambiguousCount`, counted on the time-stripped value). Files that are all ISO / typed / month-name, or have no rows, import without a question. |
| 09 Q2 | CREW-033, §8 Q2 | For a Conflicted file the answer is adopted (`adopt(_:byUser:)`): ambiguous values are read with the chosen order and carry the usual order-dependent Warning. `DateSummary` then reads `dates read day first (dd/mm) as chosen at import, although this file writes dates BOTH ways` (month-first likewise); `proved by N` is 0 whenever the user chose the order. |
| 09 Q3 | CREW-035, 06 D9 | A re-import keeps the existing member's `Schedule` and `ScheduleVesselId` as well as `Id` and `Checklist`. |
| 09 Q4 | §8 Q4, CREW-073 | Stored crew dates are read through `CrewStoredDate`: identical to `CrewMember.parseDate` except that a numeric day/month value whose two components are both 1…12 and different (`03/04/2026`) is not read (no expiry, not counted in the badge, shown verbatim in the table, sorted last). The editor stores such text verbatim instead of silently normalising it to 4 March, and shows an inline hint under the date row. Stored text is never changed. |
| 09 Q6 | §3.6 StripTime, §8 Q6 | `T` is a date/time separator only at index ≥ 8 after a digit; a space starts a time only when the text after it begins `H:mm`. `12 AUGUST 2026`, `DECEMBER 1ST 2026`, `12 Mar 2026 10:00` now read correctly. An unreadable value keeps the whole cell text (never a truncated fragment). |
| 09 Q7 | §8 Q7 | A plain five-digit number in a date column is read as an Excel serial (1…73051) in the workbook's own date system (1900 / 1904). |
| 09 Q8 | §8 Q8, 06 D6 | Only ASCII digits are digits (resolver, `NormTime`); other digits never crash and are not read. |
| 09 Q9 | §8 Q9 | A two-digit-year month-name date whose expansion lands on 29 Feb of a non-leap year (`29-Feb-00` future-likely → 2100) is unreadable with the note `'…' is not a real date` (Error flag) instead of aborting the import. |
| 09 Q10 | §8 Q10 | The table separator is used verbatim (built from components; a backslash is literal). |
| 09 Clear all | CREW-061, DECISIONS 09 | Clear all moves every member to the Trash as one batch (F2 `trashAllCrew`, one ⌘Z restores all). The confirmation keeps `Remove ALL crew from the roster?` and adds a line saying the batch goes to the Trash. |
| 06 log | DECISIONS 06 ("log the unlogged actions"), 06 D8 | Schedule add / delete log `Added`/`Removed` · `Schedule entry` · title · crew name; schedule apply logs `Added` · `Schedule` · template name · `{n} entr{y|ies} applied to {crew}` (+ ` (replaced)`). |
| 06 R1 | DECISIONS 06 | The editor commits by id; if the member vanished (deleted / reloaded) Save shows a warning and writes nothing. |

## Sanctioned Mac presentation (P4) — no data effect

| ID | Spec ref | Divergence |
|---|---|---|
| question | CREW-033, 09 §6.4 | Three explicit buttons `Day First (03/04 = 3 April)` / `Month First (03/04 = 4 March)` / `Cancel Import`; the Yes/No/Cancel legend lines are dropped from the body, every other line kept. |
| ⌘Z | CREW-060, 09 §6.4 | The delete confirmation says `undo with ⌘Z`; buttons `Move to Trash` / `Cancel`. |
| apply | BUILD-122 | The Yes/No/Cancel apply question uses `Replace` / `Append` / `Cancel` buttons; the message keeps the legend lines. |
| export | CREW-105, 09 §6.4 | `Export complete` offers `Open` / `Show in Finder` / `Done` (superset of Yes/No). |
| table | CREW-100…104 | The table is the `crew-table` Window scene (non-modal) and reflects the live roster in the current sort order. The chooser also supports drag-to-reorder, Space toggles, ⌃⌘↑/↓, and a `Columns` menu bound to the same state; Contract Status / Days cells are tinted with the roster colours. Choices are written on every rebuild; the store is marked dirty only when a value actually changed. |
| roster | CREW-010…017, 09 §6.4 | Row context menu (Edit…, Open Checklist…, Open Schedule…, Move to Trash…), double-click = Edit…, ⌘⌫ / ⌫ = Move to Trash (with the confirmation), ⌥⌘F focuses the search field (placeholder shown), an expiring-count capsule beside the title, empty states. Day counts refresh when the tab is selected and at `NSCalendarDayChanged` (09 §8 Q15). |
| card | CREW-020…025 | Section glyphs are SF Symbols (`person.text.rectangle`, `ferry`, `book.closed`, `cross.case`, `ruler`, `person.2`); values are selectable; banner and checklist box carry symbols. |
| editor | CREW-070…076 | Sheet with a segmented Details / Checklist / Schedule switch; Esc = Cancel (Windows had none); date rows use `OptionalDatePicker` + the 130-pt text box with the same one-way sync. |
| schedule | BUILD-112, 06 §6.5 | Visible placeholders `HH:mm` and `What... (or pick an item)`; hover-revealed ✎/✕; context menu on entries. |
| busy | CREW-030 | The workbook is parsed off the main actor behind `AAProgressOverlay`; Import is disabled while running. |
