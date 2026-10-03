# W-GOLD — progress

Moved verbatim from `Docs/Deviations/W-GOLD.md` once `check-ownership.sh` mapped `Docs/Progress/<id>.md`
(REQ-W-GOLD-05, f556cb5). Post-wave: REQ-W-GOLD-04 applied (portsDate / portsTime compared); the E09, E11, E13, E15b,
X04, X05, X06 reproducers stay pending (entry points now public; reproducers need the Windows goldens — Stage V).

Card: OWNERSHIP §3 "W-GOLD — Golden-fixture plan". Specs: 01 Addendum GF (DATA-300…326), 10 §X.7.6, 05 XD.8.
Branch `wave/W-GOLD`. Format of each row: ID · status · where.

### Counts

| | Count |
|---|---|
| Feature IDs | 27 (DATA-300…326) |
| Complete in this worktree (code + tests/docs) | 23 |
| Complete here, Swift reproducers of some must-cases pending another owner's API (Requests) | 2 (DATA-319: E09, E11, E13, E15b; DATA-320: X04, X05, X06) |
| Not done here — needs a person on Windows (tooling, procedure and the Swift consumer complete) | 2 (DATA-322, DATA-323) |
| Placeholders / ContractStatus owned | 0 (`Scripts/check-placeholders.sh W-GOLD` prints nothing) |
| Goldens committed | 0 Windows goldens (no .NET SDK here; see "Remaining") · 16 mac-out artefacts · 6 synthetic XLSX inputs |
| Swift | 21 files under `Tests/AACoreTests/WinFixtures/`, 6 235 lines, 90 `@Test` functions (several parameterised over the manifest) |
| C# | 3 oracle projects under `Tools/`, ~7 060 lines, compiled by inspection only |
| Gate | `swift build`/`swift test -warnings-as-errors` green (489 tests in 97 suites), `check-ownership` OK, `check-placeholders W-GOLD` empty |

### Feature IDs

| ID | Status | Where |
|---|---|---|
| DATA-300 WinFixtures project | done | `Tools/WinFixtures/WinFixtures.csproj` (linked read-only sources, ClosedXML 0.104.2, PDFsharp-MigraDoc 6.2.0), `Shims/DispatcherTimer.cs` |
| DATA-301 source pinning | done | `Support/SourcePin.cs` (`verify-sources`, provenance in MANIFEST), `Scripts/fixtures.sh verify-sources` |
| DATA-302 CLI | done | `Program.cs` (`verify-sources`, `generate`, `case`, `selfcheck`, `check-mac`, `list`); parent pins a scratch `AA_DATA_DIR` |
| DATA-303 process-per-group driver, determinism | done | `Support/Driver.cs` (groups, staging, swap, `--verify-only` diff); A20 noise SHA-256-derived; fixed ZIP timestamps |
| DATA-304 reflection access | done | `Fx.Call/CallVoid`, `Fx.Opts/TrashOpts` (read-only reflection) |
| DATA-305 masking | done | C# `Support/Masker.cs`; Swift `GoldenMatcher.swift` (+ `%%DATADIRUPPER%%`, Deviations) |
| DATA-306 fixture tree | done | `Tests/AACoreTests/Fixtures/{winfixtures,mac-out,xaml/wpf-capture,xaml/mac-roundtrip}`; authored inputs `winfixtures/inputs/{A05,A10}.input.json`, `E11.rows.json` |
| DATA-307 MANIFEST + case records | done | C# `CaseRun.Record`, `Driver.MergeManifest`; Swift `GoldManifest`/`GoldFixtureIndex` (rejects duplicate ids, unknown modes, divergent without reason) |
| DATA-308 goldens win / spec conflicts | done | C# `Support/SelfCheck.cs` (01 §4.2.1, §4.4, §7.1, §7.2, §7.4, §7.5, §7.8; 02 §7.7–7.9; 05 §7.6; 09 §7.1, §7.13); Swift presence suite fails on an open conflict |
| DATA-309 comparison modes | done | `GoldCaseRunner.compare` (bytes, bytes-masked, json-semantic, zip-manifest(-ordered), text-lf, xml-canonical, record-only); `GoldZipManifest`, `GoldXMLCanonicalizer` |
| DATA-310 platform matrix | done | `Runs` Any/Unix/Windows/Both; `w`-suffixed windows twins; `GoldFixtureIndex.windowsTwin` |
| DATA-311 Swift golden harness | done | `GoldFixtureIndex`, `GoldenMatcher`, `GoldZipManifest`, `GoldCaseRunner`, one suite per family; GF.9 self-tests (`GoldHarnessTests`) |
| DATA-312 reverse direction (mac-out) | done for F1/F2 paths | `GoldMacOutEmitter.swift` (+ always-on read-back `GoldMacOutTests`); committed `Fixtures/mac-out/` (json ×5, settings ×4 + expect, crypto locks/blobs, INDEX.json); bundles/ and xaml/ emit once W-PERSIST / W-RICH flip; C# `Support/CheckMac.cs` |
| DATA-313 toolchain pin, regeneration, CI | done | `Tools/global.json` (SDK 10.0.100, latestPatch), `Scripts/fixtures.sh` (`ci`, `verify-generated`, `require`, `status`, …) |
| DATA-314 privacy | done | synthetic content only; `GoldRealDataRoundTrip` (`AA_REAL_DATA_JSON`, `fixtures.sh real-data`; copy in temp, offsets only); C# parent/child scratch data folders |
| DATA-315 family (a) | done | C# `Cases/FamilyA.cs` (A01–A26, W19); Swift `GoldJSONGoldenTests.swift` (A25/A25x/A25s/A26-paths gated on W-PERSIST) |
| DATA-316 family (b) | done | C# `FamilyB.cs` (S01–S12, one process each); Swift `GoldSettingsGoldenTests.swift` |
| DATA-317 family (c) | done | C# `FamilyC.cs` (B01–B08, R01–R17, M, P, T, C01); Swift `GoldBundleGoldenTests.swift` (writer/import/peek gated on W-PERSIST; B07/B08 run now) |
| DATA-318 family (d) | done | C# `FamilyD.cs` (K01–K10); Swift `GoldCryptoGoldenTests.swift` (K03/K08 literal tests pass) |
| DATA-319 family (e) | partial — C# complete; Swift reproducers for E09, E11, E13, E15b pending other owners | C# `FamilyE.cs` (E01–E16); Swift `GoldServiceGoldenTests.swift`; E09, E11, E15b → REQ-W-GOLD-01, E13 → REQ-W-GOLD-02 |
| DATA-320 family (f) | partial — C# complete; Swift reproducers for X04, X05, X06 pending other owners | C# `FamilyF.cs` (X01.rel/purge/rec/recToday/tr/log, X02–X06); Swift `GoldExtGoldenTests.swift`; X04/X05 → REQ-W-GOLD-03, X06 → REQ-W-GOLD-01 |
| DATA-321 WinCapture W01–W18 | done | `Tools/WinCapture/` (Program.cs W01–W06, Cases/Recipes.cs W07–W18, culture invariance); Swift `GoldXamlCaptureTests.swift` (gated on W-RICH) |
| DATA-322 clipboard input capture | **not done** — needs Word/Excel/Outlook/Edge on Windows | tool `WinCapture dump-clipboard` and the R-1…R-11 / H-1…H-7 recipe table are complete (`Tools/WinCapture/README.md` §2) |
| DATA-323 manual confirmations M-01…M-09 | **not done** — needs a person driving AA.exe on Windows | procedure + extraction script complete (`Tools/WinCapture/README.md` §4); Swift consumer `GoldManualCaptures.swift` (M ↔ W claims, M-06, M-09, M-capture round trip) with synthetic self-tests (GOLD-R6/R7) |
| DATA-324 Windows-only non-WPF artefacts | done (tooling) | W19 in FamilyA (`Runs.Windows`), windows run + neutrality cross-check in `Driver`; W21 Explorer ZIP joins the M/P matrices as R20 and survives windows runs (GOLD-C9); W20 = M-07, compared with E13.X1 by `GoldManualCaptureTests` |
| DATA-325 WPF load-check of Mac XAML (W23) | done | `WinCapture load-check`; Swift `GoldMacRoundtripTests` (load-check rows, sentinel count, canonical differences recorded, text check gated on W-RICH) |
| DATA-326 acceptance gate | done (harness side) | `GoldFixturePresenceTests` (absence fails under `AA_REQUIRE_FIXTURES=1`; open spec conflicts / platform divergences fail); `GoldAcceptanceGate.swift` (GF.9 items 1, 3, 6, 9 — GOLD-R8); `fixtures.sh ci` |

10 §X.7.6 XlsxGolden (not a DATA id): `Tools/XlsxGolden/` + `GoldXlsxGoldenTests.swift` + synthetic X.8 inputs
`Fixtures/winfixtures/xlsx-inputs/` (emitter `GoldXlsxInputEmitter`).

### Remaining (not doable in this worktree)

1. Generate the Windows goldens — needs the .NET 10 SDK (only the 10.0.12 runtime is installed here; installing the
   SDK is a download, not done): `Scripts/fixtures.sh generate`, `xlsx-golden`, then commit
   `Fixtures/winfixtures/`. First run also confirms the C# compiles (written by inspection).
2. Windows capture machine: `WinCapture all`, DATA-322 clipboard inputs, DATA-323 manual steps, the windows run of
   WinFixtures (`generate --platform windows`, W19/W22), W21 Explorer ZIP, `check-mac --platform windows`,
   `load-check` (W23) over `mac-out/xaml` once W-RICH has emitted it.
3. Windows capture machine, W21: the Explorer ZIP `windows/bundles/R20.explorer.bundle.zip`, then a `generate` to add
   its M/P rows.
4. Post-merge: re-run `Scripts/fixtures.sh emit-mac-out` once W-PERSIST and W-RICH have flipped (adds `bundles/`,
   `xaml/`); write the pending reproducers when REQ-W-GOLD-01…04 are answered; `Scripts/fixtures.sh require`.

### Independent audit (2026-10-02)

Gate re-run from a clean `.build`: green. Every DATA-300…326 row re-read against the spec and the code. Found and
fixed:

| Gap | Fix |
|---|---|
| W21 (GF.6.8): "the M matrix gains row R20 on the next generate" was not implemented, and a `generate --platform windows` would have deleted a committed `windows/bundles/R20.explorer.bundle.zip` (the windows run rebuilds `windows/bundles/` from scratch) | `FamilyC` R20 rows, `CaseDef.RequiresFile`, `Driver.AuthoredWindowsArtefacts` carried into staging (GOLD-C9); coverage ids in `GoldBundleReproducerTests` |
| DATA-323 / W20 / W24: nothing on the Swift side read `wpf-capture/manual/` — the manual confirmations, the shipped-exe XLSX and the AA.exe-written data.json would have settled nothing | `GoldManualCaptures.swift` + synthetic self-tests; README §4 table and the timezone file (GOLD-R6, GOLD-R7) |
| GF.9 items 1, 3, 6, 9 had no check (ledger coverage, provenance, release-gate presence of manual/W23/XlsxGolden/clipboard sources, source pins) | `GoldAcceptanceGate.swift` (GOLD-R8) |
| GF.6.10: the W01b root start tag was never compared with the Mac writer's new-document root | `GoldW01bRootTagTests` (runs once W-RICH flips and W01b is committed) |
| DATA-319/320 were counted done although seven must/should reproducers are pending other owners | counted as partial above |

Not fixable here: the .NET 10 SDK is not installed (runtime 10.0.12 only), so the C# oracles are still unbuilt; the
audit re-checked their calls against the linked AA sources by inspection (DataStore, AppRepository, PasswordService,
ItemLockService, DataDiff, Models, ZIP inspection) and found no mismatch.
