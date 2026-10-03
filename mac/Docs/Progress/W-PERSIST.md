# W-PERSIST — progress (bundles, attachments, shared save, instance model, data-file conflicts)

Feature IDs (OWNERSHIP §4): **49 assigned** — 41 done, 1 partial (cross-owner surfaces requested), 7 not applicable
(documented Windows behaviour replaced by the Mac instance model, `Docs/Deviations/W-PERSIST.md`). Missing: 0.

| Group | IDs | Status |
|---|---|---|
| Bundles | DATA-041, 044, 045, 046, 047 | done — `BundleService` (export off-main, smart/shared/legacy import, peeks, source.json, DataOnly, Finder metadata, traversal rejected, D-3, D-13; refused while the write gate is closed) |
| Flash Sync apply | DATA-049 | done — `DataStore.applySyncedData` (validates first; external lock released; write gate) |
| Shared save | DATA-052…058; SHELL-123…126 | done — `SharedSaveCoordinator` (1-min push, 60-s poll, directory watcher + 1.5-s debounce + re-arm, NSFileCoordinator, indicator texts, on-close push, adopt/stop with the Windows indicator state, D-1, D-2, D-12) |
| Attachments | DATA-060…068; CONT-081 | done — `AttachmentStore` (stored leaf `<32hex>_<Windows-safe original, 150-unit cap>`, packages → one zip, pasted bytes, resolve, normalise, migrate, classify, enumerate; DATA-067 tested), `PathMapper`, `AttachmentOpener`, `PersistOpenFlow`, Settings ▸ File Links view |
| Windows multi-process | DATA-160…166 | N/A — replaced by DATA-170…182 (see Deviations) |
| Instance model | DATA-170…173, 175…179 | done — `InstanceGuard` (flock `.aa.lock`, record, lease mode + heartbeat + wake check incl. first launch on a network volume, forwarding, external-file lock incl. its own read-only upgrade, DATA-178 cleanup), `InstanceAlerts` (1-s re-check, Take Over…), `PersistReadOnlySession` (live view, 5-s upgrade, Stay Read-Only pause), `PersistLeaseLoss` |
| Read-only instance | DATA-174 | **partial** — W-PERSIST parts done (banner, live view, write-gate backstop on every W-PERSIST writer, ⌘S sheet via the banner's key monitor); the window subtitle "Read-Only", greyed commands with the help text and the settings status suffix live in F3/W-SHELL code — REQ-W-PERSIST-02 |
| Outside changes | DATA-180, 181 | done — `DataFileFingerprint` (writer-queue check, watcher that follows the active file, Keep Mine / Use Theirs / Review / Stop Editing (sync + autosave stopped) / Resume), `ConflictCopies` (+ `DataFileConflictSheet`, `ConflictCopiesSheet`, File ▸ Recover Conflict Copies… enablement) |
| Other files / shared with Windows | DATA-183, 184, 185 | done — editor-only gating (per-file remedies owned by W-FLASH/W-DRIVE/F3), evidence banner with per-folder Don't Show Again, NSFileCoordinator for every bundle read/peek/push |

## Tests (in-worktree acceptance)
97 W-PERSIST tests in 6 suites (`Tests/AACoreTests/{Attachments,Bundles,SharedSave,Instance}`): 01 §7.6 path table and
resolve vectors, stored-leaf cap and symlink name, §7.7 bundle vectors (export rows, IsDataOnlyBundle table, smart-import
matrix, shared import, missing/nested data.json, `../evil.txt`, D-3), export→import round trip keeps attachments, Finder
metadata never bundled or swept, package import → one zip entry, DATA-067 (trash/purge/empty keep files), write gate
(imports, apply, attachments, adopt refused; exports allowed), §7.13 + 03 §7.2 shared-save state machine with a temp folder
and scripted host (push, external update, Keep Mine prompt, offline / NOT SAVING texts, torn bundle, on-close, adopt
indicator), MP.7.1 G-1…G-11 incl. the spawned-helper crash test, G-9 analogue (unwritable folder), G-10 (retry while
blocked) and a read-only lock file, MP.7.2 forward payload and F-2 rule, MP.7.3 lease table and L-1 (lease lost after
wake), first launch in lease mode, MP.7.5 X-1…X-11, MP.7.7 E-1/E-2 plus the external-file read-only upgrade, MP.7.8,
MP.7.9, DATA-175 session incl. Stay Read-Only, path mapping / opener. Gate: 496 tests / 74 suites green.

## Fix round 1 (FIX-W-PERSIST, verifier V-01)
* DATA-184 banner text (`PersistWindowsEvidence.message`) and the "Show Me How" help (`PersistUIText.sharedSaveSetup`)
  named `File ▸ Shared Save File ▸ Set…`, which does not exist. They now name the real menu path,
  `File ▸ Shared Save ▸ Set Shared Save File…` (03 §6.5.1 registry; 03 §X-13 renames 01's title, so 01:4560's quoted
  banner text is superseded there — not a deviation). New test `windowsEvidenceMenuPath` builds the path from
  `ShortcutRegistry.row(.setSharedSaveFile)` and checks the banner quotes it. Snapshot `w-persist.banners` re-checked in
  light and dark: the three-line banner fits, no clipping. Gate: 1,587 tests green, ownership check OK.

## Fix round 2 (FIX2-W-PERSIST, verifiers V2-J6, V2-SCALE, V2-COMPAT) — 3 findings: 3 fixed, 0 rejected
* V2-J6 (major) + V2-SCALE (blocker), one defect: an edit autosaved while a background shared-save push was zipping
  was recorded as synced (`pushFinished` took `store.data.lastModified` when the ZIP finished), so later ticks never
  pushed it and the next pull from another copy dropped it without a prompt. `pushInBackground` and `push(label:)` now
  capture the stamp right after the save that feeds the bundle and set `lastSeen`/`lastSynced` from it (Deviations
  W-PERSIST-21, a Windows-bug fix). Tests `PersistSharedSaveRaceTests` (both verifiers' journeys adopted, plus the
  synchronous push) — they fail on the old code.
* V2-COMPAT (minor): attachment names Windows cannot create, arriving in foreign bundles, were extracted and re-exported
  as is. Smart and shared imports now rename such top-level `files/` leaves to the Windows-safe form in staging (collision
  suffix `_2`…) and repoint the data's `files/` paths (Deviations W-PERSIST-22). Tests `PersistWindowsSafeImportTests`
  (the verifier's `winreserved.zip` names, re-import is DataOnly, the re-export has no illegal leaf, shared import,
  predicate table). Note: `abc_CON` is legal on Windows (the stem is not a device name) and is kept.
* 6 new tests in 2 new suites. No UI touched (AACore only), so no snapshots this round. Gate: build + tests (-warnings-as-errors) + ownership check green.

## Snapshots (both appearances, `--sheet w-persist.*`)
`conflict-changed`, `conflict-unreadable`, `conflict-deleted`, `conflict-copies` (fixture `Fixtures/ui/w-persist/conflicts/`),
`path-mappings`, `path-mappings-empty`, `path-mappings-unc`, `path-mapping-editor`, `path-mapping-invalid`, `banners`
(read-only, can-edit, stopped-editing, shared-with-Windows). Checked: no clipping or overlap, readable in light and dark,
backslashes shown verbatim (UNC prompts were Markdown-escaped before).

## Known limitations
* The debug snapshot hook cannot render the main window while any top banner is shown (F3's safe-mode banner behaves the
  same); banner looks are verified through `w-persist.banners`. NSAlert-based dialogs (DATA-172 launch alert, ⌘S sheet,
  Take Over confirmation) are not snapshot-able.
* Post-merge items (Stage V): "Review Changes…" through W-QUICK's `ReviewChangesSheet`; F3/W-SHELL wiring requested in
  `Docs/Requests/W-PERSIST.md` (REQ-W-PERSIST-01…05; local workarounds in place for 01 and part of 02).
* `Scripts/check-ownership.sh` reports this file as an unowned path (REQ-W-PERSIST-05, owner F1); every code commit passes.
* Two-computer lease mode is covered with injected volume/host facts; it was not exercised against a real SMB server.
