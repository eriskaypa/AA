# AA for macOS — port progress

Running record of the Swift port (the root `PROGRESS.md` documents the Windows app and is read-only during the port).
Counts are feature IDs from `Docs/OWNERSHIP.md` §4 (1,583 total).

| Stage | Owner(s) | Status | Notes |
|---|---|---|---|
| Specs | 14 spec agents + critic + 10 gap-fills | done | `Docs/Spec/01…14` (~34.6k lines) |
| Architecture | architect + 3 critics + revision | done | `Docs/ARCHITECTURE.md`, `Docs/OWNERSHIP.md` |
| F1 core data layer | F1 | done (core) | Foundation, JSON, all models, persistence, crypto, save pipeline, ZIP, XLSX writer; 202 tests / 35 suites green; deviations in `Docs/Deviations/F1.md` |
| F1 placeholders | F1-stubs | pending | other owners' AACore placeholders, `<Area>ContractStatus.swift`, `Scripts/check-*.sh`; also wire `DataStore.normalizeFilePaths` → `AttachmentStore`, `CrewMember.parseDate` → `NetDateParser`, `ContractStatus.isImplemented` → per-owner flags |
| F2 domain services | F2 | pending | |
| F3 app shell | F3 | pending | |
| Wave (16 vertical slices) | W-* | pending | |
| Verification | V | pending | |

## Log
- 2026-09-29/30 — specs, decisions, architecture committed on `mac-port`.
- 2026-09-30 — F1 started; foundation workflow aborted by API 500 errors after F1's first two commits.
- 2026-10-02 — foundation workflow restarted (resume-aware, with retries).
- 2026-10-02 — F1 core finished: uncommitted tests from the crashed attempt verified and fixed; crypto, persistence, settings (DATA-182), AppStore save pipeline, ZIP, XLSX writer, model-helper and fixture tests added; P2 fixes recorded (`Docs/Deviations/F1.md`).
