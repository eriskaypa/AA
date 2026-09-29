# AA for macOS — OWNERSHIP (work breakdown, path ownership, feature map)

Binding for every stage and wave agent. Contracts referenced as `ARCH §n` are in `ARCHITECTURE.md`.
Authority: brief → DECISIONS → ARCHITECTURE → this file → specs. **No path is owned twice; every feature ID has
exactly one owner.** An owner owns every file under its directories, including placeholder files other stages
created there for it (ARCH §11). Revision 2 (see ARCH "Review log"): the save pipeline IDs moved to F1; the XLSX
reader, `NetDateParser` and `CrewText` moved to F2; the File-menu flows, Settings/About/Shortcuts windows,
reminders and packaging moved from F3 to the new wave agent **W-SHELL**; the golden-fixture plan moved from
W-PERSIST to the new **W-GOLD**; W-CAL+W-BOARD merged into **W-PLAN** (spec 07) and W-WIN+W-QWORK into **W-QUICK**
(spec 08), keeping 16 wave agents.

## 1. Stages

| Stage | Agents | Starts from | Delivers |
|---|---|---|---|
| F1 | F1 (main checkout, branch `mac-port`) | spec commit | Package, AACore data layer, codecs, crypto, AppStore core + the whole save pipeline, XLSX writer, all AACore placeholders (except `Launch/`, `Commands/`), AACoreTests base |
| F2 ∥ F3 | F2, F3 (separate worktrees) | F1 commit | F2: repository domain ops + services + XLSX reader + `NetDateParser`/`CrewText`. F3: app plumbing — scenes incl. bootstrap/`SceneOpener`, launch, commands/router/menus, design system, shared dialogs, navigation/status/flush, snapshot hook, all AA-target placeholders |
| W | 16 wave agents (one worktree each) | merged F1+F2+F3 | vertical slices (below), each replacing only its own placeholders |
| V | verifiers | merged W | checks every feature ID of §4 against its owner's code; runs every card's **post-merge** acceptance and all `ContractStatus`-gated tests; merges `Docs/Deviations/*.md` into `Docs/DEVIATIONS.md` |

Wave agents (16): **W-SHELL, W-PERSIST, W-GOLD, W-RICH, W-CONT, W-FILES, W-HIER, W-BUILD, W-PLAN, W-QUICK,
W-CREW, W-VESSEL, W-PDF, W-SIRE, W-FLASH, W-DRIVE.**

Size estimates (Swift lines, from the C# sizes and the library replacements; ID counts are a poor proxy):

| Agent | ≈ lines | Agent | ≈ lines | Agent | ≈ lines |
|---|---|---|---|---|---|
| F1 | 8–9k | W-GOLD | 1k Swift + 3–5k C# (not compiled here) | W-PLAN | 4–4.5k |
| F2 | 6.5–7.5k | W-RICH | 6–7k | W-QUICK | 3.5–4k |
| F3 | 8–10k | W-CONT | 3.5k | W-CREW | 3.5k |
| W-SHELL | 4–5k | W-FILES | 2.5k | W-VESSEL | 3.5k |
| W-PERSIST | 5–6k | W-HIER | 4–4.5k | W-PDF | 6–7k |
| | | W-BUILD | 3.5k | W-SIRE 3.5k · W-FLASH 4–4.5k · W-DRIVE 4k | |

---------------------------------------------------------------------------------------------------------------------

## 2. Path ownership (authoritative; paths relative to `mac/`)

`dir/**` = the directory and everything below it. Every agent additionally owns `Docs/Requests/<id>.md` and
`Docs/Deviations/<id>.md`. Only `.swift` files under `Sources/**`, `Tests/AACoreTests/<Area>/**` and
`Tools/FlashSyncInterop/**` (ARCH §1.1).

| Owner | Paths |
|---|---|
| lead / architect | `Docs/ARCHITECTURE-BRIEF.md`, `Docs/DECISIONS.md`, `Docs/Spec/**`, `Docs/original-source-checksums.sha256`, `Docs/ARCHITECTURE.md`, `Docs/OWNERSHIP.md`, (Stage V) `Docs/DEVIATIONS.md` |
| **F1** | `Package.swift`; `.gitignore` (append-only; incl. the 01 GF.4.1 lines, ARCH §1.2); `Scripts/check-placeholders.sh`; `Scripts/check-ownership.sh`; `Sources/AACore/{Foundation,JSON,Model,Persistence,Crypto,Zip,Xlsx,Resources}/**`; `Sources/AACore/Store/AppStore.swift`; `Sources/AACore/Store/PersistenceWriter.swift`; `Tests/AACoreTests/Support/**`; `Tests/AACoreTests/{Foundation,JSON,Model,Persistence,Crypto,Zip,Xlsx,Store}/**`; `Tests/AACoreTests/Fixtures/{foundation,json,model,persistence,zip,xlsxwriter}/**` |
| **F2** | `Sources/AACore/Store/AppStore+Lookups.swift`, `AppStore+Relations.swift`, `AppStore+Log.swift`, `AppStore+Trash.swift`, `AppStore+Recurrence.swift`, `AppStore+Groups.swift`, `AppStore+Creation.swift`; `Sources/AACore/{Services,XlsxRead}/**`; `Tests/AACoreTests/{Services,StoreDomain,XlsxRead}/**`; `Tests/AACoreTests/Fixtures/{services,xlsx}/**` |
| **F3** | `Sources/AACore/{Launch,Commands}/**`; `Sources/AA/{App,Shell,Commands,Design,Shared,Debug,Resources}/**`; `Tests/AACoreTests/{Launch,Commands}/**`; `Tests/AACoreTests/Fixtures/{launch,ui/f3}/**` |
| **W-SHELL** | `README.md`; `VERSION`; `Packaging/**`; `Resources/**`; `Scripts/build-app.sh`; `Sources/AACore/ShellSupport/**`; `Sources/AA/ShellFeatures/**`; `Tests/AACoreTests/ShellSupport/**`; `Tests/AACoreTests/Fixtures/{shell,ui/w-shell}/**` |
| **W-PERSIST** | `Sources/AACore/{Bundles,Attachments,SharedSave,Instance}/**`; `Sources/AA/PersistenceUI/**`; `Tests/AACoreTests/{Bundles,Attachments,SharedSave,Instance}/**`; `Tests/AACoreTests/Fixtures/{bundles,settings,attachments,ui/w-persist}/**` |
| **W-GOLD** | `Tools/global.json`; `Tools/{WinFixtures,WinCapture,XlsxGolden}/**`; `Scripts/fixtures.sh`; `Tests/AACoreTests/WinFixtures/**`; `Tests/AACoreTests/Fixtures/{winfixtures,mac-out,xaml/wpf-capture,xaml/mac-roundtrip}/**` (XlsxGolden writes to `Fixtures/winfixtures/xlsx/`, never into F2's `Fixtures/xlsx/`) |
| **W-RICH** | `Sources/AACore/RichText/**`; `Tests/AACoreTests/RichText/**`; `Tests/AACoreTests/Fixtures/xaml/**` **except** `xaml/wpf-capture/**` and `xaml/mac-roundtrip/**` (W-GOLD); `Tests/AACoreTests/Fixtures/html/**` |
| **W-CONT** | `Sources/AACore/Editor/**`; `Sources/AA/Editor/**`; `Tests/AACoreTests/Editor/**`; `Tests/AACoreTests/Fixtures/{editor,ui/w-cont}/**` |
| **W-FILES** | `Sources/AACore/FileBank/**`; `Sources/AA/FileBank/**`; `Tests/AACoreTests/FileBank/**`; `Tests/AACoreTests/Fixtures/{filebank,ui/w-files}/**` |
| **W-HIER** | `Sources/AACore/Hierarchy/**`; `Sources/AA/Hierarchy/**`; `Tests/AACoreTests/Hierarchy/**`; `Tests/AACoreTests/Fixtures/{hierarchy,ui/w-hier}/**` |
| **W-BUILD** | `Sources/AACore/Builders/**`; `Sources/AA/Builders/**`; `Tests/AACoreTests/Builders/**`; `Tests/AACoreTests/Fixtures/{builders,ui/w-build}/**` |
| **W-PLAN** | `Sources/AACore/{Calendar,Board}/**`; `Sources/AA/{Calendar,Board}/**`; `Tests/AACoreTests/{Calendar,Board}/**`; `Tests/AACoreTests/Fixtures/{calendar,board,ui/w-plan}/**` |
| **W-QUICK** | `Sources/AACore/{QuickWork,Windows}/**`; `Sources/AA/{QuickWork,Windows}/**`; `Tests/AACoreTests/{QuickWork,Windows}/**`; `Tests/AACoreTests/Fixtures/{quickwork,windows,ui/w-quick}/**` |
| **W-CREW** | `Sources/AACore/Crew/**`; `Sources/AA/Crew/**`; `Tests/AACoreTests/Crew/**`; `Tests/AACoreTests/Fixtures/{crew,ui/w-crew}/**` |
| **W-VESSEL** | `Sources/AACore/Vessel/**`; `Sources/AA/Vessel/**`; `Tests/AACoreTests/Vessel/**`; `Tests/AACoreTests/Fixtures/{vessel,ui/w-vessel}/**` |
| **W-PDF** | `Sources/AACore/Export/**`; `Sources/AA/Export/**`; `Tests/AACoreTests/Export/**`; `Tests/AACoreTests/Fixtures/{pdf,ui/w-pdf}/**` |
| **W-SIRE** | `Sources/AACore/Sire/**`; `Sources/AA/Sire/**`; `Tests/AACoreTests/Sire/**`; `Tests/AACoreTests/Fixtures/{sire,ui/w-sire}/**` |
| **W-FLASH** | `Sources/AACore/FlashSync/**`; `Sources/AA/FlashSync/**`; `Tools/FlashSyncInterop/**`; `Tests/AACoreTests/FlashSync/**`; `Tests/AACoreTests/Fixtures/{flashsync,ui/w-flash}/**` |
| **W-DRIVE** | `Sources/AACore/{GoogleDrive,Tools}/**`; `Sources/AA/{Drive,Tools}/**`; `Tests/AACoreTests/{GoogleDrive,Tools}/**`; `Tests/AACoreTests/Fixtures/{drive,tools,ui/w-drive}/**` |

Notes:
* `Sources/AACore/Store/` holds exactly the nine files listed (2 F1 + 7 F2); nobody adds files there.
* F1 creates, inside other owners' folders, the placeholder files of every AACore contract (ARCH §5.3, §6.5–§6.8),
  one `<Area>ContractStatus.swift` per wave owner with an AACore folder (ARCH §6.1, §11), the minimal AA-target
  bootstrap (`Sources/AA/App/AAMain.swift`, `Sources/AA/Resources/*`) and `Tools/FlashSyncInterop/main.swift` —
  they belong to the folder owner from creation. F1 creates nothing in `Sources/AACore/{Launch,Commands}` (F3
  writes them). F3 creates the AA-target placeholders of ARCH §7.7 (incl. W-SHELL's) and every
  `Sources/AA/<Dir>/<Area>DebugSnapshots.swift` (ARCH §9.6) in the wave owners' folders.
* `Tests/AACoreTests/Fixtures/` is one SwiftPM resource folder; each owner only adds files in its sub-folders.
* Paths that required IDs name and that had no owner before revision 2: `Tools/global.json` (DATA-313),
  `Scripts/fixtures.sh` (GF.4.1), `Fixtures/mac-out/**` (DATA-312/325) → W-GOLD; `VERSION` (BD.3.11) → W-SHELL;
  the GF.4.1 `.gitignore` lines → F1; `Tests/AACoreTests/Foundation/**` and `Fixtures/foundation/**` → F1.

---------------------------------------------------------------------------------------------------------------------

## 3. Agent cards

Every card: **Scope · Specs · Implements (contracts) · Consumes · Acceptance (in-worktree / post-merge).** All
agents also follow ARCH §2 (layering/isolation), §8 (design system), §9 (cross-cutting), §10.5–10.6 (vectors,
gated tests, gate), §11 (placeholders), §12 (protocol incl. §12.2 namespacing). **In-worktree** acceptance gates
"done" (ARCH §12.4); **post-merge** items need another wave owner's real code, are written as
`ContractStatus`-gated tests or manual checks, and are verified in Stage V.

### F1 — Foundation: data layer, codecs, crypto, AppStore core and save pipeline, XLSX writer
* **Scope:** Package.swift (ARCH §1.1) and folder skeleton; ordered JSON layer with the .NET-compatible writer
  (ordinal strings, `.rawString` dates, `deepEquals`, lenient UTF-8); `NetDateTime`/`CivilDate`/clock, .NET GUID and
  enum formats (Int32 rules); **all model classes** of ARCH §4 with JSON mappings, defaults, legacy migrations and
  extra-member preservation (isolated conformances, `nonisolated` value records, `HierarchyItem` class-var shape);
  `ModelCodec`, `TrashPayload`, dynamic-type deep clone; `DataStore` (paths, load/save/atomic write, schema
  migration, BOM, safe-mode flags, local at-rest encryption `AAENCM1` with a per-session key cache, Windows `AAENC1`
  detection, `saveTo` D-14 fix, `writeGuard` calls); `SettingsStore` (DATA-182 key-level merge, retry, refusal,
  joint writes, per-key tolerance, throwing `readRawTree`, atomic refusing `writeRawTree`); `AppStore` core — the
  whole save pipeline (dirty tracking, 750 ms debounce, confirmed save with 15 s timeout, ordered writer, stamp
  rollback, `suspendSaving`, `pauseWrites`/`resumeWrites`, `replaceData`, events) + `PersistenceWriter` with the
  `DataFileWriteGuard` hook; ZIP reader/writer; CRC-32 + raw DEFLATE; XLSX **writer** (09 §3.10/§4.10, 10 §6.6,
  raw parts for 11 §4.5) + `NetNumberText`; crypto primitives, PBKDF2 app password hash, `enc:` blobs, item-lock
  hashing, `PasswordService`, `ItemLockService`, `SecretStore` (file-based login keychain); Foundation helpers
  (Identifiers, SceneID, UTTypes, AAResources, NetText, Ordinal, WindowsFileName, WpfColor + `ARGB` public init,
  OrderedMap with .NET slot reuse, EventHub + `isolated deinit`, MacPreferences, AALog, **MacKeyStrings** (full
  20-row table), ContractStatus); byte copies of `AA/Sire/Data/sire2_question_bank.json` →
  `Sources/AACore/Resources/` and `AA/Assets/Splash.png` → `Sources/AA/Resources/Splash.png` (SHA-256 must match 03
  BD.7.3), placeholder `MenuBarIconTemplate*.png`; `Scripts/check-placeholders.sh` / `check-ownership.sh` (path,
  non-Swift-file, basename and cross-owner symbol checks, ARCH §12.2); **compiling placeholders for every other
  AACore contract** (ARCH §5.3, §6.5–§6.8, per-owner ContractStatus files; nothing in `Launch/`/`Commands/`) and the
  AA bootstrap (`AAMain.swift` that just shows an empty window, marked `PLACEHOLDER(F3)`); AACoreTests `Support/`
  + golden-format tests (ARCH §10.3) + fixtures.
* **Specs:** 01 §4 (all), §3.1–3.4, §3.11, §3.13, §3.14 (byte format only), §3.19–3.23, §3.25–3.26, §6.1–6.5,
  §6.8, §6.11, §7.1–7.5, §7.10, §7.12; 01 App. A; 01 OWN (DATA-200…224 governance; DATA-215 Keychain registry);
  01 DATA-025, 031, 135, 182 and MP.7.6; 02 REPO-001…008, REPO-003a, REPO-040, 054, 064; 03 SHELL-051, §6.5.1.9
  (MacKeyStrings), BD.3.4, BD.7.3; 05 CONT-094; 05 XD.4 + ARCH §6.7 (placeholder signatures only); 07 VIEW-154;
  09 §3.1, §3.10, §4.10, §7.13, CREW-052, CREW-093; 10 §6.6 "Writing"; 11 §4.5 (package API only); 13 §3.2–3.3,
  §3.11.9–3.11.10, §6.2, §7.2, §7.6.
* **Implements:** ARCH §3, §4, §5.2, §6.1–§6.4.
* **Consumes:** nothing (placeholders only).
* **Acceptance — in-worktree (all of it; F1 has no post-merge part):** gate green; §10.3 goldens (fresh DB string;
  escaping table incl. the 01 §7.4 `Pump → main …` vector; numbers incl. `1E-05`/`0.0001`/`1.5E-07`/`5E-324`;
  dates incl. three time zones, fraction trimming, originalText round trip, mutation clears originalText,
  `toLocalTime` on Unspecified, A12 DST vectors; literal `+` in typed dates (01 §4.4 `source.json` literal, B07,
  B08, a Local date in data.json, the Trash payload case); GUIDs; order; unknown members incl. null/`1.50`/`-0`/
  `1e2`; Int32 range rules (A07); Status/IsComplete; BucketId incl. malformed → load failure; depth 64; A19 root
  and trailing-content cases; lenient UTF-8; CS-19 ordinal/deep-equals vectors; OrderedMap slot reuse);
  round-trip of every `Fixtures/json` sample byte-identical; PBKDF2/`enc:`/lock vectors (01 §7.1–7.3, 04 §7.8);
  ZIP round-trip incl. empty `files/` dir entry and Zip64 header; XLSX **writer** bytes of 09 §7.13 and the
  ColRef/escape/sheet-name rows of 11 §7.14 and 06 §7.13; 06 §7.14 JSON round trip; 04 §7.3 WhenText; settings
  MP.7.6 S-1…S-4; autosave test (markDirty ×N → one write ≥ 750 ms later; failure restores `LastModified`); save
  timeout path; write-guard refusal → `.pausedByGuard`, stamp restored, writes paused; `deepClone(task as
  HierarchyItem) is TaskItem`; observation test for base-class properties on subclasses (ARCH §3.9); `swift
  build` of the whole package with every placeholder; `check-placeholders.sh` lists only non-F1 owners.

### F2 — Repository & domain services, XLSX reader, shared date parser
* **Scope:** all AppStore domain operations (ARCH §5.3) and AACore services (ARCH §6.5): lookups, relations and
  reference purge (widened, DECISIONS 02 Q-3), creation catalogue, activity log, Trash/soft delete/batch/restore/
  purge/prune/undo incl. `trashSubtask` (DECISIONS 02 Q-4), recurrence regeneration (calendar-date outputs),
  groups, WorkRange, BatchDone/Deadline/Delete, search documents & scan & snippets, quick-switcher scoring,
  reminders, saved-list order (fixed nudge), checklist-template service, schedule service (`.aasched.json` via F1
  JSON, `includeExtra = false`), DataDiff (+ "Other data", OC-13), AgeVerdict, XamlPlainText (search + diff
  variants); **the XLSX reader** (10 Addendum X, `AACore/XlsxRead/`, three renderers + `ShippalmDates`);
  **`NetDateParser`** (09 §6.3) and **`CrewText`** (09 §3.2).
* **Specs:** 02 (all of §2–§4, §6, §7, §8 decisions, except REPO-001…009 and REPO-003a); 01 §3.15–3.18, §3.24,
  §7.8, §7.9, §7.11; 08 §3.6–3.7, §7.3, §7.4, §7.7; 04 §3.11–3.13, §7.2, §7.4–7.6; 06 BUILD-A7…A9, A12…A14,
  A19, A20, §7.1, §7.4, §7.10, §7.11; 09 §3.2, §6.3, §7.1; 10 Addendum X (VESSEL-300…334, X.8.1 columns
  Kind/A/B/B+/C, X.8.2–X.8.8).
* **Implements:** ARCH §5.3, §6.5.
* **Consumes:** F1 models, JSON, DataStore, NetNumberText, MacKeyStrings, ItemLockService (`isGated` passed as
  closure).
* **Acceptance — in-worktree:** every 02 §7 vector (T-REL, status/done, T-RNG, recurrence incl. `.unspecified`
  outputs, trash/undo incl. subtask trash/restore, batch-delete description texts with Mac key strings, search incl.
  lock gating and snippets, reminders, T-ORD incl. OC-16 per-group assertions, templates, schedule JSON bytes,
  log, groups, switcher scoring); 01 §7.8/7.9/7.11 (as amended by DECISIONS Q-6, ARCH §3.4); 08 §7.3/§7.7; 04
  §7.2/§7.4–7.6; 06 §7.1/§7.4/§7.10/§7.11; 09 §7.1 ParseDate; 10 X.8.1 (Kind/A/B/B+/C) and X.8.2–X.8.8 with
  hand-built workbooks; 2 524×16 sheet < 200 ms; no UI code. **Post-merge:** XlsxGolden comparisons when W-GOLD's
  goldens exist.

### F3 — Application plumbing
* **Scope:** `AAMain`/AppDelegate/LaunchCoordinator (instance check → splash → login → main), the **bootstrap
  scene + `SceneOpener`** (ARCH §7.1), crash reporting (SHELL-001/197, `CrashLog`, uncaught exceptions, MetricKit),
  launch arguments & data-folder resolution/pre-flight (`--data-dir`, `AA_DATA_DIR`, `--version`; `--smoke-test`
  dispatch to W-SHELL), all scenes (ARCH §7.1, restoration disabled, `NSQuitAlwaysKeepsWindows = false`),
  `AppEnvironment` (incl. `SharedSaveHost`, `DataFileConflictHost`), launch wiring of the DATA-180 guard and the
  external-file lock, main window (section sidebar = tab strip with reorder preserving unknown TabOrder entries,
  colours, Crew badge; toolbar; status line; shared-save indicator; shortcut strip; banners), Tab Colours sheet,
  window-state persistence, **the full menu bar per 03 §6.5.1** (registry, CommandRouter, AppKit menu bridge,
  list/section/window publishing modifiers, `AARichTextResponder` protocol) wired to owners (File/Tools flows →
  W-SHELL `ShellFlows`), ⌘S/`doSave`, quit pipeline, 5-min autosave, recurrence-after-save, `loadDataAndInitUI`,
  import review gate (`reviewAndConfirmImport` incl. the DATA-104 fallback), navigation (`Navigator`),
  `StatusCenter`, `EditorFlushCenter`, design system (ARCH §8), shared dialogs (ARCH §7.5: `@Entry` presenter,
  prompt, date prompt, `OptionalDatePicker`, item picker, alerts, password sheet, panels), debug snapshot hook +
  `SnapshotRegistry`; **compiling placeholders for every AA-target contract of ARCH §7.7** (incl. W-SHELL's).
* **Specs:** 03 (all, incl. Addendum BD and §6.5.1) **except** the W-SHELL rows of §4 below; 01 §A, §6.2, §6.10
  (UI parts), DATA-001…005, 010, 020, 021, 026…028, 035, 035a, 036, 081, 104, 186, 214, 223; 01 MP.6.1–6.2 (launch
  order); 02 REPO-009; 04 HIER-120, 123, 130…132; 06 Addendum (BUILD-130, 131, 136…150; A22–A24, A28); 07
  VIEW-203…205, 208…212, 215, 216 (components; caller rows per §4 "Caller registries"); 08 QUICK-190, 210…212,
  230; 13 FLASH-001, 002; DECISIONS 03.
* **Implements:** ARCH §6.9, §7 (all plumbing), §8, §9.2, §9.6.
* **Consumes:** F1 (DataStore, SettingsStore, AppStore, PasswordService, ItemLockService, Identifiers,
  MacKeyStrings), F2 (undo/trash counts, reconcileRecurrences, DataDiff/AgeVerdict), W placeholders (views, action
  enums, `ShellFlows`, `ReminderCenter`, `SharedSaveCoordinator`, `DriveSyncCoordinator`, `InstanceGuard`,
  `DataFileFingerprint`, `CrewExpiry`, `DueDatesPanelController`…).
* **Acceptance — in-worktree:** `swift run AA --data-dir $(mktemp -d)` shows splash (≈2.4 s) → login
  (44233/redemption, wrong password rejected) → main window with 13 sections (placeholders visible) and status
  `Loaded — …/data.json`; no window is restored by the system after a relaunch; `--version`; snapshot hook
  produces PNGs for every `SectionID` and every scene id in both appearances (rendering the scene's window by
  identifier); registry integrity tests (uniqueness after shift normalisation, reserved keys, text safety) and
  router tests T-KB-01…58 that are pure; BD.7.1/7.5 vectors; menu tree equals 03 §6.5.1.6; ⌘S/⌘W/⌘Q pipelines;
  shared dialogs demo sheets registered in the snapshot registry; `SectionID.writeTabOrder` unknown-entry
  vectors. **Post-merge:** T-KB rows that exercise wave views; `--smoke-test` end to end (W-SHELL).

### W-SHELL — App-level features: File-menu flows, Settings/About/Shortcuts, reminders, packaging
* **Scope:** `ShellFlows` for every File/Tools row of ARCH §7.8 marked W-SHELL (Save a Copy As with the D-14 fix,
  Reload from Disk, Import from File with Copy-into/Use-in-place and `InstanceGuard.acquireExternal`, Export /
  Import Data Folder (ZIP) incl. text-only toggle, Encrypt Local Data toggle (confirm, status, re-save), Shared
  Save ▸ Set/Stop/Check via `SharedSaveCoordinator`, Set App Identity (BUILD-145 B1), Open Data Folder, Set /
  Change Password with current password (DECISIONS 01 Q-4), Lock Now), `.aaz`/document opening from Finder
  (SHELL-185, forwarded documents), `SettingsView` (General, Security, Sync, File Links, AI tabs embedding the
  owners' sections), `AboutView`, `KeyboardShortcutsView` (SHELL-523), `MenuBarExtraContent`, `ReminderCenter`
  (UserNotifications, Dock badge, MenuBarExtra headline, digest cadence incl. day rollover and wake, calling
  `WorkOrderNotifications.runDigest`), `NotificationCenterBridge` (SceneRequest round trip through `userInfo`),
  `SmokeTest` (`--smoke-test`, BD.3.12), `Scripts/build-app.sh`, `Packaging/**` (Info.plist incl. UTTypes and
  `NSCameraUsageDescription`, entitlements, portable launcher), icon generation, `VERSION`, README.
* **Specs:** 03 SHELL-061…063, 065…072, 101, 102, 115, 130…133, 170…174, 176, 177, 180…191, 195, 196, 202…207,
  523, §6.8, BD (packaging, build, smoke, docs parts); 01 DATA-012, 032…034,
  040, 042, 043, 048, 050, 051, 070, 080; 02 REPO-112, 113; 09 CREW-092; 06 BUILD-A25, A27 (B1 part; B2 status is
  W-SIRE's); DECISIONS 01 Q-4, Q-5, Q-7, 02 Q-7, 03 Q-4.
* **Implements:** ARCH §7.7 rows W-SHELL; §9.3.
* **Consumes:** F1 (DataStore, SettingsStore, PasswordService, ItemLockService, SecretStore), F2
  (ReminderService), F3 (AppEnvironment, dialogs, router state, `SceneOpener`, `loadDataAndInitUI`,
  `reviewAndConfirmImport`), W-PERSIST (`BundleService`, `SharedSaveCoordinator`, `InstanceGuard`,
  `PathMappingSettingsView`), W-DRIVE (`DriveSettingsSection`), W-SIRE (`GeminiKeySettingsSection`), W-VESSEL
  (`WorkOrderNotifications`), W-QUICK (`DueDatesPanelController`), W-CREW (`CrewExpiry`).
* **Acceptance — in-worktree:** file-flow unit tests over F1/F2 code with a temp AppFolder (Save a Copy As stamps
  only the copy; encrypt toggle re-save; identity blank → default; password change requires the current one);
  reminder dedup/digest cadence tests with `FixedClock` (launch, 30-min, day change, wake); SceneRequest
  userInfo round trip; `--smoke-test` JSON lines (BD.4.7) and exit 0; `Scripts/build-app.sh` produces
  `dist/AA.app` (universal, ad-hoc signed, hardened runtime, one camera entitlement, no sandbox) and passes the
  BD.7.4 checks that can run on this host; snapshots of Settings (every tab), About, Keyboard Shortcuts. **Post-
  merge:** export→import ZIP through the real `BundleService`; shared save set/stop against the real
  coordinator; work-order notifications fired from the digest.

### W-PERSIST — Bundles, attachments, shared save, instance model, data-file conflicts
* **Scope:** bundle export/import (smart, shared, legacy), `source.json`, peeks, data-only guard, attachments
  store (import copy incl. directory/package → one `.zip` entry, `importData` for pasted bytes, Windows-safe names,
  resolve, normalise, legacy migration, classify, enumerate), path-mapping table + UNC/drive-letter opening
  (`PathMapper`, `AttachmentOpener`) + Settings ▸ File Links view, `DataStore.applySyncedData`, shared-save
  coordinator (push/poll/watch/indicator state, on-close push, join/create outcomes), instance guard (`.aa.lock`,
  forward-to-running-instance per DECISIONS, alerts for other user/remote, read-only banner, external-file lock
  DATA-179), `DataFileFingerprint` (the `DataFileWriteGuard`, watcher, DATA-180 sheet and its outcomes),
  conflict copies (DATA-181) incl. `ConflictCopiesSheet`.
* **Specs:** 01 §D (except DATA-040, 042, 043, 050, 051 flows), §E, §F, §3.5–3.10, §3.12, §4.4–4.5, §4.12,
  §6.6–6.7, §6.9, §7.6–7.7, §7.13; 01 MP (DATA-160…186 except 182, 186); 03 SHELL-123…126, §3.9, §7.2; 05
  CONT-081; DECISIONS 01, 05 (packages zipped, pasted images), 10 Q4.
* **Implements:** ARCH §6.6; `PathMappingSettingsView`, `InstanceAlerts`, `ReadOnlyInstanceBanner`,
  `DataFileConflictBanner`, `DataFileConflictSheet`, `ConflictCopiesSheet` (ARCH §7.7).
* **Consumes:** F1 (DataStore, Zip, JSON, models, AtomicWrite, LocalEncryption, `DataFileWriteGuard`,
  `pauseWrites`), `SharedSaveHost`/`DataFileConflictHost` (F3's AppEnvironment), F3 dialogs (sheets).
* **Acceptance — in-worktree:** 01 §7.6/7.7/7.13 vectors; export→import round trip keeps attachments; data-only
  bundle never sweeps; path traversal rejected; Finder metadata never bundled; package import produces one zip
  entry; shared-save state-machine tests with a temp folder (push, external update, unsynced-edits prompt stub,
  offline/not-saving texts); two-process lock test (spawned helper) and forward rule; MP.7.5 outside-change
  vectors X-1…X-11 with a scripted host; MP.7.7 external-file lock. **Post-merge:** the conflict sheet's "Review
  Changes…" through W-QUICK's review sheet; snapshots of banners and sheets.

### W-GOLD — Golden-fixture plan (Windows oracles and the Swift golden harness)
* **Scope:** C# oracle sources under `Tools/` (WinFixtures, WinCapture, XlsxGolden; never built here — `dotnet` is
  not installed; compilable by inspection), `Tools/global.json`, `Scripts/fixtures.sh`, the fixture tree layout and
  MANIFEST format, masking, platform matrix, Swift `GoldenMatcher`/`FixtureIndex` harness that **skips cleanly**
  when goldens are absent, the `mac-out` emitter (reverse direction), privacy rules.
* **Specs:** 01 GF (DATA-300…326) incl. GF.4.1 paths; 10 X.7.6 (XlsxGolden, output to `Fixtures/winfixtures/xlsx/`);
  05 XD.8 / DATA-321/322 capture folders (`Fixtures/xaml/wpf-capture/`, `Fixtures/xaml/mac-roundtrip/`).
* **Implements:** the GF plan; no ARCH contract is consumed from it by other agents.
* **Consumes:** F1 (JSON, Zip, Fixtures support), F2 (XLSX reader for the XlsxGolden comparisons).
* **Acceptance — in-worktree:** harness compiles and every golden test skips with a clear message when goldens are
  absent; MANIFEST/selfcheck logic unit-tested on synthetic manifests; `mac-out` emitter writes the DATA-312
  artefacts for F1/F2 code paths; C# sources complete per GF.3–GF.6 (reviewed by inspection). **Post-merge:** the
  `mac-out` emitter covers W-PERSIST bundles and W-RICH XAML once those are real.

### W-RICH — Rich-text core (XAML ⇄ attributed string)
* **Scope:** tolerant XamlDOM (arena, parent links, raw + parsed attributes, source ranges), cascade/computed
  style with the four consumer contexts (the complete type set of ARCH §6.7), XamlReader (DOM →
  NSAttributedString + metadata, opaque preservation, display font substitution, lists/tables/blocks on TextKit 1
  types), XamlWriter (05 §4.3.7 rules, "differs from inherited" test, byte-stable untouched content, line-break
  provenance), HTMLToXAML (exact 05 §3.3 output + whitespace clean-up decision), RichListFormatter engine over
  `NSTextStorage`, LockRules geometry and fast scan, loadability verdicts.
* **Specs:** 05 §3.1 (geometry), §3.2, §3.3, §4.3, §4.4, §6.1, §6.4, §6.5 (engine), §7.1, §7.2, §7.4, §7.7;
  05 Addendum XD (CONT-150…169, all XD vectors); 05 CONT-035, 042, 065; 01 §4.11; 12 §4.4 shapes; 11 §6.3
  requirements; DECISIONS 05.
* **Implements:** ARCH §6.7 (XD.4 as completed there).
* **Consumes:** F1 (WpfColor, NetText, JSON escaping for goldens).
* **Acceptance — in-worktree (all):** all XD-V/XD-C/XD-E/XD-W/XD-L vectors; 05 §7.1 HTML goldens (canonical XML
  compare); §7.2 list engine; §7.4 lock geometry; §7.7 reader/writer goldens incl. untouched-body byte stability
  and lock sentinel round-trip; performance budget 1 MB < 50 ms; `RichTextContractStatus` flipped.

### W-CONT — Container rich-text editor
* **Scope:** `ContainerEditorView` (rich text + embedded `FileBankView`), `AARichTextView` (TextKit 1,
  `AARichTextResponder`), load/flush/400 ms debounce, content-withheld guard (incl. the placeholder-reader guard,
  ARCH §6.7), legacy `enc:` migration, one editor per container via `EditorFlushCenter`, identity rebind on
  reload (ARCH §2.4), format bar (all CONT-020…034 controls) and every Format-menu action, find bar, paste
  pipeline (own XAML type, RTF, HTML via W-RICH, plain, Paste and Match Style, images → `AttachmentStore.importData`
  → `FileBankOperations.addImported` + inline notice), lists UX (Tab/⇧Tab/Return/Backspace/move), insert
  hyperlink/table/saved list (dialogs), text lock (lock/unlock with app-password gate, edit filtering, hint),
  spelling defaults, ⌘-click links, ⎋ pass-through.
* **Specs:** 05 §2.1–2.4 (CONT-001…066 except 035, 042, 049, 050, 065), §3.1, §3.4, §6.2–6.3, §6.5–6.8, §6.10,
  §6.12, §7.3, §7.8; 06 BUILD-100, §4.6, A18, §7.12; 03 SHELL-678, 680…682, 685, 689, §6.5.1 Format rows
  (behaviour); BUILD-145 B5 (insert-table prompt caller); DECISIONS 05.
* **Implements:** `ContainerEditorView`, `ContainerEditorContext`, `EditorHost` (ARCH §7.7); `AARichTextResponder`
  conformance; pure helpers in `AACore/Editor`.
* **Consumes:** W-RICH (reader/writer/HTML/RichListFormatter/LockRules), W-FILES (`FileBankView`,
  `FileBankOperations`), W-PERSIST (`AttachmentStore.importData`), F1 (PasswordService, LegacyBodyCrypto), F3
  (EditorFlushCenter, dialogs incl. password sheet, StatusCenter, router), F2 (ChecklistTemplateService for insert
  saved list).
* **Acceptance — in-worktree:** pure helper vectors (06 §7.12 insert-into-note lines, link normalisation, table
  plans); load/flush/withhold state machine with a stub reader; untouched notes never rewritten (open/close does
  not mark dirty); no persistence while `ContractStatus.isImplemented(.wRich)` is false. **Post-merge:** 05 §7.3,
  §7.8 behaviours; list keys; paste pipeline; T-KB-07/15/21/28/30/31/48/52 manual checks; snapshots of every host
  context (main pane, item window, component/subtask/step editors) in both appearances.

### W-FILES — File bank, read-only viewer, Quick Look, backlinks
* **Scope:** `FileBankView` (tabs, columns, thumbnails/icons, add file/folder/link in place/web link, drag in/out,
  cut/copy/paste true move, remove, open/open all/show in Finder, rename, link to items (VIEW-212 row 26), source
  labels, missing badges), `FileBankOperations`, shared containers UI (`SharedWithContainerIds`), "Linked to" column
  and `FileBacklinksSection` (DECISIONS 05), `ContainerViewerSheet` (HIER-136 incl. OC-12 resolved paths),
  `QuickLookCoordinator` (responder-chain implementation, ARCH §7.7).
* **Specs:** 05 §2.5 (CONT-080, 082…093, 095…098), §3.5, §3.6 (consumer side), §4.2, §6.9, §7.5; 04 HIER-136,
  HIER-M06, §6.8; 03 SHELL-669, 671, 679; DECISIONS 05.
* **Implements:** `FileBankView`, `FileBankContext`, `FileBankOperations`, `FileBacklinksSection`,
  `ContainerViewerSheet`, `QuickLookCoordinator` (ARCH §7.7).
* **Consumes:** W-PERSIST (AttachmentStore, AttachmentOpener, PathMapper), W-RICH (reader for the viewer), F3
  (dialogs, router list commands, item picker), F2 (lookups).
* **Acceptance — in-worktree:** pure FileBank helpers (tab filters, columns, source labels, link rows); T-KB-04/05
  routing; Quick Look on Space with local files. **Post-merge:** 05 §7.5 vectors that go through AttachmentStore;
  drag-in copy vs link-in-place; Windows-path open behaviour; viewer rendering; snapshots.

### W-HIER — Hierarchy pages & item windows
* **Scope:** `HierarchyTabView(kind:)` (sidebar with groups, A→Z, search incl. `#tag`, multi-select, context
  menus, drag to group, empty states), detail pane (header Name/Description/Tags with TagParser, lock buttons,
  Export PDF button), tabs Container / Relationships (incl. `FileBacklinksSection`) / Specifics (Equipment
  components + component editor + linked procedures/tasks; Task schedule & subtasks list with range editors
  against the model; Procedure fields + embed `ProcedureChecklistSection`; Vessel tabs embedding W-VESSEL panels),
  item lock gate + item lock sheet + Lock Now integration (incl. open windows), `ItemWindowView` (detach/reattach,
  orphaning, rename propagation, flush), batch menus/actions (done, deadline, confirm-then-trash incl. nested
  subtasks), navigation request handling, selection persistence, status messages, F2/Return rename, ⌘⌫ routing,
  ⇧⌘N.
* **Specs:** 04 (all except HIER-091, 093…096, 092, 120, 123, 130…132, 136, M06); 02 REPO-023…026, 028, 043,
  051, 053, 075, 106; 07 VIEW-200, 201, VIEW-212 rows 7–12 (callers); 01 §I UI; DECISIONS 04.
* **Implements:** ARCH §6.8 `TagParser`; ARCH §7.7 rows W-HIER.
* **Consumes:** F2 (relations, groups, trash, creation, BatchDone/Deadline/Delete, WorkRange), F1
  (ItemLockService, WhenText), W-CONT (`ContainerEditorView`), W-FILES (`FileBacklinksSection`), W-BUILD
  (`ProcedureChecklistSection`, builders/editors sheets), W-VESSEL (panels, `VesselActions`), W-PDF
  (`PdfExportFlows.exportItem`), F3 (Navigator, dialogs, router, EditorFlushCenter).
* **Acceptance — in-worktree:** 04 §7.1 (TagParser), §7.7 (sidebar build), §7.9, §7.11–7.13 (vectors owned by
  W-HIER); T-KB-02/03/24/25/35/36/49…51; snapshots of all four kinds incl. locked item, empty states, item
  window. **Post-merge:** detached-note snapshot (W-CONT), procedure checklist (W-BUILD), vessel tabs (W-VESSEL).

### W-BUILD — Builders, editors, procedure checklist, saved lists
* **Scope:** generic `ChecklistBuilderView`/`Sheet` (bulk add, insert before/after, edit, ↑/↓, move to, delete,
  save/load/manage saved lists; procedure, crew and saved-list hosts), `ChecklistStepEditorSheet` (stepID + the
  internal detached-step overload), `ProcedureChecklistSection` (step grid, + Step, Remove, Link tasks, + New task,
  Link equipment, context menu, export buttons → W-PDF), `SubtaskBuilderSheet` (+ nested subtasks per DECISIONS
  06), `TaskItemEditorSheet` (subtask editor), Saved Lists tab (groups, arranged order, A–Z, rename, duplicate, edit
  items via `TemplateEditorSheet`, read-only viewer via W-FILES, export buttons → W-PDF), shared-editor reload
  safety.
* **Specs:** 06 §A–§H (except BUILD-091…096, 100, 101, 102), §J (BUILD-132…135), §3 (A1…A6, A10, A11), §6.1–6.4,
  §7.3, §7.5–7.8; 04 HIER-091, 093…096; 02 REPO-027, 134, 147; 07 VIEW-206, VIEW-212 rows 4–6, 13, 14, 18–22
  (callers); 03 SHELL-668; DECISIONS 06.
* **Implements:** ARCH §7.7 rows W-BUILD.
* **Consumes:** F2 (ChecklistTemplateService, SavedListOrder, WorkRange, creation/log), W-CONT
  (`ContainerEditorView`), W-FILES (`ContainerViewerSheet`), W-HIER (`BatchContextMenuItems`), W-PDF
  (export flows), F3 (dialogs, `OptionalDatePicker`, router list commands).
* **Acceptance — in-worktree:** 06 §7.3, §7.5–7.8 vectors; T-KB-32/33/40/45; snapshots of every builder host and
  editor (notes panes show the W-CONT placeholder). **Post-merge:** editors with the real rich-text pane; export
  buttons produce files.

### W-PLAN — Calendar, Planner, Board, Buckets, Relationship Map (all of spec 07)
* **Scope:** Calendar tab (graphical month picker, Day/Week/Month/All Upcoming/Agenda + Overdue group per
  DECISIONS 07 Q-12, table with inline Done bound to the model, batch menus, editors, text size A−/A+ routed from
  ⌘+/⌘−, persistence of Ui keys, crew checklist rows), Planner tab (unscheduled pool with search, Day/Week hour
  grid with 15-min snap and overlap columns, all-day strip, Month grid, drag & drop with live ghost, range-aware
  placement (calendar-date outputs), deadline-aware rules, + Saved list, double-click editors incl. procedures per
  DECISIONS, grey completed per Q-06, localised weekday headers), Board (4 status columns, every task and subtask
  as a card, search, hide done, counts, drag between columns, visible selection, context menu incl. open all files
  and delete **via Trash** per DECISIONS 02 Q-4 — `trashSubtask` for nested cards, + New task, + From saved list),
  Buckets tab (categories case-insensitive merge, members, rename/category/delete, open/remove member),
  Relationship Map (inspect list, per-kind coloured nodes, animated recentre, focus persistence), the internal
  saved-list→tasks picker (VIEW-202/214), reload re-init of all five pages (VIEW-207), navigation call sites
  (VIEW-205).
* **Specs:** 07 (all except VIEW-153, 154, 200, 201, 203…206, 208…213, 215, 216) incl. VIEW-202, 207, 214, VIEW-212
  row 15 (caller); 05 CONT-050; 06 BUILD-101, BUILD-145 B3/B4 (bucket prompts); 09 CREW-091; 02 REPO-031; 03
  SHELL-632…634 behaviour; DECISIONS 07.
* **Implements:** `CalendarTabView`, `PlannerTabView`, `BoardTabView`, `BucketsTabView`, `RelationshipMapTabView`,
  `SectionCommands` for planner/calendar/board.
* **Consumes:** F2 (allJobs, lookups, relations, trash incl. `trashSubtask`, BatchDone/Deadline, WorkRange,
  ChecklistTemplateService.itemToTask), W-BUILD (editor sheets), W-HIER (batch menu items), F3 (Navigator,
  dialogs, item picker).
* **Acceptance — in-worktree:** 07 §8.1–§8.5 vectors (Calendar rows, Board model, Planner geometry/placement,
  Buckets, Map layout); T-KB-06/22/23/26/27; snapshots of every mode. **Post-merge:** editor sheets opened from
  Calendar/Planner/Board.

### W-QUICK — Quick work window and floating/utility windows (all of spec 08 except F2/F3 parts)
* **Scope:** `QuickWorkView` (pinned board with tiles and progress, left list with filters/search/grouping by
  bucket/sorting/counts, context menu, + Task / + Procedure, detail pane with header fields and optional dates,
  children builder (bulk add, reorder, move, delete, edit), save/load saved lists, open in main window, delete via
  Trash per DECISIONS 02 Q-4, flush on close, bucket assignment flow (≤ 2, selection order)); due-dates `NSPanel`
  (sections, rows, tick done, navigation, size persistence, day rollover refresh), quick-switcher panel (scoring
  from F2, keys, open), Search window (single instance per DECISIONS 08 OQ-3, snapshot + background scan,
  highlight `#FFE066`, navigate with child selection per DECISIONS 02 Q-11, `focusQuery`), Activity log window
  (single instance; filter, clear, CSV export), Trash sheet (Finder wording Put Back / Delete Immediately / Empty
  Trash per DECISIONS 02 Q-5, in-sheet keys), `ReviewChangesSheet` (tree, age box, "Other data" toggle per
  DECISIONS 01 Q-3), safe-mode and save-failure behaviour of these windows.
* **Specs:** 08 §2.1–2.7 (QUICK-001…025, 040…084, 100…107, 120…125, 150…156, 170…178, 191…193, 213, 214, 231),
  §3.1–3.6, §4.5–4.7, §6.2 A–G, §7.1, §7.2, §7.4–7.6; 07 VIEW-153, 213, VIEW-212 rows 2–3 (callers); 06 BUILD-102;
  02 REPO-044, 078, 092, 100, 114; 01 DATA-100, 113; 09 CREW-090; 03 SHELL-672, 673, 675; DECISIONS 08.
* **Implements:** ARCH §7.7 rows W-QUICK.
* **Consumes:** F2 (SearchService, QuickSwitcherScoring, ReminderService, creation, trash ops, log, DataDiff
  types, BatchDone/Deadline, ChecklistTemplateService, WorkRange), W-BUILD (`SubtaskBuilderSheet`,
  `ChecklistBuilderSheet`, `ChecklistStepEditorSheet`, `TaskItemEditorSheet`), W-HIER (batch items), F3
  (Navigator, dialogs, item picker, `OptionalDatePicker`, router). (The quick-work window has no rich-text pane;
  notes are edited through the W-BUILD editor sheets.)
* **Acceptance — in-worktree:** 08 §7.1, §7.2, §7.4–7.6 (Activity-log CSV bytes incl. `LocalTime` via
  `toLocalTime`); T-KB-08/09 (window reuse), 55/56/57; snapshots of each window with pins/buckets.
  **Post-merge:** "Open full builder" and editor sheets from quick work.

### W-CREW — Crew
* **Scope:** DateResolver, COMPAS reader over F2's XLSX reader (renderer A), mapping tables, converter, date-order
  question, upsert with Schedule carry-over, import/expiry reports, roster (search, sort modes, expiring filter,
  status line), read-only card, crew editor sheet (Details draft, Checklist tab = W-BUILD builder, Schedule tab),
  **crew schedule builder** (06 §I, templates save/apply/export/import via F2 ScheduleService), delete via Trash,
  Clear all as one Trash batch, crew table window (40-column catalog, chooser, date formats, XLSX export via F1
  writer), `CrewExpiry`, `CrewActions`, badge count.
* **Specs:** 09 (all except CREW-052, 090, 091, 092, 093, §3.2, §6.3, §7.1); 06 §I (BUILD-110…125), BUILD-A15,
  A16, §4.5 UI, §6.5, §7.2, §7.9, VIEW-212 rows 16–17 (callers); 02 REPO-155; DECISIONS 09.
* **Implements:** ARCH §6.8 `CrewExpiry`; ARCH §7.7 rows W-CREW.
* **Consumes:** F1 (XLSX writer, models incl. `contractStatus`), F2 (XLSX reader, `NetDateParser`, `CrewText`,
  trash, ScheduleService, log), W-BUILD (`ChecklistBuilderView(host: .crew)`), F3 (dialogs,
  `OptionalDatePicker`, Navigator crew requests).
* **Acceptance — in-worktree:** 09 §7.2–7.15 vectors; 06 §7.2 (NormTime), §7.9 (timeline); snapshots of
  roster/card/editor/table. **Post-merge:** crew Checklist tab with the real builder.

### W-VESSEL — Vessel dashboard, work orders, ports
* **Scope:** `QuickCardsPanel` (canvas, drag/resize, context menu, open targets through `AttachmentOpener`,
  optional Quick Look), `QuickCardEditorSheet` (targets, icon grid, palette, custom colour, preview),
  `WorkOrdersPanel` (Shippalm import via renderer B, upsert, filters, sort, done/notify, bulk actions,
  notifications bar & master switch, export, `.aaFilterField(for: .main)` search), `WorkOrderNotifications`
  (DECISIONS 10 Q7), `VesselPortsPanel` (two layouts via renderer C, NormDate/NormTime, merge, export, delete with
  fixed RemoveCall matching), `PortsDatabaseTabView`, `MaritimeIcons`, `VesselActions` for the Tools ▸ Vessel
  submenu.
* **Specs:** 10 §A–§G, §3.1–3.7, §4.2–4.9, §6, §7.1–7.16 (excluding VESSEL-280, 283, 284, 300…334), X.8.1 columns
  C·D and C·T, X.8.9; 03 SHELL-157, App. C; DECISIONS 10.
* **Implements:** ARCH §6.8 `MaritimeIcons`; ARCH §7.7 rows W-VESSEL.
* **Consumes:** F1 (XLSX writer, NetNumberText), F2 (XLSX reader, `NetDateParser`, `CrewText`), W-PERSIST
  (AttachmentStore, AttachmentOpener), W-FILES (QuickLookCoordinator, optional), W-SHELL
  (`NotificationCenterBridge`), F3 (dialogs).
* **Acceptance — in-worktree:** 10 §7 vectors (NormDate/NormTime, both port layouts incl. `AA/POC` samples copied
  to `Fixtures/vessel`, Apply/RemoveCall, Shippalm dates/header detection/round trip, due/summary texts, filters,
  quick cards); X.8.1 C·D/C·T and X.8.9; work-order notification dedup with `FixedClock`; performance with 2 524
  rows; snapshots. **Post-merge:** quick-card targets opened through the real `AttachmentOpener`; notifications
  from the W-SHELL digest.

### W-PDF — PDF & checklist export
* **Scope:** MigraDoc-like engine (PdfDOM, styles, CoreText layout with pagination rules, renderer with link
  annotations and page fields), FontResolver (Mac substitution table), LinkScanner, RichTextToPdf over W-RICH's
  XamlDOM (`.pdf` context), item PDF, saved-lists PDF, checklist-only PDF, checklist-only XLSX (exact package
  bytes), `PdfExportFlows` (save panels, busy state, auto-open / "Open it now?", errors), `ListStyleSheet`,
  optional Print (⌘P).
* **Specs:** 11 (all); 06 BUILD-091…096, §4.7–4.9, A17, A21, C1–C3; 04 HIER-092, §3.9, §7.10; 05 CONT-049;
  DECISIONS 11.
* **Implements:** ARCH §7.7 rows W-PDF.
* **Consumes:** W-RICH (XamlDOM/XamlStyleResolver, ARCH §6.7 types), F1 (XLSX package writer, models), F2
  (SavedListOrder, relatedItems, lookups), F3 (dialogs, EditorFlushCenter via `env.flushAllEditors`).
* **Acceptance — in-worktree:** 11 §7.1–7.12, §7.14 (package rows), §7.15 over PdfDOM built from model data
  without rich bodies; checklist XLSX package bytes (PDF-090); layout-engine pagination tests; snapshots of the
  list-style sheet. **Post-merge (gated on `.wRich`):** 11 §7.13 item-PDF DOM golden with rich bodies,
  RichTextToPdf, §7.16 PDFKit integration checks (page count, text, `/URI` annotations).

### W-SIRE — SIRE 2.0
* **Scope:** bank loader (resource via `AAResources`, lazy on first activation), models, filters/sort/stats,
  three-pane tab, detail rendering (SireFlow blocks → NSAttributedString), insertion-only body editor
  (`AARichTextResponder` subset, flush hooks), body persistence to `QuestionBodies` via W-RICH writer, tasks panel,
  offline TaskIdentifier, TagExtractor (verbatim keyword lists as Swift literals), Gemini client + Keychain key
  store (import once), candidate picker, quick-add to AA (`SireToAa` with cross-links and logs), 16-mode export
  sheet (clipboard/file), `SireActions`, `GeminiKeySettingsSection`.
* **Specs:** 12 (all, incl. Addendum SIRE-049…051); 02 REPO-030; 03 SHELL-688; 06 BUILD-A26, BUILD-145 B2 (and the
  B2 part of A27); VIEW-212 rows 23–25 (callers); DECISIONS 12.
* **Implements:** ARCH §6.8 `GeminiKeyStore`; ARCH §7.7 rows W-SIRE.
* **Consumes:** F1 (models, SecretStore, AAResources), W-RICH (reader/writer, `.sirePane` context), F2 (creation,
  relations, log), F3 (dialogs, Navigator, StatusCenter, EditorFlushCenter).
* **Acceptance — in-worktree:** 12 §7.1–7.11 vectors and addendum vectors that do not persist bodies; export golden
  outputs byte-exact (LF); T-KB-53; snapshots. **Post-merge (gated on `.wRich`):** body persistence round trip.

### W-FLASH — Flash Sync
* **Scope:** Base45, xorshift32, degree table, indices, frames, fountain encoder, peeling decoder, manifest labels,
  change sets and snapshots over F1 `JSONValue` (`deepEquals`, per-device Ui keys, excluded keys, settings merge
  with `readRawTree`/`writeRawTree` errors surfaced, apply order, transactional apply per DECISIONS), baseline
  store (encrypted when local encryption is on), pure Swift QR generator (Nayuki parity) + raster, `FlashSyncView`
  (Send: frame clock, keep-awake, speed, confirm; Receive: camera permission/enumeration/format, Vision detection,
  progress, completion, review/apply), optional additions per DECISIONS (Reset pairing, full-screen QR, rich
  review sheet), `AAFlashSyncInterop` CLI.
* **Specs:** 13 (all except FLASH-001, 002, 061, 062), `QR_SYNC_PROTOCOL.md` (read-only reference); 10 VESSEL-284;
  03 SHELL-676; DECISIONS 13.
* **Implements:** `FlashSyncView`; AACore/FlashSync.
* **Consumes:** F1 (JSON incl. `deepEquals`, `NetDateFormat.isoLocal7`/`isoLocalSeconds`/`roundTripO`, CRC32,
  RawDeflate, SettingsStore raw tree, DataStore), W-PERSIST (`DataStore.applySyncedData`), F3
  (`env.flushAllEditors`, `saveQuietly`, `loadDataAndInitUI`, appearance).
* **Acceptance — in-worktree:** all protocol vectors (ARCH §10.4); 13 §7.7 encoder/decoder loss simulations; §7.8
  change-set exact compact outputs; unreadable settings abort the apply with nothing written; QR matrix parity
  tests (and CIQRCodeDescriptor cross-check); unbundled-run guard text; T-KB-46/47; snapshots of Send/Receive idle
  states. **Post-merge (gated on `.wPersist`):** apply → `applySyncedData` → reload end to end.

### W-DRIVE — Google Drive & tools
* **Scope:** synced-folder copy (detection order, backup names, reveal), OAuth client file, loopback OAuth with
  PKCE + cancel sheet + timeout, token store (`AAKCGCM1` files + Keychain key), Drive REST (list with paging,
  shared drives, download, resumable upload/update), restorable-bundle rule, backup picker (VIEW-212 row 1),
  whole-Drive best remote, sync-on-save push (debounce/coalesce), background/interactive newer-save checks, decline
  memory, smart import via the review gate, re-consent notice, status/indicator vocabulary (`roundTripO` for
  `aaLastModified`); tools: Folder builder, Date calculator, Unit converter (.NET number parsing/formatting
  emulation).
* **Specs:** 14 (all); 01 DATA-073, 153; 03 SHELL-010, 011, 073…080, 121, 122, §3.8; DECISIONS 14.
* **Implements:** ARCH §6.8 `GoogleTokenStore`, `BundleName`; ARCH §7.7 rows W-DRIVE (`DriveSyncCoordinator`,
  `DriveActions`, `DriveSettingsSection`, tool views).
* **Consumes:** F1 (DataStore, SettingsStore, SecretStore, NetDateTime), W-PERSIST (BundleService, peeks,
  importBundleSmart), F2 (DataDiff via F3 gate), F3 (`reviewAndConfirmImport`, `loadDataAndInitUI`, dialogs,
  item picker, StatusCenter).
* **Acceptance — in-worktree:** 14 §7.1–7.6, §7.8 vectors (SafeIdentity names, restorable names, folder plan parse,
  date calculator, unit converter, Drive decisions with a mock client, AgeVerdict usage); snapshots of the three
  tools and the sign-in wait sheet. **Post-merge (gated on `.wPersist`):** 14 §7.7 smart import in a temp
  AppFolder.
---------------------------------------------------------------------------------------------------------------------

## 4. Feature map — every feature ID of every spec, exactly one owner

**How the ID sets were built** (re-run it to verify; nothing may be missing or doubly owned):
```
cd mac/Docs/Spec
for p in 01:DATA 02:REPO 03:SHELL 04:HIER 05:CONT 06:BUILD 07:VIEW 08:QUICK 09:CREW 10:VESSEL 11:PDF 12:SIRE 13:FLASH 14:TOOLS; do
  f=${p%%:*}; x=${p##*:}; grep -ohE "\b$x-(M[0-9]{2}|[0-9]{3})[a-z]?\b" $f-*.md | sort -u
done
```
(The revision-1 pattern `M?[0-9]{1,4}` also matched the section reference `SHELL-3.x` at 03:317 as a spurious
`SHELL-3`; the pattern above does not.) Only the spec's **own** prefix counts as its feature IDs (a spec citing
another spec's ID does not create a new ID). Addendum IDs are included (DATA-160…186, 200…224, 300…326;
SHELL-170…207, 500…699; CONT-150…169; BUILD-136…150; VIEW-208…216; VESSEL-300…334; SIRE-049…051;
HIER-M01…M07; suffixed IDs DATA-035a, REPO-003a, VESSEL-046a). SHELL-530…695 are the §6.5.1 registry rows.
**SHELL-699 and CONT-169** occur only as reserved-range bounds (no behaviour) — their owners simply confirm nothing
is required. Test-vector ids (`T-KB-…`, `XD-…`, `TV-…`, `T-ORD-…`), conflict rulings (`OC-…`), questions and defect
ids are not feature IDs: a vector is implemented by the owner of the feature it verifies ("Vector homes" below);
a ruling binds whoever owns the affected feature. The algorithm ids `BUILD-A1…A28`/`BUILD-C1…C3` (not matched by
the pattern) have their own table below.

Reading the tables: a range `X-a–b` means every ID of that spec's ID set from a to b; the first row of each spec is
the main owner; the other rows are the exceptions (e.g. "HIER-001…150 → W-HIER except HIER-091, 093…096 →
W-BUILD; HIER-092 → W-PDF; HIER-120, 123, 130…132 → F3; HIER-136, HIER-M06 → W-FILES").

### DATA- (01-data-model-persistence.md) — 173 IDs

ID set (grep): `001–005, 010–013, 020–036, 040–058, 060–068, 070–073, 080–084, 090–094, 100–104, 110–115, 120–121, 130–140, 150–153, 160–166, 170–186, 200–224, 300–326, 035a`

| Owner | IDs | n |
|---|---|---|
| F1 | DATA-011, DATA-013, DATA-022–025, DATA-029–031, DATA-071–072, DATA-082–084, DATA-090–094, DATA-130–135, DATA-139–140, DATA-150–152, DATA-182, DATA-200–213, DATA-215–222, DATA-224 | 54 |
| W-PERSIST | DATA-041, DATA-044–047, DATA-049, DATA-052–058, DATA-060–068, DATA-160–166, DATA-170–181, DATA-183–185 | 44 |
| W-GOLD | DATA-300–326 | 27 |
| F3 | DATA-001–005, DATA-010, DATA-020–021, DATA-026–028, DATA-035–036, DATA-081, DATA-104, DATA-186, DATA-214, DATA-223, DATA-035a | 19 |
| F2 | DATA-101–103, DATA-110–112, DATA-114–115, DATA-120–121, DATA-136–138 | 13 |
| W-SHELL | DATA-012, DATA-032–034, DATA-040, DATA-042–043, DATA-048, DATA-050–051, DATA-070, DATA-080 | 12 |
| W-QUICK | DATA-100, DATA-113 | 2 |
| W-DRIVE | DATA-073, DATA-153 | 2 |

### REPO- (02-repository-domain-services.md) — 95 IDs

ID set (grep): `001–015, 020–031, 035–036, 040–044, 050–054, 060–064, 070–081, 090–092, 100–107, 110–114, 120, 130–136, 140–147, 150–155, 003a`

| Owner | IDs | n |
|---|---|---|
| F2 | REPO-010–015, REPO-020–022, REPO-029, REPO-035–036, REPO-041–042, REPO-050, REPO-052, REPO-060–063, REPO-070–074, REPO-076–077, REPO-079–081, REPO-090–091, REPO-101–105, REPO-107, REPO-110–111, REPO-120, REPO-130–133, REPO-135–136, REPO-140–146, REPO-150–154 | 59 |
| F1 | REPO-001–008, REPO-040, REPO-054, REPO-064, REPO-003a | 12 |
| W-HIER | REPO-023–026, REPO-028, REPO-043, REPO-051, REPO-053, REPO-075, REPO-106 | 10 |
| W-QUICK | REPO-044, REPO-078, REPO-092, REPO-100, REPO-114 | 5 |
| W-BUILD | REPO-027, REPO-134, REPO-147 | 3 |
| W-SHELL | REPO-112–113 | 2 |
| F3 | REPO-009 | 1 |
| W-PLAN | REPO-031 | 1 |
| W-CREW | REPO-155 | 1 |
| W-SIRE | REPO-030 | 1 |

### SHELL- (03-main-shell-theme.md) — 315 IDs

ID set (grep): `001–014, 020–033, 040–048, 050–056, 060–082, 090–102, 110–112, 115, 120–126, 130–133, 140–144, 150–162, 170–177, 180–207, 500–526, 530–534, 540–570, 575–593, 600–623, 630–640, 645–658, 660, 662–663, 665–695, 699`

| Owner | IDs | n |
|---|---|---|
| F3 | SHELL-001–009, SHELL-012–014, SHELL-020–033, SHELL-040–048, SHELL-050, SHELL-052–056, SHELL-060, SHELL-064, SHELL-081–082, SHELL-090–100, SHELL-110–112, SHELL-120, SHELL-140–144, SHELL-150–156, SHELL-158–162, SHELL-175, SHELL-192–194, SHELL-197–201, SHELL-500–522, SHELL-524–526, SHELL-530–534, SHELL-540–570, SHELL-575–593, SHELL-600–623, SHELL-630–640, SHELL-645–658, SHELL-660, SHELL-662–663, SHELL-665–667, SHELL-670, SHELL-674, SHELL-677, SHELL-683–684, SHELL-686–687, SHELL-690–695, SHELL-699 | 236 |
| W-SHELL | SHELL-061–063, SHELL-065–072, SHELL-101–102, SHELL-115, SHELL-130–133, SHELL-170–174, SHELL-176–177, SHELL-180–191, SHELL-195–196, SHELL-202–207, SHELL-523 | 46 |
| W-DRIVE | SHELL-010–011, SHELL-073–080, SHELL-121–122 | 12 |
| W-CONT | SHELL-678, SHELL-680–682, SHELL-685, SHELL-689 | 6 |
| W-PERSIST | SHELL-123–126 | 4 |
| W-FILES | SHELL-669, SHELL-671, SHELL-679 | 3 |
| W-QUICK | SHELL-672–673, SHELL-675 | 3 |
| F1 | SHELL-051 | 1 |
| W-BUILD | SHELL-668 | 1 |
| W-VESSEL | SHELL-157 | 1 |
| W-SIRE | SHELL-688 | 1 |
| W-FLASH | SHELL-676 | 1 |

### HIER- (04-hierarchy-pages.md) — 99 IDs

ID set (grep): `001–006, 010–027, 030–034, 040–044, 050–058, 060–064, 070–073, 080–087, 090–096, 100, 110–117, 120–125, 130–136, 140–141, 150, M01, M02, M03, M04, M05, M06, M07`

| Owner | IDs | n |
|---|---|---|
| W-HIER | HIER-001–006, HIER-010–027, HIER-030–034, HIER-040–044, HIER-050–058, HIER-060–064, HIER-070–073, HIER-080–087, HIER-090, HIER-100, HIER-110–117, HIER-121–122, HIER-124–125, HIER-133–135, HIER-140–141, HIER-150, HIER-M01, HIER-M02, HIER-M03, HIER-M04, HIER-M05, HIER-M07 | 86 |
| F3 | HIER-120, HIER-123, HIER-130–132 | 5 |
| W-BUILD | HIER-091, HIER-093–096 | 5 |
| W-FILES | HIER-136, HIER-M06 | 2 |
| W-PDF | HIER-092 | 1 |

### CONT- (05-container-richtext-filebank.md) — 88 IDs

ID set (grep): `001–011, 020–050, 060–066, 080–098, 150–169`

| Owner | IDs | n |
|---|---|---|
| W-CONT | CONT-001–011, CONT-020–034, CONT-036–041, CONT-043–048, CONT-060–064, CONT-066 | 44 |
| W-RICH | CONT-035, CONT-042, CONT-065, CONT-150–169 | 23 |
| W-FILES | CONT-080, CONT-082–093, CONT-095–098 | 17 |
| F1 | CONT-094 | 1 |
| W-PERSIST | CONT-081 | 1 |
| W-PLAN | CONT-050 | 1 |
| W-PDF | CONT-049 | 1 |

### BUILD- (06-builders-savedlists.md) — 122 IDs

ID set (grep): `001–025, 030–046, 050–057, 060–064, 070–096, 100–102, 110–125, 130–150`

| Owner | IDs | n |
|---|---|---|
| W-BUILD | BUILD-001–025, BUILD-030–046, BUILD-050–057, BUILD-060–064, BUILD-070–090, BUILD-132–135 | 80 |
| F3 | BUILD-130–131, BUILD-136–150 | 17 |
| W-CREW | BUILD-110–125 | 16 |
| W-PDF | BUILD-091–096 | 6 |
| W-CONT | BUILD-100 | 1 |
| W-PLAN | BUILD-101 | 1 |
| W-QUICK | BUILD-102 | 1 |

### VIEW- (07-calendar-board-planner-buckets-map.md) — 115 IDs

ID set (grep): `001–022, 040–056, 080–109, 140–155, 170–182, 200–216`

| Owner | IDs | n |
|---|---|---|
| W-PLAN | VIEW-001–022, VIEW-040–056, VIEW-080–109, VIEW-140–152, VIEW-155, VIEW-170–182, VIEW-202, VIEW-207, VIEW-214 | 99 |
| F3 | VIEW-203–205, VIEW-208–212, VIEW-215–216 | 10 |
| W-HIER | VIEW-200–201 | 2 |
| W-QUICK | VIEW-153, VIEW-213 | 2 |
| F1 | VIEW-154 | 1 |
| W-BUILD | VIEW-206 | 1 |

### QUICK- (08-quick-floating-windows.md) — 103 IDs

ID set (grep): `001–020, 022–025, 040–055, 060–062, 064, 070–084, 100–107, 120–125, 150–156, 170–178, 190–196, 210–214, 230–231`

| Owner | IDs | n |
|---|---|---|
| W-QUICK | QUICK-001–020, QUICK-022–025, QUICK-040–055, QUICK-060–062, QUICK-064, QUICK-070–084, QUICK-100–107, QUICK-120–125, QUICK-150–156, QUICK-170–178, QUICK-191–193, QUICK-213–214, QUICK-231 | 95 |
| F3 | QUICK-190, QUICK-210–212, QUICK-230 | 5 |
| F2 | QUICK-194–196 | 3 |

### CREW- (09-crew.md) — 65 IDs

ID set (grep): `001–006, 010–018, 020–026, 030–040, 050–053, 060–062, 070–076, 080–086, 090–093, 100–106`

| Owner | IDs | n |
|---|---|---|
| W-CREW | CREW-001–006, CREW-010–018, CREW-020–026, CREW-030–040, CREW-050–051, CREW-053, CREW-060–062, CREW-070–076, CREW-080–086, CREW-100–106 | 60 |
| F1 | CREW-052, CREW-093 | 2 |
| W-SHELL | CREW-092 | 1 |
| W-PLAN | CREW-091 | 1 |
| W-QUICK | CREW-090 | 1 |

### VESSEL- (10-vessel-ports-jobs-cards.md) — 128 IDs

ID set (grep): `001–007, 010–028, 040–055, 100–123, 200–212, 250–256, 280–285, 300–334, 046a`

| Owner | IDs | n |
|---|---|---|
| W-VESSEL | VESSEL-001–007, VESSEL-010–028, VESSEL-040–055, VESSEL-100–123, VESSEL-200–212, VESSEL-250–256, VESSEL-281–282, VESSEL-285, VESSEL-046a | 90 |
| F2 | VESSEL-280, VESSEL-283, VESSEL-300–334 | 37 |
| W-FLASH | VESSEL-284 | 1 |

### PDF- (11-pdf-checklist-export.md) — 74 IDs

ID set (grep): `001–007, 010–012, 020–027, 030–045, 050–055, 060–077, 080–084, 090–094, 100–105`

| Owner | IDs | n |
|---|---|---|
| W-PDF | PDF-001–007, PDF-010–012, PDF-020–027, PDF-030–045, PDF-050–055, PDF-060–077, PDF-080–084, PDF-090–094, PDF-100–105 | 74 |

### SIRE- (12-sire.md) — 51 IDs

ID set (grep): `001–051`

| Owner | IDs | n |
|---|---|---|
| W-SIRE | SIRE-001–051 | 51 |

### FLASH- (13-flash-sync.md) — 84 IDs

ID set (grep): `001–006, 010–024, 030–048, 060–071, 080–095, 100–107, 120–121, 130–135`

| Owner | IDs | n |
|---|---|---|
| W-FLASH | FLASH-003–006, FLASH-010–024, FLASH-030–048, FLASH-060, FLASH-063–071, FLASH-080–095, FLASH-100–107, FLASH-120–121, FLASH-130–135 | 80 |
| F1 | FLASH-061–062 | 2 |
| F3 | FLASH-001–002 | 2 |

### TOOLS- (14-drive-tools.md) — 71 IDs

ID set (grep): `001–035, 040–052, 060–071, 080–090`

| Owner | IDs | n |
|---|---|---|
| W-DRIVE | TOOLS-001–035, TOOLS-040–052, TOOLS-060–071, TOOLS-080–090 | 71 |

### Totals per owner

| Owner | IDs |
|---|---|
| F1 | 73 |
| F2 | 112 |
| F3 | 295 |
| W-SHELL | 61 |
| W-PERSIST | 49 |
| W-GOLD | 27 |
| W-RICH | 23 |
| W-CONT | 51 |
| W-FILES | 22 |
| W-HIER | 98 |
| W-BUILD | 90 |
| W-PLAN | 103 |
| W-QUICK | 109 |
| W-CREW | 77 |
| W-VESSEL | 91 |
| W-PDF | 82 |
| W-SIRE | 53 |
| W-FLASH | 82 |
| W-DRIVE | 85 |
| **all** | **1583** |

### BUILD- algorithm ids (06 §3, 06 Addendum) — one owner each

| Owner | Ids |
|---|---|
| W-BUILD | BUILD-A1–A6, A10, A11 |
| F2 | BUILD-A7–A9, A12–A14, A19, A20 |
| W-CREW | BUILD-A15, A16 |
| W-PDF | BUILD-A17, A21, C1–C3 |
| W-CONT | BUILD-A18 |
| F3 | BUILD-A22–A24, A28 |
| W-SHELL | BUILD-A25, A27 (the B2 status half of A27 is implemented by W-SIRE together with B2) |
| W-SIRE | BUILD-A26 |

### Caller registries (the component owner owns only the component; each caller row belongs to the call site's owner)

* **BUILD-144 / BUILD-145 (prompt callers, 06 Addendum §Add.2.1):** F3 owns the shared prompt (BUILD-136…143,
  A22–A24, A28). Each of the 35 caller rows is implemented by the owner of the calling view: hierarchy pages →
  W-HIER; builders, saved lists, subtask builder → W-BUILD; crew schedule builder → W-CREW; Board/Buckets/Planner
  → W-PLAN; quick work → W-QUICK; container editor → W-CONT; SIRE → W-SIRE; File/Tools menu callers → W-SHELL.
  The five blank-meaningful paths: **B1** App identity → W-SHELL; **B2** Gemini key → W-SIRE; **B3/B4** bucket
  prompts → W-PLAN (Buckets tab) and W-QUICK (quick-work bucket assignment) by call site; **B5** insert table →
  W-CONT.
* **VIEW-212 (26 item-picker call sites; F3 owns VIEW-208…211, 215, 216 components):** row 1 → W-DRIVE; rows 2–3
  → W-QUICK; rows 4–6 → W-BUILD; rows 7–12 → W-HIER; rows 13–14 → W-BUILD (procedure checklist area, OC-48);
  row 15 → W-PLAN; rows 16–17 → W-CREW; rows 18–22 → W-BUILD; rows 23–25 → W-SIRE; row 26 → W-FILES. **VIEW-215**
  (replace-and-normalise + Save/MarkDirty) is done by the caller of rows 2, 11–14 and 26.
* **REPO-091 (F2) and QUICK-156 (W-QUICK) log call-site catalogues:** F2 owns the log API and the Kind strings it
  emits itself; every catalogued call site is implemented by the owner of that call site (W-HIER, W-BUILD,
  W-PLAN, W-QUICK, W-CREW, W-VESSEL, W-SIRE, W-SHELL). QUICK-156's window side (what the Activity log shows) stays
  W-QUICK.
* **VIEW-205 (navigate from Calendar procedure rows and Buckets members):** F3 owns the `Navigator` contract; the
  call sites are W-PLAN's. **VIEW-207** (reload re-inits all five pages) is W-PLAN's for all five pages.
* **DATA-104 / QUICK-190 / TOOLS-027 (Confirm-import fallback):** the gate and its fallback alert are F3's
  (`reviewAndConfirmImport(incoming: nil, …)`); TOOLS-027 stays W-DRIVE (the Drive flow that calls the gate);
  DATA-100 and QUICK-191…193 (the sheet) are W-QUICK's.

### Vector homes (spec §7 vectors whose owner is not obvious — the feature owner owns the vector)

| Vector | Owner | Note |
|---|---|---|
| 01 §7.1–7.5, §7.10, §7.12; 01 §4.4 literal, B07/B08; MP.7.6 | F1 | |
| 01 §7.6, §7.7, §7.13; MP.7.5, MP.7.7 | W-PERSIST | |
| 01 §7.8, §7.9, §7.11 | F2 | §7.11 "clone Deadline … Local" is superseded by DECISIONS Q-6 (ARCH §3.4) |
| 04 §7.1 TagParser, §7.7 sidebar, §7.9, §7.11–§7.13 | W-HIER | |
| 04 §7.2 WorkRange, §7.4–§7.6 batch deadline/done/delete | F2 | |
| 04 §7.3 WhenText, §7.8 locks | F1 | |
| 04 §7.10 checklist XLSX | W-PDF | |
| 06 §7.1 WorkRange, §7.4 SavedListOrder, §7.10 capture/apply, §7.11 schedule service | F2 | |
| 06 §7.2 NormTime, §7.9 timeline | W-CREW | |
| 06 §7.3, §7.5–§7.8 | W-BUILD | |
| 06 §7.12 insert-into-note lines | W-CONT | (BUILD-100, A18) |
| 06 §7.13 XLSX helpers (ColRef, sheet names), §7.14 JSON round trip | F1 | |
| 09 §7.1 ParseDate | F2 | |
| 09 §7.2–§7.15 | W-CREW | §7.8 ContractStatus rows are F1-model code, asserted in W-CREW's suite |
| 10 X.8.1 Kind/A/B/B+/C, X.8.2–X.8.8 | F2 | |
| 10 X.8.1 C·D/C·T, X.8.9, §7.* | W-VESSEL | |
| 11 §7.14 ColRef/escape/sheet-name rows | F1 | package rows (6 entries, PDF-090, `<cols>` widths) → W-PDF |
| 13 CS-19 deep-equals / §3.11.10 accessor vectors | F1 | the change-set vectors §7.8 → W-FLASH |
| 13 §7.2 CRC-32, §7.6 DEFLATE | F1 | |
| 14 §7.7 smart import | W-DRIVE | post-merge (needs W-PERSIST) |

### Why the non-obvious splits (so verifiers look in the right place)

* **Menus vs behaviour (03 §6.5.1):** registry rows SHELL-530…663 (key, title, placement, enablement, routing) are
  F3's; the behaviour behind a row is owned by the spec feature it calls (e.g. SHELL-601 Bold row = F3,
  CONT-023 Bold = W-CONT; SHELL-569 row = F3, PDF-001…007 = W-PDF; SHELL-547 row = F3, SHELL-061/DATA-032 Save a
  Copy As = W-SHELL). In-window key rows SHELL-665…695 belong to the owner of the window/view they act in (F3
  for generic/native rows).
* **Save pipeline in F1:** DATA-025, DATA-031, REPO-001…008, REPO-003a and SHELL-051 are implemented in F1's
  `AppStore.swift`/`PersistenceWriter.swift` (ARCH §2.3, §5.2). REPO-009 (app-level cadence) and the callers of
  REPO-005 (`suspendSaving` on load failure) are F3's.
* **Plumbing vs features in the shell:** F3 owns what every wave consumes (scenes, launch, registry/router/menus,
  AppEnvironment, dialogs, navigation, design system, snapshot hook, import gate, quit pipeline, autosave cadence).
  W-SHELL owns the File/Tools menu flows (SHELL-061…072 except 064, 101, 102; DATA-012, 032…034, 040, 042, 043,
  048, 050, 051, 070, 080), About, Settings, Keyboard Shortcuts window, reminders/notifications/Dock/MenuBarExtra
  (SHELL-130…133, REPO-112/113, CREW-092) and packaging/build/smoke/docs (SHELL-170…174, 176, 177, 180…191, 195,
  196, 202…207).
* **Service vs UI:** 02's service semantics are F2's; REPO rows that describe a specific window or panel are owned
  by that window's owner (REPO-078/092/100 → W-QUICK; REPO-023…028/075/106 → W-HIER; REPO-134/147 → W-BUILD).
  Same rule for 01 (DATA-100/113 → W-QUICK) and 08 (QUICK-194…196 algorithms → F2).
* **Model rules live in F1:** Status/IsComplete sync and load rule (DATA-130, REPO-040), range helpers
  (DATA-131, REPO-054), BucketId migration (DATA-132, VIEW-154), v0→v1 migration (DATA-023, REPO-064), crew
  persistence and contract status (CREW-093, CREW-052, DATA-135), `FileItem.sourceLabel` (CONT-094), CRC-32/DEFLATE
  (FLASH-061/062). The ParseDate algorithm those models forward to is F2's `NetDateParser`.
* **Shared parsers in F2:** the XLSX reader contract (VESSEL-300…334), `NetDateParser` (09 §6.3) and `CrewText`
  (09 §3.2) are F2's so that every wave worktree has the real code.
* **Attachments:** `ClassifyFile` (CONT-081) is `AttachmentStore.classify` → W-PERSIST.
* **Ownership rulings of 01 OWN applied:** prompt/picker/date prompt → F3 (C1–C3); list-style prompt → W-PDF
  (OC-46, CONT-049); saved-list→tasks picker → W-PLAN (OC-47, CONT-050, BUILD-101); procedure checklist area →
  W-BUILD (OC-48, HIER-091/093…096); checklist-only exports and saved-lists PDF → W-PDF (OC-44/45, HIER-092,
  BUILD-091…096); shared save semantics → W-PERSIST with indicator in F3 and menu flows in W-SHELL (OC-50,
  SHELL-123…126 vs SHELL-023 / SHELL-066/067). Where 01 OWN (DATA-214, OC-27, OC-28) and 03 §6.5.1 disagree on
  keys, **03 §6.5.1 wins** (DECISIONS: it is the single registry).
* **Load balancing (deliberate, contract-level):** the crew schedule builder (06 §I, BUILD-110…125, CREW-080…086,
  REPO-155) is implemented by W-CREW together with its only host, the crew editor; its semantics remain those of
  06 §I (and 02 §2.O for the F2 service). Spec 07 is one agent (W-PLAN), spec 08 one agent (W-QUICK) except the
  F2 algorithms and F3 components.
* **Open item for the lead:** DATA-181's "File ▸ Recover ▸ Conflict Copies…" has no 03 §6.5.1 registry row; the
  list is reachable from W-PERSIST's own surfaces until the lead adds a row (ARCH §6.6).

---------------------------------------------------------------------------------------------------------------------

## 5. Wave coordination notes

* **Nothing shared is live; nobody waits.** Worktrees are independent. Heavily consumed wave contracts should land
  early behind unchanged signatures anyway (W-RICH reader/writer for W-CONT, W-FILES, W-SIRE, W-PDF; W-PERSIST
  AttachmentStore/Opener/applySyncedData for W-FILES, W-VESSEL, W-FLASH, W-CONT; W-CONT `ContainerEditorView` for
  W-HIER, W-BUILD; W-BUILD editor sheets for W-HIER, W-PLAN, W-QUICK, W-CREW; W-HIER `BatchContextMenuItems`),
  because the merge order is free and Stage V runs the post-merge acceptance of everyone.
* **Cross-owner tests are gated**, never faked: `@Test(.enabled(if: ContractStatus.isImplemented(.<owner>)))`
  (ARCH §10.5); they are skipped in the worktree and run in Stage V. W-CONT never persists against the
  placeholder reader (ARCH §6.7, §11).
* **Cross-agent UI checks** (post-merge, Stage V): item detail with notes/files/backlinks
  (W-HIER+W-CONT+W-FILES), procedure checklist (W-HIER+W-BUILD+W-PDF), vessel tabs (W-HIER+W-VESSEL), crew editor
  tabs (W-CREW+W-BUILD), Planner "+ Saved list" (W-PLAN), imports through the review sheet
  (F3+W-QUICK+W-SHELL/W-PERSIST/W-DRIVE), data-file conflict sheet (F3+W-PERSIST+W-QUICK), Flash Sync apply →
  reload (W-FLASH+F3+W-PERSIST), SIRE quick-add → hierarchy (W-SIRE+W-HIER), reminders + work-order notifications
  (W-SHELL+W-VESSEL).
* **Symbol hygiene:** every agent follows ARCH §12.2 (area prefixes, prefixed extension members, `aa.<area>.*`
  preference keys) and runs `Scripts/check-ownership.sh`; the orchestrator runs the gate on the merged tree after
  every merge.
* **Shared fixtures:** each owner builds its own synthetic data folders under `Fixtures/ui/<owner>/`; a UI owner
  may copy (not reference) another owner's fixture file into its own folder.
* **Deviations and requests:** P2 fixes and sanctioned deviations go to `Docs/Deviations/<owner>.md`; missing or
  wrong contracts and spec defects go to `Docs/Requests/<owner>.md` (ARCH §12.3).
