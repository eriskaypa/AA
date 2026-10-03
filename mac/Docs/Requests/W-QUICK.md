# W-QUICK — contract change requests (ARCHITECTURE.md §12.3)

None open. REQ-F2-02 (switcher rows with the session lock state) and REQ-F3-03 (panels register with `SceneOpener`)
are implemented as ruled (`QuickSwitcherPanelController`, `DueDatesPanelController`).

Notes for the integrator (no contract change needed):
- The shared session scratchpad is used by every wave agent; W-QUICK keeps its helper scripts under
  `scratchpad/wquick/` (an earlier `scratchpad/b.sh` was overwritten by another agent).

## REQ-W-QUICK-01: `check-ownership.sh` must accept `Docs/Progress/<id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §12.2; DECISIONS "Foundation requests" REQ-F1-01
Need: in `owner_of`, map `Docs/Progress/*.md` to the agent named by the basename, exactly like
`Docs/Requests/*.md|Docs/Deviations/*.md` (line 54).
Why: the lead's REQ-F1-01 ruling makes every wave agent keep `Docs/Progress/<agent-id>.md`, but the script reports it
as an unowned path, so the §10.6 gate fails on that file alone.
Workaround in place: all code, tests and the other docs were committed with a green gate; `Docs/Progress/W-QUICK.md`
is committed separately in a docs-only commit whose only `check-ownership` complaint is this path.
