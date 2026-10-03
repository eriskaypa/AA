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
* `swift test -j 3 -Xswiftc -warnings-as-errors` — green; W-CONT: 84 tests in 15 suites under
  `Tests/AACoreTests/Editor/` (2 of them gated on W-RICH and skipped here).
* `Scripts/check-placeholders.sh W-CONT` — empty; `EditorContractStatus` = true.
* `Scripts/check-ownership.sh` — passes except `Docs/Progress/W-CONT.md` (unmapped in the script; REQ-W-CONT-01).
* Snapshots (DEBUG hook, both appearances) in the session scratchpad `snapshots/W-CONT/`: editor (wide and narrow),
  withheld, legacy-locked with Unlock…, locked-hint notice, real container + file bank, Insert Saved List, Insert
  hyperlink (valid / invalid), colour pop-overs and table grid. Sheet ids: `w-cont.editor`, `w-cont.editor-narrow`,
  `w-cont.editor-withheld`, `w-cont.editor-legacy`, `w-cont.editor-notice`, `w-cont.container`,
  `w-cont.insert-saved-list`, `w-cont.insert-link`, `w-cont.insert-link-invalid`, `w-cont.palettes`; fixture data in
  `Tests/AACoreTests/Fixtures/ui/w-cont/`.

## Post-merge (Stage V)

* Gated tests `EditorSessionRealEngineTests` (real reader/writer round trip, untouched notes not rewritten).
* 05 §7.3, §7.8 behaviours with the real list engine; T-KB-07/15/21/28/30/31/48/52 manual checks; snapshots of
  every host context (main pane, item window, component / subtask / step editors) — the hosts are W-HIER / W-BUILD
  views.
* Requests REQ-W-CONT-02…05 (W-RICH seams).
