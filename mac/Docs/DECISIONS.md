# AA for macOS — lead decisions on the specs' open questions

Binding for every implementer and verifier. Order of authority: `ARCHITECTURE-BRIEF.md` (incl. Rule zero) →
this file → `ARCHITECTURE.md` → `Spec/*.md`. The shortcut/menu registry in `Spec/03 §6.5.1` stays the single
authority for keys and menu placement.

## Governing principles

- **P1 — Parity by default.** Every feature, text, default, ordering and data effect of the Windows app is
  reproduced. "Intricacies retained" means the Mac user can do everything the Windows user can, the same way,
  with the same result on disk.
- **P2 — Fix real defects when the fix is data-compatible.** Anything a spec labels a defect that loses/corrupts
  data, crashes, silently does nothing, or targets the wrong item (all `D-*`, `W-*`, `DEV-*` items flagged as
  bugs) is fixed on the Mac, provided the files written stay readable by the Windows build with the same
  meaning. Record each fix in `Docs/DEVIATIONS.md` (ID, spec ref, one line).
- **P3 — Quirks that are behaviour, not bugs, stay.** Wording, sort orders, which fields are exported, one-way
  relationship semantics, what the Windows UI logs or doesn't log — keep unless P2 applies.
- **P4 — Mac grace is additive.** Native idioms (sidebar, inspector, toolbar, sheets, popovers, SF Symbols,
  materials, Quick Look, drag & drop with Finder, Services, Dock badge, notifications, MenuBarExtra, Touch-ID-free
  password sheets, proper pluralisation, "Finder" instead of "Explorer", ellipsis glyph `…` in menu titles) may
  replace the WPF presentation, but never remove a capability or change stored data.

## Specific resolutions

### Data & persistence (01)
- Q-1 hard-coded login gate `44233` / `redemption` and the master password `redemption`: **keep exactly**.
- Q-2 property order: write in the documented System.Text.Json order (derived-class members first, then base,
  in declaration order); readers are order-independent. No byte-golden tests against Windows output until a real
  Windows fixture exists; golden tests use hand-built fixtures that follow the spec.
- Q-3 change preview: add the opt-in **"Other data"** section (crew, saved lists, ports, SIRE) — additive.
- Q-4 changing the app password requires the current password on the Mac (additive safety).
- Q-5 importing an external JSON: offer "Copy into AA folder" (default) or "Use in place" (Windows behaviour).
- Q-6/02-Q-8/07-Q-05 **dates**: a `NetDateTime` value keeps the exact textual form it was read with and writes
  it back unchanged if the value was not edited. Newly created or edited **calendar dates** (Deadline,
  RangeStart, step/subtask deadlines, recurrence-generated dates, Planner placements `ScheduledStart`) are written
  as **Unspecified** (no offset) wall-clock values; **timestamps** (`Added`, `LastModified`, `CreatedUtc`,
  `DeletedUtc`, `TimestampUtc`, `WrittenUtc`, …) keep the Windows kind (Local with offset / Utc with `Z`).
  Reading an offset-bearing value converts to local wall-clock time exactly like .NET.
- Q-7 **not sandboxed** (arbitrary network paths, in-place links); ad-hoc signed by `build-app.sh`.
- Q-8 `SchemaVersion`: Mac writes **1** (Windows parity); newer-version warning semantics as Windows.
- Defects D-1…D-15 listed in 01/03: **fix** per P2.
- Concurrent processes: a second launch activates the running instance (standard Mac single-instance).
- DPAPI "encrypt local data at rest" → AES-GCM key in the Keychain, Mac-own header (e.g. `AAMENC1\n`); reading a
  Windows DPAPI file shows a clear "encrypted on another computer" error, never garbage.

### Repository / domain (02)
- Q-1 fixed `SavedListOrder.Nudge`: **yes**. Q-2 recurrence clones: **parity**. Q-3 widen `PurgeReferences`: **yes**
  (P2). Q-4/07-Q-01/08-OQ-1 Board & Ctrl+N deletes: **route through the Trash** (undoable; permanent delete stays
  available from the Trash window). 07-Q-02 purge the whole deleted subtree: **yes**.
- Q-5 Trash wording: Finder-style **"Put Back" / "Delete Immediately"**, with "Restore" in tooltips.
- Q-6 add ⌘⌫ Move to Trash and arrangement keys only as allotted in the §6.5.1 registry.
- Q-7/03-Q-8 digest: also at local day rollover (`NSCalendarDayChanged`), digest date tracked per device.
- Q-9/05/08 find: **⌘F = global search** (parity), in-note find as allotted by §6.5.1. Q-10 ⌘O quick switcher.
- Q-11 search hit selects the matched child (subtask/step/component): **yes**. Q-12 skip no-op write-backs: **yes**.
- Q-13 notifications: UserNotifications + **Dock badge + MenuBarExtra** replace the tray balloon.
- D-2 / D-9 / D-21: accept the Swift behaviours proposed in the spec.

### Shell & theme (03)
- Q-1 light theme: keep the AA identity palette but map pure-black muted/border tokens to Mac semantic
  equivalents where contrast allows; dark theme follows the spec palette.
- Q-2 appearance: **System / Light / Dark** picker (per device, UserDefaults); choosing Light/Dark also writes the
  synced `DarkMode` bool; "System" leaves `DarkMode` untouched.
- Q-3 reloads keep the Mac's own window geometry and per-device `Ui` keys. Q-4 tray → **MenuBarExtra** (on by
  default, toggle in Settings). Q-5 quit-save failure → Retry / Quit Anyway / Cancel. Q-6 ⌘R as per registry.
- Q-7 and W-1…W-11: **fix** (P2); correct the "every 10 minutes" text to the real cadence.
- Appearance defaults to "System" on first launch unless settings.json says `DarkMode: true`.

### Hierarchy (04)
- Q-A unify tag parsing (multi-delimiter, `#` strip, case-insensitive de-dup): **yes**.
- Q-B disable Remove (with help text) for one-way `ProcedureIds/TaskIds` rows. Q-C filter-independent picker
  selection: **yes**, returning **selection order** (preselected first, then click order) as on Windows.
- Q-D Lock now gates open item windows in place. Q-E `#tag` matching in sidebar search: **yes**.
- Q-F no Touch ID for item locks. Q-G status/recurrence shown with friendly labels ("To Do", "In Progress",
  "Blocked", "Done"; "None", "Daily", …) while storing the same integers. Q-H keep the tab label **"Container"**.

### Container / rich text / file bank (05)
- Exact XAML output: follow spec 05's writer rules; the converter must round-trip untouched content
  byte-stably (keep unrecognised elements/attributes in a side channel where possible).
- File-bank Cut = **true move**. ⌘F per registry. Images pasted/dropped into the note text are **added to the
  file bank** (with a brief inline notice), not embedded — XAML can't carry them.
- Empty document is written as `""`. macOS packages dropped as copies are zipped into one `files/` entry.
- HTML paste whitespace quirk: **clean up** (don't create blank " " paragraphs).
- Surface `FileItem.LinkedItemIds` (a "Linked to" column + item backlinks) and a UI for
  `Container.SharedWithContainerIds`: **yes** (the brief requires both; additive).
- D-1 / D-2: fix (never wipe an undecryptable body; clear undo on item switch).

### Builders & saved lists (06)
- "Banked tasks" = linking existing Tasks to a step + "New task" auto-linked: **confirmed**.
- Nested subtasks: the Mac subtask editor **gains a nested Subtasks section** (additive, data already nested).
- D1–D7 deviations: **accept**. Background reloads while a builder is open: resolve by Id on commit, and warn if
  the target vanished (never orphan edits silently).
- Keep crew `Schedule`/`ScheduleVesselId` on COMPAS re-import: **yes**. Log the unlogged actions: **yes**
  (additive log entries). Crew schedules in Calendar/due-dates: **no** (parity).

### Calendar / Board / Planner / Buckets / Map (07)
- Q-03 log Board/saved-list task creation: **yes**. Q-04 locks not enforced in these views: **parity**.
- Q-06 grey completed procedures/steps in Planner: **yes**. Q-07 double-click in Planner navigates: **yes**.
- Q-08 keep picker selections across searches: **yes**. Q-09 localise weekday headers via the user's locale.
- Q-10 per-kind colours on the map: **yes** (Equipment #4FC3F7, Task #FFB74D, Procedure #A5D6A7, Vessel #CE93D8,
  adapted for dark mode). Q-11 bucket categories: **case-insensitive merge** for display only.
- Q-12 add an **Overdue** group to All Upcoming/Agenda (additive).

### Quick / floating windows (08)
- OQ-2 quick switcher = floating **Open Quickly-style panel**. OQ-3 Search & Activity log: reuse a single window
  each. OQ-5 "no date" states: an explicit toggle/clear button beside every optional date picker.
- OQ-6 keep Windows wording. OQ-7 match across formatting runs: **yes**. OQ-8 gate locked-item descriptions from
  ranking: **yes**. OQ-9 extend DataDiff beyond Windows scope: covered by 01-Q-3 "Other data". OQ-10 friendly labels.

### Crew (09)
- Q1 only ask dd/mm vs mm/dd when an ambiguous value was seen. Q2 make the answer take effect for Conflicted
  files. Q3 yes. Q4/Q6/Q9 **fix** (never truncate raw text, never mis-read, unreadable instead of abort). Q7 add
  Excel-serial handling. Q8/Q10 accepted. Clear all → through the Trash as one batch (undoable).
- Crew stays out of global search/quick switcher (parity) but appears in the "Other data" change preview.

### Vessel / ports / jobs / cards (10)
- Q1/Q2/Q3: **parity** for export columns; **fix** RemoveCall matching (VesselId + port + date) per P2.
- Q4 per-device **path-mapping table** (Settings) for Windows paths → Mac paths, applied only when opening;
  UNC → `smb://` fallback. Q5 detached vessel shows its own panels. Q6 "Finder". Q7 notifications for flagged
  overdue work orders: **yes**, respecting the per-ship master switch. Q8 pluralise. Q9 honour `date1904`.
- Q10 orphaned copies: parity. Q11 show placeholders. Q12 parity. Q13 month-first text dates: parity with the
  shared date parser.

### PDF (11)
- Q1/Q3 **parity** (Windows PDF output is the reference). Q2 no bundled font: use the system sans (SF Pro /
  Helvetica Neue) with metrics tuned to match page breaks as closely as practical. Q4 render nested tables.
  Q5 print "(locked content)". Q6 name only for gated related items. Q7 fixed `yyyy-MM-dd HH:mm`. Q8 no outline.

### SIRE (12)
- Q-3 enable multi-select "Selected Questions" export. Q-6 keep model/params but raise `maxOutputTokens` to
  8192 and send the key in the `x-goog-api-key` header. Gemini key in the **Keychain**; a key found in
  settings.json is imported once and the settings key is preserved untouched. Filter state/splitters remembered
  per Mac (UserDefaults). Show the EXP tag. Windows-side fixes: noted in DEVIATIONS.md for the user.

### Flash Sync (13)
- Q-1/Q-2 skip excluded keys on apply: **yes**. Q-3 fold a root-level `Ui` into the Ui merge: **yes**.
- Q-4 clear stale encoder/baseline: **yes**. Q-5 refuse in safe mode; unreadable settings = error. Q-10 apply
  transactionally. Q-11 encrypt the baseline when local encryption is on. Q-12 single baseline per device
  (parity; documented). Q-16 `From` = AppIdentity. Q-18 persist Speed per device. Separate single-instance
  window; optional additions (Reset pairing, full-screen QR, rich review sheet): **yes**; ScreenCaptureKit /
  iPhone-mirroring receive: **no** for v1.

### Drive & tools (14)
- Ellipsis glyph in menu titles. Q-1 paging via `nextPageToken`: **yes**; Q-6 `supportsAllDrives`: **yes**.
- Google token in the Keychain (own item, separate from the local-data key). Default AppIdentity = the Mac's
  computer name (`SCDynamicStoreCopyComputerName`). Q-3 harden EnsureFolder: **yes**. Q-16 "Result is out of
  range." message: **yes**.

### Architecture review follow-ups
- R-70 (DATA-181 conflict-copies recovery): add a registry row **File ▸ Recover Conflict Copies…** (no key
  equivalent, `APP` scope, enabled when conflict copies exist), placed after Reload from Disk. Owner of the
  flow: W-PERSIST; F3 wires the row like every other File item.
- Worktrees for F2/F3 and the wave live outside the repo, under the session scratchpad
  (`…/scratchpad/wt/<agent-id>`), on branches `stage/F2`, `stage/F3`, `wave/<agent-id>`; the lead merges them.
