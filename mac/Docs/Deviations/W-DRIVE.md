# W-DRIVE — P2 fixes, sanctioned deviations and Mac additions

Spec 14 (Google Drive & tools), 01 DATA-073/153, 03 SHELL-010/011/073…080/121/122. Format: ID · spec ref · one line.
Files written stay readable by the Windows build with the same meaning (DECISIONS P2).

## Sanctioned deviations (DECISIONS 14 / spec 14 §8 recommendations)

- Q-1 · 14 §3.1.5 · `files.list` requests `nextPageToken,files(…)`, so the intended ≤ 10-page whole-Drive scan works (Windows reads only the first 200 results). Identical results with ≤ 200 matches.
- Q-3 · 14 §3.1.10, DECISIONS 14 ("Q-3 harden EnsureFolder: yes") · `EnsureFolder` asks `mimeType='application/vnd.google-apps.folder' and name='{name}' and 'me' in owners and trashed=false` with `fields=files(id,name,capabilities/canAddChildren)`; it picks the first match Drive reports as `canAddChildren`, else the first whose capability is not reported (Windows' first result), else creates a new folder in My Drive root. A shared, hand-made or other-app `AA Backups` / `AA Sync` that `drive.file` cannot write into is no longer chosen. Vector 7.6-7 pins the new query and fields; `ensureFolderHardened` covers the pick.
- Q-6 · TOOLS-019 · downloads pass `supportsAllDrives=true` (shared-drive files that are listed can also be downloaded).
- Q-7 · TOOLS-008, §6.3 · interactive sign-in shows a "Waiting for Google sign-in in your browser…" sheet with Cancel (status `Google sign-in cancelled.`) and times out after 5 minutes; Windows waits forever.
- Q-8 · §4.5 · a Drive 400 while `aaIdentity` exceeds the 124-byte appProperty limit is reported as "App identity is too long for Google Drive metadata…" followed by Drive's own message.
- Q-12 · TOOLS-002/014 · the synced-folder copy and the OAuth upload flush **all** editors (incl. detached item windows and the SIRE body) before saving (`env.saveQuietly()`); Load and the newer-save check also flush before the review (ARCH §7.9), so the "current" side of the diff includes pending edits.
- Q-15 · TOOLS-046, §6.7 · Folder builder creates paths from the tree's canonical (first-seen) spelling, so a case-sensitive volume gets the same structure as Windows; the preview count and `rels` keep the Windows rule.
- Q-16 · TOOLS-069 · Date calculator computes in Int64 and shows `Result is out of range.` instead of crashing for results outside 0001-01-01…9999-12-31 (incl. the `n × 7` overflow).
- Q-17 · §6.2, §6.7 · a stored `GoogleDriveFolder` / `FolderBuilderBase` that is not an absolute POSIX path (e.g. `G:\My Drive` from a copied Windows settings file) is treated as unset and left untouched until a new folder is chosen.
- Q-18 · §6.5 · a background check is skipped while a push or another check is running; the review sheet goes through the window's dialog queue, so a background prompt never stacks on another sheet. Upload / Load / Check are disabled while one of them is in flight (router reads `inFlight`).
- DATA-174 · TOOLS-002/003/007/014/015/023 · in a read-only copy (or after DATA-180 "Stop Editing Here") the Settings ▸ Sync Drive buttons that match the router's `readOnlyDisabled` rows (Choose… folder, Save a Copy to Google Drive, Choose client_secret.json…, Check for Newer Save, Upload Backup…, Load Backup…) are disabled with the tooltip `Not available in a read-only copy of AA.`; the six `DriveActions` entry points refuse with that status text when reached anyway, and the newer-save check (background or after turning sync on) does not run. Sign Out and the sync-on-save toggle stay available, as in the menu.
- Q-21 · TOOLS-002/014 · in safe mode the synced-folder copy and the OAuth upload refuse with the "Safe mode — not saving" alert instead of bundling an unreadable file.
- TOOLS-034 · Drive / OAuth errors show Google's own message in the .NET client's wording (`The service drive has thrown an exception. HttpStatusCode is Forbidden. …`, `Error:"access_denied", Description:"…", Uri:""`) and append the setup hint for `access_denied`, `invalid_client`, `unauthorized_client` and `insufficientPermissions`.
- TOOLS-012, §6.3 · token at rest = `AAKCGCM1` + AES-256-GCM (combined) with the key in the Keychain item `AA` / `google-token-key` (DATA-215, OC-34); a copied Windows `AADPAPI1` file never counts as a token (re-consent notice shows instead); a legacy plaintext JSON token is read and re-stored encrypted (DATA-073). The token JSON is Mac-private (keys as Windows, STJ escaping).
- §3.1.14 · the loopback listener binds `127.0.0.1` only (no `localhost` fallback, RFC 8252); PKCE S256 + `state`; one retry with `prompt=consent` when no refresh token came back; a 4xx refresh deletes the token, 5xx keeps it; a 401 refreshes once and retries. The `code_verifier` is base64url of 48 random octets (64 characters, RFC 7636 §4.1's recommended form, every character equally likely).
- TOOLS-060 · Stage V ruling + design rule 14 · the Date calculator's From / To / Date fields show ISO `yyyy-MM-dd` (en_CA locale on the field only, `ToolDateCalc.pickerLocale`), like the result lines; Windows shows the system short date. The calendar popover and weekday names keep the system locale.
- TOOLS-060 / TOOLS-080 · design rule 16 · the tool windows hug their content: Date calculator stays 540 wide and fixed-size, but its height is the content's (≈ 490 pt) instead of 520 with blank space above Close; the Unit converter keeps 500 wide (width resizable) and its height follows the selected category's rows (3–10), so the card no longer stretches to the note and the rows need no scroll area. The scene half (`.windowResizability(.contentSize)` on the Unit converter, no fixed `.frame(height: 520)` on the Date calculator) is F3's `AAApp.swift` (REQ-W-DRIVE-04).
- §6.2 vs 03 §6.x · Drive-folder auto-detection uses spec 14 §6.2's order (CloudStorage `GoogleDrive-*/My Drive` sorted, `/Volumes/GoogleDrive/My Drive`, `/Volumes/*/My Drive`, then `~/My Drive`, `~/Google Drive`, `~/GoogleDrive`); 03's list puts the home candidates first — 14 is the feature owner's spec.

## Kept quirks (P3)

- Q-2 listing creates `AA Backups`; Q-4 duplicate `AA Sync` folders; Q-5 best-remote key mixes local-wall-clock stamps with UTC Drive times (vector 7.6-1 asserts it); Q-9 a new client keeps the old token; Q-10 upload text always says `AA Backups`; Q-11 Load cancel keeps the "listing backups…" status; Q-19 re-consent notice on every launch; Q-20 fallback wording; 3.4.1 negative day counts in the Y/M/D line.

## Mac additions (P4, additive)

- Saved-to-Drive alert has a **Show in Finder** button; the upload alert has **Open in Browser** when Drive returned a link.
- Sign-in sheet: countdown and **Open Browser Again**.
- Settings ▸ Sync embeds `DriveSettingsSection` (folder, client, sign-in state, sync toggle, last activity with the 14 §6.5 indicator symbols, Check / Upload / Load buttons).
- Folder builder: SF Symbol `folder.fill` replaces 📁, always-expanded preview, ⌘↩ = Create folders, Esc = Close, folder picker can create folders, read-only path display with selectable text.
- Date calculator: segmented Add/Subtract, a stepper beside the free-text amount, a calendar popover beside each date field, selectable monospaced results.
- Unit converter: category popup with SF Symbols, monospaced value fields; a field that merely gains focus never rewrites the others (only a real text change does, like WPF `TextChanged`).

## Not applicable / not shipped

- §3.1.11 `GetSyncStateAsync` / `DownloadSyncAsync` — unused on Windows; omitted (spec: MAY).
- §3.2.9 legacy `ImportFolderFromZip` — W-PERSIST's (DATA-047), not wired to UI.
- 14 §6.5 toolbar sync indicator — the main toolbar is F3's; the indicator state is published (`env.driveSync.indicator`, `lastStatus`) and shown in Settings ▸ Sync until F3 adds a toolbar slot (REQ-W-DRIVE-01).
