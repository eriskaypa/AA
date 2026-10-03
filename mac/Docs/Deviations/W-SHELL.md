# W-SHELL — deviations, P2 fixes and not-applicable IDs (ARCHITECTURE.md §12.2)

## P2 fixes and sanctioned deviations

| ID | Spec ref | Change (one line) |
|---|---|---|
| W-2 / Q-7 | 03 SHELL-066, D29, DECISIONS 03 Q-7 | The "Shared save file" info box says the shared file is autosaved "every minute" (the real cadence), not "every 10 minutes". |
| D-6 / Q-4 | 01 DATA-080, 03 SHELL-101, DECISIONS 01 Q-4 | Changing an existing app password requires the current one (the master password is accepted); an empty new password still does nothing. |
| Q-5 | 01 DATA-034 / D-17, 03 SHELL-063, DECISIONS 01 Q-5 | Import from File asks **Copy into AA Folder** (default) or **Use in Place** (Windows behaviour) after the review gate; the default data file itself is adopted without asking. |
| DATA-179 | 01 DATA-179 | Use in Place takes the per-user external-file lock before the file becomes active; another holder cancels the import with "That file is already open in another copy of AA." |
| §6.9 | 03 SHELL-066, §6.9 MAC-ADAPT | Set Shared Save File first asks **Join an Existing Shared Save File…** (open panel → D28 with "Use Its Contents" / "Overwrite It" / "Cancel") or **Create a New Shared Save File…** (save panel; confirming a replace = D28 "Overwrite It"). All three Windows outcomes stay reachable. |
| P2 | 03 SHELL-066, 01 DATA-021 | Set Shared Save File is refused in safe mode and in a read-only instance (D4 text): pushing from there would overwrite the shared bundle with an empty or stale database. |
| P2 | 03 SHELL-065, 01 DATA-021 | The encryption toggle is also refused in a read-only instance (D32 text), where nothing can be written. |
| W-9 | 03 SHELL-061/070/071, W-9 | Save a Copy As, Export / Import Data Folder and Import from File flush every live editor first (Windows flushed four pages or none). Reload from Disk keeps the Windows rule (no flush). |
| DATA-040 | 01 DATA-040 | An export destination inside AppFolder is refused before anything is saved ("Choose a destination outside the AA data folder." under "Export failed"). |
| Q-7 / Q-8 | 02 REPO-113, 03 SHELL-132, W-8, DECISIONS 02 Q-7 | The digest also runs at the local day change (`NSCalendarDayChanged`) and after a wake; the date this Mac last showed the digest is kept per data file in UserDefaults (`aa.shellx.digestDates`) and wins over a pulled `LastDigestDate`. `Ui.LastDigestDate` is still written and marked dirty exactly as on Windows. |
| Q-13 | 03 SHELL-130/131, §6.8, DECISIONS 02 Q-13 | Tray icon and balloon → MenuBarExtra (headline, per-bucket counts, crew line, Show Due Dates…, Show AA, Settings…, Quit AA), UserNotifications (`aa.reminder`, banner while frontmost, click → due-dates panel) and a Dock badge with the overdue count. Unbundled runs and `--smoke-test` post the text to the status line instead (`AA — due soon: …`). |
| Q-16 | 03 SHELL-196, BD Q-16 | When `EncryptLocalData` is on, the local data file is plaintext and this Mac has no local-data key, AA asks **Encrypt** / **Keep Plaintext** (writes paused while asking); Keep Plaintext turns the setting off. |
| SHELL-190 | 03 SHELL-190, REQ-F3-02 | The "Move AA to Applications" sheet is shown once per launch when `ReminderCenter` starts (after the main window and the D1/D2 alerts), never in smoke runs. |
| PC → Mac | 03 Appendix A.3, §6.9 | D31 "on this Mac only"; D33 = the 01 §6.5 Mac wording verbatim ("a key stored in your macOS Keychain", "Only THIS Mac's local file", "between computers"; 01 owns the DATA-070 strings, DATA-202 A14); D29 "Point every computer at this same file." |
| D12 | 03 SHELL-069, 01 DATA-012 | NSWorkspace reports no error text, so Open Data Folder's failure box says "Finder couldn't open the data folder:\n\n{path}" under "Open failed". |
| BD.3.7 | 03 BD.3.7, SHELL-185 | A Finder document that vanished before it was drained shows "Import failed" with the .NET wording "Could not find file '{path}'." |
| §6.10 | 01 §6.10 (File ▸ Shared Save ▸ Check Now) | Check Shared Save Now posts "Checked the shared save file (HH:mm:ss)." when the coordinator found nothing to reload and posted nothing itself. |
| SHELL-115 | 03 SHELL-115, D26, §6.4, BD.3.11 | About AA is a small window (icon, "AA", tagline, `Version x (n)`, build date and commit, the exact credits line, data folder with Show), not an information box; the credits text is unchanged. |
| SHELL-523 (layout) | 03 SHELL-523, ARCHITECTURE.md §8 | The shortcuts window is a native `Table` (resizable Command / Mac / Windows / Menu columns, one section per menu, alternating rows) so the column headers always line up with the cells. |
| Q-13 (menu) | 03 §6.8, 02 REPO-112 | The menu-bar menu shows the Windows headline split into one line per non-zero part with its exact wording (`{n} overdue`, `{n} due today`, `{n} due this week`, `{n} crew contract(s) expiring`), or `Nothing due.`; the joined headline is not repeated above them. |
| REQ-W-SHELL-02 | DECISIONS 03 Q-4 | Main phase: a stored `aa.menuBarExtra = false` that the user did not choose is turned back on (local workaround for the F3 binding, see Requests). |
| SHELL-523 | 03 SHELL-523 | The Windows column of the shortcuts window drops the registry's spec cross-references and WPF access-key underscores (`E_xit` → `Exit`); a reference-only cell shows "—". |
| §6.4 | 03 §6.4 | Settings: General (identity with Use Mac Name, appearance System/Light/Dark, shortcut bar, menu-bar item, notification settings link, data folder, version), Security (password status, Set/Change Password…, Lock Now, encryption toggle, on-disk state), Sync (shared save file with status, Change…/Check Now/Stop Using…, text-only exports, W-DRIVE's section), File Links (W-PERSIST), AI (W-SIRE). Data-bound controls are disabled until the user has signed in. Committing a blank identity resets it to this Mac's name (BUILD-145 B1). |
| BD.3.12 | 03 BD.3.12 | The smoke harness treats a window as shown when it is ordered in (`isVisible`); `occlusionState` stays "occluded" while the display sleeps or another Space is in front, which made unattended runs time out. The expected status path is standardised like DataStore's (`/private/tmp/…` → `/tmp/…`). |
| §9.4 | ARCHITECTURE.md §9.4, 03 BD.4.1 | Info.plist also exports `com.eriskay.aa.job-ref` and `com.eriskay.aa.item-ref` (all in-app drag types; BD.4.1 listed only `task-ref`). |
| BD.3.9 | 03 BD.3.9 | build-app.sh builds only the `AA` product per slice with `-j $AA_JOBS` (default 3, shared build Mac) and copies each slice aside, because every `--triple` writes into the same `.build/out/Products/Release`. |

## IDs satisfied by their Mac counterpart (Windows-baseline rows of 03 §N)

| ID | Note |
|---|---|
| SHELL-170 | Windows single-file publish → SHELL-180 (one self-contained `AA.app`, no runtime). |
| SHELL-171 | "Runs from any folder; data elsewhere" → SHELL-180 (read-only bundle) + SHELL-190 (translocation) + F3's data-folder resolution. |
| SHELL-172 | Embedded resources → SHELL-184 (flat copies + SwiftPM bundles in `Contents/Resources`, checksums verified). |
| SHELL-173 | Dependency trimming → not applicable: `Package.swift` has no dependencies; nothing to trim. |
| SHELL-174 | Framework-dependent variant → not applicable (the Mac build links only OS libraries). |
| SHELL-176 | Build gate → SHELL-200/201 (warnings as errors, no `warning:` lines, tests) inside build-app.sh steps 3–4. |
| SHELL-177 | Smoke test → SHELL-204 (manual checklist, Install.txt/README) and SHELL-205 (`--smoke-test`, implemented and run). |

## Not done in this worktree (needs another owner, Windows data or other hardware)

| ID | Why |
|---|---|
| SHELL-206 | Cross-version data smoke needs a folder written by the Windows build (and the Windows app for Mac → Windows); Stage V. |
| SHELL-207 | Clean-machine / Intel run needs a second Mac or user account; the x86_64 slice is executed under Rosetta by build-app.sh only when Rosetta is installed. |
| SHELL-204 | The manual checklist (BD.7.7) is documented; steps that need a person (Finder double-click, camera prompt, Gatekeeper) were not performed by the agent. |
