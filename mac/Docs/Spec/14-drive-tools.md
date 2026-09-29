# 14 — Google Drive & Tools (`TOOLS-`)

> Porting spec for the Swift/macOS rewrite of **AA**. Contract for implementers and verifiers.
> Source of truth: the Windows WPF app (.NET 10, C#) at `AA/` in this repo, branch `mac-port`, commit `37cdab0`.
> This document describes behaviour **as it is**, including quirks. Where the C# has a latent defect, the
> defect is described exactly, then a recommendation is given (section 8). Nothing here is aspirational
> unless it is explicitly labelled **Mac addition** or **Recommended deviation**.

Files covered (all read completely):

| File | Lines | Role |
|---|---|---|
| `AA/Services/GoogleDriveUploader.cs` | 395 | Drive API client: OAuth, scopes, token cache, upload/list/download, whole-Drive search, rolling sync file, restorable-bundle name rule |
| `AA/Services/DpapiDataStore.cs` | 93 | Token cache store for the Google auth library, DPAPI-encrypted, migrates legacy plaintext tokens |
| `AA/Services/Dpapi.cs` | 65 | CryptProtectData / CryptUnprotectData P/Invoke (CurrentUser) |
| `AA/Views/FolderBuilderWindow.xaml` / `.xaml.cs` | 73 / 190 | Tools ▸ Folder builder |
| `AA/Views/DateCalculatorWindow.xaml` / `.xaml.cs` | 59 / 94 | Tools ▸ Date calculator |
| `AA/Views/UnitConverterWindow.xaml` / `.xaml.cs` | 17 / 233 | Tools ▸ Unit converter |
| `AA/MainWindow.xaml` (menu) + `AA/MainWindow.xaml.cs` (Drive parts) | 196 / 1691 | File-menu Drive commands, sync-on-save, newer-save checks, Tools-menu launchers |
| `AA/Services/DataStore.cs` (Drive/bundle parts) | 965 | Paths, settings keys, Drive-folder detection, bundle export/peek/smart import |

Also read to establish behaviour: `Views/ItemPickerWindow.xaml(.cs)` (backup picker), `Views/DiffWindow.xaml(.cs)`
(import review), `Services/AppRepository.cs` (`Save` stamps `LastModified`), `App.xaml(.cs)` (crash handler,
theme keys), `Services/ThemeManager.cs`, `FlashSync/FlashChangeSet.cs` (settings keys that never travel),
`PROGRESS.md` sections "Whole-Drive search + reads the iPhone's backups", "Text-only export/import",
"App identity", "Smart Google Drive import", "Save a copy to Google Drive", "Direct Google Drive upload",
"Load a backup from Google Drive", "Real-time Google Drive sync", "Change preview before any import",
"Folder Builder", "Date calculator", "Maritime unit converter", "Encrypt-at-rest (DPAPI)",
`QR_SYNC_PROTOCOL.md` (settings exclusion table), git history of `GoogleDriveUploader.cs` (legacy token key).

---

## 0. Conventions in this document

* `file:line` references are to the C# at the commit above. `GDU` = `Services/GoogleDriveUploader.cs`,
  `MW` = `MainWindow.xaml.cs`, `MWX` = `MainWindow.xaml`, `DS` = `Services/DataStore.cs`,
  `FB` = `Views/FolderBuilderWindow.xaml.cs`, `FBX` = its `.xaml`, `DC`/`DCX` = Date calculator, `UC`/`UCX` = Unit
  converter.
* Quoted UI strings are **exact**, including Unicode punctuation: `…` (U+2026, a single glyph), `...` (three
  ASCII dots — used in menu headers and some prompts; do NOT normalise either into the other), `▸` (U+25B8),
  `—` (U+2014), `≈` (U+2248), `➜` (U+279C), `“ ”` (U+201C/U+201D), `•` (U+2022), `📁` (U+1F4C1), `²` `³` `°`.
  `\n` inside a message is a line break. `{x}` is an interpolation. `folder{s}` means "folder" when the count is
  1 else "folders".
* WPF access keys: `_X` in a header underlines X (Alt+X on Windows). On macOS menus have no access keys — drop
  the underscore from the visible title (e.g. `Save a copy to Google _Drive (synced folder)` →
  "Save a copy to Google Drive (synced folder)").
* "Status line" = `MainWindow.StatusBlock`, the muted text in the main window header (right side). Every
  "status:" string below is written there, replacing the previous text.
* "Message box" = `MessageBox.Show(owner?, text, title, buttons, icon)`. On Mac: `NSAlert` (sheet on the owner
  window where there is one). Icons map: Information → `.informational`, Warning → `.warning`, Error →
  `.critical`, Question → `.informational` with Yes/No buttons.
* .NET `DateTime` has a *Kind* (Unspecified / Local / Utc). **Comparisons of two `DateTime`s compare ticks only
  and ignore Kind.** Several Drive decisions depend on that (section 3.2.10). The Mac port MUST model these
  values as the shared AACore .NET-DateTime type (`ticks: Int64` (100 ns since 0001-01-01) + `kind`) rather than
  `Foundation.Date`, or equality/ordering will differ from Windows.
* MUST / SHOULD / MAY have their RFC meanings for the Swift port.

---

## 1. Overview

This subsystem is two unrelated families that share a spec because both live behind menus rather than tabs.

### 1.1 Google Drive family (File menu)

AA can move its data to and from Google Drive in four ways, all built on the same **bundle** (a ZIP of
`data.json` + `files/` + `source.json`, see 4.4) produced by `DataStore.ExportFolderToZip`:

1. **Synced-folder copy** — write a timestamped bundle into the local folder that *Google Drive for desktop*
   syncs (`<Drive folder>/AA Backups/aa-data-<identity>-<yyyyMMdd-HHmmss>.zip`). No network code; Google's client
   does the upload. (TOOLS-002…006)
2. **Direct OAuth upload / download** via the Drive v3 REST API with the user's own OAuth *Desktop app* client
   (`client_secret.json`): upload a bundle into a Drive folder `AA Backups`; list every restorable bundle across
   the **whole Drive** (including iPhone `.aaz` backups and shared drives), pick one, preview the changes, import.
   (TOOLS-007…019)
3. **Real-time sync on save** — with the "Sync to Google Drive on save" toggle on, every explicit Save (Ctrl+S)
   pushes a single rolling `AA Sync/AA-sync.zip` whose Drive `appProperties` carry the data's save stamp and the
   installation identity; at startup, every 5 minutes, and on demand AA looks across the whole Drive for a save
   newer than the local one and offers to load it. (TOOLS-020…030)
4. **Import mechanics shared by all Drive pulls** — the change-review dialog, the *smart* import that applies
   only `data.json` when the incoming attachments are unchanged, and the data-only guard that never sweeps local
   attachments for a text-only bundle. (TOOLS-027…032)

Nothing here runs unless the user acts: OAuth needs a user-supplied client; sync needs the toggle; background
checks never open a browser unless a current-scope token is already cached.

### 1.2 Tools family (Tools menu)

* **Folder builder** (TOOLS-040…052) — type an indented list of folder names, see a live tree preview, and
  bulk-create the structure under a remembered base location on disk.
* **Date calculator** (TOOLS-060…071) — difference between two dates (days / weeks+days / years+months+days,
  optional inclusive end) and add/subtract days/weeks/months/years.
* **Unit converter** (TOOLS-080…090) — 14 maritime-focused categories; type in any unit and every other unit
  updates instantly.

None of the three tools writes to `data.json`. Only the Folder builder persists anything (`FolderBuilderBase`
in `settings.json`).

### 1.3 Where they are opened (menu map)

`MWX:23-71` File menu (only this subsystem's items are listed with their neighbours for order; `—` = separator):

| # | Header (exact, WPF) | Kind | Tooltip (exact) | Handler |
|---|---|---|---|---|
| … | `Set app _identity...` | item | "Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save. Always editable; defaults to the PC name." | `MenuSetIdentity_Click` (identity spec; used here) |
| — | | | | |
| … | `Open data _folder` / `_Export data folder (ZIP)...` / `I_mport data folder (ZIP)...` | items | (persistence spec) | |
| a | `Export _text only (no attachments)` | checkable | "When on, exports and Google Drive saves carry only your text, changes and formatting — not the attached files. Much smaller and far quicker over a slow link. Importing one leaves the attachments already on the other PC exactly as they are." | `MenuTextOnlyExport_Click` |
| — | | | | |
| b | `Save a copy to Google _Drive (synced folder)` | item | "Save a timestamped backup ZIP into your Google Drive desktop folder, which syncs it to the cloud." | `MenuSaveToDrive_Click` |
| c | `Set Google Drive folde_r...` | item | "Choose which local folder is your Google Drive (the one Google Drive for desktop syncs)." | `MenuSetDriveFolder_Click` |
| — | | | | |
| d | `Upload backup to Google Drive (O_Auth)...` | item | "Upload a backup directly to Google Drive via the Drive API (no desktop client needed). Requires a Google OAuth client." | `MenuUploadDriveOAuth_Click` |
| e | `_Load backup from Google Drive (OAuth)...` | item | "Download a backup from your Google Drive and (after a newer/older check) replace your current data with it." | `MenuLoadDriveOAuth_Click` |
| f | `Set Google OAuth _client (client_secret.json)...` | item | "Load the client_secret.json you downloaded from Google Cloud Console (OAuth 'Desktop app' client)." | `MenuSetOAuthClient_Click` |
| g | `Sign out of _Google` | item | "Forget the cached Google sign-in for OAuth uploads." | `MenuGoogleSignOut_Click` |
| — | | | | |
| h | `_Sync to Google Drive on save` | checkable (`x:Name="SyncOnSaveMenu"`) | "When on, Ctrl+S also pushes your data to Google Drive (OAuth), and the app checks for a newer save pushed from other PCs." | `MenuSyncOnSave_Click` |
| i | `C_heck Google Drive for newer save` | item | "Ask Google Drive whether a newer save state exists, and offer to load it." | `MenuCheckRemote_Click` |
| — | | | | |
| … | `Flash S_ync with iPhone (QR)...`, `—`, `E_xit` | | (Flash Sync spec) | |

`MWX:72-100` Tools menu, in order: `_Folder builder...` (tooltip "Bulk-create a folder structure (with
subfolders) at a location of your choice."), `Date _calculator...` (tooltip "Find the range between two dates,
or add/subtract days from a date."), `Floating _due-dates window`, `Quick _work window (Ctrl+N)`,
`Quick s_witcher (Ctrl+O)`, `_Activity log...`, `U_nit converter...` (tooltip "Convert maritime units — speed,
distance, pressure, temperature, volume, mass and more."), `—`, `Import COMPAS _crew (.xlsx)...`,
`Check crew contract e_xpiries`, `—`, `SIRE 2.0 e_xport...`, `Set _Gemini API key...`, `—`,
`Set / change _password...`, `_Lock now`. (Only the three tools are this spec's; the rest belong to other specs
but the order must be kept.)

Launch modes (`MW:304-305, 856-866`):

| Tool | Owner | Modality | Instances |
|---|---|---|---|
| Folder builder | MainWindow | **modal** (`ShowDialog`) | one at a time (modal) |
| Date calculator | MainWindow | **modal** (`ShowDialog`) | one at a time (modal) |
| Unit converter | MainWindow | **modeless** (`Show`) | **unlimited** — every menu click opens a new independent window |

No keyboard shortcut opens any of the three tools or any Drive command. The only related shortcut is Ctrl+S
(Save), which feeds sync-on-save.

---

## 2. Feature checklist

### 2.A Google Drive — synced-folder copy

**TOOLS-001 — Drive commands in the File menu.** The nine Drive-related entries (1.3 rows a–i) exist with the
exact titles, separators, order and tooltips above. `Export text only` and `Sync to Google Drive on save` are
checkable; their check state is initialised at startup from `DataStore.TextOnlyExport` / `DataStore.SyncOnSave`
(`MW:80-81`) and re-synchronised after every Drive import (`MW:449`).

**TOOLS-002 — Save a copy to Google Drive (synced folder).** `MW:661-684`. On click:
1. Resolve the Drive folder with `ResolveDriveFolder(forcePick: false)` (TOOLS-003). If it returns null
   (user cancelled), stop silently.
2. Flush the four hierarchy pages' pending editors (`EquipmentPage`, `TasksPage`, `ProceduresPage`,
   `VesselsPage` — **not** the SIRE body and **not** detached item windows; see quirk Q-12), capture UI state,
   and `_repo.Save()` (synchronous; stamps `AppData.LastModified = DateTime.Now`; a no-op in safe mode).
3. `backups = <folder>/AA Backups`; create it if missing.
4. `zip = <backups>/aa-data-{SafeIdentity(AppIdentity)}-{DateTime.Now:yyyyMMdd-HHmmss}.zip` (TOOLS-006).
5. `DataStore.ExportFolderToZip(zip)` — honours the text-only toggle (TOOLS-031). Runs synchronously on the UI
   thread.
6. Status: `Saved a copy to Google Drive: {zip}` (full path). Message box, title **"Saved to Google Drive"**,
   Information, OK: `A backup was saved to your Google Drive folder:\n\n{zip}\n\nGoogle Drive for desktop will
   sync it to the cloud.`
7. Any exception in 2–6: message box `{ex.Message}`, title **"Save to Google Drive failed"**, Error. Status is
   not changed.

There is no confirmation before writing. Files are never pruned — each click adds a new timestamped ZIP.

**TOOLS-003 — Resolve the Drive folder.** `MW:821-842` `ResolveDriveFolder(bool forcePick)`:
* If `!forcePick`: if the remembered `DataStore.GoogleDriveFolder` is non-blank **and exists** → return it.
  Else `DetectGoogleDriveFolder()` (TOOLS-005); if found → persist it (`SetGoogleDriveFolder`) and return it
  (silently — no status, no message).
* Otherwise (forced, or nothing found): message box, title **"Locate Google Drive"**, Information, OK, text:
  * forced: `Select your Google Drive folder — the local folder that Google Drive for desktop syncs.`
  * not found: `Couldn't find your Google Drive folder automatically. Please locate the local folder that Google
    Drive for desktop syncs.`
* Then a folder picker (WinForms `FolderBrowserDialog`, description **"Select your Google Drive folder"**, no
  initial path). On OK **and** the chosen path exists → persist, status `Google Drive folder set: {path}`,
  return the path. On cancel → return null (no status change).

**TOOLS-004 — Set Google Drive folder...** `MW:686` = `ResolveDriveFolder(forcePick: true)`; the returned path
is not used further. Always shows the "Select your Google Drive folder — …" message, then the picker.

**TOOLS-005 — Auto-detect the Google Drive for desktop folder.** `DS:217-235`. Candidates, first existing
directory wins (every probe wrapped in try/catch; failures skip):
1. `%USERPROFILE%\My Drive`
2. `%USERPROFILE%\Google Drive`
3. `%USERPROFILE%\GoogleDrive`
4. For every logical drive returned by `DriveInfo.GetDrives()` (A:, C:, G:, network, removable — including not
   ready ones), `<root>\My Drive` (e.g. `G:\My Drive`, the Drive-for-desktop virtual drive).

Returns null when none exists. See 6.2 for the macOS candidate list.

**TOOLS-006 — Synced-folder backup filename.** `aa-data-{SafeIdentity(DataStore.AppIdentity)}-{yyyyMMdd-HHmmss}.zip`
where the timestamp is **local** wall-clock `DateTime.Now`, and `SafeIdentity` (`MW:1521-1525`) removes every
Windows-invalid file-name character (`" < > | NUL, U+0001…U+001F, : * ? \ /`) **and every ASCII space**, then
trims; an empty result becomes `AA`. Examples in 7.1. The `aa-data` prefix is what makes the file restorable
(TOOLS-017) when Drive later lists it.

### 2.B Google Drive — OAuth client, sign-in, token

**TOOLS-007 — Set Google OAuth client (client_secret.json)...** `MW:689-713`.
* Open-file dialog: title **"Select the OAuth client_secret.json downloaded from Google Cloud Console"**, filter
  `Google client secret (*.json)|*.json|All files (*.*)|*.*` (two choices, JSON first).
* On OK: `GoogleDriveUploader.SetClientSecret(path)` — create the data folder if needed, then **copy the file
  byte-for-byte** to `<AppFolder>/google_client_secret.json`, overwriting. **No validation** of the content
  happens here (a malformed file is only discovered at the next Drive action, as an error message).
* Status `Google OAuth client set.` then message box, title **"Google OAuth"**, Information:
  `Google OAuth client saved.\n\nMake sure in Google Cloud Console you have:\n  • Enabled the Google Drive API\n
  • Created an OAuth client of type 'Desktop app'\n  • Added your Google account as a test user (if the consent
  screen is in Testing)\n\nNow use File ▸ 'Upload backup to Google Drive (OAuth)...'.` (each bullet line starts
  with two spaces).
* Exception → message box `{ex.Message}`, title **"Set OAuth client failed"**, Error.
* Setting a new client does **not** clear the cached token (quirk Q-9).

"Configured" is defined solely as `File.Exists(<AppFolder>/google_client_secret.json)` (`GDU:113`).

**TOOLS-008 — Sign-in (OAuth installed-app flow).** `GDU:155-179`. Every Drive API operation first calls
`GetServiceAsync`, which:
1. Throws `InvalidOperationException("No Google OAuth client configured. Use File ▸ 'Set Google OAuth client...' first.")`
   if not configured.
2. Parses `google_client_secret.json` with `GoogleClientSecrets.FromStreamAsync` (accepts a top-level
   `"installed"` **or** `"web"` object; uses `client_id` and `client_secret`).
3. `GoogleWebAuthorizationBroker.AuthorizeAsync(secrets, Scopes, user: "v2-wholedrive", ct, new
   DpapiDataStore(<AppFolder>/google-token))`. If a token for user key `v2-wholedrive` is cached it is used
   (refreshed silently when expired). Otherwise the library runs the **installed-app loopback flow**: it starts a
   local HTTP listener on `127.0.0.1` (fallback `localhost`) on a free ephemeral port with callback path
   `/authorize/`, opens the system default browser at Google's consent URL
   (`https://accounts.google.com/o/oauth2/v2/auth`, `response_type=code`, `access_type=offline`, the client id,
   the two scopes space-separated, `redirect_uri=http://127.0.0.1:<port>/authorize/`), waits for the redirect,
   answers the browser with a small "Received verification code. You may now close this window." page, exchanges
   the code at `https://oauth2.googleapis.com/token` (client id + client secret), and stores the token response in
   the data store.
4. Builds the Drive service with `ApplicationName = "AA"`.

User-visible: while waiting, the status line shows the caller's "… (a browser window may open)" text. There is
**no timeout and no cancel** — if the user abandons the browser, the operation never completes and the status
stays as it was (quirk Q-7). A consent refusal (`access_denied`) or other token error surfaces as the calling
command's error message box.

**TOOLS-009 — Scopes (least privilege that can read the whole Drive).** `GDU:34`:
`https://www.googleapis.com/auth/drive.readonly` + `https://www.googleapis.com/auth/drive.file`. AA can read any
file in the user's Drive but create/modify only files AA itself created. (Setup note to surface to users:
`drive.readonly` is a Google *restricted* scope — keep the OAuth consent screen in **Testing** with the Google
account added as a **Test user**, otherwise sign-in fails with `access_denied`.)

**TOOLS-010 — Scope-versioned token cache.** `GDU:36-41,115-121`. The token is stored under user key
`v2-wholedrive` (constant `ScopeVersion`). The previous build used key `user` with scope `drive.file` only; a
token minted for the old scope would keep "working" while silently returning only AA's own files, so the key was
versioned to force fresh consent. `HasToken` = the folder `<AppFolder>/google-token` exists **and** contains a
file whose name ends with `-v2-wholedrive` (ordinal, case-sensitive). A token under any other key does **not**
count.

**TOOLS-011 — Re-consent notice at startup.** `MW:100-109`. On main-window load, after data is loaded:
* If `SyncOnSave && IsConfigured && HasToken` → run the background newer-save check (TOOLS-024).
* **else if** `IsConfigured && NeedsReconsentForWholeDrive` (= `!HasToken` and the token folder exists and
  contains **any** file, `GDU:125-128`) → message box, title **"Google Drive — one more sign-in needed"**,
  Information, OK:
  `AA can now find your backups anywhere in Google Drive — including files you put there by hand, that Google
  Drive for desktop synced in, or that the iPhone app uploaded. Previously it could only see files AA itself
  created.\n\nThat needs broader permission than your existing sign-in granted, so the next Drive action will ask
  you to sign in to Google once more. AA asks for read access to your Drive plus write access only to its own
  files — it cannot change or delete anything it did not create.`
  This repeats on **every launch** until a `-v2-wholedrive` token exists or the user signs out (it is not a
  one-shot; PROGRESS.md's "one-time" means "until re-consented").
* It is shown after the safe-mode / newer-schema warnings (those use an if/else-if chain before it; this block is
  a separate if/else-if).

**TOOLS-012 — Token encrypted at rest.** `DpapiDataStore`. Each stored value (the library stores exactly one:
the `TokenResponse` for user `v2-wholedrive`) is written to `<AppFolder>/google-token/<TypeFullName>-<key>`, i.e.
`Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive`, as `ASCII("AADPAPI1") ‖
DPAPI_CurrentUser(UTF-8(Newtonsoft JSON))`. Reading a file without the magic treats it as a legacy plaintext
token, returns it, and re-stores it encrypted (best effort). Any read/decrypt failure returns "no token" (so the
flow re-prompts). Details in 3.1.6 / 4.3. The folder is created by the store's constructor, i.e. on the first
Drive action even if sign-in is then abandoned (an empty folder does not trigger TOOLS-011).

**TOOLS-013 — Sign out of Google.** `MW:813-817` → `GDU:138-142`: recursively delete `<AppFolder>/google-token`
(all keys, all versions; errors swallowed). No confirmation. Status: `Signed out of Google (OAuth token
cleared).` The client secret is **kept**; the token is **not revoked** server-side. Next Drive action re-prompts.

### 2.C Google Drive — OAuth upload / list / download

**TOOLS-014 — Upload backup to Google Drive (OAuth)...** `MW:715-755`.
1. If not configured: Yes/No question, title **"Google OAuth"**: `No Google OAuth client is configured yet.
   Choose your client_secret.json now?` No → stop. Yes → run TOOLS-007 (its own success message box appears);
   if still not configured (dialog cancelled) → stop; otherwise **continue** with the upload.
2. Flush the four hierarchy pages, capture UI state, `_repo.Save()`.
3. `temp = <system temp>/aa-data-{DateTime.Now:yyyyMMdd-HHmmss}.zip`; `ExportFolderToZip(temp)` (honours
   text-only; synchronous on the UI thread).
4. Status `Signing in to Google and uploading… (a browser window may open)`.
5. `GoogleDriveUploader.UploadAsync(temp)` (3.1.8): find-or-create Drive folder `AA Backups`, create a file
   named `aa-data-yyyyMMdd-HHmmss.zip` (**no identity in this name**, unlike TOOLS-006) with
   `appProperties = { "aaIdentity": AppIdentity }`, content type `application/zip`, in that folder (or Drive
   root if the folder lookup/creation threw), requesting fields `id, name, webViewLink`.
6. Status `Uploaded to Google Drive: {name}`; message box, title **"Uploaded to Google Drive"**, Information:
   `Uploaded '{name}' to your Google Drive (folder 'AA Backups').` followed by `\n\n{webViewLink}` when a link
   was returned. (The text says `AA Backups` even when the file landed in root — quirk Q-10.)
7. Exception anywhere: status `Google Drive upload failed.` and message box `{ex.Message}`, title **"Google Drive
   upload failed"**, Error.
8. Always delete the temp ZIP (errors swallowed).

No re-entrancy guard: clicking twice runs two uploads.

**TOOLS-015 — Load backup from Google Drive (OAuth)...** `MW:757-811`.
1. Same not-configured prompt as TOOLS-014 step 1 (same text/title).
2. Status `Signing in to Google and listing backups… (a browser window may open)`.
3. `ListBackupsAsync()` (TOOLS-016). If empty: status `No backups found on Google Drive.` and message box, title
   **"Load from Google Drive"**, Information: `No backups were found in your Google Drive 'AA Backups'
   folder.\n\nUpload one first with File ▸ 'Upload backup to Google Drive (OAuth)...'.` (text predates the
   whole-Drive search; keep verbatim). Stop.
4. Backup picker (TOOLS-018): prompt **"Choose a backup to load from Google Drive (newest first)"**, single
   selection. Cancel, or OK with nothing selected → stop silently (status still shows the "listing backups…"
   text — quirk Q-11).
5. Status `Downloading {name}…`; `temp = <system temp>/aa-drive-{DateTime.Now:yyyyMMddHHmmss}.zip` (no dash);
   `DownloadAsync(id, temp)`.
6. `incoming = DataStore.PeekZipData(temp)`; review dialog (TOOLS-027) with `incomingLast =
   incoming?.LastModified` and source name `Google Drive: {name}`. Cancelled → status `Load from Google Drive
   cancelled.` stop.
7. `kind = DataStore.ImportBundleSmart(temp)` (TOOLS-028); `LoadDataAndInitUi()` (reloads settings + data, rebuilds
   every page); status `Loaded backup from Google Drive: {name}` + ` (text only — attachments unchanged).` when
   `kind == DataOnly`, else ` (with attachments).`
8. Exception anywhere: status `Load from Google Drive failed.` + message box `{ex.Message}`, title **"Load from
   Google Drive failed"**, Error. Always delete the temp.

Note: unlike Upload, Load does **not** flush editors or save first; unsaved in-memory edits are part of the
"current" side of the review and are discarded if the user imports.

**TOOLS-016 — Whole-Drive backup listing.** `GDU:207-229`. Finds (and, as a side effect, **creates if missing**)
the `AA Backups` folder, then lists, across the whole Drive including shared drives, every non-folder,
non-trashed file that is either inside `AA Backups` or whose name matches the bundle name terms; sorted
`modifiedTime desc` by the server; filtered client-side by the restorable-bundle rule (TOOLS-017). Exact query in
3.1.9. Returns `DriveBackup(Id, Name, Modified)` records. The rolling `AA-sync.zip` is included (it matches).

**TOOLS-017 — Restorable-bundle rule (iPhone backups, `.aaz`).** `GDU:55-74` `IsRestorableBundleName(name,
mimeType)` — the contract with the iOS app's `isRestorableBundle`, plus `aa-sync`:
* empty/null name → false;
* `mimeType` starting (ordinal, case-sensitive) with `application/vnd.google-apps` (Docs, Sheets, folders,
  shortcuts, …) → false;
* lower-cased name ends with `.aaz` → true (covers `AA-backup-iOS-<stamp>.aaz` and
  `AA-backup-iOS-dataonly-<stamp>.aaz`);
* lower-cased name ends with `.zip` **and** contains `aa-data`, `aa-backup` or `aa-sync` → true;
* else false.
Used by both the listing (TOOLS-016) and best-remote detection (TOOLS-025). Vectors in 7.2.

**TOOLS-018 — Backup picker.** Reuses `ItemPickerWindow` (title **"Pick items"**, 500×500, centred on owner): a
bold prompt label, a search box (live filter: shows items whose display text contains the query, case-
insensitive, trimmed; empty query shows all), a single-selection list, buttons **Cancel** (80 wide) and **OK**
(80 wide, accent, default/Enter). Each row's text is `DriveBackup.Display`:
`{Name}    (uploaded {Modified in local time:yyyy-MM-dd HH:mm})` — exactly **four spaces** before `(` — or just
`{Name}` when Drive gave no parseable modified time. Order = server order (newest modified first).

**TOOLS-019 — Download.** `GDU:232-239`: `files.get(fileId, alt=media)` streamed into a newly created local file;
a non-completed download throws the underlying exception or `Download did not complete.`.

### 2.D Google Drive — real-time sync

**TOOLS-020 — "Sync to Google Drive on save" toggle.** `MW:490-504`. Persisted immediately as settings key
`SyncOnSave`. Turning **on**: status `Google Drive sync on save: ON`; then if not configured → message box,
title **"Google Drive sync"**, Information: `Sync is on. Set your Google OAuth client via File ▸ 'Set Google OAuth
client...' so saves can reach Drive.`; else → an **interactive** newer-save check (TOOLS-023; may open the
sign-in browser). Turning **off**: status `Google Drive sync on save: OFF`. The setting is per machine and never
travels by Flash Sync.

**TOOLS-021 — Push on explicit save (debounced, coalesced, off the UI thread).** `MW:71-73, 328-393`.
* Only `DoSave()` — Ctrl+S, the header **Save (Ctrl+S)** button, File ▸ Save — calls `MaybeQueueSync()` after a
  successful save (a failed save shows "Save failed" and does not queue; in safe mode `DoSave` refuses before
  saving, so nothing is pushed). Debounced autosaves (750 ms repository debounce), the 5-minute autosave, Save As, exports,
  imports and window close do **not** push.
* `MaybeQueueSync`: if `SyncOnSave && IsConfigured` → (re)start a **1500 ms** one-shot debounce timer. Rapid
  saves coalesce into one push 1.5 s after the last.
* On tick → `RunSyncPush()`: returns if no repo / sync off / not configured. If a push is already running, set
  `_syncQueued = true` and return. Otherwise loop: clear the queued flag; capture `stamp = _repo.Data.LastModified`;
  temp `<system temp>/aa-sync-{Guid:N}.zip`; status `Syncing to Google Drive…`; build the bundle **on a
  background thread** (`ExportFolderToZip(temp)`, honours text-only); `PushSyncAsync(temp, stamp)`;
  `_lastSeenRemote = stamp`; status `Synced to Google Drive {HH:mm:ss}` (local time); delete temp; repeat while
  another request was queued during the push.
* Any exception ends the loop: status `Drive sync failed: {ex.Message}`. No message box, no retry (the next save
  will push again).
* There is **no `HasToken` guard** here: if the user is signed out, the push opens the consent browser (the user
  did press Ctrl+S with sync on).

**TOOLS-022 — Rolling sync file.** `GDU:339-390`. One file named `AA-sync.zip` inside a Drive folder `AA Sync`
(found or created in My Drive root; falls back to root if that fails). If a non-trashed `AA-sync.zip` already
exists in that folder (or anywhere, when the folder is unavailable) it is **overwritten in place** (content +
`appProperties`, no rename, no parent change); otherwise it is created. `appProperties`:
`aaLastModified` = the data's `LastModified` in .NET round-trip format `"o"` (always 7 fractional digits and the
Kind's offset — see 4.5) or `""` when null; `aaIdentity` = `AppIdentity`. Content type `application/zip`. Manual
timestamped backups stay in `AA Backups`; the rolling file keeps Drive tidy (one file, no version pile-up).

**TOOLS-023 — Check Google Drive for newer save (interactive).** `MW:506` → `CheckRemoteNewer(interactive:
true)`. Full algorithm 3.2.4. Interactive differences from the background check: shows a message box instead of
silently returning when sync is off / unconfigured; may open the sign-in browser; reports "no save found";
re-offers a remote version the user already declined; errors go to a message box.

**TOOLS-024 — Background newer-save checks.** `CheckRemoteNewer(interactive: false)` runs (a) once at startup
when `SyncOnSave && IsConfigured && HasToken` (TOOLS-011), and (b) on **every 5-minute autosave tick** right
after `DoAutosave()` (`MW:244-250`) — regardless of whether the autosave had changes. It never opens a browser
(returns immediately without a current-scope token), never repeats a prompt for the exact remote stamp last
seen/declined, and reports errors on the status line only: `Drive check failed: {ex.Message}`.

**TOOLS-025 — Best remote across the whole Drive.** `GDU:305-335` `GetBestRemoteAsync`: lists (whole Drive incl.
shared drives, newest modified first) every non-trashed non-folder file named exactly `AA-sync.zip` or matching
the bundle terms; keeps only restorable bundles (TOOLS-017); for each, key = `aaLastModified` appProperty parsed
round-trip, else the Drive `modifiedTime` as UTC, else `DateTime.MinValue`; returns the file with the greatest key
(first wins on ties), with its id, parsed stamp (may be null), Drive modified time and `aaIdentity`. So a newer
backup from **another PC's rolling file, an OAuth upload, a synced-folder backup, or an iPhone `.aaz`** is found
wherever it lives. Kind-mixing quirk in 3.2.10.

**TOOLS-026 — "Is it newer?" and decline memory.** `newer = remote != null && (local == null || remote > local)`
(tick comparison). A remote with no stamp in appProperties (synced-folder, OAuth-upload and iPhone files) is
downloaded once to read `LastModified` from its `data.json`. `_lastSeenRemote` (in-memory, per session, starts
null) remembers the last remote stamp that was offered, pushed by this session, or imported; a **background**
check that finds exactly that stamp again returns silently, so a declined version is not re-offered every 5
minutes, and this session's own pushes are never offered back. The interactive check ignores it.

**TOOLS-027 — Review before any Drive import.** Every Drive pull (TOOLS-015, TOOLS-023/024) routes through
`ReviewAndConfirmImport(incoming, incomingLast, sourceName)` (`MW:629-642`): if the incoming `data.json` could
not be parsed → Yes/No warning, title **"Confirm import"**: `Replace your current data with '{sourceName}'?\n(Could
not read a change preview for this source.)`; else the modal **Review changes before importing** dialog
(`DiffWindow`, owned by the import-review spec) with header `Importing from: {sourceName}`, the age verdict
(`AgeVerdict`, 3.2.6), the added/changed/removed summary and drill-down tree, buttons **Cancel** /
**Import (overwrite)**. Source names used here: `Google Drive (newer save)` and `Google Drive: {file name}`.

**TOOLS-028 — Smart import (data only when attachments are unchanged).** `DS:835-887`
`ImportBundleSmart(zip)`: extract to a temp folder first (a torn/bad bundle throws before anything local
changes); require `data.json` (else `InvalidDataException("The bundle has no data.json.")`); if the bundle is a
data-only bundle (TOOLS-029) **or** its top-level `files/` set equals the local `files/` set (same names
case-insensitively, same byte sizes) → write only `data.json` and leave attachments untouched → `DataOnly`;
otherwise copy the bundle's attachments in first (overwrite), switch `data.json`, then delete local top-level
attachments the bundle doesn't have → `WithAttachments`. Always re-points the active data file to the default
`<AppFolder>/data.json`, migrates foreign absolute attachment paths, re-serialises through the local-encryption
policy, and rewrites settings (preserving password, Google client/token and every other setting). Algorithm
3.2.7.

**TOOLS-029 — Data-only bundle guard.** `DS:893-904`. A bundle is data-only when its `source.json` has
`"DataOnly": true` **or** it has no `files/` directory at all (how every iPhone `-dataonly` `.aaz` and older
text-only bundles look). An **empty** `files/` directory is NOT data-only (it means "sender has no
attachments" and will sweep local orphans). Importing a data-only bundle never deletes local attachments.

**TOOLS-030 — Who wrote the newer save.** When the best remote carries `aaIdentity`, the check's status reads
`Newer save on Google Drive from “{identity}” — downloading to preview…`; without it,
`Newer save on Google Drive — downloading to preview…`. (Identity from `source.json` is **not** consulted here.)

**TOOLS-031 — Text-only export governs Drive.** `DS:668`: every Drive export path (synced-folder copy,
OAuth upload, sync push) calls `ExportFolderToZip(zip)` = `ExportFolderToZip(zip, includeAttachments:
!TextOnlyExport)`. With **Export text only** on, bundles carry `data.json` + `source.json` only and are stamped
`DataOnly: true`. Toggle status: `Exports carry text only (no attachments)` / `Exports carry everything,
attachments included` (`MW:466-472`).

**TOOLS-032 — Google state survives imports.** Bundles never contain `google_client_secret.json`, `google-token/`
or `settings.json` (export stages only `data.json`, `files/`, `source.json`). The smart importer does not touch
them. (The legacy wipe-and-extract `ImportFolderFromZip`, `DS:727-773`, explicitly saved and restored the client
secret and token folder; it now has **no callers** — see 3.2.9.)

**TOOLS-033 — Status line vocabulary.** All status strings of this family, in one place (exact):

| When | Text |
|---|---|
| sync push start | `Syncing to Google Drive…` |
| sync push ok | `Synced to Google Drive {HH:mm:ss}` |
| sync push error | `Drive sync failed: {msg}` |
| check: nothing on Drive (interactive only) | `No AA save found on Google Drive yet.` |
| check: not newer | `Google Drive is up to date ({HH:mm:ss}).` |
| check: newer found | `Newer save on Google Drive{ from “X”} — downloading to preview…` |
| check: declined | `Kept local version (Drive has a newer one).` |
| check: imported | `Loaded newer save from Google Drive (text only — attachments unchanged).` / `Loaded newer save from Google Drive (with attachments).` |
| check error (background) | `Drive check failed: {msg}` |
| toggle | `Google Drive sync on save: ON` / `Google Drive sync on save: OFF` |
| synced-folder save | `Saved a copy to Google Drive: {zip path}` |
| folder chosen | `Google Drive folder set: {path}` |
| client set | `Google OAuth client set.` |
| upload | `Signing in to Google and uploading… (a browser window may open)` → `Uploaded to Google Drive: {name}` / `Google Drive upload failed.` |
| load | `Signing in to Google and listing backups… (a browser window may open)` → `No backups found on Google Drive.` / `Downloading {name}…` → `Load from Google Drive cancelled.` / `Loaded backup from Google Drive: {name} (text only — attachments unchanged).` / `… (with attachments).` / `Load from Google Drive failed.` |
| sign out | `Signed out of Google (OAuth token cleared).` |
| text-only toggle | `Exports carry text only (no attachments)` / `Exports carry everything, attachments included` |

`LoadDataAndInitUi()` itself sets `Loaded — {CurrentDataFile}` (or the safe-mode text) before the Drive handler
overwrites it with its own message.

**TOOLS-034 — Error surfaces.** Drive exceptions display `ex.Message` verbatim (Google client messages such as
"The service drive has thrown an exception. HttpStatusCode is Forbidden. …" or token errors such as
`Error:"access_denied", Description:"", Uri:""`). The Mac port cannot reproduce library-specific wording; it
MUST show the Drive/OAuth error's own message (`error.message` / `error` + `error_description`) and SHOULD append
the TOOLS-009 setup hint for `access_denied`, `insufficientPermissions` and `invalid_client` (Mac addition).

**TOOLS-035 — Temp-file hygiene.** Every temp ZIP (`aa-data-…zip`, `aa-drive-…zip`, `aa-sync-{guid}.zip`) is
deleted in a `finally` (errors swallowed). Extraction staging folders (`AA_import_{guid}`, `AA_export_{guid}`)
are deleted in `finally` too. Nothing is left in the user-visible data folder.

### 2.E Folder builder (Tools ▸ Folder builder...)

**TOOLS-040 — Window.** `FBX`. Title **"Folder builder"**, 820×660, centred on owner, resizable, app icon,
initial keyboard focus in the bulk text box (both `FocusManager.FocusedElement` and `Loaded → Focus()`). Layout
(12 px margin, top to bottom):
1. Heading **"Folder builder"** (15 pt bold).
2. Muted wrapped help text (exact): `Type one folder name per line on the left. Indent a line (Tab, or 2 spaces)
   to nest it as a subfolder of the line above. A line may also contain '\' or '/' to create a nested path
   directly. The right panel previews the structure that will be created under the base location.`
3. A bordered panel (PanelAlt background, 1 px border, radius 4, padding 8): label **"Base location:"**, a
   **read-only** text box `BaseBox`, and a **"Browse..."** button at the right.
4. Two equal columns separated by an 8 px draggable splitter (`GridSplitter`, border colour):
   * Left: bold **"Folder list (one per line; indent to nest)"**; a row with buttons **"Clear"** and
     **"Example"** (tooltip **"Fill in a small example structure."**); the bulk text box (multi-line, Return and Tab
     insert characters, **no wrap**, both scrollbars auto, **Consolas**).
   * Right: bold header `PreviewHeader` and a tree view (every node expanded), each node shows `📁` then the
     folder name.
5. Bottom bar (10 px top padding): left, a muted status text (initially empty); right, **"Open base folder"**,
   **"Create folders"** (accent style; access key R — header `C_reate folders`), **"Close"** (min width 80).
   None is default or cancel: Enter in the text box inserts a newline; Esc does nothing.

**TOOLS-041 — Base location.** Initialised from settings `FolderBuilderBase` (empty if unset). Editable only via
**Browse...**: folder picker with description **"Choose the base location where folders will be created"**,
pre-selected to the current base if it exists. On OK the box shows the path and it is **persisted immediately**
(`SetFolderBuilderBase`). Also persisted after every Create attempt (TOOLS-049). It can never be cleared (settings
writer keeps the old value when null).

**TOOLS-042 — Bulk text.** Not persisted (lost when the window closes). Every text change re-parses and rebuilds
the preview synchronously (no debounce).

**TOOLS-043 — Indentation nesting.** A line's depth = (number of leading `\t`) + ⌊(number of leading spaces)/2⌋
counted over the whole leading run of spaces/tabs in any order. Depth is clamped to at most one more than the
previous accepted line's depth (so over-indenting never skips a level; the first line is always a root). The
line nests under the most recent accepted line one level shallower. Blank/whitespace-only lines are ignored and
do not affect nesting. Exact algorithm 3.3.1.

**TOOLS-044 — Slash paths.** Within a line, `/` and `\` split the name into a nested chain (`Shared/Templates`
→ `Shared` ▸ `Templates`). The chain hangs under the line's resolved parent, and later deeper lines nest under the
**last** segment.

**TOOLS-045 — Name sanitisation.** Each segment: trim whitespace; replace every Windows-invalid file-name
character (`"` `<` `>` `|` NUL, U+0001–U+001F, `:` `*` `?` `\` `/`) with `_`; trim again; strip trailing `.` and
space characters. Empty segments are dropped (so `a//b` = `a/b`, and `.`/`..` segments vanish — no path
traversal). A line whose segments are all empty is ignored.

**TOOLS-046 — Duplicate merging.** Sibling names are matched case-insensitively (ordinal-ignore-case): a
repeated name reuses the existing node (first spelling kept in the preview). The creation list holds each
relative path once (case-insensitive), parent before child.

**TOOLS-047 — Live preview + count.** Header text `Preview ({n} folder{s})` where n = number of distinct
relative paths that will be created, including intermediate folders from slash paths (e.g. the Example gives
9). `folder` when n == 1, else `folders` (so `Preview (0 folders)` on open, since the constructor refreshes
once).

**TOOLS-048 — Clear / Example.** **Clear** empties the text (preview → 0). **Example** replaces the text with:
```
Project A
\tDocuments
\tImages
\tReports
\t\t2026
Project B
\tDrawings
Shared/Templates
```
(`\t` = a real tab; the text ends with a trailing `\n`.) Resulting tree and paths in 7.3.

**TOOLS-049 — Create folders.** `FB:119-163`:
1. `baseDir = BaseBox.Text.Trim()`. Blank → message box, title **"Folder builder"**, Information:
   `Choose a base location first (Browse...).` Stop.
2. Parse; no paths → status text `Nothing to create — type some folder names.` Stop (no dialog).
3. If `baseDir` doesn't exist: Yes/No question, title **"Folder builder"**: `The base location does not
   exist:\n{baseDir}\n\nCreate it?` No → stop. Yes → create it (all intermediate levels); failure → message box
   `{ex.Message}`, title **"Folder builder"**, Error; stop.
4. Confirm: Yes/No question, title **"Confirm"**: `Create {n} folder{s} under:\n{baseDir}?` No → stop.
5. For each relative path in order: `full = baseDir/<rel with / → platform separator>`; if a directory already
   exists there → `existed++`; else create it (with intermediates) → `created++`; any exception → `failed++`
   (continue).
6. Persist base (`SetFolderBuilderBase(baseDir)`), whatever the outcome.
7. Status text `Created {c}, already existed {e}` + (`, failed {f}` only when f > 0) + `.`
8. If `created > 0`: Yes/No, title **"Folder builder"**, Information icon: `Created {c} folder(s). Open the base
   location?` Yes → TOOLS-050 open.

**TOOLS-050 — Open base folder.** Button (and the post-create offer): if the path is blank or doesn't exist →
status text `Base location not found.`; else open it in Explorer (`explorer.exe <dir>`); failure → message box
`{ex.Message}`, title **"Open failed"**, Error. The button uses the untrimmed box text.

**TOOLS-051 — Close.** **Close** button closes the window (window close box too). No confirmation even with
unsaved text.

**TOOLS-052 — Theme.** Uses theme brushes `Muted`, `PanelAlt`, `BorderB` (DynamicResource) so it follows the
app's light/dark toggle live. The tree glyph `📁` is an emoji (colour).

### 2.F Date calculator (Tools ▸ Date calculator...)

**TOOLS-060 — Window.** `DCX`. Title **"Date calculator"**, 540×520, **not resizable**, centred on owner, modal.
Heading **"Date calculator"** (15 pt bold). Two bordered sections (PanelAlt background, radius 4, padding 12).
Bottom-right **"Close"** (min width 90, **IsCancel** → Esc closes).

**TOOLS-061 — Defaults.** From, To and Date pickers = today (local `DateTime.Today`). Operation = `Add`
(choices `Add`, `Subtract`). Amount = `0`. Unit = `Days` (choices `Days`, `Weeks`, `Months`, `Years`). Inclusive
unchecked. Both results computed once on open; change handlers are ignored until construction has finished
(`_ready`).

**TOOLS-062 — Section 1 "1. Difference between two dates".** Rows `From:` (label width 60) + date picker (width
180), `To:` + date picker, checkbox **"Count the end date too (inclusive)"**, and a result box (Panel
background, border, padding 10, **Consolas**, wrapping) `DiffResult`. Recomputed on either date change and on
check/uncheck. Result has exactly three lines (3.4.1). If either picker is empty (the WPF picker allows clearing
or typing an unparseable date) → `Pick both dates.`

**TOOLS-063 — Inclusive rule.** Shown total = raw day difference + 1 when the difference ≥ 0, − 1 when it is
negative (so same-day inclusive = 1 day), and ` (inclusive)` is appended. The weeks line and the Y/M/D line are
**not** affected by inclusive.

**TOOLS-064 — Weeks line.** From |raw difference|: `≈ {w} week{s}, {r} day{s}` with w = ⌊|d|/7⌋, r = |d| mod 7.

**TOOLS-065 — Years/months/days line.** Calendar difference between the earlier and later date with a borrow
rule that can produce a **negative day count** (e.g. Jan 31 → Mar 1 gives `-1 day` in a leap year). Must be
reproduced exactly (3.4.1, vectors in 7.4).

**TOOLS-066 — Section 2 "2. Add / subtract from a date".** Row `Date:` + picker; a row with the operation combo
(width 100), the amount text box (width 80, 8 px gap), the unit combo (width 110, 8 px gap); the result box
`AddResult` (Consolas, wrapping). Recomputed on any change of date, operation, amount text (every keystroke) or
unit. Empty date → `Pick a date.`

**TOOLS-067 — Amount validation.** Must parse as a 32-bit integer with .NET `NumberStyles.Integer` +
invariant culture: optional leading/trailing whitespace, optional leading `+`/`-`, ASCII digits only; no
thousands separators, decimals or exponents; overflow = invalid. Invalid → `Enter a whole number.` Negative
amounts are allowed (Add −5 = Subtract 5).

**TOOLS-068 — Add result.** Two lines: `Result: {yyyy-MM-dd} ({weekday name})` and `({+}{Δ} days from
{yyyy-MM-dd})` where Δ = actual day difference (month/year arithmetic clamps to month end, so Δ varies), `+`
prefixed when Δ ≥ 0 (so `+0`), and the word is always `days` (even ±1).

**TOOLS-069 — Out-of-range results.** Results before 0001-01-01 or after 9999-12-31 make .NET throw inside the
change handler; the app's global handler logs to `crash.log` and shows "AA hit an unexpected error and had to
stop: …" (the app actually continues), and the result box keeps its previous text. Integer overflow in
`n * 7` (Weeks) silently wraps. Recommended Mac deviation in section 8 (Q-16).

**TOOLS-070 — Number/culture formatting.** Day and week counts use .NET `N0` (current-culture digit grouping,
no decimals): `1,460` in en-US, `1.460` in de-DE. Weekday name is the current culture's full name (`dddd`). Dates
use `yyyy-MM-dd`.

**TOOLS-071 — Close / Esc.** Close button or Esc closes. Nothing persisted.

### 2.G Unit converter (Tools ▸ Unit converter...)

**TOOLS-080 — Window.** `UCX`. Title **"Unit converter"**, 500×660, centred on owner, resizable, modeless;
several can be open at once, each with its own state. Layout (14 px margin): top row bold **"Category:"** + a
category combo box (stretches); bottom muted wrapped note (exact): `Type a value in any unit — every other unit
updates instantly. Maritime-focused units included.`; middle a vertical scroll area of unit rows.

**TOOLS-081 — Categories.** Exactly 14, in this order (combo shows these names): `Speed`, `Distance / Length`,
`Pressure`, `Temperature`, `Volume`, `Mass / Weight`, `Angle / Bearing`, `Time`, `Power`, `Force`, `Density`,
`Flow rate`, `Area`, `Energy`. Initially `Speed`. Full unit table with exact factors in 3.5.3.

**TOOLS-082 — Rows.** Selecting a category rebuilds the rows: one per unit, in table order — a label (width 210,
wrapping, vertically centred) and a text box (3 px vertical margin). The **first unit's box is seeded with `1`**,
which immediately fills every other box.

**TOOLS-083 — Live conversion.** Typing in any box converts that value to the category's base unit and writes
every **other** box (the box being typed in is never rewritten, so the caret/selection is undisturbed).
Programmatic writes are guarded so they do not trigger further conversions.

**TOOLS-084 — Parsing.** .NET `double.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture)`: leading/
trailing whitespace, leading or trailing sign, parentheses for negative, `.` decimal point, `,` thousands
separators (so **`1,5` parses as 15**), exponent (`1e3`), the invariant currency symbol `¤`,
`Infinity`/`-Infinity`/`NaN` (case-insensitive); values beyond double range parse as ±Infinity. Exact rules in
3.5.2.

**TOOLS-085 — Invalid or blank input.** Clears every other box (not the edited one).

**TOOLS-086 — Output format.** NaN/±∞ → empty box; exactly 0 → `0`; |v| < 1e-4 or |v| ≥ 1e12 → `G6` invariant
(e.g. `1.15741E-05`, `1E+12`); else fixed `0.######` invariant (≤ 6 decimals, trailing zeros removed, no
grouping, `.` decimal). The two-step .NET rounding (15 significant digits, then half-away-from-zero at the 6th
decimal) MUST be reproduced — 3.5.4, vectors 7.5.

**TOOLS-087 — Conversions are exact to the table.** Linear units: `toBase = v × factor`, `fromBase = v ÷ factor`
(division, not multiplication by a reciprocal). Temperature uses Celsius as base with the formulas in 3.5.3.
Derived factors are computed in IEEE double in the written operation order.

**TOOLS-088 — Category switch resets.** Changing category discards the current values and re-seeds `1` in the
new first unit. The chosen category is not remembered (a new window starts at Speed).

**TOOLS-089 — No persistence.** Nothing is saved.

**TOOLS-090 — Theme.** The note uses the `Muted` brush; rows are default text boxes — follows light/dark.

---

## 3. Logic & algorithms

### 3.1 `GoogleDriveUploader` (Drive client)

#### 3.1.1 Constants (`GDU:27-45`)

| Name | Value | Use |
|---|---|---|
| `BackupFolderName` | `AA Backups` | Drive folder for OAuth uploads (and synced-folder subfolder name, hard-coded separately in `MW:671`) |
| `SyncFolderName` | `AA Sync` | Drive folder of the rolling file |
| `SyncFileName` | `AA-sync.zip` | the rolling file |
| `LastModifiedProp` | `aaLastModified` | appProperties key |
| `IdentityProp` | `aaIdentity` | appProperties key |
| `Scopes` | `drive.readonly`, `drive.file` (full URLs in TOOLS-009) | OAuth |
| `ScopeVersion` | `v2-wholedrive` | OAuth user key → token file suffix |
| `IosBackupPrefix` | `AA-backup` | query term |

#### 3.1.2 `IsRestorableBundleName(string? name, string? mimeType = null)` — `GDU:60-74`

```
if name is null or "" → false
if mimeType != null && mimeType.StartsWith("application/vnd.google-apps", Ordinal) → false
n = name.ToLowerInvariant()
if n.EndsWith(".aaz", Ordinal) → true
if !n.EndsWith(".zip", Ordinal) → false
return n.Contains("aa-data") || n.Contains("aa-backup") || n.Contains("aa-sync")   // ordinal
```
`IsBundleCandidate(file)` = `IsRestorableBundleName(file.Name, file.MimeType)`. Swift: use `lowercased()` (locale-
independent) and `hasSuffix`/`contains` on the lowered string; `hasPrefix` for the MIME check (case-sensitive).
Note `mimeType` is checked only when non-null; whitespace-only names are not empty and fall through to the
extension checks.

#### 3.1.3 `BundleNameQuery` — `GDU:80-81`

Exact string:
`(name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz')`.
Drive's `name contains` is case-insensitive and matches **word prefixes**, which is why `AA-backup` (not `.aaz`)
is what actually finds `AA-backup-iOS-….aaz`. Precision comes from the client-side rule.

#### 3.1.4 `SearchWholeDrive(list)` — `GDU:85-91`

Sets on a `files.list` request: `spaces=drive`, `includeItemsFromAllDrives=true`, `supportsAllDrives=true`,
`pageSize=200`. `corpora` is **not** set (server default).

#### 3.1.5 `ListAllPagesAsync(list, ct, maxPages = 10)` — `GDU:96-110`

Loop up to 10 times: set `pageToken`, execute, append `files`, stop when `nextPageToken` is empty.
**Latent defect (Q-1):** both callers restrict `fields` to `files(...)` without `nextPageToken`, and Drive's
partial-response returns only requested fields, so `nextPageToken` is never present and **only the first page
(≤ 200 results, newest modified first) is ever read**. The documented intent is up to 10 pages (2000).

#### 3.1.6 Token store (`DpapiDataStore`, `Dpapi`)

* File path: `Path.Combine(folder, $"{typeof(T).FullName}-{key}")` → for the auth library
  `Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive` (legacy: `…TokenResponse-user`).
* `StoreAsync`: `json = NewtonsoftJsonSerializer.Serialize(value)`; `enc = CryptProtectData(UTF-8(json),
  description "AA", no entropy, CRYPTPROTECT_UI_FORBIDDEN (0x1), CurrentUser scope)`; write `"AADPAPI1"` (8 ASCII
  bytes) + `enc` with `File.WriteAllBytes` (not atomic).
* `GetAsync`: missing → default (null). Starts with magic → decrypt + deserialize. Otherwise → treat as legacy
  plaintext JSON, deserialize, fire-and-forget re-store encrypted, return it. Any exception → default (null).
* `DeleteAsync`: delete that file (errors swallowed). `ClearAsync`: delete every file in the folder.
* Constructor creates the folder.

The Google library (`AuthorizationCodeFlow`) calls `DeleteAsync` itself when the token endpoint rejects a
refresh with a non-5xx error (e.g. `invalid_grant` after the user revoked access): the error surfaces once, the
token file is removed, `HasToken` turns false (background checks stop), and the next user action re-prompts.
The Mac port MUST replicate this (3.1.14 step 5).

#### 3.1.7 `GetServiceAsync(ct)` — `GDU:155-179` (see TOOLS-008)

#### 3.1.8 `UploadAsync(localFilePath, ct)` — `GDU:183-204`

1. Service; `folderId = EnsureFolderAsync("AA Backups")` (null on any error).
2. Metadata `{ name: basename(localFilePath), appProperties: { aaIdentity: AppIdentity }, parents: [folderId]
   (omitted when null) }`.
3. `files.create` media upload (the .NET client uses the **resumable** protocol, 10 MiB chunks), content type
   `application/zip`, `fields=id, name, webViewLink`.
4. Upload status not `Completed` → throw `progress.Exception` or `Exception("Upload did not complete.")`.
5. Return `UploadResult(Name: response.name ?? meta.name, Link: response.webViewLink)`.

#### 3.1.9 `ListBackupsAsync(ct)` — `GDU:207-229`

1. Service; `folderId = EnsureFolderAsync("AA Backups")` — **creates** the folder when missing.
2. `q` =
   * with folder: `('{folderId}' in parents or (name contains 'aa-data' or name contains 'AA-backup' or name
     contains 'AA-sync' or name contains '.aaz')) and trashed=false and
     mimeType!='application/vnd.google-apps.folder'`
   * without: `(name contains … '.aaz') and trashed=false and mimeType!='application/vnd.google-apps.folder'`
3. `fields=files(id,name,modifiedTime,mimeType)`, `orderBy=modifiedTime desc`, `SearchWholeDrive`, pages (3.1.5).
4. Empty → empty list. Else keep `IsBundleCandidate`, map to `DriveBackup(id, name, Modified =
   DateTimeOffset.TryParse(modifiedTimeRaw) ? value : null)`, preserving order.

#### 3.1.10 `EnsureFolderAsync(service, name, ct)` — `GDU:244-265`

```
try:
  list q = "mimeType='application/vnd.google-apps.folder' and name='{name}' and trashed=false"
       fields = "files(id,name)", spaces = "drive"   (no pageSize, no shared drives, no orderBy)
  if any → return files[0].id          // first result, unspecified order
  create { name, mimeType: "application/vnd.google-apps.folder" } (no parents → My Drive root), fields "id"
  return created.id
catch → return null                   // callers fall back to Drive root
```
With `drive.readonly` this can now return a folder **not created by AA** (e.g. made by hand or by another app);
creating a file inside it may then fail under `drive.file` (Q-3). Names are constants, so no quote escaping is
needed; the Mac port SHOULD still escape `'` and `\` in any interpolated query value.

#### 3.1.11 `GetSyncStateAsync` / `DownloadSyncAsync` — `GDU:274-299, 393-394`

Present but **unused** by the app (superseded by `GetBestRemoteAsync`). `GetSyncStateAsync`: ensure/create
`AA Sync`; list `'{folderId}' in parents and name='AA-sync.zip' and trashed=false` (or without the parent clause
when no folder), `fields=files(id,appProperties,modifiedTime)`, `spaces=drive`, `pageSize=1`; parse
`aaLastModified` (round-trip) and `aaIdentity` (non-blank), Drive modified time; null when none. The Mac port MAY
omit these; if kept, keep the same semantics.

#### 3.1.12 `GetBestRemoteAsync(ct)` — `GDU:305-335`

```
q = "trashed=false and mimeType!='application/vnd.google-apps.folder' " +
    "and (name='AA-sync.zip' or (name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz'))"
fields = "files(id,name,appProperties,modifiedTime,mimeType)"; orderBy = "modifiedTime desc"; SearchWholeDrive; pages
if none → null
best = null; bestKey = DateTime.MinValue
for f in files (server order):
    if !IsBundleCandidate(f) continue
    last = appProperties["aaLastModified"] parsed with DateTime.TryParse(raw, Invariant, RoundtripKind) else null
    identity = appProperties["aaIdentity"] if not null/whitespace else null
    driveMod = DateTimeOffset.TryParse(modifiedTimeRaw) else null
    key = last ?? driveMod?.UtcDateTime ?? DateTime.MinValue
    if key > bestKey (ticks): bestKey = key; best = SyncState(f.id, last, driveMod, identity)
return best
```
Note the space before `and (name=` in the query (the string is two concatenated literals). Ties keep the
earlier (more recently modified) file. A file whose key is `MinValue` can never win.

#### 3.1.13 `PushSyncAsync(localZipPath, lastModified, ct)` — `GDU:339-390`

1. Service; `folderId = EnsureFolderAsync("AA Sync")`.
2. Existing id: list `'{folderId}' in parents and name='AA-sync.zip' and trashed=false` (or `name='AA-sync.zip' and
   trashed=false` when no folder), `fields=files(id)`, `spaces=drive`, `pageSize=1`; take the first id.
3. `props = { "aaLastModified": lastModified?.ToString("o") ?? "", "aaIdentity": AppIdentity }`.
4. Existing → `files.update(existingId)` with body `{ appProperties: props }` (**no parents, no name**) + media,
   `application/zip`, `fields=id`; not completed → throw `progress.Exception` or `Exception("Sync upload did not
   complete.")`; id = response id ?? existing id.
   None → `files.create` with `{ name: "AA-sync.zip", appProperties: props, parents: [folderId] (if any) }` + media,
   same error text; id = response id ?? "".
5. Return `SyncState(id, lastModified, DriveModified: null, Identity: AppIdentity)` (the caller ignores it).

Drive `appProperties` update semantics: keys sent are replaced, others kept.

#### 3.1.14 OAuth flow, precisely enough to re-implement (Mac)

The Mac cannot use the .NET library; it MUST implement RFC 8252 "OAuth 2.0 for Native Apps" with a **loopback
redirect**, because the user's `client_secret.json` is a Google **Desktop app** client (the same file must work on
both OSs), and Desktop clients support only loopback redirects (custom URL schemes are not available to them):

1. Read `<AppFolder>/google_client_secret.json`; accept the `installed` or `web` object; require `client_id`
   and `client_secret` (else error "The OAuth client file is not a valid Google client_secret.json." — Mac
   wording, since .NET's message cannot be reproduced). Use `auth_uri`/`token_uri` from the file when present,
   else `https://accounts.google.com/o/oauth2/v2/auth` / `https://oauth2.googleapis.com/token`.
2. Load the token for key `v2-wholedrive` (6.3). If present and the access token is valid for ≥ 5 more minutes
   → use it. If present but expiring → refresh (`grant_type=refresh_token`, `client_id`, `client_secret`,
   `refresh_token`); keep the old refresh token when the response omits one; store.
3. Otherwise interactive: start an `NWListener` bound to `127.0.0.1`, port 0 (ephemeral); redirect URI
   `http://127.0.0.1:{port}/authorize/`; generate PKCE `code_verifier` (43–128 chars, unreserved set) and
   `code_challenge = BASE64URL(SHA256(verifier))`, method `S256`, and a random `state`; open (via
   `NSWorkspace.shared.open`) `auth_uri?response_type=code&client_id=…&redirect_uri=…&scope=https://www.googleapis.com/auth/drive.readonly%20https://www.googleapis.com/auth/drive.file&access_type=offline&code_challenge=…&code_challenge_method=S256&state=…`.
4. On the first `GET /authorize/?…` whose `state` matches: reply `200 text/html` with a page equivalent to
   "Received verification code. You may now close this window."; if `error=` is present (e.g. `access_denied`)
   fail with that error; else POST `grant_type=authorization_code`, `code`, `client_id`, `client_secret`,
   `redirect_uri` (identical string), `code_verifier` to the token URI. If the response has no `refresh_token`,
   repeat once with `prompt=consent` added (ensures an offline token after a local sign-out).
5. Token errors: a 4xx from the token endpoint during **refresh** deletes the stored token (mirrors the .NET
   library) and surfaces the error; 5xx keeps it.
6. Store the token (6.3). Build every Drive request with `Authorization: Bearer <access_token>`,
   `User-Agent: AA/<version> (macOS)`; on a 401 refresh once and retry.

### 3.2 `MainWindow` Drive orchestration

#### 3.2.1 Startup (`MW:76-109`)

After `LoadDataAndInitUi()`: set `SyncOnSaveMenu.IsChecked = SyncOnSave`, `TextOnlyExportMenu.IsChecked =
TextOnlyExport`; after safe-mode/newer-schema warnings: TOOLS-011 logic. `_lastSeenRemote` starts null.

#### 3.2.2 `MaybeQueueSync()` / debounce — `MW:71-73, 355-360`

`_syncDebounce` = one-shot 1500 ms `DispatcherTimer` created in the constructor; `Stop(); Start();` restarts it;
tick stops it and calls `RunSyncPush()`.

#### 3.2.3 `RunSyncPush()` — `MW:364-393`

`async void`, UI-thread state `_syncRunning`, `_syncQueued`. See TOOLS-021. The captured `stamp` is the in-memory
`LastModified` at loop start; the bundle's `data.json` is whatever is on disk when `ExportFolderToZip` runs
(normally the file `DoSave` just wrote). The whole loop is in one try: an exception aborts remaining queued
iterations too.

#### 3.2.4 `CheckRemoteNewer(bool interactive)` — `MW:397-464`

```
if _repo == null → return
if !SyncOnSave || !IsConfigured:
    if interactive: MessageBox("Turn on 'Sync to Google Drive on save' and set a Google OAuth client first.",
                               "Google Drive sync", OK, Information)
    return
if !interactive && !HasToken → return                    // never pop a browser unprompted
temp = null
try:
    best = await GetBestRemoteAsync()
    if best == null: if interactive: status "No AA save found on Google Drive yet."; return
    remote = best.LastModified
    if remote == null:
        temp = <tmp>/aa-drive-{Guid:N}.zip; await Download(best.FileId, temp)
        remote = PeekZipLastModified(temp)                // null if unreadable / no stamp
    local = _repo.Data.LastModified
    newer = remote != null && (local == null || remote > local)
    if !newer: status "Google Drive is up to date ({Now:HH:mm:ss})."; return   // also in background
    if !interactive && _lastSeenRemote != null && remote == _lastSeenRemote → return (silent)
    _lastSeenRemote = remote
    who = best.Identity
    status "Newer save on Google Drive" + (who blank ? "" : " from “{who}”") + " — downloading to preview…"
    if temp == null: temp = <tmp>/aa-drive-{Guid:N}.zip; await Download(best.FileId, temp)
    incoming = PeekZipData(temp)
    if !ReviewAndConfirmImport(incoming, remote, "Google Drive (newer save)"):
        status "Kept local version (Drive has a newer one)."; return
    kind = ImportBundleSmart(temp)
    LoadDataAndInitUi(); SyncOnSaveMenu.IsChecked = SyncOnSave
    _lastSeenRemote = _repo.Data.LastModified
    status kind == DataOnly ? "Loaded newer save from Google Drive (text only — attachments unchanged)."
                            : "Loaded newer save from Google Drive (with attachments)."
catch ex:
    interactive ? MessageBox(ex.Message, "Drive sync check failed", OK, Error)
                : status "Drive check failed: {ex.Message}"
finally: delete temp (swallow)
```
Notes: `_lastSeenRemote` is set **before** the review, so declining in the background means "don't ask again for
this exact stamp this session". The review's age text uses `remote` (possibly from appProperties) as
"Incoming saved". There is no flush of editors before the review; the "current" side is the in-memory model.
Concurrency: a background check may run while a push is in flight or while the user edits; no mutual exclusion
exists (Mac: see 6.5).

#### 3.2.5 `ReviewAndConfirmImport` — `MW:629-642` (TOOLS-027)

#### 3.2.6 `AgeVerdict(DateTime? incoming, DateTime? current)` — `MW:645-658`

```
inc = incoming?.ToString("yyyy-MM-dd HH:mm:ss") ?? "(no save date)"     // the value's own wall clock, no conversion
cur = current?.ToString("yyyy-MM-dd HH:mm:ss") ?? "(no save date)"
both: incoming > current → "➜ The incoming data is NEWER than your current data."
      incoming < current → "➜ The incoming data is OLDER than your current data."
      else               → "➜ The incoming data is the SAME age as your current data."
incoming only → "➜ Your current data has no save date; relative age is unknown."
current only  → "➜ The incoming data has no save date (older format); it may be older."
neither       → "➜ Neither copy has a save date; relative age is unknown."
return "Incoming saved: {inc}\nCurrent saved:  {cur}\n{verdict}"        // two spaces after "Current saved:"
```

#### 3.2.7 `DataStore.ImportBundleSmart(zipPath)` — `DS:835-887`

```
mkdir AppFolder
staging = <tmp>/AA_import_{Guid:N}
try:
  extract zip → staging            // throws on bad/torn zip or entries escaping the folder → nothing local touched
  dataSrc = staging/data.json; if missing → throw InvalidDataException("The bundle has no data.json.")
  mkdir FilesFolder
  filesSrc = staging/files
  dataOnlyBundle = IsDataOnlyBundle(staging, filesSrc)
  attachmentsChanged = !dataOnlyBundle && !AttachmentsMatch(filesSrc, FilesFolder)
  if attachmentsChanged:
      names = case-insensitive set
      for f in top-level files of filesSrc (if it exists): names += basename; copy → FilesFolder/basename (overwrite)
      CurrentDataFile = DefaultDataFile; WriteLocalDataFile(DefaultDataFile, readAllText(dataSrc))
      for f in top-level files of FilesFolder: if basename ∉ names → delete (swallow)
  else:
      CurrentDataFile = DefaultDataFile; WriteLocalDataFile(DefaultDataFile, readAllText(dataSrc))
  data = LoadFrom(DefaultDataFile)                 // parse, schema migration, path normalisation
  MigrateLegacyAbsolutePaths(data)                 // ".../files/<name>" absolute → "files/<name>" (not links / in-place)
  WriteLocalDataFile(DefaultDataFile, SerializeForSave(data))   // honours local at-rest encryption
  WriteSettings()                                   // persists CurrentDataFile, keeps everything else
  return attachmentsChanged ? WithAttachments : DataOnly
finally: delete staging (swallow)
```
Sub-directories inside the bundle's `files/` are **ignored** (only top-level files are compared/copied), while
export copies `files/` recursively (Q-14). `WriteLocalDataFile` is atomic (temp + fsync + rename) — persistence
spec.

`AttachmentsMatch(bundleDir, localDir)`: maps name→byte size for top-level files of each (case-insensitive keys;
a missing directory = empty map); equal counts and every bundle name present locally with the same size.
`IsDataOnlyBundle(staging, filesSrc)`: `source.json` exists and deserialises with `DataOnly == true` → true
(parse errors ignored); else `!exists(filesSrc)`.

#### 3.2.8 `DataStore.ExportFolderToZip(zipPath, includeAttachments)` — `DS:675-716`

```
mkdir AppFolder, FilesFolder
if fullPath(zipPath).StartsWith(fullPath(AppFolder), OrdinalIgnoreCase) → throw IOException("Choose a destination outside the AA data folder.")
if exists(zipPath) delete
staging = <tmp>/AA_export_{Guid:N}; mkdir
data.json = ReadDataText(CurrentDataFile) if it exists, else ReadDataText(DefaultDataFile) if that exists
            (decrypts an at-rest-encrypted local file; strips a UTF-8 BOM) → written UTF-8 without BOM
if includeAttachments && exists(FilesFolder): copy FilesFolder → staging/files recursively (overwrite)
source.json = BundleSource{ Identity: AppIdentity, Machine: machine name, WrittenUtc: UtcNow,
                            LastModified: PeekFileLastModified(CurrentDataFile), DataOnly: !includeAttachments }
              serialised with the app's JSON options
ZipFile.CreateFromDirectory(staging, zipPath, Optimal, includeBaseDirectory: false)
finally delete staging
```
The prefix test has no trailing separator (a sibling folder named e.g. `AA2` next to `AA` is also refused —
harmless quirk; keep). Bundle layout in 4.4.

#### 3.2.9 Legacy `ImportFolderFromZip` — `DS:727-773` (no callers)

Wipes every file and folder in `AppFolder`, extracts the ZIP over it, deletes any extracted `settings.json`,
restores `google_client_secret.json` (if it was present and is now missing) and `google-token/` (copied to a temp
folder beforehand), resets the active file to default and migrates legacy absolute paths. Not reachable from
the UI; the Mac port need not implement it. If implemented, the Google-state preservation is mandatory.

#### 3.2.10 Date/Kind semantics that decide "newer" (must be reproduced)

* `AppData.LastModified` is stamped `DateTime.Now` (Kind **Local**) by every save; when read back from JSON with
  an offset it becomes Kind Local **converted to this machine's current zone** (System.Text.Json / `GetDateTime`
  behaviour); `Z` → Kind Utc; no offset → Unspecified.
* `aaLastModified` is written with `"o"`: `yyyy-MM-ddTHH:mm:ss.fffffff` + (`+hh:mm`/`-hh:mm` for Local, `Z` for
  Utc, nothing for Unspecified). Parsed with `RoundtripKind` → same Kind rules as above.
* Drive `modifiedTime` is RFC 3339 UTC; `DateTimeOffset.UtcDateTime` → Kind Utc ticks.
* All comparisons (`>`, `==`) are on **ticks only**.
Consequences: (a) `CheckRemoteNewer` compares local-wall-clock with local-wall-clock → consistent; (b)
`GetBestRemoteAsync` compares appProperty stamps (local wall clock of the *reading* machine) against Drive
modifiedTime (UTC wall clock) for files without appProperties → east of UTC, stamped files win ties they should
lose; west of UTC, synced-folder/iPhone files win more easily (Q-5). (c) Equality for `_lastSeenRemote` needs
exact 100 ns ticks — a Mac `Double`-based `Date` round-trip can lose the last digit and make the session's own
push look "newer" by 100 ns, popping a bogus review. **The Mac port MUST parse/print these stamps with 7-digit
tick precision and keep Kind.**

### 3.3 Folder builder

#### 3.3.1 `Parse(string? text)` — `FB:40-99`

Returns `(roots: [FolderNode{Name, Children}], rels: [String])`.
```
roots = []; rels = []; seen = case-insensitive set; stack = [] of (depth, node, rel); lastDepth = -1
for raw in (text ?? "").replace("\r\n", "\n").split("\n"):
    if raw is null/empty/all-whitespace → continue                       // char.IsWhiteSpace (Unicode)
    i = 0; spaces = 0; depth = 0
    while i < len && raw[i] in {' ', '\t'}: if '\t' depth++ else spaces++; i++
    depth += spaces / 2                                                  // integer division
    name = raw[i...].Trim()                                             // Unicode whitespace trim
    if name == "" → continue
    if depth > lastDepth + 1 → depth = lastDepth + 1
    segments = name.split on '/' and '\\' → map Sanitize → drop empty
    if segments empty → continue                                         // lastDepth NOT updated
    parentNode = nil; parentRel = ""
    if depth > 0:
        search stack from top for entry with depth == depth-1 → take its node & rel
        if none → depth = 0                                              // defensive; unreachable in practice
    current = parentNode; currentRel = parentRel
    for seg in segments:
        currentRel = currentRel == "" ? seg : currentRel + "/" + seg
        siblings = current?.Children ?? roots
        existing = first sibling with Name equal to seg (OrdinalIgnoreCase), else append new node(seg)
        if seen.add(currentRel) → rels.append(currentRel)               // case-insensitive dedup
        current = existing
    stack.removeAll(depth >= this depth); stack.append((depth, current, currentRel)); lastDepth = depth
```
Observations to preserve: a stray lone `\r` is not a line break (it is trimmed at the ends or sanitised to `_` in
the middle); `rel` strings use **this line's** spelling of each segment even when an existing node with other
casing was reused (e.g. `Docs` then `docs/Sub` → rels `Docs`, `docs/Sub`); non-breaking spaces are not
indentation but are trimmed.

#### 3.3.2 `Sanitize(string s)` — `FB:101-106`

`s.Trim()` → replace each char of .NET-on-Windows `Path.GetInvalidFileNameChars()` =
`" < > | \0 \u0001 … \u001F : * ? \ /` with `_` → `Trim()` → `TrimEnd('.', ' ')`. The Mac MUST use this
Windows set (not the POSIX set `{ '\0', '/' }`), so a structure created on Mac is identical to Windows and valid
on SMB shares. Windows reserved device names (`CON`, `NUL`, `COM1`…) are **not** sanitised; on Windows their
creation fails (counted as failed); on Mac it succeeds — accepted platform difference.

#### 3.3.3 `RefreshPreview()` — `FB:30-35`

`PreviewTree.ItemsSource = roots` (tree fully expanded by style); header `Preview ({rels.Count} folder{s})`.

#### 3.3.4 `Create_Click` — TOOLS-049. Existence test is directory-only: an existing **file** at a target path
makes creation throw → counted as failed. Creation uses "create with intermediates" and never fails because the
directory already exists.

#### 3.3.5 `OpenBase(dir)` — TOOLS-050.

### 3.4 Date calculator

#### 3.4.1 `ComputeDiff()` — `DC:34-61`

```
if From or To empty → "Pick both dates."
a = From.Date; b = To.Date
totalDays = (b - a).Days                                  // whole days, may be negative
inclusive = checkbox
shown = totalDays + (inclusive ? (totalDays >= 0 ? 1 : -1) : 0)
absDays = |totalDays|; weeks = absDays / 7; remDays = absDays % 7
(s, e) = a <= b ? (a, b) : (b, a)
years = e.Year - s.Year; months = e.Month - s.Month; days = e.Day - s.Day
if days < 0: months -= 1; pm = e.AddMonths(-1); days += DaysInMonth(pm.Year, pm.Month)
if months < 0: years -= 1; months += 12
dir = totalDays < 0 ? "  (To is before From)" : ""        // two leading spaces
text = "Total: {shown:N0} day{|shown|==1 ? "" : "s"}{inclusive ? " (inclusive)" : ""}{dir}\n"
     + "≈ {weeks:N0} week{weeks==1 ? "" : "s"}, {remDays} day{remDays==1 ? "" : "s"}\n"
     + "= {Plural(years,"year")}, {Plural(months,"month")}, {Plural(days,"day")}"
Plural(n, w) = "{n} {w}{|n|==1 ? "" : "s"}"               // n printed with plain ToString() (culture minus sign)
```
The borrow uses the month **before `e`'s month** (`e.AddMonths(-1)`), not the month of `s`; when `s.Day` exceeds
that month's length the result is negative (e.g. `-1 day`, `-2 days`). Reproduce, do not "fix" (vectors 7.4).

#### 3.4.2 `ComputeAdd()` — `DC:63-89`

```
if Date empty → "Pick a date."
if !int.TryParse(Amount, NumberStyles.Integer, Invariant, out amt) → "Enter a whole number."
n = (Op == "Subtract") ? -amt : amt                       // unchecked: -int.MinValue == int.MinValue
r = Unit switch { "Weeks": d.AddDays(n * 7) /*unchecked int multiply*/, "Months": d.AddMonths(n),
                  "Years": d.AddYears(n), default: d.AddDays(n) }       // throws when outside 0001-01-01…9999-12-31
delta = (r.Date - d.Date).Days
text = "Result: {r:yyyy-MM-dd} ({r:dddd})\n({delta >= 0 ? "+" : ""}{delta:N0} days from {d:yyyy-MM-dd})"
```
`AddMonths`: same day number, clamped to the target month's last day (Jan 31 + 1 month = Feb 28/29).
`AddYears`: Feb 29 + 1 year = Feb 28. Gregorian (proleptic) calendar, no time zones involved.

### 3.5 Unit converter

#### 3.5.1 Structure — `UC:14-72`

`Unit { Name, ToBase, FromBase }`; `Linear(name, perBase)` → `ToBase = v * perBase`, `FromBase = v / perBase`;
`Custom(name, to, from)`. `Category { Name, Units }`. Categories are built once per window. `BuildRows` clears
rows, adds one label+textbox per unit (the textbox's `Tag` = its unit), subscribes `Value_Changed`, then sets the
first box's text to `"1"` (which fires `Value_Changed`).

#### 3.5.2 `Value_Changed` — `UC:74-90`

```
if _suppress or sender isn't a row box → return
if !double.TryParse(src.Text, NumberStyles.Any, InvariantCulture, out v):
    _suppress = true; every other box.Text = ""; _suppress = false; return
baseVal = srcUnit.ToBase(v)
_suppress = true; for every other row: box.Text = Format(unit.FromBase(baseVal)); _suppress = false
```
`NumberStyles.Any` with the invariant culture, exactly (implement a dedicated parser; `Double(String)` is not
equivalent):
* optional leading and trailing white space (Unicode `char.IsWhiteSpace` subset .NET accepts: U+0009–U+000D,
  U+0020);
* sign: leading `+`/`-`, **or** trailing `+`/`-`, **or** enclosing parentheses `( … )` (negative); only one form;
* currency symbol `¤` allowed before or after the number (adjacent to sign/whitespace);
* digits with `,` group separators, which .NET accepts only **after at least one digit** and **before** the
  decimal point, in any number and position (`1,2,3` = 123, `1,,2` = 12, `1,` = 1, `1,000.5` = 1000.5), while a
  leading `,5` and a `,` after the decimal point (`1.2,3`) are invalid; accepted separators are simply ignored;
* optional `.` and fractional digits; `.5` and `5.` are valid; `.` alone is invalid;
* optional exponent `e`/`E` with optional sign and ≥ 1 digit (only after at least one digit);
* when the numeric parse fails, the whitespace-trimmed text is compared case-insensitively with `Infinity`,
  `-Infinity`, `NaN`, and `+`/`-`-prefixed forms `+Infinity`, `+NaN`, `-NaN` → the IEEE values;
* magnitudes beyond `Double.greatestFiniteMagnitude` → ±Infinity (not a failure); underflow → ±0;
* anything else (letters, two decimal points, hex) → failure.
Vectors in 7.5.2 pin the behaviours that matter to users (`1,5`→15, `(5)`→−5, `5-`→−5, `1e3`, blanks).

#### 3.5.3 Unit table — `UC:102-232` (exact; factor = how many base units one unit is)

**Speed** (base: metre/second)

| # | Name | factor |
|---|---|---|
| 1 | `Knots (nautical mile/h)` | `0.514444` |
| 2 | `Kilometres per hour (km/h)` | `0.277778` (literal — not 1/3.6) |
| 3 | `Miles per hour (mph)` | `0.44704` |
| 4 | `Metres per second (m/s)` | `1.0` |
| 5 | `Feet per second (ft/s)` | `0.3048` |
| 6 | `Nautical miles per day` | `1852.0 / 86400.0` |

**Distance / Length** (base: metre)

| # | Name | factor |
|---|---|---|
| 1 | `Nautical miles (NM)` | `1852.0` |
| 2 | `Statute miles` | `1609.344` |
| 3 | `Kilometres (km)` | `1000.0` |
| 4 | `Metres (m)` | `1.0` |
| 5 | `Cables` | `185.2` |
| 6 | `Fathoms` | `1.8288` |
| 7 | `Yards` | `0.9144` |
| 8 | `Feet` | `0.3048` |
| 9 | `Inches` | `0.0254` |
| 10 | `Centimetres (cm)` | `0.01` |

**Pressure** (base: pascal)

| # | Name | factor |
|---|---|---|
| 1 | `Bar` | `100000.0` |
| 2 | `Millibar / hPa` | `100.0` |
| 3 | `Pounds per sq inch (psi)` | `6894.757293` |
| 4 | `Kilopascal (kPa)` | `1000.0` |
| 5 | `Megapascal (MPa)` | `1000000.0` |
| 6 | `Atmospheres (atm)` | `101325.0` |
| 7 | `kg-force / cm²` | `98066.5` |
| 8 | `mm of mercury (mmHg/torr)` | `133.322387` |
| 9 | `in of mercury (inHg)` | `3386.389` |
| 10 | `Pascal (Pa)` | `1.0` |

**Temperature** (base: Celsius; custom)

| # | Name | toBase | fromBase |
|---|---|---|---|
| 1 | `Celsius (°C)` | `c => c` | `c => c` |
| 2 | `Fahrenheit (°F)` | `f => (f - 32.0) * 5.0 / 9.0` | `c => c * 9.0 / 5.0 + 32.0` |
| 3 | `Kelvin (K)` | `k => k - 273.15` | `c => c + 273.15` |

(Evaluate left to right: `((f − 32) × 5) ÷ 9` and `((c × 9) ÷ 5) + 32`.)

**Volume** (base: litre)

| # | Name | factor |
|---|---|---|
| 1 | `Litres (L)` | `1.0` |
| 2 | `Cubic metres (m³)` | `1000.0` |
| 3 | `Cubic feet (ft³)` | `28.316846` |
| 4 | `US gallons` | `3.785412` |
| 5 | `Imperial gallons` | `4.546090` |
| 6 | `Oil barrels (42 US gal)` | `158.987295` |
| 7 | `US quarts` | `0.946353` |
| 8 | `Millilitres (mL)` | `0.001` |

**Mass / Weight** (base: kilogram)

| # | Name | factor |
|---|---|---|
| 1 | `Kilograms (kg)` | `1.0` |
| 2 | `Metric tonnes (t)` | `1000.0` |
| 3 | `Long tons (2240 lb)` | `1016.0469` |
| 4 | `Short tons (2000 lb)` | `907.18474` |
| 5 | `Pounds (lb)` | `0.45359237` |
| 6 | `Stone` | `6.35029318` |
| 7 | `Grams (g)` | `0.001` |

**Angle / Bearing** (base: degree)

| # | Name | factor |
|---|---|---|
| 1 | `Degrees (°)` | `1.0` |
| 2 | `Radians` | `57.29577951` (literal — not 180/π) |
| 3 | `Gradians (gon)` | `0.9` |
| 4 | `Compass points (32-pt)` | `11.25` |
| 5 | `Mils (NATO, 6400)` | `0.05625` |
| 6 | `Arcminutes (')` | `1.0 / 60.0` |

**Time** (base: second)

| # | Name | factor |
|---|---|---|
| 1 | `Seconds` | `1.0` |
| 2 | `Minutes` | `60.0` |
| 3 | `Hours` | `3600.0` |
| 4 | `Days` | `86400.0` |
| 5 | `Weeks` | `604800.0` |
| 6 | `Watches (4 h)` | `14400.0` |

**Power** (base: watt)

| # | Name | factor |
|---|---|---|
| 1 | `Kilowatts (kW)` | `1000.0` |
| 2 | `Watts (W)` | `1.0` |
| 3 | `Metric horsepower (PS)` | `735.49875` |
| 4 | `Mechanical horsepower (hp)` | `745.699872` |
| 5 | `BTU per hour` | `0.29307107` |

**Force** (base: newton)

| # | Name | factor |
|---|---|---|
| 1 | `Newtons (N)` | `1.0` |
| 2 | `Kilonewtons (kN)` | `1000.0` |
| 3 | `Tonnes-force (tf)` | `9806.65` |
| 4 | `Kilograms-force (kgf)` | `9.80665` |
| 5 | `Pounds-force (lbf)` | `4.4482216` |

**Density** (base: kg/m³)

| # | Name | factor |
|---|---|---|
| 1 | `Kilograms / m³` | `1.0` |
| 2 | `Grams / cm³ (= t/m³)` | `1000.0` |
| 3 | `Pounds / cubic foot` | `16.018463` |
| 4 | `Pounds / US gallon` | `119.826427` |

**Flow rate** (base: m³/hour)

| # | Name | factor |
|---|---|---|
| 1 | `Cubic metres / hour (m³/h)` | `1.0` |
| 2 | `Cubic metres / day` | `1.0 / 24.0` |
| 3 | `Litres / minute` | `0.06` |
| 4 | `Litres / hour` | `0.001` |
| 5 | `US gallons / minute (GPM)` | `0.2271247` |
| 6 | `Oil barrels / day` | `158.987295 / 1000.0 / 24.0` (= `(158.987295 / 1000.0) / 24.0`) |

**Area** (base: m²)

| # | Name | factor |
|---|---|---|
| 1 | `Square metres (m²)` | `1.0` |
| 2 | `Square kilometres (km²)` | `1000000.0` |
| 3 | `Hectares` | `10000.0` |
| 4 | `Square feet (ft²)` | `0.09290304` |
| 5 | `Acres` | `4046.8564` |

**Energy** (base: joule)

| # | Name | factor |
|---|---|---|
| 1 | `Kilojoules (kJ)` | `1000.0` |
| 2 | `Joules (J)` | `1.0` |
| 3 | `Kilowatt-hours (kWh)` | `3600000.0` |
| 4 | `Kilocalories (kcal)` | `4184.0` |
| 5 | `BTU` | `1055.05585` |

Totals: 6 + 10 + 10 + 3 + 8 + 7 + 6 + 6 + 5 + 5 + 4 + 6 + 5 + 5 = **86 units** in 14 categories. Names are
display text; there are no internal ids.

#### 3.5.4 `Format(double v)` — `UC:92-100`

```
if NaN or ±Infinity → ""
if v == 0 → "0"                       // also -0.0
a = |v|
if a < 1e-4 || a >= 1e12 → v.ToString("G6", Invariant)
else                     → v.ToString("0.######", Invariant)
```
Exact .NET (Core 3.0+) semantics to implement in Swift (no `String(format:)` shortcut — it rounds differently):
* **`"0.######"` (custom format)**: (1) take the shortest-correct **15 significant digits** of `v` (correctly
  rounded from the exact binary value — `.NET DoublePrecisionCustomFormat = 15`); (2) round that digit string
  to 6 fractional digits **half away from zero** (a 7th-decimal digit ≥ 5 rounds up, carrying); (3) print the
  integer part (at least `0`), then `.` and the fractional digits with trailing zeros removed (no `.` if none);
  a leading `-` for negatives. No group separators. Example: `0.1234565` → 15 digits `0.123456500000000` →
  `0.123457` (C's `%.6f` gives `0.123456`).
* **`"G6"`**: round to 6 significant digits (correctly rounded); let `e` = the decimal exponent **after**
  rounding; if `-5 < e < 6` → fixed notation, trailing zeros removed (e.g. `9.999996e-5` → `0.0001`); else
  scientific: mantissa digits with trailing zeros removed (`d` or `d.ddddd`), then `E`, sign (`+`/`-` always),
  exponent with **at least two digits** (`1E+12`, `1.15741E-05`, `1E+100`). Negative values get a leading `-`.
  In this code path fixed notation can only occur via the rounding case above.

---

## 4. Data formats

### 4.1 Files in the data folder touched here

| Path (relative to AppFolder) | Written by | Content | Travels? |
|---|---|---|---|
| `settings.json` | `WriteSettings` | see 4.2 | never in bundles; Flash Sync strips the keys below |
| `google_client_secret.json` | `SetClientSecret` | verbatim copy of the user's Google file | never |
| `google-token/` | token store | one file per stored value (4.3) | never |
| `data.json` | imports | the AppData JSON (repository/persistence spec) | inside every bundle |
| `files/` | smart import | attachments | inside full bundles |

AppFolder: Windows `%LOCALAPPDATA%\AA`; Mac `~/Library/Application Support/AA`; both overridable with env
`AA_DATA_DIR`.

### 4.2 `settings.json` keys owned or read by this subsystem

Serialised by `System.Text.Json` with the app options: compact, nulls omitted, PascalCase names in declaration
order `CurrentDataFile, PasswordHash, PasswordSalt, GoogleDriveFolder, SyncOnSave, DarkMode, FolderBuilderBase,
SharedSaveFile, EncryptLocalData, GeminiApiKey, AppIdentity, TextOnlyExport`, then unknown keys preserved
(`[JsonExtensionData]`). Booleans are always written.

| Key | Type | Meaning here | Default | Notes |
|---|---|---|---|---|
| `GoogleDriveFolder` | string? | synced-folder root (absolute local path) | absent | writer keeps the old value when the in-memory value is null → cannot be cleared |
| `SyncOnSave` | bool | TOOLS-020 | `false` | per machine |
| `FolderBuilderBase` | string? | TOOLS-041 | absent | cannot be cleared |
| `TextOnlyExport` | bool | TOOLS-031 | `false` | per machine |
| `AppIdentity` | string? | stamped into Drive metadata/filenames | machine name when blank | trimmed on set |

All five are in Flash Sync's `ExcludedSettingsKeys` (never transferred). Windows paths in these keys are
meaningless on a Mac and vice versa (see 6.2 for handling a copied settings file). Example:
`{"CurrentDataFile":"C:\\Users\\op\\AppData\\Local\\AA\\data.json","GoogleDriveFolder":"G:\\My Drive","SyncOnSave":true,"DarkMode":false,"FolderBuilderBase":"D:\\Projects","EncryptLocalData":false,"AppIdentity":"Vessel-Alpha","TextOnlyExport":false}`

### 4.3 `google-token/` (Windows)

* File name: `Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive` (current); legacy
  `Google.Apis.Auth.OAuth2.Responses.TokenResponse-user` (old `drive.file`-only sign-in; plaintext JSON in very
  old builds, DPAPI in later ones).
* Bytes: `41 41 44 50 41 50 49 31` (`AADPAPI1`) + DPAPI blob of UTF-8 JSON (Newtonsoft):
  `{"access_token":"…","token_type":"Bearer","expires_in":3599,"refresh_token":"…","scope":"https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive.file","id_token":null,"Issued":"…","IssuedUtc":"…"}`.
* **Not portable**: DPAPI blobs are bound to the Windows user account. A Mac can never read them (6.3).

### 4.4 Bundle ZIP (`.zip` / `.aaz`, identical format)

Produced by `ExportFolderToZip` (`ZipFile.CreateFromDirectory`, `CompressionLevel.Optimal` = DEFLATE, no base
directory). Entry names use `/`.

| Entry | Present | Content |
|---|---|---|
| `data.json` | always (when a data file exists) | plaintext AppData JSON exactly as on disk (decrypted), UTF-8 without BOM |
| `files/<name>` (recursive sub-paths possible) | only when attachments included and non-empty | attachment bytes |
| `files/` (directory entry) | when attachments included and the folder is **empty** | — (CreateFromDirectory emits entries for empty directories) |
| `source.json` | always | BundleSource JSON |

`source.json` (`DS:12-24`), keys in order, nulls omitted:
`{"Identity":"Vessel-Alpha","Machine":"BRIDGE-PC","WrittenUtc":"2026-09-30T08:15:30.1234567Z","LastModified":"2026-09-30T16:15:29.9876543+08:00","DataOnly":false}`
* `Identity` = AppIdentity; `Machine` = machine name (`Environment.MachineName`); `WrittenUtc` = UTC now (Kind
  Utc → `Z`); `LastModified` = the data file's own stamp (omitted when null); `DataOnly` = true for text-only
  exports. `WrittenLocal` is `[JsonIgnore]` (never written).
* System.Text.Json writes DateTime with **trailing fractional zeros trimmed** (`…:30.12Z`, `…:30Z`) — unlike the
  `"o"` format of 4.5.

Rules the Mac writer MUST follow for Windows/iOS compatibility: emit a `files/` directory entry when attachments
are included but none exist (otherwise a Windows receiver treats the bundle as data-only and keeps its orphans);
omit `files/` entirely for text-only bundles and set `DataOnly: true`; never include `settings.json`,
`google_client_secret.json` or `google-token/`. The Mac reader MUST accept `/` and `\` separators, reject entries
that escape the extraction folder (like .NET does), and look up `data.json` / `source.json` by exact name.

Bundle **names** seen on Drive (all restorable by TOOLS-017):

| Producer | Name |
|---|---|
| Windows synced-folder copy | `aa-data-{SafeIdentity}-{yyyyMMdd-HHmmss}.zip` (in `<Drive folder>/AA Backups/`) |
| Windows OAuth upload | `aa-data-{yyyyMMdd-HHmmss}.zip` (in Drive folder `AA Backups`) |
| Windows sync-on-save | `AA-sync.zip` (in Drive folder `AA Sync`) |
| Windows Export data folder | `aa-data-{yyyyMMdd-HHmm}.zip` default name (user may pick `.aaz`) |
| iPhone app | `AA-backup-iOS-{stamp}.aaz`, `AA-backup-iOS-dataonly-{stamp}.aaz` |

### 4.5 Drive file metadata written by AA

| Field | OAuth upload | Rolling sync file |
|---|---|---|
| `name` | `aa-data-yyyyMMdd-HHmmss.zip` | `AA-sync.zip` (create only) |
| `parents` | `[<AA Backups id>]` or none | `[<AA Sync id>]` or none (create only) |
| MIME (media) | `application/zip` | `application/zip` |
| `appProperties.aaIdentity` | AppIdentity | AppIdentity |
| `appProperties.aaLastModified` | — (not set) | `LastModified.ToString("o")` or `""` |

`"o"` format: always 7 fractional digits: Local → `2026-09-30T16:15:29.9876540+08:00`; Utc →
`2026-09-30T08:15:29.9876540Z`; Unspecified → `2026-09-30T16:15:29.9876540`. Drive limits each appProperty
key+value to 124 bytes (UTF-8), so an AppIdentity longer than ~113 bytes makes uploads/pushes fail with a Drive
400 error (Q-8). Folders created: `AA Backups`, `AA Sync` (MIME `application/vnd.google-apps.folder`, in My Drive
root).

### 4.6 Tools

No `data.json` fields. `FolderBuilderBase` only (4.2). The Folder builder writes directories only.

---

## 5. Dependencies

### 5.1 Calls out of this subsystem

| Callee | Used for |
|---|---|
| `AppRepository.Save()`, `.Data.LastModified`, `.IsDirty` | stamp before export; local stamp for comparisons |
| `MainWindow.CaptureUiState()`, page `FlushPendingEditors()` | before synced-folder copy / OAuth upload / Save |
| `MainWindow.LoadDataAndInitUi()` | after any Drive import (reloads settings + data, rebuilds pages, re-points item windows) |
| `DataStore.ExportFolderToZip`, `PeekZipData`, `PeekZipLastModified`, `ImportBundleSmart`, `SetGoogleDriveFolder`, `DetectGoogleDriveFolder`, `SetSyncOnSave`, `SetFolderBuilderBase`, `AppIdentity`, `TextOnlyExport` | bundle I/O + settings |
| `DataDiff.Compare`, `DiffWindow` | review before import (import-review spec) |
| `ItemPickerWindow` / `PickerItem` | backup picker |
| Google.Apis.Auth / Google.Apis.Drive.v3 (NuGet 1.75.0 / 1.74.0.4135) | OAuth + Drive REST |
| `App.ReportCrash` (global dispatcher handler) | swallowed date-calculator exceptions |

### 5.2 Callers into this subsystem

Menu handlers only (1.3), plus `DoSave` (sync push), the startup hook and the 5-minute autosave timer
(background check). Nothing else in the app references `GoogleDriveUploader` or the three tool windows. Flash
Sync references the settings keys only to exclude them.

### 5.3 Windows-only APIs used

| API | Where | Purpose |
|---|---|---|
| DPAPI `CryptProtectData`/`CryptUnprotectData` (crypt32.dll P/Invoke), `LocalFree` | `Dpapi.cs`, `DpapiDataStore.cs` | token at rest |
| `GoogleWebAuthorizationBroker` + `LocalServerCodeReceiver` (HttpListener, `Process.Start(url)`) | `GDU:165` | loopback OAuth + browser |
| WinForms `FolderBrowserDialog` | `MW:834`, `FB:110` | folder pickers |
| WPF `OpenFileDialog` | `MW:691` | client secret picker |
| `Process.Start("explorer.exe", dir)` | `FB:170` | open folder |
| `Environment.SpecialFolder.UserProfile`, `DriveInfo.GetDrives()` | `DS:217-235` | Drive-folder detection |
| `Path.GetInvalidFileNameChars()` (Windows set) | `FB:104`, `MW:1523` | sanitising names |
| `System.IO.Compression.ZipFile` | `DS` | bundles |
| WPF `DatePicker`, `DispatcherTimer`, `MessageBox`, `TreeView`, `GridSplitter` | views | UI |

---

## 6. macOS adaptation notes

### 6.1 Architecture placement

* `AACore/GoogleDrive/`: `BundleName.isRestorable(name:mimeType:)` (pure), `DriveQuery` (exact query strings),
  `GoogleClientSecret` parser, `OAuthLoopback` (NWListener + PKCE), `GoogleTokenStore`, `DriveClient` (URLSession
  REST: list with paging, get `alt=media` download-to-file, resumable create/update from file), `DriveSync`
  (best-remote selection with .NET-tick semantics). No SwiftUI.
* `AACore/Tools/`: `FolderPlan.parse(_:)` + `sanitize`, `DateCalc.diff/add` over a civil-date type,
  `UnitCatalog` + `DotNetNumberParser` + `DotNetDoubleFormatter` (`G6`, `0.######`). All pure and unit-tested.
* App target: `DriveCommands` (menu actions), `DriveSyncCoordinator` (`@MainActor`: debounce, running/queued
  flags, `lastSeenRemote`, 5-minute check hook), tool windows.

### 6.2 Synced-folder copy on macOS

* Google Drive for desktop on macOS (File Provider) mounts at `~/Library/CloudStorage/GoogleDrive-<account
  email>/My Drive`; older installs used `/Volumes/GoogleDrive/My Drive` (or `/Volumes/GoogleDrive-<id>/My Drive`)
  and legacy Backup & Sync used `~/Google Drive`. Detection order (first existing directory wins):
  1. `~/Library/CloudStorage/GoogleDrive-*/My Drive` (glob, sorted by name; with several accounts take the first
     and let "Set Google Drive folder…" change it);
  2. `/Volumes/GoogleDrive/My Drive`, then `/Volumes/*/My Drive` (analogue of "each drive root's My Drive");
  3. `~/My Drive`, `~/Google Drive`, `~/GoogleDrive` (the Windows profile candidates).
* A remembered `GoogleDriveFolder` that is **not an absolute POSIX path** (e.g. `G:\My Drive` from a copied
  Windows settings file) MUST be treated as missing, never resolved relative to the working directory. Leave the
  stored value untouched until a new one is chosen.
* Folder picker: `NSOpenPanel` (`canChooseDirectories`, `!canChooseFiles`, `canCreateDirectories`), message
  "Select your Google Drive folder", preceded by the same informational alert text as Windows.
* If the app is ever sandboxed, persist a security-scoped bookmark for the chosen folder in `UserDefaults` (not in
  `settings.json`, whose keys are shared with Windows/iOS).
* The success alert keeps its text; SHOULD offer a **Reveal in Finder** button (Mac addition,
  `NSWorkspace.activateFileViewerSelecting`).

### 6.3 OAuth & token on macOS

* Flow: 3.1.14 (loopback + system browser + PKCE). `ASWebAuthenticationSession` is **not** usable because Desktop
  clients cannot use a custom-scheme callback and loopback `http` callbacks cannot be intercepted by it.
  Entitlements if sandboxed: `com.apple.security.network.client` + `com.apple.security.network.server`.
* While waiting for consent show a small sheet: "Waiting for Google sign-in in your browser…" with **Cancel**
  (Mac addition — Windows waits forever, Q-7). Cancel stops the listener and fails the operation with a quiet
  status (`Google sign-in cancelled.`). SHOULD time out after 5 minutes.
* Token storage (Mac-private format; must preserve the Windows *semantics* of `HasToken`,
  `NeedsReconsentForWholeDrive` and Sign out, which are defined on the `google-token/` folder):
  write `<AppFolder>/google-token/Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive` containing
  `ASCII("AAKCGCM1")` + AES-256-GCM `combined` (nonce‖ciphertext‖tag) of the UTF-8 TokenResponse JSON (same field
  names as 4.3), with the 256-bit key held in the Keychain (generic password, service `AA`, account
  `google-token-key`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Coordinate the key/magic naming with the
  "encrypt local data at rest" Keychain design in the persistence spec.
* `HasToken` (Mac) = a file ending `-v2-wholedrive` exists **and starts with the Mac magic** (a copied Windows
  DPAPI file is undecryptable here and must not count, or a background check would open a browser unprompted).
  `NeedsReconsentForWholeDrive` = `!HasToken` and the folder has any file (so a copied Windows token folder shows
  the same "one more sign-in needed" alert — correct: the user must sign in on the Mac). Sign out = delete the
  folder (Keychain key may stay).
* A sign-in can never move between Windows and Mac (DPAPI, device-bound tokens). This is inherent and matches
  Flash Sync's rule that OAuth tokens never travel.

### 6.4 Drive REST details (URLSession)

* `GET https://www.googleapis.com/drive/v3/files` with `q`, `fields`, `orderBy`, `spaces`, `pageSize`,
  `pageToken`, `includeItemsFromAllDrives`, `supportsAllDrives` exactly as in 3.1. Percent-encode `q` with
  `URLComponents` (the queries contain no `+`).
* Paging: see Q-1 (recommended: request `fields=nextPageToken,files(...)` so the intended ≤10-page scan works).
* Download: `GET …/files/{id}?alt=media&supportsAllDrives=true` via `URLSession.download(for:)`, then move to
  the temp path (streams; no whole file in memory). A non-2xx → throw with Drive's message.
* Upload: resumable (`POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=…`,
  `X-Upload-Content-Type: application/zip`, JSON metadata; then `PUT` the bytes from file in chunks that are
  multiples of 256 KiB — 8 MiB recommended — or a single PUT for small files). Update = `PATCH
  …/upload/drive/v3/files/{id}?uploadType=resumable&fields=id` with `{"appProperties":{…}}`.
* Build bundles off the main actor (`Task.detached`/background executor) exactly where Windows uses
  `Task.Run` (sync push) — and SHOULD also do so for the synced-folder copy and OAuth upload, which Windows runs
  on the UI thread (no behavioural change, just no beach-ball).

### 6.5 Sync coordination on macOS

* `DriveSyncCoordinator` (`@MainActor`): `debounce: Task` restarted by `queueSync()` with a 1.5 s sleep;
  `isRunning`/`isQueued` flags with the same loop; `lastSeenRemote: DotNetDateTime?`.
* ⌘S (and the toolbar Save button, File ▸ Save) → save → `queueSync()` when on & configured.
* 5-minute timer: autosave, then `checkRemoteNewer(interactive: false)`.
* Present the review (DiffWindow equivalent) as a **sheet on the main window**; if a sheet is already up
  (another modal), queue the background prompt until it is dismissed (a background check must never stack two
  modal sheets). SHOULD skip a background check while a push or another check is running (Mac addition; avoids
  racing prompts — Windows has no guard).
* SHOULD disable Upload / Load / Check menu items while one of those operations is in flight (Mac addition —
  Windows allows duplicate runs).
* Status line: the main window's status area (shell spec). Mac addition: a small toolbar sync indicator (SF
  Symbols `arrow.triangle.2.circlepath` while pushing, `checkmark.icloud` after success, `exclamationmark.icloud`
  after failure) whose tooltip is the last status string — in addition to, not instead of, the status text.

### 6.6 Menus on macOS

* Keep all Drive items, in order, under **File** (a "Google Drive" submenu is acceptable if it contains exactly
  rows b–i with the same separators; `Export text only` stays with the export items). Titles drop the access-key
  underscore; keep `...` in titles (or render as `…` — cosmetic; tests should match the Mac titles chosen by the
  shell spec consistently). Set `NSMenuItem.toolTip` to the Windows tooltip text.
* Checkable items use a checkmark state bound to the settings.
* Tools menu keeps order; the three tools have no shortcuts (none on Windows). Closing any tool window: ⌘W.

### 6.7 Folder builder on macOS

* A standalone utility `Window` scene (single instance; bring to front if open) or a sheet — Windows is modal;
  a Mac window that is modal to the app is not required, but only one Folder builder may exist.
* Base location: `NSPathControl` (read-only display) + **Browse...** → `NSOpenPanel` (directories, can create,
  message "Choose the base location where folders will be created", `directoryURL` = current base if it exists).
  Ignore a stored base that isn't an absolute POSIX path (shows empty; Q-17).
* Bulk editor: `NSTextView` in an `NSScrollView`, monospaced token font, **no wrapping** (horizontal scroller),
  Tab inserts `\t`, and **all automatic substitutions off** (smart quotes/dashes, text replacement, spelling
  autocorrect, link detection) — they would silently change folder names. Keep `\n` line endings.
* Preview: `HSplitView`/`NSSplitView` (resizable divider) with an `OutlineGroup`/`NSOutlineView` fully expanded;
  rows `Label(name, systemImage: "folder.fill")` (SF Symbol replaces the 📁 emoji).
* Buttons: **Clear**, **Example** (help tag "Fill in a small example structure."), **Open base folder**
  (`NSWorkspace.shared.open(url)` → Finder; failure alert title "Open failed"), **Create folders** (prominent;
  ⌘↩ as Mac addition), **Close** (⌘W / Esc as Mac addition).
* Creation: `FileManager.createDirectory(at:withIntermediateDirectories:true)`, `fileExists(atPath:isDirectory:)`
  for the existed count; keep every message and count exactly. Case: on case-sensitive volumes build each path
  from the tree's canonical spelling (Q-15) so the result matches what Windows produces.

### 6.8 Date calculator on macOS

* Utility `Window` (single instance, fixed size ≈ 540×520, not resizable), Esc and ⌘W close; **Close** button
  is the cancel button.
* Date fields: SwiftUI `DatePicker(displayedComponents: .date)` in `.field` style with a calendar popover
  (`.graphical`) — Mac pickers always hold a value, so `Pick both dates.` / `Pick a date.` become unreachable;
  keep the code path anyway.
* Operation: segmented or popup `Picker` with exactly `Add` / `Subtract`; Unit popup `Days`/`Weeks`/`Months`/
  `Years`; Amount: plain `TextField` (keep free-text + validation message; a `Stepper` MAY be added beside it).
* Implement on a pure civil-date type (`year, month, day`; proleptic Gregorian; days-from-civil arithmetic) — do
  **not** use `Calendar.current` (which may be Buddhist/Japanese and is time-zone/DST sensitive). Output always
  `yyyy-MM-dd` with ASCII digits; weekday name and `N0` grouping from `Locale.current` (matches .NET current
  culture) — tests pin `en_US_POSIX`/`en_US`.
* Results in monospaced `Text` with `.textSelection(.enabled)` (Mac addition: copyable).

### 6.9 Unit converter on macOS

* `WindowGroup(id: "unit-converter")` opened with `openWindow` — each menu click opens a **new** window
  (Windows parity). Default size 500×660, resizable.
* Category: popup `Picker` at the top (a sidebar `List` with SF Symbols is acceptable as long as order, default
  and reseeding are kept — suggested symbols: `gauge.with.needle`, `ruler`, `barometer`, `thermometer.medium`,
  `drop`, `scalemass`, `safari`, `clock`, `bolt`, `arrow.right.to.line`, `cube`, `water.waves`, `square.dashed`,
  `flame`).
* Rows: `Form`/`Grid` with a 210-pt wrapping label and a `TextField`. Track the focused/edited field
  (`@FocusState` or per-field bindings) so only *other* fields are rewritten; guard programmatic writes (the
  `_suppress` flag). Do not use a `NumberFormatter`-bound field — parsing/formatting must be the .NET emulations.
* Keep the bottom note text. Monospaced digits (`.monospacedDigit()`) are a welcome cosmetic addition.

### 6.10 Dark mode

Windows swaps theme brushes (`Panel`, `PanelAlt`, `BorderB`, `Muted`, `Fg`…) live. Mac: semantic colours
(`windowBackgroundColor`, `controlBackgroundColor`, `separatorColor`, `secondaryLabelColor`) following both the
system appearance and the app's own dark-mode toggle (shell/theme spec). No tool has dark-specific behaviour
beyond colours.

### 6.11 Genuinely impossible / different on macOS

| Windows | Mac | Faithful alternative |
|---|---|---|
| DPAPI token blob | unreadable | re-sign-in on the Mac; Keychain-backed AES-GCM store (6.3) |
| `G:\My Drive` virtual drive, `%USERPROFILE%` candidates | different paths | CloudStorage/Volumes candidates (6.2) |
| Explorer | Finder | `NSWorkspace` |
| Reserved device names fail to create | succeed | accepted difference (Q-13) |
| WPF DatePicker can be emptied | cannot | messages unreachable, kept in code |

---

## 7. Test vectors / verification

### 7.1 `SafeIdentity` and backup names

| AppIdentity | SafeIdentity | Synced-folder name at 2026-09-30 14:03:07 local |
|---|---|---|
| `Vessel-Alpha` | `Vessel-Alpha` | `aa-data-Vessel-Alpha-20260930-140307.zip` |
| `Vessel Alpha` | `VesselAlpha` | `aa-data-VesselAlpha-20260930-140307.zip` |
| `M/V Nord: 1` | `MVNord1` | `aa-data-MVNord1-20260930-140307.zip` |
| `   ` (after SetAppIdentity it's the machine name; if a raw blank reached SafeIdentity) | `AA` | `aa-data-AA-20260930-140307.zip` |
| `Eris's MacBook Pro` | `Eris'sMacBookPro` | `aa-data-Eris'sMacBookPro-20260930-140307.zip` |
| `A<B>C\|D?E*F"G` | `ABCDEFG` | … |

OAuth upload name at the same instant: `aa-data-20260930-140307.zip`. Load temp: `aa-drive-20260930140307.zip`.

### 7.2 `IsRestorableBundleName`

| name | mimeType | expected |
|---|---|---|
| `AA-backup-iOS-20260930-101500.aaz` | `application/octet-stream` | true |
| `AA-backup-iOS-dataonly-20260930-101500.aaz` | nil | true |
| `aa-data-20260930-101500.zip` | `application/zip` | true |
| `aa-data-Vessel-Alpha-20260930-101500.zip` | `application/x-zip-compressed` | true |
| `AA-sync.zip` | `application/zip` | true |
| `AA-DATA-X.ZIP` | nil | true |
| `My renamed backup.AAZ` | nil | true |
| `xaa-backupx.zip` | nil | true |
| `aa-database notes` | `application/vnd.google-apps.document` | false |
| `AA Backups` | `application/vnd.google-apps.folder` | false |
| `backup.aaz` | `application/vnd.google-apps.shortcut` | false |
| `holiday-photos.zip` | `application/zip` | false |
| `aa-data.json` | `application/json` | false |
| `aa-data.zip.txt` | `text/plain` | false |
| `` (empty) / nil | any | false |

### 7.3 Folder builder `Parse`

| Input (`\t` = tab) | Tree | rels (in order) | Header |
|---|---|---|---|
| Example (TOOLS-048) | Project A▸{Documents, Images, Reports▸2026}, Project B▸Drawings, Shared▸Templates | `Project A`, `Project A/Documents`, `Project A/Images`, `Project A/Reports`, `Project A/Reports/2026`, `Project B`, `Project B/Drawings`, `Shared`, `Shared/Templates` | `Preview (9 folders)` |
| `A\n  B\n    C\n   D\n E\n` | A▸{B▸C, D}, E | `A`, `A/B`, `A/B/C`, `A/D`, `E` | `Preview (5 folders)` |
| `\t\tDeep\n\t\t\tDeeper\nTop\n\t\t\tJump` | Deep▸Deeper, Top▸Jump | `Deep`, `Deep/Deeper`, `Top`, `Top/Jump` | 4 |
| `Bad:Name?\nTrail. . \n..\n.\n a / b \\ c \nx//y` | Bad_Name_, Trail, a▸b▸c, x▸y | `Bad_Name_`, `Trail`, `a`, `a/b`, `a/b/c`, `x`, `x/y` | 7 |
| `Docs\ndocs/Sub\nDOCS\n\tInner` | Docs▸{Sub, Inner} | `Docs`, `docs/Sub`, `DOCS/Inner` | 3 |
| `Shared/Templates\n\tX\n\t\tY` | Shared▸Templates▸X▸Y | `Shared`, `Shared/Templates`, `Shared/Templates/X`, `Shared/Templates/X/Y` | 4 |
| `R\n\t  M\n` (tab + 2 spaces = depth 2, clamped to 1) | R▸M | `R`, `R/M` | 2 |
| `` / `\n\n  \n` | (empty) | — | `Preview (0 folders)` |
| `One` | One | `One` | `Preview (1 folder)` |
| `a\r\nb` | a, b | `a`, `b` | 2 |

Create outcome vectors (temp dir): Example into an empty base → status `Created 9, already existed 0.`; run
again → `Created 0, already existed 9.` and no "Open the base location?" prompt; a regular **file** named
`Project B` in the base → `Created 7, already existed 0, failed 2.` (`Project B` and `Project B/Drawings` fail).

### 7.4 Date calculator (en-US formatting)

Difference (`From → To`, inclusive flag) → DiffResult:

| From | To | incl | Result text |
|---|---|---|---|
| 2026-09-30 | 2026-09-30 | no | `Total: 0 days\n≈ 0 weeks, 0 days\n= 0 years, 0 months, 0 days` |
| 2026-09-30 | 2026-09-30 | yes | `Total: 1 day (inclusive)\n≈ 0 weeks, 0 days\n= 0 years, 0 months, 0 days` |
| 2026-01-01 | 2026-12-31 | no | `Total: 364 days\n≈ 52 weeks, 0 days\n= 0 years, 11 months, 30 days` |
| 2026-01-01 | 2026-12-31 | yes | `Total: 365 days (inclusive)\n≈ 52 weeks, 0 days\n= 0 years, 11 months, 30 days` |
| 2026-03-10 | 2026-01-15 | no | `Total: -54 days  (To is before From)\n≈ 7 weeks, 5 days\n= 0 years, 1 month, 23 days` |
| 2026-03-10 | 2026-01-15 | yes | `Total: -55 days (inclusive)  (To is before From)\n≈ 7 weeks, 5 days\n= 0 years, 1 month, 23 days` |
| 2024-01-31 | 2024-03-01 | no | `Total: 30 days\n≈ 4 weeks, 2 days\n= 0 years, 1 month, -1 day` |
| 2023-01-31 | 2023-03-01 | no | `Total: 29 days\n≈ 4 weeks, 1 day\n= 0 years, 1 month, -2 days` |
| 2020-02-29 | 2024-02-28 | no | `Total: 1,460 days\n≈ 208 weeks, 4 days\n= 3 years, 11 months, 30 days` |
| 2000-01-01 | 2026-09-30 | no | `Total: 9,769 days\n≈ 1,395 weeks, 4 days\n= 26 years, 8 months, 29 days` |
| 2026-09-23 | 2026-09-30 | no | `Total: 7 days\n≈ 1 week, 0 days\n= 0 years, 0 months, 7 days` |
| 2026-09-29 | 2026-09-30 | no | `Total: 1 day\n≈ 0 weeks, 1 day\n= 0 years, 0 months, 1 day` |
| 2026-05-31 | 2026-06-30 | no | `Total: 30 days\n≈ 4 weeks, 2 days\n= 0 years, 0 months, 30 days` |

Add/subtract → AddResult:

| Date | Op | Amount | Unit | Result text |
|---|---|---|---|---|
| 2026-09-30 | Add | `0` | Days | `Result: 2026-09-30 (Wednesday)\n(+0 days from 2026-09-30)` |
| 2026-09-30 | Add | `10` | Days | `Result: 2026-10-10 (Saturday)\n(+10 days from 2026-09-30)` |
| 2026-09-30 | Subtract | `10` | Days | `Result: 2026-09-20 (Sunday)\n(-10 days from 2026-09-30)` |
| 2026-09-30 | Add | `1` | Days | `Result: 2026-10-01 (Thursday)\n(+1 days from 2026-09-30)` |
| 2026-09-30 | Add | `2` | Weeks | `Result: 2026-10-14 (Wednesday)\n(+14 days from 2026-09-30)` |
| 2026-01-31 | Add | `1` | Months | `Result: 2026-02-28 (Saturday)\n(+28 days from 2026-01-31)` |
| 2024-01-31 | Add | `1` | Months | `Result: 2024-02-29 (Thursday)\n(+29 days from 2024-01-31)` |
| 2026-03-31 | Subtract | `1` | Months | `Result: 2026-02-28 (Saturday)\n(-31 days from 2026-03-31)` |
| 2024-02-29 | Add | `1` | Years | `Result: 2025-02-28 (Friday)\n(+365 days from 2024-02-29)` |
| 2024-02-29 | Add | `4` | Years | `Result: 2028-02-29 (Tuesday)\n(+1,461 days from 2024-02-29)` |
| 2026-09-30 | Add | `-5` | Days | `Result: 2026-09-25 (Friday)\n(-5 days from 2026-09-30)` |
| 2026-09-30 | Add | `1000` | Days | `Result: 2029-06-26 (Tuesday)\n(+1,000 days from 2026-09-30)` |
| any | any | ` 7 ` / `+7` | Days | valid (whitespace and `+` accepted) |
| any | any | `1,000` / `3.5` / `1e3` / `` / `abc` / `2147483648` | any | `Enter a whole number.` |

de-DE check: 2000-01-01 → 2026-09-30 gives `Total: 9.769 days` and `≈ 1.395 weeks, 4 days` (the words stay
English; only grouping changes).

### 7.5 Unit converter

#### 7.5.1 Seed rows (window opened, `1` in the first unit — expected text of every other box)

| Category | Unit → box text |
|---|---|
| Speed | km/h `1.851997`; mph `1.150778`; m/s `0.514444`; ft/s `1.687808`; NM/day `23.999979` |
| Distance / Length | Statute miles `1.150779`; km `1.852`; m `1852`; Cables `10`; Fathoms `1012.685914`; Yards `2025.371829`; Feet `6076.115486`; Inches `72913.385827`; cm `185200` |
| Pressure | hPa `1000`; psi `14.503774`; kPa `100`; MPa `0.1`; atm `0.986923`; kgf/cm² `1.019716`; mmHg `750.061578`; inHg `29.52998`; Pa `100000` |
| Temperature | °F `33.8`; K `274.15` |
| Volume | m³ `0.001`; ft³ `0.035315`; US gal `0.264172`; Imp gal `0.219969`; bbl `0.00629`; US qt `1.056688`; mL `1000` |
| Mass / Weight | t `0.001`; long tons `0.000984`; short tons `0.001102`; lb `2.204623`; Stone `0.157473`; g `1000` |
| Angle / Bearing | Radians `0.017453`; gon `1.111111`; points `0.088889`; mils `17.777778`; arcmin `60` |
| Time | Minutes `0.016667`; Hours `0.000278`; Days `1.15741E-05`; Weeks `1.65344E-06`; Watches `6.94444E-05` |
| Power | W `1000`; PS `1.359622`; hp `1.341022`; BTU/h `3412.141635` |
| Force | kN `0.001`; tf `0.000102`; kgf `0.101972`; lbf `0.224809` |
| Density | g/cm³ `0.001`; lb/ft³ `0.062428`; lb/US gal `0.008345` |
| Flow rate | m³/day `24`; L/min `16.666667`; L/h `1000`; GPM `4.402868`; bbl/day `150.955458` |
| Area | km² `1E-06`; Hectares `0.0001`; ft² `10.76391`; Acres `0.000247` |
| Energy | J `1000`; kWh `0.000278`; kcal `0.239006`; BTU `0.947817` |

#### 7.5.2 Targeted conversions and parsing

| Category / source value | Target → text |
|---|---|
| Temperature: 100 °C | °F `212`, K `373.15` |
| Temperature: −40 °F | °C `-40`, K `233.15` |
| Temperature: 0 K | °C `-273.15`, °F `-459.67` |
| Temperature: 98.6 °F | °C `37` |
| Speed: 15 kn | km/h `27.779954`, NM/day `359.999689` |
| Speed: 1 km/h | kn `0.539958` |
| Distance: 1 cable | NM `0.1`; 100 fathoms → m `182.88` |
| Pressure: 1e7 bar | Pa `1E+12`; 1e-10 bar → Pa `1E-05`; 1 Pa → MPa `1E-06` |
| Angle: 8 points | ° `90`; 3.14159265358979 rad → ° `180` |
| Time: 6 watches | hours `24`; 1 day → watches `6` |
| Mass: 1 long ton | lb `2239.999981`; 1 short ton → lb `2000` |
| Volume: 1 bbl | US gal `41.999998`; 1 m³ → bbl `6.289811` |
| Flow: 1000 bbl/day | m³/h `6.624471` |
| Speed box `1,5` | parsed as 15 (km/h `27.779954`) |
| any box `(5)` or `5-` | parsed as −5 |
| any box `1e3`, ` 2.5 `, `¤3` | 1000, 2.5, 3 |
| any box ``, `-`, `.`, `1e`, `e3`, `,5`, `abc`, `1.2.3`, `0x10` | invalid → all other boxes empty |
| any box `1,,2` / `1,000.5` | 12 / 1000.5 |
| any box `NaN`, `Infinity`, `1e400` | valid → all other boxes empty (Format of NaN/∞) |

#### 7.5.3 `Format` (direct)

| v | text |
|---|---|
| `0`, `-0.0` | `0` |
| `0.30000000000000004` | `0.3` |
| `0.1234565` | `0.123457` (naive `%.6f` → `0.123456` — must NOT match) |
| `0.5000005` | `0.500001` (naive → `0.5`) |
| `5.0000015` | `5.000002` (naive → `5.000001`) |
| `1234567.8912345` | `1234567.891235` |
| `999999999999.9` | `999999999999.9` |
| `1e12` | `1E+12` |
| `123456789012345.0` | `1.23457E+14` |
| `1e21` | `1E+21` |
| `0.00001234` | `1.234E-05` |
| `-1e-5` | `-1E-05` |
| `2.5e-7` | `2.5E-07` |
| `9.999996e-5` | `0.0001` |
| `0.0001` | `0.0001` |
| `-0.5` | `-0.5` |
| NaN / ±∞ | `` |

### 7.6 Drive decisions (mock `DriveClient`)

1. **Best remote, stamps vs Drive time** (reading machine at UTC+08:00): files
   A `AA-sync.zip` appProps `aaLastModified="2026-09-30T10:00:00.0000000+08:00"`, modifiedTime
   `2026-09-30T02:00:05Z`; B `aa-data-20260930-090000.zip`, no appProps, modifiedTime `2026-09-30T05:00:00Z`.
   Keys: A = 10:00 (local wall clock), B = 05:00 (UTC wall clock) → **A wins** although B is newer in real time.
   Same files read at UTC−05:00: A's key = 21:00 on 09-29 local, B = 05:00 on 09-30 → **B wins**. (Documents Q-5.)
2. **Not a bundle**: a Google Doc named `aa-data notes` with the newest modifiedTime is skipped; the next valid
   file wins.
3. **No stamp → download**: best has no appProps; the downloaded zip's `data.json` has
   `"LastModified":"2026-09-30T11:00:00+08:00"`, local is `2026-09-30T10:59:59.9999999+08:00` → newer → review.
4. **Decline memory**: background check finds remote `R`; user cancels review → status `Kept local version (Drive has a newer one).`;
   next background tick with the same `R` → no prompt, status unchanged; interactive check → prompt again.
5. **Own push not offered**: push with stamp `S` sets `lastSeenRemote = S`; next background check finds best
   stamp `S` → not newer (equal to local) → `Google Drive is up to date (HH:mm:ss).`. With a 100 ns precision loss
   this test fails — keep it.
6. **Round-trip `"o"`**: `DotNetDateTime(ticks: 639_…, kind: .local)` → `2026-09-30T16:15:29.9876543+08:00` →
   parse → identical ticks and kind; `…Z` → kind utc; no suffix → unspecified.
7. **Query strings** equal byte-for-byte to 3.1.9 / 3.1.12 / 3.1.10 / 3.1.13.
8. **HasToken**: folder with `…TokenResponse-user` only → HasToken false, NeedsReconsent true; with a Mac-magic
   `…-v2-wholedrive` → true/false; with a DPAPI (`AADPAPI1`) `…-v2-wholedrive` on Mac → false/true; empty folder →
   false/false; no folder → false/false.

### 7.7 Smart import (temp AppFolder)

| Local `files/` | Bundle | Expected kind | Local `files/` after |
|---|---|---|---|
| {a.pdf 10 B, b.png 20 B} | files {a.pdf 10, b.png 20} | DataOnly | unchanged |
| {a.pdf 10, b.png 20} | files {a.pdf 11, b.png 20} | WithAttachments | a.pdf replaced (11 B), b.png kept |
| {a.pdf, b.png} | files {a.pdf} | WithAttachments | b.png deleted |
| {a.pdf, b.png} | no `files/` entry (iPhone `-dataonly`) | DataOnly | unchanged |
| {a.pdf, b.png} | `source.json` `DataOnly:true`, no files | DataOnly | unchanged |
| {a.pdf, b.png} | empty `files/` directory entry, DataOnly false | WithAttachments | **both deleted** |
| {A.PDF 10} | files {a.pdf 10} | DataOnly (case-insensitive match) | unchanged |
| any | zip without `data.json` | throws "The bundle has no data.json." | unchanged |
| any | corrupt zip | throws | unchanged |

In every success case: `data.json` equals the bundle's (re-serialised, encrypted if local encryption on),
`settings.json` keeps password/Google/identity keys, `CurrentDataFile` = default.

### 7.8 AgeVerdict

`(2026-09-30 10:00:00, 2026-09-29 08:00:00)` →
`Incoming saved: 2026-09-30 10:00:00\nCurrent saved:  2026-09-29 08:00:00\n➜ The incoming data is NEWER than your current data.`;
`(nil, 2026-09-29 08:00:00)` → `Incoming saved: (no save date)\nCurrent saved:  2026-09-29 08:00:00\n➜ The incoming data has no save date (older format); it may be older.`

---

## 8. Known quirks, latent defects and recommended deviations

| ID | Behaviour (as is) | Recommendation for Mac |
|---|---|---|
| Q-1 | `ListAllPagesAsync` never pages: `fields` omits `nextPageToken`, so only the first 200 results (newest modified first) are considered (both listing and best-remote). | **Recommended deviation:** request `nextPageToken,files(…)` so the documented ≤10-page scan works. Identical results whenever there are ≤200 matches. |
| Q-2 | `ListBackupsAsync` creates `AA Backups` as a side effect of listing. | Keep (harmless, and the upload expects it). |
| Q-3 | `EnsureFolderAsync` may now pick an `AA Backups`/`AA Sync` folder AA did not create (readable via `drive.readonly`); uploading into it can fail under `drive.file`. | Keep query; SHOULD add `'me' in owners` or prefer a folder with `capabilities/canAddChildren` — only if the architect accepts the deviation. Otherwise surface the error. |
| Q-4 | Duplicate `AA Sync` folders: first unordered result wins, so two PCs may push into different folders (detection still works — it's whole-Drive). | Keep. |
| Q-5 | Best-remote key mixes local-wall-clock stamps with UTC Drive times (3.2.10). | Keep for parity (vector 7.6-1); do not "fix" silently. |
| Q-6 | `Download` doesn't pass `supportsAllDrives`. Best-remote/listing include shared drives, so a shared-drive file may be listed but fail to download on strict API behaviour. | Pass `supportsAllDrives=true` on get (harmless superset). |
| Q-7 | No cancel/timeout for browser sign-in; status sticks. | Mac addition: waiting sheet with Cancel, 5-minute timeout. |
| Q-8 | Long AppIdentity (> ~113 UTF-8 bytes) breaks Drive uploads/pushes (appProperties 124-byte limit). | Keep behaviour; SHOULD show a clear message ("App identity is too long for Google Drive metadata") when Drive returns that 400. |
| Q-9 | Setting a different client_secret keeps the old token (minted for the old client) → refresh fails `unauthorized_client`, the library deletes the token, next action re-prompts. | Keep; MAY clear the token when `client_id` changes (cleaner, same end state). |
| Q-10 | Upload success text always says folder 'AA Backups', even when it fell back to root. | Keep text. |
| Q-11 | Load: Cancel/empty selection leaves "Signing in to Google and listing backups…" in the status. | MAY clear/restore the status (cosmetic). |
| Q-12 | Synced-folder copy, OAuth upload and Ctrl+S flush only the four hierarchy pages (not SIRE body, not detached item windows) before saving; `FlushAllEditors` would. | **Recommended:** flush all editors (the Mac editor model may make this moot). Data-safety improvement with no visible downside. |
| Q-13 | Folder builder: Windows reserved names fail on Windows, succeed on Mac. | Accept. |
| Q-14 | Export copies `files/` recursively, smart import only reads top-level files of `files/` (sub-folders ignored; can't match). AA itself never creates sub-folders in `files/`. | Keep top-level semantics for compatibility. |
| Q-15 | Folder builder rel paths use the typed casing of reused segments; on a case-sensitive volume this would create sibling folders differing only by case. | Build rel paths from canonical node names (identical result on Windows/APFS-insensitive). |
| Q-16 | Date calculator: out-of-range results throw into the global crash handler (crash.log + "AA hit an unexpected error…" dialog); `n*7` overflow wraps (e.g. 613,566,757 weeks → +3 days). | **Recommended deviation:** compute in Int64, and when the result is outside 0001-01-01…9999-12-31 show `Result is out of range.` in the result box — never crash. |
| Q-17 | A Windows `FolderBuilderBase`/`GoogleDriveFolder` in a copied settings file would be used as a relative path on Mac. | Treat non-absolute paths as unset (6.2, 6.7). |
| Q-18 | Background check runs even while the user is typing and can raise a modal review; no guard against overlapping push/check. | Mac: queue the sheet; skip overlapping checks (6.5). |
| Q-19 | The re-consent alert repeats on every launch until re-sign-in. | Keep (it is the only hint that Drive search is limited). |
| Q-20 | No-content `ReviewAndConfirmImport` fallback uses the source name in quotes: `Replace your current data with 'Google Drive (newer save)'?…` | Keep. |
| Q-21 | Safe mode (data file unreadable at startup): `DoSave` refuses (so no sync push), but the synced-folder copy and OAuth upload call `_repo.Save()` (a silent no-op) and then bundle the **unreadable on-disk file** (usually throwing from `ReadDataText`, shown as the command's error). | SHOULD refuse both commands in safe mode with the same "Safe mode — not saving" alert the Save command uses (shell spec). |
| Q-22 | Backup picker: Esc does not cancel on Windows (Cancel isn't `IsCancel`). | Mac: Esc cancels (standard sheet behaviour). |

---

## 9. Open questions

1. Menu title punctuation on Mac: keep `...` from WPF or use `…`? (Shell spec decision; this spec's strings for
   messages are exact either way.)
2. Should the Mac port adopt Q-1 (real paging) and Q-6 (`supportsAllDrives`) — both behaviour-preserving for
   normal Drives — or stay bit-identical to the Windows first-page behaviour?
3. Keychain naming for the token-encryption key and whether it shares a key with "encrypt local data at rest".
4. Default `AppIdentity` on Mac: `Host.current().localizedName` ("Eris's MacBook Pro") vs the short host name
   (closer to `Environment.MachineName`). It flows into Drive `aaIdentity`, `source.json` and synced-folder
   filenames.
5. Should the Mac add Drive-side housekeeping (e.g. a "Show in Google Drive" link in the picker) — out of parity
   scope, listed only as ideas.
