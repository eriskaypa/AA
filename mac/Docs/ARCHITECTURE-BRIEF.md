# AA for macOS — architecture brief (binding decisions)

This is the lead's brief for the Swift port. `ARCHITECTURE.md` (written by the architect) expands it into
concrete contracts; where the two disagree, this brief wins unless the lead amends it.

## Rule zero — the original source is read-only
- **All Mac code, docs, tests, scripts and fixtures live under `mac/`** (this folder). Nothing outside `mac/` may
  be created, modified, moved, reformatted or deleted — not `../AA/**`, not `../Tests/**`, not `PROGRESS.md`,
  `QR_SYNC_PROTOCOL.md`, `AA.sln`, `.gitignore`, `.gitattributes`. The C# sources are **read-only reference**.
- Enforced: the original files are `chmod a-w` in the main checkout, a git `pre-commit` hook rejects any commit
  on a non-`main` branch that touches a path outside `mac/`, and `Docs/original-source-checksums.sha256`
  records SHA-256 of every original file for a final integrity check.
- Resources the Mac app needs from the original tree (SIRE question bank, splash, icon) are **copied** into
  `mac/Sources/...`, never referenced by moving the originals.
- The repo-root `.gitignore` ignores any file named `data.json` or `settings.json`: name Mac fixtures
  differently (e.g. `sample-data.json`).

## Goal
A native macOS port of the WPF/.NET 10 app in `../AA`, in **Swift**, retaining every function, feature and
intricacy catalogued in `Docs/Spec/*.md`, while feeling like a first-class Mac app (sidebar/inspector layouts,
toolbars, sheets, popovers, SF Symbols, materials/Liquid Glass, smooth animation, ⌘-shortcuts, Quick Look,
Services/Share, native text system, Touch-ID-friendly where it adds grace).

## Toolchain & packaging
- Swift 6.4 toolchain / Xcode 27 / macOS 27 host. **Deployment target macOS 26** (`.macOS(.v26)`),
  `swift-tools-version: 6.2`. Swift **language mode 5** for all targets (`.swiftLanguageMode(.v5)`) to avoid
  strict-concurrency churn; UI and stores are `@MainActor`.
- **Swift Package Manager**, rooted at `mac/Package.swift` (opens directly in Xcode). **No third-party
  dependencies** — everything is built on Apple frameworks (Foundation, AppKit, SwiftUI, Observation,
  Compression, CryptoKit, CommonCrypto, Security/Keychain, PDFKit/CoreGraphics, CoreText, AVFoundation, Vision,
  CoreImage, QuickLookThumbnailing/QuickLookUI, UniformTypeIdentifiers, UserNotifications, Network,
  AuthenticationServices, LocalAuthentication).
- Targets:
  - `AACore` (library): models, JSON, persistence, crypto, zip/xlsx, rich-text XAML conversion, domain services,
    importers/exporters, Flash Sync codec, SIRE logic, Google Drive client. May import AppKit (NSAttributedString,
    NSFont, NSColor, PDF drawing) but **never SwiftUI**.
  - `AA` (executable): the SwiftUI/AppKit app.
  - `AACoreTests` (Swift Testing or XCTest): unit tests incl. Windows-compat fixtures and Flash Sync vectors.
- `mac/Scripts/build-app.sh` builds release and assembles `mac/dist/AA.app` (Info.plist with bundle id
  `com.eriskay.aa`, NSCameraUsageDescription for Flash Sync, icon `.icns` generated from `../AA/AA.ico` /
  `../AA/Assets/Splash.png` via `sips`/`iconutil`, resources copied, ad-hoc `codesign`).
- Resources (SIRE question bank, splash image, app icon) are loaded through one helper that looks in
  `Bundle.main` first, then the SwiftPM resource bundle, so both `swift run` and the assembled `.app` work.

## Data compatibility (non-negotiable)
- Data folder: `~/Library/Application Support/AA/` (`data.json`, `settings.json`, `files/`, `crash.log`,
  `google-token/`, …), overridable with the `AA_DATA_DIR` env var exactly like Windows.
- `data.json` / `settings.json` / bundle `source.json` are read and written in the **exact System.Text.Json
  shape** the Windows build uses: PascalCase keys, enums as **integers**, nulls omitted on write
  (`WhenWritingNull`), compact output, `[JsonIgnore]` members never written, GUIDs as lowercase
  `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, `DateTime` as ISO-8601 with the same Kind semantics (Local →
  `+hh:mm` offset, Utc → `Z`, Unspecified → no offset; fractional seconds up to 7 digits), tolerant reading of
  every variant, missing keys → C# defaults, legacy migrations (e.g. `BucketId` → `BucketIds`), and
  **unknown members preserved** (the C# preserves them on `AppData`, `UiState` and settings; the Mac build
  preserves them on *every* object so it is at least as forward-compatible). Output uses the default
  System.Text.Json escaping (non-ASCII and HTML-sensitive characters as `\uXXXX`) so files diff cleanly against
  Windows-written ones.
- Implement this with a small ordered JSON layer in `AACore` (`JSONValue` tree + parser + writer that preserves
  key order and writes numbers the way .NET does), and explicit `init(json:)` / `json` mappings on each model —
  **not** synthesized `Codable` (which can't do tolerant defaults + extra-member preservation + .NET formats).
- Rich text stays stored as **WPF XAML** (`Container.RichTextXaml`, the `TextRange.Save(DataFormats.Xaml)`
  `<Section …>` vocabulary). The Mac editor works on `NSAttributedString`; a lossless-as-possible
  XAML ⇄ NSAttributedString converter lives in `AACore/RichText`. Anything the Mac can't represent natively
  must round-trip untouched where feasible.
- Encrypted blobs that travel with the data (`enc:` container bodies, per-item lock hashes, the app password
  hash) must be **byte-compatible** with the C# algorithms. Windows-only DPAPI "encrypt local data at rest" maps
  to an AES-GCM key held in the macOS Keychain (machine-local, same opt-in semantics: bundles/exports stay
  portable plaintext).
- `.aaz` / ZIP bundles: same entry layout and `source.json` semantics (incl. `DataOnly`), written with an
  in-house ZIP reader/writer (Compression framework raw DEFLATE + CRC-32). Flash Sync: same wire protocol v1.
- In-place linked files hold Windows paths (`Z:\…`, `\\server\share\…`); the Mac build keeps them verbatim,
  opens them when reachable, maps UNC paths to `smb://` URLs as a convenience, and never rewrites them.

## App structure
- `@Observable` `@MainActor` model classes (reference semantics like the C# `NotifyBase` objects, so the same
  task instance can be shown in many views). `AppStore` (the repository) owns `AppData`, dirty tracking,
  debounced/off-main autosave, shared-save sync, trash/undo, activity log.
- Main window: a tabbed shell reproducing the WPF tab set, order and customization (draggable order, custom
  colours, persisted selection) — rendered Mac-style (toolbar segmented/tab strip + `NavigationSplitView`
  sidebars + inspector panes). Extra windows are SwiftUI `Window`/`WindowGroup(for:)` scenes (item windows,
  floating due-dates panel at `.floating` level, quick-work, quick switcher, search, crew table, flash sync,
  tools…). Menus via `.commands`, mapping every Ctrl-shortcut to its ⌘ equivalent.
- Debug snapshot hook for visual verification without screen-recording permission:
  `AA --data-dir <dir> --snapshot <TabName|window-id> --out <file.png> [--appearance dark|light]` opens the
  window, selects the tab, waits for layout, renders the window's content view to PNG via
  `bitmapImageRepForCachingDisplay`, and exits.

## Visual language
- Primary font: Consolas when installed, otherwise SF Mono (`NSFont.monospacedSystemFont`), exposed as design
  tokens so the whole UI keeps the brief's monospaced identity. UI chrome (menus, toolbars) stays system.
- Colours: translate the WPF palette (light + dark) into asset-free `Color` tokens that follow the system
  appearance and the app's own dark-mode toggle; accent derived from the WPF primary blue; per-kind colours for
  Equipment / Task / Procedure / Vessel used consistently (sidebar badges, map nodes, calendar chips).
- Use SF Symbols in place of emoji glyphs where the WPF used emoji as icons, keeping emoji that are user data
  (e.g. Quick Card icons).
