# W-BUILD — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| D1 | 06 §8 D1, BUILD-072, A10 | Saved Lists sections are keyed by group **Id** (equal names stay separate); a dangling `GroupId` shows under "Ungrouped"; "Ungrouped" is always last (explicit, not via U+FFFF). Data unchanged. |
| D2 | 06 §8 D2, BUILD-079, 07 VIEW-211 | "Move to group…" preselects the list's current group (or "(No group — ungrouped)"); OK needs a choice, so an empty OK can no longer ungroup by accident. |
| D3 | 06 §8 D3, BUILD-063, DECISIONS 02 Q-12 | Template editor writes back only when the items changed (no container/file id churn); if the list was deleted meanwhile the user is asked "Save as New List" / "Discard Changes"; in a saved-list step Deadline/Done are shown disabled with "Set when the list is applied". |
| R1 | 06 §8 R1, ARCH §2.4 | Builders, editors and the procedure checklist re-resolve their owner by id on every read; a vanished owner shows an orphan state instead of editing detached objects. |
| R3 | 06 §8 R3, §6.3 | "Export ALL (PDF)…" is reachable with no list selected (empty detail state). |
| T-KB-40 | 03 T-KB-40, W-9 | An open template editor registers with `EditorFlushCenter`, so ⌘S, autosave and the quit pipeline write its edits back. |
| buttons | 06 §6.2 | Yes/No/Cancel boxes use explicit verbs: Replace / Append / Cancel (load a saved list) and Rename… / Delete… / Cancel (manage list / manage group); the Windows sentences are kept verbatim. Destructive confirmations default to Cancel (03 §6.5). |
| glyphs | ARCH §8.5, DECISIONS P4 | Emoji / "+ " / "..." button prefixes become SF Symbols and the `…` glyph (e.g. "💾 Save as list..." → `square.and.arrow.down` "Save as list…", "+ Item" → `plus` "Item"). ↑/↓ are icon-only buttons with the Windows tooltips. Window titles become sheet headers. |
| additive | DECISIONS 06 | The subtask editor has a nested "Subtasks" section (add, edit recursively, reorder, delete, open the builder). |
| additive | 06 §6.2 | Drag-and-drop reorder in the builders (BUILD-A3 with the drop index) and within a Saved Lists group (`SavedListOrder.moveTo`); disabled while Sort A-Z is on. |
| additive | 06 §6.2 | ⌘↩ Add all; ↩ / double-click Edit…; ⌃⌘↑/↓, ⇧⌘M, ⌫ through the list-command registry; context menus on builder lists, Saved Lists and the item preview. |
| additive | 06 BUILD-045 | Builder rows show a small badge with the number of deeper subtasks carried by a subtask; the subtask builder footer counts them. |
| additive | 04 HIER-095 | The step editor shows the step's linked tasks / equipment as read-only chips. |
| additive | — | Procedure checklist shows "{done} of {n} done" with a progress bar; Link tasks… / Link equipment/area… / Remove / Edit… are disabled without a selected step (Windows: silent no-op); the bulk pane shows "{n} lines ready to add". |
| additive | BUILD-022 | An invalid duration keeps the model unchanged (parity) and gets a faint red outline. |
| bulk box | BUILD-002, A28 | The bulk text box is a plain-text, no-wrap NSTextView with smart quotes/dashes/autocorrect off (raw text like the WPF TextBox). |
| labels | DECISIONS 04 Q-G | Status / Recurrence pickers show friendly labels ("To Do", "In Progress"…); the stored integers are unchanged; an out-of-range stored value is offered as its own row so it round-trips. |
| not mine | OWNERSHIP §4 | BUILD-091…096 (saved-list / checklist PDF + XLSX exports) are W-PDF's: the buttons call `PdfExportFlows`. BUILD-101 (`SavedListPicker` → tasks) is W-PLAN's; BUILD-102 is W-QUICK's; BUILD-110…125 (crew schedule builder) are W-CREW's; BUILD-100 is W-CONT's; BUILD-130/131/136…150 are F3's. |
