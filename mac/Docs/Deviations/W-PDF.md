# W-PDF — deviations and P2 fixes (ARCHITECTURE.md §12.2)

Sanctioned deviations of spec 11 §6.9 that the Mac applies, P2 fixes, DECISIONS 11 rulings and layout choices.
Windows behaviour is kept wherever this list says nothing (DECISIONS P1/P3).

| ID | Spec ref | Change (one line) |
|---|---|---|
| DEV-01 | 11 PDF-066, Q1, DECISIONS 11 | **Not applied** (parity): only a Run's own `TextDecorations` print; Span/`Underline`-element decorations are dropped as on Windows. |
| DEV-02 | 11 §3.5.4 | Inside a targeted Hyperlink every text descendant (Runs inside Spans, nested links, LineBreaks) is part of the one link, in document order (Windows reorders A C B and leaves B unlinked). |
| DEV-03 | 11 PDF-091, PDF-094, §3.6.2 | XLSX sheet name: sanitise → truncate (31 UTF-16 units, no split surrogate) → escape; XML-illegal characters dropped from every cell (F1's `XlsxWriter.sanitizeSheetName` / `xmlEscape`). |
| DEV-04 | 11 PDF-067, §3.5.7 | Strike-through is drawn as a native line over exactly the characters Windows overlays with U+0336 (not whitespace / control); extracted text carries no U+0336. |
| DEV-05 | 11 PDF-064c, Q3, DECISIONS 11 | **Not applied** (parity): partial (few-word) highlights are dropped; only whole-paragraph shading. |
| DEV-06 | 11 §6.4, DECISIONS 11 Q2 | Mac font substitution table (Calibri → Carlito / Helvetica Neue / Helvetica, Consolas → Menlo / SF Mono / Monaco / Courier New, Segoe UI → system UI font, …). A substitute is drawn at a **metric scale** (Calibri→Helvetica Neue ×0.91, Consolas→Menlo ×0.914, …) so advance widths and page breaks match the Windows fonts; line heights follow the requested size. Stored font names are never changed. |
| DEV-07 | 11 §6.4 | CoreText cascade fallback renders glyphs missing from the chosen font (emoji, CJK) instead of tofu. |
| DEV-08 | 11 §3.2 rule 8 | A table row (or MergeDown group) taller than a page is split at line boundaries across pages, heading rows repeated; normal rows stay atomic. |
| DEV-09 | 11 PDF-003 | Item export/print flushes **every** editor (`env.flushAllEditors()`, incl. detached item windows) before `FlushIfDirty`. |
| DEV-10 | 11 PDF-022 | "Export ALL (PDF)…" never needs a selection (`PdfSavedListsExportButtons`); "No saved lists to export." kept for the empty case. |
| DEV-11 | 11 PDF-071, §7.2 | A formal link's target is the trimmed `NavigateUri` (www. → https://), not .NET `Uri.ToString()`; strings Foundation rejects are percent-encoded; a target that is still not a URL gets no annotation (the text stays blue/underlined). |
| DEV-12 | 11 PDF-025 | A failure to *open* the saved-lists PDF is ignored (never reported as "Could not export the PDF"). |
| DEV-13 | 11 PDF-101 | CRLF and lone CR become LF before `\n` splitting everywhere text enters the PDF. |
| PDF-105 | 11 PDF-105 | Nil names/titles print as "" (model strings are non-optional on the Mac); no export ever fails on a hand-edited null. |
| PDF-103 | 11 PDF-103, DECISIONS 11 Q7 | Header timestamp is `yyyy-MM-dd HH:mm` with en_US_POSIX digits and the Gregorian calendar (`NetDateTime.format(.isoMinute)` of the local now). |
| Q4 | 11 §3.5.8, DECISIONS 11 Q4 | A table inside a table cell is rendered inside the cell (Windows may fail or drop it). |
| Q5 | 11 §7.11, DECISIONS 11 Q5 | A legacy whole-document `enc:` body prints `(locked content)` (under its heading) instead of the ciphertext. |
| Q6 | 11 PDF-037/040/044, DECISIONS 11 Q6 | Password-gated related/linked items print their **name only**: no relationship description, no linked-procedure description/steps, no linked-task checkbox/meta/description. |
| Q8 | DECISIONS 11 Q8 | No PDF outline (parity). |
| PDF-025 buttons | 11 PDF-025, §6.5 | "Export complete" alert buttons `Open` (default) / `Not Now` / `Show in Finder` (allowed addition); message text verbatim. |
| PDF-005 busy | 11 PDF-005, §6.2 | Rendering runs off the main actor; an "Exporting PDF…" sheet appears only when an export takes longer than ~300 ms (also for saved lists and the workbook). |
| §6.2 Print | 11 §6.2 | File ▸ Print… (⌘P, F3 registry row) prints the same in-memory item PDF at 100 % through PDFKit's print operation (additive). |
| saved-lists flush | 11 §2.3 | Saved-lists export first flushes open editors (in memory only, no save), so a list item's last keystrokes print (additive; Windows reads the in-memory model too). |
| cell words | 11 §3.2, PDF-100 | In table cells a single word wider than the column may run into the cell's right padding (as MigraDoc overflows it) instead of being broken by character; body text and words wider than the cell still wrap by character so nothing is clipped. |
| table position | 11 §3.2 rule 8 | Tables are shifted left by their left padding, so cell text aligns with body text (MigraDoc's placement). |
| file names | ARCHITECTURE.md §1.2 vs §12.2 | The §1.2 tree's file names (PdfDOM, PdfStyles, FontResolver, LinkScanner, RichTextToPdf, ItemPdfBuilder, …) are implemented with the mandatory `Pdf` prefix: `PdfDOM`, `PdfStyles`, `PdfFontResolver`, `PdfLinkScanner`, `PdfRichText`, `PdfItemBuilder`, `PdfListBuilders` (saved lists + checklist), `PdfChecklistXlsx`, `PdfLayoutEngine`, `PdfRenderer`, `PdfSnapshots`, `PdfExport`. |
| PDF-027 order | 11 PDF-027 | Group order of Export ALL comes from F2's `SavedListOrder.allEntries` (REPO-136: culture comparison of the lower-cased name, ungrouped last, stable) — the same order the Windows `OrderBy` produces; the spec's "code-point" remark only concerns the `￿` sentinel, which is not used. |
| checklist lock | 11 PDF-010 | Checklist-only exports are not lock-checked (parity; unreachable while gated). |
| KWN + orphans | 11 §3.2 rules 7 + widow control, §7.16 #6 | A KeepWithNext chain reserves the lines the next paragraph's orphan control needs (2, or all of a ≤ 3-line paragraph), so a heading is never left alone at a page bottom while its paragraph moves on. |
| save-panel title | 11 PDF-004, PDF-011, PDF-024, §6.2 | The save panel runs as a sheet, which has no title bar, so the Windows dialog title (`Export to PDF`, `Export checklist to PDF` / `to Excel`, `Export saved lists to PDF`) is also set as the panel's message (visible text); additive. |
