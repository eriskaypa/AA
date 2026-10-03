# W-FLASH — progress

Recorded by the lead from W-FLASH's final report (`Docs/Requests/W-FLASH.md`, REQ-W-FLASH-01): the agent kept the
record outside the repository because `check-ownership.sh` rejected `Docs/Progress/W-FLASH.md` at the time; the
script maps the path since f556cb5.

## Counts
- Feature IDs: **82** — 81 done, 1 not applicable, 0 remaining.
- Not applicable: FLASH-133 (DECISIONS 13: no screen-capture receive in v1).

## Notes
- Debug snapshots: `AA_FLASH_DEBUG_TAB=send|receive`, `AA_FLASH_DEBUG_AUTOSTART=1`; sheets `w-flash.review-changeset`,
  `w-flash.review-snapshot`, `w-flash.review-bare-snapshot`. Fixture folder `Tests/AACoreTests/Fixtures/ui/w-flash/`.
- The end-to-end apply test runs against W-PERSIST's real `DataStore.applySyncedData(_:)` now that it is merged.

## FIX-W-FLASH (verification round 1, V-13 findings) — 6 fixed, 0 open
- **major** Send stream stalled after a confirm / an apply during flashing when a frame render was in flight
  (`rendering` never cleared for a stale generation). The render bookkeeping is now `FlashRenderGate` (AACore):
  replacing the encoder starts a new generation **and** frees the render slot; a stale completion is ignored without
  touching the new stream's slot. Test `renderGateSurvivesAReplacedEncoder` (FLASH-013/020/023/046, DEV-FLASH-27).
- **minor** Start camera stayed disabled after the user allowed the camera: the permission is re-read on Rescan and
  when the window becomes key; `FlashReceiveFlow.setAccess(.granted/.unknown)` clears the denied text. Test
  `cameraAccessGrantedAfterDenial` (FLASH-030/032/033, DEV-FLASH-39).
- **minor** Full-screen code stayed up after an apply dropped the flashing stream: `dropStream()` now closes full
  screen (confirm, apply, nothing-to-send, failure); a new prepare while full screen is up and idle blanks its plate
  (FLASH-134, FLASH-046).
- **polish** Idle key-window refresh rebuilt the payload every time: skipped when not dirty and the
  `FlashSourceFingerprint` (data file, settings.json, baseline) is unchanged since the last prepare. Test
  `sourceFingerprintTracksEverySource` (FLASH-010, DEV-FLASH-38).
- **polish** More menu help: the menu says `More Flash Sync options`; Show Full Screen and Reset Pairing… carry their
  own help (FLASH-131/134).
- **polish** Snapshot review Apply now has a red label (`AAColor.Status.danger`, DEV-FLASH-29). Don't Apply keeps
  `.defaultAction` + the hidden `.cancelAction`; the snapshot hook renders a non-key window, so the blue default tint
  is not visible in PNGs (live behaviour of `.keyboardShortcut(.defaultAction)`).
- V-DESIGN pass on the Flash Sync window and review sheet: content text in `aaMono` (summary semibold 13, help/meta
  11 via `AAHelpText`, speed/fps/progress/status with monospaced digits, bold "Incoming:" line), chrome stays system;
  plate border `AAColor.border`, plate/preview placeholders `AAColor.Status.neutral`; hierarchical symbols; review
  sheet in NSAlert layout (13 bold title, 11 body), breakdown rows aaMono 13 / meta aaMono 11, measured height (no
  clipped last row, scrolls past 380 pt), footer Divider + 44-pt bar. Snapshots (light + dark):
  `scratchpad/snapshots/fix1-W-FLASH/`.

## FIX2-W-FLASH (verification round 2, V2-SCALE finding) — 1 fixed, 0 open
- **minor** Flash Sync Send preparing read, decoded and re-serialised the whole database on the main thread
  (1.24 s on a 70 MB database; the `--snapshot flash-sync` scene took 15.5 s against about 8 s for the others).
  `FlashSyncModel.prepareSend` now awaits `FlashSyncStore.captureSendInputs(live:)`: on main only the live model's
  save encoding (`saveEncodingTree`, the same steps as `DataStore.serializeForSave` minus the JSON write); off-main the
  JSON write, the data-file read + decryption + byte comparison, and the baseline read + decryption. A match means the
  file already is what `readDataJSON()` returns; anything else reloads exactly as before. Payload bytes, errors and
  error order are unchanged (DEV-FLASH-40). The superseded-prepare token is checked after the read and after the build.
- Measured (debug build, the V2-SCALE 70 MB database): synchronous capture 7.38 s on main → longest main-actor stall
  0.93 s during the new capture (the live-model encoding), about 8x less; the release ratio puts it near 0.15 s against
  the reported 1.24 s. `--snapshot flash-sync` on that database: 9.9 s, level with `TabTasks` (9.5 s) on the same
  data; the window now draws `Preparing…` instead of blocking.
- Tests (8, `FlashSendCaptureTests`): saved model takes the off-main route; encrypted data file + encrypted baseline
  take it too; indented / pre-SchemaVersion bytes reload exactly; unsaved live edits never leak into the payload; a
  path whose normalisation changed since the save reloads; missing file / no live model reload; unreadable database
  before unreadable settings (Q-5); `saveEncodingTree` equals `serializeForSave` byte for byte. Every case also asserts
  equality with the synchronous `captureSendInputs()`.
- Snapshots (light + dark, `snapdata-full` copy) and the 70 MB run: `scratchpad/snapshots/fix2-W-FLASH/`. The
  `reentrant NSTableView delegate` warning in the 70 MB log comes from the main window and appears for every scene on
  that database (V2-SCALE logs); none in the Flash Sync runs on `snapdata-full`.
- The apply path (`apply(_:)`) still reads the trees on main; it runs after an explicit Apply in a modal flow and was
  not part of the finding.
