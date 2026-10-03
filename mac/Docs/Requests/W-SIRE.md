# W-SIRE — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-SIRE-01: `check-ownership.sh` does not know `Docs/Progress/<agent-id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) — `owner_of`; DECISIONS "Foundation requests" (REQ-F1-01 ruling)
Need: `Docs/Progress/*.md` owned by the agent named by the file's basename (same rule as `Docs/Requests/*.md` and
`Docs/Deviations/*.md`).
Why: the ruling requires `Docs/Progress/W-SIRE.md`; the script reports it as `unowned path (not in OWNERSHIP.md §2)`,
so step 1/4 of the gate flags that single file (build, all tests and steps 2–4 pass). Same as REQ-W-HIER-01 /
REQ-W-CREW-03 / REQ-W-PDF-01.
Workaround in place: none possible inside W-SIRE's paths; the file is committed as ruled.

## REQ-W-SIRE-02: snapshot hook renders nested split views over the toolbar (informational)
Target: `Sources/AA/Debug/SnapshotHook.swift` (owner F3) — ARCHITECTURE.md §9.6
Need: nothing blocking. A SwiftUI `HSplitView` inside the NavigationSplitView detail extends under the toolbar and
the floating sidebar on macOS 26 and grows the window beyond its frame; W-SIRE therefore uses app-drawn dividers
(Deviations D-SIRE-05). Other owners following ARCH §7.2 ("internal layouts use HSplitView") may hit the same.
Why: ARCH §7.2 recommends `HSplitView` for section layouts.
Workaround in place: `SireTabView` uses an `HStack` with `SireSplitHandle` dividers.
