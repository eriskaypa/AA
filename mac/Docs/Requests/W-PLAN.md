# W-PLAN — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-PLAN-01: give `Docs/Progress/<agent-id>.md` an owner in `check-ownership.sh`
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §10.6, §12.2; DECISIONS "Foundation requests" REQ-F1-01
Need: `owner_of` maps `Docs/Progress/<id>.md` to `<id>` (the same rule the script already applies to
`Docs/Requests/<id>.md` and `Docs/Deviations/<id>.md`).
Why: the lead ruling on REQ-F1-01 tells every wave agent to keep its progress record in `Docs/Progress/<agent-id>.md`,
but the script reports that path as unowned, so the §10.6 gate fails as soon as the file exists (verified in this
worktree: `check-ownership: FAILED`, path check). A wave agent may not commit a red gate.
Workaround in place: W-PLAN's progress record (feature-ID counts, not-done list) is kept as the first section of
`Docs/Deviations/W-PLAN.md`; the integrator can move it to `Docs/Progress/W-PLAN.md` verbatim once the script knows
the path.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5); the progress record moved verbatim to `Docs/Progress/W-PLAN.md` (ad9a24b)

## REQ-W-PLAN-02: `AASearchField` focus hook for section commands (informational)
Target: `Sources/AA/Design/AASearchField.swift` (owner F3) — ARCHITECTURE.md §7.6, §8.6
Need: none required; recorded so F3 / verifiers know how W-PLAN publishes ⌥⌘F. Several W-PLAN section roots stay alive
in the main window at the same time (ARCH §7.2 ZStack), so registering their fields with `.aaFilterField(for: .main)`
would make the router choose between several main-window registrations when no panel has focus-within. W-PLAN
therefore publishes `SectionCommands.focusSearchField` / `searchFieldIsFocused` (Board "Find:", Planner "Search
jobs...", Map Inspect search) and binds an outer `.focused(_:)` on `AASearchField`, whose own focus handler then makes
the `NSSearchField` first responder.
Workaround in place: as described; no change to F3 code is needed unless the outer binding proves unreliable in
Stage V (then: an `AASearchField(text:prompt:onSubmit:focus:)` overload taking a `FocusState<Bool>.Binding`).

Resolution: applied — informational; the outer `.focused` binding + `SectionCommands.focusSearchField` approach is accepted; no AASearchField overload added unless Stage V shows it unreliable (no commit)

## REQ-W-PLAN-03: snapshot hook artefacts with ZStack-hosted sections and nested split views (informational)
Target: `Sources/AA/Debug/SnapshotHook.swift` (owner F3) — ARCHITECTURE.md §9.6
Need: (1) in the default layer-rendering mode the hook re-draws every "narrower split-view item" with `cacheDisplay`
as if it were the floating sidebar; that also catches split views *inside* a section (and, through them, section roots
that are kept alive at opacity 0 by `SectionContentHost`), so a hidden Calendar table was painted over the Board and
Planner and pane fills covered the toolbar. Restricting the re-draw to the window's own `NavigationSplitView`
sidebar item (and skipping views whose effective alpha is 0) would fix it. (2) The data folder's
`Ui.SelectedMainTabIndex` decides which section is visited first, so `--snapshot TabBoard` on a fixture saved on the
Calendar renders two sections.
Workaround in place: W-PLAN's verification renders with `AA_SNAPSHOT_CACHE_DISPLAY=1` and sets
`Ui.SelectedMainTabIndex` in the scratch copy to the section being rendered. W-PLAN's pages no longer use
`HSplitView` (see Deviations, audit), which also removes the artefact for them.
Also observed (not W-PLAN-specific, left for F3): AppKit logs "Application performed a reentrant operation in its
NSTableView delegate" once when the Calendar `Table` first appears; nothing in W-PLAN's cells mutates state, the
likely source is a list/command registration written during the table's first layout.

Resolution: applied — (1) SnapshotHook no longer redraws section-internal split views or alpha-0 section roots (ee1411b); (2) not changed: `--snapshot <Tab>` still visits the data's saved tab first, but the hidden root is no longer painted, so the artefact is gone
