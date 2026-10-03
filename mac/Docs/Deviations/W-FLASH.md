# W-FLASH — deviations and P2 fixes (ARCHITECTURE.md §12.2)

Format: ID · spec reference · one line. Stage V merges this file into `Docs/DEVIATIONS.md`. Nothing here changes the
wire protocol v1 or what a well-formed peer sends; every file written stays readable by Windows and iOS.

## P2 defect fixes (sanctioned by DECISIONS 13)

| ID | Spec ref | Fix |
|---|---|---|
| DEV-FLASH-01 | 13 §8 Q-1 | On apply, `Sets`, `Deletes`, `Order` and `BlockDeletes` naming an excluded data key (`Ui`, `LastModified`) are skipped, so a malformed or legacy sender cannot wipe `Ui` (per-device keys included) or turn it into an array. |
| DEV-FLASH-02 | 13 §8 Q-2, protocol §10 | `SettingsDeletes` is filtered through the 11 excluded settings keys on apply: a legacy sender can no longer remove the receiver's `PasswordHash`/`PasswordSalt` (or any other excluded key). |
| DEV-FLASH-03 | 13 §8 Q-3, protocol §10 "Legacy senders" | A root-level `Ui` object in a change set (the very first iOS build) is folded into the key-level Ui merge with the lowest precedence (root `Ui` < `Blocks.Ui` < `UiChanges`), per-device keys stripped. |
| DEV-FLASH-04 | 13 §8 Q-4 | When a prepare finds nothing to send, the encoder and pending baseline are dropped, flashing stops and the confirm button is disabled. After an apply while a stream is flashing or awaiting confirmation, that pre-apply stream is dropped and re-prepared, so a confirm can never write a pre-apply baseline. |
| DEV-FLASH-05 | 13 FLASH-071, §6.4 step 5, §7.9 | Measured (FlashQRTests): Apple Vision's current barcode revisions (3–4) cannot read clean, valid symbols whose data is mostly zero bytes when masks 0, 1, 2, 3 or 5 are used — exactly the zero-padded tail chunk, which Nayuki's penalty rule masks with 0. At K ≤ 8 that frame travels alone, so the transfer would never complete. **Sending:** the Mac picks the lowest-penalty mask among 4, 6 and 7 (`FlashQRCode.appleReaderSafeMasks`, `FlashQRCode.flashFrame`), which every Apple reader tested decodes; the generator itself stays bit-identical to Nayuki (golden matrices) for the default mask set. **Receiving:** every camera frame runs Vision's current revision and revision 2 together, and CoreImage's `CIDetector` when both found nothing (`FlashQRDetector`), so Windows' mask-0 tail frames are read. Frames remain standard QR codes; WeChat/ZXing/OpenCV read them. |
| DEV-FLASH-06 | 13 §8 Q-5 | A data file that exists but cannot be read refuses to prepare or apply with `The database could not be read, so Flash Sync is unavailable until it is fixed.` (never a snapshot of an empty database or a change set deleting everything); safe mode refuses the same way. An unreadable `settings.json` is an error, never `{}` (which would emit `SettingsDeletes` for every shared key). A missing data file is still an empty database (parity). |
| DEV-FLASH-07 | 13 §8 Q-10 | The apply is transactional: both trees are read before anything is written; settings.json is written atomically, then the data goes through `applySyncedData`; if that throws, the previous settings.json bytes are restored (or the file removed if it did not exist), so "Failed to apply — your data was not changed." is true. |
| DEV-FLASH-08 | 13 §8 Q-11 | `qrsync-baseline.json` is written encrypted (`AAENCM1`, the local AES-GCM key) while EncryptLocalData is on; plaintext baselines are still read. If encryption is on and the key cannot be read, the baseline is not written (the next sync is a snapshot) rather than leaking the database in plaintext. |
| DEV-FLASH-09 | 13 §8 Q-7 | Rescan and the camera picker are disabled while the camera runs (Windows let Rescan re-enable Start and leak the running camera). |
| DEV-FLASH-10 | 13 §8 Q-12, DECISIONS 02 Q-12 | The apply writes settings.json only when the merge changed it (no-op write-backs skipped); the baseline is still written. |

## Sanctioned Mac behaviour and additions (P4, DECISIONS 13)

| ID | Spec ref | Change |
|---|---|---|
| DEV-FLASH-20 | 13 FLASH-004, §6.6 | A single-instance, non-modal `Window` (not `ShowDialog`). Modal guarantees are kept by construction: every prepare and every apply first flushes all editors and saves synchronously; a prepare never runs while flashing or while a confirmation is pending; the summary refreshes when the window becomes key and is idle; the apply cancels the pending autosave and reloads through `loadDataAndInitUI` immediately. |
| DEV-FLASH-21 | 13 §8 Q-8, Q-9 | The time estimate follows the Speed slider live; `framesShown` and the pass count reset with every new payload. |
| DEV-FLASH-22 | DECISIONS 13 Q-18 | Speed (6…15, default 12) is remembered per Mac (`aa.flash.speed`, UserDefaults — never settings.json); the last tab is remembered too (`aa.flash.tab`). |
| DEV-FLASH-23 | 13 FLASH-030, §6.4 step 2 | Cameras are listed by their real names (`localizedName`) from an AVCaptureDevice discovery session (built-in, external, Continuity, Desk View), the system default preselected, refreshed automatically on connect/disconnect; Windows' positional "Default camera" / "Camera N" names are not used. |
| DEV-FLASH-24 | 13 FLASH-033, §6.4 step 9 | Detection is Apple Vision (no WeChat model files, no `qrmodels/` folder). `The QR reader could not start: {message}` is kept in `FlashSyncTexts` but cannot occur. |
| DEV-FLASH-25 | 13 FLASH-034/036, §6.4 | Capture: the largest format ≤ 1920×1080 at its highest frame rate, continuous autofocus where supported, 420f buffers, late frames discarded (≙ buffer size 1), unmirrored data path; the preview is an `AVCaptureVideoPreviewLayer` (no 100 ms throttle needed) and is mirrored for cameras that face the user. A 1.2 s watchdog reports `The camera stopped sending frames.`; interruptions report the same; runtime errors report `Camera error: …`. |
| DEV-FLASH-26 | 13 §6.4 step 1, 03 SHELL-199 | Mac-only texts: `Camera access is turned off for AA. Allow it in System Settings ▸ Privacy & Security ▸ Camera.` with **Open System Settings**; unbundled runs show `The camera needs the packaged app. Build it with Scripts/build-app.sh and open dist/AA.app.` and never touch the camera. |
| DEV-FLASH-27 | 13 §6.5 | Frame clock: a display link on the window's screen (each code held for whole refreshes) with a 60 Hz common-mode timer fallback while the link is paused (display asleep / window occluded); frame n+1 is rendered on a background queue while n is shown; the first frame appears one interval after Start (parity). Keep-awake = `ProcessInfo` activity (idle display + system sleep disabled). |
| DEV-FLASH-28 | 13 FLASH-016, §6.3 | The plate draws the code at an integer number of device pixels per module, centred and pixel-aligned, interpolation off (crisper than Windows' uniform stretch); before the first frame it shows a light placeholder instead of an empty plate. |
| DEV-FLASH-29 | 13 FLASH-044/135, §6.6 | The review is a sheet with the exact FLASH-044 text plus a per-collection breakdown (removals in red); buttons **Apply** (destructive for a snapshot) / **Don't Apply** (default for Return and Esc). |
| DEV-FLASH-30 | 13 FLASH-019, §6.6 | The confirm question uses **Yes, It Finished** / **Not Yet** (Not Yet is the default button). |
| DEV-FLASH-31 | 13 FLASH-131 | Send ▸ More ▸ **Reset Pairing…** (with a destructive confirmation) clears the baseline so the next send is a full snapshot; disabled while flashing or while a confirmation is pending. |
| DEV-FLASH-32 | 13 FLASH-134 | Send ▸ More ▸ **Show Full Screen** (a submenu of displays when there are several) shows the live code alone on a white borderless window; click or Esc returns. |
| DEV-FLASH-33 | 13 FLASH-132 | A snapshot without settings (bare data.json, or `Settings` not an object) adds `This copy carries no settings (dark mode etc. stay as they are).` to the review text. |
| DEV-FLASH-34 | 13 §6.6 "Copy" | "this PC" → "this Mac" in the intro and the snapshot warning; `Looking for the iPhone's screen…` uses the typographic ellipsis. Additions: the brightness hint, the Mac camera-distance hint, `Preparing…`, plate placeholders. All other strings are verbatim. |
| DEV-FLASH-35 | 13 §8 Q-13, FLASH-130 | An incoming `DarkMode` takes effect immediately (the reload re-applies the appearance). |
| DEV-FLASH-36 | 13 §3.14 | `AAFlashSyncInterop` prints `Swift …` where the C# harness prints `C# …`, writes LF frame files, splits frame files on bytes (CRLF safe), and answers missing arguments with the usage line (exit 2) instead of an exception. Change sets use `From = "Windows"` and 2026-09-27 12:00:00 like the C# harness, so outputs compare byte for byte. |
| DEV-FLASH-37 | 13 §6.6 | Applying is refused in a read-only instance (another AA owns the data folder), with the safe-mode message. |
| DEV-FLASH-38 | 13 §6.6 point 3 | The refresh when the window becomes key and is idle is skipped when nothing changed since the last prepare: the editors are flushed, nothing is dirty, and the data file, settings.json and the baseline carry the same path/size/modification date/inode (`FlashSourceFingerprint`). Returning from the window's own alerts or from the main window therefore no longer rebuilds the whole payload (and keeps the same session). Any change, or a failed last prepare, still re-prepares. |
| DEV-FLASH-39 | 13 §6.4 step 1, DEV-FLASH-26 | The camera permission is re-read on **Rescan** and whenever the window becomes key, so after the user allows the camera in System Settings the denied text clears and **Start camera** enables without reopening the window (and a revoked permission shows the text again). |

## Not shipped

| ID | Spec ref | Reason |
|---|---|---|
| FLASH-133 | 13 §6.4.4 | Receive from the screen (ScreenCaptureKit / iPhone Mirroring): DECISIONS 13 — "ScreenCaptureKit / iPhone-mirroring receive: **no** for v1". |

## Note for the Windows build (not a Mac change)

DEV-FLASH-05 applies to Windows → iPhone as well: Windows (Nayuki, automatic mask) flashes the zero-padded tail chunk
with mask 0, which Apple Vision's current revisions do not decode. If the iPhone's reader uses them, a small Windows →
iPhone change set (K ≤ 8, tail chunk mostly zeros) can stall. Restricting the automatic mask to 4, 6 and 7 (as the Mac
sender does) or decoding with Vision revision 2 / CIDetector on iOS removes the stall.
