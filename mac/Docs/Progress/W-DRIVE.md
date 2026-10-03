# W-DRIVE — progress (Google Drive & tools)

Owner card: OWNERSHIP §3 "W-DRIVE". Feature IDs: OWNERSHIP §4.

## Counts

| Set | Done | Total |
|---|---|---|
| TOOLS-001–035, 040–052, 060–071, 080–090 | 71 | 71 |
| DATA-073, DATA-153 | 2 | 2 |
| SHELL-010–011, 073–080, 121–122 | 12 | 12 |
| **All** | **85** | **85** |

Remaining: 0. Not done: none (N/A items and deviations: `Docs/Deviations/W-DRIVE.md`).

Caller registry: VIEW-212 row 1 (backup picker) — done (`DriveActions.loadBackup`, single selection, newest first).
Vector home: 14 §7.7 smart import — written, gated on `.wPersist` (post-merge, Stage V).

## Contracts

- AACore (ARCH §6.8): `GoogleTokenStore` (+ `DriveTokenVault`), `BundleName` — real; `GoogleDriveContractStatus` = true.
- AA (ARCH §7.7): `DriveSyncCoordinator` (+ `DriveOperation`), `DriveActions` (8 commands), `DriveSettingsSection`,
  `FolderBuilderView()`, `DateCalculatorView()`, `UnitConverterView(sessionID:)` — real; no placeholders left
  (`Scripts/check-placeholders.sh W-DRIVE` prints nothing).

## Tests (AACoreTests)

- `Tools/`: unit converter (catalog, 7.5.1 seed rows of all 14 categories, 7.5.2 conversions and parsing, 7.5.3
  formatting), date calculator (7.4 difference and add tables, amount validation, de-DE, Q-16), folder plan (7.3 parse
  table, headers, sanitise, Q-15, create outcomes incl. the file-in-the-way case).
- `GoogleDrive/`: 7.1 names, 7.2 restorable table, 7.6-1…8 (best remote in two zones, non-bundles, no-stamp download,
  decline memory, own push, "o" round trip, query strings incl. the Q-3-hardened folder query, HasToken/NeedsReconsent),
  Q-3 EnsureFolder pick, 7.8 AgeVerdict, synced-folder
  detection order, token vault (Keychain item, legacy plaintext, foreign DPAPI), client file, PKCE (RFC 7636 vector),
  consent URL, live loopback redirect on 127.0.0.1, refresh rules (4xx deletes / 5xx keeps), REST paging + 401 retry,
  resumable upload, download, error texts, the whole interactive flow with a fake browser (prompt=consent retry,
  access_denied, Cancel, timeout).
- 50 test functions; gated: 2 (`.wPersist`, 14 §7.7).

## Snapshots (both appearances, `scratchpad/snapshots/W-DRIVE/`)

folder-builder (empty and with the Example + case-merge text), date-calculator (today and the 2026-09-30 → 2027-03-01
inclusive / +1000 days state), unit-converter (Speed seed and Pressure with 14.7 psi typed), sign-in waiting sheet,
Settings ▸ Sync Drive section. Registered sheets: `w-drive.sign-in`, `w-drive.settings`, `w-drive.folder-builder`,
`w-drive.date-calculator`, `w-drive.unit-converter`.

## Independent audit (2026-10-02)

Clean rebuild (`rm -rf .build`), then every assigned ID re-checked against spec 14, 01 DATA-073/153, 03
SHELL-010/011/073…080/121/122 and the C# (`GoogleDriveUploader.cs`, `MainWindow.xaml.cs` Drive parts, the three tool
windows; the 86-unit table diffed programmatically against `UnitConverterWindow.xaml.cs` — names and factors identical).

| Result | Count |
|---|---|
| IDs checked | 85 |
| OK as built | 85 (behaviour, exact strings, persistence) |
| Fixed in audit | 1 visual defect (below); no functional gaps found |
| Still missing | 0 |

Visual fix: Folder builder — on macOS 26 the `HSplitView` panes showed a grey rounded band behind the "Folder list" /
"Preview" headers (both appearances); the panes and the window root now paint `AAColor.bg`, so the bordered editor and
preview sit on a clean canvas. Re-rendered and checked in light and dark: Folder builder (empty, Example + case merge),
Date calculator (today; 2026-09-30 → 2027-03-01 inclusive / +1,000 days), Unit converter (Speed seed; Pressure with
14.7 psi typed), sign-in waiting sheet, Settings ▸ Sync Drive section.

## Verification fixes (FIX-W-DRIVE, 2026-10-03)

| Finding (V-14) | IDs | Result |
|---|---|---|
| Settings ▸ Sync Drive buttons skipped the DATA-174 read-only gate | TOOLS-002, 007, 015 (also 003, 014, 023) | Fixed: `DriveActions.isWriteGated(env)` = the router's `writeGated` (read-only copy or DATA-180 stopped editing); the six buttons matching `readOnlyDisabled` are disabled with `PersistReadOnlyText.disabledHelp` as tooltip; the six actions refuse (status text) when reached anyway; `checkRemoteNewer` returns early while gated. |
| DECISIONS 14 "Q-3 harden EnsureFolder: yes" not implemented | TOOLS-014, 016, 022 | Fixed: query adds `'me' in owners`; fields `files(id,name,capabilities/canAddChildren)`; pick = first writable, else first with unknown capability, else create. Vector 7.6-7 updated; new test `ensureFolderHardened` (writable-over-read-only, all-read-only → create, unknown → first, REST row parsing). Q-3 moved from "Kept quirks" to "Sanctioned deviations" in `Docs/Deviations/W-DRIVE.md`. |
| Drive footers in Settings ▸ Sync were monospaced and outside the boxes | TOOLS-001 | Fixed: both help lines are in-section rows (`DriveSettingsHelp`: callout, secondary, wrapping) — the same style as the Shared Save File / Exports help. The `w-drive.settings` debug sheet resets to `.body` so it renders like the Settings scene. |

Counts: findings 3 · fixed 3 · not fixed 0. Tests: 1,587 passing (+1 Drive test function).
Snapshots (light and dark, checked): `scratchpad/snapshots/fix1-W-DRIVE/` — `settings-sync-*.png` (Settings scene,
Sync tab), `w-drive-settings-*.png` (the whole Drive section incl. the OAuth part below the Settings fold).
Not rendered: the read-only state (no snapshot switch for a read-only instance); the gate is the same expression the
router uses (`CommandRouter` context `writeGated`).
Lead request: `Docs/DEVIATIONS.md` (lead-owned) still lists Q-3 under W-DRIVE "Kept quirks"; see crossOwnerRequests.

## Verification fixes round 2 (FIX2-W-DRIVE, 2026-10-03)

| Finding | By | IDs | Result |
|---|---|---|---|
| Production Drive transport could not be driven by a mock `URLProtocol` (no test of 308 / User-Agent / staging move) | V2-J6 | TOOLS-014…019, 14 §6.4, §3.1.14 step 6 | Fixed: `DriveURLSessionTransport.init(configuration:)` applies AA's settings on top of a given configuration (production `init()` = ephemeral). New `DriveTransportTests` (4) drive the real URLSession through a scripted `URLProtocol` that reports 3xx+Location as a redirect like CFNetwork: `User-Agent: AA/<v> (macOS)` on the wire, a 308 with `Range` + `Location` returned unfollowed (one request seen), a 70 KB download moved to `tmp/aa-drive-dl-*` intact, 403 handed back, offline → `DriveError.transport` for data and download. Mutation-checked: following the redirect, dropping the header or skipping the move each fails. |
| PKCE `code_verifier` modulo bias (`byte % 66`) | V2-J6 | §3.1.14 step 3 | Fixed: verifier = base64url of 48 random octets (64 characters, RFC 7636 §4.1). Test `pkceVerifierIsUnbiased`: 48 octets packing 0…63 yield all 64 symbols once, round-trip decodes to the octets, 0xFF… → `_` only. |
| Date calculator pickers showed `10/ 3/2026` beside ISO results | V2-DESIGN | TOOLS-060…062 | Fixed: the stepper date field carries `.environment(\.locale, ToolDateCalc.pickerLocale)` (en_CA, Stage V ruling); popover and weekday names keep the system locale. Test `pickerLocaleShowsISODates` (short date in the picker locale = `2026-10-03` = the `Result:` date). |
| Tool windows stretched a card to fill the window (rule 16) | V2-DESIGN | TOOLS-060, TOOLS-080 | Fixed (W-DRIVE half): Date calculator = 540 wide, height fixed to content, no Spacer above Close; Unit converter = card hugs the rows (no stretched scroll area), root fixed vertically, width 460…∞. Scene half is F3's (REQ-W-DRIVE-04: `.windowResizability(.contentSize)` on the Unit converter; drop `.frame(width: 540, height: 520)` around the Date calculator). Login window: F3 (`Sources/AA/Shell/LoginView.swift`), forwarded. |

Counts: findings 4 · fixed 4 (one needs F3's scene half) · rejected 0. Tests: 1,660 passing (+6: 4 transport, 1 PKCE,
1 picker locale). No regression test for the layout (AA target is not testable from AACoreTests); checked by snapshot.
Snapshots (light and dark, checked) in `scratchpad/snapshots/fix2-W-DRIVE/`: `scene-date-calculator-*`,
`scene-unit-converter-*` (with REQ-W-DRIVE-04 applied locally, not committed: windows hug, ISO fields),
`pre-scene-*` (as committed, without F3's half: the content is centred in the old 520 / 660-pt windows),
`sheet-date-calculator-*` (2026-09-30 → 2027-03-01 inclusive, +1,000 days) and `sheet-unit-converter-*` (Pressure,
10 rows, 14.7 psi). Snapshot logs show no AppKit/SwiftUI runtime warning.

## Gate

`swift build -j 3 -Xswiftc -warnings-as-errors && swift test -j 3 -Xswiftc -warnings-as-errors` green;
`Scripts/check-ownership.sh` green for every code path — it flags only this file, whose path the F1 script does not map
yet (REQ-W-DRIVE-03).

## Open requests

REQ-W-DRIVE-01 (toolbar sync indicator slot, F3), REQ-W-DRIVE-02 (tool window default sizes, F3),
REQ-W-DRIVE-03 (`Docs/Progress/*.md` in check-ownership, F1), REQ-W-DRIVE-04 (tool windows hug content: Unit
converter `.windowResizability(.contentSize)`, Date calculator without the fixed 540×520 frame, F3).
