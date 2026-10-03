# W-GOLD — deviations from the golden-fixture plan

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`. None of these changes
what any golden asserts about Windows; they are naming, layout and plan refinements.

## Naming and layout

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-N1 | DATA-311, ARCH §12.2 | Swift types carry the `Gold` prefix: `GoldFixtureIndex` (plan: `FixtureIndex`), `GoldZipManifest` (`ZipManifest`), `GoldXMLCanonicalizer` (`XMLCanonicalizer`), `GoldenMatcher` kept; suites `Gold*Tests`. |
| GOLD-N2 | GF.8.6, DATA-313 | Tag `.goldWinFixtures` / `.goldShould` (plan: `.winFixtures` / `.should`); CI filter `swift test --filter Gold` (plan: `--filter WinFixtures`); the emitter suite is `GoldMacOutEmitter` (plan: `MacOutEmitter`). `Scripts/fixtures.sh` uses the new names. |
| GOLD-N3 | GF.4.1, DATA-312 | Fixture roots live in the SwiftPM fixture folder (ARCH §10.2): `Tests/AACoreTests/Fixtures/winfixtures/`, `…/mac-out/`, `…/xaml/wpf-capture/`, `…/xaml/mac-roundtrip/` (plan text: `mac/Tests/Fixtures/…`). |
| GOLD-N4 | GF.4.1 | XLSX goldens: `winfixtures/xlsx/<workbook>.golden.json` (F2's `windowsGoldens` reads the same path); the synthetic 10 §X.8 workbooks the oracle reads are committed in `winfixtures/xlsx-inputs/` (written by the Swift emitter `GoldXlsxInputEmitter`, F2's `SvcXlsxTestBook`). |
| GOLD-N5 | DATA-310 | The windows-run twin of a `Runs.Both` / `Runs.Windows` case is recorded with the id suffix `w` (`A25xw`, `M.R14.smart.L0w`) under `windows/`; `GoldFixtureIndex.windowsTwin` resolves it. |
| GOLD-N6 | DATA-324, GF.6.8 | W19 (DPAPI samples) is a WinFixtures family-(a) case run only on Windows (it needs no WPF), recorded under `windows/json/`. |

## Manifest and comparison extensions

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-M1 | GF.4.5 | Extra token `%%DATADIRUPPER%%` — the data folder upper-cased, which A25 writes on case-insensitive file systems. Masked only as a whole literal; the Swift matcher accepts the Mac folder upper-cased (invariant). |
| GOLD-M2 | GF.4.4 | Per-output `compare` (overrides the case mode), `pointer` and `"mac": false` (a Windows record the Mac does not reproduce). `macExpectation.file` may carry `#/json/pointer`; `macExpectation.compare` overrides; a `divergent` expectation without `file` is record-only (the Mac rule is asserted by the owner's own tests, the reason cites them). |
| GOLD-M3 | GF.4.4, DATA-303 | `nonDeterministic: true` (K04: real random-IV blobs are decrypt-only vectors) — excluded from `--verify-only` byte comparison like `dependsOnToday` outputs. |
| GOLD-M4 | GF.4.7 | Exception shapes: `type` is never compared when the object carries `aaAuthored` (Swift error types cannot be .NET type names); `message` is compared only when `aaAuthored` is true. |
| GOLD-M5 | GF.3.9, GF.4.6 | In `zip-manifest` mode the uncompressed size and CRC of masked AA-format payloads (`data.json`, `source.json`, `settings.json`) are not compared — their bytes are compared `bytes-masked` from the payload golden instead. |
| GOLD-M6 | DATA-308 | Must-level cases whose Swift side needs another owner's private code are registered as *pending* reproducers: reported (never silent) and a failure only under `AA_REQUIRE_FIXTURES=1` (Requests REQ-W-GOLD-01…04). |

## Case catalogue refinements (GF.5)

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

## Reverse direction and inputs

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

## Tooling

| ID | Spec ref | Deviation |
|---|---|---|
| GOLD-T1 | GF.0, DATA-300 | The C# oracles were written and reviewed by inspection only: this machine has the .NET 10.0.12 runtime but no SDK, and installing one is a download. The first `Scripts/fixtures.sh generate` (macOS) and `WinCapture all` (Windows) are also the compile check. |
| GOLD-T2 | DATA-314 | WinFixtures pins `AA_DATA_DIR` to a never-created scratch path in the parent process before the case catalogue touches `DataStore`, so no process of the tool can resolve the operator's real `%LOCALAPPDATA%\AA`. |
| GOLD-T3 | DATA-313 | `Scripts/fixtures.sh` adds `xlsx-golden`, `emit-xlsx-inputs`, `real-data <path>` and `status` to the commands named in GF.8.6. |

## Progress record

`Docs/Progress/W-GOLD.md` is not an owned path (OWNERSHIP §2; `Scripts/check-ownership.sh` rejects it), so the
progress record lives here until the lead rules on REQ-W-GOLD-05.

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
