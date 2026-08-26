# AA — Build Progress

## Summary
A WPF (.NET 10, C#) Windows desktop application named **AA** that lets you organize **Equipment/Area**, **Tasks**, **Procedures**, and **Vessels** into containers, each with a rich-text editor and an OneDrive-style file bank (files can be imported as copies or **linked in place** to live network-drive originals, with an **Open all** action for daily routines). Items can be related to each other across kinds, visualized as a 2D relationship map; tasks can be scheduled and viewed in a **Calendar** (Day / Week / Month / All / Agenda) and worked in a **Kanban Board** (To Do / In Progress / Blocked / Done, drag to change status).

The app opens behind a **login screen**, persists locally under `%LOCALAPPDATA%\AA\`, and can back up / sync to **Google Drive** — a synced-folder copy, or direct **OAuth** upload/download with **real-time sync on save** and newer-save detection across PCs. Any import/overwrite is gated by a **deep, drill-down change preview**.

The app uses Consolas as its primary font, a clean light UI palette, and an intuitive tabbed navigation model. The newest capabilities are documented in the dated update sections near the end of this file.

## How to run
```powershell
cd "<repo>\AA"
dotnet build
.\bin\Debug\net10.0-windows\AA.exe
```

### Portable self-contained build (single file, no .NET runtime required)
```powershell
cd "<repo>\AA"
dotnet publish AA/AA.csproj -c Release -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true `
  -o publish
.\publish\AA.exe
```
Produces a single **~112 MB** `publish\AA.exe` that runs on any 64-bit Windows machine without installing .NET. Copy it anywhere; it is fully portable. *(It grew from ~72 MB when Flash Sync added OpenCV's native QR decoder. `-r win-x64` keeps the x86 natives out, and the build drops OpenCV's 26 MB FFmpeg DLL since capture is DirectShow-only.)*

### Framework-dependent build (smaller, requires .NET 10 runtime)
```powershell
dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o publish-fd
.\publish-fd\AA.exe
```
Application data is stored under: `%LOCALAPPDATA%\AA\` (file: `data.json`, imported files under `files\`).

## Features implemented

### No crew-expiry popup at startup
AA no longer interrupts every launch with a modal list of crew contracts overdue or due soon ([MainWindow](AA/MainWindow.xaml.cs), which called `CrewPg.CheckExpiries(interactive: false)` on load). The information was never lost by dismissing it, so the popup only cost a click.
Crew expiries are still surfaced, just without blocking startup: the **Crew tab badge** shows `Crew ⚠ n` passively, **Tools ▸ Check crew contract expiries** reports on demand (and still says so when nothing is due), and a COMPAS import still reports what it found. The tray reminder balloon and the once-a-day digest continue to include a crew count alongside other due work.

### Open a task / procedure / equipment in its own window
Right-click an item ▸ **Open in new window** ([HierarchyPage](AA/Views/HierarchyPage.xaml)) opens it in a new [ItemWindow](AA/Views/ItemWindow.xaml) — name, description, tags, notes and the file bank — so several items can be worked on at once. Schedule, subtasks, steps and relationships deliberately stay in the main window; those are ~500 lines of imperative code-behind and moving them is where the breakage risk lives, so v1 says so on screen rather than half-moving them.

**Only one editor is ever bound to a container.** `ContainerEditor.PersistRichText` serialises its whole document over the container's text with no dirty check, so two live editors on one item means whichever saves last silently wins. While an item is detached, the main pane unbinds its editor (parking it on a throwaway container) and shows "This item is open in its own window"; closing the window rebinds it. Opening an already-open item focuses its window instead of making a second one.

**The window holds an Id, never a model reference.** Any reload — File ▸ Reload, an import, a shared-save pull, Flash Sync apply — replaces every model object, so a window still pointing at the old one would write edits into an orphan that is never saved. `SetRepo` re-resolves through `FindById`; if the item is gone the window goes read-only and says so. Pinned by tests showing that undo restores an item under the same Id but as a **different object**, which is exactly why a held reference would be silently dead.

**Every path that must reach these windows now does:** `FlushAllEditors` (so a save, sync or export includes their buffered edits, and the shared-save "changes will be lost" prompt actually sees them), the post-reload fan-out, deletion (their windows close rather than keep editing something in the Trash), and app exit (closed and flushed *before* the final save and shared-bundle push). Each window's close-flush is wrapped in try/catch — a throw there would cancel the close and trap the window open.

Locked items refuse to open in a window at all, matching the main pane's gate. Suite **313/313**, build **0/0**. WPF windows cannot be exercised headlessly, so the manual check is: open an item in a window, type, Ctrl+S in the main window, restart — the text should be there.

### Crew date parser: reads any format, and works out dd/mm vs mm/dd
New [Services/DateResolver.cs](AA/Services/DateResolver.cs) replaces the COMPAS importer's date handling. It reads ISO, year-first, compact `20260304`, month names in any position (`12 Mar 2026`, `March 4, 2026`, `12-MAR-26`, `SEPT`, ordinals like `1st`), 2-digit years, times and zone markers (dropped, never time-zone converted — that can shift the day), Excel serial numbers in both the 1900 and 1904 systems, and placeholders (`-`, `N/A`, `TBC`, `#N/A`, `00/00/0000`) as empty rather than errors.

**Fixed a silent month-shifting bug.** The old `FmtDate` matched **year-first only** ([CrewConverter](AA/Services/CrewConverter.cs)), so an ordinary `15/07/2026` never matched and was stored as raw text. `CrewMember.ParseDate` then re-read that text with `DateTime.TryParse(…InvariantCulture)` — which is **month-first**. So a day-first `03/04/2026` (3 April) came back as **4 March**: wrong by a month, with nothing on screen looking wrong. Three different parsers in the app disagreed about this.

**The ambiguity is resolved from the whole file, not per value.** `03/04/2026` is undecidable alone, so the importer reads every date in the sheet first: any value with a first component above 12 proves day-first, any with a second above 12 proves month-first. One unambiguous date settles every ambiguous one around it.
- **Conflicting evidence** (the file writes dates both ways) is reported as a conflict, never resolved by majority — half the rows would be wrong. Unambiguous values still import; ambiguous ones are left unread and flagged.
- **No evidence at all** (every date has both components ≤ 12) asks the user which convention the file uses, showing what 03/04/2026 would mean either way, with Cancel importing nothing. It never guesses silently.
- **2-digit years use a role-aware pivot**: an expiry in `'30` is 2030, a birth date in `'98` is 1998. The base pivot is 00–68 → 2000s; blindly using the current century read a 1998 birth date as 2098 (caught by a test).
- **Every date that leaned on the inferred convention is flagged per crew member** ("read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first"), and the inferred convention goes to the status line and the activity log — so a wrong reading is visible now and explicable months later.
- Unreadable dates are now **Error** severity, not Info: an unread date silently disables the contract-expiry tracking that depends on it.
- Existing stored dates are **not** re-interpreted. The live store is already canonical `yyyy-MM-dd`, so a migration would be a no-op with non-zero risk.
- Harness **49/49** for the parser (every format, the inference rule including the conflict and no-evidence cases, the year pivot, placeholders, junk, Excel serials, storage form). Suite **309/309**, build **0/0**.

### Arrange the order saved lists appear in (and export in)
Saved lists were always shown and exported alphabetically, with no way to choose the order. The Saved Lists tab now has **↑ / ↓ / Move to position…** (matching the checklist builder's existing reorder controls), and that arrangement is what a group export uses. New [Services/SavedListOrder.cs](AA/Services/SavedListOrder.cs) holds the logic so it is testable.
- **Persistent, not per-export.** The order lives on the tab, so what you see is what you get in the PDF. A per-export dialog would have left the tab alphabetical and the PDF different — the exact mismatch the request is about — and would have added a fourth modal to a flow that already asks bullets/numbers, then a file dialog, then "open it now?". Export gained **no** extra step.
- **No new model field.** `AppData.ChecklistTemplates` is a plain collection round-tripped by System.Text.Json, so array order already persists; the order of the collection *is* the arrangement. A `SortIndex` field would have needed keeping in step on every add, delete and group change, and drifts the moment one path forgets. Pinned by a save/reload test.
- **Moves never cross a group boundary.** Reordering works on the group's subsequence of the collection, not flat indices — a flat `Move` would happily hop the boundary, leaving a list apparently in another group while its `GroupId` says otherwise. Multi-select moves as a block keeping relative order; a selection spanning two groups is refused with an explanation rather than scattered.
- **Group headings stay contiguous.** `PdfExporter` emits a heading only when the group changes between consecutive entries, so an interleaved order would print the same heading twice with the lists split under it. "Export ALL" sorts by group first and by collection position second (a stable sort), which re-blocks any interleaving structurally rather than trusting the data. Tested with a deliberately interleaved collection.
- **Sort A–Z toggle** (persisted via the existing `Ui.SortAZ`) for finding a list by name in a long tab; it only changes what is displayed, the arrangement underneath is untouched, and the reorder buttons disable while it is on so nothing is rearranged against a view that is not the real order.
- The insert-saved-list picker now follows the same order, so the tab and the picker agree.
- Harness **18/18** (span, nudges, boundary refusals, cross-group refusal, multi-select order, no loss/duplication, move-to-top/bottom, export order, contiguity under an adversarial order, ungrouped last, save/reload). Suite **258/258**, build **0/0**.

### Saved-list PDF export asks bulleted or numbered, every time
Exporting a saved list, a group, or all of them ([SavedListsPage](AA/Views/SavedListsPage.xaml.cs) — all three buttons share one path) now asks how the items should be marked, via a new [ListStylePromptWindow](AA/Views/ListStylePromptWindow.xaml). Previously `PdfExporter.ExportSavedLists` hardcoded `1.`, `2.`, `3.` — in a paragraph style named "Bullet".
- **Always asked, never remembered, and bullets are preselected.** Numbering asserts the items run in sequence, which is a claim about the content: true of a procedure, false of a set of checks that can be done in any order. The old default quietly made that claim on every export.
- The `numbered` parameter on `ExportSavedLists` deliberately has **no default value**, so no caller can inherit numbering without having asked.
- Cancelling the prompt cancels the export before the file dialog appears.
- Harness **2/2** — both styles produce a valid PDF, and the two files are byte-different, which is what catches the flag being accepted and then ignored. Suite **240/240**, build **0/0**.

### Insert a saved list into a note as bullets/numbers, edit and reorder it + LibreOffice-like list editing
A **≔** button in the container editor's list group inserts any saved list into the note body as a real bulleted or numbered list. New [Services/ListFormatting.cs](AA/Services/ListFormatting.cs) (pure, testable) + [Views/InsertSavedListWindow.xaml](AA/Views/InsertSavedListWindow.xaml).
- **Adds, never replaces.** The list goes into the caret's *own* block collection, after the block the caret sits in — so it works inside a table cell or an existing bullet instead of being dumped at the end of the note. An active selection is left completely untouched (the list lands after it), and the whole insert is one `BeginChange`/`EndChange` in a `try/finally`, so **one Ctrl+Z removes it**.
- **Not crowded.** WPF's defaults are the problem: a nested list carries an automatic margin that renders as a full blank line, and its indent step (~49px) is about double Writer's. Outer lists get `Margin 0,6`, nested lists `Margin 0`, every level `Padding 24`, and item paragraphs `Margin 0,1` — so an imported 20-step checklist reads as a list, not a wall. Normalisation runs *after* each list command, because those commands rebuild paragraphs and discard explicit margins.
- **Picker** shows saved lists grouped by List Group with a live preview, bullets/numbers, and an optional duration suffix. It states plainly what is **not** carried across (item notes, attached files) rather than letting the user find out later. Item notes are deliberately not imported: reading them means parsing each item's stored XAML, and that would add a fifth unrestricted-XAML-parser site to the one already flagged as a risk below.
- **LibreOffice parity.** Per-level markers now cycle like Writer (disc/circle/square, 1./a./i.). **Backspace at the start of a list item** outdents a level, or leaves the list at the top level — WPF's default merges the item into the previous one as a marker-less second paragraph, which reads as a rendering fault. **Indent on an ordinary paragraph** now moves the whole paragraph; WPF was setting `TextIndent`, which shifts only the first line. Enter, Enter-on-empty-item, Tab and Shift+Tab are already correct natively and were deliberately left alone — intercepting them is the main way to make a list editor worse.
- **Cannot be done in WPF** (so not promised): outline numbering (1.1.1), custom bullet glyphs, `1)`/`(a)` punctuation, per-item marker suppression, and restarting numbering without physically splitting the list.
- **The imported list is ordinary editable text**, not a fixed block — click into any bullet and type at the start, middle or end of any item, empty one and refill it, add or remove items. Pinned by tests, because it is the whole point of importing rather than pasting a picture of a list.
- **Reorder with ⤒ / ⤓ or Ctrl+Alt+Up / Ctrl+Alt+Down** (Writer's own gesture). Moves the list item the caret is in, or a contiguous multi-item selection, keeping relative order; a moved item **carries its sub-items with it**, because they live inside the item. With the caret in ordinary text it moves the whole block instead, which is how one inserted list moves past another. Items are re-anchored in their existing collection — nothing is created or deleted — so a reorder can change order but never lose content. At the ends of a list it does nothing rather than wrapping.
- Harness **38/38** for list building/spacing/markers/normalisation, insert-preserves-content, typing inside imported items, and reordering (including nested items travelling with their parent, group moves, and edge refusals). Suite **238/238**, build **0/0**.

#### Fixed: a locked note could be destroyed by a single keystroke
Found while mapping the editor, and **pre-existing** — nothing to do with the feature above. A legacy whole-document-encrypted body that the user had not unlocked was rendered as an **empty document over live ciphertext** ([ContainerEditor.xaml.cs](AA/Views/ContainerEditor.xaml.cs) `Load`), the editor has **no read-only mode**, and `PersistRichText` had no guard while being wired to a 400 ms autosave debounce. So opening such a note and typing one character serialised the empty document over the encrypted content — permanently, with no undo and no warning. The same applied to a body whose XAML failed to parse and was flattened to literal text: saving made the flattening permanent. Both now set a `_contentWithheld` flag that blocks persistence entirely, and the list insert refuses with an explanation rather than writing.

### Batch delete for tasks, procedures and equipment/areas
Select many items in the Hierarchy list and delete them in one action — right-click **🗑 Delete selected…**, or the toolbar Delete button, which now acts on the whole selection instead of only the last-clicked item. New [Services/BatchDelete.cs](AA/Services/BatchDelete.cs) + [Views/BatchDeleteMenu.cs](AA/Views/BatchDeleteMenu.cs), following the existing two-layer `BatchDone` / `BatchDeadline` pattern (pure operations in the service, confirmation in the menu).
- **Soft-delete, as the single delete already does.** Everything goes to the Trash with its whole subtree, restorable from File ▸ Trash. References are deliberately **not** scrubbed at delete time — matching `TrashHierarchyItem` ([AppRepository.cs:339](AA/Services/AppRepository.cs)), so a restore rebuilds the relationship graph intact. Scrubbing still happens on permanent removal.
- **One Ctrl+Z restores the whole batch.** `UndoLastDelete` previously restored a single entry, so undoing a 40-item delete would have taken 40 presses — and the user would realistically stop partway and never learn the rest were still gone. Trash entries deleted together share a new `BatchId` ([Models.cs](AA/Models/Models.cs)); a single delete leaves it `Guid.Empty`, so old saves and one-off deletes keep undoing one at a time. `UndoLastDelete` now returns **every** ItemType restored, because a mixed batch spans several pages and refreshing only one would leave the others showing stale rows.
- **The confirmation states what a multi-select hides**: the kind breakdown, how many subtasks/steps/components ride along inside collapsed items, how many carry attachments, how many are linked from elsewhere (those links read "(missing)" until the Trash is emptied), how many locked items will be skipped — and a warning when the batch would push the oldest entries past the 200-item Trash cap, i.e. out of undo range.
- **Selecting a parent and its own subtask deletes it once**, not twice; duplicate picks collapse; row wrappers and raw models are both accepted, since lists bind to different shapes across pages.
- **Attachments are left on disk**, matching every existing delete path. An orphan sweep was deliberately *not* written: blobs can be shared with checklist templates and `QuickCard` targets, and `IsLink`/`LinkInPlace` files point at the user's own network originals — a sweep would delete real work. Pre-existing, unchanged, and called out here rather than silently "fixed".
- Harness **19/19** for this (kind counts, hidden-descendant counts, empty/locked/duplicate selections, parent+descendant dedup, batch removal, one-undo-restores-all, per-page refresh set, subtree survival, relationship survival across delete→restore, and child removal from subtask lists). Suite **202/202**, build **0/0**.
- **Not yet attached** (deliberate, needs its own decision): the Board and Ctrl+N quick window delete tasks *hard*, without the Trash, so a batch entry there could not honestly promise undo; and the Calendar shows one recurring task as several rows, which needs dedup first.

### Whole-Drive search + reads the iPhone's backups
AA previously used the least-privilege `drive.file` OAuth scope, which returns **only files AA itself created**. The whole-Drive queries were already written — the permission was the limit — so a backup placed by hand, synced in by Google Drive for desktop, or uploaded by the **iPhone app** was invisible.
- **Scopes are now `drive.readonly` + `drive.file`** ([GoogleDriveUploader](AA/Services/GoogleDriveUploader.cs)): read anything in the Drive, write **only** AA's own files. AA therefore cannot modify or delete anything it did not create — the least privilege that still satisfies "search my whole Drive". *(The iOS app takes full `drive` for the same purpose; Windows deliberately takes less.)*
- **Re-consent is forced, not assumed.** A cached refresh token carries only the scopes it was granted under, and Google's library will happily keep using it — so an old token would appear to work while still returning just AA's own files, i.e. the exact bug being fixed. The token's user key is scope-versioned (`v2-wholedrive`), so a fresh consent is genuinely obtained; `HasToken` is version-aware so a background check can't surprise the user with a browser, and `NeedsReconsentForWholeDrive` drives a one-time explanatory prompt at startup.
- **Reads the iPhone's backups.** iOS uploads `AA-backup-iOS-<stamp>.aaz` (and `-dataonly-` when it sends text only). Windows' query never mentioned that prefix, and Drive's `contains` on `name` matches word **prefixes**, so `'.aaz'` alone was not dependable — `AA-backup` is what actually finds them. `IsRestorableBundleName` mirrors the iOS app's `isRestorableBundle` exactly so both sides agree on what is restorable, **plus** `aa-sync` for the Windows-only rolling file that iOS never restores from (omitting it would have silently broken sync-on-save detection).
- **Name matching is no longer proof.** Under the old scope only AA's uploads could come back, so a name match was safe; now a Google Doc called "aa-database notes" matches the query too. Candidates must be a real `.aaz`/`.zip` and never a Google-native type, or AA would offer to import a stranger's file.
- Searches **shared drives** too (`IncludeItemsFromAllDrives`), and **pages** through results (capped) — a broad name query can otherwise bury the real backup behind a first page of near-misses.
- An iPhone `-dataonly` bundle carries no `files/` folder, which is exactly the case the text-only import guard handles: importing one leaves this PC's attachments untouched instead of sweeping them.
- **Setup note:** `drive.readonly` is a Google *restricted* scope. Keep the OAuth client in **Testing** mode with your Google account added as a **Test user**, or sign-in returns `access_denied` (the same requirement the iOS app already documents in its `SETUP_GOOGLE_DRIVE.md`).
- Harness **11/11** for the matching rule (finds iPhone backups incl. text-only, Windows OAuth backups, the rolling sync file, hand-renamed `.aaz`, case-insensitively; ignores Google Docs/folders that merely match the query, unrelated zips, non-archives, empty names). Suite **183/183**, build **0/0**.

### Flash Sync with iPhone (QR fountain) + text-only export/import everywhere
Text, changes and formatting now move between this PC and the iPhone app **by flashing QR codes on screen** — no network, no cable, no Wi-Fi — and every export path can carry data **without attachments**. Attachments are never part of either: they live in `files/` and are referenced by path, so the JSON tree that travels holds no bytes.

**Wire protocol (byte-exact with the shipping iOS app).** [FlashSync/](AA/FlashSync/) implements the `AAQ\x01` contract: Base45 · CRC-32 · raw DEFLATE · xorshift32 · a coarsened Robust-Soliton degree table · a **fountain (rateless) code** so the receiver needs *any* K·(1+ε) frames rather than a specific set, with a systematic prefix (a clean capture decodes in one pass) and round-robin cycling for K ≤ 8. Verified against **every vector in the spec** plus loopback at 40 % loss, mid-stream join and foreign-code rejection.
- **Incremental by default** ([FlashSyncStore](AA/FlashSync/FlashSyncStore.cs)). A **baseline** records what the other device last *confirmed* receiving; the next send is a structural diff against it, so a one-task edit is a couple of frames instead of ~500. The baseline advances **only on explicit user confirmation** — guessing would silently drop the very changes that never arrived.
- **Never carries credentials.** `PasswordHash` / `PasswordSalt` / `AppIdentity` / `EncryptLocalData` / `SyncOnSave` / `GeminiApiKey` / machine-local paths are excluded; `Ui` (window layout) is excluded from change sets *and* snapshots, and the receiver's own layout is carried forward on apply. Settings are **merged**, never replaced.
- **Review before apply.** Nothing is written until the user sees a summary and agrees; a snapshot says plainly that it replaces the database.

**QR libraries — two upstream defects found and designed around.**
- **QRCoder was removed.** Its Reed-Solomon long division terminates early when a block's data begins with ≥ `eccPerBlock` zero codewords, emitting **all-zero ECC**. Our zero-padded tail chunk hits exactly that, producing a symbol *no* decoder can read (ZBar, OpenCV and Apple Vision all fail); at K ≤ 8 that frame travels alone, so an ordinary small edit would have **hung forever**. Generation is now `Net.Codecrete.QrCodeGenerator` (Nayuki's reference algorithm) — 39/39 spec-perfect at the codeword level.
- **ZXing.Net was rejected for reading.** Its detector misses **mask-0** symbols even when perfectly clean, and zero-padded frames naturally select mask 0 — i.e. it fails on precisely our traffic, unfixably from the Windows side. Reading uses OpenCV's **WeChat** model (95.5 % overall, 82 % under blur+warp+glare vs 42 %, zero wrong decodes in ~5 000 trials). Its four weight files ride **embedded in the exe** and unpack on first use; the 26 MB FFmpeg DLL is trimmed from the output since capture is DirectShow-only.

**Hostile-input hardening** (a camera feeds the decoder whatever it sees, through error-correction that can mis-correct). A manifest claiming `chunkCount = 0` previously made the decoder report a **completed transfer before any data arrived** and hand an empty payload to apply — now rejected, as iOS does. `Finish()` honours its "return null, change nothing" contract instead of throwing on the capture thread (20 000 fuzzed frames: zero exceptions, zero false payloads), with bounds on every camera-supplied length. `Summarize` now names `BlockDeletes`/`SettingsDeletes` — a change set that removes whole sections previously summarised as **"no changes"** while the applier deleted them.

**Text-only export/import (Google Drive, shared save, ZIP).** **File ▸ Export text only (no attachments)** governs *every* export path at once (Ctrl+S sync, synced-folder save, OAuth upload, shared save), stamping `DataOnly` into `source.json`.
- **Data-loss bug found and fixed first.** A bundle with no `files/` made `AttachmentsMatch` compare 0 against N, conclude "attachments changed", and **permanently delete every local attachment** as an orphan (`File.Delete`, errors swallowed) — so shipping a text-only export without this guard would have destroyed attachments on every receiving PC. Both importers now recognise a data-only bundle and leave attachments alone; a bundle that genuinely carries attachments still syncs and still sweeps real orphans.
- **File ▸ Import data folder** now routes through the smart importer instead of the folder-wiping one, so it keeps this PC's settings, password and Google state.
- `Settings` gained `[JsonExtensionData]`, so keys from a newer build or another device survive a save; `MigrateLegacyAbsolutePaths` was restored to the smart-import path (dropped in `e8bad18`).

Suite **172/172**, build **0/0** — including a synthetic optical loop (rendered QR → real detector → fountain reassembly, byte-exact) proving generation and decoding without a camera. **Not yet proven: a real webcam filming a real phone screen** — every degradation tested so far is synthetic (no rolling shutter, moiré, autofocus hunting or PWM banding). The Send direction needs no camera and is the one to try first.

### App identity (stamped into every shared save & Google Drive export)
Each installation has its own **editable identity** (e.g. a vessel or operator name; defaults to the PC name, always editable via **File ▸ Set app identity…**, shown in the title bar and persisted per-machine in `settings.json`). It is stamped into **every exported bundle** so you can tell which machine/operator produced a given save:
- `DataStore.ExportFolderToZip` writes a `source.json` (identity, machine, timestamp) into every bundle — which covers **both** the shared-save file and all Google Drive backups (they share this export path). Read back with `DataStore.PeekBundleSource` / `PeekBundleIdentity`.
- Google Drive additionally records the identity in the file's **appProperties** (rolling sync file and uploaded backups) and in the backup **filename** (`aa-data-{identity}-{timestamp}.zip`).
- On a shared-save reload or a "newer save on Drive" prompt, AA surfaces **who wrote it** (`Reloaded the shared save from "Vessel-Alpha"`). ([DataStore](AA/Services/DataStore.cs), [GoogleDriveUploader](AA/Services/GoogleDriveUploader.cs))

### Smart Google Drive import (data-only when attachments unchanged) + whole-Drive detection
- **Detect `aa-data` anywhere in Drive** — `GoogleDriveUploader.GetBestRemoteAsync` now finds the newest AA save across the **whole Drive** (the rolling `AA-sync.zip` OR any `aa-data*` backup, in any folder), keyed by the data's own LastModified (appProperties) or, when absent, the Drive modified-time. Previously the check only looked inside the `AA Sync` folder. *(Scope note — **superseded**: this originally used the least-privilege `drive.file` scope and so saw only files AA itself created. AA now reads the whole Drive; see "Whole-Drive search + reads the iPhone's backups" above.)*
- **Import everything-but-attachments on a text/data-only change** — `DataStore.ImportBundleSmart` extracts + validates the bundle in a temp folder, then compares its `files/` to the local attachments; when they're **identical** (same names + sizes) it applies **only the data.json** and leaves the (potentially large) attachments untouched, otherwise it syncs attachments additively. Used by the Drive real-time "check for newer save" and by *Load backup from Google Drive*; the status line says which path ran (`… (text only — attachments unchanged)`). Settings / password / Google state are preserved (no folder wipe). ([DataStore](AA/Services/DataStore.cs))
- **`.aaz` bundles** — AA now recognizes the `.aaz` extension everywhere it handles a `.zip` bundle (they're the same ZIP format, so reading is extension-agnostic): the Drive detection (`GetBestRemoteAsync`) and backup-list queries match `*.aaz` anywhere in the Drive, and the *Import data folder*, *Set shared save file* and *Export data folder* dialogs accept/offer `*.aaz`. *(Originally limited to `.aaz` files AA itself created; AA now reads the whole Drive, so hand-placed and iPhone-uploaded `.aaz` bundles are found too.)* ([GoogleDriveUploader](AA/Services/GoogleDriveUploader.cs), [MainWindow](AA/MainWindow.xaml.cs))

### SIRE 2.0 Knowledge Bank tab + quick-add to AA
Integrated the standalone **SIRE 2.0 Knowledge Bank** (the OCIMF tanker-inspection question library) into AA as a new **SIRE 2.0** tab, and added a quick-add bridge that turns any part of it into AA work items.

- **Embedded question bank** — all **410 questions across 12 chapters** ship inside the app ([`Sire/Data/sire2_question_bank.json`](AA/Sire/Data/sire2_question_bank.json), a `<Resource>`), loaded lazily on first tab open ([SireBank](AA/Sire/SireBank.cs)). Offline; no server.
- **Browser** — filter by chapter / vessel type / question type / evidence category / session status, full-text search, and a detail view showing every section (objective, industry & inspection guidance, inspector actions, expected evidence, negative-observation grounds, publications). The detail renders in the **original SIRE styling** ([SireFlow](AA/Sire/SireFlow.cs)): **Segoe UI, no bold** (hierarchy comes from size, colour and the chip backgrounds), PDF bullets preserved as nested lists, and colour-coded section headers (amber Inspector Actions, green Expected Evidence, red Negative-Observation Grounds). The **same document** is serialized (in AA's native `TextRange`/`Section` rich-text format) into the container body on quick-add, so an imported item keeps the font, bullets and highlighting — and actually loads in AA's editor/viewer (an earlier `FlowDocument`-rooted body would not have). ([SirePage](AA/Views/SirePage.xaml.cs))
- **Annotatable question body (insertion-only)** — the detail pane is a live rich-text editor, but **insertion-only**: you can add line breaks and notes anywhere to make an outline clearer, while the **original SIRE text is protected from deletion** (Backspace / Delete / Cut are blocked, a selection can't be typed or pasted over, drag-drop is off; the context menu offers only Copy / Paste / Select-all). Edits are saved **per question** into the AA database (`SireState.QuestionBodies`), so they persist, back up and sync; flushed on question-switch, focus-loss and every autosave/close, with a **↺ Reset** to restore the original generated body. The body renders in normal weight (no bold — forced at the document and control level).
- **Offline task engine** — ported the SIRE `TaskIdentifierService` ([AA/Sire/TaskIdentifierService.cs](AA/Sire/TaskIdentifierService.cs)) so AA regenerates the same actionable tasks the standalone app derives from each question's guidance text — no AI needed (the "check if the generated tasks are there; if not, create them smartly" requirement). ~then surfaced per question and in bulk.
- **Inspection session in the AA database** — per-question status (In Progress / Checked / N/A), bookmarks, for-export tags and tasks are stored in `AppData.Sire` ([SireState](AA/Sire/SireState.cs)), so they **back up and sync** with everything else (no separate `.sire` file needed).
- **Quick-add to AA** (the headline feature) — from any question, section, or chapter, create an AA **Equipment / Task / Procedure** (kind pre-selected from the question's dominant evidence category). The SIRE detail becomes the item's rich-text body; child questions become checklist steps / subtasks / components; and **each offline-identified task is spun off as its own top-level AA Task, cross-linked back to the parent** ([SireToAa](AA/Sire/SireToAa.cs)).
- **AI task suggestions (Gemini)** — optional. Uses **your own** Google Gemini API key (Tools ▸ *Set Gemini API key…*, stored in `settings.json`, never committed). The standalone SIRE repo shipped a **hardcoded** key — AA deliberately does **not** copy it (that key should be revoked). ([GeminiService](AA/Sire/GeminiService.cs))
- **Exports** — all 16 SIRE export modes (checklist, tasks, status report, by-chapter/ROVIQ/vessel, identified tasks, full session report, …) to a `.txt` file or the clipboard, via Tools ▸ *SIRE 2.0 export…* ([SireExport](AA/Sire/SireExport.cs)).

### Data-safety, reminders & housekeeping batch (9 improvements)
A batch of reliability, security and workflow improvements, each verified by the headless harness (83 checks total) and an adversarial multi-agent review.

- **Hardened atomic writes.** [`DataStore.AtomicWrite`](AA/Services/DataStore.cs) now flushes the temp file to disk (`Flush(true)`/fsync) **before** the swap, so a power loss on the vessel can't leave a zero-length file; the swap is `File.Move`-overwrite → `File.Replace` (both atomic) with a byte-copy only as an absolute last resort. A second AA instance polling the shared file every 60s can no longer read a torn file.
- **Schema version + forward-compat.** [`AppData.SchemaVersion`](AA/Models/Models.cs) is stamped on every save; an older build opening a **newer** file warns instead of silently downgrading, and unknown top-level fields are preserved via `[JsonExtensionData]` round-trip. A one-time migration (`DataStore.MigrateSchema`) runs on load for older files.
- **Persistent "shared save OFFLINE" indicator.** The header shows a green *"Shared synced HH:mm"* or a red *"Shared save OFFLINE since HH:mm — retrying"* ([MainWindow](AA/MainWindow.xaml.cs) `UpdateSharedIndicator`). On a VSAT/network drop the folder becomes unreachable and the indicator stays red (not a status line that scrolls away) so you know your edits aren't reaching the bundle yet.
- **Sidebar list virtualization.** The main hierarchy list ([HierarchyPage.xaml](AA/Views/HierarchyPage.xaml)) now sets `VirtualizingPanel.IsVirtualizingWhenGrouping` + recycling, so a grouped list of many items no longer realizes a container per row.
- **More keyboard shortcuts + empty states.** `Ctrl+1…9` switch tabs, `F2` renames the selected item, `Ctrl+Z` undoes the last delete (deferring to the editor's own text-undo when a text/rich-text field has focus), `Esc`/`Ctrl+W` close tool windows. Empty hierarchy pages show a first-run prompt; a filtered-to-nothing search shows "No items match".
- **Undo + soft-delete Trash.** Deleting an Equipment/Task/Procedure/Vessel or crew member now moves it (with its whole subtree) to a **Trash** (File ▸ Trash) instead of vanishing; restore it there or press **Ctrl+Z**. Trashed items are excluded from search/board/calendar, auto-pruned (200 items / 90 days, enforced on load too), and cross-item references are scrubbed only on *permanent* delete so a restore is lossless. ([AppRepository](AA/Services/AppRepository.cs), [TrashWindow](AA/Views/TrashWindow.xaml.cs))
- **Background reminders.** A tray icon raises balloon notifications for overdue / due-today / due-this-week work (deduped so it doesn't nag), a once-a-day **digest** opens the due-dates window on first launch of the day, and that window gained a **"Next 7 days"** section. ([ReminderService](AA/Services/ReminderService.cs), [FloatingTasksWindow](AA/Views/FloatingTasksWindow.xaml.cs))
- **Encrypt-at-rest (DPAPI).** The Google OAuth **refresh token** is now DPAPI-encrypted at rest (auto-migrating an existing plaintext token) via [`DpapiDataStore`](AA/Services/DpapiDataStore.cs). The local **data file** can optionally be DPAPI-encrypted too (File ▸ *Encrypt local data file*) — applied **only** to files inside `%LOCALAPPDATA%\AA`, while shared-save bundles, ZIP exports and Drive backups stay portable plaintext, so cross-PC sync is unaffected. Uses P/Invoke ([`Dpapi`](AA/Services/Dpapi.cs)) — no new dependency.
- **Recurrence made real.** Completing a recurring Task/Procedure now regenerates its **next occurrence** (advanced deadline, reset completion, fresh ids, child deadlines shifted by the same delta), so a monthly fire-drill re-raises instead of dropping off. Idempotent (a `RecurrenceSpawned` flag prevents duplicates); an upgrade migration stamps already-completed recurring items so they don't retro-spawn a backlog. ([AppRepository](AA/Services/AppRepository.cs) `ReconcileRecurrences`)

**Safety addition (data-loss guard):** the previously-dead `DataStore.LastLoadFailed` signal is now honored — if the data file is present but unreadable (locked / corrupt / DPAPI-undecryptable on a foreign account), AA opens in **read-only safe mode** and refuses to save over it (`AppRepository.SuspendSaving`), instead of overwriting the real data with an empty model.

### Non-blocking autosave (fast typing at scale) + per-item re-lock
- **Autosave no longer freezes typing.** The whole model persists to one `data.json`; the debounced autosave used to serialize **and** write it on the UI thread, so with a very large note count a save on each typing pause would hitch. Now the debounce serializes a consistent snapshot on the UI thread (edits are UI-thread, so nothing changes mid-serialize) and writes it to disk on a **background thread** ([AppRepository](AA/Services/AppRepository.cs) `BackgroundSaveIfDirty`; [DataStore](AA/Services/DataStore.cs) split into `SerializeForSave` + `WriteData`). All writes go through one **ordered chain** (`QueueWrite`) so the newest snapshot always lands last — no older write can clobber a newer one. The synchronous `Save()` (used on close / before critical ops) chains its write too and blocks until it's on disk, so nothing is lost on exit. Per-keystroke work stays O(1) (it only resets the debounce). *Note: serialization is still O(model) on the UI thread; for literal hundreds of thousands of notes the next step is externalising note bodies to per-note files so a single edit writes O(note), not the whole model.*
- **Re-lock a single item.** After you unlock a password-protected Equipment/Task/Procedure, a **"🔒 Lock again"** button ([HierarchyPage](AA/Views/HierarchyPage.xaml.cs)) re-gates just that item for the session (`ItemLockService.Relock`) so it needs the password again — without relocking everything.
- Verified in a headless harness — **10/10**: re-lock re-gates one item (master still unlocks after); the async autosave writes correct data off-thread; the synchronous `Save()` persists the newest data; `SerializeForSave` round-trips; and a *failed* write throws, keeps the data dirty, and reverts the stamp (no silent loss). Build **0/0**.
- **Adversarial review** (2 dimensions → verify) confirmed and fixed one **high-severity** regression: the new synchronous `Save()` cleared the dirty flag and reported "Saved" *before* the write finished and swallowed write faults/timeouts — so a failed save (disconnected share, disk full, AV lock) silently lost data and never retried. `Save()` now only clears dirty / fires `Saved` on a **confirmed** write and **throws** on failure (so `DoSave`/`DoAutosave` show their error and the autosave retries), reverting the `LastModified` stamp on failure so it can't push a stale bundle — mirroring the background path.

### Crew roster sort + tabulated table view with Excel export
- **Sort the roster** ([CrewPage](AA/Views/CrewPage.xaml.cs)) by **Sign-off date** (default), **Last name**, **First name**, **CID** (employee id), or **Birth date** — a `SortBox` combo whose choice persists in `UiState.CrewSortMode`. Blank/unparseable keys sink to the bottom.
- **"▦ Table view…"** opens all crew in a separate [CrewTableWindow](AA/Views/CrewTableWindow.xaml) (in the roster's current sort order). There you can:
  - **Pick columns and their order** from the full [CrewColumns](AA/Services/CrewColumns.cs) catalog (~40 fields) — a checkable, ↑/↓-reorderable list drives a dynamic `GridView`.
  - **Set the date format** (ISO `Y-M-D`, `D-M-Y`, `M-D-Y`, `D-Mon-Y`) and the **separator** (`-`, `/`, `.`, …), applied to every date column (unparseable dates fall back to their raw text).
  - **Export to `.xlsx`** — the exact shown columns/order/formatting, via a new dependency-free [XlsxWriter](AA/Services/XlsxWriter.cs) (SpreadsheetML, bold header row; strips XML-illegal control chars so imported data can't corrupt the workbook).
  - Column selection/order + date format + separator persist in `UiState`.
- Verified in a headless harness — **28/28**: cell formatting for every format/separator, CID→employee-id mapping, catalog resolve, the `.xlsx` reopened as a zip with the right headers/formatted dates/bold header, the window's dynamic columns + persistence, and all five roster sort orders. Build **0/0**.
- **Adversarial review** (2 dimensions → verify; 6 raised, 3 refuted) confirmed and fixed three issues: (med) the date **separator** was spliced raw into the .NET format string, so `/` became the *culture's* separator and letters like `m` were interpreted — it's now emitted as a quoted literal and formatted with `InvariantCulture`; (med) the **string sort** modes pushed **blank** last/first/CID keys to the top instead of the bottom — blanks now sink last; (low) only *shown* columns were persisted, so "None" reverted to defaults and hidden columns lost their order — the full column order and the shown-set are now stored separately.

### Containers (per item)
- **Rich text editor** ([Views/ContainerEditor.xaml](AA/Views/ContainerEditor.xaml)):
  - Font family & size selectors
  - Bold / Italic / Underline / Strikethrough
  - Foreground text color and background highlight (color picker)
  - Align left / center / right / justify
  - Bullets, numbering, indent / outdent
  - Undo / Redo
  - Insert hyperlink (opens in default browser)
  - Clear formatting
  - Spell check enabled, no character limit
  - Content stored as serialized FlowDocument XAML for round-tripping
- **File bank** with OneDrive-like UX:
  - Drag-and-drop files or folders directly onto any category tab
  - Add File / Add Folder / Add Link buttons
  - Cut / Copy / Paste / Remove / Open
  - Tabs categorize by kind: **All**, **Documents** (PDF, DOCX, XLSX, PPTX, TXT, RTF...), **Images** (JPG/JPEG, PNG, TIFF, BMP, HEIC, GIF), **Videos** (MOV, MP4, WMV, AVI, MKV, M4V, WEBM), **Links**, **Other**
  - Files are imported into the app's data folder so they stay accessible
  - Double-click to open with the OS default application
- Per-`FileItem` linkage to any hierarchy item id (model field `LinkedItemIds`) — laid out as a structural foundation for cross-linking files to hierarchy items.
- Containers can be explicitly linked to other containers via `SharedWithContainerIds` (model field; access can be extended in UI).

### Hierarchy
Each of Equipment / Tasks / Procedures uses the same generic [Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml) and adds kind-specific UI under a **Specifics** tab.

#### I. Equipment ([Models/Models.cs](AA/Models/Models.cs))
- User creates equipment freely.
- Each equipment has:
  - **Components** (name + notes), editable inline.
  - **Related Procedures** — selecting procedures here automatically pulls in the procedure's sub-hierarchy (steps / linked tasks / equipment) when traversed via `AppRepository.RelatedItems`.
  - **Related Tasks** — explicit links.
  - Its own **Container** (rich text + files).
  - Cross-cutting `RelatedIds` for arbitrary 2-way relationships.

#### II. Tasks
- User creates tasks freely; tasks can also be linked from equipment, procedure steps, etc.
- Each task has:
  - **Subtasks** (recursive `TaskItem` tree).
  - **Deadline** (DatePicker).
  - **Recurrence** — None / Daily / Weekly / Monthly / Yearly.
  - **IsComplete** flag.
  - Container.
- Tasks do **not** automatically relate to sub-hierarchies — per requirement, only direct relationships are recorded.
- All tasks (and subtasks) with deadlines appear in the **Calendar** view.

#### III. Procedures
- User creates procedures freely.
- Each procedure contains:
  - **Checklist steps** (`ChecklistStep`) with a Done checkbox.
  - Each step can link to **tasks** (`TaskIds`) and **equipment** (`EquipmentIds`).
  - Container.

#### IV. Vessels
- User creates an unlimited number of vessels.
- Each vessel has its own **Container** (rich text + file bank) and a **Relationships** tab.
- Any equipment, task, procedure, or checklist step can be related to any vessel (and vice versa) via the shared two-way `RelatedIds` mechanism — vessels appear in every "Add relationship..." picker and in the relationship map.

### Relationships
- Two-way `RelatedIds` between any items, managed via the **Relationships** tab on each item.
- [Services/AppRepository.cs](AA/Services/AppRepository.cs) exposes `AddRelation`, `RemoveRelation`, `RelatedItems`.
- Deletion of an item also cleans up dangling relationship references.

### Relationship Map (2D)
[Views/RelationshipMapPage.xaml](AA/Views/RelationshipMapPage.xaml) renders the selected item at the center of a Canvas with related items on a radial layout. Edges connect the focused node to its neighbors (solid accent line) and dashed muted lines indicate neighbor↔neighbor relationships. Click any node to recenter the map on it. Color-coded by kind:
- Equipment: blue (`#FF4FC3F7`)
- Task: amber (`#FFFFB74D`)
- Procedure: green (`#FFA5D6A7`)

### Calendar / Schedule Matrix
[Views/CalendarPage.xaml](AA/Views/CalendarPage.xaml) shows a Calendar control with view modes:
- **Day** — tasks due that day
- **Week** — tasks due in the selected week
- **Month** — tasks due in the selected month
- **All Upcoming** — all future tasks
- **Agenda** — all upcoming tasks grouped by day (Today / Tomorrow / date headers)

The schedule list has bigger, **wrapped** text with an **A- / A+** size stepper (persisted) and a **Status** column; double-click a row to edit and the **Done** checkbox autosaves. Subtasks are flattened and included. A separate **Board** tab provides a Kanban view of tasks by workflow status. (Full details in the dated update sections below.)

### Persistence
- JSON via `System.Text.Json` in [Services/DataStore.cs](AA/Services/DataStore.cs).
- Auto-saves on every change and on window close. Manual **Save** button in header.

### Save / Load / Autosave
- **Ctrl+S** (and the **Save** button / File ▸ Save menu) writes the full app state immediately.
- **Autosave every 5 minutes** via `DispatcherTimer`; status shows the last autosave time.
- **Save As...** exports the entire data file to any path (File ▸ Save As).
- **Reload from disk** (Load button / File ▸ Reload) re-reads the data file, discarding in-memory changes (with confirmation).
- **Import from file...** replaces current data with a chosen `.json` file and persists it.
- **Open data folder** opens `%LOCALAPPDATA%\AA\` in Explorer.
- All items (Equipment, Tasks, Procedures, components, subtasks, checklist steps, containers, files, relationships) plus full **UI state** (selected main tab, selected item per page, calendar view mode and date, map focus, and window size/position) are saved and restored — the app reopens in exactly the state it was left.

### Styling
- Theme palette (`Bg`, `Panel`, `PanelAlt`, `Accent`, `AccentHover`, `Fg`, `Muted`, `BorderB`, `HoverBg`) defined in [App.xaml](AA/App.xaml) and consumed app-wide via `DynamicResource`, so it can be swapped at runtime (see **Light / Dark theme** below).
- Default (light) palette: white surfaces with black text/accents; the accent style only adds bold emphasis; the selected tab inverts (black bg / white text) for a clear active indicator.
- `Consolas` set globally via `MainFont`.
- Restyled buttons, tabs, text inputs, list views, tree views with consistent rounded corners and hover/selected states.

### Menu bar
- **File** menu: Save, Save As..., Reload from disk, Import from file..., Open data folder, Exit.
- **About** menu (top-level): opens a dialog reading `Created by B.E.P. Avida - May 2026`.

### Performance & stability
- **Debounced save**: [Services/AppRepository.cs](AA/Services/AppRepository.cs) coalesces rapid edits through `MarkDirty()` (~750 ms quiet window) and exposes `IsDirty` / `FlushIfDirty()` / immediate `Save()`. The autosave timer and window-close path flush only when actually dirty, so idle sessions perform zero disk I/O.
- **Debounced rich-text persistence**: the `RichTextBox` in [Views/ContainerEditor.xaml.cs](AA/Views/ContainerEditor.xaml.cs) serializes its FlowDocument ~400 ms after the last keystroke instead of on every character. Switching items, saving, and closing all flush any in-flight edits first via `FlushPending()` / `FlushPendingEditors()`.
- Per-keystroke fields (name, description, deadline, recurrence, completion, file add/remove/paste) use `MarkDirty()` instead of full saves.
- Build: `dotnet build` succeeds with 0 warnings / 0 errors.

### File bank — extras
- Right-click context menu on every file list: **Open**, **Open containing folder** (uses `explorer.exe /select,…`), **Rename...**, **Link to items...**, **Remove**.
- **Link to items...** surfaces the previously-internal `FileItem.LinkedItemIds` model field, letting any file be cross-linked to any Equipment / Task / Procedure.

### PDF export (A4)
- Every item (Equipment / Task / Procedure / Vessel) has an **Export PDF...** button at the top of its details pane.
- Built on **PDFsharp + MigraDoc** ([Services/PdfExporter.cs](AA/Services/PdfExporter.cs)) so MigraDoc handles word-wrap and pagination automatically — text never clips at the page edge and never spills past the printable area.
- A4 portrait, 2 cm margins, running header (kind + name + export date) and footer with "Page X / Y".
- Full hierarchy is rendered intact:
  - Title block (name + kind + description)
  - **Notes** — the container's rich text, including bold/italic/underline runs, bullet lists and line breaks (parsed from the stored FlowDocument).
  - **Kind-specific details**:
    - *Equipment*: components table, then each linked procedure with its full checklist, then each linked task.
    - *Task*: deadline / recurrence / status, plus every subtask summarised inline.
    - *Procedure*: numbered checklist; each step lists its linked equipment and linked tasks.
  - **Relationships** — every related item from `RelatedIds`, **grouped by tab in tab order** (Equipment → Tasks → Procedures → Vessels) and alphabetised within each group.
  - **Attached Files** — table of name / kind / path for every entry in the container's file bank.
- After export, the PDF is opened with the OS default viewer.

### Rich-text paste from the web
- The container's rich text editor now intercepts clipboard paste ([Views/ContainerEditor.xaml.cs](AA/Views/ContainerEditor.xaml.cs)) via `DataObject.AddPastingHandler`.
- When the clipboard contains HTML (e.g. content copied from a web page), the payload is run through [Services/HtmlToXamlConverter.cs](AA/Services/HtmlToXamlConverter.cs) — backed by **HtmlAgilityPack** — which strips the CF_HTML header, drops `<script>` / `<style>` / `<head>` blocks, and recursively converts the HTML tree into a FlowDocument XAML fragment (`Section` → `Paragraph` / `List` / `ListItem` / `Span` / `Run` / `Hyperlink` / `LineBreak`).
- Inline CSS is mapped to FlowDocument attributes (`color`, `background-color`, `font-weight`, `font-style`, `text-decoration`, `font-family`, `font-size`, `text-align`); everything else is dropped, so raw CSS no longer leaks into the document.
- Native Xaml / XamlPackage / Rtf clipboard formats are still handled by WPF itself; only HTML-only payloads are rewritten.

### Per-subtask deadline and container
- Each subtask of a Task is now a fully-fledged `TaskItem` (it already was in the model), and is now editable as such through a dedicated **Subtask editor window** ([Views/SubtaskEditorWindow.xaml](AA/Views/SubtaskEditorWindow.xaml) / [.cs](AA/Views/SubtaskEditorWindow.xaml.cs)).
- The Subtasks list on every Task ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs)) now exposes an **Edit...** button (and a double-click shortcut) that opens the editor with its own Name / Description / Deadline / Recurrence / Completed checkbox, plus an embedded full `ContainerEditor` — so each subtask carries its own rich-text notes and file bank.
- Because the calendar already flattens subtasks, the new per-subtask deadlines automatically appear on the schedule alongside their parent task.

### Data folder export / import and persistent loaded path
- New **File ▸ Export data folder (ZIP)...** and **File ▸ Import data folder (ZIP)...** menu entries ([MainWindow.xaml](AA/MainWindow.xaml) / [.cs](AA/MainWindow.xaml.cs)) round-trip the entire `%LOCALAPPDATA%\AA` folder — including `data.json`, the `files/` bank and `settings.json` — via `System.IO.Compression.ZipFile`. Import wipes the current data folder before extracting, so it's a true drop-in replacement when moving between workstations.
- `DataStore` now tracks a mutable **`CurrentDataFile`** and persists it in `settings.json` ([Services/DataStore.cs](AA/Services/DataStore.cs)). `Load()` / `Save()` always go through the current path.
- **File ▸ Import from file...** now sets the chosen JSON as the active data file and persists the choice via `SetCurrentDataFile`, so re-launching the app reloads the same file automatically. The status bar shows the actual `CurrentDataFile` path.

### Per-component container (Equipment)
- Each `Component` of an Equipment now owns its own full `Container` (rich text + file bank) in addition to the existing one-line `Notes` field ([Models/Models.cs](AA/Models/Models.cs)).
- Components are edited through a dedicated **Component editor window** ([Views/ComponentEditorWindow.xaml](AA/Views/ComponentEditorWindow.xaml) / [.cs](AA/Views/ComponentEditorWindow.xaml.cs)) opened from an **Edit...** button or by double-clicking the row in the Components list — exactly mirroring the subtask UX. The container is therefore only loaded and rendered when the user explicitly opens a component.
- Every container in the app (item, subtask, component) uses the same `ContainerEditor` user control, so they all share identical features: the toolbar, file bank, image previews, link bank, and the new HTML→XAML paste fidelity.
- **Scale**: both the Components and Subtasks `ListView`s now have `VirtualizingPanel.IsVirtualizing=true` with `VirtualizationMode.Recycling` and `ScrollViewer.CanContentScroll=true`, so row cost stays flat even with thousands of entries. Each row only binds the cheap `Name` / `Notes` (or `Name` / `Deadline` / `IsComplete`) properties; the heavy `Container` payload (XAML + files) is never realized in the list and only deserialized into a `FlowDocument` when a single editor window is opened on click.

## Project layout
```
AA/
  AA.csproj
  App.xaml / App.xaml.cs
  MainWindow.xaml / MainWindow.xaml.cs
  Models/
    Models.cs          # Container, FileItem (+LinkInPlace), HierarchyItem, Equipment, TaskItem (+WorkStatus/Status), Procedure, Vessel, ChecklistStep, AppData
  Services/
    DataStore.cs       # Load/Save/ImportFile/ClassifyFile
    AppRepository.cs   # Cross-item lookups & relations
  Views/
    ContainerEditor.xaml(.cs)     # Rich text + file bank
    HierarchyPage.xaml(.cs)       # Generic page used for Equipment/Tasks/Procedures
    CalendarPage.xaml(.cs)        # Calendar + schedule matrix (Day/Week/Month/All/Agenda)
    BoardPage.xaml(.cs)           # Kanban board (status columns, drag-drop)
    RelationshipMapPage.xaml(.cs) # 2D relationship visualization
    PromptWindow.xaml(.cs)        # Simple input modal
    ItemPickerWindow.xaml(.cs)    # Multi-select picker modal
```

## Verification
- `dotnet build` succeeds with 0 warnings, 0 errors on .NET SDK 10 targeting `net10.0-windows`.
- `dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true` produces a portable `publish\AA.exe` (~72 MB) that runs without an installed .NET runtime.
- Smoke-tested: `AA.exe` launches and displays the main window.

## Notes & extension points
- `FileItem.LinkedItemIds` is now editable via the file context menu (**Link to items...**); the storage layer already supported it.
- `Container.SharedWithContainerIds` is present so cross-container file sharing (per requirement: "accessible to that container and to other containers IF explicitly linked") can be surfaced as an aggregated file view; data layer is in place.
- The relationship map is 1-hop with click-through navigation; multi-hop expansion or pan/zoom can be added on top of the existing Canvas.

### Inline task creation auto-linked
- Equipment editor: new `+ New task` button next to `Pick...` in Related Tasks. Prompts for a name, creates a `TaskItem` in the repo, and appends its Id to `eq.TaskIds` so the new task is auto-linked to the current equipment.
- Procedure editor: new `+ New task` button on the checklist step toolbar. Requires a selected step; creates a `TaskItem` and appends its Id to `st.TaskIds` so the new task is auto-linked to the selected checklist step.

### Global highlighted search
- New `Search` button on the top bar (also Ctrl+F).
- `Services/SearchService.cs` scans every text-bearing field across the database: item Name/Description, container plain text (extracted from FlowDocument XAML via XmlReader), container file names/paths, Equipment.Components (Name/Notes/Container/Files), TaskItem.Subtasks recursively, Procedure.Steps titles. Search runs off the UI thread, capped at 500 hits.
- `Views/SearchWindow.xaml(.cs)` shows `[Kind] Name` plus the `Where` location and a 120-char snippet with the matched word highlighted in bold on yellow. Double-click or Enter navigates to the owning hierarchy item (switches tab + selects it).

### Portable attachments / ZIP round-trip
- `FileItem.Path` is now stored relative to the AA data folder (e.g. `files/<guid>_name.ext`). `DataStore.ResolveFilePath` converts to an absolute path at open time. URLs and external absolute paths pass through unchanged.
- `DataStore.NormalizeFilePaths` is called on Load/LoadFrom/Save/SaveTo, rewriting any legacy absolute path that points inside the current AA folder back to relative � old databases auto-migrate on first load.
- `ExportFolderToZip` now stages a temp folder containing `data.json` (the active data file, even if it lives outside AppFolder) plus the `files/` attachments folder, then zips that. The source workstation's `settings.json` (with its absolute CurrentDataFile) is no longer included.
- `ImportFolderFromZip` deletes any imported `settings.json`, resets `CurrentDataFile` to the default in the new AppFolder, then re-saves the data with normalized paths plus a recovery pass that rewrites any remaining `...\\files\\<name>` absolute paths to the new relative ones. Attachments now reconnect after an export ? import on a different machine.

### Inline procedure creation from Equipment
- Equipment editor: new `+ New procedure` button next to `Pick...` in Related Procedures. Prompts for a name, creates a `Procedure` in `_repo.Data.Procedures`, and pushes its Id into `eq.ProcedureIds` so it is auto-linked to the current equipment (mirrors the existing `+ New task` button).

### Task PDF export now includes subtasks + per-subtask notes
- `WriteTaskSpecifics` now calls a recursive `WriteSubtaskDetailed` for each subtask. Output per subtask: `[ ]/[x]` status, name (bold), deadline/recurrence meta in muted italics, plain-text Description, and the full rich-text `Container` notes rendered via the same FlowDocument-to-MigraDoc pipeline used by top-level items. Nested subtasks recurse with a depth-based left indent so the hierarchy is visible in the PDF.
- `WriteContainerBody` gained an optional `leftIndent` parameter (and now skips its heading paragraph when called with `heading: """"`). After it appends paragraphs, every newly added MigraDoc paragraph in the section is shifted to that indent so subtask notes sit visually under their parent subtask.

### Attachment recovery on every Load (foreign ZIP fix)
- `DataStore.NormalizeFilePaths` now handles two cases: (1) rooted path inside the current AppFolder -> rewritten to relative `files/<name>`; (2) foreign absolute path of the form `...\files\<name>` (left behind by a ZIP imported from another workstation) -> rewritten to relative `files/<name>` whenever `<name>` actually exists under the local `files/` folder.
- Because the normalizer runs on every `Load`/`LoadFrom`/`Save`/`SaveTo`, databases that were imported with the previous build (and still carry absolute paths from another user profile) self-heal the next time the app opens them. No re-import is required; attachments resolve and open instead of showing `File not found`.
- `MigrateLegacyAbsolutePaths` is kept inside `ImportFolderFromZip` as a belt-and-braces safety net.

### Equipment renamed to "Equipment/Area" (broader scope)
- The first tab and its corresponding kind label are now **Equipment/Area** everywhere the user sees them: the tab header in [MainWindow.xaml](AA/MainWindow.xaml), the page title and default "New Equipment/Area" name in [Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs), the `+ New task` / `+ New procedure` tooltips ("...auto-link it to this Equipment/Area"), the procedure step `Link equipment/area...` button + picker title ("Pick equipment/area for this step"), and the PDF output ("Equipment/Area Details", "Equipment/Area: " inline label, the running header, the subtitle, and the Relationships group heading).
- The C# `Equipment` class and `ItemKind.Equipment` enum value are unchanged so existing `data.json` files keep loading without migration; only the user-facing label changed via a `KindLabel(ItemKind)` helper in [Services/PdfExporter.cs](AA/Services/PdfExporter.cs).

### Per-step container on every checklist step
- [`ChecklistStep`](AA/Models/Models.cs) now carries its own `Container Container { get; set; } = new();` — identical to the containers on items, components and subtasks (rich-text XAML + file bank + `SharedWithContainerIds`).
- New [Views/ChecklistStepEditorWindow.xaml](AA/Views/ChecklistStepEditorWindow.xaml) / [.cs](AA/Views/ChecklistStepEditorWindow.xaml.cs) mirrors the Component / Subtask editor: title + Done checkbox up top, full `ContainerEditor` filling the rest, and on Close flushes pending rich-text edits + repo save.
- The procedure checklist toolbar in [Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) gained an **Edit...** button and a double-click handler on the steps list, both opening the new editor (matches the Components / Subtasks UX). The steps `ListView` is now virtualized (`IsVirtualizing` + `Recycling` + `CanContentScroll`) so procedures with many steps stay cheap to render — the heavy `Container` payload is only deserialized when a single step editor is opened.
- [Services/SearchService.cs](AA/Services/SearchService.cs) now indexes `step.Container` plain text and its file names alongside the existing `step.Title` so global Ctrl+F finds matches inside step notes too.
- [Services/PdfExporter.cs](AA/Services/PdfExporter.cs) renders each step's container body indented under the step heading (using the existing `WriteContainerBody(..., leftIndent: "0.6cm")` path), so step notes appear inline in the printed checklist.

### PDF export: rich text no longer leaks raw XAML tags
- Bug: the editor persists rich text via `TextRange.Save(DataFormats.Xaml)`, which produces a `<Section xmlns="...">` root — not a `<FlowDocument>`. The previous PDF exporter called `XamlReader.Load`, which silently returned `null` for that root, so the catch path dumped the entire raw XAML string straight into the PDF (the "hundreds of formatting tags" the user observed).
- Fix in [Services/PdfExporter.cs](AA/Services/PdfExporter.cs#L420) `WriteContainerBody`: parse via the inverse of the save call — `new FlowDocument()` + `TextRange.Load(stream, DataFormats.Xaml)`. This round-trips every variant the editor produces (Section, FlowDocument, Span, raw runs) and feeds the existing `RenderBlock`/`RenderInline` pipeline so bold / italic / underline / bullets / hyperlinks survive intact.
- Last-ditch fallback: if even `TextRange.Load` throws, `StripXamlTags` strips everything between angle brackets and HTML-decodes entities, then emits the remaining plain text line-by-line. Raw `<Paragraph FontWeight=...>` style markup can no longer reach the PDF under any code path.

### PDF export: full rich-text fidelity (color, font, size, alignment, hyperlinks)
- [Services/PdfExporter.cs](AA/Services/PdfExporter.cs) now mirrors the on-screen container into the PDF much more faithfully:
  - **Foreground colour** of any `Run` / `Inline` is read from its `Foreground` brush via `TryGetColor` and pushed to MigraDoc's `FormattedText.Color`; a fully-transparent brush (Alpha = 0) is treated as "inherit" so the page default still wins.
  - **Font family** and **font size** of every run are propagated (`source.FontFamily.Source` → `Font.Name`, `source.FontSize` converted px → pt with the standard 0.75 factor).
  - **Paragraph alignment** (`Left` / `Right` / `Center` / `Justify`) maps to MigraDoc `ParagraphAlignment`.
  - **Paragraph background highlight** (`Block.Background` SolidColorBrush) maps to `ParagraphFormat.Shading.Color`, so highlights laid down with the toolbar appear in the PDF.
  - **Bullets vs numbered** lists are now distinguished by reading `List.MarkerStyle` (`Decimal` / `LowerRoman` / `UpperRoman` / `LowerLatin` / `UpperLatin` → numbered, everything else → bulleted).
  - **Hyperlinks** become real MigraDoc `Hyperlink` runs (`HyperlinkType.Web`) instead of plain underlined text, so clickable links survive into the exported PDF.
  - **Strikethrough** runs are visibly decorated (MigraDoc 6.2's `TextFormat` enum has no `Strikethrough` flag, so the renderer falls back to an underline so the decoration is still visible to the reader).

### App-wide container password lock
- New static [Services/PasswordService.cs](AA/Services/PasswordService.cs) holds a per-app password (PBKDF2-SHA256, 100 000 iterations, 16-byte salt). The hash + salt live in `settings.json` via new [Services/DataStore.cs](AA/Services/DataStore.cs) `SavePasswordSettings(hash, salt)`. The unlocked state itself is kept only in memory for the running session and is forgotten on **Tools ▸ Lock now**.
- The container toolbar in [Views/ContainerEditor.xaml](AA/Views/ContainerEditor.xaml) gained two buttons: 🔒 **Lock highlighted text** and 🔓 **Unlock highlighted text**. The lock protects the **currently-selected text** from edits — it does **not** encrypt the document and never alters how content is exported, searched, printed, or rendered. Locked text stays fully visible everywhere; it just can't be modified unless the session is unlocked with the app password.
- Implementation in [Views/ContainerEditor.xaml.cs](AA/Views/ContainerEditor.xaml.cs):
  - The lock marker is a sentinel `Run.Background` brush colour (`#FFFFE699`, pale gold). Because `Background` round-trips through `DataFormats.Xaml` save/load, locked ranges survive autosave, ZIP export/import, and copy/paste without any side-channel storage.
  - `Lock_Click` requires a non-empty selection, ensures the session is unlocked (prompting to set or enter the app password), then calls `Selection.ApplyPropertyValue(TextElement.BackgroundProperty, …)`.
  - `Unlock_Click` requires a non-empty selection, ensures the session is unlocked, then walks the selection and clears the sentinel background from any matching runs (other backgrounds are left untouched).
  - Edit filtering: `Rtb.PreviewKeyDown`, `Rtb.PreviewTextInput`, and a `CommandManager.AddPreviewExecutedHandler` cancel any input or command (typing, Backspace, Delete, Paste, Cut, DeleteWord) that would modify a locked run while the session is locked. Selection, copy, navigation, and Ctrl+F are always allowed. Blocked attempts show a short hint in the status bar (or a system beep) throttled to once every 1.5 s.
- [MainWindow.xaml](AA/MainWindow.xaml) gained a **Tools** menu with **Set / change password...** and **Lock now**. *Lock now* clears the in-memory unlocked flag and re-initializes the hierarchy pages so subsequent edits to any locked text are immediately blocked.
- Back-compat: any legacy container whose `RichTextXaml` was previously whole-document encrypted (`enc:` prefix from earlier builds) is silently decrypted and migrated to plaintext on first load when the session is unlocked, then re-saved.

### Checklist builder window
- New [Views/ChecklistBuilderWindow.xaml](AA/Views/ChecklistBuilderWindow.xaml) (and .cs) offers a focused two-pane experience: on the left a multiline textbox + "Add all" (with **Replace existing** checkbox) for bulk-creating steps from a list of titles; on the right a reorderable ListBox of the procedure's current steps with **+ Step / Edit... / ↑ / ↓ / Delete** buttons. **Edit...** opens the per-step rich-text editor that already existed.
- Opened from a new **Checklist builder...** accent button in the procedure's Specifics tab ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildProcedureSpecifics`). On close the window flushes any pending repo writes.

### Checklist-only export (PDF + Excel)
- New [Services/ChecklistExporter.cs](AA/Services/ChecklistExporter.cs) emits *just* the procedure's checklist — no notes, no relationships, no file bank.
  - **PDF**: A4 portrait via MigraDoc; 4-column table (`# | Done | Step | Linked tasks / equipment`). The Done column shows `[x]` for completed steps and `[ ]` otherwise. Linked tasks are listed as `T: …` and linked equipment as `E/A: …` beneath the step title.
  - **Excel (.xlsx)**: minimal Office Open XML SpreadsheetML zip written directly via `System.IO.Compression.ZipArchive` — no third-party dependency. Columns: `#`, `Done`, `Step`, `Linked Tasks`, `Linked Equipment/Area`. The header row is bold; the Done column says `Yes`/`No` so it round-trips back to a checkbox in Excel filters.
- Surfaced via two new buttons next to **Checklist builder...** in the procedure's Specifics tab: **Export checklist (PDF)** and **Export checklist (Excel)**. Each shows a `SaveFileDialog` (filtering by `.pdf` / `.xlsx`), flushes any pending edits, and opens the resulting file with the OS default handler.

### Sidebar: alphabetical sort + groups
- [Models/Models.cs](AA/Models/Models.cs) gained `HierarchyItem.GroupId` (nullable Guid), an `ItemGroup` class, an `AppData.Groups` collection, and a per-kind `UiState.SortAZ` dictionary so the toggle persists across sessions.
- [Services/AppRepository.cs](AA/Services/AppRepository.cs) added `GroupsFor(ItemKind)` / `CreateGroup` / `RenameGroup` / `DeleteGroup` (which ungroups affected items) / `AssignToGroup`.
- [Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml) gained a sidebar toolbar with a `A→Z` `ToggleButton`, **+ Group**, **Assign group...**, **Rename group...**, **Delete group**. The sidebar `ListBox` now uses `GroupStyle` so items render under collapsible group headers showing the group name and `ItemCount`.
- [Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `RefreshList` now wraps each `HierarchyItem` in a lightweight private `Row` projection that exposes a `GroupKey`, then builds a `ListCollectionView` with `PropertyGroupDescription(nameof(Row.GroupKey))` and a `CustomSort` comparer that orders real groups alphabetically (with the synthetic "Ungrouped" pushed to the end via a `\uFFFF` prefix) and optionally orders items A→Z within each group based on the persisted toggle. Selection-change and `SelectItemById` were updated to unwrap `Row → Row.Item` so the rest of the page keeps working unchanged.
- [Views/ItemPickerWindow.xaml.cs](AA/Views/ItemPickerWindow.xaml.cs) constructor now takes an optional `bool singleSelect = false`; when `true` it switches the ListBox to `SelectionMode.Single` so the group pickers can require a single selection.

## Latest portable build
- `dotnet publish AA/AA.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o publish` produces `publish\AA.exe` (~80 MB, **2026-07-08 build**; bundles the Google Drive API libraries, **ClosedXML** for COMPAS crew import, and **HtmlAgilityPack** for web/Office table paste).
- Self-contained: no .NET runtime required on the target machine. Copy `publish\AA.exe` anywhere and run. (`publish\AA.pdb` is just debug symbols and is not needed to run.)
- Smoke-tested: the single-file exe self-extracts and launches at the login screen; after sign-in (44233 / redemption) the main window opens.

## UX fixes (2026-06-07)
- **Sidebar groups visible even when empty.** Previously, creating a group via `+ Group` appeared to do nothing because `ListCollectionView` hides headers for groups with zero items. `RefreshList` in [Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) now injects a placeholder `Row` for each empty group so the header always renders (with a muted "(empty — right-click an item to assign)" hint). Placeholders are sorted to the bottom of their group, can't be selected as items, and a confirmation message is surfaced in the status bar when a new group is created.
- **Sidebar right-click context menu.** [Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml) now attaches a `ContextMenu` to the items list with **Move to group...**, **Remove from group**, and **New group...** so the grouping feature is discoverable without hunting the toolbar.
- **Checklist Builder is now a prominent banner.** [Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildProcedureSpecifics` renders **🛠  Open Comprehensive Checklist Builder** as a full-width accent button at the top of every Procedure's Specifics tab. The PDF / Excel export buttons sit on the right of the same row.
- **Calendar: wrapped task text, no clipping, double-click to edit + inline done.** [Views/CalendarPage.xaml](AA/Views/CalendarPage.xaml) replaces the old display-only `GridView` columns with `CellTemplate`s that use `TextWrapping="Wrap"` for Task / Deadline / Recurrence and `ListViewItem.HorizontalContentAlignment="Stretch"` so long names occupy multiple lines instead of clipping. The **Done** column is now a real two-way-bound `CheckBox` (autosaves on toggle via `MarkDirty + FlushIfDirty`). Double-clicking any task row opens it in [Views/SubtaskEditorWindow.xaml](AA/Views/SubtaskEditorWindow.xaml) for full editing (the editor works on any `TaskItem`, top-level or nested), then refreshes the grid on close.

## Major update (2026-06-16): in-place file links, Kanban board, calendar views

### Link files in place (network-drive routines) + Open all
The file bank ([Views/ContainerEditor.xaml](AA/Views/ContainerEditor.xaml) / [.cs](AA/Views/ContainerEditor.xaml.cs)) — which every container uses, so **every Task automatically gets it** — can now **reference files where they already live** instead of only importing copies. This is aimed at the daily routine of opening many files spread across a network drive.
- New **🔗 Link in place** button: pick one or more files via `OpenFileDialog`; each is stored with its **original absolute/UNC path** and `FileItem.LinkInPlace = true` — **never copied** into `%LOCALAPPDATA%\AA\files\`. Opening it launches the live file, so edits save straight back to the source on the drive.
- **Drag & drop now supports both modes**: a plain drop imports copies (unchanged); **holding Shift while dropping links the items in place**. A dropped *folder* under Shift becomes a single entry that opens in Explorer (great for "jump to this area of the drive").
- New **Open all** button: opens every file shown in the current file-bank tab at once (confirms past 15) — one click launches a whole routine. Mirrored on the Board (see below) via a per-card **Open all files (routine)** context-menu item.
- The **All** tab gained a **Source** column showing `Live` / `Copy` / `Web link` (`FileItem.SourceLabel`, a `[JsonIgnore]` computed property) so referenced files are obvious at a glance.
- Persistence/portability: [Services/DataStore.cs](AA/Services/DataStore.cs) `NormalizeFilePaths` and `MigrateLegacyAbsolutePaths` now **skip `LinkInPlace` entries** (alongside `IsLink`), so a network path is never rewritten, copied, or broken by a ZIP round-trip. `ResolveFilePath` returns rooted paths verbatim, and `OpenFileItem` accepts files **and folders** (`Directory.Exists`).

### Task workflow status (model)
- [Models/Models.cs](AA/Models/Models.cs) adds `enum WorkStatus { Todo, InProgress, Blocked, Done }` (named `WorkStatus`, not `TaskStatus`, to avoid clashing with `System.Threading.Tasks.TaskStatus`) and a `TaskItem.Status` property.
- `Status` and the existing `IsComplete` **stay in sync both ways**: setting `Done` marks the task complete; any other status clears completion; ticking *Completed* sets `Done`. The setters guard via `Set(...)` returning `false` on no-change, so there is no infinite recursion, and legacy databases (no `Status` field) derive `Done` from `IsComplete` on load.
- `FileItem.LinkInPlace` (bool) marks live references as described above.

### Kanban Board (new top-level tab)
- New [Views/BoardPage.xaml](AA/Views/BoardPage.xaml) / [.cs](AA/Views/BoardPage.xaml.cs), surfaced as a **Board** tab between Calendar and Relationship Map ([MainWindow.xaml](AA/MainWindow.xaml)).
- Four colour-headed columns — **To Do / In Progress / Blocked / Done** — each a `ListBox` of task cards. Cards show the task name (big, **wrapped**), a deadline line (turns red + `OVERDUE` when past due and not done), recurrence, and badges (`📎 N files`, `☑ done/total subtasks`) with a status-coloured left stripe.
- **Drag a card to another column to change its `Status`** (persisted immediately via `MarkDirty + FlushIfDirty`); the threshold/`DoDragDrop` plumbing carries a lightweight private `Card` projection so the underlying `TaskItem` is reached without serialization. Right-click selects the card under the cursor first.
- **Double-click** opens the task in the shared [Views/SubtaskEditorWindow.xaml](AA/Views/SubtaskEditorWindow.xaml). Per-card context menu: **Open / edit task**, **Open all files (routine)**, **Delete task**. Header has a live **Find** filter, a **Hide done** toggle, and **+ New task**. Shows top-level tasks; refreshed on tab switch and after any edit.

### Calendar: more views, bigger + wrapped text
- [Views/CalendarPage.xaml](AA/Views/CalendarPage.xaml) / [.cs](AA/Views/CalendarPage.xaml.cs): the schedule list font is larger (`FontSize=15`) with roomier rows, plus an **A- / A+** stepper that scales the list text and **persists** via new `UiState.CalendarFontScale`.
- New **Agenda** view (5th radio next to Day / Week / Month / All Upcoming): all upcoming tasks **grouped by day** with bold date headers (`Today` / `Tomorrow` / `ddd, yyyy-MM-dd`) and per-group counts, built with a `ListCollectionView` + `PropertyGroupDescription(nameof(TaskItem.Deadline), DateGroupConverter)`. Items remain `TaskItem`, so double-click-to-edit and the inline Done checkbox keep working.
- New **Status** column shows each task's workflow status. The view mode (`"Agenda"` added) and font scale restore on relaunch alongside the existing calendar UI state.

### Status editable everywhere it makes sense
- [Views/SubtaskEditorWindow.xaml](AA/Views/SubtaskEditorWindow.xaml) gained a **Status** dropdown (and the Completed checkbox is relabelled), kept visually in sync with the checkbox.
- The Task **Schedule & Subtasks** specifics tab ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildTaskSpecifics`) gained the same **Status** dropdown next to *Completed*, each updating the other.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**; the app launches and shows the main window.

## Update (2026-06-17): login gate, Google Drive backup, stale-import guard, wrapped lists

### Login screen
- New [Views/LoginWindow.xaml](AA/Views/LoginWindow.xaml) / [.cs](AA/Views/LoginWindow.xaml.cs) is shown **before** the main window. Credentials are **hardcoded** (username `44233`, password `redemption`) per request — *note: this is a basic gate, not real security; the values live in the binary and the local data file is not encrypted by this check.*
- [App.xaml](AA/App.xaml) no longer sets `StartupUri`; [App.xaml.cs](AA/App.xaml.cs) overrides `OnStartup` to run the login modal under `ShutdownMode.OnExplicitShutdown` (so closing the dialog doesn't quit the app prematurely), then creates `MainWindow` and switches to `ShutdownMode.OnMainWindowClose`. A failed/cancelled login calls `Shutdown()`.

### Warn when importing data older than what's saved locally
- [Models/Models.cs](AA/Models/Models.cs): `AppData.LastModified` (nullable `DateTime`) is stamped on every user save by [Services/AppRepository.cs](AA/Services/AppRepository.cs) `Save()` (and on Save As / Export-to-ZIP). `DataStore.Save`/`SaveTo` themselves never stamp, so a timestamp survives import unchanged.
- [Services/DataStore.cs](AA/Services/DataStore.cs) adds `PeekFileLastModified(jsonPath)` and `PeekZipLastModified(zipPath)` — they read just the `LastModified` field via `JsonDocument` (the ZIP variant reads the `data.json` entry **without extracting**).
- [MainWindow.xaml.cs](AA/MainWindow.xaml.cs) `ConfirmNotOlder(...)` is called by **Import from file...** and **Import data folder (ZIP)...** before anything is replaced. If the incoming data is older than (or has no date while the current data does) the loaded data, the user gets an explicit warning with both save dates and must confirm to proceed.

### Save a copy to Google Drive
- Approach: write a timestamped backup ZIP into the **Google Drive for desktop** synced folder (which uploads it to the cloud). This keeps the app a dependency-free, portable single-file exe — no OAuth client/credentials baked in.
- [Services/DataStore.cs](AA/Services/DataStore.cs): `GoogleDriveFolder` (persisted in `settings.json`), `SetGoogleDriveFolder`, and `DetectGoogleDriveFolder()` (checks `%USERPROFILE%\My Drive` / `Google Drive` and each drive root's `My Drive`).
- [MainWindow.xaml](AA/MainWindow.xaml): File ▸ **Save a copy to Google Drive** and **Set Google Drive folder...**. The first resolves the folder (remembered → auto-detected → browse-and-remember), saves the current data, then writes `…\AA Backups\aa-data-<timestamp>.zip` via the existing `ExportFolderToZip`.

### Wrapped text for task / checklist rows
- The Tasks/Equipment/Procedures/Vessels **sidebar** ([Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml)) now uses a wrapping `ItemTemplate` + `HorizontalContentAlignment="Stretch"` (replacing `DisplayMemberPath`), so long names wrap to the panel width instead of clipping.
- The **Subtasks** list and the procedure **Checklist Steps** list ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `WrapColumn` helper) wrap their Name/Title columns. The Subtasks list also gained a **Status** column.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**; the app starts at the login screen and opens the main window after a correct sign-in.

### Direct Google Drive upload (OAuth via the Drive API)
- New [Services/GoogleDriveUploader.cs](AA/Services/GoogleDriveUploader.cs) uploads a backup ZIP **straight to Google Drive** through the Drive API — no Google Drive desktop client required. Uses NuGet **Google.Apis.Drive.v3** + **Google.Apis.Auth** ([AA.csproj](AA/AA.csproj)).
  - OAuth via `GoogleWebAuthorizationBroker.AuthorizeAsync` with the least-privilege `drive.file` scope (the app only ever sees files it creates). The refresh token is cached in `%LOCALAPPDATA%\AA\google-token` (`FileDataStore`) so subsequent uploads don't re-prompt.
  - The user supplies their own OAuth **Desktop app** `client_secret.json` (from Google Cloud Console); it is copied to `%LOCALAPPDATA%\AA\google_client_secret.json` ([Services/DataStore.cs](AA/Services/DataStore.cs) `GoogleClientSecretFile`). Neither the secret nor the token folder is included in `ExportFolderToZip` backups (it only stages `data.json` + `files/`), so they never leak into a backup.
  - Uploads into an **"AA Backups"** Drive folder (found or created), returning the file name + `webViewLink`.
- [MainWindow.xaml](AA/MainWindow.xaml) File menu: **Upload backup to Google Drive (OAuth)...**, **Set Google OAuth client (client_secret.json)...**, **Sign out of Google**. The upload handler ([MainWindow.xaml.cs](AA/MainWindow.xaml.cs), `async`) flushes editors, saves (stamping `LastModified`), exports a temp ZIP, uploads it, then deletes the temp file.
- One-time Google Cloud setup the user must do: create a project, **enable the Google Drive API**, create an **OAuth client ID → Desktop app**, download its `client_secret.json`, and (while the consent screen is in "Testing") add their account as a **test user**.
- This complements the existing **Save a copy to Google Drive (synced folder)** option; both are in the File menu.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

### Load a backup from Google Drive (OAuth) + newer/older check
- [Services/GoogleDriveUploader.cs](AA/Services/GoogleDriveUploader.cs) refactored to share auth via `GetServiceAsync`, and adds:
  - `ListBackupsAsync()` — lists the ZIPs in the Drive **"AA Backups"** folder (newest first); each `DriveBackup` shows its name + Drive upload time. Works under the `drive.file` scope because the app created those files for this account.
  - `DownloadAsync(fileId, destPath)` — downloads a chosen backup to a local temp file.
- [MainWindow.xaml](AA/MainWindow.xaml): File ▸ **Load backup from Google Drive (OAuth)...** ([MainWindow.xaml.cs](AA/MainWindow.xaml.cs), `async`): signs in, lists backups, lets the user pick one (reusing `ItemPickerWindow`), downloads it, then compares ages **before** replacing anything.
  - `ConfirmLoadFromDrive(...)` reads the downloaded ZIP's own `AppData.LastModified` (via `DataStore.PeekZipLastModified`) and the current PC data's `LastModified`, then states plainly whether the Drive backup is **NEWER / OLDER / SAME age** (or unknown when a date is missing) and asks to confirm. On confirm it routes through `ImportFolderFromZip` + `LoadDataAndInitUi`.
- [Services/DataStore.cs](AA/Services/DataStore.cs) `ImportFolderFromZip` now **preserves the Google OAuth client (`google_client_secret.json`) and cached token (`google-token/`)** across the folder wipe, so loading a backup from Drive doesn't sign you out or forget the client.
- Build: clean rebuild succeeds with **0 warnings / 0 errors** (a stale-`obj` WPF markup glitch was cleared with an `obj`/`bin` clean).

### Real-time Google Drive sync (push on save + detect newer across sessions)
- New persisted toggle `DataStore.SyncOnSave` (settings.json) and File ▸ **Sync to Google Drive on save** (checkable) + **Check Google Drive for newer save**.
- **Push on save**: when the toggle is on, every explicit Save (Ctrl+S / Save button / File ▸ Save) schedules a background push to a **single rolling sync file** `AA Sync/AA-sync.zip` on Drive ([MainWindow.xaml.cs](AA/MainWindow.xaml.cs) `MaybeQueueSync` → `RunSyncPush`). Pushes are debounced (~1.5 s) and coalesced (one in flight; the latest re-runs after) and the ZIP is built on a background thread so the UI never blocks. Per-keystroke debounced autosaves do **not** push — only deliberate saves do.
- **Cheap freshness**: [Services/GoogleDriveUploader.cs](AA/Services/GoogleDriveUploader.cs) `PushSyncAsync` overwrites the rolling file (create-or-update) and stamps the data's `LastModified` into Drive **`appProperties`**. `GetSyncStateAsync` reads just that metadata (no download) to tell if the remote is newer.
- **Detect newer from another PC**: `CheckRemoteNewer` runs on **startup** (only when already signed in, so it never pops a browser unprompted), every **autosave tick (~5 min)**, and on demand via the menu. If the remote `LastModified` is newer than local, it asks to load it, then downloads `AA-sync.zip` and routes through `ImportFolderFromZip` + reload. A `_lastSeenRemote` guard prevents re-prompting for a version already declined, and our own pushes set it so we never prompt for our own save.
- Uses the same `drive.file` OAuth scope and the rolling file keeps Drive tidy (no version pile-up; manual timestamped backups still go to the separate **AA Backups** folder).
- Note: the sync ZIP includes attachments (the `files/` folder); link-in-place network files aren't copied so it stays small, but many imported copies make each push larger.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**; app launches at the login screen.

### Change preview before any import/overwrite
- New [Services/DataDiff.cs](AA/Services/DataDiff.cs) `DataDiff.Compare(current, incoming)` diffs two `AppData`s by item Id across Equipment/Tasks/Procedures/Vessels and reports **Added / Removed / Changed**. For changed items it summarizes *what* changed (renamed, description, notes, +N/−N files, deadline/recurrence/status, ±subtasks/components/steps/linked items); added/removed items show a short content summary (files/subtasks/components/steps).
- New [Services/DataStore.cs](AA/Services/DataStore.cs) `PeekZipData(zipPath)` deserializes the incoming `data.json` **without extracting** the ZIP, so the preview works for ZIP/Drive sources too.
- New review dialog [Views/DiffWindow.xaml](AA/Views/DiffWindow.xaml) shows the source, the **newer/older age comparison**, a one-line summary (`＋ add / ～ change / － remove`), and a colour-coded, wrapped list of every change. The user clicks **Import (overwrite)** or **Cancel**.
- **Every overwrite path now routes through it** via `MainWindow.ReviewAndConfirmImport(...)`: File ▸ Import from file, File ▸ Import data folder (ZIP), Load backup from Google Drive (OAuth), and the automatic **sync pull** of a newer Drive save. The old age-only confirmations (`ConfirmNotOlder` / `ConfirmLoadFromDrive`) were replaced by this single richer review.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**; app launches at the login screen.

#### Deeper drill-down preview (tree)
- [Services/DataDiff.cs](AA/Services/DataDiff.cs) was upgraded from a flat list to a **recursive change tree** (`DataDiff.Node`). Each added/removed/changed item expands to show field-level changes with old → new values (name, description, notes snippet, deadline, recurrence, status, component name/notes, step title/done), the specific **files** added/removed, and changed **subtasks / components / steps / linked items** — recursing into nested subtasks.
- [Views/DiffWindow.xaml](AA/Views/DiffWindow.xaml) is now a **TreeView**: top-level item rows start expanded (first level of detail visible); deeper levels expand on demand. Colour-coded ＋ added / ～ changed / － removed.

### Light / Dark theme (sleek dark mode)
- New [Services/ThemeManager.cs](AA/Services/ThemeManager.cs) `Apply(bool dark)` swaps the theme **brush** resources (`Bg`/`Panel`/`PanelAlt`/`Accent`/`AccentHover`/`Fg`/`Muted`/`BorderB`/`HoverBg`) in `Application.Current.Resources` at runtime. Dark inverts white surfaces to a sleek near-black (`#1E1E1E`/`#252526`/`#2D2D30`) with light text (`#F0F0F0`) and white accents; light restores the original white/black palette.
- [App.xaml](AA/App.xaml) control styles were converted from `StaticResource`/hardcoded hex to **`DynamicResource`** theme keys (and a new `HoverBg` key added) so the whole app — windows, buttons, text inputs, lists, trees, tabs — re-themes **live** without a restart.
- Persisted via `DataStore.DarkMode` (settings.json); applied in `App.OnStartup` **before** the login window renders. Toggle at **View ▸ 🌙 Dark mode** ([MainWindow.xaml](AA/MainWindow.xaml)); the choice is remembered across launches.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**; login gate verified intact under the new startup path.

#### Full control theming (dark mode reaches the native controls)
- Follow-up pass so dark mode darkens the previously-light controls and keeps text readable:
  - [App.xaml](AA/App.xaml) gained themed templates/styles for **ComboBox + ComboBoxItem** (custom dropdown, themed popup), **ListBoxItem** and **ListViewItem** (the latter keeps GridView columns via `GridViewRowPresenter`; selection uses readable `SelBg`/`SelFg`), **GridViewColumnHeader**, **ScrollBar** (themed thumb), **PasswordBox**, **ToolTip**, **Menu/Separator**, and best-effort **Calendar / CalendarDayButton / CalendarButton / DatePicker(TextBox)**.
  - New `SelBg` / `SelFg` theme brushes for selection (dark: deep blue / white; light: pale blue / black).
  - [Services/ThemeManager.cs](AA/Services/ThemeManager.cs) now also overrides the **system-colour brushes** (`Window`, `Control`, `Menu`, `Highlight`, `Info`, `GrayText`, …) in dark mode (and removes the overrides in light) so default-templated popups (context menus, calendar/date-picker popups, tooltips, selection) follow the theme too.
  - [Views/CalendarPage.xaml](AA/Views/CalendarPage.xaml) inline `ListViewItem` style now `BasedOn` the themed one, and the local light header style was removed so calendar rows/headers darken.
- Verified by scripted login + runtime toggle: the main window renders under the new templates and switching to dark live does not crash; the setting persists.
- Residual: a few deeply OS-drawn chrome bits (e.g. native scrollbar arrows, the exact calendar-grid cell background) may not be pixel-perfect dark, but backgrounds are dark and text is light/readable throughout.

## Update (2026-06-18): export indentation, Jobs + Planner, dark-mode readability

### PDF export — indentation preserved as-is
- [Services/PdfExporter.cs](AA/Services/PdfExporter.cs) `ApplyParagraphFormat` now treats a **positive `TextIndent`** (how WPF's Indent button may record a shift) as a **whole-paragraph** left indent — summed with `Margin.Left` — and a negative `TextIndent` as a hanging first-line indent. Previously a button-indent stored on `TextIndent` only moved the first line in the PDF.
- `RenderBlock` carries a per-level indent so **nested bullets/numbers compound their indentation** (each level +0.6 cm with a hanging marker), matching the editor's visual nesting.

### Jobs (approximate duration) + Planner (drag-drop scheduler)
- [Models/Models.cs](AA/Models/Models.cs): new `IJob` interface (`IsJob`, `DurationMinutes`, `ScheduledStart`, `JobName`) implemented by **`TaskItem`** (top-level tasks and subtasks) and **`ChecklistStep`**. Any of them can be tagged a **Job** with an approximate duration (minutes).
- Tagging UI (checkbox + duration) added to the task editor ([Views/SubtaskEditorWindow.xaml](AA/Views/SubtaskEditorWindow.xaml)), the checklist-step editor ([Views/ChecklistStepEditorWindow.xaml](AA/Views/ChecklistStepEditorWindow.xaml)), and the Task **Specifics** panel ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs)).
- The **Procedures tab** checklist list also gained a **Job** checkbox column (next to Done) so steps can be marked as jobs inline without opening each step editor; toggling persists immediately (duration is still set in the step editor). The inline Done checkbox now persists on toggle too.
- The **whole procedure** can also be tagged as a Job: `Procedure` now implements `IJob` ([Models/Models.cs](AA/Models/Models.cs)), the Procedure **Specifics** panel has a "Mark this procedure as a schedulable job" checkbox + duration at the top ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs)), and `AppRepository.AllJobs()` includes procedure-level jobs so they appear in the Planner alongside task/subtask/step jobs.

### Folder Builder (bulk-create a folder structure on disk)
- New **Tools ▸ Folder builder...** ([Views/FolderBuilderWindow.xaml](AA/Views/FolderBuilderWindow.xaml) / [.cs](AA/Views/FolderBuilderWindow.xaml.cs)), modelled on the Checklist Builder: a two-pane window with a **base-location picker** (Browse..., remembered in settings via `DataStore.FolderBuilderBase`), a left **bulk text box** (one folder name per line) and a right **live preview tree**.
- **Nesting**: indent a line with a Tab or 2 spaces to make it a subfolder of the line above; a line may also contain `/` or `\` to create a nested path directly. Names are sanitized (invalid filename characters → `_`).
- **Create folders** parses the text into a parent-before-child list of relative paths and `Directory.CreateDirectory`s each under the base location (confirming first; reporting created / already-existed / failed counts; offering to open the base folder). Intermediate folders are created automatically.
- Verified end-to-end via UI Automation: typing an indented/`/`-pathed list and invoking Create produced the exact nested folder tree on disk.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

### Per-vessel Quick Cards dashboard (first screen for each ship)
- Each **Vessel** now opens on a **Quick Cards** tab (the first tab, auto-selected when a vessel is picked) — [Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml) gained a `QuickCardsTab` shown only for vessels; [HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) loads it and fronts it on selection. Each ship has its own independent layout.
- [Models/Models.cs](AA/Models/Models.cs): `QuickCard` (Title, Target, IsLink/LinkInPlace/IsFolder, Icon, Color, X/Y/Width/Height) and `Vessel.QuickCards`.
- [Views/QuickCardsPanel.xaml](AA/Views/QuickCardsPanel.xaml) / [.cs](AA/Views/QuickCardsPanel.xaml.cs): a free-form **Canvas** of cards. Each card can be **dragged to move** and **resized via a bottom-right grip**; double-click (or right-click ▸ Open) launches its target; right-click also offers Edit / Duplicate / Delete. Every move/resize/edit persists immediately (`MarkDirty + FlushIfDirty`), so the layout is saved per vessel.
- [Views/QuickCardEditorWindow.xaml](AA/Views/QuickCardEditorWindow.xaml) / [.cs](AA/Views/QuickCardEditorWindow.xaml.cs): set the card's **target** — *Link file (in place)* on a network/other drive, *Import a copy*, *Link folder*, or *Web link* — plus a **maritime icon** picker, a **colour** palette (+ custom colour), size, and a live preview.
- [Services/MaritimeIcons.cs](AA/Services/MaritimeIcons.cs): a curated set of ~50 common ship-operations icons (anchor, helm, lifebuoy, compass, engine, fuel, fire, radar, cargo, reefer, medical, …), a preset colour palette, and a readable-foreground (black/white) calculation so titles/icons stay legible on any card colour.
- Targets reuse the existing file plumbing: imported copies go through `DataStore.ImportFile` (relative `files/…`, resolved at open time and included in ZIP backups); in-place links store the original absolute/UNC path; web links open in the browser.
- Verified end-to-end via UI Automation: created a vessel, confirmed Quick Cards is the front tab, added a card through the editor, and confirmed it persisted (title + icon + colour) to the data file.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

### Date calculator (Tools)
- New **Tools ▸ Date calculator...** ([Views/DateCalculatorWindow.xaml](AA/Views/DateCalculatorWindow.xaml) / [.cs](AA/Views/DateCalculatorWindow.xaml.cs)) — a small live-updating utility with two sections:
  1. **Difference between two dates** — From / To pickers compute the total days (with an optional *inclusive* checkbox that counts the end date), an approximate weeks + days breakdown, and an exact years / months / days breakdown (handles To-before-From).
  2. **Add / subtract from a date** — a base date, an Add/Subtract selector, an amount, and a unit (Days / Weeks / Months / Years) produce the resulting date with its weekday and the net day offset.
- Wired into the Tools menu ([MainWindow.xaml](AA/MainWindow.xaml) / [.cs](AA/MainWindow.xaml.cs)). Build is clean; the date math is deterministic (`DateTime` arithmetic). Live GUI run was skipped this session to avoid keyboard automation interfering with the user's open applications.

### Strikethrough on completed checklist items / tasks
- New [Views/Converters.cs](AA/Views/Converters.cs) `BoolToStrikethroughConverter` (registered in [App.xaml](AA/App.xaml) as `BoolToStrike`): true → `TextDecorations.Strikethrough`, false → none.
- Marking an item **done now strikes its whole text through, live** (the `Done` / `IsComplete` model properties raise `PropertyChanged`, so the bound decoration updates the instant the checkbox is toggled):
  - Procedure **checklist steps** (Title column) and the **Checklist Builder** list — keyed on `ChecklistStep.Done`.
  - **Subtasks** list (Name column), the **Calendar** schedule list (Task column), and the **Board** cards — keyed on `TaskItem.IsComplete`.
- A `StrikeWrapColumn` helper in [Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) adds the decoration to the code-built GridView columns; the XAML lists use `{Binding Done|IsComplete, Converter={StaticResource BoolToStrike}}`.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.
- [Services/AppRepository.cs](AA/Services/AppRepository.cs) `AllJobs()` enumerates every tagged Job across tasks/subtasks/steps.
- New **Planner** tab ([Views/PlannerPage.xaml](AA/Views/PlannerPage.xaml) / [.cs](AA/Views/PlannerPage.xaml.cs)), between Board and Relationship Map:
  - **Unscheduled Jobs** side list of tagged jobs with no start time.
  - **Day / Week / Month** views with prev/today/next navigation.
  - Day/Week render an hourly time grid; each scheduled job is a **block sized by its duration**, and overlapping jobs in a day are split into side-by-side columns (interval-cluster layout) so they don't cover each other.
  - **Drag-and-drop**: drag a job from the side list onto the grid to schedule it (drop position snaps to 15-minute steps → sets `ScheduledStart`); drag a block to another time/day to reschedule; drag a block back to the side list to unschedule. Month view drags set the date (keeping time-of-day). Double-click any job opens its editor. Every change persists via `MarkDirty + FlushIfDirty`.
- Wired in [MainWindow.xaml](AA/MainWindow.xaml) (tab + init + refresh-on-select). Verified by scripted login: the Planner builds at startup and tab navigation doesn't crash.

### Dark-mode readability fixes
- **Container rich text**: the document editing surface now uses fixed **light "paper" brushes** (`EditorBg` / `EditorFg` in [App.xaml](AA/App.xaml)) in *both* themes, so every text colour and highlight the user applied stays readable; the toolbar/file-bank/chrome still follow the theme. `ClearFormat` resets to `EditorFg` (not the themed `Fg`, which is light in dark mode). ([Views/ContainerEditor.xaml](AA/Views/ContainerEditor.xaml) / [.cs](AA/Views/ContainerEditor.xaml.cs))
- **Menus**: a full **`MenuItem`** template (top-level + submenu, with checkmark, highlight, gesture text, submenu arrow) and a **`ContextMenu`** template were added so menu popups are dark with white text in dark mode (replacing reliance on the system-colour overrides alone). Verified by scripted open-menu in both themes.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

### Deep, drill-down change preview
- [Services/DataDiff.cs](AA/Services/DataDiff.cs) now produces a **recursive `Node` tree** instead of flat one-liners. Each added/removed/changed top-level item expands to show, recursively:
  - **Field changes with old → new values**: name, description (snippet), notes (plain-text snippet extracted from the FlowDocument XAML), and per-kind fields — Task `deadline`/`recurrence`/`status`, Component `name`/`notes`, Step `title`/`done`.
  - **Files** added/removed by name (per container, including component/step containers).
  - **Children** added/removed/changed by name and recursed into: Task **subtasks** (fully recursive), Equipment **components** + **linked procedures/tasks**, Procedure **steps** + per-step **linked tasks/equipment**. Added/removed items list their full contents so you see exactly what's coming in or being lost.
- [Views/DiffWindow.xaml](AA/Views/DiffWindow.xaml) is now a **`TreeView`**: colour-coded (green ＋ / amber ～ / red －) expandable nodes; top-level items start expanded (first level of detail visible), deeper levels expand on click. Linked-item changes resolve to names via a combined current+incoming lookup.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**; app launches at the login screen.

## Update (2026-07-03): per-entry password locks + COMPAS crew import & contract-expiry tracking

### Per-entry password lock (custom password + hint; master password always "redemption")
Any **Equipment/Area, Task, Procedure or Vessel** can now be individually password-locked — separate from the existing app-wide *container* text lock.
- [Models/Models.cs](AA/Models/Models.cs): `HierarchyItem` gained `LockHash` / `LockSalt` / `LockHint` and a computed `IsLockProtected`. The password is stored **only as a PBKDF2-SHA256 hash** (never plaintext); the optional **hint** is shown on request on the lock screen.
- New [Services/ItemLockService.cs](AA/Services/ItemLockService.cs): `Protect` / `RemoveProtection` / `Verify` / `TryUnlock` / `IsGated` / `RelockAll`. The app **master password `redemption` always unlocks** any entry. Which entries have been unlocked is kept **only in memory for the session** (forgotten on relaunch and on **Tools ▸ Lock now**), so locked entries are gated again next launch. **Setting a lock takes effect immediately** — `Protect` gates the entry at once, so the padlock replaces the body the moment you lock it (no relaunch needed).
- New [Views/ItemLockWindow.xaml](AA/Views/ItemLockWindow.xaml)(.cs): set/change dialog (password + confirm + optional hint).
- [Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml)(.cs): a **🔒 Lock / 🔓 Locked** button in each entry's header (set, change password/hint, or remove the lock), and a full **lock overlay** that gates the entry when it's locked and not unlocked this session. The gate hides **both** the details tabs (Container / Relationships / Specifics / Quick Cards) **and** the Name/Description header, so nothing is viewable or editable until unlocked; the overlay offers **Show hint** and an **Unlock** box. Deleting and **Export PDF** are both blocked while gated so the lock can't be bypassed.
- **Global search respects the lock**: [Services/SearchService.cs](AA/Services/SearchService.cs) takes the set of locked/gated item ids (snapshotted on the UI thread by [Views/SearchWindow.xaml.cs](AA/Views/SearchWindow.xaml.cs) before the background scan) and, for a locked entry, indexes **only its Name** — its description, notes, files and child content (components / subtasks / steps) are omitted, so Ctrl+F can't leak locked content via result snippets. Navigating to a locked hit just opens it on the lock screen. Verified by a 10-assertion harness.
- [MainWindow.xaml.cs](AA/MainWindow.xaml.cs) **Tools ▸ Lock now** also calls `ItemLockService.RelockAll()` and then `HierarchyPage.RelockCurrent()` on each page, which re-applies the gate to the current selection **in place** (selection preserved) so an open locked entry immediately shows its padlock.
- Verified by a 17-assertion harness: master password, own password, wrong/empty rejection, session re-lock, and that the stored hash round-trips through JSON without ever containing the plaintext.

### Import COMPAS crew reports → crew cards, with contract-expiry tracking & notification
A new **Crew** tab (and **Tools ▸ Import COMPAS crew (.xlsx)...**) imports a COMPAS report and keeps every crew member as an info card. Schema/mapping logic is ported from the CrewBridge project.
- New [Services/CompasReader.cs](AA/Services/CompasReader.cs) (via **ClosedXML**, added to [AA.csproj](AA/AA.csproj)) reads the `report` sheet **by column header** (resilient to column reordering); [Services/CrewConverter.cs](AA/Services/CrewConverter.cs) + [Services/CrewMapping.cs](AA/Services/CrewMapping.cs) translate rank codes, nationality (ISO-3/demonym), ports → UN/LOCODE, gender and dates, lift the middle name out of the `Name` field, split next-of-kin, and raise colour-coded **review notes** for anything guessed or missing (nothing is silently invented).
- [Models/CrewMember.cs](AA/Models/CrewMember.cs): the full DNV-shaped record **plus the COMPAS `Sign Off Date` and `SignOff Port`** and the `Last Vessel`. Crew are stored in `AppData.Crew` (System.Text.Json), so they ride along with every Save, ZIP backup and Google-Drive sync. Re-importing **upserts by employee id** (updates existing members).
- **Contract-expiry tracking** keys off each member's **sign-off date**: `DaysUntilSignOff` / `ContractStatusOn` bucket into **Expired / Critical (≤30d) / Due-soon (≤60d) / OK**.
- [Views/CrewPage.xaml](AA/Views/CrewPage.xaml)(.cs): a roster (search + "expiring only" filter, soonest-expiring first, colour-coded expiry line per member) beside a full **info card** (Identity, Employment & Sign-On/Sign-Off, Travel Documents, Certificates & Medical, Physical, Next of Kin) with a prominent **CONTRACT** banner and the member's review notes.
- **Notification**: on startup (and after each import) the app pops a summary of any crew whose contract is **overdue or due within 60 days**; the **Crew tab shows a ⚠ badge** with that count; **Tools ▸ Check crew contract expiries** (and a roster button) list them on demand.
- Verified end-to-end against a real COMPAS export (`E:\Crew\COMPAS.xlsx`): all 29 crew parsed with sign-off dates/ports, vessel, and correct Expired/Critical/Due-soon buckets.

### Review
- Both features' pure logic was validated by standalone harnesses; the WPF wiring was then put through an adversarial multi-agent review, which caught (and the fix closed) a partial lock bypass where the header Name/Description stayed editable behind the overlay.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

## Update (2026-07-04): Shippalm PMS import (per ship), editable crew cards, procedure deadlines, floating due-dates window

### Per-ship Shippalm work-order import + per-job notification choice
Each **Vessel** now owns its own **Shippalm PMS** data — the import and the notify settings live inside the ship.
- [Models/Models.cs](AA/Models/Models.cs): `Vessel.Jobs` (`ObservableCollection<ShipJob>`) and the new **`ShipJob`** (keyed by `JobNo` — the Shippalm "No.", e.g. `ARA.22.3120`) with Title, Work Plan No., Status, Class/Category, Responsible Rank, Function, **Interval** (`64,000 H` / `60M`), Due Status, **Due Date**, Last Done, Overdue Days, and a **`Notify`** flag (the per-job choice of whether it raises notifications).
- New [Services/ShippalmReader.cs](AA/Services/ShippalmReader.cs) (via **ClosedXML**) reads a "Work Order List" export **by column header** (resilient to reordering) and converts **Excel date serials** (e.g. `48108` → `2031-09-17`) to `yyyy-MM-dd`. Verified against a real export: **2524 jobs**, all due-dates parsed, no duplicate job numbers.
- New [Views/ShipJobsPanel.xaml](AA/Views/ShipJobsPanel.xaml)(.cs) is a vessel-only **Work Orders** tab: **Import Shippalm (.xlsx)...** (runs off the UI thread with a wait cursor; **upserts by job number**, preserving each job's Notify choice on re-import), a search box, a **status filter**, **Due/overdue-only** and **Notify-on-only** toggles, per-row **Notify** checkboxes plus **Notify: shown ON/OFF** bulk buttons (so you choose which recurring jobs notify), and a live **analysis** line (total · overdue · due ≤30d · due ≤90d · notify-on · by-category), with colour-coded due status per row.
- The Work Orders tab shows only for vessels ([Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml)); it's loaded alongside Quick Cards when a vessel is selected.

### Editable crew cards (accidental-edit-proof)
- The crew info card stays **read-only**; a new **✎ Edit...** button opens a modal [Views/CrewEditorWindow.xaml](AA/Views/CrewEditorWindow.xaml)(.cs) that edits **every** field — dates (including the emphasised **Sign-off / contract date**) via a calendar picker kept in sync with a text box, everything else via text boxes. Nothing can be changed by accident (edits only happen through the explicit dialog + Save); Cancel discards. On Save the contract expiry, roster colours and Crew-tab badge all recompute ([Views/CrewPage.xaml.cs](AA/Views/CrewPage.xaml.cs) `EditCrew`).

### Procedure deadlines
- [Models/Models.cs](AA/Models/Models.cs): `Procedure.Deadline` (`DateTime?`), parallel to a Task's. A **Deadline** DatePicker was added to the top of the Procedure **Specifics** tab ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildProcedureSpecifics`). Procedure deadlines surface in the floating due-dates window (below).

### Floating due-dates window (today & tomorrow)
- New [Views/FloatingTasksWindow.xaml](AA/Views/FloatingTasksWindow.xaml)(.cs): a small **always-on-top**, draggable, rounded window with a gradient header that lists everything due **today** and **tomorrow** — top-level **tasks** and **subtasks** (by deadline, incomplete only), **procedures** (by their new deadline), and **notify-enabled Shippalm work orders** (overdue ones surface under Today) — each as a colour-coded row (click a task/procedure/vessel row to navigate to it). It stays live by refreshing on every save.
- Opened from a **📌 Due** header button or **Tools ▸ Floating due-dates window** ([MainWindow.xaml](AA/MainWindow.xaml)(.cs)); a single instance is kept and re-pointed at the current data after a reload/import.

### Review
- The four features were put through an adversarial multi-agent review; the one confirmed finding (the Work Orders list not re-running its filter when a job's **Notify** was toggled under the "Notify on only" filter, leaving stale rows / count) was fixed by rebuilding the view on notify changes. A tab-index shift from adding the Work Orders tab (which had mis-selected the Container tab for non-vessels) was also caught and fixed (Container tab now selected by name).
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

### Follow-up (2026-07-04): per-vessel export + notifications kept inside the vessel tab
- **Export per vessel**: the Work Orders tab gained an **Export (.xlsx)...** button ([Views/ShipJobsPanel.xaml](AA/Views/ShipJobsPanel.xaml)) that writes THIS ship's work orders — including each job's **Notify** choice — to an .xlsx via [Services/ShippalmReader.cs](AA/Services/ShippalmReader.cs) `Write`, using the same headers `Read` expects so it **round-trips** back into any ship. `Read` now also picks up a `Notify` column when present (raw Shippalm exports don't have one; AA's exports do). Verified by a 9-check round-trip harness against the real 2524-row file.
- **Notifications stay inside the vessel tab**: Shippalm work-order notifications were removed from the global floating due-dates window ([Views/FloatingTasksWindow.xaml.cs](AA/Views/FloatingTasksWindow.xaml.cs) — it now shows only tasks/subtasks/procedures). Each vessel's Work Orders tab now has its own **🔔 Notifications** bar summarising that ship's flagged jobs that are overdue / due ≤30d (colour-coded), so notifications never leak across ships.
- **On/off switch per ship**: `Vessel.NotificationsEnabled` ([Models/Models.cs](AA/Models/Models.cs), defaults on) is toggled by the notifications bar's checkbox; when off, that ship shows no work-order notifications regardless of individual Notify flags.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

### Performance pass for large imports (2026-07-04)
Tuned for ships carrying thousands of Shippalm work orders (measured with the real 2524-row export):
- **Compact data file**: [Services/DataStore.cs](AA/Services/DataStore.cs) now serializes `data.json` **without indentation**. Measured on one ship of 2524 jobs: each save **108 ms → 21 ms (~5× faster)** and the file **1.66 MB → 1.07 MB (~35% smaller)** — every autosave, manual save, Drive sync and reload benefits. Parsing is unaffected.
- **O(n) re-import**: the Work Orders upsert ([Views/ShipJobsPanel.xaml.cs](AA/Views/ShipJobsPanel.xaml.cs)) replaced an O(n²) `ObservableCollection.IndexOf`-per-row with a dictionary + `ShipJob.CopyFrom` in-place update ([Models/Models.cs](AA/Models/Models.cs)). Re-importing all 2524 jobs now takes **~3 ms** (was hundreds of ms) with no duplicates and notify choices preserved.
- **Debounced search**: the Work Orders search box debounces (200 ms) so typing doesn't re-filter/rebuild thousands of rows on every keystroke.
- **No full-save on every checkbox**: per-row **Notify** toggles now use the debounced save (save-on-pause) instead of writing the whole data file on each click, so bulk-flagging jobs stays smooth.
- Still in place: the work-order list is **UI-virtualized** (recycling), and the (ClosedXML) import runs **off the UI thread** with a wait cursor — first import ~2–3 s cold, ~1 s warm, with the window responsive throughout.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

## Update (2026-07-04): checklist steps act like subtasks (per-step deadlines)
Each procedure **checklist step** can now carry its own **deadline**, so it behaves like a task subtask.
- [Models/Models.cs](AA/Models/Models.cs): `ChecklistStep.Deadline` (`DateTime?`).
- **Set it** in the step editor's new **Deadline** picker ([Views/ChecklistStepEditorWindow.xaml](AA/Views/ChecklistStepEditorWindow.xaml)); the procedure's checklist list gained a read-only **Deadline** column ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildProcedureSpecifics`), edited via the step editor (double-click) exactly like a subtask's deadline.
- **Calendar**: [Views/CalendarPage.xaml.cs](AA/Views/CalendarPage.xaml.cs) was refactored onto a uniform `ScheduleRow` wrapper (same XAML binding names, no XAML change) so dated **checklist steps appear alongside tasks and subtasks** in every view (Day/Week/Month/All/Agenda); double-click opens the step editor, and ticking Done writes back and live-updates the strike-through **and** the Status cell.
- **Floating due-dates window** ([Views/FloatingTasksWindow.xaml.cs](AA/Views/FloatingTasksWindow.xaml.cs)) now lists dated, not-done checklist steps due today/tomorrow (labelled "Checklist step · <procedure>").
- **Exports**: the checklist PDF/Excel ([Services/ChecklistExporter.cs](AA/Services/ChecklistExporter.cs)) gained a **Due** column, and the full procedure PDF ([Services/PdfExporter.cs](AA/Services/PdfExporter.cs)) appends "(due …)" to each step.
- Reviewed by a multi-agent pass; the one confirmed finding (Calendar Status cell going stale after a Done toggle) was fixed by making `ScheduleRow.Status` read the live underlying state and notify on toggle.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

## Update (2026-07-04): comprehensive subtask builder + procedure recurrence/status
- **Comprehensive Subtask Builder (Tasks)**: new [Views/SubtaskBuilderWindow.xaml](AA/Views/SubtaskBuilderWindow.xaml)(.cs) mirrors the procedure Checklist builder but for a task's **subtasks** — bulk entry (one per line, optional "replace existing"), **+ Subtask**, **Insert before/after**, **Edit...** (opens the full subtask editor: deadline / recurrence / status / notes / files), **↑/↓** reorder, **Move to...** (top / bottom / before another), **Delete**, and double-click to edit. Opened from a prominent **🛠 Open Comprehensive Subtask Builder** accent button at the top of the Task's **Specifics** tab ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildTaskSpecifics`). The builder mutates the same `ObservableCollection` the Specifics subtasks list is bound to, so both stay in sync automatically.
- **Procedure recurrence + status**: [Models/Models.cs](AA/Models/Models.cs) `Procedure` gained `Recurrence` (RecurrenceKind) and `Status` (WorkStatus) — the same vocabularies Tasks use. Both surface as dropdowns at the top of the Procedure **Specifics** tab ([Views/HierarchyPage.xaml.cs](AA/Views/HierarchyPage.xaml.cs) `BuildProcedureSpecifics`), next to the procedure's deadline / job tagging.
- Reviewed by a multi-agent adversarial pass with **0 confirmed findings**.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

## Update (2026-07-06): procedures on the calendar, scheduled jobs in the floating window, resizeable floating window, planner search
- **Procedures on the Calendar**: [Views/CalendarPage.xaml.cs](AA/Views/CalendarPage.xaml.cs) now also lists any **Procedure with a deadline** (via `ScheduleRow.ForProcedure`) across Day/Week/Month/All/Agenda. Its Done checkbox maps to the procedure's new `Status` (Done⇄Todo, live-updating the Status cell); double-clicking a procedure row **navigates** to it in the Procedures tab (a navigator callback is now passed via `CalendarPg.Init(_repo, NavigateToItem)`).
- **Scheduled jobs show in the floating window**: [Views/FloatingTasksWindow.xaml.cs](AA/Views/FloatingTasksWindow.xaml.cs) `Collect` now also adds any Planner **scheduled job** (`IJob.ScheduledStart`) starting today/tomorrow (🕒 with its time), so a job you drop onto today's grid appears here too. Deduped by Id against deadline entries (an item due *and* scheduled the same day shows once), and completed jobs are skipped. Checklist-step jobs resolve their owning procedure for navigation.
- **Floating window is resizeable**: [Views/FloatingTasksWindow.xaml](AA/Views/FloatingTasksWindow.xaml) `ResizeMode=CanResize` with `MinWidth`/`MinHeight`, plus an explicit **resize grip** in the bottom-right corner (borderless+transparent windows have thin edges) that resizes via `Thumb.DragDelta`.
- **Planner job search**: [Views/PlannerPage.xaml](AA/Views/PlannerPage.xaml) gained a **Search jobs...** box over the Unscheduled Jobs list; [Views/PlannerPage.xaml.cs](AA/Views/PlannerPage.xaml.cs) filters the schedulable-jobs list by name (case-insensitive) as you type.
- Reviewed by a multi-agent adversarial pass with **0 confirmed findings**.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

## Update (2026-07-06): startup loading screen (splash)
- New [Views/SplashWindow.xaml](AA/Views/SplashWindow.xaml)(.cs): a borderless, centered, always-on-top loading screen shown at startup. It displays the bundled splash photo (`Assets/Splash.png`, added as a WPF `<Resource>` in [AA.csproj](AA/AA.csproj)); if that resource is ever missing it falls back to a simple "AA + tagline" text screen so the app still runs.
- [App.xaml.cs](AA/App.xaml.cs) `OnStartup` now shows the splash first, then after ~2.4 s (a `DispatcherTimer`) closes it and continues to the login → main window (`ContinueToMain`). Shown on **every launch**.
- Verified: Debug build launches and holds at the login screen after the splash; the published single-file exe's app process runs past the splash. Portable exe republished (~76.5 MB).

## Update (2026-07-06): single shared save file (multi-instance auto-sync, data + attachments)
A "one save file at a location of your choice" that every copy of AA keeps in sync — **including attachments**.
- **File ▸ Set shared save file...** / **Stop shared save file** ([MainWindow.xaml](AA/MainWindow.xaml)): choose one **.zip bundle** on a network drive or synced folder. `DataStore.SharedSaveFile` is persisted ([Services/DataStore.cs](AA/Services/DataStore.cs)); it's a sync target, so the app still works from its fast local data file.
- **Bundles data AND attachments**: the shared file is a ZIP of `data.json` + the `files/` folder (via the existing `ExportFolderToZip`). New [Services/DataStore.cs](AA/Services/DataStore.cs) `ImportSharedBundle` pulls a bundle back in — bringing in its attachments first, switching the data index, then removing orphans — WITHOUT wiping settings/password (unlike the full ZIP import).
- **Saves every 10 minutes** (reconcile-first, then only if changed) and on close (only if we're not older than the bundle). Writes are **atomic** — `DataStore.Save`/`SaveTo` and the shared push write a temp file then rename over the target, so another copy never reads a half-written file.
- **Each copy detects updates and reloads itself**: a `FileSystemWatcher` + a 60 s poll compare the bundle's `LastModified` to the local data; when the bundle is newer, the app reloads it (data + attachments) — **silently** when there are no un-synced local changes, or **after a prompt** when there are (tracked via a "last synced" stamp so a saved-but-not-yet-pushed change is never silently lost). Pulls extract to a temp folder and validate before touching local data, so a torn/locked bundle can't corrupt you.
- Reviewed across three adversarial multi-agent passes; each confirmed data-loss risk was fixed (torn-read→empty→overwrite; outbound writes clobbering newer data; and saved-but-unpushed local changes being silently discarded). Remaining behaviour is intentional last-writer-wins for genuinely concurrent edits.
- Detection primitives verified by a 7-check harness (exact stamp round-trip, self-writes never look "newer", real updates detected, older ignored). Build: **0 warnings / 0 errors**.

## Update (2026-07-06): shared-save verified, activity log, unit converter, Ctrl+N quick-work
- **Shared save verified end-to-end**: added an `AA_DATA_DIR` override to [Services/DataStore.cs](AA/Services/DataStore.cs) `AppFolder` (portable data dir / isolated testing) and ran a 12-check isolated test — the bundle includes the attachment file, stamps detect correctly (no reload loop), and a pull restores data **and** the attachment with matching content.
- **Activity log (UTC)**: [Models/Models.cs](AA/Models/Models.cs) `LogEntry` + `AppData.Log`; [Services/AppRepository.cs](AA/Services/AppRepository.cs) `LogAdded`/`LogRemoved` (UTC-stamped, bounded to 10k). Hooked at every add/remove point (hierarchy New/Delete, inline creates, subtask/step add/remove + bulk builders, crew import/delete/clear). New **Tools ▸ Activity log...** ([Views/ActivityLogWindow.xaml](AA/Views/ActivityLogWindow.xaml)): newest-first list (UTC + local time), filter, Clear, CSV export.
- **Maritime unit converter**: **Tools ▸ Unit converter...** ([Views/UnitConverterWindow.xaml](AA/Views/UnitConverterWindow.xaml)) — 14 categories (Speed, Distance, Pressure, Temperature, Volume, Mass, Angle/Bearing, Time, Power, Force, Density, Flow rate, Area, Energy) with maritime units (knots, NM, fathoms, cables, compass points, oil barrels, long/short tons, PS/hp, GPM…). Type in any unit; all others convert instantly.
- **Ctrl+N Quick-work window** ([Views/QuickWorkWindow.xaml](AA/Views/QuickWorkWindow.xaml)): a big window — left lists **pending** tasks (incomplete) & procedures (not Done), filter/search/create; pick one (assignable) and the right side is a **comprehensive builder** (Name/Deadline/Status/Recurrence + bulk-add + reorderable subtasks/steps + Edit + "Open full builder"). Opened via Ctrl+N (`ApplicationCommands.New`) or Tools; single-instance; re-points its repo on shared reload.
- Reviewed by an adversarial pass; two confirmed HIGH bugs in the quick-work window were fixed: the Name field rebuilding the panel per keystroke (focus loss), and the non-modal window not being re-pointed after a shared reload (stale-write data loss).
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**.

## Update (2026-07-08): Obsidian-style navigation (tags, backlinks, quick switcher) + table paste + editor perf
Adopted the top three "Obsidian" suggestions, reworked the rich-text editor to detect & round-trip tables, and hardened it for speed.

### Tags (Obsidian-style)
- Every item carries free-form **Tags** ([Models/Models.cs](AA/Models/Models.cs) `HierarchyItem.Tags`), edited via a **Tags** box in the item header ([Views/HierarchyPage.xaml](AA/Views/HierarchyPage.xaml)). Comma/space/semicolon separated; a leading `#` is accepted and stripped.
- Tags are searchable in **Ctrl+F** ([Services/SearchService.cs](AA/Services/SearchService.cs) — tags stay searchable even for password-locked items since they carry no protected content) and in the quick switcher.

### Backlinks ("Referenced by")
- [Services/AppRepository.cs](AA/Services/AppRepository.cs) `ReferencedBy` surfaces every **incoming** reference: two-way `RelatedIds`, an Equipment/Area's one-way `ProcedureIds`/`TaskIds`, and a procedure step's `TaskIds`/`EquipmentIds`. So a Task/Procedure can now see who points at it even for the one-way links that never appeared in its own relationship list.
- New **↩ Referenced by** panel under the Relationships tab; double-click any related item **or** backlink to jump to it (`Navigate` callback wired on all four hierarchy pages via `MainWindow.NavigateToItem`).

### Quick switcher (Ctrl+O)
- New [Views/QuickSwitcherWindow.xaml](AA/Views/QuickSwitcherWindow.xaml) — fuzzy-jump to any item by **name, kind or #tag**. Type, **↑/↓** to move, **Enter**/double-click to open, **Esc** to close. Weighted scoring (name-prefix > name-contains > subsequence > tag > kind > description). Bound to `ApplicationCommands.Open` (Ctrl+O), a Tools menu item, and a **Go to (Ctrl+O)** header button.

### Rich-text editor: table paste & insert
- **Paste tables** from Excel / Word (native WPF RTF path) and the **web** (HTML-only path via the rewritten [Services/HtmlToXamlConverter.cs](AA/Services/HtmlToXamlConverter.cs) `EmitTable`) as real FlowDocument `Table`s — visible cell borders, bolded header cells, `colspan`/`rowspan` preserved, and they copy back out intact.
- **Insert Table (▦)** toolbar button ([Views/ContainerEditor.xaml](AA/Views/ContainerEditor.xaml)) — prompts for `rows x cols` and inserts an empty bordered table at the caret.

### Lightning-fast editing
- Per-keystroke lock filtering is skipped entirely unless the document actually contains a locked run (`_hasAnyLock`, computed by an accurate one-pass `DocumentContainsLock()` walk after load).
- System fonts are enumerated **once** into a static cache shared by every editor instance (was re-enumerated per editor).

### Two adversarial review passes (16 + 5 agents)
A multi-agent review found and I fixed six issues, then a second pass re-verified each fix:
1. **[High]** Nested tables duplicated rows/content on paste → `EmitTable` now only takes rows owned by *this* table (`OwnedByThisTable`).
2. **[Med]** Unknown CSS colors (`rebeccapurple`, `lightgrey`, `currentColor`, malformed hex) made WPF reject the whole styled paste → `NormaliseColor` validates hex, clamps `rgb()`, and whitelists real WPF color names (built once from `System.Windows.Media.Colors`), dropping the rest.
3. **[Med]** Quick switcher didn't match the `#tag` form it advertised → query strips a leading `#`.
4. **[Med]** Adding a procedure/task on the Specifics tab left the Relationships tab + backlinks stale → `RefreshRelList()` after those mutations.
5. **[Med]** `_hasAnyLock` false-positived on gold foreground/highlight colors (perf regression) → replaced the `"FFE699"` substring test with the exact `DocumentContainsLock()` walk.
6. **[Low]** Deleting an item left dangling one-way references (→ "(missing)" rows, phantom backlinks) → new `AppRepository.PurgeReferences` scrubs `RelatedIds` + `ProcedureIds`/`TaskIds` + step `TaskIds`/`EquipmentIds` **and** every file's `LinkedItemIds` (across all containers); used by both delete paths (`HierarchyPage.Delete_Click`, `BoardPage.DeleteTask`).
- Converter fixes verified empirically in a WPF STA harness (**31/31**: nested-table dedup, bad-color drop, rgb clamp, valid-color pass-through, plain-table round-trip). Second review pass returned **4/5 FIX_CORRECT**; the one FIX_INCOMPLETE (`LinkedItemIds` not scrubbed) was then completed.
- Build: `dotnet build` succeeds with **0 warnings / 0 errors**. Portable exe republished to `publish\AA.exe` (~80 MB, 2026-07-08 build).

### Follow-up (2026-07-08): Ctrl+N shows ALL tasks & procedures (not just pending)
- The Ctrl+N Quick-work window no longer hides completed tasks / done procedures. [Views/QuickWorkWindow.xaml.cs](AA/Views/QuickWorkWindow.xaml.cs) `RefreshPending` now lists **every** task and procedure; completed/done items sort to the bottom (active work still leads) and are tagged **✓ completed** in the subtitle. The count line reads e.g. "12 item(s) — 9 active, 3 completed/done." Labels/title updated from "pending" to "all tasks & procedures". The All / Tasks / Procedures filter and search still apply.

## Update (2026-07-08): per-crew-member checklists, reusable saved lists, crew due-dates, Ctrl+R & shortcut bar

### Per-crew-member checklist
- `CrewMember` ([Models/CrewMember.cs](AA/Models/CrewMember.cs)) gained a stable `Guid Id` and an `ObservableCollection<ChecklistStep> Checklist` — so a crew member's checklist reuses the same item type as procedures (each item can carry a **deadline, done-state, notes and files**).
- The crew editor ([Views/CrewEditorWindow.xaml](AA/Views/CrewEditorWindow.xaml)) is now tabbed: **Details** + a **Checklist** tab hosting the comprehensive builder. The read-only crew card shows a checklist summary (count / done / next due) with a **🗒 Open checklist...** button that jumps straight to that tab.
- COMPAS re-import **preserves** each existing member's `Id` and `Checklist` ([Views/CrewPage.xaml.cs](AA/Views/CrewPage.xaml.cs) `ImportCompas`) — the report has neither, so a blind replace would have wiped them.

### Reusable saved lists (templates) in every builder
- New `ChecklistTemplate` / `ChecklistTemplateItem` models + `AppData.ChecklistTemplates` ([Models/Models.cs](AA/Models/Models.cs)), and [Services/ChecklistTemplateService.cs](AA/Services/ChecklistTemplateService.cs) — a **full copy** (titles, durations, schedulable flag, and a deep-cloned rich-text + file-bank container) that can be applied over and over (append or replace).
- A new shared **[Views/ChecklistBuilderControl](AA/Views/ChecklistBuilderControl.xaml)** UserControl holds the whole builder (bulk add, reorder, full per-item editor, and **💾 Save as list / 📋 Load a saved list / Manage**). It's hosted by the procedure `ChecklistBuilderWindow` **and** the crew editor's Checklist tab, so both share one implementation.
- Save/Load buttons were also wired into **[SubtaskBuilderWindow](AA/Views/SubtaskBuilderWindow.xaml)** (tasks) and the **Ctrl+N QuickWork** inline builder ([Views/QuickWorkWindow.xaml.cs](AA/Views/QuickWorkWindow.xaml.cs)) — templates convert cleanly between `ChecklistStep` and `TaskItem`.
- Crew-checklist and template containers were added to `DataStore.EnumerateContainers` and `AppRepository.AllContainers` so their **files are bundled with the save** (and path-normalised) and not lost on a cross-machine import.

### Crew items in due-dates & everywhere necessary
- A crew checklist item with a due date now appears in the **📌 due-dates window** ([Views/FloatingTasksWindow.xaml.cs](AA/Views/FloatingTasksWindow.xaml.cs) — purple accent, click → jumps to that crew member) and on the **Calendar** ([Views/CalendarPage.xaml.cs](AA/Views/CalendarPage.xaml.cs) `ScheduleRow.ForCrewStep`, double-click → full editor). Crew items tagged **Schedulable job** now also reach the **Planner** (`AppRepository.AllJobs` enumerates crew checklists).

### Due-dates window resize + Ctrl+R + shortcut bar
- The floating due-dates window was already user-resizable (corner grip); its **size now persists** across sessions ([UiState.DueWindowWidth/Height]).
- **Ctrl+R** opens the due-dates window (`ApplicationCommands.Refresh` bound in [MainWindow.xaml](AA/MainWindow.xaml)).
- A **hideable keyboard-shortcuts strip** sits at the bottom of the main window (Ctrl+S/F/N/O/R). Toggle via the ✕ button or **View ▸ Shortcut bar**; state is remembered (`UiState.ShowShortcutBar`).

### Adversarial review (9 agents) → 3 fixes
1. **[Med]** crew steps tagged "Schedulable job" were a no-op → `AllJobs()` now yields crew checklist steps and `FloatingTasksWindow.JobNav` resolves a crew-owned step to its member for navigation.
2. **[Low]** `CloneContainer` dropped the `Container.IsLocked` flag → now copied.
3. **[Low]** the due-window's resized size could be lost if the whole app closed while it was open → size is now persisted during the resize (`ResizeGrip_DragDelta`) so the normal/close-time save captures it.
- Build: **0 warnings / 0 errors**. Portable exe republished to `publish\AA.exe` (~80 MB, 2026-07-08 build).

## Update (2026-07-08): Saved Lists tab, List Groups, PDF export, customizable tab colors

### Saved Lists tab + List Groups
- New top-level **Saved Lists** tab ([Views/SavedListsPage.xaml](AA/Views/SavedListsPage.xaml)) — a home for the reusable saved checklists that previously lived only inside the builder dialogs. Left: the lists **grouped by List Group** (ungrouped sink to the bottom); right: the selected list's items preview + actions.
- New `ListGroup` model + `ChecklistTemplate.GroupId` + `AppData.ListGroups` ([Models/Models.cs](AA/Models/Models.cs)). A saved list can be **freely moved into any group** ("Move to group…"), and groups are created/renamed/deleted in the same tab ("+ Group" / "Manage groups…"; deleting a group keeps its lists, just ungroups them). Both saved lists and groups **persist in the save** and ride along in shared/exported bundles (their item containers were already added to `EnumerateContainers`).
- Full list management in the tab: **+ List** (empty), **Rename**, **Delete**, **Duplicate**, and **✎ Edit items…** — which round-trips the list through the shared checklist builder ([Views/TemplateEditorWindow.xaml](AA/Views/TemplateEditorWindow.xaml), via `ChecklistTemplateService.ToSteps`/`WriteBackFromSteps`) so you get bulk-add, reorder and full per-item notes/files editing.

### PDF export (lists & groups)
- **📄 Export** a single saved list, a whole group, or **all** saved lists to a nice A4 PDF ([Services/PdfExporter.cs](AA/Services/PdfExporter.cs) `ExportSavedLists`) — group headings, numbered items with duration/schedulable tags, rich-text notes and attached file names. Verified with a real-method smoke test (**3/3** PDFs generated: single-with-notes+file, grouped-with-empty-list, ungrouped-multi).

### Customizable tab colors
- **View ▸ 🎨 Customize tab colors…** ([Views/TabColorsWindow.xaml](AA/Views/TabColorsWindow.xaml)) — pick a background colour per main tab (or reset to the theme default). The [TabItem template](AA/App.xaml) was refreshed so a tab **keeps its custom colour when selected**, marked active by a bold **accent underline** (text colour auto-contrasts black/white). Choices persist in `UiState.TabColors` and re-apply on launch.
- Build: **0 warnings / 0 errors**. Portable exe republished to `publish\AA.exe` (~80 MB, 2026-07-08 build).

### Hotfix (2026-07-08): app failed to start after login (invalid Ctrl+R command)
- **Symptom:** the app showed the splash + login, then died the moment you logged in (never reached the main window) — a silent "not starting".
- **Cause:** the Ctrl+R binding used `Command="ApplicationCommands.Refresh"` in [MainWindow.xaml](AA/MainWindow.xaml). `ApplicationCommands` has **no** `Refresh` member (it lives on `NavigationCommands`). Command strings are resolved by `CommandConverter` at **runtime**, so this compiled cleanly (0/0) but threw `XamlParseException → CommandConverter cannot convert from System.String` while `MainWindow`'s XAML loaded, right after login.
- **Fix:** both the `KeyBinding` and `CommandBinding` now use `NavigationCommands.Refresh` (Ctrl+R still opens the due-dates window). Reproduced the exact crash by loading `MainWindow` against a copy of the real `data.json` in a headless WPF harness, then confirmed it constructs + loads cleanly after the fix.
- **Hardening:** added global crash logging to [App.xaml.cs](AA/App.xaml.cs) — any unhandled exception is now written to `%LOCALAPPDATA%\AA\crash.log` and shown in a dialog, so a startup failure can never again be a silent black box.
- Rebuilt & republished the self-contained single-file `publish\AA.exe`; verified it launches.

## Update (2026-07-08): pinned squares in the Ctrl+N quick-work window
- The Ctrl+N quick window ([Views/QuickWorkWindow.xaml](AA/Views/QuickWorkWindow.xaml)) gained a **📌 Pinned** board at the top: pin any task or procedure as a **square tile**. Each tile shows the name, kind, a **progress bar** (subtasks/steps done ÷ total), a deadline chip (overdue in red), an unpin button, and a **Done** checkbox. Clicking a tile selects it for editing in the builder below.
- **Everything applies everywhere.** Pins are stored in `UiState.QuickViewPinIds` (persisted + shared). Ticking a tile's Done, editing/adding/removing its subtasks or steps, or **🗑 Delete**-ing the whole item (new button in the detail pane, with `PurgeReferences`) all write straight to the real `TaskItem`/`Procedure` — so the change shows up on the Calendar, Board, Planner, due-dates window, etc. The tiles auto-refresh with every change (`RefreshPinned` is coupled to `RefreshPending`), and a deleted item's stale pin is pruned automatically.
- Verified against a copy of the real data in a headless WPF harness: the window constructs and renders pinned tiles (task + done procedure, with progress bars) without error; the main window still loads cleanly after the `UiState` addition.
- Build: **0 warnings / 0 errors**. Portable exe republished to `publish\AA.exe` (~80 MB).

## Update (2026-07-08): work-orders area — filtering, sorting, completion & deletion
The per-vessel Shippalm work-orders panel ([Views/ShipJobsPanel.xaml](AA/Views/ShipJobsPanel.xaml)) gained full list management:
- **More filtering:** existing search + status, now plus **Category** and **Responsible-rank** dropdowns and a **Show: All / Active only / Completed only** filter (alongside the existing due/overdue and notify-only toggles).
- **Column sorting:** click any **column header** to sort by it (click again to reverse) — Job No., Title, Due, Interval, Status, Due Status, Category, Responsible, Function, Done, Notify. Default remains soonest-due first with completed jobs sunk to the bottom.
- **Mark as completed:** a new **Done** checkbox column, plus **✓ Mark completed / ↺ Mark active** buttons and a right-click menu (act on the selected rows, or all shown if none selected). A new `ShipJob.IsCompleted` + `CompletedDate` ([Models/Models.cs](AA/Models/Models.cs)) is preserved across re-import (like the Notify flag). Completed jobs are struck-through, shown as "✓ completed", and **excluded from overdue/due counts and notifications**.
- **Deletion:** multi-select rows and **🗑 Delete** (toolbar or right-click), with confirmation; the summary/filters refresh afterward.
- **Verified** in a headless WPF harness with synthetic jobs: the panel builds, and the completion filter renders All=4 / Completed=1 / Active=3 correctly with no error; the main window still loads cleanly after the `ShipJob` model change.
- Build: **0 warnings / 0 errors**. Portable exe republished to `publish\AA.exe` (~80 MB).

## Update (2026-07-08): quick-work window — strike-through on done, and "buckets"
- **Done items are crossed out in the quick window** ([Views/QuickWorkWindow.xaml](AA/Views/QuickWorkWindow.xaml)): the left task/procedure list, the pinned squares, and the builder's subtask/step list now render a **strike-through** when an item is complete. Because completion lives on the real `TaskItem`/`Procedure`/`ChecklistStep`, the crossed-out state matches everywhere else in the app (Calendar, Board, due-dates window, etc.) — marking done anywhere shows everywhere.
- **Buckets** — a cross-kind container to sort tasks & procedures into within the quick window. New `QuickBucket` model + `HierarchyItem.BucketId` + `AppData.QuickBuckets` ([Models/Models.cs](AA/Models/Models.cs)). Toolbar/right-click: **🪣 + Bucket**, **Move to bucket…**, **Remove from bucket**, **Manage buckets…** (rename/delete — deleting a bucket just unbuckets its items). When any bucket exists, the left list is **grouped by bucket** (unbucketed items sink to a "(No bucket)" group at the bottom); within each bucket, active work leads and completed items sink. Buckets persist and travel with the shared save.
- **Verified** in a headless WPF harness against a copy of the real data: with a bucket created and an item assigned, the window builds and the list shows 2 groups ("Engine room" + "(No bucket)") across all 29 items; the main window still loads cleanly after the model change.
- Build: **0 warnings / 0 errors**. Portable exe republished to `publish\AA.exe` (~80 MB).

## Update (2026-07-08): buckets rework — predefined, own tab, up-to-two, every level
- **Buckets are now predefined in their own [Buckets tab](AA/Views/BucketsPage.xaml)** (name + optional **Category** like Location/Rank; grouped by category). The right pane lists everything sorted into the selected bucket; double-click opens it. Creation moved out of the quick window.
- **Up to two buckets per item.** `HierarchyItem.BucketId` (single) was replaced by `BucketIds` (collection), and **`ChecklistStep` gained `BucketIds`** too, via a shared **`IBucketable`** interface. So **each task, subtask, procedure and checklist step** can be sorted into buckets — from the Ctrl+N window (a 🪣 Buckets button on the selected item and on any subtask/step in the builder), capped at two via a multi-select picker.
- An item in two buckets appears under **both** bucket groups in the quick window; unbucketed items fall under "(No bucket)".
- **Text no longer clips:** pinned tiles grow (MinHeight + wrapped name, no ellipsis); rows wrap.
- **Thin separator line** between rows added to the global `ListBoxItem`/`ListViewItem` templates ([App.xaml](AA/App.xaml)) — shows in the quick window and every other list.

### Adversarial review (14 agents) → fixes
Confirmed issues, all fixed:
1. **[Med]** the quick list grouped by bucket **name**, so two buckets sharing a name collided → now grouped by bucket **id** (header shows the name via the first row); verified two same-named buckets stay distinct (3 groups).
2. **[Med]** right-click context menus (quick list + Buckets-tab members) acted on the *previously selected* row, not the right-clicked one → added `PreviewMouseRightButtonDown` to select the clicked row first (both lists).
3. **[Low]** replacing `BucketId` with `BucketIds` dropped older single-bucket assignments on load → added a write-null-skipped **migration shim** (verified: legacy `BucketId` JSON migrates in, and is never written back).
4. **[Low]** a two-bucket item's selection jumped groups on refresh → track the selected bucket group (`_selectedBucketKey`).
5. **[Low/perf]** grouping disabled list virtualization → set `IsVirtualizingWhenGrouping`.
- **Verified** in a headless harness (migration in/out + same-name grouping = 3/3) and the main window loads cleanly. Build **0/0**; portable exe republished to `publish\AA.exe` (~80 MB).

## Update (2026-07-17): ports of call, crew scheduler, draggable tabs
Project drive moved to **F:**. All four asks below built **0/0** and verified in headless WPF harnesses.

### Ports of call import (two formats) → per-vessel + global database
- New [Services/PortCallReader.cs](AA/Services/PortCallReader.cs) auto-detects and parses **both** exports in `AA\POC`:
  **A** "Last Ports of Call — 2 Years" (No | Port Name, Country | Date Arrived/Departured | Security levels | SSP | Special) and **B** "Port of Call List — Last 10 Ports" (Vessel/IMO/Call-sign header + two-row header with UN/LOCODE, Port Facility, Security Level PF/Vessel, Arrival & Departure Date+Time).
- Every import is **linked to a vessel**. A new **Ports** tab in each vessel's view ([Views/PortsPanel.xaml](AA/Views/PortsPanel.xaml)) imports (auto-detect), sorts/filters, exports (.xlsx) and deletes port calls (`Vessel.PortCalls`). Re-importing / importing both formats **merges** by port+date (a vessel is at one port per date), enriching fields ([Services/PortsService.cs](AA/Services/PortsService.cs)).
- Each import also feeds the global **Ports Database** tab ([Views/PortsPage.xaml](AA/Views/PortsPage.xaml), `AppData.Ports`): every port with the **vessels that called and when** (deduped per vessel/date).
- Verified end-to-end on the real files: A=47 calls, B=10 calls, Bonny merged to one call (country from A, time+UN/LOCODE from B), DB deduped, idempotent re-import, panels render — **10/10**.

### Per-crew scheduler
- Each crew member gains a **Schedule** ([CrewMember.Schedule], a `ScheduleEntry` timeline) built in a new **Schedule tab** in the crew editor ([Views/ScheduleBuilderControl.xaml](AA/Views/ScheduleBuilderControl.xaml)): interactive add row (date + time + kind + **pick a Task/Procedure/Equipment or type a note**), a **date-grouped timeline** (Today/Tomorrow/…) with done/edit/delete, and a **linked-vessel** combo.
- **Save / apply / export / import** reusable schedules ([Services/ScheduleService.cs](AA/Services/ScheduleService.cs), `AppData.ScheduleTemplates`): save a crew's schedule as a named template, **apply it to any crew** (append/replace), export to a portable `.aasched.json`, import (adds to your saved schedules and applies). A schedule can be linked to a vessel. Verified — **11/11**.

### Draggable tab order
- The main tabs can now be **dragged to reorder** ([MainWindow.xaml](AA/MainWindow.xaml) — `Tab_PreviewMouseDown/Move/Drop`). The order persists (`UiState.TabOrder`) and is re-applied on launch (unknown/new tabs keep their place after the saved ones), preserving the selected tab.

- All prior features confirmed intact (build 0/0, main window loads with the real data). Portable exe republished to `publish\AA.exe` (~80 MB, 2026-07-17).

## Update (2026-07-18): saved-list tasks in Planner/Board, deadline-aware Planner
Three asks, all built **0/0** and verified in a headless WPF harness (**16/16**).

### 1. Saved-list item preview no longer shows the duration
- [Views/SavedListsPage.xaml.cs](AA/Views/SavedListsPage.xaml.cs) drops the `~{N}m` chip from each saved-list item's preview meta (the `if (it.DurationMinutes > 0) meta.Add(...)` line). The item still shows `job` / `notes` / `N files` when relevant; duration is still stored and still shown in the Planner's own job rows.

### 2. Add tasks from saved lists — searchable, in the Planner and Board
- Saved lists are **templates**, so a new shared flow turns a template item into a **real, standalone Task** (kept distinct from the template). [Services/ChecklistTemplateService.cs](AA/Services/ChecklistTemplateService.cs) `ItemToTask` copies title → `Name`, duration, the `IsJob` (schedulable) flag and a **deep-cloned** notes/files container; the task starts in **To&nbsp;Do**. Deadline/done are per-instance, so left unset.
- New [Views/SavedListPicker.cs](AA/Views/SavedListPicker.cs) `PickAndAddTasks` opens the existing searchable, multi-select [ItemPickerWindow](AA/Views/ItemPickerWindow.xaml) over **every item in every saved list** (labelled `list › item · schedulable`); each pick is added to `Data.Tasks` and saved.
- Surfaced as **+ From saved list** on the [Board](AA/Views/BoardPage.xaml) toolbar and **+ Saved list** in the [Planner](AA/Views/PlannerPage.xaml)'s Unscheduled-Jobs header. Because both tabs read `Data.Tasks`, a picked item immediately appears as a Board card and (being a job) in the Planner's unscheduled pool — schedulable/movable/deletable like any task.

### 3. Planner is deadline-aware; no-time items stack in an all-day strip
- [Views/PlannerPage.xaml.cs](AA/Views/PlannerPage.xaml.cs) now places **anything with a due date**, not just IsJob items dragged onto the grid. A new `AllSchedulable()` enumerates every task (incl. nested subtasks), procedure, procedure step and crew checklist step; `DeadlineOf()`/`WhenOf()` (scheduled time else due date) decide placement. `_placed` = everything with a when.
- **Day/Week** grew an **all-day ("due") strip** between the day-name header and the hour grid: items with a **due date but no time-of-day** are chronologically stacked there per day (wrapping chips, so nothing clips), while time-scheduled items stay on the hour grid. Dragging an all-day chip onto the grid gives it a time (sets `ScheduledStart`); dragging it back leaves the due date so it returns to the strip (non-destructive).
- **Month** cells now show both timed (`HH:mm name`) and no-time (`• name`) items for each date, timed first.
- The **Unscheduled Jobs** side list now holds only IsJob items with **neither** a time **nor** a due date (deadline-bearing jobs moved onto the calendar), so it stays a true "still needs placing" pool.
- Verified: deadline-bearing tasks/subtasks/non-job tasks/procedures/steps/crew steps are all placed; a timed task stays timed; a loose job is the only unscheduled entry; today's all-day strip shows exactly its 5 no-time items; Day/Week/Month all rebuild without crashing; `ItemToTask` round-trips correctly.
- Portable exe republished to `publish\AA.exe` (~80 MB, 2026-07-18).

### Optional working date-range on tasks & subtasks (the last date IS the deadline)
Every `TaskItem` (top-level tasks and all nested subtasks) gained an **optional working range** — "the range of doing it". Its LAST date is the existing **Deadline** (the range END); the new **`RangeStart`** is the first day. A task with only a deadline (no start) stays a single-day point item, exactly as before.
- **Model** ([Models/Models.cs](AA/Models/Models.cs)): `RangeStart` (nullable, `Set(ref …)` like Deadline — pure setter, no cross-field logic so `System.Text.Json` loads never mis-clamp), plus computed `HasRange`, `RangeFirst`, `CoversDay(day)` and a bindable `WhenText` ("start → deadline" / "yyyy-MM-dd" / ""). Null omitted from JSON ⇒ **zero migration**, byte-identical saves for point items. `RangeStart` is TaskItem-only; Procedure/ChecklistStep stay point items.
- **Smart validation** ([Services/WorkRange.cs](AA/Services/WorkRange.cs) `Coerce`): the editors keep two pickers (start + deadline) consistent by nudging the *other* field — editing the start past the deadline pushes the deadline out (the last date is always the deadline); editing the deadline before the start clamps the start; a start with no deadline sets the deadline to that day. Never a modal.
- **Editors**: [SubtaskEditorWindow](AA/Views/SubtaskEditorWindow.xaml) (start picker + "Clear range" + day-count hint + greyed-out impossible days), [HierarchyPage.BuildTaskSpecifics](AA/Views/HierarchyPage.xaml.cs) (start picker; subtask list "When" column via `WhenText`), and [QuickWorkWindow](AA/Views/QuickWorkWindow.xaml.cs) (a "Range start" field shown only for tasks — the shared deadline picker still serves procedures unchanged).
- **Planner** ([Views/PlannerPage.xaml.cs](AA/Views/PlannerPage.xaml.cs)): new `RangeStartOf`/`DueSpan` helpers. A due-only ranged task now renders on **every day of its span** — a chip per column in the day/week all-day strip and a chip per cell in the month, with the deadline day emphasised (`⚑`, bold, full opacity) and other days de-emphasised (`▸`/`·`, dimmed). Timed items (with `ScheduledStart`) stay on the hour grid. Drag is range-aware: a chip carries its anchor day, so **dragging a ranged task in Month slides the whole window** (length preserved); dropping onto the hour grid schedules a time (and extends the window if outside it); a point item dragged in Month moves its due date.
- **Calendar** ([Views/CalendarPage.xaml.cs](AA/Views/CalendarPage.xaml.cs)): `ScheduleRow` carries the range (`Covers`, `EffectiveStart`, `RangeDisplay`); Day/Week/Month filters became interval-overlap (also fixing the month view's old year+month-equality limitation), and the **Agenda** fans a ranged task into one row per covered day (capped at 31). The schedule "When" column shows the range.
- **Board / PDF / floating due-dates**: the [Board](AA/Views/BoardPage.xaml.cs) card shows `start → deadline` (OVERDUE still keyed on the deadline); the [PDF export](AA/Services/PdfExporter.cs) adds a "Working range" row and range meta on subtasks; the [floating due-dates window](AA/Views/FloatingTasksWindow.xaml.cs) surfaces a ranged task on every covered day (starts / ongoing / ends). Saved lists/templates deliberately carry **no** range (per-instance, like the deadline). Change-preview ([DataDiff](AA/Services/DataDiff.cs)) gained a `start:` line.
- Verified in a headless WPF harness — **32/32**: `WorkRange.Coerce` for every start/deadline ordering; model boundaries (`CoversDay` start/middle/end/outside, `WhenText`); Planner week all-day spans 3 days + point 1; Planner month spans 3 cells; Calendar Day/Week/Month span-aware; Agenda fans today..+2 into 3 rows; Board meta shows the range; window-slide preserves span. Build **0/0**.
- **Adversarial review** (4 dimensions → per-finding verify) confirmed and fixed two low-severity edge cases: (1) the Calendar's `EffectiveStart` didn't clamp an *out-of-order* range (`RangeStart > Deadline`) that could only arrive via a hand-edited/imported `data.json`, so Day/Week silently dropped the item while the Planner/floating window still showed it — now clamped to the deadline like `CoversDay`/`DueSpan`; (2) the subtask "When" column bound to the computed `WhenText`, which never raised `PropertyChanged`, so it went stale after editing dates through the bulk Subtask Builder — the `RangeStart`/`Deadline` setters now notify `WhenText`/`HasRange`/`RangeFirst`. A flagged high-severity month-drag corruption was **refuted** — the proactive `MonthCell_Drop` hardening (slide on any `RangeStart`, not just multi-day) had already eliminated it.
- Portable exe republished to `publish\AA.exe` (~80 MB, 2026-07-18).

### Batch "mark as done" (right-click) + tab-drag crash fix
Two changes verified together in the headless harness — **45/45** (4 crash-fix + 32 range + 9 batch-done). Build **0/0**.

**Crash fix — clicking a tab while rich text is focused no longer errors.** The crash log showed a repeating `InvalidOperationException: 'System.Windows.Documents.FlowDocument' is not a Visual or Visual3D` at `MainWindow.FindAncestor` ← `Tab_PreviewMouseDown`: the draggable-tabs handler (added 2026-07-17) walks up from `e.OriginalSource`, and when the click lands on rich-text content the source is a `FlowDocument`/`Run` — a `ContentElement`, which `VisualTreeHelper.GetParent` **throws** on. Every one of the app's **five** copies of `FindAncestor` had the same latent bug. Introduced [Views/UiTree.cs](AA/Views/UiTree.cs) — a single content-safe `FindAncestor`/`GetParent` that hops content elements via `ContentOperations`/`LogicalTreeHelper` and only visuals via `VisualTreeHelper`, so it never throws — and routed all five ([MainWindow](AA/MainWindow.xaml.cs), [BoardPage](AA/Views/BoardPage.xaml.cs), [CalendarPage](AA/Views/CalendarPage.xaml.cs), [PlannerPage](AA/Views/PlannerPage.xaml.cs), [QuickCardsPanel](AA/Views/QuickCardsPanel.xaml.cs), [QuickWorkWindow](AA/Views/QuickWorkWindow.xaml.cs)) through it. Harness feeds the exact crash input (`FlowDocument`, and a `Run` inside one) and confirms it returns null instead of throwing, still finds real ancestors, and climbs a content element up to its hosting `RichTextBox`.

**Batch mark-as-done via right-click.** New [Services/BatchDone.cs](AA/Services/BatchDone.cs) sets done-state on any completable model object — `TaskItem.IsComplete`, `ChecklistStep.Done`, `Procedure.Status` (kept in sync by the model setters). New [Views/BatchDoneMenu.cs](AA/Views/BatchDoneMenu.cs) appends **"✓ Mark selected as done"** / **"○ Mark selected as not done"** to a context menu (selection evaluated fresh at click time; one `MarkDirty`+`FlushIfDirty`+refresh) and a `RightClickSelect` that keeps an existing multi-selection when you right-click an already-selected row. Wired into every multi-select list of completables: the **Board** (cards, now `Extended`), the **subtask** list and **checklist-step** list ([HierarchyPage](AA/Views/HierarchyPage.xaml.cs)), the **Calendar** schedule grid (rows map to the underlying item), and the **Ctrl+N quick window** (the children list and the `PendingList`, now `Extended`). Harness verifies the core matrix (Task/Step/Procedure done+undone, mixed selection count) plus Board and Calendar end-to-end: select rows → invoke the menu item → the right items flip to done and the untouched one stays.

**Adversarial review** (3 dimensions → per-finding verify; crash-fix and selection-UX dimensions came back clean) confirmed and fixed one low-severity inconsistency: `BatchDone.SetDone` on a **Procedure** unconditionally forced `Status = Todo` when unmarking, wiping an `InProgress`/`Blocked` workflow status — whereas the same action on a `TaskItem` is a state-preserving no-op. `SetDone` now mirrors the model's contract (un-complete demotes only a *Done* item, preserving in-progress/blocked) and returns whether it actually changed anything, so a pure no-op no longer triggers a disk write. Also hardened the wrapper-VM selection casts to `OfType<T>`. Full run **49/49**, build **0/0**.

### "Paste text only" (strip formatting) in the rich-text editor
The container rich-text editor ([Views/ContainerEditor.xaml.cs](AA/Views/ContainerEditor.xaml.cs)) gained a **"Paste text only"** entry on its right-click menu (plus a **Ctrl+Shift+V** shortcut) that inserts the clipboard as plain text, dropping every colour/font/size/link from the source — the inserted run simply adopts the destination style.
- The `RichTextBox` now carries a custom `ContextMenu` rebuilt on `ContextMenuOpening`: it reproduces the **native spelling suggestions** (`GetSpellingError` at the caret → *Correct*/*Ignore All*) so the proofing UX is preserved, then **Cut / Copy / Paste / Paste text only / Select All** (Cut/Copy/Paste/SelectAll are `ApplicationCommands` so they self-enable). `PreviewMouseRightButtonDown` moves the caret under the cursor (unless the click is inside an existing selection) so the menu's suggestions and the paste target match the click.
- `PasteTextOnly()` reads `Clipboard.GetText()` (which ignores any Rtf/Html/Xaml payload) and hands it to `InsertPlainText()`, which sets `Rtb.Selection.Text` inside a single `BeginChange`/`EndChange` undo unit and **respects the per-run edit lock** exactly like the normal Paste command (blocked with the usual hint when the caret/selection touches locked text). The existing HTML→XAML pasting handler for normal `Ctrl+V` is untouched. The debounced 400 ms save fires via `TextChanged`.
- Harness (**54/54** total): custom menu installed; plain text inserted (incl. into an emptied document); the inserted run carries no bold/colour; and a paste into locked text is blocked. Build **0/0**.
- **Adversarial review** (2 dimensions → verify) confirmed and fixed two issues: (med) the reproduced spelling-suggestion menu could `Correct()` a misspelled word sitting inside a **locked** run (the only ungated edit path) — corrections are now suppressed/blocked via `CaretInsideLocked` while "Ignore All" (no text mutation) stays; (low) the empty-document paragraph creation sat outside `BeginChange`/`EndChange`, splitting a paste into two undo units — now inside, so one Ctrl+Z reverts it.

### Clickable links in exported PDFs
Every link in the rich-text notes now exports as a **clickable** link in the PDF ([Services/PdfExporter.cs](AA/Services/PdfExporter.cs)). Previously only formal `Hyperlink` elements with a non-null `NavigateUri` were wired up; bare URLs/e-mails typed or pasted as plain text rendered as dead text.
- Plain runs go through `AddRunAutoLinked` → `ScanLinks`, a conservative regex that detects `http(s)://` / `www.` URLs and e-mail addresses, splits the run, and emits a MigraDoc `AddHyperlink(uri, Web)` for the link parts (blue + underline) and normal formatted text for the rest. `www.` hosts get an `https://` scheme; e-mails become `mailto:` links; trailing sentence punctuation is pushed back into the following text.
- Formal WPF hyperlinks are hardened: the `NavigateUri` is normalised (bare `www.` → `https://`) and, when it's null, falls back to a URL found in the link's own display text.
- Verified by re-opening the exported PDF and reading its `/URI` link annotations: a plain URL, an e-mail (as `mailto:`), a bare `www.` URL, and a formal hyperlink are all present as real clickable annotations. Harness **60/60**, build **0/0**.
- **Adversarial review** (2 dimensions → verify) confirmed and fixed three issues: the detection regex was **O(n²)** on a long unbroken paste (a ~50k-char token could freeze the export for minutes) and matched **mid-token** (a filename like `backup_www.tar.gz` became a bogus link) — a start-of-token lookbehind fixes both (non-boundary positions now fail in O(1)), with an atomic local-part and non-overlapping domain labels removing the remaining backtracking; and a **targetless** formal hyperlink wrapped its whole label as the link — it now routes through the same auto-linker so only the URL portion is clickable. New harness checks confirm a mid-token filename isn't linked and a 40k-char pathological token exports in ~60 ms.

### Rich-text formatting fidelity in PDF export
Closed the biggest gaps between what the rich-text editor shows and what the PDF export produced ([Services/PdfExporter.cs](AA/Services/PdfExporter.cs)). Bold / italic / underline / colour / font / size / alignment / lists / indent / links were already faithful; the remaining gaps were:
- **Tables were dropped entirely.** `RenderBlock` was refactored to render into any MigraDoc container (`DocumentElements`), and a new `RenderTable` turns an editor `Table` into a real MigraDoc table — column widths (absolute px honoured, else even split of the printable width), per-cell borders/shading from the WPF cell, header-row bold, and **colspan/rowspan** mapped to `MergeRight`/`MergeDown` via an occupancy grid. Cell content renders recursively (so lists/paragraphs inside cells work).
- **Strikethrough rendered as underline** (misleading). MigraDoc 6.2 has no strikethrough flag, so struck runs now get the Unicode combining long-stroke overlay (`U+0336`) after each glyph — a genuine line-through that stays selectable — while real underline stays exact.
- **Highlight was dropped.** MigraDoc can't shade a sub-run span, but a **whole-line highlight** (every run in a paragraph sharing one background) now shades the paragraph. Partial (few-word) highlights remain unrepresentable in MigraDoc — the one honest limit, since the alternative (rasterising the note) would break the clickable links above and make text unselectable.
- Verified at the render level (glyph-encoded PDFs can't be text-searched): struck text gets the overlay (not underline), a 2×2 editor table exports as a real 2×2 MigraDoc table with preserved cell text, uniform highlight shades the paragraph while a partial one does not, and a note combining all three exports without error.
- **Adversarial review** (2 dimensions → verify) confirmed and fixed three issues (a surrogate-pair strike bug was refuted — already handled): (med) `RenderTable` under-counted columns when a **pasted** merged-cell table had a rowspan outside the widest row, silently dropping a cell — the column count is now derived by simulating the occupancy grid so every cell survives; (med) the editor's **edit-lock** pale-gold sentinel leaked into the PDF as a paragraph highlight — that specific colour is now excluded from highlight detection; (low) the strikethrough overlay on **spaces** left a stray stroke at a soft-wrap boundary — spaces are no longer struck. Harness **72/72** for the PDF suite, build **0/0**.

### Shared-save cadence + complete items from the floating window
- **Shared save every 1 minute.** The single-file multi-instance sync ([MainWindow](AA/MainWindow.xaml.cs) `_sharedSaveTimer`) now pushes to the shared ZIP bundle every **1 min** instead of 10 (still only when there are changes; the reconcile-then-push and 60 s external-update poll are unchanged).
- **Tick items off in the floating due-dates window.** Every row in [FloatingTasksWindow](AA/Views/FloatingTasksWindow.xaml.cs) now carries its completable model (`Item`) and shows a **done checkbox**. Ticking it marks the underlying task / subtask / procedure / checklist step / crew step / scheduled job complete (`BatchDone.SetDone`), persists, and the item drops off the window (a completed item is neither overdue nor due). The checkbox click is isolated from the row's navigate-on-click (an `OriginalSource`-under-`CheckBox` guard), and the rebuild is deferred so the checkbox isn't torn down inside its own event.
- **Adversarial review** (2 dimensions → verify; 5 raised) confirmed and fixed two issues, and flagged one pre-existing limitation: (med) `Collect(day)` added a procedure with **no done-guard** (unlike every other kind), so a completed today/tomorrow procedure lingered with a ticked box that could then be *un-ticked* back to Todo — the guard `p.Status != WorkStatus.Done` is now applied; (med) the periodic shared-save re-zipped **all attachments synchronously on the UI thread**, which at the new 1-min cadence would freeze the window during editing — the heavy zip is now offloaded to a background thread (mirroring the Drive-sync path) with a running-guard so pushes don't stack, while on-close stays synchronous. **Not changed** (pre-existing, needs its own conflict-tracking design, *not* introduced by the interval): the shared-file sync is timestamp-based **last-writer-wins**, so two PCs editing the same bundle concurrently can still silently lose one side's update — the 1-min cadence changes how often, not the mechanism.
- Harness **8/8** for the window (every row carries a completable item; completing a task/subtask/step/procedure marks each done and drops it off; a completed today-due procedure no longer lingers). Overall suite **110/110**, build **0/0**.

### Board shows every task and nested subtask
The Kanban [Board](AA/Views/BoardPage.xaml.cs) previously showed only top-level `Data.Tasks`. It now flattens the whole tree — **every task and every nested subtask (recursively)** is its own card, grouped by its **own** `WorkStatus`, so an incomplete subtask lands in **To Do** whether or not it has a deadline. `Refresh` builds `FlattenTasks`/`WalkTasks` (depth-first, `HashSet<Guid>` cycle-guard) and each subtask card shows a muted "↳ ancestor › path" so you can tell which task it belongs to. Dragging a subtask card between columns sets only that subtask's status; deleting one removes it from wherever it actually lives (`RemoveTaskAnywhere` recurses into the owning parent's `Subtasks`, warns about descendant count). Search and Hide-done apply to the flattened set. Harness **8/8** (tasks + sub-subtasks land in To Do with no deadline, done subtask in Done, parent path shown on nested cards and empty on top-level, hide-done filters a done subtask, nested delete removes from the parent, and a subtask of an *unnamed* parent still shows a path). **Adversarial review** (2 dimensions → verify; 3 raised, 2 refuted) confirmed one low cosmetic bug — a subtask of an empty-named parent collapsed to a blank path and looked top-level; the path now falls back to "(unnamed)". Overall suite **103/103**, build **0/0**.

### Deadline a whole checklist at once + read-only saved-list item viewer
- **Bulk deadline.** New [Services/BatchDeadline.cs](AA/Services/BatchDeadline.cs) applies **one shared date** to a whole selection of dated items (`TaskItem` / `Procedure` / `ChecklistStep`), and [Views/BatchDeadlineMenu.cs](AA/Views/BatchDeadlineMenu.cs) adds a **"📅 Set deadline for selected…"** right-click entry (with a new [DatePromptWindow](AA/Views/DatePromptWindow.xaml) offering pick-a-date / Clear / Cancel) to every multi-select list: a task's **subtasks**, a procedure's **steps**, the Board, the Calendar schedule, and both Ctrl+N lists. Select the whole list (Ctrl+A) → right-click → one date on everything. It reports only real changes, so a no-op selection doesn't write. A task's **working range stays valid**: clearing the deadline also clears the range start (a range can't exist without its end), and a start later than the new deadline is clamped onto it via `WorkRange.Coerce`.
- **Read-only item viewer.** Double-clicking an item in the Saved Lists tab now opens [ContainerViewerWindow](AA/Views/ContainerViewerWindow.xaml) — the item's notes and file bank, **read-only**: hyperlinks are clickable (a single class-level `RequestNavigate` handler, since the editor's per-link handlers aren't part of the saved XAML) and files open on double-click, so links are reachable without exporting a PDF first. Nothing can be edited, so a reusable saved list can't be changed by accident.
- Harness **13/13** for these (deadline across all three item kinds, no-op detection, range clamp, clear-clears-range; viewer is read-only + document-enabled, renders notes, keeps hyperlinks, lists files, and leaves the saved-list item untouched).
- **Adversarial review** (2 dimensions → verify; 7 raised, 4 refuted) confirmed a **high-severity data-loss bug** the batch deadline exposed, plus a medium variant of the same root cause. The long-lived detail panes (the Ctrl+N window and the Hierarchy *Specifics* tab, which isn't rebuilt on tab switch) coerced the working range against the **sibling DatePicker** instead of the model. After a deadline was set elsewhere — a batch "Set deadline", the Board, the Calendar — that sibling held a **stale** date, so the next nudge of either picker silently wrote the old value back over the new one (and the mirror case resurrected a range start that a clear had just removed), then persisted it. Both handlers in both panes now coerce against the **model** (`t.Deadline` / `t.RangeStart`), so a stale control can never win; the Ctrl+N pane also re-seeds its pickers after a batch change (`SyncDetailDates`). Four regression tests reproduce the original scenario end-to-end. Overall suite **95/95**, build **0/0**.
- **Known pre-existing risk (not introduced here, not yet fixed):** rich-text notes are loaded with the unrestricted XAML reader (`TextRange.Load(DataFormats.Xaml)`) — the same call the editor has always used — so a **maliciously crafted imported save/ZIP bundle** could carry XAML that instantiates arbitrary types on load. Hardening this means restricting the parser on *both* the editor and viewer load paths; worth doing as its own change.

### Floating due-dates window now shows OVERDUE
The always-on-top "📌 Due dates" popup ([Views/FloatingTasksWindow.xaml.cs](AA/Views/FloatingTasksWindow.xaml.cs)) only listed today & tomorrow, so past-due work silently fell off. It now leads with an **OVERDUE** section (red, oldest-first) covering every task/subtask/procedure/checklist-step/crew-step whose **deadline** has passed and that isn't done — a task still inside its working range isn't overdue (it shows under TODAY), and completed items are excluded. The header shows the overdue count, and the section is omitted entirely when nothing is overdue. Harness **5/5** for this (past-due shown, completed hidden, today/future excluded, all item kinds included, oldest-first); overall suite **78/78**, build **0/0**.
