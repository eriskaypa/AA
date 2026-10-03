# W-RICH — deviations, P2 fixes and porting decisions

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`.

## Sanctioned decisions applied

| ID | Spec ref | Decision |
|---|---|---|
| RICH-D01 | 05 §8 K-12, §9 Q9, DECISIONS 05 | HTML paste whitespace is cleaned up: a whitespace-only text node never opens a paragraph (no `" "` paragraphs between blocks), whitespace held in a block's not-yet-written paragraph is dropped with it, and a paragraph opened by a block element that a nested block closes before any content (`<div><p>…`) leaves nothing. A truly empty `<p></p>` still gives `<Paragraph />` (a blank line). §7.1 H7 is tested in its cleaned form. |
| RICH-D02 | 05 §8 K-13 | `rgba(…, 0)` (alpha 0) is "no colour" (inherit) instead of black; any other alpha is still ignored. |
| RICH-D03 | 05 §6.4 "Opaque" | The opaque attachment class is `XamlPreservedAttachment` (spec name `PreservedXamlAttachment`, renamed for the ARCH §12.2 prefix rule). |
| RICH-D04 | 05 §4.3.7 rule 11, XD.2.13 | Thicknesses are written in the canonical 4-value form and colours as `#AARRGGBB` (modelled values); carried attributes keep their original tokens. An empty `<Run></Run>` is not content and is not written back (`<Paragraph><Run></Run></Paragraph>` → `<Paragraph />`, same document). |
| RICH-D05 | 05 XD-X8 | `Foreground="{x:Null}"` shows the inherited colour and is not written back (sanctioned in XD.7). |
| RICH-D06 | 05 CONT-169 | N/A — CONT-169 is the reserved upper bound of the XD range; no behaviour (OWNERSHIP §4 note). |

## P2 fixes (data-compatible)

| ID | Spec ref | Fix |
|---|---|---|
| RICH-P01 | 05 §3.3 rule 2 | CF_HTML `StartFragment`/`EndFragment` are honoured as UTF-8 **byte** offsets (Windows used char indices, wrong for non-ASCII headers). |
| RICH-P02 | 05 §3.3 rules 5–9 | HTML attribute values are entity-decoded (`href="a?x=1&amp;y=2"` → `NavigateUri="a?x=1&amp;y=2"` in XAML = `a?x=1&y=2`); HtmlAgilityPack's default left `&amp;` literal, breaking such links. |
| RICH-P03 | 05 §3.2, §3.1 `ChangeIndent` | Indent/outdent treat an `Auto` (NaN) left margin as 0 (`Math.Max(0, NaN)` left the paragraph stuck on Windows); the other sides stay `Auto` (`24,Auto,Auto,Auto`). |
| RICH-P04 | 05 CONT-162 | Recognised attributes with invalid values and markup extensions are never re-emitted, so a Mac save makes such documents loadable again. |
| RICH-P05 | 05 CONT-155, XD-X6 | Every read resolves against a fresh context (no wrapper values leak between containers). |

## Implementation choices (no data effect)

| ID | Spec ref | Choice |
|---|---|---|
| RICH-I01 | 05 §3.3 ("SHOULD use XMLDocument(.documentTidyHTML)") | The HTML is read by a small HtmlAgilityPack-shaped parser (lower-cased names, void elements, raw-text script/style, li/tr/td/th auto-close) instead of Tidy, because Tidy restructures documents (inserts `<p>`, `<tbody>`) and would change the converter's output against the Windows vectors. |
| RICH-I02 | 05 §4.3.1, XD.2.1 step 7 | Without `xml:space="preserve"`: whitespace runs collapse to one space; text at the edges of an inline container and next to `LineBreak` is trimmed; a Run's own text is only collapsed (XD-V6 keeps `Hi `). |
| RICH-I03 | 05 §6.4, XD.2.10 | Paragraph structure lives on the characters (`.richContainerPath`: Section/List/ListItem/Table/RowGroup/Row/Cell descriptors with carried and modelled values; `.richParagraphModel`), so lists and tables survive editing, undo and in-app copy/paste; AppKit-native lists/tables (RTF paste) are reconciled from `textLists`/`textBlocks`. `RichTextMetadata.elementAttributes` is filled as the contract asks. |
| RICH-I04 | 05 §6.4, §6.7 | Every paragraph, including the last, ends with `\n` (the text view shows one insertion line after the last paragraph). An empty "synthetic" paragraph follows a table that ends the document (§6.4 "keep an ordinary paragraph after a table"); it is never written while empty. |
| RICH-I05 | 05 §6.2, 12 §6.5 (display only) | Auto paragraph margins use the font's line height; margins collapse as `max(prevBottom, top)`; an un-normalised List without `Padding` indents 49 pt; a Table without `CellSpacing` uses WPF's 2; paragraph/section/list blocks span the container width. |
| RICH-I06 | 05 XD.2.10 `wanted()` | Text inside a Hyperlink created on the Mac whose colour only inherited is written link-styled (no `Foreground`), as WPF's wrap would leave it; links read from XAML keep their exact colours. |
| RICH-I07 | 05 XD.2.10 Run `BaselineAlignment` | Sub/superscript applied on the Mac (no preserved token) is written as `BaselineAlignment="Subscript"/"Superscript"`; a preserved `Typography.Variants` token is kept while the shift still matches it. |
| RICH-I08 | 05 XD.2.10, XD-W7 | A font picked on the Mac that is the system monospaced / UI substitute is written as `Consolas` / `Segoe UI`; any other Mac family is written by name. |
| RICH-I09 | 05 §3.2, CONT-044 | Tab on the first item of a list (no previous sibling to nest under) is consumed without change; Return on an empty item outdents it (top level → ordinary paragraph); toggling a list on paragraphs next to a list of the same marker style merges with it (WPF `MergeLists`). |
| RICH-I10 | 05 XD.3 lockSource row | `LockRules.unlock` removes a block-level sentinel from the paragraph model or from the container descriptors of every paragraph of that container (whole-element unlock) and drops the gold display block. |
| RICH-I11 | 01 §4.11 invariant 1 | Untouched bodies are protected by `RichTextMetadata.sourceHash` (FNV-1a, stable across launches) in the editor; `write(read(x))` is a byte-for-byte fixed point for Mac-written XAML and semantically equal for Windows-written XAML. |
| RICH-I12 | 05 XD.2.12, CONT-162 | Tolerant display of invalid nesting the spec leaves open: elements inside a `Run`'s content are shown at their source position (`XamlDocument.runChildOffsets`) — recognised inlines as real content inheriting through the Run, anything else as a verbatim chip; a recognised non-row element where `TableRow`s belong becomes an implicit row (and cell) of its own, as `processRow` already did for cells. A rewrite of such a note is loadable and a fixed point (input mutation fuzzing). Unknown elements and misplaced blocks inside inlines stay verbatim chips (§4.3.7 rule 10), so such a note stays `.notLoadable` as it was. |
| RICH-I13 | 05 CONT-162/164/165 | The writer drops an invalid recognised attribute from the loaded root too (root completion then supplies the context value), and a carried `X.Foreground` property element on a block takes part in the CONT-164 cascade like the attribute form (it is dropped from an empty paragraph, whose character properties come from the terminator). |
| RICH-I14 | 05 CONT-036/037, CONT-161, §6.4 | Foreign rich text (RTF / RTFD) is pasted through `XamlReader.insertFragment(attributed:into:replacing:base:)`: it is written to XAML first (AppKit-native `NSTextTable` / `NSTextList` become Table / List with fresh element ids, so a pasted copy never fuses with its source) and inserted on the block tree like an HTML or own-XAML fragment (WPF `TextRange` paste shape: the destination paragraph splits, structures go into its block collection, the paragraph after a pasted table is an ordinary one). A fragment ending with a paragraph mark after ordinary text keeps that break; a single run merges into the destination paragraph. |
