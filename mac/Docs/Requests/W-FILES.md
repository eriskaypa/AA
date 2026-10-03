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
