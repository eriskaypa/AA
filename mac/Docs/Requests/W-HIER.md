# W-HIER — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-HIER-01: `check-ownership.sh` does not know `Docs/Progress/<agent-id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — `owner_of`, ARCHITECTURE.md §12.2; DECISIONS "Foundation requests"
(REQ-F1-01 ruling: each wave agent writes `Docs/Progress/<agent-id>.md`).
Need: `Docs/Progress/*.md` owned by the agent whose id is the file's basename (same rule as `Docs/Requests/*.md` and
`Docs/Deviations/*.md`, lines 54–57).
Why: the lead's ruling requires the file; the script reports it as an unowned path, so step 1/4 of the gate fails for
every wave agent that follows the ruling (build, tests, basenames and symbols are green).
Workaround in place: none possible inside W-HIER's paths; `Docs/Progress/W-HIER.md` is committed per the ruling and
is the only path the check flags.

## Additive API (no change requested)
Every contract of ARCH §6.8 (`TagParser`) and §7.7 (W-HIER rows) is implemented with the published signatures.
Additive public API in `Sources/AACore/Hierarchy/` (Hier-prefixed): `HierSidebarBuilder`, `HierText`, `HierPageOps`,
`HierUiState`, `HierRelations`, `HierGroupPicker`, `HierLinkPicker`, `HierLockForm`, `HierDuration`, `HierExportName`,
`HierCommandState`, `TagParser.parseCommaOnly` / `isHashQuery`; additive AA initializer `ItemLockSheet(itemID:onFinish:)`.
