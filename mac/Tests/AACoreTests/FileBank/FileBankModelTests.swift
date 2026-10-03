// W-FILES — pure file-bank helpers: tabs, columns, entry shapes, open-all threshold, source labels, strings,
// router publishing (T-KB-04/05).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct FileBankTabTests {
    private func sample() -> [FileItem] {
        [FileItem(name: "a.pdf", path: "files/x_a.pdf", kind: .document),
         FileItem(name: "b.png", path: "files/x_b.png", kind: .image),
         FileItem(name: "c.mov", path: "files/x_c.mov", kind: .video),
         FileItem(name: "https://x", path: "https://x", kind: .link, isLink: true),
         FileItem(name: "Routine  (folder)", path: "Z:\\Routine", kind: .other, linkInPlace: true),
         FileItem(name: "d.zip", path: "files/x_d.zip", kind: .other),
         // A web link whose kind is not Link (data written elsewhere) still lists under Links, not Other.
         FileItem(name: "odd", path: "www.imo.org", kind: .other, isLink: true)]
    }

    @Test func filtersMatchCONT080() {
        // TV: 05 CONT-080 tab filters
        let files = sample()
        #expect(FileBankTab.all.filter(files).map(\.name) == files.map(\.name))
        #expect(FileBankTab.documents.filter(files).map(\.name) == ["a.pdf"])
        #expect(FileBankTab.images.filter(files).map(\.name) == ["b.png"])
        #expect(FileBankTab.videos.filter(files).map(\.name) == ["c.mov"])
        #expect(FileBankTab.links.filter(files).map(\.name) == ["https://x", "odd"])
        #expect(FileBankTab.other.filter(files).map(\.name) == ["Routine  (folder)", "d.zip"])
    }

    @Test func tabsKeepInsertionOrderAndWindowsTitles() {
        // TV: 05 CONT-080 "no sorting … insertion order"; tab headers
        #expect(FileBankTab.allCases.map(\.title) == ["All", "Documents", "Images", "Videos", "Links", "Other"])
        let files = [FileItem(name: "z.pdf", kind: .document), FileItem(name: "a.pdf", kind: .document)]
        #expect(FileBankTab.documents.filter(files).map(\.name) == ["z.pdf", "a.pdf"])
    }

    @Test func columnsPerTab() {
        // TV: 05 CONT-080 columns (+ DECISIONS 05 "Linked to", additive, before Path/URL)
        #expect(FileBankTab.all.columns == [.name, .kind, .source, .added, .linkedTo, .path])
        #expect(FileBankTab.documents.columns == [.name, .added, .linkedTo, .path])
        #expect(FileBankTab.images.columns == [.name, .added, .linkedTo])
        #expect(FileBankTab.videos.columns == [.name, .added, .linkedTo])
        #expect(FileBankTab.links.columns == [.name, .linkedTo, .url])
        #expect(FileBankTab.other.columns == [.name, .linkedTo, .path])
        #expect(FileBankColumn.url.title == "URL" && FileBankColumn.path.title == "Path")
        #expect(FileBankColumn.added.idealWidth(in: .all) == 150 && FileBankColumn.added.idealWidth(in: .documents) == 160)
        #expect(FileBankColumn.name.idealWidth(in: .all) == 280 && FileBankColumn.source.idealWidth(in: .all) == 64)
        #expect(FileBankColumn.kind.idealWidth(in: .all) == 80 && FileBankColumn.path.idealWidth(in: .all) == 500)
    }

    @Test func kindNamesAndSourceLabels() {
        // TV: 05 CONT-080 Kind column = enum name; CONT-094 source label
        #expect([FileKind.document, .image, .video, .link, .other].map(FileBankDisplay.kindName) ==
                ["Document", "Image", "Video", "Link", "Other"])
        #expect(FileItem(isLink: true).sourceLabel == "Web link")
        #expect(FileItem(linkInPlace: true).sourceLabel == "Live")
        #expect(FileItem().sourceLabel == "Copy")
    }
}

@MainActor @Suite struct FileBankEntryTests {
    let now = NetDateTime(year: 2026, month: 9, day: 29, hour: 14, minute: 3, kind: .local)

    @Test func webLinkIsUntrimmedAndUnvalidated() {
        // TV: 05 CONT-086
        let bare = FileBankEntries.webLink("https://", added: now)
        #expect(bare?.name == "https://" && bare?.path == "https://" && bare?.kind == .link && bare?.isLink == true)
        #expect(bare?.linkInPlace == false)
        let spaced = FileBankEntries.webLink("  www.imo.org ", added: now)
        #expect(spaced?.path == "  www.imo.org ")
        #expect(FileBankEntries.webLink("   ", added: now) == nil)
        #expect(FileBankEntries.webLink("", added: now) == nil)
    }

    @Test func folderLinkedInPlace() {
        // TV: 05 §7.5 "Folder Shift-drop D:\Routine → {Name: "Routine  (folder)", Kind: 4, LinkInPlace: true}"
        let f = FileBankEntries.linkedFolder(folderName: "Routine", storedPath: "D:\\Routine", added: now)
        #expect(f.name == "Routine  (folder)" && f.kind.rawValue == 4 && f.linkInPlace && !f.isLink)
        #expect(f.path == "D:\\Routine")
        #expect(FileBankDisplay.isLinkedFolder(f))
        #expect(FileBankEntries.folderName(for: URL(fileURLWithPath: "/Volumes/Ops/Routine/")) == "Routine")
    }

    @Test func copiesAndLiveFiles() {
        // TV: 05 CONT-082, CONT-084
        let c = FileBankEntries.copy(name: "Manual v2.pdf", storedPath: "files/0123456789abcdef0123456789abcdef_Manual v2.pdf",
                                     kind: .document, added: now)
        #expect(!c.linkInPlace && !c.isLink && c.sourceLabel == "Copy" && c.added == now)
        let l = FileBankEntries.linkedFile(name: "Daily log.xlsx", storedPath: "\\\\shipserver\\ops\\Daily log.xlsx",
                                           kind: .document, added: now)
        #expect(l.linkInPlace && l.sourceLabel == "Live" && l.path == "\\\\shipserver\\ops\\Daily log.xlsx")
    }

    @Test func pastedCopyShape() {
        // TV: 05 §7.5 paste semantics (copy): new Id, same Path, LinkedItemIds [], Added now
        let a = FileItem(name: "A.pdf", path: "files/x_A.pdf", kind: .document,
                         added: NetDateTime(year: 2025, month: 1, day: 1, kind: .local), isLink: false, linkInPlace: true,
                         linkedItemIds: [UUID()])
        let b = FileBankEntries.pastedCopy(of: a, added: now)
        #expect(b.id != a.id && b.name == a.name && b.path == a.path && b.kind == a.kind)
        #expect(b.isLink == a.isLink && b.linkInPlace == a.linkInPlace)
        #expect(b.linkedItemIds.isEmpty && b.added == now)
    }

    @Test func openAllThreshold() {
        // TV: 05 §7.5 "Open all with 16 entries → confirmation …; with 15 → no prompt"; HIER-136 viewer
        #expect(FileBankDisplay.openAllNeedsConfirmation(16))
        #expect(!FileBankDisplay.openAllNeedsConfirmation(15))
        #expect(FileBankText.openAllPrompt(16) == "Open all 16 items in this tab now?")
        #expect(FileBankText.openAllTitle == "Open all")
        #expect(FileBankText.viewerOpenAllPrompt(16) == "Open all 16 files?")
        #expect(FileBankText.viewerNoFiles == "This item has no files.")
        #expect(FileBankText.viewerOpenAllFilesTitle == "Open all files")
    }

    @Test func pathExtensionAndAddedFormat() {
        #expect(FileBankDisplay.pathExtension("files/x_Report.PDF") == "pdf")
        #expect(FileBankDisplay.pathExtension("Z:\\dir.v2\\noext") == "")
        #expect(FileBankDisplay.pathExtension(".pdf") == "")
        #expect(FileBankDisplay.pathExtension("\\\\srv\\s\\a.tar.gz") == "gz")
        // K-17: the user's locale (pinned here), not en-US.
        let d = NetDateTime(year: 2026, month: 9, day: 29, hour: 14, minute: 3, second: 12, kind: .unspecified)
        let us = FileBankDisplay.added(d, locale: Locale(identifier: "en_US_POSIX"), zone: TZ.athens)
        #expect(us.contains("9/29/26") && us.contains("2:03"))
        let gb = FileBankDisplay.added(d, locale: Locale(identifier: "en_GB"), zone: TZ.athens)
        #expect(gb.hasPrefix("29/09/2026") && gb.contains("14:03"))
    }
}

@Suite struct FileBankStringsTests {
    @Test func windowsStringsVerbatim() {
        // TV: 05 CONT-080…093 exact texts; HIER-136; 05 §6.9 Mac labels
        #expect(FileBankText.title == "File Bank")
        #expect(FileBankText.addFileHelp == "Import a COPY of the file into the app's data folder.")
        #expect(FileBankText.linkInPlaceHelp ==
                "Link a file/folder at its ORIGINAL location (e.g. on a network drive) without copying. Opening it edits the live file.")
        #expect(FileBankText.addFolderHelp == "Import copies of every file inside a folder.")
        #expect(FileBankText.addLinkHelp == "Add a web link (URL).")
        #expect(FileBankText.openAllHelp == "Open every file shown in the current tab at once — ideal for launching a whole routine.")
        #expect(FileBankText.dropHint == "Drag & drop to import — hold ⌥⌘ or ⇧ to link in place")
        #expect(FileBankText.linkInPlacePanelMessage == "Link file(s) in place (the originals are referenced, not copied)")
        #expect(FileBankText.addLinkTitle == "Add link" && FileBankText.addLinkPrompt == "URL:" && FileBankText.addLinkInitial == "https://")
        #expect(FileBankText.renameTitle == "Rename" && FileBankText.renamePrompt == "New name:")
        #expect(FileBankText.linkPickerPrompt("Manual v2.pdf") == "Link 'Manual v2.pdf' to items")
        #expect(FileBankText.notFound("/x/y.pdf") == "Not found:\n/x/y.pdf" && FileBankText.openFailedTitle == "Open failed")
        #expect(FileBankText.fileNotFound("/x") == "File not found:\n/x" && FileBankText.openFolderTitle == "Open folder")
        #expect(FileBankText.openFolderFailedTitle == "Open folder failed")
        #expect(FileBankText.emptyTitle == "No files" && FileBankText.emptyMessage == "Drop files here or use Add File.")
        #expect(FileBankText.windowsDriveUnmapped("Z:") ==
                "This file is on a Windows drive (Z:). Map the drive letter to a folder on this Mac in Settings ▸ File Links.")
        #expect([FileBankText.menuOpen, FileBankText.menuShowInFinder, FileBankText.menuRename, FileBankText.menuLinkToItems,
                 FileBankText.menuRemove] == ["Open", "Show in Finder", "Rename…", "Link to Items…", "Remove"])
    }

    @Test func viewerStrings() {
        // TV: 04 HIER-136, 05 CONT-098
        #expect(FileBankText.viewerWindowTitle("Check oil") == "View — Check oil")
        #expect(FileBankText.viewerDefaultSubtitle == "Read-only view — click a link to open it. Editing is disabled.")
        #expect(FileBankText.savedListSubtitle(listName: "Engine rounds") ==
                "Saved-list item · Engine rounds — read-only. Click a link to open it; double-click a file to open it.")
        #expect(FileBankText.savedListSubtitle(listName: "  ") ==
                "Saved-list item — read-only. Click a link to open it; double-click a file to open it.")
        #expect(FileBankText.viewerNoNotes == "(no notes)" && FileBankText.viewerLocked == "(locked content)")
        #expect(FileBankText.viewerFilesNone == "Files — none")
        #expect(FileBankText.viewerFilesCount(3) == "Files (3) — double-click to open")
        #expect(FileBankText.viewerMissing("/p/a.pdf") == "That file is missing:\n\n/p/a.pdf")
        #expect(FileBankText.viewerMissingTitle == "Open file" && FileBankText.viewerOpenTitle == "Open")
        #expect(FileBankText.viewerCouldNotOpen("t", "e") == "Could not open:\n\nt\n\ne")
        #expect(FileBankText.viewerOpenAllFilesHelp == "Open every file listed below.")
    }
}

@Suite struct FileBankRoutingTests {
    typealias R = CommandRouterCore

    private func ctx(_ list: ShellListState?, keyWin: ShellKeyWindow = .main) -> CommandContext {
        var c = CommandContext()
        c.section = .equipment
        c.keyWin = keyWin
        c.list = list
        return c
    }

    @Test func tkb04RemoveWithoutConfirmation() {
        // TV: 03 T-KB-04 — item window, file bank with 2 selected, ⌘⌫ → "Remove" (no confirmation, CONT-088)
        let fb = FileBankListPolicy.state(selectionCount: 2, canRemove: true)
        let d = R.state(.deleteFamily, ctx(fb, keyWin: .item(UUID())))
        #expect(d.enabled && d.title == "Remove" && d.effect == .listDelete)
        #expect(FileBankListPolicy.deleteConfirms == false)
        #expect(fb.role == "fileBank")
    }

    @Test func tkb05PlainDeleteDoesNothing() {
        // TV: 03 T-KB-05 — plain ⌫ in the file bank: no onDeleteCommand because Windows Remove has no confirmation
        // (SHELL-670); the publishing modifier installs `.onDeleteCommand` only when `deleteConfirms` is true.
        #expect(!FileBankListPolicy.deleteConfirms)
        let none = FileBankListPolicy.state(selectionCount: 0, canRemove: true)
        #expect(!R.state(.deleteFamily, ctx(none)).enabled)
    }

    @Test func quickLookAndViewerList() {
        // TV: 03 SHELL-543 / SHELL-669 — Quick Look needs a selection in fileBank | viewerFiles
        let fb = FileBankListPolicy.state(selectionCount: 1, canRemove: false)
        #expect(R.state(.quickLook, ctx(fb)).effect == .listQuickLook)
        let viewer = FileBankListPolicy.viewerState(selectionCount: 1)
        #expect(viewer.role == "viewerFiles" && !viewer.hasDelete)
        #expect(R.state(.quickLook, ctx(viewer, keyWin: .viewer)).enabled)
        #expect(!R.state(.deleteFamily, ctx(viewer, keyWin: .viewer)).enabled)
        #expect(!R.state(.quickLook, ctx(FileBankListPolicy.viewerState(selectionCount: 0))).enabled)
    }
}
