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

## Tests (Tests/AACoreTests/Sire, 12 suites)
- Bank: TV-BANK-1…5 (SHA-256, 410 / 12 chapters / 72 sections, types, filter lists, 39 ROVIQ locations), metadata,
  lazy load + cached failure texts, tolerant decoding.
- TaskIdentifier: TV-ID-1…4, TV-ID-BANK (332 questions, 6 106 tasks, per chapter, min 6 / max 39).
- TagExtractor: TV-KW-1…4 (counts, SHA-256 fingerprints, containment pairs, coverage 182 / 55), C# source diff,
  TV-TAG-1…4, TV-TAGX-1/2, TV-DOM-E/P/T/X, TV-TAGX-SYN 1–10, TV-TAGX-BANK-2, TV-TAG-BANK, ROVIQ §7.5.
- SireFlow: TV-FLOW-1…4, TV-FLOW-Q, XAML shape (§4.4 / 05 S-1, S-8), display renderer.
- Export: §7.10 goldens for all modes, empty state, file name, bytes.
- Filters §7.9, stats, SireState TV-ST-1…5, SireToAa §7.11 (+ chapter-8 scale), Gemini TV-GEM-1…7 (URLProtocol stub),
  GeminiKeyStore (clear deletes, import once, settings untouched), insertion-only gate incl. T-KB-53.
- Post-merge (gated on `.wRich`): body persistence round trip; quick-add bodies load in the container editor/viewer.

## Snapshots (both appearances, `scratchpad/snapshots/W-SIRE/`)
Tab with a selected question (1500 and 1300 pt), unreadable saved body banner, candidate picker, kind picker,
export sheet, Gemini prompt, Settings ▸ AI section.

## Not done / open
- None of the assigned IDs. Optional extras not shipped are listed in `Docs/Deviations/W-SIRE.md`.
- Gate step 1/4 (`check-ownership.sh` paths) flags only `Docs/Progress/W-SIRE.md` until REQ-W-SIRE-01 lands.
- Body editing becomes live after the W-RICH merge (read-only original until then, D-SIRE-21).
