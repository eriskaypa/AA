# AA for macOS

A native Swift / SwiftUI port of **AA**, the Windows WPF maritime-operations app (equipment and areas, tasks,
procedures with containers, files and relationships, vessels, calendar / planner / board, crew, SIRE 2.0, Flash Sync
with the iPhone app, Google Drive backups). It reads and writes the same `data.json`, `settings.json` and `.zip` /
`.aaz` bundles as the Windows build, so one data folder can move between the two.

Everything in this folder (`mac/`) is the Mac port. The C# sources in `../AA` are read-only reference.

## Requirements

| What | Version |
|---|---|
| macOS to **run** AA | 26 or later, Apple silicon or Intel |
| macOS to **build** | 26 or later with **Xcode 27** selected (`xcode-select -p` must point into `Xcode.app`) |
| Swift | 6.4 toolchain (package `swift-tools-version: 6.2`, language mode 5) |
| Third-party code | none — Apple frameworks only |

## Build, test and run during development

```sh
cd mac
swift build -Xswiftc -warnings-as-errors          # debug build of AACore, AA and the interop tool
swift test  -Xswiftc -warnings-as-errors          # AACoreTests (Swift Testing)
swift run AA --data-dir "$(mktemp -d)/aa"         # run unbundled against a scratch data folder
```

On a shared build Mac add `-j 3` to `swift build` / `swift test`. The full gate before every commit is:

```sh
swift build -Xswiftc -warnings-as-errors && swift test -Xswiftc -warnings-as-errors && Scripts/check-ownership.sh
```

`swift run` starts AA without a bundle: it still gets a Dock icon and a menu bar, but notifications fall back to
the status line and the camera (Flash Sync ▸ Receive) needs the packaged app. Sign in with the standard AA
credentials (the same as on Windows).

### Command-line options

| Option | Meaning |
|---|---|
| `--data-dir <path>` / `--data-dir=<path>` | data folder for this launch (wins over `AA_DATA_DIR`) |
| `--version` | prints `AA 1.0.0 (412) arm64` and exits; no window, no data access |
| `--smoke-test` | automated launch smoke (needs `--data-dir` naming an empty or new folder); see below |
| `--snapshot <target> --out <file.png> [--appearance dark\|light] [--select <uuid>] [--sheet <id>] [--size WxH]` | DEBUG builds only: renders one window to PNG for visual checks |

The data folder is, in order: `--data-dir`, the `AA_DATA_DIR` environment variable, else
`~/Library/Application Support/AA`. A missing volume or an unwritable folder is reported before the splash, with
Try Again / Quit.

## Build the app bundle

```sh
mac/Scripts/build-app.sh            # from anywhere; --help lists every option
```

The script (03 BD.3.9) checks the toolchain, verifies the copied resources against
`Docs/original-source-checksums.sha256`, builds **release** binaries for **arm64 and x86_64** with warnings as
errors (and fails on any `warning:` line), runs the tests, assembles a universal `AA.app`, writes the dSYM, stamps
`Info.plist` from `Packaging/Info.plist` (`VERSION` file, build number = commit count, build date, commit hash),
copies the resources, generates `AppIcon.icns` from `Resources/AppIcon-1024.png`, signs **ad-hoc with the hardened
runtime** and exactly one entitlement (camera; **not sandboxed**), verifies the bundle (BD.7.4: plist values and
forbidden keys, slices and `minos 26.0`, system libraries only, signature and entitlements, resource checksums,
`--version`, size ≤ 60 MB) and only then publishes:

```
mac/dist/AA.app
mac/dist/AA.app.dSYM                      debug symbols, not shipped
mac/dist/AA-<version>-<build>-macOS.zip   AA/AA.app + AA/Install.txt (+ the portable launcher)
mac/dist/SHA256SUMS
```

Useful switches: `SKIP_TESTS=1`, `ARCHS=arm64`, `PACKAGE=dmg`, `PORTABLE_LAUNCHER=1`,
`SIGN_IDENTITY="AA Local Signing"` (a self-signed identity keeps camera / Keychain grants across rebuilds) or a
Developer ID identity with `NOTARY_PROFILE=<profile>` for notarisation. `dist/` is git-ignored.

Automated launch smoke of the built app (real splash, login, main window, autosave and quit; JSON lines on stdout,
exit 0 on success, 3 when the folder already holds data):

```sh
mac/dist/AA.app/Contents/MacOS/AA --data-dir "$(mktemp -d)/aa" --smoke-test
```

## Install

1. Unzip `AA-<version>-<build>-macOS.zip` and **move `AA.app` to Applications before opening it** (opening it from
   Downloads makes macOS run it from a temporary read-only copy; AA then says "Move AA to Applications").
2. The build is ad-hoc signed, not notarised. The first time, macOS refuses to open it: choose **Done**, then
   **System Settings ▸ Privacy & Security ▸ Open Anyway**, authenticate, and open AA again. Or, in Terminal:
   `xattr -dr com.apple.quarantine /Applications/AA.app`.
3. Update by replacing `AA.app`; the data lives outside the bundle and is not touched.

`Packaging/Install.txt` (shipped in the zip) has the full first-launch, data-folder, portable-use and camera notes.

### Portable use

Put `AA (portable).command` (from `Packaging/`, or build with `PORTABLE_LAUNCHER=1`) next to `AA.app` on a USB
stick; double-clicking it opens AA with the `AA Data` folder beside it. Only one copy of AA (Mac or Windows) should
use a data folder at a time.

## Where things are

| Path | What |
|---|---|
| `Sources/AACore` | models, JSON (System.Text.Json-compatible), persistence, crypto, ZIP/XLSX, rich text, services |
| `Sources/AA` | the SwiftUI / AppKit app (scenes, shell, menus, windows, every section) |
| `Tests/AACoreTests` | unit tests and fixtures |
| `Packaging/` | `Info.plist` template, `AA.entitlements` (shipped), `AA-sandbox.entitlements` (reference only), `Install.txt`, `AA (portable).command`, `make-app-icon.swift` |
| `Resources/` | `AA.ico` (byte copy of the Windows icon), `AppIcon-1024.png` (vector re-draw of the icon art) |
| `Scripts/` | `build-app.sh`, `check-ownership.sh`, `check-placeholders.sh` |
| `Docs/` | brief, decisions, architecture, ownership, specs, deviations, requests, progress |
| `VERSION` | marketing version (`CFBundleShortVersionString`) |

To redraw the app icon after changing its art: `swift Packaging/make-app-icon.swift Resources/AppIcon-1024.png`.

## Mac-only state

Besides the data folder, AA keeps per-Mac preferences in `~/Library/Preferences/com.eriskay.aa.plist` (appearance,
menu-bar item, Windows-path mappings, digest dates, remembered choices) and Keychain items for the local-data
encryption key, the Google Drive token key and the Gemini key. None of these travel with a data folder.
