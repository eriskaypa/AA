# AA for macOS — port progress

Running record of the Swift port (the root `PROGRESS.md` documents the Windows app and is read-only during the port).
Counts are feature IDs from `Docs/OWNERSHIP.md` §4 (1,583 total).

| Stage | Owner(s) | Status | Notes |
|---|---|---|---|
| Specs | 14 spec agents + critic + 10 gap-fills | done | `Docs/Spec/01…14` (~34.6k lines) |
| Architecture | architect + 3 critics + revision | done | `Docs/ARCHITECTURE.md`, `Docs/OWNERSHIP.md` |
| F1 core data layer | F1 | done (merged) | Foundation, JSON, all models, persistence, crypto, save pipeline, ZIP, XLSX writer; 202 tests / 35 suites green; deviations in `Docs/Deviations/F1.md` |
| F1 placeholders | F1-stubs | done | 69 placeholder files for 16 owners (F2 29: Store 7, Services 15, XlsxRead 7; W-PERSIST 11; W-RICH 10; §6.8 contracts 6; ContractStatus flags 15 — W-PERSIST's and W-RICH's counted above); 306 `PLACEHOLDER(...)` markers, 0 for F1; `Scripts/check-placeholders.sh`, `Scripts/check-ownership.sh` (paths, non-Swift files, basenames, cross-owner symbols); wired `DataStore.normalizeFilePaths` → `AttachmentStore`, `CrewMember.parseDate` → `NetDateParser`, `ContractStatus.isImplemented` → per-owner flags; 209 tests / 38 suites green |
| F1 verification | F1 (verifier) | done | clean-build gate green (229 tests / 42 suites); every in-worktree acceptance item of the F1 card mapped to a passing test; compile-time conformance tests for every public signature of ARCH §3–§6.8 (`Foundation/FoundationContractSignatureTests.swift`, `FoundationPlaceholderSignatureTests.swift`) — 0 mismatches; hand-written Windows-style data.json (`Fixtures/model/WIN.*`) round-trips byte-identically |
| F2 domain services | F2 | done (merged) | AppStore domain operations (lookups, relations + widened purge, creation catalogue, log, Trash/undo incl. `trashSubtask` and `trashAllCrew`, recurrence with calendar-date outputs, groups), 15 services (search + XAML text, switcher, reminders, batch done/deadline/delete, saved-list order, templates, `.aasched`, DataDiff + "Other data", AgeVerdict, WorkRange, `NetDateParser`, `CrewText`), XLSX reader (OPC package, strict XML scanner, styles, strings, sheets incl. comments/tables/1904, serials, renderers A/B/B+/C); 0 `PLACEHOLDER(F2)` markers; 114 new tests (343 total / 57 suites) green; POC workbooks copied to `Tests/AACoreTests/Fixtures/xlsx/`; deviations in `Docs/Deviations/F2.md`, requests in `Docs/Requests/F2.md` |
| F3 app shell | F3 | done (merged) | AACore Launch/Commands (args, AppFolder + pre-flight, crash log, registry of every §6.5.1 row, menu tree, pure router table, picker model); AA App/Shell/Commands/Design/Shared/Debug (launch phases, bootstrap scene + SceneOpener, all scenes, AppEnvironment, main window, menus via router + AppKit bridge, shared dialogs, quit pipeline, autosave, snapshot hook); placeholders for every AA-target contract (71 files, 14 wave owners); 285 tests green (56 F3 tests); 80 snapshots (every section and scene, both appearances, F3 sheets); deviations `Docs/Deviations/F3.md`, requests `Docs/Requests/F3.md` |
| Foundation integration | INTEGRATOR | done | `stage/F2` and `stage/F3` merged into `mac-port` (`--no-ff`); one conflict (`Docs/PROGRESS.md`, both rows kept), no code fix needed. Feature IDs owned (OWNERSHIP §4): F1 73, F2 112, F3 295 = 480 of 1,583. Swift: 291 files / 29,923 lines — Sources 250 files / 21,590 lines (AACore 144 / 14,624; AA 106 / 6,966), Tests 41 files / 8,333 lines. Gate from a clean `.build`: warnings-as-errors build clean, 399 tests / 68 suites pass, `check-ownership.sh` OK, `check-placeholders.sh` F1/F2/F3 empty; 364 `PLACEHOLDER(...)` markers left in 112 files for 15 wave owners (W-SHELL 28, W-PERSIST 77, W-RICH 43, W-CONT 6, W-FILES 16, W-HIER 23, W-BUILD 23, W-PLAN 18, W-QUICK 26, W-CREW 15, W-VESSEL 23, W-PDF 9, W-SIRE 16, W-FLASH 8, W-DRIVE 33). Rule zero: no change outside `mac/` against `main`; original-source checksums pass. Debug snapshot hook renders the main window (TabEquipment) in light and dark. |
| Wave (16 vertical slices) | W-* | done (merged) | 16 wave branches built, audited in their worktrees and merged into `mac-port` (`--no-ff`, OWNERSHIP order W-RICH … W-DRIVE; W-RICH's post-audit commit merged last); per-owner counts below; every `<Area>ContractStatus` flag `true` |
| Wave integration | INTEGRATOR | done | No file conflicts (merge commits ae7b9cd…47c7463, then W-RICH's post-audit commit); warnings-as-errors build of the merged tree green; one integration fix (W-GOLD's `GoldMacOutTests`, see log). Clean-build gate: build clean, **1,582 tests / 234 suites pass** (cross-owner `ContractStatus`-gated tests now run for real; only environment-gated suites skip: Windows goldens/captures absent, dump switches), `check-ownership.sh` OK, `check-placeholders.sh` prints nothing (0 `PLACEHOLDER(` markers in `Sources`, `Tests`, `Tools`). Rule zero: no change outside `mac/` against `main`; original-source checksums pass. Swift: 595 files — Sources 433 files / 79,706 lines (AACore 276 / 45,849; AA 157 / 33,857), Tests 161 files / 33,954 lines, Tools 1. Snapshots: every section (13) and scene (16 + item ×2) in light and dark from one merged fixture folder (64 PNGs). Deviations consolidated into `Docs/DEVIATIONS.md` |
| Verification | V | pending | Stage V: manual / person-only checks and the open items below |

## Feature IDs by owner (OWNERSHIP.md §4; 1,583 IDs)

Done = implemented and verified in the owner's worktree audit (and, after the merge, by the gated tests); N/A = not
applicable by a DECISIONS / Deviations ruling. Source: the owner's progress record (`Docs/Progress/<id>.md`; W-PLAN's and
W-GOLD's moved there from `Docs/Deviations/<id>.md`, W-FLASH's was recreated from its report — post-wave resolutions).

| Owner | Done / total | Partial | Not done | N/A | Open items |
|---|---|---|---|---|---|
| F1 | 73 / 73 | 0 | 0 | 0 | — |
| F2 | 112 / 112 | 0 | 0 | 0 | — (REQ-F2-01 rejected, REQ-F2-02 applied) |
| F3 | 295 / 295 | 0 | 0 | 0 | no XCUITest menu walk (REQ-F3-01…04 applied; snapshot-hook split-view artefacts fixed, ee1411b) |
| W-SHELL | 58 / 61 | 1 (SHELL-204 — person-only launch checklist steps) | 2 (SHELL-206 cross-version data smoke: needs a Windows-written data folder; SHELL-207 clean-machine / Intel runs: needs another Mac, Rosetta absent) | 0 | REQ-W-SHELL-01, 02, 04 |
| W-PERSIST | 41 / 49 | 1 (DATA-174 — menu commands greyed with help, subtitle, ⌘S sheet and settings suffix done (406368f); in-window Trash / lock / file-bank add controls rely on the write-gate refusal instead of greying) | 0 | 7 (DATA-160…166, replaced by the Mac instance model DATA-170…182) | REQ-W-PERSIST-01…04; lease mode not exercised on a real SMB server |
| W-GOLD | 23 / 27 | 2 (DATA-319, DATA-320 — E09/E11/E13/E15b/X04/X05/X06 reproducers deferred: entry points public, Windows goldens absent; REQ-W-GOLD-04 applied) | 2 (DATA-322, DATA-323 — need a person on Windows) | 0 | Windows goldens not generated (no .NET 10 SDK on this Mac): 12 WinFixtures suites skip; `Scripts/fixtures.sh emit-mac-out` to be re-run now W-PERSIST / W-RICH have flipped (adds `mac-out/bundles/`, `mac-out/xaml/`) |
| W-RICH | 22 / 23 | 0 | 0 | 1 (CONT-169, reserved range bound) | 05 §7.7 item 10 (Mac output loads in WPF) needs the W-GOLD Windows harness; release-build 1 MB parse budget to re-confirm on an idle machine |
| W-CONT | 51 / 51 | 0 | 0 | 0 | T-KB-07/15/21/28/30/31/48/52 manual checks |
| W-FILES | 22 / 22 | 0 | 0 | 0 | Quick Look panel with the app frontmost (manual) |
| W-HIER | 98 / 98 | 0 | 0 | 0 | — |
| W-BUILD | 90 / 90 | 0 | 0 | 0 | — |
| W-PLAN | 103 / 103 | 0 | 0 | 0 | — |
| W-QUICK | 109 / 109 | 0 | 0 | 0 | live key handling (Trash ⌘⌫, switcher ↑↓↩⎋, Search ↩) checked by snapshot / manual run only |
| W-CREW | 77 / 77 | 0 | 0 | 0 | — |
| W-VESSEL | 91 / 91 | 0 | 0 | 0 | Quick Look of file cards and work-order notifications: manual checks |
| W-PDF | 82 / 82 | 0 | 0 | 0 | — |
| W-SIRE | 53 / 53 | 0 | 0 | 0 | — |
| W-FLASH | 81 / 82 | 0 | 0 | 1 (FLASH-133, screen-capture receive: DECISIONS 13 "no for v1") | camera receive with a real iPhone (manual) |
| W-DRIVE | 85 / 85 | 0 | 0 | 0 | live Google sign-in (manual) |
| **all** | **1,566 / 1,583** | **4** | **4** | **9** | 49 contract requests resolved post-wave: 45 applied, 1 rejected, 3 deferred (`Docs/Requests/` "Resolution:" lines) |

## Log
- 2026-09-29/30 — specs, decisions, architecture committed on `mac-port`.
- 2026-09-30 — F1 started; foundation workflow aborted by API 500 errors after F1's first two commits.
- 2026-10-02 — foundation workflow restarted (resume-aware, with retries).
- 2026-10-02 — F1 core finished: uncommitted tests from the crashed attempt verified and fixed; crypto, persistence, settings (DATA-182), AppStore save pipeline, ZIP, XLSX writer, model-helper and fixture tests added; P2 fixes recorded (`Docs/Deviations/F1.md`).
- 2026-10-02 — F1 placeholders finished: compiling stubs for every F2 and wave-owned AACore contract (ARCH §5.3, §6.5–§6.8, §11), one `<Area>ContractStatus.swift` per wave owner (15), `Scripts/check-placeholders.sh` + `Scripts/check-ownership.sh`; gate (build, tests, check-ownership) green; `check-placeholders.sh F1` empty. `MigrateLegacyAbsolutePaths` deliberately not run on a plain load (Windows parity — bundle import / Flash Sync apply only, W-PERSIST). Open request: `Docs/Requests/F1.md` REQ-F1-01 (owner of `Docs/PROGRESS.md`).
- 2026-10-02 — F1 adversarial audit: gate re-run from a clean `.build`; acceptance list checked item by item (all
  covered); every public AACore signature compiled against ARCH §3–§6.8 (F1 code and all F2/wave placeholders: no
  mismatch); parser/date/number edge cases probed (no defect); new Windows-style fixture (every model type, three
  date kinds, unknown members on 20+ objects, legacy `BucketId`, Trash payload) proves parse → model → write is
  byte-identical in five time zones; element-level JSON null leniency recorded as A06e in `Docs/Deviations/F1.md`.
- 2026-10-02 — F2 finished on `stage/F2`: every ARCH §5.3 domain operation and §6.5 service real, XLSX reader per 10 Addendum X (X.8.1 Kind/A/B/B+/C matrix, X.8.2–X.8.8, POC used ranges; 2 524 × 16 sheet < 50 ms optimised), every 02 §7 vector (except T-LOG-4, the Activity-log CSV of W-QUICK), 01 §7.8/7.9/7.11, 04 §7.2/7.4–7.6, 06 §7.1/7.4/7.10/7.11, 08 §7.3/7.4/7.7, 09 §7.1; P2 fixes D-1/D-2/D-3/D-10/D-17, DECISIONS 02 Q-4, 07 Q-02, 08 OQ-7/OQ-8, 01 Q-3 applied. Post-merge: XlsxGolden comparison test is gated on `Fixtures/winfixtures/xlsx/` (W-GOLD).
- 2026-10-02 — F3 finished in its worktree (`stage/F3`): app plumbing, menu bar per 03 §6.5.1 (live menu dump matches §6.5.1.6), design system, shared dialogs, snapshot hook; `check-placeholders.sh F3` empty.
- 2026-10-02 — Foundation integrated on `mac-port`: merged `stage/F2` then `stage/F3`; gate green from a clean build after each merge (343 tests / 57 suites after F2; 399 tests / 68 suites after F3); rule-zero diff empty, checksums pass, no F1/F2/F3 placeholders left; main-window snapshots (light, dark) produced by the debug hook.
- 2026-10-03 — Stage W integrated on `mac-port`: the 16 wave branches merged (`--no-ff`) in OWNERSHIP order (ae7b9cd…47c7463), no file conflicts; W-RICH's post-audit commit (6d0349c: input-mutation fuzzing, root-attribute filtering, carried Foreground cascade) merged last. `check-ownership.sh` maps `Docs/Progress/<id>.md` to its owner (f556cb5). Clean-build gate: 1,582 tests / 234 suites; the one failure was an integration mismatch in W-GOLD's `GoldMacOutTests` — it exported its bundles into the data folder, which W-PERSIST's real `BundleService` refuses (DATA-041 / D-13), and passed `&report.skipped` while its write closure appended to `report` (a Swift exclusivity trap once W-RICH emits `xaml/`); fixed in the test (b8fe439). Placeholders: none left. Rule zero and checksums pass. 64 snapshots of every section and scene (light + dark) from one merged fixture folder; `Docs/DEVIATIONS.md` consolidated from `Docs/Deviations/*.md`.

- 2026-10-03 — Contract requests resolved by the lead on `mac-port` (15 `[LEAD-REQ]` commits, 95e9a99…99e4b14): 49 requests — 45 applied, 1 rejected (REQ-F2-01, pre-wave ruling kept), 3 deferred (REQ-W-GOLD-01…03: reproducers need the Windows goldens). Contract changes listed in DECISIONS "Contract amendments (post-wave)": viewer subtitle, checklist step reveal, DATA-174 write gate in the router (+ help text), ⌘S sheet, Read-Only subtitle, settings suffix, `InstanceGuardResult.sameUserNoApp`, shared-save adopt semantics, MenuBarExtra binding, Drive toolbar indicator, tool window sizes, shortcut strip below the sections, snapshot hook split-view redraw. Requester workarounds removed (⌘S key monitor, banner attach, Crew inset, menu-bar guard, shared-save duplicate reload/clear, W-HIER step discard). Gate green after each change (1,585 tests); snapshots of Equipment and Crew confirm the strip no longer overlaps lists.

## Known remaining problems (after Stage W integration, 2026-10-03)

Visual (from the integrated snapshots, scratchpad `snapshots/integrated/`):
- Resolved post-wave (916cfb9, ee1411b): lists running under the shortcut bar, and the layer-mode card artefacts of
  `HSplitView` sections. Re-check SIRE and Saved Lists in Stage V snapshots (only Equipment and Crew were re-rendered).
- Snapshot hook (F3): the SIRE tab is captured while "Loading SIRE 2.0 question bank…" unless
  `AA_SIRE_SELECT` is set (the hook's 1 s idle is shorter than the debug-build bank load). Hook limits, not app defects.
- Date pickers in the Quick work builder (Deadline `10/18/2026`) and the Date calculator (`10/ 3/2026`) follow the
  system locale while the rest of the app shows `yyyy-MM-dd` — check against ARCH §9.8 / specs 08, 14.
- Planner "Unscheduled Jobs" truncates titles to about 12 characters in its default column width ("Order replac…") —
  check against 07.

Other:
- Not done / partial IDs: SHELL-204 (partial), SHELL-206, SHELL-207, DATA-174 (partial — in-window controls),
  DATA-319 / DATA-320 (partial), DATA-322, DATA-323 — see the owner table above.
- Flaky under load: `EditorSessionTests.debouncePersists` (30 ms debounce, 250 ms wait) failed once in a full run and
  passed on every re-run; timing-based, not caused by the post-wave changes.
- Windows goldens (WinFixtures, WinCapture, XlsxGolden) not generated: no .NET 10 SDK here; 12 WinFixtures suites skip
  until `Scripts/fixtures.sh generate` / WinCapture run on Windows. `Fixtures/mac-out/` still lacks `bundles/` and `xaml/`.
- Person-only checks (Stage V): Finder / Gatekeeper launch, camera prompt and iPhone Flash Sync, Google sign-in, Quick
  Look with the app frontmost, notifications and MenuBarExtra, real SMB lease mode, T-KB keyboard rows, no XCUITest
  menu walk (03 §6.5.1.14).
- MetricKit next-launch crash dialog and signal-marker path tested only at string/format level.
- Snapshots render Liquid Glass/materials as flat fills and prominent buttons grey (window not key).

## Known remaining problems (after foundation) — superseded

- 02 T-LOG-4 (Activity-log CSV quoting) untested: the CSV writer is W-QUICK's `ActivityLogCSV` (QUICK-155).
- XLSX golden comparison (10 X.7.6) runs only once W-GOLD supplies `Tests/AACoreTests/Fixtures/winfixtures/xlsx/`.
- 2 524 × 16 sheet budget (< 200 ms) met only in optimised builds; the debug gate checks < 1.5 s (`Docs/Deviations/F2.md`).
- Splash → login → main not driven end to end in a live GUI run; `--smoke-test` (SHELL-205) is W-SHELL's and still a placeholder.
- T-KB rows that need wave views (sidebar confirmations, file-bank keys, Planner date maths, Trash-sheet keys, quick switcher) are post-merge; router side tested.
- No XCUITest menu walk (03 §6.5.1.14): no UI-test target; covered by ShellMenuTree tests + `--snapshot menu` dump.
- AA ▸ Settings… stays enabled during login; `NSWindow.identifier` not set to the scene id (SceneOpener registry instead) — both in `Docs/Deviations/F3.md`.
- MetricKit next-launch crash dialog and signal-marker path tested only at string/format level; no real crash exercised.
- Snapshots render Liquid Glass/materials as flat fills and prominent buttons grey (window not key) — rendering limits of the hook.
- Every section page and wave scene is a placeholder view until its wave owner lands (364 markers above).
