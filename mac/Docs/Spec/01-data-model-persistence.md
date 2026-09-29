# 01 — Data Model & Persistence (`DATA-`)

> **Porting spec — AA (Windows WPF, .NET 10, C#) → native macOS (Swift 6.4, SwiftUI + AppKit, macOS 26+).**
> This document is the contract for the Swift implementation and for later verifiers. It describes what the
> Windows build *actually does today* (commit `37cdab0`, branch `mac-port`), including quirks and bugs, and
> says explicitly where the Mac port should deviate.
>
> **Subsystem:** the in-memory data model (`AA/Models`), its JSON persistence (`data.json`, `settings.json`),
> the data folder and attachment store, bundle (`.zip` / `.aaz`) export/import, the shared save file
> (multi-instance sync), local at-rest encryption, the app password and its `enc:` blob format, per-item
> password locks, the change-preview diff model, the Trash / activity-log / recurrence rules that live on the
> repository, and application startup (splash, login gate, crash log).

## 0. Conventions used in this spec

| Marker | Meaning |
|---|---|
| **MUST** | Required for data compatibility or feature parity. A verifier fails the port if violated. |
| **SHOULD** | Strongly recommended; deviation needs a written reason. |
| **[FAITHFUL]** | Reproduce the Windows behaviour exactly, even if it looks odd. |
| **[DEFECT]** | A real bug found in the Windows code while writing this spec. The spec states the Windows behaviour and a recommendation. Unless a note says "Mac MUST replicate", the Mac port SHOULD fix it — *without* changing the on-disk format. All defects are collected in §8. |
| **[MAC]** | A Mac-specific adaptation (no Windows equivalent, or the Windows mechanism is impossible on macOS). |
| `file.cs:NNN` | Line numbers refer to `/Users/eriskay/erisdev/AA/AA/<file>` at commit `37cdab0`. |
| "status line" | The one-line status text in the main window header (`MainWindow.StatusBlock`). The Mac equivalent is owned by the main-window spec; this spec only supplies the strings. |

Exact user-visible strings are quoted in `"double quotes"` with C# escapes (`\n` = newline). Where the
Windows string contains a Unicode glyph (`—`, `▸`, `＋`, `“ ”`, `⚠`, `🔗`) the Mac string MUST use the same glyph.
Where the Windows string names a Windows concept ("Windows DPAPI", "Windows account", "Explorer", "PC"), §6
gives the Mac wording.

Sources read completely for this spec: `Models/Models.cs`, `Models/CrewMember.cs`, `Services/DataStore.cs`,
`Services/DpapiDataStore.cs`, `Services/Dpapi.cs`, `Services/PasswordService.cs`, `Services/ItemLockService.cs`,
`Services/DataDiff.cs`, `App.xaml.cs`, `AssemblyInfo.cs`, `.gitignore`, `Services/AppRepository.cs`,
`MainWindow.xaml.cs` (all persistence, shared-save, safe-mode, import/export, encryption, password paths),
`MainWindow.xaml` (File/Tools/View menus), `Views/DiffWindow.xaml(.cs)`, `Views/TrashWindow.xaml(.cs)`,
`Views/LoginWindow.xaml(.cs)`, `Views/SplashWindow.xaml(.cs)`, `Views/PasswordWindow.xaml(.cs)`,
`Views/ItemLockWindow.xaml(.cs)`, the lock handlers in `Views/HierarchyPage.xaml.cs`, `Views/ContainerEditor.xaml.cs`
(load/persist/enc paths), `Sire/SireState.cs`, `Sire/SireModels.cs`, `FlashSync/FlashSyncStore.cs`,
`FlashSync/FlashChangeSet.cs` (equality + per-device keys), `Services/ChecklistTemplateService.cs`
(container clone), `Services/ScheduleService.cs` (export format), `Services/GoogleDriveUploader.cs` (token store,
bundle names), `PROGRESS.md` (all persistence-related sections), `QR_SYNC_PROTOCOL.md` §10.

---

## 1. Overview

### 1.1 Purpose

AA keeps **one database** — a single JSON document, `data.json` — that holds every Equipment/Area, Task,
Procedure, Vessel, crew member, saved list, bucket, port, schedule template, SIRE session state, the Trash,
the activity log and the persisted UI state. Attachments are **not** inside the JSON: imported copies live as
files in a sibling `files/` folder and are referenced by relative path (`files/<guid>_<name>`); "live" links
reference an absolute path elsewhere; web links are URLs.

A second JSON file, `settings.json`, holds **per-machine** settings (active data file path, password hash/salt,
dark mode, sync/shared-save paths, identity, API key…). It never travels inside bundles.

Everything the user can do to "move" data goes through this subsystem:

* **autosave** (debounced 750 ms, written off the UI thread, atomically), explicit **Save** (Ctrl+S),
  periodic 5-minute autosave, save on close;
* **Save As** (JSON copy), **Import from file** (JSON), **Reload from disk**;
* **bundles** — a ZIP (extension `.zip` or `.aaz`, identical format) of `data.json` + `files/` + `source.json`,
  used by *Export/Import data folder*, the Google Drive paths and the **shared save file**;
* the **shared save file** — one bundle on a network/synced folder that several AA installations push to and
  pull from, with file watching, polling and a persistent health indicator;
* **Flash Sync** (QR transfer) enters through `DataStore.ApplySyncedData` (the protocol itself is another spec);
* a **change preview** (`DataDiff`) shown before *every* overwrite;
* optional **local at-rest encryption** of `data.json` (Windows DPAPI);
* the **app password** (PBKDF2 hash in settings; legacy `enc:` AES blobs in container bodies);
* **per-item password locks** (PBKDF2 hash on the item; UI gate, not encryption).

Data compatibility with the Windows app (and with the iOS app, which reads/writes the same `data.json`
and `.aaz` bundles) is the overriding requirement: a user must be able to move a database between Windows,
macOS and iPhone in any direction without loss.

### 1.2 Where it sits in the app

| Entry point (Windows) | What it reaches in this subsystem |
|---|---|
| App start (`App.OnStartup`) | `DataStore.LoadSettings`, theme, splash (2.4 s), login gate, then `MainWindow` → `LoadDataAndInitUi` → `DataStore.Load` |
| **File** menu | Save (Ctrl+S), Save As…, Reload from disk, Import from file…, Trash…, Encrypt local data file (this PC), Set shared save file…, Stop shared save file, Set app identity…, Open data folder, Export data folder (ZIP)…, Import data folder (ZIP)…, Export text only (no attachments), Google Drive items (Drive spec), Flash Sync (Flash Sync spec), Exit |
| **Tools** menu | Set / change password…, Lock now |
| Header | Save button, shared-save indicator (`SharedStatusBlock`), status line |
| Keyboard | Ctrl+S (save), Ctrl+Z (undo last delete, only when no text box has focus) |
| Timers | 750 ms debounce (repository), 5 min autosave + Drive check, 1 min shared push, 60 s shared poll, 1.5 s watcher debounce |
| Every item page | `MarkDirty()` after edits; `ItemLockService` gate; Trash on delete |
| Every import path (JSON, ZIP, Drive, shared, Flash Sync) | `DataDiff.Compare` + `DiffWindow` (except the shared-save auto-pull, which prompts only when there are unsynced local edits, and Flash Sync, which has its own review) |

### 1.3 Component map

| Windows component | Role | Mac component (recommended) |
|---|---|---|
| `Models/Models.cs`, `Models/CrewMember.cs`, `Sire/SireState.cs` | Model classes (`INotifyPropertyChanged`) | Swift `@Observable final class` per model type, same property names; `@MainActor` |
| `DataStore` (static) | Paths, settings, load/save, atomic write, bundles, encryption, path normalisation | `DataStore` (actor for I/O) + `SettingsStore` + `BundleService` + `AttachmentStore` |
| `AppRepository` | Debounced autosave, ordered write chain, lookups, relations, trash, log, recurrence | `AppRepository` (`@MainActor @Observable`), owns the model graph and a `PersistenceWriter` actor |
| `System.Text.Json` (`DataStore.Opts`) | Serialisation | Hand-written ordered JSON parser/writer emulating System.Text.Json (see §4.1, §6.3) |
| `Dpapi` / `DpapiDataStore` | Windows DPAPI | Keychain-held AES-GCM key [MAC] |
| `PasswordService` | App password + `enc:` blobs | `PasswordService` using CommonCrypto (PBKDF2, AES-CBC) + CryptoKit (HMAC) |
| `ItemLockService` | Per-item PBKDF2 locks | `ItemLockService` (same algorithm) |
| `DataDiff` + `DiffWindow` | Change preview | `DataDiff` (pure Swift) + SwiftUI sheet with `OutlineGroup` |
| `FileSystemWatcher` + `DispatcherTimer` | Shared-save watching | `DispatchSource` directory watcher + `Task`-based timers [MAC] |
| `System.IO.Compression.ZipFile` | Bundles | ZIP reader/writer (ZIPFoundation or in-house on Apple `Compression`) [MAC] |
| `App.xaml.cs` | Startup, crash log | `@main App` + `NSApplicationDelegate` |

---

## 2. Feature checklist

Each feature has a stable ID. "Persisted" says what reaches disk and when.

### A. Startup & application shell

**DATA-001 — Splash screen.** On every launch a borderless, centred, always-on-top window shows the bundled
image `Assets/Splash.png` (`SizeToContent`, white background). If the image resource is missing a text fallback
is shown: `"AA"` (128 pt bold, black), `"A tool for Active minds"`, `"Created by B.E.P Avida"`, `"May 2026"`
(each 28 pt italic, black). After **2.4 s** (`DispatcherTimer`) the splash closes and the login gate opens
(`App.xaml.cs:36`). Nothing is loaded from `data.json` while the splash shows; settings and the theme already are.

**DATA-002 — Login gate.** A modal window titled `"AA — Sign in"` (420×280) with header `"AA"` (28 pt bold,
accent colour), subtitle `"Please sign in to continue"`, labels `"Username"` / `"Password"`, error text
(red `#D45050`), buttons `"Exit"` and `"Sign in"` (default). Credentials are **hard-coded**: username `44233`
(input trimmed, ordinal compare) and password `redemption` (ordinal, not trimmed) (`LoginWindow.xaml.cs:12-13`).
Enter in the password box submits. Username box focused on open. Wrong credentials → error
`"Incorrect username or password."`, password box cleared and focused. `"Exit"` or closing the window quits the
app (`App.ContinueToMain`: `ShowDialog() != true → Shutdown()`). This is a basic gate, not security; the data
file is not encrypted by it. [FAITHFUL]

**DATA-003 — Settings and theme load before any window.** `DataStore.LoadSettings()` then
`ThemeManager.Apply(DataStore.DarkMode)` run in `OnStartup` before the splash (`App.xaml.cs:25-26`), so the
splash/login already use the saved theme. `ShutdownMode` is `OnExplicitShutdown` while only the login is open,
then `OnMainWindowClose` once `MainWindow` is shown — closing the main window quits the app.

**DATA-004 — Crash reporting.** Unhandled dispatcher exceptions and `AppDomain` unhandled exceptions are
appended to `<AppFolder>/crash.log` as `"[yyyy-MM-dd HH:mm:ss] {exception.ToString()}\r\n\r\n"` (local time)
and shown in a message box titled `"AA — error"`:
`"AA hit an unexpected error and had to stop:\n\n{ex.Message}\n\nThe full details were written to:\n{path}"`
(Error icon). Dispatcher exceptions are then marked **handled** (the app keeps running despite the wording).
Unobserved task exceptions are silently observed. Any failure while reporting is swallowed.

**DATA-005 — Window/app lifetime.** Closing the main window runs the close sequence (DATA-028, DATA-055) and
quits the app. File ▸ `"E_xit"` = close the main window.

### B. Data folder

**DATA-010 — Data folder location.** `AppFolder` = the value of environment variable **`AA_DATA_DIR`** if it
is set and not blank/whitespace, else `%LOCALAPPDATA%\AA` (`DataStore.cs:32`). Created on demand everywhere.
Derived paths: `FilesFolder = AppFolder/files`, `DefaultDataFile = AppFolder/data.json`,
`SettingsFile = AppFolder/settings.json`, `GoogleClientSecretFile = AppFolder/google_client_secret.json`,
`GoogleTokenFolder = AppFolder/google-token`.

**DATA-011 — Data folder contents.** See §4.12 for the full inventory (`data.json`, `settings.json`, `files/`,
`crash.log`, `google_client_secret.json`, `google-token/`, `qrsync-baseline.json`, `qrmodels/`, transient
`*.tmp`).

**DATA-012 — Open data folder.** File ▸ `"Open data _folder"` launches `explorer.exe <AppFolder>`; on error a
message box `"{ex.Message}"` titled `"Open failed"`.

**DATA-013 — Active data file.** `DataStore.CurrentDataFile` is the JSON file the app loads and saves. Default
`AppFolder/data.json`. *Import from file…* (DATA-034) repoints it at the chosen external `.json`; the choice is
persisted in `settings.json` (`CurrentDataFile`). On the next launch the persisted path is used **only if that
file exists**; otherwise the default is used silently (`DataStore.cs:125`). Every bundle import and Flash Sync
apply resets it to the default. Attachments are always resolved against `AppFolder`, never against the active
file's folder.

### C. Load, save, autosave, safe mode, schema

**DATA-020 — Load on startup.** `LoadDataAndInitUi` (`MainWindow.xaml.cs:1173`): `LoadSettings()` →
`DataStore.Load()` → detach the previous repository (if any) → new `AppRepository(data)` → safe-mode flag from
`DataStore.LastLoadFailed` → subscribe `Saved` → rebuild all pages and restore UI state (DATA-035) → update the
shared indicator → status line `"Loaded — {CurrentDataFile}"` (or the safe-mode text below). `Load()` returns an
empty `AppData` when the file does not exist (correct: first run). See §3.2 for the algorithm.

**DATA-021 — Read-only safe mode.** If the data file **exists but cannot be read or parsed** (locked,
mid-write, corrupt JSON, undecryptable DPAPI blob, any exception) `Load()` returns an empty model and sets
`LastLoadFailed = true`. The app then:
* sets `AppRepository.SuspendSaving = true` (all `MarkDirty`/`Save` calls become no-ops);
* shows at startup (Warning) titled `"Data file unreadable — safe mode"`:
  `"Your data file is present but could not be read — it may be locked by another program, still being written, corrupt, or (if you enabled local encryption) created under a different Windows account.\n\nAA opened in READ-ONLY safe mode and will NOT save over it, so nothing already on disk is lost. Close AA, restore a copy if needed (File ▸ Trash or a backup), then reopen."`;
* status line `"⚠ Data file unreadable — read-only safe mode (not saving)."`;
* Ctrl+S / File ▸ Save shows (Warning) titled `"Safe mode — not saving"`:
  `"AA is in read-only safe mode because the data file couldn't be read at startup, so saving is disabled to protect the file on disk. Close and reopen AA once the file is available."`;
* autosave does nothing; Ctrl+Z undo is ignored; toggling encryption shows `"Can't change encryption in read-only safe mode."` titled `"Safe mode"` and reverts the checkbox;
* on close: no save, no shared push;
* startup housekeeping (trash prune, recurrence reconcile, daily digest, reminders) is skipped.
Safe mode ends only by a later successful load (reload, import) — e.g. *Import from file* sets it false.
[DEFECT D-12: the shared-save auto-pull can still overwrite the unreadable file.]

**DATA-022 — Schema version & newer-file warning.** `AppData.SchemaVersion` (int). `CurrentSchemaVersion = 1`
(`DataStore.cs:284`). On `Load()`, if the file's version > 1, `LoadedNewerSchema = version` and (only when not in
safe mode) the app shows (Information) titled `"Newer data format"`:
`"This data file was saved by a newer version of AA (format v{v}; this build understands v1).\n\nYou can keep working — newer fields are preserved — but update AA on this PC to avoid missing new features' data."`.
Every save stamps `SchemaVersion = 1` **only if the current value is lower** — a higher value is never
downgraded. A file with no `SchemaVersion` key reads as 0 (legacy). The Mac build MUST use the same number
space and MUST NOT bump the version unless Windows bumps it in lockstep.

**DATA-023 — Migration v0 → v1.** When `SchemaVersion < 1` on any load (`Load` and `LoadFrom`), every
already-completed recurring task (recursively including subtasks: `Recurrence != None && IsComplete`) and every
recurring procedure with `Status == Done` gets `RecurrenceSpawned = true`, so upgrading does not retroactively
spawn a backlog of occurrences (`DataStore.cs:325`).

**DATA-024 — Forward-compatible unknown keys.** Unknown JSON members are captured and re-written on save at
three places only: **top level of `data.json`** (`AppData.ExtraData`), **inside `Ui`** (`UiState.ExtraData`),
and **top level of `settings.json`** (`Settings.ExtraData`). Unknown members anywhere else (inside items,
containers, `Sire`, …) are **dropped** by Windows. The Mac port MUST preserve at those three places and
SHOULD preserve unknown members at every object level (a strict superset — harmless to Windows, and it matches
what iOS does: "including an unmodelled Windows-only key nested inside a new item", QR_SYNC_PROTOCOL §14).

**DATA-025 — Debounced autosave.** Any edit calls `AppRepository.MarkDirty()`: sets dirty and (re)starts a
**750 ms** one-shot timer. When it fires (`BackgroundSaveIfDirty`, `AppRepository.cs:42`): stamp
`LastModified = DateTime.Now`, clear dirty, serialise **on the UI thread** (consistent snapshot), then write on a
background thread through an **ordered write chain** (each write awaits the previous one, so the newest
snapshot always lands last). On serialisation failure: restore the previous stamp, keep dirty, stop. On write
failure: restore the previous stamp and set dirty again (retried by the next edit/tick). On success raise
`Saved`. No status-line text for debounced saves.

**DATA-026 — Periodic autosave (5 min).** A 5-minute timer runs `DoAutosave()` then the Google Drive
"newer save" check (Drive spec). `DoAutosave` (`MainWindow.xaml.cs:252`): return if no repo or safe mode; flush
pending rich-text editors of the four hierarchy pages; if not dirty → status `"Autosave — no changes (HH:mm:ss)"`;
else capture UI state, `Save()`, status `"Autosaved HH:mm:ss"`; on exception → `"Autosave failed: {message}"`.

**DATA-027 — Explicit Save (Ctrl+S / File ▸ `"_Save"` / header Save button).** `DoSave`
(`MainWindow.xaml.cs:328`): safe mode → message (DATA-021). Else flush the four pages' editors, capture UI
state, `AppRepository.Save()` (always writes, even if not dirty), status `"Saved HH:mm:ss"`, then queue a Google
Drive push if *Sync to Google Drive on save* is on (Drive spec, 1.5 s debounce). On exception → message box
`"{ex.Message}"` titled `"Save failed"` (Error).

**DATA-028 — Save on close.** `OnClosing` (`MainWindow.xaml.cs:144`): stop shared-save timers/watcher; dispose
tray icon; if safe mode → stop here; flush and close every detached item window; flush all editors (including
SIRE body and item windows); capture UI state; `Save()` (errors ignored); then the shared-bundle push rule
(DATA-055).

**DATA-029 — Atomic, durable writes.** Every data-file write goes through `AtomicWrite`
(`DataStore.cs:439`): temp file `"{path}.{guid:N}.tmp"` in the same directory, written with exclusive access and
**flushed to disk** (`Flush(flushToDisk: true)` = FlushFileBuffers) before the swap; if the target does not exist
`File.Move(tmp, path)`; else `File.Move(tmp, path, overwrite: true)`; on `IOException`/`UnauthorizedAccessException`
fall back to `File.Replace(tmp, path, null, ignoreMetadataErrors: true)`; if that also fails
(`IOException`/`UnauthorizedAccessException`/`PlatformNotSupportedException`) fall back to a plain
`File.Copy(tmp, path, overwrite: true)`. The temp file is always deleted in `finally`. Exceptions from the
first move/replace chain propagate to the caller. A reader (another AA instance) never sees a torn file.

**DATA-030 — Compact JSON.** `data.json`, `settings.json` and `source.json` are written **without
indentation** (measured 5× faster saves, 35% smaller files on large ship imports). UTF-8, **no BOM**.

**DATA-031 — `LastModified` stamping.** `AppData.LastModified` (local time with offset) is stamped `= DateTime.Now`
by `AppRepository.Save()` and by the debounced background save, by *Save As*, and by the encryption toggle.
`DataStore.Save/SaveTo/WriteData` never stamp. Imports adopt the incoming stamp unchanged (no re-stamp) — this
is what makes the shared-save "already seen" check work. Flash Sync's applier re-stamps (Flash Sync spec).

**DATA-032 — Save As (JSON copy).** File ▸ `"Save _As..."`: save dialog filter
`"AA data (*.json)|*.json|All files (*.*)|*.*"`, default name `"aa-data.json"`, initial folder `AppFolder`.
On OK: capture UI state, set `LastModified = DateTime.Now` (in memory only; not marked dirty),
`DataStore.SaveTo(data, path)` = normalise attachment paths + atomic **plaintext** write (never encrypted, no
schema stamp). Status `"Exported to {path}"`. The active data file does **not** change. Error →
`"{message}"` titled `"Save As failed"`.

**DATA-033 — Reload from disk.** File ▸ `"_Reload from disk"`: confirm (Warning, Yes/No) titled
`"Confirm reload"`: `"Reload data from disk? Unsaved changes will be lost."`. Yes → `LoadDataAndInitUi()`,
status `"Reloaded HH:mm:ss"`. Note `LoadSettings()` inside it also re-locks the app-password session (DATA-081).

**DATA-034 — Import from file (JSON).** File ▸ `"_Import from file..."`: open dialog filter
`"AA data (*.json)|*.json|All files (*.*)|*.*"`, initial folder `AppFolder`. `DataStore.LoadFrom(path)` (throws on
any read/parse error → message `"{message}"` titled `"Import failed"`). Then the change preview (DATA-100) with
source name = file name and incoming stamp = its `LastModified`. On confirm: detach the old repository, create a
new one over the imported data, leave safe mode, rebuild pages, **set the chosen file as the active data file**
(persisted), then `DataStore.Save(data)` — which rewrites *the chosen file itself* (normalised paths, schema
stamp; encrypted only if it lies inside `AppFolder` and encryption is on). Status `"Loaded — {path}"`.
Errors → `"Import failed"`.

**DATA-035 — UI state persistence & restore.** Persisted in `AppData.Ui` (§4.2.20), captured by
`CaptureUiState` (`MainWindow.xaml.cs:1383`) before every explicit/periodic/close save and before exports:
window Left/Top/Width/Height **only when the window state is Normal**, window state name, selected main-tab
index, selected item per hierarchy page, calendar date and view mode, relationship-map focus. Restore rules
(`InitPagesAndRestoreUi`, `MainWindow.xaml.cs:1222-1244`): width/height applied only if **> 200**; left/top
applied unconditionally; window state parsed by name (`"Normal"`, `"Maximized"`; `"Minimized"` restores as
Normal); selected items re-selected by id; main tab index applied only if in range; shortcut-bar visibility;
tab order (DATA-035a) then tab colours. Many other `Ui` keys are owned by other pages (see §4.2.20).
* **DATA-035a Tab order** — `Ui.TabOrder` = list of tab identifiers (§4.2.20). Tabs not listed keep their
  relative order after the listed ones; duplicates/unknown names ignored. [DEFECT D-15: index restored before order.]

**DATA-036 — Repository swap on reload.** Every reload/import creates a **new** repository and model graph;
the old repository is `Detach()`ed: saving suspended, its debounce stopped, its `Saved` subscribers dropped —
so a stale timer can never write discarded data over the freshly loaded file. All open auxiliary windows are
re-pointed to the new repository; detached item windows re-resolve their item **by id** (a reload replaces
every object).

### D. Bundles (`.zip` / `.aaz`)

**DATA-040 — Export data folder.** File ▸ `"_Export data folder (ZIP)..."`: save dialog filter
`"AA bundle (*.zip)|*.zip|AA bundle (*.aaz)|*.aaz|All files (*.*)|*.*"`, default name
`"aa-data-{yyyyMMdd-HHmm}.zip"` (local time). On OK: capture UI state, `Save()` (stamps), then
`ExportFolderToZip(path)` honouring the text-only toggle. Status `"Exported data folder to {path}"`; error
`"Export failed"`. Destination inside `AppFolder` is refused with `IOException("Choose a destination outside the AA data folder.")`.

**DATA-041 — Bundle layout & source stamp.** A bundle is a ZIP (Deflate, "Optimal") of a staging folder
containing: `data.json` (the **plaintext** active data file as currently on disk — decrypted if encrypted;
falls back to `AppFolder/data.json` if the active file is missing; omitted if neither exists), `files/` (a
recursive copy of `AppFolder/files`, only when attachments are included) and `source.json` (the
`BundleSource` stamp: identity, machine, UTC write time, the data's `LastModified`, `DataOnly`). No
`settings.json`, no Google secrets/tokens, no baseline. See §4.5.

**DATA-042 — Export text only (no attachments).** File ▸ `"Export _text only (no attachments)"` (checkable,
persisted per machine as `TextOnlyExport`). Tooltip: `"When on, exports and Google Drive saves carry only your
text, changes and formatting — not the attached files. Much smaller and far quicker over a slow link. Importing
one leaves the attachments already on the other PC exactly as they are."` Status on toggle:
`"Exports carry text only (no attachments)"` / `"Exports carry everything, attachments included"`. Governs
**every** bundle writer (Export data folder, shared save, Drive synced folder, Drive OAuth upload, Drive sync
push): with it on, `files/` is omitted and `source.json` has `"DataOnly":true`.

**DATA-043 — Import data folder (smart import).** File ▸ `"I_mport data folder (ZIP)..."`: open dialog filter
`"AA bundle (*.zip;*.aaz)|*.zip;*.aaz|All files (*.*)|*.*"`. Preview = `PeekZipData` + change preview
(DATA-100; source name = file name). On confirm `DataStore.ImportBundleSmart(path)` (§3.10) then
`LoadDataAndInitUi()`. Status `"Imported {name} (text only — your attachments are untouched)"` or
`"Imported {name} (with attachments)"`. Error → `"Import failed"`. Keeps this machine's settings, password and
Google state (no folder wipe).

**DATA-044 — Data-only bundles never sweep attachments.** A bundle is *data-only* if its `source.json` says
`"DataOnly": true` **or** it has **no** `files/` directory at all (how iOS `-dataonly-` bundles and older
text-only bundles look). Importing one never deletes a local attachment. An **empty** `files/` directory is
*not* data-only: it means "the sender has no attachments", and the orphan sweep then removes local attachments.
(PROGRESS: this guard fixed a data-loss bug.)

**DATA-045 — Attachments-unchanged fast path.** Smart import compares the bundle's `files/` with the local
`files/` (same set of top-level file names, case-insensitive, each with the same byte size). If identical (or the
bundle is data-only) only `data.json` is applied (`ImportKind.DataOnly`); otherwise attachments are synced
additively then orphans are swept (`ImportKind.WithAttachments`).

**DATA-046 — Peek without extracting.** `PeekZipLastModified(zip)`, `PeekFileLastModified(json)`,
`PeekBundleSource(zip)`, `PeekBundleIdentity(zip)`, `PeekZipData(zip)` read single entries/fields for previews
and freshness checks; all return null on any failure. §3.9.

**DATA-047 — Legacy full-wipe ZIP import (`ImportFolderFromZip`).** Still present but **no longer called**
(File ▸ Import data folder uses the smart importer). Wipes every file/dir in `AppFolder` (preserving Google
client secret + token), extracts the ZIP over it, deletes any extracted `settings.json`, resets the active file,
migrates absolute paths, rewrites. The Mac port need not expose it; if ported, only as an internal utility.

**DATA-048 — App identity.** File ▸ `"Set app _identity..."` — prompt titled `"App identity"`:
`"Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save:"`,
pre-filled with the current identity. Blank → resets to the machine name; otherwise trimmed. Persisted per
machine (`AppIdentity`). Window title = `"AA — {identity}"`. Status `"App identity set: {identity}"`. Tooltip:
`"Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save. Always editable; defaults to the PC name."`.
Stamped into `source.json` (`Identity`, and `Machine` = real machine name) and into Drive file properties /
backup file names (Drive spec).

**DATA-049 — Apply synced data (Flash Sync entry point).** `DataStore.ApplySyncedData(json)`: point the
active file at the default, write the JSON through the local encryption policy, `LoadFrom`, migrate legacy
absolute paths, re-serialise and write again, persist settings, return the loaded model. Never touches
`files/`. The caller must already have shown the user what will change.

### E. Shared save file (multi-instance sync)

**DATA-050 — Set shared save file.** File ▸ `"Set s_hared save file..."`. Tooltip: `"Use ONE save file at a
location you choose (e.g. a network drive or a synced folder). AA autosaves there every 10 minutes and
auto-reloads when another copy of AA updates it — point every PC at the same file to keep them in sync."`
(stale "10 minutes": the real cadence is 1 minute — [DEFECT D-9]). Save dialog titled
`"Choose the single shared save file (put it on a network drive or synced folder). It bundles your data AND attachments."`,
filter `"AA shared save (*.zip;*.aaz)|*.zip;*.aaz|All files (*.*)|*.*"`, default name `"aa-shared.zip"`,
no overwrite prompt. Then flush editors and:
* file **exists** → Yes/No/Cancel (Question) titled `"Shared save file"`:
  `"'{fileName}' already exists.\n\nUse ITS contents (data + attachments) as your data (Yes), or keep your current data and overwrite it (No)?"`
  — Cancel aborts; Yes: persist path, `ImportSharedBundle(path)`, reload UI, mark in-sync; No: persist path,
  push our data (DATA-052 synchronous variant);
* file **absent** → persist path, push our data (creates the bundle).
Then start sync (timers + watcher), status `"Shared save file set — {path}"`, information box titled
`"Shared save file"`: `"This copy of AA now saves to and syncs from:\n\n{path}\n\nIt bundles your data AND all attachments, autosaves there every 10 minutes, and reloads automatically when another copy of AA updates it. Point every PC at this same file."`
On any exception: clear the setting, error box `"{message}"` titled `"Set shared save file failed"`.
The shared file is a **sync target**, not the active data file: AA always works on its local `data.json`.

**DATA-051 — Stop shared save file.** File ▸ `"Stop shared save file"` (tooltip `"Go back to saving locally on
this PC only."`). If none set → status `"No shared save file is set."`. Else confirm (Question, Yes/No) titled
`"Stop shared save file"`: `"Stop using the shared save file and save locally on this PC only from now on?\n(Your current data is kept.)"`
→ stop timers/watcher, clear setting, hide indicator, status
`"Stopped using the shared save file (now saving locally)."`.

**DATA-052 — Periodic push (every 1 minute).** `SharedSaveTick` (`MainWindow.xaml.cs:991`): skip if no repo, no
shared file, or an update is being handled. First run the update check (DATA-053/054) so a newer bundle is
adopted before we write; flush editors; **only if the repository is dirty** push in the background: flush,
capture UI state, `Save()`, build the bundle into `"{sharedPath}.{guid:N}.tmp"` on a background thread,
`File.Move(tmp, sharedPath, overwrite: true)`, record the pushed stamp as both "last seen" and "last synced",
status `"Shared save written HH:mm:ss (data + attachments)."`, indicator healthy. Failure → status
`"Shared save failed: {message}"` and indicator "NOT SAVING". A running guard prevents overlapping pushes.
[DEFECT D-1: the dirty flag is almost always already cleared by the 750 ms autosave, so this push rarely fires.]

**DATA-053 — External update detection.** While a shared file is set: a `FileSystemWatcher` on the bundle's
directory filtered to the bundle's file name (LastWrite | Size | FileName | CreationTime; Changed/Created/
Renamed) → 1.5 s debounce → check; plus an unconditional **60 s poll** (reliable on network/synced folders
where watcher events are missing). The watcher is best-effort (creation failure ignored).

**DATA-054 — Reload policy.** `CheckSharedFileForUpdate` (`MainWindow.xaml.cs:1057`, §3.12): folder
unreachable → OFFLINE; bundle absent → healthy (nothing to pull); stamp unreadable → try later; bundle not
newer than local `LastModified` → nothing; bundle stamp equals the last seen/declined stamp → nothing. Otherwise,
if there are **unsynced local changes** (dirty, or local stamp newer than the last pushed/pulled stamp) ask
(Question, Yes/No) titled `"Shared save updated"`:
`"The shared save file was updated by another copy of AA.\n\nReload it now (data + attachments)? Changes on this PC that aren't in the shared file yet will be lost.\n\nYes = reload (discard my changes)\nNo = keep mine (they overwrite the shared file on the next save)"`.
No → remember this bundle stamp as declined. Yes / no local changes → `ImportSharedBundle` + reload UI
**silently**; status `"Reloaded the shared save from “{identity}” (HH:mm:ss)."` (or without the `from “…”`
part when the bundle has no identity). Exceptions (locked/torn bundle) → status
`"Shared reload skipped (busy): {message}"` and nothing local changes.

**DATA-055 — Push on close.** After the close-save: if a shared file is set, push synchronously when the
bundle does not exist, **or** it exists, its stamp is readable, and (local stamp is null or local ≥ bundle
stamp). If the bundle exists but its stamp can't be read, do **not** push. Label `"Shared save (on close)"`.
[DEFECT D-2: the close-save just stamped `Now`, so "local ≥ bundle" is effectively always true.]

**DATA-056 — Shared-save indicator.** Visible only while a shared file is set (header, left of the status line).
Two independent trouble flags — *offline* (folder unreachable on a check) and *push failed* (last push threw);
the time trouble started is kept until a successful push/pull. Texts:
* offline: `"⚠ Shared save OFFLINE since {HH:mm} — retrying"` (red `#D45050`);
* push failed: `"⚠ Shared save NOT SAVING since {HH:mm} — last write failed"` (red);
* healthy after at least one successful push/pull: `"🔗 Shared synced {HH:mm}"` (green `#3CA05A`);
* healthy, never synced this session: `"🔗 Shared save on"` (green).
A read-only reachability success clears *offline* only; only a real push/pull clears *push failed*.

**DATA-057 — Startup check.** On main-window load the "last seen" and "last synced" stamps are both set to the
loaded data's `LastModified` (startup state is treated as in sync), the sync machinery starts, and an update
check is queued at background priority, so a bundle another machine wrote while this one was off is adopted.

**DATA-058 — Shared bundle import algorithm.** `ImportSharedBundle` (`DataStore.cs:780`, §3.10): extract to
temp, require `data.json`, copy bundle attachments in (overwrite), write the data index, sweep orphans (unless
data-only), reload + migrate + rewrite, persist settings. Never touches settings/password/Google state.

### F. Attachments (file bank storage)

**DATA-060 — Import a copy.** `DataStore.ImportFile(source)`: copy to `files/{Guid:N}_{originalFileName}`
(32 lowercase hex digits, underscore, original name incl. extension; overwrite) and return the relative path
`"files/{Guid:N}_{name}"` with `/` separators. Used by the container file bank and Quick Card targets.

**DATA-061 — Link in place.** `FileItem.LinkInPlace = true` (and `QuickCard.LinkInPlace`) store the original
absolute or UNC path verbatim; such paths are **never** copied, normalised or rewritten by the data store
(skipped by normalisation, migration and bundling). Opening launches the live file so edits save back to the
source.

**DATA-062 — Web links.** `FileItem.IsLink = true`: `Path` holds a URL; never rewritten. `SourceLabel` shows
`"Web link"`; link-in-place `"Live"`; imported copy `"Copy"`.

**DATA-063 — Resolve a stored path.** `ResolveFilePath(stored)`: empty → `""`; starts with `http://`,
`https://` or `mailto:` (case-insensitive) → unchanged; rooted → unchanged; otherwise
`GetFullPath(Combine(AppFolder, stored))`.

**DATA-064 — Normalise paths on every load and save.** `NormalizeFilePaths` runs in `Load`, `LoadFrom`,
`SerializeForSave` and `SaveTo`: for every non-link, non-live file item whose path is rooted: (1) inside the
current `AppFolder` → rewritten relative; (2) a foreign absolute path containing `/files/` whose leaf exists in
the local `files/` → rewritten to `files/<leaf>`; (3) otherwise untouched. Self-heals databases imported from
other machines. §3.7.

**DATA-065 — Legacy absolute-path migration on bundle import.** After every bundle/Flash Sync import,
`MigrateLegacyAbsolutePaths` rewrites any rooted non-link, non-live path containing `/files/` to
`files/<leaf>` **without** checking existence. §3.8.

**DATA-066 — Classify by extension.** `ClassifyFile(path)` → `FileKind` (§3.6). Links use `FileKind.Link`
(set by the file bank, not by this function).

**DATA-067 — Attachments are never deleted by item deletion.** Deleting/trashing/purging an item leaves its
files in `files/` (blobs may be shared with saved lists and Quick Cards; live links point at user originals).
The only code that deletes attachment files is the bundle-import orphan sweep. [FAITHFUL]

**DATA-068 — Container enumeration scope.** Path normalisation and migration visit exactly these containers
(`EnumerateContainers`, `DataStore.cs:548`): each Equipment's container and each of its Components'
containers; each Task's container recursively through all Subtasks; each Procedure's container and each Step's
container; each Vessel's container; each crew member's checklist-step containers; each saved-list
(ChecklistTemplate) item's container. **Not** visited: Quick Card targets, trash payloads (they are strings),
SIRE bodies, schedule entries.

### G. Local at-rest encryption

**DATA-070 — Encrypt local data file toggle.** File ▸ `"Encr_ypt local data file (this PC)"` (checkable).
Tooltip: `"Encrypt this PC's data file at rest with Windows DPAPI (tied to your Windows account). Shared,
exported and Google Drive copies stay portable plaintext, so sync between machines is unaffected."`. Turning
**on** asks (Information, OK/Cancel) titled `"Encrypt local data file"`:
`"Encrypt this PC's data file at rest with Windows DPAPI (tied to your Windows account)?\n\n• Only THIS machine's local file is encrypted.\n• Shared-save bundles, ZIP exports and Google Drive backups stay portable plaintext, so syncing between PCs still works.\n• It can only be read back under your Windows account on this PC."`
— Cancel unticks. Turning **off** asks nothing. Then: persist `EncryptLocalData`, stamp `LastModified = Now`,
`DataStore.Save(data)` rewrites the active file in the new form; status
`"Local data file is now encrypted at rest."` / `"Local data file is now plaintext."`. Error →
`"{message}"` titled `"Encrypt local data file failed"`, checkbox reverts. Refused in safe mode (DATA-021).

**DATA-071 — Encrypted file format & scope.** Only when `EncryptLocalData` is on **and** the target path is
inside `AppFolder`: file bytes = ASCII `"AAENC1\n"` + DPAPI(UTF-8 JSON). Reading detects the 7-byte magic and
decrypts transparently; otherwise the file is UTF-8 JSON (a UTF-8 BOM is stripped). An external active file
(chosen via Import from file) is never encrypted. §4.6.

**DATA-072 — Portable artifacts are always plaintext.** Bundles (`data.json` inside ZIPs), Save As copies,
Drive uploads and Flash Sync payloads are always plaintext; the encrypted local file is decrypted when bundled.

**DATA-073 — Google OAuth token encrypted at rest.** The Google auth library's token store is replaced by
`DpapiDataStore` (folder `google-token/`): each value = ASCII `"AADPAPI1"` + DPAPI(UTF-8 Newtonsoft JSON).
A legacy plaintext token file is read and transparently re-stored encrypted. Unreadable → treated as absent.
§4.9. (Drive spec owns the OAuth flow.)

### H. App password (container password)

**DATA-080 — Set / change app password.** Tools ▸ `"Set / change _password..."` opens the password dialog
in *SetNew* mode (no password yet) or *ChangeExisting* mode. Dialog (440×220, title `"Password"`): header
`"Set app password"` / `"Change app password"`; prompt `"Pick a password (used to lock/unlock every container).\nConfirm it on the second line."`
/ `"Enter the new password and confirm it on the second line."`; two password boxes; buttons `"Cancel"`,
`"OK"`. Validation: empty → `"Password cannot be empty."`; fewer than 4 characters (UTF-16 length) →
`"Password must be at least 4 characters."`; mismatch → `"Passwords do not match."`. On OK:
`PasswordService.SetPassword(pw)` (new random 16-byte salt, PBKDF2 hash, session unlocked with this password),
`DataStore.SavePasswordSettings(hash, salt)`, status `"App password updated."`. The current password is **not**
asked for when changing [DEFECT D-6]. Changing re-salts, which orphans any legacy `enc:` blob [DEFECT D-5].

**DATA-081 — Session unlock and Lock now.** The unlocked state is an in-memory "current password" only.
*Unlock* dialog mode: header `"Unlock"`, prompt `"Enter the app password to unlock locked containers:"`, one box;
wrong → `"Wrong password."`. Tools ▸ `"_Lock now"` (tooltip `"Forget the unlocked password for this session.
Any open locked container will require re-unlock."`) forgets the session password **and** all per-item unlocks
(DATA-092), re-gates the current selection on all four hierarchy pages in place, status
`"Locked. Locked containers and entries will require re-unlocking."`. Every `LoadSettings()` (startup, reload,
every import, shared pull) also forgets the session password.

**DATA-082 — Master password.** `PasswordService.Verify("redemption")` is always true (ordinal compare),
whether or not a password is set. Unlocking with it sets the session password to `"redemption"` (which cannot
decrypt blobs made with a different password — [DEFECT D-4]).

**DATA-083 — Legacy `enc:` container bodies.** Older builds encrypted a whole container body; the stored
`RichTextXaml` then starts with `"enc:"`. Current builds never create them (`PasswordService.Encrypt` has no
caller). When a container editor opens such a body: if the session is unlocked it decrypts, stores the plaintext
back into `RichTextXaml`, clears `IsLocked`, marks dirty (migration); if locked it shows an empty document and
**withholds persistence** so a keystroke can never overwrite the ciphertext. The read-only viewer shows
`"(locked content)"`. Format and algorithm: §4.7, §3.14. [DEFECT D-4: a failed decrypt stores `""`.]

**DATA-084 — Password storage.** `settings.json` keys `PasswordHash` (Base64 of 32-byte PBKDF2 output) and
`PasswordSalt` (Base64 of 16 random bytes). `HasPassword` = both present. Never sent by Flash Sync.

### I. Per-item password locks

**DATA-090 — Protect an item.** Any Equipment/Task/Procedure/Vessel can carry its own lock
(`LockHash`, `LockSalt`, `LockHint` on the item). `ItemLockService.Protect(item, pw, hint)`: empty password →
`ArgumentException("Password required.")`; new random 16-byte salt; PBKDF2-SHA256 100 000 iterations 32 bytes;
Base64 both; hint trimmed, blank → null (omitted from JSON); the item is **immediately gated** (removed from the
session-unlocked set). UI (hierarchy spec): lock dialog `"Lock “{name}”"` / `"Change lock on “{name}”"`,
prompts `"Set a password for this entry. It will be required to view or edit the entry. The app master password always unlocks it."`
/ `"Enter a new password (and, optionally, a new hint). The master password always unlocks it."`, labels
`"Password:"`, `"Confirm password:"`, `"Hint (optional — shown on the lock screen, never the password):"`, same
validation strings and 4-character minimum as DATA-080; after protect the repository **saves immediately**
(`_repo.Save()`), status `"'{name}' is now locked."` / `"Lock updated."`.

**DATA-091 — Verify / unlock.** `Verify(item, pw)`: `pw == "redemption"` (ordinal) → true; item not protected
or `pw` empty → false; else recompute PBKDF2 with the stored salt and compare in constant time; any decode
error → false. `TryUnlock` = verify then remember the item id for the session. UI wrong-password text:
`"Wrong password. Use the entry's password or the master password (“redemption”)."`; success status
`"'{name}' unlocked for this session."`; hint button → `"(No hint was set.)"` or `"Hint: {hint}"`.

**DATA-092 — Session unlock memory.** A process-wide set of unlocked item ids. `IsGated(item)` =
`IsLockProtected && !unlocked.Contains(id)`. `Relock(item)` removes one id (the per-item `"🔒 Lock again"`
button; status `"'{name}' locked again — the password is needed to open it."`). `RelockAll()` (Tools ▸ Lock
now) clears the set. The set is **not** cleared by reloads/imports (ids are stable). Forgotten on relaunch.

**DATA-093 — Remove protection.** `RemoveProtection` nulls hash, salt and hint and forgets the id; the
repository saves immediately; status `"Lock removed."`. The manage prompt (Yes/No/Cancel, titled
`"Manage lock"`): `"This entry is locked.\n\nYes  = Change the password / hint\nNo   = Remove the lock\nCancel = keep it as is"`.

**DATA-094 — Locks gate, never encrypt.** The item's data stays plaintext in `data.json`. Gated items can't be
viewed/edited, deleted, exported to PDF or opened in their own window; search indexes only their name/tags;
batch delete skips them (owned by other specs; the predicate is `ItemLockService.IsGated`).

### J. Change preview before every overwrite

**DATA-100 — Review dialog.** Every overwrite path (Import from file, Import data folder, Load backup from
Google Drive, Drive sync pull) calls `ReviewAndConfirmImport(incoming, incomingLastModified, sourceName)`
(`MainWindow.xaml.cs:629`) which shows `DiffWindow` (title `"Review changes before importing"`, 760×580,
centred on owner):
* bold header `"Importing from: {sourceName}"`;
* a bordered box with the age verdict (DATA-101);
* bold summary: when there are changes
  `"This import will   ＋ add {A}     ～ change {C}     － remove {R}   item(s).  Expand a row to see details."`
  (spacing exactly as shown: 3 spaces before `＋`, 5 before `～` and `－`, 3 before `item(s).`, 2 before
  `Expand`), else `"No differences detected — the incoming data appears identical to your current data."`;
* muted line `"Review what this import will do, then choose Import to overwrite your current data or Cancel to keep it."`;
* a tree of change nodes: glyph `＋` green `#2E7D32` (added), `－` red `#C62828` (removed), `～` orange
  `#EF6C00` (changed), bold, 20 px column; text wraps (max 640 px). Top-level rows start **expanded**, deeper
  levels collapsed.
* buttons `"Cancel"` (Esc) and `"Import (overwrite)"` (accent, default/Enter). Returns true only on Import.

**DATA-101 — Age verdict.** Text (`AgeVerdict`, `MainWindow.xaml.cs:645`):
`"Incoming saved: {inc}\nCurrent saved:  {cur}\n{verdict}"` where each date is `yyyy-MM-dd HH:mm:ss` or
`"(no save date)"` (note two spaces after `Current saved:`), and verdict is one of:
`"➜ The incoming data is NEWER than your current data."`, `"➜ The incoming data is OLDER than your current data."`,
`"➜ The incoming data is the SAME age as your current data."`, `"➜ Your current data has no save date; relative age is unknown."`
(incoming has a date, current doesn't), `"➜ The incoming data has no save date (older format); it may be older."`,
`"➜ Neither copy has a save date; relative age is unknown."`.

**DATA-102 — Diff tree semantics.** Top-level items (Equipment, Tasks, Procedures, Vessels) are matched by
`Id`. Roots: added, removed, changed; sorted Added → Changed → Removed, then by text (case-insensitive). Root text
`"[{KindLabel}] {Name}"` with `Equipment/Area`, `Task`, `Procedure`, `Vessel`. Counts A/C/R are top-level only.
Full rules in §3.15.

**DATA-103 — What is compared.** Name, description, notes (plain text of the rich body), files (by name+path),
task deadline/start/recurrence/status and subtasks (recursive), equipment components (name, one-line notes, notes
body, files) and linked procedures/tasks, procedure steps (title, done, notes, files, linked tasks/equipment).
**Not** compared: crew, saved lists, buckets, ports, logs, trash, SIRE, UI, vessel quick cards/jobs/ports,
tags, relations, groups, buckets, jobs/durations, procedure deadline/recurrence/status, step deadlines, locks.
[FAITHFUL; see open question Q-3.]

**DATA-104 — Fallback confirm.** If the incoming data can't be read for a preview (`incoming == null`):
Warning Yes/No titled `"Confirm import"`: `"Replace your current data with '{sourceName}'?\n(Could not read a change preview for this source.)"`.

### K. Trash, undo, activity log (model rules)

**DATA-110 — Soft delete.** Deleting an Equipment/Task/Procedure/Vessel (top level) or a crew member moves
it to `AppData.Trash` as a `TrashedItem` whose `PayloadJson` is the item's full JSON (whole subtree), then removes
it from its live collection, logs `Removed … "moved to Trash"`, marks dirty. References to it are **not**
scrubbed at trash time (restore is lossless). §3.17.

**DATA-111 — Batch delete.** Several items deleted together share a new `BatchId`; single deletes keep
`Guid.Empty` (`00000000-0000-0000-0000-000000000000`).

**DATA-112 — Undo last delete (Ctrl+Z).** Only when no text box/password box has keyboard focus and not in
safe mode. Restores the newest Trash entry — or, if it has a non-empty `BatchId`, every entry of that batch
(newest first), continuing past failures; refreshes every affected page; saves; status
`"Restored {n} deleted items (Ctrl+Z)."` (n > 1) or `"Restored the last deleted item (Ctrl+Z)."`; empty Trash →
`"Nothing to undo."`.

**DATA-113 — Trash window.** File ▸ `"_Trash (restore deleted items)..."` (tooltip `"Restore items you
deleted, or remove them for good. Deletes go here instead of vanishing — Ctrl+Z undoes the last one."`). Window
`"Trash"` (680×480) with explanation `"Deleted items are kept here so a mistake can be undone. Restore puts an
item (with its whole subtree) back where it was. Items are auto-removed after 90 days, or once there are more
than 200."`, buttons `"↩ Restore"`, `"Delete permanently"`, `"Empty Trash"`, `"Close"`, list columns
`"Name"`, `"Kind"`, `"Deleted"` (local `yyyy-MM-dd HH:mm`). Restore failure → `"Couldn't restore the selected
item(s)."` titled `"Restore"`. Permanent delete → confirm `"Permanently delete {n} item(s) from the Trash? This
cannot be undone."` titled `"Delete permanently"`; Empty → `"Permanently remove all {n} item(s) in the Trash?
This cannot be undone."` titled `"Empty Trash"`. Each action saves immediately. (UI may be owned by another
spec; data rules here.)

**DATA-114 — Retention.** At most **200** entries and **90 days** (by `DeletedUtc`). Pruned on every add and
once at startup (not in safe mode). Evicted/purged/emptied entries have all references to their `ItemId`
scrubbed (`PurgeReferences`).

**DATA-115 — Activity log.** `AppData.Log`: append-only `LogEntry` (UTC timestamp, `"Added"`/`"Removed"`,
kind label, name — blank → `"(unnamed)"`, trimmed — and optional detail). Capped at **10 000** entries (oldest
removed first). Every log append marks dirty. (Viewer window owned by the tools spec.)

### L. Recurrence

**DATA-120 — Regenerate next occurrence.** A top-level Task with `Recurrence != None`, `IsComplete` and not
`RecurrenceSpawned` (or a top-level Procedure with `Status == Done`) spawns a fresh clone for the next
occurrence (§3.18). Runs after every successful save (`Saved` event; re-entrancy guarded) and once at startup.
When anything spawns, the Tasks/Procedures lists reload.

**DATA-121 — Idempotence.** The source gets `RecurrenceSpawned = true` before cloning; the clone has it false.
Un-completing and re-completing the source never spawns again. Schema migration (DATA-023) protects upgrades.

### M. Model behaviours (computed rules that must be identical)

**DATA-130 — Task `Status` ⇄ `IsComplete`.** Setting `IsComplete = true` sets `Status = Done` (if not already);
setting it false while `Status == Done` sets `Status = Todo`. Setting `Status = Done` sets `IsComplete = true`;
any other status sets `IsComplete = false`. No recursion (setters no-op when unchanged). Procedures have only
`Status`; checklist steps only `Done`.

**DATA-131 — Working range.** `TaskItem.RangeStart` (optional) + `Deadline` (range end). `HasRange`,
`RangeFirst`, `WhenText`, `CoversDay(day)` — §3.19. Setters of either date raise change notifications for the
three derived properties.

**DATA-132 — Legacy `BucketId`.** A legacy single `BucketId` on any Task/Procedure/Equipment/Vessel is merged
into `BucketIds` on load and never written back. §3.20.

**DATA-133 — Identity / de-dup keys.** `PortCall.Key`, `Port.Key`, `PortVisit.VisitKey`, `CrewMember.Key`,
`ShipJob.JobNo` — §3.21.

**DATA-134 — Display strings.** `ChecklistTemplate.Display`, `ScheduleTemplate.Display`,
`QuickBucket.Display`, `TrashedItem.Display/DeletedLocal`, `LogEntry.TimeUtc/TimeLocal`, `FileItem.SourceLabel`,
`ScheduleEntry.KindIcon/WhenDisplay`, `PortCall.DisplayName/ArrivalDisplay/DepartureDisplay`,
`Port.Display`, `BundleSource.WrittenLocal`, `CrewMember.FullName` — §3.22.

**DATA-135 — Crew contract status & tolerant date parse.** `CrewMember.ParseDate`, `DaysUntilSignOff`,
`ContractStatusOn` (Critical ≤ 30 days, DueSoon ≤ 60, Expired < 0, Unknown when no date);
`ShipJob.DaysUntilDue` — §3.23.

**DATA-136 — Sidebar groups.** `CreateGroup(kind, name)` (blank → `"New group"`, trimmed), `RenameGroup`
(blank ignored, trimmed), `DeleteGroup` (ungroups members), `AssignToGroup` — §3.24.

**DATA-137 — Relations & references.** `AddRelation` (two-way, no self, no duplicates), `RemoveRelation`,
`RelatedItems`, `ReferencedBy` (backlinks), `PurgeReferences` — §3.24.

**DATA-138 — Lookups.** `AllItems`, `FindById`, `AllContainers`, `AllJobs`, `Label(id)`
(`"[{Kind}] {Name}"` or `"(missing)"`) — §3.24.

**DATA-139 — Copy helpers.** `QuickCard.Clone()` (same Id), `QuickCard.CopyFrom`, `ShipJob.CopyFrom` (all 19
fields) — §3.25.

**DATA-140 — SIRE state helpers.** Status map by question number (names `InProgress`/`Checked`/
`NotApplicable`; `None` removes the key), bookmark/for-export toggles, tasks per question, counts — §3.26.

### N. settings.json

**DATA-150 — Keys and merge-on-write.** §4.3. Every setter re-reads the existing file and writes the merged
result (preserving keys it doesn't model). Some keys coalesce with the existing file value when the in-memory
value is null [DEFECT D-7 for `GeminiApiKey`]. Writes are **not** atomic and errors are swallowed.

**DATA-151 — Setters.** `SetCurrentDataFile`, `SavePasswordSettings`, `SetGoogleDriveFolder`, `SetSyncOnSave`,
`SetTextOnlyExport`, `SetDarkMode`, `SetEncryptLocalData`, `SetGeminiApiKey` (blank → null, else trimmed),
`SetAppIdentity` (blank → machine name, else trimmed), `SetFolderBuilderBase`, `SetSharedSaveFile`
(blank → null). Each persists immediately. View ▸ `"🌙 _Dark mode"` → `SetDarkMode` + theme apply + status
`"Dark mode on."` / `"Dark mode off."`.

**DATA-152 — Load settings.** Missing file or any parse error → all defaults (see §3.1). Password hash/salt are
handed to `PasswordService.LoadFrom` (which also forgets the session password).

**DATA-153 — Google Drive folder auto-detection.** `DetectGoogleDriveFolder()`: first existing of
`%USERPROFILE%\My Drive`, `%USERPROFILE%\Google Drive`, `%USERPROFILE%\GoogleDrive`, then `<each drive root>\My Drive`.
(Drive spec owns the menu flow; Mac equivalent in §6.)

---

## 3. Logic & algorithms

All pseudo-code is normative unless marked otherwise. "Ordinal" = exact code-unit comparison;
"OrdinalIgnoreCase" = simple case folding (ASCII + invariant upper-casing), which the Mac MUST emulate with
`caseInsensitiveCompare` on `String` using `.caseInsensitive` **without** locale (i.e.
`compare(_:options:[.caseInsensitive], range:nil, locale:nil)`), never a localized comparison.

### 3.1 `DataStore.LoadSettings()` — `DataStore.cs:118`

```
ensure AppFolder exists
if settings.json does not exist:
    CurrentDataFile = DefaultDataFile; GoogleDriveFolder = null; SyncOnSave = false; TextOnlyExport = false
    DarkMode = false; SharedSaveFile = null; EncryptLocalData = false; AppIdentity = machineName()
    PasswordService.LoadFrom(null, null); return
try:
    s = parse settings.json with Opts (unknown keys -> ExtraData)
    CurrentDataFile = (s.CurrentDataFile not blank AND File.Exists(it)) ? it : DefaultDataFile
    GoogleDriveFolder = s.GoogleDriveFolder           (may be null)
    SyncOnSave = s.SyncOnSave; TextOnlyExport = s.TextOnlyExport; DarkMode = s.DarkMode
    EncryptLocalData = s.EncryptLocalData
    GeminiApiKey = s.GeminiApiKey
    AppIdentity = blank(s.AppIdentity) ? machineName() : s.AppIdentity
    FolderBuilderBase = s.FolderBuilderBase
    PasswordService.LoadFrom(s.PasswordHash, s.PasswordSalt)   // forgets the session password
    SharedSaveFile = blank(s.SharedSaveFile) ? null : s.SharedSaveFile
catch (anything, incl. invalid Base64 salt):
    same defaults as the "missing" branch; GeminiApiKey / FolderBuilderBase are NOT reset (they keep whatever
    was assigned before the failure — possibly the values just read from the file)
```
`machineName()` = `Environment.MachineName`, or `"AA"` if that throws. Notes:
* The missing-file branch does **not** reset `GeminiApiKey`/`FolderBuilderBase` (keeps whatever was in memory). [FAITHFUL, harmless]
* A `null` JSON (`"null"`) parses to a null object → every `s?.X` is null/false → defaults.

### 3.2 `DataStore.Load()` — `DataStore.cs:291`

```
create AppFolder, FilesFolder
LastLoadFailed = false; LoadedNewerSchema = null
if !exists(CurrentDataFile): return new AppData()          // genuinely absent
try:
    json = ReadDataText(CurrentDataFile)                     // §3.4 (decrypts, strips BOM)
    data = deserialize<AppData>(json, Opts) ?? new AppData() // "null" -> empty
    if data.SchemaVersion > CurrentSchemaVersion: LoadedNewerSchema = data.SchemaVersion
    MigrateSchema(data)                                      // DATA-023
    NormalizeFilePaths(data)                                 // §3.7
    return data
catch: LastLoadFailed = true; return new AppData()           // present but unreadable
```
`LoadFrom(path)` (`DataStore.cs:312`) is identical except it reads an explicit path, **throws** on any failure,
and never sets `LastLoadFailed`/`LoadedNewerSchema`.

Things that make a Windows load fail (→ safe mode) and therefore MUST NEVER appear in a Mac-written file:
invalid UTF-8/JSON, comments, trailing commas, `NaN`/`Infinity`, a string where a number/bool is expected (e.g.
enum as `"Done"`), a number where a string is expected, `null` for a non-nullable value type
(`Guid`, `bool`, `int`, `double`, `DateTime`, enums), a Guid not in 36-character `8-4-4-4-12` form, a date not
in ISO-8601 (§4.1.5), nesting deeper than **64** levels (§4.1.9).

### 3.3 Save pipeline

* `DataStore.Save(data)` = `WriteData(SerializeForSave(data))`.
* `SerializeForSave(data)` (`DataStore.cs:346`): `NormalizeFilePaths(data)`; `if data.SchemaVersion < 1 then data.SchemaVersion = 1`; serialise with `Opts`.
* `WriteData(json)` (`:357`): ensure `AppFolder`; `WriteLocalDataFile(CurrentDataFile, json)`.
* `WriteLocalDataFile(path, json)` (`:392`): if `EncryptLocalData && IsUnderAppFolder(path)` → bytes =
  `"AAENC1\n"` ‖ `DPAPI.Protect(UTF8-noBOM(json))`, atomic write; else atomic write of `UTF8-noBOM(json)`.
* `IsUnderAppFolder(path)` (`:381`): `full = GetFullPath(path)`; `root = GetFullPath(AppFolder)` with trailing
  `\`/`/` trimmed, plus one separator; `full.StartsWith(root, OrdinalIgnoreCase)`; any exception → false.
* `SaveTo(data, path)` (`:423`): `NormalizeFilePaths`; atomic plaintext write of `serialize(data)` (**no**
  schema stamp, **no** encryption).
* `AtomicWrite` — DATA-029.

**Repository level** (`AppRepository.cs`):

```
MarkDirty():                       // :301
    if SuspendSaving: return
    dirty = true; restart 750 ms one-shot timer

on timer: BackgroundSaveIfDirty()  // :42 (async void, UI thread)
    if SuspendSaving or !dirty: return
    prev = Data.LastModified; Data.LastModified = Now; dirty = false
    try json = SerializeForSave(Data) catch { Data.LastModified = prev; dirty = true; return }
    try { await QueueWrite(json); raise Saved } catch { Data.LastModified = prev; dirty = true }

QueueWrite(json):                  // :62 — ordered chain
    prev = writeChain
    mine = Task.Run { try await prev catch {}; DataStore.WriteData(json) }
    writeChain = mine; return mine

Save():                            // :261 synchronous
    if SuspendSaving: return
    stop timer
    prev = Data.LastModified; Data.LastModified = Now
    try json = SerializeForSave(Data) catch { Data.LastModified = prev; rethrow }   // dirty stays as it was
    if !QueueWrite(json).Wait(15 000 ms): Data.LastModified = prev; throw TimeoutException("Timed out writing {CurrentDataFile}.")
    (AggregateException -> restore stamp, rethrow inner)
    dirty = false; raise Saved

FlushIfDirty(): if dirty: Save()
Detach(): SuspendSaving = true; stop timer; Saved = null      // :293
```
Invariants the Mac MUST keep: (1) writes complete in submission order; (2) the in-memory `LastModified` equals
the stamp in the newest file on disk, or is rolled back on failure; (3) dirty is cleared only after a confirmed
write (explicit `Save`) or optimistically before a background write that re-sets it on failure; (4) `Saved`
fires only after a successful write; (5) the UI thread never blocks on disk I/O except in `Save()` (bounded by
15 s).

### 3.4 `ReadDataText(path)` — `DataStore.cs:409`

```
raw = readAllBytes(path)
if raw starts with 41 41 45 4E 43 31 0A ("AAENC1\n"):
    return UTF8.decode(DPAPI.Unprotect(raw[7...]))           // throws if not decryptable
off = (raw starts with EF BB BF) ? 3 : 0
return UTF8.decode(raw[off...])                              // invalid sequences -> U+FFFD (no throw)
```
Used by `Load`, `LoadFrom`, `PeekFileLastModified`, and bundle export (so bundles are plaintext).

### 3.5 `ImportFile(sourcePath)` — `DataStore.cs:471`

```
ensure FilesFolder
name = fileName(sourcePath)                                   // leaf incl. extension
dest = FilesFolder / "{newGuid():N}_{name}"                   // N = 32 lowercase hex, no dashes
copy source -> dest (overwrite)
return "files/" + fileName(dest)                              // always forward slash
```
Example: `C:\docs\Pump manual.pdf` → `files/3f2504e04f8911d39a0c0305e82c3301_Pump manual.pdf`.

### 3.6 `ClassifyFile(path)` — `DataStore.cs:653`

Extension lower-cased (invariant), including the dot:

| `FileKind` (JSON number) | Extensions |
|---|---|
| `Document` (0) | `.pdf .docx .doc .xlsx .xls .pptx .ppt .txt .rtf` |
| `Image` (1) | `.jpg .jpeg .png .tif .tiff .bmp .heic .gif` |
| `Video` (2) | `.mov .mp4 .wmv .avi .mkv .m4v .webm` |
| `Other` (4) | everything else (incl. `.csv`, `.md`, `.zip`, no extension) |

`Link` (3) is assigned by the file bank for URLs, never by this function.

### 3.7 `NormalizeFilePaths(data)` — `DataStore.cs:504`

```
if data == null: return
appFull = GetFullPath(AppFolder) trimmed of trailing '\' '/' + DirectorySeparator
ensure FilesFolder
for c in EnumerateContainers(data):                  // DATA-068
  for f in c.Files:
    if f.IsLink or f.LinkInPlace: continue           // verbatim, never touched
    p = f.Path
    if p empty or !IsPathRooted(p): continue
    // case 1
    try: full = GetFullPath(p)
         if full.StartsWith(appFull, OrdinalIgnoreCase):
             f.Path = full.Substring(appFull.Length).Replace('\\','/'); continue
    catch: ignore
    // case 2
    norm = p.Replace('\\','/')
    idx = norm.LastIndexOf("/files/", OrdinalIgnoreCase)
    if idx >= 0:
        rel  = norm.Substring(idx + 1)               // "files/<leaf>"  (keeps the original case of "files")
        leaf = rel.Substring(6)
        if File.Exists(FilesFolder / leaf): f.Path = rel
```
**[MAC] rootedness.** On Windows `IsPathRooted` is true for `C:\…`, `C:/…`, `\\server\share\…` and `\…`/`/…`.
On macOS the port MUST treat all of these as rooted **plus** POSIX `/…`, so that Windows-origin absolute paths
reach case 2. Recommended predicate:
`^([A-Za-z]:[\\/]|[\\/]{2}|[\\/])` (drive-absolute, UNC, or root-relative/POSIX absolute). Drive-relative
`C:foo` (no slash) is rooted on Windows too; include `^[A-Za-z]:` for fidelity.
Case 1 on the Mac compares against the Mac `AppFolder` (POSIX, case-insensitive like Windows).
Note: case 2 keeps the *original* case of the `files` segment (`/Files/x` → `Files/x`). [FAITHFUL]

### 3.8 `MigrateLegacyAbsolutePaths(data)` — `DataStore.cs:949`

Same loop as §3.7 but: skip links/live; skip empty or non-rooted; `norm = p.Replace('\\','/')`;
`idx = LastIndexOf("/files/", OrdinalIgnoreCase)`; if found → `f.Path = norm.Substring(idx+1)` **unconditionally**
(no existence check). Called only after bundle imports and Flash Sync applies.

### 3.9 Peek helpers — `DataStore.cs:584-651`

* `PeekZipLastModified(zip)`: open the ZIP, entry **exactly** `"data.json"` (case-sensitive, root level) → null if
  missing; read as UTF-8 (BOM-aware) → `ReadLastModified(json)`; any exception → null.
* `PeekFileLastModified(jsonPath)`: `ReadLastModified(ReadDataText(path))`; exception → null.
* `ReadLastModified(json)`: parse document; root property **`LastModified`** (case-sensitive); if present and not
  JSON null → parse as DateTime (§4.1.5; a malformed string → exception → null); else null.
* `PeekBundleSource(zip)`: entry `"source.json"` → deserialize `BundleSource` with `Opts`; null on failure/missing.
* `PeekBundleIdentity(zip)` = `PeekBundleSource(zip)?.Identity`.
* `PeekZipData(zip)`: entry `"data.json"` → deserialize `AppData` with `Opts` — **no** migration, **no**
  normalisation; null on failure/missing. Used only for previews.

### 3.10 Bundle export & import

**`ExportFolderToZip(zipPath)`** = `ExportFolderToZip(zipPath, includeAttachments: !TextOnlyExport)`.

**`ExportFolderToZip(zipPath, includeAttachments)`** — `DataStore.cs:675`:
```
ensure AppFolder, FilesFolder
if GetFullPath(zipPath).StartsWith(GetFullPath(AppFolder), OrdinalIgnoreCase):     // NOTE: no trailing separator
    throw IOException("Choose a destination outside the AA data folder.")
if exists(zipPath): delete it
staging = TEMP / "AA_export_{guid:N}"
try:
  create staging
  if exists(CurrentDataFile):      write staging/data.json = ReadDataText(CurrentDataFile)   // UTF-8, no BOM
  elif exists(DefaultDataFile):    write staging/data.json = ReadDataText(DefaultDataFile)
  if includeAttachments and exists(FilesFolder): CopyDirectory(FilesFolder, staging/files)  // recursive
  source = { Identity: AppIdentity, Machine: machineName(), WrittenUtc: UtcNow,
             LastModified: PeekFileLastModified(CurrentDataFile), DataOnly: !includeAttachments }
  write staging/source.json = serialize(source, Opts)
  ZipFile.CreateFromDirectory(staging, zipPath, Optimal, includeBaseDirectory: false)
finally: delete staging recursively (errors ignored)
```
`CopyDirectory` copies every file (overwrite) then recurses into subdirectories. `CreateFromDirectory` emits one
entry per file (names relative to staging, `/` separators) and a directory entry (`name/`) **only for empty
directories** — so an existing-but-empty `files/` yields an entry `files/`, which matters for DATA-044.

**`ImportBundleSmart(zipPath)`** — `DataStore.cs:835`:
```
ensure AppFolder
staging = TEMP / "AA_import_{guid:N}"
try:
  ExtractToDirectory(zipPath, staging)                 // throws on a torn/invalid zip -> nothing local touched
  dataSrc = staging/data.json; if missing: throw InvalidDataException("The bundle has no data.json.")
  ensure FilesFolder
  filesSrc = staging/files
  dataOnly = IsDataOnlyBundle(staging, filesSrc)
  changed  = !dataOnly && !AttachmentsMatch(filesSrc, FilesFolder)
  if changed:
     names = {} (OrdinalIgnoreCase)
     if exists(filesSrc): for f in topLevelFiles(filesSrc): names.add(leaf(f)); copy f -> FilesFolder/leaf (overwrite)
     CurrentDataFile = DefaultDataFile
     WriteLocalDataFile(DefaultDataFile, readAllText(dataSrc))       // BOM-aware read; encryption policy honoured
     for f in topLevelFiles(FilesFolder): if leaf(f) ∉ names: try delete f   // orphan sweep
  else:
     CurrentDataFile = DefaultDataFile
     WriteLocalDataFile(DefaultDataFile, readAllText(dataSrc))
  data = LoadFrom(DefaultDataFile)                     // migrate schema + normalise
  MigrateLegacyAbsolutePaths(data)
  WriteLocalDataFile(DefaultDataFile, SerializeForSave(data))
  WriteSettings()                                      // persists CurrentDataFile; everything else preserved
  return changed ? WithAttachments : DataOnly
finally: delete staging (errors ignored)
```

**`ImportSharedBundle(zipPath)`** — `DataStore.cs:780`: same skeleton (staging `AA_shared_{guid:N}`, message
`"The shared save bundle has no data.json."`) but **always** copies the bundle's top-level `files/*` in
(additive, overwrite), then writes the data index, then sweeps orphans **unless** `IsDataOnlyBundle`, then
`LoadFrom` → migrate → rewrite → `WriteSettings()`. Returns nothing.

**`IsDataOnlyBundle(staging, filesSrc)`** — `:893`: if `staging/source.json` exists and deserialises with
`DataOnly == true` → true (parse errors ignored); else `!Directory.Exists(filesSrc)`.

**`AttachmentsMatch(bundleDir, localDir)`** — `:926`: map leaf→size of top-level files in each dir
(OrdinalIgnoreCase keys; a missing dir = empty map); equal counts and every bundle entry present locally with
equal size.

Only **top-level** files of `files/` participate in copy, sweep and match (sub-folders are neither imported nor
deleted). [FAITHFUL] [DEFECT D-3: the JSON is not parse-validated before local files are modified.]

**`ImportFolderFromZip(zipPath)`** — `:727` (dead code, DATA-047):
```
save bytes of google_client_secret.json (if any); copy google-token/ to TEMP/AA_gtok_{guid:N} (if any)
delete every file and every directory in AppFolder (errors ignored per entry)
ExtractToDirectory(zip, AppFolder, overwrite: true)
delete AppFolder/settings.json if extracted
restore client secret (if not present) and token dir (if not present); delete temp copy
SetCurrentDataFile(DefaultDataFile)                     // persists settings (merged with nothing)
if data.json exists: data = LoadFrom; MigrateLegacyAbsolutePaths; WriteLocalDataFile(SerializeForSave(data))  (errors ignored)
```

**`ApplySyncedData(json)`** — `:912`: ensure `AppFolder`; `CurrentDataFile = Default`; `WriteLocalDataFile(Default, json)`;
`data = LoadFrom(Default)`; `MigrateLegacyAbsolutePaths(data)`; `WriteLocalDataFile(Default, SerializeForSave(data))`;
`WriteSettings()`; return data.

### 3.11 Settings write — `WriteSettings(newHash = null, newSalt = null)`, `DataStore.cs:237`

```
try:
  ensure AppFolder
  existing = settings.json exists ? try parse (errors -> null) : null
  s = {
    CurrentDataFile   = CurrentDataFile,
    PasswordHash      = newHash ?? existing?.PasswordHash,
    PasswordSalt      = newSalt ?? existing?.PasswordSalt,
    GoogleDriveFolder = GoogleDriveFolder ?? existing?.GoogleDriveFolder,
    SyncOnSave        = SyncOnSave,
    DarkMode          = DarkMode,
    FolderBuilderBase = FolderBuilderBase ?? existing?.FolderBuilderBase,
    SharedSaveFile    = SharedSaveFile,                      // null clears
    EncryptLocalData  = EncryptLocalData,
    GeminiApiKey      = GeminiApiKey ?? existing?.GeminiApiKey,   // null does NOT clear  [DEFECT D-7]
    AppIdentity       = AppIdentity,
    TextOnlyExport    = TextOnlyExport,
    ExtraData         = existing?.ExtraData }                // unknown keys preserved
  File.WriteAllText(settings.json, serialize(s, Opts))       // NOT atomic; UTF-8 no BOM
catch: ignore
```
Every public setter (`SetX`) assigns the static then calls `WriteSettings()`; `SavePasswordSettings(h, s)` calls
`WriteSettings(h, s)`. There is no API to delete the password.

Flash Sync writes `settings.json` directly (merged JSON tree, compact) and then calls `LoadSettings()` — that
path belongs to the Flash Sync spec, but it means `settings.json` may contain keys written by other devices.

### 3.12 Shared-save machinery — `MainWindow.xaml.cs:931-1171`

State: `lastSeen` (bundle stamp already handled/declined), `lastSynced` (data stamp last pushed/pulled),
`handling` (re-entrancy), `pushRunning`, `offline`, `pushFailed`, `troubleSince`, `lastSyncOk`.

```
Start():  Stop(); if no path: return
          saveTimer = every 60 s -> SharedSaveTick()
          pollTimer = every 60 s -> CheckForUpdate()
          debounce  = 1.5 s one-shot -> CheckForUpdate()
          try: if dir(path) exists: watcher(dir, filter = fileName(path),
                      notify = LastWrite|Size|FileName|CreationTime) on Changed/Created/Renamed -> restart debounce
          UpdateIndicator()
Stop():   stop/dispose timers and watcher

SharedSaveTick():
    if !repo or !path or handling: return
    CheckForUpdate()
    FlushAllEditors()
    if !repo.IsDirty: return                  // [DEFECT D-1]
    PushBackground("Shared save")

PushBackground(label) / Push(label):
    if pushRunning (background variant only): return
    tmp = path + "." + guid:N + ".tmp"
    try: FlushAllEditors(); CaptureUiState(); repo.Save()
         ExportFolderToZip(tmp)               // background thread in the Background variant
         File.Move(tmp, path, overwrite: true)
         lastSeen = lastSynced = repo.Data.LastModified
         status "{label} written HH:mm:ss (data + attachments)."; SetOnline(synced: true)
    catch ex: status "{label} failed: {ex.Message}"; SetPushFailed()
    finally: delete tmp if present

CheckForUpdate():
    if !repo or handling or !path: return
    if dir(path) missing/unreachable: SetOffline(); return
    if !exists(path): SetOnline(false); return
    fileStamp = PeekZipLastModified(path); if null: return
    local = repo.Data.LastModified
    newer = local == null || fileStamp > local
    if !newer: SetOnline(false); return
    if lastSeen != null && fileStamp == lastSeen: SetOnline(false); return
    handling = true
    try:
        FlushAllEditors()
        unsynced = repo.IsDirty || (local != null && (lastSynced == null || local > lastSynced))
        if unsynced and user answers No: lastSeen = fileStamp; SetOnline(false); return
        who = PeekBundleIdentity(path)
        ImportSharedBundle(path); LoadDataAndInitUi()
        lastSeen = lastSynced = repo.Data.LastModified
        status "Reloaded the shared save[ from “who”] (HH:mm:ss)."; SetOnline(true)
    catch ex: status "Shared reload skipped (busy): {ex.Message}"
    finally: handling = false

SetOnline(synced): offline = false; if synced: pushFailed = false; troubleSince = null; lastSyncOk = Now; UpdateIndicator()
SetOffline():      if !offline && !pushFailed: troubleSince = Now; offline = true; UpdateIndicator()
SetPushFailed():   if !offline && !pushFailed: troubleSince = Now; pushFailed = true; UpdateIndicator()
```
Stamp comparisons are .NET `DateTime` comparisons: **by ticks only, ignoring `Kind`** (§4.1.5).

On close (DATA-055): `exists = File.Exists(path)`; `fileStamp = exists ? Peek : null`;
`push = !exists || (fileStamp != null && (local == null || local >= fileStamp))`; if push → `Push("Shared save (on close)")`.

### 3.13 `PasswordService` — `Services/PasswordService.cs`

Constants: `Iterations = 100_000`, `SaltSize = 16`, `KeySize = 32`, `IvSize = 16`, `HmacSize = 32`,
`Prefix = "enc:"`, `MasterPassword = "redemption"`. State (process-wide): `salt: bytes?`, `hashB64: string?`,
`currentPassword: string?`.

```
HasPassword  = hashB64 non-empty && salt != null
IsUnlocked   = currentPassword != null
LoadFrom(hash, saltB64): hashB64 = empty(hash) ? null : hash
                         salt = empty(saltB64) ? null : base64Decode(saltB64)   // throws on bad Base64
                         currentPassword = null
SetPassword(pw): if empty(pw) throw ArgumentException("Password required.")
                 salt = random(16); hash = PBKDF2-HMAC-SHA256(UTF8(pw), salt, 100000, 32)
                 hashB64 = base64(hash); currentPassword = pw
                 return (hashB64, base64(salt))
Verify(pw):      if pw == "redemption" (ordinal): return true
                 if !HasPassword: return false
                 return fixedTimeEquals(PBKDF2(UTF8(pw), salt, 100000, 32), base64Decode(hashB64))
Unlock(pw):      if !Verify(pw) return false; currentPassword = pw; return true
Lock():          currentPassword = null
IsEncrypted(v):  v non-empty && v.StartsWith("enc:", Ordinal)
DeriveKeys(pw, salt): k = PBKDF2(UTF8(pw), salt, 100000, 64); enc = k[0..<32]; mac = k[32..<64]
Encrypt(text):   require currentPassword && salt else throw InvalidOperationException("Password vault is locked.")
                 (enc, mac) = DeriveKeys(currentPassword, salt); iv = random(16)
                 ct  = AES-256-CBC-PKCS7(enc, iv, EF BB BF ‖ UTF8(text))       // StreamWriter(Encoding.UTF8) writes a BOM
                 tag = HMAC-SHA256(mac, iv ‖ ct)
                 return "enc:" + base64(iv ‖ ct ‖ tag)
Decrypt(blob):   if !IsUnlocked || salt == null || !IsEncrypted(blob): return null
                 try: b = base64Decode(blob[4...]); if b.count < 16 + 32 + 16: return null
                      iv = b[0..<16]; tag = b[count-32..<count]; ct = b[16..<count-32]
                      (enc, mac) = DeriveKeys(currentPassword, salt)
                      if !fixedTimeEquals(HMAC-SHA256(mac, iv ‖ ct), tag): return null
                      pt = AES-256-CBC-PKCS7-decrypt(enc, iv, ct)
                      return UTF8-decode with BOM detection (strip EF BB BF; a UTF-16/32 BOM would switch encoding)
                 catch: return null
```
Important consequences: the first 32 bytes of the 64-byte derivation are **identical** to the stored password
hash (PBKDF2 block 1), i.e. `PasswordHash` *is* the AES key [DEFECT D-8, format must stay]. The HMAC key is
only derivable from the password.

### 3.14 `ContainerEditor` legacy `enc:` handling (consumer contract) — `Views/ContainerEditor.xaml.cs:384-445`

```
toShow = c.RichTextXaml
if IsEncrypted(toShow):
    if PasswordService.IsUnlocked:
        toShow = Decrypt(c.RichTextXaml) ?? ""        // [DEFECT D-4] null -> "" is then persisted
        c.RichTextXaml = toShow; c.IsLocked = false; repo.MarkDirty()
    else:
        toShow = ""; contentWithheld = true           // editor shows empty, never persists
c.IsLocked = false                                     // in-memory; persisted on the next save
if toShow not blank: load as XAML; on parse failure show the raw text as one paragraph and contentWithheld = true
PersistRichText(): if contentWithheld: return; else RichTextXaml = TextRange.Save(Xaml); MarkDirty
```
The Mac editor MUST implement the same withholding rule (never write a stand-in over real content) and SHOULD
fix D-4 (on decrypt failure keep the blob and withhold).

### 3.15 `DataDiff.Compare(current, incoming)` — `Services/DataDiff.cs`

Types: `Change { Added, Removed, Changed }`; `Node { Change, Text, Children }`;
`Result { Roots, Added, Removed, Changed, HasChanges = Roots.Count > 0 }`.

```
Items(d) = d.Equipment ++ d.Tasks ++ d.Procedures ++ d.Vessels        // top level only
names = {}; for i in Items(current): names[i.Id] = i.Name; for i in Items(incoming): names[i.Id] = i.Name   // incoming wins
cur = map Id->item over Items(current) (last wins);  inc = same over Items(incoming)
for (id, b) in inc where id ∉ cur:  Added++;   root(Added,   Root(b)) with ContentChildren(b, Added)
for (id, a) in cur where id ∉ inc:  Removed++; root(Removed, Root(a)) with ContentChildren(a, Removed)
for (id, b) in inc where id ∈ cur:  kids = CompareItem(cur[id], b); if kids non-empty: Changed++; root(Changed, Root(b)) with kids
sort Roots by (Order(change): Added 0, Changed 1, Removed 2), then Text with OrdinalIgnoreCase   // unstable sort
```
Map iteration order = first-insertion order of the key (i.e. collection order; a duplicate id keeps its first
position but the *last* value). The Mac MUST use an insertion-ordered map with the same semantics.

`Root(i) = "[{KindLabel(i.Kind)}] {i.Name}"`, `KindLabel(Equipment) = "Equipment/Area"`, else the enum name
(`Task`, `Procedure`, `Vessel`).

**ContentChildren(i, c)** (added/removed item listing):
1. for each file in `i.Container.Files`: `c "file: {Name}"`;
2. Task: for each subtask `s`: `c "subtask: {s.Name}"` + `TaskContentChildren(s, c)`;
   Equipment: for each component: `c "component: {Name}"` + (its files as `"file: {Name}"`); then for each
   `ProcedureIds` id `c "linked procedure: {Name(id)}"`; for each `TaskIds` id `c "linked task: {Name(id)}"`;
   Procedure: for each step: `c "step: {Title}"` + `StepContentChildren(step, c)`; Vessel: nothing more.

`TaskContentChildren(t, c)` = files of `t` (`"file: …"`) then each subtask recursively (`"subtask: …"`).
`StepContentChildren(st, c)` = files, then `"linked task: {Name(id)}"` per `TaskIds`, then
`"linked equipment/area: {Name(id)}"` per `EquipmentIds`. `Name(id)` = names lookup or `"(unknown)"`.

**CompareItem(a, b)** (both same Id):
1. `AddHierarchyFields`:
   * `a.Name != b.Name` (ordinal) → `Changed "name: \"{a.Name}\" → \"{b.Name}\""`
   * `(a.Description ?? "") != (b.Description ?? "")` → `Changed "description: \"{Snip(a)}\" → \"{Snip(b)}\""`
   * `PlainText(a.Container.RichTextXaml) != PlainText(b…)` → `Changed "notes: \"{Snip(an)}\" → \"{Snip(bn)}\""`
   * `DiffFiles(a.Container, b.Container)`: key = `Name + "|" + Path`; for keys only in b → `Added "file: {Name}"`
     (b order); only in a → `Removed "file: {Name}"` (a order). (`ToDictionary` throws on a duplicate key —
     [DEFECT D-10].)
2. Task/Task: `Deadline` differ (tick equality, Kind ignored) → `Changed "deadline: {Fmt(a)} → {Fmt(b)}"`;
   `RangeStart` → `"start: … → …"`; `Recurrence` → `"recurrence: {a} → {b}"` (enum names: `None Daily Weekly Monthly Yearly`);
   `Status` → `"status: {a} → {b}"` (`Todo InProgress Blocked Done`); then `DiffTasks(a.Subtasks, b.Subtasks, "subtask")`.
   Equipment/Equipment: `DiffComponents`; `DiffLinks(ProcedureIds, "linked procedure")`; `DiffLinks(TaskIds, "linked task")`.
   Procedure/Procedure: `DiffSteps`.
   (Mismatched kinds sharing an Id → only step 1.)

`DiffTasks(a, b, label)`: added (in b order) → `Added "{label}: {Name}"` + TaskContentChildren(Added); removed
(in a order) → `Removed …` + TaskContentChildren(Removed); common (in b order) → `CompareItem` recursively, if
non-empty `Changed "{label}: {b.Name}"` with those children.

`DiffComponents`: added/removed `"component: {Name}"` + files; common: `name: "a" → "b"`,
`notes line: "{Snip(a.Notes)}" → "{Snip(b.Notes)}"` (null-coalesced), `notes: …` (plain text of container),
files; if any → `Changed "component: {b.Name}"`.

`DiffSteps`: added/removed `"step: {Title}"` + StepContentChildren; common: `title: "a" → "b"`,
`done: {a.Done} → {b.Done}` (**`True`/`False`**, .NET capitalisation), `notes: …`, files,
`DiffLinks(TaskIds,"linked task")`, `DiffLinks(EquipmentIds,"linked equipment/area")`; if any →
`Changed "step: {b.Title}"`.

`DiffLinks(a, b, label)`: set semantics; ids in b∖a → `Added "{label}: {Name(id)}"`; a∖b → `Removed …`
(iteration order of a hash set — unspecified; the Mac SHOULD use collection order).

Helpers:
* `Fmt(d) = d?.ToString("yyyy-MM-dd") ?? "(none)"`.
* `Snip(s)`: `(s ?? "")` with every `\r` and `\n` replaced by a space, `Trim()`; if length ≤ 40 UTF-16 units
  keep, else first 40 UTF-16 units + `"…"` (U+2026). The Mac SHOULD avoid splitting a surrogate pair.
* `PlainText(xaml)`: empty → `""`; replace regex `<[^>]+>` with `" "`; `WebUtility.HtmlDecode`; replace regex
  `\s+` with `" "`; `Trim()`.

All texts use `→` (U+2192) with one space each side and straight double quotes around values.

### 3.16 `AgeVerdict(incoming, current)` — `MainWindow.xaml.cs:645`

See DATA-101 for the exact strings. Dates are formatted `yyyy-MM-dd HH:mm:ss` from the parsed `DateTime`
(the local wall clock for Local-kind stamps). Comparison is by ticks (`>`/`<`/equal). Branch order: both present
→ NEWER/OLDER/SAME; only incoming present → "current data has no save date"; only current present → "incoming
has no save date (older format)"; neither → "Neither copy…".

### 3.17 Trash — `AppRepository.cs:317-531`

```
TrashType(kind): Equipment->"Equipment", Task->"Task", Procedure->"Procedure", Vessel->"Vessel"
TrashHierarchyItem(item):
    ti = TrashedItem{ ItemType: TrashType(kind), ItemId: item.Id, Name: item.Name, KindLabel: KindLabel(kind),
                      PayloadJson: serialize(item as its runtime type, TrashOpts) }   // DeletedUtc = UtcNow, BatchId = Empty
    remove item from its collection (top-level only)
    AddToTrash(ti)  -> Trash.append(ti); PruneTrash()
    LogRemoved(KindLabel, item.Name, "moved to Trash"); MarkDirty(); return ti
TrashCrew(m): ItemType "Crew", Name = FullName blank ? LastName : FullName, KindLabel "Crew member", PayloadJson = serialize(m)
TrashHierarchyItems(items): batch = newGuid(); for item in snapshot(items): ti = TrashHierarchyItem(item); if ti: ti.BatchId = batch; n++
PruneTrash(): cutoff = UtcNow - 90 days
    for i from last to first: if Trash[i].DeletedUtc < cutoff: EvictAt(i)
    while Trash.count > 200: EvictAt(indexOf(min by DeletedUtc))
    if anything changed: MarkDirty()
EvictAt(i): PurgeReferences(Trash[i].ItemId); Trash.removeAt(i)
RestoreTrash(ti): deserialize PayloadJson as the type named by ItemType (TrashOpts); null or exception -> return null
    add to its collection ONLY IF no live item has the same Id (else silently dropped)   [FAITHFUL; see D-11]
    Trash.remove(ti); LogAdded(ti.KindLabel, ti.Name, "restored from Trash"); MarkDirty(); return ti.ItemType
UndoLastDelete(): newest = max by DeletedUtc; none -> []
    batch = newest.BatchId == Empty ? [newest] : all with same BatchId ordered by DeletedUtc desc
    restore each, collecting distinct ItemTypes in order; continue past failures
PendingUndoCount(): 0 | 1 | count of newest's batch
PurgeTrash(ti): if Trash.remove(ti): PurgeReferences(ti.ItemId); MarkDirty()
EmptyTrash(): if empty return; PurgeReferences for each; clear; MarkDirty()
```
`TrashOpts` = `{ ReferenceHandler = IgnoreCycles, DefaultIgnoreCondition = WhenWritingNull }` — identical output
to `Opts` (compact). "Newest" ties: `OrderByDescending(...).First()` is stable → the earliest-inserted of equal stamps.

`PurgeReferences(id)` (`:186`): for every top-level item remove `id` from `RelatedIds`; Equipment also from
`ProcedureIds`, `TaskIds`; Procedure: every step's `TaskIds`, `EquipmentIds`; then every container in
`AllContainers()` → every file's `LinkedItemIds`. (Does not touch subtasks' `RelatedIds`, bucket lists, pins,
schedules — [FAITHFUL].)

### 3.18 Recurrence — `AppRepository.cs:535-643`

```
NextOccurrence(from, r): Daily +1 day; Weekly +7 days; Monthly AddMonths(1); Yearly AddYears(1); None -> from
   (AddMonths/AddYears clamp to the last day of the target month: Jan 31 + 1M = Feb 28/29; Feb 29 + 1Y = Feb 28)
ReconcileRecurrences():
  for t in snapshot(Tasks) where t.Recurrence != None && t.IsComplete && !t.RecurrenceSpawned:
     t.RecurrenceSpawned = true
     clone = deepClone(t)                   // JSON round-trip with TrashOpts
     RenewTask(clone)
     old = t.Deadline; next = NextOccurrence(old ?? DateTime.Today, t.Recurrence)
     if t.RangeStart is rs && old is dl && rs.Date < dl.Date: clone.RangeStart = next.AddDays(-(dl.Date - rs.Date).Days)
     else clone.RangeStart = null
     clone.Deadline = next
     if old is od: ShiftChildren(clone, next.Date - od.Date)
     append clone (after the loop); LogAdded("Task (recurring)", clone.Name, "next {Recurrence} occurrence → {next:yyyy-MM-dd}")
  for p in snapshot(Procedures) where p.Recurrence != None && p.Status == Done && !p.RecurrenceSpawned:
     p.RecurrenceSpawned = true; clone = deepClone(p); RenewProcedure(clone)
     old = p.Deadline; next = NextOccurrence(old ?? Today, p.Recurrence); clone.Deadline = next
     if old is od: for each step s with Deadline sd: s.Deadline = sd + (next.Date - od.Date)
     append; LogAdded("Procedure (recurring)", clone.Name, "next {Recurrence} occurrence → {clone.Deadline:yyyy-MM-dd}")
  if anything: MarkDirty(); return changed
RenewTask(t): t.Id = new; t.Container.Id = new; RecurrenceSpawned = false; ScheduledStart = null
              IsComplete = false (→ Status Todo); recurse into Subtasks
ShiftChildren(t, Δ): for st in t.Subtasks: Deadline += Δ; RangeStart += Δ (if set); recurse
RenewProcedure(p): Id, Container.Id new; RecurrenceSpawned = false; ScheduledStart = null; Status = Todo
                   each step: Id, Container.Id new; Done = false; ScheduledStart = null
```
Only top-level tasks/procedures recur. File item Ids inside cloned containers are **not** renewed. `DateTime`
arithmetic preserves `Kind` and time-of-day; `DateTime.Today` is Local-kind (so an undated recurring task gets a
Local deadline with an offset in JSON).

### 3.19 Task working-range helpers — `Models.cs:189-211`

* `HasRange = RangeStart != nil && Deadline != nil && RangeStart.Date < Deadline.Date`
* `RangeFirst = RangeStart ?? Deadline`
* `WhenText = Deadline == nil ? "" : (RangeStart != nil && RangeStart.Date < Deadline.Date ? "{start:yyyy-MM-dd} → {deadline:yyyy-MM-dd}" : "{deadline:yyyy-MM-dd}")`
* `CoversDay(day)`: no deadline → false; `end = Deadline.Date`; `start = (RangeStart != nil && RangeStart.Date <= end) ? RangeStart.Date : end`; `start <= day.Date <= end`. (An out-of-order range collapses to the deadline day.)
The model applies **no** clamping on load (RangeStart after Deadline is kept as-is). `.Date` = wall-clock
midnight of the stored value (no time-zone conversion).

### 3.20 Legacy `BucketId` — `Models.cs:111`

Getter always returns null (so it is never written — `WhenWritingNull`). Setter: if the value is a Guid not
already in `BucketIds`, append it. Windows reads keys in document order and **assigns a new collection** when it
reaches `"BucketIds"`, so a legacy file with `BucketId` **before** `BucketIds` would lose the legacy value; legacy
files only have `BucketId`, so this does not occur in practice. The Mac MUST: decode `BucketIds` (default []),
then, if a non-null `BucketId` exists and is not contained, append it — regardless of key order.

### 3.21 Identity & de-dup keys

| Key | Formula |
|---|---|
| `PortCall.Key` | `PortName.ToLowerInvariant() + "@" + ArrivalDate` |
| `Port.Key` | `UnLocode != "" ? UnLocode.ToLowerInvariant() : (Name + "\|" + Country).ToLowerInvariant()` |
| `PortVisit.VisitKey` | `(VesselName + "\|" + ArrivalDate + "\|" + ArrivalTime).ToLowerInvariant()` |
| `CrewMember.Key` | `EmployeeId` if not blank/whitespace, else `(FirstName + "\|" + LastName).Trim('\|')` |
| `ShipJob` | primary key `JobNo` (Shippalm "No.") |

`ToLowerInvariant` = Unicode simple lower-casing, culture-invariant (Swift `lowercased()` with no locale is close;
avoid `lowercased(with: Locale(identifier:"tr"))`-style locale casing).

### 3.22 Display strings (must be byte-identical)

* `FileItem.SourceLabel`: `IsLink ? "Web link" : LinkInPlace ? "Live" : "Copy"`.
* `ChecklistTemplate.Display`: `"{Name or (unnamed)}  ·  {n} item{s}"` — two spaces around `·` (U+00B7); `item` if n == 1 else `items`.
* `ScheduleTemplate.Display`: `"{Name or (unnamed)}  ·  {n} entr{y|ies}"` + (`VesselName != "" ? "  ·  {VesselName}" : ""`).
* `QuickBucket.Display`: `Category != "" ? "{Name}  ·  {Category}" : (Name != "" ? Name : "(unnamed)")`.
* `TrashedItem.DeletedLocal`: `DeletedUtc.ToLocalTime()` as `yyyy-MM-dd HH:mm`.
* `TrashedItem.Display`: `"{Name or (unnamed)}   ·   {KindLabel}   ·   deleted {local yyyy-MM-dd HH:mm}"` (three spaces each side).
* `LogEntry.TimeUtc`: `"yyyy-MM-dd HH:mm:ss 'UTC'"` → e.g. `2026-09-29 08:15:30 UTC`; `TimeLocal`: `ToLocalTime()` `yyyy-MM-dd HH:mm:ss`.
* `ScheduleEntry.KindIcon`: Task `✓`, Procedure `📋`, Equipment `⚙`, else `•`; `WhenDisplay = "{Date} {Time}".Trim()`.
* `PortCall.DisplayName = Country != "" ? "{PortName}, {Country}" : PortName`; `ArrivalDisplay = "{ArrivalDate} {ArrivalTime}".Trim()`; `DepartureDisplay` likewise; `PortVisit` has the same two.
* `Port.Display = (UnLocode != "" ? "{Name} ({UnLocode})" : Name) + (Country != "" ? ", {Country}" : "")`.
* `BundleSource.WrittenLocal`: `WrittenUtc == default ? "" : WrittenUtc.ToLocalTime() yyyy-MM-dd HH:mm`.
* `CrewMember.FullName`: non-blank of First, Middle, Last joined by one space.
* `AppRepository.Label(id)`: `"[{Kind}] {Name}"` (enum name, e.g. `[Equipment]`) or `"(missing)"`.
* `AppRepository.KindLabel`: `Equipment/Area`, `Task`, `Procedure`, `Vessel`.

`ToLocalTime()` on a `Utc` or `Unspecified` value converts from UTC to local; on a `Local` value it is a no-op.

### 3.23 Dates on crew and jobs — `CrewMember.cs:118-151`, `Models.cs:390-398`

```
ParseDate(s): if blank -> null; s = trim(s)
   for fmt in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"]: exact parse (InvariantCulture) -> return
   DateTime.TryParse(s, InvariantCulture, None) -> return      // month-first for ambiguous a/b/yyyy
   null
DaysUntilSignOff(today) = ParseDate(SignOffDate) == null ? null : (int)(d.Date - today.Date).TotalDays
ContractStatusOn(today, critical = 30, soon = 60):
   null -> Unknown; days < 0 -> Expired; days <= 30 -> Critical; days <= 60 -> DueSoon; else Ok
ShipJob.DaysUntilDue(today): same arithmetic on ParseDate(DueDate)
```
The invariant fallback accepts (among others) `M/d/yyyy`, `MM/dd/yyyy`, `yyyy-MM-ddTHH:mm[:ss]`,
`d MMM yyyy`, `MMM d, yyyy`, `dddd, MMMM d, yyyy`; a string with `Z`/offset is converted to local time. The Mac
port MUST implement the three exact formats and SHOULD implement the fallback for at least: `M/d/yyyy`
(month-first), `yyyy-MM-ddTHH:mm[:ss[.f+]]` with optional `Z`/offset, `d MMM yyyy`, `d MMMM yyyy`,
`MMM d, yyyy`, `MMMM d, yyyy` (English month names, case-insensitive). Stored values are canonical
`yyyy-MM-dd` today (DateResolver spec), so the fallback matters only for legacy data. [FAITHFUL month-first]

`ContractStatus` enum: `Unknown, Ok, DueSoon, Critical, Expired` (not persisted).

### 3.24 Repository lookups and relations — `AppRepository.cs:74-223, 645-675`

* `AllItems()` = Equipment, then Tasks, then Procedures, then Vessels (top level only).
* `FindById(id)` = first of `AllItems()` with that id, else nil (subtasks are **not** found).
* `AllContainers()` = same set/order as `EnumerateContainers` (DATA-068).
* `AllJobs()` = every `IsJob` task recursively (pre-order), then per procedure: the procedure itself if `IsJob`,
  then its `IsJob` steps; then each crew member's `IsJob` checklist steps.
* `RelatedItems(item)` = distinct ids of `RelatedIds` (+ for Equipment its `ProcedureIds` and `TaskIds`) resolved
  via `FindById`, missing ones skipped; order = hash-set iteration (unspecified).
* `ReferencedBy(target)` = every item (≠ target) whose `RelatedIds` contains the id, or (Equipment) whose
  `ProcedureIds`/`TaskIds` contain it, or (Procedure) any step whose `TaskIds`/`EquipmentIds` contain it.
* `AddRelation(a, b)`: no-op if same id; add each id to the other's `RelatedIds` if absent.
* `RemoveRelation(a, b)`: remove both directions.
* Groups: `GroupsFor(kind)` filter by `Kind`; `CreateGroup(kind, name)` appends `ItemGroup{Kind, Name = blank ? "New group" : trim}`;
  `RenameGroup(g, n)`: blank ignored, else trimmed; `DeleteGroup(g)`: every item with `GroupId == g.Id` → null, then remove g;
  `AssignToGroup(items, id?)`.
  None of these call `MarkDirty` — callers do.

### 3.25 Copy helpers

* `QuickCard.Clone()` → new object with **the same Id** and all fields copied.
* `QuickCard.CopyFrom(o)` → copies every field except `Id`.
* `ShipJob.CopyFrom(o)` → copies all 19 persisted fields (JobNo, Title, WorkPlanNo, Status, ClassCode, Category,
  ResponsibleRank, FunctionNo, FunctionDescription, Interval, DueStatus, DueDate, FinishedDate, LastDoneDate,
  OverdueDays, Notify, IsCompleted, CompletedDate, ImportedAt).

### 3.26 `SireState` — `Sire/SireState.cs`

* `GetStatus(q)`: `QuestionStatuses[q]` parsed with `Enum.TryParse<QuestionStatus>` (case-**sensitive** name;
  also accepts numeric strings like `"2"`); missing/unparseable → `None`.
* `SetStatus(q, s)`: `None` removes the key; else stores the enum **name** (`"InProgress"`, `"Checked"`, `"NotApplicable"`).
* `CountByStatus(s)`: count of values equal to the name.
* `ToggleBookmark(q)`, `ToggleForExport(q)`: remove if present else append.
* `GetTasksForQuestion(q)`: tasks with `QuestionNumber == q` in list order.
* `QuestionNumberComparer`: split on `.`, parse each part as int (non-numeric → 0), compare component-wise, missing parts = 0.

### 3.27 Startup sequence (normative order) — `App.xaml.cs`, `MainWindow.OnLoaded`

1. Install crash handlers (DATA-004).
2. `LoadSettings()`; apply theme.
3. Splash 2.4 s → login (quit on cancel) → main window.
4. `LoadDataAndInitUi()` (DATA-020), start 5-min autosave timer, sync menu check-marks from settings
   (`SyncOnSave`, `TextOnlyExport`, `DarkMode`, `EncryptLocalData`), set title `"AA — {identity}"`.
5. Safe-mode alert, else newer-schema alert.
6. Drive: if sync-on-save and configured and signed in → background newer-save check; else if configured and
   needs re-consent → info alert (Drive spec).
7. Shared save: `lastSeen = lastSynced = LastModified`; start machinery; queue an update check.
8. Tray + 30-min reminder timer (reminders spec).
9. If not safe mode, queued at background priority: `PruneTrash()`; `ReconcileRecurrences()` (reload task &
   procedure lists if anything spawned); daily digest; reminders.

---

## 4. Data formats

### 4.1 The serializer contract (System.Text.Json as configured by AA)

`DataStore.Opts` (`DataStore.cs:267`) — used for `data.json`, `settings.json`, `source.json`, bundle peeks:

```csharp
new JsonSerializerOptions {
    WriteIndented = false,                                  // compact
    ReferenceHandler = ReferenceHandler.IgnoreCycles,       // no $id/$ref metadata; a cycle would write null
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
}
```
Everything else is the System.Text.Json (.NET 10) default. `AppRepository.TrashOpts` produces identical output.
Consequences, each a MUST for the Mac reader/writer unless marked SHOULD:

#### 4.1.1 Property names
* Exactly the C# property names, **PascalCase**, no naming policy (`"Id"`, `"RichTextXaml"`, `"LastModified"`).
* Reading is **case-sensitive**: `"id"` is an unknown key (dropped, or kept in `ExtraData` where it exists).
* Dictionary keys are written verbatim (no key policy).

#### 4.1.2 Which properties are written
* Every **public instance property with a public getter**, including get-only ones, **except** those marked
  `[JsonIgnore]`. Fields and non-public members are never written. (§4.2 lists the exact set per type; all
  computed helpers are `[JsonIgnore]`.)
* `HierarchyItem.Kind` is **not** written: the overrides are `[JsonIgnore]` and System.Text.Json skips a virtual
  base property whose override is ignored. An item's kind is implied by the top-level array it lives in (and by
  `TrashedItem.ItemType` for trash payloads).
* `HierarchyItem.BucketId` has a getter that always returns null → never written.
* **Null** reference values and null `Nullable<T>` values are **omitted** (`WhenWritingNull`). Non-null defaults
  (`false`, `0`, `""`, `[]`, `{}`, `Guid.Empty`) **are** written.
* `[JsonExtensionData]` dictionaries (`AppData.ExtraData`, `UiState.ExtraData`, `Settings.ExtraData`) are
  flattened into the containing object **after** all regular properties, each value written as its original raw
  JSON. When no unknown keys were read the dictionary is null and nothing is written.

#### 4.1.3 Property order (SHOULD emulate; readers MUST NOT depend on it)
System.Text.Json's reflection resolver walks the type hierarchy **from the most-derived type up**: the derived
class's declared properties first, then the base class's, each group in source declaration order; extension data
last. Example for a Task: `Deadline, RangeStart, IsJob, DurationMinutes, ScheduledStart, Recurrence,
RecurrenceSpawned, IsComplete, Status, Subtasks, Id, Name, Description, Container, RelatedIds, Tags, GroupId,
BucketIds, LockHash, LockSalt, LockHint`. §4.2 lists every type in this order.
*Verification TODO:* confirm against a `data.json` produced by the Windows build (Tests fixture) before
declaring byte-level golden tests final. Order only matters for byte-identical output and for the
`IsComplete`/`Status` read-order subtlety (§4.2.6); Flash Sync compares objects order-insensitively
(`FlashChangeSet.DeepEquals`).

#### 4.1.4 Value encodings

| C# type | JSON | Write format | Read acceptance (Windows) |
|---|---|---|---|
| `string` | string | escaped per §4.1.7 | any JSON string; JSON `null` → property set to null (then omitted on next write) |
| `bool` | `true`/`false` | | only literals; `null` → **load failure** |
| `int` | number | invariant integer | integer literal only (no `"5"`, no `5.0`) |
| `double` | number | shortest round-trip (`24` not `24.0`; `0.1`; exponent form `1E+15` and above, capital `E`) | any number literal; `NaN`/`Infinity` → failure |
| **enums** | **number** | underlying `int` value (no string-enum converter anywhere in AA) | integer; any integer accepted even if undefined; a string → **load failure** |
| `Guid` | string | `"D"` format, **lowercase** hex: `"3f2504e0-4f89-11d3-9a0c-0305e82c3301"` | 36-char `8-4-4-4-12`, hex digits any case; other forms (braces, 32-digit) → failure |
| `Guid.Empty` | string | `"00000000-0000-0000-0000-000000000000"` (never omitted) | |
| `DateTime` / `DateTime?` | string | §4.1.5 | §4.1.5 |
| `ObservableCollection<T>`, `List<T>` | array | elements in collection order | `null` → property null (crash-prone; Mac: treat as empty) |
| `Dictionary<string,T>` | object | insertion order | duplicate keys: last wins |
| nested class | object | | `null` → property null (Mac: treat as default instance) |

#### 4.1.5 DateTime format (critical)

System.Text.Json writes a `DateTime` as ISO-8601 extended, **fraction trimmed**, suffix by `Kind`:

```
yyyy-MM-dd'T'HH:mm:ss[.F{1..7}] + ( "" | "Z" | ±HH:mm )
                                    Unspecified  Utc   Local (offset of the local zone AT that local time)
```
* The fraction is the 7-digit tick fraction with trailing zeros removed; if it is zero there is **no** `.` at all.
* `Kind = Local` writes the machine's current UTC offset for that local date-time (`+00:00` in a zero-offset
  zone — **never** `Z` for Local).
* Examples: `2026-10-01T00:00:00` (Unspecified), `2026-09-29T08:15:30.123456Z` (Utc, ticks …1234560),
  `2026-09-29T11:15:30.5+03:00` (Local).

Reading (System.Text.Json):
* Accepts `yyyy-MM-dd`, `yyyy-MM-ddTHH:mm`, `yyyy-MM-ddTHH:mm:ss`, with optional fraction, optional `Z` or
  `±HH:mm` offset. A space instead of `T`, or any other shape → **failure**.
* No offset → `Kind = Unspecified`, wall clock kept as written.
* `Z` → `Kind = Utc`, value kept.
* `±HH:mm` → converted to the **reading machine's local time zone**, `Kind = Local`.
  So `"2026-10-01T00:00:00+03:00"` read on a machine in New York (UTC−4 that day) becomes local
  `2026-09-30 17:00:00`, and is re-written as `"2026-09-30T17:00:00-04:00"`. Same instant, different wall clock.
* .NET compares and equates `DateTime` by **ticks only**, ignoring `Kind`.

Which fields carry which kind in practice (important for faithful round-trips and for cross-time-zone use):

| Field | Written by | Typical kind |
|---|---|---|
| `AppData.LastModified` | `DateTime.Now` | Local (offset) |
| `FileItem.Added` | `DateTime.Now` (also the default when missing) | Local |
| `SireTask.CreatedAt` | `DateTime.Now` | Local |
| `*.CreatedUtc`, `TrashedItem.DeletedUtc`, `LogEntry.TimestampUtc`, `BundleSource.WrittenUtc` | `DateTime.UtcNow` | Utc (`Z`) |
| `BundleSource.LastModified` | parsed from the data file | Local |
| `TaskItem.Deadline`/`RangeStart`, `Procedure.Deadline`, `ChecklistStep.Deadline` | date pickers | mostly Unspecified midnight; Local when derived from `DateTime.Today` (recurrence of an undated task, planner drops) |
| `*.ScheduledStart` | planner (day + minutes) | Local or Unspecified depending on the source day value |
| `UiState.CalendarSelectedDate` | calendar control | Unspecified (Local if it was `DateTime.Today`) |

**Mac requirement:** model every persisted DateTime as a value type that stores **wall-clock ticks + kind**
(`NetDateTime { ticks: Int64; kind: .unspecified | .utc | .local }`), not as `Foundation.Date`:
* parse exactly as above (offset → convert to `TimeZone.current` wall clock, kind `.local`);
* write exactly as above (for `.local`, compute the offset with `TimeZone.current.secondsFromGMT(for:)` of the
  corresponding instant);
* compare/equate by ticks only;
* keep 100 ns precision (a `Double`-based `Date` cannot represent every tick; equality checks such as the
  shared-save "already seen" test depend on exact ticks);
* when the Mac *creates* a value, use the kind Windows would: `Now` → `.local`; `UtcNow` → `.utc`; a user-picked
  calendar date → `.unspecified` midnight; "today"-derived dates → `.local` midnight (or `.unspecified` — both
  are read by Windows; `.unspecified` is safer across time zones; see Q-6).
Ticks: `0001-01-01T00:00:00` = 0; one tick = 100 ns; Unix epoch = `621355968000000000`;
`2026-10-01T00:00:00` = `639264096000000000`.

#### 4.1.6 Numbers
* `int` values: `SchemaVersion`, `SelectedMainTabIndex`, `DurationMinutes`, `OverdueDays`, enum values.
* `double` values: `QuickCard.X/Y/Width/Height`, `UiState.Window*`, `DueWindow*`, `CalendarFontScale`.
  Mac writer: integral doubles with |x| < 1e15 → integer text (`180`, `-24`); else the shortest round-trip form
  with `E` (e.g. `12.5`, `0.30000000000000004`, `1E+16`). `-0.0` writes `-0`. Never write `NaN`/`Infinity`
  (clamp/skip — a `NaN` window coordinate would make Windows' save throw and its load fail).

#### 4.1.7 String escaping (default `JavaScriptEncoder`) — SHOULD emulate for golden files
Readers accept any valid JSON escaping. Windows writes:
* ASCII letters, digits, space and ``! # $ % ( ) * , - . / : ; = ? @ [ ] ^ _ { | } ~`` literally;
* `"` → `\u0022`, `\` → `\\`, `&` → `\u0026`, `'` → `\u0027`, `+` → `\u002B`, `<` → `\u003C`, `>` → `\u003E`,
  `` ` `` → `\u0060`;
* `\b \t \n \f \r` → those short escapes; other C0 controls and U+007F → `\u00XX`;
* **every non-ASCII character** → `\uXXXX` (uppercase hex); non-BMP → surrogate pair (`😀` → `\uD83D\uDE00`).
So a Windows `data.json` is pure ASCII: `"Icon":"\u2693"`, rich text looks like
`"RichTextXaml":"\u003CSection xmlns=\u0022http://schemas…\u0022 …"`. Property names and dictionary keys are
escaped the same way.

#### 4.1.8 Encoding & framing
UTF-8 without BOM on write; a UTF-8 BOM is tolerated on read (`ReadDataText`, `File.ReadAllText`). No trailing
newline. Comments and trailing commas are rejected on read.

#### 4.1.9 Depth limit
`MaxDepth` = 64 on read **and** write. A document nested deeper cannot be written by Windows (save throws) nor
read (load fails → safe mode). The deepest structure is the subtask tree: a top-level task object is at depth 3,
each subtask level adds 2, and a file's `LinkedItemIds` array sits 4 below its task — so Windows supports about
**28 levels of subtasks** with attachments. The Mac MUST refuse (with a clear message) to create a structure
that would exceed depth 64, and MUST never write one.

#### 4.1.10 Missing keys and JSON null (read defaults)
System.Text.Json constructs each object with its **parameterless constructor**, so a key that is missing keeps
the C# initializer value — *including* `Id = Guid.NewGuid()` (a missing `Id` becomes a fresh random id on every
load), `Added = DateTime.Now`, `DurationMinutes = 60`, `Expanded = true`, `ShowShortcutBar = true`,
`NotificationsEnabled = true`, `Icon = "⚓"`, `Color = "#FF1E88E5"`, `X = Y = 24`, `Width = 180`, `Height = 120`,
`UserType = "Crew"`, `SignedOnOff = "On"`, `Status = Todo`, `CreatedUtc/DeletedUtc/TimestampUtc = UtcNow`,
`CreatedAt = Now`. The Mac decoder MUST apply exactly these defaults (tables below). For explicit JSON `null`:
Windows assigns null to reference-typed properties (strings, collections, nested objects) and fails on value
types; the Mac SHOULD map null to the default for reference-typed properties and MUST NOT emit null itself.

### 4.2 `data.json` schema (every persisted type)

Column **Default** = value when the key is missing. **Order** is the emission order (§4.1.3).
`Guid?` / `DateTime?` / `string?` rows are omitted from JSON when null.

#### 4.2.1 `AppData` (root) — `Models.cs:605`
| # | Key | JSON | Default | Notes |
|---|---|---|---|---|
| 1 | `Equipment` | array of Equipment | `[]` | top-level Equipment/Area items |
| 2 | `Tasks` | array of TaskItem | `[]` | top-level tasks (subtasks nest) |
| 3 | `Procedures` | array of Procedure | `[]` | |
| 4 | `Vessels` | array of Vessel | `[]` | |
| 5 | `Groups` | array of ItemGroup | `[]` | sidebar groups, all kinds |
| 6 | `Crew` | array of CrewMember | `[]` | |
| 7 | `Log` | array of LogEntry | `[]` | ≤ 10 000, oldest first |
| 8 | `ChecklistTemplates` | array of ChecklistTemplate | `[]` | array order = user arrangement (Saved Lists) |
| 9 | `ListGroups` | array of ListGroup | `[]` | |
| 10 | `QuickBuckets` | array of QuickBucket | `[]` | |
| 11 | `Ports` | array of Port | `[]` | global ports database |
| 12 | `ScheduleTemplates` | array of ScheduleTemplate | `[]` | |
| 13 | `Trash` | array of TrashedItem | `[]` | ≤ 200, ≤ 90 days |
| 14 | `Sire` | SireState | `{…empty}` | |
| 15 | `Ui` | UiState | `{…defaults}` | |
| 16 | `LastModified` | DateTime? | omitted | Local; stamped on user saves |
| 17 | `SchemaVersion` | int | `0` | written as ≥ 1 |
| — | *(unknown keys)* | any | — | preserved (`ExtraData`), appended last |

A freshly created database saved by Windows (no stamp yet) is exactly:
```json
{"Equipment":[],"Tasks":[],"Procedures":[],"Vessels":[],"Groups":[],"Crew":[],"Log":[],"ChecklistTemplates":[],"ListGroups":[],"QuickBuckets":[],"Ports":[],"ScheduleTemplates":[],"Trash":[],"Sire":{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}},"Ui":{"SelectedMainTabIndex":0,"ShowShortcutBar":true,"QuickViewPinIds":[],"TabColors":{},"TabOrder":[],"SortAZ":{},"GroupExpanded":{},"CrewTableColumns":[],"CrewTableShownColumns":[]},"SchemaVersion":1}
```

#### 4.2.2 `HierarchyItem` base keys (emitted **after** each subclass's own keys) — `Models.cs:89`
| Key | JSON | Default | Notes |
|---|---|---|---|
| `Id` | Guid | new Guid | identity used everywhere |
| `Name` | string | `""` | |
| `Description` | string | `""` | plain text |
| `Container` | Container | new | rich text + file bank |
| `RelatedIds` | [Guid] | `[]` | two-way relations |
| `Tags` | [string] | `[]` | free-form, no `#` |
| `GroupId` | Guid? | omitted | sidebar `ItemGroup.Id`; null = ungrouped |
| `BucketIds` | [Guid] | `[]` | UI caps at 2; model does not enforce |
| `BucketId` | Guid? | never written | legacy, read-only migration (§3.20) |
| `LockHash` | string? | omitted | Base64(32-byte PBKDF2) |
| `LockSalt` | string? | omitted | Base64(16 bytes) |
| `LockHint` | string? | omitted | trimmed; blank → omitted |
`IsLockProtected` = `LockHash` and `LockSalt` both non-empty (not written).

#### 4.2.3 `Container` — `Models.cs:50`
| Key | JSON | Default | Notes |
|---|---|---|---|
| `Id` | Guid | new | |
| `RichTextXaml` | string | `""` | WPF XAML (§4.11) or legacy `enc:` blob (§4.7) |
| `Files` | [FileItem] | `[]` | |
| `SharedWithContainerIds` | [Guid] | `[]` | reserved; round-trip only |
| `IsLocked` | bool | `false` | legacy flag; the editor clears it on open |

#### 4.2.4 `FileItem` — `Models.cs:26`
| Key | JSON | Default | Notes |
|---|---|---|---|
| `Id` | Guid | new | |
| `Name` | string | `""` | display name |
| `Path` | string | `""` | `files/<32hex>_<name>` (copy), absolute/UNC path (live), URL (link) |
| `Kind` | int `FileKind` | `0` | Document 0, Image 1, Video 2, Link 3, Other 4 |
| `Added` | DateTime | `Now` | Local |
| `IsLink` | bool | `false` | URL entry |
| `LinkInPlace` | bool | `false` | live reference, never rewritten |
| `LinkedItemIds` | [Guid] | `[]` | item ids this file is linked to |

#### 4.2.5 `Equipment` (+ base) — `Models.cs:141`
Own keys first: `ProcedureIds` [Guid] `[]`, `TaskIds` [Guid] `[]`, `Components` [Component] `[]`; then §4.2.2.

`Component`: `Id` Guid (new), `Name` string `""`, `Notes` string `""` (one-line), `Container` Container (new).

#### 4.2.6 `TaskItem` (+ base) — `Models.cs:167`
| Key | JSON | Default | Notes |
|---|---|---|---|
| `Deadline` | DateTime? | omitted | range end |
| `RangeStart` | DateTime? | omitted | range first day (TaskItem only) |
| `IsJob` | bool | `false` | |
| `DurationMinutes` | int | `60` | |
| `ScheduledStart` | DateTime? | omitted | planner slot |
| `Recurrence` | int `RecurrenceKind` | `0` | None 0, Daily 1, Weekly 2, Monthly 3, Yearly 4 |
| `RecurrenceSpawned` | bool | `false` | |
| `IsComplete` | bool | `false` | kept in sync with Status |
| `Status` | int `WorkStatus` | `0` | Todo 0, InProgress 1, Blocked 2, Done 3 |
| `Subtasks` | [TaskItem] | `[]` | recursive |
then §4.2.2.

**Read-order subtlety [FAITHFUL outcome]:** Windows applies setters in document order, each keeping the other in
sync (DATA-130). With the canonical order (`IsComplete` before `Status`) the net effect is: **`Status` wins**
and `IsComplete = (Status == Done)`. If only `IsComplete` is present (legacy) → `Status = IsComplete ? Done : Todo`.
If only `Status` → `IsComplete = (Status == Done)`. The Mac decoder MUST implement exactly this rule (it is
order-independent and equals Windows for every Windows- or canonically-ordered file).

#### 4.2.7 `Procedure` (+ base) — `Models.cs:254`
Own keys: `Steps` [ChecklistStep] `[]`, `Deadline` DateTime? (omitted), `Recurrence` int `0`,
`RecurrenceSpawned` bool `false`, `Status` int `0`, `IsJob` bool `false`, `DurationMinutes` int `60`,
`ScheduledStart` DateTime? (omitted); then §4.2.2. (No `IsComplete`; no `RangeStart`.)

#### 4.2.8 `ChecklistStep` — `Models.cs:454`
`Id` Guid (new), `Title` string `""`, `BucketIds` [Guid] `[]`, `Done` bool `false`, `Deadline` DateTime? (omitted),
`IsJob` bool `false`, `DurationMinutes` int `60`, `ScheduledStart` DateTime? (omitted), `TaskIds` [Guid] `[]`,
`EquipmentIds` [Guid] `[]`, `Container` Container (new). Used by procedures **and** crew checklists.

#### 4.2.9 `Vessel` (+ base) — `Models.cs:283`
Own keys: `QuickCards` [QuickCard] `[]`, `Jobs` [ShipJob] `[]`, `NotificationsEnabled` bool **`true`**,
`PortCalls` [PortCall] `[]`; then §4.2.2.

`QuickCard` — `Models.cs:416`: `Id` Guid (new), `Title` `""`, `Target` `""` (relative `files/…`, absolute
path, or URL), `IsLink` false, `LinkInPlace` false, `IsFolder` false, `Icon` **`"⚓"`**, `Color`
**`"#FF1E88E5"`** (WPF colour string, **#AARRGGBB** — alpha first — or #RRGGBB; also any WPF-parsable form),
`X` 24, `Y` 24, `Width` 180, `Height` 120 (doubles).

`ShipJob` — `Models.cs:360` (no `Id`; keyed by `JobNo`): `JobNo`, `Title`, `WorkPlanNo`, `Status` (Shippalm
text), `ClassCode`, `Category`, `ResponsibleRank`, `FunctionNo`, `FunctionDescription`, `Interval`,
`DueStatus`, `DueDate` (`yyyy-MM-dd`), `FinishedDate`, `LastDoneDate` — all strings default `""`;
`OverdueDays` int `0`; `Notify` bool `false`; `IsCompleted` bool `false`; `CompletedDate` string `""`
(`yyyy-MM-dd`); `ImportedAt` string `""`.

`PortCall` — `Models.cs:303`: `Id` Guid (new), then strings (default `""`): `PortName`, `Country`, `UnLocode`,
`PortFacility`, `PfNo`, `ArrivalDate` (`yyyy-MM-dd`), `ArrivalTime` (`HH:mm`), `DepartureDate`,
`DepartureTime`, `SecurityLevelPort`, `SecurityLevelVessel`, `SspFollowed` (`YES`/`NO`/blank),
`SpecialMeasures`, `ImportedAt`.

#### 4.2.10 `Port` / `PortVisit` — `Models.cs:330, 342`
`Port`: `Id` Guid (new), `Name` `""`, `Country` `""`, `UnLocode` `""`, `Visits` [PortVisit] `[]`.
`PortVisit` (no Id): `VesselName` `""`, `VesselId` Guid? (omitted), `ArrivalDate`, `ArrivalTime`,
`DepartureDate`, `DepartureTime`, `ImportedAt` (strings `""`).

#### 4.2.11 `ItemGroup` — `Models.cs:132`
`Id` Guid (new), `Kind` int `ItemKind` (Equipment 0, Task 1, Procedure 2, Vessel 3; default 0), `Name` `""`,
`Expanded` bool **`true`** (round-trip only; UI expansion lives in `Ui.GroupExpanded`).

#### 4.2.12 `CrewMember` — `CrewMember.cs:36`
`Id` Guid (new), `Checklist` [ChecklistStep] `[]`, `Schedule` [ScheduleEntry] `[]`, `ScheduleVesselId` Guid?
(omitted), then strings (default `""` unless noted): `EmployeeId`, `FirstName`, `MiddleName`, `LastName`,
`Nationality`, `DateOfBirth`, `PlaceOfBirth`, `Gender`, `Height`, `EyesColor`, `HairColor`, `UserType`
(**`"Crew"`**), `Rank`, `RankCode`, `SignedOnOff` (**`"On"`**), `Company`, `Vessel`, `SignOnDate`,
`SignOnPort`, `SignOnPortRaw`, `SignOffDate`, `SignOffPort`, `SignOffPortRaw`, `PassportNumber`,
`PassportExpiry`, `PassportIssued`, `SeamansBookNumber`, `SeamansBookExpiry`, `SeamansBookIssued`, `CocNumber`,
`CocExpiry`, `CocIssue`, `HealthCertExpiry`, `NokFirstName`, `NokLastName`, `NokRelationship`,
`RawNationality`, then `Flags` [CrewReviewFlag] `[]`, `ImportedAt` `""`, `SourceFile` `""`.
Dates inside crew records are **strings** (canonical `yyyy-MM-dd`).

`CrewReviewFlag`: `Severity` int (Info 0, Warning 1, Error 2), `Field` `""`, `Message` `""`.

#### 4.2.13 `ScheduleEntry` / `ScheduleTemplate` — `Models.cs:529, 550`
`ScheduleEntry`: `Id` Guid (new), `Title` `""`, `Kind` int `ScheduleKind` (Note 0, Task 1, Procedure 2,
Equipment 3; default 0), `RefId` Guid? (omitted), `Date` `""` (`yyyy-MM-dd`), `Time` `""` (`HH:mm`),
`EndDate` `""`, `EndTime` `""`, `Done` bool `false`, `Notes` `""`.
`ScheduleTemplate`: `Id`, `Name` `""`, `VesselId` Guid? (omitted), `VesselName` `""`, `Entries` `[]`,
`CreatedUtc` DateTime (UtcNow).

#### 4.2.14 `ChecklistTemplate` / `ChecklistTemplateItem` / `ListGroup` — `Models.cs:487-522`
`ChecklistTemplate`: `Id`, `Name` `""`, `Items` [ChecklistTemplateItem] `[]`, `CreatedUtc` (UtcNow),
`GroupId` Guid? (omitted).
`ChecklistTemplateItem` (no Id): `Title` `""`, `DurationMinutes` int `60`, `IsJob` bool `false`, `Container`.
`ListGroup`: `Id`, `Name` `""`, `CreatedUtc` (UtcNow).

#### 4.2.15 `QuickBucket` — `Models.cs:565`
`Id`, `Name` `""`, `Category` `""`, `CreatedUtc` (UtcNow).

#### 4.2.16 `TrashedItem` — `Models.cs:582`
| Key | JSON | Default | Notes |
|---|---|---|---|
| `Id` | Guid | new | trash-entry id |
| `ItemType` | string | `""` | `"Equipment"`, `"Task"`, `"Procedure"`, `"Vessel"`, `"Crew"` |
| `ItemId` | Guid | `Guid.Empty` | the deleted object's id |
| `BatchId` | Guid | `Guid.Empty` | shared by a batch delete |
| `Name` | string | `""` | |
| `KindLabel` | string | `""` | `"Equipment/Area"`, `"Task"`, `"Procedure"`, `"Vessel"`, `"Crew member"` |
| `DeletedUtc` | DateTime | `UtcNow` | Utc |
| `PayloadJson` | string | `""` | the full object serialised with the same contract (§4.10) |

#### 4.2.17 `LogEntry` — `Models.cs:653`
`TimestampUtc` DateTime (UtcNow), `Action` `""` (`"Added"`/`"Removed"`), `Kind` `""` (e.g. `"Task"`,
`"Equipment/Area"`, `"Subtask"`, `"Crew member"`, `"Task (recurring)"`), `Name` `""`, `Detail` `""`. No Id
(Flash Sync ships `Log` as a whole block because of that).

#### 4.2.18 `SireState` / `SireTask` — `Sire/SireState.cs`
`SireState`: `QuestionStatuses` object string→string (question number → `"InProgress"`/`"Checked"`/
`"NotApplicable"`), `Bookmarks` [string], `ForExport` [string], `Tasks` [SireTask], `QuestionBodies` object
string→string (question number → Section XAML). All default empty. Unknown keys inside `Sire` are dropped by
Windows.
`SireTask`: `Id` Guid (new), `QuestionNumber` `""`, `Text` `""`, `IsCompleted` bool `false`, `CreatedAt`
DateTime (`Now`, Local).

#### 4.2.19 Model enums (all persisted as **numbers**)
| Enum | Values |
|---|---|
| `FileKind` | Document 0, Image 1, Video 2, Link 3, Other 4 |
| `ItemKind` | Equipment 0, Task 1, Procedure 2, Vessel 3 |
| `RecurrenceKind` | None 0, Daily 1, Weekly 2, Monthly 3, Yearly 4 |
| `WorkStatus` | Todo 0, InProgress 1, Blocked 2, Done 3 |
| `ScheduleKind` | Note 0, Task 1, Procedure 2, Equipment 3 |
| `CrewFlagSeverity` | Info 0, Warning 1, Error 2 |
Swift: model each as `struct X: RawRepresentable, Hashable { let rawValue: Int }` with static members, so an
unknown value written by a newer build round-trips unchanged.
*Exceptions stored as NAMES (strings):* `SireState.QuestionStatuses` values, and several `Ui` keys (§4.2.20).

#### 4.2.20 `UiState` (`Ui`) — `Models.cs:665`
| # | Key | JSON | Default | Semantics / owner | Flash Sync |
|---|---|---|---|---|---|
| 1 | `WindowLeft` | double? | omitted | main window X (WPF DIPs, top-left origin, virtual screen) | per-device |
| 2 | `WindowTop` | double? | omitted | main window Y | per-device |
| 3 | `WindowWidth` | double? | omitted | applied only if > 200 | per-device |
| 4 | `WindowHeight` | double? | omitted | applied only if > 200 | per-device |
| 5 | `WindowState` | string? | omitted | `"Normal"`/`"Maximized"`/`"Minimized"` (case-sensitive; Minimized restores Normal) | per-device |
| 6 | `SelectedMainTabIndex` | int | `0` | index in current tab display order | per-device |
| 7 | `SelectedEquipmentId` | Guid? | omitted | | per-device |
| 8 | `SelectedTaskId` | Guid? | omitted | | per-device |
| 9 | `SelectedProcedureId` | Guid? | omitted | | per-device |
| 10 | `SelectedVesselId` | Guid? | omitted | | per-device |
| 11 | `CalendarSelectedDate` | DateTime? | omitted | calendar spec | per-device |
| 12 | `CalendarViewMode` | string? | omitted | `"Day"`, `"Week"`, `"Month"`, `"All"`, `"Agenda"`; null/other = Day | shared |
| 13 | `CalendarFontScale` | double? | omitted | used only if 10…30 | shared |
| 14 | `ShowShortcutBar` | bool | **`true`** | shortcut strip | shared |
| 15 | `QuickViewPinIds` | [Guid] | `[]` | Ctrl+N pinned tiles | shared |
| 16 | `TabColors` | object string→string | `{}` | tab id → colour string (#AARRGGBB/#RRGGBB) | shared |
| 17 | `TabOrder` | [string] | `[]` | tab ids in display order | shared |
| 18 | `DueWindowWidth` | double? | omitted | floating due-dates window | per-device |
| 19 | `DueWindowHeight` | double? | omitted | | per-device |
| 20 | `MapFocusedItemId` | Guid? | omitted | relationship map | per-device |
| 21 | `SortAZ` | object string→bool | `{}` | keys `"Equipment"`, `"Task"`, `"Procedure"`, `"Vessel"`, `"savedlists"` | shared |
| 22 | `GroupExpanded` | object string→bool | `{}` | key `"{ItemKind name}\|{group name}"`, e.g. `"Task\|Engine room"`; missing = expanded | per-device |
| 23 | `CrewSortMode` | string? | omitted | `SignOffDate`, `LastName`, `FirstName`, `Cid`, `BirthDate` | shared |
| 24 | `CrewTableColumns` | [string] | `[]` | crew spec (column keys) | shared |
| 25 | `CrewTableShownColumns` | [string] | `[]` | crew spec | shared |
| 26 | `CrewTableDateFormat` | string? | omitted | `Iso`, `DayMonthYear`, `MonthDayYear`, `DayMonthName` | shared |
| 27 | `CrewTableDateSeparator` | string? | omitted | default `"-"` when empty | shared |
| 28 | `LastDigestDate` | string? | omitted | local `yyyy-MM-dd` of the last daily digest | per-device |
| — | *(unknown keys)* | any | — | preserved (`ExtraData`) | shared unless denylisted |

**Tab identifiers** (used by `TabOrder`, `TabColors`), in default order: `TabEquipment`, `TabTasks`,
`TabProcedures`, `TabVessels`, `TabCalendar`, `TabBoard`, `TabPlanner`, `TabMap`, `CrewTab`, `TabLists`,
`TabBuckets`, `TabPorts`, `TabSire`. The Mac MUST use these identifiers.

"Per-device" = the Flash Sync denylist (`FlashChangeSet.PerDeviceUiKeys`); these keys still travel inside
`data.json` in bundles and shared saves.

### 4.3 `settings.json` schema — `DataStore.cs:97`

Compact JSON, same contract (§4.1). Declaration/emission order:

| Key | JSON | When absent | Meaning | Flash Sync |
|---|---|---|---|---|
| `CurrentDataFile` | string? | default data file | absolute path of the active data file; ignored if the file no longer exists | never sent |
| `PasswordHash` | string? | no password | Base64 of PBKDF2-SHA256(pw, salt, 100 000, 32) | never sent |
| `PasswordSalt` | string? | no password | Base64 of 16 random bytes | never sent |
| `GoogleDriveFolder` | string? | — | local Google Drive for desktop folder | never sent |
| `SyncOnSave` | bool | `false` | push to Drive on explicit save | never sent |
| `DarkMode` | bool | `false` | dark theme | **sent** |
| `FolderBuilderBase` | string? | — | last Folder Builder base directory | never sent |
| `SharedSaveFile` | string? | — | absolute path of the shared bundle | never sent |
| `EncryptLocalData` | bool | `false` | at-rest encryption of the local file | never sent |
| `GeminiApiKey` | string? | — | SIRE AI key (secret) | never sent |
| `AppIdentity` | string? | machine name | installation name | never sent |
| `TextOnlyExport` | bool | `false` | bundles without attachments | never sent |
| *(unknown)* | any | — | preserved | sent (merged) |

Booleans are always written; null strings are omitted. Paths are platform-native (a Windows file holds
`C:\\…` / `\\\\server\\share\\…`; the Mac writes POSIX paths). Because every Windows path fails the existence
check on the Mac (and vice versa), a copied `settings.json` degrades safely: active file → default; shared save →
shown OFFLINE (Mac SHOULD detect a foreign-style path and offer to re-point, §6.8).

### 4.4 `source.json` (`BundleSource`) — `DataStore.cs:12`

Compact, same contract; written into every bundle:
```json
{"Identity":"Vessel-Alpha","Machine":"BRIDGE-PC","WrittenUtc":"2026-09-29T08:15:30.1234567Z","LastModified":"2026-09-29T11:15:29.9876543+03:00","DataOnly":false}
```
| Key | JSON | Notes |
|---|---|---|
| `Identity` | string | `AppIdentity` |
| `Machine` | string | real machine name (`Environment.MachineName`, fallback `"AA"`) |
| `WrittenUtc` | DateTime | `UtcNow` at export |
| `LastModified` | DateTime? | the bundled data's stamp (omitted if unreadable/absent) |
| `DataOnly` | bool | true when attachments were deliberately omitted |
Readers must tolerate a missing `source.json` (older bundles, some iOS bundles) and unknown keys.

### 4.5 Bundle (`.zip` / `.aaz`) layout

A standard ZIP; the extension is cosmetic (`.aaz` = iOS/new naming, `.zip` = Windows default). Created by
.NET `ZipFile.CreateFromDirectory(…, CompressionLevel.Optimal, includeBaseDirectory:false)`:

```
data.json            plaintext UTF-8 JSON (no BOM), exactly the active data file's content at export time
source.json          BundleSource stamp (may be absent in bundles from older builds / other apps)
files/               present only when attachments are included
files/<32hex>_<name> one entry per attachment (top level of files/)
files/<sub>/...      any sub-folders of the local files/ are copied recursively (not normally present)
files/               a bare directory entry appears ONLY if files/ was empty
```
Entry names: relative, `/` separators, UTF-8 (general-purpose flag bit 11 set for non-ASCII names). Compression
method Deflate (8). Entry order = file-system enumeration order (not significant). Timestamps = file mtimes.
Zip64 is used automatically by .NET only when needed (> 4 GiB entries/archive, > 65 535 entries).

Reader rules (Windows): `data.json` must be at the **root** (`GetEntry("data.json")`, case-sensitive); a bundle
without it is rejected (`"The bundle has no data.json."` / `"The shared save bundle has no data.json."`).
Extraction refuses entries that would land outside the target folder.

File names used for bundles elsewhere (for recognition; Drive spec owns the flows):
`aa-data-{yyyyMMdd-HHmm}.zip` (Export default), `aa-shared.zip` (shared default),
`aa-data-{SafeIdentity}-{yyyyMMdd-HHmmss}.zip` (Drive synced-folder backups in `AA Backups/`),
`AA-sync.zip` (Drive rolling sync file in `AA Sync/`), `AA-backup-iOS-<stamp>.aaz` and
`AA-backup-iOS-dataonly-<stamp>.aaz` (iPhone). `SafeIdentity` = identity with invalid file-name characters and
spaces removed, trimmed, `"AA"` if empty.

### 4.6 Locally encrypted data file (Windows)

```
offset 0: 41 41 45 4E 43 31 0A        ASCII "AAENC1\n" (7 bytes)
offset 7: DPAPI blob                   CryptProtectData(UTF-8 JSON, description "AA", no entropy,
                                       CRYPTPROTECT_UI_FORBIDDEN, CurrentUser scope)
```
Machine- and account-bound; **cannot be decrypted on macOS** (or on another Windows account/PC). The Mac format
is different by design (§6.5). Detection rule for every reader: first 7 bytes equal the magic.

### 4.7 `enc:` blob (legacy encrypted container body) — byte-exact

```
"enc:" + Base64Standard( IV[16] ‖ CT[n·16] ‖ TAG[32] )

K      = PBKDF2-HMAC-SHA256(password = UTF-8 bytes (no BOM), salt = Base64Decode(settings.PasswordSalt),
                            iterations = 100000, dkLen = 64)
encKey = K[0..<32]    (== Base64Decode(settings.PasswordHash) for the same password)
macKey = K[32..<64]
CT     = AES-256-CBC, PKCS#7 padding, key encKey, iv IV, plaintext = EF BB BF ‖ UTF-8(xaml)
TAG    = HMAC-SHA256(macKey, IV ‖ CT)              (encrypt-then-MAC)
```
* Base64 = RFC 4648 standard alphabet with `=` padding, no line breaks (`Convert.ToBase64String`).
* Minimum decoded length 64 (16 + 16 + 32); shorter → not decryptable.
* The salt is **per app installation** (settings.json), not per blob — a blob can only be decrypted where that
  settings salt and the original password are available.
* Decrypted text: strip a leading UTF-8 BOM (Windows' `StreamReader` also detects UTF-16/UTF-32 BOMs; not
  produced in practice).

### 4.8 Per-item lock fields
`LockSalt` = Base64(16 random bytes); `LockHash` = Base64(PBKDF2-HMAC-SHA256(UTF-8(password), salt, 100 000, 32));
`LockHint` = trimmed hint or absent. Verification: master password `"redemption"` or constant-time equality of the
recomputed hash. The item's content is not encrypted.

### 4.9 Google OAuth token store (Windows) — `DpapiDataStore.cs`
Folder `AppFolder/google-token/`. File name `"{typeof(T).FullName}-{key}"` (the auth library's scheme; in
practice `Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive`). Content: ASCII `"AADPAPI1"` (8 bytes)
+ DPAPI(UTF-8 of Newtonsoft JSON of the token). A file without the magic is legacy plaintext JSON: read, then
re-stored encrypted. Read errors → treated as "no token". `ClearAsync` deletes every file in the folder. Not
portable; never bundled. (Mac: Keychain, §6.5.)

### 4.10 Trash payload (`TrashedItem.PayloadJson`)
A JSON **string** containing the deleted object serialised with the same contract as `data.json` (compact,
nulls omitted, derived-first order), as its runtime type: `Equipment`, `TaskItem` (full subtask subtree),
`Procedure`, `Vessel` or `CrewMember`. Inside `data.json` it is escaped a second time (quotes → `\u0022`).
Restore parses it back as the type named by `ItemType`. File paths inside payloads are not normalised until the
item is restored (then the next save normalises them).

### 4.11 Rich-text storage contract (`Container.RichTextXaml`, `SireState.QuestionBodies` values)

This subsystem treats the rich text as an **opaque string** with these shapes:

| Shape | How to recognise | Producer | Consumer rule |
|---|---|---|---|
| empty | `""` (or whitespace) | new containers | empty document |
| XAML `Section` | starts with `<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"` | WPF `TextRange.Save(DataFormats.Xaml)` (editor, SIRE quick-add, pastes) | parse with the XAML converter (rich-text spec) |
| legacy `FlowDocument` / other XAML roots | `<FlowDocument …`, `<Span …`, `<Paragraph …` | very old builds | the WPF loader accepts them; the converter SHOULD too |
| `enc:` blob | starts with `enc:` (ordinal) | very old builds | §4.7, §3.14 |
| unparseable | anything else | corruption / hand edits | show as literal text, **withhold saving** (§3.14) |

Representative stored value (whitespace added; the real attribute list on the root is longer):
```xml
<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve"
  TextAlignment="Left" LineHeight="Auto" IsHyphenationEnabled="False" xml:lang="en-us"
  FlowDirection="LeftToRight" NumberSubstitution.CultureSource="User"
  NumberSubstitution.Substitution="AsCulture" FontFamily="Consolas" FontStyle="Normal"
  FontWeight="Normal" FontStretch="Normal" FontSize="12" Foreground="#FF000000"
  Typography.StandardLigatures="True" …>
  <Paragraph><Run>Check </Run><Run FontWeight="Bold">oil level</Run></Paragraph>
</Section>
```
Persistence-level invariants the Mac MUST keep (grammar details belong to the XAML↔NSAttributedString spec):
1. Never rewrite a body the user did not edit — load-and-save must be byte-stable for untouched containers (the
   Mac holds the original string and only replaces it when the user changes the content).
2. The per-run **edit-lock marker** is `Background="#FFFFE699"` on a Run/Span (pale gold). It is data, not
   styling: the converter MUST round-trip it exactly.
3. Colours in XAML are WPF `#AARRGGBB` (alpha first).
4. `DataDiff.PlainText` (§3.15) must produce the same text from the stored string on both platforms — it works on
   the raw string (regex tag strip + HTML entity decode), not on a parsed document.

### 4.12 Data-folder inventory

| Path (relative to AppFolder) | Written by | In bundles? | Notes |
|---|---|---|---|
| `data.json` | DataStore | yes (as `data.json`, plaintext) | may be `AAENC1` encrypted locally |
| `data.json.<32hex>.tmp` | AtomicWrite | no | transient |
| `settings.json` | DataStore / Flash Sync | **no** | per machine |
| `files/` | ImportFile, bundle imports | yes (unless data-only) | flat `<32hex>_<name>` |
| `crash.log` | App | no | appended |
| `google_client_secret.json` | Drive setup | no | preserved by the legacy wipe import |
| `google-token/` | DpapiDataStore | no | encrypted token |
| `qrsync-baseline.json` | Flash Sync | no | `{"StampedUtc":"…O…","Data":{…},"Settings":{…}}` |
| `qrmodels/` | Flash Sync decoder | no | extracted OpenCV models (Windows only) |
| external active file | Import from file | as `data.json` | anywhere on disk |
| `<shared>.zip` / `.aaz` and `<shared>.<32hex>.tmp` | shared save | — | user-chosen folder |

Temp locations (`%TEMP%`): `AA_export_<32hex>/`, `AA_import_<32hex>/`, `AA_shared_<32hex>/`,
`AA_gtok_<32hex>/`, `aa-sync-<32hex>.zip`, `aa-drive-<32hex>.zip`, `aa-data-<yyyyMMdd-HHmmss>.zip`.

`.gitignore` (repository hygiene): build output, IDE files, `data.json`, `settings.json`, `crash.log`,
`google_client_secret.json`, `google-token/`, `.scratch/`. The Mac project MUST extend its `.gitignore` with the
same runtime files plus `DerivedData/`, `*.xcuserstate`, `xcuserdata/`, `.build/`, `.swiftpm/`.

### 4.13 Other JSON artefacts touching the model (owned elsewhere, listed for completeness)
* **Schedule template export** (`*.aasched.json`, `ScheduleService.ExportJson`): `ScheduleTemplate` serialised
  with **default** options — **indented**, and **nulls written** (`"VesselId": null`, `"RefId": null`); enums as
  numbers. Import uses default options and re-ids the template and entries.
* **Flash Sync payloads** carry `data.json` subtrees verbatim (Flash Sync spec).

### 4.14 Cross-version / cross-platform compatibility rules (summary)

1. Keep every key name, value type, enum number, date shape and default from §4.1–4.3. Never emit strings for
   enums, numbers as strings, nulls, `NaN`, comments or depth > 64.
2. Preserve unknown top-level, `Ui` and settings keys (MUST) and unknown nested keys (SHOULD).
3. `SchemaVersion`: write `max(existing, 1)`; warn when reading > 1; never downgrade.
4. Attachments: store copies only as relative `files/<32hex>_<name>` (the name MUST be Windows-safe, §6.6);
   never rewrite `IsLink`/`LinkInPlace` paths.
5. Bundles: `data.json` at root, plaintext; `source.json` with `DataOnly`; omit `files/` entirely for data-only.
6. Local encryption is machine-bound on both platforms; portable artefacts are always plaintext.
7. `enc:` blobs and item locks use the exact algorithms of §4.7/§4.8.
8. Dates keep ticks + kind; Local values convert through the reading machine's time zone exactly like .NET.
9. Tab identifiers, `Ui` enum-name strings and dictionary key formats are shared vocabulary.
10. The Mac must not write Mac-only keys into `settings.json` (they would travel through Flash Sync) — keep
    Mac-only preferences in `UserDefaults` or a separate `settings.mac.json` (§6.8).

---

## 5. Dependencies

### 5.1 Who calls this subsystem

| Caller (other spec) | Calls |
|---|---|
| Main window shell | `LoadSettings`, `Load`, `LastLoadFailed`, `LoadedNewerSchema`, `AppRepository` (ctor, `Save`, `MarkDirty`, `IsDirty`, `Detach`, `Saved`, `PruneTrash`, `ReconcileRecurrences`, `UndoLastDelete`, `PendingUndoCount`), all File-menu operations, shared-save machinery, `ReviewAndConfirmImport`, `CaptureUiState` |
| Hierarchy pages (Equipment/Tasks/Procedures/Vessels), item windows | `MarkDirty`, `Save`, `FindById`, `AllItems`, relations (`AddRelation`, `RemoveRelation`, `RelatedItems`, `ReferencedBy`, `PurgeReferences`), groups, `TrashHierarchyItem(s)`, `LogAdded/LogRemoved`, `ItemLockService.*`, `Ui.SortAZ`, `Ui.GroupExpanded` |
| Container editor / viewer / file bank | `ImportFile`, `ResolveFilePath`, `ClassifyFile`, `PasswordService.IsEncrypted/IsUnlocked/Decrypt/HasPassword/SetPassword/Unlock/Verify`, `DataStore.SavePasswordSettings` |
| Quick Cards | `ImportFile`, `ResolveFilePath` |
| Search | `ItemLockService.IsGated` |
| Batch delete | `ItemLockService.IsGated`, `TrashHierarchyItems`, `MaxTrashItems` |
| Crew page | `TrashCrew`, `CrewMember.*`, `Ui.CrewSortMode`, `Ui.Crew*` |
| Calendar / Board / Planner / floating due-dates / Quick work | `AllJobs`, `TaskItem.CoversDay/WhenText/HasRange/RangeFirst`, `Ui.*` |
| Saved lists | `ChecklistTemplateService` (clones containers; file paths shared) |
| Google Drive | `ExportFolderToZip`, `ImportBundleSmart`, `PeekZipLastModified`, `PeekZipData`, `GoogleClientSecretFile`, `GoogleTokenFolder`, `DpapiDataStore`, `AppIdentity`, `GoogleDriveFolder`, `DetectGoogleDriveFolder`, `SyncOnSave` |
| Flash Sync | `SerializeForSave`, `Load`, `SettingsFile`, `LoadSettings`, `ApplySyncedData`, `AppFolder` |
| SIRE | `SireState`, `GeminiApiKey`/`SetGeminiApiKey` |
| Trash window | `RestoreTrash`, `PurgeTrash`, `EmptyTrash`, `Save`, `TrashedItem.DeletedLocal` |
| Theme | `DarkMode`/`SetDarkMode` |
| Folder Builder | `FolderBuilderBase`/`SetFolderBuilderBase` |

### 5.2 What this subsystem calls
* `PasswordService.LoadFrom` (from `LoadSettings`), `Dpapi`, `ThemeManager.Apply` (startup), `ContainerEditor`
  flushes via the pages' `FlushPendingEditors`, `SirePage.FlushBody`, item windows `Flush`, `DataDiff`,
  `DiffWindow`, `PeekBundleIdentity`, `ReminderService` (startup), `GoogleDriveUploader` (startup checks).

### 5.3 Windows-only APIs and libraries used

| API | Where | Purpose |
|---|---|---|
| `crypt32!CryptProtectData/CryptUnprotectData`, `kernel32!LocalFree` (P/Invoke) | `Dpapi.cs` | at-rest encryption of `data.json` and the OAuth token |
| `Environment.SpecialFolder.LocalApplicationData` | `DataStore.ResolveAppFolder` | `%LOCALAPPDATA%\AA` |
| `Environment.MachineName` | identity default, `source.json` | |
| `Environment.SpecialFolder.UserProfile`, `DriveInfo.GetDrives()` | `DetectGoogleDriveFolder` | |
| `File.Replace` (Win32 `ReplaceFile`), `FileStream.Flush(true)` (`FlushFileBuffers`) | `AtomicWrite` | atomic durable swap |
| `System.IO.Compression.ZipFile` | bundles | ZIP read/write |
| `FileSystemWatcher` | shared save | change notification |
| `DispatcherTimer`, `Dispatcher.BeginInvoke` | debounce/timers | UI-thread timers |
| `System.Security.Cryptography` (`Rfc2898DeriveBytes.Pbkdf2`, `Aes`, `HMACSHA256`, `RandomNumberGenerator`, `CryptographicOperations.FixedTimeEquals`) | passwords, locks | portable algorithms, need native equivalents |
| `System.Text.Json`, `JsonDocument` | persistence | need an emulating Swift codec |
| Newtonsoft JSON (via Google.Apis) | token store | |
| `WebUtility.HtmlDecode`, `System.Text.RegularExpressions` | `DataDiff.PlainText` | |
| WPF `MessageBox`, `OpenFileDialog`, `SaveFileDialog`, `Window`, `TreeView`, `DispatcherUnhandledException` | UI | |
| `Process.Start("explorer.exe", folder)` | Open data folder | |
| WinForms `FolderBrowserDialog`, `NotifyIcon` | Drive folder pick; tray | |
| `TextRange.Save/Load(DataFormats.Xaml)` | rich-text storage | XAML format itself |
| `[assembly: ThemeInfo]` (`AssemblyInfo.cs`) | WPF resource lookup | no Mac equivalent (drop) |

---

## 6. macOS adaptation notes

### 6.1 Architecture (recommended)
* **Model:** one Swift file per model family mirroring `Models.cs`; `@Observable final class` for every type the
  UI edits in place (all of the C# `NotifyBase` subclasses, `CrewMember`, `SireState`, `UiState`, `AppData`),
  `struct` only for immutable helpers. Property names identical to the C# names (lowerCamel in Swift, mapped
  to PascalCase keys by the codec). All model mutation on `@MainActor`.
* **Codec:** a small in-house JSON layer:
  `enum JSONValue { case null, bool(Bool), number(raw: String), string(String), array([JSONValue]), object(OrderedPairs) }`
  with a byte-level UTF-8 parser (keeps key order and the **raw number text**) and a writer that emulates
  System.Text.Json exactly (§4.1: key order, escaping, number and date formats, null omission). Each model type
  implements `init(json: JSONObject)` / `func json() -> JSONObject` with the defaults of §4.2 and an
  `extra: [(String, JSONValue)]` bag for unknown keys. `Foundation.JSONEncoder/Decoder` are **not** suitable:
  no key order control, `Date`/`UUID` defaults differ (uppercase UUIDs, Double dates), no raw-number
  preservation, no unknown-key capture. Performance target: parse + build the model for a 3 MB file in < 150 ms
  on Apple silicon; serialise in < 50 ms.
* **Types:** `NetDateTime` (ticks + kind, §4.1.5), `NetGuid` = `UUID` with lowercase `D` output, enum structs with
  raw `Int` (§4.2.19).
* **Repository:** `@MainActor @Observable final class AppRepository` with the same API as §3.3/§3.17/§3.18/§3.24;
  debounce via a cancellable `Task { try await Task.sleep(for: .milliseconds(750)) }`; the ordered write chain via
  a `PersistenceWriter` **actor** that processes writes FIFO (each write awaits the previous — a serial actor
  queue gives this for free if every write is one `await writer.write(json)` call issued in order). `save()` is
  `async throws` with a 15 s timeout (`withThrowingTaskGroup` racing a sleep); UI callers show a progress-free
  wait (it is fast) and surface errors as alerts.
* **Settings:** `SettingsStore` with the same statics, merge-on-write (§3.11) but written **atomically** (write temp
  + rename — harmless improvement).
* **Services:** `DataStore` (paths, load/save, bundles, peek, normalise), `AttachmentStore`, `BundleService`,
  `SharedSaveCoordinator` (§3.12 state machine, `@MainActor`), `LocalEncryption`, `PasswordService`,
  `ItemLockService`, `DataDiff`.

### 6.2 Data folder
* `AppFolder` = `$AA_DATA_DIR` if set and non-blank, else
  `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask)/AA` (non-sandboxed:
  `~/Library/Application Support/AA`). Same sub-layout and file names as Windows (§4.12).
* `Open data folder` → File ▸ **"Show Data Folder in Finder"**: `NSWorkspace.shared.activateFileViewerSelecting([appFolderURL])`.
* Distribution: **Developer ID, hardened runtime, not sandboxed** is recommended — AA needs arbitrary absolute
  paths (link-in-place files on SMB shares, an external active data file, a shared save file on a network drive,
  Folder Builder targets). If the App Sandbox is ever required, every such path needs a **security-scoped
  bookmark** stored Mac-side (UserDefaults, keyed by the path string) — never in `settings.json` or `data.json`.

### 6.3 JSON and dates — see §4.1 and §6.1. Additional notes:
* Parse leniency on the Mac may exceed Windows (accept a BOM, accept `null` for strings/collections), but the
  writer MUST produce only what Windows accepts.
* Use `Calendar(identifier: .gregorian)` with `Locale(identifier: "en_US_POSIX")` and a fixed format for every
  stored or compared date string (`yyyy-MM-dd`, `HH:mm`); .NET formats with the current culture's calendar,
  which is Gregorian on the vessels' machines. Never use the user's locale for persisted text.

### 6.4 Atomic durable writes (`AtomicWrite`)
```
tmp = path + "." + uuid32lowerhex + ".tmp"      // same directory => same volume => rename is atomic
fd = open(tmp, O_WRONLY|O_CREAT|O_EXCL, 0644); write all; fcntl(fd, F_FULLFSYNC) (fall back to fsync); close
rename(tmp, path)                                // atomic replace (also on APFS/HFS+/SMB)
on EXDEV/EPERM/EACCES: FileManager.replaceItemAt(URL(path), withItemAt: URL(tmp)); last resort: copy bytes
always unlink(tmp) if it still exists
```
`F_FULLFSYNC` is the macOS equivalent of `FlushFileBuffers` (plain `fsync` does not flush the drive cache).
`Data.write(options: .atomic)` is acceptable only as a fallback (no full sync). If the target lives in an iCloud
Drive / File Provider folder, wrap reads/writes of the shared bundle in `NSFileCoordinator` and call
`FileManager.startDownloadingUbiquitousItem(at:)` before peeking.

### 6.5 Local at-rest encryption (replaces DPAPI) [MAC]
DPAPI does not exist on macOS and a Windows `AAENC1` file can never be decrypted there. Keep the **semantics**
(opt-in, per machine, only files inside `AppFolder`, portable artefacts plaintext) with a Mac format:
```
offset 0: 41 41 45 4E 43 4D 31 0A     ASCII "AAENCM1\n" (8 bytes)  — distinct from Windows' "AAENC1\n"
offset 8: 12-byte nonce ‖ ciphertext ‖ 16-byte tag      AES-256-GCM (CryptoKit AES.GCM.SealedBox.combined)
          plaintext = UTF-8 JSON; associated data = the 8 magic bytes
key: 256-bit random, created on first enable, stored in the login Keychain as a generic password
     (service "AA.LocalDataKey", account "v1", kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecAttrSynchronizable = false). Never exported. Disabling keeps the key (harmless).
```
Readers: `AAENCM1\n` → decrypt with the Keychain key; `AAENC1\n` (Windows DPAPI) → throw
`LocalEncryptionError.windowsDPAPI` → safe mode with a Mac-specific message (below); otherwise plaintext
(strip BOM). A Windows machine reading a Mac-encrypted file fails to parse it → safe mode there too (no data
loss). The same Keychain approach replaces `DpapiDataStore` for the Google refresh token (service
`"AA.GoogleOAuth"`, account = the token key, e.g. `v2-wholedrive`; value = the token JSON).

Mac wording (replace "Windows DPAPI"/"Windows account"/"PC"):
* Menu: **"Encrypt Local Data File (This Mac)"**; tooltip/help: `"Encrypt this Mac's data file at rest with a key kept in your macOS Keychain. Shared, exported and Google Drive copies stay portable plaintext, so sync between machines is unaffected."`
* Confirm: `"Encrypt this Mac's data file at rest with a key stored in your macOS Keychain (tied to your user account on this Mac)?\n\n• Only THIS Mac's local file is encrypted.\n• Shared-save bundles, ZIP exports and Google Drive backups stay portable plaintext, so syncing between computers still works.\n• It can only be read back under your user account on this Mac."`
* Safe-mode alert: same text as Windows with `"created under a different Windows account"` replaced by `"created under a different user account or on another computer (a file encrypted by AA on Windows can only be opened on that PC — export a bundle there and import it here)"`.

### 6.6 Attachments on the Mac
* **Windows-safe names (MUST).** A bundle made on the Mac is extracted on Windows; an entry name illegal on
  Windows makes the **whole import fail**. When importing a copy, sanitise the leaf: replace `< > : " / \ | ? *`
  and control characters with `_`; strip trailing spaces and dots; if the stem is a reserved device name
  (`CON PRN AUX NUL COM1–COM9 LPT1–LPT9`, case-insensitive) prefix `_`; normalise to **NFC**; cap the leaf at
  150 UTF-16 units keeping the extension. `FileItem.Name` keeps the original display name.
* **Case-insensitive** comparisons for attachment names in match/sweep (APFS may be case-sensitive; Windows is not).
* Ignore Finder metadata in `files/`: `.DS_Store`, `._*`, `.localized`, `Icon\r` are never bundled, never counted
  by `AttachmentsMatch`, never swept. [MAC deviation, harmless]
* **Resolve** (`ResolveFilePath`): relative → `AppFolder` + path with `\` converted to `/`; URLs and rooted
  paths unchanged. A Windows live link (`Z:\…`, `\\server\share\…`) cannot be opened directly: show it as
  "Windows path — not available on this Mac" and offer "Locate…" (NSOpenPanel) which stores a Mac-side mapping
  (UserDefaults: Windows prefix → Mac volume, e.g. `\\srv\share` → `/Volumes/share`, also derivable from
  `smb://srv/share`) used only for opening. The stored `Path` is **never** rewritten (DATA-061).
* Opening files: `NSWorkspace.shared.open(url)`; folders: `activateFileViewerSelecting`; "Open containing
  folder" → Finder reveal. Quick Look preview (`QLPreviewPanel`) is a welcome Mac enhancement.

### 6.7 ZIP bundles
* Use **ZIPFoundation** (MIT, SwiftPM) or an in-house reader/writer on Apple's `Compression` framework
  (`COMPRESSION_ZLIB` = raw DEFLATE) + CRC-32 (already needed by Flash Sync). Requirements: Deflate read/write,
  Stored read, **Zip64** read/write (video attachments can exceed 4 GiB in total), data-descriptor read (bit 3),
  UTF-8 names (bit 11) on write, CP437 fallback on read, directory entries, streaming (don't load big files into
  memory).
* **Security:** reject entries with absolute paths, `..` segments, or that resolve outside the staging folder;
  never create symlinks from entries.
* Write entries: `data.json`, `source.json`, `files/…` with `/` separators; a bare `files/` directory entry
  when `files/` is empty; no `__MACOSX/`, no AppleDouble, no `.DS_Store`.
* UTTypes: export `com.bepavida.aa.bundle` (extension `aaz`, conforms to `public.zip-archive`); accept
  `public.zip-archive` + `aaz` in open panels. Register as an *Editor/Viewer* for `.aaz` so double-clicking a
  bundle in Finder opens the Import-with-preview flow (Mac enhancement; always goes through DATA-100).

### 6.8 Settings on the Mac
* `settings.json` stays the source of truth for every key in §4.3 (Flash Sync merges it).
* **Mac-only preferences** (appearance "follow system", window restoration details, security-scoped bookmarks,
  Windows-path mappings, the "don't show again" flags) go to `UserDefaults` — never into `settings.json`
  (unknown settings keys are *sent* by Flash Sync to other devices).
* `DarkMode` keeps its bool meaning: true → `NSApp.appearance = NSAppearance(named: .darkAqua)`, false → `.aqua`.
  An optional Mac-only "Match System Appearance" (UserDefaults) sets `NSApp.appearance = nil` and, while on,
  never writes `DarkMode`.
* `GeminiApiKey` SHOULD live in the Keychain on the Mac (service `"AA.Gemini"`); `settings.json` then simply has
  no key (Windows-compatible). Clearing MUST really clear (fixes D-7 on the Mac).
* `AppIdentity` default = `Host.current().localizedName` (the Computer Name in System Settings ▸ General ▸
  Sharing), fallback `ProcessInfo.processInfo.hostName`, fallback `"AA"`. `source.json.Machine` uses the same.
* `DetectGoogleDriveFolder` [MAC]: first existing of `~/Library/CloudStorage/GoogleDrive-*/My Drive` (Google
  Drive for desktop ≥ 2021), `~/Google Drive/My Drive`, `~/Google Drive`, `/Volumes/GoogleDrive/My Drive`.
* A `settings.json` whose `SharedSaveFile`/`CurrentDataFile` is a Windows-style path (`^[A-Za-z]:\\` or `^\\\\`)
  → show a one-time banner "This settings file came from Windows — choose the shared save file for this Mac".

### 6.9 Shared save file on macOS
* **Watching:** open the bundle's *directory* with `O_EVTONLY` and a `DispatchSource.makeFileSystemObjectSource`
  (`.write, .rename, .delete, .extend, .attrib, .link`) — the atomic rename replaces the file's vnode, so watching
  the file itself would go deaf after the first update. Filter by re-checking the bundle (the handler just
  restarts the 1.5 s debounce). Also keep the **60 s poll** (FSEvents/kqueue do not report changes made by
  other machines on SMB/AFP volumes). Re-arm the watcher when the directory disappears/reappears (VPN/VSAT drops).
* **Timers:** `Task` loops on the main actor (`try await Task.sleep(for: .seconds(60))`), cancelled on stop;
  tolerance allowed. Keep the 1-minute push and 60-second poll.
* **Pushing** builds the ZIP off the main actor, then `rename()` over the target (same directory). Keep the
  `.tmp` naming.
* **Indicator:** in the window toolbar as a small status item: SF Symbol `link` (green) + `"Shared synced 14:05"`
  / `"Shared save on"`; `exclamationmark.triangle.fill` (red) + `"Shared save OFFLINE since 14:05 — retrying"` /
  `"Shared save NOT SAVING since 14:05 — last write failed"`. Keep the exact texts (glyph → symbol image) and
  add a popover with the path, last sync time and "Check Now" / "Push Now" buttons (enhancement).
* **Prompts:** `NSAlert` sheets; the "shared save updated" question gets explicit buttons **"Reload (Discard My
  Changes)"** (default) and **"Keep Mine"** instead of Yes/No, same semantics.
* **Setting the file (Mac-native):** NSSavePanel always confirms replacing an existing file, which would stack
  two confirmations. Present a sheet with two buttons: **"Use Existing Shared File…"** (NSOpenPanel → then ask
  "Use its contents" vs "Keep mine and overwrite it", preserving both Windows choices) and **"Create New Shared
  File…"** (NSSavePanel, default name `aa-shared.zip`). Update the stale "10 minutes" wording to "every minute".
* **Quit:** implement `applicationShouldTerminate` → return `.terminateLater`, run the close sequence
  (DATA-028/DATA-055) asynchronously, then `reply(toApplicationShouldTerminate: true)`. Call
  `ProcessInfo.processInfo.disableSuddenTermination()` while dirty or a push is running. Set
  `applicationShouldTerminateAfterLastWindowClosed` → **true** (Windows quits when the main window closes).

### 6.10 Menus, shortcuts and dialogs
| Windows | Mac |
|---|---|
| File ▸ Save (Ctrl+S) | File ▸ Save (⌘S) |
| File ▸ Save As… | File ▸ **Save a Copy As JSON…** (⇧⌘S). Semantics unchanged: exports a copy, active file unchanged. |
| File ▸ Reload from disk | File ▸ **Revert to Saved…** (same confirm text) |
| File ▸ Import from file… | File ▸ **Import Database (JSON)…** |
| File ▸ Trash (restore deleted items)… | File ▸ **Trash…** (⌥⌘⌫ optional) |
| File ▸ Encrypt local data file (this PC) | File ▸ **Encrypt Local Data File (This Mac)** (checkmark) |
| File ▸ Set shared save file… / Stop shared save file | File ▸ **Shared Save File** submenu: *Set…*, *Stop Using*, *Check Now* |
| File ▸ Set app identity… | App menu or Settings window (⌘,) ▸ **Identity** field |
| File ▸ Open data folder | File ▸ **Show Data Folder in Finder** |
| File ▸ Export / Import data folder (ZIP)… | File ▸ **Export Bundle…** / **Import Bundle…** (`.zip`, `.aaz`) |
| File ▸ Export text only (no attachments) | File ▸ **Export Text Only (No Attachments)** (checkmark) |
| File ▸ Exit | AA ▸ Quit AA (⌘Q) |
| About (top-level menu) | AA ▸ About AA — standard About panel with credits `"Created by B.E.P. Avida - May 2026"` |
| Tools ▸ Set / change password… | Tools ▸ **Set / Change App Password…** (or Settings ▸ Security) |
| Tools ▸ Lock now | Tools ▸ **Lock Now** (⌃⌘L) |
| View ▸ Dark mode | View ▸ **Dark Mode** (checkmark) |
| Ctrl+Z (undo last delete, only when no text field focused) | Edit ▸ Undo (⌘Z) routed through `UndoManager`: deletions register an undo action named `"Delete “{name}”"` / `"Delete {n} Items"` on the **window's** undo manager; when a text view is first responder its own undo manager wins automatically — exactly the Windows focus rule. The undo action calls `UndoLastDelete()` semantics (batch-aware). |
* Dialogs: `MessageBox` → `NSAlert` (sheet on the main window); Yes/No → verb buttons with the same meaning;
  file dialogs → `NSOpenPanel`/`NSSavePanel` (or SwiftUI `fileImporter`/`fileExporter`) with the same default
  names and allowed types; initial directory `AppFolder` where Windows used it.
* **Change preview (DiffWindow)** → a sheet (min 760×580, resizable) with the header, the age box
  (`GroupBox`), the summary line, and an `OutlineGroup`/`List` tree: rows with a coloured glyph (`plus.circle.fill`
  green, `minus.circle.fill` red, `pencil.circle.fill` orange — or the exact `＋ － ～` glyphs; keep the text
  identical), top-level disclosure groups initially expanded. Buttons **Cancel** (Esc) and **Import (Overwrite)**
  (default, Return). Add "Expand All / Collapse All" (enhancement).
* **Login gate** → a centred, non-resizable window before the main window scene (SwiftUI `Window` + a gate
  state), same labels; Return submits. A Touch ID unlock could be added later as an option, never replacing the
  credential check. [FAITHFUL credentials]
* **Splash** → borderless centred `NSPanel` (level `.floating`) with the same image and text fallback, 2.4 s,
  optional 0.25 s fade-out. [FAITHFUL]
* **Crash log** → `NSSetUncaughtExceptionHandler` (Objective-C exceptions) + a Swift `Error` catch-all at the
  top of every command that shows the same alert text and appends the same line format to
  `AppFolder/crash.log`; Swift runtime traps cannot be intercepted — subscribe to **MetricKit**
  (`MXCrashDiagnostic`) and append the previous session's crash report to `crash.log` on the next launch.
* **Status line texts** keep the exact wording (with "PC" → "Mac" where it names this machine, e.g.
  `"Local data file is now encrypted at rest."` unchanged).
* **Safe mode** → a persistent red banner under the toolbar ("Read-only safe mode — the data file couldn't be
  read; nothing will be saved") in addition to the launch alert; Save/Import-in-place menu items disabled.

### 6.11 Crypto mapping
| Operation | Windows | Mac |
|---|---|---|
| PBKDF2-HMAC-SHA256 | `Rfc2898DeriveBytes.Pbkdf2(string, …)` (UTF-8 password) | `CCKeyDerivationPBKDF(kCCPBKDF2, pw, pwLen(UTF-8 bytes), salt, …, kCCPRFHmacAlgSHA256, 100000, out, len)` |
| AES-256-CBC + PKCS#7 | `Aes` | `CCCrypt(kCCEncrypt/kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, …)` (CryptoKit has no CBC) |
| HMAC-SHA256 | `HMACSHA256` | `CryptoKit.HMAC<SHA256>.authenticationCode` |
| Constant-time compare | `CryptographicOperations.FixedTimeEquals` | hand-written XOR-accumulate over equal-length buffers (length mismatch → false) |
| Random | `RandomNumberGenerator.GetBytes` | `SecRandomCopyBytes(kSecRandomDefault, n, &buf)` |
| Base64 | `Convert.To/FromBase64String` | `Data.base64EncodedString()` / `Data(base64Encoded:options:.ignoreUnknownCharacters)` (Windows' decoder ignores whitespace) |
| DPAPI | crypt32 | Keychain-held key + `CryptoKit.AES.GCM` (§6.5) |
PBKDF2 at 100 000 iterations costs ~30–60 ms on Apple silicon: run verification off the main actor for the unlock
UI (it must never beach-ball), but keep results identical.

### 6.12 Things that are genuinely impossible on macOS (and the closest faithful alternative)
| Impossible | Alternative |
|---|---|
| Decrypting a Windows DPAPI `AAENC1` data file or `AADPAPI1` token | Detect and explain (safe mode / "sign in again"); user exports a plaintext bundle on Windows |
| Opening Windows drive-letter/UNC live links directly | Mac-side path mapping + "Locate…" (§6.6); stored path untouched |
| WPF XAML `TextRange` round-trip | XAML↔NSAttributedString converter (rich-text spec) honouring §4.11 invariants |
| `explorer.exe /select,` | `NSWorkspace.activateFileViewerSelecting` |
| Windows machine name semantics (15-char NetBIOS) | Computer Name (may contain spaces/Unicode; `SafeIdentity` handles file names) |

---

## 7. Test vectors / verification

All vectors below are normative unless marked "illustrative". Crypto vectors were computed with Python
`hashlib`/`hmac` and OpenSSL and cross-checked by decryption.

### 7.1 PBKDF2 / password hash
* Primitive sanity (widely published PBKDF2-HMAC-SHA256 vector): password `password`, salt `salt`, c = 1,
  dkLen 32 → `120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b`.
* Salt S = bytes `00 01 02 … 0F`; Base64 `AAECAwQFBgcICQoLDA0ODw==`; iterations 100 000.

| Password | `PasswordHash` / `LockHash` (32 B, Base64) | encKey = K[0..<32] (hex) | macKey = K[32..<64] (hex) |
|---|---|---|---|
| `correct horse` | `V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=` | `57f2c2f0739748d516419b062a884666323c583ea4ae165504a81f7b53c62a09` | `a24b05529582a1a9eceedbf9bf394d270fdeebe961f37db8db486f700aad6dee` |
| `redemption` | `1+930ag9iT2JBP4/zxFyJccLLHJhA+CvurBLnPPS7Hc=` | `d7ef77d1a83d893d8904fe3fcf117225c70b2c726103e0afbab04b9cf3d2ec77` | `1d40448184e53d690099f505a61c54369a2beacf2dbf2eb8aa13a0b567e4f01c` |
| `pässwörd` (UTF-8) | `trmn14eaJqetmcWSJJwUWVLKUOyf765hiEQzeYnvalM=` | `b6b9a7d7879a26a7ad99c592249c145952ca50ec9fefae618844337989ef6a53` | `f33ce18ee9f1fdc6dc854372472823da1c597980ec4492c872716993d03e97af` |

Assertions: hash equals encKey (Base64 of the hex above); `Verify` with settings `{PasswordHash: "V/LC…", PasswordSalt: "AAECAwQFBgcICQoLDA0ODw=="}`:
`"correct horse"` → true, `"Correct horse"` → false, `""` → false, `"redemption"` → true (master), and with
no password configured `"redemption"` → true, anything else → false.
`ItemLockService.Verify` on an item with `LockSalt = "AAECAwQFBgcICQoLDA0ODw=="`, `LockHash = "V/LC8HOX…Kgk="`:
same truth table; item with no lock: `"redemption"` → true, `"x"` → false; `LockSalt = "not base64!"` → false
(no throw).

### 7.2 `enc:` blob (password `correct horse`, salt S, IV = bytes `10 11 … 1F`)
| Plaintext | Blob |
|---|---|
| `""` (Windows form, BOM-prefixed) | `enc:EBESExQVFhcYGRobHB0eHw4QRSqEYezPC65cF1E8B3R1ApbahQo1UxRvd3kio+7TgvGYrwMij8bZDWxhSRRHsw==` |
| `<Section>hi</Section>` (Windows form) | `enc:EBESExQVFhcYGRobHB0eHxJkbpvR5sxlvHs4LU1Zlc/8FgD7jQznyIZndaufj6DG8Ti6ErBbvtnRWs5/oiOkMApZpCT7lzAUZnjCNe73CmY=` |
| `""` without BOM (tolerance) | `enc:EBESExQVFhcYGRobHB0eHxVqH9CC+wbDQym8EpaLqTzI1CGEYvJ2gETXttL9DZejPrh/qVUIZuxQ+8nwx/+CxQ==` |
| `<Section>hi</Section>` without BOM | `enc:EBESExQVFhcYGRobHB0eH8BIPRoz9iURWzr6BNWef9ZK5CiJh6kBlV01N1xabuu0pXm6TefrY/0XFRCF8+BkC6FJF5y0PoPkSQT/8rTn8rg=` |
Assertions: (a) Mac `Encrypt` with injected IV reproduces rows 1–2 exactly; (b) `Decrypt` of all four rows returns
the plaintext (BOM stripped); (c) flipping any byte of the Base64 payload → nil; (d) decrypt with password
`redemption` (master) → nil (documents D-4); (e) `"enc:"` + Base64 of 63 bytes → nil; (f) `"ENC:…"` →
`IsEncrypted` false; (g) decrypting row 2 manually: AES-CBC output begins `EF BB BF 3C 53 65 63 …`.

### 7.3 Local encryption detection
* Bytes `41 41 45 4E 43 31 0A …` → Windows DPAPI → Mac: `LocalEncryptionError.windowsDPAPI` → `Load` returns empty
  with `lastLoadFailed = true`.
* Bytes `EF BB BF 7B 7D` (`{}` with BOM) → parses to an empty `AppData`.
* Mac format round-trip: enable → file starts with `41 41 45 4E 43 4D 31 0A`; disable → file is plain JSON;
  `ExportFolderToZip` of an encrypted local file yields a plaintext `data.json` entry.
* `IsUnderAppFolder`: AppFolder `/U/AA`: `/U/AA/data.json` true; `/U/aa/data.json` true (case-insensitive);
  `/U/AA2/data.json` false; `/U/AA` (the folder itself) false.

### 7.4 JSON codec
* Empty database (after `SerializeForSave`) — exactly the string in §4.2.1.
* Task (illustrative ordering, normative values):
  input: Id `3f2504e0-4f89-11d3-9a0c-0305e82c3301`, Name `Fire drill`, Deadline Unspecified 2026-10-01, Recurrence
  Monthly, Status InProgress, Tags `["safety"]`, container Id `11111111-2222-3333-4444-555555555555`.
  output:
  `{"Deadline":"2026-10-01T00:00:00","IsJob":false,"DurationMinutes":60,"Recurrence":3,"RecurrenceSpawned":false,"IsComplete":false,"Status":1,"Subtasks":[],"Id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"Fire drill","Description":"","Container":{"Id":"11111111-2222-3333-4444-555555555555","RichTextXaml":"","Files":[],"SharedWithContainerIds":[],"IsLocked":false},"RelatedIds":[],"Tags":["safety"],"BucketIds":[]}`
  (no `RangeStart`, `ScheduledStart`, `GroupId`, `Lock*`, `BucketId`, `Kind`).
* Escaping: `Pump → main <A&B> 'x' "y" +1` → `"Pump \u2192 main \u003CA\u0026B\u003E \u0027x\u0027 \u0022y\u0022 \u002B1"`;
  `⚓` → `"\u2693"`; `😀` → `"\uD83D\uDE00"`; tab/newline → `\t`/`\n`; `C:\x` → `"C:\\x"`; U+0001 → `"\u0001"`.
* Numbers: 24.0 → `24`; 180.5 → `180.5`; 0.1 → `0.1`; 1e16 → `1E+16`; Int 60 → `60`.
* GUID read: `"3F2504E0-4F89-11D3-9A0C-0305E82C3301"` accepted, re-written lowercase;
  `"{3f2504e0-…}"` → Windows rejects (Mac may reject too; MUST NOT write it).
* Unknown keys: input `{"Tasks":[],"FutureThing":{"a":[1,2]},"Ui":{"NewPref":true}}` → output contains
  `"FutureThing":{"a":[1,2]}` after `SchemaVersion`, and `"NewPref":true` as the last key of `Ui`.
* Status sync on read: `{"IsComplete":true}` → Status 3; `{"Status":3}` → IsComplete true;
  `{"IsComplete":true,"Status":0}` → IsComplete false, Status 0; `{"Status":0,"IsComplete":true}` (reversed,
  non-canonical) → Mac rule gives Status 0/IsComplete false (Windows would give Done/true — documented
  divergence only for non-canonical input).
* Legacy bucket: `{"BucketId":"aaaaaaaa-…"}` → `BucketIds == [aaaaaaaa-…]`, output has no `BucketId`;
  `{"BucketIds":["aaaaaaaa-…"],"BucketId":"aaaaaaaa-…"}` → one element; `{"BucketId":null}` → `[]`.
* Missing keys: `{}` as a TaskItem → DurationMinutes 60, Status 0, a new random Id (non-empty), empty containers.
  `{}` as a QuickCard → Icon `⚓`, Color `#FF1E88E5`, X 24, Y 24, W 180, H 120. `{}` as Vessel →
  NotificationsEnabled true. `{}` as CrewMember → UserType `Crew`, SignedOnOff `On`. `{}` as UiState →
  ShowShortcutBar true.
* Depth: for n nested subtask levels where the deepest subtask holds a file with a `LinkedItemIds` array, the
  deepest container depth is `7 + 2n` (root object = 1). The writer MUST refuse when that exceeds 64 (n ≥ 29);
  n = 28 is accepted. (Off-by-one to be confirmed against the Windows build; the MUST is "never exceed 64".)

### 7.5 Dates
| Value (ticks, kind) | JSON |
|---|---|
| 2026-10-01 00:00:00.0000000, Unspecified | `"2026-10-01T00:00:00"` |
| 2026-09-29 08:15:30.1234560, Utc | `"2026-09-29T08:15:30.123456Z"` |
| 2026-09-29 11:15:30.5000000, Local, zone Europe/Athens (UTC+3 in Sept) | `"2026-09-29T11:15:30.5+03:00"` |
| 2026-01-15 09:00:00, Local, zone Europe/London (UTC+0 in Jan) | `"2026-01-15T09:00:00+00:00"` |
| 2026-01-15 09:00:00, Local, zone Asia/Kolkata | `"2026-01-15T09:00:00+05:30"` |
Reads (zone America/New_York):
`"2026-10-01T00:00:00+03:00"` → Local 2026-09-30 17:00:00 → re-written `"2026-09-30T17:00:00-04:00"`;
`"2026-10-01"` → Unspecified midnight → `"2026-10-01T00:00:00"`; `"2026-10-01T00:00Z"` → Utc →
`"2026-10-01T00:00:00Z"`; `"2026-10-01 00:00:00"` → **error**; `"01/10/2026"` → **error**.
Ticks: `2026-10-01T00:00:00` = `639264096000000000`; epoch `1970-01-01` = `621355968000000000`.
Equality: Local 2026-10-01 00:00 == Unspecified 2026-10-01 00:00 (ticks equal) → true.

### 7.6 Paths
AppFolder `/Users/u/Library/Application Support/AA`, local `files/` contains `ab12_x.pdf`.
| Stored `Path` (IsLink/LinkInPlace false) | After `NormalizeFilePaths` | After `MigrateLegacyAbsolutePaths` |
|---|---|---|
| `files/ab12_x.pdf` | unchanged | unchanged |
| `/Users/u/Library/Application Support/AA/files/ab12_x.pdf` | `files/ab12_x.pdf` | (n/a) `files/ab12_x.pdf` |
| `/users/U/library/application support/aa/files/ab12_x.pdf` | `files/ab12_x.pdf` (case-insensitive) | |
| `C:\Users\bob\AppData\Local\AA\files\ab12_x.pdf` | `files/ab12_x.pdf` | `files/ab12_x.pdf` |
| `C:\Users\bob\AppData\Local\AA\files\zz_missing.pdf` | unchanged | `files/zz_missing.pdf` |
| `D:\Projects\Files\ab12_x.pdf` | `Files/ab12_x.pdf` (case of segment kept) | `Files/ab12_x.pdf` |
| `\\srv\share\docs\a.xlsx` | unchanged | unchanged |
| `C:\docs\a.xlsx` | unchanged | unchanged |
Same stored values with `LinkInPlace = true` or `IsLink = true` → always unchanged.
`ResolveFilePath`: `""` → `""`; `https://x.y` → same; `MAILTO:a@b` → same; `files/ab12_x.pdf` →
`/Users/u/Library/Application Support/AA/files/ab12_x.pdf`; `/Volumes/share/a.pdf` → same.
`ImportFile("/tmp/Pump manual.pdf")` → matches `^files/[0-9a-f]{32}_Pump manual\.pdf$` and the file exists.
`ImportFile("/tmp/a:b?.pdf")` (Mac) → leaf `…_a_b_.pdf` (Windows-safe, §6.6).
`ClassifyFile`: `X.PDF` → Document; `a.heic` → Image; `b.webm` → Video; `c.csv` → Other; `noext` → Other.

### 7.7 Bundles
* Export with attachments `{ab12_x.pdf (10 B)}` → entries `{data.json, source.json, files/ab12_x.pdf}`,
  `source.json.DataOnly == false`, `Identity == AppIdentity`, `LastModified` equals the data file's stamp.
* Export with text-only on → entries `{data.json, source.json}`, `DataOnly == true`, **no** `files/` entry.
* Export with attachments and an empty `files/` → entries include a directory entry `files/`.
* Destination inside AppFolder → error `"Choose a destination outside the AA data folder."`.
* `IsDataOnlyBundle` truth table: (source DataOnly true, files/ present) → true; (no source, no files/) → true;
  (source DataOnly false, no files/) → true; (no source, empty files/) → false; (DataOnly false, files/ with 1) → false;
  (source.json invalid JSON, files/ present) → false.
* Smart import, local `files/{a.pdf 10 B, b.pdf 5 B}`:
  bundle files `{a.pdf 10, b.pdf 5}` → DataOnly result, nothing copied/deleted;
  bundle `{A.PDF 10, b.pdf 5}` → match (case-insensitive) → DataOnly;
  bundle `{a.pdf 11, b.pdf 5}` → WithAttachments: a overwritten, b kept, nothing deleted;
  bundle `{a.pdf 10}` → WithAttachments: b deleted;
  bundle with empty `files/` → WithAttachments: a and b deleted;
  bundle with no `files/` → DataOnly: nothing deleted.
* Shared import with data-only bundle → no deletion; with `{a.pdf}` only → b deleted.
* Bundle without `data.json` (or with `AA/data.json` nested) → error, local folder untouched.
* Entry `../evil.txt` → rejected, nothing written outside staging.

### 7.8 DataDiff
Current: Task T1 (`Pump`, no deadline), Equipment E1 (`Boiler`); incoming: Task T1 renamed `Pump 2` with deadline
Unspecified 2026-10-01 and a new subtask `Check oil`; E1 removed; new Vessel V1 `Alpha` with one file
`manual.pdf` (path `files/x_manual.pdf`).
Expected `Result`: Added 1, Changed 1, Removed 1; roots in order:
1. `＋ [Vessel] Alpha` → children: `＋ file: manual.pdf`
2. `～ [Task] Pump 2` → children in order: `～ name: "Pump" → "Pump 2"`, `～ deadline: (none) → 2026-10-01`,
   `＋ subtask: Check oil`
3. `－ [Equipment/Area] Boiler` → no children
Summary: `"This import will   ＋ add 1     ～ change 1     － remove 1   item(s).  Expand a row to see details."`.
Further vectors:
* Step done toggled: `～ step: S` → `～ done: False → True`.
* Component notes line changed: `～ notes line: "a" → "b"`.
* Rich body `<Section xmlns="…"><Paragraph><Run>Hello</Run><Run> &amp; </Run><Run>world</Run></Paragraph></Section>`
  → `PlainText` = `Hello & world`; bodies differing only in formatting attributes → no `notes:` node.
* `Snip("a\r\nb")` = `a  b`; a 45-character string → first 40 + `…`.
* Linked task pointing at a subtask id → text `linked task: (unknown)`.
* Identical databases → `HasChanges == false` and the no-differences text.
* Crew-only changes → `HasChanges == false` (documents DATA-103 scope).

### 7.9 Age verdict
(incoming 2026-09-29 10:00:00, current 2026-09-28 09:00:00) →
`"Incoming saved: 2026-09-29 10:00:00\nCurrent saved:  2026-09-28 09:00:00\n➜ The incoming data is NEWER than your current data."`;
(nil, 2026-09-28 09:00:00) → `"Incoming saved: (no save date)\nCurrent saved:  2026-09-28 09:00:00\n➜ The incoming data has no save date (older format); it may be older."`;
(nil, nil) → `…\n➜ Neither copy has a save date; relative age is unknown.`

### 7.10 Model helpers
* `WhenText`: (nil, D=2026-10-05) → `2026-10-05`; (S=2026-10-01, D=2026-10-05) → `2026-10-01 → 2026-10-05`;
  (S=2026-10-05 10:00, D=2026-10-05) → `2026-10-05`; (S=2026-10-09, D=2026-10-05) → `2026-10-05`; (S only) → `""`.
* `CoversDay` with S=10-01, D=10-05: 09-30 false, 10-01 true, 10-03 true, 10-05 23:59 true, 10-06 false; S=10-09,
  D=10-05: only 10-05 true.
* `ContractStatusOn(today 2026-09-29)`: sign-off `2026-09-28` Expired; `2026-09-29` Critical; `2026-10-29`
  Critical (30); `2026-10-30` DueSoon (31); `2026-11-28` DueSoon (60); `2026-11-29` Ok (61); `""` Unknown;
  `"31/12/2026"` Unknown (unparseable, month-first).
* `ParseDate`: `2026-03-04`, `2026/03/04`, `2026.03.04`, `" 2026-03-04 "` → 2026-03-04; `03/04/2026` → 2026-03-04
  (**March 4**); `12 Mar 2026` → 2026-03-12; `abc` → nil.
* Keys: `PortCall{PortName "Bonny", ArrivalDate "2026-05-01"}.Key` = `bonny@2026-05-01`;
  `Port{UnLocode "NGBON"}.Key` = `ngbon`; `Port{Name "Bonny", Country "Nigeria"}.Key` = `bonny|nigeria`;
  `PortVisit{"Alpha","2026-05-01","08:00"}.VisitKey` = `alpha|2026-05-01|08:00`;
  `CrewMember{EmployeeId " "}` with First `Ana`, Last `Cruz` → `Ana|Cruz`; First `""`, Last `Cruz` → `Cruz`.
* Displays: template `""` with 1 item → `(unnamed)  ·  1 item`; schedule `Watch` with 2 entries and vessel `Alpha`
  → `Watch  ·  2 entries  ·  Alpha`; bucket `Deck` / `Location` → `Deck  ·  Location`; bucket `""`/`""` →
  `(unnamed)`; log 2026-09-29 08:15:30Z → TimeUtc `2026-09-29 08:15:30 UTC`.
* Status sync: new task → set IsComplete true → Status Done; set Status Blocked → IsComplete false; set
  IsComplete false when Status is InProgress → Status stays InProgress.

### 7.11 Trash / undo / log / recurrence
* Trash 201 items → oldest by `DeletedUtc` evicted and its `ItemId` purged from every `RelatedIds`,
  `ProcedureIds`, `TaskIds`, step links and file `LinkedItemIds`.
* Entry with `DeletedUtc` = now − 91 days → evicted by `PruneTrash` at startup.
* Batch of 3 (same BatchId) + a later single delete: first undo restores the single (1); second restores all 3.
* Restore when an item with the same Id already exists → entry removed from Trash, item not duplicated.
* Log: 10 001 appends → count 10 000, first entry is the 2nd appended; blank name → `(unnamed)`.
* Recurrence: monthly task Deadline 2027-01-31 completed → clone Deadline 2027-02-28, source RecurrenceSpawned true,
  clone RecurrenceSpawned false/IsComplete false/Status Todo/new Ids/ScheduledStart nil; ranged task S=10-01,
  D=10-05 weekly → clone S=10-08, D=10-12; subtask deadline 10-03 → 10-10; undated daily task completed on
  2026-09-30 → clone Deadline = 2026-10-01 00:00 **Local**; log detail `next Monthly occurrence → 2027-02-28`.
  A second `ReconcileRecurrences()` spawns nothing.
* Migration: file without `SchemaVersion`, completed monthly task (with a completed monthly subtask) and a Done
  weekly procedure → all `RecurrenceSpawned = true`; next save writes `"SchemaVersion":1`; a file with
  `"SchemaVersion":7` → warning v7, stays 7 on save.

### 7.12 Settings
* No file → defaults; `AppIdentity` = computer name.
* `{"CurrentDataFile":"C:\\x\\data.json","DarkMode":true,"Foo":1}` on the Mac → CurrentDataFile = default,
  DarkMode true; after `SetSyncOnSave(true)` the file contains `"Foo":1` (preserved) and
  `"CurrentDataFile":"<mac default path>"`.
* `SetAppIdentity("  ")` → identity = computer name; `SetAppIdentity(" Vessel-Alpha ")` → `Vessel-Alpha`.
* `SetSharedSaveFile(nil)` → key removed. `SetGeminiApiKey(nil)` → Windows keeps the old key (D-7); Mac clears.
* Invalid `PasswordSalt` (`"%%%"`) → all defaults (catch branch), `HasPassword` false.

### 7.13 Shared-save decision tables
`CheckForUpdate` (local L, bundle B, lastSeen S, lastSynced Y, dirty d):
| Situation | Result |
|---|---|
| folder missing | OFFLINE, no pull |
| folder ok, bundle missing | healthy, no pull |
| B unreadable | no state change |
| B ≤ L (L non-nil) | healthy, no pull |
| B > L and B == S | healthy, no pull (declined/seen) |
| B > L, B ≠ S, !d, L == Y | silent pull; S = Y = new L; status "Reloaded the shared save…" |
| B > L, B ≠ S, d | prompt; No → S = B |
| B > L, B ≠ S, !d, L > Y | prompt |
| L nil (fresh DB) | pull (prompt only if dirty) |
On close: (bundle absent) → push; (B unreadable) → no push; (L ≥ B) → push; (L < B) → no push.

### 7.14 Suggested automated tests (Swift Testing)
1. Golden round-trip: a real Windows `data.json` fixture (to be captured from the Windows build; include tasks with
   subtasks, a vessel with quick cards/jobs/ports, crew with flags, trash, SIRE bodies, unknown keys) →
   parse → write → byte-identical (verifies order, escaping, dates). **Required before release.**
2. Semantic round-trip: parse → write → parse → deep-equal (all models).
3. Cross-TZ: parse/write under `TZ=America/New_York`, `Europe/Athens`, `Asia/Kolkata`, `UTC`.
4. Crypto vectors §7.1–7.2.
5. Bundle import/export matrix §7.7 in a temp `AA_DATA_DIR`.
6. Atomic write under concurrent reader (reader never sees a partial file).
7. Shared-save state machine §7.13 with an injected clock and file system.
8. DataDiff §7.8 with snapshot-tested tree text.

---

## 8. Known defects and open questions (for the product owner)

### 8.1 Defects found in the Windows code
| ID | Where | Defect | Mac recommendation |
|---|---|---|---|
| D-1 | `SharedSaveTick` (`MainWindow.xaml.cs:996`) | Periodic shared push only runs if `IsDirty`, but the 750 ms autosave clears dirty long before the 1-minute tick → edits reach the shared bundle mostly only on close. | Push when `IsDirty \|\| LastModified > lastSynced` (the predicate the pull side already uses). |
| D-2 | `OnClosing` (`:163-177`) | The close-save stamps `Now` before the "not older than the bundle" test, so the test is always true → a bundle written by another machine within the last poll interval can be overwritten on close. | Run `CheckSharedFileForUpdate` first and compare the bundle stamp with `lastSynced`/pre-save stamp; prompt if the bundle changed since last sync. |
| D-3 | `ImportBundleSmart` / `ImportSharedBundle` | Only the presence of `data.json` is validated; invalid JSON is written over the local file and orphans are swept before `LoadFrom` throws → next launch in safe mode. | Parse-validate the staged `data.json` (full model decode) **before** touching `files/` or the local data file. |
| D-4 | `ContainerEditor.Load` (`:404-409`) | If the session is unlocked with a different password (incl. the master `redemption`, or after the password was changed/re-salted), `Decrypt` returns null and the body is replaced by `""` and saved — destroying the legacy encrypted note. | On decrypt failure keep the blob, withhold persistence, and tell the user the password doesn't match. |
| D-5 | `SetPassword` | Changing the app password generates a new salt; existing `enc:` blobs become undecryptable. | Before re-salting, decrypt-and-migrate any remaining `enc:` bodies with the old password (they are legacy anyway), or warn. |
| D-6 | `MenuSetPassword_Click` | Changing the app password does not ask for the current one. | Ask for the current password (master accepted) before changing — confirm with owner (Q-4). |
| D-7 | `WriteSettings` | `GeminiApiKey = GeminiApiKey ?? existing` — clearing the key does not persist. | Clear really clears (Keychain on Mac). |
| D-8 | `PasswordService.DeriveKeys` | The stored `PasswordHash` equals the AES key (first PBKDF2 block). Anyone with `settings.json` can decrypt the ciphertext part of `enc:` blobs (MAC can't be checked without the password). | Format must stay for compatibility; no new blobs are produced, so risk is limited to legacy data. Document only. |
| D-9 | Shared-save tooltip and confirmation text | Say "every 10 minutes"; actual cadence is 1 minute. | Use "every minute". |
| D-10 | `DataDiff.DiffFiles` | `ToDictionary` throws if one container has two files with the same `Name\|Path` (e.g. the same live link added twice) → the preview crashes (caught by the crash handler; import aborted). | Use multiset semantics (count-aware) instead of throwing. |
| D-11 | `RestoreTrash` | If a live item with the same Id exists, the trashed copy is dropped silently and still logged "restored". | Keep behaviour (no duplicate ids) but tell the user "already exists — kept the current one". |
| D-12 | Safe mode + shared save | In safe mode the empty model has no `LastModified`, so the shared-save auto-pull imports the bundle silently, overwriting the unreadable local file that safe mode promised not to touch. | In safe mode, ask before pulling (or suspend auto-pull) and first copy the unreadable file to `data.unreadable-<stamp>.json`. |
| D-13 | `ExportFolderToZip` | "Inside AppFolder" test has no trailing separator (`…\AA2\x.zip` is refused too). | Compare with a trailing separator. |
| D-14 | `MenuSaveAs_Click` | Stamps `LastModified` in memory without marking dirty/saving; Save As output has no schema stamp. | Stamp only the exported copy; write via the normal serializer (with `SchemaVersion`). |
| D-15 | `InitPagesAndRestoreUi` | `SelectedMainTabIndex` (captured in display order) is applied before the custom tab order on first load → wrong tab selected when the order was customised. | Apply order first, then the index. |
| D-16 | `WriteSettings` | Not atomic; failures swallowed silently. | Atomic write; surface failures in the status line. |
| D-17 | `MenuImport_Click` | The chosen external file is rewritten in place (normalised, stamped) and becomes the active file — surprising for a file on a USB stick/network. | Faithful by default; consider a "copy into AA folder instead" option (Q-5). |

### 8.2 Open questions
* **Q-1** Keep the hard-coded login (44233/redemption) on the Mac exactly as is? (Spec assumes yes.)
* **Q-2** Property order: confirm derived-first order with a real Windows fixture (§4.1.3, §7.14-1).
* **Q-3** Should the Mac change preview add a (clearly labelled) "Other data" section for crew/saved lists/ports/
  SIRE differences, which Windows silently omits? (Additive UI only; default off to stay faithful.)
* **Q-4** Require the current password before changing the app password (D-6)?
* **Q-5** Offer "copy into AA folder" when importing an external JSON (D-17)?
* **Q-6** For dates the Mac creates from "today", write Local (Windows-like) or Unspecified (time-zone-safe)?
  Recommendation: Unspecified for calendar dates, Local only for timestamps (`LastModified`, `Added`, `CreatedAt`).
* **Q-7** Sandbox or not? Spec recommends Developer ID without sandbox (§6.2).
* **Q-8** The iOS app may write a different `SchemaVersion` (the protocol doc's example shows 3). Align all three
  apps on one number before shipping, or the Mac/Windows will show "newer format" warnings for iOS files.

---

## Appendix A — Swift shape sketch (non-normative)

```swift
struct NetDateTime: Hashable, Comparable, Sendable {          // .NET DateTime emulation
    enum Kind: Sendable { case unspecified, utc, local }
    var ticks: Int64; var kind: Kind
    static func == (a: Self, b: Self) -> Bool { a.ticks == b.ticks }   // Kind ignored, like .NET
    static func < (a: Self, b: Self) -> Bool { a.ticks < b.ticks }
    init(parsing: String, zone: TimeZone = .current) throws           // §4.1.5 read rules
    func jsonString(zone: TimeZone = .current) -> String               // §4.1.5 write rules
    var date: NetDateTime { get }                                      // midnight, same kind
    func toLocalTime(zone: TimeZone = .current) -> NetDateTime
    static func now() -> NetDateTime; static func utcNow() -> NetDateTime; static func today() -> NetDateTime
}
struct WorkStatus: RawRepresentable, Hashable, Sendable { let rawValue: Int
    static let todo = Self(rawValue: 0), inProgress = Self(rawValue: 1), blocked = Self(rawValue: 2), done = Self(rawValue: 3) }

@MainActor @Observable final class TaskItem: HierarchyItem {
    var deadline: NetDateTime? ; var rangeStart: NetDateTime?
    var isJob = false; var durationMinutes = 60; var scheduledStart: NetDateTime?
    var recurrence = RecurrenceKind.none; var recurrenceSpawned = false
    var isComplete = false { didSet { /* DATA-130 sync, guarded */ } }
    var status = WorkStatus.todo { didSet { /* DATA-130 sync, guarded */ } }
    var subtasks: [TaskItem] = []
}

actor PersistenceWriter { func write(_ json: String, to url: URL, encrypt: Bool) throws }   // FIFO, §6.4/§6.5
@MainActor @Observable final class AppRepository {
    let data: AppData; private(set) var isDirty = false; var suspendSaving = false
    func markDirty(); func save() async throws; func detach()
    // §3.17 trash, §3.18 recurrence, §3.24 lookups/relations/groups, log
}
```

---

## Addendum: Golden-fixture plan to close the 'Verification TODO' / '(confirm)' items

> **Status:** normative plan appended 2026-09-30 to spec 01. Feature IDs **DATA-300 … DATA-326** continue this
> spec's prefix (DATA-160 … DATA-186 belong to the multi-process addendum written alongside this one, so this plan
> starts at DATA-300); section numbers are prefixed **GF.** so they never collide with §0–§8 above or with the
> multi-process addendum's **MP.** sections. Nothing above this
> heading is changed. When a golden produced by this plan contradicts a statement anywhere in
> `mac/Docs/Spec/*.md`, **the golden wins** and the statement is corrected by an erratum (DATA-308).
>
> **Sources read for this addendum** (in addition to §0): `Tests/FlashSync.Interop/FlashSync.Interop.csproj` and
> `Program.cs` (the linking pattern), `AA/Models/Models.cs`, `AA/Models/CrewMember.cs`, `AA/Sire/SireState.cs`,
> `AA/Sire/SireModels.cs`, `AA/Services/DataStore.cs` (all of it), `DataDiff.cs`, `SearchService.cs`,
> `ReminderService.cs`, `WorkRange.cs`, `BatchDone.cs`, `BatchDeadline.cs`, `BatchDelete.cs`, `SavedListOrder.cs`,
> `DateResolver.cs`, `CrewConverter.cs`, `CrewMapping.cs` (signatures), `CompasReader.cs` (the `CompasRow` type),
> `PasswordService.cs`, `ItemLockService.cs`, `AppRepository.cs`, `Dpapi.cs` (dependency), `ChecklistExporter.cs`,
> `XlsxWriter.cs`, `HtmlToXamlConverter.cs` / `ListFormatting.cs` / `Sire/SireFlow.cs` / `Sire/SireBank.cs` /
> `Sire/SireToAa.cs` / `Sire/TagExtractor.cs` (WPF-dependency check and call sites), `Views/ContainerEditor.xaml(.cs)`
> (editor properties, `Load`, `PersistRichText`, `OnRtbPasting`, `InsertPlainText`, toolbar handlers),
> `Views/SirePage.xaml(.cs)` (`DetailBox`, `FlushBody`), `App.xaml` (editor resources), `AA/AA.csproj` (package
> versions), `.gitattributes` / `git ls-files --eol` (line endings), `mac/Docs/ARCHITECTURE-BRIEF.md` (Rule zero),
> `mac/Docs/original-source-checksums.sha256`, `PROGRESS.md` (harness/verification notes, Flash Sync interop,
> data-safety batch, portable attachments), and every `(confirm` / `— confirm` / `Verification TODO` / `— verify`
> marker in `mac/Docs/Spec/*.md` (01, 02, 03, 04, 05, 08, 09, 10, 12, 13).

### GF.0 "This should be written in Swift" — where C# is, and is not, allowed

* Everything that ships — `AACore` and the `AA` app — and **every test that consumes a golden** is Swift
  (`AACoreTests`, Swift Testing). No C# is compiled by `mac/Package.swift`, linked into `AA.app`, or needed to
  build, run or unit-test the Mac app.
* The two generators in this plan are **oracles, not ports**. `WinFixtures` (Part 1) and `WinCapture` (Part 2)
  compile the **unmodified, read-only** Windows C# files and *record what that code actually does*. That is their
  entire value: a generator re-written in Swift could only compare Swift with Swift and would prove nothing about
  Windows compatibility. They follow the existing precedent `Tests/FlashSync.Interop` (sources linked, never copied).
* They are dev-only tools under `mac/Tools/` (Rule zero: "all Mac code, docs, tests, scripts and fixtures live under
  `mac/`"), excluded from `Package.swift`, never shipped. The only things that cross into the Swift world are
  **data files** (JSON, ZIP, XLSX parts, XAML text, manifests).
* All consumer-side infrastructure — fixture index, golden matcher, ZIP-manifest builder, the `mac-out` emitter for
  the reverse check, the release gate — is Swift (GF.8).

### GF.1 Overview

**Purpose.** Specs 01–13 were written from the C# source. Some claims could not be proven by reading: the exact
bytes System.Text.Json (STJ) emits (property order, escaping, dates), what WPF's `TextRange.Save` writes, how .NET
casing/parsing behaves on edge inputs. Those claims carry `(confirm)`, `Verification TODO` or `— verify` markers.
This plan replaces every such marker with a **committed golden file produced by the real Windows code**, plus a Swift
test that must reproduce it byte-for-byte (or, where bytes cannot be identical by nature, a precisely defined
normalised comparison — GF.4.9).

**Two parts.**
* **Part 1 — `mac/Tools/WinFixtures`**: a `net10.0` console that links the WPF-free model/service files the way
  `FlashSync.Interop` does, runs on macOS/Linux (and, for platform-sensitive cases, on Windows), and emits goldens
  under `mac/Tests/Fixtures/winfixtures/`: (a) `data.json`, (b) `settings.json`, (c) `.zip`/`.aaz` bundles with
  `source.json`, (d) `enc:` blobs and PBKDF2 vectors, (e) service outputs, (f) optional extension families.
* **Part 2 — `mac/Tools/WinCapture` + a manual script**: the items that need WPF or Windows itself (the
  `TextRange.Save` root attribute set, table `Thickness` form, default Hyperlink style, `Typography.Variants`, the
  empty document, RTF/Word/HTML paste shapes, built-in editing commands, SIRE XAML, DPAPI samples, Explorer ZIPs,
  Windows path semantics), with an exact capture procedure and commit locations.

**Where it sits.** Nothing in the app UI. It is part of the test pyramid: `swift test` (AACoreTests) reads the
goldens; the generators are run by a developer (or CI) when the pinned Windows sources or the pinned .NET runtime
change.

#### GF.1.1 Marker ledger (every verification marker → the case that settles it)

| Marker (file:line) | Claim to settle | Settled by | Part |
|---|---|---|---|
| 01:1438 §4.1.3 *Verification TODO* | derived-first property order; `Kind`/`BucketId` never written; extension data last | A02, A03, A04, A23 | 1 |
| 01 §8.2 Q-2 | same | A02 | 1 |
| 01 §7.4 depth "(Off-by-one to be confirmed…)" | max subtask depth (n = 28) | A18 | 1 |
| 01 §7.14-1 "Required before release" | a Windows-written `data.json` round-trips byte-identically | A02/A03 (+ optional local-only real file, DATA-314) | 1 |
| 01 §3.15 "hash set iteration — unspecified", "unstable sort" | .NET `HashSet`/`Dictionary` enumeration order; `List.Sort` tie order | E01.14–E01.16 | 1 |
| 01 §4.1.5 (implicit) | offset chosen for ambiguous/invalid local times; the hidden ambiguous-DST bit | A12, A13 | 1 |
| 01 §4.1.7 "SHOULD emulate for golden files" | default `JavaScriptEncoder` escaping set | A09 | 1 |
| 01 §7.2 "computed with Python" | `enc:` vectors from the real C# | K03, K04 | 1 |
| 04:931 "verify against a Windows-written data.json fixture" | property order | A02 | 1 |
| 04:1018 | lock hashes verify across platforms | K08, K09, DATA-312 | 1 |
| 02 §7.2 T-DONE-12 / D-21 | reversed-key decode result on Windows | A16 | 1 |
| 05 §7.6 | `test1234` `enc:` vector | K03 | 1 |
| 06 §7.14 | template order, dangling `GroupId`, `+02:00` step deadline round-trip | A02 sub-objects, A14 | 1 |
| 09 §7.1 rows "— verify" | `CrewMember.ParseDate` month-first, two-digit year, junk | E10 | 1 |
| 09 §7.2 rows "— verify" | `DateResolver` on `12 AUGUST 2026`, `DECEMBER 1ST 2026` | E09 | 1 |
| 10:1637 "verify against the crew spec's shared parser" | .NET two-digit-year window (`TwoDigitYearMax`) | E10 | 1 |
| 11 §4.5, 09 §7.13 | XLSX part bytes (modulo newline) | E13, E14 (+ W20 shipped-exe export) | 1 + 2 |
| 05 §4.3.4 S-1 (925), 03 Q-9 (1883), 03:1221 | the root `<Section>` attribute set | W01, M-01 | 2 |
| 05 S-4 (947) | `Table.Columns` present? 4-value `BorderThickness`? | W02, M-02 | 2 |
| 05 S-5 | Hyperlink default style written or not | W03, M-03 | 2 |
| 05 S-9 (972) | `Typography.Variants` from Ctrl+= / Ctrl+Shift+= | W04, M-04 | 2 |
| 05 S-10 (974), 05 §9 Q6 | empty-document form | W05, M-05 | 2 |
| 05 CONT-030 (214) | built-in RichTextBox key map | W06 | 2 |
| 05 CONT-023 (182), 05:566 | toggle semantics; strike reference comparison | W07 | 2 |
| 05 CONT-040/041/043 (290), CONT-044 (307) | list toggles, indentation, native list keys | W08 | 2 |
| 05 S-2/S-3 | normalised list shapes | W09 | 2 |
| 05 CONT-011 (157), D-2 (1495) | undo after a programmatic load | W10 | 2 |
| 05 §9 Q1 "RTF/Word paste shapes" | RTF → XAML conversions | W11 | 2 |
| 05 §7.1 "exact Windows output" | `HtmlToXamlConverter` output (it references `System.Windows.Media.Colors` → WPF-only) and the pasted result | W12 | 2 |
| 05 §9 Q1 combined decorations | attribute vs property-element form | W13 | 2 |
| 05 CONT-038 (280) | embedded-image placeholder | W14 | 2 |
| 05 §4.3.1 (851) | contextual properties applied on load/paste | W15 | 2 |
| 12 Q-1 (834, 1421) | SIRE golden XAML | W16 | 2 |
| 05 §4.4 | lock sentinel round-trip | W17 | 2 |
| 05 CONT-028 | Clear formatting output | W18 | 2 |
| 05 §7.7-10 "mandatory before release" | Windows loads every Mac XAML output | W23 | 2 (reverse) |
| 01 §4.6, §7.3 | real `AAENC1` / `AADPAPI1` files for detection tests | W19 | 2 (Windows run) |
| 01 §3.7 [MAC] rootedness, §7.6 | Windows `Path` semantics for Windows-form paths | A25 (windows run) | 2 (Windows run) |

#### GF.1.2 Markers that are *not* verification items (closed here: no fixture needed)

| Marker | Why no fixture |
|---|---|
| 01:2495 D-6 / Q-4 "confirm with owner" | product decision (ask for the current password), not a fact about Windows |
| 02:588 "— confirm …" | the word "confirm" is part of a dialog description, not a marker |
| 04:1405 Q-C | deliberate Mac divergence awaiting sign-off |
| 08:1420 | policy sentence ("confirm with the product owner") |
| 12:429, 12:1105 | product string `" — confirm this is not the case"` |
| 13:152 | UI flow ("stop and then confirm") |

### GF.2 Feature checklist

**DATA-300 — WinFixtures oracle project.** `mac/Tools/WinFixtures/WinFixtures.csproj`, `net10.0`, `OutputType Exe`,
`Nullable` and `ImplicitUsings` enabled (the linked files rely on the SDK implicit usings exactly as `AA.csproj`
does), `InvariantGlobalization=false` (GF.3.5), sources **linked** from `../../../AA/...` with `Link="Linked\..."`
(never copied, never edited), one shim (`System.Windows.Threading.DispatcherTimer`, GF.3.2), packages `ClosedXML
0.104.2` (same version as `AA.csproj`; needed by the linked `CompasReader.cs`) and `PDFsharp-MigraDoc 6.2.0` (the
cross-platform build of the `PDFsharp-MigraDoc-gdi 6.2.0` the app uses; needed only so `ChecklistExporter.cs`
compiles — `ExportPdf` is never executed). Full csproj in GF.3.1.

**DATA-301 — Source pinning & provenance.** Before generating, the tool computes SHA-256 of every linked file and
compares it with `mac/Docs/original-source-checksums.sha256` (`<hex>␠␠<path>` lines). Any mismatch aborts with the
list of differing files (a CRLF checkout on Windows is the usual cause — GF.6.2). `MANIFEST.json` records the
commit (`37cdab0` today), each linked path + hash, SDK/runtime (`RuntimeInformation.FrameworkDescription`), OS,
ICU version, culture, time zones used, and the generation date ("today").

**DATA-302 — CLI.** `generate`, `case` (child), `selfcheck`, `check-mac`, `verify-sources` (GF.3.3).

**DATA-303 — Process-per-group driver & determinism.** `DataStore.AppFolder` is a static initialised once from
`AA_DATA_DIR`, and `TimeZoneInfo.Local` is cached per process, so the driver re-launches itself per
(family, time zone) group — and per case for families that mutate statics (settings) — with a fresh data folder
and a pinned environment (GF.3.4, GF.3.5). Two consecutive `generate` runs produce byte-identical outputs except
`MANIFEST.json.generatedAtUtc` (verified by DATA-326).

**DATA-304 — Reflection access (read-only).** Private members are invoked by reflection, never by editing the
source (list in GF.3.6: `DataStore.Opts`, `IsDataOnlyBundle`, `AttachmentsMatch`, `MigrateLegacyAbsolutePaths`,
`ReadLastModified`, `IsUnderAppFolder`, `ReadDataText`, `DataDiff.Snip/PlainText`, `SearchService.MakeSnippet`,
`CrewConverter._importedAt`, …).

**DATA-305 — Volatile-value masking.** Values that are random or clock-derived **by design** (random salts/IVs,
`Guid.NewGuid()` defaults, `DateTime.Now/UtcNow` defaults, machine name, the data-folder path, temp paths) are
replaced in goldens by tokens (`%%NEWGUID:1%%`, `%%NOWLOCAL%%`, `%%DATADIR%%`, …, GF.4.5) using exact-value
substitution; the Swift matcher accepts any value of the right shape, with same-numbered tokens required to be equal.

**DATA-306 — Fixture tree, naming and the `.gitignore` trap.** Layout in GF.4.1. The repository `.gitignore`
ignores every file named exactly `data.json`, `settings.json` or `crash.log`; golden files therefore **never** use
those basenames (`*.golden.json`, `*.data-json.golden.json`, …) and extracted bundle trees are never committed —
only the `.zip`/`.aaz` plus its manifest and renamed payloads.

**DATA-307 — MANIFEST and case records.** One `MANIFEST.json` per fixture root lists every case (GF.4.3–GF.4.4):
id, family, title, platform, time zone, normative level (`must` / `should` / `record-only`), comparison mode,
input and output files, the Mac expectation (`same` or `divergent` + reason + Mac-expected file) and the spec
markers it settles.

**DATA-308 — Goldens win; spec-conflict protocol.** `selfcheck` compares goldens with literal vectors quoted in the
specs (GF.3.10). Every mismatch is recorded in `MANIFEST.json.specConflicts[]` and printed. A Swift test that
depends on a conflicting literal is written against the **golden**; the spec's owner appends an erratum to that spec
(this addendum does not edit other specs). A case is "settled" when it has a golden and no open conflict.

**DATA-309 — Comparison modes.** `bytes`, `bytes-masked`, `json-semantic`, `zip-manifest`, `zip-manifest-ordered`,
`text-lf`, `xml-canonical`, `record-only` — definitions and the reason for each in GF.4.9.

**DATA-310 — Platform matrix.** Each case is `platform: any`, `unix` or `windows`. The tool runs on macOS for
`any` + `unix`, and on Windows (same console, same sources) for `windows` cases and a neutrality cross-check of all
`any` cases (GF.3.12). The Mac expectation for Windows-form inputs (paths `C:\…`, `\\srv\…`) is the **windows** run.

**DATA-311 — Swift golden harness.** `mac/Tests/AACoreTests/WinFixtures/`: `FixtureIndex`, `GoldenMatcher`,
`ZipManifest`, one parameterised `@Suite` per family, time-zone/today/data-folder injection, mismatch diffs attached
to the test (GF.8).

**DATA-312 — Reverse direction.** A Swift emitter writes Mac-produced artefacts to `mac/Tests/Fixtures/mac-out/`
(JSON, settings, lock hashes, `enc:` blobs, bundles, XAML); `WinFixtures check-mac` (macOS **and** Windows) and
`WinCapture load-check` (Windows) prove the real C#/WPF accepts them (GF.3.11, W23).

**DATA-313 — Toolchain pinning, regeneration and CI.** `mac/Tools/global.json` pins the .NET SDK band; goldens are
regenerated only deliberately (`generate` then review the diff); CI runs `generate --verify-only` (regenerate to a
temp dir and diff against the committed goldens) plus `swift test --filter WinFixtures` (GF.8.6).

**DATA-314 — Privacy.** All fixture content is synthetic. A real user `data.json` (crew passports, dates of birth,
next of kin) is **never** committed. An optional local-only test round-trips a real file named by
`AA_REAL_DATA_JSON` and reports only pass/fail and byte offsets.

**DATA-315 — Family (a) `data.json`.** Cases A01–A26 (GF.5.a).
**DATA-316 — Family (b) `settings.json`.** Cases S01–S12 (GF.5.b).
**DATA-317 — Family (c) bundles.** Writer cases B01–B08, reader fixtures R01–R17, import matrix M, peek matrix P,
truth tables T, `ApplySyncedData` C01 (GF.5.c).
**DATA-318 — Family (d) crypto.** K01–K10 (GF.5.d).
**DATA-319 — Family (e) services.** E01–E16 (GF.5.e).
**DATA-320 — Family (f) extensions (SHOULD).** X01–X07 (GF.5.f).
**DATA-321 — WinCapture WPF harness.** `mac/Tools/WinCapture` (`net10.0-windows`, `UseWPF`), W01–W18 (GF.6).
**DATA-322 — Clipboard input capture.** `WinCapture dump-clipboard` records RTF/HTML/text formats from Word, Excel,
Outlook and browsers as committed inputs (GF.6.5).
**DATA-323 — Manual confirmations in the real `AA.exe`.** M-01…M-09 performed by a person in a scratch
`AA_DATA_DIR` (GF.6.6).
**DATA-324 — Windows-only non-WPF artefacts.** Windows run of WinFixtures (paths, CRLF-sensitive outputs, DPAPI
samples), Explorer-made ZIP, shipped-exe XLSX (W19–W22).
**DATA-325 — WPF load-check of Mac XAML.** W23.
**DATA-326 — Acceptance gate.** Definition of done in GF.9.

### GF.3 Logic & algorithms

#### GF.3.1 `mac/Tools/WinFixtures/WinFixtures.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <!--
    WinFixtures: golden-fixture ORACLE for the Mac port (spec 01, Addendum G).
    Compiles the Windows app's own WPF-free C# files (LINKED, never copied or modified) into a plain console so
    the real logic runs on macOS/Linux/Windows and its outputs can be recorded as goldens for the Swift tests.
    Dev-only: not referenced by mac/Package.swift, never shipped.
  -->
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>WinFixtures</RootNamespace>
    <!-- NOT invariant: casing and culture data must come from ICU as on a Windows install (.NET on Windows
         uses ICU too). The culture itself is pinned in code to en-US. -->
    <InvariantGlobalization>false</InvariantGlobalization>
    <AASrc>$(MSBuildThisFileDirectory)..\..\..\AA\</AASrc>
  </PropertyGroup>

  <ItemGroup Label="Linked read-only sources (hash-pinned by mac/Docs/original-source-checksums.sha256)">
    <Compile Include="$(AASrc)Models\Models.cs"                 Link="Linked\Models\Models.cs" />
    <Compile Include="$(AASrc)Models\CrewMember.cs"             Link="Linked\Models\CrewMember.cs" />
    <Compile Include="$(AASrc)Sire\SireState.cs"                Link="Linked\Sire\SireState.cs" />
    <Compile Include="$(AASrc)Sire\SireModels.cs"               Link="Linked\Sire\SireModels.cs" />
    <Compile Include="$(AASrc)Services\DataStore.cs"            Link="Linked\Services\DataStore.cs" />
    <Compile Include="$(AASrc)Services\Dpapi.cs"                Link="Linked\Services\Dpapi.cs" />
    <Compile Include="$(AASrc)Services\PasswordService.cs"      Link="Linked\Services\PasswordService.cs" />
    <Compile Include="$(AASrc)Services\ItemLockService.cs"      Link="Linked\Services\ItemLockService.cs" />
    <Compile Include="$(AASrc)Services\AppRepository.cs"        Link="Linked\Services\AppRepository.cs" />
    <Compile Include="$(AASrc)Services\DataDiff.cs"             Link="Linked\Services\DataDiff.cs" />
    <Compile Include="$(AASrc)Services\SearchService.cs"        Link="Linked\Services\SearchService.cs" />
    <Compile Include="$(AASrc)Services\ReminderService.cs"      Link="Linked\Services\ReminderService.cs" />
    <Compile Include="$(AASrc)Services\WorkRange.cs"            Link="Linked\Services\WorkRange.cs" />
    <Compile Include="$(AASrc)Services\BatchDone.cs"            Link="Linked\Services\BatchDone.cs" />
    <Compile Include="$(AASrc)Services\BatchDeadline.cs"        Link="Linked\Services\BatchDeadline.cs" />
    <Compile Include="$(AASrc)Services\BatchDelete.cs"          Link="Linked\Services\BatchDelete.cs" />
    <Compile Include="$(AASrc)Services\SavedListOrder.cs"       Link="Linked\Services\SavedListOrder.cs" />
    <Compile Include="$(AASrc)Services\DateResolver.cs"         Link="Linked\Services\DateResolver.cs" />
    <Compile Include="$(AASrc)Services\CrewConverter.cs"        Link="Linked\Services\CrewConverter.cs" />
    <Compile Include="$(AASrc)Services\CrewMapping.cs"          Link="Linked\Services\CrewMapping.cs" />
    <Compile Include="$(AASrc)Services\CompasReader.cs"         Link="Linked\Services\CompasReader.cs" />
    <Compile Include="$(AASrc)Services\ChecklistExporter.cs"    Link="Linked\Services\ChecklistExporter.cs" />
    <Compile Include="$(AASrc)Services\XlsxWriter.cs"           Link="Linked\Services\XlsxWriter.cs" />
  </ItemGroup>

  <ItemGroup Label="Extension families (f) — WPF-free, SHOULD">
    <Compile Include="$(AASrc)Services\ChecklistTemplateService.cs" Link="Linked\Services\ChecklistTemplateService.cs" />
    <Compile Include="$(AASrc)Services\ScheduleService.cs"      Link="Linked\Services\ScheduleService.cs" />
    <Compile Include="$(AASrc)Sire\SireExport.cs"               Link="Linked\Sire\SireExport.cs" />
    <Compile Include="$(AASrc)Sire\TagExtractor.cs"             Link="Linked\Sire\TagExtractor.cs" />
    <Compile Include="$(AASrc)Sire\TaskIdentifierService.cs"    Link="Linked\Sire\TaskIdentifierService.cs" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="ClosedXML" Version="0.104.2" />
    <PackageReference Include="PDFsharp-MigraDoc" Version="6.2.0" />
  </ItemGroup>
</Project>
```

Files deliberately **not** linked, and why: `HtmlToXamlConverter.cs` (uses `System.Windows.Media.Colors`, line 504 →
Part 2), `ListFormatting.cs`, `Sire/SireFlow.cs`, `Sire/SireBank.cs` (WPF → Part 2), `DpapiDataStore.cs` (Google
`IDataStore` dependency; not needed), `GoogleDriveUploader.cs`, every `Views/*` and `MainWindow.*`.
`Dpapi.cs` compiles everywhere (P/Invoke declarations only); on macOS/Linux any call throws
`DllNotFoundException`, which is exactly the "unreadable file" path `DataStore.Load` already catches (A20).

#### GF.3.2 The only shim — `mac/Tools/WinFixtures/Shims/DispatcherTimer.cs`

```csharp
// Lets the unmodified AA/Services/AppRepository.cs compile outside WPF. Provides only what AppRepository uses
// (object-initializer Interval, Tick, Start, Stop; AppRepository.cs:17,34-35,264,296,305-306). It never ticks by
// itself: the generator persists explicitly (AppRepository.Save) so no background timing can reach a golden.
namespace System.Windows.Threading;

public sealed class DispatcherTimer
{
    public TimeSpan Interval { get; set; }
    public bool IsEnabled { get; private set; }
    public event EventHandler? Tick;
    public void Start() => IsEnabled = true;
    public void Stop() => IsEnabled = false;
    /// <summary>Generator-only: fire the 750 ms debounce (BackgroundSaveIfDirty) on demand.</summary>
    public void RaiseTick() => Tick?.Invoke(this, EventArgs.Empty);
}
```
No other shim is permitted. A case that would need more (e.g. `MainWindow.AgeVerdict`) moves to Part 2.

#### GF.3.3 CLI (`dotnet run --project mac/Tools/WinFixtures -c Release -- <mode> …`)

| Mode | Arguments | Behaviour |
|---|---|---|
| `verify-sources` | — | DATA-301 check only; exit 1 on mismatch |
| `generate` | `--out <root>` `[--platform unix\|windows]` `[--families a,b,c,d,e,f]` `[--verify-only]` | Driver (GF.3.4). `--verify-only` generates into a temp root and diffs against `<root>`; exit 1 on any difference (CI) |
| `case` | `<family> --out <root> --tz <id> --run <runId> --platform <p> [--only <caseId>]` | Child process; never run by hand |
| `selfcheck` | `--out <root>` | Compares goldens with spec literals (GF.3.10), rewrites `specConflicts[]` |
| `check-mac` | `<mac-out dir> --report <file> [--platform unix\|windows]` | Reverse check (GF.3.11) |

Default `--out` is `mac/Tests/Fixtures/winfixtures`; default platform is detected (`OperatingSystem.IsWindows()`).

#### GF.3.4 Driver algorithm (`generate`)

```
generate(root, platform, families):
  verifySources() or abort                                   // DATA-301
  runId  = UtcNow "yyyyMMdd'T'HHmmss'Z'"
  groups = [(f, tz) for f in families for tz in TZS(f)]      // TZS(json) = Athens, New_York, Kolkata, UTC, Kathmandu, Chatham
                                                             // TZS(other) = [Europe/Athens]; settings and bundle-M cases: one group PER CASE
  order groups so that (json, Europe/Athens) runs first      // A14 reads Athens-written files
  for g in groups:
    dataDir = platform == unix ? "/tmp/aa-winfixtures/{runId}/{g.slug}" : "C:\aa-winfixtures\{runId}\{g.slug}"
    delete dataDir recursively; create it
    env = inherited + { AA_DATA_DIR=dataDir, LANG=en_US.UTF-8, LC_ALL=en_US.UTF-8,
                        DOTNET_CLI_TELEMETRY_OPTOUT=1, TZ=g.tz (unix only) }
    rc = spawn(Environment.ProcessPath, ["case", g.family, "--out", stagingRoot, "--tz", g.tz, "--run", runId,
                                         "--platform", platform] + (g.caseId ? ["--only", g.caseId] : []), env)
    if rc != 0: abort("group {g} failed")                    // never commit a partial run
    delete dataDir
  merge stagingRoot/.partial/*.json → MANIFEST.json.cases (sorted by id, ordinal)
  selfcheck(); neutralityCheck() when both platforms' outputs are present
  move stagingRoot over root atomically (or diff only, with --verify-only)

case(family) [child]:
  pin cultures (GF.3.5); assert TimeZoneInfo.Local.Id == tz (unix) ; assert DataStore.AppFolder == $AA_DATA_DIR
  assert Environment.NewLine == (platform == unix ? "\n" : "\r\n")
  for c in cases(family) where platform matches and (--only absent or c.id == --only):
     ResetWorld()                                            // GF.3.5
     build inputs → write input files → call the linked C# → mask (GF.3.7) → write outputs → append case record
```

#### GF.3.5 Determinism controls

| Source of variation | Control |
|---|---|
| Data folder | fresh `AA_DATA_DIR` per group (`/tmp/aa-winfixtures/<run>/<group>` or `C:\aa-winfixtures\…`); every literal occurrence → `%%DATADIR%%` |
| Static state between sub-cases | `ResetWorld()`: delete everything inside `AA_DATA_DIR`; `DataStore.LoadSettings()`; `PasswordService.LoadFrom(null, null)`; `ItemLockService.RelockAll()`. Cases that exercise statics that `LoadSettings` does **not** reset (`GeminiApiKey`, `FolderBuilderBase`, §3.1) run one-per-process |
| Culture | at child start: `CultureInfo.DefaultThreadCurrentCulture = DefaultThreadCurrentUICulture = CurrentCulture = CurrentUICulture = new CultureInfo("en-US")`. The Windows app runs under the user's culture; en-US is the reference (culture probes are separate `record-only` cases) |
| Time zone | `TZ` env var (unix); the child asserts `TimeZoneInfo.Local.Id`. Windows runs use whatever zone the machine has, recorded in the manifest; Local-date cases are `platform: unix` |
| Ids | every constructed object gets an explicit id `G(n) = aaaaaaaa-0000-4000-8000-{n:D12}` (e.g. `G(3)` = `aaaaaaaa-0000-4000-8000-000000000003`) |
| Dates | built with `new DateTime(y, mo, d, h, mi, s, kind).AddTicks(fraction)` (exact ticks and kind) |
| "Today" | services take `today` as an argument where the C# does; where it reads `DateTime.Today` internally (`DateResolver.ExpandYear`, recurrence of undated tasks) the case is flagged `dependsOnToday` and `MANIFEST.today` is injected by the Swift test |
| Clock defaults | `DateTime.Now/UtcNow` initialisers read back from the objects and masked `%%NOWLOCAL%%` / `%%NOWUTC%%` |
| Machine name | `%%MACHINE%%` |
| Random by design | salts, IVs, `ImportFile` names, batch ids, recurrence clone ids → tokens |
| Line endings | unix run asserts `Environment.NewLine == "\n"` and LF sources (hash check); CRLF-sensitive outputs are also produced by the windows run |
| File-system case sensitivity | the child probes (`create x`, `exists X`) and records it; case-insensitive (APFS default, NTFS) is required for bundle cases |
| `CrewConverter` import stamp | private readonly `_importedAt` set by reflection to `"2026-09-29 14:05"` after construction |

#### GF.3.6 Reflection access list (read-only use of private members)

| Member | Location | Used by |
|---|---|---|
| `DataStore.Opts` (private static field) | `DataStore.cs:267` | serialising expectation inputs exactly like the app (B07, A22, A24, K09, E11) |
| `DataStore.ReadDataText(string)` | `:409` | A19, A20 |
| `DataStore.IsUnderAppFolder(string)` | `:381` | A25 |
| `DataStore.ReadLastModified(string)` | `:641` | A26 |
| `DataStore.IsDataOnlyBundle(string, string)` | `:893` | T tables |
| `DataStore.AttachmentsMatch(string, string)` | `:926` | T tables |
| `DataStore.MigrateLegacyAbsolutePaths(AppData)` | `:949` | A25 |
| `DataDiff.Snip(string?)`, `DataDiff.PlainText(string?)`, `DataDiff.Fmt(DateTime?)` | `DataDiff.cs:264, 270, 262` | E01, E03 |
| `SearchService.MakeSnippet(string, int, int)` | `SearchService.cs:131` | E02 |
| `DateResolver.ExpandYear(int, DateRole, bool)`, `StripTime`, `Clean` | `DateResolver.cs:290, 253, 250` | E09 |
| `CrewConverter._importedAt` (field) | `CrewConverter.cs:18` | E11 |
| `XlsxWriter.ColRef/Esc`, `ChecklistExporter.ColRef/Esc` | `XlsxWriter.cs:138,151`; `ChecklistExporter.cs:242,255` | E13, E14 |
| `PasswordService.DeriveKeys(string, byte[])` | `PasswordService.cs:138` | K01 |
| `AppRepository.NextOccurrence`, `_debounce` | `AppRepository.cs:535, 17` | X01 |

Helper: `static T Call<T>(Type t, string name, params object?[] a) => (T)t.GetMethod(name, BindingFlags.NonPublic |
BindingFlags.Static)!.Invoke(null, a)!;` (none of the listed methods is overloaded).

#### GF.3.7 Masking algorithm

```
Masker:
  subs = []                                  // (literal, token)
  Guid(g, n)       → subs += (g.ToString("D"), "%%NEWGUID:{n}%%"), (g.ToString("N"), "%%GUIDN:{n}%%")
  Now(dt)          → subs += (stjText(dt), dt.Kind == Utc ? "%%NOWUTC%%" : "%%NOWLOCAL%%")   // stjText = the value as Opts writes it, without quotes
  Literal(s, token)→ subs += (s, token), (jsonEscape(s), token)    // jsonEscape = STJ default-encoder form (paths with '\' or non-ASCII)
  Apply(text)      : for (lit, tok) in subs ordered by lit.Length descending: text = text.Replace(lit, tok)
```
Tokens are pure ASCII and contain `%`, which STJ writes literally, so masking never collides with real content
(the generator asserts that no input contains `%%`). The Swift matcher reverses the process (GF.8.2).

#### GF.3.8 Expectation JSON (service outputs, state dumps, matrices)

Written with `new JsonSerializerOptions { WriteIndented = true, IndentSize = 2, NewLine = "\n", Encoder =
JavaScriptEncoder.UnsafeRelaxedJsonEscaping }` plus a trailing `\n`: human-reviewable in diffs. They are compared
**semantically** (`json-semantic`): same keys, same array order, strings compared exactly (UTF-16 code units),
numbers compared as decimal text. They are *not* AA file formats — AA formats (`data.json`, `settings.json`,
`source.json`, `PayloadJson`) are always written with the app's own `Opts` and compared as bytes.

#### GF.3.9 ZIP manifest algorithm

For a ZIP produced by the app (bundle, XLSX), the generator reads it with `ZipArchive` **and** parses the raw local
and central headers (to get the method, flags and version-made-by that `ZipArchive` hides), then writes
`<id>.zip-manifest.golden.json` (GF.4.6) and every payload as a separate file (`<id>.entry.<n>-<sanitised-name>.golden.<ext>`).
Payloads that are AA formats (`data.json`, `source.json`) are additionally masked and compared as bytes.

#### GF.3.10 Self-checks against literals quoted in the specs (`selfcheck`)

| Literal | Spec | Golden |
|---|---|---|
| empty database string | 01 §4.2.1 | A01 |
| Task output line | 01 §7.4 | A02 sub-object / A04 |
| escaping examples | 01 §7.4, §4.1.7 | A09 |
| date table | 01 §7.5 | A12, A13 |
| path table | 01 §7.6 | A25 |
| `source.json` example | 01 §4.4 | B07 |
| PBKDF2 table, `enc:` table | 01 §7.1, §7.2 | K01, K03 |
| `test1234` vector | 05 §7.6 | K03 |
| DataDiff example | 01 §7.8 | E01.1 |
| Age verdict strings | 01 §7.9 | — (WPF-bound; W25) |
| search/snippet/plain-text tables | 02 §7.7 | E02, E03 |
| reminder example | 02 §7.8 | E04 |
| saved-list order table | 02 §7.9 | E12 |
| date tables | 09 §7.1–7.4 | E09, E10 |
| XLSX helpers | 09 §7.13, 11 §7.14 | E13, E14 |
Each mismatch → `specConflicts[]` entry `{case, spec, literal, golden, note}`.

#### GF.3.11 Reverse check (`check-mac`)

Input: `mac/Tests/Fixtures/mac-out/` written by the Swift emitter (GF.8.5). For each artefact:
* **json/** — `LoadFrom(file)` must not throw; `SerializeForSave(LoadFrom(file))` must equal the file bytes after
  projecting out nested unknown members (the Mac keeps them, Windows drops them — A10). Byte equality proves the Mac
  writes STJ's canonical form.
* **settings/** — `LoadSettings()` on the file; the state dump equals `<name>.expect.json`; a subsequent
  `SetDarkMode(x)` round-trip keeps every key.
* **crypto/** — `ItemLockService.Verify(item(LockHash, LockSalt), pw)` is true for the right password, false for a
  wrong one; `PasswordService.LoadFrom(hash, salt); Unlock(pw); Decrypt(blob) == plaintext`.
* **bundles/** — for each Mac `.aaz`/`.zip`, in a fresh data folder with local state L1 (GF.5.c):
  `ImportBundleSmart` returns the expected `ImportKind`, the expected `files/` listing results, `PeekBundleSource`,
  `PeekZipData` and `PeekZipLastModified` are non-null. **This mode must also run on Windows**: only NTFS rejects
  Windows-illegal entry names (`a:b.pdf`), and that is the failure it exists to catch (§6.6).
Report: `mac-out/check-report.<platform>.json` (CI artefact; not committed).

#### GF.3.12 Neutrality cross-check

When both `unix` and `windows` outputs exist, every `platform: any` case is compared byte-for-byte (after masking).
A difference is written to `MANIFEST.platformDivergences[]` and must be resolved by re-classifying the case
(`unix`/`windows`) with a documented cause (newline, path API, time-zone database, file-system semantics).

### GF.4 Data formats

#### GF.4.1 Tree

```
mac/Tools/
  global.json                              .NET SDK pin for both tools (DATA-313)
  WinFixtures/  WinFixtures.csproj  Program.cs  Shims/DispatcherTimer.cs  Support/*.cs  Builders/*.cs  Cases/*.cs
  WinCapture/   WinCapture.csproj   Program.cs  Cases/*.cs                            (Windows only)
mac/Scripts/fixtures.sh                    generate | verify | emit-mac-out | check-mac  (thin wrapper)
mac/Tests/Fixtures/
  winfixtures/
    MANIFEST.json
    inputs/      <id>.input.json, <id>.rows.json, <id>.input.bin …     (synthetic inputs shared by Swift and C#)
    json/        A01.appdata.golden.json … A13.read-matrix.golden.json …
    settings/    S01.settings.golden.json  S01.state.golden.json …
    bundles/     B01.bundle.zip  B01.zip-manifest.golden.json  B01.entry.1-data-json.golden.json …
                 R01.bundle.zip … R16.bundle.aaz   M.matrix.golden.json   P.matrix.golden.json   T.tables.golden.json
    crypto/      K01.pbkdf2.golden.json …
    services/    E01.datadiff.golden.json … E13.X1.zip-manifest.golden.json  E13.X1.part.6-sheet1-xml.golden.xml …
    ext/         X01… (SHOULD)
    windows/     same sub-structure for platform:windows cases, plus W19 DPAPI samples
  xaml/
    wpf-capture/ MANIFEST.json  W01b-S1-typed.xaml  W01b-S1-typed.json-string.txt  W01b-S1-typed.meta.json …
      inputs/    R-1.rtf  R-1.html  R-1.txt  R-1.formats.json  H-1.html …
      manual/    M-01.xaml … M-capture.data-json.golden.json  M-07.checklist.xlsx
    mac-roundtrip/  load-check.json  <name>.wpf-resaved.xaml
  mac-out/       json/ settings/ crypto/ bundles/ xaml/   (Swift emitter output, DATA-312)
mac/Tests/AACoreTests/WinFixtures/
  FixtureIndex.swift  GoldenMatcher.swift  ZipManifest.swift  XMLCanonicalizer.swift  MacOutEmitter.swift
  JSONGoldenTests.swift  SettingsGoldenTests.swift  BundleGoldenTests.swift  CryptoGoldenTests.swift
  ServiceGoldenTests.swift  XamlCaptureTests.swift
```
`mac/.gitignore` gains: `Tools/*/bin/`, `Tools/*/obj/`, `Tools/.dotnet/`, `Tools/*/.aa-build/`,
`Tests/Fixtures/**/.partial/`, `Tests/Fixtures/mac-out/check-report.*.json`.

#### GF.4.2 Naming rules

* Never a basename of exactly `data.json`, `settings.json` or `crash.log` (repo `.gitignore`).
* Goldens: `<caseId>.<artefact>.golden.<ext>`; inputs: `<caseId>.input.<ext>`; bundles `<caseId>.bundle.zip|.aaz`.
* Payload names inside bundle folders: `<caseId>.entry.<index>-<name with / → _ and non-[A-Za-z0-9._-] → _>.golden.<ext>`.
* Case ids: family letter + two digits (+ `.n` sub-case), e.g. `A13.7`, `E01.14`; Part 2: `W01a`, `M-01`.

#### GF.4.3 `MANIFEST.json` (winfixtures)

```json
{
  "schema": 1,
  "generator": {
    "name": "WinFixtures", "version": "1.0.0",
    "linkedSourcesCommit": "37cdab0",
    "linkedSources": [{ "path": "AA/Models/Models.cs", "sha256": "356c56b0…27e21" }],
    "runtime": ".NET 10.0.x", "sdk": "10.0.1xx", "icu": "…", "os": "macOS 27.0 (arm64)"
  },
  "generatedAtUtc": "2026-09-30T10:00:00Z",
  "today": "2026-09-30",
  "runs": [
    { "platform": "unix", "timeZones": ["Europe/Athens", "America/New_York", "Asia/Kolkata", "UTC", "Asia/Kathmandu", "Pacific/Chatham"], "caseInsensitiveFs": true },
    { "platform": "windows", "timeZone": "GTB Standard Time", "caseInsensitiveFs": true }
  ],
  "cases": [ /* GF.4.4 */ ],
  "specConflicts": [],
  "platformDivergences": []
}
```

#### GF.4.4 Case record

```json
{
  "id": "A13.4", "family": "json", "title": "read +03:00 in New York",
  "platform": "unix", "tz": "America/New_York", "normative": "must",
  "compare": "json-semantic", "dependsOnToday": false,
  "inputs":  { "inline": "\"2026-10-01T00:00:00+03:00\"" },
  "outputs": [{ "role": "result", "file": "json/A13.read-matrix.golden.json", "pointer": "/A13.4" }],
  "macExpectation": { "kind": "same" },
  "settles": ["01 §4.1.5", "01 §7.5"]
}
```
`macExpectation.kind` ∈ `same` | `divergent` (then `file` = Mac-expected golden and `reason` = the spec clause that
mandates the deviation, e.g. `"01 DATA-024 (preserve nested unknown keys)"`, `"01 §4.2.6 order-independent
Status rule"`, `"01 §6.6 Windows-safe names"`, `"11 DEV-03 sheet names"`).

#### GF.4.5 Token grammar

| Token | Matches (Swift regex) | Notes |
|---|---|---|
| `%%NEWGUID:n%%` | `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}` | same `n` ⇒ same value; different `n` ⇒ different values |
| `%%GUIDN:n%%` | `[0-9a-f]{32}` | shares the value space of `NEWGUID:n` (same GUID, `N` format) |
| `%%NOWLOCAL%%` | `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?[+-]\d{2}:\d{2}` | STJ Local form; also checked to be within ±10 min of the test's clock |
| `%%NOWUTC%%` | same with `Z` | |
| `%%MACHINE%%` | `[^"\\\r\n]+` | |
| `%%DATADIR%%` | literal substitution of the test's data folder (raw and JSON-escaped) | not a regex |
| `%%TEMP%%` | `[^"\r\n]*` | temp paths inside exception messages |
| `%%SALT16%%` | `[A-Za-z0-9+/]{22}==` | Base64 of 16 bytes |
| `%%HASH32%%` | `[A-Za-z0-9+/]{43}=` | Base64 of 32 bytes |
| `%%ENCBLOB%%` | `enc:[A-Za-z0-9+/]+={0,2}` | random-IV blob |

#### GF.4.6 `zip-manifest` schema

```json
{
  "entries": [
    { "name": "data.json", "isDirectory": false, "method": 8, "flags": 0, "utf8NameFlag": false,
      "uncompressedSize": 2345, "crc32": "0x1A2B3C4D", "sha256": "…",
      "payload": "B01.entry.1-data_json.golden.json",
      "versionMadeByHost": 3, "externalAttributes": "0x81A40000", "hasDataDescriptor": false }
  ],
  "zip64": false, "comment": "", "orderSignificant": false
}
```
Significant (Swift must match): the **set** of names (the **sequence** for XLSX, `orderSignificant: true`),
`isDirectory`, `uncompressedSize`, `crc32`, payload bytes, `utf8NameFlag` (set **iff** the name is non-ASCII),
`method` = 8 for non-empty files. Recorded but not significant: entry order (bundles), timestamps, compressed
bytes/size, `versionMadeByHost` (0 on Windows, 3 on Unix), `externalAttributes`, extra fields, data descriptors,
the method .NET picks for empty files and directory entries (expected 0, recorded). Container bytes can never be
byte-identical: DEFLATE encoders legitimately differ (.NET's zlib-ng vs Apple `Compression`), and DOS timestamps
are file mtimes.

#### GF.4.7 Expectation shapes (GF.3.8 options)

| Output | Shape |
|---|---|
| `DataDiff.Result` | `{"Added":1,"Changed":1,"Removed":1,"HasChanges":true,"Roots":[{"Change":"Added","Text":"[Vessel] Alpha","Children":[…]}]}` or `{"exception":{…}}` |
| search | `{"query":"FUEL","maxResults":500,"lockedOwnerIds":[],"hits":[{"OwnerId":"…","OwnerName":"…","Kind":"Component","Where":"Component › Name","Snippet":"Fuel pump","MatchStart":0,"MatchLength":4,"ChildId":"…"}]}` (`ChildId` `null` when absent) |
| reminder | `{"today":"2026-09-29","Overdue":2,"DueToday":2,"DueWeek":3,"Total":7,"Any":true,"Headline":"2 overdue  ·  2 due today  ·  3 due this week"}` |
| `DateResolution` | `{"input":"…","role":"Any","order":"Unknown","Value":"2026-03-04"\|null,"Raw":"…","DependedOnOrder":false,"Note":null,"ToStorage":"…"}` |
| DateTime read | `{"input":"…","ok":true,"ticks":639264096000000000,"kind":"Local","isAmbiguousTime":false,"isDaylightSavingTime":false,"wall":"2026-09-30 17:00:00.0000000","rewritten":"2026-09-30T17:00:00-04:00"}` or `{"input":"…","ok":false,"error":{"type":"System.Text.Json.JsonException"}}` |
| `BatchDelete.Summary` | all public fields + `Total`, `IsEmpty`, `KindBreakdown` |
| state dump (settings) | `{"CurrentDataFile":"%%DATADIR%%/data.json","GoogleDriveFolder":null,"SyncOnSave":false,"TextOnlyExport":false,"DarkMode":false,"EncryptLocalData":false,"GeminiApiKey":null,"AppIdentity":"…","FolderBuilderBase":null,"SharedSaveFile":null,"HasPassword":false,"IsUnlocked":false}` |
| exception | `{"exception":{"type":"System.IO.InvalidDataException","message":"The bundle has no data.json.","aaAuthored":true}}` — messages are compared only when `aaAuthored` (text written in AA's source); framework messages are informational |

#### GF.4.8 Selection-reference grammar (inputs of batch services)

```
ref      := "null" | "#literal:" <text> | "#row:" path | path
path     := root "[" int "]" ( "." child "[" int "]" )*
root     := Equipment | Tasks | Procedures | Vessels | Crew | ChecklistTemplates
child    := Subtasks | Steps | Components | Checklist | Items
```
`#row:` wraps the object in `new Row(item)` where `Row` exposes `public object Item { get; }` (the shape
`BatchDelete.Unwrap` reflects on, `BatchDelete.cs:132-139`).

#### GF.4.9 Comparison modes

| Mode | Rule | Used for |
|---|---|---|
| `bytes` | exact byte equality | AA formats without volatile values; crypto hex/Base64 |
| `bytes-masked` | exact equality outside tokens; tokens per GF.4.5 | `data.json`, `settings.json`, `source.json`, `PayloadJson` |
| `json-semantic` | GF.3.8 | service outputs, state dumps, matrices |
| `zip-manifest` / `zip-manifest-ordered` | GF.4.6 | bundles / XLSX |
| `text-lf` | exact after `\r\n → \n` on **both** sides | Windows-captured text whose newline depends on the build checkout (W20) |
| `xml-canonical` | parse (namespaces on), sort attributes by (namespace, local name), keep text nodes byte-exact (the XAML uses `xml:space="preserve"`), normalise empty elements to `<X />` and entities to `&amp; &lt; &gt; &quot;`, compare | Part 2 XAML semantic round-trip |
| `record-only` | no assertion; the Swift test logs a diff attachment | platform/culture-dependent probes, `.NET` quirks the Mac need not copy |

### GF.5 Part 1 — case catalogue

Defaults unless a row says otherwise: `platform: any`, `tz: Europe/Athens`, `normative: must`,
`compare: bytes-masked`, `macExpectation: same`. "Op" is the linked C# call; "Out" is what is recorded.

#### GF.5.a `data.json` (DATA-315)

**Kitchen-sink builder (KS)** — committed C# (`Builders/KitchenSink.cs`); coverage rules (normative): every type
of §4.2 present at least once; every persisted property **non-default** at least once; every enum at a non-zero
value; at least one `Guid?` set and one null; every `DateTime` kind; fractions with 1 and 7 digits; the strings below.

| Object (id) | Content |
|---|---|
| Equipment `G(1)` | Name `Main Engine → ⚓ <ME>`, Description `Two-stroke & 'slow' "speed" +1`, Tags `["engine","ME"]`, RelatedIds `[G(3)]`, GroupId `G(40)`, BucketIds `[G(50),G(51)]`, LockHash/LockSalt = the `correct horse`/S vector of §7.1, LockHint `the usual`, ProcedureIds `[G(4)]`, TaskIds `[G(3)]`, Components `[G(2): "Fuel pump", Notes "check every 500 h", Container G(102) with one file]`, Container `G(101)`: RichTextXaml = S-6-like XAML with `&amp;`, non-ASCII and `#FFFFE699`; Files: copy `files/0123456789abcdef0123456789abcdef_Manual v2.pdf` (Kind 0, Added = D_L, LinkedItemIds `[G(3)]`), live `\\shipserver\ops\Daily log.xlsx` (LinkInPlace), live folder `Z:\Routine` named `Routine  (folder)` (Kind 4), link `https://www.imo.org` (Kind 3, IsLink), image (1), video (2); SharedWithContainerIds `[G(103)]`; IsLocked `true` |
| Task `G(3)` | Name `Fire drill 😀`, Deadline `D_U` (2026-10-01 00:00 Unspecified), RangeStart 2026-09-27 00:00 **Local**, IsJob, DurationMinutes 90, ScheduledStart `D_L`, Recurrence 3, RecurrenceSpawned, IsComplete + Status 3; Subtasks `[G(5): Status 2, Deadline D_U7 (…08:30:15.1234567 Unspecified), Subtasks [G(6): Recurrence 4, RangeStart only]]` |
| Procedure `G(4)` | Steps `[G(7): Title "Sample fuel", BucketIds [G(50)], Done, Deadline D_Z (…08:15:30.1234560 Utc), IsJob, DurationMinutes 15, ScheduledStart D_U7, TaskIds [G(3)], EquipmentIds [G(1)]]`; Deadline D_L; Recurrence 2; Status 1; IsJob; DurationMinutes 120; ScheduledStart `D_Z0` (…08:15:30 Utc) |
| Vessel `G(8)` | QuickCards `[G(9): Title "Manuals", Target "files/…", IsFolder, Icon "🛟", Color "#80FF0000", X 12.5, Y -24, Width 333.25, Height 0.1]`, Jobs `[all 19 ShipJob fields non-default; OverdueDays -3; Notify; IsCompleted]`, NotificationsEnabled `false`, PortCalls `[G(10): all 14 strings]` |
| Group `G(40)` | Kind 3, Name `Engine room`, Expanded `false` |
| Crew `G(11)` | every string field non-empty incl. `José`, `Ωmega`; Checklist `[G(12)]`; Schedule four entries `G(13)…G(16)` with Kind 0–3 and RefId on three; ScheduleVesselId `G(8)`; Flags one per severity |
| Log | one entry, TimestampUtc `D_Z0` |
| Templates | ChecklistTemplate `G(20)` with one item (DurationMinutes 45, IsJob, Container G(120)), CreatedUtc D_Z, GroupId `G(21)`; a second template `G(29)` with GroupId `G(99)` (dangling, 06 §7.14); ListGroup `G(21)`; QuickBuckets `G(50)` (`Deck`/`Location`), `G(51)` (`Bosun`/``) |
| Ports | Port `G(22)` `Bonny`/`Nigeria`/`NGBON`, Visits `[VesselName "Alpha", VesselId G(8), dates/times]`; ScheduleTemplate `G(23)` VesselId G(8), Entries `[G(24)]`, CreatedUtc D_Z |
| Trash | TrashedItem `G(25)`: ItemType `Vessel`, ItemId `G(26)`, BatchId `G(27)`, Name, KindLabel, DeletedUtc D_Z0, PayloadJson = `JsonSerializer.Serialize(v26, typeof(Vessel), Opts)` |
| Sire | QuestionStatuses `{"1.1.1":"InProgress","2.1.1":"Checked","11.1.2":"NotApplicable"}`, Bookmarks `["1.1.1"]`, ForExport `["2.1.1"]`, Tasks `[G(28), IsCompleted, CreatedAt D_L]`, QuestionBodies `{"1.1.1": "<Section …>…</Section>"}` |
| Ui | every key of §4.2.20 non-null: WindowLeft -1280.5, WindowTop 0, WindowWidth 1600, WindowHeight 900.25, WindowState `Maximized`, SelectedMainTabIndex 3, the four Selected ids, CalendarSelectedDate D_U, CalendarViewMode `Week`, CalendarFontScale 13.5, ShowShortcutBar `false`, QuickViewPinIds, TabColors `{"TabTasks":"#FF00AA00"}`, TabOrder `["TabTasks","TabEquipment"]`, DueWindow sizes, MapFocusedItemId, SortAZ `{"Task":true,"savedlists":false}`, GroupExpanded `{"Vessel\|Engine room":false}`, the Crew* keys, LastDigestDate `2026-09-29`; ExtraData `{"NewPref":true}` |
| Root | LastModified D_LM (2026-09-29T11:15:29.9876543 Local), SchemaVersion 1, ExtraData `{"FutureThing":{"a":[1,2]}}` |

| Case | Input | Op → Out | Settles |
|---|---|---|---|
| **A01** | `new AppData()` | `SerializeForSave` → `A01.appdata.golden.json` | 01 §4.2.1 literal |
| **A02** | KS | `SerializeForSave` → `A02.appdata.golden.json` | 01:1438, Q-2, 04:931, `Kind`/`BucketId` never written, ext. data last, lowercase GUIDs, enum ints |
| **A03** | `A02` bytes written to `%%DATADIR%%/data.json` | `LoadFrom` → `SerializeForSave`; must equal A02 (idempotence) | 01 §7.14-1 |
| **A04** | one instance of every type with only ids/dates fixed | `SerializeForSave` → which defaults are written (`DurationMinutes:60`, `NotificationsEnabled:true`, `Icon:"\u2693"`, `Color`, `X/Y/Width/Height`, `Expanded:true`, `UserType:"Crew"`, `SignedOnOff:"On"`, `Guid.Empty` for `ItemId`/`BatchId`) | §4.1.2, §4.1.10 |
| **A05** | `inputs/A05.input.json` = every array of AppData with one `{}` element (nested: `Steps:[{}]`, `QuickCards/Jobs/PortCalls:[{}]`, `Flags/Schedule/Checklist:[{}]`, `Items:[{}]`, `Visits:[{}]`, `Entries:[{}]`, `Sire.Tasks:[{}]`, `Ui:{}`, one Equipment `{"Container":{"Files":[{}]}}`) | `LoadFrom` → `SerializeForSave`; `NEWGUID`/`NOWLOCAL`/`NOWUTC` tokens | §4.1.10 defaults table |
| **A06.1–A06.14** | reference-typed JSON `null`, one per sub-case: `Name`, `Description`, `Tags`, `RelatedIds`, `BucketIds`, `Container`, `Files`, `RichTextXaml`, `Subtasks`, `Steps`, `Ui`, `Sire`, `LockHash`, `Ui.TabColors` | outcome `{loadOk, saveOk, bytes \| exception}` — e.g. `"Files":null` is expected to make `NormalizeFilePaths` throw inside `LoadFrom` (→ safe mode on Windows) | §4.1.10; Mac expectation **divergent** where Windows fails ("treat null as default", §4.1.10 SHOULD) |
| **A07.1–A07.12** | value-type null and type mismatches: `"IsJob":null`, `"DurationMinutes":null`, `"Id":null`, `"Added":null`, `"Status":"Done"`, `"DurationMinutes":"60"`, `"DurationMinutes":60.0`, `"DurationMinutes":6E1`, `"Name":5`, `"IsJob":1`, `"Recurrence":7` (undefined enum), `"SelectedMainTabIndex":2147483648` | `{loadOk, …}`; `Recurrence:7` expected to load and re-write as `7` | §3.2 failure list; Mac: MUST NOT write these; reading MAY be lenient except `7` which MUST round-trip |
| **A08.1–A08.6** | GUID forms: upper-case D, braces, N (32 hex), `(…)`, `Guid.Empty`, 35 chars | load outcome + re-write | §4.1.4 GUID row |
| **A09a** | Task.Name = the 95 characters U+0020…U+007E in order; Description = `U+0000 U+0001 \b \t \n U+000B \f \r U+001F U+007F U+0080 U+009F U+00A0 é e+U+0301 — → ⚓ 😀 U+2028 U+2029 U+FEFF U+FFFD U+FFFF` | `SerializeForSave` bytes | §4.1.7 escaping set; NFD kept (no normalisation) |
| **A09b** | Tags = `["\uD800"]` (lone surrogate, built in C#) | record whether STJ throws or writes `\uFFFD`; `record-only` | Swift strings cannot hold it |
| **A10** | `inputs/A10.input.json`: top-level `FutureThing` `{"a":[1,2],"n":1.50,"e":1e2,"z":-0,"s":"é\u00e9\/","sp" :  { "k" : true }}`, `"FutureNull":null`, `"X":1,"X":2`, lower-case `"tasks":[]`; `Ui.NewPref`; nested unknowns `Tasks[0].TaskFuture`, `Tasks[0].id`, `Equipment[0].Container.ContainerFuture`, `…Files[0].FileFuture`, `Sire.SireFuture` | `LoadFrom` → `SerializeForSave` (Windows: nested dropped; raw number text kept; string escapes normalised; duplicates → ?) + derived Mac-superset expectation `A10.mac-expected.golden.json` (nested unknowns re-appended at the end of their object, input order) | DATA-024; divergent (superset) |
| **A11.1–A11.6** | `{"BucketId":g}`; `{"BucketIds":[g],"BucketId":g}`; `{"BucketId":g,"BucketIds":[h]}` (legacy **before** list); `{"BucketId":null}`; BucketId on Procedure/Equipment/Vessel; BucketId on a ChecklistStep (no such property → dropped) | load → `BucketIds` + re-write | §3.20 (Mac divergent on A11.3 by design) |
| **A12** (6 TZs, `platform: unix`) | Tasks whose Deadline is: Unspecified with fractions 0/.1/.123456/.1234567/.0000001; `MinValue`, `MaxValue` Unspecified; Utc 2026-09-29 08:15:30 and `.0000001`; Local 2026-09-29 11:15:30.5, 2026-01-15 09:00, 2100-06-01; New York ambiguous 2026-11-01 01:30 built as Local, and the same wall time obtained via `new DateTime(2026,11,1,6,30,0,Utc).ToLocalTime()`; New York gap 2026-03-08 02:30 Local; Athens ambiguous 2026-10-25 03:30, gap 2026-03-29 03:30; `DateTime.MinValue` as Local (`record-only`: LMT offsets differ between tz databases) | `SerializeForSave` bytes per TZ | §4.1.5 write rule; ambiguous-DST bit |
| **A13** (6 TZs, `unix`) | strings: `2026-10-01`, `2026-10-01T00:00`, `…T00:00:00`, fractions of 1…7 and 8 digits, `Z`, `z`, `+03:00`, `+0300`, `+03`, `-00:00`, `+14:00`, `+14:01`, leading space, `2026-10-01 00:00:00`, `2026-10-01T24:00:00`, `2026-02-29`, `2024-02-29`, `01/10/2026`, `0001-01-01T00:00:00+03:00`, `9999-12-31T23:59:59.9999999-05:00`, `2026-11-01T05:30:00Z`, `2026-11-01T06:30:00Z`, `2026-03-08T02:30:00-05:00` | `JsonSerializer.Deserialize<DateTime>` via `Opts` → GF.4.7 DateTime-read shape incl. the `rewritten` string | §4.1.5 read rule, §7.5 |
| **A14** | the Athens-written A12 file | read + rewrite under New York, Kolkata, UTC | §4.1.5 cross-zone rule, 06 §7.14 `+02:00` |
| **A15** | QuickCard/Ui doubles: 24, 24.5, -24, 0.1, 0.30000000000000004, 1e15, 1e16, 1.5e-7, 5e-324, 1.7976931348623157e308, -0.0, 123456789.123; reads `1.0`, `1e2`, `1E+2`, `0.10`, `NaN` (literal), `1e400` | bytes / outcome | §4.1.6 |
| **A16.1–A16.18** | `{"IsComplete":t/f}`, `{"Status":0…3}` (single keys); all 8 canonical `IsComplete`-then-`Status` pairs; all 8 reversed pairs | resulting `(Status, IsComplete)` + bytes | §4.2.6; 02 T-DONE-10…13; Mac divergent on reversed pairs (documented) |
| **A17.1–A17.4** | no `SchemaVersion` + completed monthly task with a completed monthly subtask + Done weekly procedure; `SchemaVersion 7`; `0`; `-1` | `Load()` flags (`LoadedNewerSchema`, `RecurrenceSpawned`) + `SerializeForSave` bytes | DATA-022/023 |
| **A18** | subtask chains n = 25…32 with a file carrying `LinkedItemIds` in the deepest container; hand-built JSON documents of depth 62…66 | serialise ok/throw per n; deserialise ok/throw per depth | §4.1.9, §7.4 off-by-one |
| **A19.1–A19.9** | files: UTF-8 BOM + A01; UTF-16 LE BOM + A01; trailing `\n` and spaces; `// comment`; trailing comma; literal `null`; `[]`; empty (0 bytes); A01 followed by a second object | `Load()` → `LastLoadFailed` + model bytes; `LoadFrom` → exception type | DATA-021, §4.1.8 |
| **A20** | `AAENC1\n` + 64 random bytes | `Load()` → `LastLoadFailed == true` (unix: `DllNotFoundException`; windows run: crypto failure) | §4.6, §7.3 |
| **A21** | `{"Tasks":[{"Name":"a","Name":"b"}]}` | outcome | STJ duplicate handling in .NET 10 |
| **A22.1–A22.3** | (C#-built) two tasks sharing one `Container` instance; a task that contains itself as a subtask; JSON `"Subtasks":[null]` | bytes / exception (`record-only` for the cycle) | `IgnoreCycles` semantics |
| **A23** | KS | `Serialize(KS, TrashOpts)` equals A02 without the schema stamp step (self-check) | §3.17 claim |
| **A24.1–A24.6** | `AppRepository` over KS: `TrashHierarchyItem(task G(3))`; `TrashCrew(G(11))`; `RestoreTrash` of each; restore when the id exists (D-11); payload `{"Tasks":` (invalid) → null; `ItemType "Bogus"` → null | AppData bytes after each step (`DeletedUtc`/`TimestampUtc` → `%%NOWUTC%%`) + returned values | §3.17, §4.10 |
| **A25** (unix + windows) | AppFolder = `%%DATADIR%%`, `files/ab12_x.pdf` present; stored paths: `files/ab12_x.pdf`, `%%DATADIR%%/files/ab12_x.pdf`, the same with the data-folder path upper-cased, `/Users/bob/AA/files/ab12_x.pdf`, `/Users/bob/AA/files/zz_missing.pdf`, `/Volumes/share/Files/ab12_x.pdf`, `/Volumes/share/docs/a.xlsx`, `C:\Users\bob\AppData\Local\AA\files\ab12_x.pdf`, `C:\Users\bob\AppData\Local\AA\files\zz_missing.pdf`, `D:\Projects\Files\ab12_x.pdf`, `\\srv\share\docs\a.xlsx`, `C:/docs/a.xlsx`, `C:foo.pdf`, `files\ab12_x.pdf`, `..\files\ab12_x.pdf`; each × {plain, `IsLink`, `LinkInPlace`} | `NormalizeFilePaths`, `MigrateLegacyAbsolutePaths`, `ResolveFilePath`, `IsUnderAppFolder` per row; plus `ClassifyFile` on `X.PDF`, `a.heic`, `b.webm`, `c.csv`, `noext`, `a.tar.gz`, `.hidden`, `file.`, `dir.d/file`, `x.JPEG ` and `ImportFile` on `Pump manual.pdf` (→ `files/%%GUIDN:1%%_Pump manual.pdf`) and (unix only) `a:b?.pdf` | §3.5–3.8, §7.6; Mac expectation = **unix** output for POSIX-form inputs, **windows** output for Windows-form inputs; `a:b?.pdf` divergent (§6.6 sanitising) |
| **A26** | `{"LastModified":"2026-09-29T11:15:29.9876543+03:00"}`, `{}`, `{"LastModified":null}`, `"garbage"` value, number value, `"lastModified"` key, nested `Ui.LastModified`, `[]`, `not json`; the first also as a file with BOM | `ReadLastModified` / `PeekFileLastModified` → DateTime-read shape or null | §3.9 |

#### GF.5.b `settings.json` (DATA-316) — one process per case

Out for every case: the final file bytes (`S<nn>.settings.golden.json`, `bytes-masked`) and the state dump after
the listed calls (`S<nn>.state.golden.json`, GF.4.7).

| Case | Precondition file | Calls | Settles |
|---|---|---|---|
| **S01** | none | `LoadSettings(); SetAppIdentity("Vessel-Alpha")` | §3.1, emission order §4.3 |
| **S02** | none | every setter once, in this order: `SetCurrentDataFile(%%DATADIR%%/data.json)`, `SavePasswordSettings(V/LC…Kgk=, AAECAwQFBgcICQoLDA0ODw==)`, `SetGoogleDriveFolder("/Users/u/My Drive")`, `SetSyncOnSave(true)`, `SetTextOnlyExport(true)`, `SetDarkMode(true)`, `SetEncryptLocalData(false)`, `SetGeminiApiKey("  key-123  ")`, `SetAppIdentity(" Vessel-Alpha ")`, `SetFolderBuilderBase("/tmp/fb")`, `SetSharedSaveFile("/Volumes/share/aa-shared.zip")` | §3.11, DATA-151 (trimming) |
| **S03** | `{"Foo":1,"DarkMode":true,"Nested":{"a":[1,"é"],"b":1.50},"CurrentDataFile":"C:\\x\\data.json","SharedSaveFile":"\\\\srv\\share\\aa-shared.zip"}` | `LoadSettings()` (dump) → `SetSyncOnSave(true)` | unknown-key preservation, raw numbers, Windows paths on the Mac (§4.3, §6.8) |
| **S04** | S02 result | `SetSharedSaveFile(null)`, `SetGeminiApiKey(null)`, `SetGeminiApiKey("  ")`, `SetFolderBuilderBase("")`, `SetGoogleDriveFolder("")` — file after each | D-7 (Gemini not cleared) |
| **S05** | S02 result with `"PasswordSalt":"%%%"` | `LoadSettings()` (catch branch) → `SetDarkMode(false)` | §3.1 catch; merge keeps `"%%%"` |
| **S06** | literal `null` | `LoadSettings()` → `SetDarkMode(true)` | §3.1 |
| **S07** | S02 result with UTF-8 BOM | `LoadSettings()` | BOM tolerance |
| **S08** | S02 result with a `// comment` and a trailing comma | `LoadSettings()` → `SetDarkMode(true)` | parse failure makes the merge lose every key (feeds D-16) |
| **S09** | `{"DarkMode":"true","Foo":1}` | `LoadSettings()` → `SetSyncOnSave(true)` | type mismatch → catch → keys lost |
| **S10** | S02 result | `LoadSettings()`; delete the file; `LoadSettings()` (dump: `GeminiApiKey` still in memory); `SetDarkMode(true)` | §3.1 missing-file branch quirk (re-persists the key) |
| **S11** | none | `SavePasswordSettings(hash, salt)` for `correct horse`/S; `LoadSettings()`; `PasswordService.Verify` for `correct horse`, `x`, `redemption` | DATA-084, K02 |
| **S12** | a file with iOS-style foreign keys `{"iOSOnlyPref":{"x":[true,null]},"LastSyncDevice":"iPhone","DarkMode":false}` | `LoadSettings()` → `SetAppIdentity("Mac-Test")` | Flash Sync merge survival |

#### GF.5.c Bundles (DATA-317)

Local attachment states used below: **L0** = empty `files/`; **L1** = `files/{a.pdf (10 B "0123456789"), b.pdf (5 B "abcde")}`.
Unless stated, `data.json` in the data folder = A02 bytes and `AppIdentity` = `Vessel-Alpha`.

**Writer cases** — Op `ExportFolderToZip(out)` → `B<nn>.bundle.zip`, `B<nn>.zip-manifest.golden.json`, payloads;
`source.json` payload `bytes-masked` (`Machine` → `%%MACHINE%%`, `WrittenUtc` → `%%NOWUTC%%`).

| Case | Setup | Expected highlights |
|---|---|---|
| **B01** | `files/` = `0123456789abcdef0123456789abcdef_Manual v2.pdf` (10 B), `fedcba9876543210fedcba9876543210_Wärtsilä manual.pdf` (NFC, 5 B), `empty.txt` (0 B), `sub/x.txt` (3 B); `TextOnlyExport` off | entries `data.json`, `source.json`, the four files (`files/sub/x.txt` recursive); `utf8NameFlag` only on the Wärtsilä entry; `DataOnly:false` |
| **B02** | same, `SetTextOnlyExport(true)` then `ExportFolderToZip(path)` | no `files/` entries at all; `DataOnly:true` |
| **B03** | empty `files/` | a directory entry `files/` |
| **B04** | `SetCurrentDataFile` → external `/tmp/aa-winfixtures/<run>/ext-B04/aa-data.json` (A01 bytes + a stamp) | `data.json` payload = external content; `source.LastModified` from it |
| **B05a/b** | active file missing but default present / both missing | fallback content / no `data.json` entry and no `LastModified` key |
| **B06a/b** | destination `%%DATADIR%%/x.zip` / sibling `%%DATADIR%%2/x.zip` | `IOException` `"Choose a destination outside the AA data folder."` for both (D-13) |
| **B07** | `BundleSource{Identity "Vessel-Alpha", Machine "BRIDGE-PC", WrittenUtc 2026-09-29T08:15:30.1234567Z, LastModified 2026-09-29T11:15:29.9876543 Local, DataOnly false}` | `Serialize(…, Opts)` bytes = §4.4 literal |
| **B08** | variants: `LastModified` null; `Identity ""`; `WrittenUtc` default | `LastModified` omitted; `"Identity":""`; `"WrittenUtc":"0001-01-01T00:00:00"` and `WrittenLocal == ""` |

**Reader fixtures** — committed ZIPs built by the generator with `ZipArchive`/raw writers (byte-level choices noted):

| Id | Content |
|---|---|
| R01 | `data.json` (A01) only |
| R02 | `data.json`, `source.json {DataOnly:true}`, `files/a.pdf` (10 B) |
| R03 | `data.json`, `source.json {DataOnly:false}`, directory entry `files/` only |
| R04 | `data.json`, `files/a.pdf` (10 B), `files/b.pdf` (5 B), no `source.json` |
| R05 | as R04 with `files/A.PDF` |
| R06 | as R04 with `a.pdf` 11 B |
| R07 | `data.json`, `files/a.pdf` (10 B) |
| R08 | `AA/data.json` only |
| R09 | `data.json`, `../evil.txt` |
| R10 | R04 written through a non-seekable stream (data descriptors, bit 3) with `files/b.pdf` **Stored** |
| R11 | `data.json` and `source.json` each with a UTF-8 BOM |
| R12 | `data.json` = `{"Tasks":[` (invalid) + `files/c.pdf` |
| R13 | `source.json` = `{bad` + `files/a.pdf` |
| R14 | `DATA.JSON` (upper case) only |
| R15 | `data.json` + an absolute entry `/etc/evil` + a backslash entry `files\a.pdf` |
| R16 | iOS-shaped `AA-backup-iOS-dataonly-20260929-1015.aaz`: `data.json` with `"SchemaVersion":3` and an unknown top-level key; `source.json {"Identity":"iPhone","Machine":"iPhone","WrittenUtc":"…Z","DataOnly":true,"App":"AA iOS","Build":"42"}`; no `files/` (synthetic — see GF.10 Q-7) |
| R17 | `files/Wärtsilä.pdf` stored twice in two ZIPs: UTF-8 name with bit 11, and CP437 bytes without bit 11 |

**Import matrix M** (`M.matrix.golden.json`; one process per cell): for every B and R bundle × operation
{`ImportBundleSmart`, `ImportSharedBundle`} × local state {L0, L1} → `{result: "DataOnly"|"WithAttachments"|null,
exception, filesAfter:[{name,size}], dataJsonAfter: <bytes-masked file ref or "unchanged">, settingsAfter: <file ref>,
currentDataFile, localModifiedBeforeThrow: bool}`. Must reproduce §7.7 (e.g. R05 + L1 → `DataOnly`; R07 + L1 →
`WithAttachments` with `b.pdf` deleted; R03 + L1 → both deleted; R01 + L1 → nothing deleted; R12 → exception
**after** `c.pdf` was copied and orphans swept = D-3 evidence; R09 → `IOException`, local untouched). R14/R15/R17
are `record-only` (filesystem- and platform-dependent) and also run on Windows.

**Peek matrix P**: every bundle → `PeekZipLastModified`, `PeekBundleSource` (serialised with `Opts`),
`PeekBundleIdentity`, `PeekZipData` (serialised with `Opts`, or null).

**Truth tables T** (reflection, synthetic staging folders): `IsDataOnlyBundle` for the six rows of §7.7 plus
"`source.json` = `null` literal" and "`DataOnly:"true"` (string)"; `AttachmentsMatch` for: equal sets; case-only
differences (`A.PDF`/`a.pdf`, `Straße.pdf`/`STRASSE.pdf`); size difference; extra local file; extra bundle file;
missing bundle directory; missing local directory; files in sub-folders (ignored).

**C01 `ApplySyncedData`**: input = A02 with three extra file items: `C:\Users\bob\AppData\Local\AA\files\ab12_x.pdf`,
`/Users/bob/AA/files/ab12_x.pdf`, and a `LinkInPlace` `\\srv\share\x.pdf` → returned model bytes, the data-file
bytes, `settings.json` bytes. (`platform: unix` and `windows`; Windows-form rows differ by platform, A25 rule.)

#### GF.5.d Crypto (DATA-318)

| Case | Input | Out |
|---|---|---|
| **K01** | passwords `correct horse`, `redemption`, `pässwörd` (NFC), `pa\u0308sswo\u0308rd` (NFD), `test1234`, `""`, `😀 emoji`, `a`×1000, `  padded  `; salts S = `00…0F`, S2 = first 16 bytes of SHA-256(`"AA-fixture-salt"`); dkLen 32 and 64; iterations 100 000; plus the RFC-style `password`/`salt`/c=1 primitive | hex + Base64 of each derivation; assertion that the first 32 bytes of the 64-byte output equal the 32-byte output; NFC ≠ NFD (the Mac MUST NOT normalise passwords) |
| **K02** | `PasswordService` states: none; `LoadFrom(hash(correct horse,S), S)`; `LoadFrom("", "")`; `LoadFrom(hash, null)`; `LoadFrom(null, S)`; `LoadFrom(hash, "%%%")` | `HasPassword`, `Verify` for `correct horse`, `Correct horse`, `correct horse `, `""`, `redemption`, `Redemption`; `Unlock`/`IsUnlocked`; the `FormatException` of the last state |
| **K03** | fixed-IV reference blobs: `RefEncrypt(pw, salt, iv, plaintextBytes)` (generator's own implementation of §4.7 on .NET primitives) for (`correct horse`, S, IV `10…1F`) × plaintexts {BOM+`""`, BOM+`<Section>hi</Section>`, `""` without BOM, `<Section>hi</Section>` without BOM, BOM+12 bytes (15 total), BOM+13 bytes (16 total → a full padding block), BOM+14 bytes}, and (`test1234`, S, IV `10…1F`, BOM + the 05 §7.6 XAML) | each blob; each validated by the **real** `PasswordService.Decrypt` after `LoadFrom`+`Unlock`; `selfcheck` vs 01 §7.2 and 05 §7.6 |
| **K04** | real `PasswordService.Encrypt` (random IV) for `""`, `<Section>hi</Section>`, a 1 KB XAML with `😀`, a 15-byte string, a 16-byte string | blobs (decrypt-only vectors) + **IV-extraction equivalence**: `RefEncrypt(pw, S, iv_from_blob, EF BB BF ‖ UTF-8(text)) == blob` — proves the Windows plaintext is BOM-prefixed |
| **K05** | negatives on a K03 blob: flip byte 0 (IV), 16 (CT), last (tag); truncate to 63 decoded bytes; Base64 with embedded `\r\n` and spaces; missing `=` padding; URL-safe alphabet; `"enc:"`; wrong password; master password; not unlocked; salt null | `Decrypt` result (expected null except the whitespace variant, which .NET's `FromBase64String` accepts) |
| **K06** | `RefEncrypt` plaintexts `FF FE 41 00`, `FE FF 00 41`, `FF FE 00 00 41 00 00 00`, `EF BB BF EF BB BF 41`, `C3 28` | real `Decrypt` output (StreamReader BOM sniffing: expected `A`, `A`, `A`, `\uFEFFA`, `\uFFFD(`) |
| **K07** | `IsEncrypted` on null, `""`, `enc:`, `enc:x`, `ENC:x`, ` enc:x`, `enc`, `<Section` | bools |
| **K08** | `ItemLockService.Verify` on {LockHash V/LC…, LockSalt S} × the K02 inputs; on an unlocked item × `redemption`, `x`, `""`; `LockSalt "not base64!"`; `LockHash` only; `LockHash ""` | bools, `IsLockProtected` |
| **K09** | `Protect(item, "correct horse", "  hint  ")`; `Protect(item, "pw", "   ")`; `Protect(item, "", null)`; `TryUnlock`/`IsGated`/`Relock`/`RemoveProtection` sequence | item JSON via `Opts` with `%%HASH32%%`/`%%SALT16%%`; `LockHint` omitted when blank; `ArgumentException "Password required."`; gate booleans |
| **K10** | the S11 file | cross-reference only |

#### GF.5.e Services (DATA-319)

Inputs are committed as AA-format JSON (`inputs/E<nn>.input.json`, loaded by the Swift codec, so family (a) must
pass first) plus inline parameters. Outputs follow GF.4.7.

**E01 DataDiff** (`Compare(current, incoming)`):

| Sub | Input | Purpose |
|---|---|---|
| E01.1 | the §7.8 example | selfcheck |
| E01.2 | identical databases | `HasChanges:false` |
| E01.3 | changes only in crew, saved lists, ports, Ui, Log, Trash, tags, relations, locks | DATA-103 scope (`HasChanges:false`) |
| E01.4 | name / description (45 chars → snip) / notes changes; notes bodies containing `&amp;`, `&nbsp;`, `&#x2192;`, U+000B, U+0085, U+2028 | `PlainText` + `Snip`, .NET `\s` class |
| E01.5 | bodies differing only in formatting attributes | no `notes:` node |
| E01.6 | files added/removed by `Name\|Path`; same name, different path | add + remove pair |
| E01.7 | two files with the same `Name\|Path` in one container | `ArgumentException` (D-10), recorded |
| E01.8 | Deadline Unspecified vs Local, same wall clock; RangeStart added; Recurrence 0→3; Status 1→3 | tick equality; enum names |
| E01.9 | subtasks three levels deep: added (with files and grandchildren), removed, changed | recursion |
| E01.10 | components added/removed/changed (name, notes line, notes body, files); linked procedure/task added/removed incl. an unknown id | `(unknown)` |
| E01.11 | steps: title, `done: False → True`, notes, files, linked task/equipment | .NET bool capitalisation |
| E01.12 | the same id as a Task in current and a Vessel in incoming | only hierarchy fields; root uses the incoming kind |
| E01.13 | duplicate ids inside one collection | last value, first position |
| E01.14 | `ProcedureIds` `[G5,G3,G4]` vs `[G4]`; `[G4]` vs `[G5,G3,G4]` | `HashSet` enumeration order (expected insertion order) |
| E01.15 | three Added roots with identical text `[Task] Same`, input order X,Y,Z; twenty roots with pairwise ties | `List.Sort` tie order (3-element network; introsort path) — `should` |
| E01.16 | roots named `_pump`, `apple`, `Äpfel`, `zebra`, `Straße`, `STRASSE`, `ǅ`, `ǆ`, `İ`, `i`, `ı`, `I`, `k`, `K` (U+212A) | `OrdinalIgnoreCase` ordering |
| E01.17 | Added items of each kind with full content | `ContentChildren` listing order |
| E01.18 | a linked id renamed in incoming | names map: incoming wins |
| E01.19 | `Snip` at exactly 40, 41, and an emoji straddling position 40 | UTF-16 cut (Mac `should` avoid splitting — divergent `should`) |

**E02 Search** (`SearchService.Search(data, query, max, locked)`): the 02 §7.7 corpus and table (`FUEL`, `engine`,
`ME` with Main Engine locked, `"   "`, 501 matching items → 500 hits); the five `MakeSnippet` rows via reflection;
`File › Document` / `File › Document › Path` labels; subtask walk three levels; query with surrounding spaces
(trimmed); `a+b` (literal, no regex); casing probes: query `STRASSE` vs text `Straße`, `K` (U+212A) vs `k`,
`İ` vs `i`, `σ` vs `ς`, `ǅ` vs `ǆ`, `é` vs `e\u0301`.

**E03 plain-text extractors**: `SearchService.PlainTextFromXaml` and `DataDiff.PlainText` side by side on: every 02 §7.7
row; `<Section NS><Paragraph><Run> </Run></Paragraph></Section>` **without** `xml:space` (whitespace-only node →
`Whitespace`, expected skipped); CDATA; a comment; a processing instruction; a DOCTYPE (prohibited → fallback);
`&nbsp;` (undefined in XML → fallback, raw entity kept) vs `&#160;`; `<Run Text="x" />`; nested `Span`/`Hyperlink`;
a table; a list; the S-1 sample.

**E04 Reminders** (`ReminderService.Compute(repo, today)` + `Headline()`): the 02 §7.8 data set (today
2026-09-29) plus: a Utc deadline `2026-09-29T23:30:00Z` (`.Date` without conversion → due today in every zone); a
deadline with a time of day; the week boundary (10-06 counted, 10-07 not); a completed parent with an incomplete
subtask; a Done procedure with an open step; all-zero → `Nothing due.`; week-only → `1 due this week`.

**E05 WorkRange.Coerce**: starts {nil, 10-01, 10-05, 10-09, 10-05 13:45 Local} × deadlines {nil, 10-05, 10-05 08:00
Local} × `editedStart` {true, false} → `(start, deadline)` with ticks **and kind**.

**E06 BatchDone**: 02 T-DONE-1…9 plus `#literal:x` and `null` in the selection.

**E07 BatchDeadline**: 02 T-DL-1…8 plus Local vs Unspecified equality.

**E08 BatchDelete** (`Describe`, `TrashAll`, `RemoveAll`): selections (a) E1 + T1 + P1 + V1 of KS; (b) T1 and its
subtask T1a both selected (T1a dropped); (c) duplicates; (d) `#row:` wrappers; (e) a locked item (`Protect`, no
unlock) → `Locked`, skipped by `TrashAll`; (f) items referenced elsewhere → `LinkedFromElsewhere`; (g) a C#-built
cyclic subtask graph (cycle guard; `record-only`); `KindBreakdown` for counts 0/1/2 of each kind; after
`TrashAll`: AppData bytes (shared `BatchId` → one `%%NEWGUID:n%%`, `DeletedUtc`/`TimestampUtc` → `%%NOWUTC%%`).

**E09 DateResolver**: every row of 09 §7.2, §7.3, §7.4 (`dependsOnToday` where the role matters); `FromExcelSerial`
for 0, 0.5, 1, 1.999, 59, 60, 61, 45000.75, 46096, 73051, 73052, -1, NaN, +∞ × `use1904` {false, true};
`IsPlaceholder` on the placeholder and zero-date lists in mixed case; `ExpandYear` table via reflection.

**E10 `CrewMember.ParseDate`** (6 TZs, `unix`): every row of 09 §7.1 plus `3/4/49`, `3/4/50`, `1/2/99`,
`2026-03-15T23:30:00Z`, `2026-03-15T23:30:00+14:00` (zone conversion can move the day), `Mar 15, 2026 10:00 PM`,
`15.03.2026`, `20260315` → `{value (ticks, kind) | null}`; also `DaysUntilSignOff`/`ContractStatusOn` for the
09 §7.8 rows with injected today.

**E11 CrewConverter**: every 09 §7.6 row as a `CompasRow` (header → value, keys normalised with `CrewText.Norm`,
committed as `inputs/E11.rows.json`), under `LearnDateFormat` evidence sets {DayFirst proof, MonthFirst proof,
Conflicted, none + fallback Unknown, none + fallback DayFirst}; `_importedAt` pinned; SourceFile
`compas-fixture.xlsx` → per member `Serialize(member, Opts)` (`Id` → `%%NEWGUID:n%%`), `DateSummary()`,
`UnreadableDates`, `OrderDependentDates`, `DateOrder`, `DateEvidence`.

**E12 SavedListOrder**: 02 §7.9 T-ORD-1…16 → return value + flat order + per-group subsequences; `GroupEntries`,
`AllEntries` lists (group name or null, template name).

**E13 `ChecklistExporter.ExportXlsx`** (compare `zip-manifest-ordered`; part bytes exact against the **unix** run,
which uses LF everywhere — the Swift writer emits `\n`, 09 §7.13 / 11 §4.5):

| Sub | Procedure | Notes |
|---|---|---|
| X1 | `Pump & Valve <weekly>` with 3 steps: done/undone; Deadline Unspecified / Local with time / none; TaskIds with a top-level task, a **subtask** id (not found by `FindById` → dropped) and a dangling id; EquipmentIds; titles with `& < > "` | the normal path |
| X2 | no steps | header row only |
| X3 | name of 40 × `a`; name 29 × `a` + `&b` | truncation after escaping → broken entity (Windows defect; Mac divergent per 11 §7.14) |
| X4 | blank name; a title containing U+000B | sheet `Checklist`; the control character is **not** dropped by `ChecklistExporter.Esc` → invalid XML recorded (Mac divergent: drops it) |

**E14 `XlsxWriter.Write`**: headers `["Rank","Name","Sign-off"]`; rows short, long, with a null cell, with
`a\u0001b` and `x\ty`; sheet names `""`, `Crew & Co`, 40 characters → parts (09 §7.13).

**E15 Casing probes**: `Port.Key` (`UnLocode` `İSTANBUL`, `ΣΊΣΥΦΟΣ`, `ǅ`, `K` U+212A, `ẞ`), `PortCall.Key`,
`PortVisit.VisitKey`, `CrewMember.Key` (`EmployeeId " "`, `|` trimming), `ClassifyFile(".PDF"/".JPEG")`,
`ResolveFilePath("HTTPS://x")`/`("MAILTO:a@b")`, CrewConverter code upper-casing via Rank/Gender/Nationality
cells `ß`, `ı`, `ǆ`, `ﬁ`, `mast`, and `AttachmentsMatch` keys `Straße.pdf`/`STRASSE.pdf`. Expected (the fixture
settles): .NET invariant casing uses **simple** mappings and keeps `İ`/`ı` unchanged, so Swift's
`lowercased()`/`uppercased()` (full mappings, final sigma) are **not** acceptable substitutes (GF.8.4).

**E16 Model computed strings & helpers**: `WhenText`, `HasRange`, `RangeFirst`, `CoversDay` (02 T-RNG-8/9, 01 §7.10);
`ShipJob.DaysUntilDue`; every Display string of §3.22 (`TrashedItem.DeletedLocal/Display`, `LogEntry.TimeUtc/
TimeLocal` and `BundleSource.WrittenLocal` in each TZ); `SireState.GetStatus` on `"InProgress"`, `"2"`, `"checked"`,
`"Bogus"`, `CountByStatus`, both toggles; `QuestionNumberComparer` order of `1.10`, `1.2`, `1.1.1`, `11.1`, `2`,
`a.1`, `1..2`; culture probe (`record-only`): `WhenText` and `DataDiff.Fmt` under `th-TH` (Buddhist calendar).

#### GF.5.f Extension families (DATA-320, SHOULD)

| Case | Linked code | Content |
|---|---|---|
| X01 | `AppRepository` | trash/undo/prune/recurrence/log/groups/relations: 01 §7.11 and 02 §7.1, §7.4, §7.5, §7.12, §7.13 (clone ids masked; undated recurrence `dependsOnToday`) |
| X02 | `ChecklistTemplateService` | 02 §7.10 |
| X03 | `ScheduleService.ExportJson/ImportJson` | 06 §7.11; **windows run too** (indented output uses `Environment.NewLine` → CRLF on Windows) |
| X04 | `SireExport` | 12 §7.10 (compare `text-lf`) |
| X05 | `TaskIdentifierService`, `TagExtractor` | 12 §7.3, §7.4, §7.5 on the real bank file |
| X06 | `CompasReader` (ClosedXML) | 09 §7.7 on synthetic workbooks generated with ClosedXML |
| X07 | Flash Sync | **not duplicated**: `Tests/FlashSync.Interop` already produces the protocol vectors (13 §7) |

### GF.6 Part 2 — WPF-only and Windows-only items

#### GF.6.1 Inventory (why each cannot be generated off Windows)

| Id | Item | Why Windows is required |
|---|---|---|
| W01 | root attribute set of `TextRange.Save` (S-1) | WPF serializer (`PresentationFramework`) |
| W02 | Insert-table XAML: `Table.Columns`, `BorderThickness` form (S-4) | same |
| W03 | Hyperlink default style written or not (S-5) | theme style + serializer |
| W04 | `Typography.Variants` from ToggleSubscript/ToggleSuperscript (S-9) | `EditingCommands` |
| W05 | empty document forms (S-10) | serializer |
| W06 | built-in key map (CONT-030) | `TextEditor` class input bindings |
| W07 | Bold/Italic/Underline toggle semantics; Strike reference comparison | `EditingCommands`, `TextDecorationCollection` identity |
| W08 | ToggleBullets/ToggleNumbering/Increase-/DecreaseIndentation/Enter/Tab in lists | `EditingCommands` |
| W09 | `ListFormatting.Build/Normalise` outputs (S-2/S-3) | `ListFormatting.cs` is WPF code |
| W10 | undo after a programmatic `TextRange.Load` (CONT-011, D-2) | `RichTextBox` undo manager |
| W11 | RTF → XAML (TextRange.Load(Rtf) and clipboard paste) | WPF RTF converter; inputs from Word/Excel/Outlook |
| W12 | `HtmlToXamlConverter.Convert` raw output and the pasted result | converter references `System.Windows.Media.Colors` |
| W13 | combined decorations; brush with opacity (property elements) | serializer |
| W14 | embedded `InlineUIContainer`/`BlockUIContainer` placeholder | serializer |
| W15 | contextual properties on load/paste of a foreign-root section | serializer |
| W16 | SIRE `BuildQuestionXaml`/`BuildOverviewXaml` and an edited `QuestionBodies` entry (12 Q-1) | `SireFlow.cs` is WPF code |
| W17 | lock sentinel `Background="#FFFFE699"` round-trip | serializer |
| W18 | Clear-formatting output (`Foreground` reset to `EditorFg`) | `ApplyPropertyValue` |
| W19 | real `AAENC1` data file and `AADPAPI1` token file (detection samples) | DPAPI |
| W20 | XLSX exported by the **shipped** `AA.exe` (newline bytes of the real product) | the published exe |
| W21 | an Explorer-made ZIP bundle ("Send to → Compressed folder") | Windows shell |
| W22 | Windows run of WinFixtures (`platform: windows` cases, neutrality check) | Windows `Path`, NTFS, `Environment.NewLine` |
| W23 | WPF loads every Mac XAML output (reverse) | WPF |
| W24 | typed-text captures in the real app (xml:lang stamping by input language, real dialogs) | keyboard, `InputLanguageManager` |
| W25 | (optional) `MainWindow.AgeVerdict` and the `DiffWindow` summary line | logic lives in WPF files |

#### GF.6.2 Capture machine and checkout

1. Windows 11 x64 with the .NET 10 SDK (same major as `AA.csproj`), Git for Windows, PowerShell 7; Microsoft Word,
   Excel, Outlook (for W11 inputs) and Edge (for W12 inputs). Record `winver`, display scale, system theme.
2. **LF checkout** so the linked sources hash-match and raw string literals keep LF:
   `git -c core.autocrlf=false clone <repo> C:\src\AA`, then `git -C C:\src\AA checkout mac-port`.
3. `dotnet run --project mac\Tools\WinFixtures -c Release -- verify-sources` must pass.
4. Use a scratch data folder for everything that launches AA: `$env:AA_DATA_DIR = 'C:\aa-capture'` (never the
   operator's real `%LOCALAPPDATA%\AA`; DATA-314).
5. Nothing outside `mac/` may be created in the committed tree: the tools build into `mac\Tools\*\bin|obj`
   (gitignored). If W25 is done, build `AA.csproj` with `dotnet build AA\AA.csproj -c Release --artifacts-path
   mac\Tools\WinCapture\.aa-build` so no `AA\bin` / `AA\obj` appears; `git status --porcelain -- AA Tests` must be
   empty before committing.

#### GF.6.3 `mac/Tools/WinCapture/WinCapture.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <!-- WinCapture: Part 2 capture harness (Windows only). Runs WPF's own serializer and editing commands on
       RichTextBoxes configured exactly like AA's ContainerEditor, and links the WPF-bound AA files that produce
       stored XAML. Dev-only; never shipped. -->
  <PropertyGroup>
    <OutputType>Exe</OutputType>            <!-- console subsystem (stdout + exit code), still a WPF app -->
    <TargetFramework>net10.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AASrc>$(MSBuildThisFileDirectory)..\..\..\AA\</AASrc>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="$(AASrc)Services\ListFormatting.cs"      Link="Linked\ListFormatting.cs" />
    <Compile Include="$(AASrc)Services\HtmlToXamlConverter.cs" Link="Linked\HtmlToXamlConverter.cs" />
    <Compile Include="$(AASrc)Sire\SireFlow.cs"                Link="Linked\SireFlow.cs" />
    <Compile Include="$(AASrc)Sire\SireModels.cs"              Link="Linked\SireModels.cs" />
    <Compile Include="$(AASrc)Sire\TagExtractor.cs"            Link="Linked\TagExtractor.cs" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="HtmlAgilityPack" Version="1.11.61" />
  </ItemGroup>
</Project>
```

#### GF.6.4 The snippet — `mac/Tools/WinCapture/Program.cs` (harness + W01–W06; the other cases follow GF.6.5)

```csharp
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

internal static class Program
{
    static string Out = "";
    static readonly JsonSerializerOptions Meta = new() { WriteIndented = true, NewLine = "\n" };

    // WinCapture all <outDir> [culture] | dump-clipboard <name> <inputsDir> | load-check <macXamlDir> <outDir>
    [STAThread]
    static int Main(string[] args)
    {
        var culture = new CultureInfo(args.Length > 2 && args[0] == "all" ? args[2] : "en-US");
        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.DefaultThreadCurrentUICulture = culture;
        CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = culture;
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        int rc = 0;
        app.Startup += (_, _) =>
        {
            try
            {
                rc = args[0] switch
                {
                    "all"            => All(Out = Directory.CreateDirectory(args[1]).FullName),
                    "dump-clipboard" => DumpClipboard(args[1], Directory.CreateDirectory(args[2]).FullName),
                    "load-check"     => LoadCheck(args[1], Directory.CreateDirectory(args[2]).FullName),
                    _ => 2
                };
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); rc = 1; }
            finally { app.Shutdown(); }
        };
        app.Run();
        return rc;
    }

    static int All(string outDir)
    {
        W01(); W02(); W03(); W04(); W05(); W06();
        // W07–W18 per the GF.6.5 table, one static method each, same helpers.
        File.WriteAllText(Path.Combine(outDir, "MANIFEST.json"), JsonSerializer.Serialize(Env(), Meta));
        return 0;
    }

    // ---- the editor, configured exactly like ContainerEditor.xaml:59-63 + App.xaml:37-40 -------------------
    static RichTextBox NewEditor()
    {
        var ink = new SolidColorBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A));          // EditorFg
        var rtb = new RichTextBox
        {
            AcceptsTab = true, BorderThickness = new Thickness(0), Padding = new Thickness(8),
            Background = new SolidColorBrush(Color.FromArgb(0xFF, 0xFC, 0xFC, 0xFC)),     // EditorBg
            Foreground = ink, CaretBrush = ink,
            FontFamily = new FontFamily("Consolas"), FontSize = 14,                       // MainFont, 14
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        SpellCheck.SetIsEnabled(rtb, true);
        // Hosted in a real, shown, off-screen window so templates and the TextEditor attach as in the app.
        new Window { Content = rtb, Width = 800, Height = 600, Left = -20000, Top = -20000,
                     WindowStyle = WindowStyle.None, ShowInTaskbar = false, ShowActivated = false }.Show();
        rtb.UpdateLayout();
        return rtb;
    }
    static void Done(RichTextBox rtb) => Window.GetWindow(rtb)?.Close();

    static string Save(FlowDocument d)                                   // ContainerEditor.PersistRichText :461-464
    {
        var range = new TextRange(d.ContentStart, d.ContentEnd);
        using var ms = new MemoryStream();
        range.Save(ms, DataFormats.Xaml);
        return Encoding.UTF8.GetString(ms.ToArray());
    }
    static string Save(RichTextBox rtb) => Save(rtb.Document);

    static void Load(RichTextBox rtb, string xaml)                       // ContainerEditor.Load :425-429
    {
        using var ms = new MemoryStream(Encoding.UTF8.GetBytes(xaml));
        new TextRange(rtb.Document.ContentStart, rtb.Document.ContentEnd).Load(ms, DataFormats.Xaml);
    }

    // Programmatic typing: replace the collapsed selection and collapse after it (what TextEditor does for typed
    // text, minus input-language stamping, which M-06 captures by hand).
    static void Type(RichTextBox rtb, string text)
    {
        rtb.Selection.Text = text;
        rtb.Selection.Select(rtb.Selection.End, rtb.Selection.End);
    }
    static TextRange Find(FlowDocument d, string needle)                 // needle must lie inside one Run
    {
        for (var p = d.ContentStart; p != null; p = p.GetNextContextPosition(LogicalDirection.Forward))
            if (p.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text)
            {
                int i = p.GetTextInRun(LogicalDirection.Forward).IndexOf(needle, StringComparison.Ordinal);
                if (i >= 0) { var s = p.GetPositionAtOffset(i)!; return new TextRange(s, s.GetPositionAtOffset(needle.Length)!); }
            }
        throw new InvalidOperationException("not found: " + needle);
    }
    static void Select(RichTextBox rtb, string needle) { var r = Find(rtb.Document, needle); rtb.Selection.Select(r.Start, r.End); }

    static void Emit(string id, string xaml, string what)
    {
        File.WriteAllBytes(Path.Combine(Out, id + ".xaml"), new UTF8Encoding(false).GetBytes(xaml));
        File.WriteAllText(Path.Combine(Out, id + ".json-string.txt"), JsonSerializer.Serialize(xaml)); // as inside data.json
        File.WriteAllText(Path.Combine(Out, id + ".meta.json"),
            JsonSerializer.Serialize(new { id, what, culture = CultureInfo.CurrentCulture.Name }, Meta));
    }

    // ---- W01: root attribute set + S-1 body built through the toolbar code paths ----------------------------
    static void W01()
    {
        var p = NewEditor(); Emit("W01a-pristine", Save(p), "new editor, never touched"); Done(p);
        var rtb = NewEditor();
        Type(rtb, "Check the main engine oil level.");
        EditingCommands.EnterParagraphBreak.Execute(null, rtb);
        Type(rtb, "Urgent");
        Select(rtb, "main engine"); EditingCommands.ToggleBold.Execute(null, rtb);                    // Bold_Click :588
        Select(rtb, "Urgent");
        EditingCommands.AlignCenter.Execute(null, rtb);                                               // :616
        rtb.Selection.ApplyPropertyValue(TextElement.ForegroundProperty,
            new SolidColorBrush(Color.FromArgb(255, 255, 0, 0)));                                     // Color_Click :597-605
        rtb.Selection.ApplyPropertyValue(TextElement.BackgroundProperty,
            new SolidColorBrush(Color.FromArgb(255, 255, 255, 0)));                                   // Highlight_Click :606-614
        EditingCommands.ToggleUnderline.Execute(null, rtb);                                           // :590
        var x = Save(rtb); Emit("W01b-S1-typed", x, "S-1 through toolbar paths"); Done(rtb);
        var again = NewEditor(); Load(again, x); Emit("W01c-S1-load-save", Save(again), "load(W01b) then save"); Done(again);
    }

    // ---- W02: verbatim body of ContainerEditor.InsertTable_Click :727-768 (dialog → literal value) ------------
    static readonly Brush TableBorder = new SolidColorBrush(Color.FromRgb(0x9A, 0xA0, 0xA6));       // :725
    static void InsertTable(RichTextBox Rtb, string value)
    {
        var m = Regex.Match(value ?? "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
        int rows = m.Success ? Math.Clamp(int.Parse(m.Groups[1].Value), 1, 50) : 3;
        int cols = m.Success ? Math.Clamp(int.Parse(m.Groups[2].Value), 1, 20) : 3;
        var table = new Table { CellSpacing = 0, Margin = new Thickness(0, 4, 0, 4) };
        for (int c = 0; c < cols; c++) table.Columns.Add(new TableColumn());
        var rg = new TableRowGroup();
        for (int r = 0; r < rows; r++)
        {
            var tr = new TableRow();
            for (int c = 0; c < cols; c++)
            {
                var cell = new TableCell(new Paragraph(new Run("")))
                    { BorderBrush = TableBorder, BorderThickness = new Thickness(0.6), Padding = new Thickness(3, 1, 3, 1) };
                if (r == 0) cell.FontWeight = FontWeights.Bold;
                tr.Cells.Add(cell);
            }
            rg.Rows.Add(tr);
        }
        table.RowGroups.Add(rg);
        var caretBlock = Rtb.CaretPosition?.Paragraph as Block;
        if (caretBlock != null && ReferenceEquals(caretBlock.Parent, Rtb.Document)) Rtb.Document.Blocks.InsertAfter(caretBlock, table);
        else Rtb.Document.Blocks.Add(table);
        Rtb.CaretPosition = table.RowGroups[0].Rows[0].Cells[0].ContentStart;
    }
    static void W02()
    {
        foreach (var (id, size, prep) in new (string, string, Action<RichTextBox>)[] {
            ("W02a-2x2-after-para", "2x2",   r => Type(r, "Before table")),
            ("W02b-3x4",            "3x4",   r => Type(r, "x")),
            ("W02c-junk-3x3",       "junk",  r => Type(r, "x")),
            ("W02d-0x0-clamped",    "0x0",   r => Type(r, "x")),
            ("W02e-60x30-clamped",  "60x30", r => Type(r, "x")),
            ("W02f-empty-doc",      "2x2",   r => r.Document.Blocks.Clear()) })
        {
            var rtb = NewEditor(); prep(rtb); InsertTable(rtb, size); Emit(id, Save(rtb), "InsertTable " + size); Done(rtb);
        }
    }

    // ---- W03: verbatim body of InsertLink_Click :704-723 (RequestNavigate handler omitted: never serialized) --
    static void InsertLink(RichTextBox Rtb, string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return;
        if (Rtb.Selection.IsEmpty) Rtb.CaretPosition.Paragraph?.Inlines.Add(new Hyperlink(new Run(uri.ToString())) { NavigateUri = uri });
        else _ = new Hyperlink(Rtb.Selection.Start, Rtb.Selection.End) { NavigateUri = uri };
    }
    static void W03()
    {
        var a = NewEditor(); Type(a, "See "); InsertLink(a, "https://www.imo.org"); Emit("W03a-empty-selection", Save(a), "append to caret paragraph"); Done(a);
        var b = NewEditor(); Type(b, "Read the IMO page"); Select(b, "IMO"); InsertLink(b, "https://www.imo.org"); Emit("W03b-wrap-selection", Save(b), "wrap"); Done(b);
        var c = NewEditor(); Type(c, "x "); InsertLink(c, "https://example.com/a b/ü?q=1&r=2"); Emit("W03c-escaping", Save(c), "space, non-ASCII, &"); Done(c);
        var d = NewEditor(); Type(d, "Mail "); InsertLink(d, "mailto:ops@ship.test"); Emit("W03d-mailto", Save(d), "mailto"); Done(d);
    }

    // ---- W04: Ctrl+= / Ctrl+Shift+= commands ----------------------------------------------------------------
    static void W04()
    {
        var a = NewEditor(); Type(a, "H2O and m2");
        var h2o = Find(a.Document, "H2O"); a.Selection.Select(h2o.Start.GetPositionAtOffset(1)!, h2o.Start.GetPositionAtOffset(2)!);
        EditingCommands.ToggleSubscript.Execute(null, a); Emit("W04a-subscript", Save(a), "ToggleSubscript on 2 of H2O");
        EditingCommands.ToggleSubscript.Execute(null, a); Emit("W04b-subscript-off", Save(a), "toggled back");
        var m2 = Find(a.Document, "m2"); a.Selection.Select(m2.Start.GetPositionAtOffset(1)!, m2.End);
        EditingCommands.ToggleSuperscript.Execute(null, a); Emit("W04c-superscript", Save(a), "ToggleSuperscript on 2 of m2"); Done(a);
    }

    // ---- W05: every way a note becomes empty ------------------------------------------------------------------
    static void W05()
    {
        var a = NewEditor(); Type(a, "x"); a.SelectAll(); EditingCommands.Delete.Execute(null, a);
        Emit("W05a-typed-then-deleted", Save(a), "type x, select all, Delete"); Done(a);
        var b = NewEditor(); Load(b, File.ReadAllText(Path.Combine(Out, "W01b-S1-typed.xaml"))); b.SelectAll();
        EditingCommands.Delete.Execute(null, b); Emit("W05b-rich-then-deleted", Save(b), "S-1 then delete all"); Done(b);
        var c = NewEditor(); c.Document.Blocks.Clear();
        Emit("W05c-blocks-cleared", Save(c), "ContainerEditor.Load with empty body (:439-442), then a save"); Done(c);
    }

    // ---- W06: the built-in key map, read from WPF's class input bindings (WPF-internal field; read-only) -----
    static void W06()
    {
        Done(NewEditor());   // RichTextBox static ctor has registered TextEditor's class bindings
        var rows = new List<object>();
        var f = typeof(CommandManager).GetField("_classInputBindings", BindingFlags.NonPublic | BindingFlags.Static);
        if (f?.GetValue(null) is System.Collections.IDictionary map)
            foreach (var t in new[] { typeof(RichTextBox), typeof(System.Windows.Controls.Primitives.TextBoxBase), typeof(Control), typeof(UIElement) })
                if (map[t] is InputBindingCollection ibc)
                    foreach (InputBinding ib in ibc)
                        if (ib.Gesture is KeyGesture kg)
                            rows.Add(new { owner = t.Name, command = (ib.Command as RoutedCommand)?.Name,
                                           key = kg.Key.ToString(), modifiers = kg.Modifiers.ToString(),
                                           display = kg.GetDisplayStringForCulture(CultureInfo.InvariantCulture) });
        foreach (var cmd in new[] { ApplicationCommands.Undo, ApplicationCommands.Redo, ApplicationCommands.Cut,
                                    ApplicationCommands.Copy, ApplicationCommands.Paste, ApplicationCommands.SelectAll })
            foreach (InputGesture g in cmd.InputGestures)
                if (g is KeyGesture kg) rows.Add(new { owner = "ApplicationCommands", command = cmd.Name,
                                                       key = kg.Key.ToString(), modifiers = kg.Modifiers.ToString(), display = kg.DisplayString });
        File.WriteAllText(Path.Combine(Out, "W06-gestures.json"), JsonSerializer.Serialize(rows, Meta));
        // If the field is absent in the installed WPF, rows is empty: run the manual M-09 keyboard check instead.
    }

    // ---- clipboard capture (GF.6.6) and reverse load-check (W23) ---------------------------------------------
    static int DumpClipboard(string name, string dir)
    {
        var d = Clipboard.GetDataObject();
        File.WriteAllText(Path.Combine(dir, name + ".formats.json"), JsonSerializer.Serialize(d.GetFormats(false), Meta));
        foreach (var (fmt, ext) in new[] { (DataFormats.Rtf, "rtf"), (DataFormats.Html, "html"), (DataFormats.UnicodeText, "txt"), (DataFormats.Xaml, "xaml") })
            if (d.GetDataPresent(fmt) && d.GetData(fmt) is string s)
                File.WriteAllBytes(Path.Combine(dir, $"{name}.{ext}"), new UTF8Encoding(false).GetBytes(s));
        return 0;
    }
    static int LoadCheck(string macDir, string outDir)
    {
        var results = new List<(string name, bool ok, string detail)>();
        foreach (var file in Directory.GetFiles(macDir, "*.xaml").OrderBy(x => x, StringComparer.Ordinal))
        {
            var name = Path.GetFileNameWithoutExtension(file);
            var rtb = NewEditor();
            try
            {
                Load(rtb, File.ReadAllText(file, new UTF8Encoding(false)));
                File.WriteAllBytes(Path.Combine(outDir, name + ".wpf-resaved.xaml"), new UTF8Encoding(false).GetBytes(Save(rtb)));
                results.Add((name, true, new TextRange(rtb.Document.ContentStart, rtb.Document.ContentEnd).Text));
            }
            catch (Exception ex) { results.Add((name, false, ex.GetType().FullName + ": " + ex.Message)); }
            finally { Done(rtb); }
        }
        File.WriteAllText(Path.Combine(outDir, "load-check.json"),
            JsonSerializer.Serialize(results.Select(r => new { r.name, r.ok, r.detail }), Meta));
        return results.All(r => r.ok) ? 0 : 1;
    }

    static object Env() => new
    {
        os = Environment.OSVersion.VersionString,
        dotnet = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
        presentationFramework = FileVersionInfo.GetVersionInfo(typeof(FrameworkElement).Assembly.Location).FileVersion,
        culture = CultureInfo.CurrentCulture.Name,
        inputLanguage = InputLanguageManager.Current.CurrentInputLanguage?.Name,
        consolasInstalled = Fonts.SystemFontFamilies.Any(f => f.Source == "Consolas"),
        capturedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
    };
}
```

#### GF.6.5 Remaining automated recipes (W07–W18) — one static method each, same helpers

| Id | Steps (exact API sequence) | Outputs |
|---|---|---|
| W07 | (a) `Type "normal"`, select all, `ToggleBold`; (b) `ToggleBold` again; (c) `"one two"` with only `two` bold, select all, `ToggleBold`; (d) `FontWeights.SemiBold` via `ApplyPropertyValue`, `ToggleBold`; (e) `ToggleItalic` on a mixed selection; (f) underline + strike (`ApplyPropertyValue(TextDecorations, [Underline, Strikethrough])`), `ToggleUnderline`; (g) Strike_Click replica (`ContainerEditor.cs:591-596`, verbatim) on a typed strike, on a strike **loaded from XAML** `<Run TextDecorations="Strikethrough">x</Run>`, and on underline-only text | one XAML per step; the Strike cases settle 05:566 |
| W08 | three paragraphs `A`,`B`,`C`: select all → `ToggleBullets`; again (un-toggle); `ToggleNumbering` on bullets; caret in `B` → `IncreaseIndentation`, `DecreaseIndentation`; caret at end of `C` → `EnterParagraphBreak`; again on the new empty item; caret at start of `B` → `TabForward`, `TabBackward`; a plain paragraph → `IncreaseIndentation` (WPF TextIndent) — each **before** and **after** `ListFormatting.Normalise(rtb.Document)` (linked) | CONT-040/041/043/044 |
| W09 | `ListFormatting.Build(["Check oil  (60 min)", "Log"], numbered: true)` and `(…, false)` inserted into an empty editor; a W08 nested list normalised | S-2, S-3 |
| W10 | editor: `Load(xamlA)`; `Load(xamlB)` (as `ContainerEditor.Load` does, no clear); record `CanUndo`; `Undo()`; save | CONT-011, D-2 |
| W11 | for every `inputs/R-*.rtf`: (i) fresh `FlowDocument` + `TextRange.Load(stream, DataFormats.Rtf)` → save; (ii) `Type "Before "`, `DataObject.AddPastingHandler(rtb, OnRtbPastingReplica)` (verbatim `ContainerEditor.OnRtbPasting :354-383`), `Clipboard.SetDataObject(new DataObject(DataFormats.Rtf, rtf))`, `rtb.Paste()`, `Type " After"` → save | RTF shapes (RTF wins over HTML in AA's rule) |
| W12 | for every HTML input (05 §7.1 strings, verbatim, and `inputs/H-*.html` browser captures): `HtmlToXamlConverter.Convert(html)` → `W12-<n>.converter.xaml`; then the paste replay with a `DataObject` carrying only `Html` + `UnicodeText` → `W12-<n>.pasted.xaml` | 05 §7.1 exact output, K-12, K-13, S-7 |
| W13 | `ApplyPropertyValue(TextDecorations, new TextDecorationCollection { Underline[0], Strikethrough[0] })`; a `SolidColorBrush` with `Opacity 0.5` as Foreground; `TextDecorations.OverLine`; `BaselineAlignment.Superscript` | attribute vs property-element forms |
| W14 | `InlineUIContainer(new Image { Source = 1×1 PNG })` inside a paragraph; `BlockUIContainer(new Button { Content = "x" })` | placeholder form (CONT-038) |
| W15 | editor: `Load` the S-8-like Segoe section; save; and paste (clipboard `Xaml`) a Segoe-rooted section into a Consolas document | 05 §4.3.1 contextual properties |
| W16 | bank = `AA\Sire\Data\sire2_question_bank.json` deserialised as `QuestionBank`, each question enriched with `TagExtractor.ExtractTags` / `ExtractRoviqLocations` (the `SireBank.EnsureLoaded :49-61` steps); `SireFlow.ToContainerXaml(SireFlow.BuildQuestion(q))` for `1.1.1`, `2.1.1`, `11.1.2` (= `SireToAa.BuildQuestionXaml`, `SireToAa.cs:158`); `SireFlow.ToContainerXaml(SireFlow.BuildOverview("SIRE Section 7.1", qs))` with `qs` = section `7.1` ordered by `QuestionNumberComparer` (`SireToAa.cs:41-42, 161`); edited body: a RichTextBox configured like `SirePage.xaml:169-174` (`Segoe UI`, 13, `Normal`, `EditorBg/EditorFg`, padding 12) with `Document = SireFlow.BuildQuestion(q, Brushes.Black)`, caret at the end of the first heading, `EnterParagraphBreak`, `ToggleBold`, `Type "note"`, then the `SirePage.FlushBody :258-261` save | 12 Q-1 |
| W17 | `ApplyPropertyValue(Background, #FFFFE699)` on a word; save; load+save twice | 05 §4.4 stability |
| W18 | Clear-formatting replica (`ContainerEditor.cs:693-703`, `EditorFg` = `#FF1A1A1A`) on bold red highlighted underlined text | CONT-028 |
| — | run `all` twice more with cultures `el-GR` and `th-TH`; the harness compares all XAML outputs with the en-US run and writes `culture-invariance.json` | serializer invariance |

#### GF.6.6 Clipboard inputs (W11/W12) — recipes, captured once and committed

Procedure per recipe: build the content in the named program, select it, `Ctrl+C`, then immediately run
`dotnet run --project mac\Tools\WinCapture -c Release -- dump-clipboard <id> mac\Tests\Fixtures\xaml\wpf-capture\inputs`.

| Id | Program | Content |
|---|---|---|
| R-1 | Word | `Plain bold italic underline` with each word styled accordingly |
| R-2 | Word | bulleted list of 3 items, item 2 with one nested item |
| R-3 | Word | numbered list with a nested lettered level |
| R-4 | Word | 2×2 table, bold shaded header row |
| R-5 | Excel | range A1:C3, bold header row, one cell with a number format `0.00` |
| R-6 | Word | hyperlink `IMO` → `https://www.imo.org` |
| R-7 | Word | one word underlined **and** struck through; yellow highlight; red text; 11.5 pt |
| R-8 | Word | a small inline picture between two words |
| R-9 | Outlook | two lines separated by Shift+Enter, a tab, a signature line |
| R-10 | Word | `H2O` with subscript 2, `m2` with superscript 2 |
| R-11 | Notepad | plain text only (baseline) |
| H-1 | Edge | a paragraph with `<b>`, `<i>`, `<a>` |
| H-2 | Edge | a nested `<ul>` |
| H-3 | Edge | a `<table>` with `colspan` |
| H-4 | Edge | a selection spanning `<script>`/`<style>` |
| H-5 | Edge | text with CSS `color: rgba(0,0,0,0)` (K-13) |
| H-6 | Edge | an `<hr>` between paragraphs (S-7) |
| H-7 | Edge | nested `div > p` with whitespace between blocks (K-12) |

The `.html` file keeps the raw CF_HTML string (`Version:0.9 StartHTML:…` header included), exactly what
`OnRtbPasting` hands to the converter.

#### GF.6.7 Manual confirmations in the real `AA.exe` (DATA-323)

From a PowerShell 7 window: `$env:AA_DATA_DIR = 'C:\aa-capture'`, remove that folder if it exists, then launch the
built or published `AA.exe` from the same window (sign in as usual, DATA-002). For each step create a new Task named
after the capture id, act, press `Ctrl+S`, and continue. Afterwards close AA and extract:

```powershell
$d = Get-Content 'C:\aa-capture\data.json' -Raw | ConvertFrom-Json
$dir = 'C:\src\AA\mac\Tests\Fixtures\xaml\wpf-capture\manual'; New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($t in $d.Tasks) {
  [IO.File]::WriteAllText("$dir\$($t.Name).xaml", $t.Container.RichTextXaml, [Text.UTF8Encoding]::new($false)) }
Copy-Item 'C:\aa-capture\data.json' "$dir\M-capture.data-json.golden.json"    # synthetic content only (DATA-314)
```

| Id | Actions in the task's note |
|---|---|
| M-01 | type `Check the `, `Ctrl+B`, `main engine`, `Ctrl+B`, ` oil level.`, Enter, `Urgent`; select `Urgent`; `Ctrl+E`; toolbar Text color → red; Highlight → yellow; `Ctrl+U` |
| M-02 | toolbar ▦ Insert table → `2x2` → OK |
| M-03 | type `See `, toolbar 🔗 → `https://www.imo.org` → OK |
| M-04 | type `H2O`, select `2`, `Ctrl+=` |
| M-05 | type `x`, `Ctrl+A`, Delete, wait 1 s |
| M-06 | switch input language to Greek (Win+Space), type `Γειά σου`; switch back, type ` ok` |
| M-07 | a Procedure with two steps (one done, one with a deadline) → export the checklist as XLSX → save `manual\M-07.checklist.xlsx` (W20) |
| M-08 | (optional, W25) import a modified copy of the data → copy the change-preview header/summary text by hand into `manual\M-08.diffwindow.txt` |
| M-09 | only if W06 produced no rows: in a note, try each shortcut of CONT-030 and write the observed effect into `manual\M-09.keys.md` |

#### GF.6.8 Windows run of WinFixtures and other Windows-only artefacts (W19–W22)

* `dotnet run --project mac\Tools\WinFixtures -c Release -- generate --platform windows --out mac\Tests\Fixtures\winfixtures`
  produces `windows/` outputs for all `platform: windows` cases (A20, A25, C01, M-matrix rows R14/R15/R17, X03) and
  the neutrality cross-check.
* **W19 DPAPI samples** (same run, Windows only): A20w = `DataStore.SetEncryptLocalData(true)` then
  `DataStore.Save(KS)` → commit the resulting file as `windows/json/A20w.aaenc1-sample.golden.bin` (the Mac only
  detects the magic and must refuse it); the same file bundled with `ExportFolderToZip` → its `data.json` entry must
  be plaintext; `"AADPAPI1"` + `Dpapi.Protect(UTF8("{\"access_token\":\"fixture\"}"))` →
  `windows/json/W19.aadpapi1-sample.golden.bin`.
* **W20** is M-07 (the shipped build's XLSX; compared `text-lf` part by part with E13).
* **W21 Explorer ZIP**: in a scratch folder put a copy of A02 as `data.json` and `files\Wärtsilä manual.pdf`
  (5 bytes); select **both** items (not the folder), right-click → Send to → Compressed (zipped) folder; commit as
  `windows/bundles/R20.explorer.bundle.zip`; the M matrix gains row R20 on the next `generate`.
* **W22** is the neutrality cross-check itself.

#### GF.6.9 Reverse check (W23)

After the Swift emitter has written `mac/Tests/Fixtures/mac-out/xaml/*.xaml` (GF.8.5) and it is committed:
`dotnet run --project mac\Tools\WinCapture -c Release -- load-check mac\Tests\Fixtures\mac-out\xaml mac\Tests\Fixtures\xaml\mac-roundtrip`.
Every file must load (`load-check.json` all `ok:true`, exit 0); `*.wpf-resaved.xaml` are then compared on the Mac
with `xml-canonical` against the Mac input (differences are recorded, not failures, except lost text or lost lock
sentinels, which fail).

#### GF.6.10 Commit, and how the results feed back

* Commit only paths under `mac/` on the `mac-port` branch (the pre-commit hook rejects anything else). Commit
  message: `Capture WPF fixtures (<winver>, WPF <PresentationFramework version>)`.
* After W01: the canonical root start tag the Mac writes for a **new** document (05 §4.3.7 rule 2) becomes the
  W01b root start tag **byte-for-byte**. After W05: 05 §9 Q6 is decided by evidence (keep `""` for a Mac empty note
  only if W05 shows WPF loads `""` and saves an equivalent). After W06: the CONT-030 table is replaced by the dump.
  The owners of specs 03, 05 and 12 append errata that quote the captured files; this addendum does not edit them.

### GF.7 Dependencies

| Direction | Item |
|---|---|
| Linked read-only C# | GF.3.1 list (Part 1); `ListFormatting.cs`, `HtmlToXamlConverter.cs`, `Sire/SireFlow.cs`, `Sire/SireModels.cs`, `Sire/TagExtractor.cs` (Part 2) |
| Packages | `ClosedXML 0.104.2`, `PDFsharp-MigraDoc 6.2.0` (Part 1); `HtmlAgilityPack 1.11.61` (Part 2) — the versions of `AA.csproj` |
| Toolchain | .NET 10 SDK (macOS: `brew install --cask dotnet-sdk`, or the official `dotnet-install.sh --channel 10.0 --install-dir mac/Tools/.dotnet`, gitignored); Swift 6.4 / Xcode 27 for the consumers |
| Consumers | every AACore component with a golden: JSON codec, `NetDateTime`, models, `DataStore`, `SettingsStore`, `BundleService`, ZIP reader/writer, `PasswordService`, `ItemLockService`, `DataDiff`, search, reminders, batch services, `DateResolver`, `CrewConverter`, `SavedListOrder`, XLSX writer, XAML converter (specs 01, 02, 05, 06, 09, 11, 12) |
| Windows-only APIs used (Part 2 / Windows run only) | WPF (`PresentationFramework`, `PresentationCore`, `WindowsBase`): `RichTextBox`, `TextRange.Save/Load` (`DataFormats.Xaml`, `DataFormats.Rtf`), `EditingCommands`, `ApplicationCommands`, `CommandManager` (reflection on `_classInputBindings`), `DataObject.AddPastingHandler`, `Clipboard` (OLE), `InputLanguageManager`, `Fonts`; `crypt32!CryptProtectData` via `Dpapi.cs`; Explorer "Send to"; `System.IO.Path` Windows semantics; NTFS name rules |
| Not used by any tool | networking, Google APIs, OpenCV, DirectShow, the user's real data |

### GF.8 macOS adaptation notes — the Swift side

#### GF.8.1 `FixtureIndex`
Locates `mac/Tests/Fixtures/` from `#filePath` (no SwiftPM resource copying), decodes `MANIFEST.json` into
`FixtureCase` values (`Decodable`, `Sendable`, `CustomTestStringConvertible` = the case id), and exposes
`cases(family:)`. `FixtureIndex.available` is false when the manifest is absent: suites are then disabled
(`.enabled(if:)`) **unless** `AA_REQUIRE_FIXTURES=1` (CI/release), which turns absence into a failure.

#### GF.8.2 `GoldenMatcher`
Splits a golden on `%%…%%` tokens, escapes the literal parts, builds one anchored regex with a capture per token
(GF.4.5), matches the actual bytes, then enforces the equality constraints (same `n` ⇒ same text, different `n` ⇒
different text, `NEWGUID:n`/`GUIDN:n` share one value). `%%DATADIR%%` is substituted literally (raw and JSON-escaped
forms) before matching. On mismatch it reports the first differing byte offset with 80 bytes of context on both
sides and attaches both files to the test (`Attachment.record`).

#### GF.8.3 Injection points the goldens require from AACore
* codec and model loaders take a `TimeZone` (default `.current`) — tests pass `TimeZone(identifier: case.tz)!`;
* services with a notion of today take `today: LocalDate` — tests pass the case's value or `MANIFEST.today`;
* `DataStore`/`SettingsStore`/`BundleService` take the app-folder URL and a machine-name provider;
* `PasswordService.encrypt` has an internal overload taking the IV (K03), never used by the app;
* the XLSX and ZIP writers expose the entry list for manifest comparison.

#### GF.8.4 .NET-emulation helpers the goldens will validate (each gets its own unit test file)

| Helper | Validated by | Rule |
|---|---|---|
| `NetDateTime` (ticks + kind + ambiguous-DST bit if A12/A13 show it matters) | A12–A14, E10 | §4.1.5 |
| `STJWriter` (escaping, number text, property order) | A01–A11, A15 | §4.1.2–4.1.7 |
| `DotNetCasing.lowerInvariant/upperInvariant` | E15 | simple per-scalar mapping; `İ`/`ı` unchanged (expected; confirmed by E15) |
| `DotNetOrdinalIgnoreCase` compare/equals/indexOf | E01.16, E02, T | upper-case each UTF-16 unit/scalar with the simple mapping, compare code units |
| `DotNetWhitespace` (`\s`, `char.IsWhiteSpace`, `Trim()`) | E01.4, E02, E03 | `[\f\n\r\t\v\x85\p{Z}]` — ICU's `\s` differs (no `\v`/`\x85`) |
| `WebUtilityHtmlDecode` | E01.4, E03 | the .NET entity table |
| `XmlReaderTextExtractor` | E03 | Text + SignificantWhitespace only; `Whitespace` skipped; DTD prohibited → fallback |
| `DotNetIntroSort` (optional) | E01.15 | only if tie order is required (`should`) |
| `DotNetDateTimeParseInvariant` subset | E10 | month-first, `TwoDigitYearMax` as E10 shows |
| `DotNetDouble` formatting | A15 | shortest round-trip, `E+XX` |
| `ZipManifest` builder | B, R, E13, E14 | GF.4.6 |

#### GF.8.5 `MacOutEmitter` (reverse direction, DATA-312)
A test enabled only with `AA_EMIT_MAC_OUT=1` writes: `json/` (the Swift writer's output for A02, A04, A05, A10 and
a Mac-created database containing Mac "now" stamps, a Mac-sanitised attachment name and a subtask chain at the
maximum allowed depth), `settings/` (+ `*.expect.json`), `crypto/` (lock hashes and an `enc:` blob with random
salt/IV, + plaintexts), `bundles/` (text-only and with attachments, including a name that needed sanitising),
`xaml/` (the Swift XAML writer's output for every W capture after a Mac round-trip, and for documents created on
the Mac: lists, tables, links, locks, sub/superscript, empty). The folder is committed so a Windows machine can run
`check-mac` and `load-check` without a Mac.

#### GF.8.6 Running it (Mac-native developer flow)
* `mac/Scripts/fixtures.sh generate` → `dotnet run --project mac/Tools/WinFixtures -c Release -- generate`;
  `verify` → `swift test --package-path mac --filter WinFixtures`; `emit-mac-out` →
  `AA_EMIT_MAC_OUT=1 swift test --package-path mac --filter MacOutEmitter`; `check-mac` → the reverse mode.
* CI (macOS runner): setup .NET 10 → `generate --verify-only` → `AA_REQUIRE_FIXTURES=1 swift test`. A Windows
  runner job (optional, GF.10 Q-3) runs `generate --platform windows --verify-only`, `check-mac --platform windows`,
  and the automated WinCapture cases except clipboard-dependent ones (W11 paste path, `dump-clipboard`).
* Tests are tagged `.winFixtures`; `should` cases additionally `.should` (reported, not release-blocking);
  `record-only` cases only attach diffs.

### GF.9 Verification of the plan itself — test vectors and acceptance gate (DATA-326)

**Harness self-tests (Swift):**
* `GoldenMatcher`: golden `{"Id":"%%NEWGUID:1%%","R":"%%NEWGUID:1%%"}` matches
  `{"Id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","R":"3f2504e0-4f89-11d3-9a0c-0305e82c3301"}` and rejects the same
  text with the second GUID different; `%%NEWGUID:1%%`/`%%NEWGUID:2%%` bound to equal values → reject; `%%NOWUTC%%`
  rejects `2026-09-29T08:15:30+00:00` (Local form); `%%DATADIR%%` with a data folder containing `\` matches its
  JSON-escaped form.
* `XMLCanonicalizer`: `<A b="1" a="2"/>` ≡ `<A a="2" b="1" />`; `<R> x</R>` ≢ `<R>x</R>` (whitespace significant).
* `ZipManifest`: a Swift-written ZIP of B01's content equals B01's manifest on all significant fields while its
  container bytes differ.

**Acceptance gate** — the verification markers of GF.1.1 are closed when all of these hold:
1. `verify-sources` passes; `MANIFEST.linkedSourcesCommit` = the pinned commit.
2. Two consecutive `generate` runs are byte-identical except `generatedAtUtc`.
3. Every GF.1.1 row points at a case present in a committed manifest (Part 1 and Part 2).
4. `specConflicts` is empty, or every entry names an appended erratum.
5. `platformDivergences` is empty, or every entry is explained by a re-classified case.
6. `AA_REQUIRE_FIXTURES=1 swift test` passes all `must` cases; `should` failures are listed in the release notes.
7. `check-mac` passes on macOS **and** Windows; `load-check` returns 0.
8. Every Mac `divergent` expectation cites the spec clause that mandates it.
9. No committed fixture contains real user data; no file outside `mac/` changed
   (`shasum -a 256 -c mac/Docs/original-source-checksums.sha256` passes).

### GF.10 Open questions

* **Q-1** Which .NET runtime patch is baked into the shipped self-contained `AA.exe`? STJ ships inside it, so goldens
  should be generated with that patch; record it on the capture machine at publish time (`dotnet --list-runtimes`)
  and pin `mac/Tools/global.json` accordingly.
* **Q-2** Is a Windows machine with Office available? Without Word/Excel/Outlook, W11 falls back to RTF produced by
  WordPad (removed from Windows 11 24H2) or LibreOffice (a different RTF dialect) — acceptable only as a stopgap.
* **Q-3** May a hosted Windows CI runner be used for W22/W23 and the non-clipboard WinCapture cases?
* **Q-4** Confirm that dev-only C# oracle projects under `mac/Tools/` are acceptable under Rule zero ("all Mac
  code, docs, tests, scripts and fixtures live under `mac/`"). The alternative — hand-written goldens — loses the
  oracle property and is not recommended.
* **Q-5** Should golden regeneration ever overwrite committed files automatically? Recommendation: never; CI only
  verifies, and a human reviews every regenerated diff.
* **Q-6** May the owner run the optional local-only round-trip on the real vessel `data.json` (DATA-314)? It
  commits nothing and reports offsets only.
* **Q-7** Can the iOS owner provide anonymised real iOS bundles (`-dataonly-` and full) and an iOS-written
  `data.json`, to replace the synthetic R16 and settle 01 Q-8 (the iOS `SchemaVersion`)?

---

## Addendum: Same-machine multi-process model (two AA processes on one AppFolder)

> **Gap-fill.** No section of this spec (nor of specs 02, 03, 13 or 14) says what happens when two AA processes
> use the same data folder. This addendum records what Windows does today (there is no guard) and specifies the
> Mac instance model. It extends §1.2 (a new launch step), §2 (a new feature group **O**, IDs **DATA-160 to
> DATA-186**), §3.27 (startup order on the Mac), §4.12 and §4.14 (new Mac-only files and rules), §6 (a new
> **§6.13**, given here as §MP.6), §7 (new vectors) and §8 (defects **D-18 to D-24**, questions **Q-9 to Q-12**).
> Subsections use the prefix **MP** (multi-process) so they never collide with the main numbering. Line numbers
> refer to commit `37cdab0`, as in §0.
>
> Sources read for this addendum: `App.xaml.cs` (all); `MainWindow.xaml.cs` :1-660, :900-1260, :1587-1640;
> `Services/DataStore.cs` (all); `Services/AppRepository.cs` :1-80, :250-320; `FlashSync/FlashSyncStore.cs` (all);
> `FlashSync/FlashQrDecoder.cs` :25-50; `Services/DpapiDataStore.cs` (all); `Services/GoogleDriveUploader.cs`
> :110-176; `PROGRESS.md` sections "Data-safety, reminders & housekeeping batch" (*Hardened atomic writes*),
> "Non-blocking autosave", "single shared save file (multi-instance auto-sync…)", "shared-save verified…"
> (`AA_DATA_DIR`), "Shared-save cadence…"; spec 02 REPO-005/006; spec 03 SHELL-008 and the quit notes; spec 13
> FLASH-020/021/100-107; spec 14 §6.3; this spec §B, §C, §E, §3.3, §3.11, §3.12, §6.

### MP.1 Overview

**Windows today.** `App.OnStartup` (`App.xaml.cs:14-44`) has no single-instance guard. There is no named
`Mutex`, `EventWaitHandle`, `Semaphore`, pipe, `Process.GetProcessesByName` check or lock file anywhere in the
code base. The only `FileShare.None` is on the temp file inside `AtomicWrite` (`DataStore.cs:446`). Starting
`AA.exe` twice gives two independent processes. Each goes through splash, login and `LoadDataAndInitUi`, and
each keeps its own `AppData` graph, `AppRepository` debounce and write chain, static `DataStore`,
`PasswordService` and `ItemLockService` state, and timers (5-minute autosave, shared-save 1-minute push and
60-second poll, 30-minute reminders, Drive check). Both resolve the same `AppFolder` (`%LOCALAPPDATA%\AA`, or
`AA_DATA_DIR`), so they read and write the same `data.json`, `settings.json`, `files/`, `qrsync-baseline.json`,
`google-token/`, `crash.log` and `qrmodels/`.

Nothing coordinates the two processes:

* **No local-file watcher.** A process never notices that another process rewrote `data.json` or
  `settings.json`. The only watcher in the app watches the *shared save bundle* (DATA-053). So the two processes
  reconcile only when a shared save file is configured, and then only through the bundle, at least a minute
  late, with last-writer-wins semantics (DATA-164).
* **Whole-file writes.** Every save serialises the *entire* in-memory model (`SerializeForSave`) and atomically
  replaces `data.json`. Atomic writes (DATA-029) mean a reader never sees a half-written file, but they do
  **not** stop lost updates. The last process to save wins. The other process's edits since *its* load disappear
  from disk with no message. They survive only in that process's memory until it saves again, and that save then
  silently drops the first process's edits in turn.
* The developer's notes only address half-written reads: "A second AA instance polling the shared file every 60s
  can no longer read a torn file" (PROGRESS, *Hardened atomic writes*). Everything else is accepted as
  "intentional last-writer-wins for genuinely concurrent edits" (PROGRESS, *single shared save file*). The
  intended way to run several copies is **separate data folders joined by the shared save file**. The developer
  tested it on one machine by running copies with different `AA_DATA_DIR` values (PROGRESS, *shared-save
  verified*).

**Mac decision.** Launch Services normally keeps one process per app: clicking the Dock icon, double-clicking in
Finder, `open AA.app` and opening a `.aaz` all go to the running copy. A second process on the same data folder
can still start:

* `open -n AA.app`;
* a second copy of `AA.app` at another path, such as a download in `~/Downloads` or a beta next to the release
  (Launch Services runs copies at different paths side by side, as it does for two Xcodes);
* running `AA.app/Contents/MacOS/AA` from Terminal;
* an Xcode debug run or `swift run` of a development build while the release app is open;
* a second macOS user (fast user switching) whose `AA_DATA_DIR` points at the same shared folder.

So the Mac port adds the following. Each is a deliberate **[MAC]** safety deviation, and none of them changes a
file format:

1. an **instance guard** that allows at most one *editing* AA process per data folder. It uses `flock(2)` on
   `AppFolder/.aa.lock` (DATA-170 to DATA-179). A second launch is offered **Switch to Running AA**, **Open
   Read-Only** or **Quit**;
2. a **read-only instance mode** that never writes into the data folder (DATA-174, DATA-175);
3. **detection of outside writes** to the active data file, for writers the lock cannot stop: AA on Windows
   through a Parallels shared folder or SMB, another computer, sync or backup tools, or a user restoring a backup
   by hand. Nothing is lost: whichever version the user doesn't choose is kept as a conflict copy (DATA-180,
   DATA-181);
4. **key-level merging** for `settings.json` writes (DATA-182);
5. a clear statement of what is and isn't protected when a data folder or shared bundle is also used by Windows
   AA (DATA-184, DATA-185, §MP.6.3), together with the supported setup: separate folders joined by a shared save
   file.

Different data folders are never blocked. Two AA processes with different `AA_DATA_DIR` values (the developer's
shared-save test setup) both edit, exactly as on Windows.

### MP.2 Feature checklist — group O

#### O.1 Windows behaviour (documented here; the Mac replaces it with O.2)

**DATA-160 — No instance guard (Windows).** Any number of AA processes can run on one `AppFolder`, and the user
is told nothing when a second one starts. Both show splash, login and the main window with the same data.

* **Per process (never shared):** the model graph; the dirty flag and 750 ms debounce; the in-memory
  `LastModified`; the ordered write chain (which orders writes only *within* one process); the `PasswordService`
  session password and loaded hash/salt; the `ItemLockService` set of unlocked ids; the `DataStore` statics
  (`CurrentDataFile`, `EncryptLocalData`, `SharedSaveFile`, `DarkMode`, `SyncOnSave`, `TextOnlyExport`,
  `AppIdentity`, `GoogleDriveFolder`, `FolderBuilderBase`, `GeminiApiKey`, `LastLoadFailed`,
  `LoadedNewerSchema`); the shared-save state (`lastSeen`, `lastSynced`, indicator flags); Drive's
  `_lastSeenRemote`; the reminder dedup key; the tray icon.
* **Shared on disk:** every file in §4.12.

**DATA-161 — `data.json`: the last writer wins, silently.** Each process writes its whole model on:

* every debounced autosave (750 ms after any edit);
* explicit Save;
* the 5-minute autosave, when dirty;
* before every export, shared push and Drive upload (`_repo.Save()`);
* **every close, unconditionally.** `OnClosing` calls `_repo.Save()` (`MainWindow.xaml.cs:163`), and `Save()`
  writes even when nothing is dirty (`AppRepository.cs:261`).

Consequences, all silent:

* *An idle copy overwrites on close.* Copy B is opened at 09:00 and left alone. The user works all day in copy A,
  and A's autosaves land. Closing B at 17:00 writes B's 09:00 model, stamped 17:00, over A's work. If A is then
  closed after B, A's close-save puts A's work back (and drops anything done in B). If A was closed before B, the
  day's work is gone from disk.
* *Interleaved edits.* Each 750 ms autosave from either copy reverts the other copy's saved edits on disk, so the
  file switches back and forth between the two models.
* *Startup housekeeping can write.* `PruneTrash`, `ReconcileRecurrences` and the daily digest
  (`Ui.LastDigestDate`, `MainWindow.xaml.cs:1624-1630`) mark the model dirty. So a freshly started, idle copy can
  write within a second of its main window appearing: when a Trash entry has expired, a recurrence spawns, or it
  is the first launch of the day. Its startup shared-save check can also pull.
* A reload in either copy (Revert, an import, a shared pull) picks up whatever the other copy last wrote.
* *Occasional save failures (Windows only).* The other process sometimes has `data.json` open for reading:
  `File.ReadAllBytes` at load, `PeekFileLastModified` during a bundle export, `ReadDataTree` in Flash Sync. These
  opens share Read only, so replacing the file fails at every step of the Move → Replace → Copy fallback chain
  with a sharing violation. The debounced save then restores the stamp and the dirty flag and tries again on the
  next edit or the 5-minute autosave; an explicit Save shows `"Save failed"`.
* *First-run race (Windows only).* On a first run both copies can race the no-overwrite `File.Move(tmp, path)`
  branch (`DataStore.cs:451-454`). The loser throws and retries later.

These last two failures are recorded for completeness **[FAITHFUL]**. The Mac cannot reproduce either, because
POSIX `rename` replaces a file even while it is open.

**DATA-162 — `settings.json`: each process rewrites all of it from its own memory.** `WriteSettings`
(`DataStore.cs:237-265`) re-reads the file, but only merges these from it:

* `PasswordHash` / `PasswordSalt` (when no new value is passed);
* `GoogleDriveFolder`, `FolderBuilderBase` and `GeminiApiKey` (each `?? existing`);
* unknown keys (`ExtraData`).

`CurrentDataFile`, `SyncOnSave`, `DarkMode`, `SharedSaveFile`, `EncryptLocalData`, `AppIdentity` and
`TextOnlyExport` are always written from the calling process's statics. So any setter in copy B reverts copy A's
earlier changes to those keys:

* A sets a shared save file, then B toggles Dark Mode. `SharedSaveFile` is removed from disk. A keeps syncing
  from memory, but after the next launch there is no shared file.
* A turns on local encryption and rewrites `data.json` as `AAENC1`. B's next autosave writes plaintext (B's
  `EncryptLocalData` is still false), and B's next setter saves `EncryptLocalData:false`. Encryption is silently
  off.
* A imports an external JSON (`CurrentDataFile = X`). B's next setter writes B's `CurrentDataFile`, so A's choice
  is lost at the next launch. Meanwhile B keeps saving its model to the default `data.json`.
* A changes the app password. The hash and salt reach disk and survive B's writes (they are merged), but B keeps
  checking passwords against the old hash until its next `LoadSettings` (reload, import or shared pull).

The write is a plain `File.WriteAllText`, not an atomic replace:

* If the other process runs `LoadSettings` at the same moment, it can read a half-written file. The parse fails
  and it falls back to all defaults: the session password is forgotten, and shared save stops at the next
  `StartSharedSaveSync`.
* If the other process runs `WriteSettings` at the same moment and can't parse `existing`, it gets
  `existing = null`. It then writes **no `PasswordHash`/`PasswordSalt`, `GoogleDriveFolder`,
  `FolderBuilderBase`, `GeminiApiKey` or unknown keys**, which erases the app password from disk. **[DEFECT D-18]**

**DATA-163 — `files/`: one copy's import deletes the other copy's new attachments.** Attachment copies get unique
names (`{Guid:N}_{name}`), so two processes never collide when adding. But a bundle import in one copy deletes
every top-level file in `files/` that the bundle does not contain (the orphan sweep). This happens on
`ImportSharedBundle`, and on `ImportBundleSmart` when attachments changed (`DataStore.cs:813-815`, `:870-871`).
It includes attachments the *other* copy has just added and referenced from its own model. That copy then shows
them as missing, and the imported copies are gone (the user's original stays wherever it came from). Drive "Load
backup", Drive sync pull and Import Bundle in one copy have the same effect.

**DATA-164 — Shared save is the only thing that reconciles the copies.** With no shared save file set, the two
copies never learn about each other. With one set, both copies read the same `SharedSaveFile` from
`settings.json`, and both run the full DATA-052 to DATA-058 machinery against the same bundle *and* the same
local folder:

1. Copy A pushes. The bundle is read back from the shared `data.json`, so it normally holds A's model, or B's if
   B saved in between.
2. Copy B's next check sees a newer bundle.
3. If B has no unsynced changes, B pulls it silently: it rewrites the shared local `data.json` and sweeps
   `files/`. Otherwise B shows the `"Shared save updated"` prompt.

The result is last-writer-wins ping-pong with about a minute of delay. It is an accident, not a design.

**DATA-165 — Flash Sync across processes.** `FlashSyncStore.ReadDataTree()` (`FlashSyncStore.cs:26`) builds the
outgoing payload from `DataStore.Load()`, i.e. from **disk**, not from the calling process's model. So copy B can
flash copy A's data. `Apply` (`:134-156`) writes `settings.json` (plain `File.WriteAllText`, `:162`), `data.json`
(via `ApplySyncedData`) and the baseline, and then only the applying copy reloads. From there:

1. The other copy's next autosave reverts the phone's changes on disk.
2. `qrsync-baseline.json` still records those changes as applied.
3. The next change set sent from the other copy therefore diffs an older model against that baseline, and
   **sends the phone deletions and reverts of its own changes**.

Separately, `WriteBaseline` uses one fixed temp name, `qrsync-baseline.json.tmp` (`:73`). Two copies writing at
once collide, the error is swallowed, and the baseline is not advanced, so the next send is a larger change set.
**[DEFECT D-20]**

**DATA-166 — Other shared files.**

* **`google-token/`:** `DpapiDataStore.StoreAsync` writes with a non-atomic `File.WriteAllBytes` (`:37`). A read
  at the same moment gets a half-written blob, so `GetAsync` returns "no token". The Google library can then
  start an interactive sign-in, opening a browser even during a background Drive check. Signing out in one copy
  (`Directory.Delete(google-token)`) leaves the other copy's in-memory credential working until its next refresh.
  **[DEFECT D-21]**
* **`google_client_secret.json`:** `File.Copy(…, overwrite: true)`; the last writer wins. Harmless.
* **`crash.log`:** two copies calling `File.AppendAllText` at once can hit a sharing violation. The exception ends
  `ReportCrash` **before** its message box (`App.xaml.cs:55-60`), so that crash is neither logged nor shown.
  **[DEFECT D-22]**
* **`qrmodels/`** (Windows Flash Sync decoder, `FlashQrDecoder.cs:35-50`): two copies opening Flash Sync together
  may both re-extract the models. The second `File.Create` fails, so that copy's camera decoder does not start.
* **Tray icons, reminder balloons and the daily digest** are per process. Two copies show two tray icons and
  duplicate notifications, and both show the digest if both loaded before either wrote `LastDigestDate`.
* **Drive sync-on-save:** both copies push `AA-sync.zip`, and each sees the other's push as "newer on Drive". The
  result is import prompts (DATA-100) bouncing back and forth through Drive.
* **`settings.json` written by Flash Sync** (`WriteSettingsTree`, `FlashSyncStore.cs:158-166`): a plain, non-atomic
  write, like DATA-162. **[DEFECT D-23]**

#### O.2 Mac instance model (normative)

**DATA-170 — One editing process per data folder.** The Mac app MUST let at most one process at a time *write*
into a given data folder. The guard is an exclusive advisory lock, `flock(fd, LOCK_EX | LOCK_NB)`, on the file
`AppFolder/.aa.lock`. The process that holds it is the **editor**. Every other AA process that resolves the same
folder is refused editing and gets the alert in DATA-172. Properties:

* **The lock follows the folder, not its path.** The lock file lives *inside* the folder, so all of these compete
  for the same file: a symlinked path, a trailing slash, different letter case (case-insensitive APFS), an
  `AA_DATA_DIR` that names the default folder, and a second macOS user pointing at the same folder.
* **Different data folders never compete.** Two processes with different `AA_DATA_DIR` values both become editors
  (as on Windows), so the shared-save test setup keeps working.
* **No stale lock can outlive its process.** The kernel releases the lock however the process ends: quit, crash,
  `SIGKILL`, Force Quit or power loss (DATA-176).
* **Only this one file is ever locked** — never `data.json`, `settings.json`, attachments or the shared bundle. On
  SMB a lock on a data file can turn into a server-enforced byte-range lock that makes Windows AA's reads fail,
  which would put Windows into safe mode.
* **The lock file is never deleted, renamed or replaced** — not by the editor on quit, not by cleanup, not by
  imports. Deleting a held lock file would let the next process create and lock a *new* file of the same name
  while the old editor is still running, giving two editors. If the dead legacy full-wipe import (DATA-047) is
  ever ported, it MUST skip `.aa.lock`.
* **Windows ignores it.** Windows AA never lists or reads the folder root. The file is not bundled (bundles hold
  only `data.json`, `source.json` and `files/`), is not sent by Flash Sync, and is not in `settings.json`.

**DATA-171 — When the guard runs.** The guard runs before anything can write into the data folder and before any
window appears, i.e. before the splash (DATA-001). Order:

1. resolve `AppFolder` (DATA-010) and create it;
2. install crash reporting (DATA-004);
3. acquire the guard;
4. run `LoadSettings` (read-only; it never writes) and apply the theme, so the alert matches the saved
   appearance.

The guard's result decides the rest of the launch:

* **editor:** splash → login → main window, as before;
* **blocked:** DATA-172 (no splash, no login yet);
* **unguarded** (the lock file can't be created, §MP.3.1): continue as the editor without a guard, logging the
  reason with `os.Logger` (subsystem `AA`, category `instance`). Real write failures still show up through the
  normal save errors.

**DATA-172 — Second-launch alert.** An application-modal `NSAlert` (there is no main window yet), with
`alertStyle = .warning` and the app icon.

* `messageText`: `"AA is already running with this data folder"`
* `informativeText`: `"Another copy of AA{holder} is using:\n\n{folder}\n\nOnly one copy of AA can edit a data folder at a time — two copies would overwrite each other's changes. {choice}"`
  * `{folder}` is the resolved `AppFolder`, with the home directory abbreviated
    (`~/Library/Application Support/AA`).
  * `{holder}` comes from the lock record (§MP.4.1); the first matching case applies:

    | Holder | `{holder}` |
    |---|---|
    | Same user, this Mac | `" (started {time}, process {Pid})"` |
    | Another user, this Mac | `" (running for the user “{User}” on this Mac)"` |
    | Another computer (lease mode) | `" on “{Host}” (last seen {time})"` |
    | Record unreadable | `""` |

    `{time}` is local `HH:mm`, or `yyyy-MM-dd HH:mm` when it isn't today.
  * `{choice}` is `"Switch to the copy that is already running, or open this one read-only to look without saving."`
    when button 1 below is offered, else `"You can open this one read-only to look without saving, or quit."`
  * In lease mode, when the holder's heartbeat is stale, this line is appended:
    `"\n\nThat copy hasn't updated its claim since {time}. If that computer crashed or was switched off, you can take over."`
* Buttons, in the order macOS lays them out (the first is the default, Return):
  1. `"Switch to Running AA"` — only when the holder is an app of **this** user on **this** Mac
     (`NSRunningApplication(processIdentifier:)` is non-nil). Runs DATA-173.
  2. `"Open Read-Only"` — runs DATA-174. This is the default when button 1 is not offered.
  3. `"Quit"` — `keyEquivalent = "\u{1b}"` (Esc); quits immediately.
  4. `"Take Over…"` — **lease mode only** (DATA-177), never when the lock is held on this Mac. It is the default
     when the holder's heartbeat is stale.
* While the alert is up, the guard retries `LOCK_EX|LOCK_NB` every **1 s** (a timer in the `.modalPanel` run-loop
  mode). If the lock comes free (the user quit or force-quit the other copy), the alert is closed in code
  (`NSApp.abortModal()`), this process becomes the editor, and launch continues with the splash. No extra
  message is shown.
* Quitting from this alert MUST skip the close sequence (DATA-028 / SHELL-056). No model was loaded and nothing
  may be written: `applicationShouldTerminate` returns `.terminateNow` while the launch phase is `.blocked`.

**DATA-173 — Switch to Running AA.** Steps, in order:

1. **Collect documents.** Take any documents this process was launched with (`.aaz`/`.zip` bundles, `.json`
   databases) from `application(_:open:)`. Launch Services delivers launch documents before
   `applicationDidFinishLaunching`, which is why the alert is shown from there.
2. **Tell the editor.** Post the distributed notification `com.bepavida.aa.InstanceRequest`:
   * `object` = the holder's pid as a decimal string;
   * `userInfo` = `{"Action": "activate" or "open", "URLs": [absolute paths], "AppFolder": "<canonical path>", "FromPid": <pid>}`;
   * `deliverImmediately: true`.
3. **Hand over focus.** `NSApp.yieldActivation(to: holder)`, then `holder.activate(from: .current, options: [])`
   (macOS 14 cooperative activation).
4. **Quit**, skipping the close sequence.

The editor listens for `com.bepavida.aa.InstanceRequest` with its own pid string as the `object`. On receipt it:

* ignores the request unless `AppFolder` matches its own canonical folder;
* calls `NSApp.activate()` and brings the main window to the front (or the login window, if it is still at the
  sign-in gate);
* for `"open"`, queues the URLs into the normal open-document path, to run once the main window is up: a bundle
  goes to Import with preview (DATA-043, §6.7), a JSON to Import Database (DATA-034).

If the notification can't carry `userInfo` (a sandboxed build), the second process only activates the holder. It
then shows the alert once more, with a single `"OK"` and this line appended: `"\n\nOpen the file from the running
AA (File ▸ Import Bundle…)."` Documents opened while only one AA is running never reach this path, because
Launch Services sends them straight to the running copy's `application(_:open:)`.

**DATA-174 — Read-only instance.** "Open Read-Only" continues the launch as normal (splash → login → main, all
faithful), but the process runs in **read-only instance mode**. It does not hold the lock, and it MUST NOT create,
change, rename or delete anything inside the data folder. The one exception is appending to `crash.log`. This is
safe mode (DATA-021) plus the rules below.

* **Saving.** The repository is created with `suspendSaving = true`, as in safe mode. The debounced autosave,
  explicit save, 5-minute save, close-save and the save-before-export all write nothing.
* **⌘S** shows a warning sheet titled `"Read-only — not saving"`, with the text: `"This copy of AA opened read-only because another copy is editing the same data folder. Nothing you change here is saved. Switch to the other copy to make changes."`
  Buttons: `"Switch to Other AA"` (when the holder is available) and `"OK"`.
* **Settings.** Setters (Dark Mode, Export Text Only, identity, Folder Builder base, …) take effect for this
  session only and never write `settings.json`. Their normal status text gets `" (this window only — read-only)"`
  appended, for example `"Dark mode on. (this window only — read-only)"`.
* **Disabled** (greyed-out menu items and toolbar buttons, with the tooltip/help text `"Not available in a read-only copy of AA."`):
  * Import Database (JSON)… and Import Bundle…;
  * Encrypt Local Data File;
  * Shared Save File ▸ Set… and Stop Using;
  * Set / Change App Password…, and per-item Lock / Change lock / Remove lock;
  * Trash ▸ Restore, Delete Permanently and Empty Trash;
  * undo of the last delete (⌘Z for deletions);
  * every Google Drive command that loads, signs in or uploads;
  * Flash Sync (both send and receive, since confirming a send writes the baseline);
  * adding attachments ("Import copy" and other add-file actions);
  * crew, Shippalm and ports imports;
  * any other command that writes into `AppFolder`.
* **Still available:**
  * browsing, search and the Quick switcher;
  * opening attachments and links;
  * Revert to Saved (it only reads);
  * exports that write **outside** the data folder: Save a Copy As JSON, PDF, Excel, text, and Export Bundle.
    Export Bundle packs the file on disk, i.e. the editor's latest save — not unsaved edits made in this window;
  * Lock Now and per-item unlock (both only change session memory).
* **Not started:** the shared-save timers, watcher and indicator (hidden); the 5-minute autosave and Drive
  newer-save check; startup housekeeping (Trash prune, recurrence reconcile, daily digest); reminder
  notifications and the menu-bar extra. The editor owns all of these, so nothing is duplicated.
* **Editing controls.** Item editors and the rich-text editor SHOULD be non-editable (`isEditable = false`,
  read-only fields), driven by one environment value, `writeGate == .readOnlyInstance`. Where a control can't
  honour it, edits stay in memory and are never saved (Windows safe-mode behaviour).
* **Window.** The main window's `subtitle` is `"Read-Only"`. A persistent banner under the toolbar (yellow
  material, SF Symbol `lock.fill`) says `"Read-only — another copy of AA is editing this data folder. Changes here are not saved."`,
  with buttons `"Switch to Other AA"` and, when available, `"Edit Here"` (DATA-175).
* **Live view.** The read-only instance watches `data.json` (a directory `DispatchSource` with a 1.5 s debounce,
  plus a 60 s poll). When the editor saves, it reloads silently (a repository swap, as in DATA-036). It keeps
  *its own* selection, tab, scroll positions and window frame — captured before the swap and re-applied after —
  instead of the file's `Ui`. Status: `"Updated from the other copy of AA (HH:mm:ss)."`

**DATA-175 — Becoming the editor.** While read-only, the process retries `LOCK_EX|LOCK_NB` every **5 s**. When it
gets the lock, it **keeps** it (so a third process can't take it), and the banner changes to
`"The other copy of AA has closed. You can edit here now."` with `"Edit Here"` (prominent) and `"Stay Read-Only"`
(which releases the lock again).

"Edit Here" does the following:

1. If this window has in-memory changes, confirm first:
   `"Discard the changes you made in this read-only window and start editing the saved data?"` with
   `"Discard and Edit"` / `"Cancel"`.
2. `LoadSettings()` and reload the data from disk (a repository swap). The read-only window's unsaved changes are
   discarded.
3. Leave read-only mode and write the lock record.
4. Start everything DATA-174 suppressed: shared-save sync (with `lastSeen = lastSynced = LastModified`), the
   5-minute timer, housekeeping and reminders.
5. Status: `"Now editing — {CurrentDataFile}"`.

**DATA-176 — Stale lock after a crash.** An `flock` lock dies with its process. So when an editor crashed, was
killed or was force-quit, the next launch takes over **silently**: `LOCK_EX|LOCK_NB` succeeds, the new editor
overwrites the record (§MP.4.1) and launch continues with no message. The old record is for information only; a
record naming a dead pid is never a reason to refuse. Temp files left over from the crash are cleaned up by
DATA-178.

**DATA-177 — Lease mode (a data folder on a network or non-locking volume).** Lease mode applies when:

* `statfs(AppFolder)` reports a non-local volume (`f_flags` lacks `MNT_LOCAL`: `smbfs`, `nfs`, `afpfs`,
  `webdav`, …); or
* `flock` fails with `ENOTSUP`/`EOPNOTSUPP`.

On such volumes `flock` may only work locally, or not at all, so it isn't trusted on its own. The editor also
keeps a **lease** in the same record: `"LockKind":"lease"`, with `HeartbeatUtc` rewritten **in place** every
**30 s**. A launcher that gets the flock (or can't use flock) still checks the record:

| Record says | Decision |
|---|---|
| `Mode == "Released"` | free |
| Same `HostId`, and the pid is dead (`kill(pid,0)` returns `ESRCH`) or is alive with a different start time (pid reused) | stale; take over silently |
| Different `HostId`, heartbeat at most **90 s** old | held; DATA-172 with `"Open Read-Only"` (default), `"Quit"` and `"Take Over…"` |
| Different `HostId`, heartbeat older than 90 s | probably stale, but two computers' clocks aren't trusted enough to take over automatically; DATA-172 with `"Take Over…"` as the default and the stale-claim line appended |
| Unreadable or half-written (after 3 retries 20 ms apart) | use the lock file's mtime as the heartbeat |

`"Take Over…"` asks for confirmation (critical style):

* title `"Take over this data folder?"`;
* text `"Only do this if you are sure the copy of AA on “{Host}” is no longer running. If it is still running, both copies will overwrite each other's changes."`;
* buttons `"Take Over"` (destructive) and `"Cancel"`.

On take-over the new editor writes its record (`Mode:"Owner"`).

An editor in lease mode re-reads the record after every wake from sleep (`NSWorkspace.didWakeNotification`), and
before its first write after a gap of more than 90 s. If another computer has taken over, this copy:

1. saves its unsaved changes as a conflict copy (DATA-181);
2. switches to read-only instance mode (DATA-174);
3. shows `"Another copy of AA took over this data folder"` —
   `"While this Mac was asleep, the copy of AA on “{Host}” took over editing. This copy is now read-only so neither overwrites the other."`
   (`"OK"`).

Windows AA doesn't read the lease (Q-9), so lease mode protects only Mac against Mac.

**DATA-178 — Housekeeping on becoming the editor.** Right after getting the lock (at launch or via DATA-175), the
editor deletes stale atomic-write temp files at the top level of `AppFolder`. A file is deleted when:

* its name matches `^(data\.json|settings\.json)\.[0-9a-f]{32}\.tmp$`, or equals `qrsync-baseline.json.tmp` or
  `qrsync-baseline.json.{32hex}.tmp`; **and**
* its mtime is more than **10 minutes** old (a Windows AA sharing the folder could be part-way through writing a
  fresh one).

Failures are ignored. Windows never cleans these up (its `finally` deletes only its own current temp file).

**DATA-179 — External active data file.** When `CurrentDataFile` is outside `AppFolder` (DATA-013, Import from
file), two editors of *different* data folders could still both save to that one external file. So the editor
also holds a second `flock`, on a per-user lock file
`~/Library/Application Support/AA-locks/external-{key}.lock`. `{key}` is the lowercase hex SHA-256 of the
canonical path (`realpath`, then lowercased, since Windows paths are case-insensitive).

* **When it is held.** Acquired after `LoadSettings` at launch, and **before** Import Database switches the active
  file. Released when the active file goes back to the default (bundle import, Flash Sync apply, DATA-049).
* **If another process holds it at launch:** DATA-172 with the messageText
  `"The data file is open in another copy of AA"` and the informativeText
  `"“{fileName}” is being edited by another copy of AA{holder}. Two copies would overwrite each other's changes. {choice}"`
  (same buttons).
* **If another process holds it at import:** a sheet `"That file is already open in another copy of AA."`
  (`"OK"`), and the import is cancelled before anything changes.

**DATA-180 — Detecting outside changes to the active data file.** This protects against writers the lock can't
stop: AA on Windows through Parallels shared folders or SMB, another computer, backup or sync tools, a restored
file.

After every load, and after every write *this* process makes, the editor records a **fingerprint** of the active
data file (§MP.3.4). Its own writes include the autosave, Save, imports, shared pulls, Flash Sync apply, the
encryption toggle and conflict resolution. Before every write, inside the serial persistence writer, it compares
the file on disk with that fingerprint. If someone else has changed the file, it does **not** write. Instead:

1. **Pause writing.** It keeps the model dirty and pauses every write to that file: the debounce, ⌘S, the periodic
   autosave, the shared push and the close-save.
2. **Ask the user.** It presents a sheet on the main window:
   * `messageText` `"The data file was changed outside this copy of AA"`;
   * `informativeText` `"“{fileName}” was replaced by another program — another computer, a sync or backup tool, or AA on Windows — after this copy last saved it ({ourTime}).\n\nTheir version was saved: {theirTime}\n\nWhichever version you don't choose is kept as a copy in the data folder's “conflicts” folder."`.
     `{ourTime}` is our last-written `LastModified` and `{theirTime}` is `PeekFileLastModified` of their file, both
     local `yyyy-MM-dd HH:mm:ss`, or `"(no save date)"`;
   * buttons `"Keep Mine"` (default), `"Use Theirs"`, `"Review Changes…"` and `"Stop Editing Here"`.

   What each button does:

   | Button | Action | Status line |
   |---|---|---|
   | **Keep Mine** | Copy their exact bytes to `conflicts/data-{yyyyMMdd-HHmmss}-theirs.json`, accept their fingerprint, resume writing and save now. | `"Kept your version — the other version was saved to conflicts/{name}."` |
   | **Use Theirs** | Write our current model (serialised, following the local-encryption setting) to `conflicts/data-{…}-mine.json`, then Revert to Saved (a repository swap onto their file). | `"Loaded the other version — yours was saved to conflicts/{name}."` |
   | **Review Changes…** | Show the change-preview sheet (DATA-100) with source name `"{fileName} (changed outside AA)"`, their file as the incoming data, and the age verdict from their stamp. **Import (Overwrite)** there = Use Theirs; **Cancel** returns to this sheet. | — |
   | **Stop Editing Here** | Save ours as in Use Theirs, reload theirs, and enter read-only mode (DATA-174 behaviour, but keeping the lock). The banner says `"Read-only — this data folder is being changed outside this copy of AA. Changes here are not saved."` with `"Resume Editing"`, which re-reads from disk, refreshes the fingerprint and leaves read-only mode. | — |

   * **Their file can't be read on the Mac** (for example it starts with `AAENC1\n` — encrypted by Windows AA — or
     isn't valid JSON): the sheet says `"… Their version can't be opened on this Mac ({reason}), so it can't be reviewed. …"`
     and offers only `"Keep Mine"` (their bytes still go to `conflicts/`) and `"Stop Editing Here"` (no reload; the
     model stays as it is and nothing is written).
   * **The file was deleted:** a sheet variant `"“{fileName}” was deleted by another program …"` with
     `"Keep Mine"` (recreate it) and `"Stop Editing Here"`.
3. **Also check between saves.** A directory watcher runs the same check when the model is **not** dirty: a
   `DispatchSource` on the directory holding the active data file (`AppFolder`, or the external file's directory
   per DATA-013), with a 1.5 s debounce and a 60 s poll for network volumes. The sheet is shown then too, because
   a silent reload could throw away our last saved edits, which the other writer never saw.

This is detection, not prevention. A write that lands between the check and our `rename` (a window of
milliseconds) is still lost. And Windows AA gets no such protection against the Mac's writes.

**DATA-181 — Conflict copies.**

* **Location and names.** Folder `AppFolder/conflicts/`, created on first use. Files are named
  `data-{yyyyMMdd-HHmmss}-{theirs|mine}.json` (local time), with `-2`, `-3`, … added when two land in the same
  second.
* **Contents.** "theirs" is the foreign file's bytes exactly as found, possibly encrypted. "mine" is our
  serialised model, written like any local data file (encrypted in the Mac format when *Encrypt Local Data File*
  is on).
* **Retention.** Keep the newest **20** files (by name); delete older ones after each addition.
* **Recovery.** File ▸ Recover ▸ `"Conflict Copies…"` lists them (name, kind, size, and `LastModified` read without
  loading), with `"Show in Finder"` and `"Restore…"`. Restore shows the change preview (DATA-100, source name = the
  file name) and then applies the data into the default data file, exactly like `ApplySyncedData`. It never
  repoints `CurrentDataFile`, which avoids DATA-034 switching the active file to one inside `conflicts/`.
* **Scope.** Not bundled, not synced, ignored by Windows.

**DATA-182 — `settings.json`: key-level merge.** Every Mac settings setter reads and rewrites **only the key it
changes**:

1. Read and parse the current file, retrying up to 3 times, 50 ms apart, if it can't be read.
2. Set or remove that one key, keeping every other key.
3. Write the keys in Windows order: known keys in §4.3 declaration order, then unknown keys in their existing
   order — the order Windows itself would emit.
4. Write the file atomically (§6.4).

If the file still can't be parsed, do **not** write. Keep the value in memory and show the status
`"Couldn't update settings.json (it is unreadable) — this change applies until AA quits."` This way a half-written
or foreign-written file can never cause the password hash, salt or other keys to be dropped (fixes D-18 on the
Mac).

Some keys are written together, in one read-modify-write: `CurrentDataFile` after a bundle import or Flash Sync
apply, and `PasswordHash` with `PasswordSalt`. Changes made by another process are not picked up live; a
read-only instance, and a Windows AA on a shared folder, see them at their next `LoadSettings`.

**DATA-183 — Other files in the data folder on the Mac.** With the guard in place only the editor writes these; a
read-only instance never does.

* **`qrsync-baseline.json`** — written through a unique temp file (`qrsync-baseline.json.{32hex}.tmp`, then a
  same-directory `rename`), never the fixed `.tmp` name of D-20. Flash Sync's pre-send save runs the DATA-180
  check, and only one Mac process can write the file. So whether the payload is built from disk after that save
  or from memory (spec 13 FLASH-021), it is always this process's data. This removes the DATA-165 cross-process
  mix-up.
* **Google token** — the Mac format of spec 14 §6.3 (an `AAKCGCM1` file plus a Keychain key). The file is written
  atomically (temp + rename). Keychain items belong to the user and are safe to read from several processes.
* **`crash.log`** — appended with `open(O_WRONLY|O_APPEND|O_CREAT|O_CLOEXEC, 0o644)`, writing each entry in a
  single `write`. With `O_APPEND` every write goes to the current end of the file, so entries from different
  processes never overwrite each other. A failed append MUST NOT stop the crash alert from showing (fixes D-22).
* **Notifications, the menu-bar extra and the daily digest** — editor only.

**DATA-184 — A data folder also used by AA on Windows (Parallels shared folder, SMB/NAS): unsupported, detected
and explained.** Sharing one `AppFolder` between a Windows AA and a Mac AA can't be made safe from the Mac side.
Windows takes no locks, reads no lease, has no local-file watcher and rewrites all of `settings.json` on every
change. The Mac MUST NOT try to block Windows (no locks on data files, no opens that deny sharing). It SHOULD
detect the situation and say so once per folder.

Evidence (any one is enough):

* `data.json` begins with `AAENC1\n`;
* `google-token/` holds a file beginning `AADPAPI1`;
* `qrmodels/` exists;
* `settings.json` has a Windows-style `CurrentDataFile`, `SharedSaveFile`, `GoogleDriveFolder` or
  `FolderBuilderBase` (`^[A-Za-z]:[\\/]` or `^\\\\`);
* DATA-180 detected an outside write;
* there is a `data.json.{32hex}.tmp` this process didn't create.

The warning is a dismissible banner, remembered per canonical folder in the `UserDefaults` key
`AA.SharedWithWindowsWarned.<sha256hex>`:
`"This data folder also seems to be used by AA on Windows. Two copies of AA must not edit one data folder — they overwrite each other's changes. Give each computer its own data folder and connect them with a shared save file (File ▸ Shared Save File ▸ Set…)."`
Buttons: `"Show Me How"` (opens the Help anchor `shared-save-setup`) and `"Don't Show Again"`.

Problems the user will otherwise run into (documented, not fixed):

* Local encryption on either side makes the file unreadable to the other side, and each enters safe mode
  (DATA-021, §6.5).
* Google sign-in can't be shared: both sides write the same token file name in incompatible formats, so each
  invalidates the other's sign-in (spec 14 §6.3).
* Paths saved in settings by one OS mean nothing to the other (§6.8), and Windows' full rewrites revert the Mac's
  `SharedSaveFile`.

**DATA-185 — A shared save bundle used by Windows and Mac copies (the supported cross-OS setup).** The protocol
(DATA-050 to DATA-058) is unchanged, and each machine keeps its own data folder. Mac specifics:

* **No locks.** The bundle is never locked. The push is `rename(tmp, bundle)` in the bundle's directory.
* **Expected push failures on SMB.** The rename can fail while a Windows peer has the bundle open for reading:
  `ZipFile.OpenRead` shares Read only, and the server won't replace an open file that doesn't allow delete. The
  push then fails, shows `"Shared save failed: {message}"` and the `"NOT SAVING"` indicator, and is retried the
  next minute. This is expected, not a bug in the Mac code.
* **`NSFileCoordinator`.** Reads, peeks, pulls and pushes of the bundle SHOULD go through `NSFileCoordinator`
  (`.forReplacing` for the push, `.withoutChanges` for peeks). This orders them against other *Mac* processes —
  for example two AA editors of different folders on one Mac sharing one bundle. It also handles File Provider
  folders (iCloud Drive, and Google Drive for desktop under `~/Library/CloudStorage`), downloading placeholder
  (dataless) files before they are read. It has no effect on Windows peers or other computers.
* **Parallels.** Point the Windows copy at the bundle through the Mac share (for example
  `\\Mac\Home\AA-Shared\aa-shared.zip`) and the Mac copy at the same file (`~/AA-Shared/aa-shared.zip`). Each keeps
  its own data folder.

**DATA-186 — One main window per process.** The in-process equivalent of this addendum: the main scene is a single
`Window` (spec 03), never a `WindowGroup`. File ▸ New Window and automatic window tabbing are disabled for the
main window (`NSWindow.allowsAutomaticWindowTabbing = false`), so one process never has two sets of pages on one
repository. Item windows, Quick work, Search and the other secondary windows share that one repository (specs 03
and 08).

### MP.3 Logic & algorithms

#### MP.3.1 `InstanceGuard.acquire(folder:)` — at launch

```
enum GuardResult { case owner(LockHandle), blocked(LockRecord?, lease: Bool), unguarded(reason: String) }

acquire(folder):
  mkdir -p folder                                                    // DATA-010
  path = folder + "/.aa.lock"
  fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o666)   // umask applies (typically 0644)
  if fd < 0 && errno in {EACCES, EPERM}:
      fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)             // another user's file: flock needs no write access
  if fd < 0: return .unguarded(strerror(errno))                      // EROFS, volume vanished, ELOOP (planted symlink) …
  network = (statfs(folder).f_flags & MNT_LOCAL) == 0
  gotFlock = false
  loop:
    if flock(fd, LOCK_EX | LOCK_NB) == 0: gotFlock = true; break
    if errno == EINTR: continue
    if errno == EWOULDBLOCK: rec = readRecord(fd); close(fd); return .blocked(rec, lease: network)
    if errno in {ENOTSUP, EOPNOTSUPP}: network = true; break         // no flock on this file system: lease only
    e = errno; close(fd); return .unguarded(strerror(e))
  if network:
    rec = readRecord(fd)
    if leaseHeld(rec):                                               // §MP.3.3
        if gotFlock: flock(fd, LOCK_UN)
        close(fd); return .blocked(rec, lease: true)
  writeRecord(fd, Mode: "Owner", LockKind: network ? "lease" : "flock", …)   // no-op if fd is read-only
  if network: start the 30 s heartbeat
  return .owner(LockHandle(fd, recordWritable: fd opened O_RDWR))    // fd stays open for the process lifetime
```

* `O_CLOEXEC` is mandatory. Without it, a child process started by AA would inherit the descriptor and keep the
  lock alive after AA dies.
* `O_NOFOLLOW` refuses a symlink planted at `.aa.lock`, which would otherwise silently change which file gets
  locked.
* `flock` works on a read-only descriptor, so a lock file owned by another user can still be locked; the record
  just isn't rewritten.
* The descriptor is only closed at process exit. The exceptions are DATA-175 "Stay Read-Only" and the lease
  hand-back above, which use `flock(fd, LOCK_UN)`.
* Unit tests can run in a single process: on macOS `flock` locks belong to the *open file description*, so two
  separate `open()` calls on the same file in one process do conflict.

#### MP.3.2 `readRecord` / `writeRecord`

* `readRecord(fd)`: `pread` the whole file (≤ 64 KiB; larger counts as unreadable), decode UTF-8 and parse a JSON
  object. On a parse failure, retry up to 3 times, 20 ms apart, in case of a rewrite in progress. Still failing →
  `nil`.
* `writeRecord(fd, fields)`: serialise compact JSON with the app's JSON writer (§4.1; non-ASCII escaped), then
  `pwrite(fd, bytes, 0)` and `ftruncate(fd, bytes.count)`. Never `rename`, which would change the file and break
  the lock (DATA-170). No fsync; the data is informational.
* The record is written when a process becomes the editor (at launch, DATA-175 Edit Here, or Take Over), at each
  heartbeat in lease mode (only `HeartbeatUtc` changes), and on a clean quit (`Mode:"Released"`,
  `HeartbeatUtc = now`).

#### MP.3.3 Classifying the holder (for the alert and lease decisions)

```
classify(rec):
  if rec == nil: return .unknown
  if rec.Mode == "Released": return .released
  if rec.HostId == thisHostId():
     alive = kill(rec.Pid, 0) == 0 || errno == EPERM
     if !alive: return .dead
     start = procStartUtc(rec.Pid)          // proc_pidinfo(PROC_PIDTBSDINFO): pbi_start_tvsec/usec; nil if unavailable
     if start != nil && abs(start − rec.ProcessStartUtc) > 2 s: return .dead      // pid reused
     if rec.Uid != getuid(): return .otherUser(rec.User)
     app = NSRunningApplication(processIdentifier: rec.Pid)
     return app == nil ? .sameUserNoApp : .sameUser(app)
  hb  = rec.HeartbeatUtc ?? mtime(lockFile)
  age = nowUtc − hb
  return age <= 90 s ? .otherHostFresh(rec.Host, hb) : .otherHostStale(rec.Host, hb)

leaseHeld(rec):
  c = classify(rec)
  if c in {.released, .dead}: return false
  if c == .unknown: return (nowUtc − mtime(lockFile)) <= 90 s     // an unreadable record counts as held only while fresh
  return true
```

* On a local volume, a `.blocked` result comes from `flock` itself and is final; `classify` only chooses the alert
  wording and buttons.
* `thisHostId()` = the first 16 lowercase hex digits of SHA-256 over the `gethostuuid()` UUID string (upper-case
  canonical form). It is stable per Mac and doesn't expose the raw hardware UUID.
* `.sameUserNoApp` (for example a `swift run` build with no app bundle) shows the same-user wording without
  `"Switch to Running AA"`.

#### MP.3.4 Fingerprint and pre-write check (DATA-180)

```
struct Fingerprint { absent: Bool; dev: UInt64; ino: UInt64; size: Int64; mtime: timespec; sha256: [UInt8] }

record(path, bytes):                      // after our own load (bytes read) or write (bytes renamed in)
   st = stat(path)
   known = st missing ? Fingerprint(absent: true) : Fingerprint(false, st.dev, st.ino, st.size, st.mtimespec, SHA256(bytes))

checkBeforeWrite(path) -> Verdict:        // inside the PersistenceWriter actor, right before the rename
   st = stat(path)
   if st missing: return known.absent ? .ok : .foreignDeleted
   if known.absent: return .foreignCreated(read(path))       // we saw no file (first run) but someone created one
   if (st.dev, st.ino, st.size, st.mtimespec) == (known.dev, known.ino, known.size, known.mtime): return .ok
   bytes = read(path)                     // hash only when the metadata differs
   if SHA256(bytes) == known.sha256: known = known with (st.dev, st.ino, st.size, st.mtimespec); return .ok
   return .foreignChanged(bytes)
```

* `.foreignCreated` is handled like `.foreignChanged`.
* On network volumes the inode number may change across remounts; the SHA-256 fallback prevents false conflicts.
* Cost: one `stat` per write (microseconds); hashing only on a mismatch (a 3 MB file takes about 2 ms).
* The watcher (DATA-180 step 3) calls the same check through the writer actor, so it can never race our own write.
  Our own renames update `known` before the watcher's debounce fires.
* When the active file changes (Import Database, a bundle import, Flash Sync), the fingerprint is re-recorded for
  the new path after our write.

#### MP.3.5 One write gate

`enum WriteGate { case normal, safeMode, readOnlyInstance, externalConflict }`, and
`canWriteDataFolder = (gate == .normal)`.

* `.safeMode` keeps the Windows set of suppressions (DATA-021), plus the D-12 recommendation.
* `.readOnlyInstance` and `.externalConflict` apply the DATA-174 list.
* Every command in the other specs that writes into `AppFolder` MUST check `canWriteDataFolder`, and be disabled
  with the help text `"Not available in a read-only copy of AA."` when it is false.
* `settingsStore.set` only updates memory unless the gate is `.normal`.

#### MP.3.6 Quit

* **Editor, clean quit:** run the close sequence (DATA-028/055) first, so it writes while the lock is still held.
  Then `writeRecord(Mode:"Released")`, then exit; the kernel drops the flock. Never unlink the lock file.
* **Read-only instance:** no close-sequence writes; just exit.
* **Blocked phase:** exit immediately.

#### MP.3.7 Constants

| Constant | Value | Where |
|---|---|---|
| Re-check while the second-launch alert is up | 1 s | DATA-172 |
| Read-only upgrade poll | 5 s | DATA-175 |
| Lease heartbeat | 30 s | DATA-177 |
| Lease freshness | 90 s | DATA-177, §MP.3.3 |
| Process start-time tolerance | 2 s | §MP.3.3 |
| Lock record read retry | 3 × 20 ms | §MP.3.2 |
| Settings read retry | 3 × 50 ms | DATA-182 |
| Watcher debounce / poll | 1.5 s / 60 s (same as the shared save) | DATA-174, DATA-180 |
| Stale temp file age | 10 min | DATA-178 |
| Conflict copies kept | 20 | DATA-181 |
| Lock record maximum size | 64 KiB | §MP.3.2 |

### MP.4 Data formats

#### MP.4.1 `AppFolder/.aa.lock` (Mac only)

Compact UTF-8 JSON with no BOM, PascalCase keys in the order below, rewritten in place (§MP.3.2). Windows never
reads or writes it. Readers ignore unknown keys and tolerate missing ones.

```json
{"Format":1,"Mode":"Owner","LockKind":"flock","Pid":4242,"ProcessStartUtc":"2026-09-30T07:14:03.512Z","AcquiredUtc":"2026-09-30T07:14:03.64Z","HeartbeatUtc":"2026-09-30T07:14:03.64Z","HostId":"9f86d081884c7d65","Host":"Eris-MacBook-Pro","User":"eriskay","Uid":501,"AppPath":"/Applications/AA.app","Version":"1.0 (42)","Platform":"macOS","AppFolder":"/Users/eriskay/Library/Application Support/AA"}
```

| Key | Type | Meaning |
|---|---|---|
| `Format` | int | `1` |
| `Mode` | string | `"Owner"` while held; `"Released"` after a clean quit |
| `LockKind` | string | `"flock"` (local volume) or `"lease"` (network volume, or no flock) |
| `Pid` | int | editor process id |
| `ProcessStartUtc` | string | editor process start time, UTC, written like a `Utc` DateTime (§4.1.5) |
| `AcquiredUtc`, `HeartbeatUtc` | string | same format |
| `HostId` | string | 16 hex digits (§MP.3.3) |
| `Host` | string | `Host.current().localizedName` (the Computer Name) |
| `User`, `Uid` | string, int | editor's short user name and uid |
| `AppPath` | string | `Bundle.main.bundlePath`, or the executable path when there is no app bundle (`swift run`) |
| `Version` | string | `"{CFBundleShortVersionString} ({CFBundleVersion})"`, or `"dev"` |
| `Platform` | string | `"macOS"` (reserved so a future Windows build could share the format — Q-9) |
| `AppFolder` | string | canonical folder path as the editor resolved it (for display only) |

Created with mode `0666 & ~umask` (typically `0644`). Never deleted.

#### MP.4.2 Other new files and keys

* `~/Library/Application Support/AA-locks/external-{sha256hex}.lock` — DATA-179. The same record format plus a
  `"DataFile"` key. One per user; never deleted. It lives in Application Support rather than Caches so the system
  cache cleaner can't unlink a held lock.
* `AppFolder/conflicts/data-{yyyyMMdd-HHmmss}[-n]-{theirs|mine}.json` — DATA-181.
* `UserDefaults` `AA.SharedWithWindowsWarned.<sha256hex of canonical AppFolder>` (Bool) — DATA-184.
* Distributed notification `com.bepavida.aa.InstanceRequest` — DATA-173. `userInfo` keys: `Action`
  (`"activate"`, `"open"`), `URLs` ([String]), `AppFolder` (String), `FromPid` (Int).

#### MP.4.3 Additions to §4.12 (data-folder inventory)

| Path (relative to AppFolder) | Written by | In bundles? | Notes |
|---|---|---|---|
| `.aa.lock` | Mac instance guard | no | never delete, rename or replace; Windows ignores it |
| `conflicts/` | Mac conflict handling | no | at most 20 files; may contain encrypted bytes |
| `qrsync-baseline.json.<32hex>.tmp` | Mac baseline write | no | transient (Windows uses the fixed name `qrsync-baseline.json.tmp`) |

#### MP.4.4 Addition to §4.14 (compatibility rules)

11. Mac-only runtime files in the data folder (`.aa.lock`, `conflicts/`) are ignored by Windows and are never
    bundled or synced. The Mac MUST NOT depend on Windows honouring them, and MUST NOT lock or deny-share any file
    that Windows reads (`data.json`, `settings.json`, attachments, bundles).

### MP.5 Dependencies

**Called by / calls:**

| Component | What it uses from this addendum |
|---|---|
| App delegate | `applicationWillFinishLaunching` (guard), `application(_:open:)` (collect launch documents; route documents in the editor), `applicationDidFinishLaunching` (alert), `applicationShouldTerminate` (depends on the launch phase), `NSWorkspace.didWakeNotification` (lease) |
| `DataStore` | `AppFolder` resolution; `LoadSettings` (read-only, before the alert); `WriteLocalDataFile` / `AtomicWrite` (fingerprint check and update); `PeekFileLastModified` (sheet text); the `ApplySyncedData` path (restoring a conflict copy) |
| `SettingsStore` | key-level merge (DATA-182); only writes when the gate is `.normal` |
| `AppRepository` | `suspendSaving`, `detach`, repository swap; the serial `PersistenceWriter` actor hosts `checkBeforeWrite` |
| `SharedSaveCoordinator` | not started in read-only mode; wraps bundle access in `NSFileCoordinator` (DATA-185) |
| `DataDiff` and the review sheet (DATA-100) | "Review Changes…" and restoring conflict copies |
| Main shell (spec 03) | new launch phases `.instanceCheck` and `.blocked`; the banner area; window subtitle; command enabling |
| Commands in other specs that write | must check `canWriteDataFolder` (§MP.3.5) |
| Flash Sync (spec 13) | unique temp name for the baseline; disabled in read-only mode |
| Drive (spec 14) | atomic token file; disabled in read-only mode |

**Windows-only APIs:** the Windows behaviour uses no dedicated API, because there is no guard. The Windows facts
above depend on NTFS/SMB share modes (`FileShare`), `MoveFileEx`/`ReplaceFile` (behind `File.Move` /
`File.Replace`) and `File.AppendAllText` / `File.WriteAllText` / `File.WriteAllBytes` (not atomic).

**macOS APIs used:** `open(2)` with `O_CLOEXEC | O_NOFOLLOW`; `flock(2)`; `pread` / `pwrite` / `ftruncate`;
`statfs(2)` (`MNT_LOCAL`, `f_fstypename`); `stat(2)`; `kill(2)`; `proc_pidinfo` (libproc); `gethostuuid(3)`;
`getuid`; `NSRunningApplication` (`activate(from:options:)`); `NSApplication.yieldActivation(to:)` /
`activate()`; `DistributedNotificationCenter`; `NSAlert` + `NSApp.abortModal()`;
`DispatchSource.makeFileSystemObjectSource`; `NSFileCoordinator`; CryptoKit `SHA256`; `os.Logger`;
`NSWorkspace.didWakeNotification`; `UserDefaults`.

### MP.6 macOS adaptation notes (new §6.13 — instance model)

#### MP.6.1 Launch sequence on the Mac (amends §3.27)

0. Resolve `AppFolder` (DATA-010), create it, install crash reporting (DATA-004).
1. `InstanceGuard.acquire(AppFolder)`. If this process is the editor, run DATA-178.
2. `LoadSettings()` (read-only) and apply the appearance.
3. If `CurrentDataFile` is outside `AppFolder`, acquire the external-file lock (DATA-179).
4. If blocked: collect launch documents, then show DATA-172 from `applicationDidFinishLaunching`. Depending on the
   answer: switch and quit, quit, or continue read-only.
5. Splash → login → main window (as the editor or read-only).
6. On main-window load:
   * **editor:** `Load` records the fingerprint; start the data-file watcher; §3.27 steps 4–9 as before;
   * **read-only:** load and display only; start the live-view watcher and the upgrade poll; skip housekeeping,
     timers, reminders and shared save.
7. Evidence check for DATA-184 (in either mode); show the banner if needed.

#### MP.6.2 SwiftUI / AppKit plumbing

* Use an `@NSApplicationDelegateAdaptor`. Run the guard in `applicationWillFinishLaunching`, before any scene can
  appear.
* Open the splash scene explicitly, and only after the guard says editor or the user picks Open Read-Only — for
  example `.defaultLaunchBehavior(.suppressed)` plus `openWindow(id: "splash")` from the launch coordinator. Never
  rely on SwiftUI opening the splash before the check. This amends spec 03's scene list: every scene stays
  suppressed until the launch coordinator leaves `.instanceCheck`.
* The blocked alert runs application-modal from `applicationDidFinishLaunching`, after the launch documents have
  arrived. The 1 s re-check timer is added in `.modalPanel` mode so it fires while the alert is up.
* The editor registers the `com.bepavida.aa.InstanceRequest` observer in `applicationDidFinishLaunching`, and
  buffers requests until the main window exists.
* `applicationShouldHandleReopen` (Dock click on the running editor) brings the main window forward, or the login
  window during the sign-in gate.
* Development: `open -n --env AA_DATA_DIR=/tmp/aa-test AA.app` starts an isolated second editor, the Mac
  equivalent of the developer's Windows shared-save test setup. Without the `--env`, the second launch shows
  DATA-172.

#### MP.6.3 What each mechanism protects, and what it doesn't

| Mechanism | Scope | Protects against | Does **not** protect against |
|---|---|---|---|
| `flock` on `.aa.lock` | processes on this Mac, all users, on local volumes; on network volumes it depends on the file system and server (may be local-only or forwarded) | a second Mac AA process on the same folder (`open -n`, a second copy, `swift run`, another user) | Windows AA (never locks); another computer (unless forwarded *and* honoured by the server); programs that don't ask for the lock (Finder, sync tools, editors) |
| Lease record (lease mode) | anything that reads it | another Mac AA on another computer (cooperative) | Windows AA (doesn't read it — Q-9); badly wrong clocks (hence no automatic take-over across computers) |
| `NSFileCoordinator` / `NSFilePresenter` | processes on this Mac that use file coordination | ordering of reads and writes with File Provider (iCloud Drive, Google Drive for desktop), `NSDocument` apps and other AA processes; downloading dataless files | Windows; writes from a Parallels guest (they reach APFS through Parallels' host process, without coordination); other computers; command-line tools |
| Atomic `rename` + `F_FULLFSYNC` (§6.4) | any reader | half-written files; a zero-length file after power loss | lost updates (the last writer still wins) |
| Data-file fingerprint (DATA-180) | any writer of the active data file | silently overwriting *their* write when we save (detects it and keeps both); a stale view | a write that lands in the milliseconds between check and rename; changes to other files (settings: DATA-182) |
| Key-level settings merge (DATA-182) | any writer of `settings.json` | reverting other writers' keys; losing the password hash to a half-written file | two writers changing the *same* key (last writer wins) |
| Shared save protocol (DATA-050…058) | across machines and operating systems | the designed sync, with prompts | truly simultaneous edits (last writer wins; see D-1, D-2) |

#### MP.6.4 Parallels and SMB specifics

* **Parallels shared folders.** A Windows guest sees Mac folders as `\\Mac\Home\…`. Parallels' host process
  carries out the guest's writes on the Mac's APFS volume. The Mac sees them as ordinary file changes
  (`DispatchSource` fires, fingerprints change), but they are never coordinated, never take `.aa.lock`, and
  Windows can't see Mac `flock` locks. This is covered by DATA-180 and DATA-184. Do not point Windows AA's
  `AA_DATA_DIR` at the Mac's data folder; share a bundle instead (DATA-185).
* **SMB/NAS.** Depending on the server and macOS version, macOS `smbfs` may forward `flock` as SMB byte-range locks
  or keep it local. The spec doesn't rely on either and uses lease mode. Windows clients strictly enforce SMB
  share modes and byte-range locks — exactly why the Mac must never lock or deny-share a file Windows reads.
* **NFS/AFP/WebDAV:** lease mode, as above.
* **Cloud-synced data folders.** A data folder inside iCloud Drive or `~/Library/CloudStorage` (via
  `AA_DATA_DIR`) is unsupported: files can be evicted to dataless placeholders and changed by the sync client at
  any time. The Mac MAY show a one-time warning there. The shared bundle, however, is fine in those locations
  (DATA-185).

#### MP.6.5 Making it feel native

* "Switch to Running AA" does what Launch Services does for an ordinary launch, so the usual accident (`open -n`,
  a second copy) ends where a Mac user expects: in the running app, with any double-clicked document already
  forwarded.
* The window subtitle "Read-Only" follows Mac document conventions ("— Locked", "— Read-Only").
* SF Symbols: `lock.fill` (read-only banner), `exclamationmark.triangle.fill` (conflict sheet and the
  shared-with-Windows banner), `arrow.triangle.2.circlepath` (live-view status).
* Banners use the standard material and animate in and out (`.transition(.move(edge: .top).combined(with: .opacity))`),
  and stay until their condition ends.

#### MP.6.6 Genuinely impossible on macOS, and the closest alternative

| Impossible | Closest faithful alternative |
|---|---|
| Stopping a Windows AA from writing a data folder it shares with the Mac | Detect it (DATA-180/184), keep both versions (DATA-181), warn, and recommend separate folders joined by a shared bundle (DATA-185) |
| Preventing lost updates between any two writers, given the whole-file last-writer-wins format | Conflict copies make the loss recoverable by hand; automatic merging is Q-12 |
| Windows seeing the Mac's lock | A shared lease format both apps read (Q-9, needs a Windows change) |

### MP.7 Test vectors

**How to test.** Guard logic can be tested in one process (two `open()` calls on the same file conflict under
`flock`, §MP.3.1). Crash and inheritance cases need child processes (`Process` running a small test helper that
calls `acquire` and then sleeps). Inject a `ProcessProbe` (liveness, start time, `NSRunningApplication` lookup), a
`Clock`, a `HostId` and a `VolumeInfo` (local or network) so the lease table can be covered without two computers.
`T` below is a fresh temporary folder used as `AppFolder`.

#### MP.7.1 Guard

| # | Given | When | Then |
|---|---|---|---|
| G-1 **second launch refused** | P1 ran `acquire(T)` → `.owner`, record written | P2 runs `acquire(T)` | P2 gets `.blocked(rec)` with `rec.Pid == P1`, `rec.Mode == "Owner"`, `rec.LockKind == "flock"`. P2's alert: messageText `AA is already running with this data folder`; informativeText `Another copy of AA (started 09:14, process 4242) is using:\n\n{T abbreviated}\n\nOnly one copy of AA can edit a data folder at a time — two copies would overwrite each other's changes. Switch to the copy that is already running, or open this one read-only to look without saving.`; buttons `["Switch to Running AA","Open Read-Only","Quit"]`. Choosing Quit exits with status 0. Nothing under `T` changed: `.aa.lock` bytes are identical (P2 never writes the record), no `settings.json` was created if there wasn't one, and every mtime and size is unchanged. |
| G-2 **stale lock after a crash is reclaimed** | P1 is the editor; note the inode of `T/.aa.lock` | `kill -9 P1`; then P2 runs `acquire(T)` | `.owner` immediately, with no alert. The record now has `Pid == P2` and `Mode == "Owner"`; the inode is unchanged (the file was reused, not replaced). |
| G-3 clean quit | P1 is the editor | P1 quits normally | The record shows `Mode == "Released"`; the file still exists; the next `acquire` → `.owner`. |
| G-4 no inheritance | P1 is the editor and starts `/bin/sleep 30` as a child | `kill -9 P1`; P2 runs `acquire(T)` | `.owner` (it would be `.blocked` without `O_CLOEXEC`). |
| G-5 symlinked path | `L` is a symlink to `T`; P1 holds `T` | P2 runs `acquire(L)` | `.blocked` |
| G-6 case variant | case-insensitive APFS; P1 holds `/tmp/X/AA` | P2 runs `acquire("/tmp/X/aa")` | `.blocked` |
| G-7 different folders | P1 holds `T1` | P2 runs `acquire(T2)` | `.owner` for both |
| G-8 planted symlink | `T/.aa.lock` is a symlink to `/tmp/elsewhere` | `acquire(T)` | `.unguarded("Too many levels of symbolic links")` (`ELOOP`); launch continues; one `os.Logger` line |
| G-9 read-only volume | `T` is on a read-only disk image with no `.aa.lock` | `acquire(T)` | `.unguarded` (`EROFS`) |
| G-10 lock freed while the alert is up | P2 shows G-1's alert | P1 quits | Within about 1 s P2's alert closes by itself, P2 becomes the editor and shows the splash. |
| G-11 in-process check | — | `fd1 = open(T/.aa.lock)`, `flock(fd1, EX\|NB)` → 0; `fd2 = open(same)`, `flock(fd2, EX\|NB)` | `-1` with `EWOULDBLOCK`; after `close(fd1)` → 0 |

#### MP.7.2 Switch and forward

* F-1: P1 is the editor. `open -n -a AA.app /tmp/x.aaz` → P2 is blocked and collected `/tmp/x.aaz`. "Switch to
  Running AA" → P1 receives `com.bepavida.aa.InstanceRequest` with
  `{"Action":"open","URLs":["/tmp/x.aaz"],"AppFolder":"<T canonical>","FromPid":<P2>}` and object `"<P1 pid>"`. P1
  becomes active and shows the change-preview sheet for `x.aaz`. P2 exits having written nothing.
* F-2: a request whose `AppFolder` differs from P1's folder → ignored (P1 does nothing).
* F-3: the holder is another user's process (`NSRunningApplication` is nil) → buttons
  `["Open Read-Only","Quit"]`, and the informativeText contains `(running for the user “ana” on this Mac)` and
  `You can open this one read-only to look without saving, or quit.`

#### MP.7.3 Lease table (`classify` / `leaseHeld`; HostId H is this Mac)

| Record | Host | Pid probe | Start-time probe | Heartbeat age | Result |
|---|---|---|---|---|---|
| `Mode:"Released"` | any | — | — | — | free |
| Owner | H | `ESRCH` | — | — | `.dead` → take over silently |
| Owner | H | alive | differs by 10 s | — | `.dead` (pid reused) → take over silently |
| Owner | H | alive, same uid | same | — | held (`.sameUser`) |
| Owner | H | `EPERM` | same | — | held (`.otherUser`) |
| Owner | other | — | — | 30 s | held (`.otherHostFresh`); default `Open Read-Only`; `Take Over…` offered |
| Owner | other | — | — | 91 s | held (`.otherHostStale`); default `Take Over…`; stale-claim line appended |
| unreadable | — | — | — | lock-file mtime 10 s | held (`.unknown`, fresh) |
| unreadable | — | — | — | lock-file mtime 10 min | free (`.unknown`, stale) |

L-1 (wake): an editor in lease mode wakes; the record now shows another host as `Owner` → conflict copy
`conflicts/data-…-mine.json` written (only if dirty), gate `.readOnlyInstance`, and the alert
`Another copy of AA took over this data folder`.

#### MP.7.4 Read-only instance

* R-1: P1 is the editor; P2 is read-only. In P2: rename an item, turn on Dark Mode, press ⌘S, advance the clock 5
  minutes, then quit. A SHA-256 of every file under `T` except `crash.log` is identical before and after. ⌘S
  showed `Read-only — not saving`. The status after Dark Mode was `Dark mode on. (this window only — read-only)`.
* R-2: P1 renames "Pump" to "Pump 2" and saves → within 1.5 s plus processing, P2's list shows "Pump 2", P2's
  selected tab and item are unchanged, and the status is `Updated from the other copy of AA (HH:mm:ss).`
* R-3: P1 quits → within 5 s P2's banner reads `The other copy of AA has closed. You can edit here now.` A P3
  launched now is blocked (P2 holds the lock). "Edit Here" in P2 → gate `.normal`, record `Pid == P2`, status
  starts with `Now editing — `.
* R-4: in P2, every command in the DATA-174 disabled list reports `isEnabled == false`, with the help text
  `Not available in a read-only copy of AA.`

#### MP.7.5 Outside changes (DATA-180/181), clock fixed at 2026-09-30 14:15:02

| # | Action | Expected |
|---|---|---|
| X-1 | load → our autosave writes → next autosave | `.ok` (the rename changed the inode, but `known` was updated) |
| X-2 | `touch data.json` from outside (only the mtime changes) | hashes equal → `.ok`, no sheet |
| X-3 | an outside tool replaces `data.json` with different valid JSON; we edit | the autosave does not write; the sheet appears; "Keep Mine" → `conflicts/data-20260930-141502-theirs.json` holds exactly the outside bytes, `data.json` holds our serialisation, and later autosaves are `.ok` |
| X-4 | as X-3, choose "Use Theirs" | `conflicts/data-20260930-141502-mine.json` parses to our model (or starts with `AAENCM1\n` when encryption is on); the model now matches theirs; `known` = theirs |
| X-5 | the outside file starts with `41 41 45 4E 43 31 0A` (`AAENC1\n`) | sheet variant with only "Keep Mine" and "Stop Editing Here"; "Keep Mine" keeps their bytes as a `-theirs` copy |
| X-6 | an outside process deletes `data.json` | `.foreignDeleted` sheet; "Keep Mine" recreates the file |
| X-7 | our own `ImportSharedBundle`, `ApplySyncedData` and encryption toggle, each followed by an autosave | no sheet in any case |
| X-8 | 21 conflict copies created | 20 remain; the oldest name is gone |
| X-9 | two conflicts in the same second | `…-141502-theirs.json` and `…-141502-2-theirs.json` |
| X-10 | the model is not dirty and an outside change happens | after the 1.5 s debounce the sheet appears (no silent reload) |
| X-11 | "Stop Editing Here", then another outside change | reloads silently; status `Updated from the other copy of AA (HH:mm:ss).`; "Resume Editing" → gate `.normal` |

#### MP.7.6 Settings (DATA-182)

* S-1: after our load (our in-memory `DarkMode` is false), another process writes
  `{"SyncOnSave":false,"DarkMode":true,"Foo":1}`. The Mac calls `setTextOnlyExport(true)` → the file becomes
  `{"SyncOnSave":false,"DarkMode":true,"TextOnlyExport":true,"Foo":1}` (known keys in §4.3 order, unknown keys
  last; `DarkMode` is not reverted).
* S-2: `settings.json` = `{"PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw==","DarkMode":tr`
  (cut off) → `setDarkMode(false)` retries 3 times and then does not write. The file bytes are unchanged, memory has
  `DarkMode == false`, and the status is `Couldn't update settings.json (it is unreadable) — this change applies until AA quits.`
* S-3: read-only instance, `setDarkMode(true)` → the file is unchanged.
* S-4: `savePasswordSettings(h, s)` → both keys are written in one atomic replace (never one without the other).

#### MP.7.7 External data file (DATA-179)

* E-1: P1 (folder `T1`) imports `/tmp/shared.json` → P1 holds `AA-locks/external-<sha256("/private/tmp/shared.json")>.lock`
  (after `realpath` and lowercasing). P2 (folder `T2`) tries Import Database on `/tmp/SHARED.json` → a sheet
  `That file is already open in another copy of AA.`; P2's `CurrentDataFile` is unchanged.
* E-2: P1 then imports a bundle (the active file goes back to the default) → the lock is released, and P2's retry
  succeeds.

#### MP.7.8 Temp-file cleanup (DATA-178), clock = now

| File at the top level of `T` | mtime | Result |
|---|---|---|
| `data.json.0123456789abcdef0123456789abcdef.tmp` | −11 min | deleted |
| `data.json.0123456789abcdef0123456789abcdef.tmp` | −5 min | kept |
| `data.json.tmp` | −1 h | kept (no match) |
| `settings.json.fedcba9876543210fedcba9876543210.tmp` | −1 h | deleted |
| `qrsync-baseline.json.tmp` | −1 h | deleted |
| `files/x.0123456789abcdef0123456789abcdef.tmp` | −1 h | kept (top level only) |
| `.aa.lock` | any | kept (never touched) |

#### MP.7.9 Shared-with-Windows evidence (DATA-184)

`data.json` starting with `AAENC1\n` → banner. `google-token/Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive`
starting with `AADPAPI1` → banner. A settings `CurrentDataFile` of `"C:\\Users\\bob\\AppData\\Local\\AA\\data.json"`
→ banner. No evidence → no banner. After "Don't Show Again" → no banner for that folder; a different folder with
evidence → banner.

#### MP.7.10 Windows behaviour (reference scenarios for verifiers; reproduce with two `AA.exe` and the same `AA_DATA_DIR`)

* WIN-1 idle copy overwrites on close: A and B start at 09:00. A adds task "X", and the autosave writes. Close B,
  then close A: `data.json` contains X (A saved last). Repeat, closing A first and then B: `data.json` does **not**
  contain X, and its `LastModified` is B's close time.
* WIN-2 encryption reverted: A turns on encryption (`data.json` starts with `AAENC1\n`). B edits anything → after
  750 ms `data.json` is plaintext. B toggles Dark Mode → `settings.json` has `"EncryptLocalData":false`.
* WIN-3 shared save lost: A sets `aa-shared.zip`; B toggles Dark Mode → `settings.json` has no `SharedSaveFile`.
* WIN-4 attachment swept: B attaches `manual.pdf` (`files/<g>_manual.pdf`). A imports a bundle whose `files/` lacks
  it → the file is deleted; B shows the attachment as missing.
* WIN-5 phone changes reverted: B applies a Flash Sync change set from the phone (item P added). A edits anything →
  `data.json` has no P. A then flashes → the change set carries `Deletes` for P.

### MP.8 Defects and open questions (extends §8)

| ID | Where | Defect | Mac recommendation |
|---|---|---|---|
| D-18 | `WriteSettings` (`DataStore.cs:243-245`) | When `existing` can't be parsed (a half-written file from a concurrent write), the rewrite drops `PasswordHash`/`PasswordSalt`, `GoogleDriveFolder`, `FolderBuilderBase`, `GeminiApiKey` and unknown keys. The app password is erased from disk. | Key-level merge that refuses to write over an unreadable file (DATA-182). |
| D-19 | `App.OnStartup` (whole app) | No instance guard: two Windows copies silently overwrite each other, and an idle copy overwrites the other copy's work on close (DATA-160/161). | Instance guard + read-only mode (DATA-170…175). For Windows, see Q-9. |
| D-20 | `FlashSyncStore` (`:26`, `:73`) | The payload is read from disk, not from the calling process's model; the baseline uses a fixed temp name that two processes share. | One writer via the guard; unique temp name (DATA-183). |
| D-21 | `DpapiDataStore.StoreAsync` (`:37`) | The token is written non-atomically; a read at the same moment looks like "no token" and can start an interactive sign-in. | Atomic temp-file + rename (DATA-183). |
| D-22 | `App.ReportCrash` (`App.xaml.cs:55-60`) | If appending to `crash.log` fails, the crash alert is skipped too. | Show the alert whatever happens to the append; `O_APPEND` single writes (DATA-183). |
| D-23 | `FlashSyncStore.WriteSettingsTree` (`:162`) | Non-atomic `settings.json` write, same exposure as DATA-162. | Atomic write via `SettingsStore` (DATA-182). |
| D-24 | `MainWindow` (no watcher on the local data file) | Outside changes to `data.json` (another copy, a restored backup, Windows over a share) go unnoticed until a reload, and the next save overwrites them silently. | Fingerprint check and watcher (DATA-180) with conflict copies (DATA-181). |

* **Q-9** Should the Windows build adopt the `.aa.lock` lease (read the JSON record; write its own with
  `"Platform":"Windows"`, heartbeat it, and offer read-only when another holder is fresh) so the guard works in
  both directions across Parallels/SMB? Windows can't see Mac `flock` locks, so it would rely on the lease only.
  Recommendation: yes; small, self-contained, and it closes D-19 on Windows too.
* **Q-10** In a read-only instance, should editing be switched off everywhere (the spec says SHOULD), or only
  banner-warned like Windows safe mode?
* **Q-11** Are 20 conflict copies, kept in `AppFolder/conflicts/`, the right amount and place? Should the list also
  be reachable from the Trash window?
* **Q-12** Should the Mac, on a conflict, offer an automatic per-item three-way merge (base = the last file we
  wrote or read; merge by `Id` at the top level, like `DataDiff`) instead of "keep one, save the other as a copy"?
  Out of scope for parity; a possible later improvement.

---

## Addendum: Spec ownership map + fix dangling cross-references

> **Gap-fill (normative for cross-spec conflicts).** The fourteen specs in `mac/Docs/Spec/` were written in
> parallel. Many components are described in two, three or four of them, sometimes with different words, and
> several specs point at a "the *X* spec" that has no such file. This addendum:
>
> 1. names the **single owning spec** (and its feature IDs) for every shared component and cross-cutting area;
> 2. resolves every dangling "the *X* spec" reference to a concrete file, section and ID range;
> 3. records every **conflict** found between specs, with a ruling and, where Windows behaviour was in dispute,
>    the C# lines that were re-read to settle it;
> 4. consolidates the Mac **keyboard and menu registry** (so no two specs bind the same shortcut) and the
>    **Keychain item registry**;
> 5. maps every persisted key and file to the spec that owns its semantics.
>
> It extends §2 with a new feature group **P** (IDs **DATA-200 to DATA-224**). Subsections use the prefix **OWN**
> so they never collide with the main numbering or with the multi-process addendum above (prefix **MP**, IDs
> DATA-160…186). Conflict rulings are numbered **OC-01…**, dangling-reference fixes **XR-01…**, test vectors
> **TV-OWN-01…**, questions **Q-OWN-1…**. Nothing earlier in this file or in any other spec is deleted; where a ruling
> here contradicts an earlier paragraph of another spec, the ruling wins (DATA-200) until that spec is amended.
>
> State of the specs when this was written (2026-09-30): the 14 base specs plus eight addenda —
> 01 "Golden-fixture plan to close the 'Verification TODO' / '(confirm)' items" (DATA-300…326, prefix G),
> 01 "Same-machine multi-process model" (DATA-160…186), 03 "Build, distribution & smoke-test parity"
> (SHELL-170…207), 05 "Normative shared XamlDOM contract" (CONT-150…169), 06 "Erratum: PromptWindow Mac
> contract…" (BUILD-136…150), 07 "Erratum: ItemPicker returns tags in
> selection order…" (VIEW-208…216), 10 "One normative AACore XLSX reader contract" (VESSEL-300…334) and 12 "Embed the
> TagExtractor keyword lists verbatim" (SIRE-049…051). Later addenda are handled by DATA-224.

### OWN.0 Sources read for this addendum

| Source | What was used |
|---|---|
| `mac/Docs/Spec/01…14-*.md` | Every heading; every feature-ID definition line (`grep -n -E '^\*\*(PREFIX)-[0-9]{3}'`); every "Mac adaptation" and "open questions" section; every paragraph cited in OWN.2–OWN.4 read in full. |
| `grep -n -i 'the [a-z /-]* spec' mac/Docs/Spec/*.md` | The ten dangling references named by the task (XR-01…XR-10). |
| A multi-line scan (`perl -0777`, OWN.3.4) for `(the\|a\|see\|per\|by\|in) … spec`, plus a scan for bare `<name> spec` phrases | Every other named reference, including ones broken across a line end (e.g. 09:1327 "the reminders spec"), resolved in DATA-212. |
| `mac/Docs/ARCHITECTURE-BRIEF.md` (95 lines) | Binding decisions: no third-party packages, Swift language mode 5, bundle id `com.eriskay.aa`, `AppStore` naming, JSON layer rules, unknown-member preservation on every object. |
| `AA/Views/ItemPickerWindow.xaml(.cs)`, `PromptWindow.xaml(.cs)` | OC-08, OC-09 (confirming the two errata already appended to 06 and 07). |
| `AA/Services/SearchService.cs:57-73` | OC-11 (locked items: Name **and** Tags are searched). |
| `AA/Views/ContainerViewerWindow.xaml.cs:80-110` | OC-12 (the missing-file message shows the **resolved** path). |
| `AA/Services/SavedListOrder.cs:30-47` | OC-16 (Nudge defect D-1 re-simulated). |
| `AA/Services/DataDiff.cs:170-247` | OC-13 (`ToDictionary` / `ToHashSet` behaviour). |
| `AA/Views/SearchWindow.xaml.cs:88-99` | OC-54 (search highlight is `#FFE066`). |
| `grep` over `AA/**/*.cs` for `XLWorkbook`, `ZipArchive`, `ZipFile`, `DeflateStream` | OWN.2 group B (who reads and writes XLSX/ZIP on Windows). |
| The eight addenda listed above (headers, ID ranges, rulings; 10 §X.2 and §X.7.1 and 06 §Add.2 in full) | Rule 2 of DATA-200: each is the owner's normative text for its component. |

### OWN.1 Overview

**Why this exists.** A Swift implementer who opens spec 06 to build the item picker finds BUILD-131; spec 04 has
HIER-131; spec 07 has VIEW-202 and now VIEW-208…216; spec 08 has QUICK-231 and a §6.2 row. They mostly agree, but
not completely, and some of the disagreements change behaviour. The same is true of the prompt dialog, the date
prompt, the batch menus, the Trash window, the activity log, the change preview, the item windows, the keyboard
shortcuts, the XLSX/ZIP/XAML codecs and the Keychain. Several specs also defer to "the tools spec", "the
multi-window spec", "the batch-actions spec" and so on, none of which exists under that name.

**How to use it.**

* **Implementers:** look up the component in DATA-202…DATA-210. Implement it **once**, from the owning spec, in the
  Swift module DATA-220 names. Read the subordinate specs only for their call sites. Annotate code with the owning
  ID (DATA-221).
* **Verifiers:** a behaviour is checked against the owner. When a subordinate spec says something different, check
  OWN.2 DATA-213 (conflict register) before filing a defect.
* **Spec authors:** cite other specs as `NN §S (ID)` — e.g. `08 §2.5 (QUICK-150)` — never "the *X* spec" (DATA-222).

**What does not change.** No on-disk format, no Windows behaviour and no feature is changed by this addendum. Every
ruling picks one of the existing texts, merges two compatible ones (e.g. OC-15, OC-42, OC-55), or records a behaviour
re-verified in the C# or settled by a later normative addendum; none changes what is stored.

---

### OWN.2 Feature checklist — group P (ownership and cross-references)

#### P.1 Rules

**DATA-200 — Precedence ladder (normative).** When two documents disagree about the Mac port, the first rule that
applies wins:

1. **`mac/Docs/ARCHITECTURE-BRIEF.md`** ("binding decisions"), and `ARCHITECTURE.md` when it exists (the brief wins
   over it unless the lead amends the brief).
2. **A normative addendum or erratum appended to the owning spec** for that component (for example 06 Addendum
   BUILD-136…150 for the prompt sheet; 07 Addendum VIEW-208…216 for the item picker; 10 Addendum VESSEL-300…334 for
   the XLSX reader; 05 Addendum CONT-150…169 for the XAML DOM and cascade).
3. **A ruling in the conflict register** DATA-213 (this addendum).
4. **The owning spec's base text** (DATA-202…DATA-210).
5. **Subordinate specs** — their descriptions of a component they do not own are informative summaries.

Two special cases:

* **Windows facts.** When specs disagree about *what Windows does*, the Windows build is the arbiter: first a golden
  recorded by the oracle tools of the golden-fixture plan (01 Addendum G, DATA-300…326; "the golden wins", DATA-308),
  otherwise the C# source at commit `37cdab0`. The verifier re-reads the cited lines and the result becomes a ruling
  here (OC-11, OC-12, OC-13, OC-16, OC-54 were settled this way). A later golden that contradicts one of these rulings
  wins over it, and the ruling is corrected by an erratum.
* **Data compatibility.** For anything written to or read from `data.json`, `settings.json`, `source.json`, bundles,
  `enc:` blobs, lock hashes and Flash Sync payloads, this spec's §4 (with the brief) wins over every restatement
  elsewhere, whatever rule 2–5 say.

**DATA-201 — Spec index.** The fourteen specs, their feature prefixes and ID ranges (including addenda), and scope:

| File | Prefix | IDs | Owns (scope) |
|---|---|---|---|
| `01-data-model-persistence.md` | `DATA-` | 001–153; MP 160–186; OWN 200–224; G 300–326 | Model schema, JSON codec, data folder, load/save/safe mode, bundles, shared save, attachment storage, local encryption, app password + `enc:`, item-lock service, change-preview model, Trash/log/recurrence model rules, settings, instance guard, this map. |
| `02-repository-domain-services.md` | `REPO-` | 001–155 | `AppRepository` (= Swift `AppStore`), lookups, relationships, status sync, batch services, work ranges, recurrence, Trash operations and undo, activity-log API, search service, reminder computation, group ops, saved-list order, checklist-template service, schedule service. |
| `03-main-shell-theme.md` | `SHELL-` | 001–162; Add. 170–207 | Startup/splash/login/crash, main window chrome, tabs, keyboard, save orchestration, File/Tools/View/About menus, sync orchestration, reminders UI, navigation, theme, Password and Prompt dialogs (Windows facts); build, packaging and smoke-test contract (Addendum). |
| `04-hierarchy-pages.md` | `HIER-` | 001–150; M01–M07 | Equipment/Tasks/Procedures/Vessels pages, sidebar and groups UI, details pane, item-lock UI, relationships tab, specifics tabs, multi-window, shared dialogs and batch menus (§N), read-only container viewer. |
| `05-container-richtext-filebank.md` | `CONT-` | 001–098; Add. 150–169 | Rich-text editor, list engine, text lock, file bank UI, HTML→XAML, XAML vocabulary and XAML⇄NSAttributedString converter, insert-saved-list dialog; the shared `XamlDOM` cascade/computed-style contract for every styled consumer (Addendum). |
| `06-builders-savedlists.md` | `BUILD-` | 001–150; A1–A28; C1–C3 | Checklist builder control, step editor, procedure Checklist Steps area, subtask builder/editor, saved-list semantics and tab, crew schedule builder, `.aasched.json`, `TextPromptSheet` (Addendum). |
| `07-calendar-board-planner-buckets-map.md` | `VIEW-` | 001–216 | Calendar, Board, Planner, Buckets, Relationship Map; saved-list-to-tasks picker; item-picker contract (Addendum 208–216). |
| `08-quick-floating-windows.md` | `QUICK-` | 001–231 | Floating due-dates window, quick work (Ctrl+N), quick switcher, search window, activity-log window, Trash window, import change preview (DiffWindow + DataDiff algorithm). |
| `09-crew.md` | `CREW-` | 001–106 | Crew tab, COMPAS import, date resolver and `CrewMember.ParseDate`, expiry, crew editor, crew table + XLSX export (`XlsxWriter`). |
| `10-vessel-ports-jobs-cards.md` | `VESSEL-` | 001–285; Add. 300–334 | Quick Cards + editor, Work Orders (Shippalm), per-vessel ports, Ports database, maritime icons/palette; the one normative XLSX reader for every importer (Addendum). |
| `11-pdf-checklist-export.md` | `PDF-` | 001–105 | Item PDF, checklist-only PDF/XLSX, saved-lists PDF, rich text → PDF pipeline, list-style prompt. |
| `12-sire.md` | `SIRE-` | 001–051 | SIRE 2.0 tab, bank, filters, insertion-only body, tasks, quick-add, export, Gemini key. |
| `13-flash-sync.md` | `FLASH-` | 001–135 | QR fountain protocol, Base45, CRC-32, raw DEFLATE, change sets, baseline, send/receive UI, interop. |
| `14-drive-tools.md` | `TOOLS-` | 001–090 | Google Drive (synced folder, OAuth, token store, upload/list/download, real-time sync); Folder builder, Date calculator, Unit converter. |

#### P.2 Ownership map

Column **Owner** is the single spec that wins on conflict (subject to DATA-200 rules 1–3). Column **Also described
in** lists subordinate texts: summaries to be read only for call-site details. Column **Split / notes** says when a
component is legitimately split (e.g. service vs UI), and which OC ruling applies.

**DATA-202 — Data and persistence layers.**

| # | Component / area | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| A1 | JSON layer: `JSONValue`, byte-level parser, System.Text.Json-emulating writer, escaping, key order, null omission, number lexemes, unknown members, depth, framing | **01 §4.1** (4.1.1–4.1.10), §6.1 "Codec", §6.3, App. A | 02 §4.1; 04 §4.1; 06 §4.1; 07 §5.1; 08 §4.1; 09 §4.1; 10 §4.1; 13 §3.11.10 + §6.2 | Brief tightens 01: escaping MUST be emulated (OC-01), unknown members kept on **every** object (OC-02), no `Codable` (OC-03). 13 §3.11.10 owns the *accessor* semantics Flash Sync needs; it is the **same** `JSONValue` type, not a second one. |
| A2 | `NetDateTime` (.NET `DateTime` ticks + Kind; read/write rules) | **01 §4.1.5**, App. A | 02 §4.2; 07 §5.3; 11 PDF-103; 14 §3.2.10 | 07 §5.3 owns *which Kind each of its write paths produces*; 11 PDF-103 owns print formats. |
| A3 | Model schema: every persisted type, key order, defaults, enums as numbers | **01 §4.2** (4.2.1–4.2.20) | every spec's "fields touched" section | Field *semantics* per DATA-216. |
| A4 | Data folder, `AA_DATA_DIR`, inventory, temp names | **01 §B** (DATA-010…013), §4.12, §6.2; MP.4.3 | brief; 03 §6.9; 10 §6.2 (Quick Card copies, 10:1516) | — |
| A5 | Load / save / autosave / safe mode / schema version / migration / repository swap | **01 §C** (DATA-020…036), §3.2–3.4 | 02 §2.A (REPO-001…009); 03 §D (SHELL-050…056) | Split: file I/O = 01; repository orchestration (750 ms debounce, ordered write chain, `Detach`, `Saved`) = **02 §2.A**; UI triggers (⌘S, 5-min timer, close) = **03 §D**. |
| A6 | Atomic durable write | **01 DATA-029**, §6.4 | 02 §6.2; 03 §6.9 "Atomic replace"; 14:967 | — |
| A7 | ZIP reader/writer codec | **01 §6.7** | 09 §3.10/§6.2; 10 §6.6; 11 §4.5; 13 §6.1 | In-house on `Compression` (OC-04). CRC-32 and raw DEFLATE are shared with Flash Sync (B6). |
| A8 | Bundles (`.zip`/`.aaz`), `source.json`, smart import, data-only, peek helpers | **01 §D** (DATA-040…049), §3.10, §4.4, §4.5 | 14 §3.2.7–3.2.9, §4.4; 03 SHELL-070…072, §4.4; 05 §4.2 | Menu wiring = 03. |
| A9 | Shared save file (push/poll/watch/indicator semantics) | **01 §E** (DATA-050…058), §3.12, §6.9 | 03 §I (SHELL-123…126), §3.9, §7.2 | Indicator visuals = 03 SHELL-023. Cross-OS rules also in 01 MP DATA-185 (OC-50). |
| A10 | Same-machine multi-process / instance guard | **01 Addendum MP** (DATA-160…186) | — | Amends 01 §3.27 and 03's scene list (MP.6.1/6.2). |
| A11 | Attachment storage and path rules (`ImportFile`, `ResolveFilePath`, `NormalizeFilePaths`, legacy migration, `ClassifyFile`, Windows-safe names) | **01 §F** (DATA-060…068), §3.5–3.8, §6.6 | 05 CONT-081/097, §3.5, §3.6, §4.2, §6.9; 10 §3.1.10 | File bank **UI** = 05 §2.5. |
| A12 | `settings.json` (keys, merge-on-write, Mac `UserDefaults` split) | **01 §N** (DATA-150…153), §4.3, §6.8; MP DATA-182 | 03 §4.3; 14 §4.2; 12 §4.3 | Per-key owners: DATA-218. |
| A13 | `UiState` (`Ui`) schema | **01 §4.2.20** | 03 §4.1 | Per-key owners: DATA-217. |
| A14 | Local at-rest encryption (DPAPI → Keychain AES-GCM, `AAENCM1\n`) | **01 §G** (DATA-070…073), §4.6, §6.5 | 03 SHELL-065, §6.9 | Keychain names: DATA-215. |
| A15 | App password, PBKDF2 hash, legacy `enc:` blobs | **01 §H** (DATA-080…084), §3.13, §4.7, §6.11 | 03 SHELL-101/102/161; 05 CONT-007, §4.6, §6.10 | Bytes = 01; editor migration behaviour = 05 CONT-007; dialog = 03 SHELL-161 (C6). |
| A16 | Per-item locks (service, hash format, session set) | **01 §I** (DATA-090…094), §4.8 | 04 §F (HIER-050…058), §3.14 | UI = **04 §F**; consumers of `IsGated`: 04 HIER-057/110, 02 REPO-073/102, 11 PDF-002. |
| A17 | Startup (splash, login, crash handlers, crash log, normative order) | **03 §A** (SHELL-001…014), §1.3 | 01 §A (DATA-001…005), §3.27, §6.10 | Mac launch amended by 01 MP.6.1 (instance guard first). OC-38, OC-39. |
| A18 | Keychain items | **this addendum DATA-215** | 01 §6.5, §6.8; 03 §6.9; 12 §6.9; 14 §6.3 | OC-34, OC-35. |
| A19 | Toolchain, targets, bundle id, dependency policy, language mode, type names | **ARCHITECTURE-BRIEF.md** | every "§6" | OC-04…OC-07. |
| A20 | Build, packaging (`Package.swift`, `build-app.sh`, `.app` assembly), launch environment, smoke test | **03 Addendum** (SHELL-170…207), under the brief | 01 §6.2 | — |

**DATA-203 — Shared codecs and converters.**

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| B1 | XLSX **reader** for every importer (file gate, package, worksheets, typed cells, number-format kinds, serials, 1904, strings, used range, merges, formulas, errors) **and** the three renderers (A COMPAS `CellString`, B Shippalm `Cell`/`ExcelDate`, C ports `Cell`) | **10 Addendum VESSEL-300…334** (ruling table §X.2 D1–D14; module `AACore/Xlsx`, §X.7.1; vectors §X.8) | 09 §3.3, §6.2, §7.7; 10 §3.3.1–3.3.2, §3.4.1, §6.6 "Reading", §9 Q9 | Ground truth = ClosedXML 0.104.2 as used by the Windows build. The addendum wins over 09 §6.2 and 10 §6.6 (OC-20, OC-21). The importers' header search and mapping logic stay with 09 §3.3 / 10 §3.3 / 10 §3.4. Windows: `XLWorkbook` in `CompasReader.cs:28`, `PortCallReader.cs:32`, `ShippalmReader.cs:18`. |
| B2 | XLSX **writer** (minimal SpreadsheetML over the in-house ZIP) | **09 §3.10 + §4.10** (base API and bytes of `XlsxWriter`) | 10 §6.6 "Writing"; 11 §3.6, §4.5; 06 §4.8 | Extensions required by **10 §6.6** (per-cell number type, bold header, `numFmtId 49`, column widths) for Shippalm/Ports exports whose layouts are owned by **10 §4.4/§4.5**. Checklist-only XLSX package bytes = **11 §4.5**. Sheet names: OC-22. Windows: `XlsxWriter.cs:23` and `ChecklistExporter.cs:132` hand-roll `ZipArchive`; `ShippalmReader.cs:88` and `PortsService.cs:112` use ClosedXML. |
| B3 | `XamlDOM` + cascade/computed style + `XamlReader` (XAML → NSAttributedString) + `XamlWriter` (→ XAML) | **05 §4.3** (vocabulary, grammars), **§4.3.7** (writer rules), **§6.1** (types), **§6.4** (mapping), **§7.7** (goldens), as made precise by **05 Addendum CONT-150…169** (node kinds, parent links, inheritance table, per-consumer default contexts for editor/viewer/SIRE pane/PDF, "differs from inherited" writer test, line-break provenance, loadability; vectors `XD-`) | 01 §4.11; 11 §4.3, §6.3; 12 §4.4, §6.5; 06 §4.4, §4.6; 04 §4.6; 08 §4.8; 09 §4.11 | Binding requirements *on* the owner: 01 §4.11 (byte-stable untouched bodies; lock sentinel; `#AARRGGBB`); 11 §6.3 (the PDF consumes **`XamlDOM` directly** — now CONT-150/XD.2.9); 12 §4.4 (SIRE shapes, `Segoe UI` preserved, intra-Run newline → OC-15 / CONT-166); 06 §4.4 (clone = verbatim string copy, never parse/re-emit). Plain-text consumers do **not** go through the DOM (B8). |
| B4 | HTML → XAML paste converter | **05 §3.3** (CONT-035), §7.1 | — | Output is a paste intermediate only (05 §4.3.6). |
| B5 | List engine (`ListFormatting`) | **05 §3.2** (CONT-040…046) | 05 §6.5 | — |
| B6 | CRC-32 (ISO-HDLC) and raw DEFLATE | **13 §3.2, §3.3** (FLASH-061/062); files `AACore/Util/CRC32.swift`, `RawDeflate.swift` (13 §6.1) | 01 §6.7 | Same functions serve the ZIP codec (A7). |
| B7 | Base45, fountain frames, QR generator/raster | **13** §3.1, §3.4–3.10 | — | — |
| B8 | XAML → plain text | Two functions with different semantics: **02 REPO-104** (`SearchService.PlainTextFromXaml`) and **08 §3.7** `PlainText` (DataDiff; = 01 §4.11 invariant 4) | 01 §3.15; 05 §4.3.6 | Both live in `XamlPlainText` (05 §6.1) as two named functions; never merged. |
| B9 | Link scanner (bare URLs / e-mails) | **11 §3.5.11–3.5.12** | — | PDF only. |
| B10 | Tag parsing | **04 §3.4** (HIER-027; main pane + item-window variant) | 02 REPO-106 | — |

**DATA-204 — Shared dialogs.**

| # | Windows dialog → Mac component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| C1 | `PromptWindow` → `TextPromptSheet` | **06 Addendum BUILD-136…150** (normative erratum; adopts the Windows facts of 04 HIER-130 and 03 SHELL-162) | 04 HIER-130, §6.5; 03 SHELL-162; 06 BUILD-130, §6.2; 07 VIEW-204; 08 §6.2; 10 VESSEL-046a ("WebLinkPromptSheet") | OC-08: OK is **always** enabled; raw value; Esc/⌘. cancel; label wraps. |
| C2 | `ItemPickerWindow` → item-picker sheet | **07 Addendum VIEW-208…216** (order, filter drop rule, per-caller registry VIEW-212, Mac contract) with the window layout facts of **04 HIER-131** | 04 HIER-131, §6.5, Q-13, Q-C; 06 BUILD-131, §6.2; 07 VIEW-202 quirk, §7.6; 08 QUICK-231, §6.2; 12 SIRE-030; 14 TOOLS-018 | OC-09. 06 BUILD-131 ("drops any selection") and 04 HIER-131's "Other callers" list are superseded. |
| C3 | `DatePromptWindow` → date-prompt sheet | **04 HIER-132**, §6.5 | 07 VIEW-203; 08 QUICK-230, §6.2; 02 REPO-053, §6.5 | OC-10: buttons `Clear deadline` / `Cancel` / `OK`; OK enabled; "Pick a date…" message; stays open. |
| C4 | Nullable WPF `DatePicker` → `OptionalDatePicker` | **06 §6.2** (row "WPF `DatePicker` (nullable, typeable)") | 04 §6.6 (`OptionalDateField`); 04 §6.5 and 07 §7.6 (date prompt); 08 §6.2, OQ-5 | OC-55: one control app-wide; closes 08 OQ-5. |
| C5 | `ItemLockWindow` → lock sheet | **04 HIER-058**, §6.5 | 01 DATA-090 | Hash/verify = 01 §I (A16). |
| C6 | `PasswordWindow` (Unlock / SetNew / ChangeExisting) | **03 SHELL-161** | 01 DATA-080/081; 05 CONT-062 | Semantics = 01 §H (A15). |
| C7 | `ListStylePromptWindow` → list-style sheet | **11 PDF-023** (window title `List style`, `Cancel` = Esc, never remembered, `numbered` has no default, Mac radio group) | 05 CONT-049; 06 BUILD-094 | OC-46: 05 §1's ownership claim is superseded (05 omits the title and Esc). |
| C8 | `InsertSavedListWindow` | **05 CONT-047/048**, §3.4, §7.3 | 06 BUILD-100, §4.6 | XAML shape of the inserted list = 05 (06 §4.6 is a summary). |
| C9 | `SavedListPicker.PickAndAddTasks` (Board "+ From saved list", Planner "+ Saved list") | **07 VIEW-202** (+ VIEW-214 order) | 05 CONT-050; 06 BUILD-101 | OC-47. `ItemToTask` semantics = 02 REPO-144. |
| C10 | `ContainerViewerWindow` (read-only "View — {title}") | **04 HIER-136**, §6.8 | 05 CONT-098; 06 BUILD-076 | OC-12 (missing-file path). |
| C11 | `ComponentEditorWindow` | **04 HIER-071**, §6.5 | 05 §1 table | — |
| C12 | `TabColorsWindow` | **03 SHELL-029**, §6.7 | — | — |
| C13 | `MessageBox` → `NSAlert` (Yes/No → verbs; destructive default = Cancel) | **03 §6.5** (alert button mapping) | 01 §6.10; 04 §6.5; 06 §6.2 | Each alert's *text* is owned by the spec that owns the flow. |
| C14 | File dialogs (`SaveFileDialog`/`OpenFileDialog` → `NSSavePanel`/`NSOpenPanel`) | Default names, filters and titles: the spec owning each flow; parameter catalogue **03 App. A.5** | 01 §6.10; 04 §6.5 | — |

**DATA-205 — Batch menus and selection rules** (the "batch-actions spec").

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| D1 | `BatchDone.SetDone/SetDoneAll` (what "done" means per type; returns true only on real change) | **02 REPO-042** (§2.E) | 04 §3.11; 07 §2.3, VIEW-200; 08 QUICK-051 | — |
| D2 | "✓ Mark selected as done / ○ … not done" menu entries | **04 HIER-133** | 02 REPO-043; 06 BUILD-038; 07 VIEW-200; 08 QUICK-050/051/079 | Persist: `MarkDirty(); FlushIfDirty()` only when n > 0; always refresh. |
| D3 | `BatchDeadline.SetDeadline/SetDeadlineAll` (+ `WorkRange.Coerce`) | **02 REPO-052** (§2.F) with **REPO-050** | 04 §3.12, §3.3; 06 BUILD-A6; 07 VIEW-201 | — |
| D4 | "📅 Set deadline for selected…" menu + date prompt flow | **04 HIER-134** (+ C3) | 02 REPO-053, §6.5; 07 VIEW-201; 08 QUICK-052 | OC-10. |
| D5 | `BatchDelete` (`TopLevel`, `Describe`, `KindBreakdown`, `TrashAll`) | **02 REPO-073/074** (§2.H) | 04 §3.13 | — |
| D6 | Confirm-then-trash flow, prompt text, post-delete status line | **04 HIER-135** (dialog) with **02 REPO-075** (identical text + step 5 status line) | 04 HIER-022/023 | The two texts are identical; if they ever diverge, 04 wins for the dialog, 02 for the status line. |
| D7 | Right-click selection rule (`RightClickSelect`) | **02 REPO-043** | 04 HIER-017; 07 §2.5; 08 QUICK-050 | Mac: `.contextMenu(forSelectionType:)` (02 §6.5). |

**DATA-206 — Trash, undo, activity log, change preview.**

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| E1 | `TrashedItem` JSON + `PayloadJson` serializer options | **01 §4.2.16, §4.10** | 08 §4.7; 09 §4.6 | — |
| E2 | Trash operations: trash top-level/crew/batch, restore, purge, empty, prune (200 / 90 days), `PurgeReferences`, hard-delete paths | **02 §2.H** (REPO-070…081), §3.1.5 | 01 §K (DATA-110…114), §3.17; 08 §3.6 | — |
| E3 | Trash window | **08 §2.6** (QUICK-170…178), §6.2-F | 01 DATA-113; 02 REPO-078, §6.4; 03 SHELL-064, §6.10 | OC-19 (sheet; Windows wording). |
| E4 | Undo last delete (Ctrl+Z → ⌘Z) | Operation **02 REPO-077**; dispatch, menu item and titles **03 SHELL-047 + §6.5** | 01 DATA-112, §6.10; 02 §6.4; 04 HIER-024/123, §6.9; 08 QUICK-178, §6.1; 09 CREW-062; 10 VESSEL-285 | OC-14. |
| E5 | `LogEntry` model and 10 000 cap | **01 §4.2.17**, DATA-115 | 08 QUICK-156 | — |
| E6 | Logging API (`LogAdded/LogRemoved`) and Kind catalogue | **02 §2.I** (REPO-090/091) | producer tables (E7) | — |
| E7 | Log entries produced by a feature (Action/Kind/Name/Detail per call site) | **The producing spec** (04 HIER-141; 06 BUILD-135; 08 §4.5; 09 §4.7; 10 §4.3; 12 SIRE-046; 02 REPO-091 for repository-level calls) | 02 REPO-091 | The producer cites the call site, so it wins over the compiled catalogue; 02 REPO-091 must be corrected to match. |
| E8 | Activity-log window + CSV export | **08 §2.5** (QUICK-150…156), §4.6, §6.2-E | 02 REPO-092, §4.9, §6.8; 03 SHELL-095 | OC-17, OC-18. |
| E9 | `DataDiff.Compare` (tree, texts, ordering) | **08 §3.7** (+ QUICK-194/195) | 01 §3.15, §7.8 | OC-13 (duplicate keys; link order). |
| E10 | Review sheet (`DiffWindow`), `ReviewAndConfirmImport`, fallback confirm | **08 §2.7** (QUICK-190…193), §6.2-G | 01 DATA-100/104, §6.10; 03 SHELL-120, §3.7; 14 TOOLS-027 | OC-37: button text is `Import (overwrite)` (Windows), not "Import (Overwrite)" (01 §6.10). |
| E11 | `AgeVerdict` strings | **08 QUICK-196** | 01 DATA-101, §3.16; 14 §3.2.6; 03 §3.7 | — |

**DATA-207 — Windows and panes.**

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| F1 | Item windows / multi-window (registry, detach/reattach, one per item, reload safety, delete closes, flush, rename propagation) | **04 §L** (HIER-110…117), §6.7 | 03 SHELL-054/143, §6.10; 05 CONT-008/009, §6.12; 10 VESSEL-005; 02 REPO-076 | — |
| F2 | Flush registry + one-editor-per-container registry | **One type, `EditorFlushCenter`**: lifecycle per **04 §6.7**, binding rules per **05 §6.12** (CONT-008) | 03 SHELL-054; 12 §6.4 (SIRE body flush) | OC-42, OC-43. |
| F3 | Container editor (rich text, lists, text lock, file bank) | **05 §2** (CONT-001…098) | 04 HIER-043; 06 §B/§E hosts | — |
| F4 | Floating due-dates window | **08 §2.1** (QUICK-001…025), §6.2-A | 02 REPO-044/114; 03 SHELL-092, §6.10; 09 CREW-090 | OC-31. |
| F5 | Quick work (Ctrl+N) | **08 §2.2** (QUICK-040…084) | 06 BUILD-102; 07 VIEW-153 (bucket UI) | — |
| F6 | Quick switcher (Ctrl+O) | **08 §2.3** (QUICK-100…107), §3.3, §6.2-C | 02 REPO-107, §6.6; 03 SHELL-043 | OC-53. |
| F7 | Global search | Service **02 §2.J** (REPO-100…106), §3.2; window **08 §2.4** (QUICK-120…125), §6.2-D | 03 SHELL-041; 04 HIER-057 | OC-11, OC-17, OC-54. |
| F8 | Crew table window | **09 §I** (CREW-100…106) | — | — |
| F9 | Flash Sync window | **13 §2.1–2.3**, §6.6 | 03 SHELL-081, §6.10 | — |
| F10 | Tool windows (Folder builder, Date calculator, Unit converter) | **14 §2.E–2.G** | 03 SHELL-090/091/096 | — |
| F11 | Read-only viewer | see C10 | | |

**DATA-208 — Shell cross-cutting.**

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| G1 | Keyboard shortcuts and menu bar (titles, placement, key equivalents, responder rules) | **03 §C** (SHELL-040…048), §E–H (SHELL-060…115), App. A.2, **§6.4, §6.5**, as consolidated in **DATA-214** | 01 §6.10; 02 §6.4/§6.6; 04 §6.9; 05 §6.3; 06 §6.2; 07 §7.1–7.3, §7.6; 08 §6.1; 09 §6.4; 10 §6.8; 11 §6.2; 12 §6.3; 13 §6.6; 14 §6.6 | OC-23…OC-30, OC-40. The "global Commands spec" of 11:1221. |
| G2 | Status line | **03 SHELL-022** | every spec's status strings | Strings are owned by the feature that posts them. |
| G3 | Theme tokens, fonts, semantic colours, dark mode | **03 §L** (SHELL-150…159), §6.6; brief "Visual language" | every spec's dark-mode note | "The owning spec" of 03:1573 = the feature spec that uses the colour (e.g. 07 planner blocks, 08 diff glyphs, 09 contract colours, 10 card palette). |
| G4 | Tabs: 13 tab ids, order drag, colours, crew badge | **03 SHELL-025…031** | 04 §1.2; 07 §1; 09 CREW-001/002 | Tab ids are data (01 §4.2.20). |
| G5 | Navigation (`NavigateToItem`, `NavigateToCrew`, `RefreshAfterRestore`, `RefreshHierarchyPages`) | **03 §K** (SHELL-140…144) | 04 HIER-120; 08 QUICK-210 | — |
| G6 | Reminders and daily digest | Computation **02 §2.K** (REPO-110…114), §3.3; surfaces, timers, notification, menu-bar extra **03 §J** (SHELL-130…133), §6.8 | 02 §6.7; 08 §6.5; 09 §6.4, CREW-092 | OC-33. The "reminders spec". |
| G7 | Crew expiry surfaces | **09 §E** (CREW-050…053) | 03 SHELL-030/098/133 | — |
| G8 | Window geometry / per-page UI state capture | **03 SHELL-032/033**, §6.3 | 04 HIER-121; 07 VIEW-020; 08 QUICK-006 | Per-key semantics: DATA-217. |
| G9 | Settings scene (⌘,) and Mac-only preferences | **03 §6.4** (row "Settings…") for the scene; **01 §6.8** for storage (UserDefaults vs `settings.json`) | 12 §6.9; 14 §6.3 | OC-52: 01 §4.14 rule 10's `settings.mac.json` alternative is not used. |
| G10 | One main window per process | **01 MP DATA-186** | 03 §6.1 | — |

**DATA-209 — Sync.**

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| H1 | Shared save file | see A9 | | |
| H2 | Google Drive: synced-folder copy, OAuth client + sign-in, scopes, token store, upload/list/download, restorable names, real-time sync, decline memory | **14 §2.A–2.D** (TOOLS-001…035), §3.1, §3.2, §6.2–6.5 | 01 DATA-073, §4.9, §6.5 (token paragraph); 03 SHELL-010/011/073…080/121/122, §3.8 | OC-34 (token storage). Menu *titles* = 03 §6.4. |
| H3 | Flash Sync protocol, change sets, baseline, window | **13** (FLASH-001…135) + `QR_SYNC_PROTOCOL.md` | 01 DATA-049, §4.2.20 "Flash Sync" column; 03 SHELL-081 | `DataStore.ApplySyncedData` file-level steps = **01 DATA-049**; the per-device `Ui` key list = **13 §3.11.1** (01's column is a copy). |

**DATA-210 — Domain components.**

| # | Component | Owner | Also described in | Split / notes |
|---|---|---|---|---|
| I1 | Hierarchy pages | **04** | 11 §1.2 | — |
| I2 | Relationships (two-way links, backlinks, auto-links, scrubbing) | Ops **02 §2.C** (REPO-020…031); UI **04 §G** (HIER-060…064) | 01 DATA-137 | Map rendering = **07 §3.5**. |
| I3 | Sidebar groups | Ops **02 REPO-120**; UI **04 §D** (HIER-010…015, 030…034) | 01 DATA-136 | — |
| I4 | Task `Status` ⇄ `IsComplete` + order-independent load rule | **01 DATA-130 + §4.2.6** | 02 REPO-040/041; 07 §2.3 | — |
| I5 | `WorkRange.Coerce` and range editors | **02 REPO-050/051** | 04 §3.3; 06 BUILD-A6 | Texts agree. |
| I6 | Recurrence regeneration | **02 §2.G** (REPO-060…064) | 01 §L, §3.18; 04 §3.10; 03 SHELL-055 | The "repository spec" of 04:852. |
| I7 | Checklist builder control (bulk add, insert, reorder, move-to, delete, save/load/manage lists) | **06 §A** (BUILD-001…019) | 09 CREW-075; 04 HIER-091; 08 QUICK-075…081 | The "checklist spec" of 09:377. |
| I8 | Checklist step editor | **06 §B** (BUILD-020…025) | 09 CREW-075; 07 VIEW-014 | — |
| I9 | Procedure "Checklist Steps" area (grid, + Step, Remove, Link tasks/equipment, + New task, context menu, export buttons) | **06 §C** (BUILD-030…040) | 04 HIER-091…096 | OC-48. Procedure fields above it = **04 HIER-090**. |
| I10 | Subtask builder / subtask editor | **06 §D/§E** (BUILD-041…057) | 04 HIER-084…087; 07 VIEW-014/049 | — |
| I11 | Saved lists: "full copy" semantics and service | **02 §2.N** (REPO-140…147) for the service; **06 §F** (BUILD-060…064) for user-visible semantics | — | — |
| I12 | Saved Lists tab | **06 §G** (BUILD-070…096) | 11 §2.3 | Export flows: I19. |
| I13 | Saved-list arrangement (`GroupSpan`, `Nudge`, `MoveTo`, `GroupEntries`, `AllEntries`) | **02 §2.M** (REPO-130…136) with defect fix D-1 | 06 BUILD-A7…A9, §7.4 | OC-16. |
| I14 | Schedule builder control and `.aasched.json` | UI **06 §I** (BUILD-110…125); file format **06 §4.5**; service **02 §2.O** (REPO-150…155) | 09 §H (CREW-080…086), §4.8; 01 §4.13 | OC-41, OC-49. |
| I15 | Buckets | **07 §3.4** (VIEW-140…155) | 08 QUICK-053/054/231; 07 Addendum VIEW-213 | Assignment UI lives in 08; its order rule is VIEW-213. |
| I16 | Calendar, Board, Planner, Relationship Map | **07** | 02 REPO-031 | — |
| I17 | Crew (COMPAS import, `DateResolver`, `CrewMember.ParseDate`, cards, editor, table, XLSX export) | **09** | 01 §3.23 (DATA-135); 10 §6.7 | `ParseDate` is shared by Shippalm text dates (10 Q13); any change is a 09 decision. |
| I18 | Vessel dashboard (Quick Cards, card editor, Work Orders, Ports, Ports DB); maritime icon set and card palette | **10** (VESSEL-001…285; §4.6, §4.7) | 03 SHELL-157, App. C; 04 HIER-100 | OC-51. |
| I19 | PDF and checklist exports: item PDF, checklist-only PDF/XLSX, saved-lists PDF, rich text → PDF | **11** (PDF-001…105) | 04 HIER-044/092, §3.9; 06 BUILD-039/040/091…096, §4.7–4.9, BUILD-A17 | OC-44, OC-45. |
| I20 | SIRE (incl. Gemini key and `SireFlow` XAML) | **12** | 02 REPO-030; 03 SHELL-099/100 | Gemini Keychain item: DATA-215. |
| I21 | Text lock (protect highlighted text) | **05 §2.4** (CONT-060…066), §4.4 | 01 §4.11 invariant 2 | — |
| I22 | File bank UI | **05 §2.5** (CONT-080…098) | 10 §3.1 (Quick Card targets) | Storage = A11. |
| I23 | Tools (Folder builder, Date calculator, Unit converter) | **14 §2.E–2.G** | 03 §F | — |
| I24 | Tags parsing | see B10 | | |

#### P.3 Cross-references

**DATA-211 — The ten dangling references named by the task.** Each "the *X* spec" below has no file of that name.
Its concrete target:

| XR | Where | Text | Resolves to |
|---|---|---|---|
| XR-01 | 06:295 (BUILD-038) | "(Specified in the batch-actions spec.)" | Menu entries and flow: **04 §N HIER-133** (done) and **HIER-134** (deadline); services: **02 §2.E REPO-042** and **02 §2.F REPO-052** (+ REPO-050 `WorkRange`); date dialog **04 HIER-132** with OC-10; right-click rule **02 REPO-043**. Summary in 07 VIEW-200/201. Batch **delete**: 02 §2.H REPO-073…075 + 04 HIER-135. |
| XR-02 | 02:561 (REPO-076) | "anything holding the old reference is dead — see the multi-window spec" | **04 §L HIER-114** (windows hold ids and re-resolve after every reload/restore) and **HIER-112** (detach/reattach); Mac: **04 §6.7** (orphaning by `store.item(id:)` on every render). |
| XR-03 | 01:629 (DATA-115) | "(Viewer window owned by the tools spec.)" | **08 §2.5 QUICK-150…156** (+ §4.6 CSV, §6.2-E); menu item 03 SHELL-095. Not spec 14 ("Drive & Tools"), which owns only the three tool windows. |
| XR-04 | 06:607 (BUILD-102) | "(Owned by the quick-work spec…)" | **08 §2.2**: QUICK-075…079 (children builder), **QUICK-080** (save as reusable list), **QUICK-081** (load a saved list). |
| XR-05 | 11:1221 (§6.2) | "⌥⌘E … (coordinate with the global Commands spec)" | **03 §6.4/§6.5** as consolidated in **DATA-214**; ⌥⌘E is registered there for File ▸ Export as PDF…. |
| XR-06 | 09:377 (CREW-075) | "full spec lives in the checklist spec" | **06 §A BUILD-001…019** (crew host = BUILD-019), step editor **06 §B BUILD-020…025**; `ChecklistStep` JSON **01 §4.2.8**. |
| XR-07 | 09:1333 (§6.4 "Undo") | "…'undo last delete' … from the Trash spec" | Crew soft delete **02 REPO-071**; undo **02 REPO-077**; ⌘Z routing **03 SHELL-047 + §6.5**; Trash window **08 §2.6**; Clear All (hard, not undoable) **02 REPO-081**. |
| XR-08 | 14:423 (TOOLS-027) | "(`DiffWindow`, owned by the import-review spec)" | **08 §2.7 QUICK-190…196**, algorithm **08 §3.7**, Mac sheet **08 §6.2-G**. |
| XR-09 | 04:547 (HIER-100) | "Panel behaviour is owned by the vessels spec." | **10 §A–§E**: hosting VESSEL-001…007, Quick Cards VESSEL-010…028, card editor VESSEL-040…055, Work Orders VESSEL-100…123, per-vessel Ports VESSEL-200…212; Ports DB VESSEL-250…256. |
| XR-10 | 11:1150 (§5.3 table) | "Owned by the rich-text/XAML converter spec." | **05 §4.3** (+ §4.3.7 writer rules), **§6.1** (`XamlDOM`, `XamlReader`, `XamlWriter`), **§6.4** (mapping), **§7.7** (goldens), and **05 Addendum CONT-150…169** (the normative DOM, cascade and per-consumer defaults; the PDF projection is its §XD.2.9). The PDF pipeline consumes `XamlDOM` directly, never the `NSAttributedString`. |

**DATA-212 — Every other named cross-reference (glossary).** Found by the multi-line scan (OWN.3.4). Line numbers
are at the time of writing. "Generic" rows name no spec and need no fix, but are listed where a reader would ask
"which one?".

| Where | Phrase | Target |
|---|---|---|
| 01:24 | "the main-window spec" | 03 SHELL-022 (status line), §6.2 |
| 01:67 | "the protocol itself is another spec" | 13 + `QR_SYNC_PROTOCOL.md` |
| 01:82 | "(Drive spec)", "(Flash Sync spec)" | 14 §2.A–2.D; 13 §2.1 |
| 01:218, 01:225 | "Drive spec" | 14 TOOLS-024 (background check); TOOLS-021 (push on save) |
| 01:248, 01:1006, 01:1966 | "Flash Sync spec" | 13 FLASH-105 (apply pipeline); 13 §3.11.5–3.11.7 (settings merge); 13 §4.2 |
| 01:343 | "(Drive spec)" | 14 TOOLS-006, §4.5 (file names, properties) |
| 01:487, 01:1852 | "Drive spec" | 14 TOOLS-012, §4.3, §6.3 (token store) |
| 01:529 | "hierarchy spec" | 04 §F HIER-050…058 |
| 01:553 | "owned by other specs" | `IsGated` consumers: 04 HIER-050/057/110; 04 HIER-135 + 02 REPO-073; 11 PDF-002; 02 REPO-102 + 08 QUICK-123 (name **and** tags, OC-11) |
| 01:621 | "UI may be owned by another spec" | 08 §2.6 |
| 01:699 | "Drive spec" | 14 TOOLS-004/005 |
| 01:1340 | "DateResolver spec" | 09 §3.6 |
| 01:1389 | "Drive spec" | 14 TOOLS-011 (re-consent), TOOLS-024 |
| 01:1391 | "reminders spec" | 03 §J (SHELL-130…133), §6.8; computation 02 §2.K |
| 01:1764 | "calendar spec" | 07 VIEW-020 |
| 01:1777–1778 | "crew spec" | 09 CREW-104 |
| 01:1914, 01:1930, 01:2252 | "rich-text spec", "XAML↔NSAttributedString spec" | 05 §4.3, §4.3.7, §6.4 (+ OC-15) |
| 02:146, 02:1831 | "persistence spec" | 01 DATA-029, §3.3, §6.4, §6.5 |
| 02:178 | "persistence/shell spec" | 01 DATA-026…028 and 03 SHELL-050…056 |
| 02:294 | "SIRE spec" | 12 §3.7 (`SireToAa`) |
| 02:298 | "Map spec" | 07 §3.5 (VIEW-175…178) |
| 02:368 | "Floating-window spec" | 08 §2.1 |
| 02:775 | "(own spec)" | 08 §2.1 QUICK-012…018 |
| 02:789 | "the hierarchy spec" | 04 HIER-013, HIER-015 |
| 02:1491 | "(persistence spec)" | 01 §4.1, DATA-024 — superseded by OC-02 |
| 02:1527 | "the data-model spec" | 01 §4.2 |
| 02:1715 | "the rich-text spec" | 05 §4.3.7 |
| 03:493 | "owned by another spec" | 08 §2.6 |
| 03:621 | "owned by another spec" | 08 §2.1 |
| 03:745 | "crew spec" | 09 CREW-039, CREW-050 |
| 03:1096 | "editor spec" | 05 CONT-004 (400 ms debounce) |
| 03:1168 | "persistence/hierarchy specs" | format 01 §4.2.16/§4.10; operations 02 §2.H |
| 03:1169 | "other specs" | DATA-216 |
| 03:1212 | "persistence spec" | 01 §4.4, §4.5 |
| 03:1228 | "container-editor spec" | 05 §4.3 |
| 03:1381 | "hierarchy spec" | 04 §6.1, §6.2 |
| 03:1573 | "the owning spec" | the feature spec that uses the colour (G3) |
| 03:1666 | "the persistence spec" | 01 §6.5 |
| 03:1849 | "Drive spec" | 14 TOOLS-006, §4.5 |
| 03:1856 | "persistence spec" | 01 D-7, §6.8; 12 SIRE-038 |
| 04:53, 04:83 | "main-shell spec" | 03 SHELL-025…029/045; Trash window 08 §2.6; undo 03 SHELL-047 |
| 04:79, 04:1033 | "container-editor spec" | 05 (XAML: §4.3, §6.4) |
| 04:80, 04:478 | "builders/editors spec", "builders spec" | 06 (§D for the subtask builder) |
| 04:81, 04:978 | "vessels spec" | 10 (fields: §4.2) |
| 04:82, 04:1023 | "export spec" | 11 (PDF-004 file name) |
| 04:362 | "search spec" | 02 REPO-102 (+ OC-11) |
| 04:852 | "the repository spec" | 02 §2.G |
| 04:961 | "container spec" | 05 §4.1; 01 §4.2.3 |
| 04:1014 | "models spec" | 01 §4.2.6 (read-order rule) |
| 04:1129, 04:1174 | "if the other specs agree", "if every other spec does the same" | OC-36 |
| 05:66 | "the hierarchy spec (HIER-136)" | 04 HIER-136 |
| 05:829 | "the persistence spec" | 01 §D, §4.5 |
| 06:64, 06:251 | "the hierarchy spec" | 04 HIER-090 (+ OC-48) |
| 06:592, 06:995 | "the rich-text spec" | 05 CONT-047/048, §3.4, §4.3, §7.3 |
| 06:959 | "see hierarchy spec for full shape" | 01 §4.2.6 (schema); 04 §4.2 (fields used) |
| 06:1070 | "see PDF spec" | 11 §2.6, §3.5 |
| 06:1128, 06:1208 | "container spec" | 05 §6.1; 05 §6.9 + 01 §6.6 |
| 06:1373 | "Crew spec" | 09 CREW-035, §8 Q3 (already adopted there) |
| 07:72 | "the main-window spec" | 03 SHELL-025…029, SHELL-045 |
| 07:130 | "the model spec" | 01 DATA-130; 02 REPO-041 |
| 07:769 | "owned by other specs" | 06 §B, §E |
| 07:1057 | "the models spec" | 01 §4.1.3 |
| 07:1096 | "the model spec" | 01 §4.1.5, App. A |
| 07:1296 | "the editor spec" | 06 §6.2 (sheet or `Window` scene), §B, §E |
| 08:1254 | "(reminders spec)" | 03 §6.8 (+ 02 §2.K) |
| 09:1016 | "checklist spec" | 06 §A; 01 §4.2.8 |
| 09:1187 | "the rich-text editor spec" | 05 §4.3 |
| 09:1327 | "(Owned by the reminders spec…)" | 03 §J, §6.8; crew suffix 02 REPO-110/111 |
| 10:47 | "the container spec" | 05 |
| 10:769 | "unless those specs extend it" | 02 §2.J (search) and 08 §2.7 (diff): neither extends; parity stands |
| 10:1280 | "the activity-log spec" | schema 01 §4.2.17; API 02 §2.I; viewer 08 §2.5 |
| 10:1516 | "the persistence spec" | 01 §6.2 |
| 10:1635, 10:1638, 10:1918 | "the crew spec" | 09 §3.1, §6.3, §7.1 |
| 10:1654 | "the main-window spec" | 03 §6.5 |
| 10:1656 | "the global spec" | 03 §6.4 + DATA-214 |
| 11:481 | "the data-model spec" | 01 §4.1.5 |
| 11:1226 | "the rich-text spec" | 05 §6.1 `XamlDOM` (+ 11 §6.3 requirements) |
| 12:826, 12:991 | "the rich-text spec" | 05 §4.3.7, §6.2, §6.4 (+ OC-15) |
| 12:956, 12:959 | "shell spec" | 03 §6.4/§6.5 + DATA-214 (+ OC-27) |
| 14:105 | "identity spec" | 01 DATA-048 (+ 03 SHELL-068) |
| 14:107 | "(persistence spec)" | 01 DATA-012, DATA-040, DATA-043 |
| 14:121 | "(Flash Sync spec)" | 13 FLASH-001 |
| 14:129 | "the rest belong to other specs" | 03 §F; 09 CREW-003/004; 12 SIRE-036/038; 03 SHELL-101/102 + 01 §H |
| 14:967, 14:1514 | "persistence spec" | 01 §6.4; 01 §6.5 + DATA-215 |
| 14:1339 | "repository/persistence spec" | 01 §4.2 |
| 14:1441 | "import-review spec" | 08 §2.7 |
| 14:1551, 14:1560, 14:1615, 14:1865, 14:1872 | "shell spec", "shell/theme spec" | 03 SHELL-022; 03 §6.4; 03 §6.6 |

#### P.4 Conflict register

**DATA-213 — Rulings.** Each entry: the texts in conflict, the ruling, and why. "Supersedes" names the text that
loses. Rulings marked **[verified]** were settled by re-reading the C# at the cited lines. The `OC-nn` numbers are
stable identifiers (OC-01…OC-56, all used), grouped here by theme rather than listed in numeric order.

*Architecture and JSON*

* **OC-01 — JSON string escaping.** 02 §4.1 (row "String escaping": the Swift writer "MAY emit raw UTF-8") vs
  01 §4.1.7 ("SHOULD emulate") vs the brief ("Output uses the default System.Text.Json escaping … so files diff
  cleanly"). **Ruling:** the writer MUST emit the default `JavaScriptEncoder` escaping exactly as 01 §4.1.7 lists it:
  every non-ASCII character, the double quote, ampersand, apostrophe, plus sign, less-than, greater-than and backtick
  as `\uXXXX` (uppercase hex; surrogate pairs for non-BMP), backslash as `\\`, the five short escapes, other controls
  as `\u00XX`. Readers accept any valid escaping. Supersedes 02 §4.1.
* **OC-02 — Unknown members.** 02 §4.1 ("Dropped on item types … do not invent item-level extension data") and
  01 §4.14 rule 2 ("unknown nested keys (SHOULD)") vs the brief ("preserves them on *every* object"). **Ruling:**
  MUST preserve unknown members on every object, re-emitted after the known keys (DATA-024 placement). Supersedes
  02 §4.1 and the SHOULD in 01 §4.14.
* **OC-03 — `Codable` for persisted data.** 02 §4.1 ("Swift `CodingKeys` MUST use the exact C# names"), 02 §6.10
  (`JSONEncoder .prettyPrinted` for `.aasched.json`), 09 §6.1 ("`CrewMember` (Codable …)"), 12 §5.3 ("`AppData`
  Codable") vs 01 §6.1 and the brief (`JSONValue` + explicit `init(json:)` / `json`; "not synthesized Codable").
  **Ruling:** every `data.json`, `settings.json`, `source.json`, Trash payload, Flash Sync tree and `.aasched.json`
  goes through the 01 JSON layer. `Codable` is allowed only for read-only bundled resources (the SIRE question bank,
  12 §4.1) and Mac-private files that never leave the Mac.
* **OC-04 — Third-party packages.** 01 §1.3 and §6.7 (ZIPFoundation), 09 §6.2 (ZIPFoundation via SPM), 10 §6.6
  (CoreXLSX, ZIPFoundation, XMLCoder) vs the brief ("No third-party dependencies") and 13 §6.1. **Ruling:** in-house
  ZIP on `Compression` (`COMPRESSION_ZLIB` = raw DEFLATE) + the shared CRC-32; in-house XLSX reader on `XMLParser`.
  The functional requirements in 01 §6.7 still apply; for XLSX reading, 10 Addendum §X.2 D13 reaches the same
  conclusion and its contract replaces 09 §6.2 / 10 §6.6.
* **OC-05 — Language mode.** 03 §6 header ("strict concurrency"), 02 §6.1, 08 §6.3, 09 §6.1, 12 §6.1 vs the brief
  (Swift language mode 5 for all targets; UI and stores `@MainActor`). **Ruling:** language mode 5. The specs'
  concurrency *designs* (immutable snapshots for background search, diff and imports; FIFO writer actor) still
  apply as design rules; the compiler just does not enforce them.
* **OC-06 — Repository type name.** 01 §6.1 and App. A (`AppRepository`) vs the brief (`AppStore` "the repository")
  and 04 §6.7 (`AppStore.detachedItemIDs`). **Ruling:** the Swift type is `AppStore`. Every spec reference to
  `AppRepository` means `AppStore` on the Mac; the C# name stays in Windows citations.
* **OC-07 — Mac-private reverse-DNS identifiers.** 01 §6.7 (`com.bepavida.aa.bundle`) and 01 MP.6.2
  (`com.bepavida.aa.InstanceRequest`) vs the brief's bundle id `com.eriskay.aa` and 12 §6.9 (`{bundleID}.gemini`).
  **Ruling (SHOULD):** derive every Mac-private identifier from the bundle id, defined once in
  `AACore/Identifiers.swift`: UTType `com.eriskay.aa.bundle` (extension `aaz`, conforms to `public.zip-archive`),
  distributed notification `com.eriskay.aa.InstanceRequest`, Keychain service `com.eriskay.aa.gemini`. None of these
  is written to `data.json` or bundles, so the choice has no Windows impact. If the lead keeps `com.bepavida`, change
  the bundle id instead, so there is still only one prefix (Q-OWN-3).

*Shared dialogs*

* **OC-08 — Prompt sheet OK button.** 06 §6.2 ("OK (↩, disabled while blank)") vs 04 HIER-130, 04 §6.5, 03 SHELL-162.
  **Ruling:** already settled by 06 Addendum BUILD-137 (OK always enabled; five callers give blank a meaning) —
  recorded here so verifiers find it. [verified `PromptWindow.xaml.cs:5-20`]
* **OC-09 — Item picker filtering and result order.** 06 BUILD-131 ("changing the filter … drops any selection"),
  07 VIEW-202 quirk and §7.6 ("list order") vs 04 HIER-131 ("in selection order"; "drops the selection of rows that
  are filtered out"). **Ruling:** already settled by 07 Addendum VIEW-208…216 (selection order; only hidden rows
  lose selection on Windows; the Mac keeps hidden selections in place; per-caller registry VIEW-212). 04 HIER-131
  stays authoritative for window layout (title `Pick items`, 500×500, bold prompt, search box, `Cancel`/accent
  `OK`); its "Other callers" sentence is superseded by VIEW-212. [verified `ItemPickerWindow.xaml.cs:26-51`]
* **OC-10 — Date prompt on the Mac.** 02 §6.5 ("Clear Deadline", "Cancel", "Set" (default) … "the Set button can
  simply be disabled until a date is chosen") and 07 §7.6 ("disabled or alerting when no date … or disable OK until
  picked") vs 04 HIER-132/§6.5, 07 VIEW-203, 08 QUICK-230/§6.2 (buttons `Clear deadline` / `Cancel` / `OK`; OK with
  no date shows `Pick a date, or use "Clear deadline" to remove it.` titled `Set deadline`; the sheet stays open).
  **Ruling:** 04. OK keeps its Windows label and is always enabled; the date control has an explicit "no date" state
  (OC-55) so the message stays reachable; the message is shown. Same philosophy as OC-08: the Mac does not replace a
  Windows message with a disabled button.
* **OC-55 — Optional date control.** 04 §6.6 (`OptionalDateField`: shows `—` + "Set…"; when set, a compact
  `DatePicker` plus a clear button) vs 06 §6.2 (`OptionalDatePicker`: `DatePicker(.field)` + clear button + "no date"
  state; greyed ranges via `in:`) vs 08 OQ-5 (open). **Ruling:** one component named `OptionalDatePicker`, owned by
  06 §6.2 (including the `in:` range limits used by start/deadline pairs), whose empty state renders as 04 describes
  (`—` + "Set…"). Every nullable date in the app (task, procedure and step deadlines, range start, date prompt,
  crew editor dates, schedule add row) uses it. Closes 08 OQ-5.
* **OC-12 — Viewer "missing file" path.** 04 HIER-136 and 06 BUILD-076 (`"That file is missing:\n\n{path}"`) vs
  05 CONT-098 (`{target}`). **Ruling [verified `ContainerViewerWindow.xaml.cs:90-96`]:** the placeholder is the
  **resolved** path — `f.IsLink ? f.Path : DataStore.ResolveFilePath(f.Path)` — i.e. the absolute location on this
  machine, not the stored `files/<32hex>_name`. The same `target` appears in `"Could not open:\n\n{target}\n\n{error}"`.
  04 HIER-136 remains the owner; read its `{path}` as this resolved path.
* **OC-46 — List-style prompt ownership.** 05 §1 ("The subsystem also owns … the List style prompt") vs 11 PDF-023
  (complete contract incl. window title `List style`, `Cancel` = `IsCancel`, never remembered). **Ruling:** 11
  PDF-023 owns it; the texts agree otherwise.
* **OC-47 — Saved-list-to-tasks picker ownership.** 05 §1 and CONT-050 vs 06 BUILD-101 vs 07 VIEW-202. **Ruling:**
  07 VIEW-202 (+ VIEW-214), the most complete text, whose two callers (Board, Planner) are 07's.

*Services and algorithms*

* **OC-11 — What search reads for a locked item.** 04 HIER-057 ("global search indexes only its name") vs 02 REPO-102,
  08 QUICK-123, 01 DATA-094 (name **and** tags). **Ruling [verified `SearchService.cs:63-73`]:** Name and Tags are
  searched (tags "carry no protected content"); description, notes, files and child content are skipped. 04
  HIER-057's phrase is superseded.
* **OC-13 — DataDiff duplicate file keys and link order.** 01 §3.15 + D-10 (use count-aware multiset semantics) vs
  08 §3.7 + Q-8 ("keep last, never crash"). Windows throws in `ToDictionary` (`DataDiff.cs:172-173`). **Ruling:**
  count-aware, per 01 D-10: for each key `Name|Path`, `k = count(b) − count(a)`; emit `k` `Added "file: {Name}"`
  nodes when `k > 0`, `−k` `Removed` nodes when `k < 0`, in first-occurrence order (b's for added, a's for removed).
  With no duplicates this is identical to Windows. "Keep last" would hide the removal of one of two identical
  links. `DiffLinks` order: [verified `DataDiff.cs:241-247`] `ToHashSet()` over a sequence with no removals
  enumerates in insertion order in .NET, so "b's enumeration order" (08) and "collection order" (01) are the same
  rule: first occurrences in collection order, de-duplicated.
* **OC-16 — Saved-list `Nudge` with several picks in an interleaved group.** 06 BUILD-A7 gives the Windows algorithm
  as the Mac pseudo-code ("fuzz-verified" only for permutation and other-group invariants) vs 02 REPO-132 + §8 D-1
  (defect; fix recommended) and 02 §6.9 ("use the fixed nudge"). **Ruling [verified by simulating
  `SavedListOrder.cs:30-47`]:** 02 wins. `A(g) X(h) B(g) C(g)`, `nudge([B, C], up)`: Windows gives group order
  `B A C` (intended `B C A`); `A(g) B(g) X(h) C(g)`, `nudge([A, B], down)`: Windows gives `A C B` (intended `C A B`).
  The Mac implements the fixed nudge (compute the intended group order by swapping each pick with its group
  neighbour, then re-anchor exactly like `MoveTo`'s final loop). Tests assert **per-group subsequences** (02 §7.9).
  Consequence for 06 §7.4 row 2 (`A(g1) X(g2) B(g1) C(g1)`, Nudge down `[A,B]`): the group order `C A B` is the same
  under both algorithms, but the flat result is `C X A B` with the fix instead of Windows' `X C A B`; read that row
  as "g1: C A B; g2: X". All other 06 §7.4 rows are single-pick or contiguous and are unchanged.
* **OC-20 — Excel serial dates.** 09 §6.2 ("1900 system epoch 1899-12-30 incl. the fictitious 1900-02-29 handling
  as Excel does") vs 10 §6.6 ("1899-12-30 (`FromOADate` semantics)"). **Settled by 10 Addendum §X.2 D5/D6
  (VESSEL-309/310), read from the ClosedXML 0.104.2 source** — recorded here so verifiers find it. Neither base text
  is exact: `v ≥ 61` → `FromOADate(v)`; `v ≤ 60` → `FromOADate(v + 1)` (ClosedXML's leap-year shim), so 59 →
  1900-02-28 and 60 → 1900-03-01; `60 < v < 61` fails the import with ClosedXML's message; in a `date1904` workbook
  1462 days are added at load to **DateTime-typed cells only** (not to number or duration cells).
* **OC-21 — Is a number format a date?** 10 §6.6 ("`m` outside a pure-number context") vs 09 §6.2 ("an `m` that is a
  month, i.e. not adjacent to `h`/`s`"). **Settled by 10 Addendum §X.2 D1–D4 (VESSEL-307/308, VESSEL-326/328)**: the
  built-in ids that mean a date-time are only 14, 15, 16 and 22; 18–21 and 45–47 mean a duration; everything else
  (including 17, 27–36, 49, 50–58) is a number unless `<numFmts>` redefines the id; custom codes are classified by the
  first decisive character scanning left to right (§X.4.4). Time-only rendering: renderer A (COMPAS) `H:mm:ss` with
  unpadded, unwrapped hours — superseding 09 §6.2's `HH:mm:ss` — and renderer C (ports) `hh:mm`, hours mod 24.
* **OC-22 — XLSX sheet names.** 09 §3.10 ("XML-escaped **then** truncated to 31 chars (can split an entity)") vs
  11 §3.6.2 (DEV-03: sanitise `: \ / ? * [ ]` → `_`, trim `'`, blank or `History` → `Checklist`, truncate to 31
  UTF-16 units without splitting a surrogate pair, **then** escape). **Ruling:** the shared writer applies 11's order
  (sanitise → truncate → escape) for every workbook; the fallback name is the caller's (`Sheet1` for
  `XlsxWriter.Write`, `Checklist` for the checklist export). For the constant names Windows actually passes
  (`Crew`, `report`, `Ports of Call`) the output is identical to Windows.
* **OC-56 — One `NetDateTime` type.** 10 Addendum §X.7.1 lists `NetDateTime` among the contents of
  `AACore/Xlsx/ExcelSerial.swift`, while 01 App. A defines `NetDateTime` as the model's date type (`AACore/Model`).
  **Ruling:** there is exactly one `NetDateTime` (01 App. A, §4.1.5). `ExcelSerial.swift` holds the serial
  conversions (`fromSerial`, `fromOADate`, `toSerial`, `toTimeSpanMs`, `excelString`) as functions or an extension
  on that type; it does not declare a second date type.
* **OC-41 — `.aasched.json` writer.** 02 §6.10 (`JSONEncoder .prettyPrinted`) vs 06 §4.5 / 09 §4.8 / 01 §4.13
  (System.Text.Json indented, nulls written). **Ruling:** the 01 JSON writer in indented mode: 2-space indent,
  `"Key": value` (no space before the colon — `JSONEncoder` writes `"Key" : value`), nulls written, default
  escaping, CRLF line ends SHOULD (Windows bytes; readers accept LF/CRLF/BOM). 06 §4.5 owns the format.

*Undo, Trash, log, search, windows*

* **OC-14 — Undo last delete on the Mac.** 01 §6.10 (register on the window's `UndoManager`, action names
  `Delete “{name}”` / `Delete {n} Items`) vs 02 §6.4 (a responder implementing `undo(_:)`; title `Undo Move to
  Trash (7 Items)`; "Do not rely solely on `UndoManager`") vs 03 §6.5 (replace `CommandGroup(replacing: .undoRedo)`;
  titles from the text view's `undoManager`, else `Undo Delete` / `Undo Delete (n items)`) vs 04 §6.9 and 08 §6.1
  ("Undo Delete"). **Ruling:** 03 §6.5 mechanism and titles. 02 §6.4's semantic rule stays binding: the command is
  backed by the Trash (`PendingUndoCount`, `UndoLastDelete`) so it works after relaunch, and is not an
  `UndoManager` stack. When a text view is first responder, its own undo wins. 01 §6.10's Undo row is superseded.
* **OC-17 — Search and Activity-log window instancing.** 02 §6.6 (`Window("Search")`, single instance) and 02 §6.8
  (`Window("Activity Log")`) vs 03 §6.10 and 08 §6.2-D/E (`WindowGroup(for: UUID.self)`, a new window per
  invocation, as on Windows). **Ruling:** 08 — a new window each time. Closes 08 OQ-3.
* **OC-18 — Activity-log labels.** 02 §6.8 ("Export CSV…", "Clear Log…", window "Activity Log") vs 08 QUICK-151/§6.2-E
  (`Export (.csv)...`, `Clear log`, title `Activity log`). **Ruling:** 08 (Windows strings, `...` may render as `…`);
  the menu item is `Tools ▸ Activity Log…` (03 §6.4).
* **OC-19 — Trash presentation and wording.** 02 §6.4 (a window; Finder wording "Put Back" / "Delete Immediately…";
  02 Q-5 open) vs 08 §6.2-F and 03 §6.10 (a sheet on the main window, modal like WPF; Windows wording). **Ruling:**
  08 — a sheet; buttons `Restore` (SF Symbol `arrow.uturn.backward`, prominent), `Delete permanently`, `Empty Trash`,
  `Close`; tooltips and confirmations verbatim. 02 Q-5 is closed unless the product owner overrides it.
* **OC-31 — Due-dates panel style.** 03 §6.10 (`.nonactivatingPanel` as an option) vs 08 §6.2-A ("do **not** add
  `.nonactivatingPanel`, so clicking it gives it focus exactly like the WPF window"). **Ruling:** 08.
* **OC-32 — Scene ids.** 03 §6.10 (`Window(id: "quickWork")`) vs 08 §6.2-B (`id: "quick-work"`). **Ruling:** 08;
  the full id list is in DATA-220.
* **OC-42 — Editor registries.** 04 §6.7 (`EditorFlushCenter` with `flushAll()`) vs 05 §6.12 (`EditorRegistry` keyed
  by `Container` identity) vs 03 §6.10 (registry via `onAppear`/`onDisappear`). **Ruling:** one type,
  `EditorFlushCenter`, owning both the flush closures and the container-binding registry; the detached-item set is
  `AppStore.detachedItemIDs` (04 §6.7).
* **OC-43 — Which editors a save flushes.** 03 W-9 / SHELL-050 (Windows flushes only the four page editors on ⌘S and
  autosave), 04 HIER-116 + Q-31, 12 §6.4 (SIRE body flushed on every save path). **Ruling:** the Mac flushes **all**
  live editors (page editors, item windows, SIRE body, open modal editors) on every save, autosave, export, sync,
  reload and quit path — a strict superset of Windows with no data risk.
* **OC-53 — Quick switcher presentation.** 02 §6.6 (Spotlight-style `NSPanel`), 03 §6.10 (sheet or panel), 08 §6.2-C
  (Open-Quickly `NSPanel`, sheet acceptable), 08 OQ-2. **Ruling:** 08 — a floating `NSPanel` titled `Go to item`,
  closing on Esc and on resign-key; a sheet is an accepted alternative.
* **OC-54 — Search match highlight.** 02 §6.6 (`NSColor.findHighlightColor`) vs 08 §6.2-D (`#FFE066`, black, bold).
  **Ruling [verified `SearchWindow.xaml.cs:99`, `Color.FromRgb(0xFF, 0xE0, 0x66)`]:** `#FFE066`, black text, bold,
  in both appearances.
* **OC-37 — Review-sheet button text.** 01 §6.10 ("**Import (Overwrite)** (default, Return)") vs 08 QUICK-193 and
  §6.2-G (`Import (overwrite)`, the Windows string). **Ruling:** 08 — `Import (overwrite)` verbatim; title-casing
  applies to menu items, not to button captions that quote Windows text.

*Keyboard and menus* (the consolidated table is DATA-214)

* **OC-23 — ⌘P.** 03 §6.5 ("optionally also ⌘P alias" for the quick switcher) vs 11 §6.2 (File ▸ Print… ⌘P).
  **Ruling:** ⌘P is reserved for Print…; the switcher's alias is ⇧⌘O (02 §6.6, 08 §6.1).
* **OC-24 — ⌘T.** 05 §6.3 (Format ▸ Font ▸ Show Fonts ⌘T, the AppKit standard) vs 07 §7.3 (Planner "Today" ⌘T).
  **Ruling:** Show Fonts keeps ⌘T; *Go to Today* (Planner and Calendar) is ⇧⌘T.
* **OC-25 — ⌘+ / ⌘− / ⌘0.** 05 §6.3 (Bigger / Smaller font) vs 07 §7.1 (Calendar list text size). **Ruling:** the
  editor keeps ⌘+ (⌘=) / ⌘−; the Calendar's *Larger List Text* / *Smaller List Text* / *Default List Text Size* are
  ⌥⌘= / ⌥⌘− / ⌥⌘0.
* **OC-26 — ⌥⌘T.** 05 §6.3 (Insert Table…) vs 09 §6.4 (Crew *Table View…*). **Ruling:** Insert Table keeps ⌥⌘T;
  Crew Table View has no shortcut (toolbar button and menu item only).
* **OC-27 — ⌘F and ⌥⌘F.** 02 §6.6 / Q-9 (⌘F = the note's find bar when an editor is first responder; ⇧⌘F = global
  search), 10 §6.8 (⌘F focuses the current panel's search field), 12 §6.3 (SIRE focus-search: ⌥⌘F if the shell
  claims ⌘F) vs 03 §6.4/§6.5, 05 §6.3 and 08 §6.1/OQ-4 (⌘F = global search always; ⌥⌘F = find in the note).
  **Ruling:** ⌘F = Search Everything… always (Windows parity). ⌥⌘F is **one** context-routed menu item: when a text
  view is first responder it is *Find in Note…* (the `NSTextView` find bar, `usesFindBar = true`); otherwise it is
  *Filter This Page* and focuses the active page's own search/filter field (hierarchy sidebar search, crew roster
  search, work-orders / ports / ports-DB search, Board `Find:`, Planner `Search jobs...`, Relationship Map
  `Inspect` search, SIRE search, quick-work search, activity-log filter). ⇧⌘F is unassigned. Closes 02 Q-9, 05 §9
  Q4 and 08 OQ-4; replaces 10's additive ⌘F and 12's focus-search choice.
* **OC-28 — ⌘⌫.** 04 HIER-M02, 02 §6.4 (sidebar "Move to Trash"), 05 §6.9 (file bank remove), 07 §7.2 (Board
  delete, optional), 09 §6.4 (crew delete). **Ruling:** one *Edit ▸ Delete* item bound to ⌘⌫, context-routed with a
  dynamic title (`Move to Trash…` on hierarchy sidebars and the crew roster, `Remove` in the file bank, `Delete
  Task…` on the Board), each running its owner's confirmation. It validates to **disabled** whenever a text view or
  field editor is first responder, so text keeps ⌘⌫ (delete to line start).
* **OC-29 — Trash window shortcut.** 01 §6.10 (⌥⌘⌫ optional) vs 02 §6.4 and 03 §6.4 (none; ⇧⌘⌫ is Finder's Empty
  Trash). **Ruling:** no shortcut.
* **OC-30 — Menu titles.** 01 §6.10 (`Save a Copy As JSON…`, `Revert to Saved…`, `Import Database (JSON)…`,
  `Trash…`, `Shared Save File` ▸ `Set…`/`Stop Using`/`Check Now`, `Show Data Folder in Finder`, `Export Bundle…` /
  `Import Bundle…`, `Set / Change App Password…`) and 08 §6.1 (`Search All Items…`, `Due Dates`, `Quick Work…`,
  `Go to Item…`) vs 03 §6.4. **Ruling:** 03's titles and placements win. Kept as additions: 01's *Check Now* inside
  03's *Shared Save* submenu; 08's *File ▸ Go to Item…* as the ⇧⌘O entry (OC-40).
* **OC-40 — Same command in two menus.** 08 §6.1 puts Quick Work and Quick Switcher in both File and Tools. **Ruling:**
  only 03's placement carries the key equivalent (⌘N, ⌘O). A second entry is optional and has no shortcut, except
  *File ▸ Go to Item…*, which carries the ⇧⌘O alias so that each shortcut lives on exactly one item.

*Presentation and labels*

* **OC-15 — A newline inside a `Run`.** 05 §4.3.7 rule 4 (U+2028 → `<LineBreak />`) vs 12 §4.4 ("A Run with an embedded
  `\n` must be preserved as text inside that Run"). **Settled by 05 Addendum CONT-166 (line-break provenance)** —
  recorded here so verifiers find it. On read, a newline inside run text becomes U+2028 carrying `.aaInRunNewline` =
  the exact original sequence (`"\n"`, `"\r\n"` or `"\r"`); `<LineBreak/>` becomes an unmarked U+2028. On write, a marked
  U+2028 goes back into the current Run's text as that sequence (a CR as `&#xD;`); an unmarked one (⇧↩ on the Mac, or
  a `LineBreak` read from XAML) is written as `<LineBreak />`. Untouched bodies are never rewritten anyway (01 §4.11
  invariant 1).
* **OC-36 — Enum labels and the "Container" tab.** 04 §6.6 and Q-G ("friendlier labels … **only** if every other spec
  does the same"), 04 §6.3 and Q-H ("Notes & Files" only if the other specs agree), 06 §6.2 (optional friendly
  labels), 08 OQ-10. **Ruling:** Windows labels by default everywhere: `Todo`, `InProgress`, `Blocked`, `Done`;
  `None`, `Daily`, `Weekly`, `Monthly`, `Yearly`; tab `Container`. Board column headers keep their own Windows text
  (`To Do`, `In Progress`, …, 07 VIEW-041). Any change is one app-wide, display-only switch owned by 03 §6.6 (design
  system); stored integers never change.
* **OC-48 — Procedure checklist area.** 04 HIER-091…096 vs 06 §C BUILD-030…040 (same features; 06 adds the pick-order
  rule for *Link tasks…* and exact persist markers). **Ruling:** 06 §C. 04 keeps HIER-090 (the procedure's own fields).
* **OC-49 — Crew schedule tab.** 06 §I (BUILD-110…125) vs 09 §H (CREW-080…086). **Ruling:** 06 for the control; 09 for
  its hosting in the crew editor and crew-only rules (e.g. CREW-035 / 09 Q3: carry `Schedule` and `ScheduleVesselId`
  over on re-import).
* **OC-44 — Checklist-only exports.** 04 HIER-092 + §3.9 and 06 BUILD-039/040 + §4.7/§4.8 (C1/C2) vs 11 §2.2, §2.7, §2.8,
  §4.5. **Ruling:** 11 for layout, bytes, file names and messages; 06 BUILD-030 for the buttons' placement.
* **OC-45 — Saved-lists PDF.** 06 BUILD-091…096, §4.9, BUILD-A17 vs 11 §2.3, §2.5. **Ruling:** 11 for document
  content, prompt, dialogs and the Mac deviations (DEV-10 Export All without a selection, DEV-12 ignore open
  failures); entry selection and order via 02 REPO-135/136.
* **OC-51 — Maritime icons and card palette.** 03 SHELL-157 + App. C vs 10 §4.6/§4.7. **Ruling:** 10 (exact order,
  code points and tooltip names; the values are stored verbatim in `QuickCard.Icon`/`Color`).

*Startup, sync, secrets*

* **OC-33 — Reminders on the Mac.** Notification identifier: 02 §6.7 (`"aa.due-reminder"`) vs 03 §6.8
  (`"aa.reminder"`) → **`"aa.reminder"`**. Menu-bar extra: 02 §6.7 (optional) vs 03 §6.8 (always present, maps the
  tray icon) → **03**. Dock badge: 02 §6.7 (optional overdue count) vs 03 §6.8 ("do not add without sign-off") →
  **none by default**; 02 Q-13 (substitute when notification permission is denied) stays open.
* **OC-34 — Google OAuth token storage on the Mac.** 01 §6.5 (a Keychain item per token: service `AA.GoogleOAuth`,
  value = token JSON) vs 14 §6.3 (files in `google-token/` named as on Windows, content `AAKCGCM1` + AES-256-GCM,
  key in the Keychain). **Ruling:** 14, because `HasToken`, `NeedsReconsentForWholeDrive` and *Sign out* are defined
  on the `google-token/` folder (TOOLS-010/011/013) and a copied Windows token folder must still trigger the
  re-consent notice. 01 §6.5's sentence on the Google refresh token ("The same Keychain approach replaces
  `DpapiDataStore` …") is superseded.
* **OC-35 — Gemini key Keychain item.** 01 §6.8 (service `"AA.Gemini"`) vs 12 §6.9 (service `"{bundleID}.gemini"`,
  account `"GeminiApiKey"`). **Ruling:** 12 (the feature owner), i.e. `com.eriskay.aa.gemini` / `GeminiApiKey`.
* **OC-38 — Startup order.** 01 §3.27 vs 03 §1.3 (same order, 03 more granular). **Ruling:** 03 §1.3 for the Windows
  order; the Mac launch is 03 §1.3 as amended by 01 MP.6.1 (instance guard before splash).
* **OC-39 — Crash handling.** 01 DATA-004 vs 03 SHELL-001. **Ruling:** 03 SHELL-001 (handlers, alert text, `crash.log`
  line format); the Mac mechanism (uncaught-exception handler + MetricKit) is 01 §6.10.
* **OC-50 — Shared save described twice.** 01 §E/§3.12 vs 03 §I/§3.9/§7.2. **Ruling:** 01 for semantics and the state
  machine (incl. D-1/D-2 recommendations, which 03 W-4 repeats); 03 for menu wiring and the indicator's visuals.
* **OC-52 — Where Mac-only preferences live.** 01 §4.14 rule 10 ("`UserDefaults` or a separate `settings.mac.json`")
  vs 01 §6.8 ("go to `UserDefaults` — never into `settings.json`"). **Ruling:** `UserDefaults` only; no
  `settings.mac.json` file is created (one fewer file in the data folder, nothing that a bundle or Flash Sync could
  pick up).

#### P.5 Registries

**DATA-214 — Consolidated Mac keyboard and menu registry.** Every Mac key equivalent in the app. Base: 03 §6.4/§6.5.
Additions come from the spec named. **Rule: each key combination is bound to exactly one menu item** (TV-OWN-02);
context-dependent behaviour is done by routing inside that one item (OWN.3.2). "—" = no shortcut.

| Menu ▸ item (Mac title) | Key | Enabled when | Source / ruling |
|---|---|---|---|
| AA ▸ About AA | — | always | 03 |
| AA ▸ Settings… | ⌘, | always | 03 §6.4 (G9) |
| AA ▸ Hide AA / Hide Others / Quit AA | ⌘H / ⌥⌘H / ⌘Q | always | system; Quit = 03 SHELL-056 |
| File ▸ Save | ⌘S | any AA window key | 03 §6.5 |
| File ▸ Save As… | ⇧⌘S | always | 03 (OC-30) |
| File ▸ Reload from Disk / Import from File… | — | not read-only | 03 |
| File ▸ Trash (Restore Deleted Items)… | — | always | 03 (OC-29) |
| File ▸ Encrypt Local Data File (This Mac) | — (checkmark) | editor process | 03; 01 §6.5 |
| File ▸ Shared Save ▸ Set Shared Save File… / Stop Shared Save File / Check Now | — | — | 03; *Check Now* from 01 §6.10 (OC-30) |
| File ▸ Set App Identity… / Open Data Folder | — | — | 03 |
| File ▸ Export Data Folder (ZIP)… / Import Data Folder (ZIP)… | — | — | 03 |
| File ▸ Export Text Only (No Attachments) | — (checkmark) | — | 03 |
| File ▸ Google Drive ▸ (8 items, TOOLS-001 order) | — | — | 03, 14 §6.6 |
| File ▸ Flash Sync with iPhone (QR)… | — (⌥⌘Y optional) | — | 03; 13 FLASH-001 |
| File ▸ Export as PDF… | ⌥⌘E | an item detail or item window is focused and not gated | 11 §6.2 (XR-05) |
| File ▸ Print… | ⌘P | as Export as PDF | 11 §6.2 (optional; OC-23) |
| File ▸ Go to Item… | ⇧⌘O | always | 02 §6.6, 08 §6.1 (OC-40) |
| File ▸ New {Kind} | ⇧⌘N | a hierarchy page is active | 04 §6.9 |
| File ▸ Close | ⌘W | a window is key | system; closes tool windows (14 §6.6) and secondary windows; on the main window it runs the quit pipeline (03 §6.5, SHELL-056) |
| Edit ▸ Undo … / Redo … | ⌘Z / ⇧⌘Z (⌘Y alias in the editor) | per 03 §6.5 | OC-14 |
| Edit ▸ Cut / Copy / Paste / Select All | ⌘X / ⌘C / ⌘V / ⌘A | system | file-bank private clipboard when the file list is focused (05 §6.9) |
| Edit ▸ Paste and Match Style | ⌥⇧⌘V (⇧⌘V alias) | a container editor is key | 05 §6.3 |
| Edit ▸ Delete (dynamic title) | ⌘⌫ | a routed list is focused and no text view is first responder | OC-28 |
| Edit ▸ Find ▸ Search Everything… | ⌘F | always | 03 (OC-27) |
| Edit ▸ Find ▸ Find in Note… / Filter This Page | ⌥⌘F | see OC-27 | OC-27 |
| Edit ▸ Find ▸ Find Next / Find Previous / Use Selection for Find | ⌘G / ⇧⌘G / ⌘E | a text view is first responder | system (NSTextView find bar) |
| Edit ▸ Spelling and Grammar | ⌘: / ⌘; | a text view is first responder | system; 05 CONT-033 |
| Format ▸ Font ▸ Show Fonts | ⌘T | a container editor is key | 05 §6.3 (OC-24) |
| Format ▸ Font ▸ Bold / Italic / Underline | ⌘B / ⌘I / ⌘U | editor or SIRE body key | 05 §6.3; 12 §6.3 (typing attributes only) |
| Format ▸ Font ▸ Strikethrough | ⇧⌘X | editor key | 05 §6.3 |
| Format ▸ Font ▸ Bigger / Smaller | ⌘+ (⌘=) / ⌘− | editor key | 05 §6.3 (OC-25) |
| Format ▸ Font ▸ Show Colors | ⇧⌘C | editor key | 05 §6.3 |
| Format ▸ Font ▸ Copy Style / Paste Style | ⌥⌘C / ⌥⌘V | text view key | system |
| Format ▸ Text ▸ Align Left / Center / Right | ⌘{ / ⌘\| / ⌘} | editor key | 05 §6.3 (Justify: menu only) |
| Format ▸ Lists ▸ Bullets / Numbering | ⇧⌘7 / ⇧⌘9 | editor key | 05 §6.3 |
| Format ▸ Lists ▸ Increase / Decrease Indent | ⌘] / ⌘[ | editor key | 05 §6.3 |
| Format ▸ Lists ▸ Move Item Up / Down | ⌃⌘↑ / ⌃⌘↓ (⌃⌥↑/↓ alias) | editor key | 05 §6.3 |
| Format ▸ Insert Link… / Insert Table… / Insert Saved List… | ⌘K / ⌥⌘T / ⌥⌘L | editor key | 05 §6.3 (OC-26) |
| View ▸ Dark Mode / Shortcut Bar / Customize Tab Colors… | — | — | 03 |
| View ▸ (13 sections) | ⌘1…⌘9 | always | 03 SHELL-045 |
| View ▸ Previous / Next (Planner, Calendar) | ⌘← / ⌘→ | Planner or Calendar active and no text field first responder | 07 §7.3 |
| View ▸ Go to Today | ⇧⌘T | Planner or Calendar active | 07 §7.3 (OC-24) |
| View ▸ Larger / Smaller / Default List Text Size | ⌥⌘= / ⌥⌘− / ⌥⌘0 | Calendar active | 07 §7.1 (OC-25) |
| View ▸ Enter Full Screen | ⌃⌘F (fn-F) | — | system |
| Tools ▸ Folder Builder… / Date Calculator… / Unit Converter… / Activity Log… | — | — | 03; 14 §6.6 |
| Tools ▸ Floating Due-Dates Window | ⌘R | always | 03 |
| Tools ▸ Quick Work Window | ⌘N | always | 03 |
| Tools ▸ Quick Switcher | ⌘O | always | 03 |
| Tools ▸ Import COMPAS Crew (.xlsx)… | ⇧⌘I | editor process | 09 §6.4 on 03's item |
| Tools ▸ Check Crew Contract Expiries / SIRE 2.0 Export… / Set Gemini API Key… / Set / Change Password… | — | — | 03 |
| Tools ▸ Lock Now | ⌃⌘L | always | 03, 01 §6.10 |
| (lists, context-routed) Move Up / Move Down | ⌥⌘↑ / ⌥⌘↓ | a builder list or the Saved Lists sidebar is focused; disabled while Sort A-Z is on | 06 §6.2; 02 §6.9 |
| (lists) Move To… | ⇧⌘M | a builder list is focused | 06 §6.2 |
| (bulk editor) Add All | ⌘↩ | the bulk-entry editor is focused | 06 §6.2 |
| SIRE ▸ Mark In Progress / Mark Checked / Mark N/A / Clear Status | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 / ⌥⌘4 — optional | SIRE active and no text view first responder | 12 §6.3 (suggested free combos; not ⌥⌘0, which the Calendar uses) |
| SIRE ▸ Toggle Bookmark / Toggle Export Tag | ⌥⌘B / — optional | SIRE active | 12 §6.3 |
| Window ▸ Minimize / Zoom / Bring All to Front | ⌘M / — / — | system | lists item, search, log windows |
| Flash Sync window: Stop | ⌘. | flashing or camera running | 13 §6.6 |
| Sheets and prompts: OK / Cancel | ↩ / Esc (⌘.) | a sheet is up | 03 §6.5; 06 BUILD-139 |
| Sidebar: Rename | F2 and ↩ on a focused row | no text field first responder | 03 SHELL-046; 04 §6.9 |

Not bound anywhere (so they stay free): ⇧⌘F, ⇧⌘⌫, ⌥⌘⌫. System combinations never to be bound by AA: ⌃⌘Q (Lock
Screen), ⌃⌘Space (emoji), ⌘Tab, ⌘Space, ⌥⌘Esc, ⌥⌘D, ⌥⌘M, ⌥⌘W.

**Shortcut strip (03 SHELL-024)** lists the ⌘ forms of the Windows strip: ⌘S, ⌘F, ⌘N, ⌘O, ⌘R, ⌘1…9, F2, ⌘Z.

**DATA-215 — Keychain item registry (Mac only; nothing here travels between machines).** All items:
`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`.

| Item | Service | Account | Value | Owner |
|---|---|---|---|---|
| Local data-file key | `AA.LocalDataKey` | `v1` | 32 random bytes (AES-256-GCM key for `AAENCM1\n` files) | 01 §6.5 |
| Google token-file key | `AA` | `google-token-key` | 32 random bytes (AES-256-GCM key for `AAKCGCM1` token files in `google-token/`) | 14 §6.3 (OC-34) |
| Gemini API key | `com.eriskay.aa.gemini` (`{bundleID}.gemini`) | `GeminiApiKey` | UTF-8 key; absent = no key | 12 §6.9 (OC-35) |

The three service names follow no common pattern. They are Mac-private and could be harmonised, but only together
with a read-old/write-new migration (Q-OWN-5).

---

### OWN.3 Logic & algorithms

#### OWN.3.1 `resolveOwner(topic)` — how a verifier applies DATA-200

```
func resolve(topic) -> Source:
    if brief.addresses(topic)                      return brief
    owner = ownershipMap[topic]                    // DATA-202…210
    if let a = owner.normativeAddendum(on: topic)  return a        // e.g. 06 BUILD-136…150
    if let r = conflictRegister[topic]             return r        // DATA-213
    if topic.isWindowsFact && specsDisagree(topic) → reread C# at cited lines; record a new OC ruling
    if topic.isPersistedFormat                     return spec01.section4   // compatibility override
    return owner.baseText
```

#### OWN.3.2 Context-routed menu items (the one-item-per-shortcut rule)

Used by OC-27 (⌥⌘F) and OC-28 (⌘⌫), and by the ⌥⌘↑/↓ list commands.

```
struct RoutedCommand { key; modifiers; titleFor(context) -> String?; perform(context) }
context = (keyWindow, firstResponder, activeSection, focusedList: FocusedValue)

validate(item):
    if firstResponder is NSTextView (or a field editor) and command.yieldsToText   // ⌘⌫, ⌘←/⌘→, ⌥⌘↑/↓
        → disabled (the key reaches the text view's own key binding)
    title = command.titleFor(context)        // nil → disabled, keep last title
    item.title = title ?? item.title
perform: dispatch to the handler registered by the focused list / page (FocusedValue), never to a global guess
```

SwiftUI: publish handlers with `.focusedSceneValue(\.deleteCommand, …)` etc. and build the `Commands` with
`@FocusedValue`; set the dynamic title from the focused value. AppKit fallback: `validateMenuItem(_:)` on the
window's responder. Menu key equivalents are processed **before** `keyDown`, which is why an enabled ⌘⌫ item would
steal ⌘⌫ from text fields; the validation rule above prevents that.

#### OWN.3.3 Number formats and serials (pointer)

This addendum does **not** restate the XLSX number-format classifier or the serial conversions. They are specified,
as exact ports of ClosedXML 0.104.2, in 10 Addendum §X.4.3 (styles → `NumberKind`: `number`, `dateTime`,
`timeSpan`), §X.4.4 (`classifyCustom`), §X.4.7–§X.4.9 (serial → date-time, 1904, serial → duration), with vectors
in §X.8.2–§X.8.4. Any other spec's rule on these topics (09 §6.2, 10 §6.6) is superseded (OC-20, OC-21). The
conversions build values of the one `NetDateTime` type from 01 App. A (OC-56).

#### OWN.3.4 Dangling-reference lint (spec hygiene)

```
perl -0777 -ne 'while (/\b(the|a|see|per|by|in)\s+((?:[A-Za-z\/⇄-]+\s+){0,4})specs?\b/gi) {
    ($pre,$name)=($`,$2); $ln=($pre=~tr/\n//)+1; $name=~s/\s+/ /g;
    print "$ARGV:$ln: $name\n" unless $name =~ /^(this|that|each|every|same|full|porting) ?$/i }' mac/Docs/Spec/*.md
```

Every hit MUST either appear in DATA-211/212 (by file and phrase) or be replaced by an explicit `NN §S (ID)`
citation. Line numbers in the tables are informative (they shift when addenda are inserted above), so the lint
matches on **file + phrase**.

#### OWN.3.5 Adding a new ruling (maintenance)

1. Identify the owner in DATA-202…210 (add a row if the component is new).
2. If the conflict is about Windows behaviour, re-read the C# and record `[verified file:lines]`.
3. Append an `OC-nn` entry (never renumber), naming the superseded text by `file §section (ID)`.
4. If the ruling changes a shortcut or a Keychain item, update DATA-214 / DATA-215 in the same edit.

---

### OWN.4 Data formats — who owns the semantics of each persisted key and file

Schema (key names, value types, defaults, emission order) is always **01 §4**. The table says which spec owns the
*meaning* of the value: who writes it, when, and what the UI does with it.

**DATA-216 — `data.json` top level (`AppData`) and nested types.**

| Key / type | Semantics owner | Notes |
|---|---|---|
| `Equipment` (`Equipment`: `Components`, `ProcedureIds`, `TaskIds`) | 04 §H (HIER-070…073) | links also 02 REPO-023/024 |
| `Tasks` (`TaskItem`: `Deadline`, `RangeStart`, `Recurrence`, `RecurrenceSpawned`, `Status`, `IsComplete`, `IsJob`, `DurationMinutes`) | 04 §I; status sync 01 DATA-130; ranges 02 REPO-050…054; recurrence 02 §2.G | `ScheduledStart` = 07 §3.3 (Planner); `Subtasks` = 06 §D/§E |
| `Procedures` (`Procedure`: `Deadline`, `Recurrence`, `Status`, `IsJob`, `DurationMinutes`, `Steps`) | 04 HIER-090; `Steps` = 06 §C | — |
| `ChecklistStep` (in `Procedure.Steps`, `CrewMember.Checklist`, templates via `ChecklistTemplateItem`) | 06 §A/§B; `TaskIds`/`EquipmentIds` 06 BUILD-034/036; `BucketIds` 07 §3.4 | JSON: 01 §4.2.8 |
| `Vessels` (`QuickCards`, `Jobs`, `NotificationsEnabled`, `PortCalls`) | 10 | — |
| `HierarchyItem` base: `Id`, `Name`, `Description`, `Tags` | 04 (HIER-025…027) | — |
| … `Container` (`RichTextXaml`, `Files`, `SharedWithContainerIds`, `IsLocked`) | 05 (CONT-003…098); path rules 01 §F | XAML: 05 §4.3 |
| … `RelatedIds` | 02 §2.C | — |
| … `GroupId` | 04 §D | — |
| … `BucketIds` (+ legacy `BucketId`) | 07 §3.4; migration 01 DATA-132 | assignment UI 08 QUICK-053/054/231 |
| … `LockHash`, `LockSalt`, `LockHint` | 01 §I | UI 04 §F |
| `Groups` (`ItemGroup`) | 04 §D (ops 02 REPO-120) | `Expanded` unused by the UI (04 §4.2) |
| `Crew` (`CrewMember`, incl. `Checklist`, `Schedule`, `ScheduleVesselId`, review flags) | 09 | `Checklist` UI 06 §A; `Schedule` UI 06 §I |
| `Log` (`LogEntry`) | 02 §2.I; producers per E7 | cap 10 000 (01 DATA-115) |
| `ChecklistTemplates`, `ListGroups` | 06 §F/§G; order 02 §2.M; service 02 §2.N | array order = arrangement |
| `QuickBuckets` | 07 §3.4 | — |
| `Ports` (`Port`, `PortVisit`) | 10 §F (merge 10 §3.2) | — |
| `ScheduleTemplates` | 06 §I (service 02 §2.O) | — |
| `Trash` (`TrashedItem`) | 02 §2.H (format 01 §4.2.16/§4.10) | — |
| `Sire` (`SireState`, `SireTask`, `QuestionBodies`) | 12 §4.2 | bodies are XAML (12 §4.4) |
| `Ui` | per key, DATA-217 | schema 01 §4.2.20 |
| `LastModified`, `SchemaVersion`, unknown top-level keys | 01 (DATA-022…024, DATA-031) | — |

**DATA-217 — `Ui` keys.**

| Key(s) | Owner |
|---|---|
| `WindowLeft`, `WindowTop`, `WindowWidth`, `WindowHeight`, `WindowState` | 03 SHELL-032, §6.3 |
| `SelectedMainTabIndex`, `TabOrder`, `TabColors` | 03 SHELL-027…029 (apply order before index: 01 D-15) |
| `ShowShortcutBar` | 03 SHELL-024/111 |
| `SelectedEquipmentId`, `SelectedTaskId`, `SelectedProcedureId`, `SelectedVesselId` | 04 HIER-121 |
| `SortAZ` (`Equipment`, `Task`, `Procedure`, `Vessel`) | 04 HIER-013 |
| `SortAZ["savedlists"]` | 06 BUILD-088 |
| `GroupExpanded` (key `"{Kind}\|{group}"`) | 04 HIER-015 |
| `CalendarSelectedDate`, `CalendarViewMode`, `CalendarFontScale` | 07 VIEW-020, VIEW-017 |
| `MapFocusedItemId` | 07 VIEW-180 |
| `QuickViewPinIds` | 08 QUICK-061 |
| `DueWindowWidth`, `DueWindowHeight` | 08 QUICK-006 |
| `CrewSortMode`, `CrewTableColumns`, `CrewTableShownColumns`, `CrewTableDateFormat`, `CrewTableDateSeparator` | 09 CREW-015, CREW-104 |
| `LastDigestDate` | 03 SHELL-132 |
| per-device vs shared (Flash Sync) | 13 §3.11.1 `PerDeviceUiKeys` |

**DATA-218 — `settings.json` keys.**

| Key | Owner | Mac storage |
|---|---|---|
| `CurrentDataFile` | 01 DATA-013 (+ MP DATA-179) | `settings.json` |
| `PasswordHash`, `PasswordSalt` | 01 §H | `settings.json` (byte-compatible) |
| `GoogleDriveFolder` | 14 TOOLS-004/005 (Mac detection 01 §6.8) | `settings.json` |
| `SyncOnSave` | 14 TOOLS-020 | `settings.json` |
| `DarkMode` | 03 SHELL-110/151 | `settings.json` (Flash Sync sends it) |
| `FolderBuilderBase` | 14 TOOLS-041 | `settings.json` |
| `SharedSaveFile` | 01 DATA-050 | `settings.json` |
| `EncryptLocalData` | 01 DATA-070 | `settings.json` |
| `GeminiApiKey` | 12 SIRE-038 | **Keychain** (DATA-215); absent from the Mac's `settings.json` |
| `AppIdentity` | 01 DATA-048 (menu 03 SHELL-068) | `settings.json` |
| `TextOnlyExport` | 01 DATA-042 (Drive use 14 TOOLS-031) | `settings.json` |
| Mac-only preferences | 01 §6.8 | `UserDefaults` only |

**DATA-219 — Files and artefacts.**

| File / artefact | Owner |
|---|---|
| `data.json`, `data.json.<32hex>.tmp`, local encrypted form | 01 §4.2, §4.6, §6.4, §6.5 |
| `settings.json` | 01 §4.3 |
| `source.json`, `.zip`/`.aaz` bundle layout | 01 §4.4, §4.5 |
| `files/<32hex>_<name>` | 01 §F (UI 05 §2.5) |
| `crash.log` | 03 SHELL-001 |
| `.aa.lock` (Mac only) | 01 MP.4.1 |
| `google_client_secret.json`, `google-token/` | 14 TOOLS-007, §4.3, §6.3 |
| `qrsync-baseline.json` | 13 §4.4 |
| `qrmodels/` (Windows only) | 13 §3.13 |
| `*.aasched.json` | 06 §4.5 |
| Activity-log CSV | 08 §4.6 |
| Crew `.xlsx` export | 09 §4.10 |
| COMPAS `.xlsx` input | 09 §4.9 |
| Shippalm `.xlsx` in/out | 10 §3.4, §4.4 |
| Ports-of-call `.xlsx` in/out | 10 §3.3, §4.5 |
| Item PDF, checklist-only PDF/XLSX, saved-lists PDF | 11 §2.4, §2.7, §2.8, §2.5, §4.4, §4.5 |
| SIRE export text | 12 §3.10, §4.5 |
| SIRE question bank (bundled, read-only) | 12 §4.1 |
| Flash Sync interop frame file | 13 §4.6 |
| Drive backup names and file properties | 14 §4.5, TOOLS-006 |
| Temp folders/files (`AA_export_…`, `aa-sync-….zip`, …) | 01 §4.12 (writers: 01, 14) |

---

### OWN.5 Dependencies (spec-to-spec)

**DATA-220 — One implementation per shared type.** The Swift module, the type, and the spec that owns it. Nothing in
this table may be implemented twice; a second spec that needs it imports it.

| Module path | Types | Owner |
|---|---|---|
| `AACore/JSON` | `JSONValue`, `JSONParser`, `JSONWriter` (compact + indented) | 01 §4.1, §6.1 (OC-01…03, OC-41) |
| `AACore/Model` | `NetDateTime`, `NetGuid`, enum structs, every model class | 01 §4.2, App. A |
| `AACore/Persistence` | `DataStore`, `SettingsStore`, `AtomicWrite`, `LocalEncryption`, `AttachmentStore`, `BundleService`, `SharedSaveCoordinator`, `InstanceGuard` | 01 (§C–§G, MP) |
| `AACore/Util` | `CRC32`, `RawDeflate` | 13 §6.1 |
| `AACore/Zip` | `ZipReader`, `ZipWriter` | 01 §6.7 |
| `AACore/Xlsx` | reader: `XlsxWorkbook`, `XlsxWorksheet`, `XlsxCell`, `XlsxStyles` (`NumberKind`, `builtinKind`, `classifyCustom`), `ExcelSerial`, `NetNumberText`, `XlsxRender` (renderers A/B/C); writer: `XlsxWriter` | reader: 10 Addendum §X.7.1; writer: 09 §3.10 + 10 §6.6 "Writing" + OC-22 |
| `AACore/RichText` | `XamlDOM`, `XamlStyle` (cascade, computed style, default contexts), `XamlReader`, `XamlWriter`, `HTMLToXAML`, `ListFormatter`, `LockRules`, `XamlPlainText` (`searchText`, `diffText`), `LegacyBodyCrypto` | 05 §6.1 + 05 Addendum §XD.4 (+ B8) |
| `AACore/Security` | `PasswordService`, `ItemLockService`, `SecretStore` (Keychain wrapper, DATA-215) | 01 §H, §I, §6.11 |
| `AACore/Services` | `AppStore` (brief; 02), `SearchService`, `ReminderService`, `WorkRange`, `BatchDone`, `BatchDeadline`, `BatchDelete`, `SavedListOrder` (D-1 fixed), `ChecklistTemplateService`, `ScheduleService` | 02 |
| `AACore/Services` | `DataDiff`, `AgeVerdict` | 08 §3.7, QUICK-196 |
| `AACore/Crew` | `CrewMember.parseDate`, `DateResolver`, `CompasReader`, `CrewConverter`, `CrewColumns` | 09 |
| `AACore/Vessel` | `PortCallReader`, `ShippalmReader`, `PortsService`, `MaritimeIcons` | 10 |
| `AACore/Export` | `PdfExporter`, `ChecklistExporter`, `LinkScanner` | 11 |
| `AACore/Sire` | bank, `TagExtractor`, `TaskIdentifier`, `SireFlow`, `SireToAa`, `SireExport`, `GeminiService` | 12 |
| `AACore/FlashSync` | `Base45`, `Fountain`, `FlashFrame`, `FlashEncoder`, `FlashDecoder`, `FlashChangeSet`, `FlashSyncStore`, `QRCode` | 13 §6.1 |
| `AACore/Drive` | Drive client, OAuth loopback, token files | 14 §6.3–6.5 |
| `AA/Shared` | `TextPromptSheet` (06 Add. BUILD-136), `ItemPickerSheet` (07 Add. VIEW-208…216 + 04 HIER-131), `DatePromptSheet` (04 HIER-132), `OptionalDatePicker` (06 §6.2), `PasswordSheet` (03 SHELL-161), `ItemLockSheet` (04 HIER-058), `ListStyleSheet` (11 PDF-023), `BatchMenus` (04 HIER-133…135), `ContainerViewerView` (04 HIER-136), `EditorFlushCenter` (OC-42) | as listed |
| `AA/Editor` | `ContainerEditorView`, `ContainerTextViewController`, `FileBankView` | 05 §6.1 |
| `AA/Shell` | `AppCommands` (DATA-214), `DesignTokens` (03 §6.6), status line, tab strip, launch coordinator | 03 (+ 01 MP.6.2) |
| Scene ids | `main` (single `Window`, 01 DATA-186), `item` (`WindowGroup(for: UUID.self)`, 04 §6.7), `quick-work` (08, OC-32), `due` (08 §6.2-A), `search` (`WindowGroup(for: UUID.self)`, 08 §6.2-D), `activity-log` (`WindowGroup(for: UUID.self)`, 08 §6.2-E), `splash` (01 MP.6.2) | as listed |

**Which spec consumes which (read the owner before implementing the consumer):**

* 01 is consumed by every spec (model, JSON, dates, persistence).
* 02 → consumed by 03, 04, 06, 07, 08, 09, 10, 12, 14.
* 03 → owns the menus and status line every UI spec posts into; its Password dialog is used by 05 (text lock).
* 04 §N dialogs and batch menus → used by 05, 06, 07, 08, 09, 10, 12, 14.
* 05 → the editor is hosted by 04, 06 (step/subtask editors, template items), 08 (quick work detail), 09 (crew
  checklist items via 06); its XAML layer is consumed by 11 (PDF) and 12 (SIRE).
* 06 → builders used by 04, 07 (editors opened from Calendar/Board/Planner/Buckets), 08, 09.
* 07 Addendum → the picker contract used by 04, 05, 06, 08, 12, 14.
* 08 → `DataDiff` and the review sheet are used by 01 and 03 (every import path) and by 14 (Drive imports). Flash
  Sync does **not** use them; it has its own review (13 FLASH-044).
* 09 → `XlsxWriter` base used by 10 and 11; `ParseDate` used by 10.
* 10 → `XLSXReader` used by 09.
* 13 → CRC-32/DEFLATE used by 01's ZIP (and so by 09/10/11's XLSX).

No new Windows-only APIs are introduced by this addendum; each owner's §5.3 still lists its own.

---

### OWN.6 macOS adaptation notes

**DATA-221 — Code and test annotation.** Every Swift type or function that implements a spec feature carries a
comment naming the **owner** ID, e.g. `// Spec: 04 HIER-131, 07 VIEW-208…216` or `// Spec: 02 REPO-132 (D-1 fix,
OC-16)`. Tests name the vector they implement (`// TV: 02 T-ORD-6`, `// TV-OWN-04`). This makes the verifier's
first step — "which spec wins?" — mechanical.

**DATA-222 — Citation style for all specs from now on.** Cite another spec as `NN §S (ID)` — e.g.
`08 §2.5 (QUICK-150)` — and never as "the *X* spec". Existing references are resolved by DATA-211/212 and need not be
rewritten.

**DATA-223 — Shared components are built once and look identical everywhere.** Because each shared dialog has one
owner, the Mac gets one sheet per dialog type with one set of strings, sizes, keyboard behaviour and dark-mode
styling (sheets on the window the command came from; `.borderedProminent` default button; Esc cancels; ⌘. cancels).
The per-feature names used by some specs (`WebLinkPromptSheet`, "New Task sheet", bucket prompt…) are thin wrappers
that only supply title, prompt and initial text (06 BUILD-136).

Further Mac notes:

* **Context-routed commands** (OWN.3.2) are what make one global menu bar work for a multi-pane app: the item's
  title changes with focus (e.g. `Move to Trash…` / `Remove` / `Delete Task…`), the key stays the same, and the text
  system keeps its own bindings.
* **Keychain and signing.** The brief ships an ad-hoc-signed `.app`. Keychain items created by one ad-hoc build can
  prompt "AA wants to use your confidential information…" after a rebuild, because the item's ACL is tied to the
  code signature. Wrap all three items (DATA-215) behind one `SecretStore` protocol with an in-memory test double, so
  unit tests never touch the login keychain, and treat a user-denied read as "no key" (Drive: "sign in again"; local
  data: safe mode with the 01 §6.5 message; Gemini: "no key set").
* **No third-party code** (OC-04): the ZIP, XLSX, QR and JSON layers are all in-house; keep them in `AACore` so the
  unit tests cover them without UI.
* **Identifiers** (OC-07): one `Identifiers` enum in `AACore` holds the bundle id, UTType, notification names,
  Keychain services, notification request id `aa.reminder` (OC-33) and scene ids (DATA-220).
* **Genuinely impossible on macOS:** nothing new. The impossibilities each owner lists (DPAPI, `explorer.exe /select`,
  tray balloons, owned-window z-order, …) keep their owner's alternative.

**DATA-224 — Addenda that arrive after this one.** Other gap-fill addenda may be appended to any spec after this
one. Each such addendum that makes itself normative for a component (an "erratum", or text saying "this addendum
wins") becomes rule 2 of DATA-200 for that component automatically. Whoever appends it SHOULD also add or amend the
row in DATA-202…210, and add an `OC-nn` entry if it overrides another spec, following OWN.3.5.

---

### OWN.7 Test vectors / verification

**TV-OWN-01 — Dangling-reference lint.** Run OWN.3.4. Expected: every hit's (file, phrase) appears in DATA-211 or
DATA-212. A new unmatched hit fails the docs check.

**TV-OWN-02 — Shortcut uniqueness.** Build the `AppCommands` model (all `Commands`, including optional ones compiled
in) and collect `(key, modifiers)` pairs. Expected: no pair appears on two menu items; the set equals DATA-214's;
none of ⌃⌘Q, ⌃⌘Space, ⌥⌘Esc, ⌥⌘D, ⌥⌘M, ⌥⌘W, ⇧⌘⌫ is bound by AA.

**TV-OWN-03 — ⌘⌫ yields to text.** Focus a hierarchy sidebar row → Edit ▸ Delete reads `Move to Trash…` and is
enabled; ⌘⌫ shows the HIER-135 confirmation. Put the caret in the item's Description field → the item is disabled and
⌘⌫ deletes to the start of the line. Same for the file bank (`Remove`) and the Board (`Delete Task…`).

**TV-OWN-04 — Fixed Nudge (OC-16).** Notation `name(group)`, assert per-group order:

| Start | Call | Windows (reference only) | Mac (expected) |
|---|---|---|---|
| `A(g) X(h) B(g) C(g)` | `nudge([B, C], up)` | g: B A C | g: B C A; h: X; returns true |
| `A(g) B(g) X(h) C(g)` | `nudge([A, B], down)` | g: A C B | g: C A B; h: X; returns true |
| `A(g1) X(g2) B(g1) C(g1)` | `nudge([A, B], down)` | flat `X C A B` | flat `C X A B`; g1: C A B; g2: X |
| `A B C D` (all g) | `nudge([B, D], up)` | `B A D C` | `B A D C` |
| `A(g) X(h)` | `nudge([A, X], up)` | false | false |

**TV-OWN-05 — Search on a locked item (OC-11).** Task `T` locked, not unlocked this session, `Name = "Pump"`,
`Tags = ["engine"]`, `Description = "secret engine note"`. Query `engine` → exactly one hit, `Tags`, owner `T`. Query
`secret` → no hit. Unlock `T`, repeat `secret` → one `Description` hit.

**TV-OWN-06 — Viewer missing file (OC-12).** `AppFolder = /Users/u/Library/Application Support/AA`; stored path
`files/0123456789abcdef0123456789abcdef_manual.pdf` (file absent). Double-click → alert title `Open file`, text
`That file is missing:\n\n/Users/u/Library/Application Support/AA/files/0123456789abcdef0123456789abcdef_manual.pdf`.
A web link (`IsLink`) never shows this alert.

**TV-OWN-07 — DataDiff duplicates (OC-13).** Current container files `[X|p, X|p]`, incoming `[X|p]` → one child
`Removed "file: X"`. Current `[X|p]`, incoming `[X|p, X|p, Y|q]` → `Added "file: X"`, `Added "file: Y"` (b order).
No duplicates anywhere → output byte-identical to 08 §7.7's vectors. Links: current step `TaskIds [t1, t2]`,
incoming `[t2, t3, t3]` → `Added "linked task: {t3}"`, `Removed "linked task: {t1}"`.

**TV-OWN-08 — Date prompt without a date (OC-10).** Open "Set deadline" on two undated tasks → field empty; press OK →
alert `Pick a date, or use "Clear deadline" to remove it.` titled `Set deadline`; the sheet stays; nothing changes.
Press `Clear deadline` → returns nil; no change (both already undated) → no save.

**TV-OWN-09 — JSON escaping (OC-01).** Model `QuickCard.Icon = "⚓"`, `Name = "A&B <1>"` → the written object
contains `"Icon":"⚓"` and `"Name":"A&B <1>"`. Reading either escaped or raw input yields the same
model.

**TV-OWN-10 — Unknown nested members (OC-02).** Load
`{"Tasks":[{"Name":"a","FutureField":{"x":1}}],"SchemaVersion":1}` → save → the task object still contains
`"FutureField":{"x":1}`, emitted after the task's known keys.

**TV-OWN-11 — `.aasched.json` bytes (OC-41).** Export a one-entry template (06 §4.5 example values) → file text equals
the 06 §4.5 example, with CRLF line ends, `"VesselId": null`, 2-space indent, and no space before any colon.

**TV-OWN-12 — Excel serials (OC-20).** Authoritative table: 10 Addendum §X.8.3. Spot checks that a verifier can run
against both the Mac reader and this ruling (DateTime style, id 14): `0 → 1899-12-31`, `1 → 1900-01-01`,
`59 → 1900-02-28`, `60 → 1900-03-01`, `61 → 1900-03-01`, `45658 → 2025-01-01`, `46294 → 2026-09-29`; `60.5` → the
import fails with ClosedXML's leap-year message; 1904 workbook `44623 → 2026-03-04`. None of these may be produced
by plain `FromOADate` (which gives `59 → 1900-02-27`, `60 → 1900-02-28`).

**TV-OWN-13 — Number-format kinds (OC-21).** Authoritative tables: 10 Addendum VESSEL-307 and §X.8.2. Spot checks:

| numFmtId / code | Kind |
|---|---|
| 14, 15, 16, 22 | dateTime |
| 17, 27, 49, 0, 2 | number |
| 18, 20, 45, 46, 47 | timeSpan |
| `yyyy-mm-dd`, `dd/mm/yyyy hh:mm`, `d-mmm-yy` | dateTime (`y` / `d` first) |
| `mmm d` | dateTime (`m` look-ahead skips the space, meets `d`) |
| `h:mm`, `hh "h" mm` | timeSpan (`h` first) |
| `mm:ss`, `[h]:mm:ss` | timeSpan (`m` look-ahead meets `s`) |
| `[h]:mm` | dateTime (`[h]` skipped, `m` reaches the end) |
| `"m"0.00`, `[Red]0.00;[Blue]-0.00`, `@` | number |
| `AM/PM h:mm` | dateTime (the `m` of `AM` looks ahead to `p`) |

**TV-OWN-14 — Sheet names (OC-22).** `Crew` → `Crew`; `report` → `report`; `Ports of Call` → `Ports of Call`;
procedure `A/B: [x]` → `A_B_ _x_`; `History` → `Checklist`; `'Quoted'` → `Quoted`; a 40-character name → its first 31
UTF-16 units; `R&D` → written `R&amp;D` in `workbook.xml` (escape after truncation).

**TV-OWN-15 — Intra-Run newline (OC-15).** Load `<Section …><Paragraph><Run>line one&#xA;line two</Run></Paragraph></Section>`
(SIRE shape), type `X` at the end of the paragraph, save → the paragraph keeps `line one` LF `line two` inside Run
text, followed by the new text (no `<LineBreak />` for that break, no second paragraph). Insert ⇧↩ instead → a
`<LineBreak />` appears at the caret. The untouched-load case is 05 Addendum vector XD-W4 (byte-identical).

**TV-OWN-16 — Keychain names (DATA-215).** With the test `SecretStore`: enable local encryption → one item
`AA.LocalDataKey`/`v1`; sign in to Drive → one item `AA`/`google-token-key` and a file
`google-token/Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive` starting with `AAKCGCM1`; set the Gemini
key → one item `com.eriskay.aa.gemini`/`GeminiApiKey`, and `settings.json` has no `GeminiApiKey` key; clear it with a
blank prompt (06 BUILD-145 B2) → the item is deleted.

**TV-OWN-17 — Reminder notification (OC-33).** Two consecutive reminder checks with different counts → exactly one
delivered notification with identifier `aa.reminder` (the second replaces the first); the Dock tile has no badge.

**TV-OWN-18 — Window instancing (OC-17, OC-32).** Press ⌘F twice → two Search windows. Choose Tools ▸ Activity Log…
twice → two log windows. Press ⌘N twice → one Quick Work window (scene `quick-work`), activated.

**TV-OWN-19 — Trash wording (OC-19).** Open File ▸ Trash (Restore Deleted Items)… → a sheet (not a window) with
buttons `Restore`, `Delete permanently`, `Empty Trash`, `Close` and the 08 QUICK-171 text verbatim.

**TV-OWN-20 — Search highlight (OC-54).** In both appearances the matched run in a Search result is bold black text
on `#FFE066`.

**Verification checklist for reviewers of any spec-implementing PR:**

1. Find the component in DATA-202…210; confirm the code cites the owner (DATA-221).
2. If the PR follows a subordinate text, check DATA-213 for a ruling; if none and the texts differ, file a new
   OC entry (OWN.3.5) instead of choosing silently.
3. Any new shortcut: add it to DATA-214 and rerun TV-OWN-02.
4. Any new Keychain item or Mac-private identifier: add it to DATA-215 / `Identifiers`.

---

### OWN.8 Open questions

* **Q-OWN-1** *(resolved)* OC-20/OC-21 were first drafted from the base texts; the 10 Addendum (§X.2 D14) settled
  them from the ClosedXML 0.104.2 source. Nothing remains open here; fixture checks are 10 §X.8.9.
* **Q-OWN-2** The product owner may still overrule OC-19 (Finder wording in the Trash), OC-36 (friendly enum labels,
  "Notes & Files") and OC-33 (Dock badge). Each is display-only and would be applied app-wide.
* **Q-OWN-3** Bundle-id prefix: keep `com.eriskay.aa` (brief) and rename 01's `com.bepavida.aa.*` identifiers
  (OC-07), or change the bundle id to `com.bepavida.aa`? Either way, one prefix.
* **Q-OWN-4** Ship the optional SIRE shortcuts (12 §6.3)? DATA-214 reserves ⌥⌘1…⌥⌘4 and ⌥⌘B for them; if they are
  not shipped the combinations stay unbound.
* **Q-OWN-5** Harmonise the three Keychain service names (DATA-215) under the bundle id before the first release
  (cheap now, needs a migration later)?
* **Q-OWN-6** The brief mentions an `ARCHITECTURE.md` "written by the architect". It does not exist yet. When it is
  written it sits at DATA-200 rule 1 below the brief, and any conflict with this map must be resolved there
  explicitly.
