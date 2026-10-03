# W-SHELL — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-SHELL-01: what `SharedSaveCoordinator.adoptSharedFile` does and does not do
Target: `Sources/AACore/SharedSave/SharedSaveCoordinator.swift` (owner W-PERSIST) — ARCHITECTURE.md §6.6
Need: document the D28 outcomes the call covers. Proposed: `adoptSharedFile(url, useItsContents:)` persists
`SharedSaveFile`; with `useItsContents == true` it runs `ImportSharedBundle` and calls
`host.reloadAfterSharedImport(identity:)` (so `store.generation` changes) and sets both stamps to the loaded
`LastModified`; with `false` it pushes synchronously (`push(label: "Shared save")`, creating or overwriting the
bundle). It does **not** start the timers (the caller calls `start()`), and throws without leaving the path set
only if it cleared it itself. `stopUsing()` stops timers/watcher, clears `SharedSaveFile` and hides the indicator.
Why: 03 SHELL-066/067 (DATA-050/051) — the menu flows are W-SHELL's, the coordinator is W-PERSIST's; the split of
the reload, the `start()` call and the setting write was not fixed by ARCH §6.6 ("menu flow is F3's").
Workaround in place: `ShellFlows.setSharedSaveFile` reloads through `env.loadDataAndInitUI(.sharedSavePull)` only when
`store.generation` did not change during `adoptSharedFile`, then calls `start()`; on failure it calls `stop()` and
clears the setting. `stopSharedSaveFile` clears the setting itself if `stopUsing()` left it set. Marked
`// REQ-W-SHELL-01`.

Resolution: applied — contract documented on `SharedSaveCoordinator.adoptSharedFile` / `stopUsing` and in DECISIONS: the coordinator persists the path, imports + reloads through the host (Use Its Contents) or pushes (Overwrite/Create), STARTS the sync itself, and on failure stops and clears the setting; `stopUsing` clears the setting. ShellFlows drops its generation-check reload, extra `start()`, failure cleanup and duplicate clear (891ed61)

## REQ-W-SHELL-02: the MenuBarExtra binding persists "off" whenever the item is not shown
Target: `Sources/AA/App/AAApp.swift` (owner F3) — ARCHITECTURE.md §7.1, DECISIONS 03 Q-4
Need: `MenuBarExtra(isInserted:)`'s setter should persist only a user removal while the item is meant to be shown,
e.g. `set: { on in if coordinator.menuBarExtraVisible || on { coordinator.setMenuBarExtra(on) } }` (or no setter
at all, the Settings ▸ General toggle being the switch).
Why: the getter is `phase == .main && enabled && !snapshot && !smoke`; when SwiftUI pushes `false` back through the
binding while the getter is false (splash, login, snapshot and smoke runs), `aa.menuBarExtra` is written `false`
and the item never appears again. On the build Mac the preference already reads `0` after test runs.
Workaround in place (W-SHELL files only): when `ReminderCenter` starts in the main phase (not in snapshot or smoke
runs) it turns `aa.menuBarExtra` back on unless the user hid the item on purpose, and from then on records every
change of the preference (Settings toggle, ⌘-drag out of the menu bar) in `aa.shellx.menuBarUserHidden`
(`ShellXMenuBarPolicy`, `ReminderCenter.startMenuBarGuard`). The binding fix above makes the guard a no-op.

Resolution: applied — the MenuBarExtra `isInserted` setter persists only while the item is meant to be shown or when turning on; ReminderCenter's observation guard is replaced by a one-time repair of a stored `false` from earlier builds (`aa.shellx.menuBarRepaired`) (192cefc)

## REQ-W-SHELL-03: `Docs/Progress/<agent-id>.md` is unowned in `check-ownership.sh`
Target: `Scripts/check-ownership.sh` (owner F1) and `Docs/OWNERSHIP.md` §2 (lead) — DECISIONS "Foundation requests"
REQ-F1-01
Need: map `Docs/Progress/<id>.md` to `<id>` in `owner_of` (like `Docs/Requests/<id>.md`).
Why: the lead's ruling tells every wave agent to keep `Docs/Progress/<agent-id>.md`; the checker reports it as
"unowned path (not in OWNERSHIP.md §2)" and fails the gate for every wave branch that follows the ruling.
Workaround in place: `Docs/Progress/W-SHELL.md` is committed as ruled; with it, `check-ownership.sh` reports exactly
that one path and nothing else (verified before the commit).

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)

## REQ-W-SHELL-04: export default name lives in two places (informational)
Target: `Sources/AACore/Bundles/BundleService.swift` (owner W-PERSIST) — ARCHITECTURE.md §6.6
Need: keep `BundleService.exportDefaultName` equal to `aa-data-{yyyyMMdd-HHmm}.zip` (local time).
Why: the File ▸ Export Data Folder (ZIP)… panel (SHELL-070, W-SHELL) uses `ShellXText.exportDefaultName`, which is
tested against that format; W-DRIVE's flows may use the BundleService one.
Workaround in place: none needed.

Resolution: applied — informational; a test pins `ShellXText.exportDefaultName(t)` == `BundleService.exportDefaultName(t)` (a4972ce)
