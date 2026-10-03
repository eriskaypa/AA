# W-BUILD — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-BUILD-01: read-only viewer needs a subtitle
Target: `Sources/AA/FileBank/ContainerViewerSheet.swift` (owner W-FILES) — ARCHITECTURE.md §7.7
Need: `ContainerViewerSheet(title: String, container: Container, subtitle: String? = nil)` — nil keeps the default
`"Read-only view — click a link to open it. Editing is disabled."`.
Why: 06 BUILD-076 — the Saved Lists item viewer shows `"Saved-list item · {listName} — read-only. Click a link to open
it; double-click a file to open it."` (`BuilderSavedLists.viewerSubtitle(listName:)` builds the exact text).
Workaround in place: `SavedListsTabView` opens `ContainerViewerSheet(title:container:)` (default subtitle); switch the
call to pass `BuilderSavedLists.viewerSubtitle(listName:)` once the parameter exists.

## REQ-W-BUILD-02: `check-ownership.sh` rejects the per-agent progress file DECISIONS asks for
Target: `Scripts/check-ownership.sh` (owner F1) — ARCHITECTURE.md §12.2, DECISIONS "Foundation requests" REQ-F1-01
Need: in `owner_of`, treat `Docs/Progress/<id>.md` like `Docs/Requests/<id>.md` (owner = `<id>`), e.g. extend the first
case to `Docs/Requests/*.md|Docs/Deviations/*.md|Docs/Progress/*.md)`.
Why: DECISIONS (REQ-F1-01 ruling) has every wave agent write `Docs/Progress/<agent-id>.md`, but the script reports it as
"unowned path (not in OWNERSHIP.md §2)" and fails the gate.
Workaround in place: `Docs/Progress/W-BUILD.md` is committed on its own in the last commit, so every code commit before
it passes the full gate; with that file present the only check-ownership failure is this path.
