# W-FILES — contract change requests (ARCHITECTURE.md §12.3)

## REQ-W-FILES-01: `ContainerViewerSheet` needs the HIER-136 subtitle
Target: `Sources/AA/FileBank/ContainerViewerSheet.swift` (owner W-FILES) — ARCHITECTURE.md §7.7
Need: add the overload `ContainerViewerSheet(title: String, container: Container, subtitle: String?)` to the §7.7 row
(the contract init `ContainerViewerSheet(title:container:)` stays and shows the default subtitle
`Read-only view — click a link to open it. Editing is disabled.`). The Saved Lists caller passes
`FileBankText.savedListSubtitle(listName:)` (AACore), which renders `Saved-list item · {list} — read-only. Click a link to
open it; double-click a file to open it.` or the unnamed-list form.
Why: 04 HIER-136 / 05 CONT-098 — the Windows Saved Lists tab passes its own subtitle; the §7.7 signature has no way to
carry it.
Workaround in place: the overload exists (additive, same file); W-BUILD can call it now. No change to any other owner's
file is needed.

Resolution: applied — merged with REQ-W-BUILD-01: one init `ContainerViewerSheet(title:container:subtitle: String? = nil)` (ARCH §7.7 row amended in DECISIONS); Saved Lists passes the HIER-136 subtitle (95e9a99)

## REQ-W-FILES-02: `check-ownership.sh` does not know `Docs/Progress/<agent-id>.md`
Target: `Scripts/check-ownership.sh` (owner F1) and `Docs/OWNERSHIP.md` §2 (lead) — ARCHITECTURE.md §12.2
Need: treat `Docs/Progress/<agent-id>.md` as owned by `<agent-id>` (like `Docs/Requests/<id>.md` and
`Docs/Deviations/<id>.md`).
Why: DECISIONS "Foundation requests" REQ-F1-01 tells every wave agent to keep `Docs/Progress/<agent-id>.md`; the script
reports it as an unowned path, so step 1/4 fails on that file alone (steps 2–4 and build/test are green).
Workaround in place: the progress record is committed on its own, after the code commit whose full gate is green.

Resolution: applied — owner_of maps `Docs/Progress/*.md` (f556cb5)
