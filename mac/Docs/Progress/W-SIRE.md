# W-SIRE — progress record (DECISIONS REQ-F1-01)

Branch `wave/W-SIRE`. Scope: spec 12 (SIRE 2.0) incl. Addendum SIRE-049…051, 02 REPO-030, 03 SHELL-688,
06 BUILD-A26 / BUILD-145 B2 (+ the B2 half of A27), 07 VIEW-212 rows 23–25.

## Counts

| | Done | Total | Remaining |
|---|---|---|---|
| Feature IDs (OWNERSHIP §4: SIRE-001…051, REPO-030, SHELL-688) | 53 | 53 | 0 |
| Algorithm / caller rows (BUILD-A26, BUILD-145 B2, A27 B2 status, VIEW-212 rows 23–25) | 6 | 6 | 0 |
| Placeholders (`check-placeholders.sh W-SIRE`) | 0 left | — | 0 |
| `SireContractStatus` | `wSireImplemented = true` | | |

## Tests (Tests/AACoreTests/Sire, 11 files)
- Bank: TV-BANK-1…5 (SHA-256, 410 / 12 chapters / 72 sections, types, filter lists, 39 ROVIQ locations), metadata,
  lazy load + cached failure texts, tolerant decoding.
- TaskIdentifier: TV-ID-1…4, TV-ID-BANK (332 questions, 6 106 tasks, per chapter, min 6 / max 39).
- TagExtractor: TV-KW-1…4 (counts, SHA-256 fingerprints, containment pairs, coverage 182 / 55), C# source diff,
  TV-TAG-1…4, TV-TAGX-1/2, TV-DOM-E/P/T/X, TV-TAGX-SYN 1–10, TV-TAGX-BANK-2, TV-TAG-BANK, ROVIQ §7.5.
- SireFlow: TV-FLOW-1…4, TV-FLOW-Q, XAML shape (§4.4 / 05 S-1, S-8), display renderer.
- Export: §7.10 goldens for all modes, empty state, file name, bytes.
- Filters §7.9, stats, SireState TV-ST-1…5, SireToAa §7.11 (+ chapter-8 scale), Gemini TV-GEM-1…7 (URLProtocol stub),
  GeminiKeyStore (clear deletes, import once, settings untouched), insertion-only gate incl. T-KB-53.
- Question-list publishing (`SireListStagingTests`): plain diff vs rebuild, staged first block + reveal, supersede,
  row keys per generation; source guards for the List wiring and the inset body paper.
- Post-merge (gated on `.wRich`): body persistence round trip; quick-add bodies load in the container editor/viewer.

## Snapshots (both appearances, `scratchpad/snapshots/W-SIRE/`)
Tab with a selected question (1500 and 1300 pt), unreadable saved body banner, candidate picker, kind picker
(question and section/chapter scope), export sheet, Gemini prompt, Settings ▸ AI section.

## Independent audit (2026-10-02)
- Clean rebuild + gate re-run; all 53 IDs and the 6 caller/algorithm rows re-checked against spec 12 and the C#
  (every C# string literal of TaskIdentifierService, GeminiService and SireExport found verbatim in the Swift).
- Fixed: the kind sheet's helper lines described single-question children for section / chapter adds too (now
  scope-aware: "Each question becomes a checklist step / subtask / component"); the truncated body hint strip now
  shows its full text as a tooltip.

## FIX-W-SIRE (V-12 verification findings, 2026-10-03) — 3 / 3 fixed
- **SIRE-036 / SIRE-001 (major)** — export sheet stuck on `Loading SIRE 2.0 question bank…` when opened during a
  running load. `SireBank.load()` now runs the decode inside a MainActor task that publishes `contents` / `phase`
  before it returns, so every waiter (first or joining) resumes after the state is final; `SireExportSheet` takes its
  phase from the returned `Result` and also follows `SireBank.shared.phase`. Test
  `SireBankLoaderTests.joiningCallerSeesPublishedState` (fails on the old code, passes now). Snapshot
  `--snapshot TabSire --sheet w-sire.export` without pre-install now shows the live preview.
- **SIRE-023 / SIRE-050 (minor)** — new tests `SireRichTextIntegrationTests.paneBodyStoredShape` /
  `containerBodyStoredShape` pin the §4.4 stored shape after the W-RICH round trip (root Foreground pane `#FF000000` /
  container `#FF334155`, Segoe UI 13, chip `#FFF8FAFC` + `10,8,10,8`, section label `#FFFEF3C7` + `8,4,8,4` + run
  `#FF92400E`, Disc List → ListItem → nested Circle List, the LF-bearing full text kept in ONE Run, no U+2028 written).
  `SireBankTests.tagAggregates` now asserts the TV-TAGX-FP "only inside a longer word" column (AIS 7, UPS 2, DOC 60,
  rating 47, COW 1, SSO 54, NCR 5, COF 5, OWS 2, anchor 3, procedure 156).
  - The new test exposed a real loss: text typed right after a list bullet inherited `.aaListMarker` from the
    `\t•\t` marker and the XAML writer dropped it on save. `SireInsertionTextView` now cleans its typing attributes
    (`EditorFormatting.cleanTypingAttributes`) before every insertion / plain paste.
- **SIRE-038 (polish)** — Tools ▸ Set Gemini API Key… Keychain failure text uses the Security framework message
  (`SecCopyErrorMessageString`) plus the OSStatus instead of the raw Swift error value.
- Design rules (V-DESIGN) on the SIRE sheets / tab: candidate + kind prompts use the NSAlert title font, mono rows,
  no zebra stripes, AAEmptyState for "No matches." and the load failure; export sheet uses `BuilderSheetHeader`,
  mono mode rows and line count, 44-pt footer; status badge = `AAStatusCapsule`; no raw `.system(size:)` left in
  `Sources/AA/Sire`. Snapshots light + dark: `scratchpad/snapshots/fix1-W-SIRE/`.

## FIX2-W-SIRE (Stage V round 2 findings, 2026-10-03) — 2 defects fixed (3 findings; two were the same defect)
- **V2-J7 + V2-DESIGN rule 18 (minor)** — `WARNING: Application performed a reentrant operation in its NSTableView
  delegate` on every fill of the question list. Root cause (lldb on `NSLog`): not the `scrollTo` or the selection
  write the findings suspected — the warning came from `-[NSTableRowHeightData _cacheRowSpansInRange:]` re-entering
  itself inside `-[NSTableView endUpdates]` when SwiftUI's diff INSERTED rows (0 → 410 on load, and also 24 → 410,
  410 → 198 → 148, 106 → 99 on search / evidence changes, and in the production path without `AA_SIRE_SELECT`).
  Fix: `SireStagedRows` (AACore) — removals and re-sorts are a plain diff; a publish that adds rows rebuilds the list
  with new row identities, the first 40 rows first and the rest on a later run-loop turn (`revealRows`), then the kept
  selection (or the top) is scrolled into view (D-SIRE-22). `displayed` stays the full list (header, export,
  selection order). Tests `SireListStagingTests` (7 logic + 1 wiring). Journey (finding repro): 22 snapshot runs —
  TabSire with no selection / 2.2.2 / 2.1.1 / 2.1.1,5.1.1 / 1.1.1 and the 6 W-SIRE sheets, light + dark — print no
  reentrant (or any other AppKit) warning (was 1 per run); a 13-sequence filter battery (search, clear, evidence,
  chapters, sort, empty → full, tab away/back) printed 0 (was 6 of 13 sequences before).
- **V2-DESIGN rule 9 (minor)** — SIRE body was an edge-to-edge white slab. `SireBodyCard` now insets the paper 8 pt on
  a `panelAlt` card with radius `AARadius.paper`, 1-pt border and dark-mode shadow (same tokens as `EditorPane`);
  the paper keeps its 160-pt minimum. Rule 11 on the same card: the hint no longer truncates (`AAHelpText`, wraps).
  Test `SireListStagingTests.sireBodyIsAnInsetPaperPage`.
- Snapshots light + dark: `scratchpad/snapshots/fix2-W-SIRE/` (PNGs + stderr logs).

## Not done / open
- None of the assigned IDs. Optional extras not shipped are listed in `Docs/Deviations/W-SIRE.md`.
- Gate step 1/4 (`check-ownership.sh` paths) flags only `Docs/Progress/W-SIRE.md` until REQ-W-SIRE-01 lands.
- Body editing becomes live after the W-RICH merge (read-only original until then, D-SIRE-21).
