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
* Performance: 1 MB parse + resolve **21 ms** in a release build (budget 50 ms; debug ≈ 0.2 s) — `RichPerformanceTests`.
* `RichTextContractStatus` flipped to `true`; `Scripts/check-placeholders.sh W-RICH` prints nothing.
* Rendering checked visually (TextKit 1 `NSTextView` → PNG: lists, tables, SIRE chips, locks, pasted HTML/Excel) —
  `RichRenderSnapshotTests` (PNG export with `RICH_SNAPSHOT_DIR`).

Counts: Swift 6.4k lines in `Sources/AACore/RichText` (15 files), 2.2k lines of tests (11 files, 167 tests);
gate green (556+ tests in the package).

Post-merge (Stage V): §7.7 item 10 (every Mac output loads in Windows `TextRange.Load`) needs the W-GOLD Windows
harness; the editor behaviours of §7.8 are W-CONT's.
