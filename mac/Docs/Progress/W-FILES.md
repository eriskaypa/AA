# W-FILES — progress (OWNERSHIP.md §3 "W-FILES", §4)

Feature IDs: **22 / 22 done**, 0 remaining, 0 not applicable.

| Group | IDs | Done |
|---|---|---|
| 05 file bank | CONT-080, CONT-082…093, CONT-095…098 | 17 / 17 |
| 04 viewer | HIER-136, HIER-M06 | 2 / 2 |
| 03 in-window keys | SHELL-669 (Space = Quick Look), SHELL-671 (⌘↓ open), SHELL-679 (drop modifiers) | 3 / 3 |
| Caller registry | 07 VIEW-212 row 26 (+ VIEW-215 replace-and-normalise) | done |

Contracts (ARCH §7.7): `FileBankView`, `FileBankContext`, `FileBankOperations`, `FileBacklinksSection`,
`ContainerViewerSheet` (+ subtitle overload, REQ-W-FILES-01), `QuickLookCoordinator` (responder-chain controller) —
all real; `FileBankContractStatus.wFilesImplemented = true`; `Scripts/check-placeholders.sh W-FILES` prints nothing.

Tests (`Tests/AACoreTests/FileBank/`, 54): tab filters / columns / strings, entry shapes, clipboard (copy, true-move
cut, stale generation, duplicate ids), open-all threshold, folder scan (K-8, packages, symlinks), link-in-place stored
form (reverse mapping, SMB UNC), importer (copies, folders, failures, packages, `files/` references, links in place,
`addImported`), container owners / sharing / backlinks / link picker (VIEW-215), viewer body, resolution, T-KB-04/05
and Quick Look routing (incl. the SHELL-543 "selection has a local file" rule), the resolution state machine over
an injected stand-in for W-PERSIST's primitives (TV-OWN-06 resolved missing path, mapped / unmapped Windows paths,
`files\` separators). Gated on other owners (run in Stage V): `realAttachmentStoreImport`, `missingCopyNamesTheResolvedPath`
(TV-OWN-06), `unmappedWindowsPaths` (W-PERSIST); `viewerRendersXamlWithLinks` (W-RICH).

Snapshots (both appearances, fixture `Tests/AACoreTests/Fixtures/ui/w-files/`, sheet ids `w-files.*`): file bank (list,
icons, Images, Links, Shared, narrow, empty), viewer (with files, empty), backlinks. `w-files.quicklook` is a probe
that opens Quick Look on the fixture's local files and prints `Quick Look: … visible=… controlled=…` to stderr: in a
headless snapshot run the app cannot become active (no key window), so the panel correctly refuses to show
(`controlled=false`); with the app frontmost the coordinator's responder sits after the key window and the panel
shows the files (Stage V manual check: select a row, press Space / ⌘Y).

Not done in-worktree (post-merge, Stage V — need other owners' real code): opening / revealing through the real
`AttachmentOpener` and Windows-path mapping (W-PERSIST); real copy import into `files/` (W-PERSIST); rich-text rendering
in the viewer (W-RICH; the placeholder reader shows the raw XAML, as CONT-006 requires); hosting inside
`ContainerEditorView` (W-CONT) and `FileBacklinksSection` in the Relationships tab (W-HIER); Saved Lists double-click →
viewer (W-BUILD).

## Independent audit (2026-10-02)

Counts: 22 feature IDs checked · 19 OK as built · 3 partial → fixed (SHELL-669 / HIER-M06 — Quick Look stayed
published for selections with no local file, against the SHELL-543 enable rule; CONT-087 — Cut was disabled
without a selection, so it could not empty the clipboard as Windows does) · 0 missing.

* `FileBankListPolicy` now decides what every list publishes (file bank Table and icon grid, viewer list, backlinks):
  Quick Look only while the selection holds a local file; Remove only for an editable bank's own rows.
* `FileBankResolve` takes an injectable `FileBankResolver` (default = W-PERSIST's contract), so OC-12 / TV-OWN-06 and
  the unmapped-path state are tested now; the gated tests still run the same checks against the real store.
* Remaining user-visible strings (footer counts, drop overlay, source help, view-mode help, Yes/No, viewer link
  failure) moved into `FileBankText`.
* Snapshots re-rendered in both appearances (file bank list / icons / Images / Links / Shared / narrow / empty,
  viewer, viewer empty, backlinks): no clipping or overlap. In-worktree limits: copies show the missing badge and
  the viewer shows raw XAML until W-PERSIST's resolver and W-RICH's reader merge (the debug fixture absolutises
  copy paths so thumbnails render).

Gate: `swift build` and `swift test` (-j 3, warnings as errors) green; `check-placeholders.sh W-FILES` empty;
`check-ownership.sh` steps 2–4 green, step 1 flags only this file (`Docs/Progress/W-FILES.md`, REQ-W-FILES-02 —
required by DECISIONS REQ-F1-01, the script is F1's).
