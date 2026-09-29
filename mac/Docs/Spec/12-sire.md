# 12 — SIRE 2.0 Knowledge Bank (porting spec)

> Subsystem prefix: **SIRE-** · Target: native macOS app in **Swift 6.4** (SwiftUI + AppKit where needed, macOS 26+, Xcode 27)
> Status: contract for implementers and verifiers. **This is not code.** Where Swift type shapes are suggested they are illustrative.

## 0. Sources read and conventions

Everything under this heading was read in full:

| File | Lines | Role |
|---|---|---|
| `AA/Sire/SireModels.cs` | 103 | `QuestionStatus`, `QuestionBank`, `BankMetadata`, `SireQuestion`, `QuestionNumberComparer` |
| `AA/Sire/SireBank.cs` | 92 | Lazy, process-wide loader and cache for the embedded bank, plus groupings |
| `AA/Sire/SireState.cs` | 57 | `SireTask` and `SireState`, which is persisted inside `AppData.Sire` |
| `AA/Sire/SireFlow.cs` | 190 | Renders a question in the original SIRE styling (FlowDocument) and serializes it to XAML |
| `AA/Sire/SireToAa.cs` | 162 | Quick-add bridge into Equipment/Task/Procedure |
| `AA/Sire/TagExtractor.cs` | 148 | Evidence-tag keyword classifier, ROVIQ split, dominant category |
| `AA/Sire/TaskIdentifierService.cs` | 159 | Offline task-extraction engine |
| `AA/Sire/GeminiService.cs` | 108 | Google Gemini REST client for AI task suggestions |
| `AA/Sire/SireExport.cs` | 244 | The 16 text export modes |
| `AA/Views/SirePage.xaml` / `.xaml.cs` | 193 / 546 | The tab UI |
| `AA/Sire/Data/sire2_question_bank.json` | 3,350,301 bytes | Embedded bank. Only its **schema** is described here; its content is not copied |
| `AA/MainWindow.xaml(.cs)` (SIRE parts) | — | Tab host, Tools menu, `FlushAllEditors`, Gemini key prompt, `RefreshHierarchyPages` |
| `AA/Services/DataStore.cs` | 965 | `GeminiApiKey` setting, JSON options, settings merge |
| `AA/Services/AppRepository.cs` (parts) | — | `MarkDirty` (750 ms debounce), `Save`, `AddRelation`, `LogAdded`, `KindLabel` |
| `AA/Models/Models.cs` (parts) | — | `AppData.Sire`, `HierarchyItem`, `Equipment`, `Component`, `TaskItem`, `Procedure`, `ChecklistStep`, `Container` |
| `AA/Views/ItemPickerWindow.xaml(.cs)`, `AA/Views/PromptWindow.xaml(.cs)` | — | The generic dialogs SIRE uses |
| `AA/Services/ThemeManager.cs`, `AA/App.xaml` | — | Theme brushes. The editor "paper" stays light in dark mode |
| `AA/FlashSync/FlashChangeSet.cs` (header) and `QR_SYNC_PROTOCOL.md` §change set | — | `Sire` travels as a whole block, and `GeminiApiKey` is excluded from sync |
| `PROGRESS.md` §"SIRE 2.0 Knowledge Bank tab + quick-add to AA" (lines 156–166), plus §Flash Sync line 129 | — | Rationale and claims |

The original product brief (`Create a Windows WPF C# application.txt`) does not mention SIRE; the feature was added later.

Conventions in this document:
- `file:line` refers to the C# sources under `/Users/eriskay/erisdev/AA/AA/`.
- **Exact strings** appear in `code` quotes. Non-ASCII characters matter: `—` is U+2014 EM DASH, `–` is U+2013 EN DASH, `…` is U+2026, `·` is U+00B7, `▸` is U+25B8, `“ ”` are U+201C/U+201D, `⧗` is U+29D7, `✓` is U+2713, `★` is U+2605, `✦` is U+2726, `✕` is U+2715, `↺` is U+21BA, `➕` is U+2795, `📋` is U+1F4CB.
- "Windows quirk" marks behaviour that looks unintended. Each quirk carries an explicit **Port decision**: *replicate* or *fix*. §8 collects them all.

---

## 1. Overview

**What it is.** SIRE 2.0 is OCIMF's tanker-inspection question library: 410 questions across 12 chapters. AA embeds the whole library offline and adds these capabilities on top of it:

1. **Browse, filter, sort and search** the library.
2. **Run an inspection session** stored in the AA database: a per-question status (In Progress / Checked / N/A), bookmarks, "for export" tags, per-question follow-up tasks, and per-question **user annotations to the question body**, which are insertion-only.
3. **Generate tasks** offline with a deterministic text-mining engine, or online with Google Gemini using the user's own API key.
4. **Quick-add to AA**, the headline feature. Any question, section or chapter can become an AA **Equipment/Area, Task or Procedure**. The SIRE detail becomes the item's rich-text body, children are created, and each identified task becomes its own top-level AA Task, cross-linked back.
5. **Export** the session and the library in 16 text formats, to a `.txt` file or the clipboard.

**Where it sits.**
- Main window tab with header **`SIRE 2.0`** (`MainWindow.xaml:191`, `x:Name="TabSire"`, hosts `views:SirePage x:Name="SirePg"`). It is the last tab by default. It takes part in the user's tab order (`Ui.TabOrder`) and tab colours (`Ui.TabColors`) under the identifier **`TabSire`**, and in `Ctrl+1…9` positional tab switching.
- The **Tools** menu (`MainWindow.xaml:93-96`) has:
  - **`SIRE 2.0 e_xport...`** (access key x). Tooltip: `Export SIRE inspection data (checklist, tasks, status report, and more) to a text file or the clipboard.` Handler: `SirePg.ShowExportDialog()`.
  - **`Set _Gemini API key...`** (access key G). Tooltip: `Set your Google Gemini API key to enable AI task suggestions on the SIRE tab. Stored locally, never committed.`
- The bank is parsed **only when the SIRE tab is first shown** (`MainWindow.xaml.cs:1418`), or when the export is invoked.
- The page is initialised in `LoadDataAndInitUi` through `SirePg.Init(_repo, NavigateToItem, RefreshHierarchyPages)` (`MainWindow.xaml.cs:1214`). `Init` runs again every time the data model is swapped, which happens on reload, import or a Flash Sync apply.
- `MainWindow.FlushAllEditors()` calls `SirePg.FlushBody()` (`MainWindow.xaml.cs:236`) so a question-body edit in progress reaches the model before close, shared-save push/reconcile, Flash Sync, or opening a detached item window.

---

## 2. Feature checklist

Every item below is a user-visible behaviour the Mac app **must** retain. The "Mac" notes in this section are brief; §6 has the detail.

### SIRE-001 — SIRE 2.0 tab and lazy bank load
- The tab header is `SIRE 2.0`. On first display, `SirePage.EnsureLoaded()` (`SirePage.xaml.cs:81-100`) runs:
  1. It returns immediately if the bank is already loaded (`_bankReady`) or there is no repository.
  2. It sets `_bankReady = true` straight away to guard against re-entry.
  3. It shows the loading overlay with text `Loading SIRE 2.0 question bank…`.
  4. It parses the bank on a background thread (`Task.Run(SireBank.EnsureLoaded)`).
  5. On success, back on the UI thread: `BuildFilters()`, `SyncQuestionFlags()`, `_loaded = true`, `ApplyFilters()`, `UpdateStats()`, then the overlay is hidden.
- The bank is cached for the **process lifetime**. Tab switches never re-parse it.
- Mac: trigger with `.task {}` on the SIRE view's first appearance. Decode off the main actor.

### SIRE-002 — Loading overlay and load-error state
- The overlay covers all five columns and uses the `Panel` background. Its text is 15 pt, `Muted`, and centred.
- On failure the overlay stays up and reads `Could not load the SIRE question bank:\n{LoadError}`, then `_bankReady` is reset to false. `SireBank` caches the failure: `_questions` becomes an empty list and `LoadError` is kept. Every later attempt therefore shows the same error until the app restarts.
- The `LoadError` texts are `Embedded SIRE question bank not found.`, `SIRE question bank is empty.`, or the JSON exception message.
- Mac: `ProgressView("Loading SIRE 2.0 question bank…")` while loading, and a `ContentUnavailableView` showing the same error text on failure.

### SIRE-003 — Embedded question bank
- There are 410 questions and 12 chapters. The schema is in §4.1. The bank is read-only and never written.
- Mac: ship the **byte-identical** file as a bundle resource. A test pins its SHA-256 (§7.1).

### SIRE-004 — Three-pane layout
- The grid columns are **Filters 250 px** | 6 px splitter | **Question list 360 px** | 6 px splitter | **Detail \***. Both splitters are draggable `GridSplitter`s. Widths are **not persisted**.
- Each pane is a `Border` with background `Panel`, border `BorderB`, thickness 1 and corner radius 4.
- Pane headers use `PanelAlt` with padding 8,6. The filter header is `SIRE 2.0 Filters` in bold 14 `Accent` with a **`Reset`** button on the right. The list header is `Questions`, which becomes `Questions ({n})` after the first filter, in bold `Accent`.

### SIRE-005 — Full-text search
- The `SearchBox` TextBox sits at the top of the filter pane. Its hint text is `Search all questions…`, declared in `Tag` but **not rendered** on Windows because there is no watermark template.
- **Every keystroke** re-filters (`TextChanged` calls `ApplyFilters`). There is no debounce.
- Search text is `Trim()`med. The match is a single-substring, case-insensitive (`OrdinalIgnoreCase`) `Contains` over these fields, in this order: `QuestionNumber`, `ShortQuestionText`, `FullQuestionText`, `Objective`, `ExpectedEvidence`, `PotentialNegativeObservationGrounds`, `IndustryGuidance`, `InspectionGuidance`, `SuggestedInspectorActions`, `Publications`, `RoviqSequence` (`SirePage.xaml.cs:196-202`).
- Search does **not** cover `DataSource`, chapter name, vessel types, evidence tags, the user's tasks, or edited bodies.
- Mac: `.searchable` in the SIRE toolbar, or a search field at the top of the filter pane. Show the placeholder `Search all questions…`. An optional debounce of 100–150 ms is allowed.

### SIRE-006 — Sort by
- The label `Sort by` is 11 pt `Muted`. The ComboBox items are `Question Number` (the default), `Chapter`, `Short Question Text`, `Vessel Types`, `ROVIQ Sequence` and `Question Type`. The ordering rules are in §3.9.

### SIRE-007 — Evidence category filter
- The label is `Evidence category`. The items are `All` (the default), `Equipment`, `Document`, `Procedure`, `Record` and `Personnel`.
- Any value other than `All` keeps a question only if at least one of its `EvidenceTags` starts with `"{category}:"` (`OrdinalIgnoreCase`).

### SIRE-008 — Session status filter
- The label is `Session status`. The items are `All` (the default), `In Progress`, `Checked`, `Not Applicable`, `Bookmarked`, `For Export`, `Has Tasks` and `No Status`. The semantics are in §3.9.

### SIRE-009 — Chapter filter
- An `Expander` with header **`Chapters`** that is expanded by default. It contains `All` and `None` buttons (padding 6,1), followed by one CheckBox per chapter. Every CheckBox is initially **checked**.
- Label format: `Ch {chapter}: {chapterName} ({count})`, for example `Ch 5: Safety Management (88)`. Chapters are ordered numerically, and a non-numeric chapter sorts as 999.
- `All` checks every chapter box and `None` unchecks them all. Each checkbox change re-filters.

### SIRE-010 — Vessel types filter
- An `Expander` with header **`Vessel types`**, collapsed by default. It holds one CheckBox per distinct vessel type (case-insensitive distinct, culture-ordered), all initially checked. The shipped bank gives `Chemical`, `LNG`, `LPG`, `Oil`.
- A question with **no** vessel types, such as a Chapter 1 data field, **always passes** this filter. Any other question passes when at least one of its types is checked (case-insensitive).

### SIRE-011 — Question type filter
- An `Expander` with header **`Question type`**, collapsed by default. It holds one CheckBox per distinct `QuestionTypeDisplay`, culture-ordered. The shipped bank gives `Data Field` (25), `Inspection` (331) and `Photograph` (54).

### SIRE-012 — Reset filters
- The `Reset` button does nothing until the bank has loaded. After that it clears the search, sets all three combos back to index 0, re-checks every chapter, vessel and type box, and re-filters. It does **not** change which expanders are open.
- Filter state is **not persisted** anywhere. Mac: the same by default. Remembering it per machine in `UserDefaults` or `@SceneStorage` is an optional nicety; it must never go into `data.json`.

### SIRE-013 — Stats footer
- A `StatsText` block is docked at the bottom of the filter pane: 11 pt, `Muted`, wrapping, margin 8,6. Its format, including the two spaces between segments:
  ```
  {questionCount} questions · {totalIdentifiedTasks} auto-identified tasks
  Session — ✓ {checked}  ⧗ {inProgress}  N/A {notApplicable}  ★ {bookmarks}  tasks {taskCount}
  ```
  With the shipped bank and an empty session the text is `410 questions · 6106 auto-identified tasks` / `Session — ✓ 0  ⧗ 0  N/A 0  ★ 0  tasks 0`. The number 6106 comes from a faithful re-implementation; see §7.3 and the open questions.
- It is refreshed after load, `Init`, any status change, a bookmark toggle, an export-tag toggle, adding or removing a task, and a picker add. It is **not** refreshed when a task's completion is toggled, which is correct because completion is not shown.
- `checked`, `inProgress` and `notApplicable` use `SireState.CountByStatus`, a raw string equality on the stored values. `bookmarks` is `Bookmarks.Count` and `taskCount` is `Tasks.Count`.

### SIRE-014 — Question list rows
- The `ListBox` is virtualized (Recycling) with horizontal scrolling disabled, and each row stretches to the full width. The row template:
  - Left: the `QuestionNumber` in bold `Accent`, in a fixed 52 px column, top-aligned.
  - Right: `★` in `#FFF0A030` (a fixed amber, the same in both themes), visible only when bookmarked.
  - Centre: `ShortQuestionText` with wrapping. For the 25 Chapter 1 data fields this is **empty**, so the row shows only the number (a faithful quirk). Below it, the `StatusDisplay` text (`In Progress` / `Checked` / `N/A`) at 10 pt `Muted`, shown only when a status is set.
- The "for export" flag is **not** shown in the list.
- Row badges update live when status or bookmark changes.
- Mac: keep the same information. Nicer badges are allowed, for example a status capsule with SF Symbols `hourglass` / `checkmark.circle.fill` / `minus.circle` alongside the same text, `star.fill` in `#F0A030`, and optionally a small `tag` glyph for EXP as an additive extra. The list must support ↑/↓ keyboard navigation.

### SIRE-015 — Selection is preserved across re-filter
- Before the list is swapped, `ApplyFilters` saves the current selection and re-selects it if it is still present (`SirePage.xaml.cs:187-193`). On Windows the swap briefly clears the selection, which flushes and reloads the body. If the question has been filtered out, the selection is lost and the detail pane is disabled.
- Mac: keep the selection when the question is still visible. Do **not** rebuild the editor in that case, but flush any body edit first. When the question disappears, clear the selection. Clearing flushes, and the detail pane becomes disabled or empty.

### SIRE-016 — Detail pane disabled without a selection
- `DetailRoot.IsEnabled = (_selected != null)`. Every detail control is disabled until a question is selected: status buttons, quick-add, tasks and the editor.
- Mac: show a `ContentUnavailableView("Select a question", systemImage: "doc.text.magnifyingglass")` in the detail area, or render the controls disabled. Either is acceptable; the empty state is an additive nicety.

### SIRE-017 — Status buttons
- A `WrapPanel` holds these buttons: **`⧗ In Progress`**, **`✓ Checked`**, **`N/A`**, **`Clear`**. Clear has a 12 px right margin that separates it from the toggles.
- A click sets the status of the selected question (§3.11 `SetStatus`), updates the row badge, marks the repository dirty, and refreshes the stats. The list is **re-filtered only if the Session status filter is not `All`**, so the question may disappear from the list.
- Windows shows the current status only as the list badge; the buttons carry no selected state. Mac: a segmented control with the segments `⧗ In Progress | ✓ Checked | N/A` plus a `Clear` button, or four buttons with the active one highlighted. Showing the current state is additive.

### SIRE-018 — Bookmark toggle
- A `ToggleButton` labelled **`★ Bookmark`**. A click toggles membership in `SireState.Bookmarks`, updates the row star and the toggle state, marks dirty and refreshes the stats. It does **not** re-filter, even when the filter is `Bookmarked`. This is a Windows quirk; §8 Q-7 has the port decision.

### SIRE-019 — Export-tag toggle
- A `ToggleButton` labelled **`EXP tag`**. It toggles membership in `SireState.ForExport` and otherwise behaves exactly like SIRE-018. It feeds the `For Export` filter and the `For Export Tagged` export mode.

### SIRE-020 — Question detail rendering in the original SIRE styling
- The bottom row of the detail pane holds the question body in a rich-text editor. It uses Segoe UI 13 in normal weight (**no bold anywhere**), 12 px padding, and a vertical scrollbar when needed. The block structure, colours and sizes are specified in §3.6 (`SireFlow.BuildQuestion`).
- The on-screen document uses **black** body text. When the same document is used as a container body on quick-add, the body text is **slate `#334155`**.
- Section headers are colour-coded chips. `SUGGESTED INSPECTOR ACTIONS` is amber, `EXPECTED EVIDENCE` is green, `POTENTIAL GROUNDS FOR A NEGATIVE OBSERVATION` is red, and every other section is grey.
- PDF bullets are preserved as lists: disc markers, with circle-marker nested lists.

### SIRE-021 — Smart tags line
- If a question has evidence tags, the last block of the body is `Smart tags: {tag1}   ·   {tag2} …` at 10 pt `Muted` `#64748B`. Tags are sorted culture-aware (§3.3).

### SIRE-022 — Editable body, insertion-only
- A header strip in `PanelAlt` reads `Editable — type to add line breaks / notes (Enter = new line). Your edits are saved.` at 11 pt `Muted`, with a character-ellipsis trim. A **`↺ Reset`** button on the right carries the tooltip `Discard your edits and restore the original SIRE formatting for this question.`
- The editor is **insertion-only** (`SirePage.xaml.cs:35-68`). Only additions are possible, and the original text cannot be removed:
  - **Backspace** and **Delete** are blocked with any modifier, so Ctrl+Backspace, Ctrl+Delete and Shift+Delete are blocked too.
  - **Ctrl+X** is blocked. The **Cut** command is disabled (`CanExecute = false`).
  - With a **non-empty selection**, any key that is not a navigation or copy key first **collapses the selection to its start**, then the key acts. Typing, Enter and Paste therefore insert *before* the selected text and never replace it. The navigation and copy keys are ←, →, ↑, ↓, Home, End, PgUp, PgDn, Tab, Shift, Ctrl, Alt, System (Alt combinations), CapsLock, and Ctrl+C, Ctrl+A and Ctrl+Insert.
  - The **Paste** command (Ctrl+V, Shift+Insert, or the context menu) collapses the selection to its start, then pastes. The pasted content can be rich, using WPF RichTextBox's default formats (Xaml/Rtf/Text).
  - **Drag and drop is disabled** (`AllowDrop=False`), so text cannot be dragged, moved or dropped in.
  - The default RichTextBox formatting shortcuts remain active, but a selection is always collapsed first. Ctrl+B/I/U therefore affect only text typed afterwards. Paragraph-level commands still apply to the caret's paragraph: alignment (Ctrl+E/L/R/J), list toggles (Ctrl+Shift+L/N) and indentation (Ctrl+T, Ctrl+Shift+T).
  - **Undo and redo** (Ctrl+Z/Y) work normally. The undo stack only contains the user's own edits, because loading a document resets it.
- Mac: §6.4 specifies the NSTextView behaviour.

### SIRE-023 — Body persistence (`SireState.QuestionBodies`)
- The editor loads the user's saved XAML for the question when present and non-empty. If that XAML fails to parse, the freshly generated original is shown silently and the stored string stays untouched. With no saved XAML, the freshly generated original is shown.
- Any text change after load sets `_bodyDirty`. `FlushBody()` serializes the whole editor document with `TextRange.Save(DataFormats.Xaml)`, stores it under `QuestionBodies[questionNumber]` and calls `MarkDirty()`. Exceptions are swallowed.
- **Flush triggers on Windows:**
  1. The selected question changes.
  2. The editor loses focus.
  3. `MainWindow.FlushAllEditors()` runs, on window close, a shared-save tick/push/reconcile, a shared-file set, Flash Sync, or opening a detached item window.
- `DoSave` (Ctrl+S) and the 5-minute `DoAutosave` do **not** flush the SIRE body. This is a Windows gap; see Q-8.
- Once a question is flushed, its XAML is stored **permanently**, even if the user made no net change: typing and then undoing still produces a stored body. Only `↺ Reset` removes it.

### SIRE-024 — Reset body
- `↺ Reset` removes `QuestionBodies[q]` and calls `MarkDirty` if an entry existed. It discards any unflushed edit and reloads the generated original. There is **no confirmation**.
- Mac: the same with no confirmation. Optionally register an undo action that restores the previous body; this is additive.

### SIRE-025 — Body context menu
- The editor's context menu has exactly three items: **`Copy`**, **`Paste (insert)`** and **`Select all`**.
- Mac: a custom `menu(for:)` with `Copy`, `Paste (insert)` and `Select All`. It must not offer Cut, Delete, Services that replace text, Writing Tools, Spelling correction, Substitutions or Transformations.

### SIRE-026 — Tasks panel: list, complete and remove
- The header reads `Tasks` with no selection, and `Tasks ({n})` once a question is selected. It uses bold `Accent`. The right side holds two buttons, **`📋 Identified…`** and **`✦ AI Suggest…`**.
  - `📋 Identified…` tooltip: `Add offline-identified tasks (from the question guidance) to this question.`
  - `✦ AI Suggest…` tooltip: `Ask Google Gemini for suggested tasks (needs a Gemini API key set in Tools).`
- Each task row, top-aligned, has:
  - A **CheckBox** bound one-way to `IsCompleted`. A click toggles `IsCompleted`, marks dirty and re-renders the list.
  - The task text, wrapping.
  - A **`✕`** button on the right: 20 px wide, transparent, `Muted`. It removes the task **immediately, with no confirmation**, then marks dirty and refreshes the list and stats.
- Tasks appear in their insertion order in `SireState.Tasks`, filtered to the current question. Completed tasks get no strikethrough. Task text cannot be edited or reordered.

### SIRE-027 — Add a manual task
- A TextBox, whose `Tag` hint `Add a task and press Enter…` is not rendered, sits beside an **`Add`** button.
- **Enter** or `Add` commits the task. The text is `Trim()`med, and empty text is ignored. The new `SireTask` gets `QuestionNumber = selected`, `Text = trimmed text`, `IsCompleted = false`, `CreatedAt = DateTime.Now` and a new `Id`.
- Afterwards the box is cleared and keeps focus, the repository is marked dirty, and the list and stats refresh. Manual adds are **not** de-duplicated.
- Mac: `TextField("Add a task and press Enter…")` with `.onSubmit`, plus an `Add` button. Refocus the field after adding.

### SIRE-028 — Identified tasks (offline)
- `📋 Identified…` gets `SireBank.GetIdentifiedTasks(selected)`. The list is precomputed at bank load (§3.4).
  - If the list is empty, show an **Information** alert, title `Identified tasks`, text `No tasks could be identified from this question's guidance text.`
  - Otherwise open the candidate picker (SIRE-030) with the prompt `{n} tasks identified for Q {questionNumber} — tick to add:`.

### SIRE-029 — AI Suggest (Gemini)
- `✦ AI Suggest…` runs these checks in order:
  1. The question must be a *detailed* question (`IsDetailedQuestion`, §3.1). Otherwise show an Information alert, title `AI Suggest`, text `AI task suggestions only apply to detailed inspection questions.`
  2. A key must be set (`DataStore.GeminiApiKey`). If it is null or whitespace, show an Information alert, title `AI Suggest`, text `No Gemini API key is set. Add yours via Tools ▸ 'Set Gemini API key…' to enable AI task suggestions.`
  3. While the request runs, the button is **disabled** and reads **`✦ Asking Gemini…`**. The original label comes back afterwards, whether the call succeeds or fails.
  4. On error, show a **Warning** alert, title `AI Suggest`, containing the error text (§3.8).
  5. On success, open the candidate picker with the prompt `Gemini suggested {n} tasks for Q {questionNumber} — tick to add:`.
- Windows quirk Q-4: the result is applied to whichever question is selected **when the response arrives**, not the question that was asked about. **Port decision: fix.** Capture the question when the request starts, and use it for both the prompt text and the add target.

### SIRE-030 — Candidate task picker
- Windows reuses the generic `ItemPickerWindow`:
  - The window title is `Pick items`, the size is 500×500, and it is centred on its owner.
  - A bold prompt line sits above a search box and a multi-select list. The buttons are `Cancel` and `OK`; `OK` is the default (Enter) button. There is no Esc binding.
  - **Every candidate is pre-selected.**
  - The search box filters the list by a case-insensitive `Contains` on the display text. On Windows, reassigning the list clears the selection. That is quirk Q-11; **port decision: fix** by preserving the ticks across filtering.
- On OK, each selected string that is not empty and not already present is added as a new `SireTask` for the question. "Already present" means a case-insensitive exact match against the question's existing task texts, *or against strings added earlier in the same batch*.
- Windows adds tasks in list-selection order, which equals candidate order unless the user re-ticked items. Mac: add in **candidate (display) order**.
- If anything was added, the repository is marked dirty and the list and stats refresh. Cancel adds nothing.
- Mac: a sheet titled with the prompt string. It contains a `List` of checkbox `Toggle`s (all on), a search field, `Select All` and `Select None` (additive), and `Cancel` and `Add` buttons. `Add` is the default action and Esc cancels. Long task text wraps.

### SIRE-031 — Quick-add: `This question…`
- A `PanelAlt` strip holds the label **`➕ Add to AA:`** in bold `Accent`, followed by three buttons:
  - **`This question…`**, in the AccentButton style (bold). Tooltip: `Create an AA Equipment / Task / Procedure from this question, plus its identified tasks as top-level Tasks.`
  - **`Whole section…`**. Tooltip: `Add every question in this section under one AA item, with each question as a child and its tasks spun off.`
  - **`Whole chapter…`**. Tooltip: `Add every question in this chapter under one AA item (can be large).`
- `This question…` opens the kind picker (SIRE-034), then runs `SireToAa.AddQuestion(repo, q, kind, createTopLevelTasks: true)` (§3.7), then `FinishAdd` (SIRE-035).

### SIRE-032 — Quick-add: `Whole section…`
- First a confirmation. Buttons OK/Cancel, **Question** icon, title `Add section`, text `Add all {count} question(s) in section {section} to AA under one item (plus their identified tasks as top-level Tasks)?`, where `count = |InSection(selected.Section)|`.
- On OK: the kind picker (the default comes from the **selected question's** dominant category), then `SireToAa.AddSection`, then `FinishAdd`.

### SIRE-033 — Quick-add: `Whole chapter…`
- First a confirmation. Buttons OK/Cancel, **Warning** icon, title `Add chapter`, text `Add all {count} question(s) in chapter {chapter} to AA under one item (plus their identified tasks as top-level Tasks)?\n\nThis can create many items and tasks.`
- On OK: the kind picker, then `SireToAa.AddChapter`, then `FinishAdd`.

### SIRE-034 — Kind picker with a smart default
- The prompt is `Add to AA as which kind?` and the picker is single-select. Its options are `Procedure`, `Task` and `Equipment / Area`.
- The pre-selection comes from `TagExtractor.DominantCategory(selectedQuestion)` (§3.3): `"Equipment"` selects Equipment, `"Procedure"` selects Procedure, and anything else selects Task.
- Cancel, or OK with nothing selected, aborts silently.
- Mac: a sheet with a `.radioGroup` Picker. The labels are `Procedure`, `Task` and `Equipment / Area`, the default is pre-selected, and the buttons are `Cancel` and `Add`.

### SIRE-035 — After an add: save, refresh and navigate
- `FinishAdd` (`SirePage.xaml.cs:493-506`):
  - If `Result.Primary` is null, show an Information alert titled `Add to AA` with `Result.Summary`, which is `No questions found for that selection.` In practice this path cannot be reached.
  - Otherwise:
    1. Run `_repo.Save()` synchronously, swallowing errors.
    2. Call `RefreshHierarchyPages()`, which reloads the Equipment, Tasks, Procedures and Vessels lists.
    3. Show an Information alert with Yes/No buttons, title `Added to AA`, text `{Summary}\n\nGo to it now?`.
    4. **Yes** calls `NavigateToItem(primary)`, which switches to that item's tab and selects it.
- Summary strings (§3.7) use the enum names `Procedure`, `Task` and `Equipment`, not "Equipment / Area".

### SIRE-036 — SIRE export (Tools menu), 16 modes
- `ShowExportDialog()` (`SirePage.xaml.cs:510-542`) first calls `EnsureLoaded()`. If the bank is still loading, it shows an Information alert titled `SIRE export` with `The SIRE question bank is still loading — try again in a moment.`
  - On Windows that check is effectively unreachable: `EnsureLoaded` sets `_bankReady` synchronously, and the export then blocks on the bank lock. See Q-10.
- Next comes a picker with the prompt `Choose a SIRE export:`. It is single-select and pre-selects **`Print Checklist`**. The items are the 16 modes, in this order: `All Tasks`, `Completed Tasks`, `Pending Tasks`, `Questions with Tasks`, `Selected Questions`, `For Export Tagged`, `Bookmarked Questions`, `Current Filter Results`, `By Chapter`, `By ROVIQ Location`, `By Status`, `By Vessel Type`, `Print Checklist`, `Inspection Summary`, `Full Session Report`, `Identified Tasks`.
- The text is built with `SireExport.Build(mode, allQuestions, state, identifiedTasks, filtered)` (§3.10). `filtered` is the **currently displayed list, in its current sort order**. If the tab was never populated, it is all questions in bank order.

### SIRE-037 — Export destination
- A Yes/No/Cancel **Question** alert titled `SIRE export` with the text `SIRE export “{mode}” ready.\n\nYes = save to a .txt file\nNo = copy to clipboard`.
  - **No** copies the text to the clipboard and sets the main status bar to `SIRE export copied to clipboard.`. On an exception it shows an alert with the exception message, titled `Clipboard failed`.
  - **Yes** opens a Save dialog with the filter `Text file (*.txt)|*.txt|All files (*.*)|*.*` and the default name `SIRE_{mode with ' '→'_'}_{yyyyMMdd_HHmm}.txt`, for example `SIRE_Print_Checklist_20260930_1432.txt`. The file is written as UTF-8 **without BOM** (`File.WriteAllText`). A failure shows an **Error** alert titled `Save failed` with the exception message. A successful save gets no confirmation.
  - **Cancel** does nothing.
- Mac: one **SIRE Export sheet** (§6.8). It shows the mode list with `Print Checklist` pre-selected, a live read-only preview (monospaced), and the buttons `Copy`, `Save…` and `Cancel`. `Share…` and `Print…` are additive extras. After Copy, show a status or toast with the exact text `SIRE export copied to clipboard.`

### SIRE-038 — Set Gemini API key
- Tools ▸ `Set Gemini API key...` opens `PromptWindow`:
  - The title and heading are `Gemini API key`. The prompt is `Paste your Google Gemini API key (stored locally in settings.json, never committed):`.
  - The field shows the current key in **plain text**, pre-selected.
- On OK the value is `Trim()`med. Blank clears the key and non-blank stores it. The status bar then reads `Gemini API key cleared.` or `Gemini API key saved.`. Cancel changes nothing.
- The key lives in the settings file only. It is never in `data.json`, never in bundles, and is excluded from Flash Sync (`FlashChangeSet.cs:52-56`).
- Windows quirk Q-5: clearing the key does not survive a restart, because `WriteSettings` falls back to the old value. **Port decision: fix** on Mac, so that clearing really removes the key.
- Mac: see §6.9 (Keychain plus a Settings pane). Keep the Tools-menu command. Use a `SecureField` with a reveal toggle. The Mac prompt wording changes to name the Keychain: `Paste your Google Gemini API key (stored securely in this Mac's Keychain, never synced):`.

### SIRE-039 — Session persistence, backup and sync
- The whole session (`SireState`) is part of `AppData` under the JSON key `"Sire"`, so it saves, backs up, bundles and syncs with the rest of the database. There is no separate file.
- Every mutation calls `repo.MarkDirty()`, which triggers the 750 ms debounced autosave (`AppRepository.cs:34, 301-307`). A quick-add also calls `repo.Save()` synchronously.
- In Flash Sync, `Sire` is **not** an Id-collection, so it travels as a whole **block** (`QR_SYNC_PROTOCOL.md` ~l.505-570). On apply, the receiver's entire `Sire` object is replaced. That makes it last-writer-wins for the whole session, including `QuestionBodies`.

### SIRE-040 — Data-model swap
- `Init` is called again with the new repository after a reload, import or Flash Sync apply. If the bank is ready, the page re-derives the per-question flags, stats, task list and button toggles, then reloads the body for the current selection **from the new state**. It does not flush the old edit, which belonged to the discarded model.
- It does **not** re-apply filters, so a status-filtered list can be stale until the next filter change. **Port decision: fix**; the Mac re-filters on swap.

### SIRE-041 — Dark mode and theming
- The pane chrome uses theme brushes (`Panel`, `PanelAlt`, `BorderB`, `Accent`, `Muted`, `Fg`). In dark mode these are #252526, #2D2D30, #3F3F46, white, #B0B0B0 and #F0F0F0. In light mode they are white with a black accent, muted text and borders.
- **The body editor stays light "paper" in both themes.** `EditorBg` is #FCFCFC and is never swapped (`App.xaml:34-38`), and the body text is black. The fixed SIRE colours (blue headings, amber/green/red chips) therefore stay readable.
- The bookmark star is a fixed `#F0A030`.
- UI chrome on Windows uses the app-wide `MainFont` (Consolas 13). The body uses Segoe UI.
- Mac: use semantic colours and materials for chrome (§6.2). Force the body `NSTextView` to a light appearance (`appearance = NSAppearance(named: .aqua)`) with background `#FCFCFC`.

### SIRE-042 — Offline task-identifier engine
- At bank load, `TaskIdentifierService.IdentifyAllTasks` runs over every *detailed* question (§3.4). The result is cached, used by `📋 Identified…`, quick-add and the `Identified Tasks` export mode, and counted in the stats footer.
- Expected output for the shipped bank: **332 questions with tasks, 6106 tasks in total**, between 6 and 39 per question.

### SIRE-043 — Evidence tag extraction
- `TagExtractor.ExtractTags` runs per question at load (§3.3). It drives the Evidence category filter, the Smart tags line and the quick-add default kind.

### SIRE-044 — ROVIQ locations
- `TagExtractor.ExtractRoviqLocations` runs per question at load (§3.3). It is used **only** by the `By ROVIQ Location` export. The UI has **no** ROVIQ filter, although a code comment mentions one.

### SIRE-045 — Natural question-number ordering
- `QuestionNumberComparer` (§3.2) is used everywhere a question-number order is needed, for example `2.1.2 < 2.1.10`.

### SIRE-046 — Activity-log entry per quick-add
- Each quick-add writes one `Added` log entry for the **parent** only; spawned tasks and children get none. The fields are: `Kind` = `KindLabel`, which is `Equipment/Area`, `Task` or `Procedure`; `Name` = the parent name; `Detail` = `from SIRE Q{n}`, or `from SIRE ({count} questions)` for a section or chapter. The timestamp is UTC.

### SIRE-047 — Items created by quick-add are ordinary AA items
- Each one gets the tag **`SIRE`**, is appended to the end of its collection, is ungrouped, and has default fields. It can be edited, deleted to the Trash, searched and synced like any other item. See §3.7 for the exact shape.

### SIRE-048 — Not implemented, do not invent
- `SireState`'s doc comment mentions ".sire import/export … for interop". **No such feature exists.** It is not in the Windows UI or code, so the Mac app should not add it unless it is asked for (Q-13).
- `SireQuestion.IsSelected` is never set by the UI, so the `Selected Questions` export is always empty on Windows. See Q-3 for the port decision.
- `SireQuestion.ListTitle`, `SireBank.Get`, `SireBank.Metadata` and `SirePage.IsReady` are unused by the UI.

---

## 3. Logic and algorithms

### 3.1 `SireQuestion` computed properties (`SireModels.cs:28-82`)
| Property | Exact rule |
|---|---|
| `VesselTypesDisplay` (l.49) | `VesselTypes.Count > 0 ? string.Join(", ", VesselTypes) : "All"`. The source order is kept, for example `Oil, Chemical, LPG, LNG`. |
| `ChapterDisplay` (l.50) | `$"Ch {Chapter}: {ChapterName}"` |
| `QuestionTypeDisplay` (l.51-57) | `type == "data_field"` gives `"Data Field"`. `type == "inspection_question"` gives `"Photograph"` if `FullQuestionText` contains `photograph` (case-insensitive), otherwise `"Inspection"`. Any other type is returned raw. |
| `ListTitle` (l.58) | `$"Q {QuestionNumber} — {ShortQuestionText}"` (unused) |
| `IsDetailedQuestion` (l.67) | `Type == "inspection_question" && !string.IsNullOrEmpty(Objective)`. That covers 332 of 410: all 385 inspection questions minus the 53 photo questions with an empty objective. Note that `11.1.1` has an objective and **is** detailed. |
| `StatusDisplay` (l.74) | InProgress gives `In Progress`, Checked gives `Checked`, NotApplicable gives `N/A`, and anything else gives `""` |
| `HasStatus` (l.75) | `Status != None` |
| Runtime flags `Status`, `IsBookmarked`, `IsForExport`, `IsSelected` | `[JsonIgnore]`. They are mirrored from `SireState` onto the shared question objects for list binding (`SyncQuestionFlags`, `SirePage.xaml.cs:318-327`). |

Mac: make `SireQuestion` an immutable `struct` that is `Sendable` and `Codable`. **Derive** the flags in the view model from `SireState` instead of mutating bank objects. The observable result is the same.

### 3.2 `QuestionNumberComparer.Compare` (`SireModels.cs:85-103`)
1. Equal strings, including both null, return 0. A null `x` returns −1 and a null `y` returns +1.
2. Split both strings on `.`. Each part is parsed as an `int`; a part that is **not** a valid int becomes **0**. .NET `int.TryParse` accepts a leading sign and surrounding whitespace, rejects anything beyond Int32, and uses the current culture's NumberFormat.
3. Compare the parts pairwise up to the longer length. A missing part counts as **0**. The first difference decides the result.
4. Consequences: `"1.1" == "1.1.0"`, and `"x.1" == "0.1"`.

It is used by `InChapter`/`InSection` ordering, sorting, and every export.

### 3.3 `TagExtractor` (`TagExtractor.cs`)
**Keyword lists** (l.12-99). Each list is copied **verbatim**, including the original casing, into the Swift port and diffed in a unit test against the C# file. The counts are Equipment 87, Document 52, Procedure 47, Record 27 and Personnel 24.

**`ExtractTags(q)`** (l.101-113)
1. `searchText = string.Join(" ", ExpectedEvidence, SuggestedInspectorActions, ShortQuestionText, Objective)`. **The order matters only for readability.** Matching is substring-based, but a keyword could straddle the joining space, so keep the order.
2. Scan the categories in this order: Equipment, Document, Procedure, Record, Personnel. For each keyword, if `searchText.Contains(keyword, OrdinalIgnoreCase)`, add `"{Category}: {keyword}"` to a `HashSet` with `OrdinalIgnoreCase` comparison. The keyword keeps the list's casing, for example `Equipment: SCBA` or `Procedure: PMS`.
   - Matches are **pure substrings with no word boundaries**, which produces intentional false positives that must be kept: `AIS` matches "r**ais**ed", `UPS` matches "gro**ups**", `DOC` matches "**doc**ument", `rating` matches "ope**rating**", `COW` matches "**cow**l".
3. Return the list sorted with **the default culture-sensitive string comparer** (`OrderBy(t => t)`, the current culture). See §6.12 for the Mac comparator.

**`ExtractRoviqLocations(seq)`** (l.122-132)
1. Null or whitespace returns `[]`.
2. `Split(',', RemoveEmptyEntries | TrimEntries)`. Each entry is trimmed of Unicode whitespace, and entries that end up empty are removed.
3. `TrimEnd('.')` on each entry. Only trailing dots are removed, so `"Bridge ."` becomes `"Bridge "` with the trailing space **kept**.
4. Drop entries that are null or whitespace, then `Distinct(OrdinalIgnoreCase)`, which keeps the first casing seen, then `OrderBy` in culture order.
5. Inner newlines survive, for example `"Interview -\nRating"`. The shipped bank yields **39** distinct locations (case-insensitive) across all questions.

**`DominantCategory(q)`** (l.136-147)
1. Count tags per category. The category is the text before the first `:`, and it must be one of the five names **case-sensitively**, because `Dictionary.ContainsKey` uses the default ordinal comparer. A tag with no colon, or with a colon at index 0, is ignored.
2. If `Equipment > 0 && Equipment >= Procedure`, return `"Equipment"`. Else if `Procedure > 0`, return `"Procedure"`. Otherwise return `"Task"`. Document, Record and Personnel never decide the result.
3. Shipped-bank distribution: Procedure 187, Equipment 144, Task 79. 54 questions have no tags at all.

### 3.4 `TaskIdentifierService` (`TaskIdentifierService.cs`), bit-exact port required
**`IdentifyAllTasks(questions)`** (l.25-35): for each question in bank order where `IsDetailedQuestion`, compute `IdentifyTasksForQuestion`, and store the result under `QuestionNumber` if it is non-empty. The dictionary's insertion order is the bank order.

**`IdentifyTasksForQuestion(q)`** (l.37-45): one shared `seen` set (case-insensitive) and one output list, fed in this order:
1. `SuggestedInspectorActions` in **Direct** mode
2. `ExpectedEvidence` in **Evidence** mode
3. `PotentialNegativeObservationGrounds` in **NegativeToPositive** mode

**`ExtractBulletTasks(text, tasks, seen, mode)`** (l.49-73). Return if the text is null or whitespace. For each fragment `raw` from `SplitOnBullets(text)`:
1. `line = CleanFragment(raw)`
2. Skip if `line.Length < 10` (UTF-16 code units)
3. Skip if `IsSkippableLine(line)`
4. Skip if `IsSubItem(line)`
5. Transform by mode: Direct uses `EnsureCapitalized(line)`, Evidence uses `FormatEvidenceTask(line)`, NegativeToPositive uses `FormatNegativeAsPositive(line)`
6. Skip if the result is null or whitespace
7. `key = NormalizeForDedup(task)`. Skip if `key.Length < 8`. Skip if `key` is already in `seen`, otherwise add it
8. Append `task`

**`SplitOnBullets(text)`** (l.75-91)
- Bullet characters are `•` U+2022, `●` U+25CF, `■` U+25A0 and `▪` U+25AA. Note that `` (a Wingdings bullet present 238 times in the bank), `o`, `-` and `–` are **not** bullet characters here.
- `parts = text.Split(bulletChars, RemoveEmptyEntries)`. For each part, `Trim()`; if it is non-empty, append `CollapseWhitespace(trimmed)`.
- **Fallback:** if `parts.Length <= 1` **and** the text contains no bullet character at all, **also** append each non-empty `Trim()`med line of `text.Split('\n', RemoveEmptyEntries)`. These lines are **not** whitespace-collapsed. The result then holds *both* the whole collapsed text *and* each line (see test vector TV-ID-2). Dedup removes the duplicate when there is only one line.

**`CollapseWhitespace(t)`** (l.93-104): runs of `' '`, `'\n'`, `'\r'` and `'\t'` collapse to one space. Other whitespace, such as NBSP, `\v` and `\f`, is kept. The result is then `Trim()`med.

**`CleanFragment(text)`** (l.106-114), applied in sequence:
1. `t = text.Trim()`
2. If `t` starts with `"- "`, set `t = t[2..].Trim()`
3. If `t.Length > 3` and `char.IsDigit(t[0])` (Unicode Nd) and `t[1]` is `.` or `)` and `t[2]` is a space, set `t = t[3..].Trim()`
4. If `t.Length > 3` and `char.IsLetter(t[0])` and `t[1]` is `.` or `)` and `t[2]` is a space, set `t = t[3..].Trim()`. Steps 3 and 4 can both apply: `"1. a. x…"` becomes `"x…"`.
5. If `t` ends with `'.'` and does not end with `"etc."`, `"e.g."` or `"i.e."`, drop the last character and `Trim()`.

**`IsSkippableLine(line)`** (l.116-122) is true when either:
- The line starts, case-insensitively, with any of: `Pre-Inspection`, `Pre-inspection`, `On-board`, `On board`, `Inspectors must not`, `Inspector must not`, `Where the vessel`, `Where no defects`, `Where defects`, `In the case that`, `In such cases`, `This question will only`, `Note that`, `Note:`.
- Or `line.Length > 2 && IsDigit(line[0]) && line[1] == '.' && (IsDigit(line[2]) || line[2] == ' ')`. This drops section references such as `5.1.2 …`.

**`IsSubItem(line)`** (l.124): `line.StartsWith("o ") && line.Length > 3 && char.IsUpper(line[2])`. Because splitting is on `•`, "o " sub-items that follow a bullet are merged into that bullet's fragment (for example `"…issued with: o A condition of class. o Memoranda …"`). This rule therefore only catches a fragment that *begins* with "o X".

**`EnsureCapitalized(t)`** (l.126-127): if `t` is empty or `char.IsUpper(t[0])`, return it unchanged. Otherwise return `char.ToUpper(t[0]) + t[1..]`, uppercasing a single UTF-16 unit. Mac: uppercase the first character only if its uppercase mapping is a single scalar; otherwise leave it unchanged.

**`FormatEvidenceTask(t)`** (l.129-130): if `StartsWithActionVerb(t)`, return `EnsureCapitalized(t)`. Otherwise return `"Verify availability of: " + char.ToLower(t[0]) + t[1..]`.

**`StartsWithActionVerb(t)`** (l.146-155): a case-insensitive *prefix* match with no word boundary, so `Test` matches "Testing" and `Record` matches "Records"/"Recorded". The verbs are `Verify`, `Check`, `Review`, `Confirm`, `Inspect`, `Examine`, `Ensure`, `Compare`, `Test`, `Record`, `Sight`, `Interview`, `Observe`, `Note`, `Assess`, `Evaluate`, `Monitor`, `Measure`, `The company`, `The vessel`, `A printed`, `Shore based`, `Communications`, `Records`, `Evidence`, `Documentary`.

**`FormatNegativeAsPositive(line)`** (l.132-144): the first matching rule wins. Prefix checks are case-insensitive; `Contains` and `Replace` are case-insensitive and replace **all** occurrences.
1. Starts with `"There was no "` returns `"Verify that there is a " + line[13..]`
2. Starts with `"There were no "` returns `"Verify that there are " + line[14..]`
3. Starts with `"No "` returns `"Verify that " + lower(line[0]) + line[1..] + " — confirm this is not the case"`
4. Contains `" was not "`: replace with `" is "`, then return `"Verify that " + lower(c[0]) + c[1..]`
5. Contains `" were not "`: replace with `" are "`, same form
6. Contains `" had not been "`: replace with `" has been "`, same form
7. Contains `" had not "`: replace with `" has "`, same form
8. Contains `" did not "`: replace with `" does "`, same form
9. Otherwise return `"Verify that " + lower(line[0]) + line[1..]`

Only the **first character** is lowercased, which yields faithful oddities such as `"Verify that sMS procedures are followed"`. The grammar is not fixed, so `"records has been"` stays as is.

**`NormalizeForDedup(t)`** (l.157-158): `ToLowerInvariant()`, keep only characters where `char.IsLetterOrDigit` is true or the character is `' '`, then `Trim()`.

### 3.5 `SireBank` (`SireBank.cs`)
- `EnsureLoaded()` (l.38-74) uses double-checked locking.
  1. Load the resource `pack://application:,,,/AA;component/Sire/Data/sire2_question_bank.json` and deserialize it as `QuestionBank`, with the default `JsonSerializerOptions`: case-sensitive property names, and unknown members ignored.
  2. If there are zero questions, throw `SIRE question bank is empty.`
  3. For each question, compute `EvidenceTags = ExtractTags(q)` and `RoviqLocations = ExtractRoviqLocations(q.RoviqSequence)`.
  4. Then compute `_identified = IdentifyAllTasks(questions)`.
  5. On any exception, set `LoadError = ex.Message`, and set questions and identified to empty.
- `ByChapter()` groups by `Chapter` in first-appearance order, then orders by `int.TryParse(key) ? n : 999`.
- `InChapter(c)` and `InSection(s)` filter with an exact ordinal match, then sort by `QuestionNumberComparer`.
- `GetIdentifiedTasks(n)` returns the cached list, or an empty new list.
- `TotalIdentifiedTasks` is the sum of the list counts.

Mac: `SireBank` is a process-wide actor or `@MainActor` singleton. It exposes `load() async`, `questions`, `identifiedTasks: [String: [String]]`, keeps the **ordered** keys in bank order for exports, and exposes `loadError`. Decoding and enrichment run in a detached task and complete in well under a second.

### 3.6 `SireFlow`, the question document (`SireFlow.cs`)
**Colours** (l.28-37). Colours are fixed ARGB values; alpha is always FF.

| Name | Hex | Used for |
|---|---|---|
| Primary | `#1E40AF` | "Q n" heading, meta line, overview title |
| Muted | `#64748B` | subtitle, overview subtitle, smart-tags line |
| Slate | `#334155` | short-text heading, chip text, default body text for container XAML |
| ChipBg | `#F8FAFC` | full-question chip background |
| Default scheme | bg `#F1F5F9`, fg `#475569` | DATA SOURCE, PUBLICATIONS, OBJECTIVE, INDUSTRY GUIDANCE, INSPECTION GUIDANCE |
| Amber scheme | bg `#FEF3C7`, fg `#92400E` | SUGGESTED INSPECTOR ACTIONS |
| Green scheme | bg `#DCFCE7`, fg `#166534` | EXPECTED EVIDENCE |
| Red scheme | bg `#FEE2E2`, fg `#991B1B` | POTENTIAL GROUNDS FOR A NEGATIVE OBSERVATION |

**Document defaults (`NewDoc`, l.92-99).** FontFamily `Segoe UI`, FontSize 13, FontWeight Normal, PagePadding 0. Foreground is `bodyBrush ?? Slate`. The SIRE pane passes **Black** (`SirePage.xaml.cs:244,246`); quick-add passes nothing, which gives Slate.

**Building blocks.** Nothing is ever bold.
- `Heading(text, size, fg)`: a Paragraph with `FontSize=size` and `Margin=0,0,0,4`, containing one Run with `Foreground=fg`.
- `Line(text, size, fg, italic)`: a Paragraph with `FontSize=size`, `FontStyle=Italic|Normal` and `Margin=0,0,0,6`, containing a Run with `Foreground=fg`.
- `Chip(text, bg, fg)`: a Paragraph with `Background=bg`, `Padding=10,8,10,8` and `Margin=0,2,0,8`, containing a Run with `Foreground=fg`. The font size is inherited (13).
- `AddSection(label, body, scheme)`: skipped if `body` is null or whitespace. Otherwise, first a label Paragraph with `Background=scheme.Bg`, `FontSize=12`, `Padding=8,4,8,4`, `Margin=0,10,0,4` and a Run `label` with `Foreground=scheme.Fg`. Then every block from `ParseBlocks(body)`.
- WPF Thickness order is **left, top, right, bottom**.

**`BuildQuestion(q, bodyBrush)`** (l.41-65) emits these blocks in order:
1. `Heading("Q {QuestionNumber}", 20, Primary)`
2. `Line("{ChapterDisplay}   ·   Section {Section}   ·   {QuestionTypeDisplay}", 11, Muted, italic: true)`. There are **three spaces** on each side of `·`.
3. If `ShortQuestionText` is not whitespace: `Heading(ShortQuestionText, 15, Slate)`
4. If `FullQuestionText` is not whitespace: `Chip(FullQuestionText, ChipBg, Slate)`
5. `Line("Vessel: {VesselTypesDisplay}" + (RoviqSequence blank ? "" : "      ROVIQ: {RoviqSequence}"), 11, Primary)`. There are **six spaces** before `ROVIQ:`.
6. Sections, in order: `DATA SOURCE` (DataSource), `PUBLICATIONS`, `OBJECTIVE`, `INDUSTRY GUIDANCE`, `INSPECTION GUIDANCE` (all Default), `SUGGESTED INSPECTOR ACTIONS` (Amber), `EXPECTED EVIDENCE` (Green), `POTENTIAL GROUNDS FOR A NEGATIVE OBSERVATION` (Red)
7. If there are tags: `Line("Smart tags: " + string.Join("   ·   ", EvidenceTags), 10, Muted)`

Text fields such as the chip, meta and headings can contain embedded `\n` from PDF wrapping. They stay **inside one Run**, and WPF renders them as line breaks within the same paragraph. The Mac port must keep them in one paragraph: see §6.5, which uses U+2028.

**`BuildOverview(title, qs, bodyBrush)`** (l.68-78) is used for a section or chapter parent:
1. `Heading(title, 18, Primary)`
2. `Line("{qs.Count} SIRE 2.0 question(s). Imported from the SIRE 2.0 Knowledge Bank.", 11, Muted, italic)`
3. A `List` with `MarkerStyle=Disc` and `Margin=0,4,0,0`. It has one ListItem per question, in the order given (natural order). Each item is a Paragraph with `Margin=0,1,0,1` containing the Run `"Q {n} — {ShortQuestionText}"`.

**`ParseBlocks(text)`** (l.127-189), the PDF-bullet renderer. **Port it exactly**, because the stored structure has to match across platforms.
```
if text is null/whitespace → []
lines = text with "\r\n"→"\n", "\r"→"\n", split on '\n'
currentPara = null; inList = false; list = new List(Disc)
for rawLine in lines:
    line    = rawLine.TrimEnd()
    trimmed = line.TrimStart()
    isBullet = isSub = false
    if trimmed.Length > 1:
        if trimmed[0] in {'•','·','–','—'}  → isBullet
        else if trimmed starts with "- "     → isBullet
    if !isBullet and (line starts "    o " or line starts "\to " or trimmed starts "○ "):
        isBullet = isSub = true
    if isBullet and (line starts "    " or line starts "\t"): isSub = true
    if isBullet:
        FlushPara()
        if !inList: list = new List(Disc); inList = true
        bulletText = trimmed; strip the FIRST matching prefix of
            ["• ", "•", "· ", "– ", "— ", "- ", "o ", "○ "]  then TrimStart()
        para = Paragraph(Run(bulletText)) Margin 0,1,0,1
        if isSub and list has items:
            sub = last List inside the last ListItem, else create List(Circle) and append it to that ListItem
            sub.add(ListItem(para))
        else list.add(ListItem(para))
    else:
        FlushList()                       # any non-bullet line ends the list
        if line is whitespace: FlushPara()
        else:
            if currentPara == null: currentPara = Paragraph Margin 0,0,0,6
            else currentPara.add(Run(" "))  # separate Run holding one space
            currentPara.add(Run(trimmed))
FlushList(); FlushPara()
if no blocks: [Paragraph(Run(text))]    # effectively unreachable
```
Key consequences, all of which must be replicated:
- **PDF-wrapped bullet text is split.** A bullet line becomes a one-item list, and its wrapped continuation line becomes a separate paragraph *after* that list. A following bullet starts a *new* List.
- `o ` sub-items at column 0, which is how the bank stores all 3,049 of them, are **not** bullets. They are appended as plain text to the paragraph that follows.
- `` lines are plain paragraph text.
- A single character such as `•` alone is not a bullet, because `Length > 1` is required.
- Consecutive non-bullet lines become **one** paragraph whose Runs are `[line1, " ", line2, " ", line3…]`.
- A blank line ends both the list and the paragraph.

**`ToContainerXaml(doc)`** (l.82-88) is `TextRange(doc.ContentStart, doc.ContentEnd).Save(ms, DataFormats.Xaml)` decoded as UTF-8. §4.4 describes the resulting shape.

### 3.7 `SireToAa`, quick-add (`SireToAa.cs`)
`enum Kind { Procedure, Task, Equipment }`. `record Result(int ItemsCreated, int TasksCreated, HierarchyItem? Primary, string Summary)`.

**`CreateItem(repo, kind, name, bodyXaml)`** (l.77-95)
- Creates a `Procedure`, `TaskItem` or `Equipment` with `Name=name` and `Container.RichTextXaml=bodyXaml`, and adds the tag `"SIRE"`.
- **Appends** the item to `repo.Data.Procedures`, `.Tasks` or `.Equipment`.
- Every other field keeps the model default: new `Id`, no group, no deadline, `Status=Todo`, `DurationMinutes=60`, and so on.

**`AddQuestion(repo, q, kind, createTopLevelTasks=true)`** (l.23-39)
1. `parent = CreateItem(kind, "SIRE Q{n} — {ShortQuestionText}", BuildQuestionXaml(q))`. There is no space between `Q` and the number. A data field has an empty short text, which gives the name `"SIRE Q1.1.1 — "`.
2. `identified = GetIdentifiedTasks(n)`, then `AttachChildTasks(parent, identified)`:
   - **Procedure:** one `ChecklistStep { Title = t }` per task, with an empty container.
   - **Task:** one `TaskItem { Name = t }` per task, added to `Subtasks`.
   - **Equipment:** one `Component { Name = Truncate(t, 80), Notes = t }` per task.
3. `SpawnTopLevelTasks(repo, parent, q, identified)`. For each task text, a new `TaskItem`:
   - `Name = text`, `Tags = ["SIRE"]`, `Description = "SIRE Q{n} — {ShortQuestionText}"`
   - Appended to `repo.Data.Tasks`
   - `repo.AddRelation(parent, task)`, which adds each id to the other's `RelatedIds` if it is not already there
   - If the parent is Equipment, `eq.TaskIds.Add(task.Id)` if not already present
4. `repo.LogAdded(KindLabel(parent.Kind), parent.Name, "from SIRE Q{n}")`. This also calls `MarkDirty`.
5. Summary: `Added “{parent.Name}” as {kind}` + (`tasks > 0` ? ` with {tasks} linked task(s).` : `.`)

The same texts therefore exist **twice** when kind is Task (as subtasks and as top-level Tasks) and when kind is Equipment (as components and as linked top-level Tasks).

**`AddSection(repo, section, …)`** calls `AddGroup(InSection(section), name: "SIRE Section {section}")`.
**`AddChapter(repo, chapter, …)`** calls `AddGroup(InChapter(chapter), name: qs.Count > 0 ? "SIRE Ch{chapter} — {qs[0].ChapterName}" : "SIRE Ch{chapter}")`.

**`AddGroup(repo, qs, kind, createTopLevelTasks, parentName)`** (l.53-73)
1. If `qs` is empty, return `Result(0, 0, null, "No questions found for that selection.")`.
2. `parent = CreateItem(kind, parentName, BuildOverviewXaml(parentName, qs))`.
3. For each question, in natural order:
   - `AddQuestionChild(parent, q)`, with `title = "Q{n} — {ShortQuestionText}"` and the child body `BuildQuestionXaml(q)`:
     - **Procedure:** a `ChecklistStep { Title = title, Container.RichTextXaml = body }`
     - **Task:** a `TaskItem { Name = title, Container.RichTextXaml = body }` added to Subtasks
     - **Equipment:** a `Component { Name = Truncate(title, 90), Notes = q.FullQuestionText, Container.RichTextXaml = body }`
   - The question's identified tasks are **not** attached as grandchildren. When `createTopLevelTasks` is true, which is always the case from the UI, they are spawned as top-level Tasks linked to the **group parent**, and their Description names the originating question.
4. `LogAdded(KindLabel(kind), parent.Name, "from SIRE ({qs.Count} questions)")`.
5. Summary: `Added “{parent.Name}” as {kind} with {qs.Count} question(s)` + (`tasks > 0` ? ` and {tasks} linked task(s).` : `.`)

**`Truncate(s, max)`** (l.151): `s.Length <= max ? s : s[..max].TrimEnd() + "…"`. Length is measured in UTF-16 units; the Mac must count `s.utf16`. Do not split a surrogate pair: if unit `max-1` is a high surrogate, cut at `max-1`.

**Body XAML** (l.158-161): `BuildQuestionXaml(q)` is `ToContainerXaml(BuildQuestion(q))`, with the default Slate body. `BuildOverviewXaml` works the same way.

Scale note: a whole chapter 8 as Equipment creates 1 item, 91 components each with full XAML, and 1,705 top-level Tasks. The Mac must handle this without UI stalls. Build the model objects first, then insert them in one batched mutation and save once.

### 3.8 `GeminiService` (`GeminiService.cs`)
- **Endpoint:** `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key={Uri.EscapeDataString(apiKey)}` (l.15-16, 33).
- **Timeout:** 60 s (`HttpClient.Timeout`, l.17). One static client is shared across calls.
- **Body.** `Content-Type: application/json; charset=utf-8`:
  ```json
  {"contents":[{"parts":[{"text":"<PROMPT>"}]}],"generationConfig":{"temperature":0.4,"maxOutputTokens":2048}}
  ```
  STJ escapes non-ASCII and HTML-sensitive characters as `\uXXXX`. That makes no semantic difference, and any conforming JSON encoder is acceptable.
- **Prompt (`BuildPrompt`, l.48-72).** It is reproduced exactly below. Windows builds it with `AppendLine`, which writes CRLF, while the `\n` inside interpolations stays LF. Line endings do not matter to the model, and the Mac uses `\n` throughout. `⏎` marks a line end:
  ```
  You are a maritime SIRE 2.0 inspection expert. Based on the following SIRE 2.0 inspection question, generate specific, actionable inspection tasks that an inspector should complete. Generate as many tasks as needed to thoroughly cover the question — do not limit yourself.⏎
  ⏎
  Each task must be a concrete action using verbs like: verify, check, review, confirm, inspect, examine, ensure, compare, test, record.⏎
  Return ONLY a numbered list (1. 2. 3. etc.) with one task per line. No headings, explanations, or additional commentary.⏎
  ⏎
  === QUESTION CONTEXT ===⏎
  ⏎
  Question Number: {QuestionNumber}⏎
  Chapter: {ChapterDisplay}⏎
  Vessel Types: {VesselTypesDisplay}⏎
  ROVIQ Sequence: {RoviqSequence}⏎
  ⏎
  Full Question Text:⏎{FullQuestionText}⏎
  [if Objective not blank]                        ⏎Objective:⏎{Objective}⏎
  [if ExpectedEvidence not blank]                 ⏎Expected Evidence:⏎{…}⏎
  [if SuggestedInspectorActions not blank]        ⏎Suggested Inspector Actions:⏎{…}⏎
  [if PotentialNegativeObservationGrounds not blank] ⏎Potential Negative Observation Grounds:⏎{…}⏎
  [if IndustryGuidance not blank]                 ⏎Industry Guidance:⏎{…}⏎
  [if InspectionGuidance not blank]               ⏎Inspection Guidance:⏎{…}⏎
  [if Publications not blank]                     ⏎Publications:⏎{…}⏎
  ```
  Each optional block is `AppendLine("\n{Label}:\n{value}")`: a blank line, the label, the value, then a line end. The prompt uses the **raw bank text**, not the user's edited body.
- **Response parsing (`ParseResponse`, l.74-95).** For each `candidates[]` element, then each `content.parts[]`, then each `text`:
  1. `Split('\n', RemoveEmptyEntries)`
  2. `Trim()` each line
  3. Remove `^\d+[\.\)\-]\s*` (the .NET regex `\d` is any Unicode Nd)
  4. `Trim()` again
  5. Keep the line if `Length > 5`
  
  Markdown such as `**` and `- ` is **not** stripped. Missing properties are skipped silently. A non-array `candidates` throws, which ends up as "Unexpected error".
- **Outcomes, as an error string:**
  | Condition | Text |
  |---|---|
  | key null/whitespace (unreachable from UI) | `No Gemini API key set. Use Tools ▸ 'Set Gemini API key…' first.` |
  | non-2xx | `Gemini API error {statusCode}: {ExtractErrorMessage(body)}` |
  | 2xx but 0 tasks | `Gemini returned an empty response. Try again.` |
  | timeout (`TaskCanceledException`) | `Request timed out. Check your internet connection and try again.` |
  | `HttpRequestException` | `Network error: {ex.Message}` |
  | anything else (e.g. invalid JSON) | `Unexpected error: {ex.Message}` |
- **`ExtractErrorMessage(body)`** (l.97-107): parse the JSON and return `error.message` (or `"Unknown error"` if it is null). If parsing fails or the property is missing, return the body, truncated when it is over 200 characters to `body[..200] + "..."` (three ASCII dots).

### 3.9 Filtering and sorting (`SirePage.ApplyFilters`, `SirePage.xaml.cs:150-194`)
The function returns early until the bank and filters are ready. A question is kept only if **all** of these hold:
1. `chapters.Contains(q.Chapter)`, an ordinal set of the checked chapter keys
2. `q.VesselTypes.Count == 0 || q.VesselTypes.Any(v in checkedVessels)`, where `checkedVessels` is case-insensitive
3. `types.Contains(q.QuestionTypeDisplay)`
4. `evCat == "All" || q.EvidenceTags.Any(t => t.StartsWith(evCat + ":", OrdinalIgnoreCase))`
5. `search == "" || MatchesSearch(q, search)` (SIRE-005)
6. `statusFilter == "All" || MatchesStatus(q, statusFilter)`:
   - `In Progress`, `Checked` and `Not Applicable` require `GetStatus(n)` to equal that status
   - `Bookmarked` requires `IsBookmarked(n)`
   - `For Export` requires `IsForExport(n)`
   - `Has Tasks` requires `GetTasksForQuestion(n).Count > 0`
   - `No Status` requires `GetStatus(n) == None`

Sort orders. LINQ `OrderBy` is **stable**, so ties keep bank (natural) order. Swift must use an explicit stable sort:
| Sort | Key(s) |
|---|---|
| `Question Number` (default) | `QuestionNumberComparer` |
| `Chapter` | `int.TryParse(Chapter)` else 999, then QuestionNumberComparer |
| `Short Question Text` | ShortQuestionText (culture comparer) only. Empty short texts, such as the 25 data fields, sort first. |
| `Vessel Types` | VesselTypesDisplay (culture), then QuestionNumberComparer |
| `ROVIQ Sequence` | RoviqSequence raw string (culture), then QuestionNumberComparer |
| `Question Type` | QuestionTypeDisplay (culture), then QuestionNumberComparer |

After sorting, the list is displayed, the header shows `Questions ({count})`, and the previous selection is restored if it is still present.

### 3.10 `SireExport.Build` (`SireExport.cs`), exact text layout
Common frame, where `=` × 60 is the line of 60 equals signs:
```
============================================================
  SIRE 2.0 Knowledge Bank Export — {mode}
  Generated: {now:yyyy-MM-dd HH:mm}
============================================================
<blank>
<mode body>
<blank>
============================================================
  Generated by AA — SIRE 2.0 Knowledge Bank
============================================================
```
An unknown mode gives an empty body. Notation below: `QC` is `QuestionNumberComparer`, `T(t)` is `"[x]"` when completed and otherwise `"[ ]"`, and `{short}` is `ShortQuestionText`, which may be empty and then leaves a trailing space after `—`.

| Mode | Body |
|---|---|
| `All Tasks` | No tasks: `  No tasks found.` Otherwise group `state.Tasks` by QuestionNumber, groups ordered by QC. Each group writes `Q {key} — {short or "" if unknown}`, then its tasks **ordered by CreatedAt** (stable) as `  {T} {Text}`, then a blank line. |
| `Completed Tasks` / `Pending Tasks` | Filter by `IsCompleted`. None: `  No completed tasks found.` or `  No pending tasks found.` Otherwise `  Completed Tasks: {n}` or `  Pending Tasks: {n}`, a blank line, then the same grouping as All Tasks. |
| `Questions with Tasks` | Questions in the bank that have ≥1 task, ordered by QC. First `  Questions with Tasks: {n}` and a blank line. Each question writes `Q {n} — {short}`, its tasks in **insertion order** as `  {T} {Text}`, then a blank line. |
| `Selected Questions` | `QuestionList(all.Where(IsSelected) by QC, "Selected Questions")`. Always 0 on Windows (Q-3). |
| `For Export Tagged` | `QuestionList(ForExport members by QC, "Questions Tagged for Export")` |
| `Bookmarked Questions` | `QuestionList(Bookmarks members by QC, "Bookmarked Questions")` |
| `Current Filter Results` | `QuestionList(filtered in on-screen order, "Current Filter Results")` |
| `By Chapter` | Group all questions by ChapterDisplay, ordered by int(chapter) else 999. Each group writes `--- {ChapterDisplay} ({count} questions) ---`, then per question by QC `  Q {n}{tag} — {short}` where `tag = " [{StatusEnumName}]"` (`[InProgress]`, `[Checked]`, `[NotApplicable]`) or empty, then a blank line. |
| `By ROVIQ Location` | Map each location (case-insensitive key, first casing kept) to its questions, in bank order. Keys are culture-ordered. Each key writes `--- {loc} ({count} questions) ---`, then `  Q {n} — {short}` by QC, then a blank line. |
| `By Status` | For Checked, InProgress, NotApplicable and None, in that order: `--- {label} ({count}) ---` with the labels `Checked`, `InProgress`, `NotApplicable` and `Not Started`, then `  Q {n} — {short}` by QC, then a blank line. |
| `By Vessel Type` | Like ROVIQ, but keyed by each vessel type. Questions with no vessel types are omitted. |
| `Print Checklist` | `  INSPECTION CHECKLIST`, `  Total questions: {all.Count}`, a blank line. Then every question by QC as `{mark} Q {n} — {short}`, where mark is `[x]` Checked, `[~]` InProgress, `[N/A]` NotApplicable, or `[ ]`. Tasks follow in insertion order as `      {T} {Text}` (6 spaces). **No blank line between questions.** |
| `Inspection Summary` | `qs` is the questions with a status ≠ None if `QuestionStatuses` is non-empty, otherwise **all** questions; either way ordered by QC. First `  Inspection Summary: {n} questions` and a blank line. Each question writes `--- Q {n} [{StatusEnumName incl. "None"}] ---`, `  {short}`, the optional `  {FullQuestionText}`, `  Vessel: {VesselTypesDisplay} \| Chapter: {ChapterDisplay}`, the optional `  Objective: {…}`, the optional `  Evidence: {ExpectedEvidence}` and the optional `  Neg. Obs. Grounds: {…}`. If there are tasks, `  Tasks:` then `    {T} {Text}`. Then a blank line. |
| `Full Session Report` | `-- PROGRESS SUMMARY --`, then these lines, padded exactly: `  Checked:        {n}`, `  In Progress:    {n}`, `  Not Applicable: {n}`, `  Not Started:    {all.Count − QuestionStatuses.Count}`, `  Bookmarked:     {n}`, `  For Export:     {n}`, `  Total Tasks:    {total} ({completed} completed)`. Then a blank line, the **By Status** body, `-- ALL TASKS --`, a blank line, and the **All Tasks** body. |
| `Identified Tasks` | Empty: `  No identified tasks available.` Otherwise `  Identified Tasks: {total} tasks across {qcount} questions`, then `  (Pre-identified from question guidance text — no AI required)`, then a blank line. Group by ChapterDisplay, ordered by int(chapter). Each chapter writes `-- {ChapterDisplay} --` and a blank line, then per question by QC `  Q {n} — {short}`, its tasks as `    [ ] {task}`, and a blank line. Entries whose question is not in the bank are dropped. |

**`QuestionList(qs, title)`**: `  {title}: {count} questions` and a blank line. Each question writes:
- `Q {n} [{QuestionTypeDisplay}]`
- `  {short}`
- if the full text is non-empty: `  Full: {FullQuestionText}`. Embedded newlines are **not** re-indented.
- `  Vessel: {VesselTypesDisplay} | Chapter: {ChapterDisplay}`
- if ROVIQ is non-empty: `  ROVIQ: {RoviqSequence}`
- if the status is set: `  Status: {StatusDisplay}`, which is `In Progress`, `Checked` or `N/A`
- the tasks in insertion order as `  {T} {Text}`
- a blank line

**Status strings differ by mode, faithfully.** `By Chapter`, `By Status` and `Inspection Summary` use the **enum names** (`InProgress`, `NotApplicable`). `QuestionList` uses the **display names**.

**Line endings and clock (Windows):** `AppendLine` writes CRLF, while embedded bank text keeps LF. The `:` in `HH:mm` is the culture's time separator. Port decisions are in Q-12 and Q-14.

### 3.11 `SireState` operations (`SireState.cs`)
- `GetStatus(q)`: `QuestionStatuses.TryGetValue(q)` and then `Enum.TryParse<QuestionStatus>(value)`, which is case-**sensitive**. Otherwise `None`.
  - .NET also accepts **numeric** strings (`"2"` gives Checked), undefined numbers (`"7"` gives an out-of-range value that is `HasStatus` with an empty display), comma lists (`"InProgress, Checked"` gives 3, which is NotApplicable) and surrounding whitespace.
  - Mac: accept exactly `None`, `InProgress`, `Checked`, `NotApplicable`, or a trimmed integer 0–3. Treat anything else as None, but **keep the raw value** in the dictionary until the user sets that status.
- `SetStatus(q, None)` **removes** the key. Any other status stores `status.ToString()`, which is `"InProgress"`, `"Checked"` or `"NotApplicable"`.
- `CountByStatus(s)` counts values whose raw string equals `s.ToString()`.
- `ToggleBookmark(q)` and `ToggleForExport(q)`: `if (!list.Remove(q)) list.Add(q)`. That removes the **first** occurrence, or appends at the end.
- `GetTasksForQuestion(q)` returns the `Tasks` filtered by `QuestionNumber == q` (ordinal), in list order.
- `TotalTaskCount` and `CompletedTaskCount` are `[JsonIgnore]`.

### 3.12 Page state machine (`SirePage.xaml.cs`)
| Event | Actions |
|---|---|
| Selection changed | `FlushBody()` for the previous question, set `_selected`, enable or disable the detail pane, `LoadBody`, `RefreshTasks`, `UpdateActionButtons` |
| Editor `TextChanged` | `_bodyDirty = true`, unless the body is being loaded |
| Editor `LostFocus` | `FlushBody()` |
| Status or bookmark/export click | Mutate the state, update the question flag, `MarkDirty`, `UpdateStats`, plus a conditional re-filter for status only |
| Task add/remove/pick | Mutate `State.Tasks`, `MarkDirty`, `RefreshTasks`, `UpdateStats` |
| Task done toggle | Mutate, `MarkDirty`, `RefreshTasks` |
| `Init(repo)` when ready | `SyncQuestionFlags`, `UpdateStats`, `RefreshTasks`, `UpdateActionButtons`, `LoadBody(_selected)` |

---

## 4. Data formats

### 4.1 Embedded question bank `sire2_question_bank.json` (read-only)
- UTF-8 without BOM, pretty-printed, 3,350,301 bytes. SHA-256 `e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf`.
- Root: `{ "metadata": {…}, "questions": [ … 410 … ] }`.
- `metadata`: `title` (string), `version` (string), `date` (string), `source` (string), `total_questions` (int, 410). It also contains `parts` (an array of `{part, chapters, file}`) and `questions_by_chapter` (an object keyed by chapter string: `{name, count}`), which the model does **not** read.
- Each question object has these keys. Keys are snake_case and case-sensitive, and **absent keys default to `""` or `[]`**:

| Key | Type | Present in | Notes |
|---|---|---|---|
| `question_number` | string | all 410 | Always `N.N.N`, unique, file already in natural order |
| `chapter` | string | all | `"1"`…`"12"` |
| `section` | string | all | `"{chapter}.{n}"`, 72 distinct; every question number starts with `section + "."` |
| `chapter_name` | string | all | One name per chapter (see below) |
| `type` | string | all | `"inspection_question"` (385) or `"data_field"` (25, all chapter 1) |
| `full_question_text` | string | all | May contain `\n` from PDF wrapping |
| `short_question_text` | string | 385 inspection only | **Absent for data fields** |
| `vessel_types` | string[] | 385 inspection only | Values from {`Oil`, `Chemical`, `LPG`, `LNG`}, in source order; lengths 1–4 |
| `roviq_sequence` | string | 385 | Comma-separated locations; can contain `\n` and trailing notes |
| `publications`, `objective`, `industry_guidance`, `inspection_guidance`, `suggested_inspector_actions`, `expected_evidence`, `potential_negative_observation_grounds` | string | 385 | May be `""`. 53 chapter-11 photo questions have an empty objective and sections |
| `data_source` | string | 25 data fields only | |

- Chapter names: 1 Vessel, Operator and Inspection Particulars (25); 2 Certification and Documentation (19); 3 Crew Management (22); 4 Navigation and Communications (37); 5 Safety Management (88); 6 Pollution Prevention (16); 7 Maritime Security (6); 8 Cargo and Ballast Systems (91); 9 Mooring and Anchoring (14); 10 Engine and Steering Compartments (32); 11 General Appearance and Condition (54); 12 Ice Operations (6).
- Text characteristics that matter to the algorithms:
  - `•` starts 10,018 lines and `o ` starts 3,049 lines, all at column 0; no line has leading whitespace.
  - `` starts 238 lines. `- ` and `– ` each start 2 lines.
  - There are 1,850 blank lines.
  - Curly quotes and `…` appear in the text.
  - There is no `\r` and no tab.
- The Swift decoder must tolerate JSON `null` for any string (treat it as `""`) and must ignore unknown keys.

### 4.2 `AppData.Sire`, persisted in `data.json`
Serializer: System.Text.Json with `WriteIndented=false`, `IgnoreCycles` and `WhenWritingNull`, and **no naming policy**, so keys are PascalCase exactly as declared. Enums elsewhere are numbers, but this block stores status **strings**. Declaration order is the write order:
```json
"Sire": {
  "QuestionStatuses": { "2.1.10": "Checked", "1.1.1": "InProgress" },
  "Bookmarks": ["2.1.2"],
  "ForExport": ["2.1.10"],
  "Tasks": [
    { "Id": "0f8fad5b-d9cb-469f-a165-70867728950e",
      "QuestionNumber": "2.1.10",
      "Text": "Check log",
      "IsCompleted": true,
      "CreatedAt": "2026-09-30T10:00:00.1234567+02:00" }
  ],
  "QuestionBodies": { "2.1.10": "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" …>…</Section>" }
}
```
- **`QuestionStatuses`** is a string→string map from question number to one of `"InProgress"`, `"Checked"` or `"NotApplicable"`. `None` is never written because the key is removed instead.
- **`Bookmarks` and `ForExport`** are ordered string lists, in toggle order.
- **`Tasks`** is an ordered list. `Id` is a Guid in "D" format; STJ writes it lowercase. `CreatedAt` is the local `DateTime.Now`, serialized as ISO-8601 **with the local offset** and up to 7 fractional digits with trailing zeros trimmed.
  - Readers must accept 0–7 fractional digits, `Z`, `±hh:mm`, or no offset (unspecified, which counts as local).
  - Mac writers emit local time with the offset. Tasks created on the Mac should use **lowercase** UUID strings, because Flash Sync deep-equality compares strings.
- **`QuestionBodies`** is a string→string map from question number to a XAML `Section` document (§4.4).
  - STJ's default encoder writes `<`, `>`, `&`, `'`, `"`, `+` and non-ASCII as `<` and so on. That is textually different but semantically identical, and the Mac may write plain escapes.
  - The key is absent in data files from builds that predate the feature, and it must default to `{}`.
- **Always write the full object**, even when it is empty: `{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}}`. If `Sire` were omitted, Flash Sync would treat that as a `BlockDeletes` entry.
- Windows `SireState` has **no** `[JsonExtensionData]`, so unknown keys inside `Sire` are dropped on save. The Mac may preserve them; Windows will drop them regardless.
- **Cross-version rule:** questions are keyed by `question_number` string only. If the bank were ever replaced, entries for numbers that no longer exist would stay in the state. Exports skip them, except the `All Tasks` header, which shows an empty short text, and the Full Session Report's "Not Started" arithmetic.

### 4.3 Settings: `GeminiApiKey`
- Windows `settings.json` stores the key under `"GeminiApiKey": "<string>"`. It is omitted when null, and Trim()med on set.
- It is machine-local. It is never in `data.json` or bundles, and it is in Flash Sync's `ExcludedSettingsKeys`.
- The Mac stores the key in the Keychain (§6.9). If a settings file carried over from Windows contains `GeminiApiKey`, the Mac imports it into the Keychain once and **removes** it from the Mac's settings file. The Mac never writes it to any file.

### 4.4 Rich text produced and consumed (WPF XAML)
**Produced by SIRE on Windows:**
1. The container body of a quick-added parent item (question), or of a child step, subtask or component. This is `BuildQuestion`, with the **Slate** root foreground.
2. The container body of a section or chapter parent (`BuildOverview`), also Slate.
3. `SireState.QuestionBodies[n]`: the user-edited pane document. The root foreground is **Black**, and it contains whatever the user inserted: typed runs, new paragraphs, Ctrl+B/I/U runs, paragraph alignment and list changes, and pasted rich content.

**Consumed by SIRE:** `QuestionBodies[n]` is loaded with `TextRange.Load(DataFormats.Xaml)`, which accepts a `Section`, `Span` or `FlowDocument` root and any WPF-parsable content.

**Shape of `TextRange.Save(DataFormats.Xaml)` for a SireFlow document.** The element and attribute inventory below is authoritative. The attribute **order is not guaranteed**, so readers must be order-insensitive. There is no whitespace between elements, and text is kept verbatim under `xml:space="preserve"`.
```xml
<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve"
  TextAlignment="Left" LineHeight="Auto" IsHyphenationEnabled="False" xml:lang="en-us"
  FlowDirection="LeftToRight" NumberSubstitution.CultureSource="User" NumberSubstitution.Substitution="AsCulture"
  FontFamily="Segoe UI" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="13"
  Foreground="#FF334155"  (pane: "#FF000000")
  Typography.StandardLigatures="True" … (the ~40 Typography.* defaults WPF always emits) …>
  <Paragraph FontSize="20" Margin="0,0,0,4"><Run Foreground="#FF1E40AF">Q 2.1.10</Run></Paragraph>
  <Paragraph FontStyle="Italic" FontSize="11" Margin="0,0,0,6"><Run Foreground="#FF64748B">Ch 2: …   ·   Section 2.1   ·   Inspection</Run></Paragraph>
  <Paragraph FontSize="15" Margin="0,0,0,4"><Run Foreground="#FF334155">{short}</Run></Paragraph>
  <Paragraph Margin="0,2,0,8" Padding="10,8,10,8" Background="#FFF8FAFC"><Run Foreground="#FF334155">{full, may contain LF}</Run></Paragraph>
  <Paragraph FontSize="11" Margin="0,0,0,6"><Run Foreground="#FF1E40AF">Vessel: …      ROVIQ: …</Run></Paragraph>
  <Paragraph FontSize="12" Margin="0,10,0,4" Padding="8,4,8,4" Background="#FFFEF3C7"><Run Foreground="#FF92400E">SUGGESTED INSPECTOR ACTIONS</Run></Paragraph>
  <List MarkerStyle="Disc"><ListItem><Paragraph Margin="0,1,0,1"><Run>…</Run></Paragraph>
      <List MarkerStyle="Circle"><ListItem><Paragraph Margin="0,1,0,1"><Run>…</Run></Paragraph></ListItem></List>
  </ListItem></List>
  <Paragraph Margin="0,0,0,6"><Run>line one</Run><Run> </Run><Run>line two</Run></Paragraph>
  <Paragraph FontSize="10" Margin="0,0,0,6"><Run Foreground="#FF64748B">Smart tags: …</Run></Paragraph>
</Section>
```
Notes for the shared XAML⇄NSAttributedString converter, which is owned by the rich-text spec. The SIRE requirements are:
- **Elements:** `Section` (root), `Paragraph`, `Run`, `List` (`MarkerStyle` `Disc` or `Circle`; the Overview list also has `Margin="0,4,0,0"`), `ListItem`, and nested `List` inside `ListItem`. User edits can add `Bold`, `Italic`, `Underline`, `Span`, `LineBreak`, `Hyperlink` and pasted content such as tables.
- **Attributes:** `FontFamily`, `FontSize` (DIPs), `FontStyle`, `FontWeight`, `Foreground` and `Background` (`#AARRGGBB`), `Margin` and `Padding` (a 1-, 2- or 4-value Thickness), `TextAlignment`, `xml:space`, `xml:lang`, and the Typography.* defaults. Readers ignore the Typography.* defaults; writers may omit them, since WPF accepts XAML without them.
- An inheritable property (`Foreground`, `FontSize`, `FontStyle`) whose value equals the inherited one **may be omitted**, and readers must resolve inheritance themselves.
- A Run with an embedded `\n` must be preserved as text inside that Run, which WPF shows as a line break. It must not be split into separate paragraphs.
- `FontFamily="Segoe UI"` must be **preserved on write**, even though the Mac displays it with a substitute font.
- Colours are fixed ARGB values; there are no named or dynamic colours.
- WPF collapses adjacent vertical margins, taking the maximum of the previous bottom and the next top. The Mac approximation is described in §6.5.
- **Golden fixtures are required.** See Q-1: capture `BuildQuestionXaml` for 1.1.1, 2.1.1 and 11.1.2, `BuildOverviewXaml` for Section 7.1, and one edited `QuestionBodies` entry from the Windows harness. Commit them as Mac test fixtures.

### 4.5 Export text file
- UTF-8 without BOM. The content is exactly as in §3.10. The Windows default name is `SIRE_{mode.Replace(' ', '_')}_{yyyyMMdd_HHmm}.txt`, using the local time.

### 4.6 UI state
- The SIRE tab's identifier is `TabSire` in `Ui.TabOrder` and in `Ui.TabColors` keys. `Ui.SelectedMainTabIndex` is positional.
- Nothing else about SIRE is persisted in `Ui`: selection, filters, splitter widths and expanders are all transient.

---

## 5. Dependencies

### 5.1 What SIRE calls
| Target | Functions / members | Purpose |
|---|---|---|
| `AppRepository` | `Data.Sire`, `MarkDirty()`, `Save()`, `AddRelation(a,b)`, `LogAdded(kind,name,detail)`, static `KindLabel(ItemKind)`, `Data.Equipment/Tasks/Procedures` | Persistence and quick-add |
| Models | `Equipment` (`Components`, `TaskIds`), `Component` (`Name`, `Notes`, `Container`), `TaskItem` (`Name`, `Description`, `Subtasks`, `Tags`, `Container`), `Procedure` (`Steps`), `ChecklistStep` (`Title`, `Container`), `HierarchyItem` (`Tags`, `RelatedIds`, `Container.RichTextXaml`) | Quick-add output |
| `DataStore` | `GeminiApiKey` (read), `SetGeminiApiKey` (from MainWindow) | AI key |
| `MainWindow` | `NavigateToItem(item)`, `RefreshHierarchyPages()`, `StatusBlock.Text` (found via `FindName`) | After add, clipboard status |
| `ItemPickerWindow`, `PickerItem` | Multi/single picker | Task picker, kind picker, export mode picker |
| `PromptWindow` | Text prompt | Gemini key |
| WPF rich text | `FlowDocument`, `Paragraph`, `Run`, `List`, `ListItem`, `TextRange.Save/Load(DataFormats.Xaml)` | Body rendering and serialization |
| `HttpClient` | `PostAsync` | Gemini |

### 5.2 Who calls SIRE
| Caller | Call |
|---|---|
| `MainWindow.LoadDataAndInitUi` | `SirePg.Init(repo, NavigateToItem, RefreshHierarchyPages)` |
| `MainWindow.MainTabs_SelectionChanged` | `SirePg.EnsureLoaded()` when the SIRE tab is selected |
| `MainWindow.FlushAllEditors` | `SirePg.FlushBody()` |
| Tools ▸ SIRE 2.0 export… | `SirePg.ShowExportDialog()` |
| Tools ▸ Set Gemini API key… | `PromptWindow`, then `DataStore.SetGeminiApiKey` |
| Flash Sync / bundles / Drive | Carry `data.json`, including `Sire`, generically |

### 5.3 Cross-area dependencies (other spec owners)
- **Rich text / XAML converter**: the element and attribute inventory in §4.4, `Segoe UI` preservation, paragraph backgrounds and padding, disc and circle lists, intra-Run newlines.
- **Hierarchy (Equipment/Tasks/Procedures)**: model defaults, `NavigateToItem`, list reload, and the container editor/viewer that must render SIRE bodies.
- **Persistence**: `AppData` Codable with a `Sire` key, the debounced autosave, `FlushAllEditors` hooks, and the ISO date format.
- **Settings**: Keychain-backed secret, `GeminiApiKey` exclusion.
- **Flash Sync**: `Sire` is a block, and `GeminiApiKey` is excluded.
- **Main window shell**: `TabSire` identifier in tab order and colours, the Tools menu, and the status-line API.
- **Activity log**: `LogAdded` entries.

### 5.4 Windows-only APIs used
| API | Where | Mac replacement |
|---|---|---|
| WPF `pack://application:,,,/AA;component/…` + `Application.GetResourceStream` | SireBank:48-49 | `Bundle.main.url(forResource:withExtension:)` (tests: `Bundle.module`) |
| WPF `FlowDocument`/`RichTextBox`/`TextRange` + `DataFormats.Xaml` | SireFlow, SirePage | NSTextView (TextKit) + shared XAML converter |
| WPF `CommandBinding`/`ApplicationCommands`/`PreviewKeyDown`/`Key` | SirePage:40-68 | NSTextView subclass overrides (§6.4) |
| WPF `MessageBox` | throughout | SwiftUI `.alert` / `.confirmationDialog` / `NSAlert` sheets |
| `Microsoft.Win32.SaveFileDialog` | ShowExportDialog | `NSSavePanel` / `.fileExporter` |
| WPF `Clipboard.SetText` | ShowExportDialog | `NSPasteboard.general` |
| `ItemPickerWindow` / `PromptWindow` (WPF windows) | picks | SwiftUI sheets |
| `DispatcherTimer` (repository debounce) | indirect | `Task.sleep`-based debounce / Combine |
| `Brushes`, `ColorConverter`, `FontFamily("Segoe UI")` | SireFlow | `NSColor(srgbRed:…)`, font mapping |
| `Environment.NewLine` (CRLF), `CurrentCulture` comparisons/format separators | SireExport, TagExtractor, ApplyFilters | explicit `"\n"`, en_US locale compare, fixed `:` |
| `HttpClient` | GeminiService | `URLSession` (portable API, not Windows-only) |

No DPAPI, Win32, Process.Start, OpenCV or DirectShow code is used by this subsystem.

---

## 6. macOS adaptation notes

### 6.1 Module layout (Swift 6, strict concurrency)
- `Sire/Model`: `SireQuestion` (struct: Sendable, Codable, Identifiable by `questionNumber`), `QuestionBank`, `BankMetadata`, `QuestionStatus` (enum with `rawValue` strings `None/InProgress/Checked/NotApplicable` and `displayName`), `SireTask` and `SireState` (Codable, inside `AppData`).
- `Sire/Engine`: pure, `nonisolated`, fully unit-testable:
  - `QuestionNumberOrder`
  - `TagExtractor`
  - `TaskIdentifier`
  - `SireFlow`, which builds a small **block model** (`Paragraph`/`Run`/`List`/`ListItem` with the WPF attributes) and has two renderers: the XAML writer, which is byte-stable for container bodies, and NSAttributedString for display
  - `SireExport`, with an injected `now: Date`, `TimeZone` and `Calendar`
  - `SireToAa`
- `Sire/Services`: `SireBank`, an actor or a `@MainActor` class with a background load, and `GeminiClient`, a Sendable struct with `async throws`.
- `Sire/UI`: `SireViewModel` (`@Observable @MainActor`), `SireView`, `SireFilterPane`, `SireQuestionList`, `SireDetailView`, `SireTasksSection`, `SireBodyEditor` (an `NSViewRepresentable` wrapping `InsertionOnlyTextView`), plus the sheets `TaskCandidatePickerSheet`, `AddToAAKindSheet`, `SireExportSheet` and `GeminiKeyView`.
- Build the XAML for quick-add **directly from the block model**. Do not route it through NSAttributedString, so that container bodies are deterministic and match the Windows structure.

### 6.2 Layout and look
- In the app's main `NavigationSplitView`, SIRE is a sidebar destination titled **`SIRE 2.0`** with the SF Symbol `checklist.checked` (or `list.bullet.clipboard`). Its detail area is an `HSplitView` with three panes that keep the Windows proportions:
  - **Filter pane:** 220–320 pt, default 250, collapsible from a toolbar button with `line.3.horizontal.decrease.circle`. It uses a sidebar-style `.background(.regularMaterial)` or `List` with `.listStyle(.sidebar)`. The layout: `SIRE 2.0 Filters` header plus `Reset`, the search field, the `Sort by`, `Evidence category` and `Session status` Pickers (`.menu` style), and `DisclosureGroup`s for `Chapters` (expanded, with `All`/`None` buttons), `Vessel types` and `Question type` (collapsed), each containing `Toggle` checkboxes. The stats footer sits at the bottom in `.caption` and `.secondary`.
  - **Question list:** 300–480 pt, default 360. A `List(selection:)` with the header `Questions ({n})` and the rows described in SIRE-014. Row numbers use `.monospacedDigit()`.
  - **Detail:** flexible. From top to bottom:
    1. A status control row, which can also live in the toolbar
    2. The quick-add row
    3. The Tasks section (a `GroupBox` or `DisclosureGroup`, expanded)
    4. The body editor with its hint strip and `↺ Reset`
- Use **toolbar items** where natural: search, the filter-pane toggle, and an `Add to AA` `Menu` with the SF Symbol `plus.rectangle.on.folder` containing the items `This question…`, `Whole section…` and `Whole chapter…`. The in-pane quick-add row is still kept; it is fine to keep both, as long as all three actions stay reachable.
- **SF Symbols** (the Windows glyphs may be kept in labels):

  | Control | SF Symbol |
  |---|---|
  | In Progress | `hourglass` |
  | Checked | `checkmark.circle` |
  | N/A | `minus.circle` |
  | Clear | `xmark.circle` |
  | Bookmark | `star` / `star.fill` |
  | EXP tag | `tag` / `tag.fill` |
  | Identified | `list.clipboard` |
  | AI Suggest | `sparkles` |
  | Reset | `arrow.counterclockwise` |
  | Remove task | `xmark` (shown on hover) |

  **Keep the exact user-facing text strings** listed in §2 for labels and tooltips, via `.help()`.
- Materials and animation: animate badge changes with `.animation(.snappy)`. Removing a row animates, and filtering animates only for small result deltas.
- Empty states:
  - Filtered to nothing: `ContentUnavailableView.search(text:)`, or a generic "No questions match" when there is no search text.
  - No selection: see SIRE-016.
  - Tasks empty: a quiet `.secondary` text `No tasks yet`, which is additive.
- Dark mode: chrome follows the system appearance. **The body editor stays light paper** (SIRE-041). The bookmark star stays `#F0A030`.

### 6.3 Keyboard mapping
| Windows | Mac |
|---|---|
| Enter in the new-task box | Return (`.onSubmit`) |
| Ctrl+C / Ctrl+Insert (body) | ⌘C |
| Ctrl+A (body) | ⌘A |
| Ctrl+V / Shift+Insert (body) | ⌘V (insert at the selection start) |
| Ctrl+X, Backspace, Delete (blocked) | ⌘X, ⌫, ⌦, ⌥⌫, ⌘⌫, ⌃H, ⌃D, ⌃K and all delete/transposition actions blocked |
| Ctrl+Z / Ctrl+Y | ⌘Z / ⇧⌘Z (undo of the user's own insertions) |
| Ctrl+B/I/U (typing attributes) | ⌘B/⌘I/⌘U (typing attributes only; no effect on existing text) |
| ↑/↓ in list | ↑/↓ |
| Ctrl+1…9 tabs | ⌘1…9 (shell spec) |
| Enter = OK in pickers | Return = default button; **Esc = Cancel** (additive) |

Optional additive commands, placed in a `SIRE` CommandMenu that is enabled only while the SIRE destination is active: `Mark In Progress`, `Mark Checked`, `Mark N/A`, `Clear Status`, `Toggle Bookmark` and `Toggle Export Tag`. Choose shortcuts that do not collide with the shell spec; ⌥⌘-letter combinations are suggested. Focus-search is ⌘F only if the shell spec does not claim ⌘F globally; otherwise use ⌥⌘F.

### 6.4 Insertion-only body editor on NSTextView
Implement `InsertionOnlyTextView: NSTextView` with the following rules. Rule 1 is the single choke point.
1. **Gate:** `shouldChangeText(in affectedCharRange:, replacementString:)` returns `false` whenever `affectedCharRange.length > 0`. That rejects both replacement and attribute-only changes over existing text. Two exceptions:
   - (a) `undoManager?.isUndoing == true` or `isRedoing == true`. Undo removes the user's own insertions.
   - (b) the range lies entirely within the current **marked text** (IME composition).
2. **Collapse before insert:** override `insertText(_:replacementRange:)`, `insertNewline(_:)`, `insertParagraphSeparator(_:)`, `insertTab(_:)`, `insertLineBreak(_:)`, `paste(_:)`, `pasteAsPlainText(_:)` and `pasteAsRichText(_:)`. If `selectedRange().length > 0`, set `selectedRange = NSRange(location: sel.location, length: 0)` first, then call `super`. This mirrors Windows, which inserts before the selection.
3. **Block** these by overriding them as no-ops: `deleteBackward`, `deleteForward`, `deleteWordBackward`, `deleteWordForward`, `deleteToBeginningOfLine`, `deleteToEndOfLine`, `deleteToBeginningOfParagraph`, `deleteToEndOfParagraph`, `deleteBackwardByDecomposingPreviousCharacter`, `cut`, `delete`, `transpose`, `transposeWords`, `capitalizeWord`, `lowercaseWord`, `uppercaseWord`, `yank` (because it can replace), and `complete`. `validateUserInterfaceItem` returns `false` for `cut:` and `delete:`.
4. Disable drag and drop: `unregisterDraggedTypes()`, and override `dragSelection(with:offset:slideBack:)` to return false.
5. Disable anything that could rewrite existing text:
   - `isAutomaticSpellingCorrectionEnabled`, `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled` and `isAutomaticTextCompletionEnabled` are all false
   - `writingToolsBehavior = .none`
   - `usesFindBar = true` with replace disabled: `validateUserInterfaceItem` returns false for `performTextFinderAction` when the tag is a replace action
   - `usesInspectorBar = false`, and `usesFontPanel = false` or ignore font panel changes (they go through rule 1 anyway)
6. Paste: accept rich or plain text, but sanitize it through the converter's supported attribute set and **strip attachments**, because images are not representable in the stored XAML.
7. Context menu (`menu(for:)`): exactly `Copy`, `Paste (insert)` and `Select All`.
8. The appearance is forced to light (`.aqua`), with background `#FCFCFC`, text inset 12 pt, and a vertical scroller.
9. Dirty tracking: set `bodyDirty` in `textDidChange` unless `isLoading`. Flush:
   - (a) on a selection change
   - (b) in `resignFirstResponder` / `textDidEndEditing`
   - (c) from the app-wide flush hook, which is called by **every** save path: ⌘S, periodic autosave, window close/quit (`applicationShouldTerminate`), sync, export, Flash Sync and opening detached windows
   - (d) additionally after a **debounce of 750 ms of idle typing**, matching the repository debounce

   Points (c) and (d) close the Windows gap described in Q-8.
10. Load-failure safety: if the stored XAML fails to parse, show the generated original **read-only** with an inline banner: `Your saved edits for this question could not be displayed on this Mac. They are kept unchanged.` Offer the buttons `Reset to original` and `Edit anyway (replaces saved edits)`. This deliberately differs from Windows, which silently shows the original as editable and lets the next keystroke overwrite the stored edits. The rationale is data safety, following the `_contentWithheld` precedent in PROGRESS.md. It is recorded as Q-9.

   If the converter **can** parse the XAML but reports lossy elements it cannot represent, such as a pasted table, apply the same read-only banner.

### 6.5 Rendering the SireFlow blocks as NSAttributedString
- Fonts: `Segoe UI` maps to `NSFont.systemFont(ofSize:)` (SF Pro) for display. Keep a custom attribute `.xamlFontFamily = "Segoe UI"` so round-trips write `Segoe UI` back. Map sizes **1 WPF DIP to 1 pt** on screen. Use weight `.regular` everywhere, and `NSFontDescriptor` italic for `FontStyle=Italic`.
- Paragraph spacing: WPF `Margin(l,t,r,b)` becomes `paragraphSpacingBefore = t`, `paragraphSpacing = b`, `headIndent = firstLineHeadIndent = l`, `tailIndent = −r`. To approximate WPF's collapsed margins, when writing the attributed string, set `paragraphSpacingBefore = max(0, t − previous.b)`. The model keeps the original values for XAML.
- Chip and section-label backgrounds with padding: TextKit 1 can use `NSTextBlock` with `backgroundColor` and `setWidth(_:type:.absoluteValueType, for: .padding, edge:)`. With TextKit 2, draw them via a custom `NSTextLayoutFragment` that reads a custom `.blockBackground` / `.blockPadding` attribute. **Follow whichever approach the rich-text spec picks** for the container editor, so the two stay consistent.
- Lists: `NSTextList(markerFormat: .disc)`, and `.circle` for nested lists. Nested items have `textLists = [outer, inner]`. List item paragraphs use `Margin 0,1,0,1`.
- Intra-Run `\n` from bank text becomes **U+2028 LINE SEPARATOR** inside the same paragraph. The writer converts it back to `\n` inside the Run, so the text round-trips byte-exactly.
- Colours: `NSColor(srgbRed:green:blue:alpha:)` from the hex table in §3.6. Body text is `#000000` in the pane and `#334155` in containers.

### 6.6 Filtering and performance
- Filtering 410 structs on the main actor is sub-millisecond, so it can be synchronous on every change. An optional 100–150 ms debounce may be added to the search field.
- Precompute the lowercased search fields per question once at load, so `contains` can be case-insensitive via `range(of:options:[.caseInsensitive])`. It must match .NET `OrdinalIgnoreCase` for the relevant text; use `.caseInsensitive` **without** `.diacriticInsensitive`.
- The List needs no virtualization tricks: SwiftUI `List` is lazy.

### 6.7 Pickers and alerts
- The Yes/No and OK/Cancel `MessageBox`es become `.alert` or `.confirmationDialog` with the **exact titles and messages** from §2.
- Button role mapping:

  | Windows | Mac |
  |---|---|
  | OK / Cancel | Continue (default) / Cancel |
  | Yes / No for "Go to it now?" | Go to Item / Not Now |

  The message text must remain `{Summary}\n\nGo to it now?`.
- Warning icons use `NSAlert.Style.warning` or a SwiftUI alert with a destructive-styled action where appropriate.

### 6.8 Export
- The `SireExportSheet` contains:
  - The mode `List` (all 16, in the Windows order, `Print Checklist` pre-selected)
  - A live preview `TextEditor`, read-only, using `.monospaced()`
  - The buttons `Copy`, `Save…` (`NSSavePanel`, `allowedContentTypes: [.plainText]`, default name as in §4.5) and `Cancel`
  - Optionally `Share…` (`ShareLink` / `NSSharingServicePicker`) and `Print…` (`NSPrintOperation` over a monospaced `NSTextView`)
- Write the file as UTF-8 without BOM, with **LF** line endings (Q-12).
- After `Copy`, report `SIRE export copied to clipboard.` through the shell's status line.
- Error alerts are `Clipboard failed` and `Save failed` with `error.localizedDescription`.
- The bank may still be loading when export is invoked. In that case, `await` the load with a small progress indicator, then show the sheet. If the load failed, show `Could not load the SIRE question bank:\n{error}`. The Windows text `The SIRE question bank is still loading — try again in a moment.` is kept for the case where the user dismisses the wait.

### 6.9 Gemini API key and client
- Storage is the **Keychain**: `kSecClassGenericPassword`, service `"{bundleID}.gemini"`, account `"GeminiApiKey"`, accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and not synchronizable. On import from a Windows settings file, see §4.3.
- UI:
  - Tools ▸ **`Set Gemini API Key…`**
  - **Settings (⌘,) ▸ `AI`** tab with a `SecureField`, a reveal toggle and `Save`/`Clear` buttons
  - Status messages `Gemini API key saved.` / `Gemini API key cleared.`
  - Clearing **deletes** the Keychain item. This fixes Q-5.
- Client: `URLSession` with an ephemeral configuration and `timeoutIntervalForRequest = 60`, POST, the same URL, model and body.
  - Prefer sending the key in the **`x-goog-api-key` header** instead of the `?key=` query parameter. The API supports both, and the header keeps the key out of URL logs. This is an allowed transport difference; see Q-6.
  - Map `URLError.timedOut` to the timeout text, other `URLError`s to `Network error: {localizedDescription}`, a non-2xx status to `Gemini API error {code}: {message}`, and decode failures to `Unexpected error: {…}`.
- `ParseResponse` must be ported exactly: the regex `^\d+[\.\)\-]\s*` and `count > 5`, where the count uses UTF-16 length.
- Model constants live in one place (`GeminiClient.model = "gemini-2.5-pro"`, `temperature 0.4`, `maxOutputTokens 2048`) so they can be updated. See Q-6 about thinking tokens.

### 6.10 Quick-add on Mac
- Run `SireToAa` on the main actor against the repository model, then save once and send the shell a "hierarchy changed" notification so the Equipment, Tasks and Procedures lists refresh. After "Go to Item", navigate through the shell's `navigate(to:)`.
- For chapter-scale adds (up to about 1,700 tasks), build the objects first and append them in one batch, so observation fires once.
- Optionally register an **undo group** named `Add to AA` (⌘Z removes the created items and their relations). This is additive.

### 6.11 Data-model swap
- On reload, import or a Flash Sync apply, the view model re-binds to the new `SireState`, re-filters (fixing Q-10), re-derives the badges, keeps the selection if the question still exists, and reloads the body from the new state **without flushing** the previous editor contents into the new state. The shell must flush before the swap, as Windows does.

### 6.12 Culture-sensitive ordering
- .NET's default `string` comparer is culture-sensitive (ICU, current culture). It is used for tag order, vessel/type filter lists, the `Short Question Text`/`Vessel Types`/`ROVIQ Sequence`/`Question Type` sorts, and the ROVIQ and vessel groupings in export.
- Mac: use `a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US"))` everywhere Windows uses the default comparer. That gives deterministic results that match .NET en-US for the SIRE data: lowercase before uppercase at a tie, and punctuation before letters.
- One known possible divergence: embedded `\n` in the ROVIQ keys (`"Interview -\nRating"`). Foundation treats it as non-ignorable, while ICU in .NET may ignore it. See Q-2 and TV-SORT.
- For **ordinal / OrdinalIgnoreCase** comparisons (search, dedup, sets), use `.literal`-style comparisons, with `.caseInsensitive` where Windows says IgnoreCase.

### 6.13 Things that are impossible or different on macOS
| Windows piece | Mac status |
|---|---|
| Segoe UI font | Not bundled on macOS, and it cannot be redistributed. **Closest faithful alternative:** display in SF Pro, but store and emit `Segoe UI` in XAML so Windows keeps the original font. |
| WPF `TextRange.Save` byte-exact output | The Mac writer produces a structurally equivalent Section XAML that WPF's `TextRange.Load` accepts. Byte-identity is not required, but structural identity is, and it is verified against the golden fixtures (Q-1). |
| WPF paragraph-level formatting shortcuts on the caret paragraph | Blocked by the §6.4 rule 1 gate. Alignment and list toggles over existing text are therefore not possible on the Mac. This is an acceptable narrowing, recorded as Q-15. |

Nothing else in this subsystem is impossible on macOS.

---

## 7. Test vectors and verification

These vectors use **synthetic inputs**. The OCIMF bank content is copyrighted and must not be pasted into tests. Tests that run against the real bank assert only aggregates and structure.

### 7.1 Bank integrity
- TV-BANK-1: SHA-256 of the bundled `sire2_question_bank.json` = `e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf`, and its size is 3,350,301 bytes.
- TV-BANK-2: after decoding there are 410 questions and 12 chapters. Per-chapter counts: 1:25, 2:19, 3:22, 4:37, 5:88, 6:16, 7:6, 8:91, 9:14, 10:32, 11:54, 12:6. There are 72 distinct sections, and the question numbers are unique and already in natural order.
- TV-BANK-3: type distribution is `Data Field` 25, `Inspection` 331, `Photograph` 54. 25 questions have no vessel types. `IsDetailedQuestion` is true for 332.
- TV-BANK-4: the filter lists after load are:
  - chapter labels `Ch 1: Vessel, Operator and Inspection Particulars (25)` … `Ch 12: Ice Operations (6)`, in numeric order
  - vessel types `[Chemical, LNG, LPG, Oil]`
  - types `[Data Field, Inspection, Photograph]`
- TV-BANK-5: distinct ROVIQ locations across the bank, case-insensitive, number **39**.

### 7.2 QuestionNumberComparer
| Input | Expected |
|---|---|
| sort `["1.1.10","2.1.1","1.1.2","10.1.1","1.1.1"]` | `["1.1.1","1.1.2","1.1.10","2.1.1","10.1.1"]` |
| `compare("1.1","1.1.0")` | 0 |
| `compare("x.1","0.1")` | 0 |
| `compare("11.1.95","11.1.100")` | < 0 |
| `compare(nil,"1")` | < 0 |
| `compare("1",nil)` | > 0 |

### 7.3 TaskIdentifier
These expectations come from an independent line-by-line re-implementation of the C#. Confirm TV-ID-BANK with the Windows harness (Q-16).
- **TV-ID-BANK:** `IdentifyAllTasks(bank)` gives **332** keys and **6,106** tasks in total, with a minimum of 6 and a maximum of 39 per question. Tasks per chapter: 2:325, 3:348, 4:641, 5:1718, 6:330, 7:116, 8:1705, 9:248, 10:585, 11:6 (only 11.1.1), 12:84. The first three keys are `2.1.1`, `2.2.1` and `2.2.2`.
- **TV-ID-1**, all three modes. The input is a detailed question (non-empty objective).
  - SuggestedInspectorActions:
    `"• review the planned maintenance records for the fire pump.\n• Note: inspectors must record this\n• 5.1.2 cross reference to other question\n• short\n• 1) check the emergency generator start log."`
  - ExpectedEvidence:
    `"• The company procedure for bunkering.\n• Records of fire drills\n• oil record book entries, etc."`
  - PotentialNegativeObservationGrounds:
    `"• There was no procedure for enclosed space entry.\n• There were no records of drills.\n• No gas detector was available.\n• The Master was not familiar with the SMS.\n• Records had not been kept up to date.\n• The crew had not completed training.\n• The OOW did not know the procedure.\n• SMS procedures were not followed.\n• Fire hoses were damaged."`

  Expected output, in this exact order:
  1. `Review the planned maintenance records for the fire pump`
  2. `Check the emergency generator start log`
  3. `The company procedure for bunkering`
  4. `Records of fire drills`
  5. `Verify availability of: oil record book entries, etc.`
  6. `Verify that there is a procedure for enclosed space entry`
  7. `Verify that there are records of drills`
  8. `Verify that no gas detector was available — confirm this is not the case`
  9. `Verify that the Master is familiar with the SMS`
  10. `Verify that records has been kept up to date`
  11. `Verify that the crew has completed training`
  12. `Verify that the OOW does know the procedure`
  13. `Verify that sMS procedures are followed`
  14. `Verify that fire hoses were damaged`
- **TV-ID-2**, the no-bullet fallback. SIA `"Review the crew list against the manning certificate\nVerify rest hours"`, with EE and NEG empty, gives:
  1. `Review the crew list against the manning certificate Verify rest hours` (the whole text, collapsed)
  2. `Review the crew list against the manning certificate`
  3. `Verify rest hours`
- **TV-ID-3**, dedup, sub-item and prefix stripping. SIA `"o Oily water separator overboard valve sealed\n• - a. Verify the OWS alarm setting.\n• Verify the OWS alarm setting\n• VERIFY THE OWS ALARM SETTING!"` with EE `"• Verify the OWS alarm setting"` gives the single task `Verify the OWS alarm setting`.
- **TV-ID-4:** a question with `type="data_field"`, or an inspection question with an empty objective, has no entry in `IdentifyAllTasks`.

### 7.4 TagExtractor and DominantCategory
In each case, `searchText` is built from EE, SIA, short text and objective, in that order.
- **TV-TAG-1.** Input: short `Fire pump and SCBA readiness`, objective `To ensure the fire pump is maintained per the PMS.`, EE `• Maintenance records\n• Muster list`, SIA `• Interview the Chief Engineer`.
  - Tag set: {`Equipment: SCBA`, `Equipment: fire pump`, `Procedure: muster list`, `Procedure: PMS`, `Record: maintenance record`, `Personnel: Chief Engineer`}.
  - **Culture order (en_US):** `Equipment: fire pump`, `Equipment: SCBA`, `Personnel: Chief Engineer`, `Procedure: muster list`, `Procedure: PMS`, `Record: maintenance record`. Ordinal order would put `SCBA` before `fire pump`, which is wrong.
  - `DominantCategory` gives `Equipment` (E=2, P=2).
- **TV-TAG-2**, substring false positives. Short `Operating groups raised the document` gives, in order, `Document: DOC`, `Equipment: AIS`, `Equipment: UPS`, `Personnel: rating`. Dominant is `Equipment`.
- **TV-TAG-3**, punctuation ordering. Short `Crane and derrick; P/V valve, PV valve and pressure vacuum`, in en_US order, gives `Equipment: crane`, `Equipment: derrick`, `Equipment: P/V valve`, `Equipment: pressure vacuum`, `Equipment: PV valve`.
- **TV-TAG-4:** empty text gives `[]` and dominant `Task`. Counts {E:0, P:2} give `Procedure`, {E:2, P:3} give `Procedure`, and {D:3, R:2} give `Task`. A tag `equipment: x` (lowercase category) is **not counted**.
- **TV-TAG-BANK:** dominant distribution Procedure 187, Equipment 144, Task 79. 54 questions have zero tags. Question `1.1.1` has no tags.

### 7.5 ExtractRoviqLocations
| Input | Output |
|---|---|
| `"Documentation, Pre-board"` | `["Documentation","Pre-board"]` |
| `"Main Deck, Pre-board, Documentation"` | `["Documentation","Main Deck","Pre-board"]` |
| `"Bridge., bridge"` | `["Bridge"]` |
| `"Bridge ."` | `["Bridge "]` (the trailing space is kept) |
| `" , ,"` / `""` | `[]` |
| `"Interview -\nRating"` | `["Interview -\nRating"]` |

### 7.6 SireFlow.ParseBlocks (block structure)
- **TV-FLOW-1.** Input:
  `"Intro line one\nintro line two\n\n• First bullet\n    o nested a\n\to nested b\n• Second bullet wraps\ncontinuation text\n- dash item\n– en dash item\n· middle dot item\n○ circle sub\n wingding line\no letter-o line"`

  Expected blocks:
  1. `P[runs: "Intro line one", " ", "intro line two"]`
  2. `List(Disc)`:
     - `Item "First bullet"`, containing `List(Circle)` with `Item "nested a"` and `Item "nested b"`
     - `Item "Second bullet wraps"`
  3. `P[runs: "continuation text"]`
  4. `List(Disc)`:
     - `Item "dash item"`
     - `Item "en dash item"`
     - `Item "middle dot item"`, containing `List(Circle)` with `Item "circle sub"`
  5. `P[runs: " wingding line", " ", "o letter-o line"]`
- **TV-FLOW-2.** Input `"•\n• \n•x\n-x\n- \nplain"` gives:
  1. `P["•"," ","•"]`
  2. `List(Disc)[Item "x"]`
  3. `P["-x"," ","-"," ","plain"]`
- **TV-FLOW-3:** input `"   \n\n"` gives no blocks, and `AddSection` then omits the section entirely.
- **TV-FLOW-4**, a PDF-wrapped bullet. Input `"• First half of a long\nsecond half.\n• Next"` gives:
  1. `List[Item "First half of a long"]`
  2. `P["second half."]`
  3. `List[Item "Next"]`
- **TV-FLOW-Q**, using `BuildQuestion` on a synthetic question with number `2.1.10`, chapter 2 `Certs`, section `2.1`, type inspection, short `Beta check`, full `Is beta ok?`, vessel `[Oil, LNG]`, ROVIQ `Bridge, Documentation`, objective `Obj B` and no tags. The expected blocks are:
  1. Heading "Q 2.1.10" (20, #1E40AF)
  2. Italic line "Ch 2: Certs   ·   Section 2.1   ·   Inspection" (11, #64748B)
  3. Heading "Beta check" (15, #334155)
  4. Chip "Is beta ok?"
  5. Line "Vessel: Oil, LNG      ROVIQ: Bridge, Documentation" (11, #1E40AF)
  6. Label "OBJECTIVE" (bg #F1F5F9, fg #475569)
  7. `P["Obj B"]`

  There is no smart-tags line. The root foreground is Black in the pane and Slate in the container.

### 7.7 Gemini
- **TV-GEM-1, parse.** The body is `{"candidates":[{"content":{"parts":[{"text":"1. Verify the log.\n2) Check pump\n\n3- Inspect hoses thoroughly\n- Review plan\nOK\n10.Test alarm\n   \n123456\n12345"}]}}]}`. The result is `["Verify the log.", "Check pump", "Inspect hoses thoroughly", "- Review plan", "Test alarm", "123456"]`.
- **TV-GEM-2, multiple candidates and parts** are concatenated in order.
- **TV-GEM-3, no candidates.** `{}` with HTTP 200 gives the error `Gemini returned an empty response. Try again.`
- **TV-GEM-4, API error.** HTTP 400 with `{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}` gives `Gemini API error 400: API key not valid. Please pass a valid API key.`
- **TV-GEM-5, non-JSON error body.** HTTP 503 with a 250-character plain body gives `Gemini API error 503: ` + the first 200 characters + `...`.
- **TV-GEM-6, prompt.** For TV-FLOW-Q's question, the prompt starts with the fixed preamble and contains `Question Number: 2.1.10`, `Chapter: Ch 2: Certs`, `Vessel Types: Oil, LNG`, `ROVIQ Sequence: Bridge, Documentation`, `Full Question Text:\nIs beta ok?` and `\nObjective:\nObj B`. It does **not** contain `Expected Evidence:` because that field is blank. Compare after normalizing CRLF to LF.
- **TV-GEM-7, request.** The method is POST. The URL path is `/v1beta/models/gemini-2.5-pro:generateContent`. The JSON body decodes to `contents[0].parts[0].text == prompt`, `generationConfig.temperature == 0.4` and `maxOutputTokens == 2048`. Assert this with a `URLProtocol` stub.

### 7.8 SireState
- TV-ST-1: `SetStatus("1.1.1", .checked)` stores `"Checked"`. `SetStatus("1.1.1", .none)` removes the key.
- TV-ST-2: `GetStatus` maps `"InProgress"` to InProgress, `"inprogress"` to **None** (case-sensitive), `"2"` to Checked, and `"bogus"` to None.
- TV-ST-3: `ToggleBookmark` twice restores the original list. On `["a","b","a"]`, toggling `"a"` leaves `["b","a"]`, which is still bookmarked.
- TV-ST-4: a JSON round-trip of the §4.2 sample is lossless, keeps the key names, and accepts `CreatedAt` values `"2026-09-30T10:00:00+02:00"`, `"2026-09-30T08:00:00Z"`, `"2026-09-30T10:00:00.1234567+02:00"` and `"2026-09-30T10:00:00"`.
- TV-ST-5: decoding `{}` for `Sire`, or an object without `QuestionBodies`, gives empty collections.

### 7.9 Filters (synthetic bank of 3 questions, as in §7.10)
- With the vessel filter set to only `Chemical`, 1.1.1 (no vessel types) and 2.1.2 (Chemical) are visible, and 2.1.10 (Oil, LNG) is hidden.
- The status filter `Has Tasks` shows 2.1.2 and 2.1.10. `No Status` shows 2.1.2. `Bookmarked` shows 2.1.2.
- The search `ALPHA` finds 2.1.2 (full text, case-insensitive). The search `1.1` finds 1.1.1 and 2.1.10, because `"2.1.10"` contains the substring `"1.1"`. It does not find 2.1.2.
- The sort `Short Question Text` gives 1.1.1 (empty), then 2.1.2 (Alpha), then 2.1.10 (Beta).

### 7.10 Export golden outputs (LF-normalized, `now = 2026-09-29 14:05`)
**Synthetic bank:**
| Question | Type | Chapter | Section | Full text | Short text | Vessel types | ROVIQ | Other |
|---|---|---|---|---|---|---|---|---|
| `1.1.1` | data_field | 1 `Particulars` | 1.1 | `Name of the vessel` | (none) | (none) | (none) | |
| `2.1.2` | inspection | 2 `Certs` | 2.1 | `Is alpha ok?` | `Alpha check` | `[Chemical]` | `Main Deck` | objective `Obj A` |
| `2.1.10` | inspection | 2 `Certs` | 2.1 | `Is beta ok?` | `Beta check` | `[Oil, LNG]` | `Bridge, Documentation` | objective `Obj B`, evidence `Ev B`, negative grounds `Neg B` |

The bank order is 1.1.1, 2.1.2, 2.1.10.

**State:**
- Statuses `{2.1.10: Checked, 1.1.1: InProgress}`, bookmarks `[2.1.2]`, forExport `[2.1.10]`.
- Tasks, in insertion order:
  - T1 (2.1.10, `Check log`, done, CreatedAt 10:00)
  - T2 (2.1.2, `Sight cert`, open, 09:00)
  - T3 (2.1.10, `Review plan`, open, 09:30)
- Identified tasks, in bank order: `{2.1.2: [Verify Y, Verify Z], 2.1.10: [Verify X]}`.
- `filtered = [2.1.10, 1.1.1]`.

`Print Checklist`:
```
============================================================
  SIRE 2.0 Knowledge Bank Export — Print Checklist
  Generated: 2026-09-29 14:05
============================================================

  INSPECTION CHECKLIST
  Total questions: 3

[~] Q 1.1.1 — 
[ ] Q 2.1.2 — Alpha check
      [ ] Sight cert
[x] Q 2.1.10 — Beta check
      [x] Check log
      [ ] Review plan

============================================================
  Generated by AA — SIRE 2.0 Knowledge Bank
============================================================
```
`All Tasks` body. Tasks are ordered by CreatedAt, and the blank line before the frame's blank line is intentional:
```
Q 2.1.2 — Alpha check
  [ ] Sight cert

Q 2.1.10 — Beta check
  [ ] Review plan
  [x] Check log

```
`Full Session Report` body:
```
-- PROGRESS SUMMARY --
  Checked:        1
  In Progress:    1
  Not Applicable: 0
  Not Started:    1
  Bookmarked:     1
  For Export:     1
  Total Tasks:    3 (1 completed)

--- Checked (1) ---
  Q 2.1.10 — Beta check

--- InProgress (1) ---
  Q 1.1.1 — 

--- NotApplicable (0) ---

--- Not Started (1) ---
  Q 2.1.2 — Alpha check

-- ALL TASKS --

Q 2.1.2 — Alpha check
  [ ] Sight cert

Q 2.1.10 — Beta check
  [ ] Review plan
  [x] Check log

```
`Current Filter Results` body. Tasks are in insertion order, and the empty short-text line is two spaces:
```
  Current Filter Results: 2 questions

Q 2.1.10 [Inspection]
  Beta check
  Full: Is beta ok?
  Vessel: Oil, LNG | Chapter: Ch 2: Certs
  ROVIQ: Bridge, Documentation
  Status: Checked
  [x] Check log
  [ ] Review plan

Q 1.1.1 [Data Field]
  
  Full: Name of the vessel
  Vessel: All | Chapter: Ch 1: Particulars
  Status: In Progress

```
`By Chapter` body:
```
--- Ch 1: Particulars (1 questions) ---
  Q 1.1.1 [InProgress] — 

--- Ch 2: Certs (2 questions) ---
  Q 2.1.2 — Alpha check
  Q 2.1.10 [Checked] — Beta check

```
`By ROVIQ Location` body: `--- Bridge (1 questions) ---` / `  Q 2.1.10 — Beta check` / blank, then `--- Documentation (1 questions) ---` / `  Q 2.1.10 — Beta check` / blank, then `--- Main Deck (1 questions) ---` / `  Q 2.1.2 — Alpha check` / blank.

`By Vessel Type` body: `Chemical` (2.1.2), `LNG` (2.1.10), `Oil` (2.1.10), in the same layout as ROVIQ.

`Identified Tasks` body:
```
  Identified Tasks: 3 tasks across 2 questions
  (Pre-identified from question guidance text — no AI required)

-- Ch 2: Certs --

  Q 2.1.2 — Alpha check
    [ ] Verify Y
    [ ] Verify Z

  Q 2.1.10 — Beta check
    [ ] Verify X

```
`Inspection Summary` body:
```
  Inspection Summary: 2 questions

--- Q 1.1.1 [InProgress] ---
  
  Name of the vessel
  Vessel: All | Chapter: Ch 1: Particulars

--- Q 2.1.10 [Checked] ---
  Beta check
  Is beta ok?
  Vessel: Oil, LNG | Chapter: Ch 2: Certs
  Objective: Obj B
  Evidence: Ev B
  Neg. Obs. Grounds: Neg B
  Tasks:
    [x] Check log
    [ ] Review plan

```
`Pending Tasks` body: `  Pending Tasks: 2`, a blank line, then the groups for 2.1.2 (`[ ] Sight cert`) and 2.1.10 (`[ ] Review plan`).

`Questions with Tasks` body: `  Questions with Tasks: 2`, a blank line, 2.1.2 (`[ ] Sight cert`), then 2.1.10 (`[x] Check log`, `[ ] Review plan`, in insertion order).

With an empty state: `All Tasks` gives `  No tasks found.`, `Completed Tasks` gives `  No completed tasks found.`, `Inspection Summary` lists **all** questions with `[None]`, and `Identified Tasks` with an empty dictionary gives `  No identified tasks available.`

The export file name for mode `Print Checklist` at 2026-09-30 14:32 local is `SIRE_Print_Checklist_20260930_1432.txt`.

### 7.11 Quick-add (SireToAa)
Synthetic question: `2.1.10`, short `Beta check`, with identified tasks `["Verify X", "A very long task text … (100 chars)"]`.
- **Kind = Equipment, AddQuestion:**
  - One Equipment named `SIRE Q2.1.10 — Beta check`, tags `["SIRE"]`, and a body XAML whose root is a `Section` with the root Foreground slate.
  - Two Components:
    - `Name="Verify X"`, `Notes="Verify X"`
    - `Name` = the first 80 UTF-16 units, `TrimEnd`, plus `…`; `Notes` = the full text
  - Two new top-level Tasks, each with tags `["SIRE"]` and `Description="SIRE Q2.1.10 — Beta check"`. Each is in `equipment.RelatedIds` and `equipment.TaskIds`, and has `equipment.Id` in its own `RelatedIds`.
  - One log entry: `Added` / `Equipment/Area` / `SIRE Q2.1.10 — Beta check` / `from SIRE Q2.1.10`.
  - Summary: `Added “SIRE Q2.1.10 — Beta check” as Equipment with 2 linked task(s).`
- **Kind = Procedure:** 2 `ChecklistStep`s titled with the task texts, plus 2 related top-level Tasks. The parent has no `TaskIds`.
- **Kind = Task:** the parent Task has 2 Subtasks, plus 2 related top-level Tasks, for 3 new entries in `Data.Tasks` in total.
- **A question with no identified tasks:** Summary `Added “SIRE Q1.1.1 — ” as Task.`
- **AddSection("2.1") with Kind Procedure** over the §7.10 synthetic bank, using the §7.10 identified-task dictionary:
  - Parent `SIRE Section 2.1` with an overview body (title plus `2 SIRE 2.0 question(s). Imported from the SIRE 2.0 Knowledge Bank.` plus a disc list `Q 2.1.2 — Alpha check`, `Q 2.1.10 — Beta check`).
  - Steps `Q2.1.2 — Alpha check` and `Q2.1.10 — Beta check`, each with that question's body XAML.
  - Top-level Tasks for all identified tasks of both questions, related to the parent.
  - Log detail `from SIRE (2 questions)`.
  - Summary `Added “SIRE Section 2.1” as Procedure with 2 question(s) and 3 linked task(s).`
- **AddChapter("2"):** the parent name is `SIRE Ch2 — Certs`.
- **Truncate:** `Truncate("abc", 80) == "abc"`. `Truncate(String(repeating:"a", 79) + "  bbbb", 80) == String(repeating:"a",79) + "…"` (the cut at 80 gives 79 a's plus a space, the space is removed, and `…` is added).

### 7.12 UI behaviour checks (XCUITest / manual)
1. Opening the SIRE destination the first time shows the loading state, then the list shows `Questions (410)`, and the stats footer reads `410 questions · 6106 auto-identified tasks` / `Session — ✓ 0  ⧗ 0  N/A 0  ★ 0  tasks 0`.
2. Select 2.1.1, set `✓ Checked`. The row shows `Checked` and the footer shows `✓ 1`. Set the filter to `No Status`: 2.1.1 disappears and the detail pane is disabled or empty.
3. Bookmark: the star appears on the row. With the filter on `Bookmarked`, unbookmarking the current question keeps it visible until a filter change (Windows parity, Q-7).
4. In the body editor:
   - Select a word and type `X`: `X` is inserted **before** the word, and the word remains.
   - ⌫ with a selection does nothing. ⌘X does nothing. Dragging text does nothing.
   - ⌘Z removes the inserted `X`.
   - Switch question and come back: the edit persists.
   - ⌘S, then quit and relaunch: the edit persists.
   - `↺ Reset` restores the original immediately.
5. Writing Tools, autocorrect and Find-Replace cannot modify the original text.
6. `📋 Identified…` on 2.1.1 opens the picker with all candidates ticked. Untick one, filter, clear the filter: the ticks are preserved (fix Q-11). Add: the tasks appear, and adding again adds nothing (dedup).
7. `✦ AI Suggest…` with no key shows the exact no-key alert. With a stubbed network, switching question mid-request adds the results to the **original** question (fix Q-4).
8. `Whole chapter…` on chapter 7 creates `SIRE Ch7 — Maritime Security` with 6 children. "Go to Item" navigates to it.
9. Tools ▸ SIRE 2.0 Export… with `Print Checklist`: `Copy` puts the text on the pasteboard and shows `SIRE export copied to clipboard.` `Save…` writes a UTF-8 file with no BOM under the default name.
10. Toggle dark mode: the chrome goes dark, and the body stays light paper with black text.
11. Tools ▸ Set Gemini API Key… → Clear, then relaunch: the key is still cleared (fix Q-5).
12. Round-trip: a `data.json` with a `Sire` block written by Windows (including `QuestionBodies`) opens on the Mac with the edits visible and the statuses and tasks intact. Saving on the Mac and reopening on Windows shows the same.

---

## 8. Windows quirks register (port decisions)
| ID | Quirk | Decision |
|---|---|---|
| Q-3 | `Selected Questions` export is always empty (`IsSelected` never set) | **Fix (additive):** enable multi-selection (⌘-click, ⇧-click) in the Mac question list, and export the selected rows in QC order. Detail shows the primary (last-clicked) question. With a single selection, export that one question. |
| Q-4 | AI result is applied to whichever question is selected when the response arrives | **Fix:** bind to the originating question |
| Q-5 | Clearing the Gemini key reappears after restart | **Fix:** clearing deletes the Keychain item |
| Q-7 | Bookmark, export-tag and task changes don't re-apply the Bookmarked, For Export and Has Tasks filters | **Replicate** (only status changes re-filter). Revisit if the user asks. |
| Q-8 | SIRE body is not flushed by Ctrl+S or the 5-min autosave | **Fix:** flush on all save paths plus a 750 ms idle debounce |
| Q-9 | An unparseable saved body is shown as the original and overwritten by the next edit | **Fix (data safety):** read-only banner (§6.4 point 10) |
| Q-10 | "Still loading" export message is unreachable; export blocks on the bank lock. Also the swap does not re-filter. | **Fix:** await the load with progress; re-filter on swap |
| Q-11 | Picker search clears all ticks | **Fix:** preserve ticks |
| Q-12 | Export uses CRLF from `AppendLine` plus LF inside bank text | **Mac writes LF**. Tests normalize CRLF to LF. |
| Q-14 | `HH:mm` uses the culture time separator | **Mac always uses `:`**, with `yyyy-MM-dd` from the Gregorian calendar and local time zone (`en_US_POSIX`) |
| Q-15 | Paragraph-level formatting commands can restyle original paragraphs on Windows | **Narrowed on Mac** (blocked by the gate) |
| Q-17 | TextBox `Tag` hints (`Search all questions…`, `Add a task and press Enter…`) are never displayed | **Mac shows them** as placeholders |
| — | Faithful oddities: data-field rows show only the number, `"Verify that sMS …"`, substring tag false positives, fragmented bullet rendering, trailing space in `SIRE Q1.1.1 — ` | **Replicate** |

---

## 9. Open questions
1. **Q-1, golden XAML.** Capture from the Windows build and commit these as Mac fixtures: `BuildQuestionXaml` for 1.1.1, 2.1.1 and 11.1.2, `BuildOverviewXaml(Section 7.1)`, and one `QuestionBodies` entry after typing a newline plus a bold word. Until then, §4.4 is the best-knowledge shape, and it is not byte-verified.
2. **Q-2, culture ordering.** Does .NET/ICU on the user's Windows machine order `"Interview -\nRating"` before or after `"Interview - Deck Officer"`? Foundation (en_US) puts it first. This affects only the `By ROVIQ Location` export order.
3. **Q-3.** Is the recommended multi-select semantics for `Selected Questions` acceptable, or should the mode be hidden?
4. **Q-6, Gemini model and limits.** `gemini-2.5-pro` is a "thinking" model, and its thinking tokens count against `maxOutputTokens=2048`. Long questions may therefore return truncated or empty answers ("Gemini returned an empty response."). Keep strict parity, or raise the limit or make the model configurable on both platforms? Also confirm that the header-based key (`x-goog-api-key`) is acceptable instead of `?key=`.
5. **Q-8/Q-9.** Should the Windows app get the same fixes (flush on save and autosave, read-only on parse failure, AI race, key clearing, picker ticks) so both platforms behave identically?
6. **Keychain vs file.** Keychain storage for the Gemini key is recommended. Confirm that "same settings semantics" allows the Mac to keep this secret out of its settings file. The key never travels between machines on Windows either.
7. **Q-13.** Should the `.sire` import/export mentioned in a code comment ever be implemented? It is currently not in scope.
8. Should filter state and splitter widths be remembered per Mac, in UserDefaults and never in `data.json`? Windows does not remember them.
9. **Q-16, verification of counts.** Confirm `6106` identified tasks and `332` questions using the Windows headless harness (`SireBank.TotalIdentifiedTasks`, `IdentifiedTasks.Count`). These numbers come from a faithful Python re-implementation, not from running the C#.
10. Should the Mac show the EXP tag in list rows? It is additive, and Windows does not.

---

## Addendum: Embed the TagExtractor keyword lists verbatim

> Gap-fill 8. §3.3 gave only the list sizes (87/52/47/27/24) and said to copy the strings from the C# file. This addendum carries the five lists **verbatim**, so a Swift implementer never needs the Windows sources, and adds real-bank test vectors for `ExtractTags` and `DominantCategory`. Nothing earlier in this spec is removed. Where this addendum is more precise than §3.3, §6.12 or §7.4, the addendum wins.

**Sources re-read for this addendum**
- `AA/Sire/TagExtractor.cs`, all 148 lines. The arrays are l.12-99.
- `AA/Sire/SireModels.cs` l.10-24 (`QuestionBank`, `BankMetadata`) and l.60-63 (`EvidenceTags`, `RoviqLocations`).
- `AA/Sire/SireBank.cs` l.38-74, where the tags are computed at load and `Metadata` is assigned.
- `AA/Sire/SireFlow.cs` l.62-63, the Smart tags line.
- `AA/Views/SirePage.xaml.cs` l.166-170 (Evidence category filter) and l.445-492 (`PickKind` and the three quick-add handlers).
- `AA/AA.csproj`, checked for globalization switches. It sets neither `InvariantGlobalization` nor `UseNls`.
- `AA/Sire/Data/sire2_question_bank.json`, used for the vectors.

**How the vectors were produced.** There is no .NET runtime on the Mac. Every real-bank vector below therefore comes from an independent Swift 6.4 re-implementation of `ExtractTags` and `DominantCategory` that follows A.3: an ASCII-folded ordinal substring search over UTF-16, and a sort with `compare(_:options:[],range:nil,locale:Locale(identifier:"en_US"))`. It was run over the bundled bank. It reproduces the already-published aggregate TV-TAG-BANK exactly (Procedure 187, Equipment 144, Task 79, and 54 questions with no tags), which cross-checks it. The one vector marked ⚠ should be confirmed with the Windows headless harness (A.7).

Per §7, **no bank text is copied** into this spec or into tests. A vector names a question number and asserts an output that consists only of AA's own keyword strings. Where a false positive is explained, only the single host word is quoted.

### A.1 Feature checklist additions

### SIRE-049 — The five evidence keyword lists are embedded verbatim
- The Mac ships the **237** keyword strings of A.2 as five ordered arrays. Parsing `TagExtractor.cs` confirms the counts in §3.3:

  | List | Count |
  |---|---|
  | Equipment | 87 |
  | Document | 52 |
  | Procedure | 47 |
  | Record | 27 |
  | Personnel | 24 |

- **Verbatim** means all of the following:
  - The same order.
  - The same casing. Acronyms such as `SCBA`, `DOC`, `PMS` and `OOW` stay uppercase, and `Master`, `Chief Officer`, `Document of Compliance`, `Procedures and Arrangements` and `IG pressure` keep their capitals.
  - The same spelling variants and near-duplicates: `oxygen analyser` **and** `oxygen analyzer`, `lifejacket` **and** `life jacket`, `life raft` **and** `liferaft`, `log book` **and** `logbook`, `P/V valve` **and** `PV valve`, and every other group in A.2.7.
  - No trimming, de-duplication, synonym merging or spelling normalization. British `familiarisation` stays as it is.
  - No localization.
- **Why every string matters.** Each matched keyword becomes a visible tag `"{Category}: {keyword}"` in the keyword's list casing. That tag is used in four places:
  - It is shown in the Smart tags line (SIRE-021).
  - The Smart tags line is also **persisted** inside quick-add container bodies and in `QuestionBodies` (A.4.2).
  - It decides the Evidence category filter (SIRE-007).
  - It feeds `DominantCategory`, which pre-selects the kind in the quick-add picker (SIRE-034).

  Dropping an apparent duplicate such as `oxygen analyzer` changes the tag set of every question that uses that spelling. Changing `SCBA` to `scba` changes both the displayed text and the persisted text.
- The strings are data, not UI copy, so they never go through the localization system. See A.5.

### SIRE-050 — Tags are pure case-insensitive substrings, false positives included
- A keyword matches wherever its characters occur contiguously in the search text, ignoring ASCII case. There are **no word boundaries**, **no whitespace normalization**, **no plural handling**, and **no diacritic or compatibility folding**.
- The resulting false positives are Windows behaviour and must be reproduced. The census in TV-TAGX-FP shows their scale:
  - `Document: DOC` is present on 61 questions, 60 of them only through words such as "documented" and "documentation".
  - `Personnel: SSO` is present on 56 questions, 54 of them only through "associated", "compressor", "assessor" and similar words.
- What the user sees as a result:
  - The Evidence category `Document` lists questions that merely say "documented".
  - Questions whose text says "raises" or "appraisal" carry `Equipment: AIS`.
  - Four questions get **Equipment / Area** pre-selected on quick-add only because of a false positive (TV-DOM-E, A.3.3).

### SIRE-051 — Smart tags are in culture order, not ordinal order
- The tag list is sorted with .NET's culture-sensitive default comparer (§3.3, §6.12). The order is visible in the Smart tags line and is persisted in XAML bodies.
- On the shipped bank, **66 of the 410** questions would show a different order under a plain ordinal (code-point) sort. For example, `Document: CSSR`, `Document: DOC` and `Document: HVPQ` would move ahead of `Document: certificate` (TV-TAGX-1).
- Swift's `Array<String>.sorted()` and String `<` compare Unicode scalars, which for these ASCII strings is the ordinal order, so they are **wrong** here. Always use the comparator in A.3.2.

### A.2 The keyword arrays (normative content)

The code blocks below are Swift. The string contents and their order are **normative**; the surrounding declaration is illustrative (§6.1 puts it in `Sire/Engine`).
- Each Swift line corresponds to one C# line, with the same grouping, and ends in a `// C# l.N` comment that names its source line. That makes a line-by-line comparison with `TagExtractor.cs` l.12-99 trivial.
- No string contains a quote, a backslash or `\(`, so every C# literal is also a valid Swift literal, character for character.
- All 237 strings are pure ASCII. The only non-letter characters are the space, `/` (`P/V valve`), `&` (`P&A manual`), `-` (`quick-closing valve`, `pre-inspection`, `non-conformity`, `pre-job briefing`) and the digit `2` in `CO2 system`.

#### A.2.1 Equipment — `EquipmentKeywords`, C# l.12-35, 87 strings
```swift
// TagExtractor.cs l.12-35: EquipmentKeywords
static let equipment: [String] = [
        "fire extinguisher", "breathing apparatus", "SCBA", "lifejacket", "life jacket",  // C# l.14
        "lifeboat", "life raft", "liferaft", "rescue boat", "EPIRB", "SART",  // C# l.15
        "inert gas", "IG system", "IGS", "oxygen analyser", "oxygen analyzer",  // C# l.16
        "cargo pump", "ballast pump", "fire pump", "emergency pump",  // C# l.17
        "ventilation", "gas detector", "fixed gas detection", "portable gas",  // C# l.18
        "mooring winch", "windlass", "anchor", "crane", "derrick",  // C# l.19
        "radar", "ECDIS", "AIS", "VDR", "GMDSS", "gyro compass", "magnetic compass",  // C# l.20
        "echo sounder", "speed log", "autopilot", "steering gear",  // C# l.21
        "emergency generator", "UPS", "battery", "main engine",  // C# l.22
        "boiler", "incinerator", "oily water separator", "OWS",  // C# l.23
        "oil discharge monitor", "ODM", "sewage treatment",  // C# l.24
        "nitrogen generator", "cargo heating", "tank cleaning",  // C# l.25
        "P/V valve", "PV valve", "pressure vacuum", "flame screen",  // C# l.26
        "deck seal", "cargo manifold", "reducer", "loading arm",  // C# l.27
        "foam system", "CO2 system", "water spray", "water mist", "dry powder",  // C# l.28
        "fire damper", "fire door", "fire flap", "quick-closing valve",  // C# l.29
        "bilge alarm", "high level alarm", "overflow",  // C# l.30
        "gangway", "accommodation ladder", "pilot ladder",  // C# l.31
        "mast riser", "vent riser", "cargo tank", "slop tank", "ballast tank",  // C# l.32
        "bunker tank", "fuel tank", "engine room",  // C# l.33
        "emergency towing", "towing arrangement"  // C# l.34
]
```

#### A.2.2 Document — `DocumentKeywords`, C# l.37-55, 52 strings
```swift
// TagExtractor.cs l.37-55: DocumentKeywords
static let document: [String] = [
        "certificate", "IOPP", "ISPP", "COF", "SMC", "DOC", "ISPS",  // C# l.39
        "class survey", "CSSR", "survey status", "classification",  // C# l.40
        "safety management certificate", "cargo ship safety",  // C# l.41
        "HVPQ", "PIQ", "pre-inspection", "Document of Compliance",  // C# l.42
        "permit to work", "hot work permit", "enclosed space entry permit",  // C# l.43
        "work permit", "risk assessment", "JSA", "job safety analysis",  // C# l.44
        "passage plan", "voyage plan", "cargo plan", "stowage plan",  // C# l.45
        "stability", "loading manual", "trim and stability",  // C# l.46
        "P&A manual", "Procedures and Arrangements",  // C# l.47
        "ship security plan", "ISPS plan", "SSP",  // C# l.48
        "oil record book", "ORB", "cargo record book",  // C# l.49
        "garbage record", "ballast water record",  // C# l.50
        "ISM audit", "internal audit", "external audit",  // C# l.51
        "MSDS", "SDS", "safety data sheet", "material safety",  // C# l.52
        "IHM", "inventory of hazardous materials",  // C# l.53
        "polar water operational manual", "PWOM"  // C# l.54
]
```

#### A.2.3 Procedure — `ProcedureKeywords`, C# l.57-74, 47 strings
```swift
// TagExtractor.cs l.57-74: ProcedureKeywords
static let procedure: [String] = [
        "procedure", "checklist", "standing orders", "daily orders",  // C# l.59
        "emergency drill", "fire drill", "abandon ship", "man overboard",  // C# l.60
        "muster list", "contingency plan", "emergency plan",  // C# l.61
        "SOPEP", "SMPEP", "VRP", "shipboard oil pollution",  // C# l.62
        "cargo operation", "ballast operation", "tank cleaning procedure",  // C# l.63
        "inerting", "gas freeing", "purging", "crude oil washing", "COW",  // C# l.64
        "bunkering procedure", "STS operation", "ship to ship",  // C# l.65
        "mooring plan", "anchoring procedure",  // C# l.66
        "enclosed space entry", "hot work", "working aloft", "working overside",  // C# l.67
        "lockout tagout", "LOTO", "isolation procedure",  // C# l.68
        "drug and alcohol", "fatigue management",  // C# l.69
        "navigation procedure", "bridge procedure",  // C# l.70
        "maintenance system", "planned maintenance", "PMS",  // C# l.71
        "defect reporting", "non-conformity", "NCR",  // C# l.72
        "management of change", "MOC"  // C# l.73
]
```

#### A.2.4 Record — `RecordKeywords`, C# l.76-87, 27 strings
```swift
// TagExtractor.cs l.76-87: RecordKeywords
static let record: [String] = [
        "log book", "logbook", "deck log", "engine log", "bridge log",  // C# l.78
        "training record", "drill record", "rest hour", "work rest",  // C# l.79
        "maintenance record", "test record", "inspection record",  // C# l.80
        "calibration record", "gas reading", "atmosphere test",  // C# l.81
        "IG pressure", "cargo temperature", "ullage",  // C# l.82
        "familiarisation record", "induction record",  // C# l.83
        "near miss", "incident report", "accident report",  // C# l.84
        "superintendent report", "vessel inspection report",  // C# l.85
        "navigation assessment", "navigational audit"  // C# l.86
]
```

#### A.2.5 Personnel — `PersonnelKeywords`, C# l.89-99, 24 strings
```swift
// TagExtractor.cs l.89-99: PersonnelKeywords
static let personnel: [String] = [
        "Master", "Chief Officer", "Chief Mate", "Chief Engineer",  // C# l.91
        "officer of the watch", "OOW", "duty officer",  // C# l.92
        "deck officer", "engineer officer", "rating",  // C# l.93
        "security officer", "SSO", "CSO",  // C# l.94
        "designated person", "DPA",  // C# l.95
        "crew qualification", "STCW", "endorsement",  // C# l.96
        "familiarisation", "induction", "competency",  // C# l.97
        "safety meeting", "toolbox talk", "pre-job briefing"  // C# l.98
]
```

#### A.2.6 Scan order and fingerprints
- **Scan order** (`TagExtractor.cs:107-111`): `("Equipment", equipment)`, `("Document", document)`, `("Procedure", procedure)`, `("Record", record)`, `("Personnel", personnel)`. The category names are these exact English words.
- The scan order is neither alphabetical nor the order of the `DominantCategory` dictionary (Equipment, Procedure, Document, Record, Personnel). **Neither order affects any result**: the tag set is sorted afterwards, and the counts do not depend on order. Keep the scan order anyway, for diffability.
- **Fingerprints.** Each value is the SHA-256 of the UTF-8 bytes of `list.joined(separator: "\n")`, with no trailing newline. A unit test can assert these without access to the Windows sources:

| List | Count | First | Last | UTF-8 bytes | SHA-256 |
|---|---|---|---|---|---|
| Equipment | 87 | `fire extinguisher` | `towing arrangement` | 1012 | `71fc38c576a7d8e4c816f6ab3516aef9c9bf922a37818b58268d1a4ad2a3950d` |
| Document | 52 | `certificate` | `PWOM` | 686 | `7d7358cc49ce401598bb0676ae2c32d89c4f7fd9b8f67022c944f6c8654a8152` |
| Procedure | 47 | `procedure` | `MOC` | 654 | `3b2c452614b74da4fedf63870f0ca48e8f40e34789c72c10b7f5c47806a2b673` |
| Record | 27 | `log book` | `navigational audit` | 399 | `93e255324590bd54ee18b711d25176a3450e0b371ebaf9591dd43f94ca267bd8` |
| Personnel | 24 | `Master` | `pre-job briefing` | 286 | `2c8ab7131f23c3a8c887a66b65e81daa6caa3f7d1a4c5f959f8ee301367041a6` |
| **All 237 tags** | 237 | `Equipment: fire extinguisher` | `Personnel: pre-job briefing` | — | `e37775a1e34e0588e69bede4b3260628a7437fe439324cd96bf60ac2be7ef5e1` |

The "All" row hashes the 237 strings `"{Category}: {keyword}"` in scan order, joined by `"\n"`.

#### A.2.7 Near-duplicates and overlaps (all intentional; keep them)
Indices are 0-based positions in the Swift arrays above.

| List | Variant group (index) |
|---|---|
| Equipment | `lifejacket` [3] / `life jacket` [4] · `life raft` [6] / `liferaft` [7] · `IG system` [12] / `IGS` [13] · `oxygen analyser` [14] / `oxygen analyzer` [15] · `oily water separator` [46] / `OWS` [47] · `oil discharge monitor` [48] / `ODM` [49] · `P/V valve` [54] / `PV valve` [55] / `pressure vacuum` [56] |
| Document | `DOC` [5] / `Document of Compliance` [16] · `ISPS` [6] / `ship security plan` [33] / `ISPS plan` [34] / `SSP` [35] · `oil record book` [36] / `ORB` [37] · `MSDS` [44] / `SDS` [45] / `safety data sheet` [46] / `material safety` [47] · `hot work permit` [18] / `work permit` [20] · `certificate` [0] / `safety management certificate` [11] · `stability` [28] / `trim and stability` [30] · `P&A manual` [31] / `Procedures and Arrangements` [32] |
| Procedure | `crude oil washing` [21] / `COW` [22] · `STS operation` [24] / `ship to ship` [25] · `lockout tagout` [32] / `LOTO` [33] · `maintenance system` [39] / `planned maintenance` [40] / `PMS` [41] · `non-conformity` [43] / `NCR` [44] · `management of change` [45] / `MOC` [46] |
| Record | `log book` [0] / `logbook` [1] · `rest hour` [7] / `work rest` [8] |
| Personnel | `Chief Officer` [1] / `Chief Mate` [2] · `officer of the watch` [4] / `OOW` [5] · `designated person` [13] / `DPA` [14] |

- **No two strings are equal when case is ignored**, within a list or across lists. This was verified, and it means the `OrdinalIgnoreCase` `HashSet` in `ExtractTags` never drops a tag. A Swift ordered set keyed on the exact tag string is therefore equivalent.
- **Containment.** In 19 pairs, one keyword is a case-insensitive substring of another. Whenever the longer one matches, the shorter one matches too, so these tags always arrive together:
  - `Equipment: anchor` ⊂ `Procedure: anchoring procedure`
  - `Equipment: tank cleaning` ⊂ `Procedure: tank cleaning procedure`
  - `Document: certificate` ⊂ `Document: safety management certificate`
  - `Document: DOC` ⊂ `Document: Document of Compliance`
  - `Document: ISPS` ⊂ `Document: ISPS plan`
  - `Document: work permit` ⊂ `Document: hot work permit`
  - `Document: stability` ⊂ `Document: trim and stability`
  - `Document: SDS` ⊂ `Document: MSDS`
  - `Procedure: procedure` ⊂ `Document: Procedures and Arrangements`, and ⊂ `Procedure: tank cleaning procedure`, `bunkering procedure`, `anchoring procedure`, `isolation procedure`, `navigation procedure` and `bridge procedure` (7 pairs)
  - `Procedure: enclosed space entry` ⊂ `Document: enclosed space entry permit`
  - `Procedure: hot work` ⊂ `Document: hot work permit`
  - `Personnel: familiarisation` ⊂ `Record: familiarisation record`
  - `Personnel: induction` ⊂ `Record: induction record`

  This affects `DominantCategory`. For example, the text "anchoring procedure" alone yields Equipment 1 and Procedure 2, so the result is **Procedure** (TV-TAGX-SYN-7).

#### A.2.8 Coverage on the shipped bank
- **182** of the 237 possible tags occur at least once. The other **55** never occur. They are kept anyway, under the verbatim rule, and would matter for any future bank:
  - Equipment (17): `life jacket`, `life raft`, `oxygen analyzer`, `derrick`, `magnetic compass`, `autopilot`, `oily water separator`, `sewage treatment`, `PV valve`, `pressure vacuum`, `loading arm`, `water spray`, `fire flap`, `quick-closing valve`, `high level alarm`, `overflow`, `vent riser`
  - Document (15): `ISPP`, `SMC`, `ISPS`, `permit to work`, `JSA`, `job safety analysis`, `loading manual`, `trim and stability`, `ISPS plan`, `external audit`, `MSDS`, `material safety`, `IHM`, `inventory of hazardous materials`, `PWOM`
  - Procedure (9): `VRP`, `shipboard oil pollution`, `working aloft`, `working overside`, `lockout tagout`, `LOTO`, `isolation procedure`, `fatigue management`, `bridge procedure`
  - Record (10): `work rest`, `gas reading`, `atmosphere test`, `IG pressure`, `induction record`, `near miss`, `incident report`, `accident report`, `superintendent report`, `navigational audit`
  - Personnel (4): `officer of the watch`, `duty officer`, `designated person`, `pre-job briefing`
- An assertion that exactly these 55 never occur is a cheap tripwire against accidental whitespace normalization. If line breaks were collapsed to spaces, these tags would start to appear:
  - `Procedure: shipboard oil pollution` (5.1.3)
  - `Procedure: bridge procedure` (5.10.1)
  - `Equipment: water spray` (5.2.9 and 10.6.1)

### A.3 Logic (refines §3.3)

#### A.3.1 `ExtractTags`: the exact matching contract (`TagExtractor.cs:101-120`)
1. Build `searchText = [ExpectedEvidence, SuggestedInspectorActions, ShortQuestionText, Objective].joined(separator: " ")`.
   - A missing or null field counts as `""`. A data field has all four fields absent, so its search text is `"   "` (three spaces) and it gets no tags. That is why all 25 data fields have zero tags.
   - The text is used **raw**: no trimming, no newline replacement, no whitespace collapsing, and no Unicode normalization.
2. For each category in scan order, and each keyword in list order: if `searchText` contains the keyword under `OrdinalIgnoreCase`, add `"\(category): \(keyword)"`. There is exactly one colon and one space between the two parts.
3. Deduplicate, which is a no-op in practice (A.2.7), then sort with the culture comparer (A.3.2).

**`OrdinalIgnoreCase` for these ASCII keywords.** Compare UTF-16 code units. A text unit equals a keyword unit if the two are identical, or if both are ASCII letters that differ only in ASCII case (0x20). Nothing else folds. An illustrative signature:
```swift
/// .NET `haystack.Contains(needle, StringComparison.OrdinalIgnoreCase)` for an ASCII needle.
/// Both arguments are pre-folded with `u >= 0x61 && u <= 0x7A ? u &- 0x20 : u`.
nonisolated func containsOrdinalIgnoreCaseASCII(_ foldedHaystack: [UInt16], _ foldedNeedle: [UInt16]) -> Bool
```
Fold the 237 keywords once (a `static let`), and fold each question's search text once, at load.

**Do not use Foundation's case-insensitive search as the contract.** That covers `range(of:options: .caseInsensitive)`, `.caseInsensitive` combined with `.literal`, and `localizedCaseInsensitiveContains`. Probed on macOS 27 with Swift 6.4, all three report a match in these cases, where .NET `OrdinalIgnoreCase` (simple per-unit case mapping) matches none:
- `"\u{FB01}re pump"` (the ﬁ ligature) against `fire pump`
- `"\u{212A}ey"` (the Kelvin sign) against `key`
- `"STRA\u{00DF}E"` against `strasse`

For the shipped bank the difference makes no practical difference. The only non-ASCII characters in the four search fields are `•` U+2022, `’` U+2019, `‘` U+2018, `“` U+201C, `”` U+201D, `–` U+2013, `…` U+2026, `°` U+00B0 and the Wingdings bullet U+F0A7. The ASCII fold is still the exact contract, and it is faster.

**Matches across the joining space.** A keyword can match across the boundary between two fields (TV-TAGX-SYN-3). This was checked on the shipped bank and never happens there: tagging each field separately and taking the union gives the same 1,568 tags as tagging the joined text. Keep the join anyway, so that behaviour stays identical for any other text.

#### A.3.2 Sort order (`TagExtractor.cs:112`)
- **Windows.** `OrderBy(t => t)` uses `Comparer<string>.Default`, which is `CultureInfo.CurrentCulture.CompareInfo.Compare(a, b, CompareOptions.None)`. The project does not opt out of ICU, so .NET 10 on Windows 10 1903+ and Windows 11 collates with ICU. With `CompareOptions.None`:
  - Letters compare case-insensitively at the primary level. Lowercase sorts before uppercase only on a complete tie.
  - Spaces and punctuation are **not ignorable**. They sort before letters and digits.

  English cultures (en-US, en-GB and so on) share the root collation for these ASCII strings.
- **Mac.** Use `a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US")) == .orderedAscending` in a stable sort (§6.12). No two of the 237 tags compare `.orderedSame` under this comparator (verified), so stability never matters for tags.
- Keyword-level consequences within one category, in en_US order:
  - `fire pump` < `SCBA`
  - `Chief Mate` < `competency` < `Master` < `rating`
  - `class survey` < `classification`, because the space sorts before the letter
  - `life jacket` < `life raft` < `lifeboat` < `lifejacket` < `liferaft`
  - `log book` < `logbook`
  - `P/V valve` < `pressure vacuum` < `PV valve`
- **On the shipped bank:**
  - 66 questions order their tags differently under culture and ordinal comparison.
  - Exactly **one** question, 2.1.1, depends on whether the space is significant (TV-TAGX-1 ⚠). If the Windows harness shows `classification` before `class survey` for 2.1.1, the Windows collator is ignoring spaces. The Mac comparator would then need adjusting, and the punctuation cases in TV-TAG-3 would need re-checking.

#### A.3.3 `DominantCategory` (`TagExtractor.cs:136-147`): why the contract is strict
- The rule is unchanged from §3.3:
  1. Count the tags per category.
  2. If `Equipment > 0 && Equipment >= Procedure`, return `Equipment`.
  3. Otherwise, if `Procedure > 0`, return `Procedure`.
  4. Otherwise, return `Task`.

  **A tie goes to Equipment.** For example, 9.3.1 has Equipment 3 and Procedure 3, so it returns Equipment. Document, Record and Personnel counts never decide the result. 12.1.1 has six tags, none of them Equipment or Procedure, and returns `Task`.
- The same result sets the default in all three quick-add paths. `This question…`, `Whole section…` and `Whole chapter…` all call `PickKind(TagExtractor.DominantCategory(_selected))` for the **selected** question (`SirePage.xaml.cs:463,476,488`). `PickKind` (l.445-458, mapping at l.453-454) maps `"Equipment"` to Equipment / Area, `"Procedure"` to Procedure, and anything else to Task.
- Measured on the shipped bank against the faithful implementation, these are the deviations an implementer might be tempted to make, and how many questions would then get a different pre-selected kind:

  | Deviation | Questions whose pre-selected kind changes |
  |---|---|
  | Match whole words only (`\b…\b`) | **108** of 410 |
  | Collapse whitespace and newlines to single spaces before matching | 3: 2.3.1 Procedure→Equipment, 5.2.9 Procedure→Equipment, 5.10.1 Equipment→Procedure |
  | Suppress only the inside-a-longer-word hits of `AIS`, `UPS`, `DOC`, `rating`, `COW`, `SSO`, `NCR`, `COF` and `OWS` | 4, all Equipment→Procedure: 3.5.1 (via `OWS`), and 7.1.1, 9.3.1 and 10.5.2 (via `AIS`) |
  | Sort ordinally instead of by culture | 0. Counts do not depend on order, but the Smart tags text changes for 66 questions (SIRE-051). |

#### A.3.4 Performance
- The work is 237 keywords × 410 questions, about 97,000 substring scans over texts of at most a few KB. In an optimised build that takes milliseconds.
- Run it inside the background bank-load task (§3.5, step 3) and cache the result with the bank. There is no need for Aho-Corasick or any other index.

### A.4 Data formats

#### A.4.1 Supplement to §4.1: `metadata` and `total_questions`
- `QuestionBank.metadata` maps to `BankMetadata` (`SireModels.cs:17-24`):
  - `title`, `version`, `date` and `source`: strings, default `""`
  - `total_questions`: Int32, default `0`
- The shipped values are:

  | Key | Value |
  |---|---|
  | `title` | `SIRE 2.0 Question Library` |
  | `version` | `1.0` |
  | `date` | `January 2022` |
  | `source` | `OCIMF - Oil Companies International Marine Forum` |
  | `total_questions` | **`410`**, equal to `questions.count` |

- `SireBank.Metadata` is assigned at load (`SireBank.cs:62`) but **never read**. The "410 questions" in the stats footer is always `questions.count`, never `total_questions`.
- The Mac decodes `metadata` for parity, and a test asserts `total_questions == 410 == questions.count`. The Mac must **not** use `total_questions` to validate or reject the bank, because Windows does not. A missing `metadata` object decodes to the defaults, and `parts` and `questions_by_chapter` are ignored.
- On Windows, a non-integer `total_questions` would make STJ throw and put the tab into the load-error state (SIRE-002). That cannot happen with the byte-pinned bundled file (TV-BANK-1), so the Mac may decode `metadata` leniently.

#### A.4.2 Where tag strings end up on disk
- `SireQuestion.EvidenceTags` is `[JsonIgnore]`, so tags are never stored as a field.
- The tag **text** is serialized inside XAML, however. `SireFlow.BuildQuestion` appends `Smart tags: {t1}   ·   {t2}…` as a 10 pt `#64748B` paragraph (§3.6 step 7, §4.4). The separator is three spaces, U+00B7, three spaces. That paragraph is written to:
  - (a) `Container.RichTextXaml` of every quick-added question parent, and of every child step, subtask or component of a section or chapter add
  - (b) `SireState.QuestionBodies[n]`, once the user edits the pane body

  Both travel in `data.json`, in bundles and in Flash Sync.
- **Compatibility rule.** For the same question, the Mac must produce the Smart tags paragraph text **character for character and in the same order** as Windows. Otherwise the same quick-add made on each platform yields bodies that differ in text, and bodies created on the two platforms visibly disagree when they appear side by side.
- Stored bodies are never re-tagged. A body created with a different keyword list keeps its original text.

### A.5 macOS adaptation notes
- **Where the arrays live.** Put them in `Sire/Engine/TagKeywords.swift` as `nonisolated enum TagKeywords { static let equipment: [String] = [ … ] … }`. `[String]` is `Sendable`, so these `static let`s are valid under Swift 6 strict concurrency. Keep the file ASCII-only and keep the C# line grouping.
- **Keep the arrays out of String Catalogs.** Use plain `String` literals, never `String(localized:)` or `LocalizedStringKey`. When displaying a tag, use `Text(verbatim:)` or `Text(tagString)` with a `String` variable, because `Text("literal")` is treated as a localization key.
- **Evidence category picker.** If its labels are ever localized, the filter must still match the English prefix (`"Equipment:"` and so on). Store the English category key as the picker's tag or value.
- **Optional additive UI.** The detail view may show tags as small capsules with an SF Symbol per category: `wrench.and.screwdriver` for Equipment, `doc.text` for Document, `list.number` for Procedure, `book.closed` for Record and `person.2` for Personnel. The capsules are in addition to the Smart tags line inside the body, never instead of it.
- **Unit test for SIRE-049:**
  1. If the Windows source is reachable from the test (a full repo checkout, with the path derived from `#filePath` to `AA/Sire/TagExtractor.cs`), parse it with `private static readonly string\[\] (\w+)Keywords =\s*\[(.*?)\];`, with dot-matches-newline enabled, and extract the literals with `"((?:[^"\\]|\\.)*)"`. Assert that all five arrays equal the Swift ones, element by element.
  2. Always assert the counts and the SHA-256 fingerprints from A.2.6. This works on a Mac-only checkout, such as CI.

### A.6 Test vectors

**TV-KW-1, counts.** `equipment.count == 87`, `document.count == 52`, `procedure.count == 47`, `record.count == 27`, `personnel.count == 24`, 237 in total.

**TV-KW-2, fingerprints and spot checks.** The five SHA-256 values and the "All" row in A.2.6 match. The following hold, using 0-based indices:
- `equipment[14] == "oxygen analyser"` and `equipment[15] == "oxygen analyzer"`
- `equipment[3] == "lifejacket"` and `equipment[4] == "life jacket"`
- `document[5] == "DOC"` and `document[16] == "Document of Compliance"`
- `procedure[0] == "procedure"` and `procedure[22] == "COW"`
- `record[0] == "log book"` and `record[1] == "logbook"`
- `personnel[0] == "Master"` and `personnel[9] == "rating"`

**TV-KW-3, uniqueness and containment.**
- No two of the 237 strings are equal when compared case-insensitively.
- Exactly 19 (shorter, longer) containment pairs exist, as listed in A.2.7.
- No two of the 237 tags compare `.orderedSame` under the A.3.2 comparator.

**TV-KW-4, coverage.** Over the shipped bank, the set of tags that occur has 182 elements. The 55 tags in A.2.8 never occur.

**TV-TAGX-1 ⚠, `ExtractTags` for real question 2.1.1.**
- Expected output, sorted:
  1. `Document: certificate`
  2. `Document: class survey`
  3. `Document: classification`
  4. `Document: CSSR`
  5. `Document: DOC`
  6. `Document: HVPQ`
  7. `Document: survey status`
  8. `Procedure: defect reporting`
  9. `Procedure: procedure`
- The ordinal order, which is **wrong**, would be `Document: CSSR`, `Document: DOC`, `Document: HVPQ`, `Document: certificate`, `Document: class survey`, `Document: classification`, `Document: survey status`, `Procedure: defect reporting`, `Procedure: procedure`.
- ⚠ This is the only question in the bank whose order depends on the space being significant (items 2 and 3). Confirm it on Windows (A.7).
- `Document: DOC` is a substring-only hit, from "documents" in `expected_evidence` and `suggested_inspector_actions`.
- The Smart tags line, which is persisted in quick-add bodies, is exactly `Smart tags: Document: certificate   ·   Document: class survey   ·   Document: classification   ·   Document: CSSR   ·   Document: DOC   ·   Document: HVPQ   ·   Document: survey status   ·   Procedure: defect reporting   ·   Procedure: procedure`
- `DominantCategory` is **`Procedure`**, with counts Document 7, Procedure 2 and Equipment 0. The large Document count is irrelevant.

**TV-TAGX-2, `ExtractTags` for real question 12.1.1.**
- Expected output, sorted:
  1. `Document: certificate`
  2. `Document: polar water operational manual`
  3. `Personnel: Chief Mate`
  4. `Personnel: competency`
  5. `Personnel: Master`
  6. `Personnel: rating`
- The ordinal order, which is **wrong**, would place `Personnel: Master` before `Personnel: competency`.
- `Personnel: rating` is a substring-only hit, from "operating" in `expected_evidence`, `suggested_inspector_actions` and `objective`.
- The Smart tags line is exactly `Smart tags: Document: certificate   ·   Document: polar water operational manual   ·   Personnel: Chief Mate   ·   Personnel: competency   ·   Personnel: Master   ·   Personnel: rating`

**TV-DOM-E, `DominantCategory` = `Equipment` for real question 10.5.2. The deciding tag is an intentional false positive.**
- Tags: `Document: oil record book`, `Equipment: AIS`, `Personnel: rating`, `Procedure: procedure`. The culture and ordinal orders are the same here.
- Counts are Document 1, Equipment 1, Personnel 1 and Procedure 1. Since Equipment 1 ≥ Procedure 1, the result is **`Equipment`**, and quick-add pre-selects **Equipment / Area**.
- `Equipment: AIS` exists **only** because of "raises", in `expected_evidence` and `suggested_inspector_actions`. `Personnel: rating` comes only from "generating", in `objective`. `Procedure: procedure` comes only from "procedures".
- Two tempting deviations get this wrong:
  - A word-boundary implementation keeps only `Document: oil record book` and returns `Task`.
  - An implementation that suppresses just the `AIS` hit returns `Procedure`.

**TV-DOM-P, `DominantCategory` = `Procedure` for real question 2.3.1. This vector is also a whitespace trap.**
- Tags, sorted: `Document: classification`, `Document: DOC`, `Procedure: defect reporting`. The ordinal order would put `Document: DOC` first.
- Counts are Equipment 0 and Procedure 1, so the result is **`Procedure`**.
- `Document: DOC` is a substring-only hit, from "documents" in `expected_evidence`.
- In `suggested_inspector_actions`, the words "ballast" and "tank…" are separated by a **line break** (`"\n"`), so the keyword `ballast tank` does **not** match. An implementation that collapses whitespace adds `Equipment: ballast tank` and wrongly returns `Equipment`.

**TV-DOM-T, `DominantCategory` = `Task` for real question 12.1.1.** Using the TV-TAGX-2 tags, the counts are Document 2, Personnel 4, Equipment 0 and Procedure 0, so the result is **`Task`**. Six tags are present, and none of them decides the result.

**TV-DOM-X, further real-bank vectors.** Tags are listed in en_US order.

| Q | Tags | Counts | Dominant | Point being tested |
|---|---|---|---|---|
| 9.3.1 | `Equipment: AIS`, `Equipment: anchor`, `Equipment: windlass`, `Procedure: anchoring procedure`, `Procedure: checklist`, `Procedure: procedure`, `Record: bridge log`, `Record: log book`, `Record: maintenance record` | E3 P3 R3 | **Equipment** | A tie goes to Equipment. The tie exists only because of `AIS` ("appraisal"). `anchor` comes from "anchoring". |
| 7.1.1 | `Document: passage plan`, `Document: risk assessment`, `Document: voyage plan`, `Equipment: AIS`, `Procedure: checklist`, `Record: bridge log`, `Record: log book` | D3 E1 P1 R2 | **Equipment** | `AIS` comes only from "appraisal". |
| 3.5.1 | `Equipment: OWS`, `Personnel: deck officer`, `Personnel: engineer officer`, `Personnel: familiarisation`, `Personnel: rating`, `Procedure: procedure`, `Record: familiarisation record` | E1 Pe4 P1 R1 | **Equipment** | `OWS` comes only from "follows". |
| 5.6.2 | `Equipment: ballast tank`, `Equipment: cargo tank`, `Equipment: UPS`, `Procedure: procedure`, `Record: calibration record` | E3 P1 R1 | **Equipment** | `UPS` comes only from "groups". The culture order puts `UPS` last among Equipment; the ordinal order would put it first. |
| 5.2.8 | `Equipment: fire damper`, `Equipment: fire door`, `Equipment: ventilation`, `Procedure: COW`, `Procedure: emergency plan` | E3 P2 | **Equipment** | `COW` comes only from "cowls". |
| 4.2.3 | `Equipment: AIS`, `Equipment: ECDIS`, `Personnel: Master`, `Personnel: OOW`, `Procedure: daily orders`, `Procedure: NCR`, `Procedure: procedure`, `Procedure: standing orders` | E2 Pe2 P4 | **Procedure** | `NCR` comes only from "increased". The ordinal order would put `NCR` before `daily orders`. |
| 1.1.1 | (none) | — | **Task** | A data field. Its search text is three spaces. |
| 11.1.2 | (none) | — | **Task** | A photo question with no objective and no guidance. |

**TV-TAGX-BANK-2, aggregates over the shipped bank.** These extend TV-TAG-BANK.
- There are **1,568** tags in total. By category: Equipment 302, Document 247, Procedure 529, Record 210, Personnel 280.
- With every other filter at its default, the Evidence category filter shows these counts. The list header then reads `Questions (198)` for Equipment, and so on.

  | Filter value | Questions shown |
  |---|---|
  | `All` | 410 |
  | `Equipment` | 198 |
  | `Document` | 148 |
  | `Procedure` | 299 |
  | `Record` | 133 |
  | `Personnel` | 199 |

- The 54 zero-tag questions are the 25 data fields plus 29 inspection questions: 26 in chapter 11, 2 in chapter 10 and 1 in chapter 9. Three of those 29 are detailed questions.
- For 66 questions the culture order differs from the ordinal order. For 1 question (2.1.1) the order depends on the space weight. No match crosses a field boundary.
- The ten most frequent tags, with the number of questions carrying each:

  | Tag | Questions |
  |---|---|
  | `Procedure: procedure` | 272 |
  | `Personnel: rating` | 113 |
  | `Record: log book` | 74 |
  | `Document: DOC` | 61 |
  | `Procedure: checklist` | 58 |
  | `Personnel: SSO` | 56 |
  | `Document: certificate` | 47 |
  | `Record: bridge log` | 45 |
  | `Personnel: Master` | 43 |
  | `Equipment: cargo tank` | 39 |

- The dominant distribution remains Procedure 187, Equipment 144 and Task 79 (TV-TAG-BANK).

**TV-TAGX-FP, false-positive census.** An "inside a longer word only" hit means the keyword has no occurrence in that question's search text that is bounded by non-alphanumeric ASCII characters on both sides. The Mac must reproduce every one of these hits.

| Tag | Questions with the tag | … only inside a longer word | Typical host words |
|---|---|---|---|
| `Equipment: AIS` | 10 | 7 | appraisal, raises, raised |
| `Equipment: UPS` | 2 | 2 | groups, cups |
| `Document: DOC` | 61 | 60 | documented, documentation, documents |
| `Personnel: rating` | 113 | 47 | operating, demonstrating, integrating, gratings |
| `Procedure: COW` | 4 | 1 | cowls |
| `Personnel: SSO` | 56 | 54 | associated, compressor, assessor, accessories, lessons |
| `Procedure: NCR` | 5 | 5 | increased, increase, increasing |
| `Document: COF` | 5 | 5 | cofferdam, cofferdams |
| `Equipment: OWS` | 2 | 2 | follows, windows |
| `Equipment: anchor` | 12 | 3 | anchoring |
| `Procedure: procedure` | 272 | 156 | procedures |

**TV-TAGX-SYN, synthetic vectors.** These are safe to hard-code, because they contain no bank text. Fields that are not named are `""`.

| # | Input | `ExtractTags` (sorted) | Dominant |
|---|---|---|---|
| 1 | EE `"fire\npump"` | `[]`: a newline is not a space | Task |
| 2 | EE `"fire  pump"` (two spaces) | `[]` | Task |
| 3 | EE `"Check the fire"`, SIA `"pump room"` | `["Equipment: fire pump"]`: matches across the joining space | Equipment |
| 4 | short `"\u{FB01}re pump"` (ﬁ ligature) | `[]`. Foundation `.caseInsensitive` would wrongly match. | Task |
| 5 | short `"FIRE PUMP"` | `["Equipment: fire pump"]`: the tag uses the keyword's casing, not the text's | Equipment |
| 6 | short `"Harbour MASTER"` | `["Personnel: Master"]` | Task |
| 7 | short `"anchoring procedure"` | `["Equipment: anchor", "Procedure: anchoring procedure", "Procedure: procedure"]` | Procedure (E1 < P2) |
| 8 | short `"hot work permit"` | `["Document: hot work permit", "Document: work permit", "Procedure: hot work"]` | Procedure |
| 9 | short `"Windlass checklist"` | `["Equipment: windlass", "Procedure: checklist"]` | Equipment (a 1–1 tie) |
| 10 | short `"Documented"` | `["Document: DOC"]` | Task |

These complement the existing TV-TAG-1 to TV-TAG-4 (§7.4). Their tag sets were re-checked with the same implementation and agree.

### A.7 Open questions added by this addendum
1. **Q-18, the TV-TAGX-1 order on Windows.** Run `TagExtractor.ExtractTags` for 2.1.1 in the Windows headless harness, with the user's real culture (en-GB is likely), and record whether `Document: class survey` precedes `Document: classification`. The expectation, and the Mac behaviour, is that it does, because ICU with `CompareOptions.None` treats the space as significant. If Windows disagrees, the Mac comparator must emulate space-ignoring order for tags, and TV-TAG-3 must be re-verified. No other question in the shipped bank is affected.
2. **Q-19, whether the lists should ever be "fixed".** Word boundaries, plural handling and dropping the dead variants would make the tags more accurate. They would also change the pre-selected kind for more than 100 questions and the persisted Smart tags text. **Port decision: replicate exactly.** Any improvement must ship on both platforms together, with a note that bodies created earlier keep their old Smart tags text.
