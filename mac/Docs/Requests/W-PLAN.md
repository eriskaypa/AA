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
