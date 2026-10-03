# W-HIER — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| Q-01 | 04 §8 | A list rebuild keeps the selection while the items stay visible; an item filtered out leaves the details on the "No Selection" empty state (never stale disabled fields). |
| Q-02 | 04 §8 | An empty group's header counts 0 (the placeholder row is not counted). |
| Q-03 | 04 §8 | While a query is active, groups without matches are omitted (placeholders only when not searching). |
| Q-05 / Q-06 | 04 §8, HIER-120, HIER-021 | Navigation to an item hidden by the search clears the search, expands its section and scrolls it into view; + New clears a non-matching search before selecting the new item. |
| Q-07 / HIER-125 | 04 §8 | Sidebars rebuild live from any page or window (a structural signature of the kind's collection and groups is observed). |
| Q-08 | 04 §8 | The group picker's OK is disabled until a row is chosen (F3 picker, single mode); "(Ungrouped)" stays available. |
| Q-09 | 04 §8 | Delete group with no groups shows "No groups to delete in this tab yet." (title "Delete group"). |
| Q-11 / Q-12 | 04 §3.1, §8 | Sections are keyed by group Id (same-named groups or a group named "Ungrouped" stay separate); A→Z is a stable sort; duplicate group ids: first wins. |
| Q-14 / Q-B | 04 §8, DECISIONS 04 | Relationships Remove is disabled (help "Linked from the Specifics tab — use Pick… there.") for rows that exist only through Equipment `ProcedureIds`/`TaskIds`; such rows carry a → glyph. |
| Q-15 / Q-A | 04 §8, DECISIONS 04 | The item window parses tags with the unified main-pane parser (and shows the main-pane tooltip); `TagParser.parseCommaOnly` is kept only for the 04 §7.1 vector. |
| Q-16 / Q-17 | 04 §8 | A detached item's details show that item (disabled) — header, relationships and specifics; the Container tab shows the detached card and never binds a second editor. |
| Q-18 / Q-D | 04 §8, DECISIONS 04 | Open item windows observe `ItemLockService`: Lock Now gates them in place (the editor is unbound while gated). |
| Q-19 / HIER-114 | 04 §8 | An item window re-resolves its id on every render; deleted from anywhere or lost in a reload → read-only orphan state with the exact message; the notes area shows a notice instead of a disabled editor bound to a detached container. |
| Q-20 / HIER-115 | 04 §8 | The delete status names the first item actually trashed; only trashed ids close their windows. |
| Q-24 | 04 §8 | Every hierarchy sheet cancels on ⎋ (F3 sheets; the item-lock and component sheets set `.cancelAction` / close-type). |
| Q-26 | 04 §8 | A failed Save shows "Save failed" with the error and keeps the data dirty (no crash). |
| Q-28 | 04 §8 | Subtask Done column is a read-only check glyph, not "True"/"False". |
| Q-29 / HIER-017 | 04 §6.2, §6.11 | Context menus use native targeting (`contextMenu(forSelectionType:)`): right-click acts on the clicked selection or the clicked row without changing the selection; placeholders are not selectable; empty-space right-click offers only "New group…". |
| Q-30 | 04 §8 | With no items but groups, the empty-kind hint shows below the group headers. |
| Q-32 | 04 §8 | Committing a rename rebuilds and re-selects without re-running selection side effects (a vessel keeps its sub-tab). |
| Q-33 | 04 §8 | With several items selected, the header shows "{n} items selected — showing the first one." |
| Q-25 | 04 §8 | Invalid duration text is ignored as on Windows; the field gets a red outline and a help line. |
| Q-E | DECISIONS 04 | Sidebar search: a query starting with `#` matches tags (contains, ordinal ignore-case; several `#tokens` must all match). |
| Q-G | DECISIONS 04 | Status/recurrence pickers and the subtask Status column show friendly labels ("To Do", "In Progress"…); stored integers unchanged; an undefined stored value stays selectable. |
| HIER-054 | 04 §6.4, DECISIONS P4 | Manage lock is an NSAlert "Manage lock" / "This entry is locked." + "Change the password / hint, remove the lock, or keep it as is." with buttons Change Password / Hint… (default), Remove Lock (destructive), Cancel — same three outcomes. |
| HIER-034 | 03 §6.5 | The "Delete group '{name}'?" confirmation uses the buttons Delete Group (destructive) / Cancel (default). |
| HIER-022 | 02 §6.4 | Batch delete confirmation buttons are Move to Trash (destructive) / Cancel (default); the body text is F2's `BatchDelete.confirmationMessage` (⌘Z). |
| HIER-030 | DECISIONS P4 | The group-created status quotes the Mac menu title: "…choose 'Move to group…' to fill it." |
| BatchActions | DECISIONS 02 Q-4 | `confirmAndTrash` trashes top-level items and nested subtasks (`trashSubtask`) under one shared BatchId, re-evaluates the picks after the confirmation and flushes all editors first. |
| additive | 04 HIER-M01 | Drag rows (all selected rows when the dragged row is selected) onto a group header or an empty group's placeholder; an empty "Ungrouped (0)" header is shown as a drop target when every item is grouped. |
| additive | 04 §6.1 | The sidebar width (default 280, 220–480) is remembered per kind for the window (`@SceneStorage`); Windows does not persist it. |
| additive | 04 §6.2 | Sidebar header shows the item count; rows with an empty name display "(unnamed)" (display only); section headers have a disclosure chevron (double-click toggles too). |
| additive | 02 REPO-051 | The Task specifics show "range · {n} days" next to the start date while a range exists. |
| HIER-001 | 04 §6.3 | The details tabs are a segmented control (a pop-up menu when the pane is too narrow); the Specifics header text per kind is kept, "Container" kept (DECISIONS 04 Q-H). |
| Q-11 (02) | DECISIONS 02 Q-11, HIER-120 | A navigation naming a child selects it: a subtask (a nested one selects the direct subtask containing it) on the Schedule & Subtasks tab, a component on the Equipment specifics tab; checklist steps wait for REQ-W-HIER-02. |
| HIER-056 | 04 HIER-056, §6.7; 05 CONT-007, CONT-062, D-4 | Hosted container editors (main pane and item window) are keyed on the container and a re-load counter that steps when the app-password session goes unlocked → locked (Tools ▸ Lock Now re-loads the editor of a non-gated item, Windows `RelockCurrent`) and, on locked → unlocked, only while the body is still a legacy encrypted one (CONT-007). An unlock made by the editor's own 🔒/🔓 gate (CONT-062) keeps the same editor, so caret, scroll and undo survive (D-4). A detached item's main pane never re-binds (Q-17). |
| HIER-112 | 04 HIER-112, §6.7 | The item window binds its editor only after its id is in `AppStore.detachedItemIDs` (the main pane has parked), so one container never has two live editors, even for one frame. |
| M03 | 04 HIER-M03 | Double-clicking empty sidebar space does nothing (it never opens the details item in a window). |
| HIER-004 | 04 HIER-003/004, V-DESIGN rule 4 | The top-of-sidebar buttons and the wrapping toolbar are one icon bar: `plus` (click = + New; its menu = + New, + Group), `trash` = Delete, the A→Z toggle (`arrow.up.arrow.down`), and a trailing `ellipsis.circle` "Group commands" menu with Assign group…, Rename group…, Delete group. Spec names are the accessibility labels / menu titles, spec tooltips are kept, enablement unchanged; the row context menu and the menu bar are unchanged. |
| HIER-010 | 04 HIER-010, V-DESIGN rules 2/5 | Section headers are non-selectable rows on a PanelAlt band (not pinned List headers, whose full-width separator did not line up with the rows); the group name wraps instead of truncating, with the muted "(N)" following it. Rows are aaMono 13. |
| HIER-025 | 04 HIER-025 | After Return the Name box keeps the focus and the item stays out of the rebuild signature (`HierRenameState.editingAfterCommit`): later keystrokes re-label the row in place; the next Return or focus loss commits again. |
| HIER-085 | 04 HIER-085, Q-28 | Subtasks table: Name is the flexible, wrapping column (no line cap); When flexible (ideal 130); Status fixed 96; Done fixed 44 — every column fits without a horizontal scroll at the minimum details width. |
| VESSEL-005 | 10 VESSEL-005, DECISIONS 10 Q5 | Tools ▸ Vessel commands are withheld while the selected vessel is detached (its panels are shown disabled in the main window and the item window does not host them). |
| HIER-111 | 04 HIER-111, V-DESIGN rules 7/8/11 | Item window kind line = `AAKindBadge` on the fields' leading edge; the footer note is AAHelpText in a footer bar under a Divider. |
