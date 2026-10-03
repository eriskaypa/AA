// W-FILES — Add File / Add Folder / drops / link in place (CONT-082…085, K-8, K-9, DECISIONS 05 packages), the
// stored form of links in place (05 §6.9), viewer body and resolution helpers (HIER-136, OC-12).
import Foundation
import Testing
@testable import AACore

@Suite struct FileBankFolderScanTests {
    @Test func flattensRecursivelyAndSkipsFinderLitter() throws {
        // TV: 05 CONT-083 + §8 K-8 (skip .DS_Store, ._*, Icon\r; other hidden files are imported)
        let t = TempFolder("fb-scan")
        try t.write("Routine/b.pdf", "b")
        try t.write("Routine/a.txt", "a")
        try t.write("Routine/.DS_Store", "x")
        try t.write("Routine/._a.txt", "x")
        try t.write("Routine/Icon\r", "x")
        try t.write("Routine/.hidden.cfg", "h")
        try t.write("Routine/sub/deeper/c.png", "c")
        try FileManager.default.createDirectory(at: t.file("Routine/empty"), withIntermediateDirectories: true)
        let files = try FileBankFolderScan.importableFiles(in: t.file("Routine"))
        #expect(files.map(\.lastPathComponent) == [".hidden.cfg", "a.txt", "b.pdf", "c.png"])
        #expect(FileBankFolderScan.isSkipped(name: ".DS_Store") && FileBankFolderScan.isSkipped(name: "._x"))
        #expect(FileBankFolderScan.isSkipped(name: "Icon\r") && !FileBankFolderScan.isSkipped(name: "Icon"))
    }

    @Test func packagesAreSingleEntriesAndFolderLinksAreNotFollowed() throws {
        // DECISIONS 05: a package (e.g. .rtfd) is imported as one entry; symlinked folders are not followed
        let t = TempFolder("fb-scan")
        try t.write("Root/Note.rtfd/TXT.rtf", "{\\rtf1}")
        try t.write("Root/real/x.txt", "x")
        try FileManager.default.createSymbolicLink(at: t.file("Root/loop"), withDestinationURL: t.file("Root"))
        try FileManager.default.createSymbolicLink(at: t.file("Root/alias.txt"), withDestinationURL: t.file("Root/real/x.txt"))
        let files = try FileBankFolderScan.importableFiles(in: t.file("Root"))
        #expect(files.map(\.lastPathComponent) == ["Note.rtfd", "alias.txt", "x.txt"])
        #expect(FileBankFolderScan.isPackage(t.file("Root/Note.rtfd")))
        #expect(FileBankFolderScan.isPlainDirectory(t.file("Root/real")))
        #expect(!FileBankFolderScan.isPlainDirectory(t.file("Root/Note.rtfd")))
    }

    @Test func unreadableFolderThrows() {
        #expect(throws: (any Error).self) {
            _ = try FileBankFolderScan.importableFiles(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        }
    }
}

@Suite struct FileBankLinkPathTests {
    @Test func reverseMappingGivesTheWindowsForm() {
        // 05 §6.9: a mapped Mac folder is stored in its Windows form so the Windows build opens the same file
        let maps = [PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/Ops"),
                    PathMapping(windowsPrefix: "\\\\shipserver\\ops\\", macPath: "/Volumes/Ops/Shared/"),
                    PathMapping(windowsPrefix: "Y:\\", macPath: "/Volumes/Ops2")]
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/Ops/Routine/Daily log.xlsx", mappings: maps, volumePath: nil,
                                            remountURL: nil) == "Z:\\Routine\\Daily log.xlsx")
        // Longest Mac folder wins.
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/Ops/Shared/a.pdf", mappings: maps, volumePath: nil,
                                            remountURL: nil) == "\\\\shipserver\\ops\\a.pdf")
        // Component boundary: /Volumes/Ops2 is not inside /Volumes/Ops.
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/Ops2/b.pdf", mappings: maps, volumePath: nil,
                                            remountURL: nil) == "Y:\\b.pdf")
        // The mapped folder itself (a folder linked in place).
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/Ops", mappings: maps, volumePath: nil, remountURL: nil)
                == "Z:\\")
    }

    @Test func smbVolumesGiveUNC() {
        let remount = URL(string: "smb://chief@shipserver/ops/eng")!
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/eng/Logs/Daily log.xlsx", mappings: [],
                                            volumePath: "/Volumes/eng", remountURL: remount)
                == "\\\\shipserver\\ops\\eng\\Logs\\Daily log.xlsx")
        let spaced = URL(string: "smb://srv/Ship%20Docs")!
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/Ship Docs/x.pdf", mappings: [],
                                            volumePath: "/Volumes/Ship Docs", remountURL: spaced) == "\\\\srv\\Ship Docs\\x.pdf")
    }

    @Test func otherwiseThePOSIXPath() {
        #expect(FileBankLinkPath.storedPath(posixPath: "/Users/u/Documents/a.pdf", mappings: [], volumePath: "/",
                                            remountURL: nil) == "/Users/u/Documents/a.pdf")
        #expect(FileBankLinkPath.storedPath(posixPath: "/Volumes/USB/a.pdf", mappings: [], volumePath: "/Volumes/USB",
                                            remountURL: URL(string: "afp://x/y")) == "/Volumes/USB/a.pdf")
    }
}

@MainActor @Suite struct FileBankImporterTests {
    let now = NetDateTime(year: 2026, month: 10, day: 2, hour: 9, minute: 30, kind: .local)

    /// A stand-in for `AttachmentStore.importFile` (copies into files/ with a fixed prefix; fails on "bad" names).
    private func importer(_ made: StoreFactory.Made, failing: String? = nil) -> FileBankImporter {
        let ds = made.dataStore
        return FileBankImporter(dataStore: ds, importFile: { url in
            if let failing, url.lastPathComponent.contains(failing) {
                throw CocoaError(.fileReadNoPermission)
            }
            var leaf = url.lastPathComponent
            if FileBankFolderScan.isPackage(url) { leaf += ".zip" }
            try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
            let stored = "0123456789abcdef0123456789abcdef_" + leaf
            if !FileBankFolderScan.isPackage(url) {
                try FileManager.default.copyItem(at: url, to: ds.filesFolder.appending(path: stored))
            }
            return "files/" + stored
        }, classify: { path in
            switch FileBankDisplay.pathExtension(path) {
            case "pdf", "txt", "xlsx": return .document
            case "png", "jpg": return .image
            case "mov": return .video
            default: return .other
            }
        }, mappings: [])
    }

    @Test func copiesFilesAndFolders() throws {
        // TV: 05 CONT-082 (Name = file name, Path = files/{guid32}_{name}, Kind classified, Added now), CONT-083
        let made = StoreFactory.make()
        let src = TempFolder("fb-src")
        let manual = try src.write("Manual v2.pdf", "pdf")
        try src.write("Routine/a.txt", "a")
        try src.write("Routine/sub/b.png", "b")
        try src.write("Routine/.DS_Store", "x")
        let c = Container()
        let out = importer(made).importCopies([manual, src.file("Routine"), src.file("missing.pdf")], into: c, now: now)
        #expect(out.failures.isEmpty)
        #expect(c.files.map(\.name) == ["Manual v2.pdf", "a.txt", "b.png"])
        #expect(c.files[0].path == "files/0123456789abcdef0123456789abcdef_Manual v2.pdf")
        #expect(c.files.map(\.kind) == [.document, .document, .image])
        #expect(c.files.allSatisfy { !$0.linkInPlace && !$0.isLink && $0.added == now && $0.sourceLabel == "Copy" })
        #expect(out.added.count == 3)
    }

    @Test func failuresAreCollectedAndTheRestImported() {
        // TV: 05 §8 K-9 (Mac): a failed copy is reported (the UI offers "Link in Place Instead"), never stored as an
        // absolute path labelled Copy
        let made = StoreFactory.make()
        let src = TempFolder("fb-src")
        let good = try! src.write("good.pdf", "g"), bad = try! src.write("bad.pdf", "b")
        let c = Container()
        let out = importer(made, failing: "bad").importCopies([bad, good], into: c, now: now)
        #expect(c.files.map(\.name) == ["good.pdf"])
        #expect(out.failures.map(\.url.lastPathComponent) == ["bad.pdf"])
        let e = FileBankImportError(failures: out.failures, added: out.added.count)
        #expect(e.errorDescription?.hasPrefix("Could not import a copy of:\nbad.pdf\n\n") == true)
    }

    @Test func packagesBecomeOneZippedEntry() throws {
        // DECISIONS 05: a dropped package is ONE files/ entry (zipped by AttachmentStore); the name says .zip
        let made = StoreFactory.make()
        let src = TempFolder("fb-src")
        try src.write("Notes.rtfd/TXT.rtf", "{\\rtf1}")
        let c = Container()
        _ = importer(made).importCopies([src.file("Notes.rtfd")], into: c, now: now)
        #expect(c.files.count == 1 && c.files[0].name == "Notes.rtfd.zip")
        #expect(c.files[0].path.hasSuffix("_Notes.rtfd.zip") && c.files[0].kind == .other)
    }

    @Test func filesAlreadyInTheDataFolderAreReferenced() throws {
        // Dragging a row from one file bank to another references the same stored copy (no duplicate file).
        let made = StoreFactory.make()
        let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        let leaf = "fedcba9876543210fedcba9876543210_Purifier manual.pdf"
        try Data("p".utf8).write(to: ds.filesFolder.appending(path: leaf))
        let c = Container()
        var calls = 0
        var imp = importer(made)
        let inner = imp.importFile
        imp.importFile = { calls += 1; return try inner($0) }
        _ = imp.importCopies([ds.filesFolder.appending(path: leaf)], into: c, now: now)
        #expect(calls == 0)
        #expect(c.files.first?.path == "files/" + leaf && c.files.first?.name == "Purifier manual.pdf")
        #expect(FileBankImporter.displayName(ofStoredLeaf: leaf) == "Purifier manual.pdf")
        #expect(FileBankImporter.displayName(ofStoredLeaf: "short_x.pdf") == "short_x.pdf")
        #expect(FileBankImporter.displayName(ofStoredLeaf: "0123456789ABCDEF0123456789abcdef_x.pdf")
                == "0123456789ABCDEF0123456789abcdef_x.pdf")
    }

    @Test func linkInPlaceFilesAndFolders() throws {
        // TV: 05 CONT-084 (files), CONT-085 (a folder → ONE "{name}  (folder)" entry, Kind Other); missing skipped
        let made = StoreFactory.make()
        let src = TempFolder("fb-src")
        let log = try src.write("Daily log.xlsx", "x")
        try src.write("Routine/a.txt", "a")
        let c = Container()
        let added = importer(made).linkInPlace([log, src.file("Routine"), src.file("gone.pdf")], into: c, now: now)
        #expect(added.count == 2 && c.files.count == 2)
        #expect(c.files[0].name == "Daily log.xlsx" && c.files[0].linkInPlace && c.files[0].kind == .document)
        #expect(c.files[0].path == log.standardizedFileURL.path)
        #expect(c.files[1].name == "Routine  (folder)" && c.files[1].kind == .other && c.files[1].linkInPlace)
        #expect(c.files.allSatisfy { $0.sourceLabel == "Live" && $0.added == now })
    }

    @Test func addImportedClassifiesByDisplayName() {
        // W-CONT image paste → AttachmentStore.importData → FileBankOperations.addImported (DECISIONS 05)
        let made = StoreFactory.make()
        let c = Container()
        let f = importer(made).addImported(storedPath: "files/0123456789abcdef0123456789abcdef_Pasted image.png",
                                           displayName: "Pasted image.png", to: c, now: now)
        #expect(c.files.count == 1 && c.files[0] === f && f.kind == .image && f.name == "Pasted image.png")
        #expect(!f.linkInPlace && f.added == now)
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func realAttachmentStoreImport() throws {
        // TV: 05 §7.5 ImportFile("…/Manual v2.pdf") → files/[0-9a-f]{32}_Manual v2.pdf and the bytes exist there;
        // ClassifyFile vectors (post-merge, W-PERSIST's AttachmentStore)
        let made = StoreFactory.make()
        let src = TempFolder("fb-src")
        let manual = try src.write("Manual v2.pdf", "pdf bytes")
        let c = Container()
        let out = FileBankImporter(dataStore: made.dataStore, mappings: []).importCopies([manual], into: c, now: now)
        #expect(out.failures.isEmpty)
        let p = try #require(c.files.first?.path)
        #expect(p.range(of: "^files/[0-9a-f]{32}_Manual v2\\.pdf$", options: .regularExpression) != nil)
        #expect(FileManager.default.fileExists(atPath: made.dataStore.appFolder.appending(path: p).path))
        #expect(c.files.first?.kind == .document)
        #expect(AttachmentStore.classify(path: "photo.HEIC") == .image)
    }
}

@MainActor @Suite struct FileBankViewerAndResolveTests {
    @Test func viewerPlaceholders() {
        // TV: 04 HIER-136 — blank → "(no notes)", enc: → "(locked content)", unparseable → raw text
        if case .placeholder(let t) = FileBankViewerBody.make(xaml: "") { #expect(t == "(no notes)") } else { Issue.record("blank") }
        if case .placeholder(let t) = FileBankViewerBody.make(xaml: "  \r\n ") { #expect(t == "(no notes)") } else { Issue.record("ws") }
        if case .placeholder(let t) = FileBankViewerBody.make(xaml: "enc:AAAA") { #expect(t == "(locked content)") } else {
            Issue.record("enc")
        }
        if case .raw(let t) = FileBankViewerBody.make(xaml: "<Section><Paragraph>") { #expect(t == "<Section><Paragraph>") } else {
            Issue.record("raw")
        }
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func viewerRendersXamlWithLinks() {
        // TV: 04 §4.6 — same converter as the editor; hyperlinks clickable (post-merge, W-RICH's reader)
        let xaml = #"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph><Run>See </Run><Hyperlink NavigateUri="https://www.imo.org/"><Run>IMO</Run></Hyperlink></Paragraph></Section>"#
        guard case .document(let s) = FileBankViewerBody.make(xaml: xaml) else { Issue.record("not a document"); return }
        #expect(s.string.contains("See IMO"))
        var hasLink = false
        s.enumerateAttribute(.link, in: NSRange(location: 0, length: s.length)) { v, _, _ in if v != nil { hasLink = true } }
        #expect(hasLink)
    }

    @Test func resolutionStates() throws {
        let made = StoreFactory.make()
        let t = TempFolder("fb-res")
        let present = try t.write("a.pdf", "x")
        let ds = made.dataStore
        #expect(FileBankResolve.state(of: FileItem(path: present.path), dataStore: ds) == .present(present))
        #expect(FileBankResolve.state(of: FileItem(path: t.file("gone.pdf").path), dataStore: ds) ==
                .missing(t.file("gone.pdf").path))
        if case .web = FileBankResolve.state(of: FileItem(path: "https://x", isLink: true), dataStore: ds) {} else {
            Issue.record("web")
        }
        #expect(FileBankResolve.target(of: FileItem(path: "www.imo.org", isLink: true), dataStore: ds) == "www.imo.org")
        #expect(FileBankResolve.previewURLs([FileItem(path: present.path), FileItem(path: "https://x", isLink: true)],
                                            dataStore: ds) == [present])
        #expect(FileBankResolve.windowsRoot(of: "z:\\Routine\\a.pdf") == "Z:")
        #expect(FileBankResolve.windowsRoot(of: "\\\\shipserver\\ops\\Daily log.xlsx") == "\\\\shipserver\\ops")
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func missingCopyNamesTheResolvedPath() {
        // TV: 01 TV-OWN-06 (OC-12) — the viewer's missing-file text shows the RESOLVED path, never files/…
        let made = StoreFactory.make()
        let f = FileItem(name: "manual.pdf", path: "files/0123456789abcdef0123456789abcdef_manual.pdf")
        let expected = made.dataStore.appFolder.appending(path: "files/0123456789abcdef0123456789abcdef_manual.pdf").path
        #expect(FileBankResolve.target(of: f, dataStore: made.dataStore) == expected)
        #expect(FileBankResolve.state(of: f, dataStore: made.dataStore) == .missing(expected))
        #expect(FileBankText.viewerMissing(FileBankResolve.target(of: f, dataStore: made.dataStore)) ==
                "That file is missing:\n\n\(expected)")
        // A web link never shows the missing alert.
        if case .web = FileBankResolve.state(of: FileItem(path: "https://x", isLink: true), dataStore: made.dataStore) {} else {
            Issue.record("web")
        }
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func unmappedWindowsPaths() {
        // ARCH §9.4: drive letters without a mapping are "unmapped", never "missing"
        let made = StoreFactory.make()
        let f = FileItem(name: "Routine  (folder)", path: "Q:\\Routine", kind: .other, linkInPlace: true)
        #expect(FileBankResolve.state(of: f, dataStore: made.dataStore) == .windowsUnmapped("Q:\\Routine"))
    }
}
