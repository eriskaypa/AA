# W-CONT — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-CONT-01: map `Docs/Progress/<agent-id>.md` in check-ownership.sh
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §12.2, DECISIONS "Foundation requests" REQ-F1-01
Need: `owner_of` returns the agent id for `Docs/Progress/<id>.md`, like `Docs/Requests/*.md` and `Docs/Deviations/*.md`.
Why: the lead ruling makes `Docs/Progress/W-CONT.md` W-CONT's own record; the script still reports it as an unowned
path, so the ownership step flags exactly this one file (the same request as REQ-W-PERSIST-05, REQ-W-SHELL-03,
REQ-W-QUICK-01, REQ-W-BUILD-02, REQ-W-FILES-02).
Workaround in place: none possible inside W-CONT's paths; the file is committed per the ruling and is the only
path the script flags on this branch.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)

## REQ-W-CONT-02: the typing attributes of new text in an empty note
Target: `Sources/AACore/RichText/XamlReader.swift` (owner W-RICH) — ARCHITECTURE.md §6.7, 05 XD.2.8 ("Typing
attributes. In an empty document, typing attributes are the projection of the root context")
Need: `@MainActor public static func typingAttributes(context: XamlContext) -> [NSAttributedString.Key: Any]` — the
XD.2.8 projection of the root context incl. the paragraph style the reader gives an `Auto`-margin paragraph, so text
typed into an empty note (or after `.empty`) looks exactly like loaded text and the writer treats its spacing as
`Auto` (no explicit `Margin` written).
Why: CONT-003 / 05 §6.2 (new text: Consolas 14, `#FF1A1A1A`, paragraph spacing ≈ one line), §4.3.7 rule 5 (no
Margin unless set by the user).
Workaround in place: `EditorFormatting.defaultTypingAttributes(paragraphStyle:)` + `EditorController
.defaultParagraphStyle(fontSize:)` (spacing `round(1.17 × size)`, left aligned, `.aaFontFamilyName = "Consolas"`,
`.aaXmlLang = "en-us"`). Swap the two call sites in `EditorController` for the reader's function once it exists.

Resolution: applied — W-RICH's `XamlReader.typingAttributes(for: RichTextMetadata)` (the XD.2.8 projection, incl. the Auto-margin paragraph style) replaces `EditorFormatting.defaultTypingAttributes(paragraphStyle:)` + `EditorController.defaultParagraphStyle` at both EditorController call sites; it uses the session's loaded metadata for an empty/cleared note. Signature is W-RICH's `(for:)`, not the requested `(context:)`; DECISIONS amendment (849d2f6)

## REQ-W-CONT-03: unlocking carried element-level sentinels (ListItem / TableCell / Section backgrounds)
Target: `Sources/AACore/RichText/LockRules.swift` (owner W-RICH) — ARCHITECTURE.md §6.7, 05 CONT-061, XD.3 (`block`
lock source: "unlocking a `block` stretch removes the sentinel `Background` from that block's modelled or carried
attributes")
Need: `@MainActor public static func unlock(_ s: NSTextStorage, metadata: inout RichTextMetadata, stretches: [NSRange])`
that clears `.backgroundColor`/`.aaLockSource`/`.aaLocked` on the stretches AND removes the sentinel `Background`
from the carried element attributes (`metadata.elementAttributes[...]`) of every block whose lock covers them.
Why: the editor cannot map a character back to a carried `XamlElementID` (only the reader knows the element ids), so
a lock carried on a `ListItem`, `TableCell` or `Section` would re-appear after save.
Workaround in place: `EditorLocking.unlock(_:stretches:)` clears the run attributes and the sentinel `Background`
in `.aaParagraphAttrs` (Paragraph-level locks round-trip correctly); `EditorLocking.lockedStretches` merges
`LockRules.lockedRanges` so block stretches the reader knows are included.

Resolution: applied — no new LockRules API needed: W-RICH's `LockRules.unlock(_:range:)` already drops the sentinel from the carried ListItem/TableCell/Section attributes on the paragraph's container path (`.richContainerPath`), so `EditorLocking.unlock(_:stretches:)` now delegates to it (nested sentinels peeled across the whole stretch) before its residual sweep; test `unlockCarriedContainerSentinels` fails on the old code (849d2f6)

## REQ-W-CONT-04: list-engine call conventions used by the editor (informational)
Target: `Sources/AACore/RichText/RichListFormatter.swift` (owner W-RICH) — ARCHITECTURE.md §6.7, 05 §3.2, §6.5
Need (behaviour the editor relies on; no signature change):
* every call mutates the storage in place and returns the new selection; `nil` from `handleTab`, `handleReturn`,
  `handleBackspaceAtItemStart`, `moveItem` means "not applicable / nothing moved" and the storage is unchanged;
* `insertList(lines:kind:into:at:)` receives a collapsed range at the END of the live selection (CONT-047 "a live
  selection is untouched") and must place the list after the caret's block in the caret's own collection, add an
  empty paragraph when the list becomes the last block, and return the caret at the start of the block after it;
* `normalise` is idempotent — the editor calls it after `toggleList`, `indent`, `outdent`, `handleTab`,
  `handleBackspaceAtItemStart`, `moveItem` and `insertList`, and after `handleReturn` when the list depth changed;
* the editor wraps each call (plus its `normalise`) in one whole-document undo step, so the engine must not register
  undo itself.
Why: W-CONT and W-RICH are built in parallel; this pins the seam.
Workaround in place: none needed (the placeholder engine returns the documented "no change" values).

Resolution: applied — informational; W-RICH's RichListFormatter follows the stated conventions (nil = no change, idempotent normalise, no undo registration); no signature change (no commit)

## REQ-W-CONT-05: writer acceptance of editor-made structures (informational)
Target: `Sources/AACore/RichText/XamlWriter.swift` (owner W-RICH) — ARCHITECTURE.md §6.7, 05 §4.3.7
Need: the writer maps these editor-created shapes to the 05 §4.3.7 output:
* tables from `EditorTableBuilder` — one `NSTextTable` (`collapsesBorders`, fixed layout, content width 100 %, margin
  4 pt top/bottom = `Margin="0,4,0,4"`), one `NSTextTableBlock` per cell (border 0.6 `#FF9AA0A6` all edges, padding
  3,1,3,1), header-row runs bold → `Table CellSpacing="0"` with N `TableColumn`s without widths and one
  `TableRowGroup`;
* new links — `.link` (URL or String) with `.aaLinkStyled = true`, `.aaUnderlyingForeground`, no `.aaHyperlink` →
  a fresh `<Hyperlink NavigateUri="…">` with no formatting attributes;
* locks — `.backgroundColor` == `#FFFFE699` → `Background="#FFFFE699"` on the run;
* baseline — `.superscript` ±1 plus `.aaInheritedExtras["Typography.Variants"] = "Superscript"/"Subscript"`;
* family changes — `.aaFontFamilyName` holds the picked family name (the token to write).
Why: these are the only structures the editor creates itself; everything else comes from the reader.
Workaround in place: none needed.

Resolution: applied — informational; the writer maps the editor-made shapes (tables, links, locks, baseline, family) as listed — covered by W-RICH writer tests and W-CONT editor tests; no change (no commit)
