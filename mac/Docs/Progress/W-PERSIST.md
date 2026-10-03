# W-PERSIST — progress (bundles, attachments, shared save, instance model, data-file conflicts)

Feature IDs (OWNERSHIP §4): **49 / 49 accounted** — 42 implemented, 7 not applicable (documented Windows behaviour
replaced by the Mac instance model, `Docs/Deviations/W-PERSIST.md`). Remaining: 0.

| Group | IDs | Status |
|---|---|---|
| Bundles | DATA-041, 044, 045, 046, 047 | done — `BundleService` (export off-main, smart/shared/legacy import, peeks, source.json, DataOnly, Finder metadata, traversal rejected, D-3, D-13) |
| Flash Sync apply | DATA-049 | done — `DataStore.applySyncedData` (validates first; external lock released) |
| Shared save | DATA-052…058; SHELL-123…126 | done — `SharedSaveCoordinator` (1-min push, 60-s poll, directory watcher + 1.5-s debounce + re-arm, NSFileCoordinator, indicator texts, on-close push, adopt/stop, D-1, D-2, D-12) |
| Attachments | DATA-060…068; CONT-081 | done — `AttachmentStore` (Windows-safe leaf, packages → one zip, pasted bytes, resolve, normalise, migrate, classify, enumerate), `PathMapper`, `AttachmentOpener`, `PersistOpenFlow`, Settings ▸ File Links view |
| Windows multi-process | DATA-160…166 | N/A — replaced by DATA-170…182 (see Deviations) |
| Instance model | DATA-170…179 | done — `InstanceGuard` (flock `.aa.lock`, record, lease mode + heartbeat + wake check, forwarding, external-file lock, DATA-178 cleanup), `InstanceAlerts` (1-s re-check, Take Over…), read-only banner + `PersistReadOnlySession` (live view, 5-s upgrade, Edit Here / Stay Read-Only), lease-lost handling |
| Outside changes | DATA-180, 181 | done — `DataFileFingerprint` (writer-queue check, watcher, Keep Mine / Use Theirs / Review / Stop Editing / Resume), `ConflictCopies` (+ `DataFileConflictSheet`, `ConflictCopiesSheet`, File ▸ Recover Conflict Copies… enablement) |
| Other files / shared with Windows | DATA-183, 184, 185 | done — editor-only gating (per-file remedies owned by W-FLASH/W-DRIVE/F3), evidence banner with per-folder Don't Show Again, NSFileCoordinator for every bundle read/peek/push |

## Tests (in-worktree acceptance)
87 W-PERSIST tests in 6 suites (`Tests/AACoreTests/{Attachments,Bundles,SharedSave,Instance}`): 01 §7.6 path table and
resolve vectors, §7.7 bundle vectors (export rows, IsDataOnlyBundle table, smart-import matrix, shared import, missing/
nested data.json, `../evil.txt`, D-3), export→import round trip keeps attachments, Finder metadata never bundled or
swept, package import → one zip entry, §7.13 + 03 §7.2 shared-save state machine with a temp folder and scripted host
(push, external update, Keep Mine prompt, offline / NOT SAVING texts, torn bundle, on-close), MP.7.1 G-1…G-11 incl. the
spawned-helper crash test (perl `flock`) and the O_CLOEXEC child test, MP.7.2 forward payload and F-2 rule, MP.7.3 lease
table, MP.7.5 X-1…X-11, MP.7.7 E-1/E-2, MP.7.8, MP.7.9, path mapping / opener. Gate: 486 tests / 74 suites green.

## Snapshots (both appearances, `--sheet w-persist.*`)
`conflict-changed`, `conflict-unreadable`, `conflict-deleted`, `conflict-copies` (fixture `Fixtures/ui/w-persist/conflicts/`),
`path-mappings`, `banners` (read-only, can-edit, stopped-editing, shared-with-Windows). Checked: no clipping or overlap,
readable in light and dark.

## Known limitations
* The debug snapshot hook cannot render the main window while any top banner is shown (F3's safe-mode banner behaves the
  same: sidebar and bottom bar drop out of the cached image); banner looks are verified through `w-persist.banners`.
* Post-merge items (Stage V): "Review Changes…" through W-QUICK's `ReviewChangesSheet`; F3/W-SHELL wiring requested in
  `Docs/Requests/W-PERSIST.md` (REQ-W-PERSIST-01…04; local workaround in place for 01).
* Two-computer lease mode is covered with injected volume/host facts; it was not exercised against a real SMB server.
