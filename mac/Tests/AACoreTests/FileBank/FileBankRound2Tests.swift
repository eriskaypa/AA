// W-FILES — Stage V round 2 regressions: Windows paths mapped to smb:// (01 §6.6, ARCH §9.4 `PathMapper.join`),
// the Locate… recovery (01 §6.6, W-PERSIST-13), drag-out / ⌘C under the display name (05 §6.9, CONT-092), drops
// from another AA file bank keep the entry's name, and the viewer's `~` path cell (design rule 3).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite(.serialized) struct FileBankRemoteMappingTests {
    private func realResolver(_ mapper: PathMapper) -> FileBankResolver {
        FileBankResolver(urlForStored: { s, ds in AttachmentOpener.url(forStored: s, isLink: false, dataStore: ds) },
                         resolveFilePath: { AttachmentStore.resolveFilePath($0, stored: $1) },
                         isWindowsPath: { PathMapper.isWindowsPath($0) },
                         macURL: { mapper.macURL(for: $0) },
                         normalizeWebLink: { AttachmentOpener.normalizeWebLink($0) })
    }

    @Test func smbMappingThroughFileBank() throws {
        // V2-J4 journey: Settings ▸ File Links accepts `\\bridge-nas\manuals → smb://bridge-nas/manuals`; the file bank
        // must hand the smb:// URL to NSWorkspace (Finder mounts it), never report "Not found: /manuals/Pump.pdf".
        let made = StoreFactory.make(); let ds = made.dataStore
        let mapper = PathMapper(preferences: nil)
        mapper.mappings = [PathMapping(windowsPrefix: "\\\\bridge-nas\\manuals", macPath: "smb://bridge-nas/manuals")]
        let f = FileItem(name: "Pump.pdf", path: "\\\\bridge-nas\\manuals\\Pump.pdf", kind: .document, linkInPlace: true)
        AttachmentOpener.mapperOverride = mapper; defer { AttachmentOpener.mapperOverride = nil }
        #expect(AttachmentOpener.url(forStored: f.path, isLink: false, dataStore: ds)?.absoluteString
                == "smb://bridge-nas/manuals/Pump.pdf")
        let r = realResolver(mapper)
        if case .missing(let p) = FileBankResolve.state(of: f, dataStore: ds, using: r) { Issue.record("reported missing: \(p)") }
        #expect(FileBankResolve.state(of: f, dataStore: ds, using: r) == .remote(URL(string: "smb://bridge-nas/manuals/Pump.pdf")!))
        // Not a local file: no Quick Look / thumbnail / Finder-select, and the OC-12 target names the URL.
        #expect(FileBankResolve.fileURL(of: f, dataStore: ds, using: r) == nil)
        #expect(FileBankResolve.previewURLs([f], dataStore: ds, using: r).isEmpty)
        #expect(FileBankResolve.target(of: f, dataStore: ds, using: r) == "smb://bridge-nas/manuals/Pump.pdf")
    }

    @Test func afpAndDriveLetterMappedToANetworkURL() {
        let made = StoreFactory.make(); let ds = made.dataStore
        let mapper = PathMapper(preferences: nil)
        mapper.mappings = [PathMapping(windowsPrefix: "Z:", macPath: "afp://ops-server/Ops")]
        let f = FileItem(name: "Daily log.xlsx", path: "Z:\\Routine\\Daily log.xlsx", linkInPlace: true)
        AttachmentOpener.mapperOverride = mapper; defer { AttachmentOpener.mapperOverride = nil }
        let state = FileBankResolve.state(of: f, dataStore: ds, using: realResolver(mapper))
        guard case .remote(let u) = state else { Issue.record("expected .remote, got \(state)"); return }
        #expect(u.scheme == "afp" && u.host() == "ops-server")
        #expect(u.path().removingPercentEncoding == "/Ops/Routine/Daily log.xlsx")
        // A local mapping is still a local file (present or missing there) — unchanged.
        mapper.mappings = [PathMapping(windowsPrefix: "Z:", macPath: "/nonexistent-\(UUID().uuidString)")]
        if case .missing = FileBankResolve.state(of: f, dataStore: ds, using: realResolver(mapper)) {} else {
            Issue.record("a local mapping that does not exist must be missing")
        }
    }
}

@MainActor @Suite struct FileBankLocateRecoveryTests {
    @Test func everyUnmappedWindowsPathOffersLocate() {
        // 01 §6.6 / W-PERSIST-13: "Locate…" on every unmapped Windows path; UNC leads with Connect to Server….
        typealias C = FileBankResolve.RecoveryChoice
        #expect(FileBankResolve.recoveryChoices(for: "\\\\shipserver\\ops\\Daily log.xlsx")
                == [C.connectToServer, .locate, .fileLinksSettings, .cancel])
        #expect(FileBankResolve.recoveryChoices(for: "Z:\\Routine\\Daily log.xlsx") == [C.locate, .fileLinksSettings, .cancel])
        #expect(FileBankResolve.recoveryChoices(for: "Z:\\x").map(\.title) == ["Locate…", "File Links Settings…", "Cancel"])
        #expect(C.connectToServer.title == "Connect to Server…")
        #expect(FileBankText.locateMessage("Z:\\Routine\\Daily log.xlsx") == "Locate “Daily log.xlsx” on this Mac")
        #expect(FileBankText.mappedStatus(PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/Ops"))
                == "Mapped Z: to /Volumes/Ops on this Mac.")
        // Connect to Server… mounts the share ROOT, never the file (Finder would open it a second time).
        #expect(PathMapper.smbShareURL(forUNC: "\\\\shipserver\\ops\\Routine\\Daily log.xlsx")?.absoluteString
                == "smb://shipserver/ops")
    }

    @Test func locateStoresTheMappingAndTheEntryResolves() throws {
        // The Locate… answer (open panel → inferredMapping → upsert) turns the unmapped entry into a present file.
        let made = StoreFactory.make(); let ds = made.dataStore
        let t = TempFolder("fb-locate")
        try t.write("Ship/Routine/Daily log.xlsx", "x")
        let mapper = PathMapper(preferences: nil)
        let f = FileItem(name: "Daily log.xlsx", path: "Z:\\Routine\\Daily log.xlsx", linkInPlace: true)
        let r = FileBankResolver(urlForStored: { s, _ in PathMapper.isWindowsPath(s) ? mapper.macURL(for: s) : nil },
                                 resolveFilePath: { AttachmentStore.resolveFilePath($0, stored: $1) },
                                 isWindowsPath: { PathMapper.isWindowsPath($0) }, macURL: { mapper.macURL(for: $0) },
                                 normalizeWebLink: { AttachmentOpener.normalizeWebLink($0) })
        #expect(FileBankResolve.state(of: f, dataStore: ds, using: r) == .windowsUnmapped(f.path))
        let chosen = t.file("Ship/Routine/Daily log.xlsx")
        let m = try #require(PathMapper.inferredMapping(windowsPath: f.path, chosen: chosen))
        mapper.upsert(m)
        #expect(FileBankResolve.state(of: f, dataStore: ds, using: r) == .present(chosen.standardizedFileURL))
    }
}

@MainActor @Suite struct FileBankExportTests {
    @Test func exportNameIsTheDisplayName() {
        // 05 §6.9 + CONT-092: Finder / Mail receive FileItem.Name, never `<32hex>_<sanitised leaf>`.
        let leaf = "0123456789abcdef0123456789abcdef_Manual.pdf"
        #expect(FileBankExport.exportName(displayName: "Main engine manual (rev 3).pdf", sourceLeaf: leaf)
                == "Main engine manual (rev 3).pdf")
        #expect(FileBankExport.exportName(displayName: "Main engine manual (rev 3)", sourceLeaf: leaf)
                == "Main engine manual (rev 3).pdf")
        #expect(FileBankExport.exportName(displayName: "Report: v1/2.PDF", sourceLeaf: leaf) == "Report- v1-2.PDF")
        #expect(FileBankExport.exportName(displayName: "..hidden.pdf", sourceLeaf: leaf) == "hidden.pdf")
        #expect(FileBankExport.exportName(displayName: "  ", sourceLeaf: leaf) == "Manual.pdf")
        #expect(FileBankExport.exportName(displayName: "README", sourceLeaf: "abc_README") == "README")
        let long = String(repeating: "é", count: 200) + ".pdf"
        let fitted = FileBankExport.exportName(displayName: long, sourceLeaf: leaf)
        #expect(fitted.utf8.count <= 255 && fitted.hasSuffix(".pdf"))
    }

    @Test func stagedCloneCarriesTheNameAndRemembersItsOrigin() throws {
        let made = StoreFactory.make(); let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        let leaf = "0123456789abcdef0123456789abcdef_Manual.pdf"
        let stored = ds.filesFolder.appending(path: leaf)
        try Data("pdf-bytes".utf8).write(to: stored)
        let out = try FileBankExport.stage(stored, displayName: "Main engine manual (rev 3).pdf")
        #expect(out.lastPathComponent == "Main engine manual (rev 3).pdf")
        #expect(try Data(contentsOf: out) == Data("pdf-bytes".utf8))
        #expect(!out.path.hasPrefix(ds.appFolder.path))                       // never inside the data folder
        #expect(FileBankExport.origin(of: out)?.source == stored.standardizedFileURL)
        #expect(FileBankExport.origin(of: out)?.name == "Main engine manual (rev 3).pdf")
        #expect(try FileBankExport.stage(stored, displayName: "Main engine manual (rev 3).pdf") == out)   // reused
        #expect(FileBankExport.sourceURL(of: out) == stored.standardizedFileURL)
        #expect(FileBankExport.origin(of: stored) == nil)
        // A file whose name already is the display name, and a folder, leave as themselves.
        let t = TempFolder("fb-export")
        let plain = try t.write("Pump.pdf", "p")
        #expect(FileBankExport.exportURL(for: plain, displayName: "Pump.pdf") == plain)
        try FileManager.default.createDirectory(at: t.file("Routine"), withIntermediateDirectories: true)
        #expect(FileBankExport.exportURL(for: t.file("Routine"), displayName: "Routine  (folder)") == t.file("Routine"))
    }
}

@MainActor @Suite struct FileBankDropKeepsNameTests {
    private func importer(_ made: StoreFactory.Made, names: ((String) -> String?)? = nil, calls: Counter) -> FileBankImporter {
        let ds = made.dataStore
        return FileBankImporter(dataStore: ds, importFile: { url in
            calls.n += 1
            let stored = "fedcba9876543210fedcba9876543210_" + url.lastPathComponent
            try FileManager.default.copyItem(at: url, to: ds.filesFolder.appending(path: stored))
            return "files/" + stored
        }, classify: { _ in .document }, mappings: [], nameForStoredPath: names)
    }

    final class Counter { var n = 0 }

    @Test func rowDraggedFromAnotherBankIsReferencedUnderItsName() throws {
        // V2-J4: a renamed entry dragged into another bank arrives as "Main engine manual (rev 3).pdf", referencing
        // the same stored copy (no new file in files/).
        let made = StoreFactory.make(); let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        let leaf = "0123456789abcdef0123456789abcdef_Manual.pdf"
        try Data("m".utf8).write(to: ds.filesFolder.appending(path: leaf))
        let dragged = try FileBankExport.stage(ds.filesFolder.appending(path: leaf), displayName: "Main engine manual (rev 3).pdf")
        let calls = Counter()
        let c = Container()
        let out = importer(made, calls: calls).importCopies([dragged], into: c, now: .now())
        #expect(out.failures.isEmpty && calls.n == 0)
        #expect(c.files.first?.path == "files/" + leaf)
        #expect(c.files.first?.name == "Main engine manual (rev 3).pdf")
        #expect(try FileManager.default.contentsOfDirectory(atPath: ds.filesFolder.path) == [leaf])
        // Link in place of a dragged row links the real file, under the entry's name.
        let linked = importer(made, calls: calls).linkInPlace([dragged], into: c, now: .now())
        #expect(linked.first?.name == "Main engine manual (rev 3).pdf")
        #expect(linked.first?.path.hasSuffix(leaf) == true)
    }

    @Test func storedFileDroppedDirectlyKeepsTheExistingEntryName() throws {
        // A files/ leaf dropped from Finder: the name an existing entry gives it, else the leaf without its prefix.
        let made = StoreFactory.make(); let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        let leaf = "0123456789abcdef0123456789abcdef_Report_ v1_.pdf"
        try Data("r".utf8).write(to: ds.filesFolder.appending(path: leaf))
        let owner = Container()
        owner.files = [FileItem(name: "Report: v1?.pdf", path: "files\\" + leaf)]
        let names = FileBankImporter.storedNames(in: [owner])
        #expect(names("files/" + leaf) == "Report: v1?.pdf")
        #expect(names("FILES/" + leaf.uppercased()) == "Report: v1?.pdf")
        let calls = Counter()
        let c = Container()
        _ = importer(made, names: names, calls: calls).importCopies([ds.filesFolder.appending(path: leaf)], into: c, now: .now())
        #expect(c.files.first?.name == "Report: v1?.pdf" && calls.n == 0)
        let c2 = Container()
        _ = importer(made, calls: calls).importCopies([ds.filesFolder.appending(path: leaf)], into: c2, now: .now())
        #expect(c2.files.first?.name == "Report_ v1_.pdf")
    }
}

@Suite struct FileBankShortPathTests {
    @Test func homePathsUseTilde() {
        // Design rule 3: `~` for the home folder; the full stored path stays in the tooltip.
        let home = "/Users/officer"
        #expect(FileBankDisplay.shortPath("/Users/officer/Documents/Pump.pdf", home: home) == "~/Documents/Pump.pdf")
        #expect(FileBankDisplay.shortPath("/Users/officer", home: home + "/") == "~")
        #expect(FileBankDisplay.shortPath("/Users/officer2/x.pdf", home: home) == "/Users/officer2/x.pdf")
        #expect(FileBankDisplay.shortPath("files/0123_x.pdf", home: home) == "files/0123_x.pdf")
        #expect(FileBankDisplay.shortPath("Z:\\Routine\\a.pdf", home: home) == "Z:\\Routine\\a.pdf")
        #expect(FileBankDisplay.shortPath("https://www.imo.org", home: home) == "https://www.imo.org")
    }
}
