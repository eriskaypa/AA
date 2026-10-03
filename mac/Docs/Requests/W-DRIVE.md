# W-DRIVE — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-DRIVE-01: toolbar slot for the Drive sync indicator (14 §6.5)
Target: `Sources/AA/Shell/ShellMainToolbar.swift` (owner F3) — ARCHITECTURE.md §7.2
Need: a toolbar item (visible only while `env.settings.values.syncOnSave` is on, or while `env.driveSync.indicator`
is not `.idle`) showing `Image(systemName: env.driveSync.indicator.symbol)` with `.help(env.driveSync.lastStatus ?? "")`;
`.symbolEffect(.rotate, isActive: env.driveSync.indicator == .pushing)`. Clicking it may run
`DriveActions.checkForNewer(env:dialogs:)`.
Why: 14 §6.5 Mac addition ("small toolbar sync indicator … in addition to the status text"). The state lives in
W-DRIVE's `DriveSyncCoordinator` (`indicator: DriveIndicatorState`, `lastStatus: String?`, both observable).
Workaround in place: the indicator is shown in Settings ▸ Sync (`DriveSettingsSection`, "Last activity" row).

Resolution: applied — toolbar item `drive` (`ShellDriveSyncIndicator`): visible while Sync on Save is on or the indicator is not idle, SF Symbol from `DriveIndicatorState.symbol`, rotate effect while pushing, help = `lastStatus`, click = router `.driveCheckNewer` (gated like the menu item); the Settings ▸ Sync row stays (6ef95ac)

## REQ-W-DRIVE-02: tool window default sizes (TOOLS-040, TOOLS-080)
Target: `Sources/AA/App/AAApp.swift` (owner F3) — ARCHITECTURE.md §7.1
Need: `Window("Folder builder", id: "folder-builder")` → `.defaultSize(width: 820, height: 660)`;
`WindowGroup("Unit converter", id: "unit-converter", for: UUID.self)` → `.defaultSize(width: 500, height: 660)`.
Why: the Windows sizes (820×660 and 500×660); F3 declares 760×600 and 560×520.
Workaround in place: the views declare `idealWidth/idealHeight` with the Windows sizes and sensible minimums; they lay
out correctly at F3's sizes too (verified by snapshots).

Resolution: applied — Folder builder `.defaultSize(820, 660)`, Unit converter `.defaultSize(500, 660)` (TOOLS-040, TOOLS-080) (1b68635)

## REQ-W-DRIVE-03: `Scripts/check-ownership.sh` does not map `Docs/Progress/<id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — DECISIONS "Foundation requests" REQ-F1-01
Need: in `owner_of`, `Docs/Progress/*.md` → the basename's owner id (same rule as `Docs/Requests/*.md` /
`Docs/Deviations/*.md`).
Why: the lead's ruling REQ-F1-01 tells every wave agent to keep `Docs/Progress/<agent-id>.md`; the script reports the
path as unowned, so the §10.6 gate's path check fails on that single file.
Workaround in place: none possible inside W-DRIVE's paths; `Docs/Progress/W-DRIVE.md` is committed as instructed and is
the only path the check flags.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)
