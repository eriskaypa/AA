# AA for macOS — manual-only checks

Checks the verifiers (Stage V round 1, 2026-10-03) could not run automatically: they need a person at the keyboard, a
second machine, a Windows PC with the real AA.exe, a real Google account, an iPhone, or a signed bundled build.
Tick each box when done and note the date and the build (`AA ▸ About AA`) beside it. Anything that fails goes to
`Docs/PROGRESS.md` "Known remaining problems" with the spec ID.

Legend: **[Win]** needs the Windows PC / WPF build · **[2 Macs]** needs a second Mac or user · **[Bundle]** needs a
signed `dist/AA.app` from `Scripts/build-app.sh` · **[Phone]** needs the iPhone · **[Google]** needs a real sign-in.

> Note: the list handed to the integrator was cut off part-way through the V-09 items (at "§7.15: JSON round-trip of
> a Mac-w…"). The rest of V-09 and any manual items from V-10 … V-14, V-PACKAGE, V-E2E and V-DESIGN are not in this
> file yet; add them from those verifiers' reports.

## V-01 — Data model and persistence

- [ ] **[Win]** DATA-315…320 / DATA-326: generate the Windows goldens. Install the .NET 10 SDK (GOLD-T1), run
      `Scripts/fixtures.sh generate`, commit `Tests/AACoreTests/Fixtures/winfixtures`. Until then every WinFixtures
      suite skips, and 01 §7.14-1 "Required before release" (byte-identical round trip of a Windows-written
      `data.json`) is unproven.
- [ ] **[Win]** DATA-321 / DATA-325: run WinCapture W01–W18 and the W23 load check on a Windows machine with WPF.
- [ ] **[Win]** DATA-322: clipboard input capture from Word, Excel, Outlook and a browser on Windows.
- [ ] **[Win]** DATA-323: manual confirmations M-01…M-09 in the real AA.exe.
- [ ] **[Win]** DATA-324: Windows run of WinFixtures (Windows-form paths, DPAPI AAENC1/AADPAPI1 samples W19,
      Explorer ZIP W21).
- [ ] **[Google]** DATA-073 / 14 §6.3: Google OAuth token round trip with a real Google sign-in.
- [ ] **[Win] [2 Macs]** DATA-185: shared bundle between a Windows AA and this Mac over SMB / Parallels — expected
      push failures, NSFileCoordinator against File Provider folders.
- [ ] **[2 Macs]** DATA-177: lease mode on a real SMB/NFS data folder with two Macs — heartbeat, Take Over, lease
      lost after sleep.
- [ ] **[2 Macs]** DATA-172 / 173: the interactive second-launch alert and "Switch to Running AA" with a real
      second process (`open -n`, and another user via fast user switching). Include a forwarded `.json` (now routed
      to Import from File, round 1) and an `.aaz`.

## V-02 — Repository and domain services

- [ ] REPO-077: press ⌘Z for real in the live main window with focus in (a) the sidebar list, (b) a text field,
      (c) the rich-text editor — confirm the responder routing.
- [ ] **[Bundle]** REPO-112 / 113: notification permission prompt, the "AA — due soon" banner, clicking it opens
      the due-dates panel, the Dock badge, the MenuBarExtra headline.
- [ ] REPO-092: Export (.csv)… through the save panel, then open the file in the default app.
- [ ] **[Win]** REPO-153 / 154: Export / Import `.aasched.json` from the crew Schedule tab through the save / open
      panels, plus a round trip through the Windows importer (T-SCH-8, Windows side).
- [ ] **[Win]** REPO-076 / §4.4: a Windows build restores Trash entries the Mac wrote, including a subtask entry
      with the unknown member `ParentTaskId` (DECISIONS 02 Q-4).
- [ ] REPO-100: double-click a search hit for a password-locked item; it opens on the lock screen.

## V-03 — Main shell, menus, packaging

- [ ] **[Bundle]** SHELL-204: launch from Finder (Gatekeeper), quit, relaunch — the window frame is restored.
      (The automated `--smoke-test` passed: exit 0; a second run is refused with exit 3.)
- [ ] **[Win]** SHELL-206: cross-version data smoke with a Windows-written data folder and the Windows app.
- [ ] SHELL-207: clean-machine run, and an Intel (Rosetta) run.
- [ ] **[Bundle]** SHELL-180…191, 200…203: run `Scripts/build-app.sh` and check the BD.7.4 assertions — `lipo`
      architectures, `minos 26.0`, `codesign --verify`, entitlements, resource checksums, size tripwire.
- [ ] **[Bundle]** SHELL-183: camera permission prompt text on the first Flash Sync ▸ Receive.
- [ ] **[Bundle]** SHELL-189 / 190: Gatekeeper first launch, and the translocation sheet when run from Downloads.
- [ ] SHELL-185: Finder double-click and Dock drop of an `.aaz` onto a running AA.
- [ ] **[Bundle]** SHELL-130 / 131: notification banner look, click → due-dates panel; MenuBarExtra live behaviour.
- [ ] SHELL-511 (T-KB-41 / 42): AZERTY layout — ⌘1…9 versus ⇧⌘7, and numeric-keypad ⌘1.
- [ ] SHELL-505 / 513 (T-KB-39 / 40 / 43 / 44): ⌘Q and ⌘W while a decision sheet / a close-type sheet is up.
- [ ] SHELL-521 (T-KB-16): "Nothing to undo." when the disabled Undo item lets ⌘Z fall through to the root responder.
- [ ] SHELL-640: View ▸ Enter Full Screen is present with the main window key.
- [ ] SHELL-023 / 526: shared-save indicator in the toolbar and bottom bar while OFFLINE / NOT SAVING.
- [ ] **[Win]** SHELL-028: drag-reorder sidebar sections with the mouse; the Windows build reads the new `TabOrder`.
- [ ] §7.3: switch macOS dark mode live with several windows, a menu and an alert open — everything follows.
- [ ] Splash and login (round 1 change): the splash shows centred for ~2.4 s, never takes key focus, and the Console
      shows no `makeKeyWindow` or `-layoutSubtreeIfNeeded` warning at launch.

## V-04 — Hierarchy pages

- [ ] Sidebar Return key: ↩ on a focused sidebar row starts a rename (`onKeyPress(.return)`) and does NOT fire the
      context-menu primary action (Open in New Window).
- [ ] HIER-M01: drag several selected rows onto a group header, onto a placeholder, and onto an empty
      "Ungrouped (0)" header; `GroupId` changes and the file is saved.
- [ ] §7.13 multi-window: open two tasks and a procedure in windows, type, ⌘S, quit, relaunch; open the same item
      twice → one window; delete a detached item from the sidebar / Board / quick work → its window is orphaned or
      closed; reload while a window is open.
- [ ] HIER-056 / Q-18: Tools ▸ Lock Now with an item window of a protected item open → the window gates in place;
      the main pane re-loads the editor of a non-gated item.
- [ ] §8 Q-23: double-clicking a step's Done / Job toggle does not open the step editor (W-BUILD grid).
- [ ] HIER-024 / 123: ⌘Z after a sidebar batch delete restores the whole batch; ignored while a text field has focus.
- [ ] **[Win]** Item lock hashes written by the Mac verify on the Windows build (with a Windows-written data.json).
- [ ] HIER-150: list selection colour `#CCE8FF` (light) / `#094771` (dark) when the sidebar is the key list.

## V-05 — Container, rich text, file bank

- [ ] **[Win]** 05 §7.7 item 10 / §9 Q1: every Mac-written XAML loads in Windows `TextRange.Load` (WPF harness and
      real wpf-capture fixtures).
- [ ] Drag and drop into the file bank and onto the paper with no modifier, with ⇧ and with ⌥⌘ (CONT-085,
      SHELL-679); drag rows out to Finder and Mail.
- [ ] Finder ⌘C → file-bank Paste (system pasteboard import); file-bank Copy / Cut mirror to the pasteboard.
- [ ] Open / Open All / Show in Finder against real files, UNC shares (Connect to Server…) and drive-letter
      mappings (CONT-089…091).
- [ ] Quick Look (Space / ⌘Y) and thumbnails.
- [ ] Right-click spelling menu on a real misspelled word and on a locked word (CONT-033); Ignore Spelling.
- [ ] Typing into the CONT-062 password sheets (set / unlock / master-password "redemption") and Touch ID.
- [ ] System Colors panel and Fonts panel (Other…, ⇧⌘C, ⌘T).
- [ ] Paste images from Preview / Safari into the paper (→ file-bank notice), and RTF / HTML from Word, Excel, Chrome.
- [ ] 400 ms save debounce in the live app (unit-tested by `EditorSessionTests.debouncePersists`).

## V-06 — Builders and saved lists

- [ ] Return in a builder list (↩ = Edit…, SHELL-667) versus the sheet's default Close button; ⌘↩ "Add all" while
      the bulk text view has focus; Esc / ⌘. on a TextPromptSheet layered on a builder sheet (BUILD-139 / 147).
- [ ] Drag-and-drop reorder in the builders and inside a Saved Lists group (06 §6.2).
- [ ] D3 rescue flow: delete the template being edited via "Manage saved lists…" inside the template editor, then
      Close / ⌘W — the "Save as New List" / "Discard Changes" alert appears on the right window.
- [ ] Save / open panels and what follows: checklist PDF / XLSX auto-open; saved-list PDF "Export complete" →
      Open / Show in Finder; `.aasched.json` export / import panels and the "All files" accessory.
- [ ] Look at the generated PDFs (BUILD-C1 / C3 layout, "Page X / Y", headings) and open the XLSX in Excel.
- [ ] **[Win]** Import a Mac-exported `.aasched.json` and a Mac-saved data.json (template order, SortAZ, a `GroupId`
      pointing at a deleted group) on the Windows build.
- [ ] ItemPicker: selections kept across search filtering; in single-select, double-click = choose + OK.

## V-07 — Calendar, Board, Planner, Buckets, Map

- [ ] Board: drag a card between columns (status set, saved at once, column glow, card-shaped preview); a drop on
      the same column does nothing (VIEW-047).
- [ ] Board: ⌘-click / ⇧-click selection per column, ⌘A selects the focused column, ⌘⌫ / Return on a focused column.
- [ ] Board: "Open all files (routine)" with real attachments, web links, more than 15 files (Open All / Cancel),
      and unreachable Windows drive-letter paths skipped silently (VIEW-051).
- [ ] Board: Delete task → Move to Trash → ⌘Z restores (top-level and nested cards); status line text.
- [ ] Planner: drag pool rows / blocks / all-day chips onto the hour grid (15-min half-even snap, dashed ghost),
      onto month cells (timed keeps its time; a ranged task slides by its anchor day), and back onto the pool
      (VIEW-100…103).
- [ ] Planner: double-click a block / chip / pool row opens the subtask or checklist-step editor; a procedure
      navigates to Procedures (Q-07); ⌘← ⇧⌘T ⌘→ navigation.
- [ ] Calendar: inline Done checkbox toggles and saves at once; Agenda sibling occurrences update together;
      double-click opens the right editor (or navigates for procedures); right-click batch Mark done / not done /
      Set deadline (date sheet with Clear deadline).
- [ ] Calendar: the Agenda segment shows the tooltip "All upcoming tasks grouped by day.".
- [ ] Buckets: + New bucket two-prompt flow; Rename / Set category / Delete alerts; member double-click (navigate or
      editor) and "Remove from this bucket".
- [ ] Relationship Map: click a node to recentre (animated) with the Inspect row in sync; double-click / context menu
      "Show in {Section}", "Open in New Window"; zoom, pinch, Fit, Center.
- [ ] Quick work (⌘N) bucket picker: cap message and kept pair (VIEW-153 / VIEW-213).

## V-08 — Quick and floating windows

- [ ] QUICK-003: drag the due panel by its gradient header — the panel moves; dragging the body does not.
- [ ] QUICK-006: drag-resize from the 18×18 corner grip and from the native edges; quit, relaunch, press ⌘R — same
      size.
- [ ] QUICK-002 / §6.5: the due panel stays above other apps while AA is inactive and joins full-screen Spaces.
- [ ] QUICK-106: quick switcher ↑ / ↓ / Return / Esc in the query field; double-click opens; closes on losing key.
- [ ] QUICK-125 / SHELL-673: Return in the Search results opens the owner; Return in the query runs the search.
- [ ] QUICK-173 / SHELL-675: Trash sheet keys ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫, and Esc / ⌘W close it.
- [ ] **[Win]** QUICK-193: import review sheet — Esc = Cancel, Return = Import (Overwrite) — on a real Windows-made
      `.aaz`.
- [ ] **[Win]** QUICK-155 / §4.6 / T-AL-2: byte-compare a Mac CSV export with a Windows export of the same data in
      the same time zone.
- [ ] **[Win]** T-TR-7: Mac-written Trash `PayloadJson` deserialised by the Windows harness.
- [ ] **[Bundle]** QUICK-001: clicking the reminder notification opens the due panel; the once-a-day digest opens it
      at the first launch of the day.
- [ ] **[Phone]** §7.8 item 3: Flash Sync to the iPhone carries `QuickViewPinIds` but not `DueWindowWidth/Height`.
- [ ] QUICK-077: "Edit…" / "Open Full Builder…" from quick work opens the W-BUILD editor / builder sheets on the
      quick-work window, and the children list refreshes afterwards.

## V-09 — Crew (list received only up to §7.15)

- [ ] CREW-030…040: import a real COMPAS `.xlsx` through the open panel, including the three-button date-order
      question (Day First / Month First / Cancel Import) and the post-import expiry warning.
- [ ] CREW-105 / §7.13: open the exported `crew-yyyy-MM-dd.xlsx` in Excel / Numbers — bold shaded header; the Open /
      Show in Finder buttons.
- [ ] **[Win]** §7.15: JSON round trip of a Mac-written file (item text truncated in the hand-over; complete it from
      the V-09 report).

## Round 1 fix passes — live checks the snapshot hook cannot make

- [ ] W-FLASH: in the snapshot review sheet, Don't Apply shows as the blue default button and Return triggers it
      (the hook draws a non-key window).
- [ ] W-DRIVE / DATA-174: in a read-only copy (second launch → Open Read-Only), Settings ▸ Sync shows the six Drive
      buttons disabled with "Not available in a read-only copy of AA.".
- [ ] W-PERSIST / DATA-184: the "Show Me How" help names File ▸ Shared Save ▸ Set Shared Save File….
- [ ] D-5: with an older encrypted note (legacy `enc:` body) present, Set / Change Password… warns before
      orphaning bodies it cannot decrypt, and reports how many it decrypted and saved.

## Housekeeping (outside `mac/`, the person's call)

- [ ] About 350 empty preference plists left by test runs before the TempDefaults fix sit in
      `~/Library/Preferences` (`aa-tests-*`, `aa-sire-tests-*`, `persist-tests-*`, `persist-map-*`,
      `aa.vessel.tests.*`, `aa.tests.shellx.*`). Remove them by hand if wanted:
      `rm ~/Library/Preferences/{aa-tests-,aa-sire-tests-,persist-tests-,persist-map-,aa.vessel.tests.,aa.tests.shellx.}*.plist`
