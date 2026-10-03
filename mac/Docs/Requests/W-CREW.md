# W-CREW — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-CREW-01: HSplitView panes ignore the shell's bottom safe-area inset (informational)
Target: `Sources/AA/Shell/MainWindowView.swift` (owner F3) — ARCHITECTURE.md §7.2
Need: either document that section roots using `HSplitView` must pad their panes by the bottom inset, or have
`SectionContentHost` give sections a frame that excludes the shortcut strip (e.g. a `VStack` instead of
`safeAreaInset(edge: .bottom)`).
Why: the AppKit split view behind `HSplitView` is laid out over the full detail column; SwiftUI insets added with
`safeAreaInset` (the SHELL-024 shortcut strip, 36 pt) are not passed into its panes, so a pane's bottom row (the CREW-016
status line) is drawn under the strip. ARCH §7.2 mandates `HSplitView` for section layouts, so every section owner hits it.
Workaround in place: `CrewTabView` measures `safeAreaInsets.bottom` with a background `GeometryReader`, ignores the bottom
container safe area for the split view, and pads each pane by the measured inset.

## REQ-W-CREW-02: snapshot renderer redraws HSplitView panes as sidebar cards (informational)
Target: `Sources/AA/Debug/SnapshotHook.swift` (owner F3) — ARCHITECTURE.md §9.6
Need: limit the "narrower split-view item" redraw in layer mode to the `NavigationSplitView` sidebar column.
Why: every `_NSSplitViewItemViewWrapper` narrower than the window is redrawn with `cacheDisplay` on a rounded fill, which
includes a section's own `HSplitView` panes; in light/dark snapshots of the Crew tab the card pane is painted over the main
toolbar. `AA_SNAPSHOT_CACHE_DISPLAY=1` renders correctly.
Workaround in place: none needed for the app; snapshots were verified in both modes.

## REQ-W-CREW-03: `check-ownership.sh` does not know the `Docs/Progress/<agent-id>.md` files
Target: `Scripts/check-ownership.sh` (owner F1) — `owner_of`; OWNERSHIP.md §2 (lead)
Need: `Docs/Progress/*.md` → owned by the agent named in the file name (like `Docs/Requests/*.md` and
`Docs/Deviations/*.md`).
Why: DECISIONS "Foundation requests" REQ-F1-01 tells every wave agent to keep `Docs/Progress/<agent-id>.md`, but the script
reports it as `unowned path (not in OWNERSHIP.md §2)`, so step 1/4 of the gate fails on that one file for every wave agent.
Workaround in place: none possible without editing F1's script; `Docs/Progress/W-CREW.md` is committed as the ruling
requires and is the only path the check flags (steps 2–4 pass; build and all tests pass).
