# W-PERSIST — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-PERSIST-01: start/stop the DATA-180 guard and wire its hooks from F3
Target: `Sources/AA/App/LaunchCoordinator.swift`, `Sources/AA/Shell/ShellQuitPipeline.swift` (owner F3) — ARCHITECTURE.md §5.4, §6.6
Need: after the first load as editor, `env.dataFileGuard?.start()`; on quit and when entering read-only, `stop()`; install
`dataFileGuard.statusHandler = { env.status.post($0) }` and `reloadHandler = { env.loadDataAndInitUI(reason: .reloadFromDisk, status: $0) }`.
Why: 01 DATA-180 step 3 (watcher between saves) and the Keep Mine / Use Theirs status and Revert-to-Saved steps; ARCH only
says F3 constructs and installs the guard.
Workaround in place: `PersistUIBridge.attach(env)` (AA/PersistenceUI) does all of this from `DataFileConflictBanner.onAppear`
(the banner is always in F3's banner area); harmless if F3 also does it (idempotent).

## REQ-W-PERSIST-02: read-only instance behaviours in F3/W-SHELL code (DATA-174)
Target: `AppEnvironment.doSave`, `CommandRouter` enablement, main window subtitle (owner F3); settings setters' status texts (owner W-SHELL) — 01 DATA-174, §MP.3.5
Need: ⌘S while `env.isReadOnlyInstance` shows the sheet `PersistReadOnlyText.saveTitle` / `saveMessage` with "Switch to Other AA"
(`PersistUIBridge.shared.switchToOther()`, when `otherAppPid != nil`) and "OK"; window subtitle `PersistReadOnlyText.windowSubtitle`;
every DATA-174 "disabled" command disabled with help `PersistReadOnlyText.disabledHelp` while read-only or while
`env.dataFileGuard?.state.mode == .stoppedEditing`; W-SHELL setters append `PersistReadOnlyText.settingsSuffix` to their status
when `settings.isWriteGated`.
Why: these surfaces belong to F3/W-SHELL; the texts and state live in W-PERSIST (AACore `PersistReadOnlyText`, `PersistConflictState`).
Workaround in place: the read-only and stopped-editing banners state the mode; `SettingsStore.isWriteGated`/`suspendSaving` already
keep everything from being written, and W-PERSIST's own writers refuse with `PersistWriteGateError.readOnly` while the gate is
closed (Deviations W-PERSIST-14). ⌘S in a read-only copy is intercepted by a local key monitor installed by `ReadOnlyInstanceBanner`
(`PersistUIBridge.installReadOnlySaveInterceptor`, Deviations W-PERSIST-15) — remove it when F3's `doSave` shows the sheet itself.
Still open in F3/W-SHELL code: the window subtitle "Read-Only", greyed DATA-174 commands with the help text, and the settings
status suffix.

## REQ-W-PERSIST-03: an `InstanceGuardResult` case for "same user, no app bundle"
Target: `Sources/AACore/Instance/InstanceGuard.swift` contract (ARCH §6.6, lead) — 01 §MP.3.3 `.sameUserNoApp`
Need: `case sameUserNoApp(pid: Int32)` (or make `.runningHere` carry `canSwitch: Bool`).
Why: a `swift run` / Xcode build holding the folder has no `NSRunningApplication`, so DECISIONS' silent forward cannot work;
the launch must show the alert without "Switch to Running AA".
Workaround in place: mapped to `.otherUser(user)`; `InstanceAlerts` reads `InstanceGuard.folderBlocked` and shows the
same-user wording (Deviations W-PERSIST-4).

## REQ-W-PERSIST-04: Import Database must take the external-file lock first (DATA-179) — informational for W-SHELL
Target: `ShellFlows` Import-from-file (owner W-SHELL) — ARCH §6.6
Need: call `InstanceGuard.acquireExternal(fileURL:)` before `adoptExternalDataFile(_, copyIntoAppFolder: false)`; a result other
than `.editor`/`.unguarded` cancels with the sheet `PersistReadOnlyText.externalBusySheet` ("That file is already open in another
copy of AA.", OK). `BundleService` imports and `applySyncedData` already call `InstanceGuard.releaseExternal()`.
Why: 01 DATA-179, MP.7.7 E-1.
Workaround in place: none needed in W-PERSIST.

## REQ-W-PERSIST-05: map `Docs/Progress/<id>.md` in check-ownership.sh
Target: `Scripts/check-ownership.sh` `owner_of` (owner F1) — DECISIONS "Foundation requests" REQ-F1-01 ruling
Need: add `Docs/Progress/*.md` to the `Docs/Requests/*.md|Docs/Deviations/*.md` pattern (owner = the file's basename).
Why: the lead ruling tells every wave agent to keep `Docs/Progress/<agent-id>.md`; the script reports it as an unowned path.
Workaround in place: the progress record is committed separately from code; the gate is green on every code commit.
