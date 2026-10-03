# W-PDF — progress (PDF & checklist export, spec 11 + 06 BUILD-091…096, 04 HIER-092, 05 CONT-049)

## Counts

| | n |
|---|---|
| Feature IDs assigned (OWNERSHIP §4) | 82 |
| Done | 82 |
| Remaining | 0 |
| Algorithm ids (BUILD-A17, A21, C1, C2, C3) | 5 / 5 done |
| Placeholders left (`Scripts/check-placeholders.sh W-PDF`) | 0 |
| `ContractStatus.wPdfImplemented` | true |
| Tests (Swift Testing, `Tests/AACoreTests/Export/`) | 64 test functions (+22 extra parameterised link-scanner cases); 3 gated on `.wRich`, 1 dump suite gated on `AA_PDF_DUMP_DIR` |

## Where each feature lives

| IDs | Implementation |
|---|---|
| PDF-001 | `PdfExport.exportButtonTitle/Help`, `PdfExportItemButton` (AA/Export/PdfExportButtons.swift), `PdfExportFlows.exportItem`; the header button's placement is W-HIER's call site, ⌥⌘E / ⌘P rows are F3's router (already wired to `exportItem` / `printItem`). |
| PDF-002…007 | `PdfExportFlows.exportItem` / `prepareItemExport` / `flushIfDirty` / `runBusy` (lock refusal, flush all editors, save panel with Windows-set file names, off-main render, "Export error" alert, auto-open). |
| PDF-010…012, HIER-092, BUILD-039/040 (callers) | `PdfChecklistExportButtons`, `PdfExportFlows.exportChecklistPDF/XLSX`. |
| PDF-020…027, BUILD-091…096, CONT-049 | `PdfExport.savedListsSelection`, `PdfExportFlows.exportSavedLists`, `PdfListStyleSheet`, `PdfSavedListsExportButtons`, `PdfSavedListContextMenuItem`, `PdfSavedListsBuilder` (BUILD-A17 / C3). |
| PDF-030…045 | `PdfItemBuilder` (+ `PdfScaffold` header/footer, `PdfStyleSheet.pdfExporter`, `PdfPageSetup.pdfExporter`). |
| PDF-050…055 | `PdfSavedListsBuilder`. |
| PDF-060…077 | `PdfRichText` (fallback `stripXamlTags`, DOM path over W-RICH's `XamlDOM` + `XamlStyleResolver(.pdf)`, lists, tables, links, highlight, strike), `PdfLinkScanner`, `PdfFontResolver`. |
| PDF-080…084, BUILD-C1 | `PdfChecklistBuilder` (`PdfStyleSheet.checklist`, `PdfPageSetup.checklist`). |
| PDF-090…094, BUILD-C2 | `PdfChecklistXlsx` over F1's `XlsxWriter` package writer and constant parts. |
| PDF-100…105 | `PdfLayoutEngine` (CoreText line breaking, tabs, line heights, KeepWithNext chains, widow/orphan, row-atomic tables with repeated heading rows, DEV-08 splits), `PdfRenderer` (CGContext PDF, `/Link` `/URI` annotations, Title/Author/Creator), `PdfText` (AddText splitting, DEV-13), `PdfSnapshotBuilder` (main-actor snapshots, nil-safe). |

## Verification

* Gate: `swift build -j 3 -Xswiftc -warnings-as-errors && swift test -j 3 -Xswiftc -warnings-as-errors` green;
  `Scripts/check-ownership.sh` green except the single "unowned path" note for this file (REQ-W-PDF-01).
* 11 §7.1–§7.12, §7.14 (package rows), §7.15, §7.16 and the §7.13 DOM goldens (notes through the fallback path)
  pass in the worktree; §7.13 with rich bodies and the real-parser rich-text vectors are gated on `.wRich`
  (post-merge, Stage V).
* Visual: PDFs rendered to PNG (`AA_PDF_DUMP_DIR=… swift test --filter PdfVisualDumpTests`) and inspected — item PDFs
  of all four kinds, a 60-step checklist (header row repeated on every page), saved lists bulleted/numbered, an
  engine demo (fonts, colours, links, strike, highlight, alignment, indents, lists, merged/nested tables, emoji/CJK
  fallback, a long unbroken token). Nothing clipped past the margins (`linesStayInsideMargins` asserts it).
* Snapshot hook (both appearances): `w-pdf.list-style`, `w-pdf.list-style-many`, `w-pdf.busy`, `w-pdf.preview` (the
  in-app pipeline: fixture `Fixtures/ui/w-pdf/sample-data.json` → snapshot → DOM → layout → PDF page image).

## Independent audit (2026-10-02)

All 82 assigned IDs (PDF-001…007, 010…012, 020…027, 030…045, 050…055, 060…077, 080…084, 090…094, 100…105;
BUILD-091…096; HIER-092; CONT-049) and the 5 algorithm ids were re-checked against spec 11 / 06 / 04 / 05 and the C#
(`PdfExporter.cs`, `ChecklistExporter.cs`, `HierarchyPage.xaml.cs`, `ListStylePromptWindow.xaml`). Clean rebuild
(`rm -rf .build`) and the full suite green. Fixes made by the audit:

* PDF-100 / §7.16 #6: a KeepWithNext chain now reserves the lines the next paragraph's orphan control needs, so a
  heading can no longer be stranded at a page bottom when only one line of its paragraph would fit (new paginator
  vectors in `keepWithNextChain`).
* BUILD-A17 / PDF-052: group headings compare group names ordinally (UTF-16), like .NET `==`; Swift `==` merged
  canonically equivalent spellings.
* PDF-039: subtask indents are the Windows `"{x:0.##}cm"` values (1.8, not 1.7999…).
* PDF-004 / 011 / 024: the save-panel sheet shows the Windows dialog title as its message.
* CONT-049 sheet: both radio captions wrap at one measure.

Snapshots re-rendered in both appearances (`--snapshot TabLists --sheet w-pdf.<id>`): `list-style`,
`list-style-many`, `busy`, `preview`; the dumped PDFs (`AA_PDF_DUMP_DIR`) re-inspected page by page.

## Not done / post-merge

* None of the assigned IDs is open. Post-merge (Stage V): the `.wRich`-gated rich-text vectors; cross-agent UI checks
  of the export buttons inside W-HIER's header and W-BUILD's Specifics / Saved Lists views (they call
  `PdfExportFlows` per ARCH §7.7; ready-made button views are available in `AA/Export/PdfExportButtons.swift`).
