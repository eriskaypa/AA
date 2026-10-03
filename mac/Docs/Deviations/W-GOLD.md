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

Moved to `Docs/Progress/W-GOLD.md` (REQ-W-GOLD-05).
