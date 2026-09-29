# 05 — Container: rich-text editor, list engine, text lock & file bank (`CONT-`)

> Porting spec for the Swift/macOS build. It is the contract implementers and verifiers work from: every
> user-visible behaviour of the Windows `ContainerEditor` (and the helpers it owns) is listed with a stable ID,
> every non-trivial algorithm is specified, and every persisted byte is described so data moves between the
> Windows and Mac builds without loss.
>
> **Normative words.** *MUST* = required for parity or data compatibility. *SHOULD* = recommended Mac-native
> refinement that keeps every Windows capability. *Windows quirk* = observed behaviour that is almost certainly
> accidental; each one carries an explicit porting decision in §8.
>
> **Confidence markers.** Behaviour read directly from AA's C# is stated plainly with `file:line`. Behaviour that
> comes from WPF internals (the exact `TextRange.Save` output, built-in `RichTextBox` key bindings, etc.) is marked
> **(WPF internal: confirm with a fixture)**. Capture real fixtures from a Windows install before freezing the
> converter tests (see §9 Q1).

## 0. Sources read

| File (relative to `AA/AA/`) | Lines | Role |
|---|---|---|
| `Views/ContainerEditor.xaml` | 161 | Editor toolbar, rich-text box, splitter, file bank tabs/columns |
| `Views/ContainerEditor.xaml.cs` | 1246 | Everything the editor does: load/persist, formatting, lists, paste, lock, file bank |
| `Services/HtmlToXamlConverter.cs` | 533 | HTML clipboard → FlowDocument XAML (web paste) |
| `Services/ListFormatting.cs` | 226 | List build, normalise (LibreOffice look), move up/down |
| `Views/InsertSavedListWindow.xaml(.cs)` | 74 / 139 | "Insert saved list" picker with preview |
| `Views/ListStylePromptWindow.xaml(.cs)` | 31 / 34 | Bulleted-vs-numbered prompt (saved-list PDF export) |
| `Views/SavedListPicker.cs` | 59 | "Add tasks from a saved list" (Board / Planner) |
| Supporting | | `Models/Models.cs` (`FileKind`, `FileItem`, `Container`, `ChecklistTemplate*`), `Services/DataStore.cs` (`ImportFile`, `ResolveFilePath`, `NormalizeFilePaths`, `ClassifyFile`, JSON options, bundle import rules), `Services/PasswordService.cs`, `Services/AppRepository.cs` (`MarkDirty`, `FlushIfDirty`, `AllItems`, `AllContainers`, `PurgeReferences`), `Services/ChecklistTemplateService.cs` (`CloneContainer`, `ItemToTask`), `Services/SearchService.cs` (`PlainTextFromXaml`), `Services/DataDiff.cs` (`PlainText`), `Services/PdfExporter.cs` (`WriteContainerBody`), `Services/ThemeManager.cs`, `Sire/SireFlow.cs` (`ToContainerXaml`), `Views/PromptWindow.*`, `Views/PasswordWindow.*`, `Views/ItemPickerWindow.*`, `Views/ItemWindow.*`, `Views/ComponentEditorWindow.*`, `Views/SubtaskEditorWindow.*`, `Views/ChecklistStepEditorWindow.*`, `Views/ContainerViewerWindow.*`, `Views/HierarchyPage.xaml(.cs)` (host), `Views/SavedListsPage.xaml.cs` (export prompt caller), `MainWindow.xaml(.cs)` (StatusBlock, shortcuts, password menu), `App.xaml` (theme keys, button styles), `PROGRESS.md`, `Create a Windows WPF C# application.txt`, `mac/Docs/ARCHITECTURE-BRIEF.md`. |

---

## 1. Overview

A **Container** is the "notes + attachments" payload that every entity in AA owns: each Equipment/Area, Task
(and every nested subtask), Procedure, Vessel, equipment Component, procedure checklist step, crew-member
checklist step and saved-list (template) item has exactly one `Container`
(`Models.cs:50-64`). The product brief asks for "a text field with ALL MS-WORD features that are possible" and
"a file bank … similar to that of OneDrive … drag and drop … add file and add folder … cut/copy/and paste", with
files linkable to hierarchy items and containers linkable to each other.

`ContainerEditor` (a WPF `UserControl`) is the single, shared UI for a container. It is a vertical split:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ [Font ▾][Size ▾] | B I U S | A▾ HL | ⯇ ≡ ⯈ ☰ | • 1. →| |← ≔ ⤒ ⤓ | ↶ ↷ |   │  ← toolbar (WrapPanel, wraps)
│ 🔗 ▦ Clr | 🔒 🔓                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│ RichTextBox ("paper": #FCFCFC bg, #1A1A1A text, Consolas 14, spell-check)│  ← row * (fills)
├──────────────────────────── GridSplitter (6 px) ─────────────────────────┤
│ File Bank [Add File][🔗 Link in place][Add Folder][Add Link][Cut][Copy]  │  ← row 260 px (resizable)
│ [Paste][Remove][Open][Open all]   Drag & drop to import — hold Shift …   │
│ ┌All┬Documents┬Images┬Videos┬Links┬Other┐                               │
│ │ Name │ Kind │ Source │ Added │ Path │ (GridView list, drop target)     │
└──────────────────────────────────────────────────────────────────────────┘
```

Where it appears (every host embeds the *same* control, so all features exist everywhere):

| Host | How it is opened | Notes |
|---|---|---|
| Main window → Equipment/Area, Tasks, Procedures, Vessels pages → **Container** tab (`HierarchyPage.xaml:160-170`) | select an item in the sidebar | One long-lived editor instance per page, re-`Load`ed on every selection change. |
| **Item window** (`ItemWindow.xaml`) | right-click item ▸ *Open in new window* | Notes + file bank of one top-level item; footer: "Schedule, subtasks, steps and relationships stay in the main window — this window covers the notes and file bank." |
| **Edit component** window (`ComponentEditorWindow`, 900×700, modal) | Equipment ▸ Components ▸ *Edit…* / double-click | Title `Edit component — {name}`. |
| **Edit subtask** window (`SubtaskEditorWindow`, modal) | Tasks ▸ Subtasks ▸ *Edit…*, Calendar, Planner, Board, Buckets, Ctrl+N, Subtask builder | Title `Edit subtask — {name}`. |
| **Edit checklist step** window (`ChecklistStepEditorWindow`, modal) | Procedure checklist, checklist builder (procedures, crew, saved lists), Calendar, Planner, Buckets, Ctrl+N | Title `Edit checklist step — {title}`. |
| Read-only **View — {title}** window (`ContainerViewerWindow`) | Saved Lists ▸ double-click an item | Not an editor; owned by the hierarchy spec (HIER-136) but consumes this spec's XAML (CONT-098). |

The subsystem also owns: the **HTML→XAML paste converter**, the **list engine** (`ListFormatting`), the
**Insert saved list** dialog, the **List style** prompt used by saved-list PDF export, and the **Add tasks from a
saved list** picker used by Board/Planner.

---

## 2. Feature checklist

IDs are stable; verifiers tick them off one by one. Quoted strings are exact UI text (Windows). Where the Mac
text differs (⌘ for Ctrl, etc.) the Mac string is given in §6.

### 2.1 Hosting & lifecycle

**CONT-001 — Composite layout.** Grid with three rows: editor `*`, splitter 6 px, file bank **260 px**
(`ContainerEditor.xaml:6-10`). Both panes are rounded (radius 4) bordered panels; toolbars use `PanelAlt`
background with a bottom border. The splitter lets the user resize; the size is **not persisted**.

**CONT-002 — Hosts.** See the table in §1. Every host calls `Load(container, repo)` once when it binds and
`FlushPending()` before it unbinds/closes. Modal editor windows flush and then `repo.FlushIfDirty()` on
`Closing` (`ComponentEditorWindow.xaml.cs:27`, `SubtaskEditorWindow.xaml.cs:38`,
`ChecklistStepEditorWindow.xaml.cs:30`). `ItemWindow` flushes in `Window_Closing`, `SetRepo`, `Flush` (all
wrapped in try/catch so a throw can't trap the window open).

**CONT-003 — Load a container** (`ContainerEditor.xaml.cs:385-453`). Order:
1. If not already loading and the 400 ms debounce is running, stop it and persist to the **previous** container.
2. `_loading = true`; remember container + repo; `_contentWithheld = false`.
3. Legacy encrypted body (`RichTextXaml` starts with `enc:`) → CONT-007.
4. `c.IsLocked = false` (always, unconditionally, in memory).
5. Non-blank XAML → `TextRange(ContentStart, ContentEnd).Load(utf8Stream, DataFormats.Xaml)`. On **any**
   exception: clear the document, show the raw XAML string as a single literal paragraph and set
   `_contentWithheld = true` (CONT-006). Blank/whitespace → clear every block (an empty document with **zero**
   blocks).
6. `_hasAnyLock = DocumentContainsLock()` (CONT-065).
7. Refresh all file-bank lists (CONT-080); `_loading = false`.
Nothing is persisted by a load (the `TextChanged` fired during load is ignored while `_loading`). The file-bank
tab selection, the caret position and the undo stack are **not** reset (see CONT-011).

**CONT-004 — Debounced rich-text autosave.** Every `TextChanged` (not while loading) restarts a 400 ms
`DispatcherTimer` (`:52-61`). On tick → `PersistRichText()` (`:455-466`): return if no container or
`_contentWithheld`; serialise the whole document with `TextRange.Save(DataFormats.Xaml)`, decode UTF-8, assign
`container.RichTextXaml`, then `repo?.MarkDirty()` (the repository's own 750 ms debounce then writes `data.json`
off the UI thread). `MarkDirty` is called even when the string did not change. If the editor was loaded without
a repo (`repo == null`) the model is updated but nothing marks it dirty ("repo argument is required, or edits are
dropped", `ItemWindow.xaml.cs:56`).

**CONT-005 — FlushPending contract** (`:469-476`). `FlushPending()` persists immediately **only if the debounce
timer is running** (i.e. there is an unsaved edit), then stops it. Callers: host selection change, detach, relock
(`HierarchyPage`), PDF export, `MainWindow.FlushAllEditors` before Save/Ctrl+S/sync/export/Flash Sync/exit, item
window close/reload, modal editor close, and internally after Lock/Unlock (CONT-060/061). Several actions persist
**immediately** instead of waiting for the debounce: insert saved list, move up/down, insert hyperlink, insert
table (they call `PersistRichText()` directly).

**CONT-006 — Content-withheld guard ("a locked note could be destroyed by a single keystroke" fix).** When what
the editor shows is a stand-in — (a) a legacy `enc:` body the session cannot decrypt (shown as an empty
document), or (b) XAML that failed to parse (shown as literal markup) — `_contentWithheld = true` and
`PersistRichText` refuses to write, so typing can never overwrite the real stored value (the WPF editor has no
read-only mode, so the user *can* type; it is simply never saved). *Insert saved list* refuses with a message box
(CONT-047); *Move up/down* silently does nothing. Other commands run but cannot persist.

**CONT-007 — Legacy whole-body encryption migration** (`:400-420`). Old builds stored the whole body encrypted as
`enc:<base64>` (format §4.6). On load:
* session unlocked (`PasswordService.IsUnlocked`) → `toShow = Decrypt(blob) ?? ""`; **write it back** to
  `container.RichTextXaml` (plaintext), `IsLocked = false`, `MarkDirty()`. ⚠ If decryption fails (wrong key —
  e.g. the session was unlocked with the master password `redemption`, or the password/salt changed since) the
  body is replaced by `""` and saved: **permanent data loss on Windows** (§8 D-1; the Mac MUST NOT do this).
* session locked → show an empty document, keep the ciphertext, `_contentWithheld = true`.
No UI ever *creates* `enc:` bodies any more (`PasswordService.Encrypt` has no callers).

**CONT-008 — One editor per container.** Persisting serialises the whole document with no dirty check, so two
live editors on one container means last-writer-wins. Hosts enforce single binding: when an item is opened in
its own window the main pane flushes and parks its editor on a throw-away `new Container()` and overlays
"This item is open in its own window. Close that window to edit it here again." (`HierarchyPage.xaml.cs:450-476`,
owned by HIER). The Mac MUST keep this invariant globally (§6.12).

**CONT-009 — Disabled / orphaned editor.** When an item window's item disappears after a reload the whole editor
is disabled (`ContainerCtrl.IsEnabled = false`) and the window says "This item is no longer in the loaded data —
nothing typed here will be saved." A password-gated item hides the editor behind the lock overlay (HIER).

**CONT-010 — Editor surface & theming.** `RichTextBox` with `AcceptsTab=True`, `SpellCheck.IsEnabled=True`,
background `EditorBg #FFFCFCFC`, text `EditorFg #FF1A1A1A`, caret `#FF1A1A1A`, no border, font `MainFont`
(Consolas), size **14** (WPF DIP), vertical scrollbar Auto, padding 8, word-wrapped (no horizontal scroll)
(`ContainerEditor.xaml:59-63`, `App.xaml:37-40`). **Dark mode:** the document surface stays light "paper" in
both themes so any colour/highlight the user applied remains readable; toolbar, file bank and chrome follow the
theme (`ThemeManager` palette: dark `Panel #252526`, `PanelAlt #2D2D30`, `Fg #F0F0F0`, `Muted #B0B0B0`,
`BorderB #3F3F46`; light: white panels, black text/borders). No character limit.

**CONT-011 — Undo / redo scope.** The `RichTextBox` keeps one unlimited undo stack per editor instance. Edits
grouped in `BeginChange/EndChange` are single undo units: list toggle + normalise, indent, backspace-outdent,
insert saved list, move up/down, plain-text paste. The stack is **not cleared on `Load`** — **(WPF internal:
confirm)** programmatic document replacement is undoable in WPF, so pressing Undo right after switching items can
revert the load and then autosave the *previous* item's text into the current one (§8 D-2). The Mac MUST clear
undo on every load.

### 2.2 Formatting toolbar & text commands

**CONT-020 — Font family.** Combo, width 160, items = every installed font family name
(`Fonts.SystemFontFamilies` `.Source`), enumerated **once per process** and sorted `OrdinalIgnoreCase`
(`:41-42`). Initial selection `"Consolas"`. On selection change → apply `FontFamily` to the selection (or to the
"springloaded" typing format when the selection is empty) and focus the text box (`:575-580`).

**CONT-021 — Font size.** Editable combo, width 60, items `8 9 10 11 12 14 16 18 20 24 28 32 36 48 72`, initial
`"14"` (`:49-50`). Both picking and typing apply: every text change that parses as a `double` (current culture)
**> 0** is applied immediately to the selection (`:581-587`) — typing "16" applies 1 then 16. Values are WPF DIP
(≈ 1/96 in). No upper bound (WPF throws above ≈35 791; the global crash handler logs it).

**CONT-022 — Toolbar reflects selection** (`:568-574`). On every selection change the font combo shows the
selection's family (if uniform and in the list; otherwise the combo is left/cleared) and the size box shows the
uniform size (`double.ToString()`, e.g. `14`, `13.3333333333333`). Only family and size are reflected — B/I/U/S,
colour, alignment and list buttons show no state. Side effect: because the combos' change handlers re-apply the
value, merely selecting text can stamp an explicit (identical) `FontFamily`/`FontSize` onto the selected runs —
invisible, but it changes the stored XAML (§8 K-7).

**CONT-023 — Bold / Italic / Underline.** Buttons **B** (tooltip `Bold (Ctrl+B)`), *I* (`Italic (Ctrl+I)`),
U̲ (`Underline (Ctrl+U)`) execute WPF `EditingCommands.ToggleBold/ToggleItalic/ToggleUnderline` on the text box
(`:588-590`). WPF semantics **(WPF internal: confirm)**: Bold — if the selection is uniformly Bold → Normal,
otherwise (mixed, normal, semibold…) → Bold; Italic analogous; Underline adds/removes *only* the underline entry
in the decoration collection (strikethrough is kept). Empty selection → affects the next typed text.

**CONT-024 — Strikethrough.** Button S̶ (tooltip `Strikethrough`, no shortcut) (`:591-596`). Reads the selection's
`TextDecorations`; if it is a non-empty collection whose **first** entry is the strikethrough decoration → set
decorations to *none* (this also removes an underline); otherwise set decorations to exactly
`[Strikethrough]` (this **replaces** an underline). So Strike is not independent of Underline on Windows
(§8 K-3).

**CONT-025 — Text colour.** Button `A▾` (tooltip `Text color`) opens the WinForms `ColorDialog` (basic palette +
custom colours, alpha always 255). OK → `Foreground = SolidColorBrush(#FFRRGGBB)` on the selection; Cancel → no
change (`:597-605`).

**CONT-026 — Highlight.** Button `HL` (tooltip `Highlight`) → same dialog → `Background = #FFRRGGBB` on the
selection (inline background, i.e. run highlight) (`:606-614`). There is no "no highlight" choice; removing a
highlight is only possible through *Clear formatting*. Picking exactly **#FFE699** creates a *lock* (sentinel,
CONT-065) — and highlighting locked text overwrites/removes the lock (§2.4 CONT-066).

**CONT-027 — Alignment.** `⯇` `Align left`, `≡` `Align center`, `⯈` `Align right`, `☰` `Justify` → WPF
`EditingCommands.AlignLeft/Center/Right/Justify` → `TextAlignment` on every paragraph the selection touches
(`:615-618`).

**CONT-028 — Clear formatting.** Button `Clr` (tooltip `Clear formatting`) (`:693-703`) on the selection:
FontWeight Normal, FontStyle Normal, TextDecorations none, **Foreground = EditorFg (#FF1A1A1A)** (deliberately the
paper colour, not the theme foreground, so text never turns invisible in dark mode), Background none. It does
**not** reset font family, font size, alignment, indentation or lists. It also removes the lock sentinel
(CONT-066).

**CONT-029 — Undo / Redo buttons.** `↶` `Undo (Ctrl+Z)` → `Rtb.Undo()`, `↷` `Redo (Ctrl+Y)` → `Rtb.Redo()`
(`:691-692`). They bypass the lock filter (CONT-066).

**CONT-030 — Built-in RichTextBox keyboard commands** **(WPF internal: confirm)**. Because the control is a WPF
`RichTextBox`, users also get: Ctrl+B/I/U; Ctrl+L/E/R/J align left/center/right/justify; Ctrl+Shift+L bullets;
Ctrl+Shift+N numbering; Ctrl+T / Ctrl+Shift+T increase/decrease indentation; Ctrl+] / Ctrl+[ increase/decrease
font size by WPF's built-in step;
Ctrl+= subscript, Ctrl+Shift+= superscript (these write `Typography.Variants`, §4.3); Shift+Enter line break;
Enter paragraph break; Ctrl+Backspace / Ctrl+Delete delete word; Ctrl+Z / Ctrl+Y; Ctrl+X/C/V (also Shift+Del /
Ctrl+Ins / Shift+Ins); Ctrl+A; Tab / Shift+Tab (CONT-044). Note: the built-in list/indent/size shortcuts do **not**
run the list normaliser (CONT-042) — only the toolbar buttons do. Keys not handled by the box bubble to the main
window: Ctrl+S save, Ctrl+F global search, Ctrl+N quick work, Ctrl+O quick switcher. Ctrl+R is captured by the box
(align right) so it does **not** open the due-dates window while the editor has focus.

**CONT-031 — Insert hyperlink.** Button `🔗` (tooltip `Insert hyperlink`) (`:704-723`). Prompt window title
`Insert hyperlink`, label `URL:`, initial text `https://` (not owned → not centred on the owner). OK +
`Uri.TryCreate(value, Absolute)` succeeds, else silently nothing (so the untouched `https://` does nothing):
* empty selection → a new `Hyperlink` whose text is `uri.ToString()` (normalised, e.g. `https://example.com` →
  `https://example.com/`) is **appended to the end of the caret's paragraph** (not at the caret);
* non-empty selection → the selection is wrapped in a `Hyperlink` (throws if the selection crosses paragraphs; the
  global handler logs it).
Then persist immediately. In the editable Windows box links are **not clickable** (`IsDocumentEnabled` is false;
the `RequestNavigate` handler attached here is never raised and is not part of the saved XAML). Links are
clickable in the read-only viewer (CONT-098) and in exported PDFs.

**CONT-032 — Insert table.** Button `▦` (tooltip `Insert a table. You can also paste tables directly from Excel,
Word or the web.`) (`:727-768`). Prompt (owned) title `Insert table`, label `Size as rows x columns (e.g. 3x4):`,
initial `3x3`. Parse with `^\s*(\d+)\s*[xX*]\s*(\d+)\s*$`: rows clamp 1…50, cols 1…20; no match → **3×3** (no
error). Builds a `Table` (CellSpacing 0, Margin `0,4,0,4`, *cols* `TableColumn`s, one `TableRowGroup`); every
cell = one empty paragraph, border `#FF9AA0A6` 0.6 px all sides, padding `3,1,3,1`; **row 0 cells are Bold**
(header row). Insert after the caret's paragraph when that paragraph is a top-level block of the document,
otherwise (caret in a list, table cell, nested section, or empty doc) **append at the end of the document**.
Caret moves to the first cell; focus; persist immediately. No trailing paragraph is added after the table.

**CONT-033 — Right-click menu & spelling** (`:81-147`). Right-button-down moves the caret to the clicked point
unless the click is inside the current selection. The menu is rebuilt on every open:
1. If the caret is on a spelling error:
   * caret inside **locked** text → a single disabled item `(locked — can't correct)`;
   * else each suggestion (bold) → corrects the word (re-checks the lock at click time); none →
     disabled `(no spelling suggestions)`; then `Ignore All` (dictionary-only, allowed even on locked text);
   * separator.
2. `Cut`, `Copy`, `Paste` (standard commands, self-enabling), `Paste text only` (gesture text `Ctrl+Shift+V`,
   enabled only when the clipboard holds text, tooltip `Paste the clipboard as plain text, dropping all
   formatting.`), separator, `Select All`.
Spell-check language follows `xml:lang` (default `en-us`).

**CONT-034 — Paste text only** (`:160-168`, `:327-352`, key `Ctrl+Shift+V` `:1058-1063`). Reads
`Clipboard.GetText()` (ignores RTF/HTML/XAML), refuses if the caret/selection touches locked text (hint), then in
**one undo unit**: create a paragraph if the document has zero blocks, `Selection.Text = text` (inherits the
destination's formatting; CR LF / LF become paragraph breaks), collapse the caret after it, focus. Saved by the
normal debounce. Ctrl+Shift+V is intercepted before any lock fast-path so it works in every document.

**CONT-035 — Web/HTML paste conversion** (`:354-383`). A pasting handler runs for every paste (and, in WPF, text
drops): if the clipboard already has `Xaml`, `XamlPackage` or `Rtf` → leave it to WPF. Else if it has `Html` →
`HtmlToXamlConverter.Convert(html)` (§3.3); non-blank result → replace the data with {Xaml: result, UnicodeText:
plain fallback} and force the Xaml format. Any exception → default paste (plain text). CSS is mapped for colour,
background, weight, style, decoration, family, size, alignment only; scripts/styles/meta/link/head/title are
dropped; images are dropped.

**CONT-036 — Native rich paste.** XAML (from another WPF app/AA editor) and RTF (Word, Excel, WordPad, Outlook) are
pasted by WPF's own converters. Pasted lists keep their original look until the next list command normalises the
document (CONT-042). Drag-and-drop *of text* inside the box moves/copies text (WPF default; not lock-filtered).

**CONT-037 — Pasted tables.** Excel/Word tables arrive via RTF as real `Table`s; web tables via the HTML converter
(`EmitTable`, borders `#FF9AA0A6` 0.6, padding `3,1,3,1`, `<th>` bold, `colspan`/`rowspan` kept, nested-table
rows de-duplicated). They copy back out intact.

**CONT-038 — Images / embedded objects.** There is no image insert. Images pasted into the box are not preserved by
the stored format **(WPF internal: `TextRange.Save(DataFormats.Xaml)` writes embedded objects as a placeholder
space or empty container — confirm)**; HTML `<img>` is dropped by the converter. Images belong in the file bank
(Images tab). There are **no thumbnails/previews** anywhere in the Windows file bank (PROGRESS mentions "image
previews", but no such code exists).

**CONT-039 — Find, replace, zoom.** None inside the editor. Ctrl+F opens the app-wide Search window (it searches
container text via `SearchService.PlainTextFromXaml`). No zoom.

### 2.3 Lists ("LibreOffice-like")

**CONT-040 — Bullets.** `•` (tooltip `Bullets`) → WPF `ToggleBullets` then `ListFormatting.Normalise(document)` in
one undo unit (`:619`, `:627-636`). WPF semantics **(confirm)**: paragraphs not in a list become items of a new
list; items of a bulleted list become plain paragraphs; items of a numbered list switch to bullets.

**CONT-041 — Numbering.** `1.` (tooltip `Numbered`) → `ToggleNumbering` + normalise, same shape.

**CONT-042 — List normalisation.** After every toolbar list command, backspace-outdent, move and saved-list insert,
**every list in the document** is re-styled (§3.2): markers by depth — bullets Disc → Circle → Square → repeat;
numbers `1.` → `a.` → `i.` → repeat; each level indented **24 px** (list `Padding 24,0,0,0`); outermost list
margin `0,6,0,6`, nested lists margin 0; every paragraph directly inside a list item margin `0,1,0,1`. A list
nested inside a *numbered* list is forced into the numbered cycle. Not applied after paste or load.

**CONT-043 — Indent / Outdent.** `→|` (tooltip `Indent (Tab at the start of a list item)`), `|←` (tooltip
`Outdent (Shift+Tab at the start of a list item)`) (`:641-663`). Caret inside a list → WPF
`IncreaseIndentation`/`DecreaseIndentation` (nest / un-nest) + normalise. Caret in ordinary text → for every
paragraph the selection touches: `Margin.Left = max(0, Left ± 24)`, `TextIndent = 0` (whole-paragraph indent in
24 px steps, never first-line-only). One undo unit.

**CONT-044 — Native list keys** (deliberately left to WPF) **(confirm)**: Enter in an item → new item at the same
level; Enter on an empty item → leaves the list/outdents; Tab at the start of an item → nest; Shift+Tab → un-nest;
Tab elsewhere → inserts a tab character (`AcceptsTab`).

**CONT-045 — Backspace at the start of a list item** (`:1077-1089`). With an empty selection and the caret at
offset 0 of a paragraph whose parent is a `ListItem` (any paragraph of the item, not only the first): if the caret
is inside locked text → hint; else in one undo unit `DecreaseIndentation` + normalise (outdent one level; at top
level the item becomes an ordinary paragraph). WPF's default (merging into the previous item as a marker-less
paragraph) is suppressed.

**CONT-046 — Move up / down.** `⤒` (tooltip `Move the current list item (or block) up — Ctrl+Alt+Up. Sub-items
move with it.`), `⤓` (`… down — Ctrl+Alt+Down. …`), keys Ctrl+Alt+Up/Down (`:1066-1072`) (`:253-288`):
* no container or content withheld → nothing;
* caret/selection touches locked text → hint;
* the list items the selection touches, if all are siblings of one list → move them as a group one position,
  keeping relative order and carrying nested sub-items; else (caret in ordinary text, or items from different
  lists) → move the **outermost** block containing the caret (a paragraph, a whole list, a table, a section)
  among its siblings;
* at the top/bottom → nothing, silently (no wrap);
* after a move: normalise (numbers renumber), restore the caret to the same offset inside the moved paragraph,
  focus, persist immediately. One undo unit. Nothing is created or deleted — content can only be reordered.

**CONT-047 — Insert saved list (editor command).** `≔` (tooltip `Insert a saved list here as bullets or numbers.
Your existing notes are not changed.`) (`:172-245`):
1. no container or no repo → nothing;
2. content withheld → message box, title `Nothing inserted`, Information icon, text `This note can't be edited
   right now because its saved content isn't loaded — unlock it first (Tools ▸ Set / change password, then
   reopen).`;
3. caret/selection touches locked text → hint;
4. open the dialog (CONT-048); cancelled or zero lines → nothing;
5. stop the autosave timer; in one undo unit insert the list **into the caret's own block collection, after the
   block the caret is in** (inside a table cell → in the cell; inside a list item → as a nested list of that item;
   empty document → a paragraph is created first). A live selection is untouched — the list goes after the
   selection's end. If the list becomes the last block of its collection, an empty paragraph is added after it.
   Normalise; caret to the start of the block after the list; focus;
6. persist immediately. One Ctrl+Z removes the whole insertion.

**CONT-048 — "Insert saved list" dialog** (`InsertSavedListWindow`, 760×560, centred on owner):
* header `Insert a saved list` (bold 15, accent), sub-text `The list is added where your cursor is. Nothing
  already in the note is changed, and one Ctrl+Z removes the whole list again.`;
* left (290 px): search box (placeholder `Search saved lists...`) over a list of saved lists **grouped by List
  Group** (header = group name, or `Ungrouped`), in the **arranged order** of `Data.ChecklistTemplates` (not
  alphabetical); group headers appear in order of first occurrence; row text = `ChecklistTemplate.Display` =
  `"{name or (unnamed)}  ·  {n} item{s}"`;
* search (trimmed, current-culture case-insensitive) matches the list name **or any item title**; results re-bind
  and the first row is selected;
* right: radios `• Bullets` (default, every time) / `1. Numbered`; check box `Include each item's duration`
  (tooltip `Appends e.g. (60 min) to each line.`); `Preview` (Consolas, scrollable) shows `• line` or
  `1. line` per line, or `(this saved list has no items)`;
* footer note: `{n} line{s} will be inserted.` plus, when applicable, ` Not carried over: {k} item has notes /
  {k} items have notes, {f} attached file{s}.` (item notes and files are **not** inserted — deliberate);
* buttons `Cancel` (Esc) and **`Insert`** (default/Enter, bold). Insert disabled when the selected list yields no
  lines;
* no saved lists at all → footer `You have no saved lists yet. Build one in the Saved Lists tab first.`, Insert and
  search disabled.
Lines = item titles trimmed, blanks dropped; with durations each line becomes `"{title}  ({minutes} min)"` (two
spaces) when minutes > 0.

**CONT-049 — List style prompt** (`ListStylePromptWindow`, 430 wide, auto height, not resizable). Used by Saved
Lists PDF export (all three export buttons). Prompt text (default `How should the items be listed?`; the caller
passes `How should the items in this list be shown in the PDF?` or `How should the items in these {n} lists be
shown in the PDF?`). Radios: **`• Bulleted`** — `Every item marked with a bullet. Best when the order does not
matter.` (preselected **every time**, never remembered) and **`1. Numbered`** — `Items numbered in order. Best for
steps that run in sequence.` Buttons `Cancel` / **`Continue`** (default). Returns `true`=numbered, `false`=bullets,
`null`=cancelled (cancelling aborts the export before the file dialog).

**CONT-050 — Add tasks from a saved list** (`SavedListPicker.PickAndAddTasks`, used by Board `+ From saved list`
and Planner `+ Saved list`): no saved lists → info box `You have no saved lists yet. Build one in the Saved Lists
tab first.` (title `Add from saved list`); lists without items → `Your saved lists don't have any items yet.`
Otherwise a multi-select searchable picker, prompt `Search saved lists — pick items to add as tasks`, one row per
item of every list: `"{list name or (unnamed list)}  ›  {item title or (untitled)}"` + `"   · schedulable"` when
the item is a job. Each picked item becomes a new top-level Task via `ItemToTask` (title→Name, duration, IsJob,
deep-cloned container, Status To Do; no deadline/range/done) appended to `Data.Tasks`; if any were created →
synchronous `repo.Save()`. Returns the created tasks. The saved lists are untouched.

### 2.4 Text lock (protect highlighted text)

**CONT-060 — Lock highlighted text.** `🔒` (tooltip `Lock the highlighted text (password-protected; still visible
everywhere, just can't be edited).`) (`:1169-1185`). Empty selection → info box title `Lock highlighted text`,
text `Highlight the text you want to protect from editing, then click 🔒.` Otherwise password gate (CONT-062) →
apply the sentinel background `#FFFFE699` to the selection (runs are split as needed) → `_hasAnyLock = true` →
flush immediately.

**CONT-061 — Unlock highlighted text.** `🔓` (tooltip `Unlock the highlighted text (requires app password).`)
(`:1187-1217`). Empty selection → info box title `Unlock highlighted text`, text `Highlight the locked text you
want to unlock, then click 🔓.` Otherwise gate → walk the selection; for every position whose ancestor element
carries the sentinel, clear that element's background (once per element). Granularity is the **whole element**
carrying the sentinel, so unlocking part of a locked run unlocks the whole run. Other backgrounds are untouched.
Flush; recompute `_hasAnyLock`.

**CONT-062 — App password gate** (`EnsureUnlocked`, `:1231-1245`). Session already unlocked → proceed. No app
password yet → `Set app password` dialog (two fields, ≥ 4 chars, must match; messages `Password cannot be
empty.`, `Password must be at least 4 characters.`, `Passwords do not match.`; prompt `Pick a password (used to
lock/unlock every container).\nConfirm it on the second line.`) → `SetPassword` (session unlocked) → save
hash+salt to `settings.json` → proceed. Otherwise `Unlock` dialog (prompt `Enter the app password to unlock locked
containers:`; wrong → inline `Wrong password.`; the master password `redemption` always works) → proceed.
Cancel → abort. The session stays unlocked until **Tools ▸ Lock now** or app exit.

**CONT-063 — Edit filtering.** Locked text is **always** uneditable — the password only gates adding/removing
locks (PROGRESS's older wording "unless the session is unlocked" is outdated; code wins). Filters (all skipped
when `_hasAnyLock` is false):
* typing (`PreviewTextInput`): empty selection → blocked when the caret is *inside* locked text (both neighbours
  locked); selection → blocked when it overlaps locked text;
* Backspace (empty selection): blocked when the character to the left is locked; Delete: when the character to the
  right is locked;
* any other "modifying" key while the selection overlaps locked text (every key except arrows, Home/End, PgUp/PgDn,
  Tab, Shift/Ctrl/Alt, CapsLock, Esc, and Ctrl+C/A/F/Insert) — this also swallows Ctrl+S/N/O/Z/B… (§8 K-5);
* commands Paste, Cut, Delete, Backspace, DeleteNextWord, DeletePreviousWord: empty selection → caret inside
  locked; selection → overlaps locked;
* paste-text-only, insert saved list, move up/down, backspace-outdent, spelling correction: same rule.
Boundaries never count: inserting right before or after locked text is allowed.

**CONT-064 — Locked hint** (`:1157-1167`). Throttled to once per 1.5 s. If the hosting window has a `StatusBlock`
(only the main window does) → status text `🔒 Highlighted/touched text is locked. Select it and click 🔓 to
unlock.`; otherwise (item/component/subtask/step windows) → system beep.

**CONT-065 — Lock sentinel & scan.** The lock is purely the background colour **#FFFFE699** (A=255, R=255, G=230,
B=153, "pale gold") on any element (Run, Span, Hyperlink, Paragraph, ListItem, TableCell, Section…); a character
is locked when **any ancestor** element carries exactly that colour (`:989-1001`). It round-trips through the
stored XAML, exports, bundles, Flash Sync and copy/paste with no side storage. `DocumentContainsLock()` walks the
document once after load (the old substring test for `FFE699` false-positived on gold colours).

**CONT-066 — Lock gaps (documented, Windows).** Not filtered: toolbar formatting (bold, colour, font…), **Highlight**
(overwrites the sentinel → unlocks without the password), **Clear formatting** (removes it), Undo/Redo buttons and
Ctrl+Z (can undo a lock or re-insert text), Enter inside locked text (may split it), drag-moving selected text,
insert hyperlink/table/list toggles. See §8 D-4 for the Mac decision.

### 2.5 File bank

**CONT-080 — Panel, tabs & columns.** Header: `File Bank` (bold) then buttons (tooltips in parentheses):
`Add File` (`Import a COPY of the file into the app's data folder.`), **`🔗 Link in place`** (accent/bold;
`Link a file/folder at its ORIGINAL location (e.g. on a network drive) without copying. Opening it edits the live
file.`), `Add Folder` (`Import copies of every file inside a folder.`), `Add Link` (`Add a web link (URL).`),
`Cut`, `Copy`, `Paste`, `Remove`, `Open`, **`Open all`** (accent/bold; `Open every file shown in the current tab
at once — ideal for launching a whole routine.`), then muted hint `Drag & drop to import — hold Shift to link in
place`. Tabs (all lists are drop targets and open on double-click):

| Tab | Content filter | Columns (width px) | Selection |
|---|---|---|---|
| All | every file (live collection) | Name 280 · Kind 80 · Source 64 · Added 150 · Path 500 | Extended (multi) |
| Documents | `Kind == Document` | Name 280 · Added 160 · Path 500 | WPF default |
| Images | `Kind == Image` | Name 280 · Added 160 | WPF default |
| Videos | `Kind == Video` | Name 280 · Added 160 | WPF default |
| Links | `IsLink` (any kind) | Name 280 · URL 500 (= Path) | WPF default |
| Other | `Kind == Other && !IsLink` (incl. linked folders) | Name 280 · Path 500 | WPF default |

`Kind` shows the enum name (`Document`, `Image`, `Video`, `Link`, `Other`); `Source` shows CONT-094; `Added`
shows `DateTime` in WPF binding format — **en-US** regardless of system locale, e.g. `9/29/2026 2:03:12 PM`.
Filtered tabs are snapshots rebuilt by every file-bank action. Every list has the context menu `Open`,
`Open containing folder`, `Rename...`, `Link to items...`, separator, `Remove`. No sorting, no search, no empty-
state text, no keyboard shortcuts (no Delete/F2/Ctrl+C on the list). Items appear in collection (insertion) order.

**CONT-081 — Classification** (`DataStore.ClassifyFile`, `DataStore.cs:653-663`), by lower-cased extension:
Document `.pdf .docx .doc .xlsx .xls .pptx .ppt .txt .rtf`; Image `.jpg .jpeg .png .tif .tiff .bmp .heic .gif`;
Video `.mov .mp4 .wmv .avi .mkv .m4v .webm`; everything else Other. Web links are `Link`; in-place folders
`Other`. The kind is stored at add time and never re-derived (rename doesn't reclassify).

**CONT-082 — Add File.** Multi-select open dialog (default title) → for each file: copy into `files/` (§4.2) and
add `{Name = original file name, Path = "files/{guid32}_{name}", Kind = classify, Added = now}`. If the copy
throws, the entry is added anyway with `Path = original absolute path` and `LinkInPlace = false` (labelled
`Copy`, §8 K-9). Mark dirty, refresh.

**CONT-083 — Add Folder.** Folder browser → import **every file in the folder and all sub-folders** as separate
copies, flattened (folder structure not kept; hidden/system files included; empty folders ignored). Mark dirty,
refresh. An access error mid-way stops the import (already-copied files stay; logged by the crash handler).

**CONT-084 — Link in place (button).** Multi-select open dialog titled `Link file(s) in place (the originals are
referenced, not copied)` (files only — folders only via Shift-drop) → each becomes `{Name = file name, Path =
original absolute/UNC path, Kind = classify, LinkInPlace = true, Added = now}`. Never copied, never rewritten by
path normalisation; opening edits the live file.

**CONT-085 — Drag & drop in.** Accepts OS file drops (effect Copy; anything else refused) on any tab's list — the
tab doesn't filter what is accepted (a PDF dropped on *Images* lands in Documents). **Plain drop** → CONT-082 for
files and CONT-083 recursion for folders. **Shift held at drop** → link in place: files as CONT-084; a folder
becomes a **single** entry `{Name = "{folder name}  (folder)"` (two spaces), `Path = folder path`,
`Kind = Other`, `LinkInPlace = true}` that opens in Explorer. No drag-*out* support.

**CONT-086 — Add Link.** Prompt (not owned) title `Add link`, label `URL:`, initial `https://`; any non-whitespace
value (unvalidated, untrimmed — even the bare `https://`) → `{Name = value, Path = value, Kind = Link,
IsLink = true, Added = now}`.

**CONT-087 — Cut / Copy / Paste.** A **private, per-editor-instance** clipboard (not the OS clipboard), acting on
the current tab's selection (`:913-948`):
* `Copy` → clipboard = selected entries, cut mode off. `Cut` → same, cut mode on. With nothing selected either
  button **empties** the clipboard.
* `Paste` (clipboard non-empty): cut mode → add the **same entry object** to this container unless already
  present — the entry is **not removed from its source** (both containers now share it; same `Id`); copy mode →
  add a new entry `{new Id, same Name/Path/Kind/IsLink/LinkInPlace, Added = now}` — `LinkedItemIds` are **not**
  copied, the physical file is **not** duplicated (both entries point at the same `files/…`). Cut mode switches
  off after one paste (a second paste makes copies). Mark dirty, refresh.
* Because the main pane keeps one editor across item selections, cut/copy in item A then paste in item B works
  there; it does not work across different windows.

**CONT-088 — Remove.** Removes the selected entries of the current tab from the container. **No confirmation**,
no undo, the physical file in `files/` is **not** deleted (orphan until a bundle import sweeps it).

**CONT-089 — Open.** `Open` button, context `Open`, or double-click anywhere in a list → opens the (first) selected
entry: target = `Path` for links, else `ResolveFilePath(Path)`; a non-link target that is neither an existing file
nor folder → message `Not found:\n{target}` (title `Open failed`); otherwise shell-open with the default app
(files), Explorer (folders), default browser (URLs). Exception → message `{error}` titled `Open failed`.

**CONT-090 — Open all.** Opens **every entry shown in the current tab** (not the selection). None → nothing. More
than **15** → confirm `Open all {n} items in this tab now?` (title `Open all`, Yes/No, question icon). Each entry
opens as CONT-089 (errors reported per entry).

**CONT-091 — Open containing folder.** Link entries → open the URL (same as Open). Others: resolve the path; if it
is an existing **file** → `explorer.exe /select,"{path}"` (Explorer opens with the file selected); else message
`File not found:\n{path}` (title `Open folder`) — this includes in-place **folder** entries (§8 K-10). Exception →
`{error}` titled `Open folder failed`.

**CONT-092 — Rename.** Prompt (owned) title `Rename`, label `New name:`, initial = current name → any
non-whitespace value (untrimmed) replaces the **display name only** (the file on disk is not renamed, kind not
re-derived). Mark dirty, refresh.

**CONT-093 — Link file to hierarchy items.** Context `Link to items...` → multi-select searchable picker
`Link '{file name}' to items` over every **top-level** Equipment/Area, Task, Procedure and Vessel (no subtasks,
steps or components), sorted by kind (Equipment, Task, Procedure, Vessel) then name (case-insensitive), row text
`[{Kind}] {Name}` (enum names: `[Equipment]`, not `Equipment/Area`), pre-selecting the current links. OK replaces
`LinkedItemIds` with the picked ids (in selection order) and marks dirty; ids that aren't top-level items are
dropped. Links are **not displayed anywhere else** in the Windows UI (no column, no backlink); they are cleaned
when an item is deleted (`AppRepository.PurgeReferences`) and copied by container cloning. Picker quirk: filtering
the search list drops the selection of rows hidden by the filter (§8 K-11).

**CONT-094 — Source label** (`FileItem.SourceLabel`, `[JsonIgnore]`): `Web link` if `IsLink`, else `Live` if
`LinkInPlace`, else `Copy`.

**CONT-095 — Shared containers.** `Container.SharedWithContainerIds` (the brief's "accessible to other containers
IF explicitly linked") exists in the model and is preserved/copied, but **no UI reads or writes it**. MUST
round-trip untouched.

**CONT-096 — Thumbnails, icons, drag-out, Quick Look.** None on Windows (plain text rows). Mac additions in §6.9.

**CONT-097 — Attachment paths.** Imported copies are stored **relative** (`files/{guid}_{name}`) so databases are
portable; in-place links and web links keep their original string verbatim; legacy absolute paths self-heal on
every load/save (§3.6). Missing files only surface when opened.

**CONT-098 — Read-only viewer** (owned by HIER-136, consumes this spec). `View — {title}` window: title, subtitle
(default `Read-only view — click a link to open it. Editing is disabled.`; Saved Lists passes `Saved-list item ·
{list} — read-only. Click a link to open it; double-click a file to open it.`), read-only rich text (hyperlinks
clickable, one class-level handler), files list (Name 260, Kind 80, Source 70, `Path / URL` 380; header `Files —
none` or `Files ({n}) — double-click to open`), buttons `Open all files` (none → `This item has no files.`; > 15 →
`Open all {n} files?`) and `Close`. Blank body → grey `(no notes)`; `enc:` body → grey `(locked content)`;
unparseable → raw text. Missing file → `That file is missing:\n\n{target}`; open error → `Could not
open:\n\n{target}\n\n{error}`.

---

## 3. Logic & algorithms

### 3.1 Editor core (`Views/ContainerEditor.xaml.cs`)

| Function | Lines | Exact behaviour |
|---|---|---|
| ctor | 44-77 | Font list bound (static cache); family `Consolas`, sizes list, `14`; debounce 400 ms → `PersistRichText`; `SelectionChanged → SyncToolbarFromSelection`; `TextChanged → restart debounce unless _loading`; pasting handler; `PreviewKeyDown`, `PreviewTextInput`, preview-executed command filter; custom context menu. |
| `Load(c, repo)` | 385-453 | CONT-003. |
| `PersistRichText()` | 455-466 | CONT-004. |
| `FlushPending()` | 469-476 | CONT-005. |
| `SyncToolbarFromSelection` | 568-574 | CONT-022. |
| `ApplyFontSize` | 583-587 | `double.TryParse(text)` (current culture) and `> 0` → apply. |
| `Strike_Click` | 591-596 | CONT-024. Comparison `cur[0] == TextDecorations.Strikethrough[0]` is a *reference* comparison (WPF internal: a strike loaded from XAML may not compare equal, making "un-strike" re-apply strike — confirm). |
| `RunListCommand(cmd)` | 627-636 | `BeginChange; cmd.Execute; Normalise; EndChange` (normalise must run **after** — WPF's list commands rebuild paragraphs and drop explicit margins). |
| `ChangeIndent(increase)` | 641-663 | CONT-043. Note `Math.Max(0, NaN)` is NaN in .NET: a paragraph whose left margin is `Auto` (NaN) would not move — the Mac MUST treat NaN/Auto as 0. |
| `CaretList()` | 666-675 | Innermost `List` ancestor of the caret paragraph, else null. |
| `SelectedParagraphs()` | 678-690 | Walk context positions from selection start to end, collecting distinct `.Paragraph`s; empty → the caret paragraph. Includes paragraphs inside lists/tables the selection crosses. |
| `SelectedListItems()` | 293-301 | Distinct `ListItem` parents of `SelectedParagraphs()` (paragraph *directly* in an item); if >1 and not all siblings of the first → **empty** (caller falls back to MoveBlock). |
| `OutermostBlock(b)` | 305-310 | Climb while the parent is a `Block` (Section/List/Table…); stops at FlowDocument, ListItem, TableCell. So in a table cell it returns the cell's paragraph; in a list it returns the top-level list. |
| `BlocksOf(parent)` | 313-322 | Block collection of FlowDocument / ListItem / TableCell / Section / Floater / Figure, else null. |
| `InsertListAtCaret(lines, numbered)` | 207-245 | CONT-047 step 5. Anchor = caret paragraph (or last document block); climb anchors until `BlocksOf(anchor.Parent)` is non-null; host defaults to document blocks; `InsertAfter(anchor)` if host contains anchor, else `Add`. |
| `MoveCurrent(up)` | 253-288 | CONT-046; caret offset measured with `GetOffsetToPosition` (symbol offset incl. inline tags) from the paragraph start and restored the same way. |
| `InsertPlainText(text)` | 327-352 | CONT-034. |
| `OnRtbPasting` | 354-383 | CONT-035. |
| `InsertLink_Click` | 704-723 | CONT-031. |
| `InsertTable_Click` | 727-768 | CONT-032. `int.Parse` on the regex groups can overflow for absurd digit strings (throws → crash log); the Mac MUST clamp safely. |
| `Rtb_PreviewKeyDown` | 1054-1113 | Order: (1) Ctrl+Shift+V → paste text only; (2) Ctrl+Alt+Up/Down → move; (3) Backspace at list-item start → outdent; (4) `!_hasAnyLock` → return; (5) Backspace/Delete/modifying-key lock checks (CONT-063). |
| `IsModifyingKey` | 1115-1125 | Non-modifying: Left Right Up Down Home End PageUp PageDown Tab LeftShift RightShift LeftCtrl RightCtrl LeftAlt RightAlt CapsLock Escape; with Ctrl held: C, A, F, Insert. Everything else = modifying. |
| `Rtb_PreviewTextInput` | 1127-1139 | CONT-063 typing rule. |
| `Rtb_PreviewExecuted` | 1141-1155 | CONT-063 command rule. |
| `ShowLockedHint` | 1157-1167 | CONT-064 (`DateTime.Now` delta < 1500 ms → skip). |
| `Lock_Click` / `Unlock_Click` / `LockedAncestor` / `EnsureUnlocked` | 1169-1245 | CONT-060…062. |

**Lock geometry (normative for the Mac).** Let `L(i)` be true when character *i* is locked (effective background
== sentinel). For an edit that replaces range `[a, b)` with string *s*:
* `b > a` (deletion/replacement, incl. Backspace/Delete/cut/paste-over/typing-over): **blocked iff any `L(i)`,
  a ≤ i < b**;
* `b == a` (pure insertion at caret *a*): **blocked iff `L(a-1) && L(a)`** (strictly inside a locked stretch);
  out-of-range indices count as unlocked.
Windows implements this with symbol-level `TextPointer` walks (`RangeOverlapsLocked` `:1005-1018`,
`CaretInsideLocked` `:1035-1043`, Backspace uses the previous insertion position, Delete the next); element tags
never count as locked characters, so paragraph starts/ends behave like boundaries. The character model above is
equivalent for every case AA can produce.

### 3.2 List engine (`Services/ListFormatting.cs`)

* `IndentStep = 24` (px/DIP per level; WPF's default is ≈49).
* `BulletCycle = [Disc, Circle, Square]`, `NumberCycle = [Decimal, LowerLatin, LowerRoman]`.
* `Build(lines, numbered)` (`:32-42`): new `List { MarkerStyle = numbered ? Decimal : Disc }`; for each line:
  skip `IsNullOrWhiteSpace`, else `ListItem(Paragraph(Run(line.Trim())) { Margin = 0,1,0,1 })`; then
  `ApplySpacing(list, 0, numbered)`.
* `Build(entries, numbered)` (`:45-63`, not used by the editor today): entries `(Text, Children)`; blank texts
  skipped; non-blank children become one nested `List` inside the item; `ApplySpacing` depth 0.
* `Normalise(doc)` (`:69-74`): for each **top-level** `List` in `doc.Blocks` → `ApplySpacing(list, 0,
  IsNumbered(list.MarkerStyle))`; then for every top-level block `NormaliseWithin(block)`:
  * `List` → recurse into every item's blocks (no re-spacing — already done by the recursive ApplySpacing);
  * `Table` → for every cell: each `List` directly in the cell → `ApplySpacing(l, 0, IsNumbered)`; recurse into
    every cell block;
  * `Section` → each `List` directly in the section → `ApplySpacing(l, 0, …)`; recurse;
  * lists inside `Floater`/`Figure` or directly inside a `ListItem` that sits in a table… are reached only through
    the recursion above (a list in a table cell is depth 0 again).
* `ApplySpacing(list, depth, numbered)` (`:101-117`): `cycle = numbered ? NumberCycle : BulletCycle`;
  `MarkerStyle = cycle[depth % 3]`; `Padding = (24,0,0,0)`; `Margin = depth == 0 ? (0,6,0,6) : (0,0,0,0)`; for every
  item: every `Paragraph` directly in the item → `Margin = (0,1,0,1)`; every `List` directly in the item →
  `ApplySpacing(sub, depth+1, numbered || IsNumbered(sub.MarkerStyle))`.
* `IsNumbered(style)` = Decimal, LowerLatin, UpperLatin, LowerRoman, UpperRoman. (None, Disc, Circle, Square, Box →
  bullet cycle; so `Box`/`None` lists are converted to bullets on the next normalise.)
* `MoveItem(item, up)` (`:129-143`): owner = `item.Parent as List` (null → false); neighbour = previous/next
  sibling item (null → false); remove item from `owner.ListItems`; insert before/after neighbour; true.
  (Collection taken from the owner, not `SiblingListItems`, which detaches on removal.)
* `MoveItems(items, up)` (`:146-172`): empty → false; one → `MoveItem`; all must share the same owner list (else
  false); order by sibling position; neighbour = `up ? first.Previous : last.Next` (null → false); remove all; up →
  insert each before the neighbour in order; down → insert after the neighbour, then after each inserted one.
  Relative order preserved; non-contiguous selections become contiguous around the neighbour.
* `MoveBlock(block, up)` (`:184-196`): collection = `BlocksOf(block.Parent)`; neighbour previous/next block; remove
  and re-insert before/after it.
* `DepthOf(list)` (`:211-225`): number of `List` ancestors including itself (1 = top level); unused by the UI.

### 3.3 HTML → XAML converter (`Services/HtmlToXamlConverter.cs`)

Output is an intermediate XAML fragment that WPF pastes and re-serialises; it is **never stored as-is**. The Mac
SHOULD port it rule-for-rule (so web pastes look identical on both platforms) using
`XMLDocument(data:options: .documentTidyHTML)` as the DOM, then feed the result to the XAML reader (§4.3).

1. **`Convert(html)`** (`:22-55`): blank → `""`. `ExtractCfHtmlFragment`; parse (HtmlAgilityPack, auto-close on
   end, fix nested tags); remove every `script, style, meta, link, head, title` node (with subtree); write
   `<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">`, walk the
   document with an empty style and `paragraphOpen = false`, close a still-open paragraph, close the section.
   `XmlWriter`: no declaration, no indentation, empty elements as `<X />`, text escaping `&amp; &lt; &gt;`,
   attribute escaping adds `&quot;`.
2. **`ExtractCfHtmlFragment(html)`** (`:60-75`): regexes `StartFragment:(\d+)` and `EndFragment:(\d+)`
   (case-insensitive); both present, `0 ≤ s < e ≤ html.Length` → `html.Substring(s, e - s)` (**char** indices,
   although CF_HTML offsets are UTF-8 **byte** offsets — wrong for non-ASCII headers/content; Mac pasteboards carry
   no CF_HTML header, so implement byte offsets correctly if ever needed). Else, if `<\s*html` matches
   (case-insensitive) → substring from there. Else the input.
3. **Style** state (cloned per element): `Bold, Italic, Underline, Strike, Foreground?, Background?, FontFamily?,
   FontSize?, Align?`.
4. **`EmitChildren(parent, style, ref paragraphOpen)`** (`:100-121`), per child:
   * text: `DeEntitize(innerText)`; unless the **immediate** parent is `pre`/`code`, collapse `\s+` → one space
     (.NET `\s` includes NBSP U+00A0, so `&nbsp;` runs collapse to one ordinary space); empty → skip; open a
     paragraph (with the *current* style's alignment) if none is open; `WriteRun`. A whitespace-only text node
     between blocks therefore creates a paragraph containing `" "` (§8 K-12);
   * element → `HandleElement`; comments/other node types ignored.
5. **`HandleElement(node, style, ref paragraphOpen)`** (`:123-244`), by lower-cased name:
   * `br` → open paragraph if needed; `<LineBreak />`.
   * `hr` → close paragraph; `<Paragraph BorderThickness="0,0,0,1" BorderBrush="#888" Padding="0" />`.
   * `ul`/`ol` → close paragraph; `<List MarkerStyle="Decimal|Disc">` (ol → Decimal); for each **direct child
     named `li`** (others — text, stray nested `ul` — are dropped): `<ListItem>`, children emitted with
     `MergeStyle(style, li)` and their own paragraph state, close, `</ListItem>`. `start`/`type`/list-style ignored.
   * `li` outside a list → close paragraph; a paragraph with the li's merged style containing its children.
   * `table` → close paragraph; `EmitTable(node, MergeStyle(style, node))`.
   * otherwise `merged = MergeStyle(style, node)`:
     * **block tags** `p div section article header footer main nav aside blockquote pre figure figcaption
       h1…h6` → close paragraph; headings set Bold and, if no size is set yet, FontSize h1 22, h2 18, h3 16,
       h4 14, h5 13, h6 12; `blockquote` → `<Paragraph Margin="20,0,0,0">` (plus alignment), others
       `<Paragraph [TextAlignment]>`; emit children with `merged` (nested blocks close/reopen paragraphs, so a
       `div` wrapping a `p` leaves an empty paragraph); close if still open. Block-level colour/weight is not
       written on the paragraph — it flows down to runs;
     * **inline tags** `a b strong i em u s strike del span font mark sub sup code tt cite abbr big small` →
       b/strong Bold; i/em/cite Italic; u Underline; s/strike/del Strike (`mark`, `sub`, `sup`, `code`, `tt`,
       `big`, `small`, `abbr` have **no** visual effect); open a paragraph with the *outer* style if none;
       `a` → `<Hyperlink [NavigateUri="{raw href}"]` + style attrs **without Foreground** + inline children;
       others → `<Span` + style attrs + inline children;
     * **anything else** (`html`, `body`, `img`, `tbody` outside a table, `dl/dt/dd`, `label`, `button`, `svg`…) →
       children emitted inline with `merged` (so `img` vanishes; `dl` content runs together).
6. **`EmitTable(table, style)`** (`:248-307`): rows = descendant `tr` whose nearest ancestor `table` is this table
   (thead/tbody/tfoot rows included, document order); none → **emit nothing**. `cols = max over rows of Σ max(1,
   colspan)` over the row's direct `td`/`th`; 0 → nothing. Output `<Table CellSpacing="0" Margin="0,4,0,4">`,
   `<Table.Columns>` with *cols* `<TableColumn />`, one `<TableRowGroup>`; per row `<TableRow>`; per direct
   `td`/`th`: style = Merge(Merge(table, tr), cell), `th` → Bold; `<TableCell BorderBrush="#FF9AA0A6"
   BorderThickness="0.6" Padding="3,1,3,1" [ColumnSpan="n"] [RowSpan="n"]>` (only when > 1; invalid → 1; no upper
   clamp) containing exactly one `<Paragraph [TextAlignment]>` with the cell's **inline** children (nested blocks,
   lists and tables inside a cell are flattened into Spans; only `<br>` breaks lines). Cell/row backgrounds become
   run highlights.
7. **`EmitInlineChildren(parent, style)`** (`:309-354`): text as in 4 (no paragraph logic); `br` → `<LineBreak />`;
   any other element → merged style + b/i/u/s flags; `a` → Hyperlink (as above); everything else → `<Span …>`
   recursively.
8. **`WriteRun`/`WriteStyleAttrs`** (`:364-392`): attributes in this order, only when set:
   `FontWeight="Bold"`, `FontStyle="Italic"`, `TextDecorations="Underline" | "Strikethrough" |
   "Underline,Strikethrough"`, `Foreground` (skipped on Hyperlink elements only — child runs still get it),
   `Background`, `FontFamily`, `FontSize` (`"0.##"`, invariant). A `false` flag writes nothing, so an inner
   `font-weight:normal` cannot cancel an outer bold (the inner run inherits the Span's bold).
9. **`MergeStyle(parent, node)`** (`:396-414`): clone; legacy attributes: `color` (non-empty → `NormaliseColor`;
   an invalid value **clears** the inherited foreground), `face` → FontFamily (raw), `size` (invariant double) →
   `FontSize = 8 + 2·size` (size="3" → 14, "+1" → 10), `align` → `MapAlign`; then `style` → `ApplyCss`.
10. **`ApplyCss(css)`** (`:416-470`): split on `;`, trim, `key:value` (key lower-cased, value case-sensitive):
    * `font-weight`: `bold`, `bolder`, or integer ≥ 600 → Bold; `normal`, `lighter` → not bold;
    * `font-style`: `italic`/`oblique` → Italic; `normal` → not;
    * `text-decoration`, `text-decoration-line`: contains `underline` → U; contains `line-through` → S;
      equals `none` → neither;
    * `color` → `NormaliseColor` (null → ignored); `background-color`, `background` → same into Background;
    * `font-family` → value with outer `"`/`'` trimmed (inner quotes of a list survive);
    * `font-size` → `ParseLengthPx`; `text-align` → `MapAlign`; everything else ignored.
11. **`MapAlign`**: `center`→Center, `right`→Right, `justify`→Justify, anything else → Left.
12. **`ParseLengthPx`** (`:480-493`): `^([\d.]+)\s*(px|pt|em|rem|%)?$` (case-insensitive); `pt` ×1.333; `em`/`rem`
    ×14; `%` → 14·n/100; `px`/none → n; keywords/`calc()` → null.
13. **`NormaliseColor`** (`:510-532`): trim; empty → null; `#…` → hex digits only and length 3/4/6/8 → returned
    **unchanged** (case kept), else null; `^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$`
    (case-insensitive) → `#RRGGBB` uppercase with channels clamped 0…255 (overflow → 255), **alpha ignored**
    (`rgba(0,0,0,0)` → `#000000`, §8 K-13); `^[A-Za-z]+$` and a WPF colour name (case-insensitive, list in §4.3.5)
    → returned as given; anything else (`rebeccapurple`, `lightgrey`, `currentColor`, `inherit`, `rgb(0 0 0 / 50%)`)
    → null.

### 3.4 Insert-saved-list dialog (`Views/InsertSavedListWindow.xaml.cs`)

* ctor (`:30-48`): `_all = repo.Data.ChecklistTemplates` (arranged order). Empty → empty-state (CONT-048). Else
  `Bind(_all)`, select index 0.
* `Bind` (`:50-64`): group-name lookup from `Data.ListGroups`; rows `{Template, Display, GroupName = group name or
  "Ungrouped"}`; grouped view (no sort).
* `Search_Changed` (`:75-84`): `q = trim`; empty → all; else name contains q **or** any item title contains q
  (`CurrentCultureIgnoreCase`); rebind; select 0; update preview.
* `UpdatePreview` (`:89-112`): no selection → clear, disable Insert. `lines = BuildLines(t)`; Insert enabled iff
  lines > 0; preview text; `withNotes = items with non-whitespace RichTextXaml` (counts **all** items, even ones
  with blank titles); `withFiles = Σ Files.Count`; footer per CONT-048. Pluralisation: `line`/`lines`;
  `1 item has notes` / `N items have notes`; `1 attached file` / `N attached files`.
* `BuildLines` (`:114-127`): titles trimmed, non-empty; with duration: minutes of the *k*-th non-blank item;
  `> 0` → `"{title}  ({m} min)"`.
* `Ok_Click` (`:129-138`): recompute lines; empty → stay open; `Numbered = NumbersRadio`, `ListName`, close OK.

### 3.5 File bank operations (ContainerEditor + DataStore)

| Function | Location | Behaviour |
|---|---|---|
| `RefreshFileLists` | :478-489 | All = live collection; other tabs = filtered snapshots; ensure context menus. |
| `EnsureFileContextMenu` | :491-512 | CONT-080 menu, created once per list. |
| `Files_DragOver` / `Files_Drop` | :771-791 | CONT-085. Shift detected from `e.KeyStates` at drop. |
| `AddPathInPlace` | :795-820 | CONT-084/085 (folder name via `DirectoryInfo.Name`; for a drive root `D:\` the name is `D:\`). |
| `AddPath` / `AddFilePath` | :848-870 | CONT-082/083. |
| `LinkInPlace_Click`, `AddFile_Click`, `AddFolder_Click`, `AddLink_Click` | :822-907 | CONT-084, 082, 083, 086. |
| `CurrentLv` | :908-912 | The selected tab's ListView. |
| `Cut/Copy/Paste_Click` | :913-948 | CONT-087. |
| `RemoveFile_Click` | :949-957 | CONT-088. |
| `OpenSelected`/`OpenFileItem` | :960-981 | CONT-089. |
| `OpenAll_Click` | :838-847 | CONT-090. |
| `OpenContainingFolder` | :514-527 | CONT-091. |
| `RenameSelected` | :529-539 | CONT-092. |
| `LinkSelectedToItems` | :541-565 | CONT-093. |
| `DataStore.ImportFile` | `DataStore.cs:471-480` | §4.2. |
| `DataStore.ResolveFilePath` | `DataStore.cs:485-494` | §3.6. |
| `DataStore.ClassifyFile` | `DataStore.cs:653-663` | CONT-081. |

### 3.6 Path resolution & self-healing (`DataStore.cs`)

* **`ResolveFilePath(stored)`**: null/empty → `""`; starts with `http://`, `https://`, `mailto:`
  (case-insensitive) → unchanged; `Path.IsPathRooted` (Windows: `C:\…`, `C:…`, `\…`, `\\server\…`) → unchanged;
  otherwise `GetFullPath(Combine(AppFolder, stored))`.
* **`NormalizeFilePaths(data)`** — runs on every Load/LoadFrom/Save/SaveTo, over every container returned by
  `EnumerateContainers` (equipment + components, tasks + all nested subtasks, procedures + steps, vessels, crew
  checklist steps, saved-list items): skip `IsLink` and `LinkInPlace`; skip empty/relative paths; (1) absolute path
  under the current AppFolder → the remainder with `/` separators (e.g. `files/x.pdf`); (2) otherwise, if the
  `\`→`/` path contains `/files/` (last occurrence, case-insensitive) and `FilesFolder/{leaf}` exists locally →
  `files/{leaf}`; (3) else unchanged.
* **`MigrateLegacyAbsolutePaths`** (bundle import only): same skip rules; any rooted path containing `/files/` →
  `files/{leaf}` unconditionally.

### 3.7 Saved-list picker (`Views/SavedListPicker.cs:16-58`) — CONT-050.

---

## 4. Data formats

### 4.1 JSON (`data.json`, System.Text.Json)

Options (`DataStore.cs:267-275`): compact, `IgnoreCycles`, `WhenWritingNull`, **no naming policy** (PascalCase),
**no string-enum converter** (enums are integers), default encoder (`"` → `\u0022`, `<` → `\u003C`, `>` →
`\u003E`, `&` → `\u0026`, `'` → `\u0027`, `+` → `\u002B`, every non-ASCII char → `\uXXXX`). Properties are
written in declaration order.

**`Container`** (key `Container` on HierarchyItem, Component, ChecklistStep, ChecklistTemplateItem):

| Key | Type | Default if missing | Notes |
|---|---|---|---|
| `Id` | GUID string | **new random GUID on every load** (C# initializer) | Not referenced by anything except `SharedWithContainerIds`. |
| `RichTextXaml` | string | `""` | §4.3; may be `""`, a `<Section …>` document, or legacy `enc:…` (§4.6). `null` read → treat as `""`. |
| `Files` | array of FileItem | `[]` | Order = display order. |
| `SharedWithContainerIds` | array of GUID | `[]` | Preserve verbatim (CONT-095). |
| `IsLocked` | bool | `false` | Legacy flag; the editor forces it `false` on load; copied by cloning. |

**`FileItem`**:

| Key | Type | Default if missing | Notes |
|---|---|---|---|
| `Id` | GUID | new random GUID | **Not globally unique**: a cut-paste (CONT-087) writes the same entry (same Id) into two containers. Never de-duplicate by Id across containers. |
| `Name` | string | `""` | Display name (renameable). Folders linked in place end with `"  (folder)"`. |
| `Path` | string | `""` | `files/{guid32}_{name}` (copy), absolute Windows/UNC/POSIX path (in place, or legacy), or the raw URL text (link). |
| `Kind` | int | `0` (Document) | `FileKind`: **0 Document, 1 Image, 2 Video, 3 Link, 4 Other**. |
| `Added` | DateTime | `DateTime.Now` at load | Written from `DateTime.Now` (Kind Local) → ISO-8601 with offset, fraction trimmed: `2026-09-29T14:03:12.1234567+02:00`. |
| `IsLink` | bool | false | Web link. |
| `LinkInPlace` | bool | false | Referenced at original location; never rewritten. |
| `LinkedItemIds` | array of GUID | `[]` | Top-level item ids (CONT-093). |
| (`SourceLabel`) | — | — | `[JsonIgnore]`, never written. |

Example (one container, pretty-printed here for reading only; real files are compact):

```json
{"Id":"5e0f6a1e-3c2b-4d8e-9a51-0b6c1d2e3f40",
 "RichTextXaml":"\u003CSection xmlns=\u0022http://schemas.microsoft.com/winfx/2006/xaml/presentation\u0022 xml:space=\u0022preserve\u0022 … FontFamily=\u0022Consolas\u0022 … FontSize=\u002214\u0022 Foreground=\u0022#FF1A1A1A\u0022 …\u003E\u003CParagraph\u003E\u003CRun\u003ECheck oil\u003C/Run\u003E\u003C/Paragraph\u003E\u003C/Section\u003E",
 "Files":[
  {"Id":"9d1c…","Name":"Manual v2.pdf","Path":"files/0123456789abcdef0123456789abcdef_Manual v2.pdf","Kind":0,"Added":"2026-09-29T14:03:12.1234567+02:00","IsLink":false,"LinkInPlace":false,"LinkedItemIds":["a3e1…"]},
  {"Id":"77aa…","Name":"Daily log.xlsx","Path":"\\\\shipserver\\ops\\Daily log.xlsx","Kind":0,"Added":"2026-09-29T14:05:00+02:00","IsLink":false,"LinkInPlace":true,"LinkedItemIds":[]},
  {"Id":"c0de…","Name":"Routine  (folder)","Path":"Z:\\Routine","Kind":4,"Added":"2026-09-29T14:06:00+02:00","IsLink":false,"LinkInPlace":true,"LinkedItemIds":[]},
  {"Id":"f00d…","Name":"https://www.imo.org","Path":"https://www.imo.org","Kind":3,"Added":"2026-09-29T14:07:00+02:00","IsLink":true,"LinkInPlace":false,"LinkedItemIds":[]}],
 "SharedWithContainerIds":[],
 "IsLocked":false}
```

### 4.2 The `files/` folder

* Location: `{AppFolder}/files/` (Windows `%LOCALAPPDATA%\AA\files\`; Mac `~/Library/Application Support/AA/files/`;
  both overridable with `AA_DATA_DIR`). **Flat** — no sub-folders are ever created by AA.
* Import name: `{Guid.NewGuid():N}_{original file name}` — 32 lower-case hex digits, underscore, original name
  (extension kept). Stored path: `files/` + that name, **forward slash**. Copy with overwrite (collisions are
  impossible).
* Removing an entry never deletes the physical file. Copy-paste and container cloning (saved lists) share the same
  physical file between entries.
* Bundles (`.aaz`/ZIP, owned by the persistence spec): `data.json` + `source.json` + `files/` (the whole folder,
  including orphans) unless the export is data-only. Shared-save import copies bundle files over local ones and
  then deletes local files the bundle lacks (non-data-only bundles only) — top-level files of `files/` only.
* **Cross-platform file-name rule (Mac MUST):** a name that is legal on macOS may be illegal on Windows (`: * ? " <
  > | \`, control chars, trailing dot/space, reserved device names `CON PRN AUX NUL COM1-9 LPT1-9`), and a Windows
  extraction failure aborts the *entire* bundle import. The Mac MUST sanitise the **stored** file name (replace
  `: * ? " < > | \` and control characters with `_`, strip trailing dots/spaces, NFC-normalise, cap the original
  part at 150 UTF-16 units keeping the extension) while keeping `FileItem.Name` = the original display name.
  Reserved device names need no special rule because the stored leaf always starts with the 32-hex GUID prefix.

### 4.3 `RichTextXaml` — the WPF FlowDocument XAML vocabulary

#### 4.3.1 Envelope

* Produced by `new TextRange(doc.ContentStart, doc.ContentEnd).Save(stream, DataFormats.Xaml)` then
  `Encoding.UTF8.GetString`. Result: a single `Section` root element in the WPF presentation namespace
  `http://schemas.microsoft.com/winfx/2006/xaml/presentation`, `xml:space="preserve"`, **no XML declaration, no
  BOM, no indentation/insignificant whitespace** (every whitespace character inside text is content).
* The root carries the **inherited context** of the document as attributes (see sample S-1). For AA's editor that
  context is `FontFamily="Consolas" FontSize="14" Foreground="#FF1A1A1A"`, `xml:lang="en-us"`, left-to-right,
  left-aligned; documents that originated elsewhere (e.g. SIRE quick-add: `FontFamily="Segoe UI" FontSize="13"`)
  carry their own context, which WPF applies as explicit formatting on load **(WPF internal: contextual properties
  on paste — confirm)**.
* Reading tolerance the Mac MUST implement: a leading BOM / XML declaration / whitespace; root `Section`,
  `FlowDocument`, `Span` or `Paragraph`; missing `xml:space` (then apply XAML whitespace normalisation: collapse
  runs of whitespace inside inline content); whitespace-only text directly inside block containers (`Section`,
  `ListItem`, `TableCell`, `List`, `Table*`) is insignificant; text directly inside `Paragraph`/`Span` without a
  `Run` is an implicit run; `<Run Text="…"/>` equals `<Run>…</Run>`; newline characters inside run text render
  as line breaks (U+2028 on Mac), never paragraph breaks.
* Anything unparseable → CONT-006 (show raw, withhold). The Mac parser MUST NOT instantiate types from markup
  (the Windows editor uses the unrestricted XAML reader — a known risk noted in PROGRESS); unknown elements are
  **preserved opaquely** (§4.3.7).

#### 4.3.2 Elements

| Element | Where | Produced by | Mac mapping (§6.4) |
|---|---|---|---|
| `Section` | root; also nested block (pasted content) | editor save (root), HTML converter root | root → document defaults; nested → paragraph-level `.aaSectionPath` wrapper (+ `NSTextBlock` if it has background/border/padding) |
| `Paragraph` | block | editor, SIRE, HTML | paragraph (`\n`-terminated) with `NSParagraphStyle` |
| `Run` | inline | editor, HTML | text + character attributes |
| `Span` | inline container | HTML, RTF paste, editor (formatting over mixed runs) | inherited character attrs on children |
| `Bold` / `Italic` / `Underline` | inline container | XAML/RTF paste only | as Span with weight/style/underline |
| `Hyperlink` | inline container | toolbar, HTML `a`, RTF | `.link` + `.aaHyperlink` marker |
| `LineBreak` | inline | Shift+Enter, HTML `br` | U+2028 LINE SEPARATOR |
| `List` | block | list commands, saved-list insert, HTML `ul/ol`, SIRE | `NSTextList` in `paragraphStyle.textLists` |
| `ListItem` | in List | same | item-start paragraph + continuation paragraphs (`.aaListItemID`) |
| `Table`, `Table.Columns`, `TableColumn`, `TableRowGroup`, `TableRow`, `TableCell` | block | insert table, HTML/RTF paste | `NSTextTable` + `NSTextTableBlock` (TextKit 1) |
| `InlineUIContainer`, `BlockUIContainer` | inline / block | pasted images or controls (normally dropped by save) | opaque `PreservedXamlAttachment` |
| `Figure`, `Floater` | inline anchored blocks | XAML/RTF paste (rare) | opaque attachment (content preserved) |
| property elements `X.Foreground`, `X.Background`, `X.TextDecorations`, `Table.Columns` | any | WPF when a value has no string form (e.g. brush with opacity, custom decoration) | parse `SolidColorBrush Color= Opacity=` and `TextDecoration Location=`; else preserve |

#### 4.3.3 Attributes and value grammars

| Attribute | On | Grammar / values | Mac mapping |
|---|---|---|---|
| `xmlns` | root | presentation ns (also tolerate `x:` ns) | — |
| `xml:space` | root | `preserve` | whitespace rules |
| `xml:lang` | any | IETF tag, lower-case (`en-us`, `en-gb`, `el-gr`) — WPF stamps typed runs with the input language | `.aaXmlLang` (+ `NSAttributedString.Key("NSLanguage")` for spelling) |
| `FontFamily` | any | family name or comma-separated fallback list (`Segoe UI, Arial`); rarely `./#Name` | first installed family; original string kept in `.aaFontFamilyName` |
| `FontSize` | any | double, invariant (`14`, `14.6666666666667`) — WPF DIP | point size 1:1 on screen |
| `FontWeight` | any | `Thin ExtraLight UltraLight Light Normal Regular Medium SemiBold DemiBold Bold ExtraBold UltraBold Black Heavy ExtraBlack UltraBlack` or `1…999` | font weight trait; ≥ 600 renders bold; original token kept |
| `FontStyle` | any | `Normal Italic Oblique` | italic trait |
| `FontStretch` | any | `UltraCondensed … Normal/Medium … UltraExpanded` | preserve (width trait if available) |
| `Foreground` | any | brush (below) | `.foregroundColor` |
| `Background` | inline | brush; **`#FFFFE699` = lock sentinel** | `.backgroundColor` (+ `.aaLocked`) |
| `Background` | block (Paragraph, ListItem, TableCell, Table, Section, TableRow(Group)) | brush | `NSTextBlock.backgroundColor` / cell background; sentinel → `.aaLocked` for all its characters |
| `TextDecorations` | inline, Paragraph | comma list of `Underline Strikethrough OverLine Baseline`, or `None`, case-insensitive; or property element | `.underlineStyle` / `.strikethroughStyle`; OverLine/Baseline preserved |
| `BaselineAlignment` | inline | `Baseline Top Center Bottom TextTop TextBottom Subscript Superscript` | `.superscript` ±1 for Sub/Superscript; others preserved |
| `Typography.*` | any | ≈40 attached props (root lists all); `Typography.Variants="Superscript|Subscript|Ordinal|Inferior|Ruby|Normal"` is what Ctrl+=/Ctrl+Shift+= write | Variants → `.superscript`; the rest preserved |
| `NumberSubstitution.CultureSource`, `.Substitution`, `.CultureOverride` | root | enum | preserve |
| `FlowDirection` | any | `LeftToRight RightToLeft` | `baseWritingDirection` |
| `TextAlignment` | blocks, TableCell, ListItem | `Left Right Center Justify` | `.alignment` (.left/.right/.center/.justified) |
| `LineHeight` | blocks | double or `Auto` | min/max line height |
| `LineStackingStrategy` | blocks | `MaxHeight BlockLineHeight` | preserve |
| `IsHyphenationEnabled` | blocks | bool | `hyphenationFactor` 0/0.9 |
| `Margin`, `Padding`, `BorderThickness` | blocks, ListItem, TableCell | Thickness: `u` / `h,v` / `l,t,r,b`, comma or space separated, each a double or `Auto` (NaN) | indents/spacing (§6.4) |
| `BorderBrush` | blocks, cells | brush | `NSTextBlock` border colour |
| `TextIndent` | Paragraph | double (negative = hanging) | `firstLineHeadIndent = head + indent` |
| `KeepTogether`, `KeepWithNext`, `MinOrphanLines`, `MinWidowLines`, `BreakPageBefore`, `BreakColumnBefore`, `ClearFloaters` | Paragraph/blocks | bool/int/enum | preserve only |
| `MarkerStyle` | List | `None Disc Circle Square Box LowerRoman UpperRoman LowerLatin UpperLatin Decimal` | `NSTextList.MarkerFormat` (§6.4) |
| `StartIndex` | List | int ≥ 1 (default 1) | `startingItemNumber` |
| `MarkerOffset` | List | double/`Auto` | preserve |
| `CellSpacing` | Table | double | `NSTextTable` spacing (0 → `collapsesBorders`) |
| `Width` | TableColumn | GridLength: `Auto`, `*`, `n*`, `n` (px) | column width (absolute or proportional) |
| `ColumnSpan`, `RowSpan` | TableCell | int ≥ 1 | `NSTextTableBlock` spans |
| `NavigateUri` | Hyperlink | URI (absolute or relative; raw from HTML) | `.link` (URL if parseable, else string) |
| `TargetName` | Hyperlink | string | preserve |
| `Text` | Run | string | run text |

**Brush grammar**: `#AARRGGBB` (what WPF writes, upper-case), `#RRGGBB`, `#ARGB`, `#RGB`, a WPF colour name
(§4.3.5, case-insensitive), `sc#a,r,g,b` (scRGB floats), or a property element
`<X.Foreground><SolidColorBrush Color="#…" Opacity="0.5"/></X.Foreground>`. Mac writer MUST emit `#AARRGGBB`
upper-case sRGB.

#### 4.3.4 Samples

S-1 — typical Windows editor save **(root attribute set reconstructed from WPF's serializer — confirm with a
fixture; attribute order is not significant)**:

```xml
<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve" TextAlignment="Left" LineHeight="Auto" IsHyphenationEnabled="False" xml:lang="en-us" FlowDirection="LeftToRight" NumberSubstitution.CultureSource="User" NumberSubstitution.Substitution="AsCulture" FontFamily="Consolas" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="14" Foreground="#FF1A1A1A" Typography.StandardLigatures="True" Typography.ContextualLigatures="True" Typography.DiscretionaryLigatures="False" Typography.HistoricalLigatures="False" Typography.AnnotationAlternates="0" Typography.ContextualAlternates="True" Typography.HistoricalForms="False" Typography.Kerning="True" Typography.CapitalSpacing="False" Typography.CaseSensitiveForms="False" Typography.StylisticSet1="False" Typography.StylisticSet2="False" Typography.StylisticSet3="False" Typography.StylisticSet4="False" Typography.StylisticSet5="False" Typography.StylisticSet6="False" Typography.StylisticSet7="False" Typography.StylisticSet8="False" Typography.StylisticSet9="False" Typography.StylisticSet10="False" Typography.StylisticSet11="False" Typography.StylisticSet12="False" Typography.StylisticSet13="False" Typography.StylisticSet14="False" Typography.StylisticSet15="False" Typography.StylisticSet16="False" Typography.StylisticSet17="False" Typography.StylisticSet18="False" Typography.StylisticSet19="False" Typography.StylisticSet20="False" Typography.Fraction="Normal" Typography.SlashedZero="False" Typography.MathematicalGreek="False" Typography.EastAsianExpertForms="False" Typography.Variants="Normal" Typography.Capitals="Normal" Typography.NumeralStyle="Normal" Typography.NumeralAlignment="Normal" Typography.EastAsianWidths="Normal" Typography.EastAsianLanguage="Normal" Typography.StandardSwashes="0" Typography.ContextualSwashes="0" Typography.StylisticAlternates="0"><Paragraph><Run>Check the </Run><Run FontWeight="Bold">main engine</Run><Run> oil level.</Run></Paragraph><Paragraph TextAlignment="Center"><Run Foreground="#FFFF0000" Background="#FFFFFF00" TextDecorations="Underline">Urgent</Run></Paragraph></Section>
```

In the following samples `<Section …>` abbreviates the S-1 root.

S-2 — normalised bulleted list with a nested level (after `ToggleBullets`/`Tab` + normalise):

```xml
<Section …><List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Alpha</Run></Paragraph><List MarkerStyle="Circle" Margin="0,0,0,0" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Alpha one</Run></Paragraph></ListItem></List></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>Beta</Run></Paragraph></ListItem></List><Paragraph /></Section>
```

S-3 — numbered saved-list insert (`Build(["Check oil  (60 min)", "Log"], numbered: true)`):

```xml
<List MarkerStyle="Decimal" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Check oil  (60 min)</Run></Paragraph></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>Log</Run></Paragraph></ListItem></List>
```

S-4 — 2×2 table from **Insert table** (`2x2`) **(whether WPF writes `Table.Columns` and the 4-value thickness form —
confirm)**:

```xml
<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1" FontWeight="Bold"><Paragraph><Run></Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1" FontWeight="Bold"><Paragraph><Run></Run></Paragraph></TableCell></TableRow><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1"><Paragraph><Run></Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1"><Paragraph><Run></Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>
```

S-5 — hyperlink inserted with an empty selection (URL typed `https://www.imo.org`; WPF may also write the default
link style `Foreground="#FF0066CC" TextDecorations="Underline"` on the Hyperlink — tolerate both):

```xml
<Paragraph><Run>See </Run><Hyperlink NavigateUri="https://www.imo.org"><Run>https://www.imo.org/</Run></Hyperlink></Paragraph>
```

S-6 — locked text, a line break, a tab and a foreign input language:

```xml
<Paragraph><Run>Pressure: </Run><Run Background="#FFFFE699">7.5 bar — do not change</Run><LineBreak /><Run xml:lang="en-gb">	Colour check</Run></Paragraph>
```

S-7 — web `<hr>` after WPF round-trip: `<Paragraph BorderBrush="#FF888888" BorderThickness="0,0,0,1" Padding="0,0,0,0" />`.

S-8 — SIRE quick-add body (produced by `SireFlow.ToContainerXaml`, root context `FontFamily="Segoe UI"
FontSize="13" Foreground="#FF334155"` or the dark body brush), chip paragraph:
`<Paragraph Background="#FFFEF3C7" FontSize="12" Margin="0,10,0,4" Padding="8,4,8,4"><Run Foreground="#FF92400E">SUGGESTED INSPECTOR ACTIONS</Run></Paragraph>`.

S-9 — subscript from Ctrl+= **(confirm)**: `<Run Typography.Variants="Subscript">2</Run>`.

S-10 — empty note after the user deleted everything **(confirm)**: `<Section …><Paragraph /></Section>` (still
counts as "has notes" in `IsNullOrWhiteSpace` checks).

#### 4.3.5 WPF colour names (valid named brushes; values = CSS named colours of the same name, `Transparent` = `#00FFFFFF`)

AliceBlue, AntiqueWhite, Aqua, Aquamarine, Azure, Beige, Bisque, Black, BlanchedAlmond, Blue, BlueViolet, Brown,
BurlyWood, CadetBlue, Chartreuse, Chocolate, Coral, CornflowerBlue, Cornsilk, Crimson, Cyan, DarkBlue, DarkCyan,
DarkGoldenrod, DarkGray, DarkGreen, DarkKhaki, DarkMagenta, DarkOliveGreen, DarkOrange, DarkOrchid, DarkRed,
DarkSalmon, DarkSeaGreen, DarkSlateBlue, DarkSlateGray, DarkTurquoise, DarkViolet, DeepPink, DeepSkyBlue, DimGray,
DodgerBlue, Firebrick, FloralWhite, ForestGreen, Fuchsia, Gainsboro, GhostWhite, Gold, Goldenrod, Gray, Green,
GreenYellow, Honeydew, HotPink, IndianRed, Indigo, Ivory, Khaki, Lavender, LavenderBlush, LawnGreen, LemonChiffon,
LightBlue, LightCoral, LightCyan, LightGoldenrodYellow, LightGray, LightGreen, LightPink, LightSalmon,
LightSeaGreen, LightSkyBlue, LightSlateGray, LightSteelBlue, LightYellow, Lime, LimeGreen, Linen, Magenta, Maroon,
MediumAquamarine, MediumBlue, MediumOrchid, MediumPurple, MediumSeaGreen, MediumSlateBlue, MediumSpringGreen,
MediumTurquoise, MediumVioletRed, MidnightBlue, MintCream, MistyRose, Moccasin, NavajoWhite, Navy, OldLace, Olive,
OliveDrab, Orange, OrangeRed, Orchid, PaleGoldenrod, PaleGreen, PaleTurquoise, PaleVioletRed, PapayaWhip,
PeachPuff, Peru, Pink, Plum, PowderBlue, Purple, Red, RosyBrown, RoyalBlue, SaddleBrown, Salmon, SandyBrown,
SeaGreen, SeaShell, Sienna, Silver, SkyBlue, SlateBlue, SlateGray, Snow, SpringGreen, SteelBlue, Tan, Teal,
Thistle, Tomato, Transparent, Turquoise, Violet, Wheat, White, WhiteSmoke, Yellow, YellowGreen (141 names; note
there is **no** `LightGrey`/`RebeccaPurple`).

#### 4.3.6 Producers and consumers

Producers of stored XAML: the Windows editor (`PersistRichText`), SIRE quick-add (`SireFlow.ToContainerXaml`),
the Mac editor (this spec), and the iOS app (if it edits notes — §9 Q2). The HTML converter's output is only a paste
intermediate.

Consumers (all MUST keep working with Mac-written XAML): Windows editor/viewer (`TextRange.Load`), Windows PDF
export (`PdfExporter.WriteContainerBody`: fonts, sizes px×0.75→pt, colours, alignment, `TextIndent`, `Margin`,
lists by `MarkerStyle`, tables incl. spans/borders/shading, hyperlinks, strike, uniform-paragraph highlight,
lock colour excluded from highlight), Windows search (`SearchService.PlainTextFromXaml`: concatenates XML text
nodes, adding spaces at `Paragraph`/`LineBreak`/`ListItem` — **so run text must be element content, not a
`Text=` attribute**), change preview (`DataDiff.PlainText`: strip `<…>`, HTML-decode, collapse whitespace),
"has notes" checks (`!IsNullOrWhiteSpace(RichTextXaml)` in Saved Lists and the insert dialog), and the viewer's
`enc:` test.

#### 4.3.7 Mac writer rules (normative)

1. Empty document (no characters, no attachments) → write `""` (Windows treats `""` as an empty note; see §9 Q6).
2. Root: if the document was loaded from XAML, reuse the loaded root element's attribute list **verbatim**
   (namespace, `xml:space`, context attributes). New documents use the canonical S-1 root (Consolas / 14 /
   `#FF1A1A1A` / `en-us`). Always include `xmlns` and `xml:space="preserve"`.
3. Emit only attributes that differ from the value inherited from the enclosing element (root context for
   top-level content), using original tokens where preserved (`.aaFontFamilyName`, weight names, unknown attrs).
   Never emit Mac-only font names for text whose `.aaFontFamilyName` is set; text styled on the Mac with a Mac-only
   font writes that family name (Windows falls back gracefully).
4. Runs: element content (`<Run>text</Run>`), never `Text=`; split runs where character attributes change;
   U+2028 → `<LineBreak />`; tabs kept; XML-escape `& < >`; drop characters illegal in XML 1.0.
5. Paragraphs: `<Paragraph>` per paragraph; `TextAlignment` only when not `Left`; `Margin`/`TextIndent`/
   `LineHeight` only when set by the user or preserved; list-item paragraphs `Margin="0,1,0,1"` after normalise.
6. Lists: consecutive paragraphs sharing the same `NSTextList` object → one `List`; nested textLists → nested
   `List` inside the previous `ListItem`; `MarkerStyle`, `StartIndex` (≠1), `Margin`, `Padding` written; list
   marker characters in the text storage (TextKit 1 `\t•\t` prefixes, `.aaListMarker`) are **never** written as
   text.
7. Tables: from `NSTextTableBlock`s → `Table` (`CellSpacing`, `Margin`), `Table.Columns` (count, widths if set),
   one `TableRowGroup` per preserved group (default one), rows in order, cells with `ColumnSpan`/`RowSpan` > 1,
   `BorderBrush`, `BorderThickness` (4-value), `Padding`, `Background`, cell-level `FontWeight` if preserved; every
   cell contains ≥ 1 `Paragraph`.
8. Hyperlinks: `<Hyperlink NavigateUri="…">` (original string if preserved) around the linked runs; no default
   blue/underline attributes unless the user set them explicitly.
9. Lock: every locked character's run carries `Background="#FFFFE699"`; a preserved block-level sentinel is
   re-emitted on its block.
10. Preserved opaque fragments (`PreservedXamlAttachment`) are written back byte-for-byte at their position.
11. Output compact (no whitespace between elements), UTF-8 when stored, no declaration.
Round-trip goal: `write(read(x))` is semantically equal to `x` for every Windows sample, and Windows
`TextRange.Load` accepts every Mac output (golden tests in §7).

### 4.4 Lock sentinel

`Background="#FFFFE699"` exactly (alpha FF). Any element, any level. Highlight colour `#FFE699` picked by the user is
indistinguishable from a lock by design.

### 4.5 settings.json keys touched

`PasswordHash` (base64 of PBKDF2-SHA256(password, salt, 100 000, 32 bytes)) and `PasswordSalt` (base64 of 16 random
bytes) — written by `DataStore.SavePasswordSettings` when the lock gate creates the first app password. Unknown
keys preserved. Per the Flash Sync contract these never travel between devices.

### 4.6 Legacy `enc:` body

`"enc:" + Base64( IV[16] ‖ AES-256-CBC-PKCS7(key=encKey, iv=IV, plaintext) ‖ HMAC-SHA256(macKey, IV ‖ ciphertext)[32] )`
with `PBKDF2-SHA256(UTF-8 password, appSalt, 100 000 iterations, 64 bytes)` → `encKey = [0..32)`,
`macKey = [32..64)`; `appSalt` = the `PasswordSalt` from **this machine's** settings.json. Plaintext = UTF-8 **with
BOM** (written by `StreamWriter(…, Encoding.UTF8)`; strip it after decrypting). Decrypt rejects blobs shorter than
16+32+16 bytes and MAC mismatches (constant-time compare). Note: `encKey` equals the stored `PasswordHash` bytes
(PBKDF2 block 1 is identical for 32- and 64-byte outputs) — anyone holding settings.json can decrypt; the Mac must
be compatible, not stronger, here. Blobs are only decryptable on a machine with the same salt + password.

---

## 5. Dependencies

### 5.1 This subsystem calls

| Callee | Function(s) | Purpose |
|---|---|---|
| `AppRepository` | `MarkDirty()`, `Data.ChecklistTemplates`, `Data.ListGroups`, `Data.Tasks`, `AllItems()`, `Save()` | persistence, saved lists, link picker, picker → tasks |
| `DataStore` | `ImportFile`, `ResolveFilePath`, `ClassifyFile`, `SavePasswordSettings` | attachments, password |
| `PasswordService` | `IsEncrypted`, `IsUnlocked`, `Decrypt`, `HasPassword`, `SetPassword`, `Unlock`, `Verify` (via dialog) | legacy bodies, lock gate |
| `ListFormatting` | `Build`, `Normalise`, `MoveItems`, `MoveBlock`, `IndentStep` | lists |
| `HtmlToXamlConverter` | `Convert` | paste |
| `ChecklistTemplateService` | `ItemToTask` (SavedListPicker) | tasks from saved lists |
| Views | `InsertSavedListWindow`, `PromptWindow`, `PasswordWindow`, `ItemPickerWindow`, `ListStylePromptWindow` | dialogs |
| Host window | `FindName("StatusBlock")` | locked hint |

### 5.2 Called by

`HierarchyPage` (Load/FlushPending/park), `ItemWindow`, `ComponentEditorWindow`, `SubtaskEditorWindow`,
`ChecklistStepEditorWindow`, `MainWindow` (flush via pages/windows), `SavedListsPage`
(`ListStylePromptWindow.Ask`), `BoardPage`/`PlannerPage` (`SavedListPicker.PickAndAddTasks`). Cross-area readers of
container data: `SearchService`, `DataDiff`, `PdfExporter`, `ChecklistTemplateService.CloneContainer` (copies
`RichTextXaml`, `IsLocked`, files incl. `LinkedItemIds`, `SharedWithContainerIds`; files get **new Ids**),
`AppRepository.PurgeReferences` (scrubs `LinkedItemIds`), `DataStore.NormalizeFilePaths`/`EnumerateContainers`,
bundle import/export, Flash Sync (containers travel inside their owners; attachments never do).

### 5.3 Windows-only APIs used

WPF `RichTextBox`/`FlowDocument`/`TextRange.Save/Load(DataFormats.Xaml)` (serializer + unrestricted XAML reader),
WPF `EditingCommands`/`ApplicationCommands`/`CommandManager` preview handlers, WPF spell checker
(`GetSpellingError`, `SpellingError.Correct/IgnoreAll`), `DataObject.AddPastingHandler` and clipboard formats
(`Html` CF_HTML, `Rtf`, `Xaml`, `XamlPackage`, `UnicodeText`, `FileDrop`), `System.Windows.Forms.ColorDialog`,
`System.Windows.Forms.FolderBrowserDialog`, `Microsoft.Win32.OpenFileDialog`, `Process.Start(UseShellExecute)`
(ShellExecute default-app/URL/folder launch), `explorer.exe /select,`, `SystemSounds.Beep`, `Fonts.SystemFontFamilies`,
`Keyboard.Modifiers`/`DragDropKeyStates.ShiftKey`, HtmlAgilityPack (HTML DOM), Windows path semantics
(`Path.IsPathRooted`, drive letters, UNC).

---

## 6. macOS adaptation notes (Swift, SwiftUI + AppKit, macOS 26+)

### 6.1 Architecture (recommended types)

* `AACore/RichText/`: `XamlDOM` (tolerant XML → element tree, no type instantiation), `XamlReader`
  (DOM → `NSAttributedString` + `RichTextMetadata`), `XamlWriter` (attributed string → XAML per §4.3.7),
  `HTMLToXAML` (port of §3.3 over `XMLDocument(.documentTidyHTML)`), `ListFormatter` (§3.2 over the attributed model),
  `LockRules` (§3.1 geometry), `XamlPlainText` (Search/DataDiff semantics), `LegacyBodyCrypto` (§4.6 via
  CommonCrypto PBKDF2 + AES-CBC and CryptoKit HMAC).
* `AACore/Attachments/`: `FileClassifier` (exact CONT-081 table), `AttachmentStore` (`importFile`, `resolve`,
  `normalizePaths`, `migrateLegacyAbsolutePaths`, Windows-path helpers, file-name sanitiser §4.2).
* App: `ContainerEditorView` (SwiftUI) = `VSplitView { RichTextArea; FileBankView }`; `RichTextArea` hosts an
  `NSViewRepresentable` around `ContainerTextViewController` (AppKit, `@MainActor`), which owns the `NSTextView`,
  debounce, lock enforcement and undo. `FileBankView` is SwiftUI (`Table`).
* Custom attribute keys (never persisted as such): `.aaLocked`, `.aaListMarker`, `.aaListItemID`,
  `.aaListContinuation`, `.aaHyperlink`, `.aaXmlLang`, `.aaFontFamilyName`, `.aaFontWeightToken`,
  `.aaExtraAttributes` (unknown attrs by element), `.aaSectionPath`, `.aaTableRowGroup`, `.aaPreservedXaml`.

### 6.2 Text view configuration

* **TextKit 1** (`NSTextView(usingTextLayoutManager: false)` or `layoutManager` access forcing fallback) — required
  for `NSTextTable`/`NSTextTableBlock` (tables) and `NSTextBlock` (paragraph backgrounds/borders/padding, e.g. SIRE
  chips and `<hr>`), which TextKit 2 does not lay out.
* `isRichText = true`, `allowsUndo = true`, `importsGraphics = false` (image paste handled in 6.6),
  `isContinuousSpellCheckingEnabled = true`, grammar off, and **off by default** to match WPF (which never alters
  typed text): automatic spelling correction, quote/dash substitution, text replacement, link and data detection,
  smart insert/delete (users can still toggle them in Edit ▸ Substitutions).
* Paper look in both appearances: `appearance = NSAppearance(named: .aqua)` on the text view only;
  `drawsBackground = true`, `backgroundColor = #FCFCFC`, `insertionPointColor = #1A1A1A`, default typing attributes
  Consolas (if installed) else `NSFont.monospacedSystemFont` 14 pt, colour `#1A1A1A`; `textContainerInset ≈ 8–13 pt`;
  wraps to width. Chrome (format bar, file bank) follows the app theme (system appearance or the app's dark toggle).
* `linkTextAttributes = [.foregroundColor: #0066CC, .underlineStyle: single, .cursor: .pointingHand]` (WPF's
  default Hyperlink look). Links SHOULD open on ⌘-click (and plain click in the read-only viewer); Windows' editor
  links are not clickable, so this is purely additive.
* Paragraph spacing: WPF's automatic paragraph margin ≈ one line height between paragraphs (`Auto` margins);
  default paragraph style `paragraphSpacing ≈ 1.17 × fontSize` (Consolas line spacing), 0 before, so a
  multi-paragraph note looks like Windows. Verify side-by-side (§9 Q8).

### 6.3 Formatting bar & menus (Mac-native, nothing dropped)

A compact in-pane format bar (SwiftUI `HStack` of `ControlGroup`s, `.controlSize(.small)`, borderless buttons that
refuse first responder so the text keeps focus, wrapping into an overflow `Menu` when narrow), **plus** a menu-bar
`Format` menu with the same commands (enabled via `FocusedValue` only when a container editor is key). Tooltips
(`.help`) keep the Windows text with ⌘ substituted.

| Windows | Mac control | SF Symbol | Mac shortcut |
|---|---|---|---|
| Font combo | `NSPopUpButton` of families (static cache, `localizedCaseInsensitiveCompare`), "Show Fonts" also available | — | ⌘T (font panel) |
| Size combo | `NSComboBox` (same 15 sizes), applies on Enter/selection (live typing optional) | — | ⌘+ / ⌘− (Bigger/Smaller = WPF Ctrl+] / Ctrl+[) |
| B / I / U | toggle buttons showing state | `bold` `italic` `underline` | ⌘B ⌘I ⌘U |
| S | toggle | `strikethrough` | ⇧⌘X |
| A▾ Text color | popover swatch grid + "Other…" (`NSColorPanel`) | `character` + colour bar | ⇧⌘C (Colors panel) |
| HL Highlight | popover swatches + "No Highlight" + "Other…" | `highlighter` | — |
| ⯇ ≡ ⯈ ☰ | segmented control | `text.alignleft` `text.aligncenter` `text.alignright` `text.justify` | ⌘{ ⌘\| ⌘} (justify: menu only) |
| • / 1. | toggle buttons | `list.bullet` / `list.number` | ⇧⌘7 / ⇧⌘9 |
| →\| / \|← | buttons | `increase.indent` / `decrease.indent` | ⌘] / ⌘[ (and Tab/⇧Tab at item start) |
| ≔ Insert saved list | button → sheet | `text.badge.plus` | ⌥⌘L |
| ⤒ / ⤓ Move | buttons | `arrow.up.to.line` / `arrow.down.to.line` | ⌃⌘↑ / ⌃⌘↓ (Apple Notes) + ⌃⌥↑/↓ alias |
| ↶ / ↷ | buttons | `arrow.uturn.backward` / `arrow.uturn.forward` | ⌘Z / ⇧⌘Z (⌘Y alias) |
| 🔗 Insert hyperlink | sheet (URL, prefilled `https://`) | `link` | ⌘K |
| ▦ Insert table | sheet with rows×cols field (and a grid picker) | `tablecells` | ⌥⌘T |
| Clr | button | `eraser` | — |
| 🔒 / 🔓 | buttons | `lock` / `lock.open` | — |
| Paste text only (context menu, Ctrl+Shift+V) | context menu item + Edit ▸ "Paste and Match Style" | — | ⌥⇧⌘V (+ ⇧⌘V alias) |
| Shift+Enter line break | override `insertNewline` when ⇧ held → `insertLineBreak` | — | ⇧↩ (and ⌃↩) |

Keyboard notes: Ctrl+R in the Windows editor aligns right; on the Mac ⌘R stays the app-wide due-dates command
(alignment is ⌘}). ⌘F stays the app-wide Search (parity with Ctrl+F); an in-note find bar SHOULD be offered as
Edit ▸ Find ▸ "Find in Note…" ⌥⌘F (`usesFindBar = true`) — additive (§9 Q4).

### 6.4 XAML ⇄ NSAttributedString mapping

* **Character**: FontFamily/Size/Weight/Style → `NSFont` via `NSFontManager` (weight ≥ 600 → bold trait, else
  closest weight; Oblique → italic); Foreground → `.foregroundColor` (sRGB); inline Background → `.backgroundColor`;
  Underline → `.underlineStyle = single`; Strikethrough → `.strikethroughStyle = single`; Sub/Superscript →
  `.superscript -1/+1` + `.baselineOffset`; Hyperlink → `.link`. Font substitution for display only:
  Consolas → SF Mono/Menlo, Segoe UI → system font, Calibri → Helvetica Neue, Cambria → Georgia (others such as
  Arial, Times New Roman, Courier New, Verdana, Tahoma, Georgia exist on macOS) — the original name is kept in
  `.aaFontFamilyName` so saving never rewrites it.
* **Paragraph**: `TextAlignment` → `alignment`; `Margin.Left` (+ list/section indents) → `headIndent` and
  `firstLineHeadIndent (+ TextIndent)`; `Margin.Right` → `tailIndent = −right`; `Margin.Top/Bottom` →
  `paragraphSpacingBefore/paragraphSpacing` (`Auto` → default spacing; adjacent margins collapse in WPF, so use
  `max(prevBottom, top)`); `LineHeight` → min/max line height; block `Background`/`Padding`/`BorderThickness`/
  `BorderBrush` → an `NSTextBlock` (TextKit 1) in `textBlocks`.
* **Lists**: `MarkerStyle` → `NSTextList.MarkerFormat` with the WPF punctuation: Disc `{disc}`, Circle `{circle}`,
  Square `{square}`, Box `{box}`, Decimal `{decimal}.`, LowerLatin `{lower-alpha}.`, UpperLatin `{upper-alpha}.`,
  LowerRoman `{lower-roman}.`, UpperRoman `{upper-roman}.`, None → no marker (`.aaListMarker` empty, preserved).
  `StartIndex` → `startingItemNumber`. Level *n* content starts at `24·n` pt beyond the paragraph's own left
  margin (List `Padding.Left`, default 24 after normalise; an un-normalised WPF list with auto padding ≈ 49);
  marker in the hanging area. TextKit 1 stores markers as text (`\t{marker}\t`) — tag them `.aaListMarker`, keep
  them out of lock checks, selection-based commands and the XAML output. Continuation paragraphs of one `ListItem`
  carry `.aaListContinuation` (indented, no marker).
* **Tables**: `NSTextTable` (`numberOfColumns` = max over rows of Σ spans; `collapsesBorders` when `CellSpacing=0`;
  `hidesEmptyCells = false`), `NSTextTableBlock(table:startingRow:rowSpan:startingColumn:columnSpan:)`, border
  width per edge = `BorderThickness` (0.6), colour `BorderBrush`, padding per edge, background; column widths from
  `TableColumn.Width` (absolute points or percentage). Cell-level `FontWeight="Bold"` → bold font on the cell text,
  and the token is kept for the writer. Tab in a cell → next cell, ⇧Tab → previous (NSTextView table behaviour).
  Always keep an ordinary paragraph after a table so the caret can leave it.
* **Opaque**: `InlineUIContainer`, `BlockUIContainer`, `Figure`, `Floater`, unknown elements → `NSTextAttachment`
  subclass holding the original XML fragment, drawn as a small grey chip (`⧉ embedded content`) and written back
  verbatim.

### 6.5 Lists behaviour on the Mac

Implement WPF parity on top of NSTextView: Enter in item → new item; Enter on an empty item → outdent (top level →
leave list); Tab at item start (caret right after the marker) → nest under the previous item; ⇧Tab → un-nest;
Backspace at item start → outdent one level / leave list at top (CONT-045 — override TextEdit's "delete marker"
behaviour); toolbar list commands, indent/outdent, move, backspace-outdent and saved-list insert run
`ListFormatter.normalise` over the whole document **after** the structural change, inside one undo group
(`undoManager.beginUndoGrouping`/`endUndoGrouping`). Indent on ordinary paragraphs moves the whole paragraph by
24 pt (headIndent and firstLineHeadIndent together), clamped at 0 (`NaN`/Auto treated as 0). Move up/down
re-orders whole paragraph ranges (item + all deeper-level following paragraphs = its sub-items) within the same
list/cell/document level exactly per §3.2, restoring the caret offset.

### 6.6 Paste, drop and pasteboard

* Override `readSelection(from:type:)` / `readablePasteboardTypes` (serves paste **and** drop):
  1. `com.eriskay.aa.xaml` (our own type, written on copy alongside RTF/plain) → lossless;
  2. `public.rtf` / `com.apple.flat-rtfd` (Word, Pages, Excel, Safari) → `NSAttributedString(rtf:)` → sanitise to the
     representable subset (fonts, sizes, colours, B/I/U/S, alignment, lists, tables, links; drop images — see
     below);
  3. `public.html` (Chrome, Edge, Firefox) → `HTMLToXAML.convert` → `XamlReader` (identical result to Windows web
     paste);
  4. plain text.
* Lock check before any paste (6.8).
* **Paste text only / Paste and Match Style**: `pasteAsPlainText(_:)`-equivalent: insert the pasteboard string with
  the current typing attributes, CR LF/CR → LF (paragraph breaks), one undo group; enabled only when the
  pasteboard has a string.
* **Images** pasted or dropped onto the text: not embedded (Windows cannot store them). SHOULD offer "Add to File
  Bank" (imports the image as a copy, CONT-082) — additive (§9 Q5). Files dropped onto the text area SHOULD be
  routed to the file bank with the same copy/link-in-place modifier rules (Windows ignores such drops).

### 6.7 Load / save / debounce / undo

* `load(container)`: flush the previous container; reset `contentWithheld`; handle `enc:` (6.10); parse with
  `XamlReader`; on failure show the raw string as plain text and set `contentWithheld = true`; **clear the undo
  stack** (`undoManager.removeAllActions()`); caret to start, scroll to top; compute `hasAnyLock`; `isLocked = false`
  in memory. Editor SHOULD be read-only with an inline banner while withheld (Windows cannot do this; the guard is
  what matters).
* Debounce 400 ms after the last text/attribute change → snapshot `attributedString()` on the main actor →
  serialise (may run off-main on the immutable copy) → back on main, if the editor is still bound to the same
  container and generation, assign `richTextXaml` and `store.markDirty()` **only if the string changed**.
* `flushPending()` MUST be called by every host exactly where Windows calls `FlushPending` (§2.1 CONT-005), plus
  `applicationShouldTerminate`, window `windowShouldClose`, and SwiftUI `onDisappear` of the editor.
* Immediate-persist actions (saved-list insert, move, link, table, lock/unlock) persist synchronously.

### 6.8 Lock enforcement

* Enforce §3.1 lock geometry in `textView(_:shouldChangeTextInRanges:replacementStrings:)` — this catches typing,
  IME, Backspace/Delete/word deletes, cut, paste, drag-move, spelling correction, Services, autocorrect and
  dictation in one place. Blocked → return `false` + `showLockedHint()`.
* Hint: same 1.5 s throttle and text `🔒 Highlighted/touched text is locked. Select it and click 🔓 to unlock.`
  (lock SF Symbols may replace the emoji) in the main window status bar when hosted there; elsewhere `NSSound.beep()`
  (SHOULD also flash a small inline banner above the editor).
* Right-click spelling on a locked word: replace suggestions with disabled `(locked — can't correct)`; keep
  "Ignore Spelling".
* Lock/Unlock semantics, password gate and `hasAnyLock` fast path exactly as CONT-060…065 (Unlock clears the
  sentinel from every contiguous locked stretch the selection touches — the Mac equivalent of "whole element").
* Gaps (CONT-066): see §8 D-4 — the Mac SHOULD preserve the sentinel through Highlight/Clear formatting and block
  undo steps that would modify locked text, but must still treat a user-picked `#FFE699` highlight as a lock
  (data semantics).
* Password dialogs as sheets (`SecureField` ×1 or ×2, inline red error `#D45050`, same messages and rules;
  master password `redemption` accepted). Touch ID MAY unlock the session using the password stored in the
  Keychain after a first successful entry (additive).

### 6.9 File bank on the Mac

* Header: title "File Bank" + labelled buttons (`Label` with symbols: `doc.badge.plus` Add File,
  `link.badge.plus` Link in Place, `folder.badge.plus` Add Folder, `globe` Add Link, `scissors` Cut, `doc.on.doc`
  Copy, `doc.on.clipboard` Paste, `minus.circle` Remove, `arrow.up.forward.app` Open, `square.stack.3d.up` Open
  All) and the hint "Drag & drop to import — hold ⌥⌘ or ⇧ to link in place".
* Category switcher: segmented `Picker` (All / Documents / Images / Videos / Links / Other) with the exact filters
  and columns of CONT-080 in a SwiftUI `Table` (multi-selection in every tab — superset). Name column SHOULD show a
  file icon/thumbnail (`QLThumbnailGenerator` for images/videos/PDFs, `NSWorkspace.icon(for: UTType)` otherwise,
  `globe` for links, `folder` for linked folders, a warning badge when the target is missing). Added column:
  user-locale short date + time (Windows shows en-US format).
* Additive Mac conveniences (no data change): Space = Quick Look (`QLPreviewPanel`), ⌘O open, Return/double-click
  open, ⌘⌫ remove, ⌘C/⌘X/⌘V bound to the file-bank clipboard, drag rows **out** to Finder/Mail (file URLs; links as
  URLs), empty-state `ContentUnavailableView("No files", systemImage: "tray", description: "Drop files here or use
  Add File.")`, per-tab counts.
* Context menu: Open, Show in Finder (= "Open containing folder"), Rename…, Link to Items…, —, Remove (+ additive
  Quick Look, Copy Path, Open With ▸).
* Drops: accept `.fileURL` (and SHOULD accept web URLs → Add Link). Modifier at drop: none → import copy
  (recursive for folders, `NSWorkspace.isFilePackage` packages handled per §9 Q7); ⇧ **or** ⌥⌘ (Finder's "make
  alias" gesture, `NSDragOperation.link` cursor) → link in place. Skip `.DS_Store`, `._*` AppleDouble, `Icon\r`
  when importing folders (§8 K-8).
* Dialogs: `NSOpenPanel` (multi-select files for Add File; files **and** folders for Link in Place — superset;
  directories only for Add Folder); prompts/alerts as SwiftUI `.alert` with `TextField` or small sheets; Open All
  confirm as `.confirmationDialog` with the Windows text.
* Open: `NSWorkspace.shared.open(url)`; folders → Finder; Show in Finder → `activateFileViewerSelecting([url])`
  (works for folders too). Web links without a scheme: `www.` / domain-like → prefix `https://`, `x@y` → `mailto:`;
  Windows UNC `\\server\share\p` → try `/Volumes/share/p`, else mount `smb://server/share` (NetFS) and retry;
  drive-letter paths (`Z:\…`) → a Mac-local drive-letter map (UserDefaults, never synced; Settings ▸ File Links),
  unmapped → alert "This file is on a Windows drive (Z:). Map the drive letter to a folder on this Mac in Settings
  ▸ File Links." Keep `FileItem.Path` verbatim always.
* Link in place on the Mac: for a file on a mounted SMB volume, SHOULD store the Windows UNC form
  (`\\server\share\rel\path`, derived from `URLResourceKey.volumeURLForRemountingKey`) so Windows can open it too;
  other locations store the POSIX path (Windows will report "Not found").
* Sandboxing: if the app is ever sandboxed, in-place links need security-scoped bookmarks kept in a Mac-local store
  keyed by `FileItem.Id`+`Path` (never in `data.json`).
* Clipboard: SHOULD be app-wide (shared by every editor instance) — superset of Windows' per-instance clipboard;
  Cut semantics per §8 D-5.
* Link to Items picker: sheet with search, sections per kind (Equipment/Area, Tasks, Procedures, Vessels), check
  marks, **selection preserved across filtering**, row text may keep `[Kind] Name`.

### 6.10 Legacy `enc:` bodies on the Mac

Implement `LegacyBodyCrypto.decrypt` byte-compatibly (§4.6; `CCKeyDerivationPBKDF` SHA-256 100 000 → 64 bytes,
`CCCrypt` AES-256-CBC PKCS7, CryptoKit `HMAC<SHA256>` constant-time compare, strip UTF-8 BOM). On load with the
session unlocked: decrypt; **only on success** write the plaintext back and mark dirty; on failure keep the
ciphertext and behave as locked-withheld (never replace with `""`, §8 D-1). The viewer shows `(locked content)`.

### 6.11 Dialogs on the Mac

* **Insert Saved List** sheet (≈760×560): left search field + `List` with `Section`s per group (order of first
  appearance, "Ungrouped"), right `Picker(.radioGroup)` Bullets/Numbered (bullets every time), `Toggle` "Include
  each item's duration", monospaced preview, footer note, Cancel (Esc) / Insert (⏎, default). Same strings with
  ⌘Z for Ctrl+Z.
* **List Style** prompt: sheet with a radio group showing title + description rows, Cancel / Continue.
* **Add from saved list** (Board/Planner): the shared multi-select picker sheet with the same prompt and row text;
  info alerts as `.alert`.

### 6.12 One editor per container (Mac)

Maintain an `EditorRegistry` keyed by `Container` identity: binding a container that another live editor holds
either (a) focuses that editor's window (item windows), or (b) makes the older binding park/reload. Editors observe
`richTextXaml` changes made elsewhere (Flash Sync apply, import, modal editors) and reload when they have no pending
edit (Windows has a known last-writer-wins window here, e.g. Board opening a task's editor while the Tasks page
holds the same container).

### 6.13 Genuinely impossible / different on macOS

* WPF's RTF→XAML paste converter and exact `TextRange.Save` byte output cannot be reproduced; parity is semantic
  (golden fixtures, §7.7).
* Consolas/Segoe UI may be absent → display substitution with names preserved.
* ShellExecute URL guessing and drive letters don't exist → explicit normalisation and drive map (6.9).
* `explorer /select` for folders didn't work on Windows; Finder reveal works — acceptable superset.

---

## 7. Test vectors / verification

### 7.1 HTML → XAML (exact Windows output; compare canonicalised XML, attribute order-insensitive)

Let `R` = `<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">` and
`/R` = `</Section>`.

| # | Input HTML | Expected |
|---|---|---|
| H1 | `<b>Hi</b>` | `R<Paragraph><Span FontWeight="Bold"><Run FontWeight="Bold">Hi</Run></Span></Paragraph>/R` |
| H2 | `<p style="text-align:center;color:rgb(255,0,0)">Hello <i>world</i></p>` | `R<Paragraph TextAlignment="Center"><Run Foreground="#FF0000">Hello </Run><Span FontStyle="Italic" Foreground="#FF0000"><Run FontStyle="Italic" Foreground="#FF0000">world</Run></Span></Paragraph>/R` |
| H3 | `<ul><li>One</li><li>Two <b>bold</b></li></ul>` | `R<List MarkerStyle="Disc"><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two </Run><Span FontWeight="Bold"><Run FontWeight="Bold">bold</Run></Span></Paragraph></ListItem></List>/R` |
| H4 | `<table><tr><th>A</th><th>B</th></tr><tr><td colspan="2" style="text-align:right">C</td></tr></table>` | `R<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1"><Paragraph><Run FontWeight="Bold">A</Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1"><Paragraph><Run FontWeight="Bold">B</Run></Paragraph></TableCell></TableRow><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1" ColumnSpan="2"><Paragraph TextAlignment="Right"><Run>C</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>/R` |
| H5 | `a<br>b` | `R<Paragraph><Run>a</Run><LineBreak /><Run>b</Run></Paragraph>/R` |
| H6 | `<h1>Title</h1>` | `R<Paragraph><Run FontWeight="Bold" FontSize="22">Title</Run></Paragraph>/R` |
| H7 | `<p>a</p>\n<p>b</p>` | `R<Paragraph><Run>a</Run></Paragraph><Paragraph><Run> </Run></Paragraph><Paragraph><Run>b</Run></Paragraph>/R` (Windows quirk K-12) |
| H8 | `<span style="font-size:12pt;font-family:'Times New Roman'">x</span>` | `R<Paragraph><Span FontFamily="Times New Roman" FontSize="16"><Run FontFamily="Times New Roman" FontSize="16">x</Run></Span></Paragraph>/R` (12×1.333=15.996 → "16") |
| H9 | `<a href="https://imo.org" style="color:red">IMO</a>` | `R<Paragraph><Hyperlink NavigateUri="https://imo.org"><Run Foreground="red">IMO</Run></Hyperlink></Paragraph>/R` |
| H10 | `<font color="#12" size="5">t</font>` | `R<Paragraph><Span FontSize="18"><Run FontSize="18">t</Run></Span></Paragraph>/R` |
| H11 | `<p>a&nbsp;&nbsp;b</p>` | `R<Paragraph><Run>a b</Run></Paragraph>/R` |
| H12 | `<table><tr><td>x<table><tr><td>y</td></tr></table></td></tr></table>` | outer table has **1** row, 1 column; cell paragraph `<Run>x</Run><Span><Span><Span><Run>y</Run></Span></Span></Span>` (inner table flattened, not duplicated) |
| H13 | `<hr>` | `R<Paragraph BorderThickness="0,0,0,1" BorderBrush="#888" Padding="0" />/R` |
| H14 | `<blockquote>q</blockquote>` | `R<Paragraph Margin="20,0,0,0"><Run>q</Run></Paragraph>/R` |
| H15 | `<script>x()</script><style>p{}</style><p>ok</p>` | `R<Paragraph><Run>ok</Run></Paragraph>/R` |
| H16 | `<img src="a.png"><p>t</p>` | `R<Paragraph><Run>t</Run></Paragraph>/R` |
| H17 | `<table></table>` | `<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" />` (self-closing: `XmlWriter` closes an element with no content as `<X />`) — non-blank, so WPF pastes an empty section and nothing visible is inserted |
| H18 | `""` / `"   "` | `""` (no conversion; WPF default paste) |
| H19 | CF_HTML `Version:0.9\r\nStartHTML:00000097\r\nEndHTML:00000174\r\nStartFragment:00000131\r\nEndFragment:00000140\r\n<html><body>\r\n<!--StartFragment--><b>Hi</b><!--EndFragment-->\r\n</body></html>` | fragment `<b>Hi</b>` → same as H1 |
| H20 | `<pre>a   b</pre>` | `R<Paragraph><Run>a   b</Run></Paragraph>/R` (no collapse inside `pre`) |

`NormaliseColor`: `#abc`→`#abc`; `#ABCD`→`#ABCD`; `#12`→null; `#ggg`→null; `rgb(300,20,0)`→`#FF1400`;
`rgb(0, 128, 255)`→`#0080FF`; `rgba(0,0,0,0)`→`#000000`; `rgb(-1,0,0)`→null; `RED`→`RED`; `transparent`→
`transparent`; `lightgrey`→null; `rebeccapurple`→null; `currentColor`→null; `rgb(0 0 0 / 50%)`→null.
`ParseLengthPx`: `16px`→16; `16`→16; `12pt`→15.996; `1.5em`→21; `2rem`→28; `150%`→21; `12 PX`→12;
`medium`→null; `calc(1px)`→null. `MapAlign`: `CENTER`→Center; `start`→Left. `size="3"`→14; `size="+1"`→10.

### 7.2 List engine

1. `Build(["  Alpha ", "", "   ", "Beta"], numbered: false)` → one List, MarkerStyle Disc, Padding 24,0,0,0, Margin
   0,6,0,6, items `Alpha`, `Beta`, each paragraph Margin 0,1,0,1.
2. Numbered list containing a Disc sub-list containing a Disc sub-sub-list → after `Normalise`: Decimal → LowerLatin →
   LowerRoman (the bullet sub-lists are forced numbered). Bullet list depth 0..4 → Disc, Circle, Square, Disc,
   Circle. A top-level `Box` list → Disc; `UpperRoman` top-level → Decimal (numbered cycle restarts at depth 0).
3. List inside a table cell → depth 0 styling (Margin 0,6,0,6, Disc/Decimal).
4. Items [A, B, C], caret in B, up → [B, A, C]; caret in A, up → unchanged, returns false; down on C → false.
5. Items [A(sub a1, a2), B], caret in A, down → [B, A(sub a1, a2)] (sub-items travel).
6. Selection spanning B and C of [A, B, C], up → [B, C, A]; down from [A, B, C] with A,B selected → [C, A, B].
7. Selection spanning items of two different lists → `SelectedListItems` empty → the caret's outermost block moves.
8. Caret in a plain paragraph P2 of [P1, P2, List] → down → [P1, List, P2]; up → [P2, P1, List].
9. `MoveItems` with non-contiguous [A, C] of [A, B, C, D] down → neighbour = D → [B, D, A, C].
10. Indent on a plain paragraph with Margin.Left 0 → 24 → 48; outdent from 10 → 0 (clamped); `Auto` → treated as 0.

### 7.3 Insert table / saved-list lines

Regex `^\s*(\d+)\s*[xX*]\s*(\d+)\s*$`: `3x4`→(3,4); ` 10 X 2 `→(10,2); `2*5`→(2,5); `100x100`→(50,20);
`0x0`→(1,1); `abc`→(3,3); `3x`→(3,3); `3×4` (U+00D7)→(3,3); `99999999999x2` → Windows throws; Mac MUST give (50,2).

`BuildLines` items `[("Check oil",60), ("",30), ("  Log  ",0), ("Test",15)]`: without duration → `["Check oil",
"Log", "Test"]`; with → `["Check oil  (60 min)", "Log", "Test  (15 min)"]`; preview numbered → `1. Check oil  (60
min)\n2. Log\n3. Test  (15 min)`; bullets → `• …`. Footer with 1 noted item and 2 files: `3 lines will be inserted.
Not carried over: 1 item has notes, 2 attached files.` Single line, no extras: `1 line will be inserted.`

### 7.4 Lock geometry (string `abcDEFghi`, `DEF` locked = indices 3…5)

| Edit | Result |
|---|---|
| insert at 3 (between c and D) | allowed |
| insert at 4 / 5 | **blocked** |
| insert at 6 (after F) | allowed |
| Backspace at 3 (deletes c) | allowed |
| Backspace at 4 (deletes D) / at 6 (deletes F) | **blocked** |
| Delete at 2 (deletes c) | allowed |
| Delete at 3 (deletes D) | **blocked** |
| replace [0,3) / [6,9) | allowed |
| replace [2,4) / [5,7) | **blocked** |
| paste-text-only with caret 4 | **blocked** + hint |
| unlock selecting only `E` | whole `DEF` stretch unlocked |
| document without sentinel | `hasAnyLock == false`, no checks run |
| `#FFFFE699` on a Paragraph | every character of it locked |

### 7.5 File bank

* `ClassifyFile`: `Report.PDF`→Document; `photo.HEIC`→Image; `clip.m4v`→Video; `notes.md`→Other; `a.tar.gz`→Other;
  `noext`→Other; `.pdf`→Document; `x.JPEG`→Image; `deck.key`→Other; `s.csv`→Other.
* `ImportFile("…/Manual v2.pdf")` → `files/[0-9a-f]{32}_Manual v2.pdf` and the bytes exist there.
* Mac sanitiser (stored leaf = `{guid32}_` + sanitised name): `a:b?.pdf` → `{guid}_a_b_.pdf` with `Name` still
  `a:b?.pdf`; `CON.txt` → `{guid}_CON.txt` (legal thanks to the prefix); `report. ` → `{guid}_report`;
  a decomposed (NFD) `é` in the name → stored NFC.
* `ResolveFilePath` (Mac, AppFolder `/Users/u/Library/Application Support/AA`): `files/a.pdf` →
  `/Users/u/Library/Application Support/AA/files/a.pdf`; `files\\a.pdf` → same; `https://x`/`mailto:a@b` →
  unchanged; `C:\\a.pdf`, `\\\\srv\\s\\a.pdf`, `/Volumes/S/a.pdf` → unchanged; `""` → `""`.
* `NormalizeFilePaths` (Mac): `/Users/u/Library/Application Support/AA/files/x.pdf` → `files/x.pdf`;
  `C:\\Users\\w\\AppData\\Local\\AA\\files\\y.pdf` with local `files/y.pdf` present → `files/y.pdf`, absent →
  unchanged; any `LinkInPlace`/`IsLink` entry → unchanged; relative → unchanged.
* Paste semantics: copy A (with LinkedItemIds [x]) → paste into B → new Id, same Path, LinkedItemIds `[]`, Added now;
  cut A → paste into B → B contains the same entry (same Id); A still contains it (Windows behaviour; Mac decision
  §8 D-5); second paste of the same clipboard → a copy.
* Folder Shift-drop `D:\Routine` → `{Name: "Routine  (folder)", Kind: 4, LinkInPlace: true}`.
* Open all with 16 entries → confirmation `Open all 16 items in this tab now?`; with 15 → no prompt.
* JSON round-trip: the §4.1 example parses and re-serialises byte-identically (key order, `\u0022` escapes, the
  Added offsets, integers for Kind).

### 7.6 Legacy crypto (computed with the §4.6 algorithm)

* password `test1234`, salt bytes `00 01 … 0F` (`PasswordSalt` = `AAECAwQFBgcICQoLDA0ODw==`):
  `PasswordHash` = `r8aEvRy/8yh5is2gkdnAZp/hnmK1R108BLIM6VbhOyI=`;
  encKey = `afc684bd1cbff328798acda091d9c0669fe19e62b5475d3c04b20ce956e13b22` (= hash bytes);
  macKey = `ba07c3c7a215d6fd24ea83a600cb8422d10f235abedba31bfe9d322b9deca1e7`.
* IV `10 11 … 1F`, plaintext = UTF-8 BOM + `<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph><Run>Secret</Run></Paragraph></Section>` →
  `enc:EBESExQVFhcYGRobHB0eH7yh0+cZnnHk+wt1LaJhOt37Vp1TfN1upIjugsLMCx8A+1BO/lOwe048ZDbt09pbLyzc0beZRySCCCdKYiLMU5PdZE5PJzh+Mh/dB0qGRrpyynpDMaDlxhjSkurNzory7yVyLf5MXDJksvDN6MZQ6xq0cW8h2FEuYihYTqxvmhwrVt1py4SETHUppvsjlMHfskgrHLivepYL5vBOq4Iy1MYzL9/UXBU8F/ZSwuzCLFPP`
  (ciphertext 144 bytes). Decrypt with `test1234` → the XAML (BOM stripped); with `redemption` → MAC failure →
  the Mac keeps the blob and withholds (Windows would wipe the note).
* Flip one byte of the MAC → nil. Blob shorter than 64 bytes after base64 → nil.

### 7.7 XAML reader/writer golden tests

1. Parse S-1 → two paragraphs; runs `Check the ` (regular), `main engine` (bold), ` oil level.`; paragraph 2
   centred, red on yellow, underlined; document defaults Consolas/14/#1A1A1A. Write → semantically equal to S-1.
2. S-2 → textLists depth 1 and 2 (disc, circle), markers not in plain text; write → equal (Margins/Padding kept).
3. S-4 → `NSTextTable` 2×2, row 0 bold; write → equal (BorderThickness 0.6 each edge, padding 3,1,3,1).
4. S-5 → `.link` = `https://www.imo.org`, display `https://www.imo.org/`; write keeps `NavigateUri` string.
5. S-6 → `hasAnyLock == true`; `7.5 bar — do not change` locked; LineBreak → U+2028; tab and `xml:lang="en-gb"`
   preserved on write.
6. S-8 (Segoe UI root) → rendered with the root context; write keeps the loaded root verbatim.
7. Unknown element `<Paragraph><InlineUIContainer><Button>x</Button></InlineUIContainer></Paragraph>` → one opaque
   attachment; written back byte-for-byte.
8. Invalid XML `"<Section><Paragraph>"` → parse failure → raw text shown, `contentWithheld == true`, no write on
   typing.
9. `SearchService.PlainTextFromXaml(write(doc))` returns the visible text (runs as element content).
10. Every Mac output loads in Windows `TextRange.Load` without exception (run on a Windows CI box or the WPF harness
    against a fixture folder) — **mandatory before release** (§9 Q1).

### 7.8 Behavioural checks (UI tests / manual)

* Type, wait 400 ms → `richTextXaml` updated; switch item within 400 ms → the text lands on the previous item.
* Open a legacy `enc:` container locked → type → nothing saved; insert saved list → `Nothing inserted` alert.
* Load item A, then item B, press ⌘Z → nothing happens (undo cleared).
* Toolbar bullets on 3 paragraphs → one bulleted list (disc), Margin/Padding normalised; Tab on item 2 → nested
  circle; Backspace at start of the nested item → back to level 1; again → plain paragraph.
* ⌃⌘↓ on the first item of a 3-item numbered list → it becomes item 2, numbers renumber, caret stays in the text.
* Lock a word without an app password → set-password sheet → word turns pale gold; typing inside it beeps/hints;
  typing right after it works; Unlock requires the password (or `redemption`).

---

## 8. Known Windows defects / quirks and porting decisions

`D-` = defect with a data-integrity risk (report back to the Windows owner); `K-` = behavioural quirk (UX only).
Numbers are stable references used throughout this spec.

| ID | Windows behaviour | Decision for the Mac |
|---|---|---|
| **D-1** | Legacy `enc:` body + session unlocked + decrypt fails (master password, changed password/salt, other machine) → body replaced by `""` and saved. | **Do not port.** Keep the ciphertext, withhold, show a banner. Report to the Windows owner. |
| **D-2** | Undo stack not cleared on `Load` (WPF records programmatic loads) → Undo after switching items can pour the previous item's text into the current one. **(confirm on Windows)** | **Fix**: clear undo on every load. Report. |
| **D-3** | Editor can be bound twice to one container via modal editors (Board/Calendar/Planner) while a page editor holds it → last writer wins. | Registry + reload-on-external-change (§6.12). |
| **D-4** | Lock gaps: Highlight/Clear formatting remove the sentinel; Undo/Redo, Enter inside locked text, drag-move not filtered; conversely with a locked selection most non-text shortcuts (Ctrl+S, Alt+F4…) are swallowed. | Enforce via `shouldChangeTextInRanges` (all text mutations, incl. Enter, drag, undo that edits text). Keep formatting allowed on locked text but **preserve the sentinel** through Highlight/Clear formatting (apply to unlocked sub-ranges only). Never swallow non-editing shortcuts. Lock/unlock remain undoable (parity). |
| **D-5** | "Cut" + "Paste" doesn't remove from the source; both containers share one entry (same Id). | Recommended: true move (remove from the source container on paste into a different container, keep the Id). Needs lead sign-off (§9 Q3). Either way the Mac MUST tolerate duplicate FileItem Ids in data. |
| K-3 | Strikethrough replaces underline; un-strike removes underline. | Mac: independent underline and strike toggles (superset). Stored format unchanged. |
| K-5 | Locked selection blocks almost every key. | Covered by D-4. |
| K-7 | Selecting text re-applies identical family/size (explicit attributes appear in XAML). | Do not replicate (invisible). |
| K-8 | Add Folder imports hidden/system files (desktop.ini, Thumbs.db). | Mac skips `.DS_Store`, `._*`, `Icon\r`; imports other hidden files. |
| K-9 | Import failure falls back to an absolute path labelled `Copy`. | Mac: on copy failure, alert and offer "Link in place instead" (entry then has `LinkInPlace = true`). |
| K-10 | "Open containing folder" on a linked folder says "File not found". | Mac reveals the folder in Finder. |
| K-11 | Link-to-items picker loses selections hidden by the search filter. | Mac preserves selection across filtering. |
| K-12 | Whitespace between HTML blocks becomes `" "` paragraphs; nested `div>p` leaves empty paragraphs. | Port faithfully for identical paste results **or** trim — lead decision (§9 Q9); default: faithful. |
| K-13 | `rgba(…,0)` (transparent) becomes black. | Mac: alpha 0 → no colour (a clear improvement; paste-only, no data impact). |
| K-14 | Insert hyperlink with empty selection appends at the end of the paragraph, not at the caret; `https://` alone does nothing silently. | Mac inserts at the caret and validates inline in the sheet (disable Insert until the URL parses). Display text = normalised URL as Windows. |
| K-15 | Insert table outside a top-level paragraph appends at the end of the document; no paragraph after the table. | Mac inserts after the caret's block in its own collection (like saved-list insert) and ensures a trailing paragraph. |
| K-16 | Font size combo applies on every keystroke. | Mac applies on commit (Enter/blur/menu). |
| K-17 | `Added` shown in en-US format. | Mac uses the user's locale. |

---

## 9. Open questions

1. **Real fixtures.** The exact `TextRange.Save` output (root attribute list, whether `Table.Columns`, 4-value
   thicknesses, Hyperlink default Foreground/TextDecorations, combined decorations as attribute vs property element,
   empty-document form, embedded-image placeholder) must be captured from a Windows install and checked into
   `mac/Tests/Fixtures/xaml/` before the converter is frozen; a Windows-side harness must also load every Mac output.
2. Does the iOS app write `RichTextXaml`? If so, share the fixture set and writer rules (§4.3.7) with it.
3. File-bank **Cut**: true move on the Mac (recommended) vs Windows' shared-entry behaviour (D-5)?
4. Keep ⌘F = global Search inside the editor (parity) with ⌥⌘F for find-in-note, or the reverse?
5. Images pasted/dropped onto the text: offer "Add to File Bank" automatically, ask, or ignore?
6. Empty Mac document → `""` (recommended) vs WPF-like `<Section …><Paragraph /></Section>`?
7. Dropping Mac packages (`.pages`, `.key`, `.rtfd`, `.app`) as copies: zip them into one flat `files/` entry
   (recommended, Windows-safe) or refuse / link in place only?
8. Paragraph-spacing and tab-stop metrics (WPF auto margins ≈ line height, default incremental tab) need a
   side-by-side screenshot comparison to tune.
9. HTML paste whitespace quirk (K-12): faithful or cleaned?
10. Should the Mac surface `FileItem.LinkedItemIds` (a "Linked to" column/inspector, and backlinks on items) and a
    UI for `SharedWithContainerIds` (aggregated file view)? Both are data-compatible additions; Windows has neither.

---

## Addendum: Normative shared XamlDOM contract: inheritance/cascade, computed style, per-consumer defaults

> **Status: normative.** §6.1 names `XamlDOM`, `XamlReader`, `XamlWriter` and `XamlPlainText`, but it does not
> define how a stored `RichTextXaml` string becomes *styled* text. Spec 11 (PDF, §3.5 and §6.3) and spec 12 (SIRE,
> §4.4 and §6.5) both depend on that definition. This addendum is the single contract for four things:
> - the DOM: node kinds, parent links, and raw plus parsed attributes;
> - the WPF-style cascade: inheritance, precedence and element style layers;
> - the default context of each consumer;
> - the writer's exact "differs from inherited" test.
>
> IDs `CONT-150`…`CONT-169` and test vectors prefixed `XD-` are reserved for this addendum. Normative words and
> confidence markers are the same as at the head of this spec: *MUST*, *SHOULD*, **(WPF internal: confirm)**.
> Where a WPF internal is uncertain, the Mac rule is still stated. It is chosen so that the result is identical for
> every document AA itself produces. The uncertain points are collected as fixture questions in XD.8.

### XD.0 Sources and refinements

#### XD.0.1 Sources read for this addendum

| Source | What it contributes |
|---|---|
| This spec: §4.3.1–§4.3.7, §6.1, §6.2, §6.4, S-1…S-10 | The vocabulary and existing mapping that this addendum makes precise |
| 11 §2.6 (PDF-060…077), §3.5.1–§3.5.8, §4.3, §6.3, §6.9 (DEV-01/02/05), §7.9–§7.11 | PDF consumer: effective values, `EffectiveBackground`, defaults Segoe UI / 12 px / black |
| 12 §3.6, §4.4, §6.5; S-8 here | SIRE producer root context; SIRE pane consumer |
| 01 §3.15 (`DataDiff.PlainText`) and persistence invariants; 02 REPO-104, §3.2, §4.7 (`SearchService.PlainTextFromXaml`) | Plain-text consumers. These must **not** go through the DOM |
| `AA/Views/ContainerEditor.xaml:59-63`, `AA/App.xaml:37-40` | Editor context: `FontFamily={MainFont}` = `Consolas`; `FontSize=14`; `Foreground={EditorFg}` = `#FF1A1A1A`; paper `#FFFCFCFC` |
| `AA/Views/ContainerEditor.xaml.cs:385-453, 693-768, 985-1047, 1169-1229` | Load, Clear formatting, Insert hyperlink/table (new elements carry no fonts, so they inherit), `IsLockedRun`/`LockedAncestor` (walks **every** TextElement ancestor) |
| `AA/Views/ContainerViewerWindow.xaml(.cs)` | Viewer context, same as the editor, with `IsDocumentEnabled=True` |
| `AA/Views/SirePage.xaml:169-172`, `SirePage.xaml.cs:232-262` | SIRE pane context: `Segoe UI` / 13 / `Normal` / `EditorFg`. Saved bodies load into a bare `FlowDocument` |
| `AA/Sire/SireFlow.cs:92-99` | SIRE producer root: `FlowDocument{FontFamily=Segoe UI, FontSize=13, FontWeight=Normal, Foreground=bodyBrush ?? #334155}` |
| `AA/Services/PdfExporter.cs:576-637, 861-1083` | `WriteContainerBody`, `RenderInline`, `AddRun`, `AddLinkedText`, `ResolveFormat`, `HasDecoration`, `UniformInlineBackground`, `EnumRuns`, `EffectiveBackground`, `TryGetColor` |
| `AA/Services/HtmlToXamlConverter.cs:180-244, 309-392` | Paste fragments: a context-less `Section` root, with formatting written on **both** the `Span` and its `Run`s |
| `AA/Services/ThemeManager.cs:47-63` | Dark mode overrides the `ControlText`/`GrayText` resource keys, never the paper keys |
| `PROGRESS.md` (PDF fidelity pass, SIRE, HTML paste) | A transparent brush counts as "inherit" in the PDF; the sentinel is excluded from PDF highlight |

#### XD.0.2 Earlier text this addendum refines (the refinement wins)

| Earlier text | Refinement |
|---|---|
| §4.3.1: the root carries the inherited context | CONT-155 distinguishes wrapper roots from content roots. The root's non-inheritable attributes are ignored by every consumer |
| §4.3.7 rule 2 (reuse the root verbatim) | CONT-165: verbatim, **plus completion** of any missing core context attributes |
| §4.3.7 rule 3 (emit only attributes that differ) | CONT-164: exact test, with the `same()` table in XD.2.10 |
| §4.3.7 rule 4 (U+2028 → `<LineBreak />`) | CONT-166: line-break provenance. This also resolves the conflict with 12 §6.5, which writes an in-run `\n` back as `\n` |
| §4.3.7 rule 5 (`TextAlignment` only when not `Left`) | Only when it differs from the **inherited** value. Under an S-1 root this is identical |
| §4.3.7 rule 9 (lock on runs) | An inline sentinel goes on the run's `Background`, or on a lock `Span` (CONT-163). A block sentinel is re-emitted on its block and never copied onto runs |
| §6.2: `linkTextAttributes` containing `.foregroundColor` | MUST NOT contain `.foregroundColor`. Link colour is baked into the text per CONT-167 |
| §6.4, "Character" bullet | Replaced by the computed-style projection in XD.2.8 |
| 12 §6.5 custom key `.xamlFontFamily` | Same meaning as `.aaFontFamilyName`, which is the canonical key |

### XD.1 Feature checklist

**CONT-150 — One DOM for every styled consumer.** Every consumer that needs *formatted* text builds it from the
same `XamlDocument` plus `XamlStyleResolver` (XD.4):
- the container editor and the read-only viewer, through `XamlReader` → `NSAttributedString`;
- the SIRE pane, through the same path;
- the PDF exporter, which reads the DOM directly and never goes through `NSAttributedString` (11 §6.3);
- HTML and XAML paste, where the fragment is parsed and resolved in the destination context (CONT-161);
- the `XamlWriter`, which runs the same resolver over its *output* DOM to decide what to emit (CONT-164).

Plain-text consumers MUST NOT use the DOM, because implicit runs, whitespace rules and error recovery differ. They
work on the raw string, each with its own exact semantics:
- `SearchService.PlainTextFromXaml` (02 REPO-104);
- `DataDiff.PlainText` (01 §3.15);
- `StripXamlTags` (11 §3.4.2);
- the "has notes" `IsNullOrWhiteSpace` checks.

`XamlPlainText` is therefore a separate function over the raw string. It may share the XML tokenizer, but not the
tree.

**CONT-151 — Node kinds.** An element's local name maps case-sensitively to a kind, as in XAML:

| Kind | Category | Content model (WPF) | Notes |
|---|---|---|---|
| `Section` | block / wrapper | blocks | root wrapper (CONT-155) or nested block |
| `FlowDocument` | wrapper | blocks | accepted only as the root; treated as a wrapper root |
| `Paragraph` | block | inlines and text | bare text becomes an implicit `Run` |
| `List` | block | `ListItem`* | |
| `ListItem` | list item | blocks | |
| `Table` | block | `Table.Columns`?, `TableRowGroup`* | |
| `TableColumn` | column | empty | only inside `Table.Columns`; **not** a content ancestor of anything |
| `TableRowGroup`, `TableRow` | table structure | `TableRow`*, `TableCell`* | pass inheritance through |
| `TableCell` | cell | blocks | |
| `BlockUIContainer` | opaque block | one UIElement | subtree preserved raw |
| `Figure`, `Floater` | opaque inline anchor | blocks | preserved raw; the PDF drops them |
| `Run` | inline leaf | text only, or `Text=` | |
| `Span` | inline container | inlines and text | |
| `Bold`, `Italic`, `Underline` | inline container | inlines and text | a `Span` plus a style layer (CONT-157) |
| `Hyperlink` | inline container | inlines and text | a `Span` plus link identity plus a style layer |
| `LineBreak` | inline leaf | empty | |
| `InlineUIContainer` | opaque inline | one UIElement | preserved raw |
| `#text` | character data | — | after XML end-of-line normalisation and the §4.3.1 whitespace rules |
| `unknown(name)` | opaque | — | any other element, including any in a foreign namespace; subtree preserved raw |

Explicit collection property elements are **transparent**: their children are content children of the owner. These
are `Paragraph.Inlines`, `Span.Inlines` (and on `Bold`/`Italic`/`Underline`/`Hyperlink`), `Section.Blocks`,
`ListItem.Blocks`, `TableCell.Blocks`, `List.ListItems`, `Table.RowGroups`, `TableRowGroup.Rows` and
`TableRow.Cells`. Other property elements are handled in CONT-154.

**CONT-152 — Parent links and traversal.** Every node except the root has exactly one content parent.
Property-element subtrees and `TableColumn`s are attached to their owner, but they are **not** content ancestors of
anything: no value is ever inherited from a `TableColumn` or from inside `Run.Foreground`. The required navigation
is:
- `parent(of:)` and `children(of:)`;
- `ancestors(of:)`, nearest first and root last;
- `nearest(_ kind:, from:)`, `enclosingParagraph(of:)` and `enclosingHyperlink(of:)`;
- `inlineAncestors(of:)`: the inline containers between a Run and its Paragraph, nearest first.

Implicit nodes are real nodes with `isImplicit = true` and no attributes. There are three kinds: the synthetic
wrapper root above a content-root fragment, an implicit `Run` around bare text, and an implicit `Paragraph` around
the inlines of a `Span` root. The structure is an index-based arena, a value type with `parent: NodeID?`
(XD.5), so it is `Sendable` and needs no weak references.

**CONT-153 — Raw plus parsed attribute storage.** Each element node stores five things.
1. `rawAttributes`: every attribute except namespace declarations, in source order, as `(qualifiedName as written,
   namespaceURI, value)`. The value is taken after XML entity decoding and attribute-value normalisation.
   "Preserved verbatim" everywhere in this spec means this list.
2. `namespaceDeclarations`: every `xmlns` and `xmlns:p`.
3. `local: XamlLocalValues`: typed values for every *recognised* property of that kind (XD.2.3 and §4.3.3), each
   with its original token, e.g. `fontWeight = (700, "Bold")`. A recognised attribute whose value does not parse is
   **not** stored in `local`. It goes to `local.invalid` and raises `invalidValue` (CONT-162).
4. `propertyElements`: each `<Owner.Prop>` child as `(owner, property, rawXML source slice, parsed value?)`
   (CONT-154).
5. `sourceRange`: the UTF-16 range of the element in the original string, used for byte-for-byte opaque
   preservation (§4.3.7 rule 10).

Text nodes store the decoded string and whether it is whitespace-only. A `Run` takes its text from its content
text, otherwise from the `Text` attribute. If it has both, `runTextAndContent` is raised and the content wins.

**CONT-154 — Property-element values.**
- `X.Foreground`, `X.Background` and `X.BorderBrush` containing `<SolidColorBrush Color="…" [Opacity="…"]/>` →
  `.solid(argb, opacity)`. `Color` follows the §4.3.3 brush grammar. `Opacity` is a double, default 1, clamped to
  0…1 for display.
- Any other brush element (`LinearGradientBrush`, `RadialGradientBrush`, `ImageBrush`, `VisualBrush`,
  `DrawingBrush`) → `.nonSolid(rawXML)`.
- `X.TextDecorations` containing `<TextDecorationCollection>` and/or `<TextDecoration Location="…"/>` → the set of
  locations (`Underline`, `Strikethrough`, `OverLine`, `Baseline`). Pens and offsets are kept only in `rawXML`.
- `Table.Columns` → `TableColumn` nodes.
- Anything else → preserved raw, with no semantic effect.

Setting one property both as an attribute and as a property element is a WPF load error (`duplicateProperty`). In
that case the Mac uses the property element.

A brush attribute value that starts with `{` is a markup extension:
- `{x:Null}` → `.null`, meaning explicitly no brush;
- any other → a `markupExtension` issue, and the value is treated as absent.

**CONT-155 — Root handling.** The first element of the string is the root.
- **Wrapper roots.** These are `Section` (every AA producer), `Span` (WPF clipboard inline fragments) and
  `FlowDocument` (tolerated; AA never writes it).
  - The root's **inheritable** attributes form the document's *root context*. They override the consumer default
    context (CONT-160) for all content.
  - Its **non-inheritable** attributes (`Background`, `Margin`, `Padding`, `BorderThickness`, `BorderBrush`,
    `TextDecorations`, …) are ignored by every consumer. This includes the lock scan: a sentinel on the root locks
    nothing. They are kept raw for the writer.
  - Reason: `TextRange.Load` dissolves the wrapper into the target document **(WPF internal: confirm, XD-Q2)**.
  - A `Span` root's inlines are placed in one implicit `Paragraph`.
- **Content roots.** Any other recognised kind, typically a bare `<Paragraph xmlns="…">`. The DOM inserts an
  implicit, attribute-less wrapper above it. The element's own attributes are then ordinary local values (its
  `Background` is a real paragraph fill), and the root context is just the consumer default. Whether WPF loads
  such a string at all is XD-Q1, so its loadability is `.unconfirmed` (CONT-162).
- **Fresh context per load.** Every load resolves against a fresh context; nothing carries over from the
  previously loaded container. Windows reloads into the same `RichTextBox` document, and whether wrapper values
  applied to that `FlowDocument` leak into the next load is XD-Q4. The Mac MUST NOT leak.

**CONT-156 — Inheritance (the cascade).** The inheritable properties are exactly the ones marked "yes" in XD.2.3:
- `FontFamily`, `FontSize`, `FontWeight`, `FontStyle`, `FontStretch`, `Foreground`;
- `TextAlignment`, `LineHeight`, `LineStackingStrategy`, `FlowDirection`;
- `xml:lang`, `IsHyphenationEnabled`;
- every `Typography.*` and every `NumberSubstitution.*`.

Each one flows from an element to **all** of its content descendants, through every content kind: blocks, list
items, table row groups, rows and cells, and inline containers. This holds even through kinds on which the property
cannot be written as an attribute; for example, a `Table`'s `TextAlignment` reaches the cell paragraphs through
`TableRowGroup` and `TableRow`. Nothing flows out of property elements or `TableColumn`s. `Background` and
`TextDecorations` are **not** inherited (CONT-158).

**CONT-157 — Precedence: local over ancestor.** For every property at every node, the first matching step wins:
1. **Local.** A valid attribute or property element on the node itself wins, even when its value equals a default.
   `FontWeight="Normal"` on a Run inside `<Bold>` makes it normal, and `LineHeight="Auto"` on a Paragraph beats an
   inherited `30`.
2. **Element style layer** (XD.2.4). It applies only when step 1 found nothing on *that* element:
   - `Bold` → FontWeight 700;
   - `Italic` → FontStyle Italic;
   - `Underline` → TextDecorations {Underline};
   - `Hyperlink` → Foreground `linkDefault` and TextDecorations {Underline}.
3. **Inherited** (inheritable properties only): the content parent's computed value.
4. **Root context or consumer default** for inheritable properties; **unset** for non-inheritable ones.

The consequences:
- A Run's own value beats every ancestor.
- An inner Span beats an outer Span, and both beat the Paragraph.
- A Hyperlink's style colour beats a colour inherited from its Paragraph, but loses to a colour set on the
  Hyperlink or on anything below it.

**CONT-158 — Non-inherited properties, per consumer.** These MUST be stated per consumer, because the editor follows
WPF rendering while the PDF follows `PdfExporter`.

| Property on … | Editor, viewer, SIRE pane (WPF and Mac) | PDF (Windows reference, and the Mac default) |
|---|---|---|
| `TextDecorations` on a `Run` | drawn on the Run's text | underline or strike on that Run (PDF-066/067) |
| `TextDecorations` on `Span`, `Bold`, `Italic`, `Underline` (including the `Underline` element's style layer) or a local one on `Hyperlink` | drawn on **all descendant text** (union) | **ignored**: only the Run's own decorations are read (DEV-01, 11 Q1) |
| `TextDecorations` on `Paragraph` | drawn on all of its text | ignored (PDF-075) |
| Hyperlink style-layer underline | drawn on the link's text (on the Mac as a display attribute only, CONT-167) | formal links are always underlined (PDF-071); targetless links are not |
| `Background` on `Run`, `Span`, `Bold`, `Italic`, `Underline` or `Hyperlink` | highlight behind that element's text; a nearer element paints on top | only through `EffectiveBackground` (walk Run → … → Paragraph; first **non-null** brush), giving whole-paragraph shading when uniform (PDF-064b). Partial highlights are dropped (DEV-05) |
| `Background` on `Paragraph` | fills the paragraph box, including Padding | paragraph shading (PDF-064a); the sentinel is **not** excluded |
| `Background` on `TableCell` | cell fill | cell shading (PDF-070) |
| `Background` on `ListItem`, `List`, nested `Section`, `Table`, `TableRowGroup` or `TableRow` | fills that box (Mac: `NSTextBlock`, `NSTextTable`, or per-cell for rows) | ignored |
| `BaselineAlignment` Subscript/Superscript on an inline | shifts that inline's text; the Mac uses the nearest inline ancestor-or-self value that is not `Baseline` **(WPF internal: confirm nesting)** | ignored |
| `Margin`, `Padding`, borders, `TextIndent` | §6.4 | `Margin.Left`, `Margin.Right` and `TextIndent` on Paragraphs (PDF-063); cell borders (PDF-070); the rest ignored |

`TextDecorations="None"` on a descendant does **not** cancel an ancestor's decoration, because decorations combine as
a union **(WPF internal: confirm, XD-Q7)**. The two columns are both intentional. The Mac editor MUST show Span-level
underline, as WPF does. The Mac PDF MUST drop it, as the Windows PDF does, until 11 Q1 is decided.

**CONT-159 — Lock resolution vs PDF highlight resolution.** These are two different ancestor walks, and both are
normative.
- **Lock** (editor, viewer, `LockRules`). A character is locked iff its Run, or **any** content ancestor below the
  root wrapper, has a local `Background` that is `.solid` with ARGB exactly `0xFFFFE699`. The ancestors that count
  are Span, Bold, Italic, Underline, Hyperlink, Paragraph, ListItem, List, TableCell, TableRow, TableRowGroup,
  Table, nested Section, Figure and Floater.
  - `Opacity` is ignored, so a property-element brush with this `Color` and `Opacity="0.3"` counts.
  - `#FFE699` (six digits, so alpha FF) counts; `#80FFE699` does not.
  - `sc#` brushes never count.
  - Source: `IsLockedRun` / `LockedAncestor`, `ContainerEditor.xaml.cs:989-1001, 1219-1227`.
- **PDF highlight.** `EffectiveBackground` stops **after the Paragraph**. The first non-null brush wins, even when it
  is transparent or non-solid, and then it means "no colour". The sentinel exclusion compares **RGB only**
  (`255, 230, 153`, any non-zero alpha), `PdfExporter.cs:1044`.

The two walks disagree on `#80FFE699`: the editor says not locked, while the PDF treats it as the sentinel and does
not shade. Both behaviours are faithful to Windows.

**CONT-160 — Per-consumer default contexts.** Each consumer resolves the cascade over a fixed default context,
listed in XD.2.5. In summary:

| Consumer | Default context |
|---|---|
| Container editor and viewer | Consolas / 14 / `#FF1A1A1A` (the `RichTextBox`) |
| PDF | Segoe UI / 12 px / black (WPF's detached `FlowDocument` defaults) |
| SIRE pane | Segoe UI / 13 / `#FF1A1A1A` (the `DetailBox`) |
| SIRE producer | writes its own full root context (Segoe UI / 13 / Normal / `#FF334155`, or `#FF000000` for pane-generated documents) |

The context only fills properties the document root does not set. Every AA-produced root sets the core ones, so
contexts matter for context-less roots (XD-V8), content roots (XD-V6) and pasted fragments.

**CONT-161 — Fragment insertion context.** Content can enter an existing document through HTML or XAML paste,
*Insert saved list*, *Insert table* or *Insert hyperlink*. In each case the fragment is resolved against the
computed style of the **destination block**, i.e. the caret paragraph's computed style (root context → containers →
paragraph). It is **not** resolved against the caret run's attributes. This is what WPF does, because inserted
elements become siblings of the caret run, not children. For example, `ContainerEditor.xaml.cs:710-714` appends a
new `Hyperlink(new Run(uri))` to the paragraph.
- A fragment root that carries its own context (an AA or WPF XAML clipboard fragment) overrides the destination,
  so copied text keeps its look.
- A context-less root (every `HtmlToXamlConverter` output) contributes nothing.
- *Paste text only* (CONT-034) is different: it uses the caret run's attributes (the typing attributes).
- After an insertion, the first and last paragraphs touched keep the destination paragraph's carried attributes
  (CONT-163). Middle paragraphs that were inserted whole keep their own.
- When the Mac copies, it writes the fragment root as the source document's completed root (CONT-165), so pasting
  elsewhere keeps the look.

**CONT-162 — WPF-loadability verdict.** The parse result carries `loadability`, which is one of `.loadable`,
`.notLoadable(issues)` or `.unconfirmed(reason)`. The checks are in XD.2.12. What each consumer does with it:
- **PDF:** `.notLoadable` → the PDF-060 `StripXamlTags` fallback, exactly as when `TextRange.Load` throws on
  Windows. `.unconfirmed` → render normally until XD-Q1 is answered.
- **Editor, viewer, SIRE pane — fatal issues** (malformed XML, a DTD, a root outside the presentation namespace):
  treated as CONT-006. The editor shows the raw text and withholds, the viewer shows the raw text, and the SIRE pane
  regenerates the original body (`SirePage.xaml.cs:244`).
- **Editor, viewer, SIRE pane — recoverable issues:** displayed tolerantly and flagged:
  - unknown element → opaque attachment;
  - invalid value → the attribute is ignored;
  - text directly in a block container → implicit paragraph;
  - `Text=` together with content → the content wins;
  - duplicate property → the property element wins.
- **Writer:** it never re-emits an invalid recognised attribute, because that would keep the document unloadable on
  Windows.

**CONT-163 — Writer output model: flattened, modelled and carried attributes.**
- **Flattened.** All character formatting on inline containers (`Span`, `Bold`, `Italic`, `Underline`,
  `Hyperlink`), and `Paragraph.TextDecorations`, is resolved into per-character model attributes on read. It is
  written back **only on `Run`s**.
  - The Mac writer never emits `Bold`, `Italic` or `Underline`.
  - It emits `Span` in exactly one case, the **lock Span**: `<Span Background="#FFFFE699">` around a maximal
    sequence of runs whose characters are locked by an *inline ancestor* while their own visible inline background
    is something else (XD-V4c).
  - It emits `Hyperlink` as a link wrapper carrying only its non-formatting attributes: `NavigateUri`,
    `TargetName`, `ToolTip`, `Name`/`x:Name`, `x:Uid`, `Tag`, and unknown attributes.
- **Modelled.** These are regenerated from the Mac model on every write:
  - Paragraph: `TextAlignment`, `LineHeight`, `LineStackingStrategy`, `FlowDirection`, `Margin`, `TextIndent`,
    `Padding`, `BorderThickness`, `BorderBrush`, `Background`;
  - List: `MarkerStyle`, `StartIndex`, `Margin`, `Padding`;
  - Table: `CellSpacing`, `Margin`;
  - TableColumn: `Width`;
  - TableCell: `ColumnSpan`, `RowSpan`, `BorderBrush`, `BorderThickness`, `Padding`, `Background`;
  - every Run attribute.
- **Carried.** Every other raw attribute of a surviving block-level element is re-emitted with its original token.
  The block-level elements are Paragraph, nested Section, List, ListItem, Table, TableRowGroup, TableRow, TableCell
  and TableColumn. Carried attributes include inheritable ones, such as the Windows header-row
  `TableCell FontWeight="Bold"` (`ContainerEditor.xaml.cs:752`) or SIRE's `Paragraph FontSize="20"`. Carried
  *inheritable* attributes still pass through the CONT-164 test, so a carried value equal to the inherited one is
  dropped. A Run's non-formatting raw attributes are carried through `.aaExtraAttributes`.
- **Empty paragraphs.** A paragraph with no characters besides its terminator takes its inheritable *character*
  properties from the terminator's (`\n`) attributes, so the height of a blank line round-trips. These replace any
  carried values for those properties.
- **Paragraph identity.** On the Mac, a paragraph is identified by the `.aaParagraphAttrs` value on its **first**
  character (on its terminator when it is empty). NSTextView copies the value into the new paragraph on Return; WPF
  likewise clones a paragraph's properties on Enter. When two paragraphs are merged, the first one's value wins,
  again as in WPF.

**CONT-164 — The "differs from inherited" test.** This is how the writer decides which inheritable attributes to
emit. For every output element E except the root, and every inheritable property P that is legal on E's kind
(XD.2.3, column "Writable on"):
- emit `P` iff `wanted(E,P) != nil` and `!same(P, wanted(E,P), computedOut(parent(E), P))`;
- `computedOut` applies the CONT-157 precedence to the **output** DOM built so far: first the emitted attributes,
  then the style layers of emitted elements (only `Hyperlink` → `linkDefault` can occur), then inheritance, then the
  writer's root context.

Non-inheritable properties are emitted iff the model sets them on that element, and they are never compared with
ancestors. Nothing can cover them, because the Mac never emits a decoration or a non-sentinel background on an
ancestor of a Run. `wanted()` and `same()` are in XD.2.10.

**CONT-165 — Writer root: verbatim plus completion.**
- The root is `RichTextMetadata.rootAttributes`, i.e. the loaded `Section` root, verbatim.
- Any of the ten core context properties missing from it are appended, in this order, with the tokens of the
  context the document was edited in: `TextAlignment`, `LineHeight`, `xml:lang`, `FlowDirection`, `FontFamily`,
  `FontStyle`, `FontWeight`, `FontStretch`, `FontSize`, `Foreground`. For the container editor the tokens are `Left`,
  `Auto`, `en-us`, `LeftToRight`, `Consolas`, `Normal`, `Normal`, `Normal`, `14`, `#FF1A1A1A`.
- `xmlns` and `xml:space="preserve"` are added if they are missing.
- Why: the Windows editor always writes the full editor context as the root after an edit, so completion makes Mac
  output semantically equal to what Windows writes. For example, a context-less, HTML-shaped root edited on either
  platform stops printing in Segoe UI at 9 pt.
- Non-`Section` roots (`Span`, `FlowDocument`, content roots) are replaced by the canonical S-1 root. For wrapper
  roots, the old wrapper's inheritable attributes override the S-1 values.
- New documents use S-1 unchanged.

**CONT-166 — Line-break provenance.** On read:
- `<LineBreak/>` → U+2028 with no marker.
- A newline **inside Run text** → U+2028 with `.aaInRunNewline` set to the exact original sequence. The newline is
  `\n`, or the character references `&#xD;` / `&#xD;&#xA;`. (XML end-of-line normalisation has already turned a
  literal CR LF into `\n`.)

On write:
- A marked U+2028 → that sequence, inside the current Run's text; a CR is written as `&#xD;`.
- An unmarked U+2028 (Shift+Return on the Mac, or a `LineBreak` read from XAML) → `<LineBreak />`.

Both forms render identically in every consumer. Keeping provenance keeps SIRE bodies byte-stable (12 §6.5) and
keeps `PlainTextFromXaml` output identical, because an in-run `\n` stays inside its text node while `LineBreak` adds
a space.

**CONT-167 — Hyperlink display colour.** On read, a character inside a Hyperlink H is marked `.aaLinkStyled = true`
iff no element on the path from its Run up to and including H sets `Foreground` locally. For such a character:
- `.foregroundColor` is the **display** link colour, `#FF0066CC` on the Mac;
- `.aaUnderlyingForeground` is the colour computed **without** the style layer, which is what the text shows if the
  link is removed.

A character with a local colour at or below H keeps that colour, on WPF and on the Mac alike.

Writer and editing rules:
- The writer maps `.aaLinkStyled` to `linkDefault`, so those runs emit no `Foreground`.
- The link underline is display-only, through `linkTextAttributes = [.underlineStyle: single, .cursor:
  .pointingHand]`. This MUST NOT contain `.foregroundColor` (refines §6.2).
- Targetless hyperlinks SHOULD get the same underline as a layout-manager temporary attribute.
- Removing a link restores `.aaUnderlyingForeground`.
- Setting a colour on link text clears `.aaLinkStyled`.

Windows reference:
- The editable Windows box has `IsDocumentEnabled=False`, so links are drawn in the **disabled** style colour
  `SystemColors.GrayText`: `#FF6D6D6D` in light mode, and the theme's Muted `#FFB0B0B0` in dark mode, because
  `ThemeManager` overrides that key.
- The viewer and the detached PDF document use `HotTrack`, `#FF0066CC`.
- All of this is **(WPF internal: confirm, XD-Q5)**.

The Mac's blue in the editor is the sanctioned §6.2 decision, and it is never persisted.

**CONT-168 — Dark mode and colour space.**
- Every context colour is a fixed sRGB value. No consumer ever resolves an XAML colour to a dynamic `NSColor`
  (`labelColor`, `textColor`, …).
- The editor, viewer and SIRE pane paper stays light in both appearances (§6.2), so the `#FF1A1A1A` defaults stay
  readable.
- PDF colours are absolute (11 PDF-104).
- Changing the app theme never re-resolves a loaded document and never changes stored XAML.
- Windows parity: `ThemeManager` overrides only the `ControlText`/`GrayText` *resources*. The TextElement default
  `Foreground` is a static system brush and is untouched, so the PDF default stays black in dark mode.

### XD.2 Logic & algorithms

#### XD.2.1 Parse pipeline (`XamlDOM.parse`)

```
parse(xaml) -> Result<XamlDocument, XamlFatalError>
 1. Strip one leading U+FEFF. Leading whitespace and an XML declaration are allowed.
 2. "<!DOCTYPE" anywhere before the root           → fatal .dtdPresent   (.NET's reader prohibits DTDs)
 3. Tokenise with namespaces on and external entities off. Keep UTF-16 source ranges (XD.5).
    Malformed XML (including an undefined entity)  → fatal .malformedXML
 4. Root namespace ≠ http://schemas.microsoft.com/winfx/2006/xaml/presentation → fatal .wrongRootNamespace
    (spec 11 §7.11: "<Section><Paragraph>…" without xmlns falls back)
 5. For each element: "Owner.Prop" local name → property element (CONT-154; collection properties transparent);
    known local name in the presentation ns → kind; anything else → .unknown(name) + issue .unknownElement
 6. Attributes: xmlns* → namespaceDeclarations; xml:space, xml:lang (XML ns); x:* → raw only;
    others → raw + parse into `local` when recognised for this kind (XD.2.2/XD.2.3)
      invalid value → .invalidValue; attribute set twice (attr + property element) → .duplicateProperty
      "{…}" other than "{x:Null}" → .markupExtension; unrecognised name → .unknownAttribute (loadability unaffected)
 7. Text, using the effective xml:space (nearest ancestor-or-self; default "default"), per §4.3.1:
      inside Run → the Run's text
      inside Paragraph/Span/Bold/Italic/Underline/Hyperlink → implicit Run per maximal text chunk
      inside Section/FlowDocument/List/ListItem/Table/TableRowGroup/TableRow/TableCell:
          whitespace-only → dropped; other text → .textInBlockContainer (tolerant: implicit Paragraph+Run)
      inline element (Run, Span…) directly in a block container → .invalidNesting (tolerant: implicit Paragraph)
 8. Root classification (CONT-155): wrapper (Section/FlowDocument/Span) or content root under an implicit wrapper;
    Span root → its inlines are placed in an implicit Paragraph
 9. loadability (XD.2.12)
```

#### XD.2.2 Value parsers and canonical forms

| Value | Accepted input | Parsed | Canonical token the Mac writes |
|---|---|---|---|
| Length (FontSize, LineHeight, TextIndent, Thickness parts, absolute column Width) | `^\s*[+-]?(\d+\.?\d*\|\.\d+)([eE][+-]?\d+)?\s*(px\|in\|cm\|pt)?\s*$`, case-insensitive; `in` ×96, `cm` ×96/2.54, `pt` ×96/72; `Auto` or `NaN` → NaN where allowed; invariant `.` decimal | Double in px | shortest round-trip decimal, fixed notation (no exponent), no trailing `.0` (`14`, `14.666666666666666`); NaN → `Auto` |
| FontSize range | `1/300 ≤ v ≤ 35791.3940666667` **(WPF internal: confirm)**; outside → `invalidValue` | | |
| FontFamily | any non-blank string; comma fallback list; `./#Name` / `pack://…#Name` | raw plus `canon` = split on `,`, trim, drop empty parts, invariant lower-case, join with `,` | the raw token |
| FontWeight | names (case-insensitive): Thin 100; ExtraLight/UltraLight 200; Light 300; Normal/Regular 400; Medium 500; DemiBold/SemiBold 600; Bold 700; ExtraBold/UltraBold 800; Black/Heavy 900; ExtraBlack/UltraBlack 950; or an integer 1…999 | Int plus token | preserved token if still consistent (XD.2.10), else 100 `Thin`, 200 `ExtraLight`, 300 `Light`, 400 `Normal`, 500 `Medium`, 600 `SemiBold`, 700 `Bold`, 800 `ExtraBold`, 900 `Black`, 950 `ExtraBlack`, otherwise the integer |
| FontStyle | `Normal`, `Italic`, `Oblique` (case-insensitive) | enum plus token | same names |
| FontStretch | UltraCondensed 1, ExtraCondensed 2, Condensed 3, SemiCondensed 4, Normal/Medium 5, SemiExpanded 6, Expanded 7, ExtraExpanded 8, UltraExpanded 9, or 1…9 | Int | names; `Normal` for 5 |
| Brush | `#RGB`, `#ARGB` (nibbles doubled), `#RRGGBB` (alpha FF), `#AARRGGBB` (hex, case-insensitive); a §4.3.5 name (case-insensitive; `Transparent` = `0x00FFFFFF`); `sc#a,r,g,b` or `sc#r,g,b` (linear floats → sRGB bytes, flagged `isScRgb`); a property element (CONT-154); `{x:Null}` | `XamlBrush` | `#AARRGGBB` upper-case; a preserved property element when unchanged |
| TextDecorations | `None`, or a comma list of `Underline`, `Strikethrough`, `OverLine`, `Baseline` (case-insensitive, spaces allowed) | set | fixed order Underline, Strikethrough, OverLine, Baseline, joined with `,` (`Underline,Strikethrough`) |
| Enums | TextAlignment `Left Right Center Justify`; FlowDirection `LeftToRight RightToLeft`; LineStackingStrategy `MaxHeight BlockLineHeight`; BaselineAlignment `Top Center Bottom Baseline TextTop TextBottom Subscript Superscript`; bool `True False` (all case-insensitive) | enum | the names shown |
| `xml:lang` | any IETF tag, or empty | lower-cased string (WPF `XmlLanguage` normalises to lower case **(confirm)**) | lower case |
| `Typography.*`, `NumberSubstitution.*` | raw tokens | trimmed token | original token |

#### XD.2.3 Inheritance table (normative)

"Writable on" lists the element kinds where WPF's XAML parser accepts the property as a plain attribute. The Mac
writer MUST NOT emit it anywhere else. Inheritance still flows **through** every content kind (CONT-156).

| Property | Inherits | Writable on | WPF default | Editor / viewer / SIRE pane use | PDF use | Mac mapping (XD.2.8) |
|---|---|---|---|---|---|---|
| `FontFamily` | **yes** | every TextElement kind, plus FlowDocument | `SystemFonts.MessageFontFamily` (Segoe UI) | glyph font | `ResolveFontName` (PDF-076) | `.font` family; `.aaFontFamilyName` |
| `FontSize` | **yes** | same | `SystemFonts.MessageFontSize` (12 px) | size | × 0.75 pt | `.font` size (1 px = 1 pt on screen) |
| `FontWeight` | **yes** | same | Normal (400) | weight | ≥ 600 → bold, else explicit NotBold; cell-level bold | weight and bold trait; `.aaFontWeightToken` |
| `FontStyle` | **yes** | same | Normal | italic/oblique | Italic or Oblique → italic | italic trait; `.aaFontStyleToken` |
| `FontStretch` | **yes** | same | Normal (5) | width | ignored | `.aaInheritedExtras` |
| `Foreground` | **yes** | same | `SystemColors.ControlTextBrush` (black) | text colour | solid, alpha ≠ 0 → RGB, else Normal-style black | `.foregroundColor` (sRGB), `.aaLinkStyled` |
| `TextAlignment` | **yes** | Section, Paragraph, List, Table, BlockUIContainer, ListItem, TableCell, FlowDocument | Left **(detached FlowDocument: confirm, XD-Q8)** | paragraph alignment | paragraph alignment | `paragraphStyle.alignment` |
| `LineHeight` | **yes** | same as TextAlignment | Auto (NaN) | line height | ignored | min/max line height |
| `LineStackingStrategy` | **yes** | same as TextAlignment | MaxHeight | stacking | ignored | how LineHeight maps (XD.2.8) |
| `FlowDirection` | **yes** | blocks, ListItem, TableCell, every inline, FlowDocument | LeftToRight | direction | ignored | `baseWritingDirection`, `.writingDirection` |
| `xml:lang` (Language) | **yes** | every element | `en-us` | spelling, hyphenation | ignored | `.aaXmlLang`, `NSLanguage` |
| `IsHyphenationEnabled` | **yes** | blocks, FlowDocument | False | hyphenation | ignored | `hyphenationFactor` 0 or 0.9 |
| `Typography.*` (~40 attached) | **yes** | any element (attached) | the S-1 values | OpenType features; `Variants` → sub/superscript | ignored | `Variants` → `.superscript`; the rest in `.aaInheritedExtras` |
| `NumberSubstitution.*` | **yes** | any element (attached) | CultureSource `User`, Substitution `AsCulture` | digit shaping | ignored | `.aaInheritedExtras` |
| `Background` | no | every TextElement kind, TableColumn | null | CONT-158 | CONT-158 | CONT-158 / XD.2.7 |
| `TextDecorations` | no | inlines, Paragraph | empty | CONT-158 | CONT-158 | `.underlineStyle`, `.strikethroughStyle`, `.aaExtraDecorations` |
| `BaselineAlignment` | no | inlines | Baseline | shift | ignored | `.superscript`, `.baselineOffset`, `.aaBaselineAlignment` |
| `Margin`, `Padding`, `BorderThickness`, `BorderBrush`, `TextIndent`, `KeepTogether`… | no | per §4.3.3 | — | §6.4 | PDF-063/070 | §6.4 |
| `MarkerStyle`, `StartIndex`, `MarkerOffset`, `CellSpacing`, `ColumnSpan`, `RowSpan`, `Width` | no | List, Table, TableCell, TableColumn | — | structure | PDF-069/070 | §6.4 |
| `NavigateUri`, `TargetName` | no | Hyperlink | — | link identity (nearest Hyperlink) | PDF-071/072 | `.link`, `.aaHyperlink` |

#### XD.2.4 Element style layers (CONT-157 step 2)

| Element | Property | Value | Applies in | Notes |
|---|---|---|---|---|
| `Bold` | FontWeight | 700 | every consumer (it is materialised on WPF save) | local `FontWeight` on the `Bold` element overrides it |
| `Italic` | FontStyle | Italic | every consumer | |
| `Underline` | TextDecorations | {Underline} | editor rendering only; the PDF ignores it (DEV-01) | local `TextDecorations` overrides it |
| `Hyperlink` | Foreground | `linkDefault` | editor/viewer display (CONT-167); PDF for **targetless** links' children (`#FF0066CC` **(confirm)**); formal links are forced to `#0B61A4` | Mac stores `.aaLinkStyled = true` and bakes only the *display* colour; the writer maps it back to `linkDefault`, never to an explicit `Foreground` |
| `Hyperlink` | TextDecorations | {Underline} | display only | not part of the model decorations |

WPF supplies these values through theme styles **(WPF internal: confirm)**. On save, WPF writes `Bold`/`Italic`/
`Underline` as `Span` with the value materialised (XD.2.13). The reader MUST support both shapes.

#### XD.2.5 Default contexts (exact values)

| Property | `containerEditor` / `containerViewer` | `pdf` | `sirePane` (saved body loaded into `DetailBox`) | SIRE producer root (12 §3.6) | HTML paste fragment root |
|---|---|---|---|---|---|
| FontFamily | `Consolas` | `Segoe UI` | `Segoe UI` | `Segoe UI` | none (destination, CONT-161) |
| FontSize | 14 | 12 | 13 | 13 | none |
| FontWeight | Normal | Normal | Normal | Normal | none |
| FontStyle / FontStretch | Normal / Normal | Normal / Normal | Normal / Normal | Normal / Normal | none |
| Foreground | `#FF1A1A1A` | `#FF000000` | `#FF1A1A1A` | `#FF334155` (container bodies); `#FF000000` (pane-generated) | none |
| TextAlignment | Left | Left (XD-Q8) | Left | Left | none |
| LineHeight / LineStackingStrategy | Auto / MaxHeight | Auto / MaxHeight | Auto / MaxHeight | Auto / MaxHeight | none |
| FlowDirection | LeftToRight | LeftToRight | LeftToRight | LeftToRight | none |
| `xml:lang` | `en-us` | `en-us` | `en-us` | `en-us` | none |
| IsHyphenationEnabled | False | False | False | False | none |
| Typography.* / NumberSubstitution.* | S-1 values | S-1 values | S-1 values | S-1 values | none |
| `linkDefault` display | `#FF0066CC` (Mac); Windows editor: GrayText | `#FF0066CC` | `#FF0066CC` | — | — |

- The editor and viewer contexts are the `RichTextBox` values (`ContainerEditor.xaml:59-63`,
  `ContainerViewerWindow.xaml:34-37`).
- The PDF context is the WPF default of a detached `new FlowDocument()` (`PdfExporter.cs:586`).
- The SIRE pane context is the `DetailBox` values (`SirePage.xaml:169-172`), which apply because saved bodies load
  into a bare `FlowDocument` (`SirePage.xaml.cs:240`). A freshly generated pane document sets its own values on the
  FlowDocument: Segoe UI / 13 / Normal / Black.

#### XD.2.6 Computed-style algorithm

```
struct Computed { fontFamily, fontSize, fontWeight, fontStyle, fontStretch, foreground, textAlignment, lineHeight,
                  lineStackingStrategy, flowDirection, language, isHyphenationEnabled, typography, numberSubstitution,
                  setter: [Property: NodeID?] }          // which node supplied each value (nil = context)

init(doc, ctx):                                          // one pre-order pass, O(n)
  styles[doc.root] = ctx.overlaid(with: doc.rootRole == .wrapper ? inheritableLocals(doc.root) : [:])
  for node in preorder(doc) where node != root and node is a content node:
     s = styles[parent(node)]                            // inherited (step 3)
     for P in inheritable:
        if let v = node.local[P]           { s[P] = v; s.setter[P] = node }       // step 1
        else if let v = styleLayer(node.kind, P) { s[P] = v; s.setter[P] = node } // step 2 (Bold/Italic/Hyperlink)
     styles[node] = s
own(node, P) for non-inheritable P = node.local[P] ?? styleLayer(node.kind, P) ?? unset
own(root wrapper, P) = unset for every non-inheritable P            // CONT-155
```

`linkDefault` is a symbolic `XamlBrush` case. Each consumer turns it into a concrete colour at projection time
(XD.2.5). `.nonSolid` and `.null` foregrounds are carried as values; the projections decide how to display them.

#### XD.2.7 Rendered (non-inherited) resolution functions

```
modelDecorations(r)   = own(r).deco
                        ∪ ⋃ over a in inlineAncestors(r): (a.local.deco ?? (a.kind == .underline ? {Underline} : ∅))
                        ∪ (paragraph(r).local.deco ?? ∅)
                        // Hyperlink style underline deliberately excluded (display only, CONT-167)
displayDecorations(r) = modelDecorations(r) ∪ ({Underline} if r has a Hyperlink ancestor H with H.local.deco == nil)

inlineBackground(r):                                   // editor model → .backgroundColor
  for a in [r] + inlineAncestors(r):                   // stops BEFORE the Paragraph
     switch a.local.background
       case .solid(argb, op) where alpha(argb) * op > 0: return it
       case .nonSolid:                                  return it   // displayed as none; raw kept
       default: continue                               // absent, transparent or .null → outer paint shows through
  return nil

blockFill(b) = b.local.background  for b in {Paragraph, ListItem, List, nested Section, Table, TableRowGroup,
                                             TableRow, TableCell}; the root wrapper never has one

pdfEffectiveBackground(r):                             // 11 §3.5.6, exact
  for a in [r] + ancestors(r):
     if a.local.background != nil: return it           // even transparent / non-solid / .null
     if a.kind == .paragraph: break
  return nil

lockSource(r):                                         // CONT-159
  if case .solid(0xFFFFE699, _, false) = r.local.background: return .inlineRun
  for a in inlineAncestors(r): if a.local.background is solid 0xFFFFE699 (not scRGB):
        return inlineBackground(r) is that same sentinel ? .inlineRun : .inlineAncestor
  for a in block ancestors of r below the root wrapper: if a.local.background is solid 0xFFFFE699: return .block
  return nil

isLinkStyled(r)  = ∃ H = enclosingHyperlink(r) such that no node in [r … H] has local Foreground
baselineShift(r) = first a in [r] + inlineAncestors(r) with local BaselineAlignment ≠ Baseline:
                       Superscript → +1, Subscript → −1, other → 0 (token preserved)
                   otherwise computed Typography.Variants: Superscript → +1, Subscript → −1, else 0
```

#### XD.2.8 Projection: editor, viewer and SIRE pane → `NSAttributedString`

For every text character of Run `r` in Paragraph `p`, with `cs = computed(r)`:

| Key | Value |
|---|---|
| `.font` | `displayFont(cs)`. Family: first installed part of the family list, else the §6.4 display substitute (Consolas → SF Mono/Menlo, Segoe UI → system font, Calibri → Helvetica Neue, Cambria → Georgia), else the system font. Size: `cs.fontSize` pt. Weight: ≤150 `.ultraLight`, ≤250 `.thin`, ≤350 `.light`, ≤450 `.regular`, ≤550 `.medium`, ≤650 `.semibold`, ≤750 `.bold`, ≤850 `.heavy`, else `.black`. The bold symbolic trait is set iff weight ≥ 600. The italic trait is set iff FontStyle ≠ Normal |
| `.aaFontFamilyName` | raw FontFamily token of `cs.setter[FontFamily]`, or of the context. **Always set**, even when inherited |
| `.aaFontWeightToken` / `.aaFontStyleToken` | raw token of the setter (`"SemiBold"`, `"Light"`, `"Oblique"`, …) |
| `.foregroundColor` | `.solid` → sRGB with alpha = A/255 × opacity; `linkDefault` → the display link colour plus `.aaLinkStyled = true` plus `.aaUnderlyingForeground`; `.nonSolid` or `.null` → the nearest ancestor's solid colour, with the raw kept in `.aaForegroundBrushXml` (`.nonSolid` only) |
| `.backgroundColor` | `inlineBackground(r)`, when solid and visible. Raw non-solid or opacity≠1 brushes go in `.aaBackgroundBrushXml` |
| `.underlineStyle` / `.strikethroughStyle` | `.single` iff Underline / Strikethrough ∈ `modelDecorations(r)`; `.aaExtraDecorations` holds OverLine/Baseline |
| `.superscript` + `.baselineOffset` | `baselineShift(r)`; `.aaBaselineAlignment` = the raw token when one was set |
| `.aaXmlLang` + `NSLanguage` | `cs.language` |
| `.writingDirection` | only when `cs.flowDirection` differs from `computed(p).flowDirection` |
| `.aaInheritedExtras` | `[name: token]` for FontStretch, `Typography.*` and `NumberSubstitution.*` wherever `cs` differs from the root context |
| `.link` / `.aaHyperlink` | nearest Hyperlink: `.link` = `URL(string:)` of the non-blank `NavigateUri` (else the string); `.aaHyperlink` = the hyperlink's element id. Targetless links get only `.aaHyperlink` |
| `.aaLockSource` / `.aaLocked` | `lockSource(r)` / its non-nil-ness (derived) |
| `.aaInRunNewline` | CONT-166 |
| `.aaExtraAttributes` | the Run's unrecognised raw attributes |
| `.paragraphStyle` | from `computed(p)`: alignment; `baseWritingDirection`; LineHeight finite → `minimumLineHeight = LineHeight` (MaxHeight) or min = max = LineHeight (BlockLineHeight) **(approximation, §9 Q8)**; `hyphenationFactor`; plus §6.4 indents and blocks. For RTL paragraphs, `Left`/`Right` are relative to the flow direction (`Left` = leading) **(WPF internal: confirm)** |
| `.aaParagraphAttrs` | p's carried raw attributes (CONT-163), on every character of p including its terminator |

Further rules:
- **Paragraph terminator.** The terminator `\n` of every paragraph carries the projection of `computed(p)`, i.e. the
  paragraph's own character context, not the last run's. This is what the writer reads back for empty paragraphs.
- **List markers.** TextKit 1 `\t{marker}\t` text uses the projection of `computed(ListItem)` **(WPF internal:
  confirm, XD-Q9)**.
- **Typing attributes.** In an empty document, typing attributes are the projection of the root context. After a
  SIRE body is cleared, new text is therefore still Segoe UI 13 `#334155`, as on Windows.

#### XD.2.9 Projection: PDF (spec 11 consumer)

For every non-empty Run segment produced by the PDF-073 link scan, with `cs = computed(r)` under `XamlContext.pdf`:

```
bold      = cs.fontWeight >= 600                  // otherwise TextFormat.NotBold (always explicit)
italic    = cs.fontStyle in {Italic, Oblique}
underline = r.local.textDecorations contains Underline         // the Run's OWN value; implicit runs: none
strike    = r.local.textDecorations contains Strikethrough     // → ApplyStrike / DEV-04
colour    = cs.foreground:  .solid(argb,_) with alpha != 0 → RGB(argb)   (opacity ignored)
                            .linkDefault → RGB(0,102,204)            (targetless-link children only, XD-Q5)
                            anything else → none (Normal style colour, black)
          formal-link text: forced underline + RGB(11,97,164) regardless (PDF-071)
fontName  = ResolveFontName(cs.fontFamily.raw)   (Windows PDF-076; Mac 11 §6.4)
sizePt    = cs.fontSize * 0.75
paragraph: alignment = computed(p).textAlignment; Margin.Left/Right, TextIndent, Background = p.local (own)
cell bold = computed(cell).fontWeight >= 600      (TableCell, via Table/Section/root inheritance)
highlight = UniformInlineBackground over pdfEffectiveBackground (11 §3.5.6), not for list-item paragraphs
```

Before rendering, the PDF MUST check `loadability == .notLoadable` and, if so, use the `StripXamlTags` fallback
(CONT-162).

#### XD.2.10 Writer: output DOM, `wanted()` and `same()`

Building the output DOM:
1. Root: CONT-165. `rootComputed` = the writer context, overlaid with the root's inheritable attributes.
2. Blocks, lists and tables are built per §4.3.7 rules 5–7. Each gets its **carried** attributes (from
   `RichTextMetadata.elementAttributes` or `.aaParagraphAttrs`) and its **modelled** attributes (CONT-163).
3. Inlines of each paragraph:
   - List-marker characters are skipped.
   - A new `Run` starts whenever any writer-relevant key changes. The keys are: family token (or family),
     size, weight token/traits, style, `.aaInheritedExtras`, foreground (including `.aaLinkStyled`),
     `.backgroundColor`, decorations, `.aaXmlLang`, baseline, `.writingDirection`, `.aaExtraAttributes`, lock
     source and `.aaHyperlink`. Display-only differences (for example the substituted NSFont face) never split runs.
   - An unmarked U+2028 → `<LineBreak />`; a marked one stays in the run's text (CONT-166).
   - Consecutive runs with the same `.aaHyperlink` go under one `<Hyperlink …carried…>`.
   - Consecutive runs with `.aaLockSource == .inlineAncestor` go under one lock `Span` (CONT-163).
4. Attributes are emitted top-down. Inheritable attributes use CONT-164. A non-inheritable attribute is emitted iff
   the model sets it on that element:
   - Run `Background` iff `.backgroundColor` (or `.aaBackgroundBrushXml`) is set; the sentinel is used for
     `.inlineRun`;
   - Run `TextDecorations` iff the model decorations are not empty;
   - Run `BaselineAlignment` iff `.aaBaselineAlignment` is set;
   - block attributes as modelled.

`wanted(E, P)`:

| E | `wanted` for inheritable P |
|---|---|
| `Run` | the character's model value: FontFamily = `.aaFontFamilyName` ?? NSFont family; FontSize = point size; FontWeight = `.aaFontWeightToken`'s value if consistent with the bold trait (token ≥ 600 ⇔ bold trait), else 700 or 400 from the trait; FontStyle = `.aaFontStyleToken` if consistent with the italic trait, else Italic or Normal; Foreground = `linkDefault` if `.aaLinkStyled`, else the preserved brush if `.aaForegroundBrushXml` still yields the displayed colour, else the ARGB of `.foregroundColor` (sRGB, each channel `round(c×255)`); language = `.aaXmlLang` ?? root; extras = `.aaInheritedExtras[name]` ?? root value; FlowDirection from `.writingDirection` ?? the paragraph's |
| `Hyperlink`, lock `Span` | nil for every P (flattened) |
| `Paragraph`, non-empty | `TextAlignment`, `LineHeight`, `LineStackingStrategy`, `FlowDirection`: modelled from `paragraphStyle` (always non-nil). Other P: the carried token if present, else nil |
| `Paragraph`, empty | character properties: the terminator's model value; paragraph properties as above |
| `Section`, `List`, `ListItem`, `Table`, `TableRowGroup`, `TableRow`, `TableCell` | the carried token if present, else nil |

`same(P, a, b)`. This is normative, and it is also what the golden tests use:

| P | `same` iff |
|---|---|
| FontFamily | `canon(a) == canon(b)` (XD.2.2) |
| FontSize | both finite and `abs(a − b) ≤ 1e-6` (absorbs `.NET Framework` 15-digit versus shortest-round-trip forms) |
| FontWeight, FontStretch | numeric values equal |
| FontStyle, TextAlignment, FlowDirection, LineStackingStrategy, IsHyphenationEnabled | enum or bool equal (`Italic` ≠ `Oblique`) |
| Foreground | both `.solid` with equal ARGB and `abs(opacityA − opacityB) ≤ 1e-9`; or both `.linkDefault`; or both `.nonSolid` with byte-equal raw XML; or both `.null`. Otherwise **not** same |
| LineHeight | both NaN (`Auto`), or both finite with `abs(a − b) ≤ 1e-6` |
| `xml:lang` | ASCII case-insensitive equality after trimming |
| `Typography.*`, `NumberSubstitution.*` | ASCII case-insensitive equality of the trimmed tokens |

What gets written:
- **Tokens.** Carried attributes keep their original token. Modelled and Run attributes use the canonical tokens
  from XD.2.2.
- **Attribute order.** Not significant to WPF, but fixed for deterministic output:
  - Run: `FontFamily, FontStyle, FontWeight, FontStretch, FontSize, Foreground, Background, TextDecorations,
    BaselineAlignment, FlowDirection, xml:lang`, then `Typography.*` and `NumberSubstitution.*` sorted by name, then
    `.aaExtraAttributes` in source order;
  - Paragraph: carried attributes in source order, then modelled ones in the order `TextAlignment, LineHeight,
    LineStackingStrategy, FlowDirection, Margin, Padding, BorderThickness, BorderBrush, Background, TextIndent`,
    then the empty-paragraph character properties.

#### XD.2.11 Root completion (CONT-165)

```
rootAttributes(meta, W):
  switch meta.rootRole
   case .wrapper(.section): attrs = meta.rootAttributes                     // verbatim, source order
   case .wrapper(.span), .wrapper(.flowDocument):
        attrs = S1Root with (inheritable attrs of the old root) overriding S-1 values
   case .content, .none (new document): attrs = S1Root
  ensure xmlns = presentation ns (prepend if missing); ensure xml:space="preserve" (append if missing)
  for P in [TextAlignment, LineHeight, xml:lang, FlowDirection, FontFamily, FontStyle, FontWeight, FontStretch,
            FontSize, Foreground] where attrs lacks P:
        attrs.append(P = W[P].canonicalToken)
```

#### XD.2.12 Loadability checks (CONT-162)

| Issue | Fatal (no document) | Loadability |
|---|---|---|
| `.malformedXML`, `.dtdPresent`, `.wrongRootNamespace` | yes | n/a (every consumer treats it as a load failure) |
| `.unknownElement(name)` (any namespace) | no | `.notLoadable` |
| `.invalidNesting` (inline in a block container, a non-`ListItem` in `List`, a non-`TableRow` in `TableRowGroup`, a non-`TableCell` in `TableRow`, a block in an inline, non-text content in `Run`) | no | `.notLoadable` |
| `.textInBlockContainer` (non-whitespace text) | no | `.notLoadable` |
| `.invalidValue`, `.duplicateProperty`, `.runTextAndContent`, `.markupExtension` (other than `{x:Null}`) | no | `.notLoadable` |
| `.unknownAttribute` (not in the per-kind list of known WPF properties) | no | unaffected; preserved raw |
| content root (`Paragraph`, …) or a `FlowDocument` root | no | `.unconfirmed` (XD-Q1) |

#### XD.2.13 What WPF does (reference for verifiers; all **(WPF internal: confirm)** by the §9 Q1 fixtures)

- `TextRange.Save` writes the wrapper `Section` with **every** inheritable property of the saved range's context
  (S-1).
- For each descendant element it writes the inheritable properties whose value **differs from the parent's value**,
  and the non-inheritable properties whose value is not the default. CONT-164 mirrors this rule.
- `Bold`, `Italic` and `Underline` elements are written as `Span` with the value materialised: `FontWeight="Bold"`,
  `FontStyle="Italic"`, `TextDecorations="Underline"`. A `Hyperlink` may carry materialised style values (S-5).
- `TextRange.Load` applies the wrapper's inheritable values as the context of the pasted content, either on the
  target `FlowDocument` or as local values on the top-level pasted elements. The computed values are identical
  either way, and computed values are all this contract relies on.

### XD.3 Data formats

- **`data.json` is unchanged.** This addendum adds no keys; it only pins down the shape of the `RichTextXaml` that
  the Mac writer produces. Windows sees:
  - a `Section` root (verbatim plus completion);
  - blocks with their carried and modelled attributes;
  - `Run`s with only the inheritable attributes that differ, plus `Background`, `TextDecorations`,
    `BaselineAlignment` and extra attributes;
  - `Hyperlink` wrappers with `NavigateUri` and the other non-formatting attributes;
  - lock `Span`s (`<Span Background="#FFFFE699">`, the only `Span` the Mac writes);
  - `<LineBreak />` and in-run newlines;
  - never `Bold`, `Italic` or `Underline` elements, and never formatting attributes on `Hyperlink`.

  Every one of these shapes loads in WPF `TextRange.Load` (§7.7 item 10).
- **In-memory attribute keys.** These are never persisted. Their values are property-list types, so they survive
  undo snapshots and in-app copy/paste.

| Key (`NSAttributedString.Key` raw value) | Type | Meaning |
|---|---|---|
| `aa.fontFamilyName` (`.aaFontFamilyName`) | String | WPF family token (12 §6.5 `.xamlFontFamily` is the same key) |
| `aa.fontWeightToken`, `aa.fontStyleToken` | String | original tokens (CONT-163 consistency rule) |
| `aa.inheritedExtras` | `[String: String]` | FontStretch, `Typography.*`, `NumberSubstitution.*` that differ from the root |
| `aa.xmlLang` | String | lower-case language tag |
| `aa.linkStyled` | Bool | CONT-167 |
| `aa.underlyingForeground` | NSColor (sRGB) | the colour when not a link |
| `aa.hyperlink` | String (element id) | link wrapper identity; its carried attributes live in the metadata |
| `aa.foregroundBrushXml`, `aa.backgroundBrushXml` | String | raw property-element brush |
| `aa.extraDecorations` | `[String]` | `OverLine`, `Baseline` |
| `aa.baselineAlignment` | String | raw `BaselineAlignment` token |
| `aa.inRunNewline` | String | `"\n"`, `"\r\n"` or `"\r"` (CONT-166) |
| `aa.paragraphAttrs` | `[[String]]` (name, namespace, value) | carried Paragraph attributes |
| `aa.extraAttributes` | `[[String]]` | unrecognised Run attributes |
| `aa.lockSource` | String: `inlineRun`, `inlineAncestor`, `block` | CONT-159; `.aaLocked` is derived from it. While editing, `.backgroundColor == #FFFFE699` on its own already means `inlineRun`; only `inlineAncestor` and `block` must be stored. Unlocking an `inlineAncestor` stretch clears the key. Unlocking a `block` stretch removes the sentinel `Background` from that block's modelled or carried attributes, so the whole element unlocks, as in CONT-061 |

- **`RichTextMetadata` additions:**
  - `rootAttributes: [XamlRawAttribute]` and `rootRole`;
  - `elementAttributes: [ElementID: [XamlRawAttribute]]` for carried block elements (Section, List, ListItem,
    Table, TableRowGroup, TableRow, TableCell, TableColumn);
  - `hyperlinkAttributes: [ElementID: [XamlRawAttribute]]`;
  - `context: XamlContext`, i.e. which consumer loaded the document; it is also the completion source for
    CONT-165.

### XD.4 Dependencies and Swift API

```swift
// AACore/RichText/XamlDOM.swift
public enum XamlNodeKind: Sendable, Hashable {
    case section, flowDocument, paragraph, list, listItem, table, tableColumn, tableRowGroup, tableRow, tableCell,
         blockUIContainer, figure, floater, run, span, bold, italic, underline, hyperlink, lineBreak,
         inlineUIContainer, text, unknown(String)
}
public struct XamlNodeID: Hashable, Sendable { public let index: Int32 }
public struct XamlRawAttribute: Hashable, Sendable { public let qualifiedName: String; public let namespaceURI: String?; public let value: String }
public enum XamlBrush: Hashable, Sendable {
    case solid(argb: UInt32, opacity: Double, isScRgb: Bool)
    case nonSolid(rawXML: String)
    case null                    // {x:Null}
    case linkDefault             // Hyperlink style layer (symbolic)
}
public struct XamlNode: Sendable {
    public let kind: XamlNodeKind
    public let qualifiedName: String
    public let rawAttributes: [XamlRawAttribute]
    public let namespaceDeclarations: [XamlRawAttribute]
    public let local: XamlLocalValues               // typed, with tokens; .invalid for unparsable recognised attrs
    public let propertyElements: [XamlPropertyElement]
    public let text: String?                        // .text nodes / Run text
    public let isImplicit: Bool
    public let sourceRange: Range<Int>?             // UTF-16 offsets into XamlDocument.source
    public let parent: XamlNodeID?
    public let children: [XamlNodeID]
}
public enum XamlRootRole: Sendable { case wrapper(XamlNodeKind), content(XamlNodeKind) }
public enum XamlLoadability: Sendable { case loadable, notLoadable([XamlIssue]), unconfirmed(String) }
public struct XamlDocument: Sendable {
    public let source: String
    public let nodes: [XamlNode]
    public let root: XamlNodeID                     // wrapper (possibly implicit)
    public let rootRole: XamlRootRole
    public let loadability: XamlLoadability
    public let issues: [XamlIssue]
    public subscript(_ id: XamlNodeID) -> XamlNode { get }
    public func ancestors(of id: XamlNodeID) -> [XamlNodeID]          // nearest first
    public func inlineAncestors(of run: XamlNodeID) -> [XamlNodeID]
}
public enum XamlDOM { public static func parse(_ xaml: String) -> Result<XamlDocument, XamlFatalError> }

// AACore/RichText/XamlStyle.swift
public struct XamlContext: Sendable, Equatable {
    public var fontFamily: String, fontSize: Double, fontWeight: Int, fontStyle: XamlFontStyle, fontStretch: Int
    public var foreground: UInt32, textAlignment: XamlTextAlignment, lineHeight: Double /* NaN = Auto */
    public var lineStackingStrategy: XamlLineStacking, flowDirection: XamlFlowDirection, language: String
    public var isHyphenationEnabled: Bool, typography: [String: String], numberSubstitution: [String: String]
    public var linkDisplayColor: UInt32
    public static let containerEditor, containerViewer, pdf, sirePane: XamlContext      // XD.2.5
}
public struct XamlComputedStyle: Sendable, Equatable { /* XD.2.6 fields + setter ids */ }
public struct XamlStyleResolver: Sendable {
    public init(_ doc: XamlDocument, context: XamlContext)            // O(n) pre-order pass
    public func computed(_ id: XamlNodeID) -> XamlComputedStyle       // O(1)
    public func modelDecorations(_ run: XamlNodeID) -> XamlDecorations
    public func displayDecorations(_ run: XamlNodeID) -> XamlDecorations
    public func inlineBackground(_ run: XamlNodeID) -> XamlBrush?
    public func blockFill(_ block: XamlNodeID) -> XamlBrush?
    public func pdfEffectiveBackground(_ run: XamlNodeID) -> XamlBrush?
    public func lockSource(_ run: XamlNodeID) -> XamlLockSource?
    public func isLinkStyled(_ run: XamlNodeID) -> Bool
    public func baselineShift(_ run: XamlNodeID) -> Int
}
// XamlReader:  (XamlDocument, XamlStyleResolver) -> (NSAttributedString, RichTextMetadata)
// XamlWriter:  (NSAttributedString, RichTextMetadata, XamlContext) -> String      // runs the resolver on its output DOM
// XamlPlainText: raw-string functions only (02 REPO-104, 01 §3.15) — no dependency on XamlDOM's tree
```

| Caller | Uses |
|---|---|
| `XamlReader` (container editor, viewer, SIRE pane) | `parse`, `XamlStyleResolver(.containerEditor / .containerViewer / .sirePane)`, all resolver functions |
| `RichTextToPdf` (spec 11 §6.1) | `parse`, `loadability`, `XamlStyleResolver(.pdf)`, `computed`, `pdfEffectiveBackground`; never `NSAttributedString` |
| `HTMLToXAML` paste (§3.3) | its output → `parse` → resolver with the destination context (CONT-161) |
| `XamlWriter` | `computedOut`, i.e. a resolver instance over the output DOM; `same()` |
| `LockRules` (§3.1) | `.aaLockSource` / `.aaLocked` produced by the reader |
| `SireFlow` port (spec 12) | produces documents whose root carries the SIRE producer context |

Windows-only mechanisms replaced:

| Windows mechanism | Replacement |
|---|---|
| WPF DependencyProperty value precedence and inheritance | `XamlStyleResolver` |
| Theme styles for `Bold`/`Italic`/`Underline`/`Hyperlink` | the XD.2.4 table |
| `TextRange.Load`/`Save` | `XamlDOM`/`XamlReader`/`XamlWriter` |
| `SystemFonts.MessageFontFamily`/`MessageFontSize` | `XamlContext.pdf` constants |
| `SystemColors.ControlText`/`HotTrack`/`GrayText` | constants |
| `BrushConverter`, `FontFamilyConverter`, `LengthConverter`, `FontWeightConverter`, `FontStretchConverter`, `TextDecorationCollectionConverter` | the XD.2.2 parsers |

### XD.5 macOS adaptation notes

- **Value-type arena.** `XamlDocument` is an immutable array of nodes with integer parent links. It is `Sendable`,
  so the PDF exporter can parse and resolve off the main actor from the snapshot taken after flushing editors
  (11 §6.2). The editor parses on load; typical notes are under 5 000 nodes. Budget: parse plus resolve of a 1 MB
  string in under 50 ms on Apple silicon.
- **Tokenizer.** `XMLParser` reports only line and column, not source offsets. Opaque preservation needs exact
  slices, so either:
  - use a small hand-written XML 1.0 tokenizer (the XAML subset has no DTD and no processing instructions except the
    declaration) that records UTF-16 ranges, decodes the five predefined entities plus numeric character references,
    rejects undefined entities, and applies XML end-of-line and attribute-value normalisation; or
  - use `XMLParser` plus a line/column → offset table.

  Both MUST give identical results on the §7.7 and XD.6 vectors.
- **One resolver pass.** Compute the resolver once per document:
  `styles[child] = styles[parent].applying(local(child), styleLayer(child.kind))`. Share `typography` maps
  copy-on-write. Never walk the ancestor chain per character.
- **Display fonts.** Cache the display-font resolution by `canon(family)` plus size and traits. The display
  substitute never leaks into `.aaFontFamilyName`. The font combo in the format bar shows `.aaFontFamilyName`, not
  the substitute, and picking a family replaces the token.
- **Link colour.** Bake it into `.foregroundColor` (CONT-167) and keep colour out of `linkTextAttributes`. This
  avoids NSTextView repainting explicitly coloured link text blue, which WPF never does.
- **Colours.** All colours are created with `NSColor(srgbRed:green:blue:alpha:)` and converted back with
  `usingColorSpace(.sRGB)` before writing. `round(c × 255)` round-trips every 8-bit value exactly.
- **Appearance.** The text view keeps `appearance = .aqua` (§6.2), so the paper and context colours look the same in
  Dark Mode. The format bar and file bank follow the system appearance.
- **Tests.** Swift Testing parameterised tests over XD-V, XD-C, XD-E, XD-W and XD-L, plus the §9 Q1 fixture folder.
  Every fixture is loaded, resolved in all four contexts, written back, and compared by attribute-order-insensitive
  canonical XML.

### XD.6 Test vectors

**Conventions.**
- `R` = the S-1 root. Its context is Consolas / 14 / Normal / Normal / Normal / `#FF1A1A1A` / Left / Auto / LTR /
  `en-us`.
- `P` = `http://schemas.microsoft.com/winfx/2006/xaml/presentation`.
- `F*` = Consolas if installed, otherwise its §6.4 display substitute.
- A PDF formatted-text run is written `FT(text; bold; flags; colour; font Windows|Mac; size)`.
- `PT` = `PlainTextFromXaml`; `DD` = `DataDiff.PlainText`.
- Unless stated otherwise, inputs are the content of `R`.

#### XD.6.1 Cross-consumer vectors

**XD-V1 — Span Foreground over Runs.** Input: `<Paragraph><Span Foreground="#FFC00000"><Run>Warn</Run><Run
FontWeight="Bold" Foreground="#FF0000FF">ing</Run></Span><Run> ok</Run></Paragraph>`
- **Computed:**
  - `Warn`: 400, `#FFC00000`, inherited from the Span;
  - `ing`: 700, `#FF0000FF`; the local value beats the Span;
  - ` ok`: `#FF1A1A1A`, from the root.
- **NSAttributedString:**
  - `Warn`: {F* 14 regular, aaFontFamilyName "Consolas", fg #C00000 α1, aaXmlLang en-us};
  - `ing`: {F* 14 bold, aaFontWeightToken "Bold", fg #0000FF};
  - ` ok`: {F* 14 regular, fg #1A1A1A};
  - paragraph style: left, no text block.
- **PDF** (Windows and Mac): Para{Left, no shading}; `FT(Warn; NotBold; RGB(192,0,0); Consolas|Menlo; 10.5)`,
  `FT(ing; Bold; RGB(0,0,255); 10.5)`, `FT( ok; NotBold; RGB(26,26,26); 10.5)`.
- **Mac writer** (after an edit elsewhere): `<Paragraph><Run Foreground="#FFC00000">Warn</Run><Run FontWeight="Bold"
  Foreground="#FF0000FF">ing</Run><Run> ok</Run></Paragraph>`. The Span is flattened; runs split exactly where the
  attributes differ.
- **Plain text**, before and after: `PT` = `" Warn ing  ok "`, `DD` = `"Warn ing ok"`.

**XD-V2 — `Underline` element (plus `Bold`).** Input: `<Paragraph><Underline>Hello</Underline><Run> </Run><Bold><Run
TextDecorations="Underline">world</Run></Bold></Paragraph>`
- **Computed:**
  - `Hello`: an implicit Run; 400; model decorations {Underline}, from the Underline style layer on its ancestor;
  - ` `: nothing;
  - `world`: 700, from the Bold style layer; its own decorations are {Underline}.
- **NSAttributedString:** `Hello` {F* 14 regular, underlineStyle single}; ` ` {regular}; `world` {F* 14 bold,
  underlineStyle single}.
- **PDF:**
  - `FT(Hello; NotBold; **no underline**; RGB(26,26,26); 10.5)`. The underline lives on the element, not the Run
    (DEV-01).
  - `FT( ; NotBold)`.
  - `FT(world; Bold; underline; 10.5)`.
- **Mac writer:** `<Paragraph><Run TextDecorations="Underline">Hello</Run><Run> </Run><Run FontWeight="Bold"
  TextDecorations="Underline">world</Run></Paragraph>`. After a Mac save, both PDFs underline `Hello` (XD-X1).
- **`PT`**, before and after: `" Hello   world "`. The whitespace-only `<Run> </Run>` is a SignificantWhitespace node
  under `xml:space="preserve"`.

**XD-V3 — Nested Section with FontSize.** Input: `<Section FontSize="20" Foreground="#FF006400"
TextAlignment="Center"><Paragraph><Run>Big</Run><Run FontSize="10">small</Run></Paragraph></Section><Paragraph><Run>after</Run></Paragraph>`
- **Computed:**
  - `Big`: 20, `#FF006400`, Center;
  - `small`: 10, `#FF006400`, Center;
  - `after`: 14, `#FF1A1A1A`, Left.
- **NSAttributedString:**
  - paragraph 1 {alignment center, aaSectionPath [s1]; no NSTextBlock, because the Section has no
    background, border or padding}: `Big` {F* 20, fg #006400}, `small` {F* 10, fg #006400};
  - paragraph 2 {left}: `after` {F* 14, fg #1A1A1A}.
- **PDF:** the Section is transparent. Para{Center}: `FT(Big; NotBold; RGB(0,100,0); 15)`,
  `FT(small; RGB(0,100,0); 7.5)`. Para{Left}: `FT(after; RGB(26,26,26); 10.5)`.
- **Mac writer:** returns the input unchanged, apart from attribute order:
  - the Section's carried `FontSize`, `Foreground` and `TextAlignment` all differ from `R`, so they are kept;
  - the Paragraph's modelled `TextAlignment` (Center) equals the inherited value, so it is omitted;
  - `Big` matches what it inherits, so it gets no attributes;
  - `small` gets `FontSize="10"`.

**XD-V4 — Paragraph Background (a) with an inline highlight, plus lock variants.**
- **V4a.** Input: `<Paragraph Background="#FFFFFF00"><Run>Note: </Run><Run Background="#FF00FF00">green</Run></Paragraph>`
  - **Editor:** the paragraph's NSTextBlock background is #FFFF00 (it fills the block box); `Note: ` has no
    `.backgroundColor`; `green` has `.backgroundColor` #00FF00; nothing is locked.
  - **PDF:** rule (a) shades RGB(255,255,0). Rule (b) finds `EffectiveBackground` = yellow (the Paragraph) and
    green, which are mixed, so it gives none. The paragraph is therefore yellow, and the green is dropped (DEV-05).
    `FT`s are 10.5 pt RGB(26,26,26).
  - **Writer:** returns the input unchanged.
- **V4b.** Input: `<Paragraph Background="#FFFFE699"><Run>7.5 bar</Run></Paragraph>`
  - **Editor:** every character has `.aaLockSource = block`; the NSTextBlock background is pale gold; there is no
    `.backgroundColor`.
  - **PDF:** rule (a) shades RGB(255,230,153); rule (a) has no exclusion (11 §7.9).
  - **Writer:** the sentinel stays on the `Paragraph`, and the runs get no Background.
- **V4c.** Input: `<Paragraph><Span Background="#FFFFE699"><Run Background="#FFFFFF00">x</Run></Span></Paragraph>`
  - **Editor:** `.backgroundColor` is #FFFF00, because the nearer brush paints on top. `.aaLockSource` is
    `inlineAncestor`, so the text is locked (any ancestor counts).
  - **PDF:** `EffectiveBackground` = yellow, uniform, so the paragraph is shaded RGB(255,255,0).
  - **Writer:** `<Paragraph><Span Background="#FFFFE699"><Run Background="#FFFFFF00">x</Run></Span></Paragraph>`.
    The lock Span keeps both the lock and the highlight.

**XD-V5 — TableCell FontWeight.** Input: `<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn
/><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6"
BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1" FontWeight="Bold"
TextAlignment="Right"><Paragraph><Run>Head</Run><Run FontWeight="Normal"> (n)</Run></Paragraph></TableCell><TableCell
BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6"
Padding="3,1,3,1"><Paragraph><Run>x</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>`
- **Computed:**
  - `Head`: 700, inherited from the cell; Right, inherited from the cell;
  - ` (n)`: 400 (local);
  - `x`: 400, Left.
- **NSAttributedString:** an NSTextTable with 2 columns and `collapsesBorders`.
  - Cell (0,0): border 0.6 #9AA0A6, padding 3/1/3/1; paragraph right-aligned; `Head` {F* 14 bold, token "Bold"};
    ` (n)` {F* 14 regular, token "Normal"}.
  - Cell (0,1): paragraph left-aligned; `x` {regular}.
- **PDF:** 2 columns of 8 cm.
  - Cell (0,0): `Format.Font.Bold = true`, border 0.6 pt RGB(154,160,166). Para{Right}:
    `FT(Head; Bold; RGB(26,26,26); 10.5)`, `FT( (n); NotBold; 10.5)`. The explicit NotBold overrides the cell
    format.
  - Cell (0,1): no cell bold. Para{Left}: `FT(x; NotBold)`.
- **Mac writer:** returns the input unchanged:
  - the cell's carried `FontWeight="Bold"` and `TextAlignment="Right"` differ from `R`, so they are kept;
  - the Paragraph's alignment equals the inherited value, so it is omitted;
  - ` (n)` gets `FontWeight="Normal"`.

**XD-V6 — Root-less Paragraph fragment.** Input (the whole string): `<Paragraph
xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" FontSize="16"
TextAlignment="Center"><Run>Hi </Run><Bold>there</Bold></Paragraph>`

DOM: an implicit wrapper, then the content-root Paragraph (local FontSize 16, TextAlignment Center), containing `Run`
"Hi " and `Bold` → implicit `Run` "there". Loadability: `.unconfirmed` (XD-Q1).

| Consumer | `Hi ` | `there` | Paragraph |
|---|---|---|---|
| Editor / viewer (Mac) | F* 16 regular, fg #1A1A1A, aaFontFamilyName "Consolas" (from the context) | F* 16 bold | center; aaParagraphAttrs = [FontSize="16"] |
| SIRE pane | system font (Segoe UI) 16, #1A1A1A | bold | center |
| PDF, WPF-loads branch | `FT(Hi ; NotBold; RGB(0,0,0); Segoe UI\|system UI; 12)` | `FT(there; Bold; RGB(0,0,0); 12)` | Para{Center} |
| PDF, if XD-Q1 shows WPF rejects it | fallback: one Normal paragraph `Hi   there` (from `StripXamlTags`; three spaces) | | |

- **Mac writer** (after an edit in the container editor): S-1 root +
  `<Paragraph FontSize="16" TextAlignment="Center"><Run>Hi </Run><Run FontWeight="Bold">there</Run></Paragraph>`.
  The Bold is flattened. From then on, the Windows PDF prints Consolas 12 pt RGB(26,26,26).
- **`PT`**, before and after: `" Hi  there "`.

**XD-V7 — Hyperlink style layer.** Input: `<Paragraph Foreground="#FF800080"><Hyperlink
NavigateUri="https://www.imo.org"><Run>IMO</Run></Hyperlink><Run> and
</Run><Hyperlink><Run>x</Run><Run Foreground="#FFFF0000">y</Run></Hyperlink></Paragraph>`
- **Computed:**
  - `IMO`: `linkDefault`, because the style layer beats the inherited purple;
  - ` and `: #FF800080;
  - `x`: `linkDefault`;
  - `y`: #FFFF0000 (local).
- **Windows editor display:** `IMO` and `x` in GrayText, underlined; `y` red, underlined; ` and ` purple. In the
  viewer, `IMO` and `x` are #0066CC.
- **NSAttributedString:**
  - `IMO`: {fg #0066CC, aaLinkStyled, aaUnderlyingForeground #800080, link https://www.imo.org, aaHyperlink h1};
  - ` and `: {fg #800080};
  - `x`: {fg #0066CC, aaLinkStyled, underlying #800080, aaHyperlink h2, no `.link`; temporary underline};
  - `y`: {fg #FF0000, aaHyperlink h2}.
- **PDF:**
  - `IMO`: a link to `https://www.imo.org` with `FT(IMO; NotBold; underline; RGB(11,97,164); 10.5)` (PDF-071);
  - `FT( and ; RGB(128,0,128))`;
  - the targetless link is rendered as ordinary runs (PDF-072): `FT(x; RGB(0,102,204) (XD-Q5); no underline)`,
    `FT(y; RGB(255,0,0); no underline)`.
- **Mac writer:** returns the input unchanged:
  - the Paragraph's carried Foreground is kept;
  - `IMO` and `x` want `linkDefault`, which is what they inherit, so they get no attributes;
  - ` and ` inherits purple, so it gets no attributes;
  - `y` keeps its Foreground.

**XD-V8 — Context-less Section root (the HTML-paste shape) and root completion.** Input (the whole string):
`<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph><Run>plain</Run><Run FontSize="16">big</Run></Paragraph></Section>`

| Consumer | `plain` | `big` |
|---|---|---|
| Editor / viewer | F* 14, #1A1A1A | F* 16 |
| SIRE pane | Segoe UI (system) 13, #1A1A1A | 16 |
| PDF (Windows and Mac) | `FT(plain; NotBold; RGB(0,0,0); Segoe UI\|system UI; 9)` | `FT(big; 12)` |

- **Mac writer** (after an edit in the container editor): the root becomes `<Section xml:space="preserve"
  xmlns="…" TextAlignment="Left" LineHeight="Auto" xml:lang="en-us" FlowDirection="LeftToRight"
  FontFamily="Consolas" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="14"
  Foreground="#FF1A1A1A">`, and the content is unchanged.
- From then on, the PDF prints `FT(plain; Consolas|Menlo; 10.5; RGB(26,26,26))` and `FT(big; 12)`. This is the same
  result Windows gives after a Windows-side edit.

#### XD.6.2 Computed-style unit vectors (editor context, inside `R`)

| # | Input | Expected |
|---|---|---|
| XD-C1 | `<Paragraph><Bold FontWeight="Normal"><Run>a</Run></Bold></Paragraph>` | a: weight 400 (a local value on `Bold` beats its style layer) |
| XD-C2 | `<Paragraph><Bold><Run FontWeight="Light">a</Run></Bold></Paragraph>` | 300; NS light face, no bold trait, token "Light"; PDF NotBold |
| XD-C3 | `<Paragraph><Italic><Bold>a</Bold></Italic></Paragraph>` | 700, Italic |
| XD-C4 | `<Paragraph><Underline TextDecorations="Strikethrough">a</Underline></Paragraph>` | model {Strikethrough} only; PDF: neither |
| XD-C5 | `<List TextAlignment="Right"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem></List>` | paragraph Right; PDF list paragraph Right |
| XD-C6 | `<Section LineHeight="30"><Paragraph><Run>a</Run></Paragraph><Paragraph LineHeight="Auto"><Run>b</Run></Paragraph></Section>` | P1 LineHeight 30; P2 Auto (a local Auto beats the inherited 30) |
| XD-C7 | `<Table FontSize="10"><Table.Columns><TableColumn Background="#FFFF0000"/></Table.Columns><TableRowGroup><TableRow><TableCell><Paragraph><Run>a</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>` | a: size 10 (through the row group, row and cell); the column Background has no effect on the cell text or its fill |
| XD-C8 | `<Paragraph xml:lang="el-gr"><Run>a</Run><Run xml:lang="EN-GB">b</Run></Paragraph>` | a: `el-gr`; b: `en-gb` |
| XD-C9 | `<Paragraph><Span Background="#FFFFFF00"><Run Background="#00FFFFFF">a</Run></Span></Paragraph>` | editor `.backgroundColor` #FFFF00 (the transparent inner brush is skipped); PDF `EffectiveBackground` = the transparent run brush, so no shading |
| XD-C10 | `<Paragraph><Run Background="#80FFE699">a</Run></Paragraph>` | not locked; editor bg #FFE699 α 0.5; PDF: uniform colour RGB = sentinel, so **no** shading |
| XD-C11 | `<Paragraph TextDecorations="Strikethrough"><Run TextDecorations="Underline">a</Run></Paragraph>` | editor underline + strike; PDF underline only |
| XD-C12 | `<Paragraph><Run><Run.Foreground><SolidColorBrush Color="#FFFF0000" Opacity="0.5"/></Run.Foreground>a</Run></Paragraph>` | editor fg rgba(1,0,0,0.5), with `aaForegroundBrushXml` set; PDF RGB(255,0,0) (opacity ignored); the writer re-emits the property element |
| XD-C13 | `<Paragraph><Run Foreground="Transparent">a</Run></Paragraph>` | editor: invisible (parity); PDF: no colour, so the Normal style's black |
| XD-C14 | `<Section FontWeight="Bold"><Table><TableRowGroup><TableRow><TableCell><Paragraph><Run>a</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table></Section>` | PDF cell bold; `FT(a; Bold)` |
| XD-C15 | whole string `<Section xmlns="P" xml:space="preserve" Background="#FFFFE699"><Paragraph><Run>a</Run></Paragraph></Section>` | not locked; no paragraph fill; PDF no shading (root non-inheritable ignored, XD-Q2) |
| XD-C16 | `<Paragraph><Hyperlink Foreground="#FF008000" NavigateUri="https://a.b"><Run>a</Run></Hyperlink></Paragraph>` | a: green, `aaLinkStyled` false; PDF forced RGB(11,97,164) (formal link) |
| XD-C17 | SIRE producer root (Segoe UI / 13 / #FF334155) + chip `<Paragraph Margin="0,2,0,8" Padding="10,8,10,8" Background="#FFF8FAFC"><Run Foreground="#FF334155">full</Run></Paragraph>` | editor: system font 13, #334155, NSTextBlock bg #F8FAFC with padding 10/8/10/8; PDF: shading RGB(248,250,252), `FT(full; Segoe UI\|system UI; 9.75; RGB(51,65,85))`; writer: the Run's `Foreground` equals the root, so it is dropped (semantically equal) |
| XD-C18 | whole string `<Span xmlns="P" FontWeight="Bold"><Run>x</Run></Span>` | a wrapper Span root; an implicit paragraph; x weight 700 |

#### XD.6.3 `same()` vectors

| # | a | b | same? |
|---|---|---|---|
| XD-E1 | FontWeight `Bold` | `700` | yes |
| XD-E2 | FontWeight `Regular` | `Normal` | yes |
| XD-E3 | FontWeight `SemiBold` | `DemiBold` | yes |
| XD-E4 | FontWeight `Medium` | `Normal` | no |
| XD-E5 | FontSize `12pt` | `16` | yes |
| XD-E6 | FontSize `16px` | `16` | yes |
| XD-E7 | FontSize `14.666666666666666` | `14.6666666666667` | yes |
| XD-E8 | FontSize `14` | `14.00001` | no |
| XD-E9 | FontFamily `Segoe UI, Arial` | `segoe ui,Arial` | yes |
| XD-E10 | FontFamily `Consolas` | `Consolas, Courier New` | no |
| XD-E11 | Foreground `Red` | `#FFFF0000` / `#F00` | yes |
| XD-E12 | Foreground `#80FF0000` | `#FFFF0000` | no |
| XD-E13 | Foreground `Transparent` | `#00FFFFFF` | yes |
| XD-E14 | Foreground `#00000000` | `Transparent` | no |
| XD-E15 | Foreground `linkDefault` | `#FF0066CC` | no |
| XD-E16 | LineHeight `Auto` | `NaN` | yes |
| XD-E17 | LineHeight `Auto` | `20` | no |
| XD-E18 | `xml:lang` `en-US` | `en-us` | yes |
| XD-E19 | `Typography.Kerning` `True` | `true` | yes |
| XD-E20 | FontStyle `Oblique` | `Italic` | no |

#### XD.6.4 Writer vectors

| # | Model / input | Expected output |
|---|---|---|
| XD-W1 | an empty paragraph whose terminator has F* 20 (aaFontFamilyName "Consolas"), #1A1A1A, under `R` | `<Paragraph FontSize="20" />` |
| XD-W2 | read `<Paragraph><Run FontFamily="Consolas" FontSize="14" Foreground="#FF1A1A1A">x</Run></Paragraph>` and write it | `<Paragraph><Run>x</Run></Paragraph>` (redundant locals dropped; K-7 cleanup) |
| XD-W3 | `<Run FontWeight="SemiBold">x</Run>`; then bold turned off; then on again | `FontWeight="SemiBold"`; then no FontWeight; then `FontWeight="Bold"` |
| XD-W4 | `<Paragraph><Run>a⏎b</Run><LineBreak /><Run>c</Run></Paragraph>` (⏎ = a literal LF in the Run) | byte-identical; `PT` = `" a\nb  c "` |
| XD-W5 | `<Run Foreground="Red">x</Run>`, where the parent colour differs | `<Run Foreground="#FFFF0000">x</Run>` (colours are always canonical) |
| XD-W6 | `<ListItem FontSize="14"><Paragraph><Run>a</Run></Paragraph></ListItem>` under `R` | `<ListItem>…` (a carried value equal to the inherited one is dropped) |
| XD-W7 | a Consolas run displayed with Menlo; the user then picks "Menlo" for `x` | no FontFamily; then `<Run FontFamily="Menlo">x</Run>` |
| XD-W8 | the user merges two paragraphs, `<Paragraph FontSize="20">` followed by `<Paragraph>` | the merged paragraph keeps `FontSize="20"` (from the first character); runs from the second paragraph get `FontSize="14"` |
| XD-W9 | V4c, V6, V7 and V8 | as stated there |

#### XD.6.5 Loadability vectors

| # | Input (whole string) | Verdict | PDF | Editor |
|---|---|---|---|---|
| XD-L1 | `<Section><Paragraph>Hi</Paragraph></Section>` (no xmlns) | fatal `.wrongRootNamespace` | fallback `Hi` (11 §7.11) | CONT-006 raw + withheld |
| XD-L2 | `<Section xmlns="P"><Run>x</Run></Section>` | `.notLoadable` (invalidNesting) | fallback `x` | `x` in an implicit paragraph, flagged |
| XD-L3 | `<Section xmlns="P"><Paragraph><Foo>x</Foo></Paragraph></Section>` | `.notLoadable` (unknownElement) | fallback `x` | opaque chip |
| XD-L4 | `<Section xmlns="P"><Paragraph FontSize="abc"><Run>x</Run></Paragraph></Section>` | `.notLoadable` (invalidValue) | fallback `x` | x at 14; the writer drops `FontSize="abc"` |
| XD-L5 | `<!DOCTYPE x><Section xmlns="P"/>` | fatal `.dtdPresent` | fallback (empty after stripping, so nothing is printed) | CONT-006 |
| XD-L6 | the V6 string | `.unconfirmed` | rendered (V6) | rendered |
| XD-L7 | `<Section xmlns="P"><Paragraph><Run Text="a">b</Run></Paragraph></Section>` | `.notLoadable` (runTextAndContent) | fallback `b` | `b` |
| XD-L8 | `<Section xmlns="P"><Paragraph><Run Foreground="#FF00FF00"><Run.Foreground><SolidColorBrush Color="Red"/></Run.Foreground>x</Run></Paragraph></Section>` | `.notLoadable` (duplicateProperty) | fallback `x` | x red |
| XD-L9 | `<Section xmlns="P"><Paragraph><Run Foreground="{StaticResource Fg}">x</Run></Paragraph></Section>` | `.notLoadable` (markupExtension) | fallback `x` | x inherits #1A1A1A |
| XD-L10 | `<Section xmlns="P"><Paragraph><Run Foo="1">x</Run></Paragraph></Section>` | `.loadable` (unknownAttribute noted) | rendered | `Foo="1"` kept in `.aaExtraAttributes` and re-emitted |

### XD.7 Quirks and porting decisions

| ID | Behaviour | Decision |
|---|---|---|
| XD-X1 | Decorations on a Span, `Underline` element, Hyperlink or Paragraph are flattened onto Runs by the Mac writer. After a Mac save, both PDFs print underlines and strikes that DEV-01 / PDF-075 used to drop. | Accept: it brings the PDF closer to the editor. Report to the Windows owner. The alternative is in XD-Q3. |
| XD-X2 | A transparent inner inline background inside a coloured Span: the editor shows the outer colour, the PDF treats it as no colour. The Mac writer writes the visible colour on the Run, so the PDF may start shading it. | Accept (rare; closer to what the user sees). |
| XD-X3 | The PDF sentinel test is RGB-only; the editor lock test is exact ARGB (XD-C10). | Faithful on both sides; do not unify. |
| XD-X4 | The Windows editor draws links in the disabled grey, which becomes light grey on the paper in dark mode. The viewer uses blue. | The Mac shows #0066CC everywhere (§6.2); display only. |
| XD-X5 | Context-less roots print in Segoe UI 9 pt black on Windows until someone edits the note. | The Mac's root completion (CONT-165) makes the same change a Windows edit would. |
| XD-X6 | The Windows editor may leak wrapper context between containers loaded into the same `RichTextBox` (XD-Q4). | The Mac resolves every load against a fresh context. |
| XD-X7 | Non-formatting attributes on flattened inline containers (a Span's `Tag`, `ToolTip`, `Name`) are dropped by the Mac writer. AA never produces them. | Accept. Hyperlink and Run keep theirs. |
| XD-X8 | A `{x:Null}` Foreground: WPF draws no text. | The Mac displays the inherited colour and writes nothing for it. |
| XD-X9 | Several semi-transparent inline backgrounds stacked on top of each other. | The Mac shows only the nearest one (no compositing); display only. |

### XD.8 Open questions (each needs a Windows fixture in `mac/Tests/Fixtures/xaml/`, §9 Q1)

1. **XD-Q1.** Does `TextRange.Load` accept a bare `Paragraph` root (V6)? And a `FlowDocument` root: silently empty,
   or a throw? The answer fixes `.unconfirmed` → `.loadable` or `.notLoadable`.
2. **XD-Q2.** Are a wrapper root's non-inheritable attributes (`Background="#FFFFE699"`, `Margin`) really dropped on
   load (XD-C15)?
3. **XD-Q3.** Should the Mac writer keep Span-level `TextDecorations`, so that the Windows PDF output stays
   byte-for-byte the same after a Mac edit, or flatten them (the default, XD-X1)?
4. **XD-Q4.** Does the Windows editor carry wrapper values applied to its `FlowDocument` over into the next
   container load?
5. **XD-Q5.** Hyperlink style values: is the editor colour GrayText and the viewer colour HotTrack? Does
   `TextRange.Save` materialise `Foreground` / `TextDecorations` on the `Hyperlink`? Does the detached PDF document
   apply theme styles, so that the text of a targetless link is `#0066CC` in the PDF?
6. **XD-Q6.** Does `TextRange.Save` write `Bold`, `Italic` and `Underline` as `Span` with materialised values?
7. **XD-Q7.** Exact union semantics of `TextDecorations` (is a descendant's `None` ignored?) and how
   `BaselineAlignment` nests.
8. **XD-Q8.** The default `TextAlignment` of a detached `FlowDocument`: `Left`, or `Justify` from its theme style? It
   matters only for root-less fragments in the PDF.
9. **XD-Q9.** Are list markers drawn with the `ListItem`'s computed font and colour, or with the first run's?
