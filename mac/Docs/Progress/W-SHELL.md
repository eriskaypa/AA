# W-SHELL — progress record (DECISIONS "Foundation requests", REQ-F1-01 ruling)

Card: OWNERSHIP §3 "W-SHELL" — File / Tools menu flows, Settings / About / Keyboard Shortcuts windows, reminders,
notifications, Dock badge and MenuBarExtra, `--smoke-test`, packaging, build script, README, VERSION.

## Counts (OWNERSHIP §4)

| | IDs |
|---|---|
| Assigned | **61** (DATA 12, REPO 2, SHELL 46, CREW 1) + algorithm ids BUILD-A25, A27 (B1 half) |
| Done | **58** + BUILD-A25, A27 |
| Partly done | **1** — SHELL-204 |
| Not done here | **2** — SHELL-206, SHELL-207 |

Done:
* DATA-012, 032, 033, 034, 040, 042, 043, 048, 050, 051, 070, 080 — `ShellFlows` + `ShellXDataFlows`
* REPO-112, REPO-113, CREW-092 — `ReminderCenter`, `ShellXReminderEngine`, `NotificationCenterBridge`, MenuBarExtra
* SHELL-061…063, 065…072, 101, 102 — File / Tools flows; SHELL-115 About; SHELL-523 Keyboard Shortcuts
* SHELL-130…133 — MenuBarExtra, 30-min reminder, digest (+ day change, wake, per-device date), crew count
* SHELL-170…174, 176, 177 — Windows-baseline rows satisfied by their Mac counterparts (see Deviations)
* SHELL-180…191, 195, 196, 202, 203 — bundle, universal slices, Info.plist, camera text + entitlement, icon and
  resources, `.aaz` documents, private UTIs, not sandboxed + hardened runtime, ad-hoc / named signing, Gatekeeper
  procedure (Install.txt, `--help`), translocation sheet, zip / dmg / SHA256SUMS, portable recipes (launcher,
  `open --env`, `AA_BAKE_DATA_DIR`), Q-16 encryption guard; `Scripts/build-app.sh` with the BD.7.4 checks
* SHELL-205 — `--smoke-test` (BD.3.12 / BD.4.7), run green unbundled and from `dist/AA.app`
* BUILD-A25, A27 (B1) — blank identity → this Mac's name; status shows the stored value

Partly done / not done (reasons in `Docs/Deviations/W-SHELL.md`):
* SHELL-204 — manual launch checklist documented (README, Install.txt); the automated equivalent passes; the
  person-only steps (Finder double-click, camera prompt, Gatekeeper dialog) were not performed by the agent.
* SHELL-206 — cross-version data smoke needs a Windows-written data folder and the Windows app (Stage V).
* SHELL-207 — clean-machine and Intel runs need another Mac / account; Rosetta is not installed on the build Mac,
  so build-app.sh reports "x86_64 slice not executed".

## Gate and checks (2026-10-02)

* `swift build -j 3 -Xswiftc -warnings-as-errors` — clean; `swift test -j 3 -Xswiftc -warnings-as-errors` — 447 tests
  in 79 suites pass (W-SHELL: 48 tests in 13 suites under `Tests/AACoreTests/ShellSupport/`, 4 of them gated on
  W-PERSIST and skipped here).
* `Scripts/check-placeholders.sh W-SHELL` — empty; `ShellSupportContractStatus` = true.
* `Scripts/check-ownership.sh` — OK for every W-SHELL path except this file, which the checker does not know yet
  (REQ-W-SHELL-03).
* `Scripts/build-app.sh` — `mac/dist/AA.app` (14.9 MB, x86_64 + arm64, minos 26.0, ad-hoc, hardened runtime, one
  camera entitlement, not sandboxed), every BD.7.4 check passes on this host; `AA-1.0.0-<build>-macOS.zip` +
  `SHA256SUMS`.
* `dist/AA.app/Contents/MacOS/AA --data-dir <new> --smoke-test` — `start, splash (2.455 s), login, login-rejected,
  login-accepted, main, autosaved, quit`, exit 0; second run on the same folder exits 3; `--version` →
  `AA 1.0.0 (64) arm64`.
* Snapshots (debug hook, light and dark): Settings ▸ General / Security / Sync / File Links / AI, About AA,
  AA Keyboard Shortcuts, the App identity prompt (scratchpad `snapshots/W-SHELL/`).

## Post-merge (Stage V)

* `ShellXPersistIntegrationTests` (export → import ZIP and text-only through the real `BundleService`, export into
  the data folder refused, shared save create / join / stop through the real `SharedSaveCoordinator`).
* Work-order notifications from the digest (`WorkOrderNotifications.runDigest` is called on every reminder pass).
* Settings ▸ File Links / AI / Sync show W-PERSIST's, W-SIRE's and W-DRIVE's sections once they land.
* REQ-W-SHELL-01 (adoptSharedFile semantics), REQ-W-SHELL-02 (MenuBarExtra binding writes "off"), REQ-W-SHELL-03
  (`Docs/Progress/` in the ownership checker).
