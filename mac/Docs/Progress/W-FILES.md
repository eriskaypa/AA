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

## FIX-W-FILES — V-DESIGN findings (2026-10-03)

Counts: 1 finding (polish, 2 parts) · 2 fixed · 0 not fixed · 0 cross-owner requests.

* **Row stripes (03 §6.6.5).** `FileBankTable`, `ContainerViewerSheet` and `FileBacklinksSection` now set
  `.alternatingRowBackgrounds(.disabled)`; the viewer no longer shows striped empty rows under its files.
* **Sharing menu glyph touching its word.** The button-style `Menu` renders as an NSPopUpButton that puts the
  `folder.badge.person.crop` image flush against the title (padding is ignored there, and an `Image` interpolated in
  `Text` is dropped). The rendered title is now the spec text after an en space (`FileBankSharingMenu.spaced`), giving
  the standard icon–title gap; the accessibility label stays "Sharing" / "Shared with N". Compact (icon-only) form
  unchanged.
* **Design rules applied to the rest of the W-FILES views (no finding named them):** no `.system(size:)` left in
  `Sources/AA/FileBank` — header count is a muted mono "(N)", scope-chip counts / footer / drop overlay / viewer
  empty line / backlinks source / icon-tile names and meta use `Font.aaMono` (chip titles keep the system font as
  chrome); no raw `Color.white` — the selected scope chip and selected icon-tile name use `AAColor.selectionBg/Fg`
  (tint hairline on the chip); icon-tile name radius `AARadius.control`; backlinks rows get 4-pt vertical padding.
* Snapshots (light + dark, this worktree's binary) under scratchpad `snapshots/fix1-W-FILES/`: file bank list and
  icons and backlinks over the W-FILES fixture, file bank and viewer over a copy of `snapdata-full`. Checked: no
  stripes, Sharing glyph spaced, chips and counts legible in both appearances, nothing clipped.

Gate: `swift build` and `swift test` (-j 3, warnings as errors) green — 1,586 tests / 234 suites;
`check-ownership.sh --owner W-FILES` OK.

## FIX2-W-FILES — round 2 verification findings (2026-10-03)

Counts: 7 findings · 7 fixed · 0 not fixed · 0 rejected · 0 cross-owner requests · 9 regression tests
(`Tests/AACoreTests/FileBank/FileBankRound2Tests.swift`).

* **smb:// mappings (V2-J4, major).** `FileBankResolve.State` gains `.remote(URL)`: a Windows path mapped to
  `smb://` / `afp://` is never treated as a local path (`fileURL` nil, `target` = the URL, no "missing"). Open hands
  it to `AttachmentOpener.open` (NSWorkspace → Finder mounts the share); Show in Finder opens the containing folder
  URL; Quick Look / thumbnails / the missing badge skip it. Journey test `smbMappingThroughFileBank` adopted as given.
* **Locate… (V2-J4, major).** `FileBankOpening.reportUnmapped` (file bank, viewer, backlinks) now offers the shared
  recovery: UNC → Connect to Server… (mounts the share ROOT via `PathMapper.smbShareURL`, retries up to 15 s, else a
  status line), Locate… (open panel → `PathMapper.inferredMapping` → `PathMapper.shared.upsert` → status → retry),
  File Links Settings…, Cancel; drive letters start at Locate…. Order and titles from
  `FileBankResolve.recoveryChoices(for:)`; OC-12 alert texts unchanged. Implemented in W-FILES (PersistOpenFlow's
  `recover` is private to W-PERSIST; the flow and texts match W-PERSIST-13 / the quick cards).
* **Drag-out / ⌘C name (V2-J4, minor).** New `FileBankExport` (AACore): the stored file is cloned (APFS
  copy-on-write, a copy elsewhere) into a private staging folder on the same volume, named `FileItem.Name` (extension
  of the stored file kept, `/` `:` replaced, ≤ 255 bytes); drags, ⌘C providers and the pasteboard mirror carry the
  staged URL, so Finder / Mail get "Main engine manual (rev 3).pdf", not the `<32hex>_leaf`. Folders and files whose
  name already matches leave as themselves.
* **Drop from another bank (V2-J4, polish).** Staged exports remember their origin: the importer maps them back to
  the stored file (still referenced, not re-copied) and keeps the source entry's Name; links in place link the real
  file under that name. A `files/` leaf dropped from Finder takes the Name an existing entry gives it
  (`FileBankImporter.storedNames`), else the leaf without its prefix. Drop-on-own-bank dedup maps staged URLs back too.
* **Viewer paper (V2-DESIGN, minor).** `ContainerViewerSheet` (also the saved-list viewer) puts the read-only text on
  the editor's page: inset `EditorPane.paperInset` on `AAColor.panelAlt`, radius `AARadius.paper`, 1-pt border,
  dark-mode shadow.
* **Viewer Path / URL column (V2-DESIGN, polish).** Name ideal 220 (max 320), Path / URL flexible (min 160, ideal 260):
  the four columns fit the 820-pt sheet with a visible trailing edge. Path cells (viewer and file bank) show `~` for
  the home folder (`FileBankDisplay.shortPath`), full path in the tooltip.
* **Bank bar accent (V2-DESIGN, polish).** No prominent buttons in the bank bar: Link in Place and Open All are neutral
  bordered like the rest (DEVIATIONS W-FILES "Bank bar accent").
* Snapshots (this worktree's binary, scratch copies of `snapdata-full`, light + dark) under scratchpad
  `snapshots/fix2-W-FILES/`: viewer, viewer-empty, file-bank sheet, Equipment section. Checked: paper inset with
  visible border in light and dark, files table ends inside the sheet, bank bar has no accent-filled buttons.

Gate: `swift build` and `swift test` (-j 3, warnings as errors) green — 1,663 tests / 246 suites;
`check-ownership.sh` OK.
