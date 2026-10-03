# W-GOLD — contract change requests (ARCHITECTURE.md §12.3)

The golden reproducers call the Mac code that corresponds to each linked C# function. For the cases below that
code is private to another wave owner (ARCH §6.8) and does not exist in this worktree, so the Swift side cannot be
written yet. Each request asks the owner to name (or expose `internal`, reachable through `@testable import
AACore`) the entry point; no behaviour change is requested.

## REQ-W-GOLD-01: W-CREW date resolver, COMPAS converter and reader entry points
Target: W-CREW's AACore crew import code (09 §3–§7; ARCH §6.8).
Need, each callable from `AACoreTests` without UI:
* `DateResolver` equivalent: `init()`, `adopt(_ order:)`, `observe(_ raw:)`, `infer(fallback:)`, `order`,
  `decisiveCount`, `resolve(_ raw:role:) -> (value: CivilDate?, raw: String, dependedOnOrder: Bool, note: String?)`,
  `toStorage()`, `expandYear(_:role:alreadyFull:)`, `fromExcelSerial(_:use1904:)`, `isPlaceholder(_:)` (E09).
* `CrewConverter` equivalent: `init(sourceFile:importedAt:)` (the C# reads `DateTime.Now`; the reproducer needs to
  inject `2026-09-29 14:05`), `learnDateFormat(rows:fallback:)`, `convert(row) -> CrewMember`, `dateSummary()`,
  `unreadableDates`, `orderDependentDates`, `dateOrder`, `dateEvidence` (E11, E15b).
* `CompasReader.read(url) -> [CompasRow]` with `row.get(header)` (X06).
Why: E09, E11, E15b (must) and X06 (should) compare these against the Windows goldens.
Workaround in place: the four cases are registered as pending reproducers (`GoldServiceGoldenTests.swift`,
`GoldExtGoldenTests.swift`) — reported, failing only under `AA_REQUIRE_FIXTURES=1`.

Resolution: deferred — the entry points exist as public AACore API (`CrewDateResolver`, `CrewConverter(sourceFile:now:today:zone:use1904:)` with injectable `now`, `CrewCompasReader.read(url:)` + `CrewCompasRow.get`), and the pending registrations now name them (016be4f); the E09/E11/E15b/X06 reproducers are not written because the Windows goldens are absent on this Mac (no .NET SDK) and cannot be checked — Stage V with `Scripts/fixtures.sh generate`

## REQ-W-GOLD-02: W-PDF checklist XLSX exporter entry point
Target: W-PDF's checklist export (11 §4.5, §7.14).
Need: `exportChecklistXlsx(procedure: Procedure, store: AppStore, to url: URL) throws` (or the equivalent that
writes the workbook bytes), callable from tests.
Why: E13.X1–X4 compare the archive manifest (`zip-manifest-ordered`) with the Windows `ChecklistExporter.ExportXlsx`
output (X3b and X4 are divergent per 11 §7.14 / DEV-03).
Workaround in place: E13 is a pending reproducer.

Resolution: deferred — entry point exists (`PdfChecklistXlsx`, AACore/Export); E13 pending entry names it (016be4f); reproducer needs the Windows golden — Stage V

## REQ-W-GOLD-03: W-SIRE export, task identifier and tag extractor entry points
Target: W-SIRE's AACore SIRE code (12 §7.3–§7.5, §7.10).
Need: `SireExport.modes` and `SireExport.build(mode:all:state:identified:filtered:now:)` (with an injectable `now`;
12 §7.10 pins 2026-09-29 14:05), `TaskIdentifier.identifyAllTasks(_ questions:) -> [String: [String]]`,
`TagExtractor.extractTags(_:)`, `extractRoviqLocations(_:)`, `dominantCategory(_:)`.
Why: X04 (text-lf export per mode) and X05 (identification over the real bank).
Workaround in place: X04/X05 are pending reproducers.

Resolution: deferred — entry points exist (`SireExport.modes` / `SireExport.build(mode:all:session:…)`, `SireTaskIdentifier.identifyAllTasks`, `SireTagExtractor.extractTags` / `extractRoviqLocations` / `dominantCategory`); X04/X05 pending entries name them (016be4f); reproducers need the Windows goldens — Stage V

## REQ-W-GOLD-04: W-VESSEL Ports date/time normalisers
Target: W-VESSEL's Ports import (10 §3.x, `PortCallReader.NormDate` / `NormTime`).
Need: `PortsImport.normDate(_:) -> String` and `normTime(_:) -> String` callable from tests.
Why: XlsxGolden records `portsDate` / `portsTime` for every cell (10 X.8.1 columns C·D, C·T); the Swift comparison
(`GoldXlsxGoldenTests`) skips those two keys until the functions are reachable.
Workaround in place: the keys are skipped (documented in Deviations GOLD-R5); `ports` (the cell text) is compared.

Resolution: applied — `GoldXlsxGoldenTests.compare` checks `portsDate` / `portsTime` through `VesselText.normDate(_:today:)` / `normTime(_:)` over the ports cell text, and the self-test golden records them (0976386); GOLD-R5 closed

## REQ-W-GOLD-05: an owned path for the wave progress record
Target: `Docs/OWNERSHIP.md` §2 and `Scripts/check-ownership.sh` (owner: lead).
Need: `Docs/Progress/<id>.md` owned by each agent, like `Docs/Requests/<id>.md` and `Docs/Deviations/<id>.md`.
Why: the wave brief asks for `Docs/Progress/W-GOLD.md`, but `check-ownership.sh` reports it as an unowned path and
fails the gate.
Workaround in place: the progress record (counts, per-ID status, remaining work) is the last section of
`Docs/Deviations/W-GOLD.md`.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5); the progress record moved from Deviations/W-GOLD.md to `Docs/Progress/W-GOLD.md` (ad9a24b)
