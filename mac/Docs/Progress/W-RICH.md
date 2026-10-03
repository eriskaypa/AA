# W-RICH — progress (rich-text core: XAML ⇄ attributed string)

Feature IDs (OWNERSHIP §4): **23 / 23 done** — CONT-035, CONT-042, CONT-065, CONT-150…168 implemented; CONT-169 N/A
(reserved range bound, Deviations RICH-D06). Remaining: **0**.

| ID | Status | Where |
|---|---|---|
| CONT-035 | done | `HTMLToXAML` (05 §3.3 port + DECISIONS whitespace clean-up); the paste handler itself is W-CONT's |
| CONT-042 | done | `RichListFormatter.normalise` (+ every list command) |
| CONT-065 | done | `LockRules` (sentinel, geometry, `quickHasAnyLock`, lock/unlock), reader `.aaLockSource` |
| CONT-150 | done | one `XamlDocument` + `XamlStyleResolver` for reader, writer, fragments, PDF |
| CONT-151…155 | done | `XamlDOM` / `XamlXMLScanner` / `XamlDOMBuilder` |
| CONT-156…160 | done | `XamlStyle` (contexts, cascade, rendered functions, lock vs PDF walks) |
| CONT-161 | done | `XamlReader.readFragment`, `destinationContext` |
| CONT-162 | done | loadability verdicts; writer drops invalid recognised attributes |
| CONT-163…167 | done | `XamlWriter` (flattened / modelled / carried, CONT-164 test, root completion, line-break provenance, link colour) |
| CONT-168 | done | fixed sRGB everywhere (`RichColor`); no dynamic colours |
| CONT-169 | N/A | reserved |

Acceptance (OWNERSHIP §3 W-RICH, in-worktree): all met.
* XD-V1…V8, XD-C1…C18, XD-E1…E20, XD-W1…W9, XD-L1…L10 — `XamlReaderTests`, `XamlStyleTests`, `XamlDOMTests`
  (`XamlValuesTests.sameVectors`), `XamlWriterTests`.
* 05 §7.1 H1–H20 + helper vectors (canonical XML compare) and 3 clipboard goldens in `Fixtures/html/` —
  `RichHTMLToXAMLTests`.
* §7.2 list engine vectors 1–10 + Return / Tab / Backspace / insert — `RichListFormatterTests`.
* §7.4 lock geometry table, unlock granularity, scans — `RichLockRulesTests`.
* §7.7 goldens 1–9 incl. untouched-body byte stability (fixed point on every sample, both contexts) and the lock
  sentinel round trip — `XamlReaderTests`, `XamlWriterTests`; samples S-1…S-10 in `Fixtures/xaml/samples/`.
* Performance: 1 MB parse + resolve **21 ms** in a release build on an idle machine (budget 50 ms; debug ≈ 0.2 s) —
  `RichPerformanceTests`. Second audit, machine under load (load average 8–12 from parallel agents): 55–86 ms for this
  branch and 49–76 ms for the pre-audit commit `768cdff` measured the same way, so no regression from the audit
  changes; the release-build budget needs re-confirming on an idle machine (the gate runs the debug bound, 1.5 s).
* `RichTextContractStatus` flipped to `true`; `Scripts/check-placeholders.sh W-RICH` prints nothing.
* Rendering checked visually (TextKit 1 `NSTextView` → PNG: lists, tables, SIRE chips, locks, pasted HTML/Excel) —
  `RichRenderSnapshotTests` (PNG export with `RICH_SNAPSHOT_DIR`).

* Robustness: seeded edit fuzzing (`RichEditFuzzTests`, 30 steps × 11 samples in the gate) and seeded input-mutation
  fuzzing (`RichInputFuzzTests`, 60 mutants × 11 samples in the gate: cuts, duplicated slices, injected invalid values,
  markup extensions, duplicate properties, foreign elements, misplaced structure) — every rewrite parses, is loadable
  (bar opaque content the input already had) and is a read → write fixed point. Both take `FUZZ_SEED` /
  `FUZZ_STEPS` / `FUZZ_MUTANTS` for deeper runs; the audit ran 400 mutants × 15 seeds and 300 steps × 3 seeds green.

## Independent audit (second pass)

Counts: IDs checked **23** (CONT-035, 042, 065, 150…169) against 05 §3.2/§3.3/§4.3/§6.4/§6.5/§7.1–7.7, addendum
XD.1–XD.6 (all V/C/E/W/L vectors), 12 §6.5, 11 §6.3 and the C# (`HtmlToXamlConverter.cs`, `ListFormatting.cs`,
`ContainerEditor.xaml.cs` lock / indent code). Fixed **4** partial behaviours (CONT-162 ×2, CONT-164, CONT-166 display
order); remaining **0**.

| Finding | ID | Fix |
|---|---|---|
| An invalid recognised attribute on the loaded root (e.g. `Foreground="#FF1A1 A1A"`) was re-emitted, keeping the note unloadable on Windows | CONT-162/165 | root filtered like every carried element; completion supplies the context value (RICH-I13) |
| A carried `Paragraph.Foreground` / `Section.Foreground` property element was ignored by the writer's cascade: a Run equal to the root but not to that block lost its `Foreground` and changed colour on the next load | CONT-164 | property-element Foreground applied in `carried()`; dropped on empty paragraphs (RICH-I13) |
| Elements inside a `Run` (invalid nesting) were all shown as chips after the Run text: wrong order, and a recognised inline (`<Bold>`) written back next to the Run became real content on the next read (not a fixed point) | CONT-162 | shown in place; recognised inlines read as content (RICH-I12) |
| A recognised element where rows belong (`<Hyperlink>` in a `TableRowGroup`) was written after the table at block level, where it is invalid again | CONT-162 | becomes an implicit row/cell (RICH-I12) |

New tests: `RichVectorRowTests` (the NSAttributedString / writer columns of XD-C2/C3/C4/C10/C11/C13/C17/C18 and
XD-L2/L7/L8/L9 that the resolver-level tests did not reach, Hyperlink carried attributes, CR write-back, SIRE pane
margins/lists), `RichInputFuzzTests` + `RichTolerantInputTests` (the regressions above), root case in
`XamlWriterTests.invalidRecognisedAttributesAreNeverReemitted`.

Counts: Swift 6.8k lines in `Sources/AACore/RichText` (19 files), 2.8k lines of tests (14 files, 194 tests);
gate green (593 tests in the package).

Post-merge (Stage V): §7.7 item 10 (every Mac output loads in Windows `TextRange.Load`) needs the W-GOLD Windows
harness; the editor behaviours of §7.8 are W-CONT's.
