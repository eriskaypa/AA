# W-CONT — deviations and P2 fixes

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`. Stored data stays
readable by the Windows build with the same meaning in every row.

## P2 defect fixes

| ID | Spec ref | Fix |
|---|---|---|
| 05 D-1 | CONT-007, §6.10 | A legacy `enc:` body that the unlocked session cannot decrypt (master password, other machine, changed salt) keeps its ciphertext and is shown withheld with a banner; Windows replaced it by `""` and saved. |
| 05 D-2 | CONT-011 | The editor's own undo manager is cleared on every load; Undo after switching items can no longer pour the previous item's text into the current one. |
| 05 D-3 | CONT-008, §6.12 | One editable editor per container: the newest binding wins, older editors flush, turn read-only with a banner and reload when it closes; external changes to `RichTextXaml` (modal editors, Flash Sync apply) reload an editor that has no pending edit. |
| 05 D-4 / K-5 | CONT-063, CONT-066, 03 SHELL-524, SHELL-689 | The lock gate sits in `shouldChangeTextInRanges`: typing, IME, Backspace/Delete, word deletes, cut, paste, drag-move, spelling corrections, Services, dictation, find-and-replace and text undo/redo are all filtered with the §3.1 geometry. Highlight and Clear formatting keep the sentinel on locked runs. Non-editing shortcuts (⌘S, ⌘1…, ⌘N) are never swallowed. Lock/unlock stay undoable (parity). |
| CONT-006 | §6.7 | A withheld note (locked or undecryptable legacy body, unparseable XAML, or no rich-text engine in the build) is read-only with an inline banner instead of "typeable but never saved". Without the real engine (or with a placeholder parse) this includes blank and readable notes, so nothing is ever typed into a note that cannot be saved. The legacy-locked banner offers **Unlock…** (the CONT-062 gate) and reloads. |
| — | §6.4, §4.3.7 rule 6, XD.3 | Typed, plain-pasted and link text never inherits `.aaListMarker`, `.aaInRunNewline`, `.aaPreservedXaml` or an attachment from the neighbouring run; right after a list marker the item's first character supplies the typing attributes. Otherwise text typed at the start of an item would be tagged as marker text and dropped by the writer. |
| CONT-021 overflow | 05 §7.3, BUILD-145 B5 | Insert table: oversized numbers clamp (`99999999999x2` → 50×2) and non-ASCII digits are "no match" → 3×3, where Windows threw. Typed font sizes are capped at 1 638 (WPF's `MaxFontPoint`) instead of crashing above ≈35 791. |
| CONT-043 NaN | §3.1 `ChangeIndent` | A paragraph whose left margin is Auto/NaN indents from 0 (Windows' `Math.Max(0, NaN)` left it stuck). |
| — | §6.7 | `RichTextXaml` is assigned (and the store marked dirty) only when the serialised string changed and the document differs from what was loaded; untouched notes are never rewritten (Windows called `MarkDirty` on every tick). |
| — | §6.12 | Typing next to locked text never extends the lock (the sentinel is removed from the typing attributes); typing at the end of a link does not extend the link. Boundaries stay editable exactly as §3.1 says. |

## Sanctioned decisions and Mac refinements applied

| ID | Spec ref | Behaviour |
|---|---|---|
| K-3 | CONT-024 | Strikethrough and underline toggle independently (WPF strike replaced the underline). Stored format unchanged. |
| K-7 | CONT-022 | Selecting text never stamps family/size onto runs. |
| K-13 | CONT-035 | Pasted transparent backgrounds become "no colour". |
| K-14 | CONT-031, BUILD-146 | Insert hyperlink uses its own sheet: title `Insert hyperlink`, label `URL:`, initial `https://`, Insert disabled until the URL parses (every rejected input was a silent no-op on Windows); an empty selection inserts the normalised URL at the caret (Windows appended it at the end of the paragraph). A caret inside an existing link edits that link (Update). |
| K-15 | CONT-032 | Insert table goes after the caret's block — the whole list when the caret is in a list, the whole table when it is in a table, else the caret's paragraph — and an ordinary paragraph is added after the table when nothing (or another table) follows. The prompt is the shared `TextPromptSheet` (B5: never validating). The format bar adds a hover grid (up to 8×10) plus **Custom Size…** (the B5 prompt). |
| K-16 | CONT-021 | A typed font size applies on Return or when the field loses focus, not per keystroke; leaving the box with the value it already showed applies nothing (K-7). The size field shows at most two decimals (display only). |
| CONT-020 | XD.5 | The family control shows the stored token; a family that is not installed here is listed under "Stored in this note (shown with a substitute)". Picking a family (bar or Font panel) replaces `.aaFontFamilyName`; a weight/style change drops the original weight/style tokens. |
| CONT-022 | §6.3 | The bar also reflects bold, italic, underline, strike, alignment and list state. |
| CONT-025/026 | §6.3, 03 SHELL-608/609 | Colour pop-overs replace the WinForms dialog: text colours (Automatic = `#FF1A1A1A` ink, theme and standard rows, More Colors… = system panel); highlights (the six router swatches plus grey and coral, No Highlight, More Colors…). `#FFE699` is never offered; picking it in the system panel still creates a lock (data semantics). |
| CONT-030 step | 03 SHELL-519, T-KB-28 | Format ▸ Bigger / Smaller (⌘+ / ⌘−) step every run by WPF's `OneFontPoint` (0.75), bounded 0.75…1 638 (WPF internal: confirm with a fixture). |
| CONT-030 baseline | 03 SHELL-607 | Superscript / Subscript / Use Default set (not toggle) `Typography.Variants`. |
| CONT-030 ⇧↩ / ⌃↩ | 03 SHELL-681 | ⇧↩ and ⌃↩ insert a line break (U+2028). |
| CONT-031 | 03 SHELL-678 | ⌘-click opens a link; a plain click only places the caret. Context menu adds Open Link, Copy Link, Edit Link…, Remove Link. |
| CONT-033 | §6.8 | The right-click menu keeps the Windows items (every suggestion in bold, `(no spelling suggestions)`, `(locked — can't correct)`, Cut, Copy, Paste, `Paste text only` with ⌥⇧⌘V, Select All); Windows' "Ignore All" is the Mac's **Ignore Spelling**, also offered on a locked word (§6.8; Windows hid it there). |
| CONT-020…061 | §6.3 | The format bar keeps the Windows toolbar order (ContainerEditor.xaml:21-55) in rounded groups: font + size · B I U S · colour, highlight · alignment · bullets, numbering, indent, outdent · insert saved list, move up, move down · undo, redo · link, table, clear · lock, unlock — then the Mac additions find and zoom. The family menu starts with **Show Fonts… (⌘T)**. When the pane is too narrow for one row the bar folds instead of wrapping (§6.3 "overflow Menu when narrow"): first alignment and lists become pop-up menus, then saved list / move, lock / unlock and find / zoom move into a trailing `ellipsis.circle` menu, then undo / redo and link / table / clear too; only a pane too narrow for that wraps. Folded commands keep their Format-menu names (Align Left, Center, Align Right, Justify, Bulleted List, Numbered List, Indent, Outdent, Saved List…, Move Up, Move Down, Lock Highlighted Text…, Unlock Highlighted Text…, Link…, Table…, Clear Formatting, Find in Note…, Zoom) and their tooltips. |
| CONT-001 | §6.2, V-DESIGN 9 | The 260 pt file-bank height is the default only: on a short pane the bank gives way until the paper (below the format bar and banners) has 200 pt; the bank never drops below 110 pt. The #FCFCFC paper is presented as a page — inset 8 pt in the notes pane, radius 6, 1-pt `AAColor.border`, a soft shadow in dark mode — never an edge-to-edge slab. |
| CONT-034 | 03 §6.5.1 | Paste text only is also Edit ▸ Paste and Match Style (⌥⇧⌘V); the inserted text never carries a lock or a link from the destination. |
| CONT-036/038 | DECISIONS 05, §6.6 | Pasted / dropped images go to the file bank as copies (`AttachmentStore.importData` → `FileBankOperations.addImported`) with a short inline notice; Finder files dropped or pasted onto the text go to the file bank (none = copy; ⇧ or ⌥⌘ = link in place, SHELL-679). Foreign RTF is reduced to the storable subset (fonts with family tokens, sizes, colours, B/I/U/S, links, baseline, paragraph styles incl. lists and tables). |
| CONT-036 | §6.6 | Copy writes our own `com.eriskay.aa.xaml` type (from the real writer) next to RTF and plain text; paste prefers it. |
| CONT-039 | 03 SHELL-517, §6.5.1 | In-note find bar (⌘F when the editor has focus; ⌘G / ⇧⌘G / ⌘E / ⌘J; Replace passes the lock gate) and a per-Mac zoom (75 %…200 %, pinch; `aa.editor.zoom`). Windows had neither; ⇧⌘F still opens the global Search window. |
| CONT-040…046 | §6.5, §7.8 | Tab / ⇧Tab / Backspace at an item start, list toggles, indent/outdent and move run `RichListFormatter.normalise` afterwards (so "Tab on item 2 → nested circle" holds); Return normalises only when the list depth changed. Each is one undo step. |
| CONT-047 | §6.11 | The Insert Saved List sheet says ⌘Z instead of Ctrl+Z. A withheld note keeps the button enabled so the Windows `Nothing inserted` message can still be shown. |
| CONT-064 | §6.8 | Outside the main window the locked hint is a beep plus a short inline notice at the foot of the paper. |
| CONT-001 | §6.1 | The 6 pt splitter is a drag handle with a resize cursor; minimum heights keep both panes usable; the split is not persisted (parity). |
| SHELL-685 | 03 SHELL-514 | ⎋ and ⌘. are passed to the next responder (they close or cancel the surrounding sheet); completion stays on ⌥⎋ / F5. |

## Not applicable / not shipped

None — every W-CONT feature ID is implemented. Behaviour that depends on W-RICH's real reader, writer and list
engine (rendering stored notes, saving, list structure) is exercised by the gated tests and the Stage V checks;
in this worktree the placeholder reader makes every stored note withheld (read-only, never written), by design
(ARCHITECTURE.md §6.7, §11).
