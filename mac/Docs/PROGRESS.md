# AA for macOS — port progress

Running record of the Swift port (the root `PROGRESS.md` documents the Windows app and is read-only during the port).
Counts are feature IDs from `Docs/OWNERSHIP.md` §4 (1,583 total).

| Stage | Owner(s) | Status | Notes |
|---|---|---|---|
| Specs | 14 spec agents + critic + 10 gap-fills | done | `Docs/Spec/01…14` (~34.6k lines) |
| Architecture | architect + 3 critics + revision | done | `Docs/ARCHITECTURE.md`, `Docs/OWNERSHIP.md` |
| F1 core data layer | F1 | done (core) | Foundation, JSON, all models, persistence, crypto, save pipeline, ZIP, XLSX writer; 202 tests / 35 suites green; deviations in `Docs/Deviations/F1.md` |
| F1 placeholders | F1-stubs | done | 69 placeholder files for 16 owners (F2 29: Store 7, Services 15, XlsxRead 7; W-PERSIST 11; W-RICH 10; §6.8 contracts 6; ContractStatus flags 15 — W-PERSIST's and W-RICH's counted above); 306 `PLACEHOLDER(...)` markers, 0 for F1; `Scripts/check-placeholders.sh`, `Scripts/check-ownership.sh` (paths, non-Swift files, basenames, cross-owner symbols); wired `DataStore.normalizeFilePaths` → `AttachmentStore`, `CrewMember.parseDate` → `NetDateParser`, `ContractStatus.isImplemented` → per-owner flags; 209 tests / 38 suites green |
| F1 verification | F1 (verifier) | done | clean-build gate green (229 tests / 42 suites); every in-worktree acceptance item of the F1 card mapped to a passing test; compile-time conformance tests for every public signature of ARCH §3–§6.8 (`Foundation/FoundationContractSignatureTests.swift`, `FoundationPlaceholderSignatureTests.swift`) — 0 mismatches; hand-written Windows-style data.json (`Fixtures/model/WIN.*`) round-trips byte-identically |
| F2 domain services | F2 | done | AppStore domain operations (lookups, relations + widened purge, creation catalogue, log, Trash/undo incl. `trashSubtask` and `trashAllCrew`, recurrence with calendar-date outputs, groups), 15 services (search + XAML text, switcher, reminders, batch done/deadline/delete, saved-list order, templates, `.aasched`, DataDiff + "Other data", AgeVerdict, WorkRange, `NetDateParser`, `CrewText`), XLSX reader (OPC package, strict XML scanner, styles, strings, sheets incl. comments/tables/1904, serials, renderers A/B/B+/C); 0 `PLACEHOLDER(F2)` markers; 114 new tests (343 total / 57 suites) green; POC workbooks copied to `Tests/AACoreTests/Fixtures/xlsx/`; deviations in `Docs/Deviations/F2.md`, requests in `Docs/Requests/F2.md` |
| F3 app shell | F3 | pending | |
| Wave (16 vertical slices) | W-* | pending | |
| Verification | V | pending | |

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
