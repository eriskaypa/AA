# AA for macOS — deviations and P2 fixes (consolidated)

Consolidated on 2026-10-03 by the integrator (acting for the lead, ARCHITECTURE.md §12.2, OWNERSHIP.md §2) from
`Docs/Deviations/<id>.md`, which stay the owners' source records: an owner who adds a deviation edits its own file and
the next consolidation copies it here. Sections follow the OWNERSHIP.md order; each section is the owner's file
verbatim with its headings moved down one level. Format inside the tables: ID · spec reference · one line.

Re-consolidated after Stage V round 1 (fix branches `fix1/*` merged, 2026-10-03): every section was regenerated
from the owners' current files, so rows added, reworded or removed in round 1 appear here as their owners wrote them.

| Owner | Source file | Lines |
|---|---|---|
| F1 | [`Deviations/F1.md`](Deviations/F1.md) | 39 |
| F2 | [`Deviations/F2.md`](Deviations/F2.md) | 46 |
| F3 | [`Deviations/F3.md`](Deviations/F3.md) | 38 |
| W-SHELL | [`Deviations/W-SHELL.md`](Deviations/W-SHELL.md) | 52 |
| W-PERSIST | [`Deviations/W-PERSIST.md`](Deviations/W-PERSIST.md) | 37 |
| W-GOLD | [`Deviations/W-GOLD.md`](Deviations/W-GOLD.md) | 65 |
| W-RICH | [`Deviations/W-RICH.md`](Deviations/W-RICH.md) | 42 |
| W-CONT | [`Deviations/W-CONT.md`](Deviations/W-CONT.md) | 56 |
| W-FILES | [`Deviations/W-FILES.md`](Deviations/W-FILES.md) | 23 |
| W-HIER | [`Deviations/W-HIER.md`](Deviations/W-HIER.md) | 48 |
| W-BUILD | [`Deviations/W-BUILD.md`](Deviations/W-BUILD.md) | 23 |
| W-PLAN | [`Deviations/W-PLAN.md`](Deviations/W-PLAN.md) | 70 |
| W-QUICK | [`Deviations/W-QUICK.md`](Deviations/W-QUICK.md) | 36 |
| W-CREW | [`Deviations/W-CREW.md`](Deviations/W-CREW.md) | 39 |
| W-VESSEL | [`Deviations/W-VESSEL.md`](Deviations/W-VESSEL.md) | 32 |
| W-PDF | [`Deviations/W-PDF.md`](Deviations/W-PDF.md) | 38 |
| W-SIRE | [`Deviations/W-SIRE.md`](Deviations/W-SIRE.md) | 52 |
| W-FLASH | [`Deviations/W-FLASH.md`](Deviations/W-FLASH.md) | 57 |
| W-DRIVE | [`Deviations/W-DRIVE.md`](Deviations/W-DRIVE.md) | 42 |

---

## Post-wave contract resolutions (lead, 2026-10-03)

The contract requests were resolved after the merge (`Requests/<id>.md` "Resolution:" lines; amended signatures in
DECISIONS.md "Contract amendments (post-wave)"). These consolidated rows below are superseded:

| Row | Owner | Now |
|---|---|---|
| W-PERSIST-15 (⌘S key monitor) | W-PERSIST | Removed — F3's `AppEnvironment.doSave` presents "Read-only — not saving" (406368f). |
| W-PERSIST-4 (`.sameUserNoApp` → `.otherUser`) | W-PERSIST | `InstanceGuardResult.sameUserNoApp(pid:)` exists; the alert path is unchanged (f15d0b9). |
| REQ-W-SHELL-02 (menu-bar preference guard) | W-SHELL | F3's binding no longer persists a spurious "off"; only a one-time repair of an older stored `false` remains (192cefc). |
| Q-11 (02) "checklist steps wait for REQ-W-HIER-02" | W-HIER | Checklist steps are selected through `ProcedureChecklistSection(procedureID:revealStepID:)` (5742235). |
| GOLD-R5 (portsDate / portsTime not compared) | W-GOLD | Compared through `VesselText.normDate` / `normTime` (0976386). |
| 14 §6.5 indicator only in Settings ▸ Sync (W-DRIVE notes) | W-DRIVE | Toolbar indicator added (6ef95ac); the Settings row stays. |
| W-PLAN / W-CREW / W-SIRE notes on `HSplitView` under the shortcut strip | W-PLAN, W-CREW, W-SIRE | The shell lays the strip out below the sections (916cfb9); the owners' own split implementations (CalSplitView, SireSplitHandle) stay. |

## F1 — deviations and P2 fixes

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`.

### P2 defect fixes (files stay readable by Windows with the same meaning)

| ID | Spec ref | Fix |
|---|---|---|
| D-5 | 01 §8.1, DATA-080, 05 CONT-007, DECISIONS 01 | `PasswordService.setPassword(_:current:migratingLegacyBodiesIn:)`: before re-salting, every live legacy `enc:` body (REPO-012 `allContainers`) that the typed current password or the unlocked session password decrypts with the **old** salt is written back as plaintext (`IsLocked` cleared, CONT-007 form) and the data file is saved first; if that save cannot happen (read-only / safe mode, paused writes, write error) the change throws `.legacyBodiesNotSaved` and the password and salt stay unchanged. Bodies nothing decrypts are kept (never `""`) and counted (`LegacyBodyMigration.undecryptable`) for the caller's warning (`orphanWarning(count:)`, pre-check `undecryptableLegacyBodyCount(in:current:)`). Trash payloads (`PayloadJson`) are not rewritten. |
| D-6 | 01 §8.1, DATA-080, DECISIONS 01 Q-4 | `PasswordService.setPassword(_:current:)` requires the current password (master accepted) when one exists. |
| D-7 | 01 §8.1, DATA-150, DECISIONS 12 | The Mac never writes `GeminiApiKey`; a value found in settings.json is preserved verbatim by every key-level merge (the Keychain copy is W-SIRE's). |
| D-14 | 01 §8.1, DATA-032, ARCH §6.2 | `DataStore.saveTo` serialises a deep **copy** stamped `LastModified = now` with `SchemaVersion = max(v, 1)`; the live model's stamp and dirty state are untouched. |
| D-16 | 01 §8.1, DATA-182 | settings.json writes are atomic (`AtomicWrite`); a refused write sets `SettingsStore.lastWriteRefused` so the caller posts `SettingsStore.unreadableStatus`. |
| D-18 | 01 MP.8, DATA-182 | Every settings setter is a key-level merge that retries 3 × 50 ms and never writes over an unreadable file (memory keeps the value). |
| D-23 | 01 MP.8, DATA-182 | `SettingsStore.writeRawTree` (Flash Sync apply) is atomic and refuses over an unreadable file; it never reloads. |
| 02 D-9 | 02 §6 (REPO-003a) | The writer writes to the data-file URL captured at enqueue time, not the one current at write time. |
| 06 §7.13 / 11 DEV-03 | OC-22 | XLSX sheet names: sanitise → truncate to 31 UTF-16 units (never splitting a surrogate pair) → escape, so an entity is never cut in half (Windows escaped first). Identical output for every name Windows actually passes (`Crew`, `report`, `Ports of Call`). |
| 11 §7.14 | 09 §3.10 | `XlsxWriter.xmlEscape` also drops U+FFFE / U+FFFF (XML-illegal; Windows wrote them and produced an unreadable workbook). |
| DATA-180 | 01 MP.3.4 | Writes go through the `DataFileWriteGuard` hook (refusal → `.pausedByGuard`, stamp rolled back, writes paused); the hook is a no-op until W-PERSIST installs its implementation. |
| §3.8 rule 2 | ARCH §3.8 | An `int`/enum value outside Int32 is clamped, recorded, and fails the save (`AppStoreError.serialization`) instead of writing a file Windows cannot load. |

### Sanctioned divergences (Mac superset or Swift limits)

| ID | Spec ref | Divergence |
|---|---|---|
| SHELL-193 paths | 03 SHELL-193, BD.3.2 | `DataStore` keeps the AppFolder and the active data file **lexically** normalised (`.`/`..` removed, symlinks and the `/private` firmlink prefix kept, `DataStore.lexical`), so the status line, Settings and the persisted `CurrentDataFile` show the path the user gave. Containment tests (`isUnderAppFolder`) compare `DataStore.comparablePath`, which folds `/private/{tmp,var,etc}` onto `/tmp`, `/var`, `/etc`, so both spellings are one folder. |
| OC-02 | DATA-024 | Unknown members are preserved on **every** object (Windows keeps them only at the top level, in `Ui` and in settings.json; it drops nested ones). Emitted after the known keys, verbatim (null, `1.50`, `-0`, `1e2` kept). |
| A06 / A07 | 01 §4.1.10, ARCH §3.8 rule 1 | JSON `null` for a value-typed key (bool/int/double/enum/Guid/DateTime) or for a collection / nested object reads as the C# default instead of failing (Windows: load failure or a later crash). Real type mismatches (`"Done"` for an enum, `60.0` / `6E1` / `2147483648` for an int) still fail the load, like Windows. |
| A06e | 01 §4.1.10, ARCH §3.8 rule 1 | JSON `null` **inside** a collection: a string-array element or string-map value reads as `""` and a model-array element is skipped (Windows keeps the null and fails later in the UI); a `null` GUID-array element or bool-map value stays a load failure (STJ cannot hold it either). Only hand-edited files contain such nulls. |
| A09b | 01 GF.5.a, ARCH §3.2 | A lone surrogate escape (`"\uD800"`) cannot be held in a Swift `String`; it decodes to U+FFFD. |
| A11.3 | 01 §3.20, ARCH §4.3 | A legacy `BucketId` is appended to `BucketIds` (if not already there) whatever the key order; Windows' result depended on whether `BucketId` came before or after `BucketIds`. A malformed `BucketId` is a load failure (`invalidGuid`). |
| A16 | 01 §4.2.6, ARCH §4.3 | Status/IsComplete load rule is order-independent: `Status` present wins (IsComplete = Status == Done); only `IsComplete` → Done/Todo. Windows' result depended on key order for contradicting pairs. |
| Q-6 | DECISIONS Q-6, ARCH §3.4 | A `NetDateTime` keeps the exact text it was read with and writes it back unchanged until edited; calendar dates created/edited on the Mac are written Unspecified, timestamps keep Windows' kind. |
| §3.1 dup keys | 01 §4.1.4, ARCH §3.1 | Duplicate JSON keys keep one pair at the first position with the last value (System.Text.Json "last wins"). |
| S09 | 01 §4.11, DATA-182 | settings.json is read per key: a key with the wrong JSON type reads as that key's default and its raw value is preserved until that very key is set (Windows' catch branch reset every key). An undecodable `PasswordSalt` still takes the catch branch (all defaults except FolderBuilderBase / GeminiApiKey), as on Windows (01 §7.12). |
| AES-CBC | 01 §6.11 | `AESCBC.decrypt` rejects input that is empty or not a whole number of blocks (CommonCrypto would otherwise return a partial block); `.NET` throws in the same case. |
| ContractStatus | ARCH §4.5 vs §6.1 | ARCH declares two types named `ContractStatus` (the crew enum and the placeholder registry). They are one type: the crew enum (`Model/CrewMember.swift`) carries the registry as `extension ContractStatus { static func isImplemented(_:) }` (`Foundation/ContractStatusRegistry.swift`). Call sites in ARCH (`ContractStatus.isImplemented(.wRich)`, `member.contractStatus(on:)`) compile unchanged. |
| Local encryption | DECISIONS 01, 01 §6.5 | DPAPI is replaced by `AAENCM1\n` + AES-256-GCM with a Keychain key (file-based login keychain, generic password, not synchronizable; no `kSecAttrAccessible`, see ARCH §6.3). A Windows `AAENC1\n` file is detected and reported (`DataLoadError.windowsEncrypted`), never decoded. |
| ZIP names | 01 §6.7 | Entries that are absolute, drive-qualified or climb out with `..` are rejected (`ZipError.unsafePath`) before anything is written; Finder metadata (`.DS_Store`, `._*`, `__MACOSX/`, `Icon\r`) is skipped. |

---

## F2 — deviations and P2 fixes

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`.

### P2 defect fixes (files stay readable by Windows with the same meaning)

| ID | Spec ref | Fix |
|---|---|---|
| 02 D-1 | REPO-132, OC-16, DECISIONS 02 Q-1 | `SavedListOrder.nudge`: several picks in a group interleaved with other groups' lists now produce the intended group order (swap with the group neighbour, then re-anchor like `MoveTo`). A single pick or a contiguous group still runs the Windows moves verbatim, so the flat order there is byte-identical to Windows. |
| 02 D-2 | REPO-070 | `trash(_:)` returns nil and records/logs nothing unless the item was actually removed from its top-level collection (a nested subtask or a detached object is never "trashed" while staying in place). `trash(_ member:)` likewise does not record a member that is not in the roster. |
| 02 D-3 | REPO-029, DECISIONS 02 Q-3 | `purgeReferences(to:)` removes **every** occurrence and also scrubs nested subtasks' `RelatedIds`, crew checklist steps' `TaskIds`/`EquipmentIds`, crew schedule and saved-schedule `RefId`s (set to nil), `Ui.QuickViewPinIds`, `Ui.Selected*Id` and `Ui.MapFocusedItemId`. |
| 07 Q-02 | REPO-079/080/081, DECISIONS 07 Q-02 | Eviction, "Delete permanently", "Empty Trash" and the hard-delete paths purge references to the whole deleted subtree (the payload's nested subtask, step and component ids), not just the item id. |
| 01 D-10 / 08 Q-8 | DATA-102, OC-13 | `DataDiff` file keys are count-aware (`Name|Path` multiset: k Added / k Removed nodes) — a container holding the same link twice no longer crashes the preview. Link diffs list first occurrences in collection order. |
| 02 D-17 | REPO-145, DECISIONS 02 Q-12 | `ChecklistTemplateService.writeBackFromSteps` leaves the template untouched when the edited steps carry exactly its content (titles, durations, job flags, container text/lock/shares/files), so an unchanged "Edit items…" no longer regenerates container and file ids. |
| 02 D-5 | REPO-061/062, DECISIONS Q-6 / Q-8, ARCH §3.4 | Recurrence outputs (next deadline, kept-length range start, shifted subtask/step dates), `WorkRange.coerce` dates it changes and `BatchDeadline` values are written as Unspecified calendar dates; a date coerce keeps is returned with its original text. Supersedes 02 T-REC-7 / 01 §7.11 "Local". |
| — | REPO-035 | Unlogged structural edits (`addComponent`, `removeComponent`, `log: false` subtask/step paths, `createTopLevelTask(logKind: nil)`) mark the store dirty, so a caller that forgets to save cannot lose them (Windows relied on the caller's `Save()`). |

### Sanctioned decisions applied (DECISIONS / OC rulings)

| ID | Spec ref | Behaviour |
|---|---|---|
| 02 Q-4 | REPO-081, VIEW-052, ARCH §5.3 | `trashSubtask(_:)`: a nested subtask goes to the Trash as ItemType "Task" with the unknown member `ParentTaskId`; references to it and its descendants are purged; restore re-inserts it at the end of its parent's subtasks (or as a top-level task when the parent is gone). The hard-delete APIs stay for completeness. |
| 09 Clear all | DECISIONS 09 | `trashAllCrew()` moves every crew member to the Trash as one batch (one ⌘Z restores all) and logs a single `Removed / "Crew" / "all {n} member(s)"` line. |
| 08 OQ-7 | REPO-104, 08 Q-6 | Search text joins text nodes separated only by inline run boundaries (`Run`, `Span`, `Bold`, `Italic`, `Underline`, `Hyperlink`), so a word split across formatting runs is found (`Hel|lo` → `Hello`). Every other separator space (paragraphs, line breaks, list items, CDATA, comments, insignificant white space) is exactly Windows'. Supersedes 08 T-SR-5. |
| 08 OQ-8 | REPO-107, 08 Q-7 | `QuickSwitcherScoring.rows(store:)` blanks the description of password-protected items (`rows(store:isGated:)` blanks only items still locked this session), so locked content never influences ranking. |
| 08 OQ-10 | QUICK-194/195, 08 §4.2, 01 §3.15 | `DataDiff` status and recurrence change lines show the friendly labels (`status: To Do → Done`, `status: In Progress → Blocked`, `recurrence: None → Weekly`) instead of the C# enum names (`Todo`, `InProgress`). Only the display text differs; the stored integers and every other diff line are unchanged. |
| 09 Clear all (order) | CREW-061/062, REPO-077 | Every entry of a `trashAllCrew()` batch carries one `DeletedUtc`, so ⌘Z restores the roster in its original order (per-entry stamps would re-append it reversed). Single and multi-select (`trashItems`) deletes keep per-entry stamps as Windows. |
| 01 Q-3 | DATA-103 | `DataDiff.compareOtherData` — the opt-in "Other data" section (crew members incl. checklist and schedule, saved lists, saved schedules, ports DB, SIRE session). The Windows-scope `compare` is unchanged. |
| 02 Q-11 | REPO-101 | Every search hit carries the matched component/subtask/step id (`childID`) for the UI to select. |
| OC-11 | REPO-102 | A gated item is searched by Name and Tags only. |

### Divergences by necessity (Swift / platform limits) and documented residuals

| ID | Spec ref | Divergence |
|---|---|---|
| sort stability | 01 §3.15, REPO-107, REPO-077 | Where C# uses an unstable `List.Sort` (DataDiff roots) the Mac sorts stably (ties keep collection order). Ranking ties and batch-undo ordering are stable as in C# LINQ. |
| surrogates | REPO-103, 01 §3.15, VESSEL-314 | Snippet and `snip` cut points never split a surrogate pair; `_xD800_`-style lone surrogates in XLSX text become U+FFFD (Swift strings cannot hold a lone surrogate). |
| ParseDate | 09 §6.3, §7.1 | `NetDateParser` is a deterministic emulation of `DateTime.TryParse(InvariantCulture)` covering every shape of 09 §6.3 plus time-only input (VESSEL-327 note): ISO forms with `T`/space, `Z`/`GMT`/`UTC`/`±hh[:mm]`/`±hhmm` (converted to local), month-first numerics with any of `/ - . , space`, 2-digit years pivoting at 2049, English month and weekday names (full or 3 letters, weekday must match), `AM`/`PM`/`A`/`P`, year-less dates (year of `today`). Not emulated: non-English or genitive month names, `Sept`, era/ordinal forms, offsets beyond ±14 h — they return nil. |
| XLSX laziness | VESSEL-302, §X.7.2 | Sheets are parsed lazily: a damaged worksheet the reader never loads does not fail the import (Windows' ClosedXML loads every sheet at open). |
| XLSX formulas | VESSEL-318, §X.10 Q14 | A formula cell without a cached value renders `""` (non-empty for the used range); `XlsxWorksheet.uncachedFormulaCount()` + `XlsxRender.uncachedFormulaHint(count:)` give the Mac-only status suffix. |
| XLSX formats | VESSEL-308, §X.10 Q22 | An unterminated `"` in a custom format classifies as Number (Windows hangs). |
| XLSX Strict | §X.4.2 | Strict-namespace relationships are accepted (Windows' OpenXML SDK rejects Strict files). |
| XLSX messages | VESSEL-302, §X.4.13 | The corrupt-package message is `The file could not be opened as an Excel workbook (.xlsx).` followed by a newline and a one-line detail (Windows shows the library's own text). A 1904 date pushed past 9999-12-31 reports .NET's `The added or subtracted value results in an un-representable DateTime.` |
| ExcelDate numbers | §3.4.4 | The `NumberStyles.Any` fallback accepts white space, a leading/trailing sign, parentheses, the invariant currency symbol `¤`, `,` group separators in the integer part, a `.` fraction and an exponent. |
| schedule import | REPO-154 | A schedule file that is not valid JSON or has a wrongly typed value fails with a Mac message (`ScheduleImportError.parse`); `null` keeps the Windows text `This file is not a valid schedule.` |
| perf test | ARCH §9.7, §X.7.2 | The 2 524 × 16 budget (< 200 ms) is asserted for optimised builds (`swift test -c release -Xswiftc -enable-testing`: < 50 ms); the unoptimised debug gate asserts < 1.5 s. |

---

## F3 — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| W-1 | 03 SHELL-027, §3.3, §6.3 | Tab order is applied first, then `SelectedMainTabIndex` selects `order[index]` (`SectionID.restoredSelection`). |
| W-6 | 03 SHELL-140, 08 QUICK-210 | `Navigator.navigate(to:)` switches by the item's kind / top-level owner, never by a fixed tab index. |
| W-7 | 03 SHELL-032, DECISIONS 03 Q-3 | Reloads keep the Mac's window geometry and per-device `Ui` keys (`captureUiState` + `copyPerDeviceValues`); geometry is applied only at launch, clamped to visible screens. |
| W-9 | 03 SHELL-050/052, 01 DATA-026/027 | ⌘S, the 5-min autosave, the quit pipeline and Flash Sync flush every registered editor (`EditorFlushCenter.flushAll`), not only the four hierarchy pages. |
| W-11 | 03 §6.6.2 | Every `loadDataAndInitUI` re-applies the appearance (a synced `DarkMode` change wins over a stale Light/Dark choice) and the menu toggles are derived live from settings. |
| W-12 | 03 SHELL-048, SHELL-513 | ⌘W exists: closes the key window; on the main window it runs the quit pipeline; close-type sheets close on ⌘W / ⎋. |
| W-14 | DECISIONS 03 Q-5 | A failed final save on quit offers Retry / Quit Anyway / Cancel (Cancel restarts shared sync, reminders and the autosave timer). |
| W-16 | 06 BUILD-141 | The shared prompt's label wraps. |
| W-17 / W-18 | 03 SHELL-194, SHELL-197 | Data-folder pre-flight with Try Again / Quit before the splash; crash.log falls back to `~/Library/Logs/AA/crash.log`. |
| SHELL-001 | 03 §6.1, BD.3.5 | The signal marker opens crash.log inside the handler (`open`/`write` only), so a clean run never creates an empty crash.log (BD.4.8). |
| D1 / D2 text | 03 App. A.3 | "created under a different Windows account" → "created under a different user account or on another computer"; "update AA on this PC" → "this Mac" (PC→Mac rule). |
| D27 buttons | 03 §6.5 | Shared-save prompt uses `Reload (Discard My Changes)` / `Keep Mine`; the body's Yes/No lines are reworded to those names. |
| OQ-3 | DECISIONS 08 | ⌘F / ⇧⌘F / toolbar Search reuse the single Search window (`env.open(.search)` + `SearchWindowActions.focusQuery`). |
| SHELL-506 | 03 §6.5.1.1 | AA ▸ Settings… is SwiftUI's own item for the `Settings` scene (replacing `.appSettings` duplicates it), so it stays enabled during the login phase; the Settings window is W-SHELL's and needs no data. |
| ARCH §7.1 | ARCHITECTURE.md §7.1 | `.aaWindowRoot` registers each window with `SceneOpener` (role, presenter) but does not overwrite `NSWindow.identifier`: SwiftUI uses its own identifiers to find and focus single-instance `Window` scenes. `SceneOpener.window(for:)` answers from the registry. |
| §6.5.1.6 View order | 03 §6.5.1.6 | SwiftUI places the toolbar group first in View; `AppKitMenuBridge` re-orders the View menu after every SwiftUI rebuild (menu-delegate proxy) so the tree matches §6.5.1.6. Paste and Match Style (⌥⇧⌘V) and the Spelling / Substitutions / Transformations / Speech submenus are inserted by the bridge (SwiftUI's default Edit groups omit them). |
| CONT-026 palette | 03 SHELL-609 | Format ▸ Font ▸ Highlight offers six pastel swatches (never `#FFE699`, the lock sentinel), No Highlight and Other…; W-CONT validates/performs them via `aaValidate`/`aaPerform`. |
| §9.6 rendering | ARCHITECTURE.md §9.6 | The snapshot hook renders the window's layer tree, re-draws glass-hosted split-view columns (macOS 26 floating sidebar) piece by piece with `cacheDisplay`, and composites an attached sheet; materials and glass are approximated as flat fills. |
| additive | 03 §6.2, 01 §6.9 | Toolbar status-history popover (last 20 messages) and a shared-save popover (path, Check Now, Stop…). |
| additive | 03 §6.2 | Sidebar context menu Move Up / Move Down / Customize Tab Colors…. The brand header ("AA" + the verbatim tagline) is fixed above the section list (it does not scroll) and the tagline wraps naturally (caption, muted, up to 3 lines). |
| sidebar colour | 03 §6.2, SHELL-029 (FIX-F3, V-DESIGN) | A custom tab colour is a 20×20 rounded (radius 5) tile behind the section's SF Symbol, glyph in the SHELL-029 contrast colour, instead of a full-row fill. The selected row uses native sidebar selection; a coloured section's active row adds a semibold title and a 2-pt accent underline (the "active marker"). `TabColors` data unchanged. The Crew badge is the native list `.badge` and is recomputed at `NSCalendarDayChanged`. |
| §6.5.1.13 bridge | 03 §6.5.1.13, SHELL-509/578/591/592/640/660 (FIX-F3) | Every SwiftUI-driven menu (Edit, Format and its submenus, Tools, View, Window…) gets a delegate proxy that re-applies the bridge right after SwiftUI rebuilds it in `menuNeedsUpdate`, so Paste and Match Style, the four text submenus and the hidden aliases are never missing. The bridge also inserts View ▸ Enter Full Screen (⌃⌘F, `toggleFullScreen:`, retitled by AppKit) when SwiftUI's rebuild drops it, and collapses doubled separators in Window. |
| G2 switcher | 03 SHELL-505, §6.5.1.10, DECISIONS 08 OQ-2 (FIX-F3) | The quick switcher is non-modal on the Mac, but while it is the key window G2 applies (every APP / MAIN command disabled; Quit, Hide…, About, Keyboard Shortcuts, list/move commands and ⌘W Close stay). |
| D1 cause | 01 §6.5, DECISIONS 01 DPAPI (FIX-F3) | The D1 safe-mode alert keeps the §6.5 Mac text (now with the "(a file encrypted by AA on Windows can only be opened on that PC — export a bundle there and import it here)" parenthetical) and, for a Windows-encrypted file or an unavailable Keychain key, leads with `DataLoadError`'s own sentence. The safe-mode status line appends " The file was encrypted by AA on Windows." / " The Keychain key for this Mac's encrypted file is unavailable." in those two cases (additive). |
| password prompt | 03 SHELL-161 table, DECISIONS 01 Q-4 (FIX-F3) | ChangeExisting has three fields on the Mac (Current / New / Confirm), so its prompt reads "Enter the new password and confirm it on the line below." instead of "…on the second line.". |
| SHELL-552 help | 03 §6.9, DECISIONS 03 Q-7 (FIX-F3) | The shared-save help ends "…point every computer at the same file to keep them in sync." (PC→Mac rule, matching the D29 box). |
| subtitle | 03 SHELL-022 (FIX-F3, V-DESIGN) | The main window subtitle shows the status message with any path abbreviated (`~` for home, middle-truncated to 60 characters); the full text stays in `StatusCenter`, the status button's help and the history popover. |
| toolbar | 03 §6.2 (FIX-F3, V-DESIGN) | The status-history button and the Drive indicator sit in the leading group with the shared-save capsule; the primary actions (Due, Search, Go to, Reload, Save) follow in spec order. |
| prompt sheet look | 06 BUILD-136…150 (FIX-F3, V-DESIGN) | The shared prompt follows the NSAlert layout (headline title, 11-pt body, native rounded-bezel field, 16-pt margins); text, buttons and behaviour unchanged. |
| hidden pages | 04 HIER-025/040/120, ARCH §7.2 (FIX-F3) | Visited sections stay alive but the hidden ones are `.disabled` (out of the key-view loop and their keyboard shortcuts), and after every section switch — and when the main window opens — keyboard focus moves to the section sidebar unless it is already there, so no keystroke reaches a page the user cannot see. |
| banners | 01 DATA-021, §6.8, §6.10, DATA-174/180/184 (FIX-F3) | The main-window banners are laid out above the section content (not a safe-area inset) by `ShellBannerStack`, which never measures them narrower than 560 pt, so AppKit's minimum-size query can no longer grow the split view past the window. |
| item picker | 07 VIEW-208…211, A.6 (FIX-F3) | Multi mode: a click toggles at once (no double-click handler, so a double-click is two toggles); ↑/↓ move a list cursor and Space toggles it; each row is one accessible toggle. Single mode unchanged (click chooses, double-click chooses + OK). |
| TOOLS-027 | 03 D15, 14 TOOLS-027 (FIX-F3) | The "Confirm import" fallback uses Yes / No buttons (it used Replace / Cancel). |
| §9.6 DEBUG | ARCHITECTURE.md §9.6 (FIX-F3, V-PACKAGE) | `ShellDebugSnapshots.swift` and the registration calls in `SnapshotRegistry.registerAll()` compile only `#if DEBUG`; the wave owners' `<Area>DebugSnapshots.swift` files are wrapped by their owners (cross-owner request), after which `SnapshotRegistry` itself can be wrapped. The snapshot hook also draws the sidebar column's own SwiftUI content above its list (the fixed brand header). |

---

## W-SHELL — deviations, P2 fixes and not-applicable IDs (ARCHITECTURE.md §12.2)

### P2 fixes and sanctioned deviations

| ID | Spec ref | Change (one line) |
|---|---|---|
| W-2 / Q-7 | 03 SHELL-066, D29, DECISIONS 03 Q-7 | The "Shared save file" info box says the shared file is autosaved "every minute" (the real cadence), not "every 10 minutes". |
| D-6 / Q-4 | 01 DATA-080, 03 SHELL-101, DECISIONS 01 Q-4 | Changing an existing app password requires the current one (the master password is accepted); an empty new password still does nothing. |
| Q-5 | 01 DATA-034 / D-17, 03 SHELL-063, DECISIONS 01 Q-5 | Import from File asks **Copy into AA Folder** (default) or **Use in Place** (Windows behaviour) after the review gate; the default data file itself is adopted without asking. |
| DATA-179 | 01 DATA-179 | Use in Place takes the per-user external-file lock before the file becomes active; another holder cancels the import with "That file is already open in another copy of AA." |
| §6.9 | 03 SHELL-066, §6.9 MAC-ADAPT | Set Shared Save File first asks **Join an Existing Shared Save File…** (open panel → D28 with "Use Its Contents" / "Overwrite It" / "Cancel") or **Create a New Shared Save File…** (save panel; confirming a replace = D28 "Overwrite It"). All three Windows outcomes stay reachable. |
| P2 | 03 SHELL-066, 01 DATA-021 | Set Shared Save File is refused in safe mode and in a read-only instance (D4 text): pushing from there would overwrite the shared bundle with an empty or stale database. |
| P2 | 03 SHELL-065, 01 DATA-021 | The encryption toggle is also refused in a read-only instance (D32 text), where nothing can be written. |
| W-9 | 03 SHELL-061/070/071, W-9 | Save a Copy As, Export / Import Data Folder and Import from File flush every live editor first (Windows flushed four pages or none). Reload from Disk keeps the Windows rule (no flush). |
| DATA-040 | 01 DATA-040 | An export destination inside AppFolder is refused before anything is saved ("Choose a destination outside the AA data folder." under "Export failed"). |
| Q-7 / Q-8 | 02 REPO-113, 03 SHELL-132, W-8, DECISIONS 02 Q-7 | The digest also runs at the local day change (`NSCalendarDayChanged`) and after a wake; the date this Mac last showed the digest is kept per data file in UserDefaults (`aa.shellx.digestDates`) and wins over a pulled `LastDigestDate`. `Ui.LastDigestDate` is still written and marked dirty exactly as on Windows. |
| Q-13 | 03 SHELL-130/131, §6.8, DECISIONS 02 Q-13 | Tray icon and balloon → MenuBarExtra (headline, per-bucket counts, crew line, Show Due Dates…, Show AA, Settings…, Quit AA), UserNotifications (`aa.reminder`, banner while frontmost, click → due-dates panel) and a Dock badge with the overdue count. Unbundled runs and `--smoke-test` post the text to the status line instead (`AA — due soon: …`). |
| Q-16 | 03 SHELL-196, BD Q-16 | When `EncryptLocalData` is on, the local data file is plaintext and this Mac has no local-data key, AA asks **Encrypt** / **Keep Plaintext** (writes paused while asking); Keep Plaintext turns the setting off. |
| SHELL-190 | 03 SHELL-190, REQ-F3-02 | The "Move AA to Applications" sheet is shown once per launch when `ReminderCenter` starts (after the main window and the D1/D2 alerts), never in smoke runs. |
| PC → Mac | 03 Appendix A.3, §6.9 | D31 "on this Mac only"; D33 = the 01 §6.5 Mac wording verbatim ("a key stored in your macOS Keychain", "Only THIS Mac's local file", "between computers"; 01 owns the DATA-070 strings, DATA-202 A14); D29 "Point every computer at this same file." |
| D12 | 03 SHELL-069, 01 DATA-012 | NSWorkspace reports no error text, so Open Data Folder's failure box says "Finder couldn't open the data folder:\n\n{path}" under "Open failed". |
| BD.3.7 | 03 BD.3.7, SHELL-185 | A Finder document that vanished before it was drained shows "Import failed" with the .NET wording "Could not find file '{path}'." |
| §6.10 | 01 §6.10 (File ▸ Shared Save ▸ Check Now) | Check Shared Save Now posts "Checked the shared save file (HH:mm:ss)." when the coordinator found nothing to reload and posted nothing itself. |
| SHELL-115 | 03 SHELL-115, D26, §6.4, BD.3.11 | About AA is a small window (icon, "AA", tagline, `Version x (n)`, build date and commit, the exact credits line, data folder with Show), not an information box; the credits text is unchanged. |
| SHELL-523 (layout) | 03 SHELL-523, ARCHITECTURE.md §8 | The shortcuts window is a native `Table` (resizable Command / Mac / Windows / Menu columns, one section per menu, alternating rows) so the column headers always line up with the cells. |
| Q-13 (menu) | 03 §6.8, 02 REPO-112 | The menu-bar menu shows the Windows headline split into one line per non-zero part with its exact wording (`{n} overdue`, `{n} due today`, `{n} due this week`, `{n} crew contract(s) expiring`), or `Nothing due.`; the joined headline is not repeated above them. |
| REQ-W-SHELL-02 | DECISIONS 03 Q-4 | Main phase: a stored `aa.menuBarExtra = false` that the user did not choose is turned back on (local workaround for the F3 binding, see Requests). |
| SHELL-523 | 03 SHELL-523 | The Windows column of the shortcuts window drops the registry's spec cross-references and WPF access-key underscores (`E_xit` → `Exit`); a reference-only cell shows "—". |
| §6.4 | 03 §6.4 | Settings: General (identity with Use Mac Name, appearance System/Light/Dark, shortcut bar, menu-bar item, notification settings link, data folder, version), Security (password status, Set/Change Password…, Lock Now, encryption toggle, on-disk state), Sync (shared save file with status, Change…/Check Now/Stop Using…, text-only exports, W-DRIVE's section), File Links (W-PERSIST), AI (W-SIRE). Data-bound controls are disabled until the user has signed in. Committing a blank identity resets it to this Mac's name (BUILD-145 B1). |
| BD.3.12 | 03 BD.3.12 | The smoke harness treats a window as shown when it is ordered in (`isVisible`); `occlusionState` stays "occluded" while the display sleeps or another Space is in front, which made unattended runs time out. |
| §9.4 | ARCHITECTURE.md §9.4, 03 BD.4.1 | Info.plist also exports `com.eriskay.aa.job-ref` and `com.eriskay.aa.item-ref` (all in-app drag types; BD.4.1 listed only `task-ref`). |
| BD.3.9 | 03 BD.3.9 | build-app.sh builds only the `AA` product per slice with `-j $AA_JOBS` (default 3, shared build Mac) and copies each slice aside, because every `--triple` writes into the same `.build/out/Products/Release`. |

### IDs satisfied by their Mac counterpart (Windows-baseline rows of 03 §N)

| ID | Note |
|---|---|
| SHELL-170 | Windows single-file publish → SHELL-180 (one self-contained `AA.app`, no runtime). |
| SHELL-171 | "Runs from any folder; data elsewhere" → SHELL-180 (read-only bundle) + SHELL-190 (translocation) + F3's data-folder resolution. |
| SHELL-172 | Embedded resources → SHELL-184 (flat copies + SwiftPM bundles in `Contents/Resources`, checksums verified). |
| SHELL-173 | Dependency trimming → not applicable: `Package.swift` has no dependencies; nothing to trim. |
| SHELL-174 | Framework-dependent variant → not applicable (the Mac build links only OS libraries). |
| SHELL-176 | Build gate → SHELL-200/201 (warnings as errors, no `warning:` lines, tests) inside build-app.sh steps 3–4. |
| SHELL-177 | Smoke test → SHELL-204 (manual checklist, Install.txt/README) and SHELL-205 (`--smoke-test`, implemented and run). |

### Not done in this worktree (needs another owner, Windows data or other hardware)

| ID | Why |
|---|---|
| SHELL-206 | Cross-version data smoke needs a folder written by the Windows build (and the Windows app for Mac → Windows); Stage V. |
| SHELL-207 | Clean-machine / Intel run needs a second Mac or user account; the x86_64 slice is executed under Rosetta by build-app.sh only when Rosetta is installed. |
| SHELL-204 | The manual checklist (BD.7.7) is documented; steps that need a person (Finder double-click, camera prompt, Gatekeeper) were not performed by the agent. |

---

## W-PERSIST — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| D-1 | 01 DATA-052, 03 SHELL-124 (W-4) | The 1-minute tick pushes when `IsDirty \|\| LastModified > lastSynced` (`SharedSaveCoordinator.hasUnsyncedChanges`), not only when dirty. |
| D-2 | 01 DATA-055 | On close the bundle stamp is compared with the last sync (own push / declined stamp / not newer than `lastSynced` → push); a bundle another copy wrote since then is not overwritten — our model is kept as a `-mine` conflict copy (DATA-181) instead. Without any sync this session the Windows rule (local ≥ bundle) applies. |
| D-3 | 01 §3.10 | Smart import, shared import and `ApplySyncedData` decode the staged JSON fully before `files/` or the data file are touched. |
| D-12 | 01 §8.1 | A shared-save pull while the local file is unreadable (safe mode) always asks first and copies the unreadable file to `data.unreadable-{yyyyMMdd-HHmmss}.json` before replacing it. |
| D-13 | 01 DATA-040 | The "inside the AA data folder" test uses a trailing separator (`…/AA2/x.zip` is accepted). |
| W-PERSIST-1 | 01 DATA-180, §MP.3.4 | Deliberate replacements of the data file (bundle imports, shared pulls, Flash Sync apply, conflict restore) skip the pre-write check (MP.7.5 X-7) but first keep any foreign version found on disk as a `-theirs` conflict copy; the new fingerprint is recorded. |
| W-PERSIST-2 | DECISIONS 05 | A folder or package is zipped into one `files/<32hex>_<name>.zip`; entries sit under the folder's name; Finder metadata is skipped; symbolic links inside it are neither followed nor stored (the in-house ZIP writer has no link entries). |
| W-PERSIST-3 | 01 §6.6 | `.localized` joins `.DS_Store`, `._*`, `Icon\r`, `__MACOSX/` as Finder metadata (never bundled, counted, swept or zipped). On a case-sensitive volume, an imported attachment differing only in case replaces the local one (Windows/NTFS semantics). |
| W-PERSIST-4 | 01 §MP.3.3, ARCH §6.6 | A holder of the same user without an app bundle (`swift run`, `.sameUserNoApp`) maps to `InstanceGuardResult.otherUser(user)` (no forwarding); the alert reads the full detail from `InstanceGuard.folderBlocked` and shows the same-user wording without "Switch to Running AA". |
| W-PERSIST-5 | 01 DATA-173, §MP.4.2 | The distributed notification is `Identifiers.instanceRequestNotification` (`com.eriskay.aa.InstanceRequest`, the Mac identifier registry) instead of `com.bepavida.aa.InstanceRequest`. |
| W-PERSIST-6 | 01 DATA-180 | Texts the spec elides or leaves open: the unreadable variant ends "If you keep yours, theirs is kept as a copy in the data folder's “conflicts” folder."; the deleted variant ends "Keep Mine saves your version again. Stop Editing Here keeps this window open without saving."; statuses "Kept your version — the data file was saved again." (deleted), "Stopped editing here — changes in this window are not saved.", "Editing resumed — the data file was re-read from disk.", "Restored {name} from the conflicts folder." (DATA-181 restore), "Mapped {prefix} to {folder} on this Mac." (Locate…). |
| W-PERSIST-7 | 01 DATA-180 | The sheet adds a "Your version / Their version" facts box under the Windows text (additive, P4) and a "Conflict Copies…" button (ARCH §6.6). |
| W-PERSIST-8 | 01 DATA-184 | "Show Me How" opens the Help anchor `shared-save-setup` when the bundle has a help book; otherwise it shows the setup steps in an information alert (no help book ships yet). The banner lives in `DataFileConflictBanner` (always in F3's banner area). |
| W-PERSIST-9 | 01 DATA-174 | "Switch to Other AA" in the read-only banner activates the editor and keeps this read-only window open (the spec only says the launch alert's Switch quits). A "Show Conflict Copies…" item sits in the banner's ⋯ menu (ARCH §6.6). |
| W-PERSIST-10 | 01 DATA-180 step 3 | The data-file watcher polls every 60 s only on network volumes (local volumes rely on the directory source, as specified); the shared-save coordinator always polls every 60 s (DATA-053). |
| W-PERSIST-11 | ARCH §6.6 | Additive public API: `PersistWriteGate`/`PersistWriteGateError`, `PersistLeaseLoss.enterReadOnly`, `InstanceGuard.retryEditing/relinquishEditing/canEdit`; `BundleService.exportFolderToZipSync`, `peekBundleIdentity`, `readLastModified`; `PathMapper.inferredMapping/upsert/isValidPrefix/canonicalPrefix/uncParts/smbShareURL`; `SharedSaveCoordinator.tick/hasUnsyncedChanges/closePushAllowed/path/isRunning/isHandlingUpdate/isPushRunning`; `DataFileFingerprint.table/state/statusHandler/reloadHandler/onModeChange/checkNow/perform/resumeEditing/reviewData`; `ConflictCopies.readJSON/peekData/restore/saveMine`; `InstanceGuard.folderBlocked/externalBlocked/retryFolderLock/retryExternalLock/relinquishFolderLock/takeOver/isEditor/onLeaseLost`. |
| W-PERSIST-13 | 01 §6.6, 05 §6.9 | `PersistOpenFlow` (AA/PersistenceUI) is the open-with-recovery flow for every owner that opens attachments: missing file → OC-12 text; unmapped Windows path → "Windows path — not available on this Mac" with Locate… (stores the inferred mapping), Connect to Server… (UNC), File Links Settings…, Cancel. |
| W-PERSIST-12 | 01 §6.9 | `SharedSaveCoordinator.push(label:)` updates the status line and indicator like Windows' `PushToShared` and also rethrows (contract `throws`); the Windows flows ignore the error (`try?`), as `adoptSharedFile` does. |
| W-PERSIST-14 | 01 DATA-174, §MP.3.5 | Service-level backstop of the write gate: `BundleService` imports (smart, shared, legacy), `DataStore.applySyncedData` (also the conflict-copy restore), `AttachmentStore.importFile/importData` and `SharedSaveCoordinator.adoptSharedFile` throw `PersistWriteGateError.readOnly` ("Not available in a read-only copy of AA.") before touching anything while `SettingsStore.isWriteGated` (read-only instance, Stop Editing Here). Exports stay available. |
| W-PERSIST-15 | 01 DATA-174 | Until F3 handles ⌘S for a read-only copy (REQ-W-PERSIST-02), the read-only banner installs a local key monitor: ⌘S (exactly; ⇧⌘S Save a Copy As is untouched) shows the sheet "Read-only — not saving" with "OK" (default) and "Switch to Other AA" (when the editing copy runs on this Mac) instead of reaching Save, which wrote nothing and still reported "Saved". |
| W-PERSIST-16 | 01 DATA-175 | After "Stay Read-Only" the 5-s upgrade poll pauses until the live view sees another editor save; without the pause it re-took the lock it had just handed back and showed the same banner again within 5 s. |
| W-PERSIST-17 | 01 DATA-177, §MP.3.3 | In lease mode an EMPTY `.aa.lock` carries no claim (it was just created by this open or by a process that has not written its record yet); only a non-empty unreadable record uses the lock file's mtime. Otherwise the first launch on a network volume refused itself for 90 s. |
| W-PERSIST-18 | 05 §4.2, 01 §6.6, ARCH §6.6 | The stored attachment leaf is `<32hex>_<windowsSafe(original)>`: the 150-unit cap applies to the original part (05 §4.2, ARCH `importData`), and no reserved-device prefix is added (the GUID already makes the leaf legal: `CON.txt` → `<32hex>_CON.txt`). The stored name is the source's own leaf even when it is a symbolic link (File.Copy semantics). |
| W-PERSIST-19 | 01 DATA-180, §MP.3.5 | While editing is stopped ("Stop Editing Here") the shared-save sync and the 5-minute autosave are stopped (DATA-174 list) and restarted on "Resume Editing"; the data-file watcher follows the active file's folder after every reload. |
| W-PERSIST-20 | 01 DATA-179, DATA-175 | A copy that is read-only because the external active data file is held elsewhere polls (and on "Stay Read-Only" hands back) THAT lock — `InstanceGuard.retryEditing()/relinquishEditing()/canEdit` — not the data folder's, which it already holds. |

### Not applicable on the Mac (documented Windows behaviour replaced by the Mac instance model)
* DATA-160, DATA-161, DATA-162, DATA-163, DATA-164 — Windows-only behaviour of two AA processes on one folder; on the Mac
  they are replaced by DATA-170…182 (one editor per folder, read-only instances, fingerprint + conflict copies, key-level
  settings merge by F1). Nothing to reproduce.
* DATA-165 (Flash Sync across processes) and DATA-166 (other shared files) — the cross-process races cannot occur with
  one editor; the per-file Mac remedies are owned by W-FLASH (unique baseline temp name), W-DRIVE (atomic token file) and
  F3 (`crash.log` O_APPEND), per DATA-183.

---

## W-GOLD — deviations from the golden-fixture plan

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`. None of these changes
what any golden asserts about Windows; they are naming, layout and plan refinements.

### Naming and layout

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-N1 | DATA-311, ARCH §12.2 | Swift types carry the `Gold` prefix: `GoldFixtureIndex` (plan: `FixtureIndex`), `GoldZipManifest` (`ZipManifest`), `GoldXMLCanonicalizer` (`XMLCanonicalizer`), `GoldenMatcher` kept; suites `Gold*Tests`. |
| GOLD-N2 | GF.8.6, DATA-313 | Tag `.goldWinFixtures` / `.goldShould` (plan: `.winFixtures` / `.should`); CI filter `swift test --filter Gold` (plan: `--filter WinFixtures`); the emitter suite is `GoldMacOutEmitter` (plan: `MacOutEmitter`). `Scripts/fixtures.sh` uses the new names. |
| GOLD-N3 | GF.4.1, DATA-312 | Fixture roots live in the SwiftPM fixture folder (ARCH §10.2): `Tests/AACoreTests/Fixtures/winfixtures/`, `…/mac-out/`, `…/xaml/wpf-capture/`, `…/xaml/mac-roundtrip/` (plan text: `mac/Tests/Fixtures/…`). |
| GOLD-N4 | GF.4.1 | XLSX goldens: `winfixtures/xlsx/<workbook>.golden.json` (F2's `windowsGoldens` reads the same path); the synthetic 10 §X.8 workbooks the oracle reads are committed in `winfixtures/xlsx-inputs/` (written by the Swift emitter `GoldXlsxInputEmitter`, F2's `SvcXlsxTestBook`). |
| GOLD-N5 | DATA-310 | The windows-run twin of a `Runs.Both` / `Runs.Windows` case is recorded with the id suffix `w` (`A25xw`, `M.R14.smart.L0w`) under `windows/`; `GoldFixtureIndex.windowsTwin` resolves it. |
| GOLD-N6 | DATA-324, GF.6.8 | W19 (DPAPI samples) is a WinFixtures family-(a) case run only on Windows (it needs no WPF), recorded under `windows/json/`. |

### Manifest and comparison extensions

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-M1 | GF.4.5 | Extra token `%%DATADIRUPPER%%` — the data folder upper-cased, which A25 writes on case-insensitive file systems. Masked only as a whole literal; the Swift matcher accepts the Mac folder upper-cased (invariant). |
| GOLD-M2 | GF.4.4 | Per-output `compare` (overrides the case mode), `pointer` and `"mac": false` (a Windows record the Mac does not reproduce). `macExpectation.file` may carry `#/json/pointer`; `macExpectation.compare` overrides; a `divergent` expectation without `file` is record-only (the Mac rule is asserted by the owner's own tests, the reason cites them). |
| GOLD-M3 | GF.4.4, DATA-303 | `nonDeterministic: true` (K04: real random-IV blobs are decrypt-only vectors) — excluded from `--verify-only` byte comparison like `dependsOnToday` outputs. |
| GOLD-M4 | GF.4.7 | Exception shapes: `type` is never compared when the object carries `aaAuthored` (Swift error types cannot be .NET type names); `message` is compared only when `aaAuthored` is true. |
| GOLD-M5 | GF.3.9, GF.4.6 | In `zip-manifest` mode the uncompressed size and CRC of masked AA-format payloads (`data.json`, `source.json`, `settings.json`) are not compared — their bytes are compared `bytes-masked` from the payload golden instead. |
| GOLD-M6 | DATA-308 | Must-level cases whose Swift side needs another owner's private code are registered as *pending* reproducers: reported (never silent) and a failure only under `AA_REQUIRE_FIXTURES=1` (Requests REQ-W-GOLD-01…04). |

### Case catalogue refinements (GF.5)

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-C1 | GF.5.a A12 | A12 split: A12.1–6 (one per zone, must) and A12.7–12 (`DateTime.MinValue` as Local per zone, record-only — LMT offsets differ between tz databases). |
| GOLD-C2 | GF.5.a A16 | Extra reversed-member pairs (`Status` before `IsComplete`) whose Mac expectation is derived from the canonical order (01 §4.2.6 order-independent rule, 02 T-DONE-12, D-21). |
| GOLD-C3 | GF.5.a A25 | A25 split: A25 (POSIX-form paths, unix), A25x (Windows-form paths, `Runs.Both`, record-only on unix, must on Windows), A25s (`ImportFile("a:b?.pdf")`, divergent record-only: the Mac sanitises, 01 §6.6). |
| GOLD-C4 | GF.5.e E01 | E01.19 split into 19a (Snip at 40/41, must) and 19b (emoji straddling 40, should, divergent record-only). |
| GOLD-C5 | GF.5.e E16 | E16 (zone-free computed strings) plus E16.1–6 (display strings per zone) and E16.th (th-TH culture probe, record-only). |
| GOLD-C6 | GF.5.f X01 | X01 split into X01.rel, X01.purge (T-REL-9 is the sanctioned Mac divergence of DECISIONS 02 Q-3 — divergent record-only), X01.rec, X01.recToday (dated by `DateTime.Today`, record-only), X01.tr, X01.log. |
| GOLD-C7 | GF.5.b | Settings: the Mac reproduces reading (`state.load`, `reload`, `verify`); the Windows file bytes and post-call state are `mac: false` — the Mac writes settings by key-level merge (01 DATA-182) and keeps the Gemini key in the Keychain (DECISIONS 12 Q-6). |
| GOLD-C8 | GF.5.c | B06b (sibling folder `<datadir>2`) and the R14/R15/R17 matrix rows are record-only/divergent where 01 D-13 or file-system semantics make the Mac differ by design. |
| GOLD-C9 | GF.6.8 W21, GF.5.c | The Explorer ZIP joins the matrices as `M.R20.{smart,shared}.{L0,L1}` and `P.R20` (`Runs.Both`: record-only on unix, `should` on windows — the shell's name encoding is platform-dependent, 01 §6.7). The archive is an authored Windows artefact at `windows/bundles/R20.explorer.bundle.zip`: `CaseDef.RequiresFile` skips the rows (no record) until it is committed, and `Driver.PrepareStaging` carries it over so a windows run never deletes it with the regenerated `windows/bundles/`. |

### Reverse direction and inputs

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-R1 | GF.8.5 | `mac-out/` holds real Mac output: salts, IVs, new GUIDs and "now" stamps change on every emission. `check-mac` asks the C# to load/verify/decrypt them and compares only re-serialisation, never against a golden. `INDEX.json` lists the files and the sections skipped. |
| GOLD-R2 | GF.8.5 | `bundles/` and `xaml/` are emitted only once W-PERSIST / W-RICH have flipped their ContractStatus (the stubs cannot produce them); the always-on `GoldMacOutTests` asserts the skip is reported. Mac-created XAML documents are built from AppKit attributes (lists via `NSTextList`, tables via `NSTextTable`, links, super/subscript, lock run attributes) and written by W-RICH's `XamlWriter`. |
| GOLD-R3 | GF.8.5 | `mac-out/settings/*.json` avoid Mac paths (they do not exist on Windows); the `.expect.json` keys are those of `FamilyB.Dump`. |
| GOLD-R4 | 10 §X.8 | Re-emitting `xlsx-inputs/` changes only ZIP timestamps (F2's test-book writer stamps the current time); the workbook content is identical. Regenerate the XlsxGolden goldens after a re-emission. |
| GOLD-R6 | GF.6.7, GF.6.10 | The manual confirmations are consumed by `GoldManualCaptureTests` (enabled once `xaml/wpf-capture/manual/` exists): M-01…M-05 against their W twins on the claim each pair settles (root start tag S-1, Table S-4, Hyperlink S-5, Typography.Variants S-9, whole empty document S-10), `xml:lang` ignored (AA.exe stamps typed runs, WinCapture does not); M-06 text survival; M-07 = W20 against the E13.X1 oracle (part sequence + the four content-independent parts `text-lf`, sheet/workbook recorded); M-09 required iff W06 is empty; M-capture re-saved byte-identically in the capture zone and checked against the extracted notes. The plan names no Swift consumer for these; without one the captures would settle nothing. |
| GOLD-R7 | GF.6.7 | The extraction script also writes `manual/M-capture.timezone.txt` (the capture machine's IANA zone) and WinCapture's MANIFEST run records `ianaTimeZone`: AA.exe writes Local stamps with the machine's offset, so the Mac reproduces M-capture byte-for-byte only in that zone (A14 shows a re-save elsewhere rewrites offsets). |
| GOLD-R8 | GF.9, DATA-326 | `GoldAcceptanceGateTests` checks GF.9 items 1 (provenance = the pinned commit and hashes; a longer `git %h` abbreviation of the same commit is accepted), 3 (the GF.1.1 ledger, encoded row by row, resolves against the committed manifests), 6 (under `AA_REQUIRE_FIXTURES=1` every fixture source — manual, W23, XlsxGolden, clipboard inputs — must exist) and 9 (the read-only Windows sources still hash to `original-source-checksums.sha256`, always on). The new test `GoldW01bRootTagTests` asserts GF.6.10 (a new Mac document's root start tag = W01b's) once W-RICH has flipped. |
| GOLD-R5 | 10 §X.7.6 | `portsDate` / `portsTime` (the Ports reader's `NormDate` / `NormTime`) are recorded by XlsxGolden but not compared yet — W-VESSEL's private code (REQ-W-GOLD-04). |

### Tooling

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-T1 | GF.0, DATA-300 | The C# oracles were written and reviewed by inspection only: this machine has the .NET 10.0.12 runtime but no SDK, and installing one is a download. The first `Scripts/fixtures.sh generate` (macOS) and `WinCapture all` (Windows) are also the compile check. |
| GOLD-T2 | DATA-314 | WinFixtures pins `AA_DATA_DIR` to a never-created scratch path in the parent process before the case catalogue touches `DataStore`, so no process of the tool can resolve the operator's real `%LOCALAPPDATA%\AA`. |
| GOLD-T3 | DATA-313 | `Scripts/fixtures.sh` adds `xlsx-golden`, `emit-xlsx-inputs`, `real-data <path>` and `status` to the commands named in GF.8.6. |

### Progress record

Moved to `Docs/Progress/W-GOLD.md` (REQ-W-GOLD-05).

---

## W-RICH — deviations, P2 fixes and porting decisions

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`.

### Sanctioned decisions applied

| ID | Spec ref | Decision |
|---|---|---|
| RICH-D01 | 05 §8 K-12, §9 Q9, DECISIONS 05 | HTML paste whitespace is cleaned up: a whitespace-only text node never opens a paragraph (no `" "` paragraphs between blocks), whitespace held in a block's not-yet-written paragraph is dropped with it, and a paragraph opened by a block element that a nested block closes before any content (`<div><p>…`) leaves nothing. A truly empty `<p></p>` still gives `<Paragraph />` (a blank line). §7.1 H7 is tested in its cleaned form. |
| RICH-D02 | 05 §8 K-13 | `rgba(…, 0)` (alpha 0) is "no colour" (inherit) instead of black; any other alpha is still ignored. |
| RICH-D03 | 05 §6.4 "Opaque" | The opaque attachment class is `XamlPreservedAttachment` (spec name `PreservedXamlAttachment`, renamed for the ARCH §12.2 prefix rule). |
| RICH-D04 | 05 §4.3.7 rule 11, XD.2.13 | Thicknesses are written in the canonical 4-value form and colours as `#AARRGGBB` (modelled values); carried attributes keep their original tokens. An empty `<Run></Run>` is not content and is not written back (`<Paragraph><Run></Run></Paragraph>` → `<Paragraph />`, same document). |
| RICH-D05 | 05 XD-X8 | `Foreground="{x:Null}"` shows the inherited colour and is not written back (sanctioned in XD.7). |
| RICH-D06 | 05 CONT-169 | N/A — CONT-169 is the reserved upper bound of the XD range; no behaviour (OWNERSHIP §4 note). |

### P2 fixes (data-compatible)

| ID | Spec ref | Fix |
|---|---|---|
| RICH-P01 | 05 §3.3 rule 2 | CF_HTML `StartFragment`/`EndFragment` are honoured as UTF-8 **byte** offsets (Windows used char indices, wrong for non-ASCII headers). |
| RICH-P02 | 05 §3.3 rules 5–9 | HTML attribute values are entity-decoded (`href="a?x=1&amp;y=2"` → `NavigateUri="a?x=1&amp;y=2"` in XAML = `a?x=1&y=2`); HtmlAgilityPack's default left `&amp;` literal, breaking such links. |
| RICH-P03 | 05 §3.2, §3.1 `ChangeIndent` | Indent/outdent treat an `Auto` (NaN) left margin as 0 (`Math.Max(0, NaN)` left the paragraph stuck on Windows); the other sides stay `Auto` (`24,Auto,Auto,Auto`). |
| RICH-P04 | 05 CONT-162 | Recognised attributes with invalid values and markup extensions are never re-emitted, so a Mac save makes such documents loadable again. |
| RICH-P05 | 05 CONT-155, XD-X6 | Every read resolves against a fresh context (no wrapper values leak between containers). |

### Implementation choices (no data effect)

| ID | Spec ref | Choice |
|---|---|---|
| RICH-I01 | 05 §3.3 ("SHOULD use XMLDocument(.documentTidyHTML)") | The HTML is read by a small HtmlAgilityPack-shaped parser (lower-cased names, void elements, raw-text script/style, li/tr/td/th auto-close) instead of Tidy, because Tidy restructures documents (inserts `<p>`, `<tbody>`) and would change the converter's output against the Windows vectors. |
| RICH-I02 | 05 §4.3.1, XD.2.1 step 7 | Without `xml:space="preserve"`: whitespace runs collapse to one space; text at the edges of an inline container and next to `LineBreak` is trimmed; a Run's own text is only collapsed (XD-V6 keeps `Hi `). |
| RICH-I03 | 05 §6.4, XD.2.10 | Paragraph structure lives on the characters (`.richContainerPath`: Section/List/ListItem/Table/RowGroup/Row/Cell descriptors with carried and modelled values; `.richParagraphModel`), so lists and tables survive editing, undo and in-app copy/paste; AppKit-native lists/tables (RTF paste) are reconciled from `textLists`/`textBlocks`. `RichTextMetadata.elementAttributes` is filled as the contract asks. |
| RICH-I04 | 05 §6.4, §6.7 | Every paragraph, including the last, ends with `\n` (the text view shows one insertion line after the last paragraph). An empty "synthetic" paragraph follows a table that ends the document (§6.4 "keep an ordinary paragraph after a table"); it is never written while empty. |
| RICH-I05 | 05 §6.2, 12 §6.5 (display only) | Auto paragraph margins use the font's line height; margins collapse as `max(prevBottom, top)`; an un-normalised List without `Padding` indents 49 pt; a Table without `CellSpacing` uses WPF's 2; paragraph/section/list blocks span the container width. |
| RICH-I06 | 05 XD.2.10 `wanted()` | Text inside a Hyperlink created on the Mac whose colour only inherited is written link-styled (no `Foreground`), as WPF's wrap would leave it; links read from XAML keep their exact colours. |
| RICH-I07 | 05 XD.2.10 Run `BaselineAlignment` | Sub/superscript applied on the Mac (no preserved token) is written as `BaselineAlignment="Subscript"/"Superscript"`; a preserved `Typography.Variants` token is kept while the shift still matches it. |
| RICH-I08 | 05 XD.2.10, XD-W7 | A font picked on the Mac that is the system monospaced / UI substitute is written as `Consolas` / `Segoe UI`; any other Mac family is written by name. |
| RICH-I09 | 05 §3.2, CONT-044 | Tab on the first item of a list (no previous sibling to nest under) is consumed without change; Return on an empty item outdents it (top level → ordinary paragraph); toggling a list on paragraphs next to a list of the same marker style merges with it (WPF `MergeLists`). |
| RICH-I10 | 05 XD.3 lockSource row | `LockRules.unlock` removes a block-level sentinel from the paragraph model or from the container descriptors of every paragraph of that container (whole-element unlock) and drops the gold display block. |
| RICH-I11 | 01 §4.11 invariant 1 | Untouched bodies are protected by `RichTextMetadata.sourceHash` (FNV-1a, stable across launches) in the editor; `write(read(x))` is a byte-for-byte fixed point for Mac-written XAML and semantically equal for Windows-written XAML. |
| RICH-I12 | 05 XD.2.12, CONT-162 | Tolerant display of invalid nesting the spec leaves open: elements inside a `Run`'s content are shown at their source position (`XamlDocument.runChildOffsets`) — recognised inlines as real content inheriting through the Run, anything else as a verbatim chip; a recognised non-row element where `TableRow`s belong becomes an implicit row (and cell) of its own, as `processRow` already did for cells. A rewrite of such a note is loadable and a fixed point (input mutation fuzzing). Unknown elements and misplaced blocks inside inlines stay verbatim chips (§4.3.7 rule 10), so such a note stays `.notLoadable` as it was. |
| RICH-I13 | 05 CONT-162/164/165 | The writer drops an invalid recognised attribute from the loaded root too (root completion then supplies the context value), and a carried `X.Foreground` property element on a block takes part in the CONT-164 cascade like the attribute form (it is dropped from an empty paragraph, whose character properties come from the terminator). |

---

## W-CONT — deviations and P2 fixes

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`. Stored data stays
readable by the Windows build with the same meaning in every row.

### P2 defect fixes

| ID | Spec ref | Fix |
|---|---|---|
| 05 D-1 | CONT-007, §6.10 | A legacy `enc:` body that the unlocked session cannot decrypt (master password, other machine, changed salt) keeps its ciphertext and is shown withheld with a banner; Windows replaced it by `""` and saved. |
| 05 D-2 | CONT-011 | The editor's own undo manager is cleared on every load; Undo after switching items can no longer pour the previous item's text into the current one. |
| 05 D-3 | CONT-008, §6.12 | One editable editor per container: the newest binding wins, older editors flush, turn read-only with a banner and reload when it closes; external changes to `RichTextXaml` (modal editors, Flash Sync apply) reload an editor that has no pending edit. |
| 05 D-4 / K-5 | CONT-063, CONT-066, 03 SHELL-524, SHELL-689 | The lock gate sits in `shouldChangeTextInRanges`: typing, IME, Backspace/Delete, word deletes, cut, paste, drag-move, spelling corrections, Services, dictation, find-and-replace and text undo/redo are all filtered with the §3.1 geometry. Highlight and Clear formatting keep the sentinel on locked runs. Non-editing shortcuts (⌘S, ⌘1…, ⌘N) are never swallowed. Lock/unlock stay undoable (parity). |
| CONT-006 | §6.7 | A withheld note (locked or undecryptable legacy body, unparseable XAML, or no rich-text engine in the build) is read-only with an inline banner instead of "typeable but never saved". Without the real engine (or with a placeholder parse) this includes blank and readable notes, so nothing is ever typed into a note that cannot be saved. The legacy-locked banner offers **Unlock…** (the CONT-062 gate) and reloads. |
| — | §6.4, §4.3.7 rule 6, XD.3 | Typed, plain-pasted and link text never inherits `.aaListMarker`, `.aaInRunNewline`, `.aaPreservedXaml` or an attachment from the neighbouring run; right after a list marker the item's first character supplies the typing attributes. Otherwise text typed at the start of an item would be tagged as marker text and dropped by the writer. |
| CONT-021 overflow | 05 §7.3, BUILD-145 B5 | Insert table: oversized numbers clamp (`99999999999x2` → 50×2) and non-ASCII digits are "no match" → 3×3, where Windows threw. Typed font sizes are capped at 1 638 (WPF's `MaxFontPoint`) instead of crashing above ≈35 791. |
| CONT-043 NaN | §3.1 `ChangeIndent` | A paragraph whose left margin is Auto/NaN indents from 0 (Windows' `Math.Max(0, NaN)` left it stuck). |
| — | §6.7 | `RichTextXaml` is assigned (and the store marked dirty) only when the serialised string changed and the document differs from what was loaded; untouched notes are never rewritten (Windows called `MarkDirty` on every tick). |
| — | §6.12 | Typing next to locked text never extends the lock (the sentinel is removed from the typing attributes); typing at the end of a link does not extend the link. Boundaries stay editable exactly as §3.1 says. |

### Sanctioned decisions and Mac refinements applied

| ID | Spec ref | Behaviour |
|---|---|---|
| K-3 | CONT-024 | Strikethrough and underline toggle independently (WPF strike replaced the underline). Stored format unchanged. |
| K-7 | CONT-022 | Selecting text never stamps family/size onto runs. |
| K-13 | CONT-035 | Pasted transparent backgrounds become "no colour". |
| K-14 | CONT-031, BUILD-146 | Insert hyperlink uses its own sheet: title `Insert hyperlink`, label `URL:`, initial `https://`, Insert disabled until the URL parses (every rejected input was a silent no-op on Windows); an empty selection inserts the normalised URL at the caret (Windows appended it at the end of the paragraph). A caret inside an existing link edits that link (Update). |
| K-15 | CONT-032 | Insert table goes after the caret's block — the whole list when the caret is in a list, the whole table when it is in a table, else the caret's paragraph — and an ordinary paragraph is added after the table when nothing (or another table) follows. The prompt is the shared `TextPromptSheet` (B5: never validating). The format bar adds a hover grid (up to 8×10) plus **Custom Size…** (the B5 prompt). |
| K-16 | CONT-021 | A typed font size applies on Return or when the field loses focus, not per keystroke; leaving the box with the value it already showed applies nothing (K-7). The size field shows at most two decimals (display only). |
| CONT-020 | XD.5 | The family control shows the stored token; a family that is not installed here is listed under "Stored in this note (shown with a substitute)". Picking a family (bar or Font panel) replaces `.aaFontFamilyName`; a weight/style change drops the original weight/style tokens. |
| CONT-022 | §6.3 | The bar also reflects bold, italic, underline, strike, alignment and list state. |
| CONT-025/026 | §6.3, 03 SHELL-608/609 | Colour pop-overs replace the WinForms dialog: text colours (Automatic = `#FF1A1A1A` ink, theme and standard rows, More Colors… = system panel); highlights (the six router swatches plus grey and coral, No Highlight, More Colors…). `#FFE699` is never offered; picking it in the system panel still creates a lock (data semantics). |
| CONT-030 step | 03 SHELL-519, T-KB-28 | Format ▸ Bigger / Smaller (⌘+ / ⌘−) step every run by WPF's `OneFontPoint` (0.75), bounded 0.75…1 638 (WPF internal: confirm with a fixture). |
| CONT-030 baseline | 03 SHELL-607 | Superscript / Subscript / Use Default set (not toggle) `Typography.Variants`. |
| CONT-030 ⇧↩ / ⌃↩ | 03 SHELL-681 | ⇧↩ and ⌃↩ insert a line break (U+2028). |
| CONT-031 | 03 SHELL-678 | ⌘-click opens a link; a plain click only places the caret. Context menu adds Open Link, Copy Link, Edit Link…, Remove Link. |
| CONT-033 | §6.8 | The right-click menu keeps the Windows items (every suggestion in bold, `(no spelling suggestions)`, `(locked — can't correct)`, Cut, Copy, Paste, `Paste text only` with ⌥⇧⌘V, Select All); Windows' "Ignore All" is the Mac's **Ignore Spelling**, also offered on a locked word (§6.8; Windows hid it there). |
| CONT-020…061 | §6.3 | The format bar keeps the Windows toolbar order (ContainerEditor.xaml:21-55) in rounded groups: font + size · B I U S · colour, highlight · alignment · bullets, numbering, indent, outdent · insert saved list, move up, move down · undo, redo · link, table, clear · lock, unlock — then the Mac additions find and zoom. The family menu starts with **Show Fonts… (⌘T)**. When the pane is too narrow for one row the bar folds instead of wrapping (§6.3 "overflow Menu when narrow"): first alignment and lists become pop-up menus, then saved list / move, lock / unlock and find / zoom move into a trailing `ellipsis.circle` menu, then undo / redo and link / table / clear too; only a pane too narrow for that wraps. Folded commands keep their Format-menu names (Align Left, Center, Align Right, Justify, Bulleted List, Numbered List, Indent, Outdent, Saved List…, Move Up, Move Down, Lock Highlighted Text…, Unlock Highlighted Text…, Link…, Table…, Clear Formatting, Find in Note…, Zoom) and their tooltips. |
| CONT-001 | §6.2, V-DESIGN 9 | The 260 pt file-bank height is the default only: on a short pane the bank gives way until the paper (below the format bar and banners) has 200 pt; the bank never drops below 110 pt. The #FCFCFC paper is presented as a page — inset 8 pt in the notes pane, radius 6, 1-pt `AAColor.border`, a soft shadow in dark mode — never an edge-to-edge slab. |
| CONT-034 | 03 §6.5.1 | Paste text only is also Edit ▸ Paste and Match Style (⌥⇧⌘V); the inserted text never carries a lock or a link from the destination. |
| CONT-036/038 | DECISIONS 05, §6.6 | Pasted / dropped images go to the file bank as copies (`AttachmentStore.importData` → `FileBankOperations.addImported`) with a short inline notice; Finder files dropped or pasted onto the text go to the file bank (none = copy; ⇧ or ⌥⌘ = link in place, SHELL-679). Foreign RTF is reduced to the storable subset (fonts with family tokens, sizes, colours, B/I/U/S, links, baseline, paragraph styles incl. lists and tables). |
| CONT-036 | §6.6 | Copy writes our own `com.eriskay.aa.xaml` type (from the real writer) next to RTF and plain text; paste prefers it. |
| CONT-039 | 03 SHELL-517, §6.5.1 | In-note find bar (⌘F when the editor has focus; ⌘G / ⇧⌘G / ⌘E / ⌘J; Replace passes the lock gate) and a per-Mac zoom (75 %…200 %, pinch; `aa.editor.zoom`). Windows had neither; ⇧⌘F still opens the global Search window. |
| CONT-040…046 | §6.5, §7.8 | Tab / ⇧Tab / Backspace at an item start, list toggles, indent/outdent and move run `RichListFormatter.normalise` afterwards (so "Tab on item 2 → nested circle" holds); Return normalises only when the list depth changed. Each is one undo step. |
| CONT-047 | §6.11 | The Insert Saved List sheet says ⌘Z instead of Ctrl+Z. A withheld note keeps the button enabled so the Windows `Nothing inserted` message can still be shown. |
| CONT-064 | §6.8 | Outside the main window the locked hint is a beep plus a short inline notice at the foot of the paper. |
| CONT-001 | §6.1 | The 6 pt splitter is a drag handle with a resize cursor; minimum heights keep both panes usable; the split is not persisted (parity). |
| SHELL-685 | 03 SHELL-514 | ⎋ and ⌘. are passed to the next responder (they close or cancel the surrounding sheet); completion stays on ⌥⎋ / F5. |

### Not applicable / not shipped

None — every W-CONT feature ID is implemented. Behaviour that depends on W-RICH's real reader, writer and list
engine (rendering stored notes, saving, list structure) is exercised by the gated tests and the Stage V checks;
in this worktree the placeholder reader makes every stored note withheld (read-only, never written), by design
(ARCHITECTURE.md §6.7, §11).

---

## W-FILES — deviations and P2 fixes (ARCHITECTURE.md §12.2)

P2 fixes and sanctioned deviations applied by the file bank, the read-only viewer, Quick Look and the backlinks
section. Stored data keeps the Windows shape in every row (no new keys, same `Path` forms, same `Kind` integers).

| ID | Spec ref | Change (one line) |
|---|---|---|
| D-5 | 05 CONT-087, §8 D-5, DECISIONS 05 | Cut + Paste is a true move: the same entry (same Id) is appended to the target and removed from the source container; a second paste of the same clipboard makes copies (Windows cut mode switches off after one paste). Duplicate FileItem Ids in data are tolerated (rows are identified by object identity). |
| K-8 | 05 CONT-083, §8 K-8 | Add Folder / plain folder drops skip `.DS_Store`, `._*` and `Icon\r`; other hidden files are imported. Files are listed in ordinal name order per folder (Windows: file-system order). |
| K-9 | 05 CONT-082, §8 K-9 | A failed copy is never stored as an absolute path labelled Copy: the alert "Import failed" lists the files and offers "Link in Place Instead" (the entries then have `LinkInPlace = true`). |
| K-10 | 05 CONT-091, §8 K-10 | Show in Finder (= "Open containing folder") reveals in-place folder entries too. |
| K-11 | 05 CONT-093, §8 K-11, 07 VIEW-210 | The Link to Items picker (F3's shared picker) keeps selections hidden by the search filter; OK still applies VIEW-215 replace-and-normalise + MarkDirty. |
| K-17 | 05 CONT-080, §8 K-17 | The Added column uses the user's locale (short date + time), not en-US. |
| DECISIONS 05 | 05 CONT-093, CONT-095 | Additive UI for data Windows never shows: a "Linked to" column on every tab, `FileBacklinksSection` (item backlinks, with Show Owner / Link to Items… / Unlink from This Item), a "Shared" view listing the files of every container whose `SharedWithContainerIds` names this one, and a Sharing menu (Share With… picker, Show Owner, Stop Sharing). Ids that name no loaded container are kept untouched. |
| Locks | 04 HIER-057 analogue, PDF Q6 | Files of a password-gated owner are never listed in the Shared view or in backlinks: one "(locked item — unlock it to see its files)" line per owner, counted but not named. |
| §6.9 superset | 05 §6.9, CONT-096 | Multi-selection in every tab; list and icon views (per-Mac preference `aa.filebank.viewMode`); QuickLook thumbnails; drag rows out to Finder/Mail (file URLs, links as URLs); per-tab counts; empty states; Quick Look (Space / ⌘Y), ⌘↓ / ↩ / double-click open; context-menu additions Quick Look, Open With ▸, Copy Path, Cut / Copy / Paste. |
| Open | 05 CONT-089 | Open (button, menu, ↩, ⌘↓) opens every selected entry, Finder-style (Windows: the first selected); Rename… and Link to Items… act on the first selected entry, as on Windows. |
| Clipboard | 05 §6.9 | The file-bank clipboard is app-wide (works across windows) and is mirrored to the system pasteboard as file URLs (⌘C in AA, ⌘V in Finder/Mail works). When the system pasteboard changed since (e.g. ⌘C in Finder), Paste imports its files as copies and its web URLs as links. |
| Drops | 05 CONT-085, §6.9, SHELL-679 | Modifier ⇧ or ⌥⌘ links in place (Finder's make-alias gesture; SwiftUI has no link drop operation, so the cursor shows copy and the drop overlay names the mode). Dropped web URLs become web links (CONT-086 shape). Files already in this bank are skipped; a file from AA's own `files/` folder (dragged from another bank) is referenced, not re-copied. |
| Packages | DECISIONS 05 | A package dropped/added as a copy is one zipped `files/` entry (W-PERSIST's `AttachmentStore.importFile`); its display name gets `.zip` so it is not mistaken for the original package. |
| Link in place | 05 §6.9 | New in-place links store a Windows-openable form when one exists: the per-Mac path-mapping table in reverse (`/Volumes/Ops/a.pdf` → `Z:\a.pdf`), else the UNC form of a mounted SMB share (`\\server\share\…`), else the POSIX path. Existing paths are never rewritten (CONT-097). The Link in Place panel accepts files and folders (Windows: files only, folders via Shift-drop). |
| Windows paths | ARCH §9.4, DECISIONS 10 Q4 | Opening an unmapped drive-letter path shows "This file is on a Windows drive (Z:). …" with "File Links Settings…"; an unmapped UNC path offers "Connect to Server…" (Finder mounts `smb://server/share`, the open is retried for 15 s) and "File Links Settings…". |
| Viewer | 04 HIER-136, HIER-M06, §6.8 | The read-only viewer is a sheet (820×620): ⎋ / ⌘W / ↩ close it; its file list adds Quick Look (Space / ⌘Y), ⌘↓ / ↩ open, drag out, Show in Finder and Copy Path; the text view supports the find bar (⌘F routed via `AARichTextResponder`, kind `.viewer`). |

---

## W-HIER — deviations and P2 fixes (ARCHITECTURE.md §12.2)

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

---

## W-BUILD — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| D1 | 06 §8 D1, BUILD-072, A10, REPO-131…134 | Saved Lists sections are keyed by group **Id** (equal names stay separate); a dangling `GroupId` shows under "Ungrouped" and is arranged there too (↑ / ↓ / Move to position / drag treat it as ungrouped; Windows treated it as a group of one); "Ungrouped" is always last (explicit, not via U+FFFF). Data unchanged (pure permutation, `GroupId` kept). |
| D2 | 06 §8 D2, BUILD-079, 07 VIEW-211 | "Move to group…" preselects the list's current group (or "(No group — ungrouped)"); OK needs a choice, so an empty OK can no longer ungroup by accident. |
| D3 | 06 §8 D3, BUILD-063, DECISIONS 02 Q-12 | Template editor writes back only when the items changed (no container/file id churn); if the list was deleted meanwhile the user is asked "Save as New List" / "Discard Changes"; in a saved-list step Deadline/Done are shown disabled with "Set when the list is applied". |
| R1 | 06 §8 R1, ARCH §2.4 | Builders, editors and the procedure checklist re-resolve their owner by id on every read; a vanished owner shows an orphan state instead of editing detached objects. |
| R3 | 06 §8 R3, §6.3, §6.5, 11 PDF-022 | "Export ALL (PDF)…" is reachable with no list selected (empty detail state and the tab's overflow menu) and stays enabled with zero lists, so "No saved lists to export." is shown (Windows: the button sat in the disabled-when-empty detail pane). |
| T-KB-40 | 03 T-KB-40, W-9 | An open template editor registers with `EditorFlushCenter`, so ⌘S, autosave and the quit pipeline write its edits back. |
| buttons | 06 §6.2 | Yes/No/Cancel boxes use explicit verbs: Replace / Append / Cancel (load a saved list) and Rename… / Delete… / Cancel (manage list / manage group); the Windows sentences are kept verbatim. Destructive confirmations default to Cancel (03 §6.5). |
| glyphs | ARCH §8.5, DECISIONS P4 | Emoji / "+ " / "..." button prefixes become SF Symbols and the `…` glyph (e.g. "💾 Save as list..." → `square.and.arrow.down` "Save as list…", "+ Item" → `plus` "Item"). ↑/↓ are icon-only buttons with the Windows tooltips. Window titles become sheet headers. |
| additive | DECISIONS 06 | The subtask editor has a nested "Subtasks" section (add, edit recursively, reorder, delete, open the builder). |
| additive | 06 §6.2 | Drag-and-drop reorder in the builders (BUILD-A3 with the drop index) and within a Saved Lists group (`SavedListOrder.moveTo`); disabled while Sort A-Z is on. |
| additive | 06 §6.2 | ⌘↩ Add all; ↩ / double-click Edit…; ⌃⌘↑/↓, ⇧⌘M, ⌫ through the list-command registry; context menus on builder lists, Saved Lists and the item preview. |
| design | V-DESIGN rules 2/4, 06 BUILD-002/042, 06 §6.2 | Builder button bars are one non-wrapping row: labelled buttons when the row fits, else icon buttons with the Windows tooltips (BUILD-002's "wrapping bar" no longer wraps); the "Saved lists:" strip collapses into a "Saved lists" menu when narrow. Saved Lists: row names regular weight (BUILD-071 "semi-bold"), Rename / Duplicate / Move to group… / Manage groups… / Move to position… / exports in an `ellipsis.circle` overflow menu (same names, also in the row context menu), Sort A-Z is an icon toggle. The procedure banner's exports move under it when the row is narrow. |
| additive | 06 BUILD-045 | Builder rows show a small badge with the number of deeper subtasks carried by a subtask; the subtask builder footer counts them. |
| additive | 04 HIER-095 | The step editor shows the step's linked tasks / equipment as read-only chips. |
| additive | — | Procedure checklist shows "{done} of {n} done" with a progress bar; Link tasks… / Link equipment/area… / Remove / Edit… are disabled without a selected step (Windows: silent no-op); the bulk pane shows "{n} lines ready to add". |
| additive | BUILD-022 | An invalid duration keeps the model unchanged (parity) and gets a faint red outline. |
| bulk box | BUILD-002, A28 | The bulk text box is a plain-text, no-wrap NSTextView with smart quotes/dashes/autocorrect off (raw text like the WPF TextBox). |
| labels | DECISIONS 04 Q-G | Status / Recurrence pickers show friendly labels ("To Do", "In Progress"…); the stored integers are unchanged; an out-of-range stored value is offered as its own row so it round-trips. |
| not mine | OWNERSHIP §4 | BUILD-091…096 (saved-list / checklist PDF + XLSX exports) are W-PDF's: the buttons call `PdfExportFlows`. BUILD-101 (`SavedListPicker` → tasks) is W-PLAN's; BUILD-102 is W-QUICK's; BUILD-110…125 (crew schedule builder) are W-CREW's; BUILD-100 is W-CONT's; BUILD-130/131/136…150 are F3's. |

---

## W-PLAN — deviations and P2 fixes

Spec 07 (Calendar, Board, Planner, Buckets, Relationship Map) + 02 REPO-031, 05 CONT-050, 06 BUILD-101 / BUILD-145
B3·B4, 09 CREW-091. Format of the deviation tables: ID · spec reference · one line. Stage V merges them into
`Docs/DEVIATIONS.md`.

### Progress record

Moved to `Docs/Progress/W-PLAN.md` (REQ-W-PLAN-01).

### P2 defect fixes (data stays readable by Windows with the same meaning)

| ID | Spec ref | Fix |
|---|---|---|
| W-01 | 07 §4.2.7 | Every Board / Calendar / Planner / Buckets action resolves the store and the target item by id at action time; nothing captures a repository or model object across a reload. |
| W-02 | 07 VIEW-013 | The Done checkbox writes the model first, then MarkDirty + FlushIfDirty. |
| W-03 | 07 §4.1.4 | Agenda occurrences read the live model, so ticking one occurrence updates its siblings at once. |
| W-04 | 07 VIEW-048 | Board cards show their selection (accent ring + selection fill); ⌘-click / ⇧-click per column, ⌘A selects the focused column. |
| W-05 | 07 VIEW-094 | The Planner day header and due strip scroll horizontally with the hour grid (one horizontal scroll view). |
| W-06 | 07 VIEW-083 | The pool search field shows its placeholder "Search jobs...". |
| W-07 | 07 VIEW-093 / 097 | Today is tinted (accent at 5–8 %) in both appearances in the header, due strip, hour column and month cell. |
| W-10 | 07 VIEW-205 | Calendar procedure rows, Planner procedures (Q-07), Buckets Task/Procedure members and Map nodes navigate through `Navigator.navigate(to:)` (by kind, never by tab index). |
| W-13 | 07 VIEW-179 / 181 | A node click also selects the item in the Inspect list; the map redraws live from the store (relationship edits, reloads). |
| W-15 | 07 VIEW-014 / 151 | Double-click acts only on the clicked row (Table / List `primaryAction`), never a stale selection; the Done checkbox is isolated from the row's double-click. |
| W-17 | 07 §2.4 | An immediate save that fails shows `Save failed` with the message (the store stays dirty and retries) instead of the crash dialog. |
| W-18 | 07 VIEW-095 | A timed block that runs past 24:00 is clipped at the bottom of its day. |
| W-19 | 07 §4.5.3 | An item that lists its own id in RelatedIds is not drawn as its own neighbour. |
| 07 Q-02 | VIEW-052 | Board deletes purge references to the whole subtree (F2 `trashSubtask` / `trash`). |

### Sanctioned decisions applied (DECISIONS 02 / 07)

| ID | Spec ref | Behaviour |
|---|---|---|
| 02 Q-4 / 07 Q-01 / W-11 | VIEW-052 | Board "Delete task" keeps the Windows confirmation text (`Confirm`, `Delete task '{name}'?` + `\n\nThis also deletes its {n} subtask(s).`) with buttons Move to Trash / Cancel (Cancel default), then moves the card to the Trash — `trash(_:)` for a top-level task, `trashSubtask(_:)` for a nested card — saves, and posts `'{name}' moved to Trash — ⌘Z to undo.`. ⌘⌫ on a focused column: one card → this flow (menu title `Delete Task`, T-KB-06); several cards → W-HIER's `BatchActions.confirmAndTrash` (one undo batch). |
| 07 Q-03 / W-12 | VIEW-053, VIEW-202 | Board "+ New task" logs `Added / Task / {name} / ""` (F2 `createTopLevelTask(logKind: "Task")`); each task created from a saved list logs `Added / Task / {title} / from saved list '{list}'` (new Detail string, modelled on REPO-091's `from saved list '{tpl}'`). |
| 07 Q-04 | §2.1 | Item locks are not enforced by these pages (parity). |
| 07 Q-06 / W-08 | VIEW-090, 095, 098 | Completed procedures, steps and crew items grey (#6B7785) like completed tasks; the pool strikes done rows. |
| 07 Q-07 / W-09 | VIEW-104 | Double-click on a procedure block/chip/pool row flushes and navigates to it in the Procedures section. |
| 07 Q-08 / W-16 | VIEW-202, 210, 214 | The saved-list picker is F3's shared picker: selections survive filtering, results come back in selection order and are appended to `Data.Tasks` in that order. |
| 07 Q-09 | VIEW-010, 082, 088, 097 | Weekday / month names in chrome use `Locale.current` (Gregorian), including the Planner Month header (Windows hard-coded "Sun…Sat"); tests pin en_US. Week math stays Sunday-start. |
| 07 Q-10 / W-14 | VIEW-178 | Map nodes use the per-kind pastel fills (Equipment #4FC3F7, Task #FFB74D, Procedure #A5D6A7, Vessel #CE93D8) with black text and border (centre 3 pt + an accent focus halo so it reads on the dark canvas). |
| 07 Q-11 | VIEW-142 | Bucket categories are grouped case-insensitively for display; the group label is the first spelling in sort order; stored strings are untouched. |
| 07 Q-12 / VIEW-019 | VIEW-008, 010 | All Upcoming and Agenda get a leading `Overdue` group (past-due, not complete, one row per item, never fanned out; Agenda sorts it by deadline then name). In All Upcoming the remaining rows sit under an `Upcoming` header when an Overdue group exists; without overdue items the list stays flat (parity). New Mac strings: `Overdue`, `Upcoming`. |
| Q-6 / 07 Q-05 | §5.3 | Planner placements (`ScheduledStart`, hour-grid range extensions, month moves and slides, point deadlines) are written as Unspecified calendar values (Windows wrote Local for day drops and kept the old kind on month slides). An untouched date keeps its original text. |
| 06 BUILD-145 B3 / B4 | VIEW-147, 149 | `Set category...` saves on every OK and blank clears; Cancel on `Category (optional)` still creates the bucket uncategorised. |

### Mac-grace additions (P4; no capability removed, no data change)

| Ref | Addition |
|---|---|
| VIEW-001 | Calendar sidebar: a Today button, the selected day, and a colour key; header line with the item / overdue count; empty state "Nothing scheduled". Status cells coloured by state; overdue "When" dates red. |
| VIEW-020 | Ui keys are written when they change (selected date — only when the user picks one — and mode without MarkDirty, like CaptureUiState; font size with MarkDirty; map focus without MarkDirty). Sections are created lazily (ARCH §7.2), so a page that was never opened leaves its keys untouched (Windows rewrote CalendarViewMode / CalendarSelectedDate / MapFocusedItemId at every capture). |
| VIEW-207 | Every page re-initialises from `Ui` (Calendar date/mode/font, Planner Day + today, Map focus) when `store.generation` changes; selections are kept by id where the item still exists. |
| VIEW-040 | Board column header counts animate; "No cards" / "No matches" placeholders; hover lift on cards; drop target glows in the column colour; card-shaped drag preview. |
| VIEW-051 | The >15-files confirmation uses Open All / Cancel buttons (same message and title). |
| VIEW-087 | Day / Week columns widen to fill a larger pane (never narrower than 700 / 132); block geometry uses the actual width. A red "now" line in today's column; a dashed ghost block at the snapped time while dragging over the hour grid; month cells highlight as drop targets; block/chip context menu Edit… (or Show in Procedures) and Unschedule (same effect as a pool drop). |
| VIEW-141 | Buckets list context menu (Rename / Set category... / Delete) and empty states for the members pane; members show kind glyphs. |
| VIEW-170 | Map: dot-grid canvas, zoom (buttons, pinch, 35–250 %), Fit, Center, drag-to-pan, hover highlight of a node's edges, double-click / context menu "Show in {Section}", "Open in New Window", "Focus Here"; animated recentre (nodes glide, edges interpolate); a colour key. |
| ⌥⌘F | Board Find, Planner Search jobs..., Map Inspect search are published through `SectionCommands.focusSearchField` (REQ-W-PLAN-02). |
| VIEW-001 / 083 / 140 / 170 | The 6-wide GridSplitter is `CalSplitView` (resizable, width not persisted, double-click restores the default). Default leading widths: Calendar 232 (Windows 320; the graphical month picker needs ~160; in a narrow pane the selected day moves under the Today button), Planner 256, Buckets 340, Map 260. |
| VIEW-011 | Calendar column ideal widths 40 / 150 / 92 / 160 / 88 (Windows 56 / 210 / 120 / 420 / 110): all five columns are visible from a 1100-pt window up (incl. the default 1280 × 820) and every column grows with a wider pane; cells wrap as on Windows. Below ~1100 pt the table scrolls horizontally (the five minimum widths do not fit). Rows have no zebra stripes (hairline separators, V-DESIGN rule 5); the Task name is regular weight (V-DESIGN rule 2; Windows semi-bold). |
| VIEW-004 / 017 | Page header controls (Text: A- / A+, the five view-mode segments, Board Find / Hide done / buttons) sit beside the title when they fit; otherwise they flow onto their own lines under it (`CalFlowLayout`), and in a very narrow Calendar pane the five segments become a pop-up with the same five choices and tooltips. Nothing is clipped. |
| VIEW-012 | Status column shows the friendly labels "To Do", "In Progress", "Blocked", "Done" (Windows: enum names `Todo`, `InProgress`, …) and Recurrence the friendly label (same words) — DECISIONS 04 Q-G / 08 OQ-10 outrank VIEW-012. Steps / crew items keep "Step" / "Done". Stored integers unchanged. |
| VIEW-017 | A- / A+ are enabled whenever a click would change the size (`CalFontScale.canStep`), so a stored 10 or 30 (C18) steps back into 11…28 with the buttons as well as ⌘− / ⌘+. |
| VIEW-043 | Board card meta: the dates, then a red "OVERDUE" status chip (⚠ symbol), then the recurrence with a repeat symbol; each part wraps as a unit, so OVERDUE never lands alone behind a dangling "·". The exact Windows string (`"Due …  ·  OVERDUE   ·   Weekly"`) is the meta line's tooltip and VoiceOver label. |
| VIEW-052 | Single-card "Delete task" (context menu, ⌘⌫ with one card) flushes open editors after the confirmation, re-resolves and trashes the task, saves, closes its detached item window and drops it from `detachedItemIDs` — the same steps as the multi-card batch path (`BatchActions.confirmAndTrash`); the "Confirm" / "Delete task '{name}'?" text is unchanged. |
| VIEW-141 | Buckets header: title with the bucket count, then one icon bar — `plus` ("+ New bucket"), `trash` ("Delete"), and a trailing `ellipsis.circle` menu with "Rename" and "Set category..." (tooltip kept) — instead of the Windows wrap panel of text buttons (V-DESIGN rule 4). Bucket names regular weight (Windows semi-bold); members list without zebra stripes. |
| VIEW-084 | Pool row: the `{JobName}` part wraps to two lines before it truncates; the `   ·   {DurFmt}` part never truncates and sits trailing (same string, tooltip shows it whole). |
| VIEW-170 | Map Inspect rows: `"[{Kind}] {Name}"` wraps to two lines, then truncates in the middle (string intact, tooltip shows it whole). |
| ⌘+ / ⌘− | Calendar text size through `SectionCommands.calendarFontScale` / `setCalendarFontScale` (SHELL-605/606, T-KB-26/27); ⌘← / ⇧⌘T / ⌘→ through the planner closures (SHELL-632…634). |

---

## W-QUICK — deviations and P2 fixes

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`.

### P2 defect fixes (files stay readable by Windows with the same meaning)

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

### Sanctioned decisions applied

| ID | Spec ref | Behaviour |
|---|---|---|
| DECISIONS 02 Q-4 / 08 OQ-1 | QUICK-073, T-QW-13 | Quick-work **Delete** moves the item (whole subtree) to the Trash (undoable with ⌘Z, references kept for a lossless Put Back, pin removed). Confirmation title `Delete`, text `Delete '{name}' and everything under it? This removes it everywhere — it goes to the Trash (put it back from File ▸ Trash…, or undo with ⌘Z).`, buttons Move to Trash / Cancel (default Cancel). The log line is the Trash's `Removed / {KindLabel} / name / moved to Trash` instead of Windows' `Removed / Task|Procedure / name`. |
| DECISIONS 02 Q-5 | QUICK-173, REPO-078 | Trash buttons `Put Back` (tooltip starts "Restore:"), `Delete Immediately…`, `Empty Trash…`, `Close`; in-sheet keys ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫ (03 SHELL-675). Messages keep the Windows text. An empty Trash shows "The Trash is empty." with the line "Items you delete land here. Put them back from this window, or undo the last delete with ⌘Z." (additive). The Name column shows the raw `Name` like the WPF list (an empty name is an empty cell, REPO-078 / T-TR-15). In a read-only copy the three Trash commands are disabled with "Not available in a read-only copy of AA." (01 DATA-174). |
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
| V-DESIGN (FIX-W-QUICK) | QUICK-102, QUICK-124 | The switcher kind chip keeps `KindLabel` (`Equipment/Area`, `Task`, `Procedure`, `Vessel`, radius 3, padding 6/1, 11 pt) but uses the per-kind pastel fill with black text and a hairline border (the `AAKindBadge` look, DECISIONS 07 Q-10, V-DESIGN rule 8) instead of a `PanelAlt` chip with `Accent` text; the selected row uses `AASelBg/AASelFg`. The Search window's Where column adds a compact `AAKindBadge` before the owner header (additive; the header text is unchanged). |
| V-DESIGN (FIX-W-QUICK) | QUICK-042, QUICK-044, QUICK-010, QUICK-152 | Restyle only, every command / string / tooltip kept: the quick-work list controls are one icon bar — the All / Tasks / Procedures filter, a `plus` menu button (click = `+ Task`; its menu lists `+ Task` and `+ Procedure` with their tooltips) and an `ellipsis.circle` menu holding `Sort into Buckets…` / `Remove from Buckets` (tooltips kept; both also stay in the row context menu) — instead of two rows of text buttons; the list header shows the item count (muted, trailing). Row titles (quick-work list, due panel) are regular-weight brand mono instead of bold / semi-bold (V-DESIGN rule 2: bold is for headers only); tiles keep their bold name. Tables (Search, Trash, Activity log) and the children list have no zebra stripes (03 §6.6.5) and show `AAEmptyState` instead of an empty table. The Activity log's Name column takes the flexible width (ideal 214 pt, wraps to 2 lines) inside the 900-pt window. |

---

## W-CREW — P2 fixes and sanctioned deviations (ARCHITECTURE.md §12.2)

### P2 fixes / DECISIONS 09 rulings applied

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
| 09 Clear all | CREW-061, DECISIONS 09 | Clear all moves every member to the Trash as one batch (F2 `trashAllCrew`, one ⌘Z restores all). The confirmation keeps `Remove ALL crew from the roster?` and adds a line saying the batch goes to the Trash. Buttons `Clear All` (Return, as the Windows Yes default) / `Cancel` (⎋), like the Move to Trash confirmation. |
| 06 log | DECISIONS 06 ("log the unlogged actions"), 06 D8 | Schedule add / delete log `Added`/`Removed` · `Schedule entry` · title · crew name; schedule apply logs `Added` · `Schedule` · template name · `{n} entr{y|ies} applied to {crew}` (+ ` (replaced)`). |
| 06 R1 | DECISIONS 06 | The editor commits by id; if the member vanished (deleted / reloaded) Save shows a warning and writes nothing. A reload that keeps the member (ids survive in data.json) while the editor is open re-bases the draft on `store.dataReplaced`: untouched rows show the reloaded values, edited rows keep the user's text, and a note says so. Save writes an untouched row only while its stored value is still the one the form was filled with (`CrewEditorForm.apply(_:original:to:)`), so a stale pre-reload value is never written back; without a reload Save is the Windows apply-all (trim / date normalisation of every row). |

### Sanctioned Mac presentation (P4) — no data effect

| ID | Spec ref | Divergence |
|---|---|---|
| question | CREW-033, 09 §6.4 | Three explicit buttons `Day First (03/04 = 3 April)` / `Month First (03/04 = 4 March)` / `Cancel Import`; the Yes/No/Cancel legend lines are dropped from the body, every other line kept. |
| ⌘Z | CREW-060, 09 §6.4 | The delete confirmation says `undo with ⌘Z`; buttons `Move to Trash` / `Cancel`. |
| apply | BUILD-122 | The Yes/No/Cancel apply question uses `Replace` / `Append` / `Cancel` buttons; the message keeps the legend lines. |
| export | CREW-105, 09 §6.4 | `Export complete` offers `Open` / `Show in Finder` / `Done` (superset of Yes/No). |
| table | CREW-100…104 | The table is the `crew-table` Window scene (non-modal) and reflects the live roster in the current sort order. On open the window grows (never past the screen) so the shown columns fit at their starting widths — with the defaults, Sign-Off Date and Contract Status are in view (WPF auto-sized the grid). A data reload while it is open re-reads the four CrewTable* Ui keys instead of writing the pre-reload choices back. No alternating row stripes. The chooser also supports drag-to-reorder, Space toggles, ⌃⌘↑/↓, and a `Columns` menu bound to the same state; Contract Status / Days cells are tinted with the roster colours. Choices are written on every rebuild; the store is marked dirty only when a value actually changed. |
| roster | CREW-010…017, 09 §6.4 | Header = one row (`Crew`, expiring capsule, member count) and ONE icon bar (design rule 4): `Import COMPAS…` (`square.and.arrow.down.on.square`), `Delete` (`trash`) │ Sort menu (`arrow.up.arrow.down`, the five modes), `Expiring Only` toggle, `Contract Expiries` … overflow `ellipsis.circle` with `Table View…` and `Clear All…`. Every icon carries the spec tooltip as help and the spec name as accessibility label; the WPF wrapping text-button rows are gone. Row name in regular weight (bold for headers only). The in-window Import COMPAS… buttons are disabled with `Not available in a read-only copy of AA.` in a read-only copy or while editing is stopped (DATA-174, the Tools-menu predicate). Row context menu (Edit…, Open Checklist…, Open Schedule…, Move to Trash…), double-click = Edit…, ⌘⌫ / ⌫ = Move to Trash (with the confirmation), ⌥⌘F focuses the search field (placeholder shown), an expiring-count capsule beside the title, empty states. Day counts refresh when the tab is selected and at `NSCalendarDayChanged` (09 §8 Q15). |
| card | CREW-020…025 | The subtitle runs under the name across the full card width (not beside the Edit… button). Section glyphs are SF Symbols (`person.text.rectangle`, `ferry`, `book.closed`, `cross.case`, `ruler`, `person.2`); values are selectable; banner and checklist box carry symbols. Design rules: name in aaMono 16 bold (not 22), Edit… / Open Checklist… as small bordered buttons, field labels aaMono 13 muted trailing-aligned in the 170-pt column, values aaMono 13. |
| editor | CREW-070…076 | Sheet with a BuilderSheetHeader (heading + rank/nationality/vessel subtitle), a segmented Details / Checklist / Schedule switch and a 44-pt footer; Esc = Cancel (Windows had none); date rows use `OptionalDatePicker` + the 130-pt text box with the same one-way sync. The label column is 212 pt, muted, trailing-aligned (170 px on Windows) so the monospaced `Sign-off date  (contract)` label stays on one line; empty text rows show an empty box (no placeholder). The sheet is 640 pt wide (spec) and grows to 860 pt on the Checklist tab so W-BUILD's builder (780-pt minimum, as its own sheets) lays out without wrapping. |
| schedule | BUILD-111/112/117, 06 §6.5 | Visible placeholders `HH:mm` and `What... (or pick an item)`; hover-revealed ✎/✕; context menu on entries. The vessel bar is one row when it fits, else the vessel link above the four buttons; the add row is two deliberate lines (date · time · kind, then title · Pick item… · + Add). Kind glyphs ✓ / 📋 / ⚙ / • are SF Symbols (`checkmark.circle`, `list.clipboard`, `gearshape`, a small dot) with the kind name as tooltip and accessibility label. |
| busy | CREW-030 | The workbook is parsed off the main actor behind `AAProgressOverlay`; Import is disabled while running. |

### Audit fixes (independent audit, Stage W)

| Item | Spec ref | Change |
|---|---|---|
| import save | CREW-036, CREW-040 | A failed `Save()` after the upsert is reported through the shell's save-error path (`env.reportError`) and the import continues (status line, dates log, expiry report); it no longer shows `Import failed` for an import whose members are already in the roster. |

---

## W-VESSEL — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| Q3 / VESSEL-209, 281 | 10 §3.2.2, §7.6 sc. 7–8, DECISIONS 10 Q3 | `PortsService.removeCall` removes exactly one visit: the first visit, in the ports that match the call by Apply's port rule, whose vessel is this vessel (same `VesselId`, or no `VesselId` and the same name OIC) and whose arrival date equals the call's. A rename no longer keeps a stale visit; a same-day call at another port keeps its visit. Empty ports are still pruned DB-wide (parity). Data stays Windows-readable. |
| Q7 / VESSEL-121 | 10 §9 Q7, DECISIONS 10 Q7, ARCH §7.7 / §9.3 | `WorkOrderNotifications.runDigest` posts one system notification per vessel with flagged (`Notify`), active, overdue jobs, only when `NotificationsEnabled`, deduplicated per vessel/job/day (`aa.vessel.notified`). Unbundled runs fall back to the status line. Text is Mac-only: title `AA — work orders overdue`, body `{Vessel}: {n} flagged work order(s) overdue — {JobNo} (overdue {d}d), …`; click opens the vessel's item window. |
| Q8 / VESSEL-251 | 10 §9 Q8, DECISIONS 10 Q8 | Ports Database row count pluralised: `1 visit` / `{n} visits`. The other `(s)` strings stay verbatim. |
| Q6 / VESSEL-045 | 10 §9 Q6 | "Explorer" → "Finder": tooltip `Reference a folder (opens in Finder).`, panel message `Link a folder (opens in Finder)`. |
| Q4 / VESSEL-025 | 10 §9 Q4, §6.2, §6.9, ARCH §9.4, W-PERSIST-13 | Targets open through `AttachmentOpener` (path-mapping table, `/Volumes/<share>` for UNC). An existing folder target opens the folder itself in Finder (`NSWorkspace.open`, Explorer parity), not its parent with the folder selected. An unmapped Windows path shows `Open failed` / `Not found:\n{path}` plus a Mac-only remedy line, with the shared recovery: `Connect to Server…` (UNC only, default; Finder mounts `smb://server/share`, the open is retried as soon as the path resolves, up to 15 s, else a status line), `Locate…` (stores the inferred mapping, then retries), `Open File Links Settings…`, `Cancel`. |
| Q5 / VESSEL-005 | 10 §9 Q5, DECISIONS 10 Q5 | Panels take a `vesselID` and render that vessel in any window (never another vessel's data). |
| Q11 | 10 §9 Q11 | The search placeholders stored in `Tag` on Windows are shown (`Search job no / title / function...`, `Search port / country / UN-LOCODE...`). |
| VESSEL-004 | 10 VESSEL-004 | Defensive gate in each panel: a locked, not-unlocked vessel shows a "Locked" placeholder (the host W-HIER also overlays its lock gate). |
| VESSEL-018 / 019 | 10 §6.2 | Double-click is detected from the press event's `clickCount == 2` at drag start (WPF `ClickCount` parity); the icon size follows the live size while resizing (Windows rebuilds only at the end — cosmetic). |
| VESSEL-022 | 10 §6.3, ARCH §2.4 | After OK on Edit…, a card that vanished (reload while editing) shows a Mac-only warning instead of saving. |
| VESSEL-028 (additive) | 10 §6.2, §6.3 | Cards are focusable: Return opens, Space = Quick Look of a file target, ⌫/⌦ = Delete (same confirmation); context menu adds Quick Look for file cards. Drag a Finder file (copy; ⌥/⇧ = link in place), folder or URL onto the canvas → editor pre-filled; only OK adds the card. |
| VESSEL-048 / 049 (additive) | 10 §6.3 | The current icon and colour are highlighted in the editor; a checkerboard shows behind semi-transparent card colours in the preview. |
| VESSEL-050 | 10 §6.3 | `Custom colour…` is a native `ColorPicker` (no opacity); each change writes `#FF{RR}{GG}{BB}` from sRGB components (alpha forced to FF). |
| VESSEL-051 | 10 §3.1.11 | Width/Height text is parsed with the current locale's separators; in a locale whose decimal separator is not `.`, a text containing `.` and no locale decimal separator is read with `.` as the decimal point. |
| VESSEL-104…118 (Mac idiom) | 10 §6.4 | Header clicks keep VESSEL-111 semantics on a native `Table` (a new column always starts ascending); selection is kept by job identity across rebuilds (VESSEL-122 improvement); context-menu actions on a right-clicked row act on that row (or the selection that contains it); ⌫ deletes the selection with the same confirmation (ListCommands `workOrders` / `portsOfCall`). Emoji button labels become SF Symbols with the same words (ARCH §8.5). |
| VESSEL-200 (additive) | 10 §6.5 | Ports table gains a context menu `Delete…` and ⌫ (same confirmation). |
| VESSEL-202 | 10 §6.5 | Different-vessel prompt buttons are `Import Anyway` / `Cancel` (exact body text). |
| VESSEL-103 / 205 export styling | 10 §4.4–4.5 | Exports use F1's `XlsxWriter.write(to:sheet:)`: the bold header cells also carry a light grey fill (F1 style 1/3), widths are the auto-fit approximation `chars × 1.1 + 2` (cap 100) and empty strings are written as empty cells. Cell values, types, `@` columns, sheet names and the re-import result are unchanged. |
| VESSEL-318 | 10 §X.3 | Shippalm and ports imports append the Mac-only hint `{n} formula cell(s) had no saved result; …` to the success status line when the file had formula cells without cached values. |
| VESSEL-001 / 002 | 10 §A, OWNERSHIP W-HIER card | The vessel detail tab strip (order Quick Cards, Work Orders, Ports, Container, Relationships; Quick Cards selected on vessel selection) is hosted by W-HIER; W-VESSEL supplies `VesselTab`, the three panels and `VesselActions.menuActions(selectTab:)`. Verified post-merge (Stage V "vessel tabs"). |
| VESSEL-040 | 10 §6.3 | The editor is a sheet (no title bar), so the Windows window title `Quick card` is shown in the standard `BuilderSheetHeader` (symbol tile + mono title); footer = Divider + 44-pt bar. Field labels keep bold (mono). Sheet 660×620. |
| X.7.3 / VESSEL-101, 201 (additive) | 10 X.7.3 | Dropping a Finder workbook on the Work Orders or Ports panel runs the same import as the toolbar button (same VESSEL-301 gate, busy state, different-vessel prompt, hints and error boxes); the drop target is highlighted in the system accent. |
| VESSEL-100 (layout) | 10 §6.4 | Toolbar in two wrapping rows: Import, Export, search, then Mark completed / Mark active / Delete; then the Status / Category / Rank / Completion pickers, the two toggles, then shown ON / shown OFF. Same controls, words and tooltips as Windows. |
| VESSEL-103 / 205 (save panel) | 10 §6.4 | The save panels carry the Windows dialog title as the panel message too (a sheet shows no title). |
| DATA-174 / VESSEL-101, 201, 044 (write gate) | 01 DATA-174, DATA-180 | While the write gate is closed (read-only copy, or Stop Editing Here) the in-panel `Import Shippalm (.xlsx)…` / `Import ports (.xlsx)…` buttons and the editor's `Import a copy` are disabled with the help `Not available in a read-only copy of AA.`; the workbook drops and the quick-card canvas drag-in accept nothing; a gated import reached any other way shows that text in an `Import` box and does nothing. |
| VESSEL-109 / 207 (wrapping, widths) | 10 VESSEL-109, 207; design rules 2/5 | The wrapped columns (Title, Due, Function; Port Facility, Special measures) wrap on the native `Table` (variable row heights). Cells use the brand mono at 12 pt (the crew-table cell size); to fit the mono font some ideal widths are narrower than the Windows px widths (Ports: Port 130, Country 110, UN/LOCODE 80, Arrival/Departure 124, Sec P/V 48, SSP 42, Facility 170; Work Orders: Job No. 100, Title 230, Due 190, Responsible 110, Function 200). Work Orders still scrolls horizontally in narrow panes, as on Windows. No alternating stripes; an empty vessel shows the empty state instead of an empty table. |
| VESSEL-250…253 (type) | 10 VESSEL-250, 251, 253; design rule 2 | Ports Database text uses the brand mono: page title 16 bold accent (Windows 15), visits header 13 semibold (Windows 17 bold), port rows 13 regular (Windows semi-bold), counts 11 muted. The empty port list shows an empty state (`No ports yet` / `No matching ports`). |
| VESSEL-012 (empty state) | 10 VESSEL-012; design rule 12 | The empty canvas shows the VESSEL-012 text as a standard empty state: its first line is the title, its second the message. |

---

## W-PDF — deviations and P2 fixes (ARCHITECTURE.md §12.2)

Sanctioned deviations of spec 11 §6.9 that the Mac applies, P2 fixes, DECISIONS 11 rulings and layout choices.
Windows behaviour is kept wherever this list says nothing (DECISIONS P1/P3).

| ID | Spec ref | Change (one line) |
|---|---|---|
| DEV-01 | 11 PDF-066, Q1, DECISIONS 11 | **Not applied** (parity): only a Run's own `TextDecorations` print; Span/`Underline`-element decorations are dropped as on Windows. |
| DEV-02 | 11 §3.5.4 | Inside a targeted Hyperlink every text descendant (Runs inside Spans, nested links, LineBreaks) is part of the one link, in document order (Windows reorders A C B and leaves B unlinked). |
| DEV-03 | 11 PDF-091, PDF-094, §3.6.2 | XLSX sheet name: sanitise → truncate (31 UTF-16 units, no split surrogate) → escape; XML-illegal characters dropped from every cell (F1's `XlsxWriter.sanitizeSheetName` / `xmlEscape`). |
| DEV-04 | 11 PDF-067, §3.5.7 | Strike-through is drawn as a native line over exactly the characters Windows overlays with U+0336 (not whitespace / control); extracted text carries no U+0336. |
| DEV-05 | 11 PDF-064c, Q3, DECISIONS 11 | **Not applied** (parity): partial (few-word) highlights are dropped; only whole-paragraph shading. |
| DEV-06 | 11 §6.4, DECISIONS 11 Q2 | Mac font substitution table (Calibri → Carlito / Helvetica Neue / Helvetica, Consolas → Menlo / SF Mono / Monaco / Courier New, Segoe UI → system UI font, …). A substitute is drawn at a **metric scale** (Calibri→Helvetica Neue ×0.91, Consolas→Menlo ×0.914, …) so advance widths and page breaks match the Windows fonts; line heights follow the requested size. Stored font names are never changed. |
| DEV-07 | 11 §6.4 | CoreText cascade fallback renders glyphs missing from the chosen font (emoji, CJK) instead of tofu. |
| DEV-08 | 11 §3.2 rule 8 | A table row (or MergeDown group) taller than a page is split at line boundaries across pages, heading rows repeated; normal rows stay atomic. |
| DEV-09 | 11 PDF-003 | Item export/print flushes **every** editor (`env.flushAllEditors()`, incl. detached item windows) before `FlushIfDirty`. |
| DEV-10 | 11 PDF-022 | "Export ALL (PDF)…" never needs a selection: W-BUILD's `SavedListsTabView` shows it in the detail card and under the no-selection empty state (always enabled), both calling `PdfExportFlows.exportSavedLists(.all)`; "No saved lists to export." kept for the empty case. |
| DEV-11 | 11 PDF-071, §7.2 | A formal link's target is the trimmed `NavigateUri` (www. → https://), not .NET `Uri.ToString()`; strings Foundation rejects are percent-encoded; a target that is still not a URL gets no annotation (the text stays blue/underlined). |
| DEV-12 | 11 PDF-025 | A failure to *open* the saved-lists PDF is ignored (never reported as "Could not export the PDF"). |
| DEV-13 | 11 PDF-101 | CRLF and lone CR become LF before `\n` splitting everywhere text enters the PDF. |
| PDF-105 | 11 PDF-105 | Nil names/titles print as "" (model strings are non-optional on the Mac); no export ever fails on a hand-edited null. |
| PDF-103 | 11 PDF-103, DECISIONS 11 Q7 | Header timestamp is `yyyy-MM-dd HH:mm` with en_US_POSIX digits and the Gregorian calendar (`NetDateTime.format(.isoMinute)` of the local now). |
| Q4 | 11 §3.5.8, DECISIONS 11 Q4 | A table inside a table cell is rendered inside the cell (Windows may fail or drop it). |
| Q5 | 11 §7.11, DECISIONS 11 Q5 | A legacy whole-document `enc:` body prints `(locked content)` (under its heading) instead of the ciphertext. |
| Q6 | 11 PDF-037/040/044, DECISIONS 11 Q6 | Password-gated related/linked items print their **name only**: no relationship description, no linked-procedure description/steps, no linked-task checkbox/meta/description. |
| Q8 | DECISIONS 11 Q8 | No PDF outline (parity). |
| PDF-025 buttons | 11 PDF-025, §6.5 | "Export complete" alert buttons `Open` (default) / `Not Now` / `Show in Finder` (allowed addition); message text verbatim. |
| PDF-005 busy | 11 PDF-005, §6.2 | Rendering runs off the main actor; an "Exporting PDF…" sheet appears only when an export takes longer than ~300 ms (also for saved lists and the workbook). |
| §6.2 Print | 11 §6.2 | File ▸ Print… (⌘P, F3 registry row) prints the same in-memory item PDF at 100 % through PDFKit's print operation (additive). |
| saved-lists flush | 11 §2.3 | Saved-lists export first flushes open editors (in memory only, no save), so a list item's last keystrokes print (additive; Windows reads the in-memory model too). |
| cell words | 11 §3.2, PDF-100 | In table cells a single word wider than the column may run into the cell's right padding (as MigraDoc overflows it) instead of being broken by character; body text and words wider than the cell still wrap by character so nothing is clipped. |
| table position | 11 §3.2 rule 8 | Tables are shifted left by their left padding, so cell text aligns with body text (MigraDoc's placement). |
| file names | ARCHITECTURE.md §1.2 vs §12.2 | The §1.2 tree's file names (PdfDOM, PdfStyles, FontResolver, LinkScanner, RichTextToPdf, ItemPdfBuilder, …) are implemented with the mandatory `Pdf` prefix: `PdfDOM`, `PdfStyles`, `PdfFontResolver`, `PdfLinkScanner`, `PdfRichText`, `PdfItemBuilder`, `PdfListBuilders` (saved lists + checklist), `PdfChecklistXlsx`, `PdfLayoutEngine`, `PdfRenderer`, `PdfSnapshots`, `PdfExport`. |
| PDF-027 order | 11 PDF-027 | Group order of Export ALL comes from F2's `SavedListOrder.allEntries` (REPO-136: culture comparison of the lower-cased name, ungrouped last, stable) — the same order the Windows `OrderBy` produces; the spec's "code-point" remark only concerns the `￿` sentinel, which is not used. |
| D1 exports | 06 §8 D1 (DECISIONS 06: D1–D7 accepted), 11 PDF-021, PDF-022/027, BUILD-092/093 | A list whose `GroupId` points at a deleted group is **ungrouped in both exports**, as the Saved Lists tab shows it: "Export group (PDF)…" on it (or on any ungrouped list) prints "Ungrouped lists" = every list with a null **or** dangling `GroupId`, arranged order (Windows: null only, so the selected list was missing); "Export ALL (PDF)…" prints it under the trailing "Ungrouped" heading in arranged order (Windows: key `""`, printed first with no heading). `PdfExport.ungroupedEntries` / `allEntriesResolved`; F2's `SavedListOrder` unchanged. An existing group with an empty name keeps PDF-052 (no heading, sorts first). |
| checklist lock | 11 PDF-010 | Checklist-only exports are not lock-checked (parity; unreachable while gated). |
| KWN + orphans | 11 §3.2 rules 7 + widow control, §7.16 #6 | A KeepWithNext chain reserves the lines the next paragraph's orphan control needs (2, or all of a ≤ 3-line paragraph), so a heading is never left alone at a page bottom while its paragraph moves on. |
| save-panel title | 11 PDF-004, PDF-011, PDF-024, §6.2 | The save panel runs as a sheet, which has no title bar, so the Windows dialog title (`Export to PDF`, `Export checklist to PDF` / `to Excel`, `Export saved lists to PDF`) is also set as the panel's message (visible text); additive. |

---

## W-SIRE — P2 fixes and sanctioned deviations (ARCHITECTURE.md §12.2)

Spec 12 (SIRE 2.0), DECISIONS 12. Stage V merges these rows into `Docs/DEVIATIONS.md`.

### P2 fixes (spec §8 "Fix" decisions)

| ID | Spec ref | Fix |
|---|---|---|
| Q-3 | SIRE-048, §8, DECISIONS 12 | The question list is multi-select (⌘-click / ⇧-click); `Selected Questions` exports the selected rows in natural order; the detail shows the last-clicked row. |
| Q-4 | SIRE-029 | The AI Suggest result is added to the question that was selected when the request started (prompt text and add target). |
| Q-5 | SIRE-038, BUILD-A26 | Clearing the Gemini key deletes the Keychain item; nothing falls back to an older value. |
| Q-8 | SIRE-023, §6.4 rule 9 | The body is flushed on selection change, focus loss, every app-wide flush (⌘S, 5-min autosave, quit, sync, Flash Sync, item windows) and after 750 ms of idle typing. |
| Q-9 | §6.4 rule 10 | Saved edits that cannot be read are never overwritten silently: the original is shown read-only with the banner `Your saved edits for this question could not be displayed on this Mac. They are kept unchanged.` and the actions `Reset to original` / `Edit anyway (replaces saved edits)`. |
| Q-10 | SIRE-036/040, §6.8, §6.11 | The export sheet waits for a running bank load (progress shown; dismissing the wait shows the Windows "still loading" text); a data-model swap re-filters the list. |
| Q-11 | SIRE-030, VIEW-210 | The candidate picker keeps ticks across searching; `Select All` / `Select None` added. |
| Q-12 | §3.10 | Exports use LF line endings (UTF-8 without BOM). |
| Q-14 | §3.10 | `Generated:` and file-name stamps use `yyyy-MM-dd HH:mm` / `yyyyMMdd_HHmm` with a fixed `:` (Gregorian, en_US_POSIX, local zone). |
| SIRE-015 | §6.1 | A re-filter that keeps the selected question flushes pending body edits and does not rebuild the editor. |

### Sanctioned deviations and Mac additions (P4)

| ID | Spec ref | Deviation |
|---|---|---|
| D-SIRE-01 | Q-6, DECISIONS 12 | Gemini: same model / temperature, `maxOutputTokens` raised to 8192; the key travels in the `x-goog-api-key` header (never in the URL). |
| D-SIRE-02 | §4.3, DECISIONS 12 | The Gemini key lives in the login Keychain (`com.eriskay.aa.gemini` / `GeminiApiKey`). A `GeminiApiKey` found in settings.json is copied into the Keychain once (MacPreferences `aa.sire.geminiImported`, set only when a key was found) and the settings value is left untouched (DECISIONS wins over spec §4.3 "removes it"). |
| D-SIRE-03 | SIRE-038, §6.9, BUILD-143/148 | Tools ▸ Set Gemini API Key… uses the secure prompt with a reveal toggle, the Mac wording `Paste your Google Gemini API key (stored securely in this Mac's Keychain, never synced):` and the helper line `Leave blank and click OK to remove the key.`; Settings ▸ AI adds Save / Clear. |
| D-SIRE-04 | SIRE-012, DECISIONS 12 | Filter state (sort, evidence, status, unticked chapter / vessel / type boxes, expanders, filter-pane visibility) and the two pane widths are remembered per Mac in `aa.sire.filters`; the search text is not. Nothing goes into data.json. |
| D-SIRE-05 | SIRE-004, ARCH §7.2 | The three panes use app-drawn draggable dividers in an `HStack` instead of `HSplitView`: inside the macOS 26 NavigationSplitView detail column an `HSplitView` extends under the floating sidebar and the toolbar and forces the window wider than its frame (verified with the snapshot hook at 1300 pt). Defaults 250 / 360 pt as on Windows; the detail keeps ≥ 420 pt. |
| D-SIRE-06 | SIRE-014, DECISIONS 12 | List rows add an `EXP` tag glyph and a status capsule (SF Symbol + the same text); the bookmark star is `#F0A030`. |
| D-SIRE-07 | SIRE-017…019, §6.2 | Status / Bookmark / EXP buttons show their current state (tinted chips); the WPF glyphs `⧗ ✓ ★ 📋 ✦ ↺ ➕ ✕` are replaced by SF Symbols next to the unchanged texts (`In Progress`, `Checked`, `N/A`, `Clear`, `Bookmark`, `EXP tag`, `Identified…`, `AI Suggest…`, `Asking Gemini…`, `Reset`, `Add to AA:`). The stats footer keeps its glyphs (data string). |
| D-SIRE-08 | SIRE-030, VIEW-212 row 23 | The candidate picker is a dedicated sheet (prompt as title, wrapping rows, `Cancel` / `Add`, Esc cancels) and adds in candidate order. |
| D-SIRE-09 | SIRE-034 | The kind sheet is a radio group (`Procedure` / `Task` / `Equipment / Area`) with one muted helper line per kind that matches what §3.7 creates — for `This question…` the identified tasks become steps / subtasks / components, for `Whole section…` / `Whole chapter…` each question does — and a note that identified tasks also become linked Tasks (display only). |
| D-SIRE-10 | SIRE-035, §6.7 | Confirmations use `Continue` / `Cancel`; "Go to it now?" uses `Go to Item` / `Not Now` (message text unchanged). |
| D-SIRE-11 | SIRE-036/037, §6.8 | One export sheet replaces the mode picker + Yes/No/Cancel box: mode list (Print Checklist pre-selected), live monospaced preview, `Share…`, `Print…`, `Cancel`, `Copy`, `Save…` (default). Copy posts `SIRE export copied to clipboard.` and closes; a pasteboard refusal shows `Clipboard failed` with a Mac message (there is no exception text). |
| D-SIRE-12 | SIRE-022, Q-15 | Paragraph-level commands (alignment, list toggles, indent) cannot restyle existing paragraphs: the single `shouldChangeText` gate refuses every change touching existing characters. ⌘B / ⌘I / ⌘U change typing attributes only. |
| D-SIRE-13 | SIRE-025 | The context menu reads `Copy`, `Paste (insert)`, `Select All` (Mac capitalisation). Services can read the selection but never write back; Writing Tools, autocorrect, substitutions and find-and-replace are off. |
| D-SIRE-14 | SIRE-022, §6.4 rule 6 | Pasted rich text is sanitised: AA XAML fragments go through W-RICH `readFragment`, RTF/RTFD lose their attachments, otherwise plain text. Drag and drop is disabled. |
| D-SIRE-15 | SIRE-020, §6.5, §6.13 | Display uses the system font (SF Pro) at 1 DIP = 1 pt; stored XAML keeps `FontFamily="Segoe UI"`. Chips / labels are TextKit 1 `NSTextBlock`s with 100 % content width; intra-Run line breaks are U+2028 inside the paragraph. The body paper stays light (`#FCFCFC`, forced Aqua) in both appearances. |
| D-SIRE-16 | §3.7, §4.4, §6.1 | Quick-add bodies are written by the SireFlow block-model writer with the WPF root attribute set (05 S-1), a fixed attribute order and explicit Run `Foreground`s; byte-stable and structurally identical to `TextRange.Save` (byte identity not required, §6.13). |
| D-SIRE-17 | §3.8 | Error texts: `URLError` timeouts → the timeout text; other `URLError`s → `Network error: {localizedDescription}`; JSON type errors reproduce .NET's `The requested operation requires an element of type '…'` text; JSON syntax errors use the Mac parser's message. |
| D-SIRE-18 | §4.1 | The bank decoder tolerates JSON `null` for every string and string-array element (→ ""), ignores unknown keys and fails the load on other type mismatches with an STJ-style message. |
| D-SIRE-19 | SIRE-016 | No selection shows `Select a question` (or `{n} questions selected.`); tasks empty shows `No tasks yet`; an empty list shows `No questions match` / the search empty state. |
| D-SIRE-20 | §6.10 | Quick-add builds every object first and inserts them in one batch per collection (chapter 8 as Equipment: 1 item, 91 components, 1 705 tasks). |
| D-SIRE-21 | ARCH §6.7, §11 | Until W-RICH is merged the body is shown read-only (generated original) and nothing is persisted through the placeholder writer; with W-RICH the original is loaded through `XamlReader.read(…, .sirePane)` and flushed with `XamlWriter.write`. |

### Optional items not shipped

| Item | Spec ref | Reason |
|---|---|---|
| `SIRE` CommandMenu (⌥⌘ status / bookmark commands) | §6.3 (optional) | The menu bar is F3's registry (03 §6.5.1); no rows were allotted. |
| Toolbar `Add to AA` menu and filter toggle | §6.2 (optional) | Section roots stay alive in one ZStack, so section toolbar items would show for every section; the in-pane strip and the list-header filter toggle provide both actions. |
| Undo of quick-add / `↺ Reset` | SIRE-024, §6.10 (optional) | Not required; Windows has none. |

---

## W-FLASH — deviations and P2 fixes (ARCHITECTURE.md §12.2)

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`. Nothing here changes the
wire protocol v1 or what a well-formed peer sends; every file written stays readable by Windows and iOS.

### P2 defect fixes (sanctioned by DECISIONS 13)

| ID | Spec ref | Fix |
|---|---|---|
| DEV-FLASH-01 | 13 §8 Q-1 | On apply, `Sets`, `Deletes`, `Order` and `BlockDeletes` naming an excluded data key (`Ui`, `LastModified`) are skipped, so a malformed or legacy sender cannot wipe `Ui` (per-device keys included) or turn it into an array. |
| DEV-FLASH-02 | 13 §8 Q-2, protocol §10 | `SettingsDeletes` is filtered through the 11 excluded settings keys on apply: a legacy sender can no longer remove the receiver's `PasswordHash`/`PasswordSalt` (or any other excluded key). |
| DEV-FLASH-03 | 13 §8 Q-3, protocol §10 "Legacy senders" | A root-level `Ui` object in a change set (the very first iOS build) is folded into the key-level Ui merge with the lowest precedence (root `Ui` < `Blocks.Ui` < `UiChanges`), per-device keys stripped. |
| DEV-FLASH-04 | 13 §8 Q-4 | When a prepare finds nothing to send, the encoder and pending baseline are dropped, flashing stops and the confirm button is disabled. After an apply while a stream is flashing or awaiting confirmation, that pre-apply stream is dropped and re-prepared, so a confirm can never write a pre-apply baseline. |
| DEV-FLASH-05 | 13 FLASH-071, §6.4 step 5, §7.9 | Measured (FlashQRTests): Apple Vision's current barcode revisions (3–4) cannot read clean, valid symbols whose data is mostly zero bytes when masks 0, 1, 2, 3 or 5 are used — exactly the zero-padded tail chunk, which Nayuki's penalty rule masks with 0. At K ≤ 8 that frame travels alone, so the transfer would never complete. **Sending:** the Mac picks the lowest-penalty mask among 4, 6 and 7 (`FlashQRCode.appleReaderSafeMasks`, `FlashQRCode.flashFrame`), which every Apple reader tested decodes; the generator itself stays bit-identical to Nayuki (golden matrices) for the default mask set. **Receiving:** every camera frame runs Vision's current revision and revision 2 together, and CoreImage's `CIDetector` when both found nothing (`FlashQRDetector`), so Windows' mask-0 tail frames are read. Frames remain standard QR codes; WeChat/ZXing/OpenCV read them. |
| DEV-FLASH-06 | 13 §8 Q-5 | A data file that exists but cannot be read refuses to prepare or apply with `The database could not be read, so Flash Sync is unavailable until it is fixed.` (never a snapshot of an empty database or a change set deleting everything); safe mode refuses the same way. An unreadable `settings.json` is an error, never `{}` (which would emit `SettingsDeletes` for every shared key). A missing data file is still an empty database (parity). |
| DEV-FLASH-07 | 13 §8 Q-10 | The apply is transactional: both trees are read before anything is written; settings.json is written atomically, then the data goes through `applySyncedData`; if that throws, the previous settings.json bytes are restored (or the file removed if it did not exist), so "Failed to apply — your data was not changed." is true. |
| DEV-FLASH-08 | 13 §8 Q-11 | `qrsync-baseline.json` is written encrypted (`AAENCM1`, the local AES-GCM key) while EncryptLocalData is on; plaintext baselines are still read. If encryption is on and the key cannot be read, the baseline is not written (the next sync is a snapshot) rather than leaking the database in plaintext. |
| DEV-FLASH-09 | 13 §8 Q-7 | Rescan and the camera picker are disabled while the camera runs (Windows let Rescan re-enable Start and leak the running camera). |
| DEV-FLASH-10 | 13 §8 Q-12, DECISIONS 02 Q-12 | The apply writes settings.json only when the merge changed it (no-op write-backs skipped); the baseline is still written. |

### Sanctioned Mac behaviour and additions (P4, DECISIONS 13)

| ID | Spec ref | Change |
|---|---|---|
| DEV-FLASH-20 | 13 FLASH-004, §6.6 | A single-instance, non-modal `Window` (not `ShowDialog`). Modal guarantees are kept by construction: every prepare and every apply first flushes all editors and saves synchronously; a prepare never runs while flashing or while a confirmation is pending; the summary refreshes when the window becomes key and is idle; the apply cancels the pending autosave and reloads through `loadDataAndInitUI` immediately. |
| DEV-FLASH-21 | 13 §8 Q-8, Q-9 | The time estimate follows the Speed slider live; `framesShown` and the pass count reset with every new payload. |
| DEV-FLASH-22 | DECISIONS 13 Q-18 | Speed (6…15, default 12) is remembered per Mac (`aa.flash.speed`, UserDefaults — never settings.json); the last tab is remembered too (`aa.flash.tab`). |
| DEV-FLASH-23 | 13 FLASH-030, §6.4 step 2 | Cameras are listed by their real names (`localizedName`) from an AVCaptureDevice discovery session (built-in, external, Continuity, Desk View), the system default preselected, refreshed automatically on connect/disconnect; Windows' positional "Default camera" / "Camera N" names are not used. |
| DEV-FLASH-24 | 13 FLASH-033, §6.4 step 9 | Detection is Apple Vision (no WeChat model files, no `qrmodels/` folder). `The QR reader could not start: {message}` is kept in `FlashSyncTexts` but cannot occur. |
| DEV-FLASH-25 | 13 FLASH-034/036, §6.4 | Capture: the largest format ≤ 1920×1080 at its highest frame rate, continuous autofocus where supported, 420f buffers, late frames discarded (≙ buffer size 1), unmirrored data path; the preview is an `AVCaptureVideoPreviewLayer` (no 100 ms throttle needed) and is mirrored for cameras that face the user. A 1.2 s watchdog reports `The camera stopped sending frames.`; interruptions report the same; runtime errors report `Camera error: …`. |
| DEV-FLASH-26 | 13 §6.4 step 1, 03 SHELL-199 | Mac-only texts: `Camera access is turned off for AA. Allow it in System Settings ▸ Privacy & Security ▸ Camera.` with **Open System Settings**; unbundled runs show `The camera needs the packaged app. Build it with Scripts/build-app.sh and open dist/AA.app.` and never touch the camera. |
| DEV-FLASH-27 | 13 §6.5 | Frame clock: a display link on the window's screen (each code held for whole refreshes) with a 60 Hz common-mode timer fallback while the link is paused (display asleep / window occluded); frame n+1 is rendered on a background queue while n is shown; the first frame appears one interval after Start (parity). Keep-awake = `ProcessInfo` activity (idle display + system sleep disabled). |
| DEV-FLASH-28 | 13 FLASH-016, §6.3 | The plate draws the code at an integer number of device pixels per module, centred and pixel-aligned, interpolation off (crisper than Windows' uniform stretch); before the first frame it shows a light placeholder instead of an empty plate. |
| DEV-FLASH-29 | 13 FLASH-044/135, §6.6 | The review is a sheet with the exact FLASH-044 text plus a per-collection breakdown (removals in red); buttons **Apply** (destructive for a snapshot) / **Don't Apply** (default for Return and Esc). |
| DEV-FLASH-30 | 13 FLASH-019, §6.6 | The confirm question uses **Yes, It Finished** / **Not Yet** (Not Yet is the default button). |
| DEV-FLASH-31 | 13 FLASH-131 | Send ▸ More ▸ **Reset Pairing…** (with a destructive confirmation) clears the baseline so the next send is a full snapshot; disabled while flashing or while a confirmation is pending. |
| DEV-FLASH-32 | 13 FLASH-134 | Send ▸ More ▸ **Show Full Screen** (a submenu of displays when there are several) shows the live code alone on a white borderless window; click or Esc returns. |
| DEV-FLASH-33 | 13 FLASH-132 | A snapshot without settings (bare data.json, or `Settings` not an object) adds `This copy carries no settings (dark mode etc. stay as they are).` to the review text. |
| DEV-FLASH-34 | 13 §6.6 "Copy" | "this PC" → "this Mac" in the intro and the snapshot warning; `Looking for the iPhone's screen…` uses the typographic ellipsis. Additions: the brightness hint, the Mac camera-distance hint, `Preparing…`, plate placeholders. All other strings are verbatim. |
| DEV-FLASH-35 | 13 §8 Q-13, FLASH-130 | An incoming `DarkMode` takes effect immediately (the reload re-applies the appearance). |
| DEV-FLASH-36 | 13 §3.14 | `AAFlashSyncInterop` prints `Swift …` where the C# harness prints `C# …`, writes LF frame files, splits frame files on bytes (CRLF safe), and answers missing arguments with the usage line (exit 2) instead of an exception. Change sets use `From = "Windows"` and 2026-09-27 12:00:00 like the C# harness, so outputs compare byte for byte. |
| DEV-FLASH-37 | 13 §6.6 | Applying is refused in a read-only instance (another AA owns the data folder), with the safe-mode message. |
| DEV-FLASH-38 | 13 §6.6 point 3 | The refresh when the window becomes key and is idle is skipped when nothing changed since the last prepare: the editors are flushed, nothing is dirty, and the data file, settings.json and the baseline carry the same path/size/modification date/inode (`FlashSourceFingerprint`). Returning from the window's own alerts or from the main window therefore no longer rebuilds the whole payload (and keeps the same session). Any change, or a failed last prepare, still re-prepares. |
| DEV-FLASH-39 | 13 §6.4 step 1, DEV-FLASH-26 | The camera permission is re-read on **Rescan** and whenever the window becomes key, so after the user allows the camera in System Settings the denied text clears and **Start camera** enables without reopening the window (and a revoked permission shows the text again). |

### Not shipped

| ID | Spec ref | Reason |
|---|---|---|
| FLASH-133 | 13 §6.4.4 | Receive from the screen (ScreenCaptureKit / iPhone Mirroring): DECISIONS 13 — "ScreenCaptureKit / iPhone-mirroring receive: **no** for v1". |

### Note for the Windows build (not a Mac change)

DEV-FLASH-05 applies to Windows → iPhone as well: Windows (Nayuki, automatic mask) flashes the zero-padded tail chunk
with mask 0, which Apple Vision's current revisions do not decode. If the iPhone's reader uses them, a small Windows →
iPhone change set (K ≤ 8, tail chunk mostly zeros) can stall. Restricting the automatic mask to 4, 6 and 7 (as the Mac
sender does) or decoding with Vision revision 2 / CIDetector on iOS removes the stall.

---

## W-DRIVE — P2 fixes, sanctioned deviations and Mac additions

Spec 14 (Google Drive & tools), 01 DATA-073/153, 03 SHELL-010/011/073…080/121/122. Format: ID · spec ref · one line.
Files written stay readable by the Windows build with the same meaning (DECISIONS P2).

### Sanctioned deviations (DECISIONS 14 / spec 14 §8 recommendations)

- Q-1 · 14 §3.1.5 · `files.list` requests `nextPageToken,files(…)`, so the intended ≤ 10-page whole-Drive scan works (Windows reads only the first 200 results). Identical results with ≤ 200 matches.
- Q-3 · 14 §3.1.10, DECISIONS 14 ("Q-3 harden EnsureFolder: yes") · `EnsureFolder` asks `mimeType='application/vnd.google-apps.folder' and name='{name}' and 'me' in owners and trashed=false` with `fields=files(id,name,capabilities/canAddChildren)`; it picks the first match Drive reports as `canAddChildren`, else the first whose capability is not reported (Windows' first result), else creates a new folder in My Drive root. A shared, hand-made or other-app `AA Backups` / `AA Sync` that `drive.file` cannot write into is no longer chosen. Vector 7.6-7 pins the new query and fields; `ensureFolderHardened` covers the pick.
- Q-6 · TOOLS-019 · downloads pass `supportsAllDrives=true` (shared-drive files that are listed can also be downloaded).
- Q-7 · TOOLS-008, §6.3 · interactive sign-in shows a "Waiting for Google sign-in in your browser…" sheet with Cancel (status `Google sign-in cancelled.`) and times out after 5 minutes; Windows waits forever.
- Q-8 · §4.5 · a Drive 400 while `aaIdentity` exceeds the 124-byte appProperty limit is reported as "App identity is too long for Google Drive metadata…" followed by Drive's own message.
- Q-12 · TOOLS-002/014 · the synced-folder copy and the OAuth upload flush **all** editors (incl. detached item windows and the SIRE body) before saving (`env.saveQuietly()`); Load and the newer-save check also flush before the review (ARCH §7.9), so the "current" side of the diff includes pending edits.
- Q-15 · TOOLS-046, §6.7 · Folder builder creates paths from the tree's canonical (first-seen) spelling, so a case-sensitive volume gets the same structure as Windows; the preview count and `rels` keep the Windows rule.
- Q-16 · TOOLS-069 · Date calculator computes in Int64 and shows `Result is out of range.` instead of crashing for results outside 0001-01-01…9999-12-31 (incl. the `n × 7` overflow).
- Q-17 · §6.2, §6.7 · a stored `GoogleDriveFolder` / `FolderBuilderBase` that is not an absolute POSIX path (e.g. `G:\My Drive` from a copied Windows settings file) is treated as unset and left untouched until a new folder is chosen.
- Q-18 · §6.5 · a background check is skipped while a push or another check is running; the review sheet goes through the window's dialog queue, so a background prompt never stacks on another sheet. Upload / Load / Check are disabled while one of them is in flight (router reads `inFlight`).
- DATA-174 · TOOLS-002/003/007/014/015/023 · in a read-only copy (or after DATA-180 "Stop Editing Here") the Settings ▸ Sync Drive buttons that match the router's `readOnlyDisabled` rows (Choose… folder, Save a Copy to Google Drive, Choose client_secret.json…, Check for Newer Save, Upload Backup…, Load Backup…) are disabled with the tooltip `Not available in a read-only copy of AA.`; the six `DriveActions` entry points refuse with that status text when reached anyway, and the newer-save check (background or after turning sync on) does not run. Sign Out and the sync-on-save toggle stay available, as in the menu.
- Q-21 · TOOLS-002/014 · in safe mode the synced-folder copy and the OAuth upload refuse with the "Safe mode — not saving" alert instead of bundling an unreadable file.
- TOOLS-034 · Drive / OAuth errors show Google's own message in the .NET client's wording (`The service drive has thrown an exception. HttpStatusCode is Forbidden. …`, `Error:"access_denied", Description:"…", Uri:""`) and append the setup hint for `access_denied`, `invalid_client`, `unauthorized_client` and `insufficientPermissions`.
- TOOLS-012, §6.3 · token at rest = `AAKCGCM1` + AES-256-GCM (combined) with the key in the Keychain item `AA` / `google-token-key` (DATA-215, OC-34); a copied Windows `AADPAPI1` file never counts as a token (re-consent notice shows instead); a legacy plaintext JSON token is read and re-stored encrypted (DATA-073). The token JSON is Mac-private (keys as Windows, STJ escaping).
- §3.1.14 · the loopback listener binds `127.0.0.1` only (no `localhost` fallback, RFC 8252); PKCE S256 + `state`; one retry with `prompt=consent` when no refresh token came back; a 4xx refresh deletes the token, 5xx keeps it; a 401 refreshes once and retries.
- §6.2 vs 03 §6.x · Drive-folder auto-detection uses spec 14 §6.2's order (CloudStorage `GoogleDrive-*/My Drive` sorted, `/Volumes/GoogleDrive/My Drive`, `/Volumes/*/My Drive`, then `~/My Drive`, `~/Google Drive`, `~/GoogleDrive`); 03's list puts the home candidates first — 14 is the feature owner's spec.

### Kept quirks (P3)

- Q-2 listing creates `AA Backups`; Q-4 duplicate `AA Sync` folders; Q-5 best-remote key mixes local-wall-clock stamps with UTC Drive times (vector 7.6-1 asserts it); Q-9 a new client keeps the old token; Q-10 upload text always says `AA Backups`; Q-11 Load cancel keeps the "listing backups…" status; Q-19 re-consent notice on every launch; Q-20 fallback wording; 3.4.1 negative day counts in the Y/M/D line.

### Mac additions (P4, additive)

- Saved-to-Drive alert has a **Show in Finder** button; the upload alert has **Open in Browser** when Drive returned a link.
- Sign-in sheet: countdown and **Open Browser Again**.
- Settings ▸ Sync embeds `DriveSettingsSection` (folder, client, sign-in state, sync toggle, last activity with the 14 §6.5 indicator symbols, Check / Upload / Load buttons).
- Folder builder: SF Symbol `folder.fill` replaces 📁, always-expanded preview, ⌘↩ = Create folders, Esc = Close, folder picker can create folders, read-only path display with selectable text.
- Date calculator: segmented Add/Subtract, a stepper beside the free-text amount, a calendar popover beside each date field, selectable monospaced results.
- Unit converter: category popup with SF Symbols, monospaced value fields; a field that merely gains focus never rewrites the others (only a real text change does, like WPF `TextChanged`).

### Not applicable / not shipped

- §3.1.11 `GetSyncStateAsync` / `DownloadSyncAsync` — unused on Windows; omitted (spec: MAY).
- §3.2.9 legacy `ImportFolderFromZip` — W-PERSIST's (DATA-047), not wired to UI.
- 14 §6.5 toolbar sync indicator — the main toolbar is F3's; the indicator state is published (`env.driveSync.indicator`, `lastStatus`) and shown in Settings ▸ Sync until F3 adds a toolbar slot (REQ-W-DRIVE-01).
