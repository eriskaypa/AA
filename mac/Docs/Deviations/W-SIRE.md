# W-SIRE — P2 fixes and sanctioned deviations (ARCHITECTURE.md §12.2)

Spec 12 (SIRE 2.0), DECISIONS 12. Stage V merges these rows into `Docs/DEVIATIONS.md`.

## P2 fixes (spec §8 "Fix" decisions)

| ID | Spec ref | Fix |
|---|---|---|
| Q-3 | SIRE-048, §8, DECISIONS 12 | The question list is multi-select (⌘-click / ⇧-click); `Selected Questions` exports the selected rows in natural order; the detail shows the last-clicked row. |
| Q-4 | SIRE-029 | The AI Suggest result is added to the question that was selected when the request started (prompt text and add target). |
| Q-5 | SIRE-038, BUILD-A26 | Clearing the Gemini key deletes the Keychain item; nothing falls back to an older value. |
| Q-8 | SIRE-023, §6.4 rule 9 | The body is flushed on selection change, focus loss, every app-wide flush (⌘S, 5-min autosave, quit, sync, Flash Sync, item windows) and after 750 ms of idle typing. |
| Q-9 | §6.4 rule 10 | Saved edits that cannot be read are never overwritten silently: the original is shown read-only with the banner `Your saved edits for this question could not be displayed on this Mac. They are kept unchanged.` and the actions `Reset to original` / `Edit anyway (replaces saved edits)`. |
| Q-10 | SIRE-036/040, §6.8, §6.11 | The export sheet waits for a running bank load (progress shown; dismissing the wait shows the Windows "still loading" text); a data-model swap re-filters the list. |
| Q-11 | SIRE-030, VIEW-210 | The candidate picker keeps ticks across searching; `Select All` / `Select None` added. |
| Q-12 | §3.10 | Exports use LF line endings (UTF-8 without BOM). |
| Q-14 | §3.10 | `Generated:` and file-name stamps use `yyyy-MM-dd HH:mm` / `yyyyMMdd_HHmm` with a fixed `:` (Gregorian, en_US_POSIX, local zone). |
| SIRE-015 | §6.1 | A re-filter that keeps the selected question flushes pending body edits and does not rebuild the editor. |

## Sanctioned deviations and Mac additions (P4)

| ID | Spec ref | Deviation |
|---|---|---|
| D-SIRE-01 | Q-6, DECISIONS 12 | Gemini: same model / temperature, `maxOutputTokens` raised to 8192; the key travels in the `x-goog-api-key` header (never in the URL). |
| D-SIRE-02 | §4.3, DECISIONS 12 | The Gemini key lives in the login Keychain (`com.eriskay.aa.gemini` / `GeminiApiKey`). A `GeminiApiKey` found in settings.json is copied into the Keychain once (MacPreferences `aa.sire.geminiImported`, set only when a key was found) and the settings value is left untouched (DECISIONS wins over spec §4.3 "removes it"). |
| D-SIRE-03 | SIRE-038, §6.9, BUILD-143/148 | Tools ▸ Set Gemini API Key… uses the secure prompt with a reveal toggle, the Mac wording `Paste your Google Gemini API key (stored securely in this Mac's Keychain, never synced):` and the helper line `Leave blank and click OK to remove the key.`; Settings ▸ AI adds Save / Clear. |
| D-SIRE-04 | SIRE-012, DECISIONS 12 | Filter state (sort, evidence, status, unticked chapter / vessel / type boxes, expanders, filter-pane visibility) and the two pane widths are remembered per Mac in `aa.sire.filters`; the search text is not. Nothing goes into data.json. |
| D-SIRE-05 | SIRE-004, ARCH §7.2 | The three panes use app-drawn draggable dividers in an `HStack` instead of `HSplitView`: inside the macOS 26 NavigationSplitView detail column an `HSplitView` extends under the floating sidebar and the toolbar and forces the window wider than its frame (verified with the snapshot hook at 1300 pt). Defaults 250 / 360 pt as on Windows; the detail keeps ≥ 420 pt. |
| D-SIRE-06 | SIRE-014, DECISIONS 12 | List rows add an `EXP` tag glyph and a status capsule (SF Symbol + the same text); the bookmark star is `#F0A030`. |
| D-SIRE-07 | SIRE-017…019, §6.2 | Status / Bookmark / EXP buttons show their current state (tinted chips); the WPF glyphs `⧗ ✓ ★ 📋 ✦ ↺ ➕ ✕` are replaced by SF Symbols next to the unchanged texts (`In Progress`, `Checked`, `N/A`, `Clear`, `Bookmark`, `EXP tag`, `Identified…`, `AI Suggest…`, `Asking Gemini…`, `Reset`, `Add to AA:`). The stats footer keeps its glyphs (data string). |
| D-SIRE-08 | SIRE-030, VIEW-212 row 23 | The candidate picker is a dedicated sheet (prompt as title, wrapping rows, `Cancel` / `Add`, Esc cancels) and adds in candidate order. |
| D-SIRE-09 | SIRE-034 | The kind sheet is a radio group (`Procedure` / `Task` / `Equipment / Area`) with one muted helper line per kind that matches what §3.7 creates — for `This question…` the identified tasks become steps / subtasks / components, for `Whole section…` / `Whole chapter…` each question does — and a note that identified tasks also become linked Tasks (display only). |
| D-SIRE-10 | SIRE-035, §6.7 | Confirmations use `Continue` / `Cancel`; "Go to it now?" uses `Go to Item` / `Not Now` (message text unchanged). |
| D-SIRE-11 | SIRE-036/037, §6.8 | One export sheet replaces the mode picker + Yes/No/Cancel box: mode list (Print Checklist pre-selected), live monospaced preview, `Share…`, `Print…`, `Cancel`, `Copy`, `Save…` (default). Copy posts `SIRE export copied to clipboard.` and closes; a pasteboard refusal shows `Clipboard failed` with a Mac message (there is no exception text). |
| D-SIRE-12 | SIRE-022, Q-15 | Paragraph-level commands (alignment, list toggles, indent) cannot restyle existing paragraphs: the single `shouldChangeText` gate refuses every change touching existing characters. ⌘B / ⌘I / ⌘U change typing attributes only. |
| D-SIRE-13 | SIRE-025 | The context menu reads `Copy`, `Paste (insert)`, `Select All` (Mac capitalisation). Services can read the selection but never write back; Writing Tools, autocorrect, substitutions and find-and-replace are off. |
| D-SIRE-14 | SIRE-022, §6.4 rule 6 | Pasted rich text is sanitised: AA XAML fragments go through W-RICH `readFragment`, RTF/RTFD lose their attachments, otherwise plain text. Drag and drop is disabled. |
| D-SIRE-15 | SIRE-020, §6.5, §6.13 | Display uses the system font (SF Pro) at 1 DIP = 1 pt; stored XAML keeps `FontFamily="Segoe UI"`. Chips / labels are TextKit 1 `NSTextBlock`s with 100 % content width; intra-Run line breaks are U+2028 inside the paragraph. The body paper stays light (`#FCFCFC`, forced Aqua) in both appearances. |
| D-SIRE-16 | §3.7, §4.4, §6.1 | Quick-add bodies are written by the SireFlow block-model writer with the WPF root attribute set (05 S-1), a fixed attribute order and explicit Run `Foreground`s; byte-stable and structurally identical to `TextRange.Save` (byte identity not required, §6.13). |
| D-SIRE-17 | §3.8 | Error texts: `URLError` timeouts → the timeout text; other `URLError`s → `Network error: {localizedDescription}`; JSON type errors reproduce .NET's `The requested operation requires an element of type '…'` text; JSON syntax errors use the Mac parser's message. |
| D-SIRE-18 | §4.1 | The bank decoder tolerates JSON `null` for every string and string-array element (→ ""), ignores unknown keys and fails the load on other type mismatches with an STJ-style message. |
| D-SIRE-19 | SIRE-016 | No selection shows `Select a question` (or `{n} questions selected.`); tasks empty shows `No tasks yet`; an empty list shows `No questions match` / the search empty state. |
| D-SIRE-20 | §6.10 | Quick-add builds every object first and inserts them in one batch per collection (chapter 8 as Equipment: 1 item, 91 components, 1 705 tasks). |
| D-SIRE-21 | ARCH §6.7, §11 | Until W-RICH is merged the body is shown read-only (generated original) and nothing is persisted through the placeholder writer; with W-RICH the original is loaded through `XamlReader.read(…, .sirePane)` and flushed with `XamlWriter.write`. |
| D-SIRE-22 | SIRE-014/015, §6.2; design rule 18 (Stage V round 2, V2-J7 / V2-DESIGN) | A filter result that ADDS rows to the question `List` rebuilds it (new row identities, `SireStagedRows`): the first 40 rows go in, the rest are appended ~30 ms later, and the list then scrolls the kept selection into view (or back to the top). Removals and re-sorts stay a plain diff. Reason: SwiftUI's insert diff into the NSTableView made AppKit log "reentrant operation in its NSTableView delegate" (to become an assert) on the first fill and on most search / filter changes. Selection is kept as SIRE-015 requires; Windows also resets its scroll position when `ApplyFilters` swaps the `ItemsSource`. |
| D-SIRE-23 | SIRE-020/022, design rules 9 and 11 (DECISIONS Stage V ruling) | The body card shows the `#FCFCFC` paper inset 8 pt (`EditorPane.paperInset`) on a `panelAlt` card, radius `AARadius.paper`, 1-pt border, soft shadow in dark mode — as the container editor. The hint strip text wraps (muted 11 pt) instead of being truncated to one line. |

## Optional items not shipped

| Item | Spec ref | Reason |
|---|---|---|
| `SIRE` CommandMenu (⌥⌘ status / bookmark commands) | §6.3 (optional) | The menu bar is F3's registry (03 §6.5.1); no rows were allotted. |
| Toolbar `Add to AA` menu and filter toggle | §6.2 (optional) | Section roots stay alive in one ZStack, so section toolbar items would show for every section; the in-pane strip and the list-header filter toggle provide both actions. |
| Undo of quick-add / `↺ Reset` | SIRE-024, §6.10 (optional) | Not required; Windows has none. |
