# AA for macOS — manual-only checks

Checks the Stage V verifiers (round 1 and round 2, 2026-10-03) could not run automatically: they need a person at the
keyboard and mouse, a second machine, the Windows PC with the real AA.exe, a real Google account, the iPhone, a real
network share, or a signed bundled build. Rebuilt after round 2 from both rounds' lists: grouped by area,
de-duplicated (one item where several verifiers asked for the same thing; the source IDs are kept in brackets).

How to use it: work on a **copy** of a real data folder (never the ship's live folder). Tick the box, then write the
date and the build (`AA ▸ About AA`) after the item. A failure goes to `Docs/PROGRESS.md` "Known remaining problems"
with the item number and the spec ID.

Tags: **[Win]** Windows PC with the WPF build · **[2 Macs]** a second Mac or macOS user · **[Bundle]** signed
`dist/AA.app` from `Scripts/build-app.sh` · **[Phone]** the iPhone app · **[Google]** a real Google sign-in ·
**[Share]** a real SMB/NAS share · **[Mouse]** real pointer gestures.

Totals: 22 groups, 124 checks.

---

## A. Build, packaging and first launch

- [ ] **A-01 [Bundle]** Bundle assertions (SHELL-180…191, 200…203; V-03, V-PACKAGE).
      Steps: `cd mac && Scripts/build-app.sh`. Expect: exit 0; `lipo -archs` = `x86_64 arm64`; `minos 26.0` in both
      slices; `codesign --verify --deep --strict` valid; only entitlement `com.apple.security.device.camera`;
      resource checksums OK; app under the 60 MB tripwire. (V-PACKAGE ran this once in round 1: all passed.)
- [ ] **A-02 [Bundle]** Gatekeeper and translocation (SHELL-189/190; V-03, V-PACKAGE).
      Steps: zip `dist/AA.app`, download/quarantine it, open it from `~/Downloads` by double-click; then move it to
      `/Applications` and open again. Expect: Gatekeeper's ad-hoc procedure works as SHELL-189 documents; from
      Downloads the "Move AA to Applications" sheet appears once per launch; from /Applications it does not.
- [ ] **A-03** Intel / clean machine (SHELL-207; V-03, V-PACKAGE, V2-SCALE).
      Steps: run the universal app on an Intel Mac (or under Rosetta) and on a Mac that never ran AA. Expect: the
      x86_64 slice launches, splash → login → main window; no crash report. Note save/load/search timings on the
      slower machine (Apple Silicon reference: autosave serialise 418 ms, load 809 ms, search 779 ms, Flash Sync
      prepare 1.24 s on a 70 MB file).
- [ ] **A-04 [Bundle]** Variants (V-PACKAGE). Steps: `PACKAGE=dmg Scripts/build-app.sh` and `PORTABLE_LAUNCHER=1
      Scripts/build-app.sh`. Expect: both build; the dmg mounts and the app inside launches.
- [ ] **A-05 [Bundle]** Preferences domain split (V2-SCALE). Steps: note `defaults read com.eriskay.aa` of the installed
      app; run a dev build (`swift run AA --data-dir …`) and a snapshot run; read the domain again. Expect: the bundled
      app uses its standard domain; dev and snapshot runs use the suite `com.eriskay.aa` and leave the installed app's
      settings unchanged.

## B. Launch, login, quit, crash

- [ ] **B-01** Real launch and login (SHELL-003/004/204; V-03, V2-J8).
      Steps: launch the bundled app from Finder; wait on the splash; type the username, Tab, a wrong password, Return;
      then the right password, Return. Expect: splash centred for ~2.4 s, never key, no `makeKeyWindow` /
      `-layoutSubtreeIfNeeded` warning in Console; Return in either field submits; a wrong password clears the field
      and focus returns to it; the login card hugs its rows (no tall blank above Exit / Sign in, round 2).
- [ ] **B-02** Login closed = quit (SHELL-004; V2-J8). Steps: at the login window press ⌘W, then relaunch and click the
      red close button. Expect: AA quits each time; `data.json` and `settings.json` are byte-unchanged (`shasum`).
- [ ] **B-03** Window geometry (SHELL-204, Ui.Window*; V-03, V2-J8). Steps: move and resize the main window, quit,
      relaunch; zoom to full screen, quit, relaunch; put the window on a second monitor, quit, unplug that monitor,
      relaunch. Expect: same frame; maximized/full-screen state restored; the window comes back on the remaining
      screen, fully visible.
- [ ] **B-04** Quit with a failing final save (V2-J8). Steps: put the data folder on a USB stick, edit, unplug the stick,
      ⌘Q. Choose Retry (fails again), then Cancel. Expect: Retry / Quit Anyway / Cancel offered; Cancel keeps AA open
      and restores autosave, shared sync and reminders (an edit made afterwards is saved once the stick is back).
- [ ] **B-05** Crash report (V2-J8). Steps: `kill -SEGV <AA pid>` while running; relaunch. Expect: the launch shows
      "AA — error" naming the `crash.log` path; the file exists and holds the signal.
- [ ] **B-06 [2 Macs]** Second instance and read-only copy (DATA-172/173/174; V-01, V2-J8, round-1 W-DRIVE item).
      Steps: with AA running, `open -n` a second copy on the same folder; then repeat as another macOS user (fast user
      switching). Choose "Switch to Running AA", then on another try "Open Read-Only". In the read-only copy open
      Settings ▸ Sync and press ⌘S. Forward a `.json` and an `.aaz` to the running copy from Finder. Expect: the
      second-launch alert; "Switch" brings the first copy forward; the read-only copy shows the "Read-Only" subtitle,
      the ⌘S sheet, DATA-174 menu items disabled with their help text, the six Drive buttons disabled with "Not
      available in a read-only copy of AA."; a forwarded `.json` goes to Import from File, an `.aaz` to import with
      preview.
- [ ] **B-07 [2 Macs] [Share]** Lease mode (DATA-177; V-01). Steps: data folder on an SMB/NFS share opened by two Macs;
      take over on Mac B; sleep Mac A past the lease. Expect: heartbeat keeps the lease; Take Over works; Mac A reports
      the lease lost after waking and stops writing.
- [ ] **B-08** Opening `.aaz` from Finder (SHELL-185; V-03, V2-J4). Steps: with AA running, double-click an `.aaz` in
      Finder, then drop one on the Dock icon; quit AA and double-click an `.aaz` again. Expect: each goes through the
      import-with-preview flow (review sheet), never a silent import.

## C. Menus and keyboard

- [ ] **C-01** Undo routing (REPO-077, HIER-024/123, SHELL-521; V-02, V-04, V-03, V2-J1).
      Steps: type in the container editor, ⌘Z; click a text field, type, ⌘Z; select three sidebar rows, Delete
      selected…, click the sidebar, open the Edit menu, ⌘Z; with nothing to undo press ⌘Z. Expect: ⌘Z undoes text in
      the editor and the field; with the sidebar focused the menu reads "Undo Move to Trash (3 Items)" and ⌘Z
      restores all three in their original order; ⌘Z is ignored for the batch while a text field has focus; with
      nothing to undo the status line says "Nothing to undo.".
- [ ] **C-02** Section shortcuts on other layouts (SHELL-511, T-KB-41/42; V-03, V2-J8). Steps: switch the input source
      to French AZERTY, then German; press ⌘1…⌘9, ⇧⌘7 and ⌘1 on the numeric keypad. Expect: ⌘1…9 select sections
      1…9 on every layout; ⇧⌘7 keeps its own command; keypad ⌘1 selects section 1.
- [ ] **C-03** ⌘Q / ⌘W with sheets (SHELL-505/513, T-KB-39/40/43/44; V-03). Steps: open a decision sheet (e.g. import
      review), press ⌘W, then ⌘Q; repeat with a close-type sheet (e.g. Trash). Expect: as the T-KB rows say — decision
      sheets block, close-type sheets close.
- [ ] **C-04** Menus with a key window (SHELL-640; V-03, V2-J8). Steps: with the main window key open View, then open
      an item window, a search window and a quick-work window and open the Window menu. Expect: View ▸ Enter Full
      Screen is present; the Window menu lists each open item / search / quick-work window.
- [ ] **C-05** Sidebar rename keys (HIER-018/025; V-04, V2-J1). Steps: focus a sidebar row, press Return; Esc; press
      F2; type a new name with A→Z on; Return. Expect: Return and F2 put focus in the Name box with the text selected
      and do NOT open the item in a new window; typing does not move the cursor; Return commits and the list re-sorts.

## D. Notifications, Dock badge, menu-bar item, daily digest

- [ ] **D-01 [Bundle]** Permission and banner (REPO-112/113, SHELL-130/131, QUICK-001, CREW-092, VESSEL-121; V-02,
      V-03, V-08, V-09, V-10, V-12, V2-J5, V2-J8). Steps: first launch of the bundled app with overdue tasks, an
      expiring crew contract and a flagged overdue work order; allow notifications; keep AA frontmost, then hide it.
      Click the banner. Expect: one permission prompt; "AA — due soon" banner (also while frontmost) with
      "  ·  {n} crew contract(s) expiring"; the Mac-only work-order overdue notification; clicking opens the due-dates
      panel; the Dock badge shows the overdue count and clears at quit.
- [ ] **D-02** Menu-bar item (SHELL-130, REQ-W-SHELL-02; V-03, V2-J8). Steps: on this Mac `defaults read com.eriskay.aa`
      shows `aa.menuBarExtra = 0` and "NSStatusItem VisibleCC Item-0 = 0" — launch the bundled app; then hide the item
      with macOS 27's menu-bar control and relaunch; then turn it off in Settings and relaunch. Expect: the first launch
      repairs and shows the item; the headline matches the due panel; a user-hidden item stays hidden and the repair
      runs only once.
- [ ] **D-03** Day rollover digest (QUICK-001; V-08, V2-J8). Steps: leave AA running over local midnight; separately,
      sleep the Mac over midnight and wake it; switch to a second data file. Expect: the digest reopens the due panel
      once per day per data file, never twice.

## E. Hierarchy pages and item windows

- [ ] **E-01 [Mouse]** Drag to group (HIER-M01; V-04, V2-J1). Steps: select several rows; drag onto a group header, onto
      a group placeholder, onto an empty "Ungrouped (0)" header. Expect: drop highlight; `GroupId` updates; the file is
      saved at once.
- [ ] **E-02** Multi-window (§7.13, HIER-110…113; V-04, V2-J1). Steps: double-click a sidebar row; double-click it again;
      open two tasks and a procedure in windows, type in each, ⌘S, quit, relaunch; delete a detached item from the
      sidebar / Board / quick work; reload (⌘R) while a window is open; close an item window. Expect: one window per
      item (the second double-click focuses it); edits survive the relaunch; a deleted item's window closes; after
      closing, the main pane re-attaches its editor with the edits intact.
- [ ] **E-03** Lock Now with item windows (HIER-056, Q-18; V-04, V2-J1). Steps: open a protected item in its window and
      unlock it; Tools ▸ Lock Now (⌃⌘L); unlock in the item window; lock again and unlock from the main pane. Expect:
      the window shows the lock gate in place; unlocking in either the window or the main pane releases both; the main
      pane reloads a non-gated item's editor.
- [ ] **E-04** Manage lock (V2-J1). Steps: on a locked item use Manage lock ▸ Change Password / Hint…, OK. Expect: the
      main pane re-gates at once; status line "Lock updated.".
- [ ] **E-05** Step toggles (§8 Q-23; V-04). Steps: double-click a step's Done and Job toggles in the W-BUILD grid.
      Expect: the toggles flip; the step editor does not open.
- [ ] **E-06** Selection colour (HIER-150; V-04). Steps: click into the sidebar list (key) in light and dark. Expect:
      selection `#CCE8FF` (light) / `#094771` (dark); grey only when the list is not key.
- [ ] **E-07** Locked search hit (REPO-100; V-02). Steps: ⌘F, search a word inside a password-locked item, double-click
      the hit. Expect: the item opens on its lock screen, nothing of its text shown.

## F. Rich-text editor

- [ ] **F-01** Clipboard paste from real apps (CONT-034…038, §6.6; V-05, V2-J3). Steps: paste into a note from Word,
      Excel, Pages, Safari and Chrome (paragraphs, a bulleted list, a nested numbered list, a table); paste an image
      from Preview and Safari; drop an image file on the paper. Expect: lists and tables stay lists and tables (the
      first pasted cell stays a cell; text typed below a pasted table is an ordinary paragraph); one ⌘Z removes the
      whole paste; images go to the File Bank with the notice "Notes can't hold pictures, so it was stored as a file.".
- [ ] **F-02** Spelling menu (CONT-033; V-05, V2-J3). Steps: misspell a word; right-click it; lock a misspelled word and
      right-click it. Expect: suggestions and Ignore Spelling on the plain word; "(locked — can't correct)" on the
      locked word, and choosing a suggestion changes nothing.
- [ ] **F-03** Find and replace over locked text (V2-J3). Steps: ⌘F in a note, find a word that is partly locked,
      Replace and Replace All; ⌘G; pinch to zoom on the trackpad. Expect: locked text is never replaced; unlocked
      matches are; ⌘G moves to the next match; pinch zooms the paper.
- [ ] **F-04** Fonts and Colors panels (V-05, V2-J3). Steps: ⌘T, change family and size on unlocked and on locked
      text; ⇧⌘C, Other…, pick a colour. Save and inspect the stored XAML (Export or debug dump). Expect: formatting is
      allowed on locked text (D-4); the stored `FontFamily` is the plain family name the Windows build can load.
- [ ] **F-05** Lock hint styles (V2-J3). Steps: type into locked text in the main window, then in an item window, a
      component window and a subtask window; repeat quickly. Expect: the main window shows the status-line hint; the
      other windows beep and show the inline notice, at most once per 1.5 s.
- [ ] **F-06** Save debounce (V-05). Steps: type, stop, watch `data.json`'s mtime. Expect: written ~400 ms after the last
      keystroke.

## G. File bank and attachments

- [ ] **G-01 [Mouse]** Drag in (CONT-085, SHELL-679; V-05, V2-J4). Steps: drag a file, a folder and a macOS package
      (`.rtfd`, `.pages`) onto the file bank and onto the paper — plain, with ⇧, with ⌥⌘. Expect: plain = a copy; ⇧ and
      ⌥⌘ = link in place; a folder or package becomes one `.zip` entry.
- [ ] **G-02 [Mouse]** Drag out (V-05, V2-J4). Steps: drag file-bank rows to Finder (plain and ⌘-held), to Mail, and
      onto the Dock Trash. Expect: Finder and Mail get copies; the attachment in AA's `files/` is never moved or
      trashed.
- [ ] **G-03** Pasteboard (V-05). Steps: Finder ⌘C on files → file bank Paste; file bank Copy / Cut → paste in Finder.
      Expect: imported as copies; Finder receives the files.
- [ ] **G-04** Quick Look (V-05, V2-J4). Steps: select rows, Space, then ⌘Y; arrow through rows. Expect: the panel opens
      and follows the selection; thumbnails show (the headless probe reported the panel inactive).
- [ ] **G-05** Opening files (CONT-089…091; V-05, V2-J4). Steps: open PDF, DOCX, XLSX, PPTX, JPG, PNG, TIFF, HEIC, MOV
      and MP4 entries; Open With ▸; Open All on more than 15 entries; Show in Finder. Expect: each opens in its default
      app; Open All asks for confirmation above 15 with the spec text.
- [ ] **G-06 [Share]** UNC and drive-letter paths (CONT-089…091; V-05, V2-J4). Steps: on a mounted SMB share with no
      path mapping, link a file in place; open an unmapped `\\server\share\…` entry and choose Connect to Server…;
      open a `Z:\…` entry with and without a mapping. Expect: the stored path is UNC (`\\server\share\…`) and the
      Windows PC opens it; Finder mounts the share and the open retries within 15 s, opening exactly once; mapped
      drive letters open, unmapped ones offer recovery.
- [ ] **G-07** Other volumes (V2-COMPAT). Steps: put the data folder on HFS+ and exFAT drives (ARA1 / EE5), attach a
      file named with accents ("Café menu.pdf"), export a bundle. Expect: stored names and ZIP entry names are NFC; the
      attachment opens; nothing is swept as an orphan on re-import.

## H. Builders and saved lists

- [ ] **H-01** Builder keys (SHELL-667, BUILD-139/147; V-06). Steps: in a builder list press Return; in the bulk text
      view press ⌘Return; open a text prompt over a builder sheet, press Esc and ⌘. . Expect: Return = Edit… (not the
      sheet's Close); ⌘Return = Add all; Esc / ⌘. cancel only the prompt.
- [ ] **H-02 [Mouse]** Reorder (06 §6.2; V-06, V2-J7). Steps: drag-reorder rows in each builder and saved lists inside a
      group; right-click a row that is not selected. Expect: order changes and saves; right-click selects the row
      under the pointer.
- [ ] **H-03** D3 rescue (06 §8 D3; V-06). Steps: open a template in the editor, delete it via "Manage saved lists…"
      inside the editor, then Close / ⌘W. Expect: "Save as New List" / "Discard Changes" appears on the editor's window
      and uses the list's latest name.
- [ ] **H-04** ItemPicker (V-06). Steps: tick items, filter, clear the filter; in single-select double-click a row.
      Expect: ticks kept across filtering; double-click = choose + OK.
- [ ] **H-05** Saved Lists at the minimum window size (round 2). Steps: shrink the main window to its minimum with the
      sidebar shown, open Saved Lists. Expect: both panes fully visible, nothing clipped at either side.

## I. Calendar, Board, Planner, Buckets, Map

- [ ] **I-01 [Mouse]** Board drag (VIEW-047; V-07, V2-J2). Steps: drag a card to another column; drop one on its own
      column; drag a recurring top-level task to Done. Expect: column glow and card-shaped preview; status set and saved
      at once; same-column drop does nothing; the recurring task spawns exactly one new To Do card.
- [ ] **I-02** Board selection and keys (V-07). Steps: ⌘-click / ⇧-click cards in one column; ⌘A; ⌘⌫; Return. Expect:
      per-column selection; ⌘A selects the focused column; ⌘⌫ deletes to Trash (⌘Z restores, top-level and nested);
      Return opens.
- [ ] **I-03** Board open files (VIEW-051; V-07). Steps: "Open all files (routine)" on a card with real files, web links,
      more than 15 files, and unreachable Windows drive-letter paths. Expect: Open All / Cancel above 15; unreachable
      paths skipped silently.
- [ ] **I-04 [Mouse]** Planner drags (VIEW-100…103; V-07, V2-J2). Steps: pool row → hour grid; timed block → another day
      in Week; due chip → month cell; block → pool. Expect: 15-minute snap under the pointer with the dashed ghost; a
      timed item keeps its time; a ranged task slides its whole range; block → pool unschedules.
- [ ] **I-05** Planner open and navigate (Q-07; V-07). Steps: double-click a block, a chip and a pool row; double-click
      a procedure; ⌘← ⇧⌘T ⌘→. Expect: the subtask / checklist-step editor opens; a procedure navigates to Procedures;
      previous / today / next.
- [ ] **I-06** Calendar (V-07, V2-J2). Steps: tick an inline Done box; in Agenda tick one occurrence of a recurring task;
      double-click rows; right-click a multi-selection ▸ Mark done / not done / Set deadline (and Clear deadline);
      hover the Agenda segment; A- / A+ and ⌘− / ⌘+ several times, quit, relaunch. Expect: saves at once; sibling
      occurrences update together; the right editor opens (procedures navigate); tooltip "All upcoming tasks grouped by
      day."; text size steps by 1.5 within 11…28 and survives the relaunch.
- [ ] **I-07** Buckets (V-07). Steps: + New bucket (two prompts); Rename; Set category; Delete; double-click a member;
      Remove from this bucket. Expect: alerts as specified; members navigate or open their editor.
- [ ] **I-08** Relationship Map (V-07, V2-J1). Steps: click a node; double-click a node; context menu Show in {Section} /
      Open in New Window; zoom, pinch, Fit, Center. Expect: a single click recentres with animation and moves the
      Inspect selection without a noticeable delay; double-click navigates.
- [ ] **I-09** Quick work bucket picker (VIEW-153/213; V-07, V2-J2). Steps: ⌘N; type in the Name box; ⇧-click and
      ⌘-click rows, right-click; pick three buckets. Expect: typing does not rebuild the list; right-click follows the
      selection rule; the first two picks are kept in selection order with the cap alert.

## J. Quick and floating windows

- [ ] **J-01** Due-dates panel (QUICK-002/003/006, §6.5; V-08, V2-J2). Steps: open it, switch to another app; enter a
      full-screen Space; drag by the header, then by the body; resize from the corner grip and from the edges; quit,
      relaunch, ⌘R; tick a row; tick a recurring row. Expect: stays above other apps and joins full-screen Spaces; only
      the header drags; the size persists (`Ui.DueWindowWidth/Height`); a ticked row animates out; the next occurrence
      appears after the save.
- [ ] **J-02** Switcher and search (QUICK-106/125, SHELL-673; V-08, V2-J7). Steps: ⌘O, ↑/↓ past both ends, Return, Esc,
      click elsewhere; ⌘F, type, Return in the query, ↑/↓ and Return in the results on a component / subtask / step hit.
      Expect: arrows clamp; Return opens and brings the main window forward; Esc and losing key close; Return in the
      query searches; Return on a result navigates and selects the matched child in its page.
- [ ] **J-03** Trash sheet keys (QUICK-173, SHELL-675; V-08). Steps: in the Trash sheet ⌘⌫, ⌥⌘⌫, ⇧⌘⌫, Esc, ⌘W. Expect:
      as the shortcut table says; Esc / ⌘W close.
- [ ] **J-04** Quick work editors (QUICK-077; V-08). Steps: from quick work choose Edit… and Open Full Builder… on a task,
      a step, a subtask. Expect: the W-BUILD editor / builder opens on the quick-work window and the children list
      refreshes after Close.
- [ ] **J-05** Activity log export (REPO-092, QUICK-155; V-02, V2-J7). Steps: Activity log ▸ Export (.csv)…; note the
      default name; open the file in Numbers and Excel. Expect: default name per spec; columns intact, dates readable.

## K. Crew

- [ ] **K-01** Real COMPAS import (CREW-030…040; V-09, V2-J5). Steps: import a real crewing-office report (merged
      cells, Excel-typed dates, a 1904-dated workbook) through the open panel; on the date-order question press Return,
      then retry and press Esc, then retry and choose Day First. Expect: Return and Esc both cancel (nothing imported, no
      log); Day First imports; the expiry warning follows; status text per CREW-038.
- [ ] **K-02** Crew exports (CREW-105, §7.13; V-09, V2-J5). Steps: export `crew-yyyy-MM-dd.xlsx`; use Open and Show in
      Finder; open it in Excel (Mac and Windows) and Numbers. Expect: bold shaded header; Due Date / Last Done Date as
      text (`@`); Overdue Days numeric; no repair prompt.
- [ ] **K-03** Crew editing (CREW-062/073/102; V-09, V2-J5). Steps: delete a member, ⌘Z, then restore another from File ▸
      Trash; in the editor change a date with the picker and type in the text; reorder the column chooser by drag, Space
      to toggle, ⌃⌘↑/↓; ⌫ in the roster; ⌥⌘F; Return in the editor. Expect: undo/restore work (text-field focus rules
      respected); the picker writes the text one-way; column order persists; ⌫ deletes; ⌥⌘F focuses search; Return =
      Save.
- [ ] **K-04** Crew windows and appearance (V2-J5). Steps: open the crew table window and the editor sheet, switch macOS
      light/dark. Expect: both follow at once, no stale colours.

## L. Vessel, ports, work orders, quick cards

- [ ] **L-01 [Mouse]** Quick cards (VESSEL-017/018/019/028/043…050; V-10, V2-J5). Steps: drag-move a card; corner
      resize; double-click; context menu; Return / Space (Quick Look) / ⌫ on a focused card; Finder drag-in plain and
      with ⌥; set a custom colour in the colour panel. Expect: smooth move/resize saved; double-click opens; ⌥ = link in
      place; colour stored.
- [ ] **L-02** Card targets (VESSEL-025; V-10, V2-J5). Steps: open a web link, a folder, an imported copy, a UNC path;
      choose "Open File Links Settings…"; on a missing share use Connect to Server… / Locate…. Expect: browser, Finder,
      the default app; UNC recovery works against a real share.
- [ ] **L-03** Work orders and ports import (VESSEL-101/201, X.7.3; V-10, V2-J5). Steps: import a real 2,500-row Shippalm
      export through the open panel (Excel / All files accessory) and by Finder drop; import both port-call layouts.
      Expect: busy overlay while reading; timing acceptable; counts as in the file.
- [ ] **L-04** Vessel exports (VESSEL-103/205; V-10, V2-J5). Steps: export `WorkOrders-<ship>.xlsx` and
      `Ports-<ship>.xlsx`; open in Excel (Mac, Windows) and Numbers. Expect: header bold and shaded; date columns text;
      numbers numeric; no repair prompt.

## M. SIRE 2.0

- [ ] **M-01** Loaded tab and body editing (SIRE-020…025, §6.4; V-12, V2-J3, V2-J7, V-DESIGN). Steps: open the SIRE tab and
      wait for the bank; select a question; in the body select text and type, press Enter, ⌫, ⌘X, drag text, use Writing
      Tools / autocorrect / Find-Replace; paste plain and rich text; ⌘Z; right-click; click away; ↺ Reset; drop a file.
      Expect: three-pane layout; typing inserts before the selection; ⌫ / ⌘X / drag / replace change nothing; paste
      inserts (rich content flattened to paragraphs, Deviations D-SIRE-R2); context menu is exactly Copy / Paste
      (insert) / Select All; edits flush after 750 ms and on focus loss; Reset restores the original; drops refused.
- [ ] **M-02 [Google]** Gemini (SIRE-029/038, §6.9; V-12, V2-J7). Steps: Tools ▸ Set Gemini API Key…, enter a valid key;
      select a question, AI Suggest, switch question while it runs; repeat with a bad key and with no network; Settings ▸
      AI Clear; copy a Windows `settings.json` holding `GeminiApiKey` into a fresh folder and launch. Expect: Keychain
      prompt as applicable; "Asking Gemini…" busy state; the result goes to the question selected when the request
      started; clear error texts; Clear removes the Keychain item; the Windows key is imported once.
- [ ] **M-03** SIRE export (§7.12 #9; V-12, V2-J7). Steps: Tools ▸ SIRE 2.0 Export… ▸ Copy, Save…, Share…, Print….
      Expect: status "SIRE export copied to clipboard."; the saved file is UTF-8 without BOM; Share and Print work.

## N. PDF, XLSX and CSV exports

- [ ] **N-01** Save panels and defaults (PDF-006/012; V-11, V-06). Steps: Export PDF…, Export checklist (PDF) and (Excel),
      the three Saved Lists exports; overwrite an existing file. Expect: default names (e.g. `Task-Check_ A_B.pdf`);
      overwrite confirmation; checklist PDF opens in Preview, XLSX in Numbers/Excel; saved-list "Export complete" Open /
      Not Now / Show in Finder work; the `.aasched.json` export / import panels (crew Schedule tab) offer the "All files"
      accessory.
- [ ] **N-02** PDF look (BUILD-C1/C3; V-06, V-11, V2-J7). Steps: open the generated PDFs in Preview. Expect: layout per
      spec, "Page X / Y", headings, bulleted and numbered lists, embedded rich-text notes and links.
- [ ] **N-03** Excel open (V-11). Steps: open the checklist `.xlsx` in Microsoft Excel. Expect: no repair prompt.
- [ ] **N-04** Print (V-11). Steps: File ▸ Print… (⌘P) on an item. Expect: the print sheet shows the item at 100 %.
- [ ] **N-05** Busy sheet and keys (V-11). Steps: export a large list (> 300 ms); on the List style sheet press Esc and
      Return. Expect: the busy sheet appears; Esc cancels, Return confirms.
- [ ] **N-06** Menu state (⌥⌘E; V-11). Steps: select an item; then a gated item; then a detached item. Expect: File ▸
      Export as PDF… enabled only for the first.

## O. Shared save, data folder, conflicts

- [ ] **O-01** Indicator and popover (SHELL-023/526; V-03, V2-J6). Steps: in a normal launch set a shared save file; open
      the indicator popover, Check Now, Push Now; hide the toolbar; pull the network cable. Expect: indicator in the
      toolbar (bottom bar when the toolbar is hidden); "⚠ Shared save OFFLINE since …" in red; Check / Push work.
- [ ] **O-02 [Win] [Share]** Windows peer (DATA-185; V-01, V2-J6). Steps: a Windows AA and this Mac share one bundle on an
      SMB/NAS share or the Parallels `\\Mac\Home` path; edit on both; keep the bundle open on Windows while the Mac
      pushes. Expect: edits flow both ways; a rename failure shows "NOT SAVING" and is retried.
- [ ] **O-03 [2 Macs] [Share]** Race during a push (V2-SCALE). Steps: Mac A keeps editing during a 1-minute push that
      carries large attachments; then Mac B edits and pushes. Expect: A's edit made during the push survives (fixed in
      round 2, W-PERSIST-21).
- [ ] **O-04 [2 Macs] [Share]** Refused close push (V2-J6 blocker, fixed in round 2, W-PERSIST-23). Steps: B edits and
      pushes; A edits and quits before its poll sees B's push; relaunch A; answer Reload once, and on a second run Keep
      Mine. Expect: A asks at relaunch; Reload brings in B's edit (A's own is in a `-mine` conflict copy); Keep Mine keeps
      a `-theirs` copy before A's push replaces the bundle.
- [ ] **O-05 [Share]** Corrupt bundle (V2-COMPAT). Steps: replace `aa-shared.zip` on the share with a truncated copy.
      Expect: the shared-save tick survives (no crash) and reports it.
- [ ] **O-06** Conflict copies (DATA-181). Steps: create conflicts, open File ▸ Conflict copies, preview, restore. Expect:
      `-mine` / `-theirs` listed, preview readable, restore loads it.
- [ ] **O-07** Shared-with-Windows help (DATA-184; round-1 W-PERSIST). Steps: trigger the shared-with-Windows banner and
      press Show Me How. Expect: the help names File ▸ Shared Save ▸ Set Shared Save File….

## P. Google Drive

- [ ] **P-01 [Google]** Sign-in (TOOLS-008, §6.3, DATA-073; V-14, V-01, V2-J6). Steps: Sign in (Desktop OAuth client, consent
      screen in Testing); Open Browser Again; Cancel in the sign-in sheet; let one attempt run 5 minutes. Expect: loopback
      redirect and the "Received verification code" page; Cancel and the timeout end cleanly; a token is stored.
- [ ] **P-02 [Google]** Drive round trips (TOOLS-014/016/019/022, Q-1/Q-6; V-14, V2-J6). Steps: upload to "AA Backups"
      and Open in Browser; list the whole Drive incl. shared drives and more than 200 results; download from a shared
      drive; push and pull `AA Sync/AA-sync.zip` above 8 MiB. Expect: all succeed; resumable 308 chunks; paging.
- [ ] **P-03 [Google]** Drive for desktop (TOOLS-002/005; V-14, V2-J6). Steps: with Drive for desktop installed, use the
      synced-folder copy; make a bundle a dataless placeholder (Remove download) and load it. Expect: auto-detected
      folder; the copy uploads; the placeholder is downloaded before reading.
- [ ] **P-04 [Google] [Win] [Phone]** Cross-machine (TOOLS-017/025/026/029; V-14). Steps: the Windows build reads the Mac's
      `AA-sync.zip` (appProperties `aaLastModified`, `aaIdentity`) and the Mac reads a Windows push; restore iPhone
      `.aaz` backups (normal and `-dataonly`) through Load. Expect: both directions load; data-only keeps attachments.
- [ ] **P-05 [Google]** Error texts (TOOLS-034; V-14). Steps: provoke access-denied / insufficientPermissions. Expect: the
      texts with the setup hint.
- [ ] **P-06 [Bundle]** Token Keychain (TOOLS-011/012; V-14). Steps: first use of `google-token-key` in signed and unsigned
      builds; copy a Windows AADPAPI1 token folder in and launch. Expect: Keychain prompt behaviour noted; the
      re-consent notice appears.

## Q. Flash Sync (iPhone, camera)

- [ ] **Q-01 [Phone] [Bundle]** Camera path (FLASH-030/033…039, SHELL-183; V-13, V-03). Steps: Flash Sync ▸ Receive on the
      bundled app; allow the camera; pick devices; cover the lens; unplug a USB camera mid-run. Expect: the SHELL-183
      prompt text; real device names; 1080p; mirrored preview; the 1.2 s watchdog and the interruption texts.
- [ ] **Q-02 [Phone]** Optical round trip (FLASH-037/041, §7.8 item 3; V-13, V2-J6, V2-COMPAT). Steps: send a change set and
      a snapshot from the iPhone to the Mac camera and from the Mac's flashed codes to the iPhone; include data with
      unknown members and number lexemes `1.50`, `-0`, `1E-05`; use "The iPhone says it got it". Expect: applies on both
      sides; unknown members and lexemes preserved; `QuickViewPinIds` travels, `DueWindowWidth/Height` do not;
      Vessels / Ports round-trip (VESSEL-284).
- [ ] **Q-03** Presentation (FLASH-024/130/134; V-13). Steps: flash a long snapshot full screen on an external display;
      move the mouse, click, Esc; receive a change that flips Dark mode. Expect: the display does not sleep; cursor
      hidden; click / Esc return; the window re-themes per the stored Light/Dark/System choice.
- [ ] **Q-04 [Win]** Interop CLI (FLASH-120/121; V-13, V2-J6). Steps: C# `encode` → Swift `decode`, Swift `encode` → C#
      `decode`, then cs-build / cs-apply / snap-build / snap-apply against the C# CLI; a Windows PC applies a Mac-sent
      change set. Expect: byte-for-byte equal (the Swift side passes all vectors).
- [ ] **Q-05** Review sheet default (round-1 W-FLASH). Steps: in the snapshot review sheet press Return. Expect: Don't
      Apply is the blue default button and Return triggers it.

## R. Encryption, passwords, Keychain

- [ ] **R-01** Password sheets (CONT-062; V-05). Steps: Set / Unlock / Change password, including the master password,
      and Touch ID if offered. Expect: the sheets accept input and report as specified.
- [ ] **R-02** Legacy `enc:` notes (05 D-1, D-5; V2-J3, round-1 D-5). Steps: open a note encrypted on the Windows PC with
      its real salt — with the app password, the master password, and a wrong password; then Set / Change Password….
      Expect: the app password decrypts; master / wrong show the withheld banner and keep the ciphertext; Change
      Password warns before orphaning undecryptable bodies and reports how many it decrypted.
- [ ] **R-03 [Bundle]** Encrypt Local Data File (V2-J6). Steps: turn it on for the first time in the bundled app; quit,
      relaunch. Expect: Keychain prompt behaviour noted; the file starts `AAENCM1`; codesign/Gatekeeper unaffected.

## S. Windows interoperability [Win]

- [ ] **S-01 [Win]** Golden fixtures (DATA-315…320/326, X.7.6; V-01, V-E2E). Steps: install the .NET 10 SDK, run
      `Scripts/fixtures.sh generate`, commit `Tests/AACoreTests/Fixtures/winfixtures`, rerun the tests. Expect: the
      WinFixtures and XlsxGolden suites run instead of skipping and pass — required before release (01 §7.14-1).
- [ ] **S-02 [Win]** WPF captures (DATA-321/322/325, W01–W18, W23; V-01, V-E2E). Steps: run WinCapture on Windows,
      including clipboard capture from Word, Excel, Outlook and a browser. Expect: captures committed; Mac readers pass.
- [ ] **S-03 [Win]** AA.exe confirmations (DATA-323/324; V-01). Steps: M-01…M-09 in the real AA.exe; the Windows run of
      WinFixtures (Windows paths, DPAPI AAENC1/AADPAPI1 W19, Explorer ZIP W21). Expect: all as specified.
- [ ] **S-04 [Win]** Mac-written XAML in WPF (05 §7.7 item 10, §9 Q1; V-05, V2-J3). Steps: open in the Windows build a note
      saved on the Mac with every Spec-05 feature (`snapshots/r2-V2-J3/j3-written.xaml`). Expect: `TextRange.Load` does
      not throw; sub/superscript, Underline + Strikethrough, the nested Circle list, LowerLatin nested numbering, 0.6
      table borders and the lock sentinel all show.
- [ ] **S-05 [Win]** Real data round trip (DATA-314, SHELL-206; V-03, V-E2E, V2-COMPAT, V2-J5, V2-J7, V-10, V-12, V-06,
      V-09). Steps: mount ARA1; copy a real Windows `data.json` (DPAPI off) into a test folder; open on the Mac; edit one
      field in each area — crew (flags, checklist, schedule), vessel (quick cards, jobs, port calls, Ports DB), saved
      lists (groups, order, SortAZ, a `GroupId` pointing at a deleted group), SIRE (statuses, bookmarks, tasks,
      QuestionBodies, quick-add items); save; open it in AA on Windows; then back. Expect: everything loads with the same
      meaning on both sides; untouched values byte-identical; Severity stays an integer.
- [ ] **S-06 [Win]** Recurring spawn (V2-J2). Steps: on the Mac complete a recurring task (clone Deadline written
      `2026-10-12T00:00:00`, no offset); open the file on Windows. Expect: the clone shows on Calendar, Board and Planner;
      Windows does not spawn again (source `RecurrenceSpawned=true`).
- [ ] **S-07 [Win]** Trash, locks, tab order (REPO-076, T-TR-7, HIER, SHELL-028; V-02, V-04, V-08, V-03). Steps: on the Mac
      trash items incl. a subtask (unknown member `ParentTaskId`), set item-lock hashes, drag-reorder the sidebar
      sections; open on Windows, restore from Trash, unlock. Expect: restores work; hashes verify; `TabOrder` read.
- [ ] **S-08 [Win]** Bundles both ways (V2-J4, V2-COMPAT, QUICK-193). Steps: import on Windows a Mac-made full `.aaz` with
      non-ASCII and sanitised leaves (e.g. "Café menu.pdf"; UTF-8 flag 0x800) and a text-only `.aaz`; import a Windows-made
      bundle on the Mac and check the review sheet keys (Esc = Cancel, Return = Import (Overwrite)). Expect: no
      extraction failure; the accented attachment opens and the PC's existing NFC copy is not swept as an orphan; text-only
      leaves attachments untouched.
- [ ] **S-09 [Win]** Schedules and spreadsheets (REPO-153/154, CREW-085/086, T-SCH-8, VESSEL-103; V-02, V-09, V-10, V2-J5).
      Steps: export `.aasched.json` from the Mac crew Schedule tab, import on Windows, and the reverse; re-import a Mac
      work-order export on Windows (ClosedXML). Expect: round trips are lossless.
- [ ] **S-10 [Win]** CSV byte compare (QUICK-155, §4.6, T-AL-2; V-08). Steps: export the activity log on both machines from
      the same data in the same time zone. Expect: byte-identical.
- [ ] **S-11 [Win]** Hour-only offset (V2-COMPAT, 01 §4.1.5). Steps: on Windows load a hand-edited value
      `2026-10-03T07:05:09+05`. Expect: record whether System.Text.Json accepts it (the Mac rejects it).
- [ ] **S-12 [Win]** SIRE harness (Q-1/Q-2/Q-16/Q-18; V-12). Steps: capture golden XAML (BuildQuestionXaml 1.1.1, 2.1.1,
      11.1.2; BuildOverviewXaml 7.1; one edited QuestionBodies entry); confirm 332 questions / 6106 tasks; check culture
      ordering of "Document: class survey" vs "Document: classification" and "Interview -\nRating" vs "Interview - Deck
      Officer". Expect: matches the Mac; commit the captures as fixtures.
- [ ] **S-13** PDF comparison (V-11). Steps: compare Mac PDFs with Windows MigraDoc output of the same file. Expect: same
      content; page breaks within ±1 page (DEV-06).

## T. Appearance and design

- [ ] **T-01** Liquid Glass (V-DESIGN, V2-DESIGN). Steps: look at the toolbar, sidebar, sheets and the material list panes
      on a real macOS 26 display, light and dark. Expect: translucency and grouped capsules look right (snapshots flatten
      materials).
- [ ] **T-02** Default buttons and Save (V-DESIGN, V2-DESIGN). Steps: with each window key, look at Save (toolbar), Keep
      Mine, Sign in, Create folders, Close and sheet defaults. Expect: Save always visible; default buttons carry the
      accent tint (snapshots of non-key windows draw them grey or drop Save).
- [ ] **T-03** Scroll bars (V2-DESIGN, rule 17). Steps: System Settings ▸ Appearance ▸ Show scroll bars = Always, then
      Automatic with a trackpad; look at Quick Cards and the Relationship Map. Expect: no legacy scroller corner square
      inside the rounded borders.
- [ ] **T-04** Date pickers (Stage V ruling; V2-DESIGN). Steps: with your own region settings open every date field
      (task editor, crew editor, date prompts, date calculator, calendar). Expect: `yyyy-MM-dd`; steppers and the clear (x)
      button of OptionalDatePicker aligned.
- [ ] **T-05** Fonts (V-DESIGN, V2-DESIGN). Steps: compare the crew table and activity log with Consolas installed and with
      the SF Mono fallback. Expect: headers and columns fit in both.
- [ ] **T-06** Dark contrast (V2-DESIGN). Steps: on a calibrated display check planner chips and the paper shadow in dark.
      Expect: readable chips (≥ 3:1), visible paper edge.
- [ ] **T-07** Live dark-mode switch (§7.3; V-03, V2-J5). Steps: switch macOS appearance with several windows, a menu, an
      alert and Settings open; use View ▸ Dark Mode (⇧⌘D) with Settings open. Expect: everything follows at once; the
      Settings appearance picker updates (round 2).
- [ ] **T-08** Motion and hover (V-DESIGN). Steps: hover rows and buttons; reorder sidebar sections; lift a board card;
      recentre the map. Expect: hover states, drag previews, animations and focus rings look right.

## U. Performance and scale

- [ ] **U-01** Typing after big pages (V2-SCALE, fixed in round 2). Steps: on a large data folder visit Calendar (Agenda),
      Board and Buckets, then type fast in a Task Name and Description. Expect: no lag per keystroke (hidden sections no
      longer rebuild).
- [ ] **U-02** Digest with thousands overdue (V2-SCALE). Steps: release build, data with a few thousand overdue items,
      launch on a new day. Expect: the due panel opens without hanging.
- [ ] **U-03** Long session leaks (V2-SCALE). Steps: Instruments Leaks / Allocations over a multi-hour session using the due
      panel, quick switcher, Flash Sync window, Drive sync and reminders. Expect: no growth tied to these controllers.

## V. Housekeeping (outside `mac/`, the person's call)

- [ ] **V-01** Stray test preference files. 288 empty plists (`aa-tests-*`, `aa-sire-tests-*`, `persist-tests-*`,
      `persist-map-*`, `aa.vessel.tests-*`, `aa.tests.shellx-*`, `aa.tests.shellx.menubar-*`) sit in
      `~/Library/Preferences`, all dated 2026-10-03 07:05–07:53 — written by the round-2 verifiers' scratch copies of the
      older test code, not by the merged tree (two full test runs after the round-2 integration created none, and the
      on-disk shim is now deleted). Remove them if wanted:
      `rm ~/Library/Preferences/{aa-tests-,aa-sire-tests-,persist-tests-,persist-map-,aa.vessel.tests-,aa.tests.shellx}*.plist`
- [ ] **V-02** A verifier started the app once without `--data-dir`, which left `~/Library/Application Support/AA/` holding
      only `.aa.lock` (no data or settings). Delete it by hand if not wanted.
