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
* SHELL-204 — manual launch checklist documented (README, Install.txt); the automated equivalent passes, also when
  launched through LaunchServices (`open`), and the saved window frame is in `Ui` after quit; the person-only steps
  (looking at the Finder-launched windows, the relaunch restoring the frame on screen, camera prompt, Gatekeeper
  dialog) were not performed by the agent.
* SHELL-206 (a) — no Windows-written data folder exists on this Mac (ARA1 is not mounted; none in the repo).
* SHELL-206 — cross-version data smoke needs a Windows-written data folder and the Windows app (Stage V).
* SHELL-207 — clean-machine and Intel runs need another Mac / account; Rosetta is not installed on the build Mac,
  so build-app.sh reports "x86_64 slice not executed".

## Gate and checks (audit, 2026-10-02)

* Clean build (`rm -rf .build`): `swift build -j 3 -Xswiftc -warnings-as-errors` — clean; `swift test -j 3
  -Xswiftc -warnings-as-errors` — 449 tests in 80 suites pass (W-SHELL: 50 tests in 14 suites under
  `Tests/AACoreTests/ShellSupport/`, 4 of them gated on W-PERSIST and skipped here).
* `Scripts/check-placeholders.sh W-SHELL` — empty; `ShellSupportContractStatus` = true.
* `Scripts/check-ownership.sh` — fails on exactly one path, this file (`Docs/Progress/W-SHELL.md`), which the F1
  checker does not map although the lead's REQ-F1-01 ruling requires it (REQ-W-SHELL-03). Every W-SHELL source,
  test, packaging and doc path passes.
* `Scripts/build-app.sh` (full run incl. tests) — exit 0: `mac/dist/AA.app` 14.9 MB, x86_64 + arm64, minos 26.0,
  ad-hoc, hardened runtime, exactly one entitlement (camera), not sandboxed; every BD.7.4 check passes on this
  host except the x86_64 `--version`, reported "x86_64 slice not executed (Rosetta not installed)";
  `AA-1.0.0-67-macOS.zip` + `SHA256SUMS`.
* `dist/AA.app/Contents/MacOS/AA --data-dir <new> --smoke-test` — `start, splash, login (splashSeconds 2.466),
  login-rejected, login-accepted, main ("AA — 8800", "Loaded — …/data.json"), autosaved (566 bytes, digest
  2026-10-02), quit`, exit 0; folder afterwards = `data.json` + `files/` only (BD.4.8); second run on the same
  folder exits 3. The same smoke launched through LaunchServices (`open -W -n -a dist/AA.app --args …`, the path a
  Finder double-click takes) also passes; after quit `Ui` holds `WindowLeft/Top/Width/Height` + `WindowState
  "Normal"` (the frame SHELL-204 step 5 restores).
* Snapshots (debug hook, light and dark, `scratchpad/snapshots/W-SHELL/`): Settings ▸ General / Security / Sync /
  File Links / AI, About AA, AA Keyboard Shortcuts, the App identity prompt. Audit fixes: identity field text was
  right-aligned (now leading); the shortcuts window's hand-made header drifted up to 11 pt from its columns (now a
  native `Table`). The MenuBarExtra menu cannot be rendered by the hook (it is an `NSMenu`).

## Verification fixes (FIX-W-SHELL, 2026-10-03)

| Finding | Status | Change |
|---|---|---|
| V-01 Encrypt confirm / tooltip wording (01 §6.5) | **fixed** (confirm) + **cross-owner** (tooltip) | `ShellXText.encryptConfirmMessage` = the 01 §6.5 text verbatim ("a key stored in your macOS Keychain", "Only THIS Mac's local file"); `ShellXCatalogTests` pins the whole string. The SHELL-551 help lives in F3's `ShortcutRegistry` → REQ to F3 (exact 01 §6.5 tooltip). |
| V-PACKAGE AppleDouble `._*` entries in the zip | **fixed** | Step 13: `ditto -c -k --norsrc --noextattr --noqtn --keepParent` (still ditto, SHELL-191); the script fails if `unzip -Z1` lists any `._` entry and if `codesign --verify --deep --strict` fails after a plain Info-ZIP `unzip`. Release run: 0 `._` entries, seal valid after `unzip`. |
| V-PACKAGE "-dirty" from a file outside mac/ | **fixed** | Step 7: `git status --porcelain -- .` from mac/ (only mac/ paths), Finder metadata (`.DS_Store`, `._*`) ignored; tracked and untracked mac/ changes still stamp `-dirty`. |
| V-PACKAGE grey plate around the icon on macOS 26 | **fixed** | `Resources/AppIcon.icon` (Icon Composer): fill #1B1B1B, group "letter" (lime "A", Liquid Glass, neutral shadow) above group "dial" (#313131 / #626262 / #4F4F4F rings); layers made by `swift Packaging/make-app-icon.swift --layers Resources/AppIcon.icon` (the round-art mode still writes a byte-identical `AppIcon-1024.png`). Step 8 compiles it with actool into a temp folder and copies only `Assets.car` (actool's own flattened `.icns` would replace the round SHELL-184 art), sets `CFBundleIconName`; step 11 asserts `CFBundleIconFile`, `CFBundleIconName` and an `AppIcon` stack in `Assets.car`. `NSWorkspace.icon(forFile:)` of `dist/AA.app` renders the full-bleed squircle in light and dark (`scratchpad/snapshots/fix1-W-SHELL/app-icon-{light,dark}.png`). |
| V-PACKAGE AppKit warnings at launch | **cross-owner** (F3) | Reproduced under lldb: (1) `makeKeyWindow` on the `splash` window — SwiftUI `openWindow` sends `makeKeyAndOrderFront` to the `.plain` (borderless) splash scene; (2) the layout recursion is `LaunchCoordinator.loginWindowRegistered` calling `styleMask.remove(.resizable)` from `ShellWindowCaptureView.viewDidMoveToWindow`, inside `NSHostingView.layout`. Fix prototyped (splash as a non-activating `NSPanel` shown with `orderFrontRegardless`, style-mask change deferred one run-loop turn): both warnings gone, splash/login snapshots pixel-identical, `--smoke-test` green; reverted here and handed to F3 as a request (all files are F3's). |

Gate: `swift build -j 3 -Xswiftc -warnings-as-errors`, `swift test -j 3 -Xswiftc -warnings-as-errors` (1,586 tests),
`Scripts/check-ownership.sh` — green. `SKIP_TESTS=1 Scripts/build-app.sh` — exit 0 (38 MB, x86_64 + arm64, Assets.car,
zip without `._` entries).

## Post-merge (Stage V)

* `ShellXPersistIntegrationTests` (export → import ZIP and text-only through the real `BundleService`, export into
  the data folder refused, shared save create / join / stop through the real `SharedSaveCoordinator`).
* Work-order notifications from the digest (`WorkOrderNotifications.runDigest` is called on every reminder pass).
* Settings ▸ File Links / AI / Sync show W-PERSIST's, W-SIRE's and W-DRIVE's sections once they land.
* REQ-W-SHELL-01 (adoptSharedFile semantics), REQ-W-SHELL-02 (MenuBarExtra binding writes "off"; local guard in
  `ReminderCenter` since the audit), REQ-W-SHELL-03 (`Docs/Progress/` in the ownership checker).
