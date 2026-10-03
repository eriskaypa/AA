# W-VESSEL — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-VESSEL-01: check-ownership.sh does not know `Docs/Progress/<agent-id>.md`
Target: Scripts/check-ownership.sh (owner F1) — ARCHITECTURE.md §12.2; DECISIONS "Foundation requests" REQ-F1-01
Need: treat `Docs/Progress/<id>.md` like `Docs/Requests/<id>.md` / `Docs/Deviations/<id>.md` (owned by `<id>`).
Why: the lead ruling requires every wave agent to keep `Docs/Progress/<agent-id>.md`; the script's path check reports
`unowned path (not in OWNERSHIP.md §2): Docs/Progress/W-VESSEL.md` (its only failure on this branch; build, tests and
the other three checks are green).
Workaround in place: none possible without editing F1's script — the file is committed as the ruling requires.

Notes for the integrator:

* Quick-card "Import a copy", target resolution and opening use W-PERSIST's `AttachmentStore.importFile` /
  `AttachmentOpener` exactly as contracted (ARCH §6.6). In the W-VESSEL worktree they are placeholders, so "Import a
  copy" shows the placeholder's error and opening reports "not available"; the gated tests in
  `Tests/AACoreTests/Vessel/VesselPostMergeTests.swift` run in Stage V.
* Quick Look of file cards calls W-FILES' `QuickLookCoordinator.shared.preview` (placeholder here).
* Work-order notifications post through W-SHELL's `NotificationCenterBridge` (placeholder here; `isAvailable` is false,
  so the digest falls back to the status line until W-SHELL merges).

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)
