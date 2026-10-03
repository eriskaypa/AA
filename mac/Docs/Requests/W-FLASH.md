# W-FLASH — contract change requests (ARCHITECTURE.md §12.3)

No contract change requests. W-FLASH consumes the published contracts as they are:

* F1 — `JSONValue`/`JSONObject` (`deepEquals`, `idText`, ordinal keys), `JSONParser`/`JSONWriter`, `NetDateTime.format`
  (`.isoLocalSeconds`, `.isoLocal7`, `.roundTripO`), `CRC32`, `RawDeflate`, `DataStore` (`loadFrom`, `serializeForSave`,
  `flashBaselineFile`, `localEncryptionKeyIfEnabled`), `SettingsStore.readRawTree` / `writeRawTree` / `reload`,
  `LocalEncryption`, `AtomicWrite`, `MacPreferences`.
* W-PERSIST — `DataStore.applySyncedData(_:)` (13 FLASH-105). Until it merges, the apply pipeline is tested with an
  injected stand-in (`FlashSyncStore(dataStore:applySyncedData:)`); the end-to-end test is gated on `.wPersist`.
* F3 — `AppEnvironment` (`flushAllEditors`, `saveQuietly`, `loadDataAndInitUI(reason: .flashSyncApply, …)`,
  `isSafeMode`, `isReadOnlyInstance`, `isBundled`, `status`), `DialogPresenter`, `SceneOpener.window(for: .flashSync)`,
  `SnapshotRegistry`, the design tokens/components.
* W-SHELL — `NSCameraUsageDescription`, `NSCameraUseContinuityCameraDeviceType` and the hardened-runtime camera
  entitlement in the packaged app (03 SHELL-183); the Receive tab relies on them and never starts the camera unbundled.

Informational (for the integrator): the Flash Sync debug snapshots use DEBUG-only environment switches
`AA_FLASH_DEBUG_TAB=send|receive` and `AA_FLASH_DEBUG_AUTOSTART=1`, plus the sheets `w-flash.review-changeset`,
`w-flash.review-snapshot`, `w-flash.review-bare-snapshot`. Fixture data folder: `Tests/AACoreTests/Fixtures/ui/w-flash/`
(`sample-data.json` → `data.json`, `sample-settings.json` → `settings.json`, optional `sample-baseline.json` →
`qrsync-baseline.json`).

## REQ-W-FLASH-01: let `check-ownership.sh` accept `Docs/Progress/<id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §12.2, DECISIONS "Foundation requests" REQ-F1-01
Need: in `owner_of`, treat `Docs/Progress/*.md` like `Docs/Requests/*.md` and `Docs/Deviations/*.md` (owner = the
basename when it is a known owner id), e.g. extend the first pattern to
`Docs/Requests/*.md|Docs/Deviations/*.md|Docs/Progress/*.md)`.
Why: the lead's ruling on REQ-F1-01 has every wave agent keep `Docs/Progress/<agent-id>.md`, but the script reports
it as "unowned path (not in OWNERSHIP.md §2)", so committing the file turns the gate red.
Workaround in place: the script also rejects the file while it is merely untracked, so the progress record is kept
outside the repository (the session scratchpad, `W-FLASH-progress.md`) and its counts are repeated in the final report:
82 feature IDs — 81 done, 1 not applicable (FLASH-133, DECISIONS 13: no screen-capture receive in v1), 0 remaining.
Add `Docs/Progress/W-FLASH.md` from it once the script accepts the path.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5); `Docs/Progress/W-FLASH.md` added by the lead from the counts above (ad9a24b)
