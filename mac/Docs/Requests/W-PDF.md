# W-PDF — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-PDF-01: `check-ownership.sh` must own `Docs/Progress/<id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §12.2; DECISIONS "Foundation requests" REQ-F1-01
Need: in `owner_of`, map `Docs/Progress/<id>.md` to `<id>` exactly like `Docs/Requests/<id>.md` and
`Docs/Deviations/<id>.md`.
Why: the lead's ruling REQ-F1-01 tells every wave agent to keep `Docs/Progress/<agent-id>.md`; the script reports it
as "unowned path (not in OWNERSHIP.md §2)", so check 1/4 fails on that single path (all other checks pass).
Workaround in place: `Docs/Progress/W-PDF.md` is committed as ruled; nothing else is affected.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)

## REQ-W-PDF-02: confirm two XamlDOM shapes the PDF reads (W-RICH)
Target: `Sources/AACore/RichText/XamlDOM.swift` (owner W-RICH) — ARCHITECTURE.md §6.7, 05 CONT-152…154
Need: (1) the `TableColumn` nodes of `<Table.Columns>` appear in the owning `Table`'s `children` (kind `.tableColumn`),
with `local.width` = absolute px or NaN/nil; (2) a `Run`'s text is in `XamlNode.text` (or in `.text` children);
(3) a `Background` given as a property element (`<Run.Background><SolidColorBrush …/>`) is reflected in
`local.background` or in `propertyElements[…].brush`.
Why: `PdfRichText` (11 §3.5.8–3.5.10, PDF-064) needs column widths, run text and solid backgrounds; the shapes are
implied by CONT-152…154 but not spelled out in §6.7.
Workaround in place: `PdfRichText` reads all three forms (children of kind `.tableColumn`; `text` then `.text`
children; `local.background` then the `Background` property element). If columns live elsewhere, widths fall back to
the even 16 cm split (structure and text unaffected).

Resolution: applied — confirmed and pinned by `XamlDOMTests.pdfConsumerShapes`: TableColumn nodes are children of their Table with `local.width` in px (nil for `*`), run text is on the Run or its `.text` children, a `<Run.Background>` brush is reflected; PdfRichText's fallbacks stay harmless (99e4b14)
