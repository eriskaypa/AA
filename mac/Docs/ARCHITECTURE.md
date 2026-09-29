# AA for macOS — ARCHITECTURE (binding technical design)

Status: binding for Stage F1, F2, F3, every wave agent W-xx and every verifier.
Order of authority: `ARCHITECTURE-BRIEF.md` (Rule zero) → `DECISIONS.md` → **this file** → `Spec/*.md`
(with `Spec/03 §6.5.1` the single shortcut & menu registry). `OWNERSHIP.md` (same folder) assigns every path and
every feature ID to exactly one owner; this file fixes every contract those owners implement or consume.

Conventions used below:
* "Owner" ids: `F1`, `F2`, `F3` (foundation stages) and `W-SHELL`, `W-PERSIST`, `W-GOLD`, `W-RICH`, `W-CONT`,
  `W-FILES`, `W-HIER`, `W-BUILD`, `W-PLAN`, `W-QUICK`, `W-CREW`, `W-VESSEL`, `W-PDF`, `W-SIRE`, `W-FLASH`,
  `W-DRIVE` (16 wave agents). See OWNERSHIP.md. (Revision 2: `W-CAL`+`W-BOARD` became `W-PLAN` — all of spec 07;
  `W-WIN`+`W-QWORK` became `W-QUICK` — all of spec 08; `W-SHELL` and `W-GOLD` are new; see the Review log.)
* Swift snippets are **signatures**: names, parameter labels, types, `throws`/`async`, isolation and access level
  are binding. Bodies shown are illustrative unless marked "exact".
* `NN §S (ID)` cites a spec. Where this file and a spec disagree on a Swift *shape*, this file wins; where they
  disagree on *behaviour or data*, the spec (as amended by DECISIONS) wins.
* All public API is `public` inside `AACore` (the app target imports it); app-target types are `internal`.
* `throws(E)` (typed throws) in a signature fixes the error type the function may throw. Callers always use an
  untyped `catch` (never rely on exhaustiveness), so an implementer MAY declare plain `throws` for a *function*
  (never for a protocol requirement) if typed throws causes friction, provided it only throws `E`.

---------------------------------------------------------------------------------------------------------------------

## 1. Package, targets and directory tree

### 1.1 `mac/Package.swift` (exact; owned by F1; nobody else edits it)

```swift
// swift-tools-version: 6.2
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "AA",                                   // resource bundles are "AA_AACore.bundle" / "AA_AA.bundle" (03 BD.3.4)
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AA", targets: ["AA"]),
        .library(name: "AACore", targets: ["AACore"]),
    ],
    dependencies: [],                             // no third-party code, ever (brief; 03 SHELL-180)
    targets: [
        .target(
            name: "AACore",
            path: "Sources/AACore",
            resources: [.copy("Resources/sire2_question_bank.json")],
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "AA",
            dependencies: ["AACore"],
            path: "Sources/AA",
            resources: [
                .copy("Resources/Splash.png"),
                .copy("Resources/MenuBarIconTemplate.png"),
                .copy("Resources/MenuBarIconTemplate@2x.png"),
            ],
            swiftSettings: swift5
        ),
        .executableTarget(                        // 13 §6.1 / FLASH-120 conformance CLI (dev only, never shipped)
            name: "AAFlashSyncInterop",
            dependencies: ["AACore"],
            path: "Tools/FlashSyncInterop",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "AACoreTests",
            dependencies: ["AACore"],
            path: "Tests/AACoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: swift5
        ),
    ]
)
```

Rules:
* `.copy` (never `.process`) for every resource, so shipped bytes equal the originals (03 BD.7.3).
* No `unsafeFlags`, no `-warnings-as-errors` in the manifest — the gate passes it on the command line
  (`swift build -Xswiftc -warnings-as-errors`, 03 SHELL-200/201).
* The C# oracle tools under `mac/Tools/WinFixtures`, `mac/Tools/WinCapture`, `mac/Tools/XlsxGolden` are **not**
  SwiftPM targets and are never compiled by `swift build` (01 GF.0). `dotnet` is not installed on the build Mac:
  they are authored and kept compilable-by-inspection only.
* Frameworks are linked implicitly by `import` (AppKit, SwiftUI, CryptoKit, Security, Compression, PDFKit,
  CoreText, AVFoundation, Vision, QuickLookUI, QuickLookThumbnailing, UserNotifications, Network,
  UniformTypeIdentifiers, LocalAuthentication, os).
* **Every Swift file name is unique within its target** (SwiftPM rejects duplicates across sub-folders). Every
  file a wave agent adds starts with its **area prefix** (§12.2: `CalendarRowBuilder.swift`, never
  `RowBuilder.swift`). Test file names end in `Tests.swift` and are likewise prefixed and unique. Symbol
  namespacing (types, free functions, extension members) is mandatory too — §12.2.
* Swift language mode 5 everywhere. Concurrency is designed as if strict (see §2) but the compiler does not force
  it; **any concurrency warning still fails the gate** (warnings-as-errors), so write code that is warning-free
  in mode 5. Several Swift 6 diagnostics are *errors* even in mode 5 under `-warnings-as-errors` — §2.2 lists the
  binding idioms (isolated conformances, `nonisolated` value types, `isolated deinit`, `@Entry` defaults).
* **Only `.swift` files** live under `Sources/**`, `Tests/AACoreTests/<Area>/**` and `Tools/FlashSyncInterop/**`
  (tools-version 6.2 makes any undeclared non-Swift file in a target folder a hard build error, and only F1 may
  edit this manifest). Data tables are Swift literals. Test data goes only under `Tests/AACoreTests/Fixtures/<area>/`
  (covered by `.copy("Fixtures")`). A new runtime resource needs a `Docs/Requests/<id>.md` entry to F1 (§12.3).
  The only declared resources are the ones in the manifest above.

### 1.2 Directory tree (every path has exactly one owner — OWNERSHIP.md §2 is the authoritative table)

```
mac/
├── Package.swift                              F1
├── README.md                                  W-SHELL
├── VERSION                                    W-SHELL (read by build-app.sh, BD.3.11)
├── .gitignore                                 F1 (already exists; F1 may only append — incl. the GF.4.1 lines:
│                                                  `Tools/*/bin/`, `Tools/*/obj/`, `Tools/.dotnet/`, `Tools/*/.aa-build/`,
│                                                  `**/.partial/`, `Tests/AACoreTests/Fixtures/mac-out/check-report.*.json`)
├── Docs/
│   ├── ARCHITECTURE-BRIEF.md, DECISIONS.md    lead (read-only for agents)
│   ├── ARCHITECTURE.md, OWNERSHIP.md          architect (read-only for agents)
│   ├── Spec/                                  lead (read-only)
│   ├── Requests/<agent-id>.md                 each agent writes only its own file (§12)
│   └── Deviations/<agent-id>.md               each agent writes only its own file (P2 fixes, §12)
├── Packaging/                                 W-SHELL  Info.plist template, AA.entitlements, Install.txt,
│                                                  "AA (portable).command"; AA-sandbox.entitlements is a
│                                                  reference file only (BD.4.3) — never used by build-app.sh
│                                                  (DECISIONS 01 Q-7: not sandboxed)
├── Resources/                                 W-SHELL  AppIcon-1024.png (optional), AppIcon.icon (optional)
├── Scripts/
│   ├── build-app.sh                           W-SHELL
│   ├── fixtures.sh                            W-GOLD (01 GF.4.1)
│   ├── check-placeholders.sh                  F1  (lists PLACEHOLDER(...) markers per owner; exit 1 if any)
│   └── check-ownership.sh                     F1  (branch diff vs OWNERSHIP.md path table + the §12.2 symbol
│                                                  and basename collision checks)
├── Tools/
│   ├── FlashSyncInterop/                      W-FLASH (Swift executable target; main.swift)
│   ├── global.json                            W-GOLD (.NET SDK pin, DATA-313)
│   ├── WinFixtures/  WinCapture/  XlsxGolden/ W-GOLD (C# oracles, not built here; 01 GF, 10 X.7.6)
├── Sources/
│   ├── AACore/                                (library; never imports SwiftUI)
│   │   ├── Foundation/        F1   identifiers, clock, CivilDate, text/number/.NET helpers, OrderedMap,
│   │   │                           EventHub, AAResources locator, WpfColor, WindowsFileName, MacPreferences, Log,
│   │   │                           MacKeyStrings, ContractStatus registry (§11)
│   │   ├── JSON/              F1   JSONValue, JSONObject, JSONNumber, JSONParser, JSONWriter, NetDateTime, NetGuid,
│   │   │                           model reader/builder helpers
│   │   ├── Model/             F1   every persisted type (§4) + UiState + AppSettings + BundleSource
│   │   ├── Store/             F1   AppStore.swift, PersistenceWriter.swift
│   │   │                      F2   AppStore+Lookups.swift, AppStore+Relations.swift, AppStore+Log.swift,
│   │   │                           AppStore+Trash.swift, AppStore+Recurrence.swift, AppStore+Groups.swift,
│   │   │                           AppStore+Creation.swift
│   │   ├── Persistence/       F1   DataStore, SettingsStore, AtomicWrite, LocalEncryption, SchemaMigration,
│   │   │                           TrashPayload/ModelCloning, DataFileWriteGuard (protocol only)
│   │   ├── Crypto/            F1   PBKDF2, AESCBC, HMAC, ConstantTime, SecureRandom, PasswordService,
│   │   │                           ItemLockService, LegacyBodyCrypto, SecretStore (Keychain)
│   │   ├── Zip/               F1   ZipReader, ZipWriter (+ CRC32/RawDeflate live in Foundation/…, see §6.1)
│   │   ├── Xlsx/              F1   XLSX writer (09 §3.10, 10 §6.6, 11 §4.5 raw parts) + NetNumberText
│   │   ├── XlsxRead/          F2   XLSX reader (10 Addendum X.7.1: workbook, worksheet, cell, styles, shared
│   │   │                           strings, sheet parser, ExcelSerial, XlsxRender + ShippalmDates)
│   │   ├── Resources/         F1   sire2_question_bank.json (byte copy of AA/Sire/Data/…)
│   │   ├── Services/          F2   SearchService, QuickSwitcherScoring, ReminderService, WorkRange, BatchDone,
│   │   │                           BatchDeadline, BatchDelete, SavedListOrder, ChecklistTemplateService,
│   │   │                           ScheduleService, DataDiff, AgeVerdict, XamlPlainText, NetDateParser, CrewText
│   │   ├── Launch/            F3   LaunchOptions, AppFolderResolver, Preflight, CrashLog, Translocation
│   │   ├── Commands/          F3   SectionID, CommandID, ShortcutRegistry, CommandRouterCore (pure)
│   │   ├── ShellSupport/      W-SHELL    pure helpers (smoke-test report, digest bookkeeping, version text)
│   │   ├── Bundles/           W-PERSIST  BundleService, DataStore+Sync
│   │   ├── Attachments/       W-PERSIST  AttachmentStore, PathMapper, AttachmentOpener
│   │   ├── SharedSave/        W-PERSIST  SharedSaveCoordinator, DirectoryWatcher
│   │   ├── Instance/          W-PERSIST  InstanceGuard, DataFileFingerprint (the DataFileWriteGuard), ConflictCopies
│   │   ├── RichText/          W-RICH     XamlDOM, XamlStyle, XamlReader, XamlWriter, HTMLToXAML,
│   │   │                                 RichListFormatter, LockRules, RichTextAttributes, RichTextMetadata
│   │   ├── Editor/            W-CONT     pure helpers (insert-saved-list lines, link normalisation, table plans)
│   │   ├── FileBank/          W-FILES    pure helpers (tab filters, columns, source labels, link-to-items rows)
│   │   ├── Hierarchy/         W-HIER     TagParser, HierarchySidebarBuilder, LockMessages
│   │   ├── Builders/          W-BUILD    BuilderReorder, DurationParser, Shorten, BuilderLogKinds
│   │   ├── Calendar/          W-PLAN     CalendarRowBuilder, PlannerGeometry, PlannerPlacement
│   │   ├── Board/             W-PLAN     BoardModel, BucketsModel, MapLayout
│   │   ├── QuickWork/         W-QUICK    QuickWorkRows, PinBoard
│   │   ├── Windows/           W-QUICK    DueListBuilder, ActivityLogCSV (internal to W-QUICK)
│   │   ├── Crew/              W-CREW     DateResolver, CompasReader, CrewConverter, CrewMappingTables,
│   │   │                                 CrewColumns, CrewExpiry, CrewSort, ScheduleTime, ScheduleTimeline
│   │   │                                 (crew schedule builder logic, 06 §I)
│   │   ├── Vessel/            W-VESSEL   MaritimeIcons, ShippalmReader, PortCallReader, PortsService,
│   │   │                                 WorkOrderAnalysis, QuickCardTargets
│   │   ├── Export/            W-PDF      PdfDOM, PdfStyles, FontResolver, LinkScanner, RichTextToPdf,
│   │   │                                 ItemPdfBuilder, SavedListsPdfBuilder, ChecklistPdfBuilder,
│   │   │                                 ChecklistXlsxWriter, PdfLayoutEngine, PdfRenderer, PdfSnapshots
│   │   ├── Sire/              W-SIRE     bank, models, TagExtractor, TaskIdentifier, SireFlow, SireToAa,
│   │   │                                 SireExport, GeminiClient, GeminiKeyStore
│   │   ├── FlashSync/         W-FLASH    Base45, Fountain, FlashFrame, FlashEncoder, FlashDecoder,
│   │   │                                 FlashChangeSet, FlashSyncStore, QR/
│   │   ├── GoogleDrive/       W-DRIVE    BundleName, DriveQuery, GoogleClientSecret, OAuthLoopback,
│   │   │                                 GoogleTokenStore, DriveClient, DriveSync
│   │   └── Tools/             W-DRIVE    FolderPlan, DateCalc, UnitCatalog, DotNetNumberParser/Formatter
│   └── AA/                                    (executable; SwiftUI + AppKit)
│       ├── App/            F3   AAMain (@main), AppDelegate, LaunchCoordinator, SceneOpener, Scenes, AppEnvironment
│       ├── Shell/          F3   main window, section sidebar ("tab strip"), toolbar, status line, shared-save
│       │                        indicator, shortcut strip, safe-mode/read-only banners, splash, login, tab colours
│       │                        sheet, quit pipeline, 5-min autosave, window-state persistence
│       ├── ShellFeatures/  W-SHELL  File-menu flows (ShellFlows), Settings window, About, Keyboard Shortcuts
│       │                        window, reminders/digest/Dock badge/MenuBarExtra content, NotificationCenterBridge,
│       │                        --smoke-test runner, open-documents handling
│       ├── Commands/       F3   AppCommands (SwiftUI Commands), CommandRouter, AppKitMenuBridge,
│       │                        ListCommands/SectionCommands modifiers, AARichTextResponder protocol
│       ├── Design/         F3   tokens + reusable components (§8)
│       ├── Shared/         F3   DialogPresenter + shared sheets (prompt, date prompt, OptionalDatePicker, item
│       │                        picker, password, alerts, panels), EditorFlushCenter, Navigator, StatusCenter
│       ├── Debug/          F3   snapshot hook (DEBUG only), SnapshotRegistry
│       ├── Resources/      F3   Splash.png (byte copy), MenuBarIconTemplate(.png, @2x.png)
│       ├── PersistenceUI/  W-PERSIST  path-mapping settings, instance alerts, conflict banner/sheet, conflict copies
│       ├── Editor/         W-CONT
│       ├── FileBank/       W-FILES
│       ├── Hierarchy/      W-HIER
│       ├── Builders/       W-BUILD
│       ├── Calendar/       W-PLAN
│       ├── Board/          W-PLAN
│       ├── QuickWork/      W-QUICK
│       ├── Windows/        W-QUICK
│       ├── Crew/           W-CREW
│       ├── Vessel/         W-VESSEL
│       ├── Export/         W-PDF
│       ├── Sire/           W-SIRE
│       ├── FlashSync/      W-FLASH
│       ├── Drive/          W-DRIVE
│       └── Tools/          W-DRIVE
└── Tests/AACoreTests/
    ├── Support/            F1   shared helpers (TempFolder, FixedClock, fixture loader, store factory)
    ├── Fixtures/<area>/    per owner (§10.2); `Fixtures/` is copied whole into the test bundle
    └── <Area>/             tests, one sub-folder per AACore area, same owner as the AACore folder
```

Spec paths that say `mac/Tests/Fixtures/...` (05 XD.8, 10 X.7.6) mean `mac/Tests/AACoreTests/Fixtures/...`.
01 DATA-220 lists `XamlPlainText` under `AACore/RichText`; it lives in `AACore/Services/XamlPlainText.swift`
(owner F2) because both of its callers (search, DataDiff) are F2's — same type, different folder.
10 X.7.1 places the XLSX reader files in `AACore/Xlsx/`; they live in `AACore/XlsxRead/` (owner F2) so that the
reader and the writer have different owners — same file names and types. 09 §6.3 places `ParseDate` with the crew
code; it lives in `AACore/Services/NetDateParser.swift` (owner F2) because F1 models, the F2 XLSX renderer B+,
W-CREW and W-VESSEL all need it before Stage W (§6.5).

---------------------------------------------------------------------------------------------------------------------

## 2. Layering, isolation and threading rules

### 2.1 Layers

```
 AA (SwiftUI/AppKit views, window/scene plumbing, NSAlert/NSSavePanel, NSWorkspace UI flows)
   │  imports
   ▼
 AACore (models, JSON, persistence, services, codecs, AppKit-only helpers such as NSAttributedString/CoreText)
```
* **AACore never imports SwiftUI.** It may import AppKit (NSAttributedString, NSFont, NSColor, NSWorkspace,
  NSTextStorage attributes, CoreText/CGContext PDF drawing) and every other system framework.
* **UI never touches files, JSON text or ZIP entries directly.** Views call AACore services
  (`DataStore`, `BundleService`, `AttachmentStore`, `XlsxWorkbook`, `PdfExportFlows`…) and present panels/alerts.
  The only file operations allowed in the AA target are: presenting open/save panels, `NSWorkspace.open`, and
  writing a finished export `Data` to the URL the user chose via an AACore helper (`AtomicWrite.write`).
* **UI never mutates `settings.json` directly** — only through `SettingsStore` setters.
* **Mac-only preferences** go to `UserDefaults` via `MacPreferences` (§6.1), never to `settings.json` or
  `data.json` (01 §6.8, OC-52).
* Every feature implementation carries the owning spec ID in a comment (`// Spec: 04 HIER-131, 07 VIEW-208…216`)
  and every test names the vector it implements (`// TV: 02 T-ORD-6`) (01 DATA-221).

### 2.2 Isolation

| Kind of code | Isolation |
|---|---|
| Model classes (`AppData` and everything in §4 that is a class), `AppStore`, `DataStore`, `SettingsStore`, `PasswordService`, `ItemLockService`, every service that reads or writes model objects (F2 services, SharedSaveCoordinator, BundleService, AttachmentStore, CrewConverter apply step, PortsService, SireToAa, FlashSyncStore apply/build…) | `@MainActor` |
| Value codecs and pure algorithms over values: `JSONValue`/parser/writer, `NetDateTime`, `CivilDate`, Zip, Xlsx, crypto primitives, XamlDOM/XamlStyle, HTMLToXAML, Base45/Fountain/QR, PDF layout over snapshots, Xlsx renderers, DateResolver, NetDateParser, TagExtractor, TaskIdentifier, unit/date tools | `nonisolated`, `Sendable` value types |
| All SwiftUI views and view models | `@MainActor` (views are by protocol; `@Observable` view models are annotated) |
| AppKit bridges (`NSViewRepresentable`, NSTextView subclasses, NSPanel controllers) | `@MainActor` |

Binding Swift idioms (verified on this toolchain: Swift 6.4, `-swift-version 5`, `-warnings-as-errors`, macOS 26):
* **Isolated conformances (SE-0470).** Every `@MainActor` type that conforms to a **nonisolated** protocol
  (`Identifiable`, `Hashable`, `Equatable`, `Comparable`, `CustomStringConvertible`, `Transferable`, …) writes the
  conformance as `@MainActor P` — e.g. `public final class ChecklistStep: JSONModel, SchedulableJob, Bucketable,
  @MainActor Identifiable`. The alternative is to mark every witness `nonisolated`, which is only possible for
  `let` storage of `Sendable` type. A plain conformance fails ("conformance … crosses into main actor-isolated
  code"). Isolated `Identifiable` works with `List`, `ForEach` and `Table(selection:)` on the macOS 26 target.
  Conformances to `@MainActor` protocols (`JSONModel`, `SchedulableJob`, `Bucketable`, `SharedSaveHost`, …) are
  written plainly.
* **Value types are `nonisolated`.** A struct/enum that conforms to a `@MainActor` protocol is otherwise *inferred*
  `@MainActor` (so are its memberwise init and computed properties). Such value types are declared
  `nonisolated public struct X: …, Sendable` (SE-0449) — see §3.8 for the four value records.
* **Pure static helpers on model classes are `nonisolated`** (`public nonisolated static func parseDate(_:)`),
  so off-main readers and converters can call them.
* **Deinit that touches main-actor state is `isolated deinit`** (Swift 6.2+, compiles for macOS 26), e.g.
  `EventSubscription`. A plain `deinit` is nonisolated and cannot call the `@MainActor` hub.
* **Environment defaults for `@MainActor` classes** use a `nonisolated init()` and a `nonisolated static let`
  instance with `@Entry` (§7.5). Never allocate a new class instance in an `@Entry` default.
* **Every `public struct` in AACore declares an explicit `public init(...)` covering all stored properties**, with
  the defaults shown in this document (Swift only synthesises an *internal* memberwise init, so the AA target
  could not construct them otherwise — e.g. `ARGB(a:r:g:b:)`, `DiffResult(...)`, `PathMapping(...)`).

Rules:
1. Never touch a model object off the main actor. Background work receives **Sendable snapshots** built on the
   main actor (encoded `Data`, a `JSONValue` tree, or purpose-built value structs such as `SearchDocument`,
   `PdfItemSnapshot`) and returns values that the main actor applies.
2. Background work uses `Task.detached(priority: .userInitiated)` (or a serial `DispatchQueue` where a spec
   requires FIFO); results hop back with `await MainActor.run { … }` and are applied only if the relevant
   generation token still matches (`store.generation`, a view-model counter).
3. No `DispatchQueue.main.sync`, no `Thread.sleep`, no semaphore waits on the main thread **except**
   `AppStore.save()` (confirmed synchronous save, 02 REPO-003) which waits on the writer queue with a 15 s timeout;
   the writer never needs the main thread, so this cannot deadlock.
4. Timers are `@MainActor` async loops (`while !Task.isCancelled { try await Task.sleep(for:) … }`) or `Timer`
   in `.common` mode where they must fire during menu tracking/modal alerts (03 §6.1).

### 2.3 How autosave snapshots state safely (binding algorithm; F1)

```
markDirty():                                          // @MainActor
    guard !suspendSaving else return
    isDirty = true
    debounceTask?.cancel()
    let gen = generation
    debounceTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(750))          // 02 REPO-002
        guard !Task.isCancelled, gen == generation else { return }
        backgroundSaveIfDirty()
    }

backgroundSaveIfDirty():                              // @MainActor
    guard !suspendSaving, !writesPaused, isDirty else return
    let prev = data.lastModified
    let stamp = clock.now()                           // NetDateTime .local (DECISIONS: timestamps keep Windows kind)
    data.lastModified = stamp; isDirty = false
    let bytes: Data
    do { bytes = try dataStore.serializeForSave(data) }         // SNAPSHOT: model → JSONValue → UTF-8 on main
    catch { data.lastModified = prev; isDirty = true; lastSaveError = …; return }
    let job = WriteJob(bytes: bytes, url: dataStore.currentDataFile,   // URL captured at enqueue (fixes 02 D-9)
                       encryptionKey: dataStore.localEncryptionKeyIfEnabled(for: dataStore.currentDataFile))
                                                      // key comes from DataStore's in-memory session cache (§6.2),
                                                      // never a Keychain call per autosave
    writer.enqueue(job) { result in                   // serial DispatchQueue "aa.data-writer", FIFO (REPO-003a)
        Task { @MainActor in                          // writer: writeGuard?.shouldWrite → AtomicWrite → didWrite (§5.2)
            switch result {
            case .success: self.saved.send(())
            case .failure(let e):
                if self.data.lastModified == stamp { self.data.lastModified = prev }
                self.isDirty = true; self.lastSaveError = e.localizedDescription
                if case AppStoreError.pausedByGuard = e { self.pauseWrites(reason: .externalChange) }
            }
        }
    }
```
The serialised bytes are the snapshot: the model is only read on the main actor; the writer receives immutable
`Data` and never sees a model object. `save()` follows REPO-003 exactly (§5.2). Reload/import/apply calls
`replaceData(_:reason:)` which cancels the debounce and bumps `generation`, so a stale timer can never write
discarded data (REPO-006); writes already queued still complete.

### 2.4 Reload model (replaces the Windows "new repository per reload")

There is exactly **one** `AppStore` per process. A reload/import/Flash-Sync apply builds a new `AppData` and calls
`store.replaceData(newData, reason:)`: the old graph becomes unreachable, `generation` increments and
`store.dataReplaced` fires. Consequences for every UI owner:
* hold **ids**, never model references, across any `await` or in any `@State` that outlives one render;
  re-resolve with `store.item(id:)`, `store.task(id:)`, `store.step(id:)`, `store.crewMember(id:)` (§5.3);
* a resolved `nil` means orphaned (deleted or gone after reload) → show the owner spec's orphan state
  (04 HIER-114, 06 §6.1 R1: warn if the target vanished; never write into a detached object);
* sheets/editors that are open during a reload commit by id and alert if the target vanished (DECISIONS 06).
* views that take a **model reference** as input (`ContainerEditorView(container:)`, `FileBankView(container:)`,
  `ContainerViewerSheet(container:)`, `@Bindable var task`) are always hosted with
  `.id(ObjectIdentifier(model))`, so a replaced graph creates a fresh view. In addition every such editor, when
  its model identity changes or `store.dataReplaced` fires, **flushes the old binding first** (only if the old
  object is still reachable by id), then unregisters from `EditorFlushCenter` and rebinds — it never keeps
  editing a detached object.
* DECISIONS Q-3: a reload keeps the current window geometry and the per-device `Ui` keys
  (`UiState.copyPerDeviceValues(from:)`, §4.9), applied by F3's `loadDataAndInitUI`.

---------------------------------------------------------------------------------------------------------------------

## 3. JSON layer, dates, GUIDs and the model mapping pattern (F1)

### 3.1 Ordered JSON tree — `AACore/JSON/JSONValue.swift`

```swift
public enum Ordinal {                              // AACore/Foundation/Ordinal.swift — .NET ordinal string semantics
    public static func equals(_ a: String, _ b: String) -> Bool    // a.utf16.elementsEqual(b.utf16)
    public static func hash(_ s: String, into h: inout Hasher)     // hashes the UTF-16 code units
    public struct Key: Hashable, Sendable {                        // dictionary key with ordinal ==/hash
        public let string: String; public init(_ s: String)
    }
}

public struct JSONNumber: Sendable, Hashable {     // == and hash by lexeme (ordinal): "1" ≠ "1.0" ≠ "1e0", "-0" ≠ "0"
    public let lexeme: String                      // raw text as read, or .NET-formatted text when created
    public init(lexeme: String)                    // no validation beyond the parser's
    public init(_ value: Int)                      // invariant integer text
    public init(_ value: Int64)
    public init?(_ value: Double)                  // NetNumberText.shortest; nil for NaN/±Infinity (01 §4.1.6)
    public var doubleValue: Double? { get }
    public var int64Value: Int64? { get }          // integer lexeme only (optional "-", digits); "5.0"/"5E0" → nil
    public var int32Value: Int32? { get }          // integer lexeme within Int32.min…Int32.max, else nil
    public var intValue: Int? { get }              // = int32Value.map(Int.init) — C# `int` fields and enums are Int32
}

public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(JSONNumber)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
    /// WRITER-ONLY. A string emitted between quotes **without escaping** (the caller guarantees printable ASCII
    /// with no `"` or `\`). Produced only by `JSONObjectBuilder.date/optionalDate` to reproduce STJ's typed
    /// `DateTime` output (`Utf8JsonWriter.WriteStringValue(DateTime)` bypasses the encoder, so offsets keep a
    /// literal `+`). The parser never produces it. Everywhere else it behaves exactly like `.string` with the
    /// same text (accessors, `==`, hash, `deepEquals`, `idText`).
    case rawString(String)
    public var objectValue: JSONObject? { get }
    public var arrayValue: [JSONValue]? { get }
    public var stringValue: String? { get }        // .string or .rawString
    public var boolValue: Bool? { get }
    public var isNull: Bool { get }
    /// FlashChangeSet id text: string → raw, number → lexeme, bool → "true"/"false" (13 §3.11.10)
    public var idText: String? { get }
    /// 13 §3.11.9 DeepEquals exactly: nil (absent or JSON null) handling; objects by count incl. null-valued keys
    /// and key lookup (order ignored); arrays ordered; numbers by lexeme; strings ordinally; string ≠ number.
    public static func deepEquals(_ a: JSONValue?, _ b: JSONValue?) -> Bool
}

public struct JSONObject: Sendable, Hashable, Sequence {
    public init()
    public init(_ pairs: [(String, JSONValue)])    // later duplicates follow the parser rule below
    public private(set) var pairs: [(key: String, value: JSONValue)]      // document / insertion order
    public var keys: [String] { get }
    public var count: Int { get }
    /// nil when absent OR JSON null (mirrors JsonNode obj[key], 13 §3.11.10). GET-ONLY: there is no subscript
    /// setter, because `a[k] = b[k]` would silently turn a JSON null into a removal.
    public subscript(key: String) -> JSONValue? { get }
    public func containsKey(_ key: String) -> Bool                        // true for a key whose value is null
    public func rawValue(forKey key: String) -> JSONValue?                // .null preserved (distinguishes null/absent)
    public mutating func set(_ key: String, _ value: JSONValue)           // replace in place or append; `.null` stores null
    @discardableResult public mutating func removeValue(forKey key: String) -> JSONValue?   // re-add appends at the end
    public mutating func append(contentsOf other: JSONObject)             // used for `extra` members
    public func filtering(excluding keys: Set<Ordinal.Key>) -> JSONObject // order kept
}
```
Semantics (MUST):
* **Ordinal strings.** Key lookup in `JSONObject`, key identity in `OrderedMap`, and string equality/hashing inside
  `JSONValue` compare **UTF-16 code units** (`Ordinal`), never Swift `String ==` / `Dictionary<String,…>` (which use
  Unicode canonical equivalence: `"é"` U+00E9 and `"e\u{301}"` would merge and one would be dropped on save, where
  STJ's ordinal dictionary keeps both — 13 CS-19, `GroupExpanded` keys like `Task|Café`).
* **`JSONValue ==` is structural and ordered** (object key order significant, numbers by lexeme, strings ordinal,
  `.rawString(s) == .string(s)`); it is for tests and caches. Flash Sync and every "did it change" comparison use
  `JSONValue.deepEquals`, never `==`. F1 tests the CS-19 vectors (`{"a":1,"b":2}` deep-equals `{"b":2,"a":1}`,
  `[1,2]` ≠ `[2,1]`, `{"a":null}` ≠ `{}`, `"é"` ≠ `"e"+U+0301`, `1` ≠ `1.0`, `"1"` ≠ `1`).
* Duplicate keys on read: the parser keeps **one** pair per key at the position of its **first** occurrence with
  the **last** value (System.Text.Json dictionary / typed-property "last wins" semantics, 01 §4.1.4). Key comparison
  is ordinal and case-sensitive.

### 3.2 Parser and writer — `JSONParser.swift`, `JSONWriter.swift`

```swift
public enum JSONParseError: Error, Equatable, Sendable {
    case invalid(offset: Int, reason: String)      // comments, trailing commas, bad literal, NaN, trailing content… (01 §4.1.8)
    case tooDeep(limit: Int)                       // > 64 (01 §4.1.9)
    case invalidUTF8(offset: Int)                  // only with `invalidUTF8: .reject`
}
public enum InvalidUTF8Policy: Sendable { case replace, reject }
public enum JSONParser {
    public static let maxDepth = 64
    /// Byte-level UTF-8 parser. A leading UTF-8 BOM is skipped. Keeps key order and number lexemes.
    /// `.replace` (default) decodes invalid UTF-8 sequences as U+FFFD like .NET `Encoding.UTF8.GetString`
    /// (`ReadDataText`, `File.ReadAllText`, 01 §3.4) — every AA reader (data.json, settings.json, source.json,
    /// bundle data.json, Flash Sync payloads, which 13 §3.12 also decodes to a string first) uses it.
    public static func parse(_ data: Data, maxDepth: Int = maxDepth,
                             invalidUTF8: InvalidUTF8Policy = .replace) throws(JSONParseError) -> JSONValue
    public static func parse(_ text: String, maxDepth: Int = maxDepth) throws(JSONParseError) -> JSONValue
}

public struct JSONWriteOptions: Sendable, Equatable {
    public var indented: Bool = false              // compact by default (data.json, settings.json, source.json…)
    public var indent: String = "  "               // 2 spaces (System.Text.Json WriteIndented)
    public var newline: String = "\n"              // .aasched.json uses "\r\n" (OC-41)
    public var maxDepth: Int = 64
    public init(indented: Bool = false, indent: String = "  ", newline: String = "\n", maxDepth: Int = 64)
    public static let compact: JSONWriteOptions
    public static let aaschedIndented: JSONWriteOptions   // indented, "\r\n", `"Key": value`
}
public enum JSONWriteError: Error, Sendable { case tooDeep(limit: Int) }
public enum JSONWriter {
    public static func data(_ value: JSONValue, options: JSONWriteOptions = .compact) throws(JSONWriteError) -> Data
    public static func string(_ value: JSONValue, options: JSONWriteOptions = .compact) throws(JSONWriteError) -> String
    public static func escape(_ s: String) -> String      // exposed for tests and for XAML-in-JSON goldens
}
```
Parser edge cases (MUST; vectors 01 A19, A09b):
* Any JSON value is accepted as the root by the parser; **trailing whitespace** (space, `\t`, `\n`, `\r`) is fine;
  **any other trailing content** (A19.9: a second object) and **empty input** → `.invalid`.
* A lone surrogate escape (`"\uD800"`, or a high surrogate not followed by a low one) cannot be held in a Swift
  `String`: it decodes to U+FFFD (documented divergence, `Deviations/F1.md`; A09b is record-only).
* What a `null` / non-object root means is decided by the decoders (§3.10), not the parser.

Writer contract (MUST, 01 §4.1 + OC-01):
* Compact: no spaces, no trailing newline, UTF-8 without BOM. Indented: `"Key": value` (one space after the colon,
  none before), nested indent by `indent`, lines joined by `newline`, empty arrays/objects as `[]`/`{}`.
* Escaping = .NET default `JavaScriptEncoder` (01 §4.1.7). Every target below is written with a literal
  backslash (if you ever read a bare character on the right of an arrow, this file was corrupted — the exact
  table is 01 §4.1.7):
  - literal: ASCII letters, digits, space and ``! # $ % ( ) * , - . / : ; = ? @ [ ] ^ _ { | } ~``;
  - `"` → `\u0022`, `\` → `\\`, `&` → `\u0026`, `'` → `\u0027`, `+` → `\u002B`, `<` → `\u003C`,
    `>` → `\u003E`, `` ` `` → `\u0060`;
  - `\b \t \n \f \r` → those short escapes; every other C0 control (U+0000…U+001F) and U+007F → `\u00XX`
    (e.g. U+007F → `\u007F`);
  - **every non-ASCII scalar** → `\uXXXX` in **upper-case** hex; non-BMP as a surrogate pair (`😀` →
    `\uD83D\uDE00`).
  Keys are escaped the same way. Output is therefore pure ASCII. **F1 golden** (01 §7.4, verbatim):
  `Pump → main <A&B> 'x' "y" +1` → `"Pump \u2192 main \u003CA\u0026B\u003E \u0027x\u0027 \u0022y\u0022 \u002B1"`.
* `.rawString(s)` is written as `"` + `s` + `"` with no escaping (see §3.1; only typed dates use it). Generic
  trees (Flash Sync, `extra`, the settings raw tree) never contain it, so a date held as a plain `.string` in
  such a tree escapes `+` as `\u002B`, exactly like STJ `JsonNode.ToJsonString()`.
* Numbers are written from `JSONNumber.lexeme` verbatim (so read numbers round-trip byte-exactly).
* Depth > 64 throws; callers surface it as a save error ("the structure is too deep to save") and never write.

### 3.3 .NET number text — `AACore/Xlsx/NetNumberText.swift` (F1; shared by JSON, XLSX, tools)

```swift
public enum NetNumberText {
    /// System.Text.Json / double.ToString("R") shortest round-trip (10 X.4.12 NetShortest):
    /// integral |x| < 1e15 → integer text ("180", "-24", "-0" for -0.0);
    /// otherwise shortest round-trip digits with decimal exponent `e` of the first digit:
    /// **fixed iff -5 < e < 15**, i.e. scientific iff e ≥ 15 or e ≤ -5, formatted "1E+16", "1E-05"
    /// (capital E, explicit sign, at least 2 exponent digits); fixed otherwise ("12.5", "0.30000000000000004").
    public static func shortest(_ x: Double) -> String?          // nil for NaN/Infinity
    public static func int64Saturating(_ x: Double) -> Int64       // 10 X.4.12
    public static func net0_4(_ x: Double) -> String               // .NET "0.####", half away from zero, "-0" → "0"
}
```
F1 vectors (01 §4.1.6, A15): `1e-4` → `0.0001`, `1e-5` → `1E-05`, `1.5e-7` → `1.5E-07`, `5e-324` → `5E-324`,
`1e15` → `1E+15`, `1e16` → `1E+16`, `0.1` → `0.1`, `-0.0` → `-0`, `1.7976931348623157e308` → `1.7976931348623157E+308`.

### 3.4 `NetDateTime` — `AACore/JSON/NetDateTime.swift`

```swift
public struct NetDateTime: Sendable, Hashable, Comparable, CustomStringConvertible {
    public enum Kind: UInt8, Sendable { case unspecified, utc, local }
    /// Wall-clock ticks since 0001-01-01T00:00:00, 100 ns. NOT publicly settable: every change goes through an
    /// initializer or the arithmetic API, which clear `originalText` (a stale text would silently write the old
    /// date back to data.json).
    public private(set) var ticks: Int64
    public private(set) var kind: Kind
    /// Exact JSON text this value was read from; nil when created/edited on the Mac.
    /// Written back verbatim while non-nil (DECISIONS Q-6). Every initializer except `init?(parsing:)`, and every
    /// arithmetic/conversion function, produces nil.
    public private(set) var originalText: String?
    /// UTC offset in seconds of a `.local` value whose instant is known (set by `now()`, `init(date:kind:.local)`,
    /// `toLocalTime`, and parsing an offset-bearing text); nil for wall-clock-only values. Used by `jsonString` so an
    /// ambiguous DST hour writes the right offset (.NET's hidden ambiguous-DST bit, 01 A12). Cleared by arithmetic.
    public private(set) var offsetHint: Int32?

    public init(ticks: Int64, kind: Kind)
    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0,
                fractionTicks: Int64 = 0, kind: Kind)
    /// 01 §4.1.5 read rules: yyyy-MM-dd | yyyy-MM-ddTHH:mm | …:ss[.fraction] + optional Z / ±HH:mm.
    /// Fraction: 1…16 digits accepted (STJ JsonConstants.DateTimeParseNumFractionDigits); the first 7 are used,
    /// the rest truncated — **the A13 golden is normative** and replaces this rule when it exists.
    /// No offset → .unspecified; Z → .utc; offset → converted to `zone` wall clock, kind .local (offsetHint set).
    /// Anything else (space instead of T, other shapes) → nil. Keeps originalText.
    public init?(parsing text: String, zone: TimeZone = .current)
    /// 01 §4.1.5 write rules; returns originalText when non-nil.
    public func jsonString(zone: TimeZone = .current) -> String
    /// Canonical formatting ignoring originalText (tests, display helpers).
    public func formattedISO(zone: TimeZone = .current) -> String

    public static func == (a: Self, b: Self) -> Bool          // ticks only (.NET semantics; kind & text ignored)
    public func hash(into h: inout Hasher)                     // ticks only
    public static func < (a: Self, b: Self) -> Bool           // ticks only

    // Creation (the kinds Windows would use — DECISIONS Q-6)
    public static func now(clock: AppClock = SystemClock()) -> NetDateTime        // .local  (LastModified, Added, CreatedAt)
    public static func utcNow(clock: AppClock = SystemClock()) -> NetDateTime     // .utc    (CreatedUtc, DeletedUtc, TimestampUtc, WrittenUtc)
    public static func calendarDate(_ d: CivilDate) -> NetDateTime                // .unspecified midnight (deadlines, ranges,
                                                                                   // recurrence dates, step/subtask deadlines)
    public static func calendarDateTime(_ d: CivilDate, minutes: Int) -> NetDateTime // .unspecified (Planner ScheduledStart)
    /// Same wall clock, kind .unspecified, originalText and offsetHint nil (DECISIONS Q-6 "edited calendar date").
    public var asCalendarDate: NetDateTime { get }

    // Arithmetic (all drop originalText and offsetHint; kind preserved — calendar-date producers then apply
    // `asCalendarDate`, see the rule below)
    public var date: NetDateTime { get }                       // .Date: midnight, same kind
    public var civilDate: CivilDate { get }                    // wall-clock Y-M-D (no zone math)
    public var minutesOfDay: Int { get }
    public func addingDays(_ n: Int) -> NetDateTime
    public func addingMonths(_ n: Int) -> NetDateTime          // .NET AddMonths end-of-month clamp
    public func addingYears(_ n: Int) -> NetDateTime           // Feb 29 → Feb 28
    public func addingTicks(_ t: Int64) -> NetDateTime
    /// .NET ToLocalTime(): `.utc` AND `.unspecified` are treated as UTC and converted to `zone` wall clock, kind
    /// .local (offsetHint set); `.local` → unchanged (01 §3.22). Vector: Unspecified 2026-09-29T08:15:30 in
    /// Europe/Athens → 2026-09-29 11:15:30 Local.
    public func toLocalTime(zone: TimeZone = .current) -> NetDateTime
    public func foundationDate(zone: TimeZone = .current) -> Date       // for display/arithmetic only
    public init(date: Date, kind: Kind, zone: TimeZone = .current)
    public func format(_ pattern: NetDateFormat, zone: TimeZone = .current) -> String
    public static let unixEpochTicks: Int64 = 621_355_968_000_000_000
}
/// Fixed invariant formats (en_US_POSIX, Gregorian; 01 §6.3). Every owner uses these — nobody re-implements tick
/// formatting.
public enum NetDateFormat: Sendable {
    case isoDate            // "yyyy-MM-dd"
    case isoMinute          // "yyyy-MM-dd HH:mm"
    case isoSecond          // "yyyy-MM-dd HH:mm:ss"
    case time               // "HH:mm"
    case stampMinute        // "yyyyMMdd-HHmm"
    case stampSecond        // "yyyyMMdd-HHmmss"
    case isoLocalSeconds    // "yyyy-MM-ddTHH:mm:ss" (no offset) — Flash change-set `Created` (13 §3.11.6)
    case isoLocal7          // "yyyy-MM-ddTHH:mm:ss.fffffff" (no offset) — applier `LastModified` (13 §4.5);
                            // vector 13 §7.8 `2026-09-27T12:00:00.0000000`
    case roundTripO         // .NET "o": 7 fixed fraction digits + kind suffix ("" / "Z" / "±HH:mm") — Drive
                            // `appProperties.aaLastModified` (14 §4.5), Flash baseline `StampedUtc` (13 §4.4)
}
```
Write rules: local offsets = `offsetHint` when present, else `zone.secondsFromGMT(for:)` of the instant the wall
clock denotes; when that wall clock is **ambiguous or invalid** (DST fall-back / spring-forward), use the zone's
**standard (base) offset** like .NET `TimeZoneInfo.GetUtcOffset`. A `.local` value never writes `Z`; fractions are
the 7-digit tick fraction with trailing zeros removed (no `.` when zero). `AppClock` injection makes every
"now/today" testable. F1 tests: parse → (no edit) → `jsonString` returns the original text; parse → any arithmetic
or `asCalendarDate` → `jsonString` no longer equals the original text; A12 New York and Athens ambiguous/gap
vectors; the `toLocalTime` vector above.

**Calendar-date rule (DECISIONS Q-6, binding for every producer):** a date that is newly created or edited as a
*calendar date* is written `.unspecified`. So `nextOccurrence`/`reconcileRecurrences` outputs, `WorkRange.coerce`
outputs that change a date (a kept date keeps its value *and* its originalText), `BatchDeadline`, Planner
placements (`ScheduledStart`), step/subtask deadline edits, `OptionalDatePicker`/date-prompt results and the
`UiState.calendarSelectedDate` capture all go through `calendarDate(_:)`, `calendarDateTime(_:minutes:)` or
`asCalendarDate`. Timestamps keep their Windows kind. **Spec vectors superseded by DECISIONS Q-6** (tests assert
`.unspecified` / the preserved originalText instead): 01 §7.11 "clone Deadline … Local"; 02 §4.2 recurrence row
(Local from `DateTime.Today`); 06 §4.2 where it expects a Local calendar date; 03 §4.1 `CalendarSelectedDate`
"Local if it was DateTime.Today"; 13 §4.5 / §7.8 where a round trip through the typed model is expected to *trim*
an applied `LastModified` — the Mac keeps the applied text verbatim (`.0000000`) because originalText is kept.

### 3.5 `CivilDate`, clock — `AACore/Foundation/CivilDate.swift`, `AppClock.swift`

```swift
public struct CivilDate: Sendable, Hashable, Comparable, CustomStringConvertible {   // proleptic Gregorian
    public let year: Int, month: Int, day: Int
    public init?(year: Int, month: Int, day: Int)            // validates
    public init?(iso text: String)                            // exactly "yyyy-MM-dd"
    public var iso: String { get }                            // "yyyy-MM-dd"
    public var daysFromCivil: Int { get }                     // days since 1970-01-01
    public init(daysFromCivil: Int)
    public func addingDays(_ n: Int) -> CivilDate
    public func addingMonths(_ n: Int) -> CivilDate           // end-of-month clamp
    public func addingYears(_ n: Int) -> CivilDate
    public func days(to other: CivilDate) -> Int
    public var weekday: Int { get }                           // 0 = Sunday … 6 = Saturday (.NET DayOfWeek)
}
public protocol AppClock: Sendable {
    func now() -> NetDateTime          // .local
    func utcNow() -> NetDateTime       // .utc
    func today() -> CivilDate          // local date
    var timeZone: TimeZone { get }
    func instant() -> Date
}
public struct SystemClock: AppClock { public init() }
public struct FixedClock: AppClock { public init(local: String /* "2026-09-29T14:05:00" */, zone: TimeZone) }
```

### 3.6 GUIDs — `AACore/JSON/NetGuid.swift`

```swift
public extension UUID {
    var netString: String { get }                          // lowercase "D" format
    init?(netString: String)                               // 36-char 8-4-4-4-12, hex any case; else nil
    static let netEmpty: UUID                              // 00000000-0000-0000-0000-000000000000 (never omitted)
}
```
A JSON value that is not a valid GUID string for a GUID-typed key is a **load failure** (Windows parity → safe
mode). A missing `Id` gets a fresh `UUID()` on every load (C# initializer semantics, 01 §4.1.10).

### 3.7 .NET-style integer enums — `AACore/Model/NetEnums.swift`

```swift
public protocol NetIntEnum: RawRepresentable, Hashable, Sendable where RawValue == Int {
    init(rawValue: Int)                                    // any Int accepted; unknown values round-trip
    static var names: [Int: String] { get }                // enum names as C# prints them
}
public extension NetIntEnum { var name: String { get } }   // names[rawValue] ?? String(rawValue)
public struct FileKind: NetIntEnum         { document 0, image 1, video 2, link 3, other 4 }
public struct ItemKind: NetIntEnum         { equipment 0, task 1, procedure 2, vessel 3 }
public struct RecurrenceKind: NetIntEnum   { none 0, daily 1, weekly 2, monthly 3, yearly 4 }
public struct WorkStatus: NetIntEnum       { todo 0, inProgress 1, blocked 2, done 3 }
public struct ScheduleKind: NetIntEnum     { note 0, task 1, procedure 2, equipment 3 }
public struct CrewFlagSeverity: NetIntEnum { info 0, warning 1, error 2 }
```
(Each declared as `public static let <case> = Self(rawValue: n)`.) Raw values are read and written only
within Int32 (§3.8 rule 2). Display labels are Windows enum names by
default (`Todo`, `InProgress`, …, OC-36); DECISIONS 04 Q-G's friendly labels are a **display-only** mapping
`WorkStatus.friendlyLabel` / `RecurrenceKind.friendlyLabel` ("To Do", "In Progress", "Blocked", "Done";
"None", "Daily", …) that UI owners use in pickers. Stored integers never change.

### 3.8 Model mapping pattern — `AACore/JSON/JSONModelSupport.swift`

```swift
public struct JSONDecodeContext: Sendable {
    public var zone: TimeZone = .current
    public var clock: AppClock = SystemClock()             // defaults: Added = Now, CreatedUtc = UtcNow …
    public var newGuid: @Sendable () -> UUID = { UUID() }  // tests inject deterministic ids
    public var path: [String] = []                         // for error messages ("Tasks[3].Subtasks[0].Deadline")
    public init(zone: TimeZone = .current, clock: AppClock = SystemClock(),
                newGuid: @escaping @Sendable () -> UUID = { UUID() }, path: [String] = [])
    public static let standard: JSONDecodeContext
}
public enum JSONModelError: Error, Sendable, CustomStringConvertible {
    case typeMismatch(path: String, expected: String)      // Windows would fail → load failure → safe mode
    case invalidGuid(path: String, text: String)
    case invalidDate(path: String, text: String)
    case notAnObject(path: String)
}
public final class JSONEncodeIssueLog: @unchecked Sendable {   // lock-protected; collects writer-side violations
    public init()
    public var issues: [String] { get }                    // e.g. "Tasks[3].DurationMinutes: 2147483648 is outside Int32"
    public func record(_ issue: String)
}
public struct JSONEncodeOptions: Sendable {
    public var writeNulls: Bool = false                    // true only for .aasched.json (06 §4.5)
    public var includeExtra: Bool = true                   // false only for .aasched.json export (TV-OWN-11: Windows'
                                                           // default-options serializer writes only declared keys)
    public var zone: TimeZone = .current
    public var issueLog: JSONEncodeIssueLog? = nil          // serializeForSave passes one and fails the save if non-empty
    public init(writeNulls: Bool = false, includeExtra: Bool = true, zone: TimeZone = .current,
                issueLog: JSONEncodeIssueLog? = nil)
    public static let dataFile: JSONEncodeOptions          // data.json / trash payloads / source.json
    public static let aasched: JSONEncodeOptions           // writeNulls = true, includeExtra = false
}
/// @MainActor protocol (decision, stated once): model CLASSES conform plainly; the four value records conform from
/// `nonisolated public struct` declarations (SE-0449), so their inits and computed members stay usable off-main.
@MainActor public protocol JSONModel {
    static var jsonKeys: [String] { get }                  // known keys in EMISSION order (derived first, then base)
    init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError)
    func toJSON(options: JSONEncodeOptions) -> JSONObject
    var extra: JSONObject { get set }                      // unknown members, emitted after known keys
}

/// Reading helpers: nil = absent OR JSON null (→ caller applies the C# default).
public struct JSONFieldReader: Sendable {
    public init(_ object: JSONObject, context: JSONDecodeContext, type: String)
    public func string(_ key: String) throws(JSONModelError) -> String?
    public func bool(_ key: String) throws(JSONModelError) -> Bool?
    public func int(_ key: String) throws(JSONModelError) -> Int?              // integer lexeme within Int32 only
    public func double(_ key: String) throws(JSONModelError) -> Double?
    public func guid(_ key: String) throws(JSONModelError) -> UUID?
    public func date(_ key: String) throws(JSONModelError) -> NetDateTime?
    public func netEnum<E: NetIntEnum>(_ key: String, _ type: E.Type) throws(JSONModelError) -> E?  // Int32 lexeme only
    public func guidArray(_ key: String) throws(JSONModelError) -> [UUID]?
    public func stringArray(_ key: String) throws(JSONModelError) -> [String]?
    public func stringMap(_ key: String) throws(JSONModelError) -> OrderedMap<String>?
    public func boolMap(_ key: String) throws(JSONModelError) -> OrderedMap<Bool>?
    @MainActor public func model<M: JSONModel>(_ key: String, _ type: M.Type) throws(JSONModelError) -> M?
    @MainActor public func modelArray<M: JSONModel>(_ key: String, _ type: M.Type) throws(JSONModelError) -> [M]?
    /// Pairs whose key ∉ knownKeys ∪ legacyKeys (ordinal), raw and in document order.
    public func unknownMembers(knownKeys: [String], legacyKeys: [String] = []) -> JSONObject
}
public struct JSONObjectBuilder {
    public init(_ options: JSONEncodeOptions)
    public mutating func string(_ key: String, _ v: String)
    public mutating func optionalString(_ key: String, _ v: String?)   // omitted when nil (null when writeNulls)
    public mutating func bool(_ key: String, _ v: Bool)
    public mutating func int(_ key: String, _ v: Int)                  // outside Int32 → clamps AND records an issue
    public mutating func double(_ key: String, _ v: Double)            // NaN/∞ → key skipped
    public mutating func optionalDouble(_ key: String, _ v: Double?)
    public mutating func guid(_ key: String, _ v: UUID)
    public mutating func optionalGuid(_ key: String, _ v: UUID?)
    public mutating func date(_ key: String, _ v: NetDateTime)         // emits .rawString(v.jsonString(zone:)) (§3.1)
    public mutating func optionalDate(_ key: String, _ v: NetDateTime?)
    public mutating func netEnum<E: NetIntEnum>(_ key: String, _ v: E) // outside Int32 → clamps AND records an issue
    public mutating func guidArray(_ key: String, _ v: [UUID])
    public mutating func stringArray(_ key: String, _ v: [String])
    public mutating func stringMap(_ key: String, _ v: OrderedMap<String>)
    public mutating func boolMap(_ key: String, _ v: OrderedMap<Bool>)
    @MainActor public mutating func model<M: JSONModel>(_ key: String, _ v: M)
    @MainActor public mutating func modelArray<M: JSONModel>(_ key: String, _ v: [M])
    public func build(appending extra: JSONObject) -> JSONObject      // extra keys that collide with known keys are
                                                                      // dropped; nothing appended when !includeExtra
}
/// AACore/Foundation. Mirrors .NET Dictionary<string,T> exactly: ordinal keys (§3.1) and the entries-array/free-list
/// layout — a removed entry frees its slot, and the next insertion of a NEW key reuses the most recently freed slot
/// (LIFO), so enumeration order after remove+add equals Windows' (remove b, add d → a, d, c).
public struct OrderedMap<Value: Sendable & Hashable>: Sendable, Hashable, Sequence {
    public init()
    public subscript(key: String) -> Value? { get set }      // set on existing key keeps position; nil removes
    public var keys: [String] { get }                        // enumeration order (slot order, holes skipped)
    public var count: Int { get }
    public var pairs: [(key: String, value: Value)] { get }
}
```
Rules (MUST):
1. **Tolerant defaults.** Missing key or JSON `null` → the C# initializer default (tables in §4). `null` for a
   value-typed key (bool/int/double/enum) is also mapped to the default (Mac leniency; Windows would fail).
2. **Type mismatch on a known key** (string for an enum, object where an array is expected, invalid GUID/date
   text) → throw `JSONModelError` → `DataStore.load` fails → safe mode (Windows parity; never silently coerces,
   so nothing can be lost on the next save). **Integers** (C# `int` fields and enums are Int32): only integer
   lexemes within `Int32.min…Int32.max` are accepted; `2147483648` (A07.12), `60.0` and `6E1` (A07.7/A07.8) are
   type mismatches — no leniency, parity with STJ. Undefined enum values inside Int32 (`"Recurrence":7`) load and
   round-trip. Writing: `int`/`netEnum` never emit a value outside Int32; one that would is clamped and recorded in
   the `issueLog`, and `serializeForSave` then fails with `AppStoreError.serialization` (a save error, never a file
   Windows cannot load). Model setters and UI entry points clamp to the documented ranges first.
3. **Unknown members are preserved on every object** (brief, OC-02): `extra = reader.unknownMembers(knownKeys: Self.jsonKeys)`; written
   after the known keys by `build(appending:)` **verbatim** — including JSON `null` values and the original number
   lexemes (`1.50`, `-0`, `1e2`). Legacy keys that are migrated (e.g. `HierarchyItem.BucketId`) are consumed and
   **not** kept in `extra`. F1 vectors (A10-style): top-level, `Ui` and nested (`Tasks[0]`, `Container`, `Files[0]`,
   `Sire`) extras carrying `null`, `1.50`, `-0` and `1e2` round-trip byte-exactly.
4. **Emission order** = the declaration order of §4 (derived members first, then `HierarchyItem` base members,
   then `extra`) — 01 §4.1.3. Readers never depend on order.
5. **Nulls are never written for known optional members** (`WhenWritingNull`) except when
   `JSONEncodeOptions.writeNulls` (.aasched.json). Rule 5 never applies to `extra` (rule 3).
6. `[JsonIgnore]` / computed members are never written (they are Swift computed properties).
7. Model `init(json:)` runs on the main actor for classes; parsing bytes → `JSONValue` may run off-main; the
   `nonisolated` value records may be decoded anywhere.
8. Dates go through `builder.date`, which emits `.rawString` so offsets keep a literal `+` like STJ's typed
   `DateTime`. Required goldens: the 01 §4.4 `source.json` literal byte-exact (`"LastModified":"2026-09-29T11:15:29.9876543+03:00"`);
   a Local date inside a data.json object; a Trash entry, where the inner payload has a literal `+` and the outer
   `PayloadJson` string (an ordinary escaped string) therefore contains the escaped form (§3.2).

### 3.9 Worked example — `ChecklistStep` (exact shape every model follows)

```swift
@MainActor @Observable
public final class ChecklistStep: JSONModel, SchedulableJob, Bucketable, @MainActor Identifiable {
    public var id: UUID
    public var title: String
    public var bucketIds: [UUID]
    public var done: Bool
    public var deadline: NetDateTime?
    public var isJob: Bool
    public var durationMinutes: Int
    public var scheduledStart: NetDateTime?
    public var taskIds: [UUID]
    public var equipmentIds: [UUID]
    public var container: Container
    @ObservationIgnored public var extra = JSONObject()

    public var jobName: String { title }                                    // [JsonIgnore] JobName

    public static let jsonKeys = ["Id", "Title", "BucketIds", "Done", "Deadline", "IsJob",
                                  "DurationMinutes", "ScheduledStart", "TaskIds", "EquipmentIds", "Container"]

    public init(id: UUID = UUID(), title: String = "") {
        self.id = id; self.title = title; bucketIds = []; done = false; deadline = nil
        isJob = false; durationMinutes = 60; scheduledStart = nil; taskIds = []; equipmentIds = []
        container = Container()
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ChecklistStep")
        id              = try r.guid("Id") ?? c.newGuid()
        title           = try r.string("Title") ?? ""
        bucketIds       = try r.guidArray("BucketIds") ?? []
        done            = try r.bool("Done") ?? false
        deadline        = try r.date("Deadline")
        isJob           = try r.bool("IsJob") ?? false
        durationMinutes = try r.int("DurationMinutes") ?? 60
        scheduledStart  = try r.date("ScheduledStart")
        taskIds         = try r.guidArray("TaskIds") ?? []
        equipmentIds    = try r.guidArray("EquipmentIds") ?? []
        container       = try r.model("Container", Container.self) ?? Container()
        extra           = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Title", title); w.guidArray("BucketIds", bucketIds); w.bool("Done", done)
        w.optionalDate("Deadline", deadline); w.bool("IsJob", isJob); w.int("DurationMinutes", durationMinutes)
        w.optionalDate("ScheduledStart", scheduledStart); w.guidArray("TaskIds", taskIds)
        w.guidArray("EquipmentIds", equipmentIds); w.model("Container", container)
        return w.build(appending: extra)
    }
}
```
Class hierarchy (`HierarchyItem` → `Equipment`/`TaskItem`/`Procedure`/`Vessel`) — exact shape (a stored
`static let` cannot be overridden, and a non-final class's protocol init must be `required`):
```swift
@MainActor @Observable
public class HierarchyItem: JSONModel, Bucketable, @MainActor Identifiable {
    public class var baseJSONKeys: [String] { get }        // "Id","Name",…,"LockHint" (§4.3 order)
    public class var jsonKeys: [String] { baseJSONKeys }   // satisfies the protocol's static requirement
    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError)   // decodes base keys
    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject
    public func decodeBase(_ r: JSONFieldReader) throws(JSONModelError)   // helpers used by the subclasses
    public func encodeBase(into w: inout JSONObjectBuilder)
}
public final class TaskItem: HierarchyItem, SchedulableJob {            // same for Equipment, Procedure, Vessel
    public override class var jsonKeys: [String] { ["Deadline", /* own keys in order */] + super.jsonKeys }
    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError) {
        /* read own keys */; try super.init(json: json, context: context)
        extra = JSONFieldReader(json, context: context, type: "Task")
                    .unknownMembers(knownKeys: TaskItem.jsonKeys, legacyKeys: ["BucketId"])
    }
    public override func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        /* own keys */; /* encodeBase(into:) */; /* build(appending: extra) */
    }
}
```
The base init leaves `extra` empty; each (final) subclass sets it after `super.init` from its own full key list
(own + base keys) plus the legacy `BucketId`. `@Observable` subclassing
compiles and observation fires for base-class properties changed on a subclass instance; F1 MUST keep a unit test
proving that `withObservationTracking` fires for a **base-class** property changed on a **subclass** instance. If
the toolchain ever breaks that, F1 switches the four item types to `final class` + a `HierarchyItem` protocol with
identical member names and records the change in `Docs/Deviations/F1.md` (consumers use the member names only, so
nothing else changes).

### 3.10 Model utilities — `AACore/Persistence/ModelCloning.swift` (F1)

```swift
@MainActor public enum ModelCodec {
    /// Root rules (01 §3.2, A19): a JSON `null` root → empty `AppData()`; any other non-object root (`[]`, number,
    /// string) → `.notAnObject` (load failure).
    public static func decodeAppData(_ root: JSONValue, context: JSONDecodeContext) throws(JSONModelError) -> AppData
    public static func encodeAppData(_ data: AppData, options: JSONEncodeOptions = .dataFile) -> JSONValue
    /// Deep clone through JSON (Trash options = data-file options) — 02 REPO-061 DeepClone. Uses the DYNAMIC type:
    /// `type(of: model).init(json: model.toJSON(options: .dataFile), context:)` (needs the `required init`), so a
    /// TaskItem typed as HierarchyItem clones to a TaskItem. F1 test: `deepClone(task as HierarchyItem) is TaskItem`
    /// with every key (own, base and extra) preserved.
    public static func deepClone<M: JSONModel>(_ model: M, context: JSONDecodeContext = .standard) -> M
}
@MainActor public enum TrashPayload {
    /// Compact JSON text of the item's runtime type (01 §4.10), full subtree.
    public static func encode(_ item: HierarchyItem) -> String
    public static func encode(_ crew: CrewMember) -> String
    /// Decodes with the concrete class named by `itemType` ("Equipment"|"Task"|"Procedure"|"Vessel"|"Crew").
    public static func decode(itemType: String, payload: String, context: JSONDecodeContext) -> AnyObject?   // nil on any error
}
```
Settings root rule (§6.2): a `null` settings.json root → defaults; a non-object root → unreadable.

---------------------------------------------------------------------------------------------------------------------

## 4. Every model type (F1 implements exactly this; `AACore/Model/`)

Notation per property: `swiftName: SwiftType = default  ← "JSONKey"`; rows are in **emission order**; every type
also has `@ObservationIgnored public var extra: JSONObject` (unknown members, emitted last) and
`public static let jsonKeys` listing the keys below in order (the `HierarchyItem` family uses `class var`, §3.9).
"omit-nil" = omitted when nil. Unless stated otherwise a type is
`@MainActor @Observable public final class … : JSONModel, @MainActor Identifiable` (isolated conformance, §2.2).
Unless stated otherwise, missing/null string keys default to `""`, bools to `false`, `Id` to a fresh GUID
(`c.newGuid()`), `CreatedUtc` to `utcNow` and `Added`/`CreatedAt` to `now` (A05 `NEWGUID`/`NOWUTC`/`NOW` tokens).
Pure static helpers on model classes are `nonisolated` (§2.2).
Type names equal the C# names except `Port` → `PortRecord` and `IJob` → `SchedulableJob` (Foundation/_Concurrency
clashes). General rule for every owner: never declare a type whose name exists in Foundation, AppKit, SwiftUI or the
standard library (e.g. `Port`, `Job`, `ListFormatter`, `Settings`, `Section`, `Group`, `Label`, `Table`, `Text`). Property naming rule: Swift name = C# name in lowerCamel (`Id`→`id`, `RichTextXaml`→`richTextXaml`, `UnLocode`→`unLocode`,
`SortAZ`→`sortAZ`); C# `ObservableCollection<T>`/`List<T>` → `[T]`; `Dictionary<string,T>` → `OrderedMap<T>`.

### 4.1 Protocols

```swift
@MainActor public protocol SchedulableJob: AnyObject {       // C# IJob — TaskItem (incl. subtasks), Procedure, ChecklistStep; not `Job` (clashes with _Concurrency.Job)
    var id: UUID { get }
    var isJob: Bool { get set }
    var durationMinutes: Int { get set }
    var scheduledStart: NetDateTime? { get set }
    var jobName: String { get }
}
@MainActor public protocol Bucketable: AnyObject { var bucketIds: [UUID] { get set } }   // HierarchyItem, ChecklistStep
```

### 4.2 Containers and files

**`FileItem`** (01 §4.2.4)
```
id: UUID = new                      ← "Id"
name: String = ""                   ← "Name"
path: String = ""                   ← "Path"            files/<32hex>_<name> | absolute/UNC | URL; never rewritten if linkInPlace/isLink
kind: FileKind = .document          ← "Kind"
added: NetDateTime = now(.local)    ← "Added"
isLink: Bool = false                ← "IsLink"
linkInPlace: Bool = false           ← "LinkInPlace"
linkedItemIds: [UUID] = []          ← "LinkedItemIds"
computed: sourceLabel: String       // IsLink ? "Web link" : LinkInPlace ? "Live" : "Copy"
```
**`Container`** (01 §4.2.3)
```
id: UUID = new                      ← "Id"
richTextXaml: String = ""           ← "RichTextXaml"    opaque; never rewritten unless the user edited (01 §4.11)
files: [FileItem] = []              ← "Files"
sharedWithContainerIds: [UUID] = [] ← "SharedWithContainerIds"
isLocked: Bool = false              ← "IsLocked"
```

### 4.3 Hierarchy items

**`HierarchyItem`** — `@MainActor @Observable public class HierarchyItem: JSONModel, Bucketable, @MainActor Identifiable`
(abstract; never instantiated; exact class-var / `required init` / `override` shape in §3.9). Base keys, emitted **after** each subclass's own keys (01 §4.2.2):
```
id: UUID = new                      ← "Id"
name: String = ""                   ← "Name"
description: String = ""            ← "Description"
container: Container = new          ← "Container"
relatedIds: [UUID] = []             ← "RelatedIds"
tags: [String] = []                 ← "Tags"
groupId: UUID? = nil                ← "GroupId"          omit-nil
bucketIds: [UUID] = []              ← "BucketIds"
(legacy read-only)                  ← "BucketId"         JSON null → ignored; valid GUID not already in bucketIds → append
                                                          (01 §3.20); any other value → `invalidGuid` (load failure, A11,
                                                          §3.8 rule 2); never written, not kept in extra
lockHash: String? = nil             ← "LockHash"         omit-nil
lockSalt: String? = nil             ← "LockSalt"         omit-nil
lockHint: String? = nil             ← "LockHint"         omit-nil
computed: kind: ItemKind (overridden), isLockProtected: Bool (lockHash & lockSalt both non-empty)
```
**`Equipment: HierarchyItem`** — own keys: `procedureIds: [UUID] = [] ← "ProcedureIds"`,
`taskIds: [UUID] = [] ← "TaskIds"`, `components: [Component] = [] ← "Components"`; `kind = .equipment`.

**`Component`** — `id ← "Id"`, `name: String = "" ← "Name"`, `notes: String = "" ← "Notes"` (one line),
`container: Container = new ← "Container"`.

**`TaskItem: HierarchyItem, SchedulableJob`** (01 §4.2.6) — own keys:
```
deadline: NetDateTime? = nil        ← "Deadline"         omit-nil; range END
rangeStart: NetDateTime? = nil      ← "RangeStart"       omit-nil
isJob: Bool = false                 ← "IsJob"
durationMinutes: Int = 60           ← "DurationMinutes"
scheduledStart: NetDateTime? = nil  ← "ScheduledStart"   omit-nil
recurrence: RecurrenceKind = .none  ← "Recurrence"
recurrenceSpawned: Bool = false     ← "RecurrenceSpawned"
isComplete: Bool = false            ← "IsComplete"       synced with status (below)
status: WorkStatus = .todo          ← "Status"
subtasks: [TaskItem] = []           ← "Subtasks"         recursive
```
Status/IsComplete (01 DATA-130, 02 REPO-040) — implemented as computed properties over two observed stored
properties `storedIsComplete`, `storedStatus` (not `didSet`, so Observation is unaffected):
* set `isComplete` (only on change): true → if status != .done then status = .done; false → if status == .done
  then status = .todo (InProgress/Blocked preserved);
* set `status` (only on change): isComplete = (status == .done) if different;
* **load rule (order-independent):** `Status` present → status = it, isComplete = (status == .done);
  only `IsComplete` present → status = isComplete ? .done : .todo; neither → defaults.
Computed (01 §3.19, 02 REPO-054, all ignore `originalText`):
```swift
var hasRange: Bool          // rangeStart & deadline set and rangeStart.date < deadline.date
var rangeFirst: NetDateTime? // rangeStart ?? deadline
var whenText: String        // "" | "yyyy-MM-dd → yyyy-MM-dd" (hasRange) | "yyyy-MM-dd"   (U+2192 with spaces)
func coversDay(_ day: CivilDate) -> Bool   // false without deadline; start = rangeStart.date if <= end else end
var jobName: String         // name
func allSubtasksDepthFirst() -> [TaskItem]  // pre-order, cycle-guarded (helper used by F2/W-*)
```
**`Procedure: HierarchyItem, SchedulableJob`** (01 §4.2.7) — own keys in order: `steps: [ChecklistStep] ← "Steps"`,
`deadline: NetDateTime? ← "Deadline"` (omit-nil), `recurrence: RecurrenceKind ← "Recurrence"`,
`recurrenceSpawned: Bool ← "RecurrenceSpawned"`, `status: WorkStatus = .todo ← "Status"`,
`isJob: Bool ← "IsJob"`, `durationMinutes: Int = 60 ← "DurationMinutes"`,
`scheduledStart: NetDateTime? ← "ScheduledStart"` (omit-nil). Computed `jobName`.

**`Vessel: HierarchyItem`** (01 §4.2.9) — own keys: `quickCards: [QuickCard] ← "QuickCards"`,
`jobs: [ShipJob] ← "Jobs"`, `notificationsEnabled: Bool = true ← "NotificationsEnabled"`,
`portCalls: [PortCall] ← "PortCalls"`.

**`ChecklistStep`** — §3.9 (used by procedures, crew checklists and builders).

**`ItemGroup`** — `id ← "Id"`, `kind: ItemKind = .equipment ← "Kind"`, `name: String ← "Name"`,
`expanded: Bool = true ← "Expanded"` (round-trip only).

### 4.4 Vessel sub-records (01 §4.2.9–4.2.10)

**`QuickCard`** — `id ← "Id"`, `title: String ← "Title"`, `target: String ← "Target"`, `isLink: Bool ← "IsLink"`,
`linkInPlace: Bool ← "LinkInPlace"`, `isFolder: Bool ← "IsFolder"`, `icon: String = "⚓" ← "Icon"`,
`color: String = "#FF1E88E5" ← "Color"`, `x: Double = 24 ← "X"`, `y: Double = 24 ← "Y"`,
`width: Double = 180 ← "Width"`, `height: Double = 120 ← "Height"`.
Helpers: `func clone() -> QuickCard` (same Id), `func copy(from: QuickCard)` (all but Id) — 01 DATA-139.

**`ShipJob`** (no Id; key = JobNo, case-insensitive) — strings default "": `jobNo ← "JobNo"`, `title ← "Title"`,
`workPlanNo ← "WorkPlanNo"`, `status ← "Status"`, `classCode ← "ClassCode"`, `category ← "Category"`,
`responsibleRank ← "ResponsibleRank"`, `functionNo ← "FunctionNo"`, `functionDescription ← "FunctionDescription"`,
`interval ← "Interval"`, `dueStatus ← "DueStatus"`, `dueDate ← "DueDate"`, `finishedDate ← "FinishedDate"`,
`lastDoneDate ← "LastDoneDate"`, `overdueDays: Int = 0 ← "OverdueDays"`, `notify: Bool ← "Notify"`,
`isCompleted: Bool ← "IsCompleted"`, `completedDate ← "CompletedDate"`, `importedAt ← "ImportedAt"`.
Helpers: `var dueDateValue: NetDateTime?` (= `CrewMember.parseDate(dueDate)`),
`func daysUntilDue(today: CivilDate) -> Int?`, `func copy(from: ShipJob)` (all fields incl. JobNo).
`@MainActor Identifiable` via `var id: String { jobNo.lowercased() }` (not persisted).

**`PortCall`** — `id ← "Id"`, strings: `portName ← "PortName"`, `country ← "Country"`, `unLocode ← "UnLocode"`,
`portFacility ← "PortFacility"`, `pfNo ← "PfNo"`, `arrivalDate ← "ArrivalDate"`, `arrivalTime ← "ArrivalTime"`,
`departureDate ← "DepartureDate"`, `departureTime ← "DepartureTime"`, `securityLevelPort ← "SecurityLevelPort"`,
`securityLevelVessel ← "SecurityLevelVessel"`, `sspFollowed ← "SspFollowed"`, `specialMeasures ← "SpecialMeasures"`,
`importedAt ← "ImportedAt"`. Computed: `key` (`"\(portName.lowercased())@\(arrivalDate)"`, invariant lower),
`arrivalValue`, `displayName`, `arrivalDisplay`, `departureDisplay` (01 Models.cs:322-326 exactly).

**`PortRecord`** (C# `Port`; renamed because `Foundation.Port` exists — JSON unchanged) — `id ← "Id"`, `name ← "Name"`, `country ← "Country"`, `unLocode ← "UnLocode"`,
`visits: [PortVisit] ← "Visits"`. Computed `key`, `display` (Models.cs:337-338).

**`PortVisit`** — `nonisolated public struct PortVisit: JSONModel, Hashable, Sendable` (value record, §3.8): `vesselName ← "VesselName"`,
`vesselId: UUID? ← "VesselId"` (omit-nil), `arrivalDate`, `arrivalTime`, `departureDate`, `departureTime`,
`importedAt` (keys = C# names). Computed `visitKey`, `arrivalValue`, `arrivalDisplay`, `departureDisplay`.

### 4.5 Crew (01 §4.2.12; 09 §4.2)

**`CrewMember`** — `id ← "Id"`, `checklist: [ChecklistStep] ← "Checklist"`, `schedule: [ScheduleEntry] ← "Schedule"`,
`scheduleVesselId: UUID? ← "ScheduleVesselId"` (omit-nil), then strings (default "" unless noted), each ← its
PascalCase key: `employeeId, firstName, middleName, lastName, nationality, dateOfBirth, placeOfBirth, gender,
height, eyesColor, hairColor, userType (= "Crew"), rank, rankCode, signedOnOff (= "On"), company, vessel,
signOnDate, signOnPort, signOnPortRaw, signOffDate, signOffPort, signOffPortRaw, passportNumber, passportExpiry,
passportIssued, seamansBookNumber, seamansBookExpiry, seamansBookIssued, cocNumber, cocExpiry, cocIssue,
healthCertExpiry, nokFirstName, nokLastName, nokRelationship, rawNationality`, then
`flags: [CrewReviewFlag] ← "Flags"`, `importedAt ← "ImportedAt"`, `sourceFile ← "SourceFile"`.
Computed (CrewMember.cs): `fullName` (first/middle/last, blanks skipped, single spaces), `key` (employeeId if not
blank else `"\(firstName)|\(lastName)"` trimmed of `|`), `hasFlags`, `hasErrors`, `signOffDateValue`,
`func daysUntilSignOff(today: CivilDate) -> Int?`,
`func contractStatus(on today: CivilDate, criticalDays: Int = 30, soonDays: Int = 60) -> ContractStatus`,
`public nonisolated static func parseDate(_ s: String?) -> NetDateTime?` — **forwards to `NetDateParser.parse(_:)`**
(`AACore/Services/NetDateParser.swift`, owner F2; F1's placeholder accepts only `yyyy-MM-dd`, `yyyy/MM/dd`,
`yyyy.MM.dd` until F2 merges). `ShipJob.dueDateValue` uses the same function. DATA-135/CREW-052 (contract status,
days until sign-off) are F1's; the parse algorithm (09 §6.3) is F2's.
`public enum ContractStatus: Int, Sendable { case unknown, ok, dueSoon, critical, expired }` (not persisted).

**`CrewReviewFlag`** — `nonisolated public struct CrewReviewFlag: JSONModel, Hashable, Sendable`:
`severity: CrewFlagSeverity = .info ← "Severity"`, `field: String = "" ← "Field"`, `message: String = "" ← "Message"`.

### 4.6 Saved lists, schedules, buckets (01 §4.2.13–4.2.15)

**`ChecklistTemplateItem`** (no Id) — `title ← "Title"`, `durationMinutes = 60 ← "DurationMinutes"`,
`isJob ← "IsJob"`, `container ← "Container"`. `@MainActor Identifiable` via an in-memory `let rowID = UUID()` (not persisted).
**`ChecklistTemplate`** — `id ← "Id"`, `name ← "Name"`, `items: [ChecklistTemplateItem] ← "Items"`,
`createdUtc: NetDateTime = utcNow ← "CreatedUtc"`, `groupId: UUID? ← "GroupId"` (omit-nil).
Computed `display` = `"{name or (unnamed)}  ·  {n} item{s}"`.
**`ListGroup`** — `id ← "Id"`, `name ← "Name"`, `createdUtc: NetDateTime = utcNow ← "CreatedUtc"`.
**`ScheduleEntry`** — `id ← "Id"`, `title ← "Title"`, `kind: ScheduleKind = .note ← "Kind"`,
`refId: UUID? ← "RefId"` (omit-nil; written as null under `.aasched`), `date ← "Date"`, `time ← "Time"`,
`endDate ← "EndDate"`, `endTime ← "EndTime"`, `done: Bool ← "Done"`, `notes ← "Notes"`.
Computed `when` (parseDate), `kindIcon` ("✓" task, "📋" procedure, "⚙" equipment, "•" note), `whenDisplay`.
**`ScheduleTemplate`** — `id ← "Id"`, `name ← "Name"`, `vesselId: UUID? ← "VesselId"`, `vesselName ← "VesselName"`,
`entries: [ScheduleEntry] ← "Entries"`, `createdUtc: NetDateTime = utcNow ← "CreatedUtc"`. Computed `display`
(Models.cs:419). `ScheduleService.exportJSON` encodes with `.aasched` (`includeExtra = false`); import still
preserves unknown members in memory.
**`QuickBucket`** — `id ← "Id"`, `name ← "Name"`, `category ← "Category"`,
`createdUtc: NetDateTime = utcNow ← "CreatedUtc"`.
Computed `display` (Models.cs:436).

### 4.7 Trash and log (01 §4.2.16–4.2.17)

**`TrashedItem`** — `nonisolated public struct TrashedItem: JSONModel, Hashable, Identifiable, Sendable`:
`id ← "Id"`, `itemType: String ← "ItemType"` ("Equipment"|"Task"|"Procedure"|"Vessel"|"Crew"),
`itemId: UUID = .netEmpty ← "ItemId"`, `batchId: UUID = .netEmpty ← "BatchId"`, `name ← "Name"`,
`kindLabel ← "KindLabel"`, `deletedUtc: NetDateTime = utcNow ← "DeletedUtc"`, `payloadJson: String ← "PayloadJson"`.
Computed `deletedLocal` (`deletedUtc.toLocalTime()` as `yyyy-MM-dd HH:mm` — an Unspecified stamp is converted as
UTC, §3.4), `display`. Unknown members of a subtask entry carry `ParentTaskId` (§5.3 `trashSubtask`).
`public enum TrashItemType: String { case equipment = "Equipment", task = "Task", procedure = "Procedure", vessel = "Vessel", crew = "Crew" }`.

**`LogEntry`** — `nonisolated public struct LogEntry: JSONModel, Hashable, Sendable`: `timestampUtc: NetDateTime = utcNow ← "TimestampUtc"`,
`action ← "Action"`, `kind ← "Kind"`, `name ← "Name"`, `detail ← "Detail"`. Computed `timeUtc`
(`yyyy-MM-dd HH:mm:ss 'UTC'`), `timeLocal` (`timestampUtc.toLocalTime()` as `yyyy-MM-dd HH:mm:ss`; feeds the
byte-exact Activity-log CSV `LocalTime` column, 08 §4.6).

### 4.8 SIRE session (01 §4.2.18; 12 §4.2)

**`SireState`** — `questionStatuses: OrderedMap<String> ← "QuestionStatuses"` (values "InProgress"/"Checked"/
"NotApplicable"), `bookmarks: [String] ← "Bookmarks"`, `forExport: [String] ← "ForExport"`,
`tasks: [SireTask] ← "Tasks"`, `questionBodies: OrderedMap<String> ← "QuestionBodies"` (XAML). Unknown keys are
**kept** on the Mac (Windows drops them). Helpers (SireState.cs): `status(for:) -> SireQuestionStatus`,
`setStatus(_:for:)`, `count(of:)`, `isBookmarked`, `toggleBookmark`, `isForExport`, `toggleForExport`,
`tasks(for:)`, `totalTaskCount`, `completedTaskCount` (01 DATA-140). `status(for:)` mirrors C# `Enum.TryParse`
(01 §3.26): exact, case-sensitive name match; else an integer string mapped by the C# enum order (None 0,
InProgress 1, Checked 2, NotApplicable 3); any other integer (C# would hold an undefined value that matches no
status) or any other text → `.none`. The stored text is never rewritten unless the status is
set (09 §4.5 uses the same rule for `CrewSortMode`).
`public enum SireQuestionStatus: String { case none = "None", inProgress = "InProgress", checked = "Checked", notApplicable = "NotApplicable" }`.
**`SireTask`** — `id ← "Id"`, `questionNumber: String = "" ← "QuestionNumber"`, `text: String = "" ← "Text"`,
`isCompleted: Bool = false ← "IsCompleted"`, `createdAt: NetDateTime = now(.local) ← "CreatedAt"`.

### 4.9 UI state — `UiState` (01 §4.2.20; key owners DATA-217)

```
windowLeft: Double? ← "WindowLeft"            windowTop: Double? ← "WindowTop"
windowWidth: Double? ← "WindowWidth"          windowHeight: Double? ← "WindowHeight"
windowState: String? ← "WindowState"          selectedMainTabIndex: Int = 0 ← "SelectedMainTabIndex"
selectedEquipmentId: UUID? ← "SelectedEquipmentId"   selectedTaskId: UUID? ← "SelectedTaskId"
selectedProcedureId: UUID? ← "SelectedProcedureId"   selectedVesselId: UUID? ← "SelectedVesselId"
calendarSelectedDate: NetDateTime? ← "CalendarSelectedDate"   calendarViewMode: String? ← "CalendarViewMode"
calendarFontScale: Double? ← "CalendarFontScale"     showShortcutBar: Bool = true ← "ShowShortcutBar"
quickViewPinIds: [UUID] = [] ← "QuickViewPinIds"     tabColors: OrderedMap<String> ← "TabColors"
tabOrder: [String] = [] ← "TabOrder"                 dueWindowWidth: Double? ← "DueWindowWidth"
dueWindowHeight: Double? ← "DueWindowHeight"         mapFocusedItemId: UUID? ← "MapFocusedItemId"
sortAZ: OrderedMap<Bool> ← "SortAZ"                  groupExpanded: OrderedMap<Bool> ← "GroupExpanded"
crewSortMode: String? ← "CrewSortMode"               crewTableColumns: [String] ← "CrewTableColumns"
crewTableShownColumns: [String] ← "CrewTableShownColumns"   crewTableDateFormat: String? ← "CrewTableDateFormat"
crewTableDateSeparator: String? ← "CrewTableDateSeparator"  lastDigestDate: String? ← "LastDigestDate"
```
All optional keys omit-nil; emission order exactly as listed (row-major). Helpers:
`public static let perDeviceKeyNames: [String]` (the 16 names of 13 §3.11.1, identical order) and
`func copyPerDeviceValues(from other: UiState)` (DECISIONS 03 Q-3 reload rule). NaN/∞ doubles are never written.
`TabOrder`/`TabColors` may hold tab names this build does not know (newer Windows/iOS, 03 §4.1): they are
preserved. The TabOrder writer (F3, `SectionID.writeTabOrder`, §6.9) keeps every unrecognised entry at its original
relative position (re-inserted directly after its original predecessor); `TabColors` is edited key by key on the
`OrderedMap`, never rebuilt.

### 4.10 Root — `AppData` (01 §4.2.1)

```
equipment: [Equipment] ← "Equipment"            tasks: [TaskItem] ← "Tasks"
procedures: [Procedure] ← "Procedures"          vessels: [Vessel] ← "Vessels"
groups: [ItemGroup] ← "Groups"                  crew: [CrewMember] ← "Crew"
log: [LogEntry] ← "Log"                         checklistTemplates: [ChecklistTemplate] ← "ChecklistTemplates"
listGroups: [ListGroup] ← "ListGroups"          quickBuckets: [QuickBucket] ← "QuickBuckets"
ports: [PortRecord] ← "Ports"                   scheduleTemplates: [ScheduleTemplate] ← "ScheduleTemplates"
trash: [TrashedItem] ← "Trash"                  sire: SireState ← "Sire"
ui: UiState ← "Ui"                              lastModified: NetDateTime? ← "LastModified" (omit-nil, .local)
schemaVersion: Int = 0 ← "SchemaVersion"        + extra (top-level unknown keys, emitted last)
```
Golden (MUST, 01 §4.2.1): `AppData()` with `schemaVersion = 1` encodes to exactly
`{"Equipment":[],"Tasks":[],"Procedures":[],"Vessels":[],"Groups":[],"Crew":[],"Log":[],"ChecklistTemplates":[],"ListGroups":[],"QuickBuckets":[],"Ports":[],"ScheduleTemplates":[],"Trash":[],"Sire":{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}},"Ui":{"SelectedMainTabIndex":0,"ShowShortcutBar":true,"QuickViewPinIds":[],"TabColors":{},"TabOrder":[],"SortAZ":{},"GroupExpanded":{},"CrewTableColumns":[],"CrewTableShownColumns":[]},"SchemaVersion":1}`.

### 4.11 `settings.json` — `AppSettings` value + `SettingsStore` (01 §4.3; §5.4)

`public struct AppSettings: Sendable, Equatable` (value snapshot of the file; order = emission order):
`currentDataFile: String? ← "CurrentDataFile"`, `passwordHash: String? ← "PasswordHash"`,
`passwordSalt: String? ← "PasswordSalt"`, `googleDriveFolder: String? ← "GoogleDriveFolder"`,
`syncOnSave: Bool ← "SyncOnSave"`, `darkMode: Bool ← "DarkMode"`, `folderBuilderBase: String? ← "FolderBuilderBase"`,
`sharedSaveFile: String? ← "SharedSaveFile"`, `encryptLocalData: Bool ← "EncryptLocalData"`,
`geminiApiKey: String? ← "GeminiApiKey"` (Mac never sets it; preserved verbatim), `appIdentity: String? ← "AppIdentity"`,
`textOnlyExport: Bool ← "TextOnlyExport"`, `extra: JSONObject` (preserved and merged; Flash Sync writes unknown keys).
Missing booleans read as `false`; a boolean is written when it is set (key-level merge, §6.2 — only the changed
key is touched); nil strings are omitted. **Per-key read tolerance:** a key whose value has the wrong JSON type
(S09 `"DarkMode":"true"`) reads as that key's default *for that key only*; the other keys still load, and the raw
value is preserved untouched on write unless that very key is set. `public init(json: JSONObject)` is the only
decoder (never throws).

### 4.12 `source.json` — `BundleSource` (01 §4.4)

`public struct BundleSource: Sendable, Equatable` (nonisolated value type; does not adopt `JSONModel`):
`identity: String = "" ← "Identity"`, `machine: String = "" ← "Machine"`,
`writtenUtc: NetDateTime = NetDateTime(ticks: 0, kind: .unspecified) ← "WrittenUtc"` (C# `default(DateTime)`;
written `"0001-01-01T00:00:00"`), `lastModified: NetDateTime? ← "LastModified"` (omit-nil),
`dataOnly: Bool = false ← "DataOnly"`, `extra`. `public init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError)`
and `public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject` follow the §3.8 rules (dates via
`builder.date`, so a literal `+`). Computed `writtenLocal` (`writtenUtc.toLocalTime()` as `yyyy-MM-dd HH:mm`, `""`
when `writtenUtc.ticks == 0`). Rule for peeks: **any** decode error (e.g. `"DataOnly":"true"`) → `peekBundleSource`
returns nil, so `IsDataOnlyBundle` falls back to the `files/` test (01 §3.10). Goldens B07 (01 §4.4 literal,
byte-exact) and B08 (defaults) are F1's.

---------------------------------------------------------------------------------------------------------------------

## 5. AppStore — the repository (core F1, domain operations F2)

### 5.1 Object graph the UI observes

```
AppEnvironment (AA/App, F3, @Observable, injected with .environment(env))
 ├── store: AppStore                 ── data: AppData ── equipment/tasks/procedures/vessels … (all @Observable)
 │                                    ├── generation, isDirty, suspendSaving, lastSaveError, detachedItemIDs
 │                                    └── events: saved, dataReplaced, trashChanged
 ├── dataStore: DataStore (= store.dataStore) ── settings: SettingsStore (@Observable)
 ├── locks: ItemLockService (@Observable; session-unlocked item ids)
 ├── passwords: PasswordService (@Observable; app password session state)
 ├── navigator: Navigator, status: StatusCenter, router: CommandRouter, flush: EditorFlushCenter (F3)
 └── sharedSave: SharedSaveCoordinator (W-PERSIST), driveSync: DriveSyncCoordinator (W-DRIVE)
```
Views read `@Environment(AppEnvironment.self) private var env` and bind directly to model objects
(`@Bindable var task: TaskItem`). Mutation entry points:
1. **Field edits** — mutate the observable model in place, then call `env.store.markDirty()` (debounced) or
   `env.store.markDirty(); try env.store.flushIfDirty()` (immediate) exactly where the owning spec says
   ("Persist: MarkDirty / Save / Flush").
2. **Domain operations** — call the `AppStore` methods of §5.3 (F2), which mutate, log and mark dirty per 02; the
   caller then saves when the spec says `Save()`.
3. **Whole-data replacement** — only F3 (`loadDataAndInitUI`) and W-PERSIST/W-FLASH/W-DRIVE through
   `env.loadDataAndInitUI(...)` (§7.9) call `store.replaceData(_:reason:)`.

### 5.2 `AppStore` core — `AACore/Store/AppStore.swift` (F1)

F1 owns the whole save pipeline and its data-integrity guarantees: 01 DATA-025 (750 ms debounce), DATA-031
(`LastModified` stamping), 02 REPO-001…008 and REPO-003a (single root, debounce, confirmed save with 15 s timeout,
ordered write chain, stamp rollback, `suspendSaving`, detach, `saved` event, `flushIfDirty`) and 03 SHELL-051.
REPO-005's *caller* is F3 (`loadDataAndInitUI` sets `suspendSaving`).

```swift
public enum DataReplaceReason: Sendable, Equatable {
    case initialLoad, reloadFromDisk, importFile, importBundle, sharedSavePull, driveImport, flashSyncApply, other(String)
}
public enum AppStoreError: Error, LocalizedError, Sendable {
    case timeout(path: String)          // "Timed out writing {path}." (02 REPO-003)
    case serialization(String)          // incl. depth > 64 and Int32 overflow (§3.8 rule 2)
    case write(String)
    case pausedByGuard                  // the DataFileWriteGuard refused the write (01 DATA-180); nothing written
    case writesPaused                   // save() while pauseWrites is in effect
}
/// DATA-180 hook (01 §MP.3.4). F1 declares it and calls it; W-PERSIST implements it (DataFileFingerprint) and
/// installs it via `store.writer.writeGuard` / `dataStore.writeGuard` at launch (F3 wiring, §7.1).
public protocol DataFileWriteGuard: AnyObject, Sendable {
    /// Called on the writer queue right before the atomic write of `url`; false → the job fails `.pausedByGuard`.
    func shouldWrite(to url: URL) -> Bool
    /// Called on the writer queue after the rename, with the exact bytes now on disk (after encryption).
    func didWrite(to url: URL, bytes: Data)
    /// Called after every load of the active data file, with the raw bytes read (before decryption).
    func didLoad(from url: URL, bytes: Data)
}
public enum WritePauseReason: Sendable, Equatable { case externalChange, readOnly, other(String) }
@MainActor public final class EventHub<Payload> {                 // AACore/Foundation/EventHub.swift
    public init()
    @discardableResult public func subscribe(_ handler: @escaping @MainActor (Payload) -> Void) -> EventSubscription
    public func send(_ payload: Payload)
    public func removeAll()
}
@MainActor public final class EventSubscription {
    public func cancel()
    isolated deinit { cancel() }        // Swift 6.2 isolated deinit (§2.2); a plain deinit cannot reach the hub
}

@MainActor @Observable
public final class AppStore {
    public init(dataStore: DataStore, data: AppData, clock: AppClock = SystemClock())
    public let dataStore: DataStore
    public let clock: AppClock
    public private(set) var data: AppData
    public private(set) var generation: Int                // +1 on every replaceData
    public private(set) var isDirty: Bool
    public var suspendSaving: Bool                         // safe mode / read-only instance (02 REPO-005)
    public private(set) var writesPaused: Bool             // DATA-180 pause: debounce, save(), 5-min autosave,
                                                           // shared push and close-save all refuse to write
    public private(set) var writePauseReason: WritePauseReason?
    public private(set) var lastSaveError: String?
    public let writer: PersistenceWriter                   // exposed so F3 can install `writer.writeGuard`
    public var detachedItemIDs: Set<UUID> = []             // item windows open (04 §6.7, OC-42)
    public var debounceInterval: Duration = .milliseconds(750)
    public static let saveTimeout: TimeInterval = 15

    @ObservationIgnored public let saved = EventHub<Void>()                      // REPO-007 (after every successful save)
    @ObservationIgnored public let dataReplaced = EventHub<DataReplaceReason>()  // reload/import/apply notification
    @ObservationIgnored public let trashChanged = EventHub<Void>()               // router's pendingUndoCount refresh

    public func pauseWrites(reason: WritePauseReason)      // DATA-180 step 1 (idempotent; model stays dirty)
    public func resumeWrites()                             // after Keep Mine / Use Theirs / Resume Editing
    public func markDirty()                                // REPO-002 (algorithm §2.3)
    public func save() throws(AppStoreError)               // REPO-003: stamp, serialise on main, enqueue, wait ≤15 s,
                                                           // restore stamp on failure; clears dirty + fires saved on success;
                                                           // returns silently when suspendSaving; throws
                                                           // .writesPaused while paused
    public func flushIfDirty() throws(AppStoreError)       // REPO-008
    public func replaceData(_ newData: AppData, reason: DataReplaceReason)  // REPO-001/006: cancels debounce, clears
                                                           // dirty, bumps generation, sends dataReplaced
    public func cancelPendingAutosave()                    // REPO-006 detach part (used before quit/reload)
    public func waitForQueuedWrites(timeout: TimeInterval) -> Bool   // quit pipeline
    public func encodedSnapshot() throws(AppStoreError) -> Data      // SerializeForSave of the live model (no stamp)
}
```
`PersistenceWriter` (`AACore/Store/PersistenceWriter.swift`, F1): `public final class PersistenceWriter: @unchecked Sendable`
with a serial `DispatchQueue(label: "aa.data-writer")`;
`public func enqueue(_ job: WriteJob, completion: @escaping @Sendable (Result<Void, Error>) -> Void) -> DispatchWorkItem`;
`public var writeGuard: DataFileWriteGuard?` (lock-protected; nil = no check);
`public struct WriteJob: Sendable { public var bytes: Data; public var url: URL; public var encryptionKey: SymmetricKey?; public init(bytes:url:encryptionKey:) }`.
Per job, on the writer queue: `writeGuard?.shouldWrite(to:)` (false → `.pausedByGuard`, nothing written) →
encrypt when a key is given (`LocalEncryption`) → `AtomicWrite.write` → `writeGuard?.didWrite(to:bytes:)`. The
writer also exposes `public func runOnWriterQueue(_ work: @escaping @Sendable () -> Void)` so W-PERSIST's watcher runs its
check on the same queue and can never race a write (01 §MP.3.4). Every other writer of the active data file
(`DataStore.writeLocalDataFile`, `adoptExternalDataFile`, conflict resolution, encryption toggle) goes through
`DataStore`, which calls the same guard (§6.2).

### 5.3 Domain operations — F2 (`AACore/Store/AppStore+*.swift`, placeholders created by F1)

All `@MainActor`, all on `AppStore`. None of them saves unless stated; they `markDirty()` exactly where 02 says.

```swift
// AppStore+Lookups.swift — 02 §2.B, §3.24
extension AppStore {
    public func allItems() -> [HierarchyItem]                          // REPO-010: E, T, P, V order
    public func items(of kind: ItemKind) -> [HierarchyItem]
    public func item(id: UUID) -> HierarchyItem?                       // REPO-011 FindById (first wins; top level only)
    public func task(id: UUID) -> TaskItem?                            // recursive incl. subtasks (Board/Planner/editors)
    public func parentTask(of subtaskID: UUID) -> TaskItem?            // nil for top level
    public func topLevelTask(containing taskID: UUID) -> TaskItem?
    public func step(id: UUID) -> (step: ChecklistStep, owner: StepOwner)?
    public func component(id: UUID) -> (component: Component, equipment: Equipment)?
    public func crewMember(id: UUID) -> CrewMember?
    public func template(id: UUID) -> ChecklistTemplate?
    public func bucket(id: UUID) -> QuickBucket?
    public func vessel(id: UUID) -> Vessel?
    public func topLevelOwner(ofAnyID id: UUID) -> (owner: HierarchyItem, childID: UUID?)?  // search/navigation
    public func allContainers() -> [Container]                         // REPO-012 order
    public func allJobs() -> [any SchedulableJob]                                 // REPO-013 order
    public func jobOwnerLabel(_ job: any SchedulableJob) -> String                // "Task"/"Subtask"/"Procedure"/"Step"/"Crew" helper
    public func label(for id: UUID) -> String                          // REPO-014 "(missing)" | "[Kind] Name"
    public nonisolated static func kindLabel(_ kind: ItemKind) -> String   // REPO-015
}
public enum StepOwner: Sendable, Hashable { case procedure(UUID), crew(UUID) }   // templates hold
// ChecklistTemplateItem values, never ChecklistStep, so no `.template` case exists

// AppStore+Relations.swift — 02 §2.C
extension AppStore {
    public func addRelation(_ a: HierarchyItem, _ b: HierarchyItem)        // REPO-020
    public func removeRelation(_ a: HierarchyItem, _ b: HierarchyItem)
    public func relatedItems(of item: HierarchyItem) -> [HierarchyItem]     // REPO-021
    public func referencedBy(_ target: HierarchyItem) -> [HierarchyItem]    // REPO-022
    public func purgeReferences(to deletedID: UUID)                         // REPO-029, widened per DECISIONS 02 Q-3:
                                                                            // also nested subtasks' RelatedIds, crew step links,
                                                                            // ScheduleEntry.RefId, QuickViewPinIds, Selected*Id,
                                                                            // MapFocusedItemId (record in Deviations/F2.md)
    public func linkProcedures(_ ids: [UUID], to equipment: Equipment)      // REPO-023 replace semantics (callers save)
    public func linkTasks(_ ids: [UUID], to equipment: Equipment)           // REPO-024
    public func linkTasks(_ ids: [UUID], to step: ChecklistStep)            // REPO-027
    public func linkEquipment(_ ids: [UUID], to step: ChecklistStep)
}

// AppStore+Creation.swift — 02 REPO-035 catalogue (each appends at the end, logs as the table says)
extension AppStore {
    @discardableResult public func createItem(kind: ItemKind, name: String? = nil) -> HierarchyItem   // "+ New": default names
                                                                            // "New Equipment/Area"/"New Task"/"New Procedure"/"New Vessel"
    @discardableResult public func createLinkedProcedure(named: String, for equipment: Equipment) -> Procedure   // REPO-025
    @discardableResult public func createLinkedTask(named: String, for equipment: Equipment) -> TaskItem        // REPO-026
    @discardableResult public func createLinkedTask(named: String, for step: ChecklistStep) -> TaskItem         // REPO-027
    @discardableResult public func addSubtask(named: String, to parent: TaskItem, log: Bool = true) -> TaskItem
    @discardableResult public func addStep(titled: String, to procedure: Procedure, log: Bool = true) -> ChecklistStep
    @discardableResult public func addComponent(named: String, to equipment: Equipment) -> Component        // not logged
    @discardableResult public func createTopLevelTask(named: String, logKind: String? = "Task") -> TaskItem   // Board/Ctrl+N
    @discardableResult public func createTopLevelProcedure(named: String) -> Procedure                      // Ctrl+N
    public func removeSubtask(_ subtask: TaskItem, from parent: TaskItem, log: Bool = true)   // hard, no scrub (REPO-036)
    public func removeStep(_ step: ChecklistStep, from procedure: Procedure, log: Bool = true)
    public func removeComponent(_ c: Component, from equipment: Equipment)
}

// AppStore+Log.swift — 02 §2.I
extension AppStore {
    public static let maxLogEntries = 10_000
    public func logAdded(kind: String, name: String?, detail: String? = "")      // REPO-090 (name trimmed / "(unnamed)")
    public func logRemoved(kind: String, name: String?, detail: String? = "")
    public func clearLog()                                                        // QUICK-154 (caller confirms + saves)
}

// AppStore+Trash.swift — 02 §2.H
extension AppStore {
    public static let maxTrashItems = 200
    public static let trashRetentionDays = 90
    /// REPO-070. TOP-LEVEL items only (Equipment/Tasks/Procedures/Vessels arrays); returns nil for anything else
    /// (e.g. a nested subtask — use trashSubtask).
    @discardableResult public func trash(_ item: HierarchyItem, batchID: UUID? = nil) -> TrashedItem?
    /// DECISIONS 02 Q-4 for Board subtask cards (REPO-081, VIEW-052). ItemType "Task"; the parent id is stored as
    /// the unknown member `"ParentTaskId"` on the TrashedItem (Windows ignores and preserves it). Removes the subtask
    /// from its parent, purges references to it and its descendants, logs like a task delete, sends trashChanged.
    /// Restore re-inserts it at the end of its parent's Subtasks if the parent still exists, else as a top-level task
    /// (what Windows' restore does with any "Task" entry). Recorded in Deviations/F2.md.
    @discardableResult public func trashSubtask(_ subtask: TaskItem, batchID: UUID? = nil) -> TrashedItem?
    @discardableResult public func trashItems(_ items: [HierarchyItem]) -> Int                            // REPO-072
    @discardableResult public func trash(_ member: CrewMember, batchID: UUID? = nil) -> TrashedItem       // REPO-071
    @discardableResult public func trashAllCrew() -> Int      // DECISIONS 09: "Clear all" = one Trash batch (undoable);
                                                              // logs Removed / "Crew" / "all {n} member(s)"
    public func restore(_ entry: TrashedItem) -> TrashItemType?                                           // REPO-076
    public func purge(_ entry: TrashedItem)                                                               // REPO-080
    public func emptyTrash()
    @discardableResult public func pruneTrash(now: NetDateTime? = nil) -> Bool                            // REPO-079
    public func pendingUndoCount() -> Int                                                                 // REPO-077
    public func undoLastDelete() -> [TrashItemType]                                                       // REPO-077
    public func hardDeleteTask(_ task: TaskItem)     // Board (REPO-081): recursive removal + purgeReferences; not logged
    public func hardDelete(_ item: HierarchyItem)    // Ctrl+N (REPO-081): logs Removed, removes, purges, unpins
}
// Every Trash mutation sends trashChanged. DECISIONS 02 Q-4: Board & Ctrl+N deletes route through the Trash on the
// Mac (W-PLAN and W-QUICK call trash(_:) for top-level items and trashSubtask(_:) for nested subtask cards instead of
// the hard-delete APIs; the hard-delete APIs stay for completeness).

// AppStore+Recurrence.swift — 02 §2.G
extension AppStore {
    public nonisolated static func nextOccurrence(from date: NetDateTime, _ r: RecurrenceKind) -> NetDateTime   // REPO-060;
                                                   // result is `.asCalendarDate` (.unspecified, DECISIONS Q-6, §3.4)
    @discardableResult public func reconcileRecurrences(today: CivilDate? = nil) -> Bool                          // REPO-061…063
}

// AppStore+Groups.swift — 02 §2.L
extension AppStore {
    public func groups(for kind: ItemKind) -> [ItemGroup]
    @discardableResult public func createGroup(kind: ItemKind, name: String) -> ItemGroup
    public func renameGroup(_ g: ItemGroup, to name: String)
    public func deleteGroup(_ g: ItemGroup)
    public func assign(_ items: [HierarchyItem], toGroup groupID: UUID?)
}
```

### 5.4 Save / autosave / sync hooks (who calls what)

| Trigger | Owner | Calls |
|---|---|---|
| any edit | every UI owner | `store.markDirty()` (+ `flushIfDirty()` where spec says Flush) |
| ⌘S / toolbar Save / File ▸ Save | F3 `env.doSave()` | `flush.flushAll()` → `captureUiState()` → `store.save()` → status `Saved HH:mm:ss` → `driveSync.queueSyncAfterExplicitSave()` (W-DRIVE, SHELL-121) |
| 5-min timer | F3 | flushAll → `if store.isDirty { save }` → status texts (REPO-009) → `driveSync.checkRemoteNewer(interactive: false)` |
| `store.saved` event | F3 subscribes | `store.reconcileRecurrences()` with `_reconciling` + safe-mode guards (REPO-063); W-QUICK due panel refresh |
| shared save timers/watcher | W-PERSIST `SharedSaveCoordinator` | 01 §3.12 state machine; calls F3 hooks (`SharedSaveHost`, §6.6) |
| quit / ⌘W on main / close button | F3 quit pipeline (SHELL-056) | stop sync → flushAll → captureUiState → `store.save()` (DECISIONS 03 Q-5: failure → Retry / Quit Anyway / Cancel) → `sharedSave.pushOnCloseIfNeeded()` → `store.waitForQueuedWrites` → terminate |
| import/reload/apply | F3 `env.loadDataAndInitUI` | `DataStore.load()` → `store.replaceData` → safe-mode flag → `ui.copyPerDeviceValues` |
| outside change to the active data file (DATA-180) | W-PERSIST `DataFileFingerprint` (the `DataFileWriteGuard`) | refusal → `store.pauseWrites(.externalChange)` → `DataFileConflictHost.presentConflict` (F3's AppEnvironment, §6.6) → Keep Mine / Use Theirs / Review / Stop Editing → `store.resumeWrites()` or reload |
| launch wiring | F3 (`AppDelegate`, after `DataStore` exists) | `store.writer.writeGuard = dataStore.writeGuard = DataFileFingerprint(...)` (W-PERSIST type); `InstanceGuard.acquireExternal` when `CurrentDataFile` is outside AppFolder |

---------------------------------------------------------------------------------------------------------------------

## 6. Every other AACore contract, grouped by owner

Anything consumed across agents is fixed here. Owners may add further public API inside their own folders; they
must not change these signatures (use `Docs/Requests/<agent>.md`, §12.3).

### 6.1 F1 — Foundation (`AACore/Foundation/`)

```swift
public enum Identifiers {                                    // one place for every Mac-private identifier (OC-07)
    public static let bundleID = "com.eriskay.aa"
    public static let logSubsystem = "com.eriskay.aa"
    public static let utBundle = "com.eriskay.aa.bundle"        // .aaz, conforms to public.zip-archive
    public static let utSchedule = "com.eriskay.aa.schedule"    // aasched.json (declared only; never in panels)
    public static let utXaml = "com.eriskay.aa.xaml"            // pasteboard, conforms to public.data
    public static let utTaskRef = "com.eriskay.aa.task-ref"     // Board drag
    public static let utJobRef = "com.eriskay.aa.job-ref"       // Planner drag
    public static let utItemRef = "com.eriskay.aa.item-ref"     // sidebar → group drag, relationship drags
    public static let instanceRequestNotification = "com.eriskay.aa.InstanceRequest"
    public static let reminderNotificationID = "aa.reminder"    // OC-33
    public enum Keychain {                                      // 01 DATA-215
        public static let localDataKey = (service: "AA.LocalDataKey", account: "v1")
        public static let googleTokenKey = (service: "AA", account: "google-token-key")
        public static let gemini = (service: "com.eriskay.aa.gemini", account: "GeminiApiKey")
    }
}
public enum SceneID: String, Sendable {                      // 01 DATA-220, OC-32
    case main, splash, login, item, quickWork = "quick-work", search, activityLog = "activity-log",
         unitConverter = "unit-converter", folderBuilder = "folder-builder", dateCalculator = "date-calculator",
         flashSync = "flash-sync", crewTable = "crew-table", shortcuts, settings, about,
         bootstrap,                                           // 1×1 transparent helper scene (§7.1), never shown
         due, switcher                                        // NSPanels (logical ids for the snapshot hook)
}
public extension UTType { static var aaBundle: UTType; static var aaXaml: UTType; static var aaTaskRef: UTType;
                          static var aaJobRef: UTType; static var aaItemRef: UTType; static var xlsx: UTType }

public enum AAResources {                                    // 03 BD.3.4 — never traps
    public static func url(name: String, ext: String) -> URL?   // Bundle.main, then AA_AACore.bundle / AA_AA.bundle
    public static func data(name: String, ext: String) -> Data?
}
public enum NetText {                                        // .NET string semantics
    public static func isBlank(_ s: String?) -> Bool          // char.IsWhiteSpace set (06 BUILD-A23)
    public static func trim(_ s: String) -> String
    public static func equalsIgnoreCase(_ a: String, _ b: String) -> Bool        // OrdinalIgnoreCase
    public static func containsIgnoreCase(_ s: String, _ q: String) -> Bool
    public static func compareIgnoreCase(_ a: String, _ b: String) -> ComparisonResult
    public static func compareCulture(_ a: String, _ b: String) -> ComparisonResult  // en_US (12 §6.12)
    public static func toLowerInvariant(_ s: String) -> String
}
public enum WindowsFileName {
    public static let invalidCharacters: Set<Character>      // " < > | : * ? \ / and U+0000–U+001F
    public static func sanitize(_ name: String, replacement: Character = "_", fallback: String) -> String
    public static func safeIdentity(_ identity: String) -> String   // 03 §3.8 SafeIdentity ("AA" when empty)
}
public struct ARGB: Sendable, Hashable {
    public var a, r, g, b: UInt8
    public init(a: UInt8 = 0xFF, r: UInt8, g: UInt8, b: UInt8)   // explicit public init (§2.2; F3 swatches, AAColor)
}
public enum WpfColor {                                        // 03 §6.7 colour parsing (tabs, cards, XAML brushes)
    public static func parse(_ text: String?) -> ARGB?        // #RGB #ARGB #RRGGBB #AARRGGBB, known WPF colour names, sc#
    public static func hexRRGGBB(_ c: ARGB) -> String         // "#RRGGBB" uppercase
    public static func hexAARRGGBB(_ c: ARGB) -> String
    public static func luma(_ c: ARGB) -> Double              // 0.299R+0.587G+0.114B
}
public final class MacPreferences: @unchecked Sendable {     // UserDefaults "com.eriskay.aa" (01 §6.8, BD.4.9)
    public static let shared: MacPreferences
    public init(defaults: UserDefaults)
    public struct Key: Hashable, Sendable { public let rawValue: String; public init(_ raw: String) }
    public func bool(_ k: Key, default: Bool) -> Bool;   public func set(_ v: Bool, _ k: Key)
    public func string(_ k: Key) -> String?;             public func set(_ v: String?, _ k: Key)
    public func data(_ k: Key) -> Data?;                 public func set(_ v: Data?, _ k: Key)
    public func codable<T: Codable>(_ k: Key, as: T.Type) -> T?; public func setCodable<T: Codable>(_ v: T?, _ k: Key)
}
// Owners declare their keys in their own files, prefixed (§12.2): raw value "aa.<area>.<name>", static name
// <area><Name>: extension MacPreferences.Key { static let persistPathMappings = Key("aa.persist.pathMappings") }
// (existing documented raw values such as "aa.pathMappings", "aa.appearance", "aa.menuBarExtra" keep their text.)
public enum AALog { public static func logger(_ category: String) -> Logger }   // os.Logger(subsystem:category:)
public enum CRC32 { public static func checksum<D: DataProtocol>(_ data: D, seed: UInt32 = 0) -> UInt32 }  // FLASH-061 (13 §3.2)
public enum RawDeflate {                                      // FLASH-062 (13 §3.3) — COMPRESSION_ZLIB = raw DEFLATE
    public static func compress(_ bytes: [UInt8]) throws -> [UInt8]
    public static func inflate(_ bytes: [UInt8], expectedLength: Int?) throws -> [UInt8]
}
public enum MacKeyStrings {                                   // 03 §6.5.1.9 — pure 20-row table, implemented by F1
    public static func render(_ windowsText: String) -> String //  (F2's BatchDelete texts and F3's registry use it)
}
/// Placeholder bookkeeping (§11) for wave-owned AACore contracts (F1/F2/F3 are merged before Stage W starts).
/// `ContractStatus.isImplemented(.wRich)` reads `ContractStatus.wRichImplemented`, a `static let` that F1 declares
/// in a one-line file INSIDE THE OWNER'S FOLDER (`Sources/AACore/RichText/RichTextContractStatus.swift`:
/// `extension ContractStatus { public static let wRichImplemented = false }`). The owner flips its own file to
/// `true` when its contracts are real; nobody edits another owner's file. Tests that need another owner's real
/// implementation use `@Test(.enabled(if: ContractStatus.isImplemented(.wRich)))` and are re-run in Stage V.
public enum ContractOwner: String, CaseIterable, Sendable {
    case wShell, wPersist, wRich, wCont, wFiles, wHier, wBuild, wPlan, wQuick, wCrew, wVessel, wPdf, wSire, wFlash, wDrive
}
public enum ContractStatus { public static func isImplemented(_ owner: ContractOwner) -> Bool }   // switch over the lets
```
(13 §6.1 names the CRC/DEFLATE folder `AACore/Util`; they live in `AACore/Foundation` — same types, one copy.)

### 6.2 F1 — Persistence (`AACore/Persistence/`)

```swift
public enum DataLoadError: Error, LocalizedError, Sendable {
    case unreadable(String)            // locked / IO / mid-write
    case windowsEncrypted              // "AAENC1\n" DPAPI file → Mac safe-mode wording (01 §6.5)
    case macKeyUnavailable             // "AAENCM1\n" but no Keychain key (or denied)
    case parse(JSONParseError)
    case model(JSONModelError)
}
@MainActor @Observable public final class DataStore {
    public init(appFolder: URL, secrets: SecretStore = KeychainSecretStore(), clock: AppClock = SystemClock())
    public let appFolder: URL
    public var filesFolder: URL { get }              // appFolder/files
    public var defaultDataFile: URL { get }          // appFolder/data.json
    public var settingsFile: URL { get }             // appFolder/settings.json
    public var googleClientSecretFile: URL { get }   // google_client_secret.json
    public var googleTokenFolder: URL { get }        // google-token/
    public var crashLogFile: URL { get }             // crash.log
    public var flashBaselineFile: URL { get }        // qrsync-baseline.json
    public var instanceLockFile: URL { get }         // .aa.lock (W-PERSIST uses; never deleted)
    public private(set) var currentDataFile: URL
    public let settings: SettingsStore
    public let secrets: SecretStore
    public let clock: AppClock
    public private(set) var lastLoadFailed: Bool
    public private(set) var lastLoadError: DataLoadError?
    public private(set) var loadedNewerSchema: Int?
    public static let currentSchemaVersion = 1

    public var writeGuard: DataFileWriteGuard?                            // DATA-180 (installed by F3; §5.2)
    public func loadSettings()                                            // 01 §3.1 (+ CurrentDataFile fallback)
    public func load() -> AppData                                         // 01 §3.2; never throws; failure → empty + flags;
                                                                          // `null` root → empty AppData (not a failure);
                                                                          // calls writeGuard?.didLoad(from:bytes:)
    public func loadInBackground() async -> AppData                       // same; read+parse off-main, decode on main
    public func loadFrom(_ url: URL) throws(DataLoadError) -> AppData     // imports; migrate + normalise
    public func serializeForSave(_ data: AppData) throws(AppStoreError) -> Data   // 01 §3.3: normalise paths
                                                                          // (AttachmentStore), SchemaVersion = max(v,1), compact
    /// Save a Copy As JSON (plaintext, atomic). D-14 fixed (DECISIONS 01): serialises a COPY with
    /// LastModified = now and SchemaVersion = max(v,1) through the normal serializer; the live model's stamp and
    /// dirty state are untouched. Recorded in Deviations/F1.md.
    public func saveTo(_ data: AppData, url: URL) throws
    public func writeLocalDataFile(_ bytes: Data, to url: URL) throws     // synchronous; honours EncryptLocalData;
                                                                          // guard check before, didWrite after (§5.2)
    public func setCurrentDataFile(_ url: URL)                            // persists CurrentDataFile
    public func adoptExternalDataFile(_ source: URL, copyIntoAppFolder: Bool) throws -> URL   // DECISIONS 01 Q-5
    public func isUnderAppFolder(_ url: URL) -> Bool
    /// Key only for files inside appFolder and only when EncryptLocalData is on. The key is read from the
    /// SecretStore ONCE per session and cached in memory (never a Keychain call per autosave); the cache is cleared
    /// when the setting is turned off or the key is replaced.
    public func localEncryptionKeyIfEnabled(for url: URL) -> SymmetricKey?
    public nonisolated static func readDataBytes(_ url: URL, key: SymmetricKey?) throws(DataLoadError) -> Data  // BOM strip,
                                                                          // decrypt; the JSON parse that follows uses
                                                                          // invalidUTF8: .replace (01 §3.4, §3.2)
}
@MainActor @Observable public final class SettingsStore {
    public init(fileURL: URL, secrets: SecretStore)
    public private(set) var values: AppSettings
    public var appIdentity: String { get }                                // values.appIdentity ?? defaultIdentity()
    public var foreignPathKeys: [String] { get }                          // Windows-style paths present (01 §6.8 banner)
    public var isWriteGated: Bool                                         // true → setters update memory only (01 §MP.3.5)
    public func reload()
    public func setCurrentDataFile(_ path: String?)
    public func setPassword(hash: String, salt: String)
    public func setGoogleDriveFolder(_ path: String)
    public func setSyncOnSave(_ on: Bool)
    public func setTextOnlyExport(_ on: Bool)
    public func setDarkMode(_ on: Bool)
    public func setEncryptLocalData(_ on: Bool)
    public func setAppIdentity(_ identity: String?)
    public func setFolderBuilderBase(_ path: String)
    public func setSharedSaveFile(_ path: String?)
    /// Flash Sync (13 §3.12, DECISIONS 13 Q-5 "unreadable settings = error"): returns `{}` ONLY when the file is
    /// absent; a `null` root reads as `{}`; IO errors, parse errors (after the DATA-182 retry, 3 × 50 ms) or any
    /// other non-object root throw `DataLoadError.unreadable(...)`.
    public func readRawTree() throws(DataLoadError) -> JSONObject
    /// Flash Sync apply: writes the whole tree compact and ATOMICALLY (AtomicWrite). Refuses (throws
    /// `.unreadable`) when the current file exists but is unreadable, so an apply can never drop PasswordHash/Salt,
    /// CurrentDataFile or unknown keys (D-18). Performs NO reload — the caller calls `reload()` afterwards.
    public func writeRawTree(_ tree: JSONObject) throws(DataLoadError)
    /// Status text DATA-182 posts when a setter could not write (exact):
    public static let unreadableStatus = "Couldn't update settings.json (it is unreadable) — this change applies until AA quits."
    /// Last setter failure (nil after a successful write); F3/W-SHELL post `unreadableStatus` when it is set.
    public private(set) var lastWriteRefused: Bool
    public nonisolated static func defaultIdentity() -> String            // Computer Name → hostName → "AA" (DECISIONS 14)
}
```
Every setter performs a **key-level merge write** (01 DATA-150/DATA-182), exactly:
1. read and parse the current file, retrying up to 3 times, 50 ms apart, if it can't be read (a missing file is
   an empty object, not an error);
2. set or remove that one key (or the joint set below), keeping every other key and unknown member;
3. write the keys in Windows order: known keys in 01 §4.3 declaration order, then unknown keys in their existing
   order;
4. write compact and atomically (AtomicWrite).
If the file still can't be parsed, **do not write**: keep the value in memory (`values` updated), set
`lastWriteRefused`, and the caller posts `SettingsStore.unreadableStatus`. Joint writes happen in one
read-modify-write: `PasswordHash`+`PasswordSalt` (`setPassword(hash:salt:)`), and `CurrentDataFile` after a bundle
import or Flash Sync apply. Nothing is written while the app is in a read-only/external-conflict write gate (01
§MP.3.5; `settings.isWriteGated`, set by F3 from `store.suspendSaving`/`writesPaused`). Per-key read tolerance per
§4.11. `GeminiApiKey` is never written by the Mac (value preserved verbatim, DECISIONS 12). F1 vectors: 01 MP.7.6
S-1…S-4.

```swift
public enum AtomicWrite {                                     // 01 DATA-029, §6.4 (F_FULLFSYNC, same-dir temp, rename)
    public static func write(_ data: Data, to url: URL) throws
    public static func tempURL(for url: URL) -> URL           // "<path>.<32 lowercase hex>.tmp"
}
public enum LocalEncryption {                                 // 01 DATA-070…072, §6.5
    public enum FileClass: Sendable { case plain, mac, windowsDPAPI }
    public static let macMagic: Data                          // "AAENCM1\n" (8 bytes)
    public static let windowsMagic: Data                      // "AAENC1\n" (7 bytes)
    public static func classify(_ bytes: Data) -> FileClass
    public static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> Data   // magic ‖ AES.GCM combined, AAD = magic
    public static func decrypt(_ blob: Data, key: SymmetricKey) throws -> Data
    public static func key(secrets: SecretStore, create: Bool) throws -> SymmetricKey?
}
public enum SchemaMigration { @MainActor public static func migrate(_ data: AppData) }   // 01 DATA-023 / 02 REPO-064
```

### 6.3 F1 — Crypto (`AACore/Crypto/`)

```swift
public enum PBKDF2 { public static func sha256(password: String, salt: Data, iterations: Int, length: Int) -> Data }
public enum AESCBC { public static func encrypt(_ d: Data, key: Data, iv: Data) throws -> Data
                     public static func decrypt(_ d: Data, key: Data, iv: Data) throws -> Data }       // PKCS#7
public enum HMACSHA256 { public static func mac(_ d: Data, key: Data) -> Data }
public enum ConstantTime { public static func equals(_ a: Data, _ b: Data) -> Bool }
public enum SecureRandom { public static func bytes(_ count: Int) -> Data }
public enum NetBase64 { public static func encode(_ d: Data) -> String
                        public static func decode(_ s: String) -> Data? }        // ignores whitespace like .NET
public enum PasswordHashing {                                // 01 §3.13, §4.8
    public static let iterations = 100_000, saltSize = 16, keySize = 32
    public static let masterPassword = "redemption"          // DECISIONS Q-1: keep exactly
    public static func newSalt() -> Data
    public static func hash(password: String, salt: Data) -> Data            // 32 bytes
}
public enum LegacyBodyCrypto {                               // 01 §4.7 byte-exact "enc:" blobs
    public static let prefix = "enc:"
    public static func isEncrypted(_ text: String) -> Bool
    public static func decrypt(_ blob: String, password: String, saltBase64: String) -> String?     // nil: never guess
    public static func encrypt(_ xaml: String, password: String, saltBase64: String, iv: Data? = nil) -> String
}
public protocol SecretStore: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}
/// File-based login keychain, generic password items: NO kSecUseDataProtectionKeychain and NO kSecAttrAccessible
/// (both need keychain-access-groups / application-identifier entitlements that ad-hoc signing and `swift run`
/// cannot provide → errSecMissingEntitlement -34018). Not synced (no kSecAttrSynchronizable). Note for README/tests:
/// the keychain ACL is bound to the code signature, so a rebuild with a new cdhash may show one "allow access"
/// prompt again. Callers cache what they read (DataStore caches the local-data key per session, §6.2).
public struct KeychainSecretStore: SecretStore { public init() }
public final class InMemorySecretStore: SecretStore, @unchecked Sendable { public init() }

public enum PasswordError: Error, Sendable { case tooShort, mismatch, wrongCurrentPassword }
@MainActor @Observable public final class PasswordService {         // app password (01 §H)
    public init(settings: SettingsStore)
    public var hasPassword: Bool { get }
    public private(set) var isUnlocked: Bool
    public func verify(_ password: String) -> Bool                    // master or hash
    public func unlock(_ password: String) -> Bool
    public func lock()                                                // Tools ▸ Lock Now (with ItemLockService.relockAll)
    public func setPassword(_ new: String, current: String?) throws(PasswordError)   // DECISIONS 01 Q-4
    public func decryptLegacyBody(_ blob: String) -> String?          // uses the session password (CONT-007)
}
@MainActor @Observable public final class ItemLockService {         // 01 §I, 04 §F
    public init()
    public private(set) var unlockedIDs: Set<UUID>
    public func isGated(_ item: HierarchyItem) -> Bool                // protected && not unlocked this session
    public func protect(_ item: HierarchyItem, password: String, hint: String?)
    public func removeProtection(_ item: HierarchyItem)
    public func tryUnlock(_ item: HierarchyItem, password: String) async -> Bool      // PBKDF2 off-main
    public func relock(_ id: UUID)
    public func relockAll()
    public nonisolated static func verify(password: String, hashBase64: String, saltBase64: String) -> Bool
}
```

### 6.4 F1 — ZIP and XLSX writer (`AACore/Zip/`, `AACore/Xlsx/`)

```swift
public enum ZipError: Error, Sendable { case notAZip, corrupt(String), unsafePath(String), crcMismatch(String),
                                        unsupported(String), io(String) }
public struct ZipEntryInfo: Sendable, Hashable {
    public let name: String; public let isDirectory: Bool; public let method: UInt16
    public let compressedSize: UInt64; public let uncompressedSize: UInt64; public let crc32: UInt32
    public let modified: Date?; public let isUTF8: Bool
}
public final class ZipReader {                               // 01 §6.7: Deflate+Stored, Zip64, data descriptors, CP437 names
    public init(url: URL) throws(ZipError)
    public init(data: Data) throws(ZipError)
    public var entries: [ZipEntryInfo] { get }
    public func entry(named name: String) -> ZipEntryInfo?   // case-sensitive
    public func data(for entry: ZipEntryInfo) throws(ZipError) -> Data
    public func extract(_ entry: ZipEntryInfo, to url: URL) throws(ZipError)          // streaming
    public func extractAll(to folder: URL, skip: (String) -> Bool = ZipReader.isFinderMetadata) throws(ZipError)
    public static func isFinderMetadata(_ name: String) -> Bool   // .DS_Store, ._*, __MACOSX/, Icon\r
}
public final class ZipWriter {                               // Deflate, UTF-8 flag for non-ASCII, Zip64 when needed
    public init(url: URL) throws(ZipError)
    public func addFile(named name: String, from source: URL, modified: Date?) throws(ZipError)  // streaming
    public func addData(_ data: Data, named name: String, modified: Date?, compress: Bool = true) throws(ZipError)
    public func addDirectory(named name: String) throws(ZipError)                                  // "files/"
    public func finish() throws(ZipError)
}
```
The XLSX **reader** is F2's (`AACore/XlsxRead/`, §6.5).
XLSX writer (`AACore/Xlsx/XlsxWriter.swift`):
```swift
public enum XlsxCellValue: Sendable, Hashable { case text(String), number(Double), empty }
public struct XlsxColumnSpec: Sendable {
    public var width: Double?; public var textFormat: Bool = false                                   // numFmtId 49
    public init(width: Double? = nil, textFormat: Bool = false)
}
public struct XlsxSheetSpec: Sendable {
    public var name: String; public var columns: [XlsxColumnSpec]; public var boldHeader: Bool
    public var header: [String]; public var rows: [[XlsxCellValue]]
    public init(name: String, columns: [XlsxColumnSpec], boldHeader: Bool, header: [String], rows: [[XlsxCellValue]])
}
public enum XlsxWriter {
    public static func write(to url: URL, sheetName: String, headers: [String], rows: [[String]]) throws  // 09 §3.10/§4.10 bytes
    public static func write(to url: URL, sheet: XlsxSheetSpec) throws                                     // 10 §6.6 extensions
    public static func writePackage(to url: URL, parts: [(path: String, data: Data)]) throws              // raw parts (11 §4.5)
    public static func sanitizeSheetName(_ name: String, fallback: String) -> String                       // OC-22 order
    public static func xmlEscape(_ text: String) -> String                                                 // strips XML-illegal chars
}
```

### 6.5 F2 — Services (`AACore/Services/`, `AACore/XlsxRead/`)

Shared parsing that must exist before Stage W (so no wave worktree ever tests against a stub) is F2's:
```swift
// AACore/Services/NetDateParser.swift — 09 §6.3 CrewMember.ParseDate (.NET DateTime.TryParse emulation, invariant +
// en-US reference culture), shared by F1 models (CrewMember.parseDate, ShipJob.dueDateValue), XlsxRender B+,
// W-CREW and W-VESSEL. Vectors: 09 §7.1 and the B+ column of 10 §X.8.1. `today` resolves time-only/year-less input.
public enum NetDateParser {
    public static func parse(_ text: String?, zone: TimeZone = .current, today: CivilDate? = nil) -> NetDateTime?
}
// AACore/Services/CrewText.swift — 09 §3.2 CrewText.Norm (used by W-CREW's converter and W-VESSEL's readers)
public enum CrewText { public static func norm(_ s: String) -> String }

// AACore/XlsxRead/ — exactly the module of 10 Addendum §X.7.1 (`XlsxWorkbook`, `XlsxWorksheet`, `XlsxCell`,
// `XlsxValue`, `XlsxStyles`/`NumberKind`, `ExcelSerial` as functions over the one `NetDateTime` (OC-56)), using F1's
// `NetNumberText`; all `Sendable` value types with explicit public inits. Parsing runs off-main.
public enum XlsxRender {                                     // X.4.11
    public static func compasCellString(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String  // A
    public static func shippalmCell(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String      // B
    public static func portsCell(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String         // C
    public static func getString(_ c: XlsxCell) -> String                                                      // VESSEL-325
    /// B+ = X.4.11 `ShippalmDates.excelDate(_ raw:, today:)` — `today` injected (time-only and year-less shapes).
    public static func shippalmExcelDate(_ text: String, today: CivilDate) -> String
}
/// Exactly 10 §X.4.13: `.gate` carries the VESSEL-301 message verbatim; `.message` carries the VESSEL-309 verbatim
/// messages; `.corrupt(detail:)` renders "The file could not be opened as an Excel workbook (.xlsx)." + detail
/// (VESSEL-302). Reader-level errors ("Could not find the Shippalm header row …", "The workbook is empty.") stay in
/// the owning readers (W-CREW, W-VESSEL).
public enum XlsxReadError: Error, LocalizedError, Sendable { case gate(String), message(String), corrupt(detail: String) }
```
F2 owns the X.8.1 columns Kind/A/B/B+/C and X.8.2–X.8.8 vectors; the C·D/C·T columns (`NormDate`/`NormTime` in
`PortCallReader`) are W-VESSEL's; X.8.9 (POC end-to-end) is W-VESSEL's.

```swift
public enum WorkRange {                                      // 02 REPO-050 (changed dates come out `.asCalendarDate`, §3.4)
    public static func coerce(start: NetDateTime?, deadline: NetDateTime?, editedStart: Bool)
        -> (start: NetDateTime?, deadline: NetDateTime?)
}
@MainActor public enum BatchDone {                           // REPO-042
    public static func setDone(_ item: AnyObject?, done: Bool) -> Bool
    public static func setDoneAll(_ items: [AnyObject], done: Bool) -> Int
}
@MainActor public enum BatchDeadline {                       // REPO-052
    public static func setDeadline(_ item: AnyObject?, date: NetDateTime?) -> Bool
    public static func setDeadlineAll(_ items: [AnyObject], date: NetDateTime?) -> Int
    public static func sharedDeadline(of items: [AnyObject]) -> NetDateTime??   // prefill: .some(nil) = all nil; nil = mixed
}
@MainActor public enum BatchDelete {                         // REPO-073…075
    public struct Description: Sendable, Equatable {
        public var equipment, tasks, procedures, vessels, descendants, withAttachments, linkedFromElsewhere, locked: Int
        public var total: Int { get }; public var isEmpty: Bool { get }
        public func kindBreakdown() -> String
    }
    public static func topLevel(_ selection: [AnyObject]) -> [HierarchyItem]
    public static func describe(_ selection: [AnyObject], store: AppStore,
                                isGated: (HierarchyItem) -> Bool) -> Description
    public static func confirmationMessage(_ d: Description, trashCount: Int) -> String   // Mac key strings (§6.5.1.9)
    public static func nothingToDeleteMessage(_ d: Description) -> (title: String, message: String)?
    @discardableResult public static func trashAll(_ selection: [AnyObject], store: AppStore,
                                                   isGated: (HierarchyItem) -> Bool) -> Int
    public static func statusAfterDelete(count: Int, firstName: String) -> String
}
public struct SearchField: Sendable, Hashable { public var kind: SearchHitKind; public var whereLabel: String
                                                public var text: String; public var childID: UUID? }
public enum SearchHitKind: String, Sendable { case item = "Item", component = "Component", subtask = "Subtask",
                                              step = "Step", file = "File" }
public struct SearchDocument: Sendable { public var ownerID: UUID; public var ownerKind: ItemKind
                                         public var ownerHeader: String; public var fields: [SearchField] }
public struct SearchHit: Sendable, Identifiable, Hashable {
    public var id: Int; public var ownerID: UUID; public var ownerKind: ItemKind; public var ownerHeader: String
    public var kind: SearchHitKind; public var whereLabel: String; public var snippet: String
    public var matchStart: Int; public var matchLength: Int; public var childID: UUID?
}
public enum SearchService {                                  // REPO-100…105 (+ OC-11: locked → Name and Tags only)
    public static let maxHits = 500
    @MainActor public static func makeDocuments(store: AppStore, isGated: (HierarchyItem) -> Bool) -> [SearchDocument]
    public static func search(_ docs: [SearchDocument], query: String,
                              isCancelled: @Sendable () -> Bool = { false }) -> [SearchHit]
    public static func makeSnippet(text: String, matchIndex: Int, matchLength: Int) -> (snippet: String, start: Int)
}
public enum QuickSwitcherScoring {                           // REPO-107, QUICK-104/105
    public struct Row: Sendable, Identifiable, Hashable { public var id: UUID; public var name: String
        public var kind: ItemKind; public var kindLabel: String; public var tags: [String]; public var description: String }
    @MainActor public static func rows(store: AppStore) -> [Row]
    public static func normalizeQuery(_ q: String) -> String
    public static func score(_ row: Row, query: String) -> Int
    public static func rank(_ rows: [Row], query: String, limit: Int = 80) -> [Row]
}
public struct ReminderSummary: Sendable, Equatable {        // REPO-110/111
    public var overdue: Int, dueToday: Int, dueWeek: Int
    public var total: Int { get }; public var any: Bool { get }
    public func headline() -> String                          // "  ·  " joins; "Nothing due."
}
@MainActor public enum ReminderService {
    public static func compute(store: AppStore, today: CivilDate) -> ReminderSummary
    public static func dedupKey(_ s: ReminderSummary, crewExpiring: Int, today: CivilDate) -> String
    public static func notificationBody(_ s: ReminderSummary, crewExpiring: Int) -> String
}
@MainActor public enum SavedListOrder {                      // REPO-130…136 (Nudge = fixed algorithm, OC-16)
    public static func groupSpan(_ all: [ChecklistTemplate], groupID: UUID?) -> [Int]
    public static func nudge(_ all: inout [ChecklistTemplate], picks: [ChecklistTemplate], up: Bool) -> Bool
    public static func moveTo(_ all: inout [ChecklistTemplate], picks: [ChecklistTemplate], targetInGroup: Int) -> Bool
    public static func groupEntries(_ data: AppData, groupID: UUID?) -> [(template: ChecklistTemplate, group: String?)]?
    public static func allEntries(_ data: AppData) -> [(template: ChecklistTemplate, group: String?)]
}
@MainActor public enum ChecklistTemplateService {            // REPO-140…146
    public static func captureFromSteps(name: String, steps: [ChecklistStep]) -> ChecklistTemplate
    public static func captureFromSubtasks(name: String, subtasks: [TaskItem]) -> ChecklistTemplate
    @discardableResult public static func applyToSteps(_ t: ChecklistTemplate, steps: inout [ChecklistStep], replace: Bool) -> Int
    @discardableResult public static func applyToSubtasks(_ t: ChecklistTemplate, subtasks: inout [TaskItem], replace: Bool) -> Int
    public static func clone(_ t: ChecklistTemplate, newName: String) -> ChecklistTemplate
    public static func itemToTask(_ item: ChecklistTemplateItem) -> TaskItem
    public static func toSteps(_ t: ChecklistTemplate) -> [ChecklistStep]
    public static func writeBackFromSteps(_ t: ChecklistTemplate, steps: [ChecklistStep])
    public static func cloneContainer(_ c: Container?) -> Container
    public static func cloneFile(_ f: FileItem) -> FileItem
}
public enum ScheduleImportError: Error, LocalizedError, Sendable { case notASchedule, parse(String) }
@MainActor public enum ScheduleService {                     // REPO-150…154
    public static func cloneEntry(_ e: ScheduleEntry) -> ScheduleEntry
    public static func captureFromCrew(name: String, crew: CrewMember, data: AppData) -> ScheduleTemplate
    @discardableResult public static func applyToCrew(_ t: ScheduleTemplate, crew: CrewMember, replace: Bool) -> Int
    public static func exportJSON(_ t: ScheduleTemplate) throws -> Data          // indented, nulls, CRLF (OC-41)
    public static func importJSON(_ data: Data) throws(ScheduleImportError) -> ScheduleTemplate   // fresh ids
}
public struct DiffNode: Sendable, Identifiable, Hashable {  // 08 §3.7, 01 §3.15
    public enum Change: Int, Sendable { case added, removed, changed }
    public var id: UUID; public var change: Change; public var text: String; public var children: [DiffNode]
}
public struct DiffResult: Sendable { public var roots: [DiffNode]; public var added: Int; public var removed: Int
                                     public var changed: Int; public var hasChanges: Bool { get }
                                     public init(roots: [DiffNode] = [], added: Int = 0, removed: Int = 0, changed: Int = 0) }
@MainActor public enum DataDiff {                           // runs on the main actor (it walks models); callers show
                                                             // AAProgressOverlay when it is slow — not in §9.7's off-main list
    public static func compare(current: AppData, incoming: AppData) -> DiffResult          // Windows scope (+OC-13)
    public static func compareOtherData(current: AppData, incoming: AppData) -> DiffResult // DECISIONS 01 Q-3
    public static func snip(_ s: String?) -> String
}
public enum AgeVerdict { public static func text(incoming: NetDateTime?, current: NetDateTime?) -> String } // QUICK-196
public enum XamlPlainText {
    public static func searchText(_ xaml: String) -> String   // 02 REPO-104 (XMLParser, spaces, fallback regex)
    public static func diffText(_ xaml: String) -> String     // 01 §3.15 PlainText (regex strip + HTML decode)
}
```

### 6.6 W-PERSIST — bundles, attachments, shared save, instance (`AACore/Bundles|Attachments|SharedSave|Instance/`)

```swift
public enum ImportKind: Sendable { case withAttachments, dataOnly }
@MainActor public enum BundleService {                       // 01 §D, §3.10
    public static func exportFolderToZip(_ ds: DataStore, to url: URL, includeAttachments: Bool) async throws  // zip off-main
    public static func importBundleSmart(_ ds: DataStore, from url: URL) throws -> ImportKind
    public static func importSharedBundle(_ ds: DataStore, from url: URL) throws
    public static func importFolderFromZipLegacy(_ ds: DataStore, from url: URL) throws   // DATA-047 (not wired to UI)
    public nonisolated static func peekZipLastModified(_ url: URL) -> NetDateTime?
    public nonisolated static func peekFileLastModified(_ url: URL, key: SymmetricKey?) -> NetDateTime?
    public nonisolated static func peekBundleSource(_ url: URL) -> BundleSource?
    public static func peekZipData(_ url: URL, dataStore: DataStore) -> AppData?
    public nonisolated static func machineName() -> String
    public static let exportDefaultName: (NetDateTime) -> String        // "aa-data-{yyyyMMdd-HHmm}.zip"
    public static let sharedDefaultName = "aa-shared.zip"
}
extension DataStore { public func applySyncedData(_ json: Data) throws -> AppData }   // 01 DATA-049 (Flash Sync)
@MainActor public enum AttachmentStore {                     // 01 §F
    /// "files/<32hex>_<leaf>". A directory or a macOS package (`.app`, `.pages`, `.rtfd`, … — any URL whose
    /// resource values say isDirectory/isPackage) is ZIPPED into ONE entry `files/<32hex>_<name>.zip` (DECISIONS 05).
    public static func importFile(_ ds: DataStore, from source: URL) throws -> String
    /// Pasted/dropped bytes without a file URL (images pasted into a note, DECISIONS 05): writes `data` directly to
    /// `files/<32hex>_<windowsSafeLeaf(suggestedName)>` (atomic) and returns the stored path. This is the only way
    /// the AA target gets such bytes into the data folder (§2.1: the AA target never writes temp files).
    public static func importData(_ ds: DataStore, _ data: Data, suggestedName: String) throws -> String
    public static func resolveFilePath(_ ds: DataStore, stored: String?) -> String
    public static func normalizeFilePaths(_ ds: DataStore, data: AppData)                     // called by serializeForSave/load
    public static func migrateLegacyAbsolutePaths(_ ds: DataStore, data: AppData)
    public nonisolated static func classify(path: String) -> FileKind                          // DATA-066 table
    public nonisolated static func windowsSafeLeaf(_ name: String) -> String                  // 01 §6.6
    public static func enumerateContainers(_ data: AppData) -> [Container]                     // DATA-068
}
public struct PathMapping: Codable, Sendable, Hashable { public var windowsPrefix: String; public var macPath: String }
@MainActor @Observable public final class PathMapper {       // DECISIONS 10 Q4, 01 §6.6, 05 §6.9
    public static let shared: PathMapper
    public var mappings: [PathMapping]                          // UserDefaults "aa.pathMappings"
    public nonisolated static func isWindowsPath(_ s: String) -> Bool   // ^[A-Za-z]:[\\/] or ^\\\\
    public func macURL(for windowsPath: String) -> URL?
    public nonisolated static func smbURL(forUNC s: String) -> URL?
}
public enum OpenOutcome: Sendable, Equatable { case opened, notFound(String), windowsPathUnmapped(String), failed(String) }
@MainActor public enum AttachmentOpener {
    public static func url(forStored stored: String, isLink: Bool, dataStore: DataStore) -> URL?
    public static func open(stored: String, isLink: Bool, dataStore: DataStore) -> OpenOutcome   // NSWorkspace
    public static func revealInFinder(stored: String, dataStore: DataStore) -> OpenOutcome
    public static func normalizeWebLink(_ s: String) -> URL?   // www.→https://, x@y→mailto:
}
@MainActor public protocol SharedSaveHost: AnyObject {       // implemented by F3's AppEnvironment
    func flushAllEditors()
    func captureUiState()
    func confirmReloadDiscardingChanges() async -> Bool       // D27: "Reload (Discard My Changes)" / "Keep Mine"
    func reloadAfterSharedImport(identity: String?)            // LoadDataAndInitUi + status "Reloaded the shared save…"
    func postStatus(_ text: String)
}
@MainActor @Observable public final class SharedSaveCoordinator {   // 01 §E, §3.12, §6.9; 03 SHELL-123…126
    public enum Health: Sendable, Equatable { case off, online(lastSync: Date?), offline(since: Date), notSaving(since: Date) }
    public init(store: AppStore)
    public weak var host: SharedSaveHost?
    public private(set) var health: Health
    public var indicatorText: String { get }                  // SHELL-023 exact texts
    public var indicatorHelp: String { get }
    public private(set) var lastSeen: NetDateTime?; public private(set) var lastSynced: NetDateTime?
    public func start(); public func stop()
    public func checkForUpdate() async
    public func push(label: String) throws                     // synchronous (menu / on close)
    public func pushInBackground(label: String)
    public func pushOnCloseIfNeeded()                          // DATA-055 rule
    public func adoptSharedFile(_ url: URL, useItsContents: Bool) async throws   // D28 outcomes (menu flow is F3's)
    public func stopUsing()
}
public enum InstanceGuardResult: Sendable, Equatable {
    case editor, unguarded(String), runningHere(pid: Int32), otherUser(String), remote(host: String, lastSeen: Date, stale: Bool)
}
@MainActor public enum InstanceGuard {                        // 01 MP (DATA-170…186) as simplified by DECISIONS
    public static func acquire(appFolder: URL) -> InstanceGuardResult
    public static func forwardToRunningInstance(pid: Int32, documents: [URL]) -> Bool   // runningHere → activate + quit
    public static func listenForForwardedDocuments(_ handler: @escaping @MainActor ([URL]) -> Void)
    public static func release()
    /// DATA-179: per-user flock on ~/Library/Application Support/AA-locks/external-{sha256}.lock. F3 calls it at
    /// launch when CurrentDataFile is outside AppFolder, and W-SHELL's Import-from-file flow calls it BEFORE
    /// `adoptExternalDataFile` (a non-`.editor` result cancels the import with the DATA-179 sheet text).
    public static func acquireExternal(fileURL: URL) -> InstanceGuardResult
    public static func releaseExternal()                        // when the active file goes back to the default
}
/// DATA-180 implementation of F1's `DataFileWriteGuard` (§5.2): fingerprint (dev, ino, size, mtime, SHA-256) per
/// 01 §MP.3.4, directory watcher (1.5 s debounce, 60 s poll on network volumes) running its check through
/// `PersistenceWriter.runOnWriterQueue`. On a refusal or a watcher hit it calls `store.pauseWrites(.externalChange)`
/// and asks the host.
@MainActor public final class DataFileFingerprint: DataFileWriteGuard {   // nonisolated witnesses, lock-protected state
    public init(store: AppStore, host: DataFileConflictHost)
    public func start(); public func stop()
}
public struct DataFileConflict: Sendable {
    public enum Kind: Sendable { case changed, deleted, unreadable(reason: String) }
    public var kind: Kind; public var fileName: String; public var ourTime: String; public var theirTime: String
    public var theirBytes: Data?
    public init(kind: Kind, fileName: String, ourTime: String, theirTime: String, theirBytes: Data?)
}
public enum DataFileConflictChoice: Sendable { case keepMine, useTheirs, stopEditingHere }  // "Review Changes…" is
                                                                  // resolved inside the host (DATA-100 sheet → one of these)
/// Implemented by F3's AppEnvironment: presents the DATA-180 sheet (W-PERSIST's `DataFileConflictSheet`) on the
/// main window and returns the choice; W-PERSIST then performs it (conflict copy, resume, Revert, read-only).
@MainActor public protocol DataFileConflictHost: AnyObject {
    func presentConflict(_ c: DataFileConflict) async -> DataFileConflictChoice
}
@MainActor public enum ConflictCopies {                       // DATA-181 (AppFolder/conflicts/, newest 20 kept)
    public struct Entry: Sendable, Identifiable, Hashable {
        public var id: String { fileName }; public var fileName: String; public var isTheirs: Bool
        public var size: Int64; public var lastModified: NetDateTime?
        public init(fileName: String, isTheirs: Bool, size: Int64, lastModified: NetDateTime?)
    }
    public static func list(_ ds: DataStore) -> [Entry]
    public static func url(of e: Entry, _ ds: DataStore) -> URL
}
```
DECISIONS: "a second launch activates the running instance": `runningHere` → forward launch documents, activate
the running AA and terminate silently (no alert). `otherUser`/`remote` keep the DATA-172 alert (W-PERSIST UI,
`AA/PersistenceUI/InstanceAlerts.swift`), with Open Read-Only setting `store.suspendSaving = true`.
DATA-181 recovery list: `ConflictCopiesSheet()` (W-PERSIST, §7.7). The 03 §6.5.1 registry has no "File ▸ Recover ▸
Conflict Copies…" row and the registry is the single menu authority, so until the lead adds a row the sheet is
reached from W-PERSIST's own surfaces: a "Conflict Copies…" button in `DataFileConflictSheet` and in
`DataFileConflictBanner`, and a "Show Conflict Copies…" item in the read-only banner. If the lead adds the row,
F3 adds `CommandID.conflictCopies` and presents the same view. Open item for the lead (Review log R-70).

### 6.7 W-RICH — rich-text core (`AACore/RichText/`)

The DOM/cascade API is **05 Addendum §XD.4** (`XamlNodeKind`, `XamlNodeID`, `XamlRawAttribute`, `XamlBrush`,
`XamlNode`, `XamlLoadability`, `XamlDocument`, `XamlDOM.parse`, `XamlContext` (`.containerEditor`,
`.containerViewer`, `.pdf`, `.sirePane`), `XamlStyleResolver`), **completed and amended** by the block below, which
fixes every type XD.4 leaves open (W-PDF, W-CONT, W-SIRE and W-FILES compile against these in parallel with W-RICH,
and F1 writes the placeholders from them). Where XD.4 and this block differ, this block wins on shape.
```swift
public enum XamlRootRole: Sendable, Hashable { case wrapper(XamlNodeKind), content(XamlNodeKind) }
// "no root yet" (XD.2.11 `.none`, a new document) is `rootRole: XamlRootRole?` == nil wherever a role is stored.
public enum XamlFontStyle: String, Sendable, Hashable { case normal = "Normal", italic = "Italic", oblique = "Oblique" }
public enum XamlTextAlignment: String, Sendable, Hashable { case left = "Left", right = "Right", center = "Center", justify = "Justify" }
public enum XamlLineStacking: String, Sendable, Hashable { case maxHeight = "MaxHeight", blockLineHeight = "BlockLineHeight" }
public enum XamlFlowDirection: String, Sendable, Hashable { case leftToRight = "LeftToRight", rightToLeft = "RightToLeft" }
public enum XamlBaselineAlignment: String, Sendable, Hashable {
    case top = "Top", center = "Center", bottom = "Bottom", baseline = "Baseline", textTop = "TextTop",
         textBottom = "TextBottom", `subscript` = "Subscript", superscript = "Superscript"
}
public struct XamlDecorations: OptionSet, Sendable, Hashable {       // written in this fixed order (XD.2.2)
    public let rawValue: UInt8; public init(rawValue: UInt8)
    public static let underline, strikethrough, overLine, baseline: XamlDecorations
}
public enum XamlLockSource: String, Sendable, Hashable { case inlineRun, inlineAncestor, block }   // CONT-159
public struct XamlFontFamily: Sendable, Hashable {
    public let raw: String                 // token as written (the writer's canonical token)
    public let canon: String               // split on ",", trimmed, empties dropped, invariant lower-case, joined ","
    public init(raw: String)
}
public struct XamlThickness: Sendable, Hashable {
    public var left, top, right, bottom: Double                      // px
    public init(left: Double, top: Double, right: Double, bottom: Double)
}
public enum XamlProperty: String, Sendable, Hashable, CaseIterable { // inheritable properties (XD.2.3 rows 1–14)
    case fontFamily, fontSize, fontWeight, fontStyle, fontStretch, foreground, textAlignment, lineHeight,
         lineStackingStrategy, flowDirection, language, isHyphenationEnabled, typography, numberSubstitution
}
/// Typed local values of one element (XD.2.2 parsers); nil = not set locally. `.invalid` values are not stored
/// here — they produce an `.invalidValue` issue and stay in `rawAttributes`.
public struct XamlLocalValues: Sendable, Hashable {
    public var fontFamily: XamlFontFamily?; public var fontSize: Double?
    public var fontWeight: Int?; public var fontWeightToken: String?
    public var fontStyle: XamlFontStyle?; public var fontStyleToken: String?
    public var fontStretch: Int?; public var foreground: XamlBrush?
    public var textAlignment: XamlTextAlignment?; public var lineHeight: Double?          // NaN = Auto
    public var lineStackingStrategy: XamlLineStacking?; public var flowDirection: XamlFlowDirection?
    public var language: String?; public var isHyphenationEnabled: Bool?
    public var typography: [String: String]; public var numberSubstitution: [String: String]
    public var background: XamlBrush?; public var textDecorations: XamlDecorations?
    public var baselineAlignment: XamlBaselineAlignment?
    public var margin: XamlThickness?; public var padding: XamlThickness?
    public var borderThickness: XamlThickness?; public var borderBrush: XamlBrush?
    public var textIndent: Double?; public var keepTogether: Bool?
    public var markerStyle: String?; public var startIndex: Int?; public var markerOffset: Double?
    public var cellSpacing: Double?; public var columnSpan: Int?; public var rowSpan: Int?
    public var width: Double?                                                             // TableColumn (NaN = Auto)
    public var navigateUri: String?; public var targetName: String?
    public init()
}
public struct XamlPropertyElement: Sendable, Hashable {             // CONT-154 "Owner.Prop" child element
    public let ownerName: String; public let propertyName: String
    public let rawXML: String                                        // verbatim source, preserved when unchanged
    public let brush: XamlBrush?                                     // parsed when it is a brush property
}
public enum XamlIssue: Sendable, Hashable {                          // XD.2.1 step 5–7, XD.2.12
    case unknownElement(String), invalidNesting(String), textInBlockContainer, invalidValue(property: String, value: String),
         duplicateProperty(String), runTextAndContent, markupExtension(String), unknownAttribute(String)
}
public enum XamlFatalError: Error, Sendable, Hashable { case malformedXML(String), dtdPresent, wrongRootNamespace(String?) }
public struct XamlComputedStyle: Sendable, Equatable {               // XD.2.6 `Computed`
    public var fontFamily: XamlFontFamily; public var fontSize: Double; public var fontWeight: Int
    public var fontStyle: XamlFontStyle; public var fontStretch: Int; public var foreground: XamlBrush
    public var textAlignment: XamlTextAlignment; public var lineHeight: Double          // NaN = Auto
    public var lineStackingStrategy: XamlLineStacking; public var flowDirection: XamlFlowDirection
    public var language: String; public var isHyphenationEnabled: Bool
    public var typography: [String: String]; public var numberSubstitution: [String: String]
    public var setter: [XamlProperty: XamlNodeID]                    // absent key = supplied by the context
}
// XamlDocument (XD.4) stores `rootRole: XamlRootRole?`; XamlNode.local is `XamlLocalValues`,
// XamlNode.propertyElements is `[XamlPropertyElement]`; XamlDOM.parse returns `Result<XamlDocument, XamlFatalError>`.
// XamlContext (XD.4) fields use the enums above. Every XD.4 value type (XamlNode, XamlDocument, XamlContext,
// XamlLoadability, XamlBrush, …) is also `Hashable` (or at least `Equatable`) so it can live in RichTextMetadata.

public extension NSAttributedString.Key {                    // 05 §6.1 + XD.3 (never persisted as such) — the UNION
    static let aaLocked, aaLockSource, aaListMarker, aaListItemID, aaListContinuation, aaHyperlink, aaXmlLang,
               aaFontFamilyName, aaFontWeightToken, aaFontStyleToken, aaInheritedExtras, aaLinkStyled,
               aaUnderlyingForeground, aaForegroundBrushXml, aaBackgroundBrushXml, aaExtraDecorations,
               aaBaselineAlignment, aaParagraphAttrs, aaExtraAttributes, aaSectionPath, aaTableRowGroup,
               aaPreservedXaml, aaInRunNewline: NSAttributedString.Key
}   // raw values and value types exactly as the XD.3 table ("aa.fontFamilyName", …)
public typealias XamlElementID = String                       // stable id of a carried element within one document
public struct RichTextMetadata: Sendable, Equatable {        // everything the writer needs that is not in the string
    public var rootAttributes: [XamlRawAttribute]; public var rootRole: XamlRootRole?     // nil = new document
    public var elementAttributes: [XamlElementID: [XamlRawAttribute]]   // carried Section/List/ListItem/Table/…/TableColumn
    public var hyperlinkAttributes: [XamlElementID: [XamlRawAttribute]]
    public var context: XamlContext                           // which consumer loaded it; CONT-165 completion source
    public var loadability: XamlLoadability; public var hasAnyLock: Bool
    public var sourceHash: Int                                // lets the editor detect "unchanged → never rewrite"
    public var isPlaceholderResult: Bool                      // true only from the F1 placeholder reader (§11)
    public init(context: XamlContext)                         // empty metadata for a new document
}
public enum XamlReadOutcome { case empty(RichTextMetadata), document(NSAttributedString, RichTextMetadata),
                              unparseable(raw: String) }      // unparseable → editor withholds saving (CONT-006)
@MainActor public enum XamlReader {
    public static func read(_ xaml: String, context: XamlContext) -> XamlReadOutcome
    public static func readFragment(_ xaml: String, destinationContext: XamlContext) -> NSAttributedString?  // CONT-161
}
@MainActor public enum XamlWriter {
    public static func write(_ text: NSAttributedString, metadata: RichTextMetadata, context: XamlContext) -> String
    public static func emptyDocument() -> String              // "" (DECISIONS 05)
}
```
Placeholder safety: F1's placeholder `XamlReader.read` returns `.unparseable(raw:)` for every non-empty input
(never `.empty`), so an editor built against the stub withholds saving (CONT-006) and cannot blank a note; W-CONT
additionally refuses to persist while `ContractStatus.isImplemented(.wRich) == false` or
`metadata.isPlaceholderResult` is true.
```swift
public enum HTMLToXAML { public static func convert(_ html: String) -> String }  // 05 §3.3 (+ DECISIONS whitespace cleanup)
@MainActor public enum RichListFormatter {   // 05 §3.2 over NSTextStorage ("ListFormatter" clashes with Foundation.ListFormatter); one undo group per call, by the caller
    public enum ListKind: Sendable, Equatable { case bullets, numbered }
    public static func toggleList(_ kind: ListKind, in s: NSTextStorage, selection: NSRange) -> NSRange   // CONT-040/041
    public static func normalise(_ s: NSTextStorage)                                                     // CONT-042
    public static func indent(_ s: NSTextStorage, selection: NSRange) -> NSRange                         // CONT-043
    public static func outdent(_ s: NSTextStorage, selection: NSRange) -> NSRange
    public static func handleTab(_ s: NSTextStorage, selection: NSRange, shift: Bool) -> NSRange?        // CONT-044 (nil = not at item start)
    public static func handleReturn(_ s: NSTextStorage, selection: NSRange) -> NSRange?
    public static func handleBackspaceAtItemStart(_ s: NSTextStorage, selection: NSRange) -> NSRange?    // CONT-045
    public static func moveItem(_ s: NSTextStorage, selection: NSRange, up: Bool) -> NSRange?            // CONT-046
    public static func insertList(lines: [String], kind: ListKind, into s: NSTextStorage, at: NSRange) -> NSRange  // CONT-047
    public static func isAtItemStart(_ s: NSAttributedString, location: Int) -> Bool
}
public enum LockRules {                                      // 05 §3.1, §4.4 (sentinel #FFFFE699 is data)
    public static let sentinel = ARGB(a: 0xFF, r: 0xFF, g: 0xE6, b: 0x99)
    public static func blocksEdit(_ s: NSAttributedString, range: NSRange, replacementLength: Int) -> Bool
    public static func lockedRanges(_ s: NSAttributedString, touching range: NSRange) -> [NSRange]
    public static func quickHasAnyLock(_ xaml: String) -> Bool                 // raw-string fast path (CONT-065)
}
```

### 6.8 Other wave-owned AACore contracts consumed by other agents

```swift
// W-CREW  (AACore/Crew/)   — NetDateParser and CrewText are F2's (§6.5)
public enum CrewExpiry {                                     // CREW-050…053 (+ SHELL-030/133 consumers)
    public static let warnDays = 60, criticalDays = 30
    @MainActor public static func expiringCount(_ crew: [CrewMember], today: CivilDate) -> Int
    public static func badgeText(_ n: Int) -> String                              // "Crew  ⚠ n"
}
// W-VESSEL (AACore/Vessel/)
public enum MaritimeIcons {                                  // 10 §4.6/4.7 (OC-51)
    public struct Icon: Sendable, Hashable { public let glyph: String; public let name: String }
    public static let all: [Icon]; public static let palette: [String]
    public static func parseColor(_ s: String?) -> ARGB       // blank/invalid → #FF1E88E5
    public static func readableForegroundIsDark(_ c: ARGB) -> Bool   // luma/255 > 0.6 → #1A1A1A
}
// W-HIER (AACore/Hierarchy/)
public enum TagParser {                                      // 04 §3.4 unified (DECISIONS 04 Q-A)
    public static func parse(_ text: String) -> [String]
    public static func display(_ tags: [String]) -> String   // ", " joined
    public static func matches(_ tags: [String], hashQuery: String) -> Bool   // "#tag" sidebar search (Q-E)
}
// W-SIRE (AACore/Sire/)
@MainActor public final class GeminiKeyStore {               // 12 §6.9, OC-35
    public init(secrets: SecretStore, settings: SettingsStore)
    public var hasKey: Bool { get }
    public func key() -> String?; public func setKey(_ s: String?) throws   // blank clears (06 BUILD-145)
    public func importFromSettingsOnce()                      // DECISIONS 12
}
// W-DRIVE (AACore/GoogleDrive/, AACore/Tools/)
public enum GoogleTokenStore {                               // 14 §6.3 (OC-34)
    @MainActor public static func hasToken(_ ds: DataStore) -> Bool
    @MainActor public static func needsReconsentForWholeDrive(_ ds: DataStore) -> Bool
}
public enum BundleName { public static func isRestorable(name: String, mimeType: String?) -> Bool }   // 14 §7.2
```
Everything else a wave agent puts in AACore (DateResolver, CompasReader, ShippalmReader, PortCallReader,
PortsService, PdfDOM, SireFlow, FlashChangeSet, DriveClient, FolderPlan, W-QUICK's DueListBuilder/DueRow/
ActivityLogCSV, …) is private to that agent: other agents never call it directly, and it follows the §12.2
naming rules.

### 6.9 F3 — launch and command logic in AACore (`AACore/Launch/`, `AACore/Commands/`)

**F3 creates these two folders itself** (F1 creates no placeholders there: nothing outside F3 uses them before F3
merges — `MacKeyStrings` lives in F1's Foundation, §6.1). Only W-SHELL and wave UI code consume them, after the F
merge.
```swift
public struct LaunchOptions: Sendable, Equatable {           // 03 BD.3.1
    public var dataDir: String?; public var version = false; public var smokeTest = false
    public var snapshot: SnapshotOptions?                    // DEBUG builds only honour it
}
public struct SnapshotOptions: Sendable, Equatable {
    public var target: String                                // SectionID raw value or SceneID raw value
    public var out: String; public var appearance: String?   // "dark" | "light"
    public var select: UUID?; public var sheet: String?; public var size: String?   // "1280x820"
}
public enum LaunchArguments { public static func parse(_ argv: [String]) -> LaunchOptions }
public enum AppFolderSource: Sendable { case argument, environment, defaultLocation }
public enum DataDirError: Error, Sendable, Equatable { case windowsPath, volumeMissing(String), notAFolder, notWritable(String), cannotCreate(String) }
public enum AppFolderResolver {                              // BD.3.2 / BD.3.3 (SHELL-193/194)
    public static func resolve(_ o: LaunchOptions, environment: [String: String], cwd: URL, home: URL)
        -> Result<(url: URL, source: AppFolderSource), DataDirError>
    public static func preflight(_ url: URL) throws(DataDirError)
}
public enum CrashLog {                                       // SHELL-001/197
    public static func block(details: String, at date: Date) -> String   // "[yyyy-MM-dd HH:mm:ss] {details}\r\n\r\n"
    @discardableResult public static func append(_ details: String, appFolder: URL?) -> URL?  // fallback ~/Library/Logs/AA
}
public enum SectionID: String, CaseIterable, Sendable, Codable {    // tab identifiers are DATA (01 §4.2.20)
    case equipment = "TabEquipment", tasks = "TabTasks", procedures = "TabProcedures", vessels = "TabVessels",
         calendar = "TabCalendar", board = "TabBoard", planner = "TabPlanner", map = "TabMap", crew = "CrewTab",
         lists = "TabLists", buckets = "TabBuckets", ports = "TabPorts", sire = "TabSire"
    public static let defaultOrder: [SectionID]              // allCases order above
    public var title: String { get }                          // "Equipment/Area", …, "SIRE 2.0"
    public var symbol: String { get }                         // 03 §6.2 table
    public var itemKind: ItemKind? { get }                    // hierarchy sections only
    public static func applyTabOrder(_ stored: [String]) -> [SectionID]   // listed valid ids first, rest in default order
    /// New stored TabOrder after a reorder: the 13 known ids in `order`, with every UNRECOGNISED entry of `stored`
    /// re-inserted directly after its original predecessor (at the front if it had none) — 03 §4.1 round-trip rule.
    public static func writeTabOrder(_ order: [SectionID], preserving stored: [String]) -> [String]
}
public enum CommandID: String, CaseIterable, Sendable, Codable {   // one case per menu-bar row of 03 §6.5.1.3
    case save /* , … F3 enumerates every row */                    // (F3 owns the file from the start; no stub)
}
public struct ShortcutRow: Sendable, Hashable {              // 03 §6.5.1.11
    public let id: String; public let command: CommandID; public let title: String
    public let key: String?; public let modifiers: [String]; public let aliases: [String]
    public let menuPath: [String]; public let windowsGesture: String; public let scope: String
    public let precedence: String; public let symbol: String?; public let help: String?
}
public enum ShortcutRegistry { public static let rows: [ShortcutRow] }
// MacKeyStrings (§6.5.1.9) is F1's (§6.1).
```

---------------------------------------------------------------------------------------------------------------------

## 7. UI architecture (F3 owns the plumbing; wave agents own the views named here)

### 7.1 Launch phases and scenes

`AAMain` (custom `@main`, F3) parses `LaunchArguments` (handles `--version` before any UI; `--smoke-test` →
`SmokeTest.run(options:)`, W-SHELL, §7.7), then runs `AAApp.main()`. `AppDelegate.applicationWillFinishLaunching`:
resolve AppFolder → crash sinks → preflight → `InstanceGuard.acquire` → `DataStore.loadSettings()` → appearance →
install the DATA-180 guard (§5.4) → `InstanceGuard.acquireExternal` when needed (03 BD.1.3 + 01 MP.6.1).
`LaunchCoordinator.phase: .instanceCheck → .splash → .login → .main` (`.blocked` while the instance alert shows).
`AAApp.init` registers the app's UserDefaults defaults, including **`NSQuitAlwaysKeepsWindows = false`**.

**Opening scenes from outside a view — the bootstrap scene (binding).** SwiftUI can only open, dismiss or show
scenes through `OpenWindowAction` / `DismissWindowAction` / `OpenSettingsAction` taken from a *live view's*
environment; an AppDelegate or coordinator has no such API. So F3 declares one always-present helper scene:
```swift
Window("", id: SceneID.bootstrap.rawValue) { BootstrapView() }     // 1×1, transparent, no chrome
    .defaultLaunchBehavior(.presented)
    .windowStyle(.plain)
    .restorationBehavior(.disabled)
    .commandsRemoved()
    .windowResizability(.contentSize)

@MainActor final class SceneOpener {          // AA/App/SceneOpener.swift (F3), owned by LaunchCoordinator
    static let shared: SceneOpener
    private(set) var ready: Bool              // true once BootstrapView captured the actions
    func open(_ id: SceneID)                  // openWindow(id:)
    func open<V: Codable & Hashable>(_ id: SceneID, value: V)   // openWindow(id:value:) — item windows
    func dismiss(_ id: SceneID)               // dismissWindow(id:)
    func openSettings()                       // openSettings()
    func window(for id: SceneID) -> NSWindow? // registry filled by .aaWindowRoot (NSWindow.identifier = scene id)
    func whenReady(_ body: @escaping @MainActor () -> Void)
}
```
`BootstrapView` stores `@Environment(\.openWindow)`, `\.dismissWindow` and `\.openSettings` into
`SceneOpener.shared`, orders its own `NSWindow` out (`orderOut`, `ignoresMouseEvents`, excluded from the Window
menu and Mission Control), and sets `ready`. The coordinator leaves `.instanceCheck` only when **both** `ready` and
the instance guard allow it. **Every other scene** is `.defaultLaunchBehavior(.suppressed)` and is opened through
`SceneOpener` — `AppEnvironment.open(_:)`, `Navigator.select` (brings main to the front), the snapshot hook and
notification clicks all go through it. This also closes the 01 MP.6.2 gap (suppressed splash opened by the
coordinator).

**State restoration is disabled for every scene** (`.restorationBehavior(.disabled)` on bootstrap, splash, login,
main, item, quick-work, search, activity-log, unit-converter, folder-builder, date-calculator, flash-sync,
crew-table, shortcuts, about), so macOS can never reopen a window before the instance check and the login gate
(03 §6.1 already requires it for splash, login and main). Main-window geometry comes from `UiState` (SHELL-032).

| Scene (F3 declares) | id / payload | Content view (owner) | Instances | Notes |
|---|---|---|---|---|
| `Window` | `bootstrap` | `BootstrapView` (F3) | 1 | always present, invisible; see above |
| `Window` | `splash` | `SplashView` (F3) | 1 | plain style, floating, 2.4 s, excluded from Window menu |
| `Window` | `login` | `LoginView` (F3) | 1 | 420×280, closing = terminate (SHELL-004) |
| `Window` | `main` | `MainWindowView` (F3) | 1 | geometry from `UiState` (SHELL-032), ⌘W = quit pipeline |
| `WindowGroup(for: UUID.self)` | `item` / item id | `ItemWindowView(itemID:)` (W-HIER) | 1 per item | |
| `Window` | `quick-work` | `QuickWorkView()` (W-QUICK) | 1 | 1200×800, `.commandsRemoved()` |
| NSPanel | `due` | `DueDatesPanelController.shared` (W-QUICK) | 1 | floating, borderless (08 §6.2-A, OC-31) |
| NSPanel | `switcher` | `QuickSwitcherPanelController.shared` (W-QUICK) | 1 | "Go to item", closes on Esc/resign-key |
| `Window` | `search` | `SearchWindowView()` (W-QUICK) | 1 | DECISIONS 08 OQ-3: reuse one window; ⌘F / ⇧⌘F open-or-focus it and select the query field (router Find line B) |
| `Window` | `activity-log` | `ActivityLogView()` (W-QUICK) | 1 | DECISIONS 08 OQ-3: reuse one window |
| `WindowGroup(for: UUID.self)` | `unit-converter` / session id | `UnitConverterView(sessionID:)` (W-DRIVE) | many | |
| `Window` | `folder-builder` | `FolderBuilderView()` (W-DRIVE) | 1 | |
| `Window` | `date-calculator` | `DateCalculatorView()` (W-DRIVE) | 1 | 540×520 fixed |
| `Window` | `flash-sync` | `FlashSyncView()` (W-FLASH) | 1 | 920×760 (13 §6.6) |
| `Window` | `crew-table` | `CrewTableView()` (W-CREW) | 1 | "Crew — Table View" |
| `Window` | `shortcuts` | `KeyboardShortcutsView()` (W-SHELL) | 1 | SHELL-523 |
| `Window` | `about` | `AboutView()` (W-SHELL) | 1 | SHELL-115 |
| `Settings` | — | `SettingsView()` (W-SHELL) embedding owners' sections (§7.7) | 1 | ⌘, |
| `MenuBarExtra` | — | `MenuBarExtraContent()` (W-SHELL) | 1 | DECISIONS Q-13, toggle in Settings |

F3 wraps every scene's content in `.aaWindowRoot(role)` (§7.5) and injects `AppEnvironment`. Wave views never
declare scenes; they request windows through `env.open(_:)`. T-KB-08/09 and TV-OWN-18 expect the existing Search /
Activity-log window to be reused (DECISIONS 08 OQ-3 supersedes 01 OC-17 and SHELL-041/095 "new window each time").

### 7.2 Main window layout (F3)

`NavigationSplitView(columnVisibility:) { SectionSidebar } detail: { SectionContentHost }` — two columns:
* **Section sidebar = the WPF tab strip** (03 §6.2): 13 rows in `UiState.TabOrder` order with SF Symbols, drag
  reorder (`.onMove`; writes `ui.tabOrder = SectionID.writeTabOrder(newOrder, preserving: ui.tabOrder)` + `markDirty`), custom colour fill + contrast label
  (SHELL-029, luma > 150), active marker, Crew badge (`CrewExpiry.badgeText`), brand header, `.help("Tip: drag a tab to reorder it.")`.
* **Content host** switches on `navigator.selectedSection` and shows the owner's root view (§7.7). Section
  roots are kept alive (a `ZStack` of lazily created roots with `opacity`/`allowsHitTesting`, or equivalent) so
  per-page state (selection, scroll, splitters) survives switching, like WPF tabs.
* Toolbar (`.toolbar(id: "main")`): shared-save indicator (always visible while in trouble), Due, Search, Go to,
  Reload, Save — no key equivalents on toolbar items (SHELL-510); `navigationTitle "AA — {identity}"`,
  subtitle = status line (SHELL-022).
* Bottom `safeAreaInset`: shortcut strip (SHELL-024) and, when the toolbar is hidden, the shared indicator.
* Top banners: safe mode (01 §6.10), read-only instance (W-PERSIST view), foreign settings paths (01 §6.8).
* **Internal layouts of sections use `HSplitView`/`VSplitView`** (never a nested `NavigationSplitView`), with
  side panes styled by `AAPaneBackground` (§8).

### 7.3 `AppEnvironment` — `AA/App/AppEnvironment.swift` (F3)

```swift
@MainActor @Observable final class AppEnvironment: SharedSaveHost, DataFileConflictHost {
    let store: AppStore
    var dataStore: DataStore { store.dataStore }
    var settings: SettingsStore { store.dataStore.settings }
    let locks: ItemLockService
    let passwords: PasswordService
    let navigator: Navigator
    let status: StatusCenter
    let router: CommandRouter
    let flush: EditorFlushCenter
    let sharedSave: SharedSaveCoordinator
    let driveSync: DriveSyncCoordinator          // W-DRIVE type (AA/Drive), placeholder by F3
    let clock: AppClock
    var isSafeMode: Bool { get }                  // store.suspendSaving due to load failure
    var mainDialogs: DialogPresenter { get }      // presenter bound to the main window

    // Shell operations (the only way wave code triggers app-level flows)
    func flushAllEditors()                         // OC-43: every live editor, item window, SIRE body, modal editor
    func captureUiState()                          // window geometry + SelectedMainTabIndex (pages keep their own Ui keys live)
    func doSave()                                  // ⌘S semantics incl. safe-mode D4 alert, status, Drive queue
    func saveQuietly() throws                      // flush + store.save(); for exports/sync (caller reports errors)
    func loadDataAndInitUI(reason: DataReplaceReason, status: String?)   // reload settings+data, replaceData,
                                                   // safe-mode flag, per-device Ui keys kept, appearance re-applied
    /// SHELL-120 gate (W-QUICK's ReviewChangesSheet). `incoming == nil` means the incoming data could not be read
    /// for a preview → the DATA-104 / QUICK-190 / TOOLS-027 Yes/No "Confirm import" alert instead of the sheet.
    func reviewAndConfirmImport(incoming: AppData?, incomingStamp: NetDateTime?, sourceName: String,
                                presenter: DialogPresenter?) async -> Bool
    func presentConflict(_ c: DataFileConflict) async -> DataFileConflictChoice   // DATA-180 host (W-PERSIST sheet)
    func open(_ request: SceneRequest)             // through SceneOpener (§7.1); single-instance scenes are focused
    func reportError(_ error: Error, context: String)   // SHELL-001: alert "AA — error" + crash.log block
    func showMainWindow()
}
/// Codable so a notification click can round-trip it through `UNNotification.userInfo` (stored JSON-encoded
/// under the key "aa.sceneRequest").
enum SceneRequest: Hashable, Codable {
    case item(UUID), search, activityLog, quickWork, dueDates, quickSwitcher, flashSync, crewTable,
         folderBuilder, dateCalculator, unitConverter, shortcuts, about, settings(tab: SettingsTab?)
}
enum SettingsTab: String, Hashable, Codable { case general, security, sync, fileLinks, ai }
```
Views obtain it with `@Environment(AppEnvironment.self) private var env`.

### 7.4 Navigation, status line and editor registry (F3, `AA/Shared/`)

```swift
@MainActor @Observable final class Navigator {
    var selectedSection: SectionID                               // sidebar selection
    var sectionOrder: [SectionID] { get }                        // SectionID.applyTabOrder(ui.tabOrder)
    func select(_ section: SectionID)                            // brings main front via SceneOpener;
                                                                 // ui.selectedMainTabIndex (no dirty)
    func moveSections(from: IndexSet, to: Int)                   // writes ui.tabOrder + markDirty (SHELL-028)
    func navigate(to itemID: UUID, childID: UUID? = nil)         // SHELL-140 / VIEW-205: by kind, never by index;
                                                                 // accepts child ids (subtask/step/component) → owner + childID
    func navigateToCrew(_ memberID: UUID)                        // SHELL-141
    func request(for kind: ItemKind) -> ItemNavigationRequest?   // observed by HierarchyTabView(kind:)
    var crewRequest: CrewNavigationRequest? { get }              // observed by CrewTabView
    func consume(_ request: ItemNavigationRequest)
    func consume(_ request: CrewNavigationRequest)
}
struct ItemNavigationRequest: Identifiable, Equatable { let id: UUID; let itemID: UUID; let childID: UUID? }
struct CrewNavigationRequest: Identifiable, Equatable { let id: UUID; let memberID: UUID }

@MainActor @Observable final class StatusCenter {                // SHELL-022 status line
    private(set) var message: String
    private(set) var history: [String]                           // last 20 (popover)
    func post(_ text: String)                                    // owners pass the exact spec strings
}

@MainActor @Observable final class EditorFlushCenter {           // OC-42: flush closures + one-editor-per-container
    struct Token: Hashable { let raw: UUID }
    func register(container: Container?, host: String, flush: @escaping @MainActor () -> Void) -> Token
    func rebind(_ token: Token, to container: Container?)
    func unregister(_ token: Token)
    func holder(of container: Container) -> Token?               // CONT-008
    func flushAll()
}
```
Detached item windows: `store.detachedItemIDs` (inserted by `ItemWindowView` on appear before binding its
editor, removed on disappear after flushing — 04 §6.7).

### 7.5 Sheets, alerts, prompts and panels — one presenter per window (F3, `AA/Shared/`)

```swift
extension EnvironmentValues { @Entry var dialogs: DialogPresenter = .unbound }   // installed by .aaWindowRoot

@MainActor final class DialogPresenter {
    nonisolated init()                               // so the nonisolated @Entry default can exist
    nonisolated static let unbound: DialogPresenter  // default when no window root installed one: logs and
                                                     // returns cancel / nil / [] / false / button index of Cancel
    func prompt(_ r: TextPromptRequest) async -> TextPromptResult                 // 06 Add. BUILD-136…150 (exact)
    func datePrompt(_ r: DatePromptRequest) async -> DatePromptResult             // 04 HIER-132, OC-10
    func pickItems<Tag: Hashable & Sendable>(_ r: ItemPickerRequest<Tag>) async -> [Tag]?   // 07 VIEW-208…216, 04 HIER-131
    func alert(_ spec: AlertSpec) async -> Int                                    // index of the pressed button
    func info(_ title: String, _ message: String) async
    func warning(_ title: String, _ message: String) async
    func error(_ title: String, _ message: String) async
    func confirm(_ title: String, _ message: String, confirm: String, cancel: String = "Cancel",
                 destructive: Bool = false, defaultIsCancel: Bool = false) async -> Bool
    func password(_ mode: PasswordSheetMode) async -> PasswordSheetResult         // 03 SHELL-161
    func reviewChanges(_ r: ReviewChangesRequest) async -> Bool                   // hosts W-QUICK's ReviewChangesSheet
    func presentSheet<Content: View>(_ kind: SheetKind,
                                     @ViewBuilder _ content: @escaping (_ dismiss: @escaping () -> Void) -> Content) async
    func savePanel(_ c: SavePanelConfig) async -> URL?
    func openPanel(_ c: OpenPanelConfig) async -> [URL]                           // [] = cancelled
    func chooseFolder(message: String, directory: URL?) async -> URL?
}
enum SheetKind { case decision, closeType }                     // SHELL-505/513 quit & ⌘W rules

struct TextPromptRequest: Equatable, Sendable { var title: String; var prompt: String; var initial: String = ""
                                                var isSecure = false; var helpText: String? = nil }
enum TextPromptResult: Equatable, Sendable { case ok(String), cancelled }        // raw text, OK always enabled
struct DatePromptRequest: Equatable { var title: String; var prompt: String; var initial: NetDateTime?
    var clearTitle = "Clear deadline"; var clearHelp: String? = "Remove the deadline from every selected item."
    var emptyMessage = "Pick a date, or use \"Clear deadline\" to remove it." }
enum DatePromptResult: Equatable { case ok(NetDateTime), cleared, cancelled }   // ok = .unspecified midnight
struct ItemPickerRow<Tag: Hashable & Sendable>: Hashable { var display: String; var tag: Tag }
enum ItemPickerMode { case single, multi }
enum ItemPickerResultOrder { case selection, candidate }
struct ItemPickerRequest<Tag: Hashable & Sendable> { var prompt: String; var rows: [ItemPickerRow<Tag>]
    var preselected: [Tag] = []; var mode: ItemPickerMode = .multi; var resultOrder: ItemPickerResultOrder = .selection }
struct AlertButton { var title: String; var role: AlertButtonRole = .normal }
enum AlertButtonRole { case normal, `default`, cancel, destructive }
struct AlertSpec { var title: String; var message: String; var style: NSAlert.Style = .informational
                   var buttons: [AlertButton]; var suppressionKey: MacPreferences.Key? = nil }
enum PasswordSheetMode { case unlock(prompt: String), setNew, changeExisting }
enum PasswordSheetResult: Equatable { case ok(password: String, current: String?), cancelled }
struct ReviewChangesRequest { var sourceName: String; var ageText: String; var diff: DiffResult; var otherData: DiffResult }
struct SavePanelConfig { var title: String? = nil; var message: String? = nil; var defaultName: String
                         var allowedTypes: [UTType]; var allowsOtherTypes = false; var directory: URL? = nil }
struct OpenPanelConfig { var message: String? = nil; var allowedTypes: [UTType] = []; var allowsMultiple = false
                         var canChooseFiles = true; var canChooseDirectories = false; var directory: URL? = nil
                         var allFilesAccessory = false }                            // "Excel workbook / All files" pop-up
struct OptionalDatePicker: View {                                                  // 06 §6.2, OC-55
    init(_ label: String? = nil, value: Binding<NetDateTime?>, earliest: CivilDate? = nil, latest: CivilDate? = nil,
         emptyTitle: String = "—", setTitle: String = "Set…")                      // edits produce .unspecified dates
}
```
Rules: NSAlert `messageText` = Windows title, `informativeText` = Windows body, Mac verb buttons with identical
semantics, destructive confirmations default to Cancel (03 §6.5, C13). Sheets attach to the window whose command
opened them. Decision sheets refuse ⌘W/⌘Q (SHELL-505/513), close-type sheets close (= save) on ⌘W/⎋.
Callers resolve picker tags to live objects **at OK time**.

**Sheet contract (every `…Sheet` type in §7.7):** a `…Sheet` is a **content view**, never self-presenting. Callers
present it with SwiftUI `.sheet(item:)` / `.sheet(isPresented:)` or with `dialogs.presentSheet(kind) { dismiss in … }`;
`DialogPresenter` itself presents through a SwiftUI `.sheet` on the window root, so `@Environment(\.dismiss)` works
inside every sheet. Each sheet applies `.aaSheet(.closeType)` or `.aaSheet(.decision)` to its own root (the ⌘W/⌘Q
rules), commits **by id** on close (re-resolving its target; alert if it vanished, §2.4) and dismisses itself with
`@Environment(\.dismiss)`. Sheets with an outcome also take an optional `onFinish` closure (e.g.
`TrashSheet(onFinish: (() -> Void)? = nil)`); the caller refreshes in it.

### 7.6 Commands architecture (03 §6.5.1; F3)

* **Registry** — `ShortcutRegistry.rows` (AACore) is the only table of keys, titles, menu paths, scopes and
  precedence; it drives `AppCommands`, the Keyboard Shortcuts window, toolbar help and the integrity tests
  (T-KB-*, §6.5.1.14).
* **Menus** — SwiftUI `Commands` built exactly as §6.5.1.13 (replaced groups, Format menu built explicitly,
  `CommandMenu("Tools")`, `SidebarCommands()`, `ToolbarCommands()`). Every item is
  `Button(router.state(.x).title) { router.perform(.x) }.disabled(!router.state(.x).enabled)` with the key from the
  registry. Hidden aliases, tooltips and badges come from `AppKitMenuBridge` (idempotent, by stable identifier).
* **CommandRouter** — `@MainActor @Observable final class CommandRouter` with the state of §6.5.1.10
  (`phase, keyWin, keyWinIsSheetOrModal, decisionSheetOpen, responder, list, section, hierSelection,
  plannerMode, calendarFontScale, safeMode, hasRepo, pendingUndoCount, inFlight`) and
  `func state(_ c: CommandID) -> (enabled: Bool, title: String)`, `func perform(_ c: CommandID)`. The pure decision
  table lives in `AACore/Commands/CommandRouterCore.swift` so AACoreTests cover T-KB-01…58.
* **How views publish context** (the only integration points for wave agents):
```swift
enum ListRole: String { case hierarchySidebar, sectionList, crewRoster, boardColumn, calendarTable, builderItems,
    savedLists, buckets, bucketMembers, fileBank, viewerFiles, workOrders, portsOfCall, quickCards, relationships,
    components, subtasks, steps, quickWorkList, quickWorkChildren, crewChecklist, crewSchedule, crewTableColumns,
    trashTable, searchResults, switcherResults, other }
enum MoveDirection { case up, down }
struct ListCommands {                                      // 03 §6.5.1.10 ListCommands
    var role: ListRole; var selectionCount: Int
    var deleteTitle: String? = nil; var delete: (() -> Void)? = nil; var deleteConfirms = true
    var canMoveUp = false; var canMoveDown = false; var move: ((MoveDirection) -> Void)? = nil
    var moveTo: (() -> Void)? = nil; var quickLook: (() -> Void)? = nil; var primary: (() -> Void)? = nil
}
struct HierarchySelectionState: Equatable { var primary: UUID?; var count: Int; var gated: Bool; var detached: Bool }
struct VesselMenuActions { var importWorkOrders, exportWorkOrders, importPorts, exportPorts, newQuickCard: () -> Void }
struct SectionCommands {
    var newItemTitle: String? = nil; var newItem: (() -> Void)? = nil
    var rename: (() -> Void)? = nil; var openInNewWindow: (() -> Void)? = nil
    var hierarchySelection: HierarchySelectionState? = nil
    var plannerPrevious: (() -> Void)? = nil; var plannerToday: (() -> Void)? = nil; var plannerNext: (() -> Void)? = nil
    var calendarFontScale: Double? = nil; var setCalendarFontScale: ((Double) -> Void)? = nil
    var focusSearchField: (() -> Void)? = nil; var searchFieldIsFocused = false
    var vessel: VesselMenuActions? = nil
}
extension View {
    func aaListCommands(_ c: ListCommands) -> some View                 // on the focusable List/Table
    func aaSectionCommands(_ section: SectionID, _ c: SectionCommands) -> some View   // on each section root
    func aaWindowRoot(_ role: KeyWindowRole) -> some View               // F3 applies in scene declarations
    func aaSheet(_ kind: SheetKind, role: KeyWindowRole? = nil, onClose: (() -> Void)? = nil) -> some View
                                                                        // marks custom sheets; `role: .viewer` for the
                                                                        // read-only viewer (router KeyWin `viewer`)
    /// ⌥⌘F target. In non-main windows: the window's filter field. In the MAIN window it may be applied to a filter
    /// field inside an embedded panel (e.g. W-VESSEL's Work Orders / Ports search, T-KB-14): rule — a filter field
    /// that has focus-within (its panel contains the first responder) wins over `SectionCommands.focusSearchField`.
    func aaFilterField(for window: KeyWindowRole) -> some View
}
enum KeyWindowRole: Hashable { case main, item(UUID), search, quickWork, due, switcher, activityLog, unitConverter,
    dateCalc, folderBuilder, crewTable, viewer, flashSync, settings, shortcuts, about, login, splash, other }
// `.aaWindowRoot(role)` also sets the hosting NSWindow's `identifier` to the scene id and registers it with
// SceneOpener (§7.1). The read-only viewer is a sheet: its root applies `.aaSheet(.closeType, role: .viewer)`, so
// the router sees keyWin == .viewer AND keyWinIsSheetOrModal.
enum RichKind { case container, sireBody, viewer }
enum FormatCommand: Hashable { case showFonts, bold, italic, underline, strikethrough, bigger, smaller,
    baselineDefault, superscript, `subscript`, showColors, highlight(ARGB?), highlightOther, alignLeft, center,
    justify, alignRight, bulletedList, numberedList, indent, outdent, insertLink, insertTable, insertSavedList,
    clearFormatting, lockSelection, unlockSelection, moveItemUp, moveItemDown, pasteAndMatchStyle,
    showFind, findNext, findPrevious, useSelectionForFind, jumpToSelection }
@MainActor protocol AARichTextResponder: NSTextView {       // adopted by W-CONT AARichTextView, W-SIRE body,
    var aaRichKind: RichKind { get }                        // W-FILES viewer text view
    func aaValidate(_ c: FormatCommand) -> Bool
    func aaPerform(_ c: FormatCommand)
}
```
The router finds the rich-text target as `NSApp.keyWindow?.firstResponder as? AARichTextResponder`; menu key
equivalents are processed before the text view (R-a…R-c), TXT-class items are disabled while any `NSText` is first
responder, and each TXT-class `perform` re-checks and forwards (step F).

### 7.7 Embed contracts between agents (exact initializers; SwiftUI `View`s unless noted)

Shorthand in this table: `env:dialogs:` always means `(env: AppEnvironment, dialogs: DialogPresenter)`; all
functions are `@MainActor`. `EditorHost.savedListItem(UUID)` carries the template id. Every `…Sheet` follows the
§7.5 sheet contract. Every view that takes a model reference is hosted with `.id(ObjectIdentifier(model))` (§2.4).

| Owner | Type / call | Used by |
|---|---|---|
| W-HIER | `HierarchyTabView(kind: ItemKind)` | F3 content host (4 sections) |
| W-HIER | `ItemWindowView(itemID: UUID)` | F3 `item` scene |
| W-HIER | `LockGateView(itemID: UUID)` (overlay; 04 §6.4) and `ItemLockSheet(itemID: UUID)` (protect/change/remove, HIER-058) | W-HIER only (main pane + item windows); every other owner checks `env.locks.isGated(item)` and refuses per its spec (e.g. PDF-002) |
| W-HIER | `BatchContextMenuItems(selection: @escaping () -> [AnyObject], refresh: @escaping () -> Void, done: Bool = true, deadline: Bool = true)` | W-BUILD, W-PLAN, W-QUICK |
| W-HIER | `enum BatchActions { static func markDone(_ items: [AnyObject], done: Bool, env: AppEnvironment) -> Int; static func setDeadline(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter) async -> Int; static func confirmAndTrash(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter) async -> Int }` (`confirmAndTrash` routes nested subtasks through `store.trashSubtask`) | same (+ ⌘⌫ delete routing) |
| W-CONT | `ContainerEditorView(container: Container, context: ContainerEditorContext)` with `struct ContainerEditorContext { var title: String; var host: EditorHost; var isEnabled = true; var showsFileBank = true }`, `enum EditorHost: Hashable { case mainPane(ItemKind), itemWindow(UUID), component(UUID), subtask(UUID), step(UUID), savedListItem(UUID) }` | W-HIER, W-BUILD, W-QUICK |
| W-CONT | (internal, not an embed contract) `RichTextEditorView`, `AARichTextView`, format bar — other owners embed `ContainerEditorView` only; W-SIRE builds its own `InsertionOnlyTextView` (12 §6.4) that adopts `AARichTextResponder` | — |
| W-FILES | `FileBankView(container: Container, context: FileBankContext)` with `struct FileBankContext { var host: EditorHost; var isEnabled = true }` | W-CONT (inside ContainerEditorView) |
| W-FILES | `@MainActor enum FileBankOperations { static func addImported(storedPath: String, displayName: String, to container: Container, env: AppEnvironment) -> FileItem; static func addFiles(_ urls: [URL], linkInPlace: Bool, to container: Container, env: AppEnvironment) throws -> [FileItem] }` — classification, Windows-safe leaf, `Added` stamp, markDirty, refresh of any open `FileBankView` of that container. W-CONT's image paste/drop = `AttachmentStore.importData` (W-PERSIST) → `FileBankOperations.addImported` + the inline notice (DECISIONS 05) | W-CONT |
| W-FILES | `FileBacklinksSection(itemID: UUID)` — DECISIONS 05 "item backlinks": every `FileItem` whose `LinkedItemIds` contains the item, with its container owner; open / show in Finder | W-HIER (Relationships tab) |
| W-FILES | `ContainerViewerSheet(title: String, container: Container)` (HIER-136) | W-BUILD (Saved Lists), others |
| W-FILES | `@MainActor final class QuickLookCoordinator { static let shared; func preview(_ urls: [URL], selectedIndex: Int = 0) }` — implemented either with SwiftUI `.quickLookPreview($url, in: urls)` on a coordinator-owned host view, or by splicing an `NSResponder` (implementing `acceptsPreviewPanelControl`/`beginPreviewPanelControl`/`endPreviewPanelControl`) into the key window's responder chain while previewing; a free-standing `QLPreviewPanel` dataSource without a responder is not allowed ("no controller") | W-VESSEL (optional), W-FILES |
| W-BUILD | `ChecklistBuilderView(host: ChecklistBuilderHost)`; `ChecklistBuilderSheet(host: ChecklistBuilderHost)` with `enum ChecklistBuilderHost: Hashable { case procedure(UUID), crew(UUID), savedList(UUID) }` | W-HIER (procedure), W-CREW (crew Checklist tab) |
| W-BUILD | `SubtaskBuilderSheet(taskID: UUID)` | W-HIER, W-QUICK ("Open full builder") |
| W-BUILD | `ChecklistStepEditorSheet(stepID: UUID)` — store-owned procedure and crew steps only (resolved with `store.step(id:)`); W-BUILD's TemplateEditor uses an internal overload `ChecklistStepEditorSheet(step: ChecklistStep, onCommit: @escaping (ChecklistStep) -> Void)` for detached `toSteps` clones (06 BUILD-063) | W-HIER, W-PLAN, W-QUICK, W-CREW |
| W-BUILD | `TaskItemEditorSheet(taskID: UUID)` (the subtask editor, used for any task) | W-HIER, W-PLAN, W-QUICK |
| W-BUILD | `ProcedureChecklistSection(procedureID: UUID)` (06 §C incl. export buttons calling W-PDF) | W-HIER |
| W-BUILD | `SavedListsTabView()` | F3 |
| W-PLAN | `CalendarTabView()`, `PlannerTabView()`, `BoardTabView()`, `BucketsTabView()`, `RelationshipMapTabView()` (the saved-list→tasks picker, VIEW-202/214, is internal to W-PLAN) | F3 |
| W-QUICK | `QuickWorkView()` | F3 `quick-work` scene |
| W-QUICK | `@MainActor final class DueDatesPanelController { static let shared; func show(env: AppEnvironment); func refresh(); var isVisible: Bool }` | F3 (⌘R), W-SHELL (digest, notification click, MenuBarExtra) |
| W-QUICK | `@MainActor final class QuickSwitcherPanelController { static let shared; func show(env: AppEnvironment) }` | F3 (⌘O/⇧⌘O) |
| W-QUICK | `SearchWindowView()`, `ActivityLogView()` (single-instance windows, DECISIONS 08 OQ-3), `TrashSheet(onFinish: (() -> Void)? = nil)`; `@MainActor enum SearchWindowActions { static func focusQuery(selectAll: Bool) }` (router Find line B) | F3 |
| W-QUICK | `ReviewChangesSheet(request: ReviewChangesRequest, finish: @escaping (Bool) -> Void)` | F3's `DialogPresenter.reviewChanges` |
| W-CREW | `CrewTabView()`, `CrewTableView()` (the crew schedule builder `ScheduleBuilderView(crewID:)` is internal to W-CREW, 06 §I by ownership split); `enum CrewActions { static func importCompas(env:dialogs:) async; static func checkExpiries(env:dialogs:, showWhenNone: Bool) async }` | F3 |
| W-VESSEL | `QuickCardsPanel(vesselID: UUID)`, `WorkOrdersPanel(vesselID: UUID)`, `VesselPortsPanel(vesselID: UUID)` (their search fields use `.aaFilterField(for: .main)`, §7.6) | W-HIER (vessel detail tabs) |
| W-VESSEL | `PortsDatabaseTabView()` | F3 |
| W-VESSEL | `enum VesselActions { static func menuActions(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter, selectTab: @escaping (VesselTab) -> Void) -> VesselMenuActions }`, `enum VesselTab { case quickCards, workOrders, ports }` | W-HIER (publishes via SectionCommands) |
| W-VESSEL | `@MainActor enum WorkOrderNotifications { static func runDigest(env: AppEnvironment, today: CivilDate) }` (AA/Vessel) — DECISIONS 10 Q7: flagged (`ShipJob.notify`) overdue work orders, only for vessels with `notificationsEnabled`, posted via `NotificationCenterBridge`, deduplicated per vessel/job/day in `MacPreferences` (`aa.vessel.notified`) | W-SHELL (same cadence as the reminder digest, §9.3) |
| W-PDF | `enum PdfExportFlows { static func exportItem(itemID: UUID, env:, dialogs:) async; static func printItem(itemID: UUID, env:, dialogs:) async; static func exportChecklistPDF(procedureID: UUID, env:, dialogs:) async; static func exportChecklistXLSX(procedureID: UUID, env:, dialogs:) async; static func exportSavedLists(_ scope: SavedListsExportScope, env:, dialogs:) async }`, `enum SavedListsExportScope { case list(UUID), group(ofList: UUID), all }` | W-HIER (header), W-BUILD (checklist + Saved Lists buttons), F3 (⌥⌘E, ⌘P) |
| W-SIRE | `SireTabView()`; `enum SireActions { static func showExportDialog(env:dialogs:) async; static func setGeminiKey(env:dialogs:) async }`; `GeminiKeySettingsSection()` | F3 (tab, menu rows), W-SHELL (Settings ▸ AI) |
| W-FLASH | `FlashSyncView()` | F3 `flash-sync` scene |
| W-DRIVE | `DriveSyncCoordinator` (`@MainActor @Observable final class`; `init()`, `func attach(_ env: AppEnvironment)` called once by F3 after construction, `queueSyncAfterExplicitSave()`, `checkRemoteNewer(interactive: Bool) async`, `startupChecks() async`, `inFlight: Set<DriveOperation>` with `enum DriveOperation: Hashable { case upload, load, check, push }`); `enum DriveActions { static func saveCopyToSyncedFolder(env:dialogs:) async; setDriveFolder; uploadBackup; loadBackup; setOAuthClient; signOut; toggleSyncOnSave; checkForNewer }` (all `(env: AppEnvironment, dialogs: DialogPresenter) async`); `DriveSettingsSection()`; `FolderBuilderView()`, `DateCalculatorView()`, `UnitConverterView(sessionID: UUID)` | F3, W-SHELL (Settings ▸ Sync) |
| W-SHELL | `@MainActor enum ShellFlows { static func perform(_ c: CommandID, env: AppEnvironment, dialogs: DialogPresenter) async; static func handles(_ c: CommandID) -> Bool; static func openDocuments(_ urls: [URL], env: AppEnvironment) async }` — the File/Tools flows of §7.8 marked W-SHELL (Save As, Reload, Import from file incl. `acquireExternal`, export/import ZIP, text-only and encrypt toggles, shared save set/stop/check, identity, open data folder, password set/change, Lock Now) and `.aaz` double-click import (SHELL-185) | F3 (router `perform`, AppDelegate `application(_:open:)`) |
| W-SHELL | `SettingsView()` (tabs per `SettingsTab`: General, Security, Sync (+ `DriveSettingsSection()`), File Links (`PathMappingSettingsView()`), AI (`GeminiKeySettingsSection()`)); `AboutView()`; `KeyboardShortcutsView()` (renders `ShortcutRegistry.rows`); `MenuBarExtraContent()` | F3 scenes |
| W-SHELL | `@MainActor final class ReminderCenter { static let shared; func start(env: AppEnvironment); func stop(); func runDigest(reason: DigestReason) }` with `enum DigestReason { case launch, timer, dayChanged, wake }` — reminders, Dock badge, MenuBarExtra headline, daily digest, and the call to `WorkOrderNotifications.runDigest` on every digest | F3 (starts it when phase becomes `.main` as editor; stops it on quit / read-only) |
| W-SHELL | `@MainActor enum NotificationCenterBridge { static var isAvailable: Bool; static func install(env: AppEnvironment); static func post(id: String, title: String, body: String, onClick: SceneRequest?) }` (no-op when unbundled; click → decodes the `SceneRequest` from `userInfo` → `env.open`) | W-VESSEL, W-SHELL reminders; F3 calls `install` at launch |
| W-SHELL | `enum SmokeTest { @MainActor static func run(options: LaunchOptions) -> Int32 }` (SHELL-205, BD.3.12) | F3 `AAMain` |
| W-PERSIST | `PathMappingSettingsView()`; `enum InstanceAlerts { static func presentBlocked(_ r: InstanceGuardResult, appFolder: URL) -> InstanceAlertChoice }`, `enum InstanceAlertChoice { case switchToRunning, openReadOnly, quit, takeOver }`; `ReadOnlyInstanceBanner()`; `DataFileConflictBanner()`; `DataFileConflictSheet(conflict: DataFileConflict, finish: @escaping (DataFileConflictChoice) -> Void)` (DATA-180 sheet incl. "Review Changes…" via `env.reviewAndConfirmImport`); `ConflictCopiesSheet()` (DATA-181, §6.6) | F3 (banners; `presentConflict` hosts the sheet), W-SHELL (Settings ▸ File Links) |

Internal (no contract; owner's choice of names, following the §12.2 prefixes): per-kind detail panes and specifics
tabs (W-HIER), calendar rows, planner chips, board cards and the saved-list task picker (W-PLAN; colours from
`AAColor.kind`/`AAColor.Status`), due rows (W-QUICK), quick-card views (W-VESSEL), SIRE panes (W-SIRE), Flash Sync
send/receive views (W-FLASH).

Settings window tabs (W-SHELL, `SettingsView`): General (identity, appearance System/Light/Dark, shortcut bar,
MenuBarExtra toggle), Security (app password, Lock Now, local encryption), Sync (shared save file +
`DriveSettingsSection()`), File Links (`PathMappingSettingsView()`), AI (`GeminiKeySettingsSection()`).

### 7.8 Menu command → implementation (F3 wires; owners implement)

| Registry rows | Action |
|---|---|
| SHELL-540 New {Kind}, 541 Open in New Window, 542 Rename | `SectionCommands` of the active section (W-HIER, W-PLAN, W-BUILD) |
| 543 Quick Look, 544 Delete family, 581–583 Move Up/Down/To | `ListCommands` of the focused list (list owner) |
| 545 Close, 546 Save | F3 (quit/⌘W pipeline, `env.doSave()`) |
| 547 Save a Copy As, 548 Reload, 549 Import from File, 551 Encrypt toggle, 552–554 Shared Save ▸, 555 Identity, 556 Open Data Folder, 557/558 Export/Import ZIP, 559 Text-only toggle | `ShellFlows.perform` (W-SHELL) over `DataStore`/`BundleService`/`SharedSaveCoordinator`/`InstanceGuard`; F3's router owns title/enablement |
| 550 Trash… | F3 presents `TrashSheet()` (W-QUICK) on the main window |
| 560–567 Google Drive ▸ | `DriveActions` (W-DRIVE) |
| 568 Flash Sync | F3: `flushAllEditors()` + `saveQuietly()` (FLASH-002) → `env.open(.flashSync)` |
| 569 Export as PDF… / 570 Print… | `PdfExportFlows.exportItem/printItem` (W-PDF) for the router's target item |
| 575 Undo | text undo or `store.undoLastDelete()` + status (F3) |
| 584–590 Find family | router (§6.5.1.10): rich text → `aaPerform(.showFind…)`; else `env.open(.search)` + `SearchWindowActions.focusQuery(selectAll: true)`; ⌥⌘F → focus-within panel filter, else section/window filter (§7.6) |
| 600–623 Format | `AARichTextResponder.aaPerform` (W-CONT editor; W-SIRE body subset) |
| 630–634 sections & Planner | `navigator.select`; `SectionCommands.planner*` (W-PLAN) |
| 605/606 Bigger/Smaller | editor step, else Calendar `setCalendarFontScale` (W-PLAN) |
| 645 Folder Builder, 646 Date Calculator, 651 Unit Converter | `env.open(...)` (views W-DRIVE) |
| 647 Due-dates, 649 Quick Switcher, 650 Activity Log | `DueDatesPanelController`, `QuickSwitcherPanelController`, `env.open(.activityLog)` (W-QUICK) |
| 648 Quick Work | `env.open(.quickWork)` (W-QUICK) |
| 652/653 Crew | `navigator.select(.crew)` then `CrewActions` (W-CREW) |
| 654 Vessel ▸ | `SectionCommands.vessel` (W-HIER publishes `VesselActions.menuActions`) |
| 655/656 SIRE | `SireActions` (W-SIRE) |
| 657 Set / Change Password, 658 Lock Now | `ShellFlows.perform` (W-SHELL: `PasswordService`, `ItemLockService.relockAll`, gating open windows through `env.locks`) |
| 662 Help ▸ Keyboard Shortcuts | `env.open(.shortcuts)` (view W-SHELL) |
| App menu About / Settings… | `env.open(.about)` / `SceneOpener.openSettings()` (views W-SHELL) |

### 7.9 Import/reload pipeline (F3 orchestrates the gate and the reload; the menu flows are W-SHELL's)

```
flow(sourceURL | bundle | drive | shared | flash):
  env.flushAllEditors()
  incoming = peek (BundleService.peekZipData / DataStore.loadFrom on a temp copy)       — W-PERSIST / F1
                                                                                        — nil when unreadable
  [import from file only] InstanceGuard.acquireExternal(fileURL:) — not .editor → DATA-179 sheet, stop
  ok = await env.reviewAndConfirmImport(incoming:, incomingStamp:, sourceName:)        — nil → DATA-104 Yes/No alert;
                                                                                          gate (not for shared auto-pull
                                                                                          without unsynced edits, 01 §1.2;
                                                                                          Flash Sync has its own review)
  guard ok
  kind = BundleService.importBundleSmart(...) / adoptExternalDataFile / applySyncedData
  env.loadDataAndInitUI(reason:, status: "Imported {file} (text only — your attachments are untouched)" …)
```
`loadDataAndInitUI` = `dataStore.loadSettings()` → `dataStore.load()` → keep per-device Ui keys from the old data
→ `store.replaceData` → `store.suspendSaving = dataStore.lastLoadFailed` → re-apply appearance and menu toggles
(W-11 fix) → status. Open windows re-resolve by id (§2.4).

---------------------------------------------------------------------------------------------------------------------

## 8. Design system (F3, `AA/Design/`) — every UI owner uses these, never raw hex or fonts

### 8.1 Appearance

* `AppearanceMode: String { case system, light, dark }` in `MacPreferences` (`aa.appearance`). First launch:
  `.dark` if `settings.darkMode`, else `.system` (DECISIONS 03). Choosing Light/Dark writes `DarkMode`
  (false/true) to settings.json; System leaves `DarkMode` untouched. Applied with `NSApp.appearance`
  (`nil` / `.aqua` / `.darkAqua`) before the splash; View ▸ Dark Mode ✓ toggles Light⇄Dark (SHELL-110/638).
  Re-applied after every reload (Flash Sync can change `DarkMode`).
* All colours are **dynamic** (`NSColor(name:dynamicProvider:)` resolving on the effective appearance), exposed as
  `Color` via `Color(nsColor:)`. No asset catalog.

### 8.2 Colour tokens (03 §6.6.1, DECISIONS 03 Q-1)

| Token (`AAColor.`) | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#1E1E1E` | canvases (map, login, planner grid) |
| `panel` | `#FFFFFF` | `#252526` | app-drawn cards, lists, popovers |
| `panelAlt` | `#FFFFFF` | `#2D2D30` | inputs, table headers, bottom strip |
| `accent` | `#000000` | `#FFFFFF` | brand text, active-section marker (the WPF "Accent") |
| `accentHover` | `#000000` | `#CCCCCC` | parity only |
| `fg` | `#000000` | `#F0F0F0` | primary app-drawn text |
| `muted` | `secondaryLabelColor` | `#B0B0B0` | secondary text (Q-1 mapping for light) |
| `border` | `separatorColor` | `#3F3F46` | 1-pt borders and separators (Q-1 mapping for light) |
| `hover` | `#EFEFEF` | `#3A3A3D` | hover fill on app-drawn rows |
| `selectionBg` | `#CCE8FF` | `#094771` | app-drawn selection |
| `selectionFg` | `#000000` | `#FFFFFF` | |
| `editorPaper` | `#FCFCFC` | `#FCFCFC` | rich-text paper (both appearances; text view forced `.aqua`) |
| `editorInk` | `#1A1A1A` | `#1A1A1A` | rich-text default ink |
| `tint` | `#1E88E5` | `#4AA3F0` | app tint (`.tint(AAColor.tint)`): prominent buttons, focus, links in chrome — "accent derived from the WPF primary blue" (brief) |

Semantic fixed colours (`AAColor.Status.`, same in both appearances unless noted, 03 §6.6.3):
`danger #D45050`, `sharedOK #3CA05A`, `ok #2E9E5B`, `dueSoon #E8890C`, `warning #C9A227`, `neutral #8A8A8A`,
`overdue #E53935` (board/palette; `#D32F2F` board meta, dark `#EF5350`), `diffAdded #2E7D32` (dark `#66BB6A`),
`diffChanged #EF6C00` (dark `#FFA726`), `diffRemoved #C62828` (dark `#EF5350`), `boardMuted #6B6B6B`,
`searchHighlight #FFE066` (+ black bold text, both appearances, OC-54), `lockSentinel #FFE699` (**data**; used only
by the editor), `crewAccent #9C6ADE`, `floatingOverdue #E05252`, `floatingHeader #3A7BD5→#00A88E`, `floatingTint
#EAF6FF`, `sireAmber #F0A030`, `hyperlinkGrey #9AA0A6`, `plannerMuted #6B7785`, `plannerGrid #22808080`,
`plannerBlock #1E88E5`, `defaultCard #1E88E5`, `splashBorder #DDDDDD`.

Per-kind colours (DECISIONS 07 Q-10; `AAColor.kind(_ kind: ItemKind)`): Equipment `#4FC3F7`, Task `#FFB74D`,
Procedure `#A5D6A7`, Vessel `#CE93D8`, Crew item `#9C6ADE`. Fills are identical in both appearances with **black**
text and a `border` stroke (pastel fills stay legible on dark); `AAColor.kindGlyph(_:)` gives a darker variant for
glyphs on light backgrounds (`#0288D1`, `#EF6C00`, `#388E3C`, `#8E24AA`) and the fill itself on dark.
Used consistently for: sidebar/section badges, map nodes, calendar/planner chips (kind stripe), due-panel glyphs,
switcher kind capsules, search result kind capsules.

### 8.3 Typography (03 §6.6.4)

```swift
enum AAFont {
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont   // Consolas if installed → SF Mono → Menlo
    static var isConsolasInstalled: Bool { get }
}
extension Font { static func aaMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font }
enum AAType { static let body: CGFloat = 13, small: CGFloat = 12, caption: CGFloat = 11, strip: CGFloat = 11,
              title: CGFloat = 16, brand: CGFloat = 22, loginBrand: CGFloat = 28, editor: CGFloat = 14 }
```
The main window root applies `.font(.aaMono(AAType.body))`; menus, toolbars, alerts and native controls stay
system. Stored font names in XAML are never changed (display substitution only, 05 §6.4).

### 8.4 Spacing, radii, materials

`AASpacing.xs 4, s 8, m 12, l 16, xl 24`. Radii `AARadius.control 4` (buttons, cards, 03 §6.6.5), `boardCard 6`,
`tile 8` (map nodes, pinned tiles), `quickCard 10`, `floatingPanel 12`, `sheet` = system.
Liquid Glass (macOS 26): system toolbars, sidebars, sheets and menus adopt it automatically — do not fight it.
App-drawn **floating chrome** uses `.aaGlass(in: shape)` (wraps `.glassEffect(.regular, in:)`): the shared-save
indicator capsule, the shortcut strip, the quick-switcher panel background, the due-dates panel header area,
Planner/Board floating controls. **Never** on content surfaces: lists, tables, the rich-text paper, the Flash Sync
QR plate (white) and camera plate (black), PDF previews, quick cards. Side panes use `AAPaneBackground`
(`.background(.regularMaterial)` for filter/inspect panes).

### 8.5 SF Symbol map for WPF emoji used as icons (keep emoji that are user data or inside computed strings)

| WPF | Symbol | WPF | Symbol |
|---|---|---|---|
| 🔒 lock / Lock again | `lock` / `lock.fill` | 🔓 unlock | `lock.open` |
| 🗑 delete | `trash` | ✓ mark done | `checkmark.circle` |
| ○ not done | `circle` | 📅 set deadline | `calendar.badge.clock` |
| 🛠 builder banner | `hammer` | ↩ restore | `arrow.uturn.backward` |
| 💾 save as list | `square.and.arrow.down` | 📋 load list | `list.clipboard` |
| 📤 export | `square.and.arrow.up` | 📥 import | `square.and.arrow.down.on.square` |
| 📄 PDF export | `doc.richtext` | ✎ edit | `pencil` |
| 🗓 schedule | `calendar` | ≔ insert saved list | `list.bullet.indent` |
| 📌 Due | `pin` | 🌙 Dark mode | `moon` |
| ⌨ shortcut bar | `keyboard` | 🎨 tab colours | `paintpalette` |
| 🔗 link | `link` | 🌐 web link | `globe` |
| 📁 folder | `folder` | 🪣 bucket (chrome) | `tray.2` |
| 🔔 / 🔕 notify | `bell.fill` / `bell.slash` | ⚠ warning | `exclamationmark.triangle.fill` |
| ▦ table | `tablecells` | ⤒ ⤓ move item | `arrow.up.to.line` / `arrow.down.to.line` |
| ↶ ↷ undo/redo | `arrow.uturn.backward` / `arrow.uturn.forward` | 🔍 search | `magnifyingglass` |
| ⚓ ports DB header | `ferry` | QR / Flash Sync | `qrcode` |
Section symbols: 03 §6.2 table (`SectionID.symbol`). Quick Card icons (10 §4.6) and computed display strings
(e.g. `"… · 👤 Name"`, `"🪣 name (n)"`) keep their characters.

### 8.6 Reusable components (all F3, `AA/Design/`; wave agents use, never fork)

| Component | Purpose |
|---|---|
| `AAProminentButtonStyle` / `.aaProminent()` | WPF `AccentButton` → `.borderedProminent` + bold |
| `AAToolbarButtonStyle` / `.aaToolbarButton()` | WPF `ToolbarButton` → `.bordered`, `.controlSize(.small)`, min width 30 |
| `AACard { … }` | panel background, `control` radius, 1-pt `border` |
| `AASectionHeader(title:count:)` | bold title + secondary count, used by grouped lists |
| `AAStatusCapsule(text:symbol:color:)` | shared indicator, notifications bar, badges |
| `AAKindBadge(kind:)` | kind capsule with per-kind colour |
| `AAEmptyState(title:symbol:message:)` | `ContentUnavailableView` wrapper |
| `AABanner(style:text:actions:)` | safe-mode / read-only / warnings banners (animated in/out) |
| `AAStrikeText(_:struck:)` | strikethrough rows (SHELL-156) |
| `AASearchField(text:prompt:onSubmit:)` | NSSearchField-backed field (clear button, ⌥⌘F target via `.aaFilterField`) |
| `AAColorSwatch(color:size:)` | tab colours / quick-card palette swatches |
| `AAProgressOverlay(text:)` | busy state replacing the WPF wait cursor (after ~300 ms) |
| `AAPaneBackground`, `.aaGlass(in:)` | materials per §8.4 |
| `AAHelpText(_:)` | muted wrapping help lines |
| `AAMonoText(_:)` | monospaced value text (`.textSelection(.enabled)`) |

Controls: native everywhere (03 §6.6.5); disabled = 45 % opacity for app-drawn elements; `.listRowSeparator(.visible)`;
app-drawn selection uses `selectionBg/Fg`, native `List`/`Table` selection keeps the system accent.

---------------------------------------------------------------------------------------------------------------------

## 9. Cross-cutting rules

### 9.1 Errors and alerts
* Every top-level command/button handler that can throw wraps in `do/catch` → `env.reportError(error, context:)`
  (SHELL-001: alert `AA — error` + `crash.log` block) **unless** the owning spec defines a specific message, in
  which case show exactly that (e.g. `Export failed`, `Could not import the schedule:\n\n{message}`).
* Message texts are the Windows strings verbatim (with the §6.5.1.9 key renderings and "PC"→"Mac",
  "Explorer"→"Finder" where the spec says). Pluralise where DECISIONS allow (10 Q8).
* Status-line texts go through `env.status.post(_:)`; windows without a status line drop them silently unless
  their spec gives them a footer.

### 9.2 Logging and crash log
* `AALog.logger("<area>")` (os.Logger, subsystem `com.eriskay.aa`); never log secrets, passwords, keys, tokens or
  personal crew data.
* `crash.log` (03 SHELL-001/197): `CrashLog.append`, `[yyyy-MM-dd HH:mm:ss] {details}\r\n\r\n`, fallback
  `~/Library/Logs/AA/crash.log`; uncaught ObjC exceptions + signal marker + MetricKit on next launch (03 §6.1).

### 9.3 User notifications, Dock badge, MenuBarExtra (W-SHELL; F3 starts/stops `ReminderCenter`)
* `UNUserNotificationCenter` authorisation requested lazily on the first reminder; identifier `aa.reminder`
  (replaces), title `AA — due soon`, body `ReminderService.notificationBody`; click → due-dates panel;
  `willPresent` → `.banner`. **Unbundled runs** (`swift run`) never touch `UNUserNotificationCenter`
  (03 SHELL-199) — fall back to the status line.
* Dock badge = `ReminderSummary.overdue` when > 0 (DECISIONS Q-13), cleared otherwise.
* MenuBarExtra (on by default; `aa.menuBarExtra` preference): template "A" disc; headline; crew suffix;
  `Show Due Dates…`, `Show AA`.
* Cadence (`ReminderCenter`): 30-minute timer, launch digest, `NSCalendarDayChanged` digest (DECISIONS 02 Q-7) and
  `NSWorkspace.didWakeNotification` re-check; same dedup key. Not run in safe mode or in a read-only instance.
* Work-order notifications for flagged overdue jobs (DECISIONS 10 Q7) are W-VESSEL's
  `WorkOrderNotifications.runDigest(env:today:)` (§7.7). `ReminderCenter` calls it on **every** digest of the
  cadence above (so they fire without the user ever visiting Vessels); it respects `Vessel.notificationsEnabled`
  and `ShipJob.notify`, posts via `NotificationCenterBridge.post(id:title:body:onClick:)` and deduplicates per
  vessel/job/day in `MacPreferences`.

### 9.4 File opening, Windows paths, Quick Look, drag & drop
* Open/reveal always through `AttachmentOpener` (W-PERSIST) — it applies the path-mapping table:

| Stored form | Mac resolution (in order) |
|---|---|
| `files/<32hex>_<name>` (relative, `\` or `/`) | `appFolder/files/…` |
| `http(s)://…`, `mailto:` | `NSWorkspace.open(URL)` |
| `www.…` / domain-like | prefix `https://`; `x@y` → `mailto:` |
| POSIX absolute path | as is |
| `X:\rest` (drive letter) | `PathMapper` mapping for `X:` → else `windowsPathUnmapped` → alert pointing to Settings ▸ File Links |
| `\\server\share\rest` (UNC) | mapping for `\\server\share` → else `/Volumes/share/rest` if it exists → else offer "Connect to Server…" (`smb://server/share`) and retry |
Stored paths are never rewritten (01 DATA-061). Missing targets show the owning spec's text (e.g.
`That file is missing:\n\n{resolved path}`, OC-12).
* Quick Look: `QuickLookCoordinator.shared.preview(_:)` (W-FILES; responder-chain or `.quickLookPreview`
  implementation, §7.7) — Space / ⌘Y in file tables and the viewer.
* Drag & drop types: in — `public.file-url` (Finder), `public.url`, `public.rtf`, `com.apple.flat-rtfd`,
  `public.html`, `public.utf8-plain-text`, `com.eriskay.aa.xaml`; internal — `com.eriskay.aa.task-ref` (Board),
  `com.eriskay.aa.job-ref` (Planner), `com.eriskay.aa.item-ref` (sidebar→group, relationships). Internal payloads
  are `Codable` structs with `ProxyRepresentation` to JSON; they carry ids only. W-SHELL declares all exported UTTypes
  in `Packaging/Info.plist` (identifiers from `Identifiers`, §6.1). File-bank drop modifiers: none = copy, ⇧ or ⌥⌘ = link in place (SHELL-679).

### 9.5 Resources
`AAResources.url(name:ext:)` only (never `Bundle.module` directly — it traps when the bundle is missing,
03 SHELL-198). Names: `sire2_question_bank`/`json` (AACore), `Splash`/`png`, `MenuBarIconTemplate`/`png` (AA).

### 9.6 Debug snapshot hook (F3, `AA/Debug/`, compiled only `#if DEBUG`)
```
AA --data-dir <dir> --snapshot <target> --out <file.png> [--appearance dark|light]
   [--select <uuid>] [--sheet <sheet-id>] [--size <W>x<H>]
```
* `<target>` = a `SectionID` raw value (`TabEquipment` … `TabSire`) → main window with that section, or a
  `SceneID` raw value (`quick-work`, `search`, `activity-log`, `flash-sync`, `crew-table`, `folder-builder`,
  `date-calculator`, `unit-converter`, `shortcuts`, `about`, `settings`, `due`, `switcher`, `login`, `splash`,
  `item` with `--select`). The hook opens scenes through `SceneOpener` after `ready`.
* Bypasses splash and login, loads `<dir>` like a normal launch (data folder must be a scratch copy), applies the
  appearance, navigates (`--select` → `navigator.navigate(to:)`), optionally presents a registered debug sheet,
  waits until layout is idle (≥ 2 run-loop idles + 1.0 s, max 5 s), renders the **target scene's window** — found
  by `NSWindow.identifier` through `SceneOpener.window(for:)` (the NSPanels `due`/`switcher` register themselves
  the same way), never `NSApp.keyWindow`, because non-activating panels may never become key — with
  `bitmapImageRepForCachingDisplay(in:)` + `cacheDisplay(in:to:)` → PNG, prints the path, exits 0 (exit 1 on any
  failure). `cacheDisplay` does not faithfully render `NSVisualEffectView` materials or `.glassEffect`: in
  snapshots they appear approximated (flat fills); verifiers judge layout, text and colours, not glass. Release
  builds print `--snapshot is only available in debug builds.` and continue normally.
* Sheet registry: `@MainActor enum SnapshotRegistry { static func register(_ id: String, _ make: @escaping @MainActor (AppEnvironment) -> AnyView) }`.
  Each UI owner registers its sheets in **its own** file `AA/<Dir>/<Area>DebugSnapshots.swift`
  (`extension SnapshotRegistry { static func registerW_HIER() }`, one per wave UI owner: `registerW_SHELL`,
  `registerW_PERSIST`, `registerW_CONT`, `registerW_FILES`, `registerW_HIER`, `registerW_BUILD`, `registerW_PLAN`,
  `registerW_QUICK`, `registerW_CREW`, `registerW_VESSEL`, `registerW_PDF`, `registerW_SIRE`, `registerW_FLASH`,
  `registerW_DRIVE`); F3 creates these files as placeholders and calls every `registerW_*()` at launch in DEBUG. Sheet ids are `<owner>.<name>` (e.g. `w-build.checklist-builder`).
* UI agents verify visually with fixture data folders from `Tests/AACoreTests/Fixtures/ui/<owner>/`
  (copied to a temp dir first — never run the hook on real data), in **both** appearances.
* `--smoke-test` (SHELL-205) is separate and exists in release builds.

### 9.7 Performance rules (thousands of jobs, 2 500 work orders, hundreds of crew)
* Never recompute derived collections in a `body` per row; build them in a memoised view model keyed on
  `store.generation` plus the inputs (query, filters), invalidated by `withObservationTracking` or explicit
  change notifications. Use `List`/`Table`/`LazyVStack` (lazy) with stable `Identifiable` ids.
* O(1) lookups: build `[UUID: T]` dictionaries once per refresh (first-wins in E→T→P→V order); no linear
  `store.item(id:)` inside per-row closures.
* Heavy work off-main over Sendable snapshots: XLSX parse, PDF layout, ZIP build/extract, search scan, Flash Sync
  encode/decode, PBKDF2. (`DataDiff` walks models and stays on the main actor; show `AAProgressOverlay` if slow.)
* Text search debounces: 200 ms work orders (VESSEL-104); others per spec (synchronous where Windows is).
* Performance budgets: load+decode 3 MB `data.json` < 150 ms; serialise < 50 ms (01 §6.1); XAML parse+resolve
  1 MB < 50 ms (05 XD.5); 2 524×16 sheet < 200 ms (10 X.7.2).

### 9.8 Dates in the UI
* Persisted/compared date strings (`yyyy-MM-dd`, `HH:mm`, crew/job/port strings, digest key) are always
  `en_US_POSIX` + Gregorian (01 §6.3) via `NetDateTime.format`/`CivilDate.iso`.
* Displayed dates keep the Windows fixed formats where the spec prints them (lists, PDFs, logs). Weekday and
  month names in chrome (Calendar headers, Planner, date-calculator weekday, crew `ddd`) use `Locale.current` with
  the Gregorian calendar (DECISIONS 07 Q-09); tests pin `en_US_POSIX`/`en_US`.
* Date pickers are native `DatePicker`s producing `.unspecified` midnight `NetDateTime` (DECISIONS Q-6);
  `OptionalDatePicker` everywhere a date may be empty.

---------------------------------------------------------------------------------------------------------------------

## 10. Testing strategy

### 10.1 Layout
* One test target `AACoreTests` (Swift Testing `import Testing`; XCTest allowed). Folders mirror AACore areas
  and owners: `Foundation/`, `JSON/`, `Model/`, `Persistence/`, `Crypto/`, `Zip/`, `Xlsx/`, `Store/` (F1) ·
  `Services/`, `StoreDomain/`, `XlsxRead/` (F2) · `Launch/`, `Commands/` (F3) · `ShellSupport/` (W-SHELL) ·
  `Bundles/`, `Attachments/`, `SharedSave/`, `Instance/` (W-PERSIST) · `WinFixtures/` (W-GOLD) · `RichText/`
  (W-RICH) · `Editor/` (W-CONT) · `FileBank/` (W-FILES) · `Hierarchy/` (W-HIER) · `Builders/` (W-BUILD) ·
  `Calendar/`, `Board/` (W-PLAN) · `QuickWork/`, `Windows/` (W-QUICK) · `Crew/` · `Vessel/` · `Export/` ·
  `Sire/` · `FlashSync/` · `GoogleDrive/`, `Tools/` (W-DRIVE).
* `Support/` (F1): `TempFolder` (auto-deleted), `FixedClock`, `Fixtures.url(_ relativePath:)` /
  `Fixtures.data(_:)` (via `Bundle.module` of the test target), `StoreFactory.make(data:clock:)` (temp AppFolder,
  `InMemorySecretStore`), `JSONAssert.equalCanonical`, `withTimeZone(_:)` helper. Model-touching suites are
  `@MainActor @Suite`.
* Tests never touch the login Keychain (`InMemorySecretStore`), `~/Library/Application Support/AA`, the network,
  the camera or `UNUserNotificationCenter`.

### 10.2 Fixtures (`Tests/AACoreTests/Fixtures/`, copied whole)
* **Never** named `data.json`, `settings.json` or `crash.log` (repo `.gitignore`): use
  `*.data-json.golden.json`, `sample-data.json`, `settings-sample.golden.json`; bundles keep only the `.zip`/`.aaz`
  (never extracted trees) (01 DATA-306).
* Folders per owner: `foundation/`, `json/`, `model/`, `persistence/`, `zip/`, `xlsxwriter/` (F1) · `xlsx/`
  (F2: copies of `AA/POC/*.xlsx` samples + synthetic workbooks), `services/` (F2) · `launch/`, `ui/f3/` (F3) ·
  `shell/`, `ui/w-shell/` (W-SHELL) · `bundles/`, `settings/`, `attachments/` (W-PERSIST) · `winfixtures/`
  (incl. `winfixtures/xlsx/` = XlsxGolden output, 10 X.7.6), `mac-out/`, `xaml/wpf-capture/`,
  `xaml/mac-roundtrip/` (W-GOLD) · `xaml/` except those two sub-folders, `html/` (W-RICH) · `crew/`, `vessel/`,
  `pdf/`, `sire/`, `flashsync/`, `drive/`, `tools/`, `ui/<owner>/` (snapshot data folders for UI owners — no real
  personal data, 01 DATA-314). OWNERSHIP §2 is authoritative.

### 10.3 Golden-format tests (F1 must have, before F2/F3 start)
* Fresh-database golden string (§4.10); every type's emission order and defaults; escaping table (01 §4.1.7
  incl. `\u2693`, surrogate pairs, `\u0022`…); numbers (01 §4.1.6, 7.4); dates (01 §7.5 incl. offsets in several
  time zones, fraction trimming, `originalText` round-trip); GUID case; unknown members on nested objects;
  IsComplete/Status rule; `BucketId` migration; depth 64 read/write; BOM; `AAENCM1`/`AAENC1` classification;
  PBKDF2/`enc:`/lock vectors (01 §7.1–7.3, 04 §7.8); atomic write; ZIP round-trip incl. Zip64 headers and
  `files/` empty-dir entry; XLSX writer bytes (09 §7.13; the ColRef / escape / sheet-name rows of 11 §7.14 and
  06 §7.13). (XLSX reader vectors 10 X.8 are F2's; the 11 §7.14 package rows are W-PDF's.)
* Byte-golden tests against Windows output only when a real Windows fixture exists (DECISIONS 01 Q-2); until then
  hand-built fixtures that follow the spec.
* Round-trip property: `parse → decode → encode → write` is byte-identical for every fixture whose values need no
  normalisation (paths, SchemaVersion).

### 10.4 Flash Sync vectors (W-FLASH)
From `QR_SYNC_PROTOCOL.md` §3 (Base45), §5 (xorshift32 first 8 outputs), §6 (degree/indices), §7 (complete frame
vectors, CRC-32) and 13 §7.1–7.8 (DEFLATE, encoder/decoder, change sets with created/now fixed at
2026-09-27 12:00:00). Copy the vectors into `Fixtures/flashsync/vectors.json` (QR_SYNC_PROTOCOL.md itself is
read-only and outside `mac/`). CRC-32/DEFLATE vectors are also in F1's tests. The optional `AAFlashSyncInterop`
executable reproduces the C# CLI outputs (FLASH-120).

### 10.5 Other vectors
Every spec's §7 ("Test vectors") is implemented by the owner of the feature IDs it verifies, named
`// TV: <spec> <vector id>` (OWNERSHIP §4 "Vector homes" lists the non-obvious ones). Consumers may add their own
integration tests but do not own the vector. Pure UI behaviours are verified by the snapshot hook (§9.6) and the
Stage V checklists.

**Cross-owner tests.** A test that can only pass with **another wave owner's** real implementation (in your
worktree that code is a placeholder) is written now but gated:
`@Test(.enabled(if: ContractStatus.isImplemented(.wRich)))` (§6.1). It is skipped in your worktree, runs after the
merge, and is part of your **post-merge** acceptance (OWNERSHIP §3 splits every card into *in-worktree* and
*post-merge (Stage V)*). Only the in-worktree part gates "done" (§12.4). F-stage code (F1, F2, F3) is always real
in a wave worktree, so tests depending on it are never gated.

### 10.6 Gates (every agent, before every commit)
```
cd mac && swift build -Xswiftc -warnings-as-errors && swift test -Xswiftc -warnings-as-errors \
       && Scripts/check-ownership.sh
```
(Release/universal builds and `Scripts/build-app.sh` are W-SHELL's and Stage V's gate, 03 SHELL-200…203.) The
orchestrator runs the same gate on the **merged tree after every merge** (trial merge before accepting it).

---------------------------------------------------------------------------------------------------------------------

## 11. Placeholder protocol

* Token: **`PLACEHOLDER(<owner-id>)`** — exactly this spelling, e.g. `PLACEHOLDER(W-HIER)`, `PLACEHOLDER(F2)`.
* Who creates placeholders:
  - **F1** — every AACore file owned by F2 or a wave agent that appears in this contract (types, functions, stored
    properties with the exact signatures of §5–§6; `Store/AppStore+*.swift`, `Services/**`, `XlsxRead/**` for F2),
    one `<Area>ContractStatus.swift` per wave owner with an AACore folder (§6.1: `ShellSupport`, `Bundles`,
    `RichText`, `Editor`, `FileBank`, `Hierarchy`, `Builders`, `Calendar`, `Windows`, `Crew`, `Vessel`, `Export`,
    `Sire`, `FlashSync`, `GoogleDrive`), the minimal AA-target files needed to compile
    (`Sources/AA/App/AAMain.swift`, `Sources/AA/Resources/*`, all marked `PLACEHOLDER(F3)`) and
    `Tools/FlashSyncInterop/main.swift` (`PLACEHOLDER(W-FLASH)`, prints a usage line and exits 0). F1 creates
    **nothing** in `AACore/Launch/` or `AACore/Commands/` (F3 writes them from scratch, §6.9), so no empty
    raw-valued enum ever has to compile as a stub.
  - **F3** — every AA-target type of §7.7 owned by a wave agent (views, controllers, action enums,
    `*DebugSnapshots.swift` registration files) and every AA-target type of W-SHELL (`ShellFlows`, `SettingsView`,
    `AboutView`, `KeyboardShortcutsView`, `MenuBarExtraContent`, `ReminderCenter`, `NotificationCenterBridge`,
    `SmokeTest`).
* Form: each placeholder **file** starts with `// PLACEHOLDER(<owner-id>) — contract: ARCHITECTURE.md §<n>`;
  each stub **function/view body** contains the token again in a comment. Stubs compile warning-free and return
  benign defaults: `[]`, `nil`, `false`, `0`, `""`, empty `DiffResult`, `.cancelled`, a no-op, or for views a
  `AAEmptyState(title: "<Name> — not yet implemented", symbol: "hammer", message: "PLACEHOLDER(<owner>)")`.
  Stubs never crash, never `fatalError`, never write files.
* Stub behaviour F1 must still make *correct enough* for foundation tests: `AttachmentStore.normalizeFilePaths`
  = no-op, `NetDateParser.parse` = the three exact formats (until F2 merges), `XamlPlainText.*` = regex tag strip,
  `XamlReader.read` = `.empty` for `""` and `.unparseable(raw:)` for anything else (so no editor can ever blank a
  note against the stub, §6.7), `XamlWriter.write` = `""` and never called for persistence by a correct consumer.
* Owners **replace** placeholder files in place (same path, same public signatures), flip their
  `<Area>ContractStatus.swift` to `true`, and remove every marker in their files. A wave is done only when
  `Scripts/check-placeholders.sh <owner-id>` prints nothing for that owner. At the end of Stage W,
  `grep -rn "PLACEHOLDER(" mac/Sources mac/Tests mac/Tools` must be empty.
* Consumers code against the contract as if the real implementation existed; they must not rely on stub values
  and must not add their own workaround copies of another owner's type. Tests that need another owner's real code
  are gated per §10.5.

---------------------------------------------------------------------------------------------------------------------

## 12. Merge and ownership protocol for worktree agents

### 12.1 Branches and worktrees
* Stage F1 commits on `mac-port`. F2 and F3 branch from the F1 commit (`stage/F2`, `stage/F3`) in separate git
  worktrees and are merged back (F2 first, then F3). Stage W agents branch from the merged F commit
  (`wave/<agent-id>`), one worktree each, merged in any order. The orchestrator creates/removes worktrees; agents
  never run `git worktree`, `git merge`, `git rebase` or `git push`.
* Path ownership makes merges free of **file** conflicts; the §12.2 naming rules plus `check-ownership.sh` make
  them free of **symbol** conflicts. After every merge the orchestrator runs the §10.6 gate on the merged tree (a
  trial merge first); a red merged build is handed back to the owners whose symbols collide, never fixed by hand.
* Rule zero: never create, modify, move or delete anything outside `mac/` (pre-commit hook enforces it on
  non-`main` branches; originals are `chmod a-w`). Read the C# sources freely.

### 12.2 Editing rules
* Edit **only** paths you own (OWNERSHIP.md §2). New files only inside your own directories. The single
  exception: none — not even "tiny fixes" in someone else's file.
* Never edit `Package.swift` (F1), `ARCHITECTURE*.md`, `OWNERSHIP.md`, `DECISIONS.md`, `Spec/**`.
* Test fixtures and tests only under your own `Tests/AACoreTests/<Area>/` and `Fixtures/<area>/` folders; only
  `.swift` files outside `Fixtures/` (§1.1).
* Keep every public signature of this document exactly; you may add public API in your own files.
* **Namespacing (mandatory — AA, AACore and AACoreTests are each ONE module shared by 16 worktrees).** Every
  top-level declaration that is not a contract type of this document — types, free functions, globals,
  typealiases, test helpers — in `Sources/AA/<Dir>`, `Sources/AACore/<Dir>` or `Tests/AACoreTests/<Area>` either
  carries the owner **area prefix** (`HierSidebarRow`, `CalPlannerGrid`, `BoardCardView`, `CrewRosterModel`,
  `VesselWorkOrderRow`, `PdfLayoutLine`, `ShellSettingsGeneralTab`) or is nested in an owner namespace enum
  (`enum Hier { struct SidebarRow … }`) or is `private`/`fileprivate`. Extension members on types you do not own
  (models, `AppStore`, `NetDateTime`, `Color`, `View`, `String`, `MacPreferences.Key`, `EnvironmentValues`,
  `FocusedValues`, `NSAttributedString.Key`, …) are `fileprivate`, or carry the prefix (`hierDisplayTitle`,
  `.calFilterText`, `.aaHierSelection`). `MacPreferences.Key` raw values are `aa.<area>.<name>`. File basenames
  start with the area name. Shared test helpers exist only in F1's `Support/` (request more via §12.3).
  Prefixes: F2 `Repo`/`Svc`, F3 `Shell`/`AA` (design system), W-SHELL `ShellX`, W-PERSIST `Persist`, W-GOLD
  `Gold`, W-RICH `Xaml`/`Rich`, W-CONT `Editor`, W-FILES `FileBank`, W-HIER `Hier`, W-BUILD `Builder`, W-PLAN
  `Cal`/`Planner`/`Board`/`Bucket`/`Map`, W-QUICK `QuickWork`/`Due`/`Switcher`/`Search`/`ActivityLog`/`Trash`/`Review`,
  W-CREW `Crew`, W-VESSEL `Vessel`/`Port`/`QuickCard`/`WorkOrder`, W-PDF `Pdf`, W-SIRE `Sire`, W-FLASH `Flash`,
  W-DRIVE `Drive`/`Tool`.
* `Scripts/check-ownership.sh` (F1) rejects: a changed path outside the branch owner's paths; a non-`.swift` file
  under `Sources/**` other than the manifest's resources; duplicate file basenames within a target; and the same
  non-private top-level type, typealias or free-function name declared in files of **different owners** anywhere
  in `Sources/**` and `Tests/**` (a line scan for column-0 `class|struct|enum|protocol|actor|func|typealias`
  declarations without `private`/`fileprivate`, run on the branch and on the merged tree).
* Record every P2 defect fix (and every sanctioned deviation you apply) in `Docs/Deviations/<agent-id>.md`
  (ID, spec ref, one line). Stage V merges them into `Docs/DEVIATIONS.md`.

### 12.3 Contract change requests
If a contract is missing or wrong, **do not edit the other owner's file**. Append to
`Docs/Requests/<your-agent-id>.md`:
```
## REQ-<agent>-<nn>: <short title>
Target: <file path> (owner <id>) — ARCHITECTURE.md §<n>
Need: <exact proposed Swift signature or behaviour>
Why: <spec ID / blocking reason>
Workaround in place: <what you did locally, e.g. private adapter in your own folder>
```
Keep working with a local, private workaround in your own folder (clearly marked `// REQ-<agent>-<nn>`), so
the request can be applied later without touching your logic. The lead batches requests between waves.

### 12.4 Commits
* Small, buildable commits; message `[<agent-id>] <summary>` (+ spec IDs), followed by the attribution lines the
  harness provides. Run the §10.6 gate before each commit; never commit a red build.
* Never commit generated output (`.build/`, `dist/`, snapshot PNGs outside `Tests/**/Fixtures`), personal data,
  secrets, or files named `data.json`/`settings.json`/`crash.log`.
* Before declaring done: gate green, `Scripts/check-placeholders.sh <agent-id>` empty, your
  `<Area>ContractStatus.swift` flipped to `true`, every feature ID assigned to you in OWNERSHIP.md §4 implemented
  or explicitly listed as "not applicable / optional not shipped" in your Deviations file, the **in-worktree**
  acceptance of your OWNERSHIP card met, and snapshot checks done for UI owners (both appearances). The
  **post-merge** acceptance items (gated tests, cross-agent UI checks) are verified in Stage V.

---------------------------------------------------------------------------------------------------------------------

## Review log (revision 2)

Every reviewer claim was checked against the specs (and, where the reviewer reported a compiler result, against
the stated Swift rule). Disposition: **A** = applied (where), **P** = applied in a different form (why), **R** =
rejected (one-line reason). OWNERSHIP.md was regenerated mechanically: 1 583 IDs, each with exactly one owner,
totals re-counted.

| # | Issue | Disposition |
|---|---|---|
| R-1 | `@MainActor` class conforming to nonisolated `Identifiable` fails | A — isolated conformances `@MainActor Identifiable` everywhere; rule in §2.2; §3.9, §4 intro, §4.3, ShipJob, ChecklistTemplateItem |
| R-2 | value records inferred `@MainActor` from `JSONModel` | A — `JSONModel` stays `@MainActor`; the four records are `nonisolated public struct … Sendable` (§3.8 states the choice; §4.4, §4.5, §4.7) |
| R-3 | `HierarchyItem` subclasses cannot redeclare `static let jsonKeys`; `required init`/`override` unspecified | A — exact `class var` / `required init` / `override toJSON` shape in §3.9 |
| R-4 | `deepClone` returns the static type | A — dynamic `type(of:)` init + F1 test (§3.10) |
| R-5 | escape table corrupted | A — §3.2 rewritten with literal backslashes (written programmatically) + the 01 §7.4 golden |
| R-6 | `ticks`/`kind` publicly mutable keep a stale `originalText` | A — `public private(set)`; tests (§3.4) |
| R-7 | no API opens a scene from a coordinator | A — bootstrap scene + `SceneOpener` (§7.1); `open`, `Navigator.select`, snapshot hook go through it |
| R-8 | restoration disabled only on `item` | A — every scene; `NSQuitAlwaysKeepsWindows = false` (§7.1) |
| R-9 | Search / Activity log contradict DECISIONS 08 OQ-3 | A — single `Window`s, `SearchWindowView()`, `ActivityLogView()`, `SearchWindowActions.focusQuery` (§7.1, §7.7) |
| R-10 | XD.4 leaves consumer-visible types undefined; key list incomplete | A — complete type block, `rootRole: XamlRootRole?`, metadata additions, key union (§6.7) |
| R-11 | pasted images cannot reach the file bank; packages not zipped | A — `AttachmentStore.importData`, package zipping (§6.6), `FileBankOperations` (§7.7) |
| R-12 | work-order notifications never run outside Vessels | A — `WorkOrderNotifications.runDigest` called by W-SHELL's `ReminderCenter` on the digest cadence (§7.7, §9.3) — the cadence moved with reminders to W-SHELL |
| R-13 | nested subtask cards cannot go through the Trash | A — `trash(_:)` top-level only; `trashSubtask` with `ParentTaskId` (§5.3) |
| R-14 | `readRawTree` cannot express "unreadable settings = error" | A — throwing `readRawTree`, no reload in `writeRawTree` (§6.2) |
| R-15 | cross-worktree acceptance impossible (NetDateParser, XamlDOM, BundleService…) | P — `NetDateParser`/`CrewText`/XLSX reader moved to **F2** (not F1: F1 is already the heaviest critical-path stage and F2 still precedes Stage W); `ContractStatus` gating via per-owner files (§6.1, §10.5, §11); acceptance split in OWNERSHIP §3 |
| R-16 | symbol collisions across worktrees | A — mandatory namespacing, prefixes, `check-ownership.sh` symbol/basename checks, trial-merge gate (§12.1, §12.2) |
| R-17 | non-Swift files in targets break the build | A — rule in §1.1 and §12.2 |
| R-18 | `EnvironmentValues.dialogs` default cannot call `@MainActor` init | A — `@Entry` + `nonisolated init` + `.unbound` (§7.5) |
| R-19 | empty `CommandID`, undefined `DueRow`/`DueSection`/`SettingsTab` | A — F3 writes `Launch/`/`Commands/` itself (no stubs); `DueListBuilder` removed from the contract (W-QUICK-internal); `SettingsTab` defined (§6.9, §6.8, §7.3) |
| R-20 | public structs lack public memberwise inits | A — rule in §2.2; `ARGB`, `DiffResult`, XLSX specs, write options shown explicitly |
| R-21 | `CrewMember.parseDate` main-actor isolated | A — `nonisolated static` + rule (§2.2, §4.5) |
| R-22 | `EventSubscription` deinit cannot call the hub | A — `isolated deinit` (§5.2) |
| R-23 | DataDiff listed as off-main | A — removed from §9.7; note on `DataDiff` (§6.5) |
| R-24 | `shippalmExcelDate` lacks `today`; error cases differ from X.4.13 | A — `today: CivilDate`; `XlsxReadError` adopts X.4.13 cases verbatim (§6.5) |
| R-25 | ⌥⌘F cannot target embedded vessel panels | A — `.aaFilterField(for: .main)` with the focus-within rule (§7.6, §7.7) |
| R-26 | who presents / dismisses sheets | A — sheet contract (§7.5) |
| R-27 | QuickLook singleton without a responder | A — responder-chain or `.quickLookPreview` implementation required, signature kept (§7.7) |
| R-28 | model-reference embeds may edit a detached graph | A — `.id(ObjectIdentifier(model))` + flush/rebind rule (§2.4) |
| R-29 | snapshot of `keyWindow`; materials | A — target window by identifier via `SceneOpener`; materials approximated (§9.6) |
| R-30 | data-protection keychain needs entitlements; Keychain per autosave | A — file-based login keychain; per-session key cache (§6.2, §6.3) |
| R-31 | `StepOwner.template` impossible; detached template steps | A — case removed; internal `ChecklistStepEditorSheet(step:onCommit:)` overload (§5.3, §7.7) |
| R-32 | item backlinks have no contract | A — `FileBacklinksSection(itemID:)` embedded by W-HIER (§7.7) |
| R-33 | `SceneRequest` not Codable; `viewer` KeyWin missing | A — `Codable` + `userInfo` key; `.viewer` role on the viewer sheet (§7.3, §7.6) |
| R-34 | Foundation tests and persistence fixtures unowned | A — F1 (§10.1, §10.2, OWNERSHIP §2) |
| R-35 | sandbox entitlements file; `encryption:` vs `encryptionKey:` | P — BD.4.3 already calls the file reference-only; kept and marked unused (§1.2); `encryptionKey:` everywhere (§2.3, §5.2) |
| R-36 | escaping table (duplicate of R-5) | A — see R-5; escaping vector added as an F1 golden |
| R-37 | typed dates must keep a literal `+` | A — writer-only `JSONValue.rawString`, used by `builder.date` only; equality as `.string`; goldens (§3.1, §3.2, §3.8 rule 8) |
| R-38 | `toLocalTime` must convert Unspecified | A — confirmed by 01 §3.22 (§3.4 + vector) |
| R-39 | `NetDateTime` mutability (duplicate of R-6) | A — see R-6 |
| R-40 | `writeRawTree` non-atomic and unguarded | A — atomic, refuses over an unreadable file (§6.2) |
| R-41 | canonical-equivalence string equality/hash | A — `Ordinal`, ordered structural `==`, `JSONValue.deepEquals` per 13 §3.11.9, CS-19 vectors (§3.1) |
| R-42 | save-pipeline IDs assigned to F2 | A — moved to F1 (OWNERSHIP §4, §5.2 note) |
| R-43 | scientific-notation rule contradicts `1E-05` | A — "fixed iff −5 < e < 15" + vectors (§3.3) |
| R-44 | Int32 range and `60.0` leniency | A — Int32-only integer lexemes, `60.0`/`6E1` rejected (parity), writer clamps + `issueLog` → save error (§3.1, §3.8 rule 2) |
| R-45 | fraction digits and ambiguous DST offsets | A — 1…16 digits pending the normative A13 golden; `offsetHint`; standard offset for ambiguous/invalid wall clocks (§3.4) |
| R-46 | missing tick formats (`o`, change-set, applier) | A — `NetDateFormat` cases (§3.4) |
| R-47 | edited calendar dates must be Unspecified | A — `asCalendarDate`, calendar-date rule, list of superseded spec vectors (§3.4) |
| R-48 | invalid UTF-8 must be replaced, not rejected | A — confirmed by 01 §3.4; `InvalidUTF8Policy.replace` default (§3.2, §6.2) |
| R-49 | `extra` nulls/lexemes | A — §3.8 rules 3 and 5 + vectors |
| R-50 | DATA-182 obligations missing | A — steps 1–4, refusal text, joint writes, write gate, per-key tolerance (§4.11, §6.2) |
| R-51 | `BundleSource` defaults and peek rule | A — §4.12 |
| R-52 | missing defaults; `.aasched` must not append extras | A — §4 intro and rows; `JSONEncodeOptions.includeExtra` (§3.8, §4.6) |
| R-53 | `SireState.status` must accept numeric strings | A — `Enum.TryParse` emulation (§4.8) |
| R-54 | subscript setter turns null into removal | A — subscript is get-only; `set`/`removeValue` (§3.1) |
| R-55 | malformed legacy `BucketId` silently ignored | A — `invalidGuid` (§4.3) |
| R-56 | root edge cases unspecified | A — §3.2 (parser) and §3.10 (decoders, settings root) |
| R-57 | unknown TabOrder entries dropped on reorder | A — `SectionID.writeTabOrder` (§4.9, §6.9, §7.2) |
| R-58 | OrderedMap append vs .NET slot reuse | A — emulate the .NET free-list (LIFO slot reuse) (§3.8) |
| R-59 | Save a Copy As D-14 | A — documented in §6.2; Deviations/F1.md |
| R-60 | DATA-010, DATA-135 owners; F1 Specs line | A — DATA-010 → F3, DATA-135/CREW-052 → F1; F1 Specs add 01 §3.25–3.26 and 13 §3.11.9–10, §6.2 |
| R-61 | dangling `§4.3.20` reference | A — now §4.9 (§2.4) |
| R-62 | IDs owned by agents that do not own the files (blocker) | A — REPO-001…008, 003a, DATA-025, 031, SHELL-051 → F1. Totals differ from the reviewer's projection (F1 110 / F2 77 / F3 341) because revision 2 also moved the XLSX reader to F2, File-menu flows/reminders/packaging to W-SHELL and the GF plan to W-GOLD; the regenerated totals are in OWNERSHIP §4 |
| R-63 | DATA-180/179 need F1-level hooks (blocker) | A — `DataFileWriteGuard`, `writer.writeGuard`, `pauseWrites/resumeWrites`, `.pausedByGuard`, `runOnWriterQueue`, `DataStore.writeGuard` (incl. `didLoad`), `DataFileConflictHost`, `acquireExternal/releaseExternal` (§5.2, §5.4, §6.2, §6.6) |
| R-64 | F1 cannot meet its own XLSX acceptance (blocker) | A — reader and B+ moved to F2; C·D/C·T and X.8.9 to W-VESSEL; 11 §7.14 package rows to W-PDF (§10.3, OWNERSHIP §3) |
| R-65 | W-VESSEL depends on W-CREW's parser | A — `NetDateParser`, `CrewText` → F2 (§6.5) |
| R-66 | wave acceptance depends on other waves' real code | A — option (b): in-worktree vs post-merge split, gated tests, §12.4 changed; plus the W-CONT placeholder-reader guard (§6.7, §11) |
| R-67 | UI-flow IDs assigned to non-owners | P — DATA-010, 020, 186, 223, 104, QUICK-190, FLASH-001/002 → F3; the File-menu flow IDs (DATA-012, 032–034, 040, 042, 043, 048, 050, 051, 070, 080) → **W-SHELL**, which now owns those flows; CONT-094 → F1; CONT-081 → W-PERSIST; DATA-135/CREW-052 → F1 |
| R-68 | caller registries mapped to component owners | A — OWNERSHIP §4 "Caller registries" |
| R-69 | `reviewAndConfirmImport` cannot express "unreadable" | A — `incoming: AppData?`; DATA-104, QUICK-190 → F3 (§7.3, §7.9) |
| R-70 | DATA-181 recovery has no menu row | P — the registry is lead-owned, so no `CommandID` is invented: `ConflictCopiesSheet()` contract (W-PERSIST) reachable from W-PERSIST's conflict sheet and banners; **open item for the lead** to add a registry row (then F3 wires `CommandID.conflictCopies`) (§6.6) |
| R-71 | load imbalance on the critical path | A — W-SHELL split off F3; XLSX reader → F2; W-GOLD split off W-PERSIST; W-CAL+W-BOARD → W-PLAN and W-WIN+W-QWORK → W-QUICK to stay at 16 wave agents; size table in OWNERSHIP §1 |
| R-72 | unowned paths; writes into other owners' folders | A — `Tools/global.json`, `Scripts/fixtures.sh`, `Fixtures/mac-out`, capture sub-folders → W-GOLD; XlsxGolden output → `Fixtures/winfixtures/xlsx/`; `VERSION` → W-SHELL; GF `.gitignore` lines → F1 |
| R-73 | symbol conflicts (duplicate of R-16) | A — see R-16 |
| R-74 | Search / Activity windows (duplicate of R-9) | A — see R-9; DECISIONS already rules it, no amendment needed |
| R-75 | recipe matches `SHELL-3`; BUILD-A/C ids unassigned or doubly assigned | A — new regex; BUILD-A/C table (OWNERSHIP §4). A19 (= `ChecklistTemplateService.CloneContainer`) and A20 go to F2 with the service, as proposed |
| R-76 | vectors claimed by non-owners | A — OWNERSHIP §4 "Vector homes"; cards corrected |
| R-77 | VIEW-207/205 callers | A — both now inside W-PLAN (merged agent); caller note in OWNERSHIP §4 |
| R-78 | card/contract mismatches | A — F1 Specs add VIEW-154, CREW-093, XD.4 (signatures); SHELL-183 now W-SHELL (packaging) and removed from W-FLASH; `DueSection` dropped with `DueListBuilder`; no `CommandID` stub needed; `MacKeyStrings` fully implemented by F1 |

No claim was rejected outright: every one was confirmed against the specs or the stated toolchain behaviour. Five
were applied in a different form than proposed (R-15, R-35, R-62, R-67, R-70), for the reasons given.
