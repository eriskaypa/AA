# W-CONT — progress record (DECISIONS "Foundation requests", REQ-F1-01 ruling)

Card: OWNERSHIP §3 "W-CONT" — the container rich-text editor: `ContainerEditorView` (rich text + embedded
`FileBankView`), `AARichTextView` (TextKit 1, `AARichTextResponder`), load / 400 ms debounce / flush / withhold,
legacy `enc:` migration, one editor per container through `EditorFlushCenter`, identity rebind on reload, the format
bar and every Format-menu action, the find bar, the paste pipeline, list keys, insert link / table / saved list,
the text lock, spelling defaults, ⌘-click links, ⎋ pass-through.

## Counts (OWNERSHIP §4)

| | IDs |
|---|---|
| Assigned | **51** — CONT 44, SHELL 6, BUILD 1 (+ algorithm id BUILD-A18, caller row B5, vector 06 §7.12) |
| Done | **51** + BUILD-A18, B5, 06 §7.12 |
| Remaining | **0** |
| Not applicable | **0** |

Done (where):
* CONT-001…011 — `ContainerEditorView` (layout, splitter, banners), `EditorController` (bind / unbind / flush /
  park / orphan / external-change reload), `EditorSession` (AACore: load order, debounce, flush, withheld guard,
  legacy migration, placeholder-reader guard), `EditorBindingRegistry` (one editable editor per container).
* CONT-020…030 — `EditorFormatBar` (family menu, size field, B/I/U/S, colour pop-overs, alignment, lists, indent,
  move, insert, clear, lock, undo/redo, find, zoom), `EditorFormatting` (AACore: WPF toggle semantics, tokens, step,
  baseline, paragraph alignment/indent, summary), Format menu through `aaValidate` / `aaPerform`.
* CONT-031…034, 036…039 — `EditorInsertLinkSheet` + `EditorLinkRules` (normalisation, insertion), table prompt +
  grid + `EditorTableBuilder`, context menu with spelling, Paste text only / Paste and Match Style, paste & drop
  pipeline (`EditorPaste`, `EditorRichSanitiser`, images and files → file bank), find bar, zoom.
* CONT-040, 041, 043…048 — list commands and keys through `RichListFormatter` (W-RICH) in one undo step each, saved
  list insert (`EditorInsertSavedListSheet`, `EditorSavedListInsert`).
* CONT-060…064, 066 — lock / unlock with the CONT-062 password gate (`dialogs.password`, `PasswordService`), the
  `shouldChangeTextInRanges` gate (`EditorLocking`), throttled hint (status line in the main pane, beep + notice
  elsewhere), D-4 fixes.
* SHELL-678, 680, 681, 682, 685, 689 — `AARichTextView` key and mouse handling.
* BUILD-100, BUILD-A18, 06 §7.12 — insert-saved-list button, dialog and line building.
* BUILD-145 B5 — insert-table prompt caller (`dialogs.prompt`, blank / junk → 3×3).

## Gate and checks

* `swift build -j 3 -Xswiftc -warnings-as-errors` — clean.
* `swift test -j 3 -Xswiftc -warnings-as-errors` — green; W-CONT: 89 tests in 15 suites under
  `Tests/AACoreTests/Editor/` (2 of them gated on W-RICH and skipped here).
* `Scripts/check-placeholders.sh W-CONT` — empty; `EditorContractStatus` = true.
* `Scripts/check-ownership.sh` — passes except `Docs/Progress/W-CONT.md` (unmapped in the script; REQ-W-CONT-01).
* Snapshots (DEBUG hook, both appearances) in the session scratchpad `snapshots/W-CONT/`: editor (wide and narrow),
  withheld, legacy-locked with Unlock…, locked-hint notice, real container + file bank, live self-test (20 AppKit-path
  checks: lock gate, undo, table, link, alignment, Tab, size step, typing after a list marker — all ✓), Insert Saved List, Insert
  hyperlink (valid / invalid), colour pop-overs and table grid. Sheet ids: `w-cont.editor`, `w-cont.editor-narrow`,
  `w-cont.editor-withheld`, `w-cont.editor-legacy`, `w-cont.editor-notice`, `w-cont.container`,
  `w-cont.selftest`, `w-cont.insert-saved-list`, `w-cont.insert-link`, `w-cont.insert-link-invalid`, `w-cont.palettes`;
  fixture data in `Tests/AACoreTests/Fixtures/ui/w-cont/`.

## Independent audit (2026-10-02)

Every assigned ID re-read against 05 / 06 / 03 and the C# (`Views/ContainerEditor.xaml(.cs)`,
`InsertSavedListWindow.xaml.cs`); clean rebuild + gate. Result: 51 / 51 implemented; 0 missing. Fixed during the audit:
* CONT-044 / §6.4 — text typed right after a list marker inherited `.aaListMarker` (the writer drops marker text, so
  it would have vanished on save); typing, plain paste and link insertion now also drop `.aaInRunNewline`,
  `.aaPreservedXaml` and attachments (`EditorFormatting.cleanTypingAttributes`, 2 new tests, self-test check 21).
* CONT-006 — without the real engine a blank note was typeable but never saved; it is now withheld (read-only,
  banner) like every other unsaveable note.
* CONT-008 — a parked editor kept its `EditorFlushCenter` binding, so `holder(of:)` named the wrong editor; parking
  now unbinds the token and unparking rebinds it; re-binding a parked controller to another container unparks it.
* CONT-021 / K-7 — leaving the size box unchanged re-applied the same size (an undo step and a dirty mark); now only a
  changed value applies.
* CONT-033 — every spelling suggestion is listed (was capped at 8).
* CONT-064 / ARCH §8.5 — the inline lock notice draws 🔓 as the `lock.open` symbol.
* CONT-020…061 — format bar order follows the Windows toolbar; Insert Saved List uses the spec symbol
  `text.badge.plus`; the family menu offers Show Fonts…; radio/checkbox labels in the Insert Saved List sheet use the
  system font (native controls); the text-colour bar keeps a visible outline in dark mode.

## Fix pass FIX-W-CONT (verification findings V-05, V-DESIGN) — 4 / 4 fixed

| Finding | Fix | Test / check |
|---|---|---|
| V-05 major — CONT-043 Indent / Outdent on ordinary paragraphs shown but not saved | `EditorFormatting.changeIndent` (AACore) runs W-RICH's `RichListFormatter.indent/outdent` for lists **and** ordinary paragraphs (Margin.Left ± 24 in the paragraph model the writer persists, TextIndent cleared, NaN/Auto = 0), one undo step via `structural`; the empty-document path (`indentTypingAttributes`) also shifts a carried paragraph model. The AppKit-only `indentParagraphs` is gone. | `paragraphIndentPersists` (stored `Margin="0,1,0,1"` → `24,1,0,1`; 0 → 24 → 48 written and reloaded; stored 24 outdents to 0 and stays 0; every touched paragraph; a user-typed paragraph), `indentInListNests`, `indentTypingAttributes`; self-test checks "Indent is persisted", "Indent on a stored paragraph is persisted", "Undo takes the stored indent back" |
| V-05 minor — CONT-032 table written without `Margin="0,4,0,4"`, header bold on the paragraphs | `EditorTableBuilder.makeTable` builds the W-RICH block tree (Table CellSpacing 0 / Margin 0,4,0,4 / Columns → row group → rows → cells with BorderBrush, BorderThickness, Padding and `FontWeight="Bold"` on the row-0 cells) and renders it with the reader's renderer. | `tableWritesS4Shape` (written body contains the S-4 table; no paragraph-level bold; reload → identical XAML, 2 columns, collapsed borders, 4-pt margins); `tableShape` unchanged |
| V-05 polish — item window paper squeezed to ~130 pt by the 260 pt bank | `ContainerEditorView`: the editor minimum is the measured format-bar + banner height + 200 pt of paper (+ the 8 pt page inset); the bank's 260 default and the splitter clamp to it (bank ≥ 110). | snapshots `item-{light,dark}.png` (bar on one row, paper ≈ 400 pt) |
| V-DESIGN polish — format bar wrapping a lone group; edge-to-edge white paper in dark | `EditorFormatBar` folds by density through `ViewThatFits` (full → alignment/lists menus → overflow `ellipsis.circle` menu → + undo/redo, link/table/clear) and wraps only as a last resort; the paper is inset 8 pt, radius 6, 1-pt border, soft dark-mode shadow. | snapshots `tasks-*`, `item-*`, `editor-narrow-*`, `selftest-*` (light + dark): one row in every host |

Also (design rules applied to every W-CONT view): format-bar symbols regular weight, hierarchical; popover
help / counts in `aaMono` with tokens, button labels system; Insert hyperlink sheet in the NSAlert layout (system 13
bold title, 11-pt body, 16 pt margins); Insert saved list sheet with `BuilderSheetHeader`, `aaMono` rows and group
headers with a muted "(N)", Divider + 44 pt footer bar, `AAEmptyState` for "no match" / "no saved lists"; the lock
notice uses `AAColor` tokens; the self-test list uses `aaMono`. `showPreview` (debug previews) clears the undo
history like a load does (D-2) — the self-test's synchronous steps otherwise undid into the previous preview.
Snapshots: `scratchpad/snapshots/fix1-W-CONT/`. Gate green: 1,589 tests.

## Post-merge (Stage V)

* Gated tests `EditorSessionRealEngineTests` (real reader/writer round trip, untouched notes not rewritten).
* 05 §7.3, §7.8 behaviours with the real list engine; T-KB-07/15/21/28/30/31/48/52 manual checks; snapshots of
  every host context (main pane, item window, component / subtask / step editors) — the hosts are W-HIER / W-BUILD
  views.
* Requests REQ-W-CONT-02…05 (W-RICH seams).
