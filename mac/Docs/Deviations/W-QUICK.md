# W-QUICK — deviations and P2 fixes

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`.

## P2 defect fixes (files stay readable by Windows with the same meaning)

| ID | Spec ref | Fix |
|---|---|---|
| 08 Q-3 | QUICK-016 | A scheduled **subtask** job in the due-dates panel opens its root task with the subtask selected (Windows navigated to the subtask itself, which selected nothing). |
| 08 Q-5 | QUICK-007 | The due-dates panel also refreshes at local day rollover (`NSCalendarDayChanged`) and after every reload (`dataReplaced`). |
| 08 Q-8 | QUICK-194 | Count-aware file keys in the diff (F2's `DataDiff`); the review sheet never crashes on duplicate `Name|Path`. |
| 08 Q-10 | QUICK-122 | The Search button follows the latest run only (generation counter); a superseded scan never publishes. |
| 08 Q-16 | QUICK-073 | Deleting from quick work closes a detached item window of that item first. |
| 08 QUICK-214 | QUICK-214 | Every save in these windows is caught: the error is shown (`Save failed`), the store stays dirty and the debounce retries; the app keeps running. |
| 08 Q-14 | QUICK-042/101/151 | The never-rendered WPF placeholders are real prompts: `Search tasks & procedures...`, `Type a name, kind or #tag...`, `Filter action / kind / name...`. |
| 08 Q-17 | QUICK-011/012/018 | `ddd, dd MMM` uses the current locale on the Gregorian calendar; fixed formats (`yyyy-MM-dd`, `MM-dd`, `HH:mm`, `yyyy-MM-dd HH:mm:ss`) are always `en_US_POSIX` Gregorian. |

## Sanctioned decisions applied

| ID | Spec ref | Behaviour |
|---|---|---|
| DECISIONS 02 Q-4 / 08 OQ-1 | QUICK-073, T-QW-13 | Quick-work **Delete** moves the item (whole subtree) to the Trash (undoable with ⌘Z, references kept for a lossless Put Back, pin removed). Confirmation title `Delete`, text `Delete '{name}' and everything under it? This removes it everywhere — it goes to the Trash (put it back from File ▸ Trash…, or undo with ⌘Z).`, buttons Move to Trash / Cancel (default Cancel). The log line is the Trash's `Removed / {KindLabel} / name / moved to Trash` instead of Windows' `Removed / Task|Procedure / name`. |
| DECISIONS 02 Q-5 | QUICK-173, REPO-078 | Trash buttons `Put Back` (tooltip starts "Restore:"), `Delete Immediately…`, `Empty Trash…`, `Close`; in-sheet keys ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫ (03 SHELL-675). Messages keep the Windows text. An empty Trash shows "The Trash is empty." (additive). |
| DECISIONS 08 OQ-2 | QUICK-100 | The quick switcher is a floating Open-Quickly panel (borderless, 620×480, centred over the main window), not a modal window; it closes on ⎋ / ⌘W / resign-key; ↑ ↓ ↩ as Windows; single click selects, double click opens. |
| DECISIONS 08 OQ-3 | QUICK-120, QUICK-150 | Search and Activity log reuse one window each (F3 scenes); ⌘F re-focuses the query and selects it. |
| DECISIONS 08 OQ-8 / REQ-F2-02 | QUICK-103/105 | Switcher rows are built with `QuickSwitcherScoring.rows(store:isGated: env.locks.isGated)`: a description of an item still locked this session never ranks. |
| DECISIONS 08 OQ-10 / 04 Q-G | QUICK-074 | Status / Recurrence pickers show friendly labels (`To Do`, `In Progress`, …) while storing the same integers. |
| DECISIONS 08 OQ-5 | QUICK-074 | Deadline / Range start use F3's `OptionalDatePicker` (explicit "—" + Set… / clear button) instead of an empty WPF DatePicker; coercion still runs against the model (T-QW-7). |
| DECISIONS 02 Q-11 | QUICK-125, QUICK-013/014 | A search hit opens its owner with the matched child (subtask / step / component) selected; due rows for subtasks and procedure steps likewise pass the child id. |
| DECISIONS 01 Q-3 | QUICK-191…194 | The review sheet has an opt-in "Show other data (crew, saved lists, schedules, ports, SIRE)" section with its own counts; the Windows summary line and tree are unchanged. |
| 08 Q-11 / Q-13 | QUICK-049/051/152 | Quick-work rows refresh after every action and whenever the window becomes key; the detail binds live (Status updates after a batch done). The Activity log rebuilds when the log changes. Selection and focus are preserved. |
| Mac buttons | 03 §6.5.1.5, 01 MP | `Import (Overwrite)` (title case, as 03 §6.5.1.5 and 01 MP.5 write it); Insert-saved-list question uses Replace / Append / Cancel buttons and the body names them (`Replace = …`, `Append = …`, `Cancel = do nothing`) instead of Yes / No; ellipsis glyph `…` on buttons that open a dialog (`Export (.csv)…`, `Sort into Buckets…`, `Edit…`, …). |
| Mac grace | 08 §6.2 | SF Symbols replace the WPF glyphs (due-row icons, tile header, bucket header — the 🪣 text stays in `QuickWorkGroup.header` for accessibility); hover states; animated tick-off; collapsible Pinned header; drag reorder (`.onMove`) of children in addition to ↑/↓; a `{done}/{total} done` hint in the children builder; a red subtitle for overdue rows in the quick-work list; Added/Removed capsules in the Activity log. |
| 08 §6.5 | QUICK-002 | The due-dates panel is `.floating` + full-screen auxiliary; above a full-screen app in another Space it cannot appear (OS limit). Both panels are excluded from the Window menu (no taskbar on the Mac). |
