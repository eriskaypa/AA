# W-RICH — contract requests

No ARCH §6.7 contract change is requested (every signature is implemented unchanged); one tooling request:

## REQ-W-RICH-01: `check-ownership.sh` does not know `Docs/Progress/<id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §10.6, DECISIONS "Foundation requests" REQ-F1-01
Need: in `owner_of`, map `Docs/Progress/*.md` like `Docs/Requests/*.md` (file basename = owner id).
Why: the lead's REQ-F1-01 ruling makes every wave agent keep `Docs/Progress/<agent-id>.md`; the script reports that
path as "unowned", so the gate's last step fails on exactly this one file for every wave branch.
Workaround in place: none possible inside W-RICH's paths; `Scripts/check-ownership.sh --no-paths` (checks 2–4) and
the path check minus this file are green. Every other changed path is W-RICH's.

Additive public API in `Sources/AACore/RichText/` (ARCH §12.2 allows it; consumers may rely on it after merge):

| API | For | Purpose |
|---|---|---|
| `XamlReader.destinationContext(in:at:base:)` | W-CONT (paste, insert table / hyperlink) | CONT-161: the caret paragraph's computed character context as a `XamlContext` for `readFragment`. |
| `XamlReader.typingAttributes(for:)` | W-CONT, W-SIRE | XD.2.8: typing attributes of an empty or cleared body (the root context's projection). |
| `LockRules.isLocked(_:at:)`, `hasAnyLock(_:)`, `lock(_:range:)`, `unlock(_:range:)` | W-CONT | CONT-060/061/065 data effects (inline, inline-ancestor and block sentinels; whole-stretch unlock). |
| `RichListFormatter.indentStep` | W-CONT | 05 §3.2 `IndentStep` (24). |
| `XamlWriter.s1RootAttributes(_:)` | W-SIRE, W-GOLD | The canonical S-1 root for a context. |
| `XamlDocument.parent(of:)`, `children(of:)`, `nearest(_:from:)`, `enclosingParagraph(of:)`, `enclosingHyperlink(of:)`, `sourceText(of:)`, `allNodeIDs` | W-PDF | CONT-152 navigation. |
| `XamlStyleResolver.document`, `.context` | W-PDF | The resolved document and its context. |
| `XamlValues` (parsers, canonical tokens, `same()` helpers, `isSentinel`) | W-PDF, W-SIRE | XD.2.2 grammars. |
| `HTMLToXAML.normaliseColor`, `parseLengthPx`, `mapAlign`, `formatSize` | tests, W-CONT | 05 §3.3 rules 8, 11–13. |
| `XamlParagraphBlock`, `XamlContainerBlock`, `XamlPreservedAttachment` | W-CONT | Display classes for paragraph/container blocks and opaque content. |

Integration notes for W-CONT (no change to any contract):
* Route Return, Tab/⇧Tab and Backspace through `RichListFormatter.handleReturn` / `handleTab` / `handleBackspaceAtItemStart` (nil = default behaviour); each call replaces the storage content inside one `beginEditing`/`endEditing`, so snapshot the storage for the undo group before calling.
* Keep `linkTextAttributes` free of `.foregroundColor` (CONT-167); the link colour is baked into `.foregroundColor` with `.aaLinkStyled`.
