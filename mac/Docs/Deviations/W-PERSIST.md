# W-PERSIST — deviations and P2 fixes (ARCHITECTURE.md §12.2)

| ID | Spec ref | Change (one line) |
|---|---|---|
| D-1 | 01 DATA-052, 03 SHELL-124 (W-4) | The 1-minute tick pushes when `IsDirty \|\| LastModified > lastSynced` (`SharedSaveCoordinator.hasUnsyncedChanges`), not only when dirty. |
| D-2 | 01 DATA-055 | On close the bundle stamp is compared with the last sync (own push / declined stamp / not newer than `lastSynced` → push); a bundle another copy wrote since then is not overwritten — our model is kept as a `-mine` conflict copy (DATA-181) instead. Without any sync this session the Windows rule (local ≥ bundle) applies. |
| D-3 | 01 §3.10 | Smart import, shared import and `ApplySyncedData` decode the staged JSON fully before `files/` or the data file are touched. |
| D-12 | 01 §8.1 | A shared-save pull while the local file is unreadable (safe mode) always asks first and copies the unreadable file to `data.unreadable-{yyyyMMdd-HHmmss}.json` before replacing it. |
| D-13 | 01 DATA-040 | The "inside the AA data folder" test uses a trailing separator (`…/AA2/x.zip` is accepted). |
| W-PERSIST-1 | 01 DATA-180, §MP.3.4 | Deliberate replacements of the data file (bundle imports, shared pulls, Flash Sync apply, conflict restore) skip the pre-write check (MP.7.5 X-7) but first keep any foreign version found on disk as a `-theirs` conflict copy; the new fingerprint is recorded. |
| W-PERSIST-2 | DECISIONS 05 | A folder or package is zipped into one `files/<32hex>_<name>.zip`; entries sit under the folder's name; Finder metadata is skipped; symbolic links inside it are neither followed nor stored (the in-house ZIP writer has no link entries). |
| W-PERSIST-3 | 01 §6.6 | `.localized` joins `.DS_Store`, `._*`, `Icon\r`, `__MACOSX/` as Finder metadata (never bundled, counted, swept or zipped). On a case-sensitive volume, an imported attachment differing only in case replaces the local one (Windows/NTFS semantics). |
| W-PERSIST-4 | 01 §MP.3.3, ARCH §6.6 | A holder of the same user without an app bundle (`swift run`, `.sameUserNoApp`) maps to `InstanceGuardResult.otherUser(user)` (no forwarding); the alert reads the full detail from `InstanceGuard.folderBlocked` and shows the same-user wording without "Switch to Running AA". |
| W-PERSIST-5 | 01 DATA-173, §MP.4.2 | The distributed notification is `Identifiers.instanceRequestNotification` (`com.eriskay.aa.InstanceRequest`, the Mac identifier registry) instead of `com.bepavida.aa.InstanceRequest`. |
| W-PERSIST-6 | 01 DATA-180 | Texts the spec elides or leaves open: the unreadable variant ends "If you keep yours, theirs is kept as a copy in the data folder's “conflicts” folder."; the deleted variant ends "Keep Mine saves your version again. Stop Editing Here keeps this window open without saving."; statuses "Kept your version — the data file was saved again." (deleted), "Stopped editing here — changes in this window are not saved.", "Editing resumed — the data file was re-read from disk.", "Restored {name} from the conflicts folder." (DATA-181 restore), "Mapped {prefix} to {folder} on this Mac." (Locate…). |
| W-PERSIST-7 | 01 DATA-180 | The sheet adds a "Your version / Their version" facts box under the Windows text (additive, P4) and a "Conflict Copies…" button (ARCH §6.6). |
| W-PERSIST-8 | 01 DATA-184 | "Show Me How" opens the Help anchor `shared-save-setup` when the bundle has a help book; otherwise it shows the setup steps in an information alert (no help book ships yet). The banner lives in `DataFileConflictBanner` (always in F3's banner area). |
| W-PERSIST-9 | 01 DATA-174 | "Switch to Other AA" in the read-only banner activates the editor and keeps this read-only window open (the spec only says the launch alert's Switch quits). A "Show Conflict Copies…" item sits in the banner's ⋯ menu (ARCH §6.6). |
| W-PERSIST-10 | 01 DATA-180 step 3 | The data-file watcher polls every 60 s only on network volumes (local volumes rely on the directory source, as specified); the shared-save coordinator always polls every 60 s (DATA-053). |
| W-PERSIST-11 | ARCH §6.6 | Additive public API: `BundleService.exportFolderToZipSync`, `peekBundleIdentity`, `readLastModified`; `PathMapper.inferredMapping/upsert/isValidPrefix/canonicalPrefix/uncParts/smbShareURL`; `SharedSaveCoordinator.tick/hasUnsyncedChanges/closePushAllowed/path/isRunning/isHandlingUpdate/isPushRunning`; `DataFileFingerprint.table/state/statusHandler/reloadHandler/onModeChange/checkNow/perform/resumeEditing/reviewData`; `ConflictCopies.readJSON/peekData/restore/saveMine`; `InstanceGuard.folderBlocked/externalBlocked/retryFolderLock/retryExternalLock/relinquishFolderLock/takeOver/isEditor/onLeaseLost`. |
| W-PERSIST-13 | 01 §6.6, 05 §6.9 | `PersistOpenFlow` (AA/PersistenceUI) is the open-with-recovery flow for every owner that opens attachments: missing file → OC-12 text; unmapped Windows path → "Windows path — not available on this Mac" with Locate… (stores the inferred mapping), Connect to Server… (UNC), File Links Settings…, Cancel. |
| W-PERSIST-12 | 01 §6.9 | `SharedSaveCoordinator.push(label:)` updates the status line and indicator like Windows' `PushToShared` and also rethrows (contract `throws`); the Windows flows ignore the error (`try?`), as `adoptSharedFile` does. |

## Not applicable on the Mac (documented Windows behaviour replaced by the Mac instance model)
* DATA-160, DATA-161, DATA-162, DATA-163, DATA-164 — Windows-only behaviour of two AA processes on one folder; on the Mac
  they are replaced by DATA-170…182 (one editor per folder, read-only instances, fingerprint + conflict copies, key-level
  settings merge by F1). Nothing to reproduce.
* DATA-165 (Flash Sync across processes) and DATA-166 (other shared files) — the cross-process races cannot occur with
  one editor; the per-file Mac remedies are owned by W-FLASH (unique baseline temp name), W-DRIVE (atomic token file) and
  F3 (`crash.log` O_APPEND), per DATA-183.
