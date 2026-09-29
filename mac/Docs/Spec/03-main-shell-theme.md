# 03 — Main Shell, Startup & Theme (`SHELL-`)

Porting spec for the **application shell** of AA: process startup (crash log, settings, theme, splash,
login gate), the main window (menu bar, header bar, status line, shared-save indicator, shortcut
strip, the 13-tab strip), every global keyboard shortcut, save/autosave orchestration, the
shared-save and Google-Drive sync hooks that live in the shell, reminders (tray + daily digest),
close/exit, the About box, and the whole visual language (theme tokens, fonts, control styles,
icons, palettes) that the Mac design system must translate.

This is a contract for Swift implementers and verifiers. Anything owned by another subsystem is
listed so the shell can call it, but its internals are specified elsewhere (hierarchy pages,
container editor, persistence/DataStore, Google Drive, Flash Sync, crew, SIRE, tools windows).

**Sources read completely:** `AA/MainWindow.xaml`, `AA/MainWindow.xaml.cs` (1691 lines),
`AA/App.xaml`, `AA/App.xaml.cs`, `AA/Services/ThemeManager.cs`, `AA/Services/MaritimeIcons.cs`,
`AA/Views/SplashWindow.xaml(.cs)`, `AA/Views/LoginWindow.xaml(.cs)`, `AA/Views/PasswordWindow.xaml(.cs)`,
`AA/Views/TabColorsWindow.xaml(.cs)`, `AA/Views/UiTree.cs`, `AA/Views/Converters.cs`, `AA/AA.ico`
(7 PNG frames 16–256 px), `AA/Assets/Splash.png` (560×632), `AA/360_A.png` (100×100), `AA/AA.csproj`,
`AA/Views/PromptWindow.xaml(.cs)`, plus the call graph: `Services/DataStore.cs` (settings, load/save,
bundles), `Services/AppRepository.cs` (dirty/debounce/save/trash/undo), `Services/ReminderService.cs`,
`Services/PasswordService.cs`, `Services/ItemLockService.cs`, `Services/GoogleDriveUploader.cs`
(public surface), `Models/Models.cs` (`UiState`, `AppData`, `LogEntry`), `Views/CrewPage.xaml.cs`
(expiry count/check), `Views/HierarchyPage.xaml.cs` (hooks), `Views/ItemWindow.xaml.cs`,
`Views/FloatingTasksWindow.*` (hooks), `FlashSync/FlashChangeSet.cs` (Ui denylist),
`QR_SYNC_PROTOCOL.md` (Ui/Settings travel rules), `PROGRESS.md` (all sections listed at the end),
and the original product brief.

**Conventions used in this spec**

* `SHELL-nnn` — stable feature IDs (section 2). Logic references use `File.cs:line`.
* **WIN-BUG** — a behaviour of the Windows build that is a defect (code contradicts its own comments
  or the stated feature). Each one states the faithful behaviour, the recommended Mac behaviour, and
  is repeated in section 8 so the product owner can decide.
* **MAC-ADAPT** — a deliberate platform translation that keeps the capability.
* Strings in `code quotes` are verbatim, including typographic characters (`…` U+2026, `—` U+2014,
  `▸` U+25B8, `➜` U+279C, `“ ”` curly quotes, `·` U+00B7, `⚠` U+26A0, `🔗`, `📌`, `🌙`, `⌨`, `🎨`).
  `\n` = newline inside a message.

---

## 1. Overview

### 1.1 Purpose

The shell is everything between "the user double-clicks AA" and "a page is showing data", plus the
cross-cutting chrome around every page:

* **Startup & gate** — crash handlers, settings + theme applied before any window, a 2.4 s splash,
  a hard-coded username/password gate, then the main window, which loads the data file.
* **Main window** — menu bar (File / Tools / View / About), a header bar (brand, tagline, shared-save
  indicator, status line, 5 quick buttons), a hideable keyboard-shortcuts strip, and a 13-tab
  `TabControl` hosting every page. Tabs can be dragged to reorder and individually coloured; the
  Crew tab shows an expiry badge.
* **Orchestration** — owns the one `AppRepository`, re-creates it on every reload/import, fans it
  out to every page and every secondary window, flushes editors before any save/sync/export,
  persists window/UI state, runs the autosave, shared-save and Drive-sync timers, reminders and
  close-time persistence.
* **Theme** — the global style dictionary (`App.xaml`) and `ThemeManager`, a live light/dark swap
  of 11 brush tokens (+ fixed "paper" editor brushes), Consolas everywhere.

### 1.2 Where it sits

```
App (App.xaml.cs)
 ├─ crash handlers → %AppFolder%/crash.log + dialog
 ├─ DataStore.LoadSettings() → ThemeManager.Apply(DarkMode)
 ├─ SplashWindow (2.4 s, borderless, topmost)
 ├─ LoginWindow (modal; 44233 / redemption)
 └─ MainWindow  ─────────────────────────────────────────────────────────────┐
     Menu: File │ Tools │ View │ About                                       │
     Header: "AA" • tagline …… [shared indicator] [status] [📌 Due][Search][Go to][Load][Save]
     TabControl (drag-reorderable, per-tab colour):                          │
       Equipment/Area │ Tasks │ Procedures │ Vessels  (HierarchyPage ×4)     │
       Calendar │ Board │ Planner │ Relationship Map │ Crew │ Saved Lists    │
       Buckets │ Ports │ SIRE 2.0                                           │
     Shortcut strip (bottom, hideable)                                        │
     Owns: AppRepository, autosave timer (5 min), shared-save timers (1 min   │
       push / 60 s poll / watcher+1.5 s debounce), Drive sync debounce 1.5 s, │
       reminder timer 30 min, tray NotifyIcon, item-window registry,          │
       floating due-dates window, quick-work window                          ─┘
```

### 1.3 Startup sequence (exact order)

```
OnStartup (App.xaml.cs:14)
  1. install DispatcherUnhandledException (→ ReportCrash, Handled=true)
     AppDomain.UnhandledException (→ ReportCrash), UnobservedTaskException (→ SetObserved, silent)
  2. DataStore.LoadSettings()              (creates AppFolder; reads settings.json)
  3. ThemeManager.Apply(DataStore.DarkMode)
  4. ShutdownMode = OnExplicitShutdown
  5. SplashWindow.Show()
  6. DispatcherTimer 2.4 s → Stop; splash.Close(); ContinueToMain()
ContinueToMain (App.xaml.cs:65)
  7. LoginWindow.ShowDialog() — not true → Shutdown() (app exits; nothing written)
  8. new MainWindow(); Application.MainWindow = it; ShutdownMode = OnMainWindowClose; Show()
MainWindow ctor (MainWindow.xaml.cs:62)
  9. InitializeComponent; hook Loaded/Closing/PreviewKeyDown; CrewPg.Changed → UpdateCrewTabHeader
 10. create Drive-sync debounce timer (1500 ms, not started)
MainWindow.OnLoaded (MainWindow.xaml.cs:76)
 11. LoadDataAndInitUi()  (LoadSettings again; DataStore.Load(); new repo; safe-mode flag; hook Saved;
                           init every page; restore UI state; tab order; tab colours; shared indicator;
                           status "Loaded — <path>" or safe-mode text)
 12. StartAutoSaveTimer() (5 min)
 13. menu checkmarks ← settings (SyncOnSave, TextOnlyExport, DarkMode, EncryptLocalData)
 14. title "AA — <identity>"
 15. if safe mode → warning dialog; else if file schema newer → info dialog
 16. if SyncOnSave ∧ OAuth configured ∧ token cached → CheckRemoteNewer(false)
     else if OAuth configured ∧ NeedsReconsentForWholeDrive → info dialog
 17. _sharedLastSeen = _lastSyncedStamp = Data.LastModified; StartSharedSaveSync();
     if shared file set → (Background priority) CheckSharedFileForUpdate()
 18. InitTray(); reminder timer 30 min (CheckReminders(false))
 19. if not safe mode → (Background priority) PruneTrash(); ReconcileRecurrences() (reload Tasks &
     Procedures lists if anything spawned); ShowDailyDigestIfDue(); CheckReminders(false)
 (No crew-expiry popup — deliberately removed.)
```

Background-priority work (steps 17, 19) runs after the window has rendered; step 17's shared check is
queued **before** step 19's digest, so a shared pull happens first.

---

## 2. Feature checklist

### A. Startup, gate, crash handling

**SHELL-001 — Global crash reporting.** Three handlers are installed first thing
(`App.xaml.cs:20-22`):
* UI-thread unhandled exception → `ReportCrash(ex)` then **`Handled = true` (the app keeps running)**.
* Any-thread unhandled exception (`AppDomain`) → `ReportCrash` (the process then terminates).
* Unobserved `Task` exceptions → `SetObserved()` — swallowed silently, no log.
`ReportCrash` (`App.xaml.cs:48-63`): appends `[yyyy-MM-dd HH:mm:ss] {ex}\r\n\r\n` (local time;
`{ex}` = `Exception.ToString()`: type, message, stack, inner exceptions) to `<AppFolder>/crash.log`
(creates the folder), then shows a modal error box titled `AA — error`:
`AA hit an unexpected error and had to stop:\n\n{ex.Message}\n\nThe full details were written to:\n{path}`
(OK button, Error icon). Any failure while reporting is swallowed. Note the text says "had to stop"
even for the UI-thread case where the app continues.

**SHELL-002 — Settings and theme before any window.** `DataStore.LoadSettings()` then
`ThemeManager.Apply(DataStore.DarkMode)` run before the splash, so the login window is already in the
saved theme. (The splash itself is hard-coded white and ignores the theme.)

**SHELL-003 — Splash screen.** Shown on **every** launch (`SplashWindow`, `App.xaml.cs:33-43`).
* Borderless (`WindowStyle=None`), not resizable, **not in taskbar**, centred on screen, **Topmost**,
  white background, `SizeToContent=WidthAndHeight`, 1 px border `#FFDDDDDD`, window icon `AA.ico`.
* Content: the bundled photo `Assets/Splash.png` (560×632 px; `Stretch=Uniform`, `MaxWidth=560`,
  `MaxHeight=640` → displays at 560×632). The image shows a large black "AA", an engraved sepia
  cherub, and italic Consolas lines "A tool for Active minds / Created by B.E.P Avida / May 2026".
* Fallback if the resource is missing (`SplashWindow.xaml.cs:34-39`): a 520-wide panel (margins
  40,34,40,34) with `AA` (Segoe UI 128 bold black, left-aligned, bottom margin 18), then three italic
  Consolas 28 black lines `A tool for Active minds`, `Created by B.E.P Avida`, `May 2026`.
* Visible for a fixed **2.4 s** (no work is done during it except settings); then it closes and the
  login appears. No click-to-dismiss, no fade.

**SHELL-004 — Login gate.** Modal `LoginWindow`, title `AA — Sign in`, 420×280, not resizable,
centred on screen, background token `Bg`, padding 22.
* Layout (top→bottom): `AA` (28, bold, `Accent`, centred); `Please sign in to continue` (`Muted`,
  centred, margin 0,2,0,16); label `Username`; text box; label `Password`; password box; error line
  (red `#FFD45050`, wraps, initially empty); right-aligned buttons `Exit` (width 90) and `Sign in`
  (width 110, `AccentButton` style = bold, **default button** → Enter anywhere submits).
* Focus goes to Username on load. Enter in the password box also submits.
* Credentials are **hard-coded**: username `44233`, password `redemption`
  (`LoginWindow.xaml.cs:12-13`). Username is compared after `Trim()` with ordinal (case-sensitive)
  equality; password exact ordinal equality, no trim.
* Failure: error text `Incorrect username or password.`, password box cleared, focus to password.
  No attempt limit, no delay.
* `Exit` → dialog result false. Closing via the title-bar ✕ → result null. Either → `Shutdown()`.
* This is a basic gate, not security (documented in PROGRESS). The same `redemption` string is also
  the master password of `PasswordService` and `ItemLockService`.

**SHELL-005 — App lifetime modes.** During splash+login the app uses `OnExplicitShutdown` (so
closing the modal login can't kill the process before the main window exists). After a successful
login it switches to `OnMainWindowClose`: **closing the main window exits the application** and
closes every owned window (floating due-dates, quick work, search, item windows, …).

**SHELL-006 — Main window defaults.** Title initially `AA`, immediately replaced by
`AA — {AppIdentity}` (SHELL-020). 1280×820 DIP, centred on screen (then overridden by restored
geometry, SHELL-032), icon `AA.ico`. Layout is a `DockPanel`: Menu (top), header bar (top), shortcut
strip (bottom), TabControl (fill, margin 8).

**SHELL-007 — Data load.** `LoadDataAndInitUi()` (`MainWindow.xaml.cs:1173`): re-reads settings,
`DataStore.Load()` (active data file = `CurrentDataFile`), detaches any previous repository (stops
its debounce so it can never write stale data), creates a new `AppRepository`, sets safe mode from
`DataStore.LastLoadFailed`, subscribes `Saved → OnRepoSaved`, initialises every page and restores UI
(SHELL-032/033), refreshes the shared indicator, and sets the status to
`Loaded — {DataStore.CurrentDataFile}` (or the safe-mode text, SHELL-008). Called at startup and after
every reload/import/pull (File ▸ Reload, Import data folder, Drive pulls, shared pulls, Flash Sync
apply, set-shared "use its contents").
Side effect worth preserving knowingly: `LoadSettings()` calls `PasswordService.LoadFrom(...)`,
which **forgets the session's unlocked app password** — every reload re-locks locked text
(per-item unlocks in `ItemLockService` survive).

**SHELL-008 — Read-only safe mode.** If the data file exists but can't be read/parsed/decrypted,
`DataStore.Load()` returns an empty model with `LastLoadFailed = true`. The shell then:
* sets `_safeMode = true` and `_repo.SuspendSaving = true` (all writes suppressed at the repo);
* status text `⚠ Data file unreadable — read-only safe mode (not saving).`;
* shows (after load) the warning `Data file unreadable — safe mode` (text in Appendix A, D1);
* refuses Ctrl+S / File ▸ Save with `Safe mode — not saving` (D4);
* autosave, Ctrl+Z undo-delete, recurrence reconcile, trash prune, daily digest are skipped;
* toggling encryption is refused (D32) and the checkmark reverted;
* **on close nothing is saved or pushed** (tray still disposed, shared sync still stopped).
Imports are still allowed; after an import the repository is replaced and safe mode recomputed
(`MenuImport` explicitly sets `_safeMode = false`).

**SHELL-009 — Newer-schema warning.** If safe mode is off and the file's `SchemaVersion` >
`CurrentSchemaVersion` (=1), show `Newer data format` (D2). Unknown fields are preserved by
`[JsonExtensionData]` so the user may keep working.

**SHELL-010 — Drive re-consent notice.** If Drive is configured but only an old-scope token exists
(`NeedsReconsentForWholeDrive`) and the startup check did not run, show
`Google Drive — one more sign-in needed` (D3). Shown on **every launch** until a Drive action
obtains the new token.

**SHELL-011 — Startup Drive check.** If `SyncOnSave` is on, a client secret is configured and a
current-scope token is cached, run `CheckRemoteNewer(false)` (SHELL-122) — never opens a browser.

**SHELL-012 — Startup shared-save check.** Stamps `_sharedLastSeen` and `_lastSyncedStamp` to the
loaded `LastModified` ("startup state is in sync with the bundle"), starts shared sync (SHELL-123),
and, if a shared file is configured, queues an immediate `CheckSharedFileForUpdate()` at background
priority so a bundle written while this PC was closed is adopted.

**SHELL-013 — Startup housekeeping.** Unless in safe mode, at background priority: enforce Trash
retention (`PruneTrash`: 90 days / 200 items), regenerate missed recurring occurrences
(`ReconcileRecurrences`; if anything spawned, reload the Tasks and Procedures lists), show the daily
digest if due (SHELL-132), and raise a reminder notification if due (SHELL-131).

**SHELL-014 — No crew-expiry popup at startup.** Deliberately removed (PROGRESS "No crew-expiry
popup at startup"). Crew expiries surface passively via the Crew tab badge, on demand via Tools, and
in reminders/digest counts. The Mac must **not** add a startup popup.

### B. Window chrome

**SHELL-020 — Window title.** `AA — {DataStore.AppIdentity}` (em dash, spaces). Updated at load and
after File ▸ Set app identity. Identity defaults to the machine name.

**SHELL-021 — Header bar.** A strip under the menu: background `Panel`, bottom border 1 px `BorderB`,
padding 14,8.
* Left: `AA` (22, bold, `Accent`) and, 14 px right, the tagline
  `• Equipment/Area / Tasks / Procedures with containers, files & relationships` (`Muted`).
* Right, in order: shared-save indicator (SHELL-023), status text (SHELL-022, `Muted`, right margin
  12), then buttons (6 px gaps):
  * `📌 Due` → due-dates window (SHELL-092). Tooltip:
    `Show a small floating window of tasks and procedures due today and tomorrow. (Ship work-order notifications live in each vessel's Work Orders tab.)`
  * `Search (Ctrl+F)` → search window (SHELL-041). No tooltip.
  * `Go to (Ctrl+O)` → quick switcher. Tooltip: `Quick switcher — fuzzy-jump to any item by name, kind or #tag.`
  * `Load` → **Reload from disk** with confirmation (same as File ▸ Reload, SHELL-062). No tooltip.
  * `Save (Ctrl+S)` → save (SHELL-050), `AccentButton` style (bold).

**SHELL-022 — Status line.** A single `TextBlock` (`StatusBlock`) — the app's transient message
channel. The shell writes it for every operation (full catalogue in Appendix A.4). Pages and panels
**also write it** by looking it up by name on their window (`Window.GetWindow(this).FindName("StatusBlock")`
— HierarchyPage, ContainerEditor lock hint, ShipJobsPanel, PortsPanel, SirePage). When such a page is
hosted in a window without a `StatusBlock` (e.g. an ItemWindow), the message is silently dropped.
Each message simply replaces the previous; nothing times out or is logged. Times are local
`HH:mm:ss` (24 h).

**SHELL-023 — Shared-save health indicator.** Hidden unless a shared save file is configured. Font
SemiBold, right margin 12. Tooltip:
`Shared save status. Turns red and stays visible if the shared file goes offline (e.g. a VSAT drop) so you know your edits aren't reaching it yet.`
States (`UpdateSharedIndicator`, `MainWindow.xaml.cs:1666`):
| condition | text | colour |
|---|---|---|
| no shared file | (hidden; both trouble flags and "since" cleared) | — |
| offline (folder/bundle unreachable) | `⚠ Shared save OFFLINE since {HH:mm} — retrying` | `#D45050` |
| push failed (reachable, last write threw), not offline | `⚠ Shared save NOT SAVING since {HH:mm} — last write failed` | `#D45050` |
| healthy, a push/pull succeeded this session | `🔗 Shared synced {HH:mm}` | `#3CA05A` |
| healthy, nothing synced yet this session | `🔗 Shared save on` | `#3CA05A` |
`{HH:mm}` for trouble = when the first of the two trouble signals was raised (`_sharedTroubleSince`);
for synced = the last successful push/pull (`_sharedLastSyncOk`). See SHELL-123..126 for transitions.

**SHELL-024 — Keyboard-shortcuts strip.** Bottom strip: background `PanelAlt`, top border 1 px
`BorderB`, padding 10,3. One line of 11-pt `Muted` text, ellipsis-trimmed, with bold key names:
`⌨  Ctrl+S Save · Ctrl+F Search · Ctrl+N Quick work · Ctrl+O Go to (quick switcher) · Ctrl+R Due-dates window · Ctrl+1…9 Switch tab · F2 Rename · Ctrl+Z Undo delete`
(separators are `   ·   `; the glyph `⌨` and each key combo bold, descriptions regular). A right-docked
`✕` button (22×20, transparent, no border, `Muted`, hand cursor) hides it; tooltip
`Hide this shortcuts strip (View ▸ Shortcut bar to bring it back).` Visibility is persisted in
`UiState.ShowShortcutBar` (default **true**) and mirrored by the checkable View ▸ Shortcut bar item.
Hiding/showing calls `MarkDirty()`.

**SHELL-025 — Tab strip (13 tabs).** Default order, internal **name (persisted key)** → header → page:
| # | name (key) | header | page |
|---|---|---|---|
| 1 | `TabEquipment` | `Equipment/Area` | HierarchyPage (kind Equipment) |
| 2 | `TabTasks` | `Tasks` | HierarchyPage (Task) |
| 3 | `TabProcedures` | `Procedures` | HierarchyPage (Procedure) |
| 4 | `TabVessels` | `Vessels` | HierarchyPage (Vessel) |
| 5 | `TabCalendar` | `Calendar` | CalendarPage |
| 6 | `TabBoard` | `Board` | BoardPage |
| 7 | `TabPlanner` | `Planner` | PlannerPage |
| 8 | `TabMap` | `Relationship Map` | RelationshipMapPage |
| 9 | `CrewTab` ⚠ note the different naming pattern | `Crew` / `Crew  ⚠ {n}` | CrewPage |
| 10 | `TabLists` | `Saved Lists` | SavedListsPage |
| 11 | `TabBuckets` | `Buckets` | BucketsPage |
| 12 | `TabPorts` | `Ports` | PortsPage |
| 13 | `TabSire` | `SIRE 2.0` | SirePage |
The names are **data keys** (`UiState.TabOrder`, `UiState.TabColors`) and must be reproduced exactly,
including `CrewTab`. Tab header style: see SHELL-155 (TabItem). All pages are created at window
construction (not lazily), except that SIRE parses its 3.2 MB bank on first activation.

**SHELL-026 — Refresh on tab activation.** When the *main* tab selection changes (the handler
ignores bubbled `SelectionChanged` from inner controls), the newly selected page is refreshed:
Calendar → `Refresh()`, Board → `Refresh()`, Planner → `Refresh()`, Relationship Map →
`RefreshSidebar()`, Crew → `Refresh()`, Saved Lists → `Refresh()`, Buckets → `Refresh()`, Ports →
`Refresh()`, SIRE → `EnsureLoaded()` (lazy parse of the embedded bank). The four hierarchy pages are
not refreshed on activation.

**SHELL-027 — Selected tab persisted.** On every user tab change (not while restoring),
`UiState.SelectedMainTabIndex = MainTabs.SelectedIndex` (index in **current display order**) — set in
memory only (no `MarkDirty`; it is written with the next save). `CaptureUiState` also writes it.
Restored at load if within range (see WIN-BUG in SHELL-032).

**SHELL-028 — Drag a tab to reorder.** Press on a tab header, move beyond the system minimum drag
distance, drop on another tab header → the dragged tab is removed and re-inserted **at the target's
index** (computed before removal), then selected, and the order is persisted as
`UiState.TabOrder = [tab names in display order]` + `MarkDirty()`. Dropping on itself, on non-header
content, or cancelling does nothing. Only headers start a drag (content clicks don't resolve to a
`TabItem` ancestor). Order is re-applied at every load (`ApplyTabOrder`, SHELL-3.x): listed names
first (unknown names ignored, duplicates ignored), then every unlisted tab in its current relative
order — so tabs added by future versions appear at the end.
The whole TabControl carries the tooltip `Tip: drag a tab to reorder it.` (WPF shows it when
hovering any part of the tab area or page that has no tooltip of its own).

**SHELL-029 — Custom tab colours.** View ▸ `🎨 Customize tab colors...` opens a modal
`TabColorsWindow` (title `Customize tab colors`, 480×560, centred on owner):
* Intro text (`Muted`, wrapped):
  `Pick a background colour for each main tab. The active tab keeps its colour with an accent underline. 'Default' restores the theme colour.`
* A scrolling list, one row per tab **in current display order**, label = tab header (for `CrewTab`
  always `Crew`, never the badge text), 190 px wide, ellipsis; a 46×24 swatch (radius 4, 1 px
  `BorderB`) showing the colour, or `Panel` fill with a centred `default` (10 pt `Muted`) when none;
  `Pick...` (opens the Windows colour dialog, full-open, pre-set to the current colour; alpha is
  **dropped** — stored as `#RRGGBB`, uppercase hex); `Default` (removes this tab's entry).
* Bottom: `Reset all` (left; clears every entry in the working copy), `Cancel` (90), `Apply` (90,
  bold, default button).
* Apply → `UiState.TabColors = result` (only tabs with a colour appear), `MarkDirty()`, re-apply.
  Cancel/close → nothing changes.
* Applying (`ApplyTabColors`): for each tab with a parseable colour, header background = that colour,
  header text = **black if 0.299R+0.587G+0.114B > 150 else white** (alpha ignored). Tabs without an
  entry (or with an unparseable one) revert to the theme (`Panel` background, `Fg` text). The active
  tab keeps its custom colour and is marked by the bold weight + 3 px `Accent` underline + `Accent`
  border (SHELL-155).
* Custom colours are **theme-independent** (same hex in light and dark).

**SHELL-030 — Crew tab badge.** Header = `Crew` when `CrewPg.ExpiringCount == 0`, else
`Crew  ⚠ {n}` (two spaces before ⚠). `ExpiringCount` = crew whose `DaysUntilSignOff(today) ≤ 60`
(overdue included; members without a parseable sign-off date excluded). Updated whenever the crew
page raises `Changed` (import, edit, delete, clear), after every page init, and after a Crew restore
from Trash/undo. The badge is **not** refreshed by a day rollover while the app stays open.

**SHELL-031 — Tab-area hint tooltip.** The TabControl's tooltip `Tip: drag a tab to reorder it.`
(see SHELL-028). In WPF it also appears over any page area without its own tooltip; on Mac attach it
to the section list/tab strip only.

**SHELL-032 — Window geometry persistence.** Captured by `CaptureUiState()` on every explicit save,
every dirty autosave, every shared push, before exports and on close:
* only while `WindowState == Normal`: `WindowLeft`, `WindowTop`, `WindowWidth`, `WindowHeight`
  (DIP, outer frame; so a maximised window keeps its last normal bounds);
* always: `WindowState` = `"Normal"`/`"Maximized"`/`"Minimized"`.
Restored in `InitPagesAndRestoreUi` (every load/reload/import): width/height only if `> 200`;
left/top whenever present (**no clamping to visible screens**); state parsed with case-sensitive
`Enum.TryParse` (numeric strings like `"2"` parse too); `Minimized` restores as `Normal`.
Because this runs on every reload, pulling a shared/Drive bundle or importing a file **moves the
window to the geometry stored in the incoming file** (see section 8, W-7).

**SHELL-033 — Per-page UI state.** Also captured/restored through `UiState`:
`SelectedEquipmentId`, `SelectedTaskId`, `SelectedProcedureId`, `SelectedVesselId` (each page
re-selects by id), `CalendarSelectedDate`, `CalendarViewMode` (`"Day"|"Week"|"Month"|"All"|"Agenda"`),
`MapFocusedItemId`. Pages own other keys (see section 4.1).

### C. Keyboard

**SHELL-040 — Ctrl+S Save.** `ApplicationCommands.Save` bound on the main window → `DoSave()`
(SHELL-050). Also File ▸ Save and the header button.

**SHELL-041 — Ctrl+F Search.** → opens a **new** non-modal `SearchWindow` (owner = main) every time
(multiple can be open). Also header `Search (Ctrl+F)`.

**SHELL-042 — Ctrl+N Quick work.** → single-instance non-modal `QuickWorkWindow` (title
`Quick work — all tasks & procedures`); if already open, activate it. Also Tools menu.

**SHELL-043 — Ctrl+O Go to.** → modal `QuickSwitcherWindow` (title `Go to item`); navigates via
`NavigateToItem`. No-op if no repository. Also Tools menu and header `Go to (Ctrl+O)`.

**SHELL-044 — Ctrl+R Due-dates window.** `NavigationCommands.Refresh` → open (or activate +
`Refresh()`) the single-instance floating due-dates window. (History: binding it to the nonexistent
`ApplicationCommands.Refresh` crashed startup — the reason SHELL-001 exists.)

**SHELL-045 — Ctrl+1…9 switch tab.** In `PreviewKeyDown` (runs before any control): Ctrl (any other
modifiers also allowed) + `1`–`9` on the main row **or numpad** selects the Nth tab in current display
order, if it exists, and marks handled. Works **even while typing in a text box**. Tabs 10–13 have no
shortcut.

**SHELL-046 — F2 Rename.** If no text input has focus and the active tab hosts a HierarchyPage,
call `BeginRename()` (focus the item's Name box and select all; no-op if nothing selected). Other
tabs: ignored.

**SHELL-047 — Ctrl+Z Undo delete.** If Ctrl+Z is pressed while **no** `TextBoxBase` (TextBox,
RichTextBox, editable ComboBox text, DatePicker text) or `PasswordBox` has focus: `UndoDelete()`,
always marked handled. With a text control focused, Ctrl+Z is left to that control's own text undo.
`UndoDelete` (safe-mode/no-repo → no-op): count = `PendingUndoCount()`; restore the newest Trash entry,
or **the whole batch** it belongs to (`BatchId`); refresh each affected page (Equipment/Task/
Procedure/Vessel lists, or Crew page + badge); synchronous `Save()`; status
`Restored {n} deleted items (Ctrl+Z).` (n>1) or `Restored the last deleted item (Ctrl+Z).`; empty
Trash → `Nothing to undo.` Because it reads the persisted Trash, Ctrl+Z works **across restarts**.
There is no redo.

**SHELL-048 — Shortcut interplay.** Window-level key bindings only exist on the **main window**:
in secondary windows (item windows, quick work, search…) Ctrl+S etc. do nothing. When the rich-text
editor has focus, WPF's own editing gestures win for keys it binds — notably **Ctrl+R = align right**
(so the due-dates window does not open), Ctrl+E/L/J alignments, Ctrl+B/I/U. Dialogs: Enter triggers
the default button (`IsDefault`), Esc only where a button has `IsCancel` (DiffWindow, DateCalculator,
CrewTable, ContainerViewer, InsertSavedList, ListStylePrompt, QuickCardEditor) and in the quick
switcher. **There is no Ctrl+W** anywhere (PROGRESS claims "Esc/Ctrl+W close tool windows" — not
implemented).

### D. Save / autosave / persistence orchestration

**SHELL-050 — Explicit save (`DoSave`).** Safe mode → D4 and stop. Otherwise flush the four
hierarchy pages' editors, `CaptureUiState()`, `_repo.Save()` (synchronous: stamps
`LastModified = DateTime.Now`, serialises, chains the write after pending background writes, waits
≤ 15 s, throws on failure/timeout and keeps the data dirty), status `Saved {HH:mm:ss}`, then
`MaybeQueueSync()` (SHELL-121). On exception: error box `Save failed` with the message (no owner).
(Note: this path does **not** flush detached item windows or the SIRE body, although PROGRESS implies
`FlushAllEditors` is used — see W-9.)

**SHELL-051 — Debounced model autosave (repository).** Every edit calls `MarkDirty()` → restarts a
**750 ms** timer → on tick: stamp `LastModified = Now`, clear dirty, serialise on the UI thread,
write on a background thread through an ordered write chain; on failure restore the stamp and the
dirty flag; on success raise `Saved`. Rich-text editors debounce their own serialisation at 400 ms
before calling `MarkDirty()`. Consequence: `IsDirty` is usually false within ~0.75 s of the last edit
(matters for SHELL-052/124).

**SHELL-052 — 5-minute autosave timer.** Every 5 min: `DoAutosave()` then `CheckRemoteNewer(false)`.
`DoAutosave`: return if no repo or safe mode; flush the four hierarchy editors; if not dirty → status
`Autosave — no changes ({HH:mm:ss})`; else `CaptureUiState()`, `Save()`, status `Autosaved {HH:mm:ss}`;
exception → status `Autosave failed: {message}`.

**SHELL-053 — `CaptureUiState()`** — see SHELL-032/033; also writes `SelectedMainTabIndex`.

**SHELL-054 — Editor flushing & detached item windows.** `FlushAllEditors()` flushes the four
hierarchy pages, the SIRE question body, and every open ItemWindow (all exceptions swallowed). Used by:
shared push/tick/pull, Flash Sync, opening an item window, set-shared, and close. The shell keeps a
registry `Dictionary<Guid, ItemWindow>` of items open in their own window:
* opening an already-open item activates its window; otherwise flush all, create
  `ItemWindow(repo, item)` owned by main, `page.DetachItem(id)` (main pane unbinds its editor and
  shows "This item is open in its own window"), show it;
* window `NameChanged` → `page.ReloadList()`; window `Closed` → remove from registry,
  `page.ReattachItem(id)`;
* items deleted on a page → their windows `GoOrphaned()` (stop writing) and close;
* after any reload every window gets `SetRepo(newRepo)` (re-resolves its item by Id; orphaned if gone);
* on close: flush + close each window before the final save.
Handlers are re-assigned (not added) on every page init so one click never opens several windows.

**SHELL-055 — Recurrence after save.** On every repository `Saved`: unless re-entrant/safe mode,
`ReconcileRecurrences()`; if it spawned occurrences, reload the Tasks and Procedures lists at
background priority.

**SHELL-056 — Close / Exit.** Triggered by the ✕, Alt+F4 or File ▸ Exit (`Close()`); no
confirmation, cannot be cancelled. `OnClosing`:
1. stop shared sync (timers + watcher) so our own final write doesn't trigger a reload;
2. dispose the tray icon;
3. safe mode → stop here (nothing written);
4. flush + close every item window (errors swallowed), clear registry;
5. `FlushAllEditors()`; `CaptureUiState()`; `_repo.Save()` — **errors ignored**;
6. if a shared file is set: push synchronously (`PushToShared("Shared save (on close)")`) when the
   bundle does not exist, or exists **and** its stamp is readable **and** (local stamp is null or
   local ≥ bundle stamp). An existing-but-unreadable bundle (mid-write) is never overwritten.
   (WIN-BUG W-5: step 5 has just re-stamped local to "now", so the ≥ test is almost always true.)
Then the process exits (owned windows close with the main window).

### E. File menu

(Headers show the WPF access-key letter as `_`; tooltips verbatim. Mac titles in section 6.4.)

**SHELL-060 — `_Save`** (gesture text `Ctrl+S`) → SHELL-050.

**SHELL-061 — `Save _As...`** → Save dialog (filter `AA data (*.json)|*.json|All files (*.*)|*.*`,
default name `aa-data.json`, initial folder = AppFolder). On OK: `CaptureUiState()`,
`Data.LastModified = DateTime.Now`, `DataStore.SaveTo(data, path)` (plain JSON, never encrypted,
atomic write, paths normalised), status `Exported to {path}`. Does **not** change the active data file
or the dirty flag. Error → `Save As failed`.

**SHELL-062 — `_Reload from disk`** (also header `Load`) → confirm `Reload data from disk? Unsaved
changes will be lost.` (title `Confirm reload`, Yes/No, warning) → `LoadDataAndInitUi()` → status
`Reloaded {HH:mm:ss}`. Pending editor buffers are deliberately not flushed first.

**SHELL-063 — `_Import from file...`** → Open dialog (JSON filter, initial folder AppFolder) →
`DataStore.LoadFrom(path)` (error → `Import failed`) → review gate (SHELL-120) with source name = file
name → detach old repo, new repo from the imported data, `_safeMode=false`, hook `Saved`,
`InitPagesAndRestoreUi()`, **make that file the active data file** (`SetCurrentDataFile`, persisted in
settings — future saves and launches use it), write it (`DataStore.Save`), status
`Loaded — {CurrentDataFile}`. Error → `Import failed`.

**SHELL-064 — `_Trash (restore deleted items)...`** → modal TrashWindow (owned by another spec);
its `Restored(type)` events call `RefreshAfterRestore(type)`. Tooltip:
`Restore items you deleted, or remove them for good. Deletes go here instead of vanishing — Ctrl+Z undoes the last one.`

**SHELL-065 — `Encr_ypt local data file (this PC)`** (checkable; initial = `EncryptLocalData`).
Tooltip: `Encrypt this PC's data file at rest with Windows DPAPI (tied to your Windows account). Shared, exported and Google Drive copies stay portable plaintext, so sync between machines is unaffected.`
Click (checkmark already toggled): safe mode → revert + D32. Turning **on** asks D33 (OK/Cancel;
Cancel → uncheck). Turning off: no confirmation. Then `SetEncryptLocalData(on)`,
`Data.LastModified = Now`, `DataStore.Save(data)` (rewrites the active file in the new form; only files
under AppFolder are ever encrypted), status `Local data file is now encrypted at rest.` /
`Local data file is now plaintext.` Error → revert checkmark to the stored setting + `Encrypt local
data file failed`.

**SHELL-066 — `Set s_hared save file...`** Tooltip:
`Use ONE save file at a location you choose (e.g. a network drive or a synced folder). AA autosaves there every 10 minutes and auto-reloads when another copy of AA updates it — point every PC at the same file to keep them in sync.`
(stale: the real cadence is 1 minute, see W-2). Save dialog: title
`Choose the single shared save file (put it on a network drive or synced folder). It bundles your data AND attachments.`,
filter `AA shared save (*.zip;*.aaz)|*.zip;*.aaz|All files (*.*)|*.*`, name `aa-shared.zip`,
**no overwrite prompt**. Then `FlushAllEditors()`:
* file exists → D28 (Yes/No/Cancel). Cancel → nothing. Otherwise persist the path; **Yes** =
  `ImportSharedBundle(path)` + `LoadDataAndInitUi()` + both stamps = loaded `LastModified`;
  **No** = `PushToShared("Shared save")` (overwrite it with ours).
* file absent → persist the path, `PushToShared("Shared save")` (create it).
Then `StartSharedSaveSync()`, status `Shared save file set — {path}`, info D29. Any exception →
clear the shared path + `Set shared save file failed`.

**SHELL-067 — `Stop shared save file`.** Tooltip `Go back to saving locally on this PC only.`
None set → status `No shared save file is set.` Else confirm D31 → stop sync, clear the setting, hide
indicator, status `Stopped using the shared save file (now saving locally).` Local data is kept.

**SHELL-068 — `Set app _identity...`.** Tooltip:
`Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save. Always editable; defaults to the PC name.`
Opens PromptWindow (title `App identity`, prompt P2, initial = current identity). OK →
`SetAppIdentity(value)` (trimmed; blank → machine name), title updated, status
`App identity set: {identity}`.

**SHELL-069 — `Open data _folder`** → opens AppFolder in Explorer. Error → message box titled
`Open failed` (message only, no icon).

**SHELL-070 — `_Export data folder (ZIP)...`** → Save dialog (filter
`AA bundle (*.zip)|*.zip|AA bundle (*.aaz)|*.aaz|All files (*.*)|*.*`, name `aa-data-{yyyyMMdd-HHmm}.zip`)
→ `CaptureUiState()`, `Save()`, `ExportFolderToZip(path)` (honours text-only; refuses a destination
inside AppFolder: `Choose a destination outside the AA data folder.`), status
`Exported data folder to {path}`. Error → `Export failed`. (Editors are not flushed first — W-9.)

**SHELL-071 — `I_mport data folder (ZIP)...`** → Open dialog (filter
`AA bundle (*.zip;*.aaz)|*.zip;*.aaz|All files (*.*)|*.*`) → `PeekZipData` → review gate (source =
file name) → `ImportBundleSmart(path)` (keeps settings/password/Google state; recognises text-only
bundles) → `LoadDataAndInitUi()` → status
`Imported {file} (text only — your attachments are untouched)` or `Imported {file} (with attachments)`.
Error → `Import failed`.

**SHELL-072 — `Export _text only (no attachments)`** (checkable). Tooltip:
`When on, exports and Google Drive saves carry only your text, changes and formatting — not the attached files. Much smaller and far quicker over a slow link. Importing one leaves the attachments already on the other PC exactly as they are.`
Persists `TextOnlyExport`; status `Exports carry text only (no attachments)` /
`Exports carry everything, attachments included`. Governs every bundle export (ZIP export, Drive
synced-folder copy, OAuth upload, Drive sync-on-save, shared save).

**SHELL-073 — `Save a copy to Google _Drive (synced folder)`.** Tooltip:
`Save a timestamped backup ZIP into your Google Drive desktop folder, which syncs it to the cloud.`
Resolve folder (SHELL-074 logic, no forced pick) → flush the four editors, `CaptureUiState()`, `Save()`
→ create `{folder}/AA Backups/` → write
`aa-data-{SafeIdentity(AppIdentity)}-{yyyyMMdd-HHmmss}.zip` → status
`Saved a copy to Google Drive: {zip}` + info D16. Error → `Save to Google Drive failed`.

**SHELL-074 — `Set Google Drive folde_r...`.** Tooltip:
`Choose which local folder is your Google Drive (the one Google Drive for desktop syncs).`
`ResolveDriveFolder(forcePick)`: unless forced, use the remembered folder if it exists, else
auto-detect (`~/My Drive`, `~/Google Drive`, `~/GoogleDrive`, then `X:\My Drive` on every drive) and
remember it. Otherwise show D25 then a folder browser (`Select your Google Drive folder`); a chosen
existing folder is remembered, status `Google Drive folder set: {path}`. Cancel → null (caller stops).

**SHELL-075 — `Upload backup to Google Drive (O_Auth)...`.** Tooltip:
`Upload a backup directly to Google Drive via the Drive API (no desktop client needed). Requires a Google OAuth client.`
Not configured → D20 (Yes/No); Yes → SHELL-077 flow; still not configured → stop. Then flush,
capture, `Save()`, temp zip `%TEMP%/aa-data-{yyyyMMdd-HHmmss}.zip` (no identity in the name — W-3),
status `Signing in to Google and uploading… (a browser window may open)`, upload (Drive folder
`AA Backups`, identity in appProperties), status `Uploaded to Google Drive: {name}` + D21. Error →
status `Google Drive upload failed.` + `Google Drive upload failed` box. Temp file always deleted.

**SHELL-076 — `_Load backup from Google Drive (OAuth)...`.** Tooltip:
`Download a backup from your Google Drive and (after a newer/older check) replace your current data with it.`
Config check as above → status `Signing in to Google and listing backups… (a browser window may open)`
→ list; none → status `No backups found on Google Drive.` + D23 → single-select picker titled
`Choose a backup to load from Google Drive (newest first)` (rows `{name}    (uploaded yyyy-MM-dd HH:mm)`)
→ status `Downloading {name}…` → temp `aa-drive-{yyyyMMddHHmmss}.zip` → review gate (source
`Google Drive: {name}`; cancel → status `Load from Google Drive cancelled.`) →
`ImportBundleSmart` → `LoadDataAndInitUi()` → status
`Loaded backup from Google Drive: {name}` + ` (text only — attachments unchanged).` or
` (with attachments).` Error → status `Load from Google Drive failed.` + box of the same title.

**SHELL-077 — `Set Google OAuth _client (client_secret.json)...`.** Tooltip:
`Load the client_secret.json you downloaded from Google Cloud Console (OAuth 'Desktop app' client).`
Open dialog (title `Select the OAuth client_secret.json downloaded from Google Cloud Console`, filter
`Google client secret (*.json)|*.json|All files (*.*)|*.*`) → copy to
`AppFolder/google_client_secret.json` → status `Google OAuth client set.` + D18. Error →
`Set OAuth client failed`.

**SHELL-078 — `Sign out of _Google`.** Tooltip `Forget the cached Google sign-in for OAuth uploads.`
Deletes the token cache; status `Signed out of Google (OAuth token cleared).` No confirmation.

**SHELL-079 — `_Sync to Google Drive on save`** (checkable). Tooltip:
`When on, Ctrl+S also pushes your data to Google Drive (OAuth), and the app checks for a newer save pushed from other PCs.`
Persists `SyncOnSave`. On → status `Google Drive sync on save: ON`; if not configured → D8, else
`CheckRemoteNewer(true)`. Off → status `Google Drive sync on save: OFF`.

**SHELL-080 — `C_heck Google Drive for newer save`** → `CheckRemoteNewer(true)`. Tooltip:
`Ask Google Drive whether a newer save state exists, and offer to load it.`

**SHELL-081 — `Flash S_ync with iPhone (QR)...`.** Tooltip:
`Transfer your text, changes and formatting to or from the iPhone app by flashing QR codes on screen — no network, no cable, no Wi-Fi. Attachments are not included.`
Flush all editors; if dirty, `Save()` (errors ignored); modal FlashSyncWindow; its `DataApplied`
event → `LoadDataAndInitUi()` + status `Applied changes received from the iPhone`.

**SHELL-082 — `E_xit`** → `Close()` → SHELL-056.

Menu separators (in order): Save, Save As | Reload, Import | Trash, Encrypt | Set shared, Stop shared,
Set identity | Open folder, Export ZIP, Import ZIP, Text only | Save to Drive, Set Drive folder |
Upload OAuth, Load OAuth, Set OAuth client, Sign out | Sync on save, Check newer | Flash Sync | Exit.

### F. Tools menu

**SHELL-090 — `_Folder builder...`** → modal FolderBuilderWindow. Tooltip:
`Bulk-create a folder structure (with subfolders) at a location of your choice.`
**SHELL-091 — `Date _calculator...`** → modal DateCalculatorWindow. Tooltip:
`Find the range between two dates, or add/subtract days from a date.`
**SHELL-092 — `Floating _due-dates window`** → open/activate+refresh the single floating window
(title `Overdue, today & tomorrow`; borderless, topmost, resizable 350×480 min 260×220; owned by
another spec). Constructed with `NavigateToItem` and `NavigateToCrew`; closed → reference cleared.
Tooltip: `Show a small always-on-top window of items due today and tomorrow.`
**SHELL-093 — `Quick _work window (Ctrl+N)`** → SHELL-042. Tooltip:
`Big window: all tasks & procedures on the left (active first), a comprehensive builder on the right.`
**SHELL-094 — `Quick s_witcher (Ctrl+O)`** → SHELL-043. Tooltip:
`Fuzzy-jump to any item by name, kind or #tag — Obsidian-style. Type, then Enter.`
**SHELL-095 — `_Activity log...`** → new non-modal ActivityLogWindow each time. Tooltip:
`UTC-timestamped log of every entry added and removed.`
**SHELL-096 — `U_nit converter...`** → new non-modal UnitConverterWindow each time. Tooltip:
`Convert maritime units — speed, distance, pressure, temperature, volume, mass and more.`
**SHELL-097 — `Import COMPAS _crew (.xlsx)...`** → select the Crew tab, `CrewPg.ImportCompas()`.
Tooltip: `Import a COMPAS crew report and keep each member as an info card; tracks contract sign-off expiries.`
**SHELL-098 — `Check crew contract e_xpiries`** → select the Crew tab,
`CrewPg.CheckExpiries(interactive: true)`: none → info `No crew contracts are overdue or due within 60 days.`;
else warning `{n} crew contract(s) overdue or due within 60 days:\n\n` + one line per member, soonest
first: `  •  {FullName}  ({rank})  —  {SignOffDate}  [{when}]` where when = `OVERDUE by {d}d` /
`signs off TODAY` / `in {d}d`; title `Contract expiries`. Tooltip:
`List crew whose contracts (sign-off dates) are due soon or overdue.`
**SHELL-099 — `SIRE 2.0 e_xport...`** → `SirePg.ShowExportDialog()`. Tooltip:
`Export SIRE inspection data (checklist, tasks, status report, and more) to a text file or the clipboard.`
**SHELL-100 — `Set _Gemini API key...`** → PromptWindow (title `Gemini API key`, prompt P1,
initial = current key **shown in clear text**) → `SetGeminiApiKey` (trimmed; blank clears) → status
`Gemini API key cleared.` / `Gemini API key saved.` Tooltip:
`Set your Google Gemini API key to enable AI task suggestions on the SIRE tab. Stored locally, never committed.`
**SHELL-101 — `Set / change _password...`** → PasswordWindow in `ChangeExisting` mode if an app
password exists, else `SetNew` (SHELL-161). **The old password is not asked for.** OK with a
non-empty password → `PasswordService.SetPassword(pw)` (new PBKDF2 hash/salt, session unlocked with
it) → `SavePasswordSettings(hash, salt)` → status `App password updated.`
**SHELL-102 — `_Lock now`** → `PasswordService.Lock()`, `ItemLockService.RelockAll()`, status
`Locked. Locked containers and entries will require re-unlocking.`, then `RelockCurrent()` on the four
hierarchy pages (re-gate the current selection in place). Tooltip:
`Forget the unlocked password for this session. Any open locked container will require re-unlock.`
Separators: after Unit converter; after Check expiries; after Set Gemini.

### G. View menu

**SHELL-110 — `🌙 _Dark mode`** (checkable; initial = `DarkMode`). Tooltip:
`Switch between the light and dark theme (remembered across launches).` → `SetDarkMode(checked)`,
`ThemeManager.Apply(checked)` (live, no restart), status `Dark mode on.` / `Dark mode off.`
**SHELL-111 — `⌨ _Shortcut bar`** (checkable) → SHELL-024. Tooltip:
`Show/hide the keyboard-shortcuts reminder strip at the bottom of the window.`
**SHELL-112 — `🎨 _Customize tab colors...`** → SHELL-029. Tooltip:
`Give each main tab its own background colour (remembered across launches).`

### H. About

**SHELL-115 — `_About`** is a **top-level menu item without a submenu**; clicking it shows an
information box titled `About AA` reading `Created by B.E.P. Avida - May 2026` (note: the splash says
`B.E.P Avida` without the final period — keep each as is).

### I. Sync orchestration (lives in the shell)

**SHELL-120 — Import review gate.** Every overwrite path (Import from file, Import ZIP, Load Drive
backup, automatic Drive pull) calls `ReviewAndConfirmImport(incoming, incomingLast, sourceName)`:
if `incoming` is null (preview unreadable) → plain Yes/No D15; else build
`DataDiff.Compare(current, incoming)` + `AgeVerdict(incomingLast, current.LastModified)` and show the
modal DiffWindow (`Review changes before importing`; buttons `Import (overwrite)` / `Cancel`). Returns
true only on confirm. `AgeVerdict` text: section 3, SHELL-120 logic. (Shared-save pulls do **not** use
this gate — they use SHELL-125's prompt or are silent.)

**SHELL-121 — Drive push on explicit save.** After a successful `DoSave` only (never after
autosave): if `SyncOnSave` ∧ configured → (re)start a 1.5 s debounce → `RunSyncPush()`: single
flight with coalescing (a request during a push sets a "queued" flag and the loop runs again), status
`Syncing to Google Drive…`, export a temp zip on a thread-pool thread
(`%TEMP%/aa-sync-{guid:N}.zip`, text-only honoured), `PushSyncAsync(temp, stamp)` (rolling file
`AA Sync/AA-sync.zip`, data stamp in appProperties), `_lastSeenRemote = stamp`, status
`Synced to Google Drive {HH:mm:ss}`; error → status `Drive sync failed: {message}`. Temp deleted.

**SHELL-122 — Drive newer-save check (`CheckRemoteNewer(interactive)`).** Runs at startup
(non-interactive, SHELL-011), every 5-min autosave tick (non-interactive), when sync is switched on
(interactive), and from File ▸ Check (interactive). Full algorithm in section 3.

**SHELL-123 — Shared save: start/stop.** `StartSharedSaveSync()` (after stopping any previous):
nothing if no path. Otherwise: push timer **1 min** → `SharedSaveTick`; poll timer **60 s** →
`CheckSharedFileForUpdate`; debounce timer **1.5 s** (not started); a `FileSystemWatcher` on the
bundle's directory filtered to the bundle's file name (LastWrite | Size | FileName | CreationTime;
Changed/Created/Renamed each restart the debounce) — best-effort, the poll is the reliable path;
then `UpdateSharedIndicator()`. `StopSharedSaveSync()` stops/disposes all four.

**SHELL-124 — Shared save periodic push.** `SharedSaveTick` (every minute; skipped with no repo/path
or while a pull is being handled): first `CheckSharedFileForUpdate()` (adopt a newer bundle before
overwriting), then `FlushAllEditors()`, then **only if `IsDirty`** → `PushToSharedBackground("Shared save")`
(WIN-BUG W-4: with the 750 ms repo autosave, `IsDirty` is almost never true at tick time).
`PushToSharedBackground`: guard against overlap; flush, capture, `Save()` (UI thread), export
data+attachments to `{path}.{guid:N}.tmp` **on a background thread**, then atomically rename over the
bundle (UI thread), `_sharedLastSeen = _lastSyncedStamp = LastModified`, status
`Shared save written {HH:mm:ss} (data + attachments).` (text unchanged even when text-only is on),
`SetSharedOnline(true)`. Error → status `Shared save failed: {message}`, `SetSharedPushFailed()`. Temp
removed.

**SHELL-125 — Shared save pull (`CheckSharedFileForUpdate`).** Every 60 s, 1.5 s after watcher
bursts, at startup, and at the start of every push tick. Algorithm in section 3. Conflict prompt D27
(Yes = reload, No = keep mine). Silent reload when there are no unsynced local changes. Status on
success `Reloaded the shared save{ from “{identity}”} ({HH:mm:ss}).`; on failure
`Shared reload skipped (busy): {message}` (local data untouched because the importer validates in a
temp folder first).

**SHELL-126 — Shared save synchronous push (`PushToShared`).** Same as SHELL-124's push but fully
synchronous; used when setting the shared file and on close (label `Shared save (on close)`).

### J. Reminders

**SHELL-130 — Tray icon.** A Windows notification-area icon (`AA.ico`, tooltip text `AA`) is created
at load and **always visible while AA runs**; no context menu. Balloon click → open the due-dates
window; double-click → `Show()` + `Activate()` the main window. Disposed on close. Best-effort: if it
fails, reminders are silently disabled.

**SHELL-131 — Periodic reminder.** At startup and every **30 min**: `CheckReminders(force:false)`.
Compute `ReminderService.Compute(repo, DateTime.Today)` (overdue / due today / due within the next 7
days over not-done tasks & nested subtasks, procedures, procedure steps, crew checklist steps — by
**deadline date**, work orders excluded) and `crew = CrewPg.ExpiringCount`. Nothing (all zero) →
reset the dedup key, no balloon. Dedup key `{yyyy-MM-dd}|{overdue}|{today}|{week}|{crew}`; unchanged →
no balloon (unless forced). Balloon: 8 s, title `AA — due soon`, text = `Headline()` (`{n} overdue`,
`{n} due today`, `{n} due this week`, joined with `  ·  `; or `Nothing due.`) plus
`  ·  {crew} crew contract(s) expiring` when crew > 0; info icon.

**SHELL-132 — Daily digest.** Once per calendar day per data file, at startup only (not at a
midnight rollover): if `UiState.LastDigestDate` ≠ today (`yyyy-MM-dd`, local): set it, `MarkDirty()`;
if anything is due or crew are expiring → open the due-dates window and force a balloon.
(`LastDigestDate` lives in data.json, so a shared-save pull from another PC that already showed its
digest today suppresses this PC's digest — see W-8.)

**SHELL-133 — Crew expiry surfaces.** Threshold `CrewPage.WarnDays = 60` days (overdue included).
Surfaces: Crew tab badge (SHELL-030), Tools ▸ Check crew contract expiries (SHELL-098), reminder/
digest count (SHELL-131/132), and COMPAS import reports (crew spec). No startup popup (SHELL-014).

### K. Navigation

**SHELL-140 — `NavigateToItem(item)`** (passed to Search, Quick switcher, Quick work, Floating
window, Calendar, hierarchy pages, Buckets, SIRE): maps kind → **fixed tab index** (Equipment 0,
Task 1, Procedure 2, Vessel 3, other → 0) and page, sets `SelectedIndex`, then at background
priority `page.SelectItemById(id)`. WIN-BUG W-6: with a custom tab order the index lands on the wrong
tab (the right page still gets the selection, invisibly).

**SHELL-141 — `NavigateToCrew(member)`** → select `CrewTab` (by reference, order-safe), then
(background) `CrewPg.SelectMember(m)` (clears crew filters so the member is visible).

**SHELL-142 — `RefreshAfterRestore(type)`** — `"Equipment"|"Task"|"Procedure"|"Vessel"` → that
page's `ReloadList()`; `"Crew"` → `CrewPg.Refresh()` + badge.

**SHELL-143 — Open in own window** — SHELL-054.

**SHELL-144 — `RefreshHierarchyPages()`** → `ReloadList()` on all four hierarchy pages; given to the
SIRE page so quick-added items appear.

### L. Theme & visual language

**SHELL-150 — Theme tokens.** 11 swappable brushes + 2 fixed editor brushes (full table in 6.6 and
Appendix B). Light theme is **pure monochrome** (white surfaces; black text, accents, "muted" text
and borders); dark theme is a VS-Code-like charcoal palette with white accent.

**SHELL-151 — Live switching.** `ThemeManager.Apply(dark)` replaces the brush resources; every view
binds via `DynamicResource`, so the whole app (all open windows) re-themes instantly without restart.
`ThemeManager.IsDark` is set but not read anywhere else.

**SHELL-152 — System-colour overrides (dark only).** In dark mode the 15 WPF `SystemColors` brush
keys used by default templates are overridden (Window/Control/Menu/Info/Highlight/GrayText/
ControlLight/ControlLightLight/ControlDark/WindowFrame…); in light mode the overrides are **removed**
so native light system colours return (mapping table in section 3).

**SHELL-153 — Fixed "paper" editor surface.** Rich-text documents always render on `EditorBg
#FCFCFC` with default ink `EditorFg #1A1A1A` in **both** themes, so user-applied colours and highlights
stay readable. The editor's toolbar, file bank and chrome follow the theme. "Clear formatting" resets
to `EditorFg`.

**SHELL-154 — Font.** `MainFont = Consolas`, applied to TextBlock, TextBox, PasswordBox, Button,
ListBox/ListView/TreeView(+items), GridView headers, ComboBox, CheckBox, RadioButton, DatePicker
(+text), ToolTip, TabItem (header), Menu, MenuItem, ContextMenu. The implicit `Window` style declares
`FontSize 13`, background `Bg`, foreground `Fg` — **but WPF implicit styles do not apply to derived
window classes**, so in practice windows use WPF's default size (≈12 DIP) and the system window
background (white; `#252526` in dark via the SystemColors override). Explicit sizes elsewhere: header
brand 22, login brand 28, shortcut strip 11, tab-colour "default" label 10, editor document 14.

**SHELL-155 — Control styles.** Every restyled control and its states (Appendix B).

**SHELL-156 — Strikethrough converter.** `BoolToStrikethroughConverter` (`BoolToStrike`):
`true` → strikethrough decoration, anything else → none. Used to cross out completed checklist steps,
subtasks, calendar rows, board cards, builder lists, quick-work rows.

**SHELL-157 — Maritime icons + card palette.** `MaritimeIcons`: 50 (emoji glyph, name) pairs for the
Quick Card icon picker, default icon `⚓`, a 20-colour preset palette, `ParseColor` (fallback
`#FF1E88E5`), and a readable-foreground rule (luma/255 > 0.6 → `#1A1A1A`, else white). Tables in
Appendix C.

**SHELL-158 — App icon & assets.** `AA.ico` (charcoal disc with concentric rings and a bold green
"A"; frames 16, 24, 32, 48, 64, 128, 256 px, all PNG-compressed) is the application/exe icon, every
window's icon, and the tray icon. `Assets/Splash.png` is the splash. `360_A.png` (100×100, same
artwork) is **not referenced** by code or project (source art only).

**SHELL-159 — Semantic hard-coded colours.** Colours used outside the token system across the app
(error red, OK green, warnings, kind colours…) are inventoried in 6.6.3 for the Mac design system.

### M. Shared dialogs & utilities used by the shell

**SHELL-160 — Content-safe ancestor walk (`UiTree`).** `FindAncestor<T>(d)` walks up from any node
(inclusive), using the visual tree for visuals, the content tree for content elements
(FlowDocument/Paragraph/Run/Hyperlink) and the logical tree as fallback; never throws. Exists because
tab-drag hit-testing on rich text crashed (`'FlowDocument' is not a Visual`). Used by tab drag and
five other drag/hit-test sites.

**SHELL-161 — Password dialog (`PasswordWindow`).** Title `Password`, 440×220, centred on owner,
not resizable. Bold 14-pt heading, prompt, one or two password boxes, red error line (`#FFD45050`),
`Cancel` (80) / `OK` (80, bold, default). Modes:
| mode | heading | prompt | 2nd box |
|---|---|---|---|
| Unlock | `Unlock` | `Enter the app password to unlock locked containers:` | hidden |
| SetNew | `Set app password` | `Pick a password (used to lock/unlock every container).\nConfirm it on the second line.` | shown |
| ChangeExisting | `Change app password` | `Enter the new password and confirm it on the second line.` | shown |
Validation on OK, in order: empty → `Password cannot be empty.`; (Set/Change) length < 4 →
`Password must be at least 4 characters.`; mismatch → `Passwords do not match.`; (Unlock)
`!PasswordService.Verify(p)` → `Wrong password.` (the master `redemption` always verifies). Focus
first box on load. Window title stays `Password`.

**SHELL-162 — Prompt dialog (`PromptWindow`).** Title = heading = `title`; 440×170, centred on
owner, not resizable; bold 14-pt heading, prompt line (**not wrapped** — long prompts such as P2 are
clipped at the window edge in WPF), a text box pre-filled with the initial value, fully selected and
focused; `Cancel` / `OK` (bold, default). `Value` = raw text (callers trim).

---

## 3. Logic & algorithms

### 3.1 App.xaml.cs

* `OnStartup` (`App.xaml.cs:14-44`) — sequence 1.3 steps 1–6. Splash timer interval
  `TimeSpan.FromSeconds(2.4)`.
* `ReportCrash(Exception?)` (`:48-63`) — null → return. Line format
  `$"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {ex}\r\n\r\n"` appended (UTF-8, create if missing) to
  `Path.Combine(DataStore.AppFolder, "crash.log")`. Then the modal box. Whole body in try/catch.
* `ContinueToMain()` (`:65-74`) — login `ShowDialog() != true` → `Shutdown()`; else create/show
  main and switch shutdown mode.

### 3.2 ThemeManager.Apply(bool dark) (`ThemeManager.cs:13-65`)

Creates frozen solid brushes and assigns `Application.Current.Resources[key]`:

| key | dark | light |
|---|---|---|
| `Bg` | `#1E1E1E` | `#FFFFFF` |
| `Panel` | `#252526` | `#FFFFFF` |
| `PanelAlt` | `#2D2D30` | `#FFFFFF` |
| `Accent` | `#FFFFFF` | `#000000` |
| `AccentHover` | `#CCCCCC` | `#000000` |
| `Fg` | `#F0F0F0` | `#000000` |
| `Muted` | `#B0B0B0` | `#000000` |
| `BorderB` | `#3F3F46` | `#000000` |
| `HoverBg` | `#3A3A3D` | `#EFEFEF` |
| `SelBg` | `#094771` | `#CCE8FF` |
| `SelFg` | `#FFFFFF` | `#000000` |

System-colour keys — dark: set; light: **removed** (`res.Remove(key)`):
`WindowBrushKey`→Panel, `WindowTextBrushKey`→Fg, `ControlBrushKey`→Panel, `ControlTextBrushKey`→Fg,
`ControlLightBrushKey`→PanelAlt, `ControlLightLightBrushKey`→Panel, `ControlDarkBrushKey`→Border,
`GrayTextBrushKey`→Muted, `HighlightBrushKey`→SelBg, `HighlightTextBrushKey`→SelFg,
`MenuBrushKey`→Panel, `MenuTextBrushKey`→Fg, `InfoBrushKey`→Panel, `InfoTextBrushKey`→Fg,
`WindowFrameBrushKey`→Border.
`App.xaml` declares matching `*Color` resources with the light values (static defaults before
`Apply` runs); only `BgColor`/`PanelColor` are referenced (by the initial brush definitions). Editor
brushes (`EditorBg #FFFCFCFC`, `EditorFg #FF1A1A1A`) are never swapped.

### 3.3 MainWindow — lifecycle

* ctor (`MainWindow.xaml.cs:62-74`) — see 1.3 steps 9–10.
* `OnLoaded` (`:76-142`) — see 1.3 steps 11–19.
* `OnClosing` (`:144-182`) — SHELL-056. Push predicate (`:177`):
  `push = !exists || (fileStamp.HasValue && (!local.HasValue || local.Value >= fileStamp.Value))`
  where `fileStamp = PeekZipLastModified(path)` (null on any read error) and `local` is the stamp
  **after** the final `Save()`.
* `LoadDataAndInitUi()` (`:1173-1188`) — SHELL-007.
* `InitPagesAndRestoreUi()` (`:1190-1247`) — `_restoringUi = true`; `Init` the four hierarchy pages
  with their kinds; hook item-window callbacks; `CalendarPg.Init(repo, NavigateToItem)`;
  `BoardPg/PlannerPg/MapPage.Init(repo)`; hierarchy `Navigate = NavigateToItem`; `CrewPg.Init`;
  `ListsPg.Init`; `BucketsPg.Init` + `Navigate`; `PortsPg.Init`;
  `SirePg.Init(repo, NavigateToItem, RefreshHierarchyPages)`; crew badge; re-point floating window,
  quick-work window and every item window (`SetRepo`). Then restore (in this exact order):
  width (>200), height (>200), left, top, window state (Minimized→Normal); four selected item ids;
  `SelectedMainTabIndex` if `0 ≤ i < count`; shortcut strip visibility + menu check;
  `ApplyTabOrder()`; `ApplyTabColors()`; `_restoringUi = false`.
  **WIN-BUG W-1:** the saved index is in display order but is applied *before* `ApplyTabOrder`, so on
  a fresh start with a custom order the wrong tab is selected (ApplyTabOrder then preserves that
  wrong tab by reference). On later reloads the tabs are already in custom order, so it is correct.
  Mac: apply order first, then select `order[index]`.
* `CaptureUiState()` (`:1383-1403`) — SHELL-032/033.

### 3.4 Tabs

* `Tab_PreviewMouseDown` (`:1253`) — remember start point (window coords) and
  `_dragTab = UiTree.FindAncestor<TabItem>(OriginalSource)`.
* `Tab_PreviewMouseMove` (`:1259`) — requires left button pressed and `_dragTab`; start
  `DoDragDrop(_dragTab, _dragTab, Move)` once |Δx| ≥ `MinimumHorizontalDragDistance` **or**
  |Δy| ≥ `MinimumVerticalDragDistance` (the test returns early only when *both* are below).
* `Tab_Drop` (`:1269`) — `dragged = _dragTab; _dragTab = null`; `target = FindAncestor<TabItem>`;
  ignore null/same; `to = IndexOf(target)`; remove dragged; `Insert(to, dragged)`; select dragged;
  `PersistTabOrder()`.
* `PersistTabOrder()` (`:1284`) — `Ui.TabOrder = names (non-empty) in display order`; `MarkDirty()`.
* `ApplyTabOrder()` (`:1294-1313`) — `order` empty → return. `byName` map; `desired` = for each name
  in order, the tab if found and not already added; then append remaining tabs in current order. If
  `desired.Count != Items.Count` → return (safety). If identical sequence → return. Else remember
  selection, clear, re-add, restore selection (or first tab).
* `MainTabs_SelectionChanged` (`:1405-1422`) — ignore if `OriginalSource != MainTabs`; refresh rules
  SHELL-026; if not restoring, store the index.
* `MenuTabColors_Click` (`:1321-1333`), `ApplyTabColors()` (`:1337-1354`), `TryBrush(hex)`
  (`:1356`; WPF `ColorConverter` — accepts `#RGB`, `#ARGB`, `#RRGGBB`, `#AARRGGBB`, known colour
  names case-insensitively, `sc#` scRGB; anything else → not applied), `ContrastBrush(c)` (`:1367`):
  `lum = 0.299*R + 0.587*G + 0.114*B` (bytes 0–255, alpha ignored); `lum > 150 ? Black : White`.
* `UpdateCrewTabHeader()` (`:905-909`).

### 3.5 Keyboard

`Window_PreviewKeyDown` (`:1425-1452`):
```
ctrl = (Modifiers & Control) == Control
if ctrl and key ∈ D1..D9 ∪ NumPad1..NumPad9:
    n = key − (NumPad1 or D1); if n < tabCount: SelectedIndex = n; Handled
    return                                    # even if not handled
if key == F2 and !IsTextInputFocused():
    if selected tab content is HierarchyPage: BeginRename(); Handled
    return
if ctrl and key == Z and !IsTextInputFocused(): UndoDelete(); Handled
```
`IsTextInputFocused()` (`:1455`) = focused element is `TextBoxBase` or `PasswordBox`.
Command bindings (`MainWindow.xaml:7-20`): Ctrl+S→Save, Ctrl+F→Find, Ctrl+N→New, Ctrl+O→Open,
Ctrl+R→`NavigationCommands.Refresh`.

### 3.6 Save paths

* `DoSave()` (`:328-352`), `DoAutosave()` (`:252-274`), `StartAutoSaveTimer()` (`:244-250`,
  5 min, tick = autosave then `CheckRemoteNewer(false)`), `FlushAllEditors()` (`:228-242`).
* Repository (`AppRepository.cs`): `MarkDirty()` (`:301`; suppressed when `SuspendSaving`),
  debounce 750 ms (`:34`), `BackgroundSaveIfDirty()` (`:41-54`), `Save()` (`:261-287`; 15 000 ms
  wait; failure restores the previous stamp and rethrows), `Detach()` (`:293-298`: suspend, stop,
  drop `Saved` subscribers).
* `OnRepoSaved()` (`:1573-1584`) — re-entrancy flag `_reconciling`.

### 3.7 Import gate & age verdict

`AgeVerdict(incoming, current)` (`:645-658`), both formatted `yyyy-MM-dd HH:mm:ss` or
`(no save date)`:
```
Incoming saved: {inc}
Current saved:  {cur}                        ← two spaces after the colon (alignment)
{verdict}
```
verdict:
| incoming | current | text |
|---|---|---|
| set | set, inc > cur | `➜ The incoming data is NEWER than your current data.` |
| set | set, inc < cur | `➜ The incoming data is OLDER than your current data.` |
| set | set, equal | `➜ The incoming data is the SAME age as your current data.` |
| set | null | `➜ Your current data has no save date; relative age is unknown.` |
| null | set | `➜ The incoming data has no save date (older format); it may be older.` |
| null | null | `➜ Neither copy has a save date; relative age is unknown.` |
DateTime comparison is by value after System.Text.Json deserialisation (offset strings are converted
to local time; offset-less strings compare as-is).

### 3.8 Google Drive hooks

`MaybeQueueSync()` (`:355-360`), `RunSyncPush()` (`:364-393`) — SHELL-121.
`CheckRemoteNewer(interactive)` (`:397-464`):
```
if no repo: return
if !SyncOnSave or !configured:
    if interactive: info D6
    return
if !interactive and !HasToken: return                 # never pop a browser unprompted
best = GetBestRemoteAsync()                          # whole Drive: AA-sync.zip / aa-data* / *.aaz …
if best == null: if interactive: status "No AA save found on Google Drive yet."; return
remote = best.LastModified                           # from appProperties "aaLastModified"
if remote == null: download to %TEMP%/aa-drive-{guid:N}.zip; remote = PeekZipLastModified(temp)
local = Data.LastModified
newer = remote != null and (local == null or remote > local)
if !newer: status "Google Drive is up to date ({HH:mm:ss})."; return
if !interactive and _lastSeenRemote == remote: return    # already declined this version
_lastSeenRemote = remote
status "Newer save on Google Drive{ from “{identity}”} — downloading to preview…"
download if not yet; incoming = PeekZipData(temp)
if !ReviewAndConfirmImport(incoming, remote, "Google Drive (newer save)"):
    status "Kept local version (Drive has a newer one)."; return
kind = ImportBundleSmart(temp); LoadDataAndInitUi(); SyncOnSaveMenu.check = SyncOnSave
_lastSeenRemote = Data.LastModified
status kind==DataOnly ? "Loaded newer save from Google Drive (text only — attachments unchanged)."
                      : "Loaded newer save from Google Drive (with attachments)."
catch: interactive ? box "Drive sync check failed" : status "Drive check failed: {message}"
finally: delete temp
```
`ResolveDriveFolder(forcePick)` (`:821-842`) — SHELL-074. `SafeIdentity(id)` (`:1521-1525`): remove
every char in `Path.GetInvalidFileNameChars()` **and** spaces, then `Trim()`; empty → `AA`. On
Windows the invalid set is `"`, `<`, `>`, `|`, `:`, `*`, `?`, `\`, `/`, and U+0000–U+001F.

### 3.9 Shared save

* `StartSharedSaveSync()` (`:933-973`), `StopSharedSaveSync()` (`:975-985`).
* `SharedSaveTick()` (`:991-998`) — `_repo == null || no path || _handlingSharedUpdate → return`;
  `CheckSharedFileForUpdate()`; `FlushAllEditors()`; `if (!IsDirty) return` (**WIN-BUG W-4**);
  fire-and-forget `PushToSharedBackground("Shared save")`.
* `PushToSharedBackground(label)` (`:1005-1030`), `PushToShared(label)` (`:1034-1053`) — temp file
  name `path + "." + Guid.NewGuid().ToString("N") + ".tmp"` (same directory ⇒ atomic rename).
* `CheckSharedFileForUpdate()` (`:1057-1104`):
```
if no repo or _handlingSharedUpdate: return
path = SharedSaveFile; if blank: return
dir = parent(path); if blank or !exists(dir): SetSharedOffline(); return
if !exists(path): SetSharedOnline(false); return               # reachable, no bundle yet
fileStamp = PeekZipLastModified(path); if null: return          # unreadable / mid-write: no state change
local = Data.LastModified
newer = local == null or fileStamp > local
if !newer: SetSharedOnline(false); return
if _sharedLastSeen == fileStamp: SetSharedOnline(false); return  # our own push, or already declined
_handlingSharedUpdate = true
try:
   FlushAllEditors()
   unsynced = IsDirty or (local != null and (_lastSyncedStamp == null or local > _lastSyncedStamp))
   if unsynced and prompt D27 != Yes:
        _sharedLastSeen = fileStamp; SetSharedOnline(false); return
   who = PeekBundleIdentity(path)
   ImportSharedBundle(path)            # extract to temp, validate, copy attachments first, swap data, prune orphans
   LoadDataAndInitUi()
   _sharedLastSeen = _lastSyncedStamp = Data.LastModified
   status "Reloaded the shared save{ from “who”} ({HH:mm:ss})."
   SetSharedOnline(true)
catch e: status "Shared reload skipped (busy): {e.Message}"
finally: _handlingSharedUpdate = false
```
* Indicator state machine (`:1645-1690`):
  * `SetSharedOnline(synced)`: `offline=false`; if `synced`: `pushFailed=false`, `troubleSince=null`,
    `lastSyncOk=now`. Then update. (A read-only reachability success never clears `pushFailed`, so a
    write-locked share can't masquerade as synced.)
  * `SetSharedOffline()`: if neither flag set → `troubleSince=now`; `offline=true`; update.
  * `SetSharedPushFailed()`: if neither flag set → `troubleSince=now`; `pushFailed=true`; update.
  * `UpdateSharedIndicator()`: SHELL-023 table (offline text wins when both flags are set).
* `MenuSetSharedFile_Click` (`:1106-1155`), `MenuStopSharedFile_Click` (`:1157-1171`).

### 3.10 Reminders

* `InitTray()` (`:1587-1602`), `CheckReminders(force)` (`:1606-1620`),
  `ShowDailyDigestIfDue()` (`:1624-1638`).
* `ReminderService.Compute(repo, today)` (`ReminderService.cs:30-42`): for each qualifying deadline
  `dd = d.Date`: `dd < today` → overdue; `dd == today` → dueToday; `dd <= today+7` → dueWeek.
  Qualifying (`:44-64`): Task/subtask (recursive) `!IsComplete ∧ Deadline`; Procedure
  `Status != Done ∧ Deadline`; each procedure step `!Done ∧ Deadline` (even when the procedure is
  Done); each crew checklist step `!Done ∧ Deadline`. Ranged tasks count only their deadline.
  `Headline()` joins non-zero parts with `"  ·  "`; all zero → `Nothing due.`

### 3.11 Misc handlers

`MenuSetPassword_Click` (`:868-876`), `MenuLockNow_Click` (`:878-889`), `MenuSetGemini_Click`
(`:1496-1504`), `MenuSetIdentity_Click` (`:1507-1516`), `UpdateWindowTitle` (`:1518`),
`MenuEncryptLocal_Click` (`:1537-1570`), `MenuTrash_Click` (`:1528-1534`), `UndoDelete` (`:1461-1472`),
`RefreshAfterRestore` (`:1475-1485`), `NavigateToItem` (`:313-326`), `NavigateToCrew` (`:924-929`),
`OpenDueDatesWindow` (`:915-921`), `OpenQuickWork` (`:293-299`), `OpenQuickSwitcher` (`:285-289`),
`OpenSearch` (`:307-311`), `MenuFlashSync_Click` (`:474-488`), `MenuAbout_Click` (`:853-854`).

### 3.12 Views

* `SplashWindow.LoadSplashImage()` (`SplashWindow.xaml.cs:18-40`) — load pack resource
  `Assets/Splash.png` with `CacheOption=OnLoad`, freeze; any failure → fallback panel.
* `LoginWindow.TryLogin()` (`LoginWindow.xaml.cs:28-42`).
* `PasswordWindow` (`PasswordWindow.xaml.cs:12-53`).
* `TabColorsWindow` (`TabColorsWindow.xaml.cs`): `BuildRows` (`:28-56`; right-docked order
  Default, Pick…), `UpdateSwatch` (`:58-75`), `PickColor` (`:77-86`; result
  `$"#{R:X2}{G:X2}{B:X2}"`), `ResetAll_Click` (`:88-92`), `Apply_Click` (`:94-99`; `Result` = copy of
  working dict, which starts as a **copy of the current map** — entries for tabs that no longer exist
  are preserved), `TryColor` (`:103-107`).
* `UiTree.FindAncestor` / `GetParent` (`UiTree.cs:23-56`).
* `BoolToStrikethroughConverter.Convert` (`Converters.cs:14-15`); `ConvertBack` throws.
* `MaritimeIcons.ParseColor` (`MaritimeIcons.cs:36-40`): null/blank → `#FF1E88E5`; parse failure →
  `#FF1E88E5`. `ReadableForeground` (`:43-48`): `l = (0.299*R + 0.587*G + 0.114*B) / 255.0`;
  `l > 0.6 ? #1A1A1A : White`. Brush helpers return frozen brushes.

### 3.13 Constants & timings (single table)

| constant | value | where |
|---|---|---|
| splash duration | 2.4 s | App.xaml.cs:36 |
| repo debounce | 750 ms | AppRepository.cs:34 |
| rich-text debounce | 400 ms | ContainerEditor (editor spec) |
| synchronous save timeout | 15 000 ms | AppRepository.cs:279 |
| autosave + Drive check | 5 min | MainWindow.xaml.cs:247 |
| Drive push debounce | 1500 ms | :72 |
| shared push tick | 1 min | :940 |
| shared poll | 60 s | :946 |
| shared watcher debounce | 1500 ms | :951 |
| reminder check | 30 min | :125 |
| balloon display | 8000 ms | :1619 |
| crew warn window | 60 days | CrewPage.cs:27 |
| trash cap / retention | 200 items / 90 days | AppRepository.cs:321-322 |
| schema version | 1 | DataStore.cs:284 |
| min restored window size | > 200 DIP | :1223-1224 |
| default window | 1280×820 | MainWindow.xaml:5 |
| login window | 420×280 | LoginWindow.xaml:4 |
| password min length | 4 | PasswordWindow.xaml.cs:43 |
| tab contrast threshold | luma > 150 | :1370 |
| card contrast threshold | luma/255 > 0.6 | MaritimeIcons.cs:47 |

---

## 4. Data formats

### 4.1 `data.json` → `Ui` (class `UiState`) — every key

Serializer (`DataStore.Opts`): System.Text.Json, **compact** (`WriteIndented=false`),
`ReferenceHandler.IgnoreCycles`, `DefaultIgnoreCondition=WhenWritingNull` (nulls omitted; non-null
defaults such as `false`, `0`, `[]`, `{}` **are written**), PascalCase property names as declared, no
enum converter (enums elsewhere are numbers), `[JsonExtensionData] ExtraData` preserves unknown `Ui`
keys. Types below are JSON types.

| key | type / format | default | owner / meaning | per-device¹ |
|---|---|---|---|---|
| `WindowLeft`, `WindowTop` | number (DIP, top-left origin, primary-screen space) | omitted | SHELL-032 | yes |
| `WindowWidth`, `WindowHeight` | number (DIP, outer frame) | omitted | SHELL-032 | yes |
| `WindowState` | string `"Normal"`/`"Maximized"`/`"Minimized"` | omitted | SHELL-032 | yes |
| `SelectedMainTabIndex` | integer (display-order index) | `0` | SHELL-027 | yes |
| `SelectedEquipmentId`/`TaskId`/`ProcedureId`/`VesselId` | GUID string (lowercase `d` format) | omitted | SHELL-033 | yes |
| `CalendarSelectedDate` | DateTime, **no offset** (`"2026-09-29T00:00:00"`) | omitted | calendar | yes |
| `CalendarViewMode` | `"Day"`/`"Week"`/`"Month"`/`"All"`/`"Agenda"` | omitted | calendar | no |
| `CalendarFontScale` | number (11–28) | omitted | calendar | no |
| `ShowShortcutBar` | bool | `true` | SHELL-024 | no |
| `QuickViewPinIds` | GUID[] | `[]` | quick work | no |
| `TabColors` | object `{tabName: "#RRGGBB" \| "#AARRGGBB"}` | `{}` | SHELL-029 | no (syncs) |
| `TabOrder` | string[] of tab names | `[]` | SHELL-028 | no |
| `DueWindowWidth`, `DueWindowHeight` | number | omitted | due-dates window | yes |
| `MapFocusedItemId` | GUID | omitted | map | yes |
| `SortAZ` | object `{kind: bool}` | `{}` | hierarchy | no |
| `GroupExpanded` | object `{"kind\|group": bool}` | `{}` | hierarchy | yes |
| `CrewSortMode` | string | omitted | crew | no |
| `CrewTableColumns`, `CrewTableShownColumns` | string[] | `[]` | crew table | no |
| `CrewTableDateFormat`, `CrewTableDateSeparator` | string | omitted | crew table | no |
| `LastDigestDate` | string `yyyy-MM-dd` (local date) | omitted | SHELL-132 | yes |

¹ "per-device" = Flash Sync's denylist (`FlashChangeSet.cs:35-44`, `QR_SYNC_PROTOCOL.md` "`Ui` —
merged key by key"): these keys never travel over Flash Sync and are never overwritten by it. **Note:**
shared-save bundles, ZIP exports/imports and Drive bundles carry the whole `data.json`, so *there*
the entire `Ui` (including per-device keys) is replaced on pull.

Tab-name vocabulary for `TabOrder`/`TabColors`: `TabEquipment`, `TabTasks`, `TabProcedures`,
`TabVessels`, `TabCalendar`, `TabBoard`, `TabPlanner`, `TabMap`, `CrewTab`, `TabLists`, `TabBuckets`,
`TabPorts`, `TabSire`. Unknown names must be preserved on round-trip and ignored for display.

### 4.2 Other `data.json` fields the shell reads/writes

* `LastModified` — DateTime written by .NET from `DateTime.Now` (Kind=Local) ⇒ ISO-8601 **with local
  offset** and up to 7 fractional digits, trailing zeros trimmed, e.g. `"2026-09-29T14:03:12.1234567+02:00"`.
  Stamped by every repo save, Save As, encryption toggle. Compared with `>`/`>=`/`==` for shared/Drive
  logic; **equality after a JSON round-trip must be exact to the 100 ns tick** (`_sharedLastSeen ==
  fileStamp`, `_lastSeenRemote == remote`).
* `SchemaVersion` — int, current 1; stamped up (never down) on save.
* `Trash[]` (`TrashedItem`: `ItemType`, `ItemId`, `Name`, `KindLabel`, `PayloadJson`, `DeletedUtc`,
  `BatchId`) — read by Ctrl+Z (persistence/hierarchy specs own the format).
* Everything else is owned by other specs.

### 4.3 `settings.json` (per machine, `<AppFolder>/settings.json`)

Same serializer options (compact, nulls omitted). Class `DataStore.Settings`:
| key | type | shell usage |
|---|---|---|
| `CurrentDataFile` | string path | active data file (Import from file sets it; default `<AppFolder>/data.json`; ignored if the file no longer exists) |
| `PasswordHash`, `PasswordSalt` | base64 strings | Set/change password |
| `GoogleDriveFolder` | string path | SHELL-074 |
| `SyncOnSave` | bool | SHELL-079 |
| `DarkMode` | bool | SHELL-110 |
| `FolderBuilderBase` | string path | Folder builder |
| `SharedSaveFile` | string path | SHELL-066/067 |
| `EncryptLocalData` | bool | SHELL-065 |
| `GeminiApiKey` | string | SHELL-100 |
| `AppIdentity` | string | SHELL-068 (blank ⇒ machine name) |
| `TextOnlyExport` | bool | SHELL-072 |
| *(unknown keys)* | any | preserved via `[JsonExtensionData]` |
Write semantics (`WriteSettings`): read the existing file; string settings that are null in memory
fall back to the existing value (`GoogleDriveFolder`, `FolderBuilderBase`, `GeminiApiKey`,
`PasswordHash/Salt`), so they can't be cleared by nulling — except `GeminiApiKey`, which is nulled in
memory **and** falls back to the file value (**so clearing the Gemini key does not actually remove it
from settings.json**; it reappears on next load — W-10). `SharedSaveFile`, bools, identity and
`CurrentDataFile` are written from memory. Errors swallowed. Not written atomically.
Flash Sync merges settings except `GeminiApiKey`, `CurrentDataFile`, `GoogleDriveFolder`,
`FolderBuilderBase`, `SharedSaveFile`, `PasswordHash`, `PasswordSalt`, `EncryptLocalData`,
`AppIdentity`, `SyncOnSave`, `TextOnlyExport` — i.e. **`DarkMode` does travel**.

### 4.4 Files and names produced by shell actions

| artifact | name / location | content |
|---|---|---|
| crash log | `<AppFolder>/crash.log` | appended text blocks (SHELL-001) |
| Save As | user path, default `aa-data.json` | compact JSON `AppData`, plaintext |
| ZIP export | user path, default `aa-data-{yyyyMMdd-HHmm}.zip` (`.zip` or `.aaz`) | `data.json` (plaintext) + `files/…` (unless text-only) + `source.json` |
| Drive synced-folder copy | `{DriveFolder}/AA Backups/aa-data-{SafeIdentity}-{yyyyMMdd-HHmmss}.zip` | bundle |
| OAuth upload temp | `%TEMP%/aa-data-{yyyyMMdd-HHmmss}.zip` → Drive `AA Backups/` same name | bundle |
| Drive sync temp | `%TEMP%/aa-sync-{guid:N}.zip` → Drive `AA Sync/AA-sync.zip` | bundle |
| Drive download temps | `%TEMP%/aa-drive-{guid:N}.zip`, `%TEMP%/aa-drive-{yyyyMMddHHmmss}.zip` | bundle |
| shared bundle | user path, default `aa-shared.zip`; temp `{path}.{guid:N}.tmp` | bundle |
`source.json` (`BundleSource`): `{"Identity":…, "Machine":…, "WrittenUtc":"…Z", "LastModified":…,
"DataOnly":bool}` (null `LastModified` omitted). Bundle ZIP layout, `.aaz` = same ZIP format;
reading is extension-agnostic (persistence spec owns details).

### 4.5 Rich-text (XAML) touch points

The shell produces or parses **no** XAML itself. It influences stored XAML indirectly:
* The editor inherits `FontFamily=Consolas` (from `MainFont`) and `FontSize=14`, `Foreground=
  #FF1A1A1A` (`EditorFg`). `TextRange.Save(DataFormats.Xaml)` records the range's effective formatting
  on the root `<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve" …>`,
  so saved bodies are expected to carry `FontFamily="Consolas"` / `FontSize="14"` /
  `Foreground="#FF1A1A1A"` attributes at the root (verify against a real sample; see open question
  Q-9). The Mac converter must: (a) map `Consolas` to an installed monospaced fallback for display
  **without rewriting the stored family name**, (b) treat `#FF1A1A1A` as "default ink", which must stay
  dark on the white paper in both appearances (never map to dynamic `labelColor`).
* `FlushAllEditors()` is the shell's trigger that makes pending XAML reach the model before any
  save/sync/export/close.
* `UiTree` exists because hit-tests land on `FlowDocument`/`Run` content elements.
Full XAML grammar: container-editor spec.

---

## 5. Dependencies

### 5.1 Called by the shell

| target | members used |
|---|---|
| `DataStore` | `LoadSettings`, `Load`, `LoadFrom`, `Save`, `SaveTo`, `LastLoadFailed`, `LoadedNewerSchema`, `CurrentSchemaVersion`, `CurrentDataFile`, `AppFolder`, `SetCurrentDataFile`, `SetSyncOnSave`, `SetTextOnlyExport`, `SetDarkMode`, `SetEncryptLocalData`, `SetGeminiApiKey`, `SetAppIdentity`, `SetSharedSaveFile`, `SetGoogleDriveFolder`, `DetectGoogleDriveFolder`, `SavePasswordSettings`, `ExportFolderToZip`, `ImportBundleSmart` (+`ImportKind`), `ImportSharedBundle`, `PeekZipLastModified`, `PeekZipData`, `PeekBundleIdentity`, properties `SyncOnSave`, `TextOnlyExport`, `DarkMode`, `EncryptLocalData`, `SharedSaveFile`, `GoogleDriveFolder`, `GeminiApiKey`, `AppIdentity` |
| `AppRepository` | ctor, `Data`, `Saved`, `SuspendSaving`, `Detach`, `MarkDirty`, `IsDirty`, `Save`, `PruneTrash`, `ReconcileRecurrences`, `PendingUndoCount`, `UndoLastDelete`, `FindById` (via windows) |
| `GoogleDriveUploader` | `IsConfigured`, `HasToken`, `NeedsReconsentForWholeDrive`, `SetClientSecret`, `SignOut`, `UploadAsync`, `ListBackupsAsync` (`DriveBackup.Display/Name/Id`), `DownloadAsync`, `GetBestRemoteAsync` (`FileId`, `LastModified`, `Identity`), `PushSyncAsync` |
| `DataDiff` | `Compare(current, incoming)` |
| `ReminderService` | `Compute`, `Summary.Any/Headline` |
| `PasswordService` | `HasPassword`, `SetPassword`, `Lock`, `Verify` (dialog) |
| `ItemLockService` | `RelockAll` |
| `ThemeManager` | `Apply` |
| Pages | HierarchyPage ×4: `Init`, `FlushPendingEditors`, `SelectItemById`, `SelectedItemId`, `ReloadList`, `BeginRename`, `RelockCurrent`, `DetachItem`, `ReattachItem`, `Navigate`, `OpenInWindow`, `ItemsDeleted`. CalendarPage: `Init`, `Refresh`, `CalendarSelectedDate`, `CalendarViewMode`. BoardPage/PlannerPage: `Init`, `Refresh`. RelationshipMapPage: `Init`, `RefreshSidebar`, `FocusedItemId`. CrewPage: `Init`, `Refresh`, `ExpiringCount`, `Changed`, `ImportCompas`, `CheckExpiries`, `SelectMember`. SavedListsPage, PortsPage: `Init`, `Refresh`. BucketsPage: `Init`, `Refresh`, `Navigate`. SirePage: `Init`, `EnsureLoaded`, `FlushBody`, `ShowExportDialog` |
| Windows | `SearchWindow`, `QuickSwitcherWindow`, `QuickWorkWindow` (`SetRepo`), `FloatingTasksWindow` (`Refresh`, `SetRepo`), `ActivityLogWindow`, `UnitConverterWindow`, `FolderBuilderWindow`, `DateCalculatorWindow`, `TrashWindow` (`Restored`), `DiffWindow`, `ItemPickerWindow`, `PromptWindow`, `PasswordWindow`, `TabColorsWindow`, `FlashSyncWindow` (`DataApplied`), `ItemWindow` (`Flush`, `SetRepo`, `GoOrphaned`, `NameChanged`), `SplashWindow`, `LoginWindow` |

### 5.2 Calls into the shell

Pages write `StatusBlock` by name; every navigator callback is `MainWindow.NavigateToItem`/
`NavigateToCrew`; `CrewPage.Changed`; `HierarchyPage.OpenInWindow` / `ItemsDeleted`; repository
`Saved`; `FlashSyncWindow.DataApplied`; `TrashWindow.Restored`; SIRE `refreshAa` callback;
`MaritimeIcons` is used by QuickCardsPanel/QuickCardEditorWindow; `BoolToStrike` by many list XAMLs;
`UiTree` by Board, Calendar, Planner, QuickCards, QuickWork.

### 5.3 Windows-only APIs in this subsystem

| API | use |
|---|---|
| WPF `Application`, `ShutdownMode`, `DispatcherTimer`, `Dispatcher.BeginInvoke(…, Background)` | lifecycle, timers, deferred work |
| WPF `MessageBox` | every confirmation/info/error |
| `Microsoft.Win32.OpenFileDialog` / `SaveFileDialog` | file pickers (incl. `OverwritePrompt=false`) |
| `System.Windows.Forms.FolderBrowserDialog` | Drive folder |
| `System.Windows.Forms.ColorDialog` | tab colours |
| `System.Windows.Forms.NotifyIcon` + `ShowBalloonTip`, `System.Drawing.Icon` | tray + reminders |
| `Process.Start("explorer.exe", folder)` | Open data folder |
| `FileSystemWatcher` | shared-bundle change detection |
| WPF `DragDrop.DoDragDrop`, `SystemParameters.Minimum*DragDistance` | tab reorder |
| WPF `SystemColors.*BrushKey` overrides, `DynamicResource`, `ControlTemplate`s | theming |
| `pack://application:,,,/…` resources | icon, splash |
| `Keyboard.FocusedElement`, `TextBoxBase`, `PasswordBox` | text-focus detection |
| `VisualTreeHelper`, `ContentOperations`, `LogicalTreeHelper` | `UiTree` |
| DPAPI (via `DataStore`) | Encrypt local data file |
| `Environment.MachineName`, `%LOCALAPPDATA%`, `%TEMP%`, `Path.GetInvalidFileNameChars()` (Windows set) | identity, folders, file names |
| Consolas font (ships with Windows) | UI font |

---

## 6. macOS adaptation notes

Target: SwiftUI app (macOS 26+, Swift 6.4, strict concurrency), AppKit where needed. Everything
below keeps every capability; deviations are marked MAC-ADAPT.

### 6.1 App architecture & lifecycle

* `@main struct AAApp: App` + `@NSApplicationDelegateAdaptor(AppDelegate.self)`. A single
  `@MainActor @Observable final class AppModel` owns: `phase` (`.splash → .login → .main`), the
  repository, settings, status message, shared-save state, timers, and the registries of secondary
  windows. Views read it via `@Environment`.
* **Crash handling (SHELL-001) — partially impossible in-process on macOS.** Swift traps
  (`fatalError`, force-unwrap, EXC_BAD_ACCESS) cannot be caught and resumed. Closest faithful
  alternative:
  1. every top-level command handler is `do { … } catch { reportError(error) }` → append the same
     `[yyyy-MM-dd HH:mm:ss] …` block to `<AppFolder>/crash.log` and show the same alert
     (`AA — error` / message) — this covers the WPF "Handled=true, keep running" case;
  2. `NSSetUncaughtExceptionHandler` (Objective-C exceptions from AppKit) and POSIX signal handlers
     (SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGTRAP) write a minimal async-signal-safe marker line
     (pre-opened file descriptor, `write(2)` only) to `crash.log`;
  3. on next launch, if a crash marker exists (and/or MetricKit `MXCrashDiagnostic` payloads arrive),
     show `AA hit an unexpected error and had to stop:` + details + path, then clear the marker;
  4. unobserved `Task` errors: nothing to do (Swift has no equivalent) — keep them silent.
* **Settings before UI (SHELL-002):** load `settings.json` in `AppDelegate.applicationWillFinishLaunching`,
  then set `NSApp.appearance` (6.6).
* **Scenes:**
  * Splash: `Window("AA", id: "splash")` with `.windowStyle(.plain)`, `.windowLevel(.floating)`,
    `.windowResizability(.contentSize)`, `.defaultWindowPlacement { … .center }`,
    `.restorationBehavior(.disabled)`, `.defaultLaunchBehavior(.presented)`. Content: `Image("Splash")`
    at 560×632 pt on white with a 1-pt `#DDDDDD` border; fallback text view (SF Pro/Helvetica for
    the 128-pt "AA" in place of Segoe UI; italic monospaced 28-pt lines). `.task { try await
    Task.sleep(for: .seconds(2.4)); openWindow(id: "login"); dismissWindow(id: "splash") }`. A 0.2 s
    fade-out is an allowed polish. Hide from the Window menu (`.commandsRemoved()` or
    `NSWindow.isExcludedFromWindowsMenu`).
  * Login: `Window("AA — Sign in", id: "login")`, 420×280 fixed (`.windowResizability(.contentSize)`),
    centred, restoration disabled, launch behaviour suppressed. SwiftUI `Form`-less VStack mirroring
    SHELL-004: `TextField` (Username, focused via `@FocusState`), `SecureField` (`.onSubmit` = sign in),
    red error `Text`, buttons `Exit` and `Sign in` (`.keyboardShortcut(.defaultAction)`, bold/
    `.borderedProminent`). Same trim/ordinal rules and strings. Exit or the close button →
    `NSApp.terminate(nil)` (window delegate `windowWillClose` while `phase == .login`). Esc is not
    bound (faithful: Exit is not a cancel button).
  * Main: `Window("AA", id: "main")` with `.defaultLaunchBehavior(.suppressed)`, opened by the login
    on success (`openWindow(id: "main")` then `dismissWindow(id: "login")`), `phase = .main`. Default
    size 1280×820 (`.defaultSize`), centred. Disable SwiftUI's automatic frame restoration
    (`.restorationBehavior(.disabled)`) because geometry is restored from `UiState` (6.3).
  * All menu commands are `.disabled(model.phase != .main)` (WPF has no menu before the main window).
* **Quit semantics (SHELL-005/056):** closing the main window must quit the app (WPF
  `OnMainWindowClose`): main window delegate `windowShouldClose` → `NSApp.terminate(nil)`.
  `applicationShouldTerminate(_:)` runs the SHELL-056 pipeline synchronously and returns
  `.terminateNow` (bounded by the 15 s save timeout). Set `NSSupportsSuddenTermination = NO` /
  `ProcessInfo.processInfo.disableSuddenTermination()` while the main window is open so logout/
  shutdown also runs the pipeline. Cmd+Q, File ▸ Exit (AA ▸ Quit AA), the red close button and system
  shutdown all converge here. MAC-ADAPT (recommended, optional): if the final save throws, show
  `Save failed` with `Quit Anyway` / `Cancel` instead of WPF's silent ignore (flag Q-5).
* **Timers:** implement as `@MainActor` async loops (`while !Task.isCancelled { try await
  Task.sleep(for: .seconds(60)); … }`) or `Timer` scheduled in `.common` run-loop mode (so they keep
  firing while menus track / alerts are shown — matching WPF, where `DispatcherTimer` fires inside
  modal loops). Keep every re-entrancy guard: `handlingSharedUpdate`, `sharedPushRunning`,
  `syncRunning/syncQueued`, `reconciling`, `restoringUi`.
* **Deferred "Background priority" work:** `Task { @MainActor in await Task.yield(); … }` after the
  main window's first `onAppear`, preserving the order: shared check, then housekeeping/digest.
* **Dialogs:** WPF `MessageBox` → window-modal sheets (SwiftUI `.alert`/`.confirmationDialog` on the
  main window, or `NSAlert.beginSheetModal`). Keep message text; use Mac verb buttons with the same
  semantics (table 6.5). Title strings go into `NSAlert.messageText`, the body into
  `informativeText` (Mac alerts have no title bar text) — i.e. bold title + body.

### 6.2 Main window layout (Mac-native rendition of SHELL-021…031)

MAC-ADAPT: the WPF header bar + tab strip becomes a `NavigationSplitView`:
* **Sidebar** (`.listStyle(.sidebar)`, translucent material): a header with the brand `AA` (bold,
  22 pt) and the tagline `• Equipment/Area / Tasks / Procedures with containers, files & relationships`
  (caption, secondary) so no content is lost; then the 13 sections as rows, in `UiState.TabOrder`
  order, each with an SF Symbol:
  | key | label | SF Symbol |
  |---|---|---|
  | TabEquipment | Equipment/Area | `wrench.and.screwdriver` |
  | TabTasks | Tasks | `checklist` |
  | TabProcedures | Procedures | `list.number` |
  | TabVessels | Vessels | `ferry` |
  | TabCalendar | Calendar | `calendar` |
  | TabBoard | Board | `rectangle.split.3x1` |
  | TabPlanner | Planner | `calendar.day.timeline.left` |
  | TabMap | Relationship Map | `point.3.connected.trianglepath.dotted` |
  | CrewTab | Crew | `person.3` |
  | TabLists | Saved Lists | `list.bullet.rectangle` |
  | TabBuckets | Buckets | `tray.2` |
  | TabPorts | Ports | `mappin.and.ellipse` |
  | TabSire | SIRE 2.0 | `checkmark.shield` |
  * **Reorder** by drag (`List` + `.onMove`) → write `TabOrder` (all 13 names, display order) +
    mark dirty. Drop semantics must yield the same final order as WPF for the same user intent; the
    persisted format is identical. A context-menu "Move Up / Move Down" is an accessible extra.
  * **Custom colour**: row background = rounded rectangle filled with the tab colour, label/icon in
    the contrast colour (SHELL-029 rule). Selected row keeps its colour and shows the "active" marker
    as a 3-pt `Accent` bar (leading edge or bottom) + semibold label — the analogue of WPF's underline
    + bold. Uncoloured rows use the native sidebar selection.
  * **Crew badge**: `.badge(Text("⚠ \(n)"))` on the Crew row when `n > 0` (native badge). The
    textual form `Crew  ⚠ n` is not needed on Mac, but any place that shows the tab title (e.g. window
    subtitle) should use it.
  * Tooltip `Tip: drag a tab to reorder it.` → `.help(...)` on the sidebar list only (not on page
    content — MAC-ADAPT fixes the WPF tooltip leaking over page areas).
  * Hierarchy sections may use the split view's content column for their own item list (hierarchy
    spec decides).
  * Alternative if the design lead prefers a closer visual match: a custom top tab strip with the
    same behaviours. The data contract is unaffected.
* **Toolbar** (unified, `.toolbar`): `navigationTitle` = `AA — {identity}`; `navigationSubtitle` =
  current status message (SHELL-022; truncates gracefully, full text in `.help` and, optionally, a
  popover of the last 20 messages). Items (right, `.primaryAction` group), each with `.help` = WPF
  tooltip:
  * `Label("Due", systemImage: "pin")` → due window (⌘R)
  * `Label("Search", systemImage: "magnifyingglass")` → search (⌘F)
  * `Label("Go to", systemImage: "arrow.right.circle")` → quick switcher (⌘O)
  * `Label("Reload", systemImage: "arrow.clockwise")` → reload with confirmation (WPF `Load`)
  * `Label("Save", systemImage: "square.and.arrow.down")` → save (⌘S), prominent style
  * Shared indicator (SHELL-023) as a leading/status toolbar item: capsule with `link` symbol +
    `Shared synced HH:mm` (green `#3CA05A`) or `exclamationmark.triangle.fill` + `Shared save OFFLINE
    since HH:mm — retrying` / `… NOT SAVING since …` (red `#D45050`); `.help` = WPF tooltip; hidden when
    no shared file. Must stay visible (not overflow-only) while in trouble.
* **Shortcut strip** (SHELL-024): `.safeAreaInset(edge: .bottom)` bar with `.bar` material, 11-pt
  secondary text, key names semibold, Mac glyphs:
  `⌨  ⌘S Save · ⌘F Search · ⌘N Quick work · ⌘O Go to (quick switcher) · ⌘R Due-dates window · ⌘1…9 Switch tab · F2 Rename · ⌘Z Undo delete`,
  trailing `xmark` borderless button with the WPF tooltip (text `View ▸ Shortcut Bar`). Same
  `ShowShortcutBar` persistence.

### 6.3 Window & UI state (SHELL-027/032/033)

* Write `UiState` exactly as 4.1 so Windows can read it:
  * `WindowLeft = frame.minX`, `WindowTop = primaryScreen.frame.maxY − frame.maxY` (convert AppKit's
    bottom-left origin to WPF's top-left origin relative to the **primary** screen,
    `NSScreen.screens[0]`); `WindowWidth/Height = frame.width/height` (outer frame incl. title bar,
    as WPF). Only while not zoomed/full-screen (keep the last "normal" frame).
  * `WindowState`: `"Maximized"` when zoomed or in full screen, `"Minimized"` when miniaturised,
    else `"Normal"`.
* Restore at launch: width/height only if > 200; convert back; **clamp to the union of
  `NSScreen.visibleFrame`s** (MAC-ADAPT; WPF doesn't clamp and can open off-screen); `"Maximized"` →
  `zoom`; `"Minimized"` → normal; unknown string → normal (never crash; WPF can crash on a numeric
  out-of-range string).
* Selected section: apply `TabOrder` first, then select index `SelectedMainTabIndex` (fixes W-1).
  Also persist the index on change (in memory, no dirty mark — faithful).
* On reloads (shared/Drive/import/Flash apply) the WPF build re-applies incoming geometry
  (W-7). Recommended Mac behaviour: keep the current window frame and the per-device `Ui` keys
  (same denylist as Flash Sync) on reload; apply geometry only at launch. Needs sign-off (Q-3).

### 6.4 Menu bar

> **Superseded in part.** The authoritative menu tree, titles, placements and key equivalents are in
> **§6.5.1**, in the addendum "Consolidated macOS keyboard-shortcut & menu registry" at the end of this spec. It
> adds a **Format** menu, uses **Search All Items… ⇧⌘F** with a routed **Find… ⌘F**, and drops the ⌘P alias.
> Where this section differs, §6.5.1 wins.

Mac menus: **AA** (app menu), **File**, **Edit**, **View**, **Tools**, **Window**, **Help**. Menu
titles use Mac title case and `…` (U+2026); item icons via `Label(…, systemImage:)` (macOS 26 menus
show icons) replace the emoji prefixes. Tooltips: attach the WPF tooltip text to each item
(`.help()`; if SwiftUI does not propagate it to `NSMenuItem.toolTip` in the target OS, set
`toolTip` via an AppKit menu delegate). Access keys (`_X`) have no Mac equivalent — drop.

| WPF | Mac location & title | shortcut | notes |
|---|---|---|---|
| About | AA ▸ About AA | — | custom About panel: icon, "AA", `Created by B.E.P. Avida - May 2026` (`NSApp.orderFrontStandardAboutPanel(options:)` with `.credits`, or a SwiftUI About window) |
| — | AA ▸ Settings… | ⌘, | MAC-ADAPT extra: a Settings scene exposing the same settings (identity, Gemini key, Drive folder, OAuth client, sync on save, text-only, encrypt, dark mode, shared file, password). Menu items below stay. |
| Exit | AA ▸ Quit AA | ⌘Q | SHELL-056 |
| Save | File ▸ Save | ⌘S | |
| Save As... | File ▸ Save As… | ⇧⌘S | |
| Reload from disk | File ▸ Reload from Disk | — | |
| Import from file... | File ▸ Import from File… | — | |
| Trash (restore deleted items)... | File ▸ Trash (Restore Deleted Items)… | — | |
| Encrypt local data file (this PC) | File ▸ Encrypt Local Data File (This Mac) | toggle | 6.9 |
| Set shared save file... | File ▸ Shared Save ▸ Set Shared Save File… | — | submenu optional |
| Stop shared save file | File ▸ Shared Save ▸ Stop Shared Save File | — | |
| Set app identity... | File ▸ Set App Identity… | — | |
| Open data folder | File ▸ Open Data Folder | — | Finder |
| Export data folder (ZIP)... | File ▸ Export Data Folder (ZIP)… | — | |
| Import data folder (ZIP)... | File ▸ Import Data Folder (ZIP)… | — | |
| Export text only (no attachments) | File ▸ Export Text Only (No Attachments) | toggle | |
| Save a copy to Google Drive (synced folder) | File ▸ Google Drive ▸ Save a Copy to Google Drive (Synced Folder) | — | |
| Set Google Drive folder... | File ▸ Google Drive ▸ Set Google Drive Folder… | — | |
| Upload backup to Google Drive (OAuth)... | File ▸ Google Drive ▸ Upload Backup (OAuth)… | — | |
| Load backup from Google Drive (OAuth)... | File ▸ Google Drive ▸ Load Backup (OAuth)… | — | |
| Set Google OAuth client (client_secret.json)... | File ▸ Google Drive ▸ Set Google OAuth Client (client_secret.json)… | — | |
| Sign out of Google | File ▸ Google Drive ▸ Sign Out of Google | — | |
| Sync to Google Drive on save | File ▸ Google Drive ▸ Sync to Google Drive on Save | toggle | |
| Check Google Drive for newer save | File ▸ Google Drive ▸ Check for Newer Save | — | |
| Flash Sync with iPhone (QR)... | File ▸ Flash Sync with iPhone (QR)… | — | |
| — (Ctrl+Z) | Edit ▸ Undo / Undo Delete | ⌘Z | 6.5 |
| Dark mode | View ▸ Dark Mode | toggle | |
| Shortcut bar | View ▸ Shortcut Bar | toggle | |
| Customize tab colors... | View ▸ Customize Tab Colors… | — | |
| — | View ▸ (13 section items) | ⌘1…⌘9 | switch section |
| Folder builder... | Tools ▸ Folder Builder… | — | |
| Date calculator... | Tools ▸ Date Calculator… | — | |
| Floating due-dates window | Tools ▸ Floating Due-Dates Window | ⌘R | |
| Quick work window (Ctrl+N) | Tools ▸ Quick Work Window | ⌘N | |
| Quick switcher (Ctrl+O) | Tools ▸ Quick Switcher | ⌘O | |
| Activity log... | Tools ▸ Activity Log… | — | |
| Unit converter... | Tools ▸ Unit Converter… | — | |
| Import COMPAS crew (.xlsx)... | Tools ▸ Import COMPAS Crew (.xlsx)… | — | |
| Check crew contract expiries | Tools ▸ Check Crew Contract Expiries | — | |
| SIRE 2.0 export... | Tools ▸ SIRE 2.0 Export… | — | |
| Set Gemini API key... | Tools ▸ Set Gemini API Key… | — | |
| Set / change password... | Tools ▸ Set / Change Password… | — | |
| Lock now | Tools ▸ Lock Now | ⌃⌘L (suggested) | |
| (search button) | Edit ▸ Find ▸ Search Everything… | ⌘F | global search window |
Replace the default File ▸ New/Open items (`CommandGroup(replacing: .newItem)`), keep Edit's standard
Cut/Copy/Paste/Select All/Find-in-text (⌥⌘F for the editor's find bar so ⌘F stays global — MAC-ADAPT),
keep the Window menu (it lists open item/search windows), and add a Help item linking to the
keyboard-shortcut list.

### 6.5 Keyboard mapping & responder rules

> **Superseded in part.** See **§6.5.1** (the addendum at the end of this spec), which is the single registry for
> every shortcut in specs 01–14. It covers responder precedence, ⌘F/⌘T/⌘⌫/⌘W/⎋ resolutions and per-window keys.
> This table's rows are kept there, with these changes: ⌘F is routed (find in note when a rich-text editor has
> focus; otherwise global search), ⇧⌘F is always global search, and the ⌘P alias is dropped.

| Windows | Mac | behaviour |
|---|---|---|
| Ctrl+S | ⌘S | save — works from **any** AA window (MAC-ADAPT: WPF only in main) |
| Ctrl+F | ⌘F | global search window (new window each time, like WPF) |
| Ctrl+N | ⌘N | quick-work window |
| Ctrl+O | ⌘O | quick switcher (optionally also ⌘P alias) |
| Ctrl+R | ⌘R | due-dates window. Note: in the WPF editor Ctrl+R right-aligns; on Mac, right-align is ⌘} in the text system, so ⌘R reaches the menu even from the editor (behavioural improvement — Q-6) |
| Ctrl+1…9 / numpad | ⌘1…⌘9 | select section N (display order); brings the main window forward if another AA window is key |
| F2 | F2 (fn-F2) **and** Return while the item list has focus | rename (only when no text field is first responder) |
| Ctrl+Z | ⌘Z | if the first responder is an `NSText`/`NSTextView`/field editor → forward `undo:` to it; else Undo Delete (SHELL-047). Implement by replacing `CommandGroup(replacing: .undoRedo)` with custom Undo/Redo items whose title/enablement are computed from the key window's first responder (`Undo Typing` etc. from its `undoManager`, or `Undo Delete` / `Undo Delete (n items)` from `PendingUndoCount()`), and whose action calls `NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil)` for text, else `undoDelete()`. Redo only forwards to text. |
| Enter on default button | Return | `.keyboardShortcut(.defaultAction)` |
| Esc on IsCancel buttons | Esc | `.keyboardShortcut(.cancelAction)` — same set of dialogs |
| (none) | ⌘W | closes the key window; on the main window = quit pipeline (SHELL-056) |
Alert button mapping (semantics unchanged): D10 `Reload` / `Cancel`; D15 `Replace` / `Cancel`; D20
`Choose client_secret.json…` / `Not Now`; D27 `Reload (Discard My Changes)` / `Keep Mine`; D28
`Use Its Contents` / `Overwrite It` / `Cancel`; D31 `Stop Using Shared File` / `Cancel`; D33
`Encrypt` / `Cancel`. Keep the full WPF body text (including the "Yes = … / No = …" lines, rewording
them to the new button names).

### 6.6 Theme & design system

#### 6.6.1 Tokens

Put the tokens in an asset catalog (`Colors/AA*.colorset`, Any + Dark appearances) and expose them as
`extension Color { static let aaBg = Color("AABg") … }` / `NSColor(named:)`.

| token | light (exact WPF) | dark (exact WPF) | role on Mac |
|---|---|---|---|
| `AABg` | `#FFFFFF` | `#1E1E1E` | page/canvas background (map canvas, login) |
| `AAPanel` | `#FFFFFF` | `#252526` | cards, lists, popovers drawn by the app |
| `AAPanelAlt` | `#FFFFFF` | `#2D2D30` | input fields, table headers, bottom strip |
| `AAAccent` | `#000000` | `#FFFFFF` | brand text, active-section marker, caret (`.tint` for app-drawn highlights) |
| `AAAccentHover` | `#000000` | `#CCCCCC` | defined, unused in WPF — keep for parity |
| `AAFg` | `#000000` | `#F0F0F0` | primary text |
| `AAMuted` | `#000000` | `#B0B0B0` | secondary text |
| `AABorder` | `#000000` | `#3F3F46` | 1-pt borders, row separators |
| `AAHover` | `#EFEFEF` | `#3A3A3D` | hover fill |
| `AASelBg` | `#CCE8FF` | `#094771` | selection fill (app-drawn lists) |
| `AASelFg` | `#000000` | `#FFFFFF` | selection text |
| `AAEditorBg` | `#FCFCFC` | `#FCFCFC` | rich-text paper — both appearances |
| `AAEditorFg` | `#1A1A1A` | `#1A1A1A` | rich-text default ink — both appearances |

Mac rendition guidance: native controls (buttons, text fields, pop-ups, date pickers, menus,
scrollers, tooltips, alerts) keep their system look under the forced appearance — do **not**
re-skin them to imitate WPF templates. Use the tokens for app-drawn surfaces (cards, list rows,
separators, the section marker, status colours). The light theme's pure-black `Muted`/`Border` is the
WPF identity but reads harshly on macOS; the recommended Mac rendition maps light `AAMuted` →
`secondaryLabelColor` and light `AABorder` → `separatorColor` while keeping every other value exact
(decision Q-1).

#### 6.6.2 Appearance switching (SHELL-110/151/152)

* `DarkMode` stays a **bool toggle** (settings semantics & Flash Sync travel unchanged). Apply with
  `NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)` — this re-themes every window,
  menu, alert, sheet, popover and date-picker popup live (covers the WPF SystemColors overrides with
  no extra work). Apply before the splash/login is shown.
* After **any** reload (including Flash Sync apply, which can change `DarkMode`), re-read settings,
  re-apply the appearance and re-sync every menu toggle (fixes W-11).
* Optional Mac-only "Match System Appearance" (stored outside settings.json, e.g. UserDefaults) is
  allowed only if it doesn't change `DarkMode` semantics (Q-2).
* Rich-text views: `NSTextView.backgroundColor = AAEditorBg`, `drawsBackground = true`, default
  `textColor`/typing attributes `AAEditorFg`, insertion point dark; set
  `textView.appearance = NSAppearance(named: .aqua)` on the editor's scroll view so spelling
  underlines, selection and link colours stay legible on paper in dark mode (SHELL-153).

#### 6.6.3 Semantic hard-coded colours (inventory for the design system)

| hex | meaning / where |
|---|---|
| `#D45050` | error/danger text (login, password, lock dialogs, shared OFFLINE, crew/work-order overdue, quick work) |
| `#3CA05A` | shared-save healthy |
| `#2E9E5B` | OK/green status (floating window, crew, work orders) |
| `#E8890C` | due-soon amber (crew, work orders) |
| `#C9A227` | warning gold (crew, work orders) |
| `#8A8A8A` | neutral/unknown grey (floating, crew, work orders) |
| `#E53935`, `#D32F2F` | overdue red (board, palette) |
| `#2E7D32` / `#EF6C00` / `#C62828` | diff added / changed / removed (DiffWindow); `#2E7D32` also Board done |
| `#6B6B6B` | board muted |
| `#FFE066` | search hit highlight |
| `#FFE699` (ARGB 255,255,230,153) | locked-text sentinel background in rich text — **data value**, must be preserved exactly |
| `#4FC3F7` / `#FFB74D` / `#A5D6A7` | kind colours: Equipment / Task / Procedure (map, floating window) |
| `#9C6ADE` | crew item accent (floating window) |
| `#E05252` | overdue (floating window) |
| `#3A7BD5` → `#00A88E`, `#EAF6FF` | floating window header gradient / tint |
| `#F0A030` | SIRE amber |
| `#9AA0A6` | hyperlink-ish grey in editor/HTML converter |
| `#6B7785`, `#22808080` | planner muted / grid |
| `#1E88E5` | default card colour |
| `#DDDDDD` | splash border |
Map each to a named colour asset (`AAStatusDanger`, `AAStatusOK`, …) with the same value in both
appearances unless the owning spec says otherwise.

#### 6.6.4 Typography (SHELL-154)

* Consolas is not part of macOS and can't be redistributed. Resolve once at launch:
  `NSFont(name: "Consolas", size:)` if installed (e.g. with Microsoft Office) → else
  `NSFont.monospacedSystemFont(ofSize:weight:)` (SF Mono) → else Menlo. Expose
  `AAFont.body(size:)`/`Font.aaMono(_:)`; apply at the root of the main window
  (`.font(.aaMono(13))`) and explicitly in AppKit views. `Font.custom("Consolas")` alone is wrong (it
  falls back to proportional SF).
* Sizes: body 13 pt (Mac standard; WPF effective ≈12 DIP), header brand 22, login brand 28, strip 11,
  editor document 14. Menus use the system font (a Mac menu bar font can't be changed — accepted).
* Keep stored font-family names (e.g. `Consolas` in rich-text XAML) untouched; only the rendering
  substitutes.

#### 6.6.5 Control styling (SHELL-155)

Use native controls; carry over the visual language: 4-pt corner radius on app-drawn buttons/cards,
1-pt borders, thin row separators in every list (`.listRowSeparator(.visible)`,
`.alternatingRowBackgrounds(.disabled)`), hover fill `AAHover` on app-drawn rows, selection
`AASelBg/AASelFg` for app-drawn lists (native `List`/`Table` selection may keep the system accent),
disabled at 45 % opacity, `AccentButton` → `.borderedProminent` + bold, `ToolbarButton` →
`.bordered` `.controlSize(.small)` min width 30. Scrollbars: native overlay scrollers (WPF's 12-px
themed bars are not reproduced). Strikethrough (SHELL-156): SwiftUI `.strikethrough(isDone)`; AppKit
`.strikethroughStyle: NSUnderlineStyle.single.rawValue`.

### 6.7 Tab colours dialog (SHELL-029) on Mac

A sheet on the main window: same intro text, a scrolling `Grid` of rows (label 190 pt, swatch 46×24
rounded 4 with 1-pt border, `ColorPicker` with `supportsOpacity: false` or a `Pick…` button opening
`NSColorPanel` with `showsAlpha = false`, `Default` button), footer `Reset All` (leading), `Cancel`,
`Apply` (default). Work on a copy; commit on Apply only. Store `#RRGGBB` uppercase
(`String(format: "#%02X%02X%02X", r, g, b)` from sRGB components rounded to bytes). Convert
`NSColorPanel` colours to **sRGB** before extracting bytes.

Colour parsing (shared helper, used for `TabColors` and card colours): accept `#RGB`, `#ARGB`,
`#RRGGBB`, `#AARRGGBB` (case-insensitive) and the WPF/.NET known colour names (case-insensitive;
full `System.Windows.Media.Colors` list); optionally `sc#a,r,g,b`. Anything else = invalid (tab: no
custom colour; card: `#FF1E88E5`).

### 6.8 Reminders (SHELL-130..133)

* Tray icon → **`MenuBarExtra`** (MAC-ADAPT) with a template image (monochrome "A" disc), always
  present while AA runs, whose menu shows the headline counts and items `Show Due Dates…` (opens the
  due window) and `Show AA` (activates the main window) — covering balloon click and tray
  double-click. (Optional per Q-4: hide it via a Mac-only preference.)
* Balloon → `UNUserNotificationCenter`: request `.alert, .sound` authorization when the first reminder
  would be posted (or at first main-window appearance); post with fixed identifier
  `"aa.reminder"` (replaces the previous), title `AA — due soon`, body = same text; the delegate's
  `didReceive` → open the due-dates window; `willPresent` → `.banner` so it shows while AA is
  frontmost (Windows balloons show regardless). Same dedup key, same 30-min cadence, same forced
  digest.
* Digest: same `LastDigestDate` logic at launch. MAC-ADAPT (optional): also run it on
  `NSCalendarDayChanged` so a Mac left open overnight gets its digest (Q-8).
* Crew badge also as `NSApp.dockTile.badgeLabel`? Not in WPF — do not add without sign-off.

### 6.9 Files, folders, panels, watchers

* **AppFolder**: `~/Library/Application Support/AA/` (honour `AA_DATA_DIR`). Same file names
  (`data.json`, `settings.json`, `files/`, `crash.log`, `google_client_secret.json`, …).
* **Sandboxing**: persisted absolute paths (`CurrentDataFile`, `SharedSaveFile`, `GoogleDriveFolder`,
  `FolderBuilderBase`) require security-scoped bookmarks if sandboxed. Keep the plain paths in
  settings.json (compat) and store bookmarks separately (UserDefaults keyed by path) — never inside
  settings.json (Flash Sync would carry unknown keys around). Recommended distribution: Developer ID,
  non-sandboxed, which avoids the issue for network shares.
* **Panels**: `NSOpenPanel`/`NSSavePanel` via SwiftUI `.fileImporter`/`.fileExporter` or AppKit.
  UTTypes: `.json`, `.zip`, and a declared `UTType(exportedAs: "com.aa.bundle")` for `.aaz`
  (conforms to `public.zip-archive`, description "AA bundle"). Default names/filters as in 4.4 and
  Appendix A.5. Panel `message` = the WPF dialog title text.
* **Set shared save file** (SHELL-066): `NSSavePanel` always asks "Replace?" for existing files and
  has no public switch to suppress it. MAC-ADAPT: first ask (sheet) `Join an existing shared save
  file…` (NSOpenPanel → existing file → D28 flow) or `Create a new shared save file…` (NSSavePanel →
  if the user confirms replacing an existing file that equals the D28 "No/overwrite" choice). All three
  WPF outcomes remain reachable.
* **Open data folder**: `NSWorkspace.shared.open(appFolderURL)` (Finder). Errors → `Open failed`.
* **Drive folder auto-detect** (SHELL-074) on macOS, in order: `~/My Drive`, `~/Google Drive`,
  `~/GoogleDrive`, each `~/Library/CloudStorage/GoogleDrive-*/My Drive`, `/Volumes/GoogleDrive/My Drive`,
  `/Volumes/GoogleDrive-*/My Drive`. Folder picker: `NSOpenPanel` with `canChooseDirectories`,
  message `Select your Google Drive folder`.
* **FileSystemWatcher** → `DispatchSource.makeFileSystemObjectSource` on the bundle's **directory**
  (`O_EVTONLY`; events `.write, .extend, .rename, .attrib, .link`) or an FSEvents stream with
  `kFSEventStreamCreateFlagFileEvents` filtered to the bundle name; restart the 1.5 s debounce on each
  event. FSEvents does not see changes made by *other* machines on SMB/AFP shares — the 60 s poll is
  the real mechanism (as on Windows); never remove it.
* **Atomic replace**: write `{path}.{uuid-no-dashes-lowercase}.tmp` in the same directory, `fsync`,
  then `rename(2)` (atomic on the same volume, works over SMB). Fall back to
  `FileManager.replaceItemAt` then copy, mirroring `AtomicWrite`.
* **Temp files**: `FileManager.default.temporaryDirectory` with the same name patterns.
* **Encrypt local data file** (SHELL-065): DPAPI → AES-GCM (CryptoKit) with a random 256-bit key in
  the **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
  not synchronizable) — "tied to this user on this Mac". The Windows blob is unreadable on Mac and
  vice versa (by design; a foreign encrypted file ⇒ safe mode). Use a Mac-specific magic (proposed
  `AAENCM1\n`) so each side can tell "encrypted on another platform" apart from corruption and show a
  precise safe-mode message; format owned by the persistence spec. Menu/confirmation text: replace
  "Windows DPAPI (tied to your Windows account)" with "the macOS Keychain (tied to your user account
  on this Mac)" and "PC" with "Mac".
* **Machine name** default identity: `Host.current().localizedName` (or
  `SCDynamicStoreCopyComputerName`); `SafeIdentity` must use the **Windows** invalid-character set
  (4.4) so Mac-produced backup names are valid on Windows/Drive.
* **Timestamps**: model .NET `DateTime` values with an exact type (e.g. `struct DotNetDateTime {
  ticks: Int64; kind: .local(offsetSeconds) | .utc | .unspecified }`) instead of `Date` — a `Double`
  cannot hold 100-ns ticks for current dates, and shared/Drive dedup compares stamps for exact
  equality. Emit 7-digit fractions trimmed of trailing zeros, offset `±HH:mm` for local, `Z` for UTC,
  none for unspecified. Convert to `Date` only for display/arithmetics.
* **GUIDs**: write lowercase (`uuidString.lowercased()`).

### 6.10 Secondary windows mapping (shell-owned opening rules)

| WPF | Mac scene | instance rule |
|---|---|---|
| SearchWindow (non-modal, new each time) | `WindowGroup(id: "search", for: UUID.self)` opened with a fresh UUID | many |
| QuickSwitcherWindow (modal) | sheet on the main window or a floating `NSPanel` (Spotlight-like) | one, modal |
| QuickWorkWindow (single) | `Window(id: "quickWork")` (openWindow focuses an existing one) | one |
| FloatingTasksWindow (single, topmost, borderless) | `Window(id: "due")` + `.windowLevel(.floating)`, `.windowStyle(.plain)` or an `NSPanel` (`.nonactivatingPanel`, `hidesOnDeactivate=false`), 12-pt corner radius, shadow; re-open = activate + refresh | one |
| ActivityLog, UnitConverter (new each time) | `WindowGroup(for: UUID.self)` | many |
| FolderBuilder, DateCalculator, Trash, DiffWindow, ItemPicker, Prompt, Password, TabColors, FlashSync (modal) | sheets on the main window (FlashSync may be a separate modal window due to size) | modal |
| ItemWindow (one per item) | `WindowGroup(id: "item", for: UUID.self)` — SwiftUI focuses the existing window for the same UUID, matching SHELL-054 | one per item |
The shell must still keep a registry of open item windows (flush/SetRepo/orphan/close on quit) —
SwiftUI scenes don't give it for free: register in `onAppear`, unregister in `onDisappear`.

### 6.11 Things that are genuinely impossible / changed on macOS

| item | closest faithful alternative |
|---|---|
| Catch-and-continue for all crashes | 6.1 crash strategy (do/catch + marker + next-launch dialog) |
| Consolas bundled | installed Consolas if present, else SF Mono |
| Custom menu-bar font / WPF menu templates | system menus with SF Symbols |
| Tray balloon with custom duration | UserNotifications banner (system-controlled duration) |
| Notification-area icon | MenuBarExtra |
| NSSavePanel without overwrite prompt | two-step Join/Create flow (6.9) |
| DPAPI | Keychain + AES-GCM (non-portable, like DPAPI) |
| WPF `SystemColors` overrides | `NSApp.appearance` |
| Access-key underscores | none (Mac menus are searchable via Help) |

---

## 7. Test vectors / verification

### 7.1 Pure functions (unit tests)

**Tab contrast** (`0.299R+0.587G+0.114B > 150` → black text):
| colour | luma | text |
|---|---|---|
| `#FFFFFF` | 255 | black |
| `#1E88E5` | 114.908 | white |
| `#FDD835` | 208.481 | black |
| `#FB8C00` | 157.229 | black |
| `#7CB342` | 149.673 | white |
| `#00FF00` | 149.685 | white |
| `#969696` | 150.0 | **white** (not > 150) |
| `#979797` | 151.0 | black |
| `#80FF0000` (alpha ignored) | 76.245 | white |

**Card readable foreground** (`luma/255 > 0.6` → `#1A1A1A`, IEEE-754 doubles, same expression order):
| colour | luma/255 | fg |
|---|---|---|
| `#999999` | 0.6 exactly | **white** |
| `#9A9A9A` | 0.60392… | `#1A1A1A` |
| `#FDD835` | 0.8176 | `#1A1A1A` |
| `#26A69A` | 0.4955 | white |
| `#9E9E9E` | 0.6196 | `#1A1A1A` |
| `#EEEEEE` | 0.9333 | `#1A1A1A` |

**ParseColor**: `null`/`""`/`"  "` → `#FF1E88E5`; `"zzz"` → `#FF1E88E5`; `"#FFF"` → `#FFFFFFFF`;
`"#8F00"` → A=88,R=FF,G=00,B=00; `"#43A047"` → `#FF43A047`; `"red"`/`"Red"` → `#FFFF0000`;
`"#80112233"` → A=80,R=11,G=22,B=33.

**TryBrush for tabs**: `"#12345"` (5 digits) → invalid → theme default; `"transparent"` → valid
(`#00FFFFFF`), contrast luma 255 → black text on a transparent header.

**Colour picker output** (Mac rule: byte = `Int((component * 255).rounded())`, Swift's default
`.toNearestOrAwayFromZero`): sRGB (0.5, 0.25, 1.0) → 127.5/63.75/255 → 128/64/255 → `#8040FF`.
Always uppercase, 7 characters, no alpha (the WPF dialog also drops alpha).

**ApplyTabOrder** (default order D = Equipment, Tasks, Procedures, Vessels, Calendar, Board, Planner,
Map, Crew, Lists, Buckets, Ports, Sire):
* `[]` → D (no change).
* `["TabSire","TabTasks","Bogus","TabTasks"]` → Sire, Tasks, Equipment, Procedures, Vessels, Calendar,
  Board, Planner, Map, Crew, Lists, Buckets, Ports.
* `["CrewTab"]` → Crew, then D without Crew.
* `["TabMap","TabMap","TabMap"]` → Map, then the rest.

**Tab drop** (dragged takes the target's index):
* [A,B,C,D] drag A → C ⇒ [B,C,A,D]; drag D → B ⇒ [A,D,B,C]; drag B → B ⇒ unchanged; drag C → A ⇒
  [C,A,B,D]. Persisted `TabOrder` = all names in the new order.

**Selected tab restore (Mac, fixed)**: `TabOrder=["TabSire", …]`, `SelectedMainTabIndex=0` ⇒ SIRE is
selected (WPF fresh start would select Equipment/Area — W-1).

**AgeVerdict**:
* inc `2026-09-29 10:00:00`, cur `2026-09-28 09:00:00` ⇒
  `Incoming saved: 2026-09-29 10:00:00\nCurrent saved:  2026-09-28 09:00:00\n➜ The incoming data is NEWER than your current data.`
* inc null, cur `2026-09-28 09:00:00` ⇒ `Incoming saved: (no save date)\nCurrent saved:  2026-09-28 09:00:00\n➜ The incoming data has no save date (older format); it may be older.`
* both null ⇒ `…(no save date)\n…(no save date)\n➜ Neither copy has a save date; relative age is unknown.`

**SafeIdentity**: `"Vessel Alpha"` → `VesselAlpha`; `"MV: Star/1"` → `MVStar1`; `"***"` → `AA`;
`"a<b>c|d?"` → `abcd`; `"Ship\t1"` → `Ship1`; `"\u00A0Bridge\u00A0"` → `Bridge` (NBSP kept inside,
trimmed at ends); `"Ω-Vessel"` → `Ω-Vessel`. Backup name at 2026-09-29 14:03:12 local →
`aa-data-VesselAlpha-20260929-140312.zip`.

**Window title**: identity `Vessel-Alpha` → `AA — Vessel-Alpha`; `SetAppIdentity("   ")` → machine
name.

**Crew badge**: `ExpiringCount` 0 → `Crew`; 3 → `Crew  ⚠ 3`. `DaysUntilSignOff` −5, 0, 60 counted;
61 or null not counted.

**Reminder summary** (today 2026-09-29): deadlines 09-28 (task, not done), 09-29 (procedure, Todo),
10-06 (crew step), 10-07 (subtask), 09-20 (task **done**) ⇒ `Summary(1,1,1)`, headline
`1 overdue  ·  1 due today  ·  1 due this week`. No deadlines ⇒ `Nothing due.`; with crew = 2 the
balloon text is `Nothing due.  ·  2 crew contract(s) expiring`. Dedup key
`2026-09-29|1|1|1|0`. A procedure step not done inside a Done procedure still counts.

**Digest**: `LastDigestDate="2026-09-29"`, today 09-29 ⇒ nothing, no dirty mark. `"2026-09-28"` ⇒
set to `2026-09-29`, mark dirty; if Summary.Any or crew > 0 ⇒ due window + notification, else nothing
shown.

**Login**: (`" 44233 "`, `redemption`) ✓; (`44233`, `Redemption`) ✗; (`44233`, ` redemption`) ✗;
(`044233`, `redemption`) ✗. Failure message `Incorrect username or password.`, password cleared.

**Password dialog**: SetNew `""` → `Password cannot be empty.`; `abc` → `Password must be at least 4
characters.`; `abcd`/`abce` → `Passwords do not match.`; `abcd`/`abcd` → OK. Unlock with no password
set: `x` → `Wrong password.`; `redemption` → OK.

**UiState restore**: `{WindowWidth:150, WindowHeight:900}` → width unchanged (default), height 900;
`WindowState:"Minimized"` → normal; `"Maximized"` → zoomed; `"maximized"` → normal (case-sensitive);
`"2"` → Maximized in WPF (numeric parse) — Mac: accept `"2"` as Maximized, other numerics → normal.

**Coordinate conversion** (primary screen 1512×982 pt): Mac frame (x 100, y 62, w 1280, h 820) ⇒
`WindowLeft 100`, `WindowTop 982 − (62+820) = 100`. Round-trip back must yield the same frame.

**JSON shape** (compact, nulls omitted) of a fresh `UiState` (all defaults):
`{"SelectedMainTabIndex":0,"ShowShortcutBar":true,"QuickViewPinIds":[],"TabColors":{},"TabOrder":[],"SortAZ":{},"GroupExpanded":{},"CrewTableColumns":[],"CrewTableShownColumns":[]}`
(property order as declared in `UiState`; Mac encoders must preserve unknown keys from
`ExtraData`).

**DateTime round-trip**: parse `"2026-09-29T14:03:12.1234567+02:00"` and re-serialise → identical
string; `"2026-09-29T14:03:12+02:00"` → identical (no fraction added); `"2026-09-29T00:00:00"`
(unspecified) → identical (no offset added). Two stamps differing by 1 tick compare unequal.

### 7.2 Shared-save state machine (integration tests with a temp folder)

1. No bundle, folder exists → `SetSharedOnline(false)` → indicator `🔗 Shared save on`.
2. Folder deleted → `⚠ Shared save OFFLINE since HH:mm — retrying`, red; folder back, bundle present
   and not newer → back to green (`Shared save on` or `Shared synced HH:mm` if a sync happened).
3. Push throws (read-only file) → `⚠ Shared save NOT SAVING since HH:mm — last write failed`; a
   subsequent reachability check alone must **not** clear it; a successful push clears it.
4. Bundle stamp == `sharedLastSeen` → no reload, no prompt.
5. Bundle newer, no unsynced changes → silent reload, status `Reloaded the shared save from “X” (HH:mm:ss).`
6. Bundle newer, local edit pending → prompt D27; "Keep Mine" → `sharedLastSeen = bundle stamp`,
   no re-prompt for that stamp.
7. Torn bundle (truncated zip) → `PeekZipLastModified` null → no state change; or import throws →
   status `Shared reload skipped (busy): …`, local data unchanged.
8. On quit with bundle absent → bundle created; with bundle unreadable → not overwritten.

### 7.3 Manual / UI verification checklist

* Launch: splash 2.4 s (floating, centred, white, bordered) → login → main window restores size,
  position (clamped), section, selections; menus disabled until main.
* Dark mode toggles live in every open window, menu and alert; persists; the note editor stays white
  paper with dark ink in both modes.
* Drag sections in the sidebar; relaunch; order persists; ⌘1…⌘9 follow the new order; Windows build
  reading the same data shows the same tab order.
* Tab colours round-trip with the Windows build (`#RRGGBB` uppercase), including `CrewTab`.
* ⌘Z in a text field undoes typing; ⌘Z in the item list restores the last deleted item/batch (also
  after relaunch); `Nothing to undo.` when the Trash is empty.
* Quit with a detached item window containing unsaved typing → text persisted.
* Reminder notification appears, click opens the due window; not repeated within the same situation.

---

## 8. Known Windows defects, discrepancies & decisions required

| id | issue | faithful behaviour | recommended Mac behaviour |
|---|---|---|---|
| W-1 | Selected tab index applied before tab order at startup (`MainWindow.xaml.cs:1235` vs `:1243`) | wrong tab on launch with custom order | apply order, then index |
| W-2 | Shared-save tooltip/info say "every 10 minutes"; real push cadence 1 min (`:940`) | keep strings | correct text to "every minute" (Q-7) |
| W-3 | PROGRESS says identity is in backup filenames; OAuth uploads are named `aa-data-{timestamp}.zip` (identity only in appProperties) | keep | keep (Drive spec may choose to add identity) |
| W-4 | `SharedSaveTick` pushes only if `IsDirty`, which the 750 ms repo autosave clears almost immediately → periodic shared push rarely fires; data reaches the bundle mainly on quit/next edit burst | as coded | push when `IsDirty ∨ LastModified > lastSyncedStamp` (the "unsynced" predicate already used by the pull) |
| W-5 | On-close "don't clobber a newer bundle" test runs after `Save()` re-stamps local = now → almost always pushes (last-writer-wins) | as coded | capture the stamp **before** the final save; if the bundle's stamp ≠ `sharedLastSeen` and > `lastSyncedStamp`, a peer wrote since our last sync → ask (Reload/Overwrite/Quit without pushing) or skip the push |
| W-6 | `NavigateToItem` uses fixed tab indices 0–3 → wrong tab after reordering | as coded | select the section by key |
| W-7 | Reloads (shared/Drive/import) re-apply the incoming file's window geometry & per-device keys | window jumps | keep local geometry & per-device keys on reload (Q-3) |
| W-8 | `LastDigestDate` travels in shared bundles → one PC's digest suppresses another's that day | as coded | keep (data compat) or also track per-device in UserDefaults (Q-8) |
| W-9 | `DoSave`, `DoAutosave`, Export ZIP, Drive saves flush only the 4 hierarchy editors (not item windows / SIRE body); PROGRESS implies all | as coded | always flush all editors before any save/export (superset, no downside) |
| W-10 | Clearing the Gemini key only nulls it in memory; `WriteSettings` falls back to the old file value, so it reappears next launch | as coded | actually remove it (persistence spec) |
| W-11 | Flash Sync can change `DarkMode`, but after apply the theme and menu checkmark are not refreshed until restart | as coded | re-apply appearance + resync toggles after every reload |
| W-12 | PROGRESS: "Esc/Ctrl+W close tool windows" — no Ctrl+W exists; Esc only in IsCancel dialogs + quick switcher | — | ⌘W closes any window natively; Esc on the same dialogs |
| W-13 | PROGRESS Styling: "selected tab inverts (black bg / white text)" — superseded by the underline+bold template | — | follow the template (6.2) |
| W-14 | Final save errors on close are silently ignored | as coded | offer Retry/Quit Anyway (Q-5) |
| W-15 | Crash dialog says "had to stop" while the UI-thread path keeps running | keep text | keep text |
| W-16 | PromptWindow prompt text doesn't wrap (identity prompt clipped) | — | wrap |

### 8.1 Open questions (need a product-owner decision)

* **Q-1** Light-theme `Muted` and `BorderB` are pure black in WPF. Keep exact (monochrome identity)
  or use `secondaryLabelColor` / `separatorColor` on Mac? (Recommendation: native values; all other
  tokens exact.)
* **Q-2** Offer a Mac-only "Match System Appearance" option in addition to the synced `DarkMode`
  bool? (Must not change `DarkMode` semantics.)
* **Q-3** On reloads (shared/Drive/import/Flash apply), keep the Mac's current window geometry and
  per-device `Ui` keys instead of adopting the incoming file's (W-7)?
* **Q-4** Replace the always-visible tray icon with an always-visible `MenuBarExtra`, or make it
  optional?
* **Q-5** On quit, if the final save fails, show Retry / Quit Anyway / Cancel instead of silently
  quitting (W-14)?
* **Q-6** ⌘R opens the due-dates window even when the rich-text editor has focus (WPF: Ctrl+R there
  right-aligns the paragraph). Accept?
* **Q-7** Fix the shared-save text "every 10 minutes" → "every minute" (W-2); and adopt the W-4/W-5
  fixes (periodic push actually fires; on-close guard actually protects a newer peer bundle)?
* **Q-8** Run the daily digest also at midnight rollover, and/or track the digest date per device so
  a shared-save pull can't suppress it (W-8)?
* **Q-9** Confirm with a real Windows-saved note what attributes `TextRange.Save(DataFormats.Xaml)`
  writes on the root `<Section>` (expected `FontFamily="Consolas"`, `FontSize="14"`,
  `Foreground="#FF1A1A1A"`), so the XAML converter treats them as document defaults.

---

## Appendix A — String catalogue

### A.1 Window titles
`AA` → `AA — {identity}`; `AA — Sign in`; `Password`; `Customize tab colors`; `Input` (PromptWindow
default, replaced by the caller's title); secondary windows (owned elsewhere): `Search`, `Go to item`,
`Quick work — all tasks & procedures`, `Overdue, today & tomorrow`, `Activity log`,
`Unit converter`, `Trash`, `Review changes before importing`, `Flash Sync with iPhone`, `Item`.

### A.2 Menu headers (WPF, with access keys)
File: `_Save` (`Ctrl+S`), `Save _As...`, `_Reload from disk`, `_Import from file...`,
`_Trash (restore deleted items)...`, `Encr_ypt local data file (this PC)`, `Set s_hared save file...`,
`Stop shared save file`, `Set app _identity...`, `Open data _folder`, `_Export data folder (ZIP)...`,
`I_mport data folder (ZIP)...`, `Export _text only (no attachments)`,
`Save a copy to Google _Drive (synced folder)`, `Set Google Drive folde_r...`,
`Upload backup to Google Drive (O_Auth)...`, `_Load backup from Google Drive (OAuth)...`,
`Set Google OAuth _client (client_secret.json)...`, `Sign out of _Google`,
`_Sync to Google Drive on save`, `C_heck Google Drive for newer save`,
`Flash S_ync with iPhone (QR)...`, `E_xit`.
Tools: `_Folder builder...`, `Date _calculator...`, `Floating _due-dates window`,
`Quick _work window (Ctrl+N)`, `Quick s_witcher (Ctrl+O)`, `_Activity log...`, `U_nit converter...`,
`Import COMPAS _crew (.xlsx)...`, `Check crew contract e_xpiries`, `SIRE 2.0 e_xport...`,
`Set _Gemini API key...`, `Set / change _password...`, `_Lock now`.
View: `🌙 _Dark mode`, `⌨ _Shortcut bar`, `🎨 _Customize tab colors...`. Top level: `_About`.
(Tooltips: quoted per item in section 2.)

### A.3 Dialogs (title — buttons/icon — text)
* **D1** `Data file unreadable — safe mode` — OK/Warning —
  `Your data file is present but could not be read — it may be locked by another program, still being written, corrupt, or (if you enabled local encryption) created under a different Windows account.\n\nAA opened in READ-ONLY safe mode and will NOT save over it, so nothing already on disk is lost. Close AA, restore a copy if needed (File ▸ Trash or a backup), then reopen.`
* **D2** `Newer data format` — OK/Information —
  `This data file was saved by a newer version of AA (format v{v}; this build understands v{CurrentSchemaVersion}).\n\nYou can keep working — newer fields are preserved — but update AA on this PC to avoid missing new features' data.`
* **D3** `Google Drive — one more sign-in needed` — OK/Information —
  `AA can now find your backups anywhere in Google Drive — including files you put there by hand, that Google Drive for desktop synced in, or that the iPhone app uploaded. Previously it could only see files AA itself created.\n\nThat needs broader permission than your existing sign-in granted, so the next Drive action will ask you to sign in to Google once more. AA asks for read access to your Drive plus write access only to its own files — it cannot change or delete anything it did not create.`
* **D4** `Safe mode — not saving` — OK/Warning —
  `AA is in read-only safe mode because the data file couldn't be read at startup, so saving is disabled to protect the file on disk. Close and reopen AA once the file is available.`
* **D5** `Save failed` — OK/Error — `{exception message}`
* **D6** `Google Drive sync` — OK/Information — `Turn on 'Sync to Google Drive on save' and set a Google OAuth client first.`
* **D7** `Drive sync check failed` — OK/Error — `{message}`
* **D8** `Google Drive sync` — OK/Information — `Sync is on. Set your Google OAuth client via File ▸ 'Set Google OAuth client...' so saves can reach Drive.`
* **D9** `Save As failed` — OK/Error — `{message}`
* **D10** `Confirm reload` — Yes/No/Warning — `Reload data from disk? Unsaved changes will be lost.`
* **D11** `Import failed` — OK/Error — `{message}` (file import, both read and apply; also ZIP import)
* **D12** `Open failed` — OK/no icon — `{message}`
* **D13** `Export failed` — OK/Error — `{message}`
* **D15** `Confirm import` — Yes/No/Warning — `Replace your current data with '{sourceName}'?\n(Could not read a change preview for this source.)`
* **D16** `Saved to Google Drive` — OK/Information — `A backup was saved to your Google Drive folder:\n\n{zip}\n\nGoogle Drive for desktop will sync it to the cloud.`
* **D17** `Save to Google Drive failed` — OK/Error — `{message}`
* **D18** `Google OAuth` — OK/Information —
  `Google OAuth client saved.\n\nMake sure in Google Cloud Console you have:\n  • Enabled the Google Drive API\n  • Created an OAuth client of type 'Desktop app'\n  • Added your Google account as a test user (if the consent screen is in Testing)\n\nNow use File ▸ 'Upload backup to Google Drive (OAuth)...'.`
* **D19** `Set OAuth client failed` — OK/Error — `{message}`
* **D20** `Google OAuth` — Yes/No/Question — `No Google OAuth client is configured yet. Choose your client_secret.json now?`
* **D21** `Uploaded to Google Drive` — OK/Information — `Uploaded '{name}' to your Google Drive (folder 'AA Backups').` + (`\n\n{link}` when a link is returned)
* **D22** `Google Drive upload failed` — OK/Error — `{message}`
* **D23** `Load from Google Drive` — OK/Information — `No backups were found in your Google Drive 'AA Backups' folder.\n\nUpload one first with File ▸ 'Upload backup to Google Drive (OAuth)...'.`
* **D24** `Load from Google Drive failed` — OK/Error — `{message}`
* **D25** `Locate Google Drive` — OK/Information — forced: `Select your Google Drive folder — the local folder that Google Drive for desktop syncs.`; auto: `Couldn't find your Google Drive folder automatically. Please locate the local folder that Google Drive for desktop syncs.`
* **D26** `About AA` — OK/Information — `Created by B.E.P. Avida - May 2026`
* **D27** `Shared save updated` — Yes/No/Question —
  `The shared save file was updated by another copy of AA.\n\nReload it now (data + attachments)? Changes on this PC that aren't in the shared file yet will be lost.\n\nYes = reload (discard my changes)\nNo = keep mine (they overwrite the shared file on the next save)`
* **D28** `Shared save file` — Yes/No/Cancel/Question —
  `'{fileName}' already exists.\n\nUse ITS contents (data + attachments) as your data (Yes), or keep your current data and overwrite it (No)?`
* **D29** `Shared save file` — OK/Information —
  `This copy of AA now saves to and syncs from:\n\n{path}\n\nIt bundles your data AND all attachments, autosaves there every 10 minutes, and reloads automatically when another copy of AA updates it. Point every PC at this same file.`
* **D30** `Set shared save file failed` — OK/Error — `{message}`
* **D31** `Stop shared save file` — Yes/No/Question — `Stop using the shared save file and save locally on this PC only from now on?\n(Your current data is kept.)`
* **D32** `Safe mode` — OK/Warning — `Can't change encryption in read-only safe mode.`
* **D33** `Encrypt local data file` — OK/Cancel/Information —
  `Encrypt this PC's data file at rest with Windows DPAPI (tied to your Windows account)?\n\n• Only THIS machine's local file is encrypted.\n• Shared-save bundles, ZIP exports and Google Drive backups stay portable plaintext, so syncing between PCs still works.\n• It can only be read back under your Windows account on this PC.`
* **D34** `Encrypt local data file failed` — OK/Error — `{message}`
* **D35** `AA — error` — OK/Error — `AA hit an unexpected error and had to stop:\n\n{ex.Message}\n\nThe full details were written to:\n{path}`
* **D36** `Contract expiries` — OK/Information|Warning — see SHELL-098.
* Prompts: **P1** `Gemini API key` / `Paste your Google Gemini API key (stored locally in settings.json, never committed):`;
  **P2** `App identity` / `Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save:`
* Picker: `Choose a backup to load from Google Drive (newest first)`.

### A.4 Status-line messages (StatusBlock)
Startup/load: `Loaded — {path}` · `⚠ Data file unreadable — read-only safe mode (not saving).` ·
`Reloaded {HH:mm:ss}`.
Save: `Saved {HH:mm:ss}` · `Autosaved {HH:mm:ss}` · `Autosave — no changes ({HH:mm:ss})` ·
`Autosave failed: {msg}` · `Exported to {path}` · `Exported data folder to {path}` ·
`Imported {file} (text only — your attachments are untouched)` · `Imported {file} (with attachments)`.
Drive: `Syncing to Google Drive…` · `Synced to Google Drive {HH:mm:ss}` · `Drive sync failed: {msg}` ·
`No AA save found on Google Drive yet.` · `Google Drive is up to date ({HH:mm:ss}).` ·
`Newer save on Google Drive — downloading to preview…` / `Newer save on Google Drive from “{who}” — downloading to preview…` ·
`Kept local version (Drive has a newer one).` ·
`Loaded newer save from Google Drive (text only — attachments unchanged).` ·
`Loaded newer save from Google Drive (with attachments).` · `Drive check failed: {msg}` ·
`Google Drive sync on save: ON` · `Google Drive sync on save: OFF` ·
`Saved a copy to Google Drive: {zip}` · `Google OAuth client set.` ·
`Signing in to Google and uploading… (a browser window may open)` · `Uploaded to Google Drive: {name}` ·
`Google Drive upload failed.` · `Signing in to Google and listing backups… (a browser window may open)` ·
`No backups found on Google Drive.` · `Downloading {name}…` · `Load from Google Drive cancelled.` ·
`Loaded backup from Google Drive: {name} (text only — attachments unchanged).` /
`Loaded backup from Google Drive: {name} (with attachments).` · `Load from Google Drive failed.` ·
`Signed out of Google (OAuth token cleared).` · `Google Drive folder set: {path}`.
Shared: `Shared save written {HH:mm:ss} (data + attachments).` ·
`Shared save (on close) written {HH:mm:ss} (data + attachments).` · `Shared save failed: {msg}` ·
`Shared save (on close) failed: {msg}` · `Reloaded the shared save ({HH:mm:ss}).` /
`Reloaded the shared save from “{who}” ({HH:mm:ss}).` · `Shared reload skipped (busy): {msg}` ·
`Shared save file set — {path}` · `No shared save file is set.` ·
`Stopped using the shared save file (now saving locally).`
Other: `Exports carry text only (no attachments)` · `Exports carry everything, attachments included` ·
`Applied changes received from the iPhone` · `Dark mode on.` · `Dark mode off.` ·
`App password updated.` · `Locked. Locked containers and entries will require re-unlocking.` ·
`Nothing to undo.` · `Restored {n} deleted items (Ctrl+Z).` · `Restored the last deleted item (Ctrl+Z).` ·
`Gemini API key cleared.` · `Gemini API key saved.` · `App identity set: {identity}` ·
`Local data file is now encrypted at rest.` · `Local data file is now plaintext.`
(On Mac replace "(Ctrl+Z)" with "(⌘Z)", "PC" with "Mac" where the text describes this machine.)

### A.5 File dialog parameters
See SHELL-061/063/066/070/071/077 and 4.4 (filters, default names, titles, initial folders).

---

## Appendix B — WPF control styles (App.xaml) for reference

| control | properties | states |
|---|---|---|
| Window (implicit; not applied to subclasses) | Bg, Fg, Consolas, 13 | — |
| TextBlock | Fg, Consolas | — |
| TextBox / PasswordBox | bg PanelAlt, fg Fg, border BorderB 1, caret Accent, Consolas, padding 6,4 | — |
| Button | bg PanelAlt, fg Fg, border BorderB 1, Consolas, padding 10,5, hand cursor; template Border radius 4, centred content | hover: bg HoverBg, border Fg; disabled: opacity 0.45 |
| AccentButton | Button + bg Panel, bold | as Button |
| ToolbarButton | Button + padding 8,3, margin 2,0, MinWidth 30 | as Button |
| ScrollBar | width/height 12, track Panel, thumb BorderB radius 3 margin 2, no arrows | vertical track reversed |
| ListBox / ListView / TreeView | bg Panel, fg Fg, border BorderB, Consolas | — |
| TreeViewItem | Fg, Consolas | — |
| ListBoxItem | padding 6,4, transparent bg, stretch; bottom separator 1 px BorderB | hover HoverBg; selected SelBg/SelFg |
| ListViewItem | same, `GridViewRowPresenter` | same |
| GridViewColumnHeader | bg PanelAlt, border 0,0,1,1 BorderB, padding 8,4, left, Consolas | hover HoverBg |
| ComboBox | bg Panel, border BorderB, radius 4, padding 6,3, arrow triangle 8×4 (Fg) right margin 8; editable text transparent; popup Panel/BorderB radius 4, slide animation, min width = control | toggle hover HoverBg |
| ComboBoxItem | padding 6,4, radius 3 | hover HoverBg; selected SelBg/SelFg |
| CheckBox / RadioButton | Fg, Consolas | — |
| Calendar / CalendarDayButton / CalendarButton | Panel/Fg/BorderB; day buttons transparent | — |
| DatePicker / DatePickerTextBox | PanelAlt, Fg, BorderB, caret Accent, Consolas | — |
| ToolTip | bg Panel, fg Fg, border BorderB 1, Consolas | — |
| TabControl | bg Bg, border BorderB | — |
| TabItem | fg Fg, bg Panel, Consolas, padding 14,6; Border 1,1,1,0 radius 4,4,0,0 margin 2,0,0,0; header text inherits the TabItem foreground; 3-px Accent underline (margin −2,0,−2,−1) | hover: border Accent; selected: underline visible, border Accent, bold |
| Menu | bg Panel, fg Fg, Consolas | — |
| Separator | bg BorderB, margin 4,3, height 1 | — |
| MenuItem | transparent, Fg, Consolas; radius 3; columns icon(min 20)/header(margin 6,4)/gesture(Muted, margin 18,0,8,0)/arrow; checkmark path `M0,5 L4,9 L11,1` stroke 2; submenu popup Panel/BorderB radius 3 padding 2, fade | highlighted HoverBg; disabled Muted; checked shows ✓ and hides icon; top-level: popup below, no icon column |
| ContextMenu | bg Panel, fg Fg, border BorderB 1, radius 3, padding 2, Consolas | — |
Editor surface (ContainerEditor, owned elsewhere): `EditorBg`/`EditorFg`, Consolas 14.

## Appendix C — Maritime icons & card palette (`MaritimeIcons.cs`)

Icons (glyph, name) in order: ⚓ Anchor · 🚢 Ship · ⛴️ Ferry · ⛵ Sailboat · 🛥️ Motorboat · 🛟 Lifebuoy ·
⛑️ Rescue · 🧭 Compass · 🗺️ Chart · 🛞 Helm/Wheel · ⚙️ Engine · 🔧 Wrench · 🛠️ Tools · 🧰 Toolbox ·
🔩 Fasteners · ⚡ Electrical · 💡 Lights · 🔦 Torch · 📡 Radar · 📻 Radio · 📞 Phone · 🔥 Fire ·
🧯 Extinguisher · 🚨 Alarm · ⚠️ Warning · ⛽ Fuel · 🛢️ Oil/Bunker · 💧 Fresh water · 🌊 Sea/Ballast ·
❄️ Reefer · 🌡️ Temperature · 📦 Cargo · 🗃️ Stores · 🗂️ Files · 📁 Folder · 📄 Document · 📋 Checklist ·
📅 Schedule · 🩺 Medical · 🧪 Lab/Test · 🪝 Hook/Crane · 🔗 Link · 🚪 Door/Hatch · 🪟 Bridge ·
🧑‍✈️ Crew · 🌐 Network · ☎️ Comms · 🧭 Navigation (same glyph as Compass) · 🔔 Bell · ⭐ Favourite.
Glyphs are stored verbatim in `QuickCard.Icon` including variation selectors (U+FE0F) and ZWJ
sequences (🧑‍✈️) — compare/store as exact Unicode scalars, never normalise. Default `⚓`.

Palette (`#AARRGGBB`): `#FF1E88E5 #FF3949AB #FF00897B #FF43A047 #FF7CB342 #FFFDD835 #FFFB8C00
#FFF4511E #FFE53935 #FFD81B60 #FF8E24AA #FF5E35B1 #FF546E7A #FF6D4C41 #FF26A69A #FF455A64 #FF263238
#FF9E9E9E #FFEEEEEE #FFFFFFFF`.

App icon art (for the Mac `AppIcon`/Icon Composer re-draw at 1024 px): outer ring `#1B1B1B`, ring
`#313131`, face `#4F4F4F`, highlight ring `#626262`, letter "A" bold sans in `#87D639` (lime green),
transparent corners. Source frames max out at 256 px (and `360_A.png` is only 100 px), so a vector
re-draw is required for the 512@2x/1024 slot and a macOS 26 layered (Liquid Glass) icon.

---

## Addendum: Build, distribution & smoke-test parity (PROGRESS build/verification sections)

This addendum adds the **build, packaging, distribution and launch-environment contract** to the shell
spec. It covers what PROGRESS records under *How to run*, *Portable self-contained build*,
*Framework-dependent build*, *Project layout*, *Verification* and *Latest portable build*, plus the smoke
test repeated at the end of nearly every PROGRESS update. `mac/Package.swift`, `mac/Scripts/build-app.sh`
and the app's launch code must satisfy it. A verifier runs its checklist before calling a Mac build
equivalent to a Windows publish.

**Sources read for this addendum:** `PROGRESS.md` lines 1–45 (summary, How to run, both publish recipes),
340–371 (Project layout, Verification), 459–462 (Latest portable build), 725–746 (splash verification,
shared-save and `AA_DATA_DIR` verification), 826–830 (the Ctrl+R startup crash that introduced crash
logging), 972–985 (interop harness, "compiles on macOS"), and every "Build: … 0 warnings / 0 errors" line;
`AA/AA.csproj`; `AA/App.xaml.cs`; `AA/Services/DataStore.cs` (`ResolveAppFolder`, `LoadSettings`, `Load`,
`Save`/`WriteData`, `DefaultIdentity`); `AA/FlashSync/FlashQrDecoder.cs` (`EnsureModels`);
`AA/Sire/SireBank.cs` (`EnsureLoaded`); `AA/Models/Models.cs` (`UiState` declaration order);
`Tests/FlashSync.Interop/*`; the repo-root `.gitignore` and `mac/.gitignore`; `mac/Docs/ARCHITECTURE-BRIEF.md`
(Toolchain & packaging, Data compatibility); `mac/Docs/original-source-checksums.sha256`. From the other
specs: 01 (DATA-004, DATA-010…013, §4.12, §6.2, §6.5, §6.7, §6.8, §6.10), this spec (§1.3, SHELL-001…005,
§6.1, §6.9), 05 §6.6/§6.9, 07 §7, 10 §6.2, 12 §2/§6, 13 §6.4–6.8 and 14 §6.2–6.3. The host toolchain was
checked: Apple Swift 6.4, Xcode 27.0, an arm64 host, with `iconutil`, `sips`, `codesign`, `lipo`, `plutil`
and `actool` present.

**IDs.** Features are `SHELL-170…SHELL-207`, in groups N–Q, continuing section 2. Windows defects are
`W-17…W-21` and open questions `Q-10…Q-17`, both continuing section 8. Section numbers inside this addendum
carry the prefix `BD.` (build & distribution).

**Supersessions.** Where this addendum is more specific than earlier text, it wins for the Mac build:
* 03 §6.9 uses `UTType(exportedAs: "com.aa.bundle")` and 01 §6.7 uses `com.bepavida.aa.bundle`. Both become
  **`com.eriskay.aa.bundle`** (SHELL-185). This matches the bundle id `com.eriskay.aa` and the
  `com.eriskay.aa.*` pasteboard and drag types already used by 05 §6.6 and 07 §7.
* 01 §6.2 and 10 §6.2 recommend "Developer ID, hardened runtime, not sandboxed". The default becomes
  **ad-hoc signed, hardened runtime, not sandboxed**. Developer ID with notarisation is the documented
  upgrade path (SHELL-188, Q-15). The *not sandboxed* decision is unchanged.
* 01 DATA-010 and 03 §6.9 say `AppFolder` honours `AA_DATA_DIR`. That is still true, but a **`--data-dir`
  launch argument now takes precedence** over it (SHELL-193).

### BD.1 Overview

#### BD.1.1 Purpose and position

The Windows app ships as one file, `AA.exe`. A user copies it anywhere and double-clicks it. There is no
installer, no registry entry, no runtime to install and no need for admin rights. Everything the app needs
is inside that file: the icon, the splash image, the 3.35 MB SIRE question bank and the Flash Sync QR
detector weights.

The app's *data* never lives next to the exe. It goes to `%LOCALAPPDATA%\AA`, or to the folder named by the
`AA_DATA_DIR` environment variable. That variable is the developer's hook for a portable data folder and for
isolated tests.

A Windows release is accepted when:
* `dotnet build` reports 0 warnings and 0 errors;
* the headless harnesses pass;
* a manual smoke run shows splash → login (44233 / redemption) → main window.

The Mac port must make the same promises in Mac form:
* one self-contained `AA.app` that runs on any Mac able to run macOS 26, with nothing else installed;
* every resource carried inside the bundle;
* data kept outside the bundle, in Application Support or an overridden folder;
* a way to point the app at a portable data folder even when it is launched from Finder;
* loud failure, never silent, when it cannot start;
* an equivalent build gate and launch smoke test.

#### BD.1.2 Windows guarantees → Mac contract

| # | Windows guarantee (evidence) | Mac contract |
|---|---|---|
| 1 | One self-contained x64 `AA.exe` that needs no .NET runtime. Built with `--self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true` (PROGRESS 17–28, 459–461) | One self-contained `AA.app` with no third-party runtime or framework (SHELL-180) |
| 2 | "runs on any 64-bit Windows machine": x64 only, because of the OpenCV natives | Universal arm64 + x86_64; runs on any Mac that runs macOS 26 (SHELL-181) |
| 3 | "Copy it anywhere; it is fully portable" (PROGRESS 28, 461) | Runs from any folder or volume and never writes into itself. Gatekeeper and translocation are handled (SHELL-180, 189, 190, 191) |
| 4 | Every resource embedded (`AA.csproj` `Resource` / `EmbeddedResource`) | Every resource in `Contents/Resources`, byte-identical where portable, and found without traps (SHELL-184, 198) |
| 5 | Icon is `AA.ico`, via `ApplicationIcon` | `AppIcon.icns`, plus an optional Icon Composer asset (SHELL-184) |
| 6 | Portable data folder via `AA_DATA_DIR` (DataStore.cs:32–37; PROGRESS 741) | `--data-dir` > `AA_DATA_DIR` > Application Support, with a recipe for Finder launches (SHELL-192…196) |
| 7 | Startup failures are never silent: `crash.log` + dialog (PROGRESS 826–830; SHELL-001) | Same file and format, a reachable fallback, and a data-folder pre-flight check (SHELL-194, 197) |
| 8 | `dotnet build` 0 warnings / 0 errors; harness suites green | `swift build` (debug and release) with warnings as errors; `swift test` green (SHELL-200, 201) |
| 9 | The publish recipe produces `publish\AA.exe` (~80–112 MB) | `build-app.sh` produces `mac/dist/AA.app` and a zip (SHELL-202, 203) |
| 10 | Smoke: self-extracts, splash, login 44233/redemption, main window (PROGRESS 462, 729) | Manual and automated smoke (SHELL-204, 205), cross-version data smoke (SHELL-206), clean-machine test (SHELL-207) |
| 11 | A framework-dependent variant exists (`publish-fd`, needs .NET 10) | Not needed: the Mac build is already small and runtime-free (SHELL-174) |

#### BD.1.3 Mac startup sequence with the launch additions (extends §1.3)

```
AAMain.main()  (a custom @main that starts the SwiftUI App)                              [Mac]
  0a. opts = parseLaunchArguments(CommandLine.arguments)                    (BD.3.1)
  0b. if opts.version: print the version line to stdout, exit(0)            (no UI, no AppFolder access)
  AAApp.main() → AppDelegate.applicationWillFinishLaunching
  1.  AppFolder = resolveAppFolder(opts, environment, cwd, home)            (BD.3.2) — fixed for the process
  2.  install the crash sinks for <AppFolder>/crash.log                      (SHELL-001, SHELL-197)
  3.  preflight(AppFolder); on failure alert Try Again / Quit, in a loop     (BD.3.3)  [Windows: W-18]
  4.  DataStore.LoadSettings(); apply the appearance                         (§1.3 steps 2–3)
  5.  if running unbundled: setActivationPolicy(.regular), activate          (BD.3.8)
  6.  splash 2.4 s → login → main window + OnLoaded pipeline                 (§1.3 steps 5–19)
        documents opened before step 6 completes are queued                 (BD.3.7)
  7.  if translocated: one informational sheet on the main window            (BD.3.6)
  8.  drain the queued documents one at a time through the import review gate (BD.3.7)
  with opts.smokeTest, the harness drives step 6 and then quits through the normal close pipeline (BD.3.12)
```

For reference, Windows installs its crash handlers before `LoadSettings`. `DataStore.AppFolder` there is a
static property, computed the first time `DataStore` is touched: during `LoadSettings`, or during
`ReportCrash` if a crash came first. On the Mac the folder is resolved first (step 1) so the crash sinks
know where to write. As on Windows, the data folder is created before the splash, so exiting at the login
leaves an empty folder and writes nothing else.

### BD.2 Feature checklist

#### N. Windows baseline (what is being matched)

**SHELL-170 — Single self-contained executable.** The Windows release is built with:
```
dotnet publish AA/AA.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o publish
```
This produces `publish\AA.exe`. The flags do the following:
* `--self-contained` bundles the .NET 10 runtime.
* `PublishSingleFile` puts every managed assembly into the exe.
* `IncludeNativeLibrariesForSelfExtract` also packs the native DLLs (OpenCV and the WPF natives). The host
  **extracts them to a per-user cache on first launch**, so the first launch is slower.
* `EnableCompressionInSingleFile` compresses the payload.
* `-r win-x64` is the only runtime identifier. OpenCvSharp's `runtime.win` natives are x64, and this also
  keeps the x86 natives out.

The `.pdb` beside the exe holds optional debug symbols. OutputType is `WinExe`, so there is no console.

Size history in PROGRESS:

| Size | Where PROGRESS records it |
|---|---|
| ~72 MB | Verification section |
| ~76.5 MB | 2026-07-06 splash update |
| ~80 MB | 2026-07-08 "Latest portable build": Google Drive libraries, ClosedXML, HtmlAgilityPack |
| ~112 MB | How to run, after Flash Sync added OpenCV |

**SHELL-171 — Runs from any folder; the data is elsewhere.** PROGRESS says "Copy it anywhere; it is fully
portable." There are no installer, registry keys, file associations, services, scheduled tasks or admin
rights. Nothing is written beside the exe. Data lives in `DataStore.AppFolder` (SHELL-175). Even the WeChat
model files are extracted to `<AppFolder>/qrmodels/`, not to the exe folder.

**SHELL-172 — Every resource embedded.** From `AA.csproj`:

| item | build action | size | used by |
|---|---|---|---|
| `AA.ico` (7 PNG frames, 16–256 px) | `ApplicationIcon` (PE icon resource) + `Resource` (`pack://application:,,,/AA.ico`) | 45,294 B | exe/taskbar icon, every window's `Icon`, tray `NotifyIcon` |
| `Assets/Splash.png` (560×632, alpha) | `Resource` | 97,640 B | SplashWindow; if missing, the text fallback (SHELL-003) |
| `Sire/Data/sire2_question_bank.json` (410 questions) | `Resource` (`pack://application:,,,/AA;component/Sire/Data/sire2_question_bank.json`) | 3,350,301 B | `SireBank.EnsureLoaded`; on failure `LoadError` is set and the bank is empty, no crash |
| `FlashSync/Models/detect.prototxt`, `detect.caffemodel`, `sr.prototxt`, `sr.caffemodel` | `EmbeddedResource` (`AA.FlashSync.Models.<name>`) | 42,656 / 965,430 / 5,984 / 23,929 B | `FlashQrDecoder.EnsureModels()` (below) |

`FlashQrDecoder.EnsureModels()` copies each model file to `<AppFolder>/qrmodels/<name>` on first receive. It
copies again whenever the file is missing or its length differs. If a resource is missing from the build it
throws `Embedded QR model '{name}' is missing from the build.`

`360_A.png` sits in the source folder but is not part of the project (unused art). No resource is ever
downloaded at run time.

**SHELL-173 — Dependency trimming.**
* The MSBuild target `TrimOpenCvFfmpeg` runs `AfterTargets="ResolveReferences"`. It removes every
  `ReferenceCopyLocalPaths` item whose file name starts with `opencv_videoio_ffmpeg`. That is a 26 MB DLL for
  reading video files, and capture uses DirectShow only.
* `UseWindowsForms` is on, because `NotifyIcon`, `ColorDialog` and `FolderBrowserDialog` need it.
  `<Using Remove="System.Windows.Forms" />` and `<Using Remove="System.Drawing" />` keep those namespaces out
  of the global usings anyway.
* Third-party packages: Google.Apis.Auth 1.75.0, Google.Apis.Drive.v3 1.74.0.4135, PDFsharp-MigraDoc-gdi
  6.2.0, HtmlAgilityPack 1.11.61, ClosedXML 0.104.2, Net.Codecrete.QrCodeGenerator 2.0.6, and OpenCvSharp4 +
  OpenCvSharp4.runtime.win 4.10.0.20241108.

The Mac has none of these. The owning specs replace each one with Apple frameworks or in-house code.

**SHELL-174 — Framework-dependent variant.** This command produces a smaller `publish-fd\AA.exe` that needs
the .NET 10 runtime installed:
```
dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o publish-fd
```
It is not the shipped form. The Mac needs no equivalent: its build links only OS-provided libraries, so it
is both small and self-contained.

**SHELL-175 — `AA_DATA_DIR`.** `DataStore.ResolveAppFolder()` (`DataStore.cs:32-37`) reads
`Environment.GetEnvironmentVariable("AA_DATA_DIR")`.
* If the value is not null, empty or whitespace, it is the AppFolder **verbatim**. It is not trimmed, not
  expanded and not made absolute. A relative value is resolved by each later file call against the
  process's current directory, which for an Explorer double-click is the exe's folder.
* Otherwise the AppFolder is `%LOCALAPPDATA%\AA`.

The value is read once per process (a static property). Every derived path follows it: `files/`,
`data.json`, `settings.json`, `google_client_secret.json`, `google-token/`, `crash.log`,
`qrsync-baseline.json` and `qrmodels/`.

The source comment says the variable is for "a portable install or isolated testing". PROGRESS 741 used it
for the 12-check isolated shared-save test. There is no command-line switch: `OnStartup` ignores `e.Args`
(W-21).

**SHELL-176 — Build gate.**
* Every PROGRESS update ends with "`dotnet build` succeeds with 0 warnings / 0 errors". The "Verification"
  section states it for `net10.0-windows` on .NET SDK 10.
* Feature work is verified by headless harnesses (counts such as 49/49 and 309/309) and by adversarial
  reviews.
* The cross-platform interop harness `Tests/FlashSync.Interop` runs on macOS. It is a net10.0 console app
  with `InvariantGlobalization`, and it links the four WPF-free Flash Sync files. Run it with
  `dotnet run --project Tests/FlashSync.Interop -- vectors`. Its verbs are `vectors`, `encode`, `decode`,
  `cs-build`, `cs-apply`, `snap-build` and `snap-apply`.
* The whole WPF app also compiles, but does not run, on macOS with
  `dotnet build AA/AA.csproj -p:EnableWindowsTargeting=true` (PROGRESS 977).

**SHELL-177 — Smoke test.** PROGRESS 462: "the single-file exe self-extracts and launches at the login
screen; after sign-in (44233 / redemption) the main window opens". PROGRESS 729: "Debug build launches and
holds at the login screen after the splash". The splash lasts 2.4 s (SHELL-003).

The crash log exists because a release once built 0/0 and still died right after login.
`ApplicationCommands.Refresh` in the XAML caused a runtime `XamlParseException`. A green build is not proof
of a working build, so the smoke run is part of acceptance.

#### O. Mac packaging, signing and first launch

**SHELL-180 — One self-contained `AA.app`.**
* **Output.** `mac/dist/AA.app` is a standard application bundle (layout in BD.4.4). It holds one
  executable `Contents/MacOS/AA`, `Info.plist`, `PkgInfo`, `Resources/` and `_CodeSignature/`.
* **No third-party code.** `Package.swift` declares `dependencies: []`, so there is no `Package.resolved`.
  There are no embedded frameworks or dylibs, and `Contents/Frameworks` is absent.
* **System libraries only.** The executable links only `/usr/lib/…` (including the OS Swift runtime in
  `/usr/lib/swift`) and public frameworks in `/System/Library/Frameworks`. It never loads `@rpath` or
  `@executable_path` libraries and never private frameworks.
* **Nothing to install on the target Mac.** No Xcode, Command Line Tools, Rosetta (on Apple silicon),
  Homebrew, .NET or Python.
* **Installation is a copy.** There is no installer package, helper tool, login item, launch agent, XPC
  service, app extension, system extension or kernel extension.
* **Safe on any file system.** The bundle has no symbolic links and nothing that depends on extended
  attributes. A copy on FAT32, exFAT or SMB media therefore keeps a valid signature.
* **Read-only at run time.** AA never writes inside its bundle, which may be translocated, on read-only
  media or owned by root. All writes go to AppFolder, the temp directory or a location the user chose.
* **Size tripwire.** The unpacked bundle must be at most 60 MB; the expected size is 15–35 MB universal.
  build-app.sh prints the size and fails above the tripwire (`AA_MAX_APP_MB` overrides it).
* **Debug symbols.** `AA.app.dSYM` is the analogue of `AA.pdb`. It is written beside the app in `dist/`, is
  not shipped and is not needed to run.

**SHELL-181 — Architectures: Universal (arm64 + x86_64).**
* **Decision.** Ship one universal executable with `arm64` and `x86_64` slices. Both slices have deployment
  target (LC_BUILD_VERSION `minos`) **26.0**.
* **Why.** The Windows promise is "any 64-bit machine". The brief's deployment target, macOS 26, still
  covers four Intel models: the 16-inch MacBook Pro 2019, the 13-inch MacBook Pro 2020 with four Thunderbolt
  ports, the 27-inch iMac 2020 and the Mac Pro 2019 (Apple's macOS 26 compatibility list). Apple has said
  macOS 26 is the last release for Intel Macs, and vessels keep hardware for a long time.
* **Cost.** Only a larger binary. Unlike OpenCV on Windows, there are no third-party natives to find for
  Intel.
* **Keys not set.** No `LSRequiresNativeExecution` and no `LSArchitecturePriority`. Apple silicon runs the
  arm64 slice natively. The x86_64 slice stays testable under Rosetta with `open --arch x86_64`.
* **Code rules.** Every availability-gated API must behave the same on both slices. Code must not use
  `#if arch(…)` except for the arch label in `--version`.

When the deployment target moves past 26, drop x86_64 (Q-10).

**SHELL-182 — Info.plist.** build-app.sh writes it from the template `mac/Packaging/Info.plist`; the full
text is in BD.4.1. Required values:

| key | value | reason |
|---|---|---|
| `CFBundleIdentifier` | `com.eriskay.aa` | brief; also the TCC, UserDefaults and Keychain identity |
| `CFBundleName` / `CFBundleDisplayName` | `AA` | App menu `AA`, `About AA`, `Quit AA` |
| `CFBundleExecutable` | `AA` | |
| `CFBundlePackageType` / `CFBundleSignature` | `APPL` / `????` | |
| `CFBundleShortVersionString` / `CFBundleVersion` | `@VERSION@` / `@BUILD@` (BD.3.11) | Windows has no explicit version (assembly 1.0.0.0); LaunchServices needs one |
| `AABuildDate` / `AAGitCommit` | `yyyy-MM-dd` (UTC) / short hash (+`-dirty`) | the analogue of PROGRESS's "2026-07-08 build" labels |
| `CFBundleIconFile` (+ `CFBundleIconName` when `Assets.car` exists) | `AppIcon` | SHELL-184 |
| `LSMinimumSystemVersion` | `26.0` | equals `.macOS(.v26)` in Package.swift |
| `LSApplicationCategoryType` | `public.app-category.productivity` | |
| `NSPrincipalClass` | `NSApplication` | |
| `NSHighResolutionCapable` | true | |
| `NSSupportsAutomaticTermination`, `NSSupportsSuddenTermination` | false | the close pipeline (SHELL-056) must always run |
| `NSHumanReadableCopyright` | `Created by B.E.P. Avida - May 2026` | the About text (SHELL-115); the standard About panel shows it |
| `NSCameraUsageDescription` | SHELL-183 text | Flash Sync receive |
| `NSCameraUseContinuityCameraDeviceType` | true | 13 §6.4 step 2 |
| `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription`, `NSFileProviderDomainUsageDescription` | BD.4.1 texts | TCC purpose strings (BD.6.8) |
| `CFBundleDocumentTypes`, `UTExportedTypeDeclarations` | BD.4.1 | SHELL-185, 186 |

These keys must be **absent**:

| key | why it must stay out |
|---|---|
| `LSUIElement` / `LSBackgroundOnly` | AA is a regular Dock app |
| `NSRequiresAquaSystemAppearance` | it would break Dark Mode (SHELL-110) |
| `CFBundleURLTypes` | OAuth uses a loopback redirect, not a URL scheme (14 §6.3) |
| `LSMultipleInstancesProhibited` | Windows allows several instances (Q-14) |
| `NSMicrophoneUsageDescription` | no audio is ever captured, and no audio input may be added |
| `NSAppTransportSecurity` | all traffic is HTTPS to Google; the loopback listener is a server, so ATS doesn't apply |
| `NSAppSleepDisabled` | see BD.6.5 |
| `NSLocalNetworkUsageDescription` | the OAuth listener binds to 127.0.0.1 only, which is exempt; binding any other interface is forbidden |
| `LSEnvironment` | allowed only in the optional baked variant (SHELL-195) |
| `ATSApplicationFontsPath` | Consolas can't be redistributed (§6.6.4) |

**SHELL-183 — Camera permission text and plumbing.** `NSCameraUsageDescription` is exactly:
`AA uses the camera only during Flash Sync ▸ Receive, to read the QR codes your iPhone shows on its screen. Video is never recorded, saved or sent anywhere.`
The `▸` is U+25B8. macOS shows this text under its own camera-access heading the first time Receive starts
the camera (13 §6.4 step 1).

Requirements:
* The hardened-runtime entitlement `com.apple.security.device.camera` (BD.4.2). Without it, the hardened app
  cannot use the camera.
* `NSCameraUseContinuityCameraDeviceType = true`, so the `.continuityCamera` device type in the discovery
  session is allowed (13 §6.4 step 2). Verify this against the SDK; it is harmless if ignored.
* **No audio input** is ever added to the capture session.

TCC stores the grant against the app's code signature. With ad-hoc signing, each new build is a new
identity and asks again (BD.6.5). Testers reset it with `tccutil reset Camera com.eriskay.aa`.

Windows has no camera prompt, so this string is Mac-only. When access is denied or restricted, show the 13
§6.4 status text with **Open System Settings**. Unbundled runs (`swift run`) have no Info.plist; see
SHELL-199.

**SHELL-184 — Icon and bundled resources.** `Contents/Resources` holds:

| file | source (the Mac copy, per brief rule zero) | rule |
|---|---|---|
| `AppIcon.icns` | generated (BD.3.10) from `mac/Resources/AppIcon-1024.png` when present; otherwise from the 256-px frame of the copied `AA.ico`, upscaled with a warning | `CFBundleIconFile = AppIcon` |
| `Assets.car` (optional) | compiled with `actool` from an Icon Composer `mac/Resources/AppIcon.icon` | adds `CFBundleIconName = AppIcon` and gives the macOS 26 layered icon. Without it, macOS 26 shows the round art inside a grey rounded-square plate |
| `Splash.png` | byte-identical copy of `AA/Assets/Splash.png` (SHA-256 `1489fd92…a6`) | SHELL-003 |
| `sire2_question_bank.json` | byte-identical copy of `AA/Sire/Data/sire2_question_bank.json` (SHA-256 `e05d3c59…bcf`) | 12 §2 |
| `MenuBarIconTemplate.png`, `MenuBarIconTemplate@2x.png` | hand-drawn 18×18 pt monochrome "A" disc (black + alpha) | `NSImage.isTemplate = true` (03 §6.8) |
| SwiftPM resource bundles (`AA_AACore.bundle`, `AA_AA.bundle`) | copied from the build products | only if the targets declare resources (BD.3.4) |

Not shipped:
* The WeChat model files. Vision replaces OpenCV (13 §6.4 step 9).
* `360_A.png`.
* `AA.ico` itself. macOS windows have no per-window icons, and the Dock/app icon comes from `AppIcon`. The
  WPF app sets `Icon="pack://…/AA.ico"` on about 35 windows; that has no Mac counterpart, which is accepted.

The Mac never creates `qrmodels/`. A `qrmodels/` folder in a data folder copied from Windows is ignored and
left alone.

**SHELL-185 — `.aaz` is an AA document; double-click imports it with review.**
* **Declarations.** Declare the exported type `com.eriskay.aa.bundle` ("AA bundle", conforms to
  `public.zip-archive`, extension `aaz`). Add document types that make AA the **owner viewer** of `.aaz`
  and an **alternate viewer** of any `.zip` (Info.plist in BD.4.1).
* **Opening.** Double-click, Open With, or a drop on the Dock icon calls `application(_:open:)`. That runs
  the File ▸ Import Data Folder (ZIP)… flow without its open panel:
  1. `PeekZipData`;
  2. the review gate (SHELL-120), with source name = file name;
  3. `ImportBundleSmart`;
  4. `LoadDataAndInitUi`;
  5. status `Imported {file} (text only — your attachments are untouched)` or
     `Imported {file} (with attachments)`.
* **Safety.** Nothing is imported without the review gate. Files wait in a queue until the main window has
  loaded (BD.3.7).
* **Mac enhancement.** The Windows exe has no installer and registers no file association, so
  double-clicking an `.aaz` on Windows does nothing useful (Q-12).
* **Format.** `.aaz` and `.zip` bundles use the same ZIP format, and reading ignores the extension.
* **iPhone.** The iPhone app also produces `.aaz` files (`AA-backup-iOS-….aaz`, 14 TOOLS-017). If it
  declares a type for `.aaz`, the identifiers must match (Q-11).

**SHELL-186 — `.aasched.json` and private types.** Schedule templates are exported as
`Schedule-{name}.aasched.json` (06, 09). macOS identifies a file by its **last** extension only, so Finder
and open panels always treat such a file as `public.json`. Therefore:
* Declare `com.eriskay.aa.schedule` (conforms to `public.json`, extension tag `aasched.json`) for
  completeness only.
* **Never** use that type in `allowedContentTypes`. An open panel would grey out every real `.aasched.json`
  file, and a save panel could append a second extension. Panels use `.json`, and code recognises the file
  with a case-insensitive `hasSuffix(".aasched.json")`.
* Declare **no** document type for it. Double-click keeps opening the user's JSON viewer, as on Windows.

Also declare the in-app pasteboard and drag types owned by other specs, so the system knows them:
`com.eriskay.aa.xaml` (05 §6.6, conforms to `public.data`) and `com.eriskay.aa.task-ref` (07 §7, conforms to
`public.data`). AA must never claim `public.json` or `public.zip-archive` as owner.

**SHELL-187 — Sandbox decision and entitlements.** AA ships **not sandboxed**, with the **hardened runtime**
on, and exactly one entitlement: `com.apple.security.device.camera` (BD.4.2).

The reason is parity. It needs unrestricted POSIX access, which the App Sandbox cannot give without
changing behaviour (BD.6.3 lists what breaks):
* in-place links to arbitrary local and network paths (05);
* an external active data file and a shared save file on a network volume, both replaced **atomically
  through a sibling temp file in the same folder** (`{path}.{32hex}.tmp` + rename). A sandbox grant for the
  file alone does not allow creating siblings;
* a data folder anywhere (`--data-dir` / `AA_DATA_DIR`);
* Google Drive folder auto-detection, which probes `~/Library/CloudStorage` and `/Volumes`;
* Folder Builder targets.

Outside the sandbox, network access (Drive REST, the OAuth token endpoint, Gemini) and the OAuth loopback
listener need no entitlement.

Not allowed:
* Hardened-runtime exceptions (`cs.allow-jit`, `cs.allow-unsigned-executable-memory`,
  `cs.disable-library-validation`, `cs.allow-dyld-environment-variables`).
* `automation.apple-events`. Finder reveal uses NSWorkspace, not AppleScript.
* Restricted entitlements (`keychain-access-groups`, `application-identifier`, `com.apple.developer.*`) in
  ad-hoc builds. The kernel refuses to launch an ad-hoc app that claims them.

A reference sandbox profile (BD.4.3) is documented for a possible future App Store build; it is not shipped.
The hardened runtime strips only `DYLD_*` variables, so `AA_DATA_DIR` still reaches the app.

**SHELL-188 — Code signing.**
* **Default: ad-hoc.** `codesign --sign -` with `--options runtime` and the entitlements file. It is the
  last step, after every file is in place (BD.3.9 step 10). Use no `--deep` (there is a single executable
  and no nested code) and no timestamp.
* **Verification.** The result must pass `codesign --verify --strict --verbose=2`.
* **Named identity.** `SIGN_IDENTITY` switches to a named identity:
  * a self-signed "AA Local Signing" code-signing certificate. This gives a stable identity on the build
    Mac, so camera, Files & Folders and Keychain grants survive rebuilds;
  * or a "Developer ID Application" certificate. Then add `--timestamp`, notarise with
    `xcrun notarytool submit … --wait` and `xcrun stapler staple`. Gatekeeper then opens the app with no
    extra step (Q-15).

The app must tolerate the consequences of ad-hoc signing described in BD.6.5.

**SHELL-189 — Gatekeeper first-launch procedure (ad-hoc builds).** A copy that arrives through a browser,
Mail, Messages or AirDrop carries the `com.apple.quarantine` attribute. Gatekeeper then refuses the first
open, because the app is not notarised. The procedure below is for macOS 15 and later. It goes into the
distribution `Install.txt` and into `build-app.sh --help`.
1. Move `AA.app` to Applications (or any permanent folder) with Finder **before** opening it. This avoids
   App Translocation (SHELL-190).
2. Double-click it. macOS says it could not verify AA and offers only Done / Move to Trash. Choose **Done**.
3. Open **System Settings ▸ Privacy & Security** and scroll to Security. Find the line saying AA was
   blocked, click **Open Anyway**, and authenticate.
4. Double-click AA again and confirm **Open Anyway** once more. From then on it opens normally.

Technical users can instead run this once in Terminal, after moving the app:
`xattr -dr com.apple.quarantine /Applications/AA.app`.

Notes:
* A copy that was built locally, copied from a USB stick with Finder, or transferred with `scp` / `rsync`
  normally has no quarantine attribute. It opens straight away.
* The right-click ▸ Open bypass of older macOS versions no longer exists.
* A bundle whose signature is broken (for example, a file changed after signing) is reported as "damaged"
  when quarantined. Never edit the bundle after signing; re-run build-app.sh.
* The Windows analogue is SmartScreen's "Windows protected your PC ▸ More info ▸ Run anyway" for the
  unsigned exe. PROGRESS does not document it.

**SHELL-190 — App Translocation.** When a quarantined app is opened from where it was downloaded or unpacked,
without first being moved by Finder, macOS runs it from a random read-only mount such as
`/private/var/folders/…/AppTranslocation/<UUID>/d/AA.app`.

AA must behave correctly there, and nothing depends on the bundle location:
* AppFolder is Application Support or an explicit override;
* resources are read through `Bundle.main`;
* nothing is written into the bundle;
* the `.command` launcher computes its paths from its own location, not from the app's.

AA detects translocation (BD.3.6). After the main window appears, it shows this informational sheet once per
launch:
* title `Move AA to Applications`;
* text `AA is running from a temporary, read-only location that macOS uses for apps opened straight from a download.\n\nQuit AA, drag it into your Applications folder, and open it from there. Your data is not affected.`;
* button `OK`.

These are Mac-only strings. The sheet is not shown in `--smoke-test` runs.

**SHELL-191 — Distribution containers.**
* build-app.sh writes `mac/dist/AA-{version}-{build}-macOS.zip`, made with `ditto -c -k --keepParent` from a
  staging folder `AA/` that holds `AA.app` and `Install.txt`. `ditto` preserves the bundle exactly;
  `zip -r` is not used.
* With `PORTABLE_LAUNCHER=1` the staging folder also gets `AA (portable).command` (BD.4.6).
* It also writes `dist/SHA256SUMS`.
* `PACKAGE=dmg` additionally writes `AA-{version}-{build}-macOS.dmg`
  (`hdiutil create -volname AA -srcfolder <staging> -ov -format UDZO`). There is no `.pkg`.
* **Install** by dragging `AA.app` anywhere: Applications is recommended, `~/Applications` suits non-admin
  users, and an external drive works too.
* **Update** by replacing the bundle. Data is untouched because it lives outside the bundle.
* `dist/` is git-ignored (`mac/.gitignore`).

#### P. Launch environment and data folder

**SHELL-192 — Command-line surface.** The executable accepts the arguments below. All are optional and
case-sensitive, BD.3.1 parses them, and unknown arguments are ignored.

| argument | builds | effect |
|---|---|---|
| `--data-dir <path>` / `--data-dir=<path>` | all | AppFolder for this process (SHELL-193) |
| `--version` | all | prints `AA {CFBundleShortVersionString} ({CFBundleVersion}) {arch}` to stdout and exits 0, before any UI or file access. Unbundled: `AA dev (unbundled) {arch}` |
| `--smoke-test` | all | automated launch smoke (SHELL-205). Requires `--data-dir` naming an empty or new folder |
| `--snapshot <TabName\|window-id> --out <file.png> [--appearance dark\|light]` | DEBUG only | the brief's visual-verification hook. It bypasses the splash and login, so release builds compile it out. A release build prints `--snapshot is only available in debug builds.` to stderr and continues normally |

AppKit's own `-Key value` argument-domain pairs (for example Xcode's `-NSDocumentRevisionsDebugMode YES`)
and legacy `-psn_…` arguments pass through untouched.

To launch from Terminal, run `/Applications/AA.app/Contents/MacOS/AA --data-dir /Volumes/STICK/AA-data`
(the bundle identity still applies), or `open -n -a AA --args --data-dir …`. `open --args` only reaches a
**newly launched** process. If AA is already running, `open` just activates it and drops the arguments, so
use `-n` (new instance) or quit AA first.

**SHELL-193 — Data-folder precedence.** AppFolder is the first of these that applies:
1. the value of `--data-dir` (last occurrence), if present and not blank;
2. the environment variable `AA_DATA_DIR`, if not blank. It can arrive in any of these ways:
   * a Terminal launch: `AA_DATA_DIR=… /Applications/AA.app/Contents/MacOS/AA`;
   * `open --env AA_DATA_DIR=/path -a AA`;
   * `launchctl setenv AA_DATA_DIR /path`, which affects every app the user session launches afterwards,
     until logout;
   * `LSEnvironment` in Info.plist (SHELL-195);
3. `~/Library/Application Support/AA`, that is
   `FileManager.url(for: .applicationSupportDirectory, in: .userDomainMask)` + `AA`.

A Finder or Dock launch does **not** see variables exported in `~/.zshrc`. That is why the argument exists.

Normalisation (BD.3.2):
* trim surrounding whitespace and newlines;
* expand `~`;
* resolve a relative path against the current directory. For Finder and `open` launches that is `/`, so
  use absolute paths;
* standardise `.` and `..`;
* leave symlinks unresolved, so status texts show the path the user gave.

A Windows-shaped value (`X:\…`, `X:/…`, `\\server\…`) is an error, not a relative path.

The folder is fixed for the process lifetime, like the Windows static property; changing it needs a
relaunch. The chosen folder and its source are logged to the unified log (`os_log`, subsystem
`com.eriskay.aa`, category `startup`). The UI shows it only through the normal `Loaded — {path}` status.
Optionally, the Settings pane can show "Data folder: {path} (from --data-dir)".

**SHELL-194 — Data-folder pre-flight.** Before the splash (Windows: at `LoadSettings` time), AA checks the
folder (BD.3.3). The check fails when:
* the path is under `/Volumes` and its `/Volumes/<name>` is missing;
* the folder cannot be created;
* it is not a folder;
* it is not writable.

On failure AA shows a modal alert (no main window exists yet):
* title `AA can't open its data folder`;
* message `AA couldn't open or create its data folder:\n\n{path}\n\n{reason}{source}`.

`{reason}` is one of:
* `The drive “{name}” isn't connected. Connect it, then choose Try Again.`
* `That is a Windows path. On a Mac, use a folder such as /Volumes/DriveName/AA-data.`
* `{error.localizedDescription}`

`{source}` is one of:
* `\n\nThe folder was given with --data-dir.`
* `\n\nThe folder comes from the AA_DATA_DIR environment variable.`
* empty, for the default folder.

Buttons are `Try Again` (default; re-runs the check) and `Quit` (Esc). A Windows-path error shows only
`Quit`.

AA never silently falls back to another folder. That would show a different, possibly empty, data set and
let the user edit it believing their data was lost. These are Mac-only strings; for the Windows behaviour
see W-18.

**SHELL-195 — Portable data folder recipes.**
* **(a) Launcher script.** Recommended for a USB stick or a shared tools folder. Put `AA (portable).command`
  next to `AA.app` (BD.4.6). It runs `open -n -a "<here>/AA.app" --args --data-dir "<here>/AA Data"`.
  Double-clicking it in Finder opens Terminal briefly and launches AA with the stick's data. A `.command`
  that arrives quarantined needs the same one-time approval as the app (SHELL-189).
* **(b) `open --env`**, for scripted launches:
  `open -n --env AA_DATA_DIR="/Volumes/STICK/AA Data" -a /Volumes/STICK/AA.app`.
* **(c) Baked `LSEnvironment`**, at build time only. `AA_BAKE_DATA_DIR=/abs/path mac/Scripts/build-app.sh`
  writes `LSEnvironment = { AA_DATA_DIR = /abs/path }` into Info.plist **before** signing. This recipe is
  discouraged:
  * editing the Info.plist of a signed app breaks its signature;
  * LaunchServices caches Info.plist, so a changed copy may need `lsregister -f`;
  * LaunchServices doesn't expand `~` (AA expands it itself);
  * a baked absolute path is machine-specific.

`--data-dir` beats all three sources of the environment variable. If both `open --env` and `LSEnvironment`
set it, LaunchServices decides which wins, so don't combine them. For completeness, a Windows user gets the
same effect with a `.cmd` wrapper (W-21).

**SHELL-196 — Folders shared with Windows (USB stick or network folder).** A portable data folder may be
used alternately by `AA.exe` (`AA_DATA_DIR=E:\AA Data`) and `AA.app` (`--data-dir "/Volumes/STICK/AA Data"`).
Each rule below is owned in detail by 01, 05, 13 or 14. They are collected here because portability is what
creates the situation.
* **`settings.json`** is shared by both apps. Paths written by one platform are unusable on the other, so
  each side leaves a foreign value untouched and treats it as absent or unreachable:
  * `CurrentDataFile`: Windows already falls back to the default when the file doesn't exist, and the Mac
    does the same;
  * `GoogleDriveFolder`: a non-POSIX value counts as missing (14 §6.2);
  * `SharedSaveFile`: a Windows path is shown as offline and never rewritten;
  * `FolderBuilderBase`.
* **`EncryptLocalData`.** A DPAPI-encrypted `data.json` (`AAENC1`) opens in safe mode on the Mac, and a
  Keychain-encrypted one (`AAENCM1`) opens in safe mode on Windows. No data is lost, but the folder stops
  being portable. Recommended Mac guard (Q-16): when `EncryptLocalData` is true, the data file on disk is
  plaintext and this Mac has no local-data key yet, ask before encrypting:
  `This data folder is set to be encrypted at rest, but that setting came from another computer. Encrypting it here means only this Mac can open it. Encrypt it on this Mac?`
  with `Encrypt` / `Keep Plaintext`. Keep Plaintext turns the setting off. Mac-only string.
* **Attachments.** On FAT, exFAT and SMB volumes, macOS creates AppleDouble `._*` files when a file carries
  extended attributes, and Finder leaves `.DS_Store` files. The Mac must not leave these in `files/`:
  * copy attachment bytes without extended attributes (`copyfile` with `COPYFILE_DATA` only, or strip the
    xattrs after copying);
  * ignore `._*`, `.DS_Store` and `Icon\r` when reading `files/`, bundles and folders (05 §8 K-8).
  Otherwise Windows ships them inside its ZIP exports.
* **`crash.log`** keeps Windows line endings (the `\r\n\r\n` block separator of SHELL-001), so one log
  reads cleanly on both.
* **Only one app at a time.** Both apps must not run on the same folder at once. The last writer wins, as
  with two Windows instances (Q-14).

**SHELL-197 — Where `crash.log` lives.**
* **Location.** `<AppFolder>/crash.log`: by default `~/Library/Application Support/AA/crash.log`, or
  `<data-dir>/crash.log` when overridden.
* **Format.** Same name and block format as Windows: `[yyyy-MM-dd HH:mm:ss] {details}\r\n\r\n`, local time,
  UTF-8, appended, created if missing. File ▸ Open Data Folder reveals it.
* **Fallback (Mac improvement, W-17).** If appending there fails (pre-flight failure, unplugged volume,
  permissions), append to `~/Library/Logs/AA/crash.log` (creating the folder) and put **that** path in the
  dialog. If both fail, the dialog replaces its last two lines with
  `The details could not be written to a log file.` (Mac-only).
* **Dialog.** It is shown whether or not the log write succeeded.
* **Fatal traps.** Swift runtime traps and signals, which the process cannot survive, are also recorded by
  macOS in `~/Library/Logs/DiagnosticReports/AA-<date>.ips` (Console ▸ Crash Reports). AA's signal handler
  writes a one-line marker to the pre-opened `crash.log` descriptor. On the next launch, AA appends MetricKit
  `MXCrashDiagnostic` payloads (JSON) and shows the crash dialog (03 §6.1).
* **Never shared.** crash.log is never bundled, never synced and is git-ignored.

**SHELL-198 — Resources at run time.** One locator (BD.3.4) finds each resource. It looks first in
`Bundle.main` (the assembled app), then in the SwiftPM resource bundles wherever they sit:
`Contents/Resources/`, next to the executable for `swift run`, or next to the test bundle for `swift test`.

The locator **never traps**. SwiftPM's generated `Bundle.module` calls `fatalError` when its bundle is
missing, so the app calls `Bundle.module` only after the locator has seen the bundle on disk.

A missing resource degrades exactly as on Windows:
* the splash shows its text fallback;
* SIRE shows `Could not load the SIRE question bank:\n{error}` (12 §2).

Resource bundles go in `Contents/Resources/`, never at the `.app` root; unsealed content at the root fails
`codesign --verify`.

Caution for verifiers: the generated accessor also falls back to the absolute build-folder path compiled
into the binary. A bundle missing its resources can therefore still work **on the build Mac**. Only
SHELL-207's clean-machine run, or a run with `.build` moved aside, proves the packaging.

**SHELL-199 — Unbundled development runs (`swift run AA`).** The executable also runs straight from SwiftPM,
with no `.app`, no Info.plist and no bundle id. It must then:
* call `NSApp.setActivationPolicy(.regular)` and `NSApp.activate()` at launch. Otherwise it has no Dock icon
  or menu bar, and its windows may open behind Terminal;
* not start the camera. Without `NSCameraUsageDescription`, macOS terminates a process that requests camera
  access. The Receive tab shows this developer-only text instead:
  `The camera needs the packaged app. Build it with Scripts/build-app.sh and open dist/AA.app.`
* not touch `UNUserNotificationCenter`, which raises an exception in a process without a bundle identifier.
  Reminders fall back to the status line;
* keep everything else working: the data folder, Keychain, Drive and Flash Sync send.

Detection: `Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app"`.

#### Q. Acceptance

**SHELL-200 — Compile gate.** Run these from `mac/`:
* `swift build -c debug -Xswiftc -warnings-as-errors`
* `swift build -c release --triple arm64-apple-macosx26.0 -Xswiftc -warnings-as-errors`
* the same release build with `--triple x86_64-apple-macosx26.0`

Each must exit 0, and the combined log must contain no `warning:` lines at all. The log check also catches
linker warnings, which `-warnings-as-errors` does not cover. This is the Mac form of the Windows
"0 warnings / 0 errors".

The flag goes on the command line (build-app.sh, CI), not into `Package.swift`, so a newer compiler's new
warnings don't block everyday `swift run`. A deprecation warning fails the gate, so deprecated APIs can't be
used.

**SHELL-201 — Test gate.** `swift test -Xswiftc -warnings-as-errors` exits 0. That covers all AACoreTests:
the Windows-compat fixtures, the Flash Sync vectors and the BD.7 vectors.

Optional cross-check when a .NET 10 SDK is installed on the Mac: `dotnet run --project ../Tests/FlashSync.Interop
-- vectors` passes, and the Swift codec reproduces its outputs (13 spec).

**SHELL-202 — `build-app.sh`.** `mac/Scripts/build-app.sh` builds, tests, assembles, signs, verifies and
packages the app (algorithm in BD.3.9). It is a bash script with `set -euo pipefail` and can run from any
directory.
* It exits non-zero at the first failure and names the failing step.
* It writes only under `mac/.build`, `mac/dist` and a temp directory, and never touches anything outside
  `mac/` (brief rule zero). It reads the originals only to check resource checksums.

On success it ends with a summary like this:
```
AA.app      mac/dist/AA.app  (23.4 MB, x86_64 arm64, minos 26.0)
Version     1.0.0 (412)  2026-09-30  a1b2c3d
Signature   adhoc, hardened runtime, entitlements: com.apple.security.device.camera
Package     mac/dist/AA-1.0.0-412-macOS.zip  sha256 …
```

**SHELL-203 — Bundle verification.** build-app.sh step 11, or a verifier by hand, checks BD.7.4:
* Info.plist lint and values;
* both universal slices, with `minos 26.0`;
* only system libraries linked;
* a valid signature with exactly the expected entitlements;
* byte-identical resources;
* `--version` runs on each available slice.

**SHELL-204 — Manual launch smoke test.** This is the Windows smoke in Mac form; the checklist is BD.7.7.
1. The splash shows for about 2.4 s.
2. The login `AA — Sign in` appears, and a wrong password is rejected.
3. 44233 / redemption opens the main window `AA — {identity}` with status `Loaded — {folder}/data.json`.
4. ⌘Q quits.
5. A relaunch restores the window frame.

Run it on every release build, from Finder, with a fresh `--data-dir`, and once with the default folder.

**SHELL-205 — Automated launch smoke (`--smoke-test`).** Run
`dist/AA.app/Contents/MacOS/AA --data-dir "$(mktemp -d)/aa" --smoke-test`. It drives the same path through:
* the real splash timer;
* the real login model: first a wrong password, then 44233 / redemption;
* the real main-window load;
* the real quit pipeline.

It prints JSON lines (BD.4.7) and exits 0 on success (BD.3.12). It refuses with exit code 3 unless
`--data-dir` is given and the folder has no `data.json` or `settings.json`, so it can never run on real data.
It exercises the login gate; it does not bypass it.

**SHELL-206 — Cross-version data smoke.** Details in BD.7.8.
* **(a) Windows → Mac.** A copy of a Windows data folder opens on the Mac with `--data-dir`. It must not be
  in safe mode, must show no `Newer data format` warning, and its attachments must open. After quitting,
  `settings.json` is byte-identical unless a setting was changed, so foreign paths are untouched.
* **(b) Mac → Windows.** A Mac ZIP export imports on Windows through the review gate and loads without
  warnings.
* **(c) Optional.** One USB-stick folder used alternately by both apps, with encryption off, keeps working.

**SHELL-207 — Clean-machine and Intel runs.** Once per release:
1. Install from the zip on a Mac, or a new macOS user account, that has never run AA and has no build tree.
   Use the SHELL-189 procedure when the copy is quarantined. Run SHELL-204.
2. Open the app once straight from Downloads to see the SHELL-190 hint.
3. Run the x86_64 slice through SHELL-204, including Flash Sync ▸ Receive's camera prompt. Use
   `open --arch x86_64 dist/AA.app` under Rosetta, or an Intel Mac on macOS 26.

### BD.3 Logic & algorithms

#### BD.3.1 `parseLaunchArguments(_ argv: [String]) -> LaunchOptions`
```
opts = LaunchOptions(dataDir: nil, version: false, smokeTest: false, snapshot: nil)
i = 1                                                  # argv[0] is the executable path
while i < argv.count:
    a = argv[i]
    if a == "--data-dir":
        if i + 1 < argv.count and not argv[i+1].hasPrefix("--"):
            opts.dataDir = argv[i+1]; i += 2; continue          # the last occurrence wins
        stderr("AA: --data-dir needs a folder path; ignored"); i += 1; continue
    if a.hasPrefix("--data-dir="):                              # prefix length 11
        opts.dataDir = String(a.dropFirst(11)); i += 1; continue
    if a == "--version":            opts.version = true
    elif a == "--smoke-test":       opts.smokeTest = true
    elif a in ["--snapshot", "--out", "--appearance"]:
        DEBUG: store argv[i+1] and i += 1;   release: stderr warning once (SHELL-192)
    elif a.hasPrefix("-psn_"):      pass                         # legacy LaunchServices process id
    elif a.hasPrefix("-") and not a.hasPrefix("--"):             # AppKit argument-domain pair "-Key value"
        if i + 1 < argv.count and not argv[i+1].hasPrefix("-"): i += 1    # skip its value
    # anything else is ignored silently
    i += 1
return opts
```
* Blank values (`--data-dir ""`, `--data-dir=`) are stored here and treated as absent by BD.3.2.
* A value that really starts with `--` must use the `=` form.
* Flags are case-sensitive.
* Warnings go to stderr only, never to a dialog.

#### BD.3.2 `resolveAppFolder(opts, env, cwd, home) -> Result<(URL, Source), DataDirError>`
```
func candidate(_ raw: String?) -> String?:
    guard let raw else { return nil }
    v = raw.trimmingCharacters(in: .whitespacesAndNewlines)     # ≈ .NET IsNullOrWhiteSpace + trim (W-20)
    return v.isEmpty ? nil : v
if let v = candidate(opts.dataDir):          (value, source) = (v, .argument)
elif let v = candidate(env["AA_DATA_DIR"]):  (value, source) = (v, .environment)
else: return .success((appSupport.appending(path: "AA", directoryHint: .isDirectory), .default))
if value ~ /^[A-Za-z]:([\\\/]|$)/ or value.hasPrefix("\\\\"):
    return .failure(.windowsPath(value, source))
value = (value as NSString).expandingTildeInPath             # "~", "~/x", "~user/x"
url = value.hasPrefix("/")
      ? URL(fileURLWithPath: value, isDirectory: true)
      : URL(fileURLWithPath: value, isDirectory: true, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
return .success((url.standardizedFileURL, source))           # absolute, no trailing "/", symlinks NOT resolved
```
* `env` is `ProcessInfo.processInfo.environment`, read once.
* `cwd` is `FileManager.default.currentDirectoryPath`.
* `appSupport` is `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)`.
* No Unicode normalisation is applied. APFS is normalisation-insensitive, so keep the user's form.
* Every derived path is built from the result, exactly as in DATA-010: `files/`, `data.json`,
  `settings.json`, `google_client_secret.json`, `google-token/`, `crash.log`, `qrsync-baseline.json`.

#### BD.3.3 `preflight(url, source) throws(DataDirError)`
```
c = url.pathComponents                               # ["/", "Volumes", "STICK", …]
if c.count >= 3 and c[1] == "Volumes" and !FileManager.fileExists(atPath: "/Volumes/" + c[2]):
    throw .volumeNotMounted(name: c[2])              # never mkdir under /Volumes (root-owned, 0755)
do { try FileManager.createDirectory(at: url, withIntermediateDirectories: true) }
catch { throw .cannotCreate(error) }
guard isDirectory(url) else { throw .notAFolder }
guard access(url.path, W_OK) == 0 else { throw .notWritable(errno) }
```
* This runs before the splash.
* Try Again repeats the check. Quit calls `exit(0)` and writes nothing. This is not a crash, so the crash
  log is not used.
* `files/` is created later by `DataStore.Load()`, exactly as on Windows.
* A read-only volume fails at `notWritable`. Windows would open and then fail every save.

#### BD.3.4 `AAResources.url(name, ext) -> URL?`
```
if let u = Bundle.main.url(forResource: name, withExtension: ext): return u      # flat copy in Contents/Resources
for bundleName in ["AA_AACore.bundle", "AA_AA.bundle"]:                           # "{package}_{target}.bundle"
    for base in [Bundle.main.resourceURL, Bundle.main.bundleURL,
                 Bundle.main.executableURL?.deletingLastPathComponent(),
                 Bundle(for: AAResourcesToken.self).resourceURL,
                 Bundle(for: AAResourcesToken.self).bundleURL]:
        if let base, let b = Bundle(url: base.appending(path: bundleName)),
           let u = b.url(forResource: name, withExtension: ext): return u
return nil                                                                         # callers degrade (SHELL-198)
```
* Resource names: `sire2_question_bank`/`json`, `Splash`/`png`, `MenuBarIconTemplate`/`png`.
* The bundle names assume the package is named `AA`. Derive them from the real package name.
* Tests call the same locator, so `swift test` exercises the fallback path.
* The SIRE bank must still be read lazily, on first activation of the SIRE section, as on Windows.

#### BD.3.5 Crash sink
```
primary  = AppFolder/crash.log
fallback = ~/Library/Logs/AA/crash.log
func report(details: String, message: String):
    block = "[" + format(now, "yyyy-MM-dd HH:mm:ss", en_US_POSIX, Gregorian, local zone) + "] " + details + "\r\n\r\n"
    written = append(primary, block) ? primary : (append(fallback, block) ? fallback : nil)
    alert(title: "AA — error",
          text: "AA hit an unexpected error and had to stop:\n\n\(message)\n\n" +
                (written != nil ? "The full details were written to:\n\(written!)"
                                : "The details could not be written to a log file."))
```
* For Swift errors, `details` is `String(reflecting: error)`, a newline, then `Thread.callStackSymbols`
  joined with `\n`.
* For `NSException`, `details` is the name, the reason and `callStackSymbols`.
* **Signal path.** At step 2 of BD.1.3, open `primary` (or `fallback` if that fails) with
  `O_WRONLY|O_APPEND|O_CREAT, 0644` and keep the fd. The handler for SIGABRT, SIGSEGV, SIGBUS, SIGILL and
  SIGTRAP writes a pre-built `"[crash marker] signal <n>\r\n\r\n"` with `write(2)` only: no allocation and no
  formatting. It then restores `SIG_DFL` and re-raises, so macOS still writes its own `.ips` report.
* Nothing is shown or logged for the pre-flight alert or for `--version`.

#### BD.3.6 Translocation detection
`isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")`. Security.framework's
`SecTranslocateIsTranslocatedURL` is equivalent where available; the path test is enough and needs nothing
extra. The result is informational only (SHELL-190) and changes no other behaviour.

#### BD.3.7 Opening documents from Finder
```
AppDelegate.application(_:open urls:):
    for u in urls where ["aaz","zip"].contains(u.pathExtension.lowercased()): pending.append(u)
    if phase == .main and mainLoaded and no alert/sheet is up: drain()
drain(): while let u = pending.first:
    pending.removeFirst()
    bring the main window to the front
    await importBundleWithReview(u)         # SHELL-071 minus the open panel; one review per file
main window finished OnLoaded, or the last alert/sheet closed → drain()
login cancelled / Exit → the app terminates and pending is discarded
```
* Imports are allowed in safe mode, as on Windows (SHELL-008).
* If a file no longer exists by the time it is drained, AA shows `Import failed` (D11) with the error
  message.
* Opening files never starts a second instance.

#### BD.3.8 Unbundled guards
See SHELL-199. The check runs once, in `applicationWillFinishLaunching`, and is exposed as
`AppEnvironment.isBundled`.

#### BD.3.9 `build-app.sh` pipeline

**Inputs.** All of these are environment variables with defaults:

| variable | default | purpose |
|---|---|---|
| `CONFIGURATION` | `release` | build configuration |
| `ARCHS` | `"arm64 x86_64"` | slices to build |
| `VERSION` | contents of `mac/VERSION`, else `1.0.0` | `CFBundleShortVersionString` |
| `BUILD_NUMBER` | `git rev-list --count HEAD`, else `1` | `CFBundleVersion` |
| `SIGN_IDENTITY` | `-` | `-` means ad-hoc |
| `NOTARY_PROFILE` | unset | enables notarisation (step 14) |
| `AA_BAKE_DATA_DIR` | unset | baked `LSEnvironment` (SHELL-195) |
| `PACKAGE` | `zip` | `zip` \| `dmg` \| `none` |
| `PORTABLE_LAUNCHER` | `0` | add `AA (portable).command` to the package |
| `SKIP_TESTS` | `0` | skip step 4 |
| `STRIP` | `1` | strip symbols in step 6 |
| `AA_MAX_APP_MB` | `60` | size tripwire |

`--help` prints the usage and the SHELL-189 procedure.

**Steps.** `$T` is a fresh `mktemp -d`.
1. **Preconditions.** Darwin host. `xcrun --find swift` succeeds. A full Xcode is selected: `xcode-select -p`
   ends in `.app/Contents/Developer`, which is needed for `actool` and the x86_64 SDK slices. The tools
   `iconutil sips codesign lipo plutil ditto shasum xattr` and `xcrun vtool/otool/dsymutil/strip` are
   present.
2. **Resource integrity.** The SHA-256 of each Mac resource copy equals its line in
   `mac/Docs/original-source-checksums.sha256` (`AA/Assets/Splash.png`,
   `AA/Sire/Data/sire2_question_bank.json`, `AA/AA.ico`). Any mismatch fails the step.
3. **Compile.** For each arch run
   `swift build -c "$CONFIGURATION" --triple "$arch-apple-macosx26.0" -Xswiftc -warnings-as-errors 2>&1 | tee "$T/build-$arch.log"`.
   It fails on a non-zero exit or on any `warning:` line. The binary is at
   `$(swift build -c "$CONFIGURATION" --triple … --show-bin-path)/AA`. (The Xcode build system's
   `--arch arm64 --arch x86_64` is an acceptable alternative that produces the universal file directly.)
4. **Tests**, unless `SKIP_TESTS=1`: `swift test -Xswiftc -warnings-as-errors` on the host arch.
5. **Assemble** in `$T/AA.app`, not in `dist`: create `Contents/MacOS` and `Contents/Resources`, then
   `lipo -create -output Contents/MacOS/AA <one binary per arch>`. With a single arch, copy the binary.
6. **Symbols.** `xcrun dsymutil Contents/MacOS/AA -o $T/AA.app.dSYM`, then `xcrun strip -S -x Contents/MacOS/AA`
   when `STRIP=1`.
7. **Info.plist.**
   * Copy the template and substitute `@VERSION@`, `@BUILD@`, `@BUILDDATE@` (`date -u +%F`) and
     `@GITCOMMIT@`.
   * If `AA_BAKE_DATA_DIR` is set, run `plutil -insert LSEnvironment -json '{"AA_DATA_DIR":"…"}'`.
   * If `Assets.car` was compiled, merge `CFBundleIconName` from actool's partial plist.
   * `plutil -lint`.
   * Write `PkgInfo` as the 8 bytes `APPL????`, with no newline.
8. **Resources.**
   * Flat-copy `Splash.png`, `sire2_question_bank.json` and `MenuBarIconTemplate(@2x).png`.
   * Copy each `*.bundle` from the build-products directory into `Contents/Resources/`.
   * Generate the icons (BD.3.10).
9. **Clean.** `xattr -cr "$T/AA.app"`: Finder-info, quarantine and provenance attributes make codesign fail
   with "resource fork, Finder information, or similar detritus not allowed". Delete any `.DS_Store`. Assert
   that `find "$T/AA.app" -type l` prints nothing.
10. **Sign.** `codesign --force --options runtime --entitlements mac/Packaging/AA.entitlements --sign "$SIGN_IDENTITY" [--timestamp] "$T/AA.app"`.
    `--timestamp` applies only when the identity is not `-`.
11. **Verify** every check in BD.7.4.
    * `--version` runs on the host slice.
    * The x86_64 slice runs through `arch -x86_64` only when Rosetta is installed (`arch -x86_64 /usr/bin/true`
      exits 0). Otherwise print `x86_64 slice not executed (Rosetta not installed)`.
12. **Publish** into `dist`: `rm -rf mac/dist/AA.app mac/dist/AA.app.dSYM`, then move both from `$T`.
    `dist` only changes after a fully verified build.
13. **Package.**
    * Stage `$T/pkg/AA/{AA.app, Install.txt[, AA (portable).command]}`.
    * Run `ditto -c -k --keepParent "$T/pkg/AA" "mac/dist/AA-$VERSION-$BUILD_NUMBER-macOS.zip"`.
    * Optionally build the dmg.
    * Write `shasum -a 256` results to `mac/dist/SHA256SUMS`.
14. **Notarise**, only with a Developer ID identity and `NOTARY_PROFILE` set:
    `xcrun notarytool submit <zip> --keychain-profile "$NOTARY_PROFILE" --wait`, then
    `xcrun stapler staple mac/dist/AA.app`, then re-package.
15. **Size and summary.** Check the size against `AA_MAX_APP_MB`, print the SHELL-202 summary, and remove
    `$T`.

**Exit codes.** 0 = success. 1 = a step failed; stderr says `build-app.sh: step <n> (<name>) failed`.
2 = usage error.

#### BD.3.10 Icon generation
```
src = mac/Resources/AppIcon-1024.png                                   # preferred vector re-draw (Appendix C)
if missing: sips -s format png <mac copy of AA.ico> --out $T/icon256.png   # sips picks the largest frame: 256×256
            src = $T/icon256.png; warn "AppIcon: upscaling the 256-px ICO frame for 512/1024 slots"
mkdir $T/AppIcon.iconset
for (file, px) in [(icon_16x16,16), (icon_16x16@2x,32), (icon_32x32,32), (icon_32x32@2x,64),
                   (icon_128x128,128), (icon_128x128@2x,256), (icon_256x256,256), (icon_256x256@2x,512),
                   (icon_512x512,512), (icon_512x512@2x,1024)]:
    sips -z px px src --out $T/AppIcon.iconset/file.png
iconutil -c icns $T/AppIcon.iconset -o Contents/Resources/AppIcon.icns
if exists mac/Resources/AppIcon.icon:                                   # optional macOS 26 layered icon
    xcrun actool mac/Resources/AppIcon.icon --compile Contents/Resources --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist $T/icon.plist
```
Keep the transparent corners. Do not add a squircle mask to the round art; macOS 26 frames legacy art
itself, and Icon Composer art replaces it.

#### BD.3.11 Version stamping
* `CFBundleShortVersionString` = `VERSION` (`MAJOR.MINOR.PATCH`), default `1.0.0`. The Windows assembly has
  no explicit version, so it reports 1.0.0.0.
* `CFBundleVersion` = `BUILD_NUMBER`, a positive integer that increases monotonically (the commit count on
  the branch).
* `AABuildDate` = `yyyy-MM-dd` (UTC).
* `AAGitCommit` = `git rev-parse --short=7 HEAD`, plus `-dirty` when `git status --porcelain` is non-empty.
* About panel: the standard panel shows `Version 1.0.0 (412)` with the credits text unchanged,
  `Created by B.E.P. Avida - May 2026` (SHELL-115).
* `--version` prints `AA 1.0.0 (412) arm64`, or `AA 1.0.0 (412) x86_64`.

#### BD.3.12 Smoke-test harness
`t` is seconds since `AAMain.main` entry, from a monotonic clock.
```
guard opts.dataDir != nil else exit(3) with stderr "--smoke-test needs --data-dir <empty folder>"
guard !exists(AppFolder/data.json) && !exists(AppFolder/settings.json)
      else exit(3) with stderr "--smoke-test refuses to run on a data folder that already holds data: <path>"
suppress: the translocation sheet, notification-authorisation requests, the MenuBarExtra
emit start   {version, build, arch, appFolder, t}
splash window becomes visible (occlusionState ∋ .visible)     → emit splash {t}
login window becomes visible                                  → emit login {t, splashSeconds}
      expect 2.3 ≤ splashSeconds ≤ 2.9
LoginModel.submit(username: "44233", password: "wrong")
      expect errorText == "Incorrect username or password." and password == ""  → emit login-rejected {message}
LoginModel.submit(username: " 44233 ", password: "redemption")     # the spaces also prove the Trim rule
      → emit login-accepted {t}
main window visible and status.hasPrefix("Loaded — ")         → emit main {t, title, status}
      expect title == "AA — " + AppIdentity and status == "Loaded — " + AppFolder/data.json
poll every 100 ms, up to 3 s, for AppFolder/data.json          → emit autosaved {t, bytes, lastDigestDate}
      (the SHELL-132 digest marks the data dirty; the 750 ms repository debounce writes it)
NSApp.terminate(nil) → the full close pipeline (SHELL-056); applicationWillTerminate → emit quit {t}; flush stdout
process exit code 0
any failed expectation → emit fail {step, expected, actual}; exit(1)     # the folder is scratch; nothing to undo
watchdog: 30 s after start → emit fail {step: "timeout"}; exit(2)
```
`LoginModel.submit` is the same entry point the `Sign in` button calls. The harness uses the real windows,
timers and repository; it does not shorten the splash or skip the credential check.

#### BD.3.13 Constants

| constant | value | where |
|---|---|---|
| bundle id | `com.eriskay.aa` | Info.plist, TCC, UserDefaults, os_log subsystem |
| deployment target | macOS 26.0 (both slices) | Package.swift, `LSMinimumSystemVersion`, `minos` |
| slices | `arm64`, `x86_64` | SHELL-181 |
| size tripwire | 60 MB unpacked | SHELL-180 |
| splash | 2.4 s (smoke tolerance 2.3–2.9 s) | SHELL-003, BD.3.12 |
| smoke: data.json after main | ≤ 3 s | BD.3.12 |
| smoke watchdog | 30 s | BD.3.12 |
| smoke exit codes | 0 ok / 1 expectation failed / 2 timeout / 3 refused | BD.3.12 |
| build-app.sh exit codes | 0 ok / 1 step failed / 2 usage | BD.3.9 |
| `--data-dir=` prefix length | 11 | BD.3.1 |
| crash log fallback | `~/Library/Logs/AA/crash.log` | SHELL-197 |
| default AppFolder | `~/Library/Application Support/AA` | SHELL-193 |
| exported UTIs | `com.eriskay.aa.bundle` (`aaz`), `com.eriskay.aa.schedule` (`aasched.json`), `com.eriskay.aa.xaml`, `com.eriskay.aa.task-ref` | SHELL-185/186 |

### BD.4 Data formats

#### BD.4.1 `mac/Packaging/Info.plist` (template; `@…@` is substituted by build-app.sh)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>AA</string>
	<key>CFBundleIdentifier</key>
	<string>com.eriskay.aa</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>AA</string>
	<key>CFBundleDisplayName</key>
	<string>AA</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleShortVersionString</key>
	<string>@VERSION@</string>
	<key>CFBundleVersion</key>
	<string>@BUILD@</string>
	<key>AABuildDate</key>
	<string>@BUILDDATE@</string>
	<key>AAGitCommit</key>
	<string>@GITCOMMIT@</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleSupportedPlatforms</key>
	<array><string>MacOSX</string></array>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
	<key>NSHumanReadableCopyright</key>
	<string>Created by B.E.P. Avida - May 2026</string>
	<key>NSCameraUsageDescription</key>
	<string>AA uses the camera only during Flash Sync ▸ Receive, to read the QR codes your iPhone shows on its screen. Video is never recorded, saved or sent anywhere.</string>
	<key>NSCameraUseContinuityCameraDeviceType</key>
	<true/>
	<key>NSDesktopFolderUsageDescription</key>
	<string>AA opens files you linked in place from your Desktop, and reads or saves the imports, exports and backups you choose there.</string>
	<key>NSDocumentsFolderUsageDescription</key>
	<string>AA opens files you linked in place from your Documents folder, and reads or saves the imports, exports and backups you choose there.</string>
	<key>NSDownloadsFolderUsageDescription</key>
	<string>AA opens files you linked in place from your Downloads folder, and reads or saves the imports, exports and backups you choose there.</string>
	<key>NSRemovableVolumesUsageDescription</key>
	<string>AA opens files you linked in place on external drives, and can keep its data folder or a shared save file on an external drive.</string>
	<key>NSNetworkVolumesUsageDescription</key>
	<string>AA opens files you linked in place on network drives, and keeps a shared save file on a network drive in sync with other copies of AA.</string>
	<key>NSFileProviderDomainUsageDescription</key>
	<string>AA saves backup copies into your Google Drive folder and reads them back when you ask.</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>AA bundle</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Owner</string>
			<key>LSItemContentTypes</key>
			<array><string>com.eriskay.aa.bundle</string></array>
		</dict>
		<dict>
			<key>CFBundleTypeName</key>
			<string>ZIP archive (AA bundle)</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array><string>public.zip-archive</string></array>
		</dict>
	</array>
	<key>UTExportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>com.eriskay.aa.bundle</string>
			<key>UTTypeDescription</key>
			<string>AA bundle</string>
			<key>UTTypeConformsTo</key>
			<array><string>public.zip-archive</string></array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array><string>aaz</string></array>
			</dict>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>com.eriskay.aa.schedule</string>
			<key>UTTypeDescription</key>
			<string>AA schedule</string>
			<key>UTTypeConformsTo</key>
			<array><string>public.json</string></array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array><string>aasched.json</string></array>
			</dict>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>com.eriskay.aa.xaml</string>
			<key>UTTypeDescription</key>
			<string>AA rich text</string>
			<key>UTTypeConformsTo</key>
			<array><string>public.data</string></array>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>com.eriskay.aa.task-ref</string>
			<key>UTTypeDescription</key>
			<string>AA task reference</string>
			<key>UTTypeConformsTo</key>
			<array><string>public.data</string></array>
		</dict>
	</array>
</dict>
</plist>
```
Notes:
* build-app.sh adds `CFBundleIconName` = `AppIcon` only when `Assets.car` is present, and `LSEnvironment`
  only for a baked build.
* The file is UTF-8 because of `▸`.
* Every user-visible string above is Mac-only; Windows has no equivalent.

#### BD.4.2 `mac/Packaging/AA.entitlements` (shipped)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.camera</key>
	<true/>
</dict>
</plist>
```

#### BD.4.3 `mac/Packaging/AA-sandbox.entitlements` (reference only — NOT used by build-app.sh)
```xml
<dict>
	<key>com.apple.security.app-sandbox</key>                   <true/>
	<key>com.apple.security.device.camera</key>                 <true/>   <!-- Flash Sync receive -->
	<key>com.apple.security.network.client</key>                <true/>   <!-- Drive REST, OAuth token endpoint, Gemini -->
	<key>com.apple.security.network.server</key>                <true/>   <!-- OAuth loopback listener on 127.0.0.1 -->
	<key>com.apple.security.files.user-selected.read-write</key> <true/>  <!-- panels, drag-in -->
	<key>com.apple.security.files.bookmarks.app-scope</key>     <true/>   <!-- persisted access, BD.6.3 -->
</dict>
```
Adopting it requires every change listed in BD.6.3. It is not a switch.

#### BD.4.4 Bundle layout
```
AA.app/
└── Contents/
    ├── Info.plist                      BD.4.1 (substituted)
    ├── PkgInfo                         "APPL????" (8 bytes)
    ├── MacOS/
    │   └── AA                          universal Mach-O: x86_64 + arm64, minos 26.0
    ├── Resources/
    │   ├── AppIcon.icns
    │   ├── Assets.car                  (optional: Icon Composer icon)
    │   ├── Splash.png                  byte-identical to AA/Assets/Splash.png
    │   ├── sire2_question_bank.json    byte-identical to AA/Sire/Data/sire2_question_bank.json
    │   ├── MenuBarIconTemplate.png
    │   ├── MenuBarIconTemplate@2x.png
    │   └── AA_AACore.bundle/ …         (SwiftPM resource bundles, if the targets declare resources)
    └── _CodeSignature/
        └── CodeResources
```
The bundle has no `Frameworks/`, `PlugIns/`, `Library/`, `Helpers/` or `XPCServices/`, no symlinks and no
`.DS_Store`.

#### BD.4.5 Build artefacts
```
mac/dist/AA.app
mac/dist/AA.app.dSYM                              debug symbols (≙ AA.pdb); not shipped
mac/dist/AA-{VERSION}-{BUILD}-macOS.zip           root folder "AA/": AA.app, Install.txt[, "AA (portable).command"]
mac/dist/AA-{VERSION}-{BUILD}-macOS.dmg           only with PACKAGE=dmg
mac/dist/SHA256SUMS                               "<sha256>  <file name>" per artefact
```
`Install.txt` is plain UTF-8 and holds:
* the SHELL-189 procedure;
* the note to move the app before opening it;
* where the data lives: `~/Library/Application Support/AA`, or `--data-dir`;
* the portable recipe (SHELL-195);
* the camera note: macOS asks the first time Flash Sync ▸ Receive starts.

#### BD.4.6 Portable launcher `AA (portable).command` (mode 0755, LF line endings)
```sh
#!/bin/sh
# Start AA with its data in the "AA Data" folder beside this file (portable use, e.g. on a USB stick).
here="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/open -n -a "$here/AA.app" --args --data-dir "$here/AA Data"
```
The Windows counterpart is user-made, since the Windows source is read-only:
`AA (portable).cmd` = `@echo off` / `set "AA_DATA_DIR=%~dp0AA Data"` / `start "" "%~dp0AA.exe"`. Both point at
the same `AA Data` folder when the stick holds both apps.

#### BD.4.7 Smoke-test report (stdout, one JSON object per line)
Numbers are seconds with 3 decimals; strings are JSON-escaped. Example:
```
{"event":"start","version":"1.0.0","build":"412","arch":"arm64","appFolder":"/tmp/aa-smoke.Qx81/aa","t":0.004}
{"event":"splash","t":0.391}
{"event":"login","t":2.797,"splashSeconds":2.406}
{"event":"login-rejected","message":"Incorrect username or password."}
{"event":"login-accepted","t":2.846}
{"event":"main","t":3.118,"title":"AA — Bridge-Mac","status":"Loaded — /tmp/aa-smoke.Qx81/aa/data.json"}
{"event":"autosaved","t":3.972,"bytes":541,"lastDigestDate":"2026-09-30"}
{"event":"quit","t":4.103}
```
On failure: `{"event":"fail","step":"login","expected":"2.3 ≤ splashSeconds ≤ 2.9","actual":"3.412"}`,
followed by exit code 1 (or 2 for `"step":"timeout"`).

#### BD.4.8 Data folder after a pristine smoke run
**Present:**
* `data.json` (a file);
* `files/` (an empty directory, created by `Load()`).

**Absent:**
* `settings.json`: no startup path writes settings, on Windows or on the Mac;
* `crash.log`;
* `qrmodels/`, `google-token/`, `qrsync-baseline.json`, `google_client_secret.json`;
* any `*.tmp`.

`data.json` after the digest autosave (before quit) is the fresh-database JSON from 01 §4.2.1 with two
changes. `"LastDigestDate":"{today}"` is appended as the **last** `Ui` key, because `LastDigestDate` is
declared last in `UiState`. `"LastModified"` is inserted before `SchemaVersion`. For example:
```
{"Equipment":[],"Tasks":[],"Procedures":[],"Vessels":[],"Groups":[],"Crew":[],"Log":[],"ChecklistTemplates":[],"ListGroups":[],"QuickBuckets":[],"Ports":[],"ScheduleTemplates":[],"Trash":[],"Sire":{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}},"Ui":{"SelectedMainTabIndex":0,"ShowShortcutBar":true,"QuickViewPinIds":[],"TabColors":{},"TabOrder":[],"SortAZ":{},"GroupExpanded":{},"CrewTableColumns":[],"CrewTableShownColumns":[],"LastDigestDate":"2026-09-30"},"LastModified":"2026-09-30T14:03:12.1234567+02:00","SchemaVersion":1}
```
This shape is derived from the Windows code path. Confirm it once against a Windows run with an empty
`AA_DATA_DIR` (Q-17).

After quit, `Ui` also carries:
* `WindowLeft`, `WindowTop`, `WindowWidth` and `WindowHeight` (the main window's outer frame);
* `"WindowState":"Normal"`;
* whatever `CaptureUiState` writes for the pages (`CalendarSelectedDate`, `CalendarViewMode`, …).

`LastModified` is re-stamped.

#### BD.4.9 Mac-local state that never enters `data.json` or `settings.json`
* **UserDefaults** domain `com.eriskay.aa` (`~/Library/Preferences/com.eriskay.aa.plist`): Windows-path and
  drive-letter mappings (05, 10), the optional "follow system appearance", security-scoped bookmarks (only if
  ever sandboxed), and don't-show-again flags.
* **Keychain** generic-password items: the local-data key, the Drive-token key and the Gemini key. Their
  service and account names are owned by 01 §6.5, 12 §6.9 and 14 §6.3; see Q-17.
* **Per user, not per folder.** Both are per user and per Mac, not per data folder. A portable data folder
  does not carry them, just as Windows DPAPI secrets stay behind.

### BD.5 Dependencies

#### BD.5.1 Build-time tools

| tool | used for | provided by |
|---|---|---|
| `swift` (Swift 6.4) | build, test | Xcode 27 toolchain |
| Xcode 27 (full, not just the CLT) | macOS SDK with both slices, `actool` | Xcode |
| `lipo`, `dsymutil`, `strip`, `otool`, `vtool` (via `xcrun`) | assemble and verify the binary | Xcode |
| `plutil` | Info.plist lint and edits | macOS |
| `sips`, `iconutil` | icon | macOS |
| `actool` (optional) | Icon Composer icon | Xcode |
| `codesign` | sign and verify | macOS |
| `xattr` | strip extended attributes before signing | macOS |
| `ditto`, `hdiutil` | zip and dmg | macOS |
| `shasum` | resource checks, SHA256SUMS | macOS |
| `git` | build number, commit | Xcode / CLT |
| `notarytool`, `stapler` (optional) | notarisation | Xcode |
| `arch` + Rosetta 2 (optional) | run the x86_64 slice on Apple silicon | macOS (Rosetta installed on demand) |
| .NET 10 SDK (optional) | `Tests/FlashSync.Interop` vectors | Microsoft |

#### BD.5.2 Runtime APIs used by this area
* Foundation: `ProcessInfo` (arguments, environment, `beginActivity`), `FileManager`, `Bundle`, `URL`.
* AppKit: `NSApplicationDelegate` (`application(_:open:)`, termination), `NSAlert`,
  `NSApp.setActivationPolicy`, `NSWorkspace`.
* MetricKit: `MXMetricManager`, `MXCrashDiagnostic`.
* `os.Logger`.
* Darwin: `signal`, `open`, `write`, `access`.
* UniformTypeIdentifiers.
* None of these needs an entitlement.

#### BD.5.3 Windows-only build/launch mechanisms and their Mac equivalents

| Windows | Mac |
|---|---|
| .NET single-file host; self-extraction of natives to a user cache on first run | not needed: an app bundle, nothing extracted |
| `--self-contained` .NET 10 runtime | the OS Swift runtime and system frameworks |
| `ApplicationIcon` (PE icon), `Icon="pack://application:,,,/AA.ico"` on windows | `AppIcon.icns` / `Assets.car`; no per-window icons |
| WPF `Resource` + `Application.GetResourceStream` | `Bundle.main` + the resource locator (BD.3.4) |
| `EmbeddedResource` + `Assembly.GetManifestResourceStream` + extraction to `qrmodels/` | not needed (Vision) |
| MSBuild target `TrimOpenCvFfmpeg` | not needed |
| `Environment.GetEnvironmentVariable("AA_DATA_DIR")`, `SpecialFolder.LocalApplicationData` | `ProcessInfo.environment`, `--data-dir`, Application Support |
| `Environment.MachineName` | `Host.current().localizedName` (§6.9) |
| `Path.GetTempPath()` (`%TEMP%`) | `FileManager.default.temporaryDirectory` |
| SmartScreen / Mark-of-the-Web | Gatekeeper, quarantine, translocation (SHELL-189/190) |
| `DispatcherUnhandledException`, `AppDomain.UnhandledException` → crash.log | §6.1 + SHELL-197 |
| `dotnet build` / `dotnet publish` | `swift build` / `build-app.sh` |

#### BD.5.4 Cross-spec links
* 01 DATA-010…013 and §4.12: the AppFolder layout. Every derived path uses the BD.3.2 result.
* 01 §6.5, 12 §6.9, 14 §6.3: Keychain items. BD.6.5 states the ad-hoc signing rules they must follow.
* 05 §6.9 and 10 §6.2: link-in-place and Windows-path mapping (BD.6.4).
* 13 §6.4: the camera. SHELL-183 provides its Info.plist and entitlement.
* 14 §6.3: the OAuth loopback listener must bind 127.0.0.1 only (SHELL-182, absent keys).
* 12 §2: lazy SIRE bank load through BD.3.4.
* This spec: SHELL-001 (crash dialog), SHELL-003/004 (splash, login), SHELL-056 (quit pipeline), SHELL-071
  (bundle import, reused by SHELL-185), SHELL-120 (review gate).

### BD.6 macOS adaptation notes

#### BD.6.1 One file vs one bundle
A macOS app cannot be a single file. The closest faithful form is an application bundle, which Finder,
the Dock, Spotlight and Launchpad all treat as one item. For transport it is zipped with `ditto`.
Everything else the single exe promises holds:
* no runtime to install;
* copy anywhere;
* nothing written next to the app;
* every resource inside.

The Windows first-run self-extraction step has no counterpart; launches are uniformly fast.

#### BD.6.2 Architecture
See SHELL-181. Universal is the faithful reading of "any 64-bit machine" for as long as the deployment
target includes Intel Macs.

#### BD.6.3 Sandbox: what would break (why AA is not sandboxed)

| capability | why the App Sandbox breaks it | the workaround if AA is ever sandboxed |
|---|---|---|
| data folder via `--data-dir` / `AA_DATA_DIR` | no access outside the container, and an argument can't grant access | a "Choose Data Folder…" command that stores an app-scope bookmark |
| default AppFolder | moves to `~/Library/Containers/com.eriskay.aa/Data/Library/Application Support/AA` | a one-time migration from the non-sandboxed folder |
| shared save file on a network volume, replaced atomically | a grant for the file does not cover creating `{path}.{32hex}.tmp` beside it | ask for the **containing folder** (NSOpenPanel, `canChooseDirectories`) and bookmark the folder |
| external active data file (Import from file) | same | same (bookmark the folder) |
| link-in-place files, including mapped UNC and drive-letter paths (05) | arbitrary paths weren't user-selected on this Mac | bookmark each file at link time (Mac-local store keyed by `FileItem.Id` + `Path`); links made on Windows must be re-selected once |
| Open all (routine), open linked file | NSWorkspace can open only what AA can access | the same bookmarks |
| Google Drive folder auto-detect (14 §6.2) | cannot probe `~/Library/CloudStorage/*` or `/Volumes/*` | the user picks the folder once (bookmark) |
| Folder Builder base folder | arbitrary path | folder bookmark |
| OAuth loopback, Drive, Gemini | network | `network.server` + `network.client` |
| camera | device | `device.camera` |
| crash-log fallback in `~/Library/Logs/AA` | outside the container | container `Library/Logs` |

Bookmarks would live in UserDefaults keyed by the absolute path string, never in `settings.json` or
`data.json`. When a bookmark goes stale, AA would ask for the folder again. The user-visible drift from
Windows behaviour is the reason for rejecting the sandbox.

#### BD.6.4 Reaching Windows, UNC and network paths without the sandbox
* **Linked-in-place paths** keep their Windows form verbatim (brief).
  * At open time, `\\server\share\rest` maps to `/Volumes/<share>/rest` when a mounted volume's
    `volumeURLForRemountingKey` matches `smb://server/share`.
  * Otherwise AA offers to mount it with `NSWorkspace.shared.open(URL(string: "smb://server/share")!)`, which
    lets Finder and NetAuthAgent handle the credentials, and then retries.
  * Drive letters use the Mac-local mapping table (05 §6.9, 10 §6.2).
  * Nothing is written back to `FileItem.Path` or `QuickCard.Target`.
* **The shared save file on the Mac** is stored as a POSIX path (for example
  `/Volumes/ships/aa-shared.zip`).
  * When the share drops (a VSAT outage), the parent folder disappears and SHELL-123/125 report
    `⚠ Shared save OFFLINE since HH:mm — retrying`. This matches Windows.
  * macOS does not remount SMB shares by itself. The user reconnects (Finder ▸ Go ▸ Connect to Server, or a
    login item).
  * An optional improvement: while offline, try a silent remount once per poll with `NetFSMountURLAsync` and
    `kNetFSNoUserInteractionKey`, using the `volumeURLForRemountingKey` captured when the file was chosen
    (UserDefaults).
  * `rename(2)` of the temp file is atomic on the same SMB share.
  * FSEvents does not see writes by other machines, so the 60 s poll stays the real mechanism (§6.9).
* **Local-network privacy (macOS 15+)** does not apply to file-system access. For the OAuth listener it is
  avoided by binding to 127.0.0.1 only; never bind to all interfaces.
* The first programmatic access to a network or removable volume can show a TCC prompt (BD.6.8). Setting a
  shared file pushes to it immediately (SHELL-066) and the pre-flight touches the data folder, so the prompt
  appears in context rather than from a background timer.

#### BD.6.5 Consequences of ad-hoc signing that the app must handle
* **TCC grants** (camera; Desktop, Documents and Downloads; removable and network volumes; File Provider)
  are tied to the code signature. An ad-hoc signature is a hash of this exact build, so each new build asks
  again, and System Settings may list stale "AA" entries. A stable self-signed identity or Developer ID
  avoids this (SHELL-188).
* **Keychain.** Ad-hoc apps cannot use the data-protection keychain, which needs `keychain-access-groups` /
  `application-identifier` and therefore a provisioning profile. They use the login (file-based) keychain,
  whose item ACL trusts the creating build. After the app is replaced by a new ad-hoc build, the first read
  of an existing item shows a system prompt to allow AA to use it (Always Allow / Allow / Deny). Rules for
  every Keychain user (01 §6.5, 12, 14):
  * Create a key **only** on `errSecItemNotFound`. Never create a replacement when the item exists but is
    inaccessible; that would orphan the old key and make encrypted data unreadable for good.
  * Treat `errSecAuthFailed`, `errSecUserCanceled` and `errSecInteractionNotAllowed` as "key unavailable":
    * local data file → safe mode (SHELL-008), with the message that the key could not be read from the
      Keychain;
    * Drive token → `HasToken = false`, so the user signs in again;
    * Gemini key → treated as not set, but not deleted.
  * Never delete Keychain items on failure.
* **App Nap.** It is not a signing issue, but it is a distribution-level default. macOS can defer the timers
  of an app whose windows are all hidden or occluded; Windows has no such mechanism. While a shared save
  file is configured, hold
  `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keeping the shared save file in sync")`
  and end it in `StopSharedSaveSync`. Give each timer a tolerance of at most 10 %. Never set the global
  `NSAppSleepDisabled` key. This keeps the 60 s poll and the 1-min push close to their Windows cadence.

#### BD.6.6 Gatekeeper
See SHELL-189. A later Developer ID + notarisation release removes steps 2–4 entirely (Q-15).

#### BD.6.7 App Translocation
See SHELL-190.

#### BD.6.8 Privacy prompts (TCC) inventory

| gate | trigger in AA | Info.plist key | on Deny | tester reset |
|---|---|---|---|---|
| Camera | Flash Sync ▸ Receive ▸ Start camera | `NSCameraUsageDescription` | status text + Open System Settings (13 §6.4) | `tccutil reset Camera com.eriskay.aa` |
| Desktop / Documents / Downloads | programmatic access to linked files, a shared save file or a data folder there. Files chosen in panels or dropped are granted implicitly | `NS{Desktop,Documents,Downloads}FolderUsageDescription` | the operation fails with its normal error (`Not found`, `Open failed`, shared OFFLINE, pre-flight alert) | `tccutil reset SystemPolicyDesktopFolder com.eriskay.aa` (also `…DocumentsFolder`, `…DownloadsFolder`) |
| Removable volumes | data folder, links or shared save file on a USB drive | `NSRemovableVolumesUsageDescription` | as above | `tccutil reset SystemPolicyRemovableVolumes com.eriskay.aa` |
| Network volumes | links or shared save file on SMB | `NSNetworkVolumesUsageDescription` | as above | `tccutil reset SystemPolicyNetworkVolumes com.eriskay.aa` |
| File Provider (Google Drive for desktop) | Drive folder detection and synced-folder copies under `~/Library/CloudStorage` | `NSFileProviderDomainUsageDescription` | the Drive synced-folder copy fails with its error | `tccutil reset FileProviderDomain com.eriskay.aa` |
| Notifications | first reminder (§6.8) | — (runtime request) | reminders only in the menu-bar extra and the status line | System Settings ▸ Notifications |
| Screen Recording (optional FLASH-133) | Receive from screen | — | feature unavailable | `tccutil reset ScreenCapture com.eriskay.aa` |
| Keychain item ACL (not TCC) | first use of an existing key after a new ad-hoc build | — | BD.6.5 rules | Keychain Access ▸ item ▸ Access Control |

When a denied TCC gate is the cause (EPERM on a protected location), the existing error text may gain a
Mac-only second line: `Allow AA in System Settings ▸ Privacy & Security ▸ Files & Folders.` (for the volume
gates: `… ▸ Privacy & Security ▸ Files & Folders ▸ AA`). Everything else stays as Windows.

#### BD.6.9 Portable and cross-platform data folders
See SHELL-195/196. On both platforms the same folder works, with the same file names and JSON. What stays
per machine is the Keychain or DPAPI state and the Mac-local mappings.

#### BD.6.10 Mac-native polish that keeps every capability
* Finder **Open With ▸ AA** and a Dock-icon drop import bundles with review (SHELL-185).
* The standard About panel shows version and build.
* The Window menu lists open windows.
* `--version` gives support a one-line identification (the equivalent of the "2026-07-08 build" labels).
* The menu-bar template icon follows light and dark menu bars automatically.
* None of this removes a Windows path. Every Windows menu command still exists (§6.4).

#### BD.6.11 Genuinely impossible or changed

| Windows | Mac | closest faithful alternative |
|---|---|---|
| one `.exe` file | an application bundle (a folder shown as one item) | `ditto` zip / dmg for transport (BD.6.1) |
| env var inherited from Explorer, shortcuts, `.cmd` | Finder/Dock launches don't inherit shell variables | `--data-dir`, `open --env`, the `.command` launcher, baked `LSEnvironment` (SHELL-193/195) |
| unsigned exe runs after SmartScreen "Run anyway" | an ad-hoc app needs Privacy & Security ▸ Open Anyway once per quarantined copy | Developer ID + notarisation (Q-15) |
| run in place from the download folder | a translocated read-only copy | the hint sheet (SHELL-190); nothing depends on the location |
| no OS permission prompts | TCC prompts for camera, protected folders, volumes, File Provider, notifications | purpose strings (BD.4.1); stable signing identity to avoid re-prompts |
| DPAPI keys survive replacing the exe | the Keychain ACL prompts after an ad-hoc update | Always Allow; never regenerate keys (BD.6.5) |
| crash handler catches and continues for UI-thread exceptions | Swift traps can't be caught | §6.1 strategy + SHELL-197 |

### BD.7 Test vectors / verification

#### BD.7.1 AppFolder resolution (BD.3.1 + BD.3.2 + BD.3.3)
Assume home `/Users/u`; "default" means `/Users/u/Library/Application Support/AA`.

| # | arguments after argv[0] | `AA_DATA_DIR` | cwd | expected AppFolder | source / outcome |
|---|---|---|---|---|---|
| 1 | — | unset | `/` | default | default |
| 2 | — | `""` | `/` | default | default |
| 3 | — | `" \t\n"` | `/` | default | default |
| 4 | — | `/Volumes/STICK/AA Data` | `/` | `/Volumes/STICK/AA Data` | environment |
| 5 | — | `/Volumes/STICK/AA Data/` + newline | `/` | `/Volumes/STICK/AA Data` | environment (trimmed; trailing `/` dropped) |
| 6 | — | `~/aa-test` | `/` | `/Users/u/aa-test` | environment |
| 7 | — | `~` | `/` | `/Users/u` | environment |
| 8 | — | `data` | `/Users/u/work` | `/Users/u/work/data` | environment |
| 9 | — | `./x/../y` | `/Users/u/work` | `/Users/u/work/y` | environment |
| 10 | `--data-dir /tmp/a` | `/Volumes/S/AA` | `/` | `/tmp/a` (**not** `/private/tmp/a`) | argument beats environment |
| 11 | `--data-dir=/tmp/b` | unset | `/` | `/tmp/b` | argument |
| 12 | `--data-dir /a --data-dir /b` | unset | `/` | `/b` | argument (last wins) |
| 13 | `--data-dir` (last token) | `/e` | `/` | `/e` | environment + stderr warning |
| 14 | `--data-dir --smoke-test` | unset | `/` | default | warning; `smokeTest = true`; the smoke then refuses (exit 3) because no `--data-dir` was accepted |
| 15 | `--data-dir ""` | `/e` | `/` | `/e` | environment |
| 16 | `--data-dir=` | unset | `/` | default | default |
| 17 | `-NSDocumentRevisionsDebugMode YES --data-dir /t` | unset | `/` | `/t` | argument |
| 18 | `-psn_0_12345 --data-dir /t` | unset | `/` | `/t` | argument |
| 19 | `--Data-Dir /t` | unset | `/` | default | default (flags are case-sensitive) |
| 20 | — | `C:\AA` | `/` | — | `.windowsPath`; alert with `Quit` only |
| 21 | — | `\\srv\share\AA` | `/` | — | `.windowsPath` |
| 22 | `--data-dir "E:/AA Data"` | unset | `/` | — | `.windowsPath` (argument) |
| 23 | — | `/Volumes/NOPE/AA` (no `/Volumes/NOPE`) | `/` | resolves | pre-flight `.volumeNotMounted("NOPE")`; no `mkdir` attempted |
| 24 | — | `/System/AA` | `/` | resolves | pre-flight `.cannotCreate` (read-only system volume) |
| 25 | `--data-dir /tmp/f`, where `/tmp/f` is a regular file | unset | `/` | resolves | pre-flight `.notAFolder` |
| 26 | `--version --data-dir /Volumes/NOPE` | unset | `/` | — | prints the version, exits 0; no pre-flight, no alert |

Alert texts for rows 20 and 23: title `AA can't open its data folder`. Row 23's message is:
```
AA couldn't open or create its data folder:

/Volumes/NOPE/AA

The drive “NOPE” isn't connected. Connect it, then choose Try Again.

The folder comes from the AA_DATA_DIR environment variable.
```

#### BD.7.2 Translocation detection

| `Bundle.main.bundlePath` | translocated |
|---|---|
| `/private/var/folders/7k/x2/T/AppTranslocation/6F1E0C2A-1B2C-4D5E-8F90-A1B2C3D4E5F6/d/AA.app` | yes |
| `/Applications/AA.app` | no |
| `/Users/u/Downloads/AA/AA.app` (not quarantined) | no |
| `/Volumes/STICK/AA.app` | no |

#### BD.7.3 Resource integrity (pin in AACoreTests and in build-app.sh step 2)

| file | SHA-256 | size |
|---|---|---|
| `sire2_question_bank.json` | `e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf` | 3,350,301 B |
| `Splash.png` | `1489fd928894042eda13a510b6916eb18ccb0310fa54b035d2e82682a84539a6` | 97,640 B (560×632, alpha) |
| `AA.ico` (source only) | `699efada2d9160395562903ce37aa32acbe4a9a983fb85c585c5469555497f12` | 45,294 B |

`sips -s format png AA.ico --out x.png` gives 256×256; this was checked on the build host. The iconset
contains 10 PNGs at 16, 32, 32, 64, 128, 256, 256, 512, 512 and 1024 px. `iconutil` accepts it.

#### BD.7.4 Bundle assertions (build-app.sh step 11; each line: command → expected)
```
A=mac/dist/AA.app; P="$A/Contents/Info.plist"; X="$A/Contents/MacOS/AA"
plutil -lint "$P"                                                   → "…: OK"
plutil -extract CFBundleIdentifier raw "$P"                         → com.eriskay.aa
plutil -extract CFBundleExecutable raw "$P"                         → AA
plutil -extract LSMinimumSystemVersion raw "$P"                     → 26.0
plutil -extract LSApplicationCategoryType raw "$P"                  → public.app-category.productivity
plutil -extract NSHumanReadableCopyright raw "$P"                   → Created by B.E.P. Avida - May 2026
plutil -extract NSCameraUsageDescription raw "$P"                   → the exact SHELL-183 text
plutil -extract UTExportedTypeDeclarations.0.UTTypeIdentifier raw "$P" → com.eriskay.aa.bundle
plutil -extract NSMicrophoneUsageDescription raw "$P"               → error (key must be absent)
plutil -extract LSUIElement raw "$P"                                → error (key must be absent)
head -c 8 "$A/Contents/PkgInfo"                                     → APPL????
lipo -archs "$X"                                                    → x86_64 arm64
xcrun vtool -arch arm64  -show-build "$X" | grep minos              → minos 26.0
xcrun vtool -arch x86_64 -show-build "$X" | grep minos              → minos 26.0
otool -L "$X" | tail -n +2 | grep -v -E '^[[:space:]]+(/usr/lib/|/System/Library/Frameworks/)'  → (no output)
test ! -e "$A/Contents/Frameworks" && [ -z "$(find "$A" -type l)" ] → true
codesign --verify --strict --verbose=2 "$A"                         → "valid on disk" + "satisfies its Designated Requirement"
codesign -d --verbose=2 "$A" 2>&1                                   → Identifier=com.eriskay.aa; flags=0x10002(adhoc,runtime); Signature=adhoc
codesign -d --entitlements - --xml "$A"                             → exactly one key: com.apple.security.device.camera = true
shasum -a 256 "$A/Contents/Resources/sire2_question_bank.json"      → BD.7.3 value
shasum -a 256 "$A/Contents/Resources/Splash.png"                    → BD.7.3 value
"$X" --version; echo $?                                             → "AA 1.0.0 (412) arm64", 0, no window opens
arch -x86_64 "$X" --version                                         → "AA 1.0.0 (412) x86_64" (Rosetta only)
du -sm "$A" | cut -f1                                               → ≤ 60
```
With a named identity, the `flags` line reads `0x10000(runtime)` and `Signature` names the certificate.
After notarisation, `spctl --assess --type execute -vv "$A"` says `accepted` / `source=Notarized Developer ID`.
For ad-hoc builds `spctl` reports `rejected`; that is expected and not a failure.

#### BD.7.5 Parser, version and crash-sink vectors
* `--version` with Info.plist `1.0.0` / `412` on arm64 → `AA 1.0.0 (412) arm64`. Unbundled →
  `AA dev (unbundled) arm64`.
* `CFBundleVersion` from `git rev-list --count HEAD` = `412` → `412`. With no git → `1`.
* `AAGitCommit`: a clean tree at `a1b2c3d…` → `a1b2c3d`; a dirty tree → `a1b2c3d-dirty`.
* Crash block, local time 2026-09-30 14:03:12, details `X` →
  `[2026-09-30 14:03:12] X\r\n\r\n` (bytes `0D 0A 0D 0A` at the end).
* Crash with an unwritable AppFolder and a writable `~/Library/Logs` → the block goes to
  `/Users/u/Library/Logs/AA/crash.log`, and the dialog ends with
  `The full details were written to:\n/Users/u/Library/Logs/AA/crash.log`.
* Both locations unwritable → the dialog ends with `The details could not be written to a log file.`
* Signal marker → `[crash marker] signal 5\r\n\r\n` (SIGTRAP). The next launch appends the MetricKit payload
  block and shows the dialog.

#### BD.7.6 Automated smoke
In a scratch folder,
`dist/AA.app/Contents/MacOS/AA --data-dir "$S/aa" --smoke-test; echo $?` prints the BD.4.7 event sequence
(`start`, `splash`, `login`, `login-rejected`, `login-accepted`, `main`, `autosaved`, `quit`) and exits 0.
Afterwards BD.4.8 holds for `$S/aa`.

Negative cases:
* Running it again on the same folder → exit 3 with the refusal text, and the folder is unchanged.
* Without `--data-dir` → exit 3.

#### BD.7.7 Manual launch smoke checklist (every release; the Windows smoke in Mac form)
1. Start from Finder with a fresh data folder (the `.command` launcher, or
   `open -n -a dist/AA.app --args --data-dir /tmp/aa-manual`). Optionally reset first with
   `tccutil reset All com.eriskay.aa`.
2. The splash appears centred, borderless and floating: white, with a 1-pt `#DDDDDD` border and the 560×632
   pt image. No title bar, no Dock-window entry. It closes by itself after about 2.4 s.
3. The login window `AA — Sign in` (420×280) appears with Username focused. A wrong password shows
   `Incorrect username or password.`, clears the password and focuses it. `44233` / `redemption` and Return
   open the main window.
4. The main window is `AA — {Computer Name}`, 1280×820 and centred on first run. The status reads
   `Loaded — /tmp/aa-manual/data.json`. The sidebar shows 13 sections and every menu is enabled. Within
   about 1 s `data.json` exists in the folder.
5. ⌘Q quits without a prompt. `data.json` now has `Window*` keys.
6. Relaunch: the same frame and section come back.
7. Relaunch and click **Exit** at the login, or close the login window. The app quits and the data folder is
   unchanged. With a brand-new folder, the folder now exists and is empty.
8. File ▸ Flash Sync ▸ Receive ▸ Start camera shows the system camera prompt with the SHELL-183 text (first
   time only).
9. Toggle View ▸ Dark Mode. The theme is remembered on relaunch, and the splash stays white.
10. Double-click a `.aaz` in Finder while AA is running. The review window appears; Cancel changes nothing.
11. Run steps 2–5 once more **without** `--data-dir`. The folder is `~/Library/Application Support/AA`.

#### BD.7.8 Cross-version data smoke
1. **Windows → Mac.** Copy a Windows `%LOCALAPPDATA%\AA` (plaintext; `EncryptLocalData` off) to
   `/tmp/aa-win`. Run `shasum settings.json` and keep the result. Launch with `--data-dir /tmp/aa-win` and
   expect:
   * `Loaded — /tmp/aa-win/data.json`;
   * no safe mode and no `Newer data format`;
   * attachments under `files/` open;
   * linked Windows paths report `Not found` or map per 05.

   Quit without changing settings: `settings.json` has the same SHA-256. `data.json` differs only in the
   stamp and `Ui` window keys, and the Windows build loads it without a warning.
2. **DPAPI file on the Mac.** Copy a Windows folder with `EncryptLocalData` on. The Mac opens in safe mode
   with the Mac-specific message (01 §6.5), and `data.json` is byte-identical after quitting. Nothing is
   written.
3. **Mac → Windows.** File ▸ Export Data Folder (ZIP)… on the Mac, then Windows File ▸ Import data folder
   (ZIP)…. The review gate shows the expected changes, and the import completes with
   `Imported … (with attachments)`.
4. **USB stick, optional.** Keep one `AA Data` folder on an exFAT stick with both `AA.exe` (`.cmd` wrapper)
   and `AA.app` (`.command`). Edit on each side in turn. Each side loads the other's save, and `files/`
   holds no `._*` or `.DS_Store` entries written by the Mac.

#### BD.7.9 Clean machine and Intel (SHELL-207)
* **New user account or second Mac.** Copy the zip over by AirDrop, which quarantines it. Unzip, move to
  Applications, and follow the SHELL-189 steps. The BD.7.7 checklist passes.
* **Translocation.** Unzip in Downloads and open the app there, without moving it. The
  `Move AA to Applications` sheet appears after login, and data still goes to
  `~/Library/Application Support/AA`.
* **Resources.** On the build Mac, move `mac/.build` aside and launch `dist/AA.app`. The splash image shows
  and the SIRE section loads; this proves the resources are inside the bundle (SHELL-198).
* **Intel.** Run `open --arch x86_64 dist/AA.app` (Rosetta) or use an Intel Mac on macOS 26. BD.7.7 steps 2–8
  pass, and `--version` prints `x86_64`.

### BD.8 Windows defects, discrepancies & decisions (continues section 8)

| id | issue | faithful behaviour | recommended Mac behaviour |
|---|---|---|---|
| W-17 | `ReportCrash` shows its dialog only if the `crash.log` append succeeded. The `MessageBox` is inside the same `try`, after `AppendAllText`. With an unwritable or unreachable AppFolder a crash is completely silent, contradicting the "never fail silently" comment (`App.xaml.cs:48-63`) | silent | always show the dialog; fall back to `~/Library/Logs/AA/crash.log` (SHELL-197) |
| W-18 | An unreachable `AA_DATA_DIR` (removed USB stick, missing drive letter). `LoadSettings` swallows the error, then `DataStore.Load()` throws from `Directory.CreateDirectory` inside `MainWindow.OnLoaded`. The dispatcher handler catches it, and W-17 makes it silent. The main window shows with uninitialised pages, no repository and no autosave timer. If the drive letter exists but the folder doesn't, an **empty** data folder is created silently | as coded | pre-flight alert with Try Again / Quit, never create folders under a missing `/Volumes/<name>`, never fall back silently (SHELL-194) |
| W-19 | PROGRESS disagrees on the size and verification facts: "Verification" says ~72 MB, the splash update ~76.5 MB, "Latest portable build" ~80 MB (2026-07-08), and "How to run" ~112 MB ("grew from ~72 MB" with OpenCV). "Project layout" lists only the original seven views | — | treat ~112 MB (with OpenCV) as current and the source tree as the inventory; the Mac size tripwire is independent (SHELL-180) |
| W-20 | The `AA_DATA_DIR` value is used untrimmed. A trailing newline or space (from a script or a pasted value) becomes part of the folder name; Win32 path normalisation hides trailing spaces but not other whitespace | as coded | trim surrounding whitespace and newlines (BD.3.2) |
| W-21 | `OnStartup` ignores `e.Args`, so Windows has no per-launch data-folder switch. A Windows shortcut can't set an environment variable, so portable use needs a `.cmd` wrapper (BD.4.6) | — | `--data-dir` is Mac-only. Document it as such, and propose it for a future Windows build (outside this port: the Windows source is read-only) |

#### BD.8.1 Open questions (continuing 8.1)
* **Q-10** Ship Universal (arm64 + x86_64) while the deployment target is macOS 26, or arm64 only?
  Recommendation: Universal, dropping x86_64 when the target moves to 27.
* **Q-11** Adopt the `com.eriskay.aa.*` UTI namespace (`…bundle`, `…schedule`, `…xaml`, `…task-ref`),
  superseding `com.aa.bundle` (§6.9) and `com.bepavida.aa.bundle` (01 §6.7). If the iPhone app already
  declares a type for `.aaz`, which identifier does it use? The two apps must declare the same one.
* **Q-12** Accept the Mac enhancement that double-click, Open With and a Dock drop on `.aaz` (owner) and
  `.zip` (alternate) run the import-with-review flow? Windows has no file association.
* **Q-13** Keep `--smoke-test` in release builds? It is guarded by a fresh `--data-dir` and exercises rather
  than bypasses the gate. The alternative is DEBUG-only, with a manual-only release smoke. Recommendation:
  keep it.
* **Q-14** Add a single-instance lock per data folder (an advisory `flock` on `<AppFolder>/.aa.lock`, with
  the alert "AA is already running with this data folder")? Windows has none: two instances, or AA.exe and
  AA.app on one stick, can overwrite each other's saves.
* **Q-15** Stay with ad-hoc signing (the brief), which needs the SHELL-189 procedure on every Mac and
  re-prompts TCC and Keychain after each build? Or move to Developer ID + notarisation for distribution
  beyond the developer's own Macs?
* **Q-16** Adopt the cross-platform `EncryptLocalData` guard (SHELL-196), so a setting that arrived from
  Windows in a shared folder doesn't silently make the folder Mac-only?
* **Q-17** (a) Confirm the BD.4.8 post-smoke `data.json` against a Windows run with an empty
  `AA_DATA_DIR`. (b) Freeze the Keychain service and account names before the first release. 01 §6.5 says
  `AA.LocalDataKey`/`v1` and `AA.GoogleOAuth`, 14 §6.3 says `AA`/`google-token-key`, and 12 §6.9 says
  `{bundleID}.gemini`/`GeminiApiKey`. Renaming after release orphans users' keys.


---

## Addendum: Consolidated macOS keyboard-shortcut & menu registry (resolve cross-spec conflicts)

> **Authority.** This addendum is §6.5.1 of this spec. The shell owns the menu bar and the global keys, so it
> is the one place where shortcuts are decided. **This registry supersedes every per-spec shortcut and
> menu-placement suggestion in specs 01–14**, including §6.2 (toolbar keys), §6.4 and §6.5 of this spec. Where any
> spec text disagrees with this registry, the registry wins. The per-spec sections are **not** edited in place; §6.5.1.8
> lists every superseded proposal. What a command *does* (its algorithm, dialogs, texts, persistence) stays owned by
> the spec named in its row. The registry decides only: **which key**, **which menu and title**, **when it is
> enabled**, and **who wins when a rich-text editor or other text field has focus**.
>
> **Sources re-read for this addendum.** `AA/MainWindow.xaml` (InputBindings/CommandBindings :7-20, all menus
> :21-100, header buttons :116-127, shortcut strip :128-147); `AA/MainWindow.xaml.cs` (`Window_PreviewKeyDown`
> :1425-1452, `IsTextInputFocused` :1455-1459, `UndoDelete` :1461-1472); `AA/Views/ContainerEditor.xaml` (toolbar
> tooltips :15-50); `AA/Views/ContainerEditor.xaml.cs` (context menu :120-150, `Rtb_PreviewKeyDown` :1054-1113,
> `IsModifyingKey` :1115-1125); `AA/Views/QuickSwitcherWindow.xaml(.cs)` (:81-99); `SearchWindow.xaml.cs` (:39-41,
> :113); `LoginWindow.xaml.cs` (:21-23); `HierarchyPage.xaml.cs` (:654-712); `SirePage.xaml.cs` (:40-67, :350); every
> `IsDefault`/`IsCancel` button in `AA/Views/*.xaml`; every user-visible string that names a key (grep of `Ctrl+`,
> `Enter`, `Esc`, `Tab`); specs 01–14 at the locations listed in §6.5.1.8; `PROGRESS.md` (lines 97, 106, 175,
> 759-760, 800-803, 825-828, 929); Apple HIG "Keyboard shortcuts" standard list, and the macOS default system and
> Services shortcuts.

### 6.5.1 Authoritative shortcut & menu registry

#### 6.5.1.0 Notation

* **IDs.** This addendum uses the reserved range **SHELL-500…SHELL-699**. Features are SHELL-500…526 and registry rows
  are SHELL-530…695. The range is kept clear of section 2 (SHELL-001…162) and of the build/distribution addendum
  (SHELL-170…207). Gaps are deliberate. IDs `T-KB-nn` (tests), `X-n` (extra conflicts) and `Q-KB-n` (open
  questions) are local to this addendum.

* **Glyph order** follows Apple convention: ⌃ Control, ⌥ Option, ⇧ Shift, ⌘ Command. So we write `⌥⇧⌘V`, `⌃⌘↑`
  and `⇧⌘F`. Arrows are `← → ↑ ↓`. `⌫` is Delete (backspace), `⌦` is forward delete (fn-⌫), `↩` is Return, `⎋` is Esc,
  `⇥` is Tab. `⌘−` means the key equivalent `-`, and `⌘+` means `+` (typed as ⇧⌘= on US layouts, SHELL-509).
* **F2** is the key equivalent `NSF2FunctionKey`. On Mac laptops it is typed as fn-F2 unless "Use F1, F2, etc. keys as
  standard function keys" is on.
* **Scope codes** used in the tables:
  * `APP`: works from any AA window, main phase only, and never while the key window is a sheet or modal (SHELL-505).
  * `MAIN`: only when the key window is the main window.
  * `SECT(x)`: `MAIN` and the active section is x.
  * `LIST(role)`: a list or table that publishes that role (§6.5.1.10) has keyboard focus.
  * `RICH`: an AA rich-text view is first responder. These are the container editor wherever it is hosted, the SIRE
    question body, and the read-only viewer.
  * `TEXT`: any text input is first responder (`NSText`: every NSTextView and every field editor, including secure
    fields).
* **Editor-focus column** (what happens when a rich-text editor or text field has focus):
  * `CMD`: the command runs. It has no text meaning. This is WPF's window KeyBinding behaviour.
  * `TXT`: the menu item is disabled, so the keystroke reaches the text system with its standard Mac meaning.
  * `EDITOR`: the command acts on the editor.
  * `ROUTE`: the command does different things by context (SHELL-512).

#### 6.5.1.1 Features

**SHELL-500 — One registry, one owner per key.** Every menu-bar key equivalent in AA is listed in §6.5.1.3, and
exactly one menu item owns it. Two items must never share the same `(key, modifiers)` pair. This is checked after
US-layout shift normalisation: `{`≡⇧`[`, `}`≡⇧`]`, `|`≡⇧`\`, `+`≡⇧`=`, `:`≡⇧`;`, `?`≡⇧`/`, `<`≡⇧`,`, `>`≡⇧`.`,
`_`≡⇧`-`, `&`≡⇧`7`, `(`≡⇧`9`. The same pair also must not appear as an in-view `.keyboardShortcut` in the main
window or on any toolbar button (SHELL-510). Context-dependent behaviour is always achieved by **routing one item**
(SHELL-512), never by putting the same key on two items. AppKit resolves duplicate key equivalents by menu search
order, and that is non-deterministic across SwiftUI menu rebuilds. Hidden aliases (SHELL-509) count as owners.
In-sheet shortcuts may reuse a menu key only where §6.5.1.5 says so. The Trash sheet's ⌘⌫ is one example: a sheet is
its own key window, so its view-level key equivalents are matched first.

**SHELL-501 — Reserved keys.** Never assign any of the following:
* **System keys:** ⌘Space, ⌥⌘Space, ⌃Space and ⌃⌥Space (input sources), ⌘⇥, ⌘\`, ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌥⌘M, ⌘,,
  ⌃⌘F/🌐F, ⌃⌘Q, ⌃⌘Space/🌐E, ⇧⌘3/4/5/6, ⇧⌘/ (Help search), ⌥⌘D, ⌥⌘⎋, ⌃↑/⌃↓/⌃←/⌃→, ⌃F1–⌃F8 (Full
  Keyboard Access), 🌐-arrow tiling.
* **Accessibility keys:** ⌥⌘8, ⌥⌘=, ⌥⌘-, ⌥⌘\\ and ⌃⌥⌘8 (Zoom and Invert, live when enabled), ⌘F5 and every ⌃⌥
  chord (VoiceOver).
* **Default Services keys:** ⇧⌘L "Search With Google", ⇧⌘Y "Make New Sticky Note", ⇧⌘A and ⇧⌘M (Terminal man-page
  services). App menus take precedence over Services, so ⇧⌘M may still be used for a list-only command (SHELL-583).
* **HIG standard meanings AA keeps:** ⌘W, ⌘S, ⇧⌘S, ⌘P, ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V, ⌥⇧⌘V, ⌘A, ⌘F, ⌘G, ⇧⌘G, ⌘E,
  ⌘J, ⌘:, ⌘;, ⌘T, ⌘B, ⌘I, ⌘U, ⌘+, ⌘−, ⇧⌘C, ⌘{, ⌘|, ⌘}, ⌃⌘S (sidebar), ⌥⌘T (toolbar), ⌃⌘I (inspector).
* **Reserved but unused:** ⌘D (the "Don't …" button in alerts), ⌥⌘C and ⌥⌘V (Copy and Paste Style), ⌃⌘C and ⌃⌘V
  (Copy and Paste Ruler), ⌥⌘I (Show Inspector in some apps).

There are **three deliberate repurposings**, all for Windows parity. Each maps a WPF `ApplicationCommands` binding.
AA has no documents, so ⌘N and ⌘O have no competing "new document" or "open document" meaning.
* ⌘N = Quick Work Window (WPF `ApplicationCommands.New`, Ctrl+N).
* ⌘O = Quick Switcher (WPF `ApplicationCommands.Open`, Ctrl+O; Xcode "Open Quickly" precedent).
* ⌘R = Due-dates window (WPF `NavigationCommands.Refresh`, Ctrl+R; ⌘R is not an HIG-standard key).

**SHELL-502 — Text-first precedence.** Some commands use a key that already means something in the macOS text
system. These `TXT`-class items are **disabled** whenever any text input is first responder, so the keystroke
reaches the text view with its normal meaning. The test is `NSApp.keyWindow?.firstResponder is NSText`, which is the
exact analogue of WPF `IsTextInputFocused()` (`TextBoxBase ∨ PasswordBox`, `MainWindow.xaml.cs:1455`).

| Command | Key | What the key does in text instead |
|---|---|---|
| Delete family | ⌘⌫ | delete to line start |
| Rename | F2 | nothing |
| Planner Previous / Next | ⌘← / ⌘→ | move to line start / end |
| Move To… | ⇧⌘M | beep |
| Move Up / Move Down (except in an AA rich-text editor, where they are the editor's own command) | ⌃⌘↑/↓ | beep |
| Search Current List (when focus is in its own field it is a no-op) | ⌥⌘F | no-op |

As a safety net, if a `TXT`-class action is ever invoked while text is first responder (for example because
enablement is stale), it forwards the text meaning (§6.5.1.10 step F).

Every other global command is `CMD`-class and wins over text, exactly like the WPF window KeyBindings that the TextBox
did not consume: ⌘S, ⌘N, ⌘O, ⌘R, ⌘1…⌘9, ⇧⌘N, ⇧⌘F, ⌥⌘E, ⌘P, ⇧⌘T, ⌃⌘L, and all File, Tools and View items.

**SHELL-503 — Rich-text scope.** The following are enabled only when an AA rich-text view is first responder (`RICH`),
and only for the subset that view allows:
* the whole Format menu;
* Edit ▸ Find ▸ Find Next, Find Previous, Use Selection for Find and Jump to Selection;
* Spelling and Grammar, Substitutions, Transformations and Paste and Match Style.

The subsets are:
* **Container editor** (main pane, item windows, subtask and step editors, builder editors): everything.
* **SIRE question body:** Bold, Italic and Underline as typing attributes only, plus Find, Copy, Paste, Select All,
  Undo and Redo (12 §6.3). Everything that removes or replaces text is blocked by its insertion-only gate.
* **Read-only viewer:** Find, Copy and Select All only.

These rich-text views are the `AARichTextView` subclasses of spec 05.

**SHELL-504 — Window scope (Mac superset).** On Windows, the five KeyBindings plus Ctrl+1…9, F2 and Ctrl+Z exist on
the **main window only** (SHELL-048). In an item window, the Search window or a tool window they do nothing. On the
Mac, menu commands are app-wide (`APP`), so ⌘S, ⌘N, ⌘O, ⌘R, ⌘F, ⇧⌘F, ⌘1…⌘9, ⌥⌘E, ⌘P and ⌃⌘L work from any AA
window. ⌘1…⌘9 and ⌘O first bring the main window to the front. This is a MAC-ADAPT superset (§6.5).

These commands stay `MAIN`-only for parity or because they have no meaning elsewhere:
* Undo Move to Trash (SHELL-521);
* Rename (F2);
* New {Kind} (⇧⌘N);
* Planner Previous, Today and Next;
* the section commands' selection effect;
* Search Current List, which also works in windows that have their own filter field (SHELL-517).

**SHELL-505 — Modal suppression and quit deferral.** WPF disables a window's owner while a modal dialog is open. To
match, while the key window is an attached sheet, an app-modal panel, or the quick switcher, every `APP` and `MAIN`
command is disabled.

These stay enabled:
* Quit, Hide, Hide Others and Show All;
* the Edit, Find and Format items that act on a text field or editor *inside* the sheet;
* Help ▸ AA Keyboard Shortcuts.

⌘Q while a **decision sheet** is open is refused. `applicationShouldTerminate` returns `.terminateCancel`, the sheet
is ordered front, and `NSSound.beep()` plays. The decision sheets are the prompt, password, date, item-lock, picker,
diff, tab-colours, insert-saved-list, list-style, quick-card editor and crew editor sheets, and any `NSAlert`. This
is faithful: Windows cannot exit while a modal dialog is open.

A **close-type sheet** is different. For builders and Trash, closing means saving, so ⌘Q closes the sheet (which
flushes it) and then runs the SHELL-056 quit pipeline.

**SHELL-506 — Phase gating.** While the phase is not `.main` (splash, login), only these items are enabled:
* AA ▸ About AA, Hide AA, Hide Others and Show All;
* Quit AA, which is the same as the login `Exit` (SHELL-004);
* the standard Edit text items acting on the login fields. The secure field refuses Cut and Copy by itself.

Everything else is disabled (§6.1). ⌘W on the login window closes it, and closing the login window terminates the
app, which is the WPF behaviour (SHELL-004/005).

**SHELL-507 — Safe mode.** If the Windows command stays available in safe mode and shows a message, the Mac item
stays enabled and shows the same message:
* ⌘S shows D4 (SHELL-008).
* The Encrypt toggle shows D32.

If the Windows command is a silent no-op in safe mode, the Mac item is disabled. The only such command is Undo Move
to Trash (`UndoDelete`: `if (_repo == null || _safeMode) return;`). All other items are unchanged. Imports stay
enabled, as in SHELL-008.

**SHELL-508 — Titles, tooltips and stable identifiers.**

*Title rule.* A Mac title is the Windows title in Mac title case, with these changes:
* `...` becomes `…` (U+2026). A title gets `…` only when the command then asks for more input. A plain confirmation
  alert does not count, so there is no ellipsis for it.
* `PC` becomes `Mac`.
* Emoji prefixes (`🌙 ⌨ 🎨 🗑 📌`) are replaced by SF Symbol images.
* Access-key underscores and `(Ctrl+X)` suffixes are dropped, because the menu shows the key.

*Exceptions* (where the Windows wording contradicts Mac semantics):

| Windows title | Mac title | Reason |
|---|---|---|
| `Save _As...` | **Save a Copy As JSON…** | the active data file does not change (SHELL-061), and on the Mac "Save As" means switching to the new file |
| `E_xit` | **Quit AA** | Mac app-menu convention |
| `_About` | **About AA** | Mac app-menu convention |
| header `Search (Ctrl+F)` | **Find…** / **Search All Items…** | the Find family, SHELL-517 |

*Dynamic titles* are allowed only for Undo, Redo, the Delete family and New {Kind}. Every other title is static.
This keeps System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ App Shortcuts overrides working, because those
(`NSUserKeyEquivalents`) are keyed by title.

*Tooltips.* `NSMenuItem.toolTip` is the verbatim Windows tooltip, with the key substitutions of §6.5.1.9. Mac-only
items get the help texts given in their rows.

**SHELL-509 — Hidden aliases.** Only these four are allowed:

| Alias | Target |
|---|---|
| ⇧⌘O | Quick Switcher… |
| ⇧⌘V | Paste and Match Style (container editor only) |
| ⌘= | Bigger |
| ⌃⌘= | Superscript |

Each alias is an extra `NSMenuItem` in the same menu as its visible owner, with `isHidden = true` and
`allowsKeyEquivalentWhenHidden = true`, using the same action and validation. SwiftUI cannot declare hidden items,
so add them from the AppKit bridge (§6.5.1.13). If no bridge is available, fall back to an in-view shortcut on the
root of the window where the alias matters. It then works only in that window, which is acceptable.

**SHELL-510 — Toolbar buttons carry no key equivalents.** No toolbar item (main toolbar: Due, Search, Go to,
Reload, Save; and all section and crew/vessel toolbars) has a `.keyboardShortcut`. In-view key equivalents are
matched *before* the menu bar, so they would bypass the SHELL-502/205 enablement rules. Each toolbar button's
`.help` shows the key, for example `Save (⌘S)`. The toolbar **Search** button always runs Search All Items
(SHELL-585), exactly like the Windows header button.

**SHELL-511 — Keyboard layouts and numpad.**
* Declare every key with `KeyboardShortcut.Localization.automatic`, the default. On layouts where the character needs
  ⌥ (German, Nordic), this remaps `[ ] { } | + −`.
* ⌘1…⌘9 must work on AZERTY, where digits are shifted. Verify that ⌘7 and ⇧⌘7 stay distinct (T-KB-41).
* Numeric-keypad digits must also trigger ⌘1…⌘9, because Windows accepted NumPad1–9 (verify, T-KB-42).
* Unlike Windows, which accepts "Ctrl plus any other modifiers plus digit" (`Window_PreviewKeyDown` tests only the
  Ctrl bit), the Mac does **not** accept extra modifiers. ⇧⌘3/4/5 are system screenshots, and ⇧⌘7/⇧⌘9 are list
  commands.

**SHELL-512 — CommandRouter.** One `@MainActor @Observable` router computes `(enabled, title)` for every routed command
from the current context and performs it. The algorithm is in §6.5.1.10. Menus, the Keyboard Shortcuts window
(SHELL-523), toolbar help and the unit tests all read the same registry table (§6.5.1.11).

**SHELL-513 — ⌘W / close semantics (resolution 7).** File ▸ Close (⌘W) is the standard `performClose:` on the key
window. On the **main window**, it is the same as the red close button: it **quits AA through the SHELL-056
pipeline** (stop sync, dispose the tray, flush and close item windows, final save, conditional shared push, exit).
There is no confirmation, as on Windows.

⌘W on a **sheet** never reaches the main window. The rules are:
* A close-type sheet (builders, Trash, the editor sheets) closes, which saves.
* A decision sheet ignores ⌘W and beeps. Its Cancel button is on ⎋.
* Other windows follow the §6.5.1.5 table.

The borderless due-dates panel overrides `performClose(_:)` so that ⌘W closes it. ⌥⌘W (Close All, the standard
alternate) closes every window, the main window last, so it also quits. Rationale and rejected alternative: §6.5.1.7
(7).

**SHELL-514 — ⎋ / ⌘. cancel semantics (resolution 8).** ⎋ and ⌘. are the same action (`cancelOperation:`). Per window
they do exactly what §6.5.1.5 says:
* **Decision sheets and alerts:** cancel. This goes beyond Windows, which bound Esc only on `IsCancel` buttons, but
  specs 04/06/07/09/12/14 all recommend it.
* **Close-type sheets and utility windows that Windows closes on Esc:** close.
* **Quick switcher:** close.
* **Flash Sync:** stop flashing or scanning.
* **Main, item, Search, Quick-work, Activity-log, Unit-converter and Settings windows:** nothing.

Inside an **AA rich-text view**, ⎋ and ⌘. are **passed to the next responder** (override `cancelOperation(_:)` →
`nextResponder?.tryToPerform(...)`), so they cancel or close the surrounding sheet instead of opening NSTextView word
completion. WPF's RichTextBox had no Esc meaning. Completion stays available on ⌥⎋ and F5 (standard `complete:`
bindings).

**SHELL-515 — Return, ⌘↩ and Space.**
* **Return** triggers the default button of every dialog (`.keyboardShortcut(.defaultAction)`, §6.5.1.5).
* **Return in a list** performs the list's Windows double-click action (SwiftUI `contextMenu(primaryAction:)`), with
  one exception: in the **hierarchy sidebar**, Return is **Rename**, the same as F2 (Finder convention; 04 §6.2).
  There, double-click is Open in New Window (HIER-M03).
* **⌘↩** is the bulk primary action in two places: "Add all" in the builder bulk editors (06) and "Create folders"
  in the Folder builder (14).
* **Space** triggers Quick Look in file tables (the file bank and the viewer's file list, 04 HIER-M06, 05). It toggles
  Done in the work-orders table (optional, 10). It toggles focused checkboxes and switches natively.
* **⌘↓** opens the selected file in file tables (Finder "Open"). This replaces 05's "⌘O open"; see X-2.

**SHELL-516 — Delete family (resolution 4).**

*The ⌘⌫ item.* One File-menu item owns **⌘⌫** (Finder places "Move to Trash ⌘⌫" in File). Its title is the Windows
button caption of the focused list:
* **Move to Trash** for the hierarchy sidebar and the crew roster;
* **Delete Task** for the Board;
* **Remove** for the file bank and the relationships list;
* **Remove from Bucket** for bucket members;
* **Delete** otherwise.

It calls exactly that button's handler, **including its Windows confirmation dialog**. It is enabled only when a
`LIST` role with a non-empty selection has focus. With any text input focused it is disabled, so ⌘⌫ keeps its
text meaning (delete to line start, or delete the selection), and the standard Edit ▸ Delete (`delete:`, no key)
still deletes selected text.

*Plain ⌫ and ⌦.* On a focused list, these trigger the same handler through SwiftUI `.onDeleteCommand`, **but only for
roles whose Windows handler shows a confirmation**. File-bank Remove (CONT-088) has no confirmation and no undo, so
there ⌫ does nothing and ⌘⌫ is required.

*Trash.* File ▸ Trash (Restore Deleted Items)… has **no** shortcut. Inside the Trash sheet, Finder's semantics apply
(SHELL-675):
* ⌘⌫ = Put Back (`↩ Restore`);
* ⌥⌘⌫ = Delete Immediately… (`Delete permanently`, with confirmation);
* ⇧⌘⌫ = Empty Trash… (with confirmation).

**SHELL-517 — Find family (resolution 1).**

*Find… (⌘F)* is routed by context:
1. An AA rich-text view is first responder: open *that view's* find bar. This uses `NSTextFinder`
   `.showFindInterface`, with `usesFindBar = true` and incremental search. The bar's Replace control is available
   only in the editable container editor, and replacements pass the lock gate.
2. Otherwise, the key window is the Search window: focus its query field and select its text.
3. Otherwise: open a **new** Search window (SHELL-041). This is the Windows Ctrl+F, also when a plain text field has
   focus, as on Windows.

*Search All Items… (⇧⌘F)* always opens a new Search window, from anywhere, including inside a note.

*Search Current List (⌥⌘F)* focuses the nearest list filter field:
* In the main window, the field of the vessel panel that currently has focus (Work Orders or Ports), if there is one.
  Otherwise the active section's field (see the table below).
* In the Quick-work window, its filter. In the Activity-log window, its filter. In the Search window, its query field.

| Section | Field focused by ⌥⌘F |
|---|---|
| Equipment/Area, Tasks, Procedures, Vessels | sidebar `Search...` |
| Board | `Find` |
| Planner | `Search jobs...` |
| Relationship Map | Inspect filter |
| Crew | `Search name / rank / nationality / ID...` |
| SIRE | the question search |
| Saved Lists, Ports | their search field, if the owner spec has one |
| Calendar, Buckets | none: the item is disabled |

*Find Next (⌘G), Find Previous (⇧⌘G), Use Selection for Find (⌘E) and Jump to Selection (⌘J)* are `RICH` only.

**SHELL-518 — ⌘T and Today (resolution 2).** ⌘T is **Format ▸ Font ▸ Show Fonts**, for `RICH` (container editor)
only. It never means Today. The Planner's `◀` / `Today` / `▶` map to View ▸ **Previous** ⌘←, **Go to Today** ⇧⌘T and
**Next** ⌘→. These are enabled for `SECT(Planner)` when no text input is focused, and implement VIEW-081: ±1 day,
±7 days or ±1 month by mode, with Today resetting the anchor and keeping the mode.

**SHELL-519 — Text size (resolution 5).** Format ▸ Font ▸ **Bigger** ⌘+ (alias ⌘=) and **Smaller** ⌘− are routed:
1. The container editor is first responder: step the selection's font size. This is the WPF Ctrl+] / Ctrl+[ step;
   spec 05 owns the exact step.
2. Otherwise the key window is the main window, the active section is Calendar, and no text is focused: step
   `Ui.CalendarFontScale` by ±1.5, clamped to [11, 28], and `MarkDirty()`. This is exactly the A+/A− buttons
   (VIEW-017). At the bound, the item stays enabled and the value stays clamped, as with the button.
3. Otherwise: disabled.

⌘0 is **not bound**. There is no calendar reset on Windows, and 07 marked ⌘0 optional.

**SHELL-520 — Indent, outdent, reorder (resolution 6).**
* Format ▸ Lists ▸ **Indent** ⌘] and **Outdent** ⌘[ run the `→|` / `|←` toolbar path, including list normalisation
  (CONT-043). They replace WPF's built-in Ctrl+T / Ctrl+Shift+T, whose Mac key ⌘T is Show Fonts.
* Tab and ⇧Tab at the start of a list item stay in-editor keys (CONT-044).
* Edit ▸ **Move Up** ⌃⌘↑ and **Move Down** ⌃⌘↓ form one pair for the whole app. In `RICH` (the container editor) they
  run CONT-046, which moves the list item or block with its sub-items (WPF Ctrl+Alt+Up/Down). On a focused `LIST`
  that has ↑/↓ buttons on Windows, they run that list's nudge.
* Edit ▸ **Move To…** ⇧⌘M opens the list's `Move to...` or `Move to position...` picker.

**SHELL-521 — Undo / Redo routing.** Edit ▸ Undo ⌘Z and Redo ⇧⌘Z replace SwiftUI's `.undoRedo` group.

*Undo* resolves in this order:
1. A text input is first responder: use the responder's `undoManager`. The title is its `undoMenuItemTitle`
   ("Undo Typing" and so on). This is the WPF editor's or TextBox's own Ctrl+Z.
2. Otherwise, the key window is the main window with no sheet: **Undo Move to Trash**, which is SHELL-047
   `UndoDelete`. Take n = `PendingUndoCount()`:
   * n == 1: title `Undo Move to Trash`.
   * n > 1: title `Undo Move to Trash ({n} Items)`.
   * n == 0, safe mode, or no repository: title `Undo`, disabled.

   The status texts are `Restored {n} deleted items (⌘Z).` and `Restored the last deleted item (⌘Z).` It works across
   relaunches because it reads the persisted Trash.
3. Otherwise: the key window's own `undoManager`. This is normally empty, so the item is disabled.

*Redo* follows step 1 only. There is never a redo of a restore (Windows has none).

*Parity for `Nothing to undo.`* When ⌘Z reaches the main window's root responder as an unhandled keyDown (because the
item was disabled with an empty Trash), the root responder's `noResponder(for:)` override sets status
`Nothing to undo.` instead of beeping. This keeps the Windows message.

*Rejected:* 01's "register an undo action on the window `UndoManager`" and 12's optional "Add to AA" undo group. Both
would compete with rule 2 and would not survive relaunch (X-9, X-10).

**SHELL-522 — Section switching.**
* View ▸ {13 section items} appear in the **current display order** (`UiState.TabOrder`). Positions 1–9 carry ⌘1…⌘9,
  so the keys follow reordering, as on Windows ("Nth tab in display order"). Positions 10–13 have no key.
* Choosing one selects the section, brings the main window to the front, and sets `SelectedMainTabIndex` in memory
  with no `MarkDirty`, as in SHELL-027.
* The selected section's item shows a checkmark. The Crew item may show `NSMenuItem.badge` with the expiry count.
* WPF TabControl's built-in Ctrl+Tab / Ctrl+Shift+Tab (cycle tabs) maps to ↑/↓ in the focused section sidebar, plus
  View ▸ **Previous Section** / **Next Section**, which have no key and wrap around like WPF.
* ⌃⇥ is **not** bound: macOS uses it to move focus out of text views and tables. ⇧⌘[ / ⇧⌘] cannot be used either,
  because they are the same keystrokes as ⌘{ / ⌘} (align) on US layouts (X-1, X-18).

**SHELL-523 — Help ▸ AA Keyboard Shortcuts.** This is a Mac addition. It opens a single-instance window (`Window(id:
"shortcuts")`, ⌘W closes it) that lists this registry grouped by menu. It has a search field and the columns
**Command**, **Mac**, **Windows** (the old gesture, which helps people who switch) and **Menu**. It is generated from
the registry table, so it can never drift.

**SHELL-524 — Locked-selection key swallowing is not replicated.** In WPF, while the selection overlaps locked text,
`Rtb_PreviewKeyDown` marks every "modifying" key handled. That covers every key except arrows, Home/End, PgUp/PgDn,
Tab, modifier keys, CapsLock, Esc and Ctrl+C/A/F/Insert (`ContainerEditor.xaml.cs:1115-1125`). A handled
PreviewKeyDown also stops WPF's `CommandManager` from running window KeyBindings. So on Windows, Ctrl+S, Ctrl+N,
Ctrl+O and Ctrl+1…9 show the lock hint instead of acting (05 K-5, D-4).

On the Mac, menu key equivalents are matched before the text view, so these always work. Only text *mutations* are
blocked, by the lock gate in `shouldChangeText(in:replacementString:)`. This is a documented improvement with no
data impact.

**SHELL-525 — Placement of menu items proposed by other specs.** The final placements are in the tree (§6.5.1.6) and
in the resolutions (§6.5.1.7):
* Format menu (05): a top-level **Format** menu with the exact contents of §6.5.1.3.
* "Find in Note…" (05) becomes Edit ▸ Find ▸ **Find…** ⌘F, routed.
* "Search All Items…" (08) becomes Edit ▸ Find ▸ **Search All Items…** ⇧⌘F.
* Vessel / Import (10) becomes Tools ▸ **Vessel** ▸ submenu.
* "Export as PDF…" (11) becomes File ▸ **Export as PDF…** ⌥⌘E.
* "Print…" (11) becomes File ▸ **Print…** ⌘P (optional feature).
* SIRE commands (12): no menu in v1.
* Due Dates, Quick Work and Go to Item (08) stay in **Tools** only.

**SHELL-526 — Standard window commands.**
* Include `SidebarCommands()` (View ▸ Show/Hide Sidebar ⌃⌘S).
* Include `ToolbarCommands()` (View ▸ Hide/Show Toolbar ⌥⌘T and Customize Toolbar…). The main toolbar is declared
  `.toolbar(id:)` so it is customisable. While the toolbar is hidden, the shared-save indicator (SHELL-023) moves
  into the bottom bar, so it is still visible while in trouble.
* Include `InspectorCommands()` (⌃⌘I) only if some view uses `.inspector`.
* Set `NSWindow.allowsAutomaticWindowTabbing = false` at launch. This keeps "Show Tab Bar", "Show All Tabs ⇧⌘\\"
  and window-tab ⌃⇥ out of the menus.
* Replace `.newItem` with an empty `CommandGroup(replacing: .newItem) {}` before adding File ▸ New {Kind}. Otherwise
  SwiftUI adds "File ▸ New … Window ⌘N" for the `WindowGroup` scenes, which would collide with ⌘N (X-11).
* Put `.commandsRemoved()` on `Window` scenes that are opened by Tools items (Quick work, Due dates, Folder builder,
  Date calculator, Keyboard Shortcuts), so the Window menu doesn't list duplicate openers. The Window menu still lists
  the windows that are *open*.
* Exclude the splash, the login, the due-dates panel and the quick switcher from the Window menu
  (`isExcludedFromWindowsMenu`; 08:1255).

#### 6.5.1.2 Key-event precedence model

This is the order in which AppKit delivers a key-down. The whole registry depends on it:

```
1. NSApplication.sendEvent(keyDown with ⌘ or a function key)
2.   keyWindow.performKeyEquivalent(event)
       → walks the key window's view hierarchy: SwiftUI in-view .keyboardShortcut buttons,
         default (↩) and cancel (⎋) buttons of THAT window (a sheet is its own key window)
3.   if unhandled: NSApp.mainMenu.performKeyEquivalent(event)
       → finds the item whose key equivalent matches, validates it (router / validateMenuItem);
         an ENABLED item consumes the event and sends its action;
         a DISABLED item does not consume it (verify: T-KB-01) → continue
4.   keyWindow.sendEvent → keyDown(with:) to the first responder
       → NSTextView/field editor: interpretKeyEvents → StandardKeyBinding
         (⌘⌫ deleteToBeginningOfLine:, ⌘← moveToBeginningOfLine:, ⌘→ moveToEndOfLine:,
          ⌥⌫ deleteWordBackward:, ⎋ cancelOperation: → complete:, ⌃⇥ focus escape …)
5.   unhandled keyDown travels the responder chain: views → window root responder → window → delegate
6.   noResponder(for:) → NSBeep (the main window's root responder overrides this for ⌘Z → "Nothing to undo.")
```

The consequences are these rules:
* **R-a:** Keys that must reach text are protected only by **disabling** their menu item (step 3). That is SHELL-502.
* **R-b:** In-view shortcuts beat the menu (step 2). So the main window must not declare in-view shortcuts that copy
  menu keys (SHELL-510). Sheets may declare in-view shortcuts, because the sheet is the key window.
* **R-c:** The WPF editor filtered keys in `PreviewKeyDown` *before* the window bindings. The Mac text view sees keys
  *after* the menu. So a WPF editor-local gesture that shared a key with a window binding (Ctrl+R) now resolves to the
  menu command (X-16, Q-6 confirmed).

#### 6.5.1.3 The registry: menu-bar commands

Columns:
* **Key** is the Mac key equivalent.
* **Windows** is the old gesture, or the menu item and button it replaces. `—` means a Mac addition, and the proposing
  spec is named.
* **Enabled when** is in addition to SHELL-505 (modal) and SHELL-506 (phase), which apply to every `APP`/`MAIN` row.
* **Editor focus** uses the codes of §6.5.1.0.
* **Owner** is the spec that owns the behaviour.

##### AA (application) menu

| ID | Mac title | Key | Windows | Enabled when | Editor focus | Owner |
|---|---|---|---|---|---|---|
| SHELL-530 | About AA | — | top-level `_About` (SHELL-115) | always (also during login) | CMD | 03 |
| SHELL-531 | Settings… | ⌘, | — (Mac addition, §6.4) | `APP` | CMD | 03, 01, 12 |
| SHELL-532 | Services ▸ | — | — | system | system | — |
| SHELL-533 | Hide AA / Hide Others / Show All | ⌘H / ⌥⌘H / — | — | always | CMD | system |
| SHELL-534 | Quit AA | ⌘Q | `E_xit`; ✕ or Alt+F4 on main (SHELL-056/082) | always. At login it is the same as `Exit`. Deferred by a decision sheet (SHELL-505). | CMD | 03 |

##### File menu

| ID | Mac title | Key | Windows | Enabled when | Editor focus | Owner |
|---|---|---|---|---|---|---|
| SHELL-540 | New {Kind}: `New Equipment/Area`, `New Task`, `New Procedure`, `New Vessel`; Board `New Task…`; Buckets `New Bucket…`; Saved Lists `New List…`; disabled title `New Item` | ⇧⌘N | `+ New` buttons (HIER-021, VIEW-053, VIEW-147, 06 New List); no key. **Not** WPF's editor Ctrl+Shift+N (numbering → SHELL-615) | `SECT` ∈ {Equipment, Tasks, Procedures, Vessels, Board, Buckets, Saved Lists}. Enabled in safe mode (Windows allows in-memory edits). | CMD (flush all editors first) | 04 (HIER-M04 focuses Name), 07, 06 |
| SHELL-541 | Open in New Window | — | sidebar context `Open in new window` (HIER-110) | `SECT(hierarchy)`, ≥1 item selected. A gated item shows the HIER-057 message, as on Windows. | CMD | 04 |
| SHELL-542 | Rename | F2 | F2 (SHELL-046; only when no text input focused, hierarchy tab) | `SECT(hierarchy)`, an item selected, no `TEXT` | TXT | 04 HIER-025/122 |
| SHELL-543 | Quick Look | ⌘Y (Space in-view, SHELL-669) | — (Mac addition, 04 HIER-M06, 05 §6.9) | `LIST(fileBank \| viewerFiles)` with a selection that has a local file | TXT | 05 |
| SHELL-544 | Delete family: `Move to Trash` / `Delete Task` / `Remove` / `Remove from Bucket` / `Delete`; idle title `Delete` | ⌘⌫ (+ ⌫/⌦ in-view, SHELL-670) | the focused list's Delete/Remove button (HIER-022, crew Delete, VIEW-052, BUILD-014, CONT-088, …); no key on Windows | a `LIST` role with a delete handler and a non-empty selection (§6.5.1.10 table) | TXT | per role |
| SHELL-545 | Close | ⌘W | ✕ / Alt+F4 (no Ctrl+W on Windows — W-12) | any key window with a close action (§6.5.1.5) | CMD | SHELL-513 |
| SHELL-546 | Save | ⌘S | Ctrl+S, `_Save`, header `Save (Ctrl+S)` (SHELL-040/050) | `APP`. In safe mode it shows D4. | CMD (flushes editors) | 03 |
| SHELL-547 | Save a Copy As JSON… | ⇧⌘S | `Save _As...` (no key) (SHELL-061) | `APP` | CMD | 03, 01 |
| SHELL-548 | Reload from Disk | — | `_Reload from disk`, header `Load` (SHELL-062) | `APP` | CMD | 03 |
| SHELL-549 | Import from File… | — | `_Import from file...` (SHELL-063) | `APP` | CMD | 03, 01 |
| SHELL-550 | Trash (Restore Deleted Items)… | — (01's ⌥⌘⌫ rejected) | `_Trash (restore deleted items)...` (SHELL-064) | `APP` | CMD | 02 REPO-078 |
| SHELL-551 | Encrypt Local Data File (This Mac) ✓ | — | `Encr_ypt local data file (this PC)` (SHELL-065) | `APP`. In safe mode it shows D32. | CMD | 03, 01 |
| SHELL-552 | Shared Save ▸ Set Shared Save File… | — | `Set s_hared save file...` (SHELL-066) | `APP` | CMD | 03 |
| SHELL-553 | Shared Save ▸ Stop Shared Save File | — | `Stop shared save file` (SHELL-067) | `APP` | CMD | 03 |
| SHELL-554 | Shared Save ▸ Check Shared Save Now | — | — (optional Mac addition, 01 §6.10). Runs `CheckSharedFileForUpdate()`. | `APP`, a shared file is set | CMD | 03 SHELL-125 |
| SHELL-555 | Set App Identity… | — | `Set app _identity...` (SHELL-068); also a Settings field | `APP` | CMD | 03 |
| SHELL-556 | Open Data Folder | — | `Open data _folder` (SHELL-069) | `APP` | CMD | 03 |
| SHELL-557 | Export Data Folder (ZIP)… | — | `_Export data folder (ZIP)...` (SHELL-070) | `APP` | CMD | 03, 01 |
| SHELL-558 | Import Data Folder (ZIP)… | — | `I_mport data folder (ZIP)...` (SHELL-071) | `APP` | CMD | 03, 01 |
| SHELL-559 | Export Text Only (No Attachments) ✓ | — | `Export _text only (no attachments)` (SHELL-072) | `APP` | CMD | 03 |
| SHELL-560 | Google Drive ▸ Save a Copy to Google Drive (Synced Folder) | — | SHELL-073 | `APP` | CMD | 14 |
| SHELL-561 | Google Drive ▸ Set Google Drive Folder… | — | SHELL-074 | `APP` | CMD | 14 |
| SHELL-562 | Google Drive ▸ Upload Backup to Google Drive (OAuth)… | — | SHELL-075 | `APP`, and no upload/load/check in flight (14 §6.5 addition) | CMD | 14 |
| SHELL-563 | Google Drive ▸ Load Backup from Google Drive (OAuth)… | — | SHELL-076 | same as SHELL-562 | CMD | 14 |
| SHELL-564 | Google Drive ▸ Set Google OAuth Client (client_secret.json)… | — | SHELL-077 | `APP` | CMD | 14 |
| SHELL-565 | Google Drive ▸ Sign Out of Google | — | SHELL-078 | `APP` | CMD | 14 |
| SHELL-566 | Google Drive ▸ Sync to Google Drive on Save ✓ | — | SHELL-079 | `APP` | CMD | 14 |
| SHELL-567 | Google Drive ▸ Check Google Drive for Newer Save | — | SHELL-080 | `APP`, and no check in flight | CMD | 14 |
| SHELL-568 | Flash Sync with iPhone (QR)… | — (13's optional ⌥⌘Y not adopted) | `Flash S_ync with iPhone (QR)...` (SHELL-081) | `APP` | CMD (flush) | 13 |
| SHELL-569 | Export as PDF… | ⌥⌘E | header button `Export PDF...` (PDF-001); no key | target item = the key item window's item, or (`MAIN`, hierarchy section) the primary selected item that is not detached. Disabled when gated (the Windows button is hidden). PDF-002 re-checks. | CMD (flush, PDF-003) | 11 |
| SHELL-570 | Print… | ⌘P | — (optional Mac addition, 11 §6.2) | same as SHELL-569. If Print is not shipped, omit the item and keep ⌘P unassigned (never an alias). | CMD (uses a custom action, not `print:`, so a focused NSTextView cannot print only the note) | 11 |

##### Edit menu

| ID | Mac title | Key | Windows | Enabled when | Editor focus | Owner |
|---|---|---|---|---|---|---|
| SHELL-575 | Undo {…} (dynamic, SHELL-521) | ⌘Z | Ctrl+Z (editor/TextBox own undo; else main-window undo-delete); editor toolbar `↶ Undo (Ctrl+Z)` | SHELL-521 | ROUTE | 03, 02, 05 |
| SHELL-576 | Redo {…} | ⇧⌘Z (05's ⌘Y alias rejected — X-3) | Ctrl+Y (text); editor `↷ Redo (Ctrl+Y)` | `TEXT` with `canRedo` | EDITOR | 05 |
| SHELL-577 | Cut / Copy / Paste | ⌘X / ⌘C / ⌘V | Ctrl+X/C/V (+ Shift+Del, Ctrl+Ins, Shift+Ins); editor context menu; file-bank buttons (CONT-087) | standard responder validation: text, and the file bank via `.onCutCommand/.onCopyCommand/.onPasteCommand` (05 §6.9) | EDITOR | 05, 12 (SIRE: no cut; paste inserts) |
| SHELL-578 | Paste and Match Style | ⌥⇧⌘V (+ hidden ⇧⌘V) | Ctrl+Shift+V / context `Paste text only` (CONT-034) | `RICH(container)`, clipboard has text. The editor overrides `pasteAsPlainText(_:)` to run CONT-034 (lock-gated, one undo unit). | EDITOR | 05 |
| SHELL-579 | Delete | — (standard `delete:`) | Del on a text selection | text with a selection; also lists with `.onDeleteCommand` | EDITOR | — |
| SHELL-580 | Select All | ⌘A | Ctrl+A (text; extended-selection lists HIER-016) | standard | EDITOR | — |
| SHELL-581 | Move Up | ⌃⌘↑ | editor Ctrl+Alt+Up / `⤒` (CONT-046); list `↑` buttons (BUILD, saved lists, crew-table columns, quick-work children) | `RICH(container)`, or a `LIST` with move support whose selection can move up. Disabled for Saved Lists while Sort A–Z is on. | ROUTE (editor: CONT-046) | 05, 06, 08, 09 |
| SHELL-582 | Move Down | ⌃⌘↓ | editor Ctrl+Alt+Down / `⤓`; list `↓` buttons | same as SHELL-581 | ROUTE | same |
| SHELL-583 | Move To… | ⇧⌘M | `Move to...` / `Move to position...` buttons (BUILD-013, subtask builder, BUILD-087) | a `LIST` with a move-to picker and ≥1 selected. Disabled while Sort A–Z is on (saved lists). | TXT | 06 |
| SHELL-584 | Find ▸ Find… | ⌘F | Ctrl+F (global Search window) | always in `APP`, routed (SHELL-517) | ROUTE (rich text: its find bar) | 08 D, 02 REPO-100, 05 |
| SHELL-585 | Find ▸ Search All Items… | ⇧⌘F | Ctrl+F / header `Search (Ctrl+F)` | `APP` | CMD | 08 D, 02 REPO-100 |
| SHELL-586 | Find ▸ Search Current List | ⌥⌘F | — (Mac addition, 10 §6.8, 12 §6.3) | there is a target field (SHELL-517) and the focus is not already in it | TXT | per section |
| SHELL-587 | Find ▸ Find Next | ⌘G | — | `RICH` | EDITOR | 05 |
| SHELL-588 | Find ▸ Find Previous | ⇧⌘G | — | `RICH` | EDITOR | 05 |
| SHELL-589 | Find ▸ Use Selection for Find | ⌘E | — | `RICH` with a selection | EDITOR | 05 |
| SHELL-590 | Find ▸ Jump to Selection | ⌘J | — | `RICH` | EDITOR | 05 |
| SHELL-591 | Spelling and Grammar ▸ (Show Spelling and Grammar ⌘:, Check Document Now ⌘;, Check Spelling While Typing ✓, Check Grammar With Spelling, Correct Spelling Automatically) | ⌘: / ⌘; | editor spell-check context menu (CONT-033) | `RICH(container)`. Defaults per 05 §6.2: continuous spelling on, grammar off, autocorrect off. | EDITOR | 05 |
| SHELL-592 | Substitutions ▸ / Transformations ▸ / Speech ▸ | — | — | `RICH(container)`. Substitutions default off. Transformations pass the lock gate. | EDITOR | 05 |
| SHELL-593 | System-inserted: Writing Tools, AutoFill, Start Dictation…, Emoji & Symbols | 🌐E / ⌃⌘Space | — | system. Writing Tools: `writingToolsBehavior = .none` on the SIRE body (insertion-only). The container editor keeps the default and mutations pass the lock gate. | EDITOR | 05, 12 |

##### Format menu

This menu is new (05 §6.3). Build it **explicitly**, not with `TextFormattingCommands()`. That built-in menu adds Show
Ruler, Copy/Paste Ruler, Copy/Paste Style, Kern, Ligatures, Writing Direction and Raise/Lower. The XAML converter
cannot round-trip those, so edits made with them would silently vanish on save. Every item is `RICH` and
editor-validated. The SIRE body enables only SHELL-601/302/303 (typing attributes). The viewer enables none.

| ID | Mac title | Key | Windows | Owner |
|---|---|---|---|---|
| SHELL-600 | Font ▸ Show Fonts | ⌘T | font-family combo (CONT-020); no key | 05 |
| SHELL-601 | Font ▸ Bold | ⌘B | Ctrl+B, `B` `Bold (Ctrl+B)` (CONT-023) | 05, 12 |
| SHELL-602 | Font ▸ Italic | ⌘I | Ctrl+I | 05, 12 |
| SHELL-603 | Font ▸ Underline | ⌘U | Ctrl+U | 05, 12 |
| SHELL-604 | Font ▸ Strikethrough | ⇧⌘X | `S` `Strikethrough` (CONT-024; no key). Windows replace-semantics owned by 05. | 05 |
| SHELL-605 | Font ▸ Bigger | ⌘+ (hidden ⌘=) | WPF built-in Ctrl+] (editor); Calendar `A+` (VIEW-017) — routed, SHELL-519 | 05, 07 |
| SHELL-606 | Font ▸ Smaller | ⌘− | WPF built-in Ctrl+[ ; Calendar `A-` — routed | 05, 07 |
| SHELL-607 | Font ▸ Baseline ▸ Use Default / Superscript / Subscript | — / ⌃⌘+ (hidden ⌃⌘=) / ⌃⌘− | WPF built-ins Ctrl+Shift+= / Ctrl+= (write `Typography.Variants`, CONT-030) | 05 |
| SHELL-608 | Font ▸ Show Colors | ⇧⌘C | `A▾` other colour (CONT-025) | 05 |
| SHELL-609 | Font ▸ Highlight ▸ {swatches…, No Highlight, Other…} | — | `HL` (CONT-026) | 05 |
| SHELL-610 | Text ▸ Align Left | ⌘{ | Ctrl+L, `⯇` (CONT-027) | 05 |
| SHELL-611 | Text ▸ Center | ⌘\| | Ctrl+E, `≡` | 05 |
| SHELL-612 | Text ▸ Justify | — | Ctrl+J, `☰` | 05 |
| SHELL-613 | Text ▸ Align Right | ⌘} | Ctrl+R **in the editor**, `⯈` (X-16) | 05 |
| SHELL-614 | Lists ▸ Bulleted List | ⇧⌘7 | Ctrl+Shift+L, `•` `Bullets` (CONT-040) | 05 |
| SHELL-615 | Lists ▸ Numbered List | ⇧⌘9 | Ctrl+Shift+N, `1.` `Numbered` (CONT-041) | 05 |
| SHELL-616 | Lists ▸ Indent | ⌘] | Ctrl+T, `→\|` (CONT-043) | 05 |
| SHELL-617 | Lists ▸ Outdent | ⌘[ | Ctrl+Shift+T, `\|←` | 05 |
| SHELL-618 | Insert ▸ Link… | ⌘K | `🔗` `Insert hyperlink` (CONT-031) | 05 |
| SHELL-619 | Insert ▸ Table… | — (05's ⌥⌘T rejected — X-4) | `▦` (CONT-032) | 05 |
| SHELL-620 | Insert ▸ Saved List… | ⌥⌘L | `≔` (CONT-047/048) | 05 |
| SHELL-621 | Clear Formatting | — | `Clr` (CONT-028). WPF built-in Ctrl+Space ResetFormat is not mapped (SHELL-687). | 05 |
| SHELL-622 | Lock Highlighted Text… | — | `🔒` (CONT-060) | 05 |
| SHELL-623 | Unlock Highlighted Text… | — | `🔓` (CONT-061) | 05 |

##### View menu

| ID | Mac title | Key | Windows | Enabled when | Editor focus | Owner |
|---|---|---|---|---|---|---|
| SHELL-630 | {13 section items in display order}, e.g. `Equipment/Area`, …, `SIRE 2.0`; SF Symbols per §6.2 | ⌘1…⌘9 on positions 1–9 | Ctrl+1…9 / NumPad1–9 (SHELL-045) | `APP` (brings main to the front) | CMD (works while typing, as on Windows) | 03 |
| SHELL-631 | Previous Section / Next Section | — | WPF TabControl Ctrl+Shift+Tab / Ctrl+Tab | `APP`. Wraps around. | CMD | 03 |
| SHELL-632 | Previous | ⌘← | Planner `◀` (VIEW-081) | `SECT(Planner)`, no `TEXT` | TXT | 07 |
| SHELL-633 | Go to Today | ⇧⌘T | Planner `Today` | `SECT(Planner)` | CMD | 07 |
| SHELL-634 | Next | ⌘→ | Planner `▶` | `SECT(Planner)`, no `TEXT` | TXT | 07 |
| SHELL-635 | Show Sidebar / Hide Sidebar | ⌃⌘S | — (standard) | main window | CMD | — |
| SHELL-636 | Hide Toolbar / Show Toolbar; Customize Toolbar… | ⌥⌘T / — | — (standard) | main window | CMD | SHELL-526 |
| SHELL-637 | Shortcut Bar ✓ | — | `⌨ _Shortcut bar` (SHELL-111) | `APP` | CMD | 03 |
| SHELL-638 | Dark Mode ✓ | — | `🌙 _Dark mode` (SHELL-110) | `APP` | CMD | 03 |
| SHELL-639 | Customize Tab Colors… | — | `🎨 _Customize tab colors...` (SHELL-112) | `APP` | CMD | 03 |
| SHELL-640 | Enter Full Screen / Exit Full Screen | ⌃⌘F / 🌐F | — | system | CMD | — |

##### Tools menu (Windows order kept)

| ID | Mac title | Key | Windows | Enabled when | Editor focus | Owner |
|---|---|---|---|---|---|---|
| SHELL-645 | Folder Builder… | — | `_Folder builder...` (SHELL-090) | `APP` | CMD | 14 |
| SHELL-646 | Date Calculator… | — | `Date _calculator...` (SHELL-091) | `APP` | CMD | 14 |
| SHELL-647 | Floating Due-Dates Window | ⌘R | Ctrl+R (main; in the editor it right-aligned), `Floating _due-dates window`, header `📌 Due` (SHELL-044/092) | `APP`. If already open: activate and refresh. | **CMD** (X-16) | 08 A |
| SHELL-648 | Quick Work Window | ⌘N | Ctrl+N, `Quick _work window (Ctrl+N)` (SHELL-042/093) | `APP` | CMD | 08 B |
| SHELL-649 | Quick Switcher… | ⌘O (+ hidden ⇧⌘O) | Ctrl+O, `Quick s_witcher (Ctrl+O)`, header `Go to (Ctrl+O)` (SHELL-043/094) | `APP`, a repository exists | CMD | 08 C |
| SHELL-650 | Activity Log… | — | `_Activity log...` (SHELL-095) | `APP` | CMD | 08 E |
| SHELL-651 | Unit Converter… | — | `U_nit converter...` (SHELL-096) | `APP` | CMD | 14 |
| SHELL-652 | Import COMPAS Crew (.xlsx)… | — (09's ⇧⌘I rejected) | `Import COMPAS _crew (.xlsx)...` (SHELL-097) | `APP` (selects Crew first) | CMD | 09 |
| SHELL-653 | Check Crew Contract Expiries | — | SHELL-098 | `APP` | CMD | 09 |
| SHELL-654 | Vessel ▸ Import Shippalm Work Orders (.xlsx)…, Export Work Orders (.xlsx)…, —, Import Ports of Call (.xlsx)…, Export Ports of Call (.xlsx)…, —, New Quick Card… | — | the vessel panels' buttons (VESSEL-101, export, VESSEL-2xx import/export, quick-card add); no keys | `SECT(Vessels)`, one vessel selected, not gated, not detached. Each item selects the matching vessel tab first. | CMD | 10 |
| SHELL-655 | SIRE 2.0 Export… | — | `SIRE 2.0 e_xport...` (SHELL-099) | `APP` | CMD | 12 |
| SHELL-656 | Set Gemini API Key… | — | `Set _Gemini API key...` (SHELL-100) | `APP` | CMD | 12, 14 |
| SHELL-657 | Set / Change Password… | — | `Set / change _password...` (SHELL-101) | `APP` | CMD | 01 |
| SHELL-658 | Lock Now | ⌃⌘L | `_Lock now` (SHELL-102) | `APP` | CMD | 01, 04 |

Separators follow Windows: after Unit Converter, after Check Crew Contract Expiries, after the Vessel submenu (new),
and after Set Gemini API Key.

##### Window and Help menus

| ID | Mac title | Key | Windows | Notes |
|---|---|---|---|---|
| SHELL-660 | Window ▸ Minimize ⌘M, Zoom, Fill / Center / Move & Resize (system tiling), Bring All to Front, open-window list | ⌘M | — | Standard. Exclusions per SHELL-526. |
| SHELL-662 | Help ▸ AA Keyboard Shortcuts | — | the shortcut strip is the nearest Windows analogue | SHELL-523. It replaces SwiftUI's default "AA Help" (no help book): `CommandGroup(replacing: .help)`. |
| SHELL-663 | Help ▸ search field | ⇧⌘/ | Alt/F10 menu access keys (SHELL-690) | system |

#### 6.5.1.4 In-window keys, native text keys and platform gestures (non-menu)

| ID | Key(s) | Where | Action | Windows origin | Owner |
|---|---|---|---|---|---|
| SHELL-665 | ↩ / ⌅ | dialogs and sheets | default button (`.defaultAction`); list in §6.5.1.5 | `IsDefault` buttons; Enter handlers | all |
| SHELL-666 | ⎋ and ⌘. | windows and sheets | cancel or close per §6.5.1.5 (SHELL-514) | `IsCancel` buttons; switcher Esc | all |
| SHELL-667 | ↩ | a focused list | Windows double-click action (`primaryAction`). **Hierarchy sidebar: Rename** (SHELL-515, X-8). File tables: Open (CONT-089). Search results: navigate (08). Builders: Edit… (06). Calendar rows and Board cards: editor (VIEW-014/049). Relationships: open item. Bucket members: open. | double-click | per role |
| SHELL-668 | ⌘↩ | builder bulk editor; Folder builder | `Add all` (06); `Create folders` (14) | — (Mac addition) | 06, 14 |
| SHELL-669 | Space | file bank table, viewer file list; work-orders table; checkboxes | Quick Look (`QLPreviewPanel`); toggle Done (optional); native toggle | — / checkbox Space | 05, 04, 10 |
| SHELL-670 | ⌫ / ⌦ | a focused list whose Windows delete confirms | same handler as SHELL-544 through `.onDeleteCommand`, with the Windows confirmation. **Not** in the file bank (CONT-088 has no confirmation) or in lists whose Windows Remove has no confirmation. | — | per role |
| SHELL-671 | ⌘↓ | file tables | Open the selected file (Finder "Open"). Replaces 05's ⌘O (X-2). | double-click / `Open` | 05 |
| SHELL-672 | ↑ ↓ ↩ ⎋ | quick-switcher query field | move selection (clamped); open selected and close; close | `SearchBox_PreviewKeyDown` (`QuickSwitcherWindow.xaml.cs:81-90`) | 08 |
| SHELL-673 | ↩ | Search window | query field → run the search; results list → navigate | `QueryBox_KeyDown` (:39-41), `Results_Key` (:113) | 08 |
| SHELL-674 | ↩ / ⌥↩ | fields | login password box → Sign in (`LoginWindow.xaml.cs:21-23`); hierarchy unlock box → unlock (`HierarchyPage.xaml.cs:654-657`); Name box → commit and re-sort (`:706-712`); SIRE new-task box → add (`SirePage.xaml.cs:350`); item Description → Return commits, ⌥↩ inserts a newline (04 §6.3) | Enter handlers | 03, 04, 12 |
| SHELL-675 | ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫ | Trash sheet only | Put Back (`↩ Restore`) / Delete Immediately… (`Delete permanently`, confirm) / Empty Trash… (confirm). Texts per REPO-078. | buttons, no keys | 02 |
| SHELL-676 | ⌘. and ⎋; ↩ | Flash Sync window | Stop (flashing or camera) when running, else nothing; ↩ = focused primary button only | — | 13 |
| SHELL-677 | ⌘A, ⌘-click, ⇧-click | Board column, tables, multi-select lists | select all in the focused column or list; toggle; range | Ctrl+A, Ctrl-click, Shift-click | 07, 04 |
| SHELL-678 | ⌘-click | links in the container editor | open the link (not clickable on Windows — addition) | — | 05 |
| SHELL-679 | drag modifiers | file-bank drop | none = import a copy; ⇧ or ⌥⌘ = link in place (Finder make-alias gesture) | none/Shift at drop | 05 |
| SHELL-680 | ⇥ / ⇧⇥ | container editor | at list-item start: nest / un-nest; elsewhere ⇥ inserts a tab character (`AcceptsTab`) | Tab / Shift+Tab (CONT-044) | 05 |
| SHELL-681 | ↩ / ⇧↩ (⌃↩ optional) | container editor | new item at the same level (empty item → leave the list); line break | Enter / Shift+Enter | 05 |
| SHELL-682 | ⌫ at list-item start | container editor | outdent one level; at top level, turn into a paragraph | `Rtb_PreviewKeyDown` Backspace branch (CONT-045) | 05 |
| SHELL-683 | ⌥⌫ / ⌥⌦ | text | delete word | Ctrl+Backspace / Ctrl+Delete | native |
| SHELL-684 | ⌥←/→, ⌘←/→, ⌘↑/↓, ⌥↑/↓, fn↑/↓, + ⇧ to extend | text | word / line / document / paragraph / page moves | Ctrl+←/→, Home/End, Ctrl+Home/End, Ctrl+↑/↓, PgUp/PgDn | native |
| SHELL-685 | ⎋ inside AA rich text | container editor, SIRE body, viewer | passed to the next responder (SHELL-514); completion on ⌥⎋ / F5 | none | 05 |
| SHELL-686 | Insert (overtype) | — | **Not available.** Mac keyboards have no Insert key and NSTextView has no overtype mode. Dropped (a platform gesture, not an AA feature). | WPF `ToggleInsert` | — |
| SHELL-687 | Ctrl+Space | — | **Not mapped.** WPF built-in `ResetFormat` (unconfirmed; 05 marks built-ins "confirm"). ⌃Space is the macOS input-source switch. Format ▸ Clear Formatting keeps the capability. | WPF internal | 05 |
| SHELL-688 | SIRE body keys | SIRE question body | ⌘C, ⌘A, ⌘V (insert at the selection start), ⌘Z/⇧⌘Z (own insertions), ⌘B/⌘I/⌘U (typing attributes). ⌘X, ⌫, ⌦, ⌥⌫, ⌘⌫, ⌃H, ⌃D, ⌃K and all delete/transpose actions are blocked by the gate. | `DetailBox_PreviewKeyDown` (`SirePage.xaml.cs:52-67`) | 12 §6.3 |
| SHELL-689 | locked text | container editor | only mutations are blocked; commands are never swallowed (SHELL-524) | CONT-063 | 05 |
| SHELL-690 | Alt / F10 access keys (`_File` …) | — | ⌃F2 (Full Keyboard Access: focus the menu bar) and the Help search field (⇧⌘/) | WPF access keys | system |
| SHELL-691 | Shift+F10 / Menu key (context menu) | — | ⌃-click or two-finger click; VoiceOver ⌃⌥⇧M. No Mac key opens a context menu for a selection. Every context-menu command that matters has a menu-bar or toolbar path in this registry. | WPF | — |
| SHELL-692 | Alt+F4 | — | ⌘W (window) / ⌘Q (app) | WPF | SHELL-513 |
| SHELL-693 | Ctrl+Tab / Ctrl+Shift+Tab | — | SHELL-631 and ↑/↓ in the section sidebar. ⌃⇥ stays macOS focus navigation. | WPF TabControl built-in. An inner TabControl (item detail, vessel tabs) catches it first when focus is inside it. | 03 |
| SHELL-694 | Alt+↓ / F4 on DatePicker and ComboBox | — | native: Space or ↓ opens pop-ups; date fields step with ↑/↓ | WPF built-ins | native |
| SHELL-695 | type-ahead in lists | — | native `List`/`Table` type-select | WPF `TextSearch` | native |

#### 6.5.1.5 Per-window close, cancel and default keys

| Window or sheet (owner) | ⌘W | ⎋ | ⌘. | ↩ | Other |
|---|---|---|---|---|---|
| Splash (03) | — (never key) | — | — | — | — |
| Login `AA — Sign in` (03 SHELL-004) | closes = Exit → terminate | nothing (faithful: `Exit` is not `IsCancel`) | nothing | `Sign in` (default; also from the password box) | — |
| Main window (03) | **quit pipeline** (SHELL-513) | nothing at window level. A search field clears (standard). | nothing | per focus (SHELL-667) | — |
| Item window (04 HIER-111) | close → flush → reattach | nothing | nothing | per focus | — |
| Search (08 D) | close | the query field clears if it is an `NSSearchField`, else nothing | nothing | run / navigate (SHELL-673) | ⌘F focuses the query |
| Quick switcher panel (08 C) | close | **close** (faithful) | close | open the selected item | ↑/↓; closes on resign-key |
| Quick work (08 B) | close (flush) | nothing | nothing | per focus | ⌥⌘F → filter |
| Due-dates panel (08 A) | close (custom `performClose`) | nothing (faithful) | nothing | per focus | ⌘R = activate and refresh |
| Activity log (08 E) | close | the filter field clears | nothing | — | ⌥⌘F → filter |
| Unit converter (14) | close | nothing | nothing | — | — |
| Date calculator (14) | close | **close** (faithful `IsCancel`) | close | — (no default button) | — |
| Folder builder (14) | close | close (Mac addition) | close | text: newline | ⌘↩ Create folders |
| Crew table view (09) | close | **close** (faithful `IsCancel`) | close | — | — |
| Container viewer (CONT-098) | close | **close** (faithful `IsCancel`) | close | **close** (faithful `IsDefault`) | Space / ⌘Y Quick Look; ⌘F find |
| Flash Sync (13) | stop everything, then close | Stop when running, else nothing | Stop | focused primary button only | — |
| Settings (03), About panel, Keyboard Shortcuts (SHELL-523) | close | nothing / close / search field clears | — | — | — |
| **Decision sheets**: Prompt (`OK`), Password (`OK`), Date prompt (`OK`), Item picker (`OK`/`Add`), Item lock (`OK`), Tab colours (`Apply`), Review changes / Diff (`Import (Overwrite)`), Insert saved list (`Insert`), List style (`Continue`), Quick card editor (`OK`), Crew editor (`Save`), New Task / New bucket prompts, relationship picker, Drive backup picker (14 Q-22), crew date-order question (09) | **nothing** (beep; never reaches main) | **Cancel** (faithful where Windows had `IsCancel`: Diff, Insert saved list, List style, Quick card; Mac addition elsewhere) | Cancel | the default button in parentheses (faithful `IsDefault`) | — |
| **Close-type sheets**: Checklist / Subtask / Template builders (06), Trash (02), Subtask and Checklist-step editors (05) when presented as sheets | **Close** (closing is saving) | Close (from inside AA rich text too, SHELL-514) | Close | builders: list → `Edit…`; Trash: none | builders ⌘↩, ⌃⌘↑/↓, ⇧⌘M, ⌫; Trash SHELL-675 |
| Alerts (`NSAlert` sheets) | nothing | the Cancel/No-role button. 13's safe defaults (`Not Yet`, `Don't Apply`) take both ↩ and ⎋. | same as ⎋ | the default button | `Don't …` buttons ⌘D |

#### 6.5.1.6 Final menu bar

```
AA
  About AA
  ─
  Settings…                                   ⌘,
  ─
  Services ▸
  ─
  Hide AA                                     ⌘H
  Hide Others                                 ⌥⌘H
  Show All
  ─
  Quit AA                                     ⌘Q
File
  New {Kind}                                  ⇧⌘N      [plus]
  Open in New Window                                   [macwindow.badge.plus]
  ─
  Rename                                      F2       [pencil]
  Quick Look                                  ⌘Y       [eye]
  Move to Trash | Delete Task | Remove | Delete   ⌘⌫   [trash]
  ─
  Close                                       ⌘W
  Save                                        ⌘S       [square.and.arrow.down]
  Save a Copy As JSON…                        ⇧⌘S      [doc.on.doc]
  Reload from Disk                                     [arrow.clockwise]
  Import from File…                                    [square.and.arrow.down.on.square]
  ─
  Trash (Restore Deleted Items)…                       [trash.circle]
  Encrypt Local Data File (This Mac)          ✓        [lock.doc]
  ─
  Shared Save ▸  Set Shared Save File… · Stop Shared Save File · ─ · Check Shared Save Now
  Set App Identity…                                    [person.text.rectangle]
  ─
  Open Data Folder                                     [folder]
  Export Data Folder (ZIP)…                            [archivebox]
  Import Data Folder (ZIP)…
  Export Text Only (No Attachments)           ✓
  ─
  Google Drive ▸ Save a Copy to Google Drive (Synced Folder) · Set Google Drive Folder… · ─ ·
                 Upload Backup to Google Drive (OAuth)… · Load Backup from Google Drive (OAuth)… ·
                 Set Google OAuth Client (client_secret.json)… · Sign Out of Google · ─ ·
                 Sync to Google Drive on Save ✓ · Check Google Drive for Newer Save
  ─
  Flash Sync with iPhone (QR)…                         [qrcode]
  ─
  Export as PDF…                              ⌥⌘E      [arrow.up.doc]
  Print…                                      ⌘P       [printer]   (optional feature)
Edit
  Undo {…}                                    ⌘Z
  Redo {…}                                    ⇧⌘Z
  ─
  Cut ⌘X · Copy ⌘C · Paste ⌘V · Paste and Match Style ⌥⇧⌘V · Delete · Select All ⌘A
  ─
  Move Up                                     ⌃⌘↑
  Move Down                                   ⌃⌘↓
  Move To…                                    ⇧⌘M
  ─
  Find ▸  Find… ⌘F · Search All Items… ⇧⌘F · Search Current List ⌥⌘F · ─ ·
          Find Next ⌘G · Find Previous ⇧⌘G · Use Selection for Find ⌘E · Jump to Selection ⌘J
  Spelling and Grammar ▸ · Substitutions ▸ · Transformations ▸ · Speech ▸
  (system: Writing Tools · AutoFill · Start Dictation… · Emoji & Symbols)
Format
  Font ▸  Show Fonts ⌘T · ─ · Bold ⌘B · Italic ⌘I · Underline ⌘U · Strikethrough ⇧⌘X · ─ ·
          Bigger ⌘+ · Smaller ⌘− · ─ · Baseline ▸ (Use Default · Superscript ⌃⌘+ · Subscript ⌃⌘−) · ─ ·
          Show Colors ⇧⌘C · Highlight ▸
  Text ▸  Align Left ⌘{ · Center ⌘| · Justify · Align Right ⌘}
  Lists ▸ Bulleted List ⇧⌘7 · Numbered List ⇧⌘9 · ─ · Indent ⌘] · Outdent ⌘[
  Insert ▸ Link… ⌘K · Table… · Saved List… ⌥⌘L
  ─
  Clear Formatting
  ─
  Lock Highlighted Text… · Unlock Highlighted Text…
View
  {section 1} ⌘1 … {section 9} ⌘9 · {section 10…13}          (display order; ✓ on the active one)
  Previous Section · Next Section
  ─
  Previous ⌘← · Go to Today ⇧⌘T · Next ⌘→                   (Planner)
  ─
  Show/Hide Sidebar ⌃⌘S
  Hide/Show Toolbar ⌥⌘T · Customize Toolbar…
  Shortcut Bar ✓ · Dark Mode ✓ · Customize Tab Colors…
  ─
  Enter Full Screen ⌃⌘F
Tools
  Folder Builder… · Date Calculator… · Floating Due-Dates Window ⌘R · Quick Work Window ⌘N ·
  Quick Switcher… ⌘O · Activity Log… · Unit Converter…
  ─
  Import COMPAS Crew (.xlsx)… · Check Crew Contract Expiries
  ─
  Vessel ▸ Import Shippalm Work Orders (.xlsx)… · Export Work Orders (.xlsx)… · ─ ·
           Import Ports of Call (.xlsx)… · Export Ports of Call (.xlsx)… · ─ · New Quick Card…
  ─
  SIRE 2.0 Export… · Set Gemini API Key…
  ─
  Set / Change Password… · Lock Now ⌃⌘L
Window  (standard; Minimize ⌘M, Zoom, tiling, Bring All to Front, open windows)
Help    (search field ⇧⌘/) · AA Keyboard Shortcuts
```

Hidden aliases (SHELL-509): ⇧⌘O in Tools, ⇧⌘V in Edit, ⌘= and ⌃⌘= in Format ▸ Font.

#### 6.5.1.7 Conflict resolutions (decisions, rationale, rejected alternatives)

**(1) ⌘F (SHELL-517).**

*Decision:* ⌘F Find… is routed: rich text → that view's find bar; Search window → its query field; anything else →
a new global Search window. ⇧⌘F Search All Items… is always global. ⌥⌘F Search Current List focuses the list filter.

*Rationale:*
* HIG: ⌘F finds within the focused content. The Find ▸ items are AppKit-standard, NSTextView implements them, and
  every Mac rich-text app finds in the note on ⌘F.
* Windows parity is kept everywhere Ctrl+F reached the WPF window: from lists, plain fields, the sidebar, other
  sections, and the header button. The one exception is inside the WPF editor, where Ctrl+F opened global search.
  On the Mac that is ⇧⌘F or the toolbar button, and the shortcut strip still reads `⌘F Search`.
* ⌥⌘F keeps Mail's "search the list" meaning instead of being spent on in-note find.

*Adopted:* 02:1890 (⌘F in-note when an editor is focused) and 02 Q-9's ⇧⌘F.

*Rejected:*
* 05 §6.3 / Q4 and 08 OQ-4 / :1463 (⌥⌘F for in-note find, ⌘F always global).
* 03 §6.4 ("⌥⌘F for the editor's find bar so ⌘F stays global").
* 10 §6.8 (⌘F focuses the panel search field), which moves to ⌥⌘F.

08 OQ-4 is answered.

**(2) ⌘T (SHELL-518).**

*Decision:* ⌘T = Show Fonts only, `RICH`. Planner Today = ⇧⌘T, with Previous ⌘← and Next ⌘→.

*Rationale:*
* The Format menu is always present, so ⌘T must mean one thing app-wide (SHELL-500).
* ⇧⌘T keeps the "T" mnemonic calendar users expect. It is free in macOS and in AA; AA has no "Make Plain Text".

*Rejected:* 07:1225's "⌘T when the Planner is focused". An in-view ⌘T on the Planner would shadow a standard
key and break SHELL-500.

*Side effect:* WPF's editor Ctrl+T (increase indentation) becomes ⌘] (X-7).

**(3) Individual proposals.**

| Proposal (spec:line) | Decision | Why |
|---|---|---|
| ⌥⌘T Table View (09:1291) | **Rejected**. Crew `Table View…` stays a toolbar button, with no key and no menu item (Windows has only a button). | ⌥⌘T is the HIG-standard Hide/Show Toolbar (SHELL-526) |
| ⌥⌘T Insert Table (05:1162) | **Rejected**. Format ▸ Insert ▸ Table…, no key. | same |
| ⇧⌘I Import COMPAS (09:1289) | **Rejected**. Tools ▸ Import COMPAS Crew (.xlsx)… and the crew toolbar button, no key. | infrequent operation; Windows has none; keeps ⇧⌘I free |
| ⌥⌘E Export as PDF (11:69, :1221) | **Adopted**: File ▸ Export as PDF… | free; mnemonic; file-menu convention |
| ⇧⌘M Move to… (06:1152) | **Adopted**: Edit ▸ Move To…, list-only (TXT) | no system use; Services ⇧⌘M loses to app menus and needs a text selection anyway |
| ⇧⌘N New {kind} (04:1210) | **Adopted**: File ▸ New {Kind}, extended to Board, Buckets and Saved Lists create buttons | it replaces WPF's in-editor Ctrl+Shift+N numbering, which is ⇧⌘9 on the Mac (X-6) |
| ⌃⌘L Lock now (03 §6.4, 01:2209) | **Adopted**: Tools ▸ Lock Now | the two specs agree; free |
| ⌘P quick-switcher alias (03 §6.5) vs Print (11:1219) | **⌘P = Print…** (optional feature). The alias is **rejected**. The switcher alias is ⇧⌘O. | ⌘P is HIG-standard Print |
| ⇧⌘7 / ⇧⌘9 lists (05:1156) | **Adopted** | Apple Notes convention; distinct from ⌘7/⌘9 (sections); verify AZERTY (T-KB-41) |
| ⇧⌘O switcher alias (02:1893, 08:1151) | **Adopted** as a hidden alias | Xcode "Open Quickly" |
| ⌥⌘Y Flash Sync (13:86, optional) | **Not adopted** | Windows has none; rare |
| ⌥⌘L Insert Saved List (05:1158) | **Adopted**, `RICH` only | free |
| ⌘K Insert Link (05:1161) | **Adopted** | de-facto Mac standard |
| ⇧⌘X Strikethrough (05:1152) | **Adopted** | Apple Notes |
| ⌥⇧⌘V + ⇧⌘V (05:1165) | **Adopted**: standard item plus hidden alias | direct Ctrl+Shift+V mapping |
| ⌘Y Redo alias (05:1160) | **Rejected**. ⌘Y = Quick Look (Finder). | X-3 |
| ⌃⌥↑/↓ move alias (05:1159) | **Rejected** | ⌃⌥ is the VoiceOver modifier (X-5) |
| ⌥⌘↑ / ⌥⌘↓ list move (02:1919, 06:1151) | **Superseded** by ⌃⌘↑ / ⌃⌘↓ | one app-wide pair. 06's own stated intent was "matching the rich-text list reorder gesture", which 05 set to ⌃⌘↑/↓. |
| ⌘O open file in the file bank (05:1278) | **Rejected**. Use ↩, ⌘↓ or double-click. | ⌘O = Quick Switcher (X-2) |
| ⌘0 calendar text reset (07:1178, optional) | **Not bound** | resolution 5 |
| ⌘←/⌘→ Planner (07:1225) | **Adopted**, TXT class | Apple Calendar precedent |
| ⌥⌘⌫ Trash window (01:2199) | **Rejected** | in Finder ⌥⌘⌫ means *Delete Immediately*, the opposite; 02:1853 says none |
| Optional SIRE CommandMenu (12:959) | **Not in v1**. If added later: Tools ▸ SIRE Question ▸ …, with no keys unless registered here first. | no section-specific top-level menus (SHELL-525) |

**(4) ⌘⌫ (SHELL-516).**

*Decision:* The Delete family is one File item on ⌘⌫, titled with the focused list's Windows caption and running
that list's handler with its confirmation. It is TXT-class, so text keeps ⌘⌫. Plain ⌫/⌦ work only where Windows
confirms. The Trash window has no shortcut. The Trash sheet uses Finder's ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫.

*Rationale:*
* One owner (SHELL-500).
* Finder puts Move to Trash (⌘⌫) in File.
* 02, 04, 07 and 09 ("Move to Trash") and 05 ("Remove") become one routed item.
* 01's "⌥⌘⌫ optional" for opening Trash is rejected (see the table above).

**(5) Font size (SHELL-519).**

*Decision:* Format ▸ Font ▸ Bigger ⌘+ / Smaller ⌘− are routed: editor font size first, then Calendar text size. ⌘0
is not bound.

*Rationale:*
* Mail's Format ▸ Bigger/Smaller acts on the composing text or on the viewer depending on context.
* A separate View ▸ zoom pair would need ⌥⌘= / ⌥⌘-, which are live Accessibility Zoom keys (X-15), or a second
  ⌘+ owner.

*Rejected:* 07:1178's "⌘−/⌘+ when the Calendar is focused" as a *separate* item, and its optional ⌘0.

**(6) Indent and reorder (SHELL-520).** ⌘] Indent and ⌘[ Outdent live in Format ▸ Lists (05 adopted). Move Up and
Move Down are ⌃⌘↑ / ⌃⌘↓ in Edit and are shared by the editor and all ↑/↓ lists (05 adopted, extended). The ⌃⌥ alias
is dropped. 02's and 06's ⌥⌘ arrows are superseded.

**(7) ⌘W on the main window: confirmed (SHELL-513).**

*Decision:* ⌘W on the main window runs the SHELL-056 quit pipeline (§6.1, 01 §6.9).

*Reasons:*
* **Semantic parity.** On Windows, closing the main window saves, pushes the shared bundle and exits. Users who hand
  off between PCs through the shared save rely on "close = saved and pushed".
* **Precedent.** Single-window Mac utilities (System Settings, Calculator) quit when their window closes.
* **No data risk.** The pipeline saves everything.

*Guards:*
* A sheet can never forward ⌘W to the main window.
* Decision sheets ignore ⌘W.
* No confirmation, matching Windows.

*Rejected for v1:* Mail-style hide-on-close with the app running, where a Dock click or MenuBarExtra "Show AA"
reopens the window. It changes the shared-save hand-off moment and the login-per-launch model (Q-KB-2).

**(8) ⎋ and ⌘. per window (SHELL-514).** See the §6.5.1.5 table. ⎋ and ⌘. are always the same action. ⌘. in Flash
Sync = Stop (13:1205 adopted). AA rich-text views pass ⎋ upward.

**Additional conflicts found while consolidating**

* **X-1.** ⌘{ / ⌘} (align left/right) are the same keystrokes as ⇧⌘[ / ⇧⌘] on US layouts. So section cycling must
  not use ⇧⌘[ / ⇧⌘] (the Safari/Finder next-tab keys).
* **X-2.** 05 proposed ⌘O to open a file in the file bank, but ⌘O is the Quick Switcher. File tables use ↩ and ⌘↓.
* **X-3.** 05 proposed ⌘Y as a redo alias, but ⌘Y is Finder Quick Look. So ⌘Y = Quick Look, and Redo is ⇧⌘Z only.
* **X-4.** ⌥⌘T is Hide/Show Toolbar, so it is not Insert Table (05) or Table View (09).
* **X-5.** ⌃⌥↑/↓ collides with VoiceOver navigation, so it is not bound.
* **X-6.** The WPF editor's Ctrl+Shift+N (numbering) and ⇧⌘N New {Kind}: on the Mac, ⇧⌘N always means New, and
  numbering is ⇧⌘9.
* **X-7.** The WPF editor's Ctrl+T / Ctrl+Shift+T (indent) and ⌘T Show Fonts: on the Mac, indent is ⌘] / ⌘[.
* **X-8.** Return on a hierarchy row: 04 §6.2 says rename, but a SwiftUI `primaryAction` fires on Return *and*
  double-click (HIER-M03 = open in window). The decision is Return = Rename and double-click = Open in New Window.
  Implement the double-click as `onTapGesture(count: 2)` on the row, or with an AppKit `doubleAction`, rather than
  `primaryAction`. Alternatively, attach `.onKeyPress(.return)` to the List, and verify that it runs before
  `primaryAction` (T-KB-24).
* **X-9.** 12's optional "Add to AA" undo group versus ⌘Z Undo Move to Trash outside text: not adopted.
* **X-10.** 01:2211 (register deletions on the window `UndoManager`) versus 02 §6.4 / 03 §6.5 (a router that reads the
  persisted Trash). The router wins, because it works across relaunches and for crew deletes.
* **X-11.** SwiftUI's automatic "New … Window ⌘N" for `WindowGroup` scenes would collide with Quick Work ⌘N. It is
  suppressed (SHELL-526).
* **X-12.** 08:1149-1151 duplicated entries (View/Window ▸ Due Dates, File ▸ Quick Work…, File ▸ Go to Item…).
  Tools keeps the single entries.
* **X-13.** Menu titles in 01 §6.10 and 03 §6.4 differed. SHELL-508 decides them:

  | 01 title | Final title |
  |---|---|
  | Save a Copy As JSON… | kept |
  | Revert to Saved… | Reload from Disk |
  | Import Database (JSON)… | Import from File… |
  | Trash… | Trash (Restore Deleted Items)… |
  | Shared Save File ▸ Set… / Stop Using / Check Now | Shared Save ▸ Set Shared Save File… / Stop Shared Save File / Check Shared Save Now |
  | Show Data Folder in Finder | Open Data Folder |
  | Export Bundle… / Import Bundle… | Export Data Folder (ZIP)… / Import Data Folder (ZIP)… |
  | Set / Change App Password… | Set / Change Password… |
  | identity in the app menu | File ▸ Set App Identity… plus a Settings field |

* **X-14.** 03's "Search Everything…" versus 08's "Search All Items…": the final title is **Search All Items…**.
* **X-15.** ⌥⌘= / ⌥⌘- are Accessibility Zoom keys, so there is no ⌥⌘+ / ⌥⌘− text-size pair.
* **X-16.** ⌘R versus the WPF editor's Ctrl+R (align right): ⌘R is always the due-dates window. Align right is ⌘}.
  This confirms 03 Q-6 and 05:1168.
* **X-17.** The ⇧⌘M and ⇧⌘A default Services: app menus win, and Move To… is list-only anyway.
* **X-18.** ⌃⇥ is not bound. It is macOS focus escape from text views and tables.
* **X-19.** ⌘0 is not bound.
* **X-20.** ⎋ in an NSTextView opens word completion, which would contradict "⎋ cancels the sheet" in 04, 06, 07, 09,
  12 and 14. AA rich-text views pass ⎋ upward (SHELL-514).
* **X-21.** Toolbar `.keyboardShortcut`s would bypass enablement, so there are none (SHELL-510).
* **X-22.** ⌘S, ⌘N and similar while a WPF locked selection is active were swallowed on Windows. The Mac does not
  replicate this (SHELL-524).

#### 6.5.1.8 Supersession map

| Spec location | Proposal | Registry outcome |
|---|---|---|
| 01 §6.10 (:2195-2211) | titles, ⇧⌘S, ⌥⌘⌫, ⌃⌘L, ⌘,, UndoManager undo | ⇧⌘S, ⌃⌘L and ⌘, adopted; titles per X-13; ⌥⌘⌫ rejected; undo per SHELL-521 |
| 02 §6.4 (:1853-1868) | Trash has no key; sidebar ⌘⌫; Put Back / Delete Immediately; ⌘Z responder | adopted (SHELL-516/221/375) |
| 02 §6.6 (:1881-1894), Q-9, Q-10 | ⌘F contextual + ⇧⌘F; ⌘O + ⇧⌘O | adopted (SHELL-517, SHELL-649) |
| 02 §6.9 (:1919), Q-6 | ⌥⌘↑/↓ for saved lists; ⌘⌫ in sidebars | ⌃⌘↑/↓ (SHELL-581/282); ⌘⌫ adopted |
| 03 §6.2 toolbar, §6.4, §6.5, Q-6 | "Search Everything…" ⌘F; ⌥⌘F editor find; ⌘P alias; ⌃⌘L; ⌘W quit; ⌘R in the editor | title and routing changed (SHELL-584/285); ⌥⌘F reassigned; ⌘P alias rejected; the rest confirmed |
| 04 §6.2 (:1115), §6.9 (:1204-1214), HIER-M02/M03/M06 | ⌘⌫, Return/F2 rename, ⇧⌘N, double-click → window, Space Quick Look, ⎋ cancels sheets | adopted (X-8 for the implementation) |
| 05 §6.3 (:1140-1170), §6.9 (:1272-1285), Q4 (:1523) | Format menu keys; ⌥⌘F Find in Note; ⌥⌘T table; ⌘Y alias; ⌃⌥ alias; ⌘O / ⌘⌫ / Space in the file bank | adopted except: Find in Note → ⌘F; ⌥⌘T, ⌘Y, ⌃⌥ and ⌘O rejected |
| 06 §6.2 (:1136-1153) | ⌥⌘↑/↓, ⇧⌘M, ⌘↩, ⌫, ⎋/⌘W close | ⌃⌘↑/↓ instead; the rest adopted |
| 07 §7.1 (:1178), §7.2 (:1207-1219), §7.3 (:1225) | ⌘−/⌘+/⌘0 calendar; Board ⌫/⌘⌫, ⌘A; Planner ⌘←/⌘→/⌘T | routed Bigger/Smaller; ⌘0 not bound; ⌘T → ⇧⌘T; the rest adopted |
| 08 §6.1 (:1149-1159), OQ-4 (:1462), Q-15 (:1449) | duplicate menu entries; "Search All Items…" ⌘F; ⌘W everywhere | single Tools entries; title adopted with key ⇧⌘F; ⌘W adopted |
| 09 §6.4 (:1289-1292) | ⇧⌘I, ⌥⌘T, ⌘⌫ + Delete key | ⇧⌘I and ⌥⌘T rejected; delete adopted |
| 10 §6.7 (:1568-1569), §6.8 (:1650-1656) | ⌫/⌦ delete, Space Done; ⌘F panel search; Vessel menu / File ▸ Import | adopted; ⌘F → ⌥⌘F; Tools ▸ Vessel ▸ |
| 11 PDF-001 (:69), §6.2 (:1219-1221) | ⌥⌘E, ⌘P Print | adopted (Print optional) |
| 12 §6.3 (:945-959), :1040 | key mapping; SIRE menu; ⌥⌘F; undo group | mapping adopted; menu not in v1; ⌥⌘F adopted; undo group rejected |
| 13 FLASH-001 (:85-86), §6.6 (:1202-1205) | no key / ⌥⌘Y; ⌘. Stop; ⌘W stops and closes | no key; the rest adopted |
| 14 §6.6-6.8 (:1555-1597), Q-22 | no tool keys; ⌘W; ⌘↩ Create folders; ⎋ closes | adopted |

#### 6.5.1.9 User-visible strings that name keys

These are Mac renderings. Everything else in each string stays verbatim. This applies to status text, tooltips,
empty states and help text. An existing Mac rule (A.4 note: "(Ctrl+Z)" → "(⌘Z)") is restated here as part of the
full list.

| Windows string (source) | Mac string |
|---|---|
| `Restored {n} deleted items (Ctrl+Z).` / `Restored the last deleted item (Ctrl+Z).` (`MainWindow.xaml.cs:1469-1471`) | `… (⌘Z).` |
| Trash menu tooltip `… Deletes go here instead of vanishing — Ctrl+Z undoes the last one.` (`MainWindow.xaml:31`) | `… — ⌘Z undoes the last one.` |
| Sync-on-save tooltip `When on, Ctrl+S also pushes your data…` (`:63`) | `When on, ⌘S also pushes your data…` |
| Tools titles `Quick _work window (Ctrl+N)`, `Quick s_witcher (Ctrl+O)` (`:79`, `:81`) | `Quick Work Window`, `Quick Switcher…` (the key column shows ⌘N / ⌘O) |
| Quick switcher tooltip `… Obsidian-style. Type, then Enter.` (`:82`) | `… Type, then Return.` |
| Header buttons `Search (Ctrl+F)`, `Go to (Ctrl+O)`, `Save (Ctrl+S)` (`:122-126`) | toolbar labels `Search`, `Go to`, `Save`; help `Search all items (⌘F; ⇧⌘F from inside a note)`, `Quick switcher — fuzzy-jump to any item by name, kind or #tag. (⌘O)`, `Save (⌘S)` |
| Shortcut strip (`:138-146`) | unchanged from §6.2: `⌨  ⌘S Save · ⌘F Search · ⌘N Quick work · ⌘O Go to (quick switcher) · ⌘R Due-dates window · ⌘1…9 Switch tab · F2 Rename · ⌘Z Undo delete` |
| Hierarchy `Delete` tooltip `… or undo with Ctrl+Z.` (`HierarchyPage.xaml:71`); `BatchDeleteMenu.cs:31` | `… or undo with ⌘Z.` |
| Tags tooltip `… global search and the quick switcher (Ctrl+O).` (`HierarchyPage.xaml:144`) | `… (⌘O).` |
| `No tasks yet.\n\nClick “+ New” to add a task, or Ctrl+N for the quick-work window.` (`HierarchyPage.xaml.cs:156`) | `… or ⌘N for the quick-work window.` |
| `'{name}' moved to Trash — Ctrl+Z to undo.` / `{n} items moved to Trash — Ctrl+Z to undo them all.` (`:418-419`) | `— ⌘Z to undo.` / `— ⌘Z to undo them all.` |
| Crew delete confirmation `… or undo with Ctrl+Z.` (`CrewPage.xaml.cs:386`); batch confirmation (`BatchDeleteMenu.cs:99`) | `… or undo with ⌘Z.` |
| Buckets help `… (in the Ctrl+N quick-work window).` (`BucketsPage.xaml:19`) | `(in the ⌘N quick-work window)` |
| Insert-saved-list note `… one Ctrl+Z removes the whole list again.` (`InsertSavedListWindow.xaml:10`) | `… one ⌘Z removes …` |
| Editor tooltips `Bold (Ctrl+B)`, `Italic (Ctrl+I)`, `Underline (Ctrl+U)`, `Undo (Ctrl+Z)`, `Redo (Ctrl+Y)` (`ContainerEditor.xaml:21-23, 45-46`) | `Bold (⌘B)`, `Italic (⌘I)`, `Underline (⌘U)`, `Undo (⌘Z)`, `Redo (⇧⌘Z)` |
| `Move the current list item (or block) up — Ctrl+Alt+Up. Sub-items move with it.` / `… down — Ctrl+Alt+Down. …` (`:41`, `:43`) | `— ⌃⌘↑.` / `— ⌃⌘↓.` |
| `Outdent (Shift+Tab at the start of a list item)` (`:37`); `Indent (Tab at the start of a list item)` (`:36`) | `Outdent (⇧Tab at the start of a list item)`; the Indent tooltip is unchanged. Tooltips without a Windows key (Strikethrough, Align…, Bullets…) *may* append the Mac key, e.g. `Strikethrough (⇧⌘X)`. |
| Context menu `Paste text only` with gesture `Ctrl+Shift+V` (`ContainerEditor.xaml.cs:137-139`) | the context item `Paste Text Only` shows ⌥⇧⌘V; the menu-bar item is `Paste and Match Style` |
| Quick switcher footer `Enter to open  ·  ↑ / ↓ to move  ·  Esc to close` (`QuickSwitcherWindow.xaml:13`) | `Return to open  ·  ↑ / ↓ to move  ·  Esc to close` |
| SIRE placeholder `Add a task and press Enter…` (`SirePage.xaml:150`); `Editable — type to add line breaks / notes (Enter = new line). Your edits are saved.` (`:164`) | `…press Return…`; `(Return = new line)` |
| Shortcut-strip close tooltip `Hide this shortcuts strip (View ▸ Shortcut bar to bring it back).` | `(View ▸ Shortcut Bar to bring it back).` |

Imperative "Enter a …" prompts (for example `Enter the app password…`) are verbs, not key names, and stay unchanged.

#### 6.5.1.10 Logic: CommandRouter

**State**, all on the main actor:

```swift
enum Responder { case richText(RichKind, editable: Bool, hasSelection: Bool)   // AARichTextView
                 case text(hasSelection: Bool, editable: Bool)                  // any other NSText
                 case none }
enum RichKind { case container, sireBody, viewer }
enum KeyWin { case main, item(UUID), search, quickWork, due, switcher, activityLog, unitConverter,
              dateCalc, folderBuilder, crewTable, viewer, flashSync, settings, shortcuts, about, login, other }
struct ListCommands {                       // published by the focused List/Table (nil when a text input has focus)
  let role: ListRole; let selectionCount: Int
  let deleteTitle: String?; let delete: (() -> Void)?; let deleteConfirms: Bool
  let canMoveUp: Bool; let canMoveDown: Bool; let move: ((Direction) -> Void)?
  let moveTo: (() -> Void)?; let quickLook: (() -> Void)?; let primary: (() -> Void)?
}
@MainActor @Observable final class CommandRouter {
  var phase: AppPhase; var keyWin: KeyWin; var keyWinIsSheetOrModal: Bool; var decisionSheetOpen: Bool
  var responder: Responder; var list: ListCommands?
  var section: TabKey; var hierSelection: (primary: UUID?, count: Int, gated: Bool, detached: Bool)
  var plannerMode: PlannerMode; var calendarFontScale: Double
  var safeMode: Bool; var hasRepo: Bool; var pendingUndoCount: Int; var inFlight: Set<LongOp>
  func state(_ c: CommandID) -> (enabled: Bool, title: String)
  func perform(_ c: CommandID)
}
```

**Global gates.** These apply first, to every command whose scope is `APP`/`MAIN`/`SECT`:

```
G1  phase != .main                       → disabled (except SHELL-530, 233, 234, text Edit items)
G2  keyWinIsSheetOrModal                 → disabled (except Quit, Hide*, Edit/Find/Format acting inside the sheet, SHELL-662)
G3  MAIN/SECT scopes require keyWin == .main
```

**Resolution of routed commands.** The first matching line wins.

```
Find (⌘F)          A richText(k,…)              → k.findBar.show()                              title "Find…"
                   B keyWin == .search           → searchWindow.focusQuery(selectAll: true)
                   C else                        → openSearchWindow()                            (SHELL-041)
SearchAll (⇧⌘F)                                  → openSearchWindow()
SearchList (⌥⌘F)   target = filterTarget(keyWin, section, focusedVesselPanel)
                   enabled = target != nil && !target.isFirstResponder → target.focus()
Undo (⌘Z)          A responder is .text/.richText → title = um.undoMenuItemTitle; enabled = um.canUndo; send undo: to nil
                   B keyWin == .main             → n = pendingUndoCount
                                                   !hasRepo || safeMode || n == 0 → ("Undo", false)
                                                   n == 1 → ("Undo Move to Trash", true)
                                                   n > 1  → ("Undo Move to Trash (\(n) Items)", true)
                                                   perform = shell.undoDelete()                   (SHELL-047)
                   C else                        → key window undoManager (standard)
Redo (⇧⌘Z)         A only                        (text redo); else key window undoManager
DeleteFamily (⌘⌫)  A responder != .none          → ("Delete", false)                              TXT
                   B list?.delete != nil && list!.selectionCount > 0 → (list!.deleteTitle!, true)
                   C else                        → ("Delete", false)
MoveUp/Down        A .richText(.container, editable: true, _) → editor.moveCurrent(up:)          (CONT-046)
                   B responder != .none          → disabled
                   C list?.move != nil && canMove(dir) → list.move(dir)
MoveTo (⇧⌘M)       responder == .none && list?.moveTo != nil && list.selectionCount ≥ 1
Rename (F2)        keyWin == .main && section.isHierarchy && responder == .none && hierSelection.primary != nil
                   → hierarchyPage(section).beginRename()                                         (SHELL-046)
QuickLook (⌘Y)     responder == .none && list?.quickLook != nil && selectionCount ≥ 1
NewKind (⇧⌘N)      keyWin == .main && section ∈ creatable → flushAllEditors(); page.createNew()
                   title = ["TabEquipment":"New Equipment/Area","TabTasks":"New Task","TabProcedures":"New Procedure",
                            "TabVessels":"New Vessel","TabBoard":"New Task…","TabBuckets":"New Bucket…",
                            "TabLists":"New List…"][section] ?? "New Item"
Bigger/Smaller     A .richText(.container, editable: true, _) → editor.stepFontSize(±)
                   B .richText(.sireBody/.viewer, …) → disabled
                   C keyWin == .main && section == .calendar && responder == .none
                                                 → s = clamp(calendarFontScale ± 1.5, 11, 28); set Ui.CalendarFontScale = s; MarkDirty()
                   D else                        → disabled
Planner prev/today/next   keyWin == .main && section == .planner && (today: true | prev/next: responder == .none)
Sections ⌘1…9      i < 13 && index exists in TabOrder-applied list → bring main front; select(order[i])
Due/QuickWork/Switcher    G1+G2 only (switcher also needs hasRepo)
Save (⌘S)          G1+G2 → shell.doSave()                                                         (safe mode → D4 inside)
ExportPDF/Print    item = keyWin == .item(id) ? id : (keyWin == .main && section.isHierarchy && !hierSelection.detached
                          ? hierSelection.primary : nil)
                   enabled = item != nil && !isGated(item)
LockNow (⌃⌘L)      G1+G2
Drive Upload/Load/Check   G1+G2 && !inFlight.contains(op)
Format items       A .richText(.container, editable: true, _) → all
                   B .richText(.sireBody, …)     → Bold/Italic/Underline only (typing attributes)
                   C else                        → disabled
```

**Step F: forwarding safety net.** Each TXT-class `perform` first re-checks `responder`. If a text input is focused,
it forwards the standard text selector and returns:

| Key | Forwarded as |
|---|---|
| ⌘⌫ | `deleteToBeginningOfLine:` (or `delete:` when the selection is non-empty) |
| ⌘← | `moveToBeginningOfLine:` |
| ⌘→ | `moveToEndOfLine:` |
| F2, ⇧⌘M, ⌃⌘↑/↓ (non-editor text) | beep |

This keeps behaviour correct even if SwiftUI's enablement refresh lags one runloop behind the first responder.

**Keeping the inputs current.**
* `keyWin` and `keyWinIsSheetOrModal`: `NSWindow.didBecomeKey/didResignKey`, `willBeginSheet/didEndSheet`, and
  `NSApp.modalWindow`.
* `responder`: KVO on `firstResponder` of every AA window, and `NSTextView.didChangeSelectionNotification` for
  `hasSelection`.
* Undo titles: `NSUndoManager` `.didCloseUndoGroup`, `.didUndoChange`, `.didRedoChange`, `.checkpoint`.
* `list`: every focusable list attaches `.focused($isFocused)` and, on change, sets or clears `router.list` with an
  identity token, so a stale list cannot clear a newer one. Selection changes update `selectionCount`.
* `section`, `hierSelection`, `plannerMode`, `calendarFontScale`: pushed by the main window's root view on change.
* `safeMode`, `hasRepo`, `pendingUndoCount`: pushed by the shell after load, reload, delete and restore
  (`PendingUndoCount()` after every Trash mutation).

**Filter targets for Search Current List.**
* `keyWin == .main` → the focused vessel panel's search field (Work Orders, Ports) if focus is inside it, otherwise
  the table in SHELL-517.
* `.quickWork`, `.activityLog` → their filter field.
* `.search` → the query field.
* Anything else → nil.

**List roles.** The owner spec is authoritative for each caption and for whether a confirmation exists. The ✓ marks
were verified in this pass.

| Role | ⌘⌫ title → handler | plain ⌫/⌦ | ⌃⌘↑/↓ | ⇧⌘M | ↩ primary | Space / ⌘Y | ⌘X/C/V |
|---|---|---|---|---|---|---|---|
| hierarchySidebar (04) | Move to Trash → HIER-022 (confirm HIER-135 ✓) | yes | — | — | **Rename** | — | — |
| sectionList (03) | — | — | optional: reorder `TabOrder` (same result as a drag, SHELL-028) | — | — | — | — |
| crewRoster (09) | Move to Trash → crew delete (confirm ✓ `CrewPage.xaml.cs:386`) | yes | — | — | — | — | — |
| boardColumn (07) | Delete Task → VIEW-052 (confirm ✓) | yes | — | — | VIEW-049 editor | — | — |
| calendarTable (07) | — | — | — | — | VIEW-014 editor | — | — |
| builderItems: checklist / subtask / template (06) | Delete → BUILD-014 (confirm ✓) | yes | BUILD ↑/↓ | BUILD-013 `Move to...` | `Edit…` | — | — |
| savedLists (06, 02) | Delete → saved-list delete (confirm per 06) | per 06 | REPO-132 nudge (disabled with Sort A–Z, REPO-134) | REPO-133 / BUILD-087 `Move to position...` | per 06 | — | — |
| buckets (07) | Delete → bucket delete (confirm ✓ 07 §7.4) | yes | — | — | — | — | — |
| bucketMembers (07) | Remove from Bucket | per 07 | — | — | Open | — | — |
| fileBank (05) | Remove → CONT-088 (**no confirmation ✓**) | **no** | — | — | Open (CONT-089) | Quick Look | file clipboard (CONT-087) |
| viewerFiles (CONT-098) | — | — | — | — | Open | Quick Look | — |
| workOrders (10) | Delete (confirm ✓ 10 §6.7) | yes | — | — | — | Space = toggle Done (optional) | — |
| portsOfCall, quickCards (10) | Delete (per 10) | only if confirmed | — | — | per 10 | — | — |
| relationships, components, subtasks, steps in the item detail (04) | Remove (per 04) | only if confirmed | where ↑/↓ exist | where `Move to...` exists | Open / `Edit…` | — | — |
| quickWorkList (08) | Delete → QUICK-073 hard delete (confirm ✓) | yes | — | — | — | — | — |
| quickWorkChildren, crewChecklist, crewSchedule (08, 09) | Delete (per owner) | only if confirmed | where ↑/↓ exist | where present | `Edit…` | — | — |
| crewTableColumns (09) | — | — | ↑/↓ | — | — | Space toggles the check | — |
| trashTable (02) | handled in-sheet (SHELL-675) | no | — | — | — | — | — |
| searchResults, switcherResults (08) | — | — | — | — | navigate / open | — | — |

#### 6.5.1.11 Data formats

* **Nothing new is persisted.** The registry is code: one Swift table, `ShortcutRegistry.swift`, with one row per ID
  above. Each row holds `id`, `command`, the static `title`, `key`, `modifiers`, `aliases`, `menuPath`,
  `windowsGesture`, `scope`, `precedence`, `symbol` and `help`. This one table drives menu construction, the Keyboard
  Shortcuts window, toolbar help strings and the tests (§6.5.1.14).
* **Persisted side effects of commands.** These are unchanged and owned elsewhere:

  | Command | Written value |
  |---|---|
  | ⌘1…⌘9 and the View section items | `Ui.SelectedMainTabIndex` (in memory; written with the next save; no `MarkDirty`) |
  | section-list reorder | `Ui.TabOrder` + `MarkDirty` |
  | View ▸ Shortcut Bar | `Ui.ShowShortcutBar` + `MarkDirty` |
  | Customize Tab Colors… | `Ui.TabColors` |
  | Bigger/Smaller on Calendar | `Ui.CalendarFontScale` (11–28, steps of 1.5; for example `16.5`) + `MarkDirty` |
  | Dark Mode | settings `DarkMode` (it travels with Flash Sync) |
  | the other toggles | settings `SyncOnSave`, `TextOnlyExport`, `EncryptLocalData` |

* **Mac-only UI state stays out of the data files.** Toolbar visibility and customisation, sidebar visibility, the
  Keyboard Shortcuts window frame, and user overrides in `NSUserKeyEquivalents` all live in `UserDefaults` or are
  system-managed. They are **never** written to `data.json` or `settings.json`, so both files stay byte-compatible with
  Windows.

#### 6.5.1.12 Dependencies and Windows-only APIs

* **Calls into:** shell SHELL-040…102 handlers; 04 `beginRename`, `createNew`, `deleteItems`, `openInWindow`; 05
  editor commands (CONT-020…061) and file-bank handlers (CONT-082…093); 06 builder nudges and pickers; 07 VIEW-017,
  VIEW-052, VIEW-081; 08 window openers; 09 crew delete and import; 10 vessel panel import, export and delete; 11 PDF
  export; 12 SIRE body gate; 13 Flash Sync stop; 14 tool windows and Drive operations.
* **Windows-only mechanisms replaced:**

  | Windows mechanism | Mac replacement |
  |---|---|
  | WPF `Window.InputBindings` / `KeyBinding` / `CommandBinding` / `RoutedUICommand` (`ApplicationCommands.Save/Find/New/Open`, `NavigationCommands.Refresh`) | SwiftUI `Commands` + `.keyboardShortcut`, with enablement from CommandRouter |
  | `Window.PreviewKeyDown` tunnelling (Ctrl+1…9, F2, Ctrl+Z) | menu key equivalents + text-first disabling |
  | `IsDefault` / `IsCancel` | `.defaultAction` / `.cancelAction` |
  | access keys `_X`, Alt / F10 | none; ⌃F2 and Help search |
  | `MenuItem.InputGestureText` | `NSMenuItem` key-equivalent column |
  | RichTextBox `EditingCommands` gestures | NSTextView standard actions + the Format menu |
  | TabControl Ctrl+Tab | sidebar ↑/↓ |
  | ContextMenu key / Shift+F10 | ⌃-click |
  | `CommandManager.AddPreviewExecutedHandler` lock filtering | `shouldChangeText(in:replacementString:)` |

#### 6.5.1.13 macOS adaptation notes (implementation)

* **Build the menu bar in SwiftUI `Commands`:**
  * `CommandGroup(replacing: .appInfo)` for the About panel with credits.
  * `CommandGroup(replacing: .newItem)` for New {Kind} and Open in New Window.
  * `CommandGroup(after: .newItem)` for Rename, Quick Look and the Delete family.
  * `CommandGroup(replacing: .saveItem)` for Save, Save a Copy…, Reload, Import, Trash, Encrypt, Shared Save,
    Identity, the data-folder items, text-only, Google Drive and Flash Sync.
  * `CommandGroup(replacing: .importExport)` for Export as PDF….
  * `CommandGroup(replacing: .printItem)` for Print….
  * `CommandGroup(replacing: .undoRedo)` for Undo and Redo.
  * The **default** `.pasteboard` group is kept. It contains the standard nil-targeted Cut, Copy, Paste, Paste and
    Match Style, Delete and Select All, which already validate against NSTextView and SwiftUI
    `onCopyCommand`/`onCutCommand`/`onPasteCommand`/`onDeleteCommand`.
  * `CommandGroup(after: .pasteboard)` for Move Up, Move Down and Move To….
  * `CommandGroup(replacing: .textEditing)` for the Find submenu, **plus** re-adding the standard Spelling,
    Substitutions, Transformations and Speech submenus. `TextEditingCommands()` may be used if its Find items can be
    overridden; otherwise build Find explicitly.
  * `CommandMenu("Format")`, built explicitly (see §6.5.1.3).
  * `CommandGroup(before: .sidebar)` for the section items and Planner navigation. Add `SidebarCommands()` and
    `ToolbarCommands()`.
  * `CommandMenu("Tools")`.
  * `CommandGroup(replacing: .help)`.
* **Command code reads the router.** `Button(router.state(.x).title) { router.perform(.x) }.disabled(!router.state(.x).enabled)`.
  Key equivalents come from the registry table. Rebuild the View section group whenever `TabOrder` changes, so that
  ⌘1…⌘9 follow the order.
* **Hidden aliases and NSMenuItem-only properties** (`toolTip`, `badge`, `allowsKeyEquivalentWhenHidden`) come from a
  small AppKit bridge. After SwiftUI builds or rebuilds `NSApp.mainMenu` (observe `NSMenu.didAddItemNotification`
  and `didChangeItemNotification` on the main menu, debounced), find items by the registry's stable
  `NSUserInterfaceItemIdentifier`, set these properties, and re-insert missing aliases. SwiftUI may regenerate items
  at any time, so the bridge must be idempotent.
* **Rich-text views** (`AARichTextView: NSTextView`):
  * implement `validateUserInterfaceItem` for every Format item;
  * set `usesFindBar = true` and `isIncrementalSearchingEnabled = true`;
  * override `pasteAsPlainText(_:)` (CONT-034);
  * override `cancelOperation(_:)` (SHELL-514);
  * put **no** `performKeyEquivalent` overrides for app keys.
  
  The SIRE body subclass sets `writingToolsBehavior = .none` and allows only the B/I/U typing attributes.
* **Lists and tables:**
  * attach `.onDeleteCommand` only for roles with a confirmation;
  * make the main-window `List` publish `ListCommands` through the focus bridge;
  * use `.contextMenu(forSelectionType:menu:primaryAction:)` for ↩ and double-click, except in the hierarchy sidebar
    (X-8).
* **Sheets:** each decision sheet sets `.keyboardShortcut(.defaultAction)` and `.keyboardShortcut(.cancelAction)` on
  its buttons. Close-type sheets add a hidden `Button("") { close() }.keyboardShortcut("w")` so that ⌘W closes the
  sheet itself. It is in-view, so it wins inside the sheet (R-b).
* **The main window's root responder** is `NSHostingView` or the root `NSViewController`. It implements
  `noResponder(for:)` for ⌘Z to show `Nothing to undo.` (SHELL-521). It must **not** implement `undo:`, because
  `NSWindow` already routes `undo:` to the text view's undo manager and the router handles the rest.
* **Accessibility:** every command in this registry is reachable from the menu bar, which gives VoiceOver and Full
  Keyboard Access coverage. Key equivalents are announced automatically. No binding uses ⌃⌥, the VoiceOver modifier.
* **Performance:** the router's `state(_:)` is a pure O(1) function of cached inputs. Never walk views or models
  during menu validation. `pendingUndoCount` is recomputed only on Trash changes.

#### 6.5.1.14 Test vectors and verification

**Pure router tests.** Build a `CommandContext` and assert the `(enabled, title, action)` returned by
`state`/`resolve`.

| # | Context | Input | Expected |
|---|---|---|---|
| T-KB-01 | main, Tasks, `responder = .text(hasSelection: false)` | ⌘⌫ | DeleteFamily disabled. **Manual/UI:** the text deletes to line start, and no confirmation appears. |
| T-KB-02 | main, Tasks, sidebar list with 3 selected | ⌘⌫ | enabled, title `Move to Trash`; runs HIER-022 with the HIER-135 confirmation |
| T-KB-03 | main, Tasks, sidebar focused with 3 selected | plain ⌫ | same confirmation (onDeleteCommand) |
| T-KB-04 | item window, file bank with 2 selected | ⌘⌫ | `Remove`; no confirmation (CONT-088) |
| T-KB-05 | file bank focused | plain ⌫ | nothing happens (no onDeleteCommand) |
| T-KB-06 | Board, column focused, 1 card | ⌘⌫ | `Delete Task`; VIEW-052 confirmation, title `Confirm` |
| T-KB-07 | `responder = .richText(.container, …)` | ⌘F | the container's find bar opens. No Search window. |
| T-KB-08 | same | ⇧⌘F | a new Search window opens; the editor keeps its text |
| T-KB-09 | main, Tasks, sidebar focused | ⌘F | a new Search window (the Windows Ctrl+F) |
| T-KB-10 | main, Name field focused (`.text`) | ⌘F | a new Search window (Windows: Ctrl+F from a TextBox opened Search) |
| T-KB-11 | key window Search | ⌘F | its query field is focused and selected; no new window |
| T-KB-12 | main, Board | ⌥⌘F | focus moves to Board `Find`; the item is enabled |
| T-KB-13 | main, Calendar | ⌥⌘F | disabled |
| T-KB-14 | main, Vessels, focus inside Work Orders | ⌥⌘F | the Work Orders search field |
| T-KB-15 | `.richText(.container)` | ⌘Z after typing `abc` | title `Undo Typing`; the text is undone; Trash untouched |
| T-KB-16 | main, list focus, `pendingUndoCount = 0` | ⌘Z | item `Undo` disabled; status `Nothing to undo.` (root responder) |
| T-KB-17 | main, `pendingUndoCount = 1` | ⌘Z | `Undo Move to Trash`; the item is restored; status `Restored the last deleted item (⌘Z).` |
| T-KB-18 | main, batch of 7 | ⌘Z | `Undo Move to Trash (7 Items)`; status `Restored 7 deleted items (⌘Z).` |
| T-KB-19 | main, safe mode, `pendingUndoCount = 3` | ⌘Z | disabled |
| T-KB-20 | key window an item window, list focus | ⌘Z | the item window's own undoManager (disabled); the Trash is untouched |
| T-KB-21 | `.richText(.container)` | ⌘T | Show Fonts panel |
| T-KB-22 | main, Planner, no text | ⌘T | Show Fonts disabled, so a beep. ⇧⌘T → anchor = today, mode unchanged. |
| T-KB-23 | Planner Week, anchor 2026-09-30 | ⌘← / ⌘→ (each from 2026-09-30) | anchor 2026-09-23 / 2026-10-07. Month mode from 2026-01-31: ⌘→ gives 2026-02-28 (VIEW-081 `AddMonths` clamp). |
| T-KB-24 | hierarchy sidebar row focused | ↩ | Name field focused with all text selected. **No** item window opens. |
| T-KB-25 | hierarchy sidebar row | double-click | Open in New Window (HIER-110) |
| T-KB-26 | main, Calendar, `CalendarFontScale = 15` | ⌘+ ×9 | 16.5, 18, 19.5, 21, 22.5, 24, 25.5, 27, 28; then stays 28 (VIEW-017 C16) |
| T-KB-27 | Calendar, 12 | ⌘− | 11 (10.5 clamped) |
| T-KB-28 | container editor, selection at 14 pt | ⌘+ | the selection size increases by the step 05 defines; Calendar unchanged |
| T-KB-29 | container editor focused | ⌘R | the due-dates window opens; the paragraph alignment is unchanged |
| T-KB-30 | container editor focused | ⌘} | the paragraph is aligned right |
| T-KB-31 | container editor, caret in item 2 of a 3-item numbered list | ⌃⌘↑ | it becomes item 1; renumbered; the caret stays in the text |
| T-KB-32 | checklist builder, rows [2,3] selected of 5 | ⌃⌘↑ | rows move to [1,2] per BUILD ↑ semantics |
| T-KB-33 | Saved Lists with Sort A–Z on | ⌃⌘↑ / ⇧⌘M | disabled |
| T-KB-34 | Name field focused | ⇧⌘M / ⌃⌘↑ | disabled (TXT) |
| T-KB-35 | main, Tasks, editor focused | ⇧⌘N | the editor is flushed, then a new Task is created and its Name is focused (HIER-021, HIER-M04). Title `New Task`. |
| T-KB-36 | main, Calendar | ⇧⌘N | disabled, title `New Item` |
| T-KB-37 | editor focused | ⇧⌘7 / ⇧⌘9 / ⌘7 | bullets / numbering / **section 7** selected. ⌘7 switches section even while typing, as Windows Ctrl+7 did (SHELL-045). |
| T-KB-38 | a prompt sheet on main | ⌘S / ⌘1 / ⌘N | all disabled |
| T-KB-39 | the crew editor sheet is open | ⌘Q | quit cancelled; the sheet is brought to the front; beep; nothing is saved or discarded |
| T-KB-40 | builder sheet open | ⌘Q | the builder is closed (flushed); then the quit pipeline runs |
| T-KB-41 | AZERTY layout | ⌘1…⌘9, ⇧⌘7 | sections 1…9; bulleted list. No ambiguity. |
| T-KB-42 | numeric keypad | ⌘1 (keypad) | section 1 |
| T-KB-43 | main window | ⌘W | SHELL-056 pipeline runs; the app exits |
| T-KB-44 | main with a Prompt sheet | ⌘W | beep; the sheet stays; main stays |
| T-KB-45 | Checklist builder sheet | ⌘W / ⎋ | the sheet closes and its items are persisted |
| T-KB-46 | Flash Sync flashing | ⌘. / ⎋ | flashing stops; the window stays open |
| T-KB-47 | Flash Sync idle | ⎋ | nothing |
| T-KB-48 | Subtask editor sheet, caret in its rich text | ⎋ | the sheet closes; no completion popover |
| T-KB-49 | item window of an item that is not gated | ⌥⌘E | the PDF export flow for that item |
| T-KB-50 | main, hierarchy item detached into its own window | ⌥⌘E, ⌘P | disabled in the main window |
| T-KB-51 | main, gated item selected | ⌥⌘E | disabled |
| T-KB-52 | locked selection in the editor | ⌘S | saves (Windows showed the lock hint instead — SHELL-524) |
| T-KB-53 | SIRE body focused, text selected | ⌘⌫ / ⌘X / ⌫ | nothing changes (the gate); ⌘C copies |
| T-KB-54 | login phase | ⌘S / ⌘F / ⌘1 | disabled; ⌘Q quits (same as Exit) |
| T-KB-55 | Trash sheet, 2 selected | ⌘⌫ | Put Back → restored; Trash sheet row count −2 |
| T-KB-56 | Trash sheet | ⇧⌘⌫ | `Empty Trash` confirmation `Permanently remove all {n} item(s) in the Trash? This cannot be undone.` |
| T-KB-57 | quick switcher open | ⎋ / ↓ ↓ ↩ | closes / opens the 3rd result (index clamped) |
| T-KB-58 | View menu after dragging SIRE to first place | ⌘1 | SIRE is selected; the menu shows `SIRE 2.0 ⌘1` |

**Registry integrity tests.** These are unit tests over `ShortcutRegistry`:
* **Uniqueness.** Normalise every `(key, modifiers)`, including aliases, using SHELL-500's shift map. Assert that no
  two menu items collide. The known collision ⌘{ vs ⇧⌘[ must be caught if someone adds ⇧⌘[.
* **Reserved.** Assert that no row uses a SHELL-501 system, accessibility or service key.
* **Text safety.** Every row whose key is in the text-system binding set {⌘⌫, ⌘←, ⌘→, ⌘↑, ⌘↓, ⌥-arrows, ⌃⇥, ⎋,
  F2…} must have `precedence == .txt` or `.editor`.
* **Coverage.** Every Windows gesture in §6.5.1.3–6.5.1.4 has a row. Every `windowsGesture` string parses.
* **Strings.** The §6.5.1.9 table round-trips: feeding the Windows strings to `MacKeyStrings.render(_:)` yields the
  Mac column.
* **Menu snapshot.** An XCUITest walks `app.menuBars` and compares titles, order, separators and key-equivalent
  display strings with the §6.5.1.6 tree. It runs in the main phase, with no selection, in the Tasks section.

**Manual checks** (the target macOS version):
* Run System Settings ▸ Keyboard ▸ Keyboard Shortcuts and confirm that no enabled system or service shortcut equals a
  registry key.
* Turn on VoiceOver: ⌃⌘↑ still moves a list item, and VO navigation is unaffected.
* Turn on Accessibility Zoom keyboard shortcuts: ⌥⌘= zooms the screen, and no AA command fires.
* Set an App Shortcuts override for `Quick Work Window`: the override takes effect.
* Use a German keyboard: Format ▸ Lists ▸ Indent is typed as ⌘⌥6 and still works (Localization.automatic).

#### 6.5.1.15 Residual open questions

The registry already applies a default for each question below. They are recorded only in case the product owner
wants to flip one. Each flip is a one-row change in `ShortcutRegistry`.

* **Q-KB-1.** ⌘F inside a note finds in the note (default) instead of opening global search. If Windows switchers
  complain, the alternative is "⌘F always global, ⌥⌘F Find in Note", and Search Current List would then lose ⌥⌘F.
* **Q-KB-2.** ⌘W on the main window quits (default, faithful). The alternative is Mail-style hide-on-close with Dock
  or MenuBarExtra reopen. That needs a rethink of the SHELL-056 on-close shared push, and of the login per launch.
* **Q-KB-3.** Plain ⌫/⌦ in lists that confirm (default: on). The alternative is ⌘⌫ only, like Finder.
* **Q-KB-4.** Ship the optional File ▸ Print… (⌘P), File ▸ Shared Save ▸ Check Shared Save Now, and the section-list
  ⌃⌘↑/↓ reorder in v1? Default: Print and Check Now yes, section reorder yes.
* **Q-KB-5.** If the optional SIRE commands (12:959) are wanted later, give them keys? Default: menu only, no keys.
